"""Independent read-only APK acceptance; no Android device/emulator claims."""
from pathlib import Path
import argparse, configparser, hashlib, json, re, struct, subprocess, zipfile

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--apk', type=Path, required=True)
ap.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
ap.add_argument('--report', type=Path)
args = ap.parse_args()
root, apk = args.source.resolve(), args.apk.resolve()
failures = []
checks = 0

def check(condition, reason):
    global checks
    checks += 1
    if not condition:
        failures.append(reason)

def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as f:
        for data in iter(lambda: f.read(1 << 20), b''):
            digest.update(data)
    return digest.hexdigest()

def manifest_nodes(data):
    """Read Android binary XML directly, independent of tools/inspect_apk.py."""
    strings, nodes = [], []
    at = 8
    while at < len(data):
        kind, header, length = struct.unpack_from('<HHI', data, at)
        if length < header or at + length > len(data):
            raise ValueError('Invalid binary XML chunk length')
        if kind == 0x0001:
            count, _, flags, start, _ = struct.unpack_from('<IIIII', data, at + 8)
            def size8(pos):
                x = data[pos]
                return (((x & 127) << 8) | data[pos + 1], pos + 2) if x & 128 else (x, pos + 1)
            def size16(pos):
                x = struct.unpack_from('<H', data, pos)[0]
                return (((x & 32767) << 16) | struct.unpack_from('<H', data, pos + 2)[0], pos + 4) if x & 32768 else (x, pos + 2)
            for i in range(count):
                pos = at + start + struct.unpack_from('<I', data, at + header + i * 4)[0]
                if flags & 0x100:
                    _, pos = size8(pos)
                    n, pos = size8(pos)
                    strings.append(data[pos:pos+n].decode('utf-8'))
                else:
                    n, pos = size16(pos)
                    strings.append(data[pos:pos+n*2].decode('utf-16le'))
        elif kind == 0x0102:
            _, name, first, stride, count = struct.unpack_from('<IIHHH', data, at + 16)
            attrs = {}
            for i in range(count):
                pos = at + 16 + first + i * stride
                _, key, _, _, _, value_type, value = struct.unpack_from('<IIIHBBI', data, pos)
                attrs[strings[key]] = strings[value] if value_type == 3 else bool(value) if value_type == 18 else value
            nodes.append((strings[name], attrs))
        at += length
    return nodes

excluded = {'build', 'tests', 'tools', 'docs', 'source', 'authoring', '.godot', '__pycache__'}
suffixes = {'.gd', '.json', '.tscn', '.tres', '.ttf', '.png', '.svg', '.ogg', '.wav', '.import'}
records = {}
for file in sorted(root.rglob('*')):
    relative = file.relative_to(root)
    if file.is_file() and not excluded.intersection(relative.parts) and (file.suffix in suffixes or file.name in {'project.godot', 'export_presets.cfg'}):
        records[relative.as_posix()] = sha(file)
source_digest = hashlib.sha256(json.dumps(records, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
preset = configparser.ConfigParser(interpolation=None)
preset.read(root / 'export_presets.cfg')
options = preset['preset.0.options']
expected_package = json.loads(options['package/unique_name'])
expected_version_code = int(options['version/code'])
expected_version_name = json.loads(options['version/name'])
build_path = apk.with_suffix('.build.json')
build = json.loads(build_path.read_text())
apk_digest = sha(apk)
check(build.get('sha256') == apk_digest, 'APK bytes differ from build manifest SHA256')
check(build.get('source_runtime_digest_sha256') == source_digest, 'Frozen source runtime digest differs from build manifest')

summary = {'apk': apk.name, 'apk_sha256': apk_digest, 'size_bytes': apk.stat().st_size,
           'source_runtime_digest_sha256': source_digest, 'runtime_source_files': len(records),
           'source_digest_scope': 'Runtime source, resource bytes, source import settings, project config and export preset; excludes development/authoring/output folders. Staged export rewrites import/remap metadata and local signing/template paths.',
           'compiled_script_provenance': 'Source digest matches reviewed isolated before/after guarded build; bytecode files/remaps verified, not claimed to contain original source text.'}
with zipfile.ZipFile(apk) as z:
    names = set(z.namelist())
    check(len(names) == len(z.namelist()), 'Duplicate ZIP entries')
    check(z.testzip() is None, 'ZIP CRC verification failed')
    nodes = manifest_nodes(z.read('AndroidManifest.xml'))
    top = next(attrs for name, attrs in nodes if name == 'manifest')
    sdk = next(attrs for name, attrs in nodes if name == 'uses-sdk')
    application = next(attrs for name, attrs in nodes if name == 'application')
    activities = [attrs for name, attrs in nodes if name == 'activity']
    permissions = sorted(attrs.get('name', '') for name, attrs in nodes if name == 'uses-permission')
    check(top.get('package') == expected_package == 'com.almostgod.game', 'Unexpected Android package')
    check(top.get('versionCode') == expected_version_code and top.get('versionName') == expected_version_name, 'App version differs from frozen export preset')
    check(sdk.get('minSdkVersion') == 24 and sdk.get('targetSdkVersion') == 36, 'Unexpected SDK range')
    check(any(a.get('screenOrientation') == 1 for a in activities), 'Portrait orientation missing')
    check(set(permissions) <= {'android.permission.VIBRATE'}, 'Unexpected Android permission')
    check(application.get('debuggable') is True and application.get('allowBackup') is False, 'Expected local debug/backup manifest flags differ')
    check(not any(n.startswith(('assets/tests/', 'assets/tools/', 'assets/docs/', 'assets/build/', 'assets/data/authoring/',
                               'assets/assets/source/', 'assets/assets/art/source/', 'assets/assets/audio/production/source/')) for n in names), 'Development/test/source-authoring files leaked into APK')
    summary['manifest'] = {'package': top.get('package'), 'version_code': top.get('versionCode'),
                           'version_name': top.get('versionName'), 'min_sdk': sdk.get('minSdkVersion'),
                           'target_sdk': sdk.get('targetSdkVersion'), 'portrait': True,
                           'permissions': permissions, 'debuggable': application.get('debuggable')}
    counts = {'raw_equal': 0, 'imported_resources': 0, 'compiled_scripts': 0, 'levels': 0,
              'rig_metadata': 0, 'environment_metadata': 0, 'portraits': 0,
              'png_textures': 0, 'audio_resources': 0, 'referenced_rig_parts': 0, 'referenced_environment_layers': 0}
    def packed_resource_available(relative):
        packed = 'assets/' + relative
        return relative in records and (packed in names or packed + '.import' in names or packed + '.remap' in names)
    for relative in records:
        # Import settings and the export preset participate in the frozen source
        # digest. Godot regenerates packed sidecars; the preset is not runtime data.
        if relative.endswith('.import') or relative == 'export_presets.cfg':
            continue
        packed = 'assets/' + relative
        if relative == 'project.godot':
            check(packed in names or 'assets/project.binary' in names, 'Project bootstrap config missing')
            continue
        if packed in names:
            check(hashlib.sha256(z.read(packed)).hexdigest() == records[relative], 'Raw resource mismatch: ' + relative)
            counts['raw_equal'] += 1
        else:
            remap = next((p for p in [packed + '.import', packed + '.remap'] if p in names), None)
            if remap is None:
                check(False, 'Runtime source/resource missing: ' + relative)
                continue
            text = z.read(remap).decode('utf-8', errors='replace')
            targets = re.findall(r'path(?:\.[A-Za-z0-9_]+)?="res://([^\"]+)"', text)
            check(bool(targets) and all('assets/' + target in names for target in targets), 'Unresolved import/remap: ' + relative)
            if relative.endswith('.gd'):
                counts['compiled_scripts'] += 1
                for target in targets:
                    if 'assets/' + target in names:
                        check(z.read('assets/' + target)[:4] == b'GDSC', 'Invalid compiled script header: ' + relative)
            else:
                counts['imported_resources'] += 1
        if relative.startswith('data/levels/L') and relative.endswith('.json'):
            counts['levels'] += 1
        if '/characters/rigs/' in relative and relative.endswith('/rig.json'):
            counts['rig_metadata'] += 1
        if '/environments/' in relative and relative.endswith('/layers.json'):
            counts['environment_metadata'] += 1
        if '/characters/portraits/' in relative and relative.endswith('.png'):
            counts['portraits'] += 1
        if relative.endswith('.png'):
            counts['png_textures'] += 1
        if relative.endswith(('.ogg', '.wav')):
            counts['audio_resources'] += 1
        if relative.endswith('/layers.json') and '/environments/' in relative:
            environment = json.loads(z.read(packed))
            base = relative.rsplit('/', 1)[0] + '/'
            check(all(packed_resource_available(base + layer['file']) for layer in environment['layers']), 'Environment layer texture unavailable: ' + relative)
            counts['referenced_environment_layers'] += len(environment['layers'])
    check(counts['levels'] == 30, 'All30 authored levels must be packed')
    check(counts['rig_metadata'] == 9, 'All9 rig metadata files must be packed')
    check(counts['environment_metadata'] == 3, 'All3 environment layer metadata files must be packed')
    check(counts['portraits'] == 81, 'All81 portrait resources must be packed')
    summary['resources'] = counts

    # Identity review only: use packed level/rig JSON, without changing author
    # geometry, re-running solutions or interpreting reused portrait panels as
    # additional world actors.
    cast = {'CH01': 'felix', 'CH02': 'plum', 'CH03': 'marfa',
            'CH04': 'semyon', 'CH05': 'nika', 'CH06': 'lada',
            'CH07': 'roza', 'CH08': 'hugo', 'CH09': 'caramelka',
            'CROWD01': 'crowd_gardener', 'CROWD02': 'crowd_postwoman',
            'CROWD03': 'crowd_fisherman', 'CROWD04': 'crowd_librarian',
            'CROWD05': 'crowd_merchant', 'CROWD06': 'crowd_musician'}
    check(len(set(cast.values())) == len(cast), 'Character IDs alias the same actor')
    stage_source = (root / 'presentation/stage_view.gd').read_text()
    match = re.search(r'^const CHARACTERS=(\{.*\})$', stage_source, re.MULTILINE)
    check(match is not None and json.loads(match.group(1)) == cast, 'Stage character identity mapping differs from reviewed cast')
    level_cast, seen_witnesses = {}, set()
    for i in range(1, 31):
        level_id = f'L{i:02d}'
        level = json.loads(z.read(f'assets/data/levels/{level_id}.json'))
        witnesses = [w['character_id'] for w in level['witnesses']]
        entities = [e['asset_id'].removesuffix('_RIG') for e in level['entities'] if e['asset_id'].startswith('CH')]
        # Plum is the explicit companion attached to the hero, not a second
        # simulated entity; it is nevertheless part of the visible scene cast.
        visible_cast = entities + ['CH02'] + witnesses
        check(len(visible_cast) == len(set(visible_cast)), 'Duplicate world character identity: ' + level_id)
        check(all(actor in cast for actor in visible_cast), 'Unknown character identity: ' + level_id)
        level_cast[level_id] = visible_cast
        seen_witnesses.update(witnesses)
    for character_id, actor in cast.items():
        baseline = 'assets/assets/art/characters/' + actor + '.png'
        check(baseline in names or baseline + '.import' in names, 'Character baseline unavailable: ' + actor)
        if character_id.startswith('CH'):
            rig = json.loads(z.read(f'assets/assets/art/characters/rigs/{actor}/rig.json'))
            check(rig['actor_id'] == actor, 'Rig identity does not match its path: ' + actor)
            check(all(packed_resource_available(f'assets/art/characters/rigs/{actor}/' + part['file']) for part in rig['parts']), 'Rig part texture unavailable: ' + actor)
            counts['referenced_rig_parts'] += len(rig['parts'])
    overrides = json.loads((root / 'data/authoring/character_cast.json').read_text())['overrides']
    for level_id, witnesses in overrides.items():
        level = json.loads(z.read(f'assets/data/levels/{level_id}.json'))
        actual = {w['id']: w['character_id'] for w in level['witnesses']}
        check(all(actual.get(witness) == actor for witness, actor in witnesses.items()), 'Author cast overrides not applied: ' + level_id)
    check(all(f'CROWD{i:02d}' in seen_witnesses for i in range(1, 7)), 'Some crowd identities never appear')
    summary['cast_identity'] = {'unique_actor_mapping': cast, 'level_cast': level_cast,
                                'duplicate_world_character_ids': [],
                                'scope': 'Packed identities and rig metadata only; no new art quality or full-cycle animation claim.'}
    libraries = []
    for name in sorted(n for n in names if n.startswith('lib/') and n.endswith('.so')):
        data = z.read(name)
        check(name.startswith('lib/arm64-v8a/'), 'Unexpected ABI: ' + name)
        check(data[:5] == b'\x7fELF\x02' and struct.unpack_from('<H', data, 18)[0] == 183, 'Not arm64 ELF: ' + name)
        phoff = struct.unpack_from('<Q', data, 32)[0]
        stride, count = struct.unpack_from('<HH', data, 54)
        aligns = [struct.unpack_from('<Q', data, phoff + i * stride + 48)[0]
                  for i in range(count) if struct.unpack_from('<I', data, phoff + i * stride)[0] == 1]
        entry = z.getinfo(name)
        with apk.open('rb') as f:
            f.seek(entry.header_offset + 26)
            filename, extra = struct.unpack('<HH', f.read(4))
        offset = entry.header_offset + 30 + filename + extra
        compatible = bool(aligns) and all(a >= 16384 for a in aligns) and ((entry.compress_type != 0 and application.get('extractNativeLibs', True)) or (entry.compress_type == 0 and offset % 16384 == 0))
        check(compatible, '16KB installation compatibility not established: ' + name)
        libraries.append({'name': name, 'elf_load_alignments': aligns, 'compressed': entry.compress_type != 0, 'installation_16k_compatible': compatible})
    check(bool(libraries), 'No native libraries packed')
    summary['native_libraries'] = libraries

signer = root.parent / 'tools/android-sdk/build-tools/31.0.2/apksigner'
signature = subprocess.run([str(signer), 'verify', '--verbose', '--print-certs', str(apk)], capture_output=True, text=True)
check(signature.returncode == 0, 'Independent apksigner verification failed')
match = re.search(r'Signer #1 certificate SHA-256 digest: ([a-f0-9]+)', signature.stdout)
certificate = (root / 'tools/signing/certificate.sha256').read_text().strip()
check(match is not None and match.group(1) == certificate == build.get('certificate_sha256'), 'Signing certificate mismatch')
summary['signature_verified_independently'] = signature.returncode == 0
summary['certificate_sha256'] = match.group(1) if match else None
summary['failures'] = failures
summary['checks'] = checks
summary['physical_device_tested'] = False
summary['signing'] = 'local debug certificate; not store/release signing'
report = args.report or root / 'tests/reports/apk-independent.json'
report.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'apk_sha256': apk_digest, 'source_runtime_digest_sha256': source_digest,
                  'checks': checks, 'resources': summary['resources'], 'failures': failures,
                  'signature_verified_independently': summary['signature_verified_independently']}, ensure_ascii=False, indent=2))
raise SystemExit(1 if failures else 0)
