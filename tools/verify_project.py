"""Run production logic/integration gates with isolated user saves.

The report proves only these automated checks, never physical-device acceptance.
Use --audio to additionally decode and measure the produced audio resources.
"""
from pathlib import Path
import argparse, hashlib, json, os, re, subprocess, sys, tempfile, time

ROOT = Path(__file__).resolve().parents[1]
def runtime_manifest():
    suffixes = {'.gd', '.json', '.tscn', '.tres', '.ttf', '.png', '.svg', '.ogg', '.wav', '.import'}
    records = {}
    for p in sorted(ROOT.rglob('*')):
        rel = p.relative_to(ROOT)
        if any(x in {'build','tests','tools','docs','source','authoring','.godot','__pycache__'} for x in rel.parts):
            continue
        if p.is_file() and (p.suffix in suffixes or p.name in {'project.godot','export_presets.cfg'}):
            records[str(rel)] = hashlib.sha256(p.read_bytes()).hexdigest()
    return records

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--godot', default=os.environ.get('GODOT_BIN', str(ROOT.parent/'tools/Godot_v4.7.2-stable_linux.x86_64')))
    ap.add_argument('--audio', action='store_true')
    ap.add_argument('--ui', action='store_true', help='Also exercise real pointer events and native controls.')
    opts = ap.parse_args()
    if not Path(opts.godot).is_file():
        ap.error('Godot binary missing; supply --godot /absolute/path/to/godot.')
    before = runtime_manifest()
    commands = [('content', [sys.executable, str(ROOT/'tools/validate_content.py')]),
                ('art-files', [sys.executable, str(ROOT/'tools/verify_art.py')])]
    suites = ['test_kernel.gd','test_validation.gd','test_s2_regressions.gd','test_campaign.gd',
              'test_services.gd','test_service_boundaries.gd','test_client_loading.gd',
              'test_save_recovery_edges.gd','test_audio_conductor.gd','test_audio_transport_edges.gd',
              'test_audio_shutdown.gd','test_audio_shutdown_edges.gd',
              'test_workbench.gd','test_puppet.gd','test_puppet_edges.gd',
              'test_layout.gd','test_stage_boundaries.gd','test_presentation.gd','test_stage_targets.gd','test_stage_input_edges.gd']
    if opts.ui:
        suites.extend(['test_ui.gd','test_touch_capability.gd','test_complex_ui_journeys.gd'])
    for name in suites:
        commands.append((name, [opts.godot, '--headless', '--path', str(ROOT), '--resolution', '1080x1920', '--script', 'tests/'+name]))
    if opts.audio:
        commands.append(('audio-files', [sys.executable, str(ROOT/'tools/verify_audio.py')]))
    outcomes=[]
    for name, command in commands:
        if name.endswith('.gd') and not (ROOT/'tests'/name).exists():
            outcomes.append({'name':name,'exit_code':127,'output':'Required suite is missing.'})
            print('FAIL',name,'missing suite',flush=True)
            continue
        with tempfile.TemporaryDirectory(prefix='almost-god-verification-') as saves:
            env=os.environ.copy();env['XDG_DATA_HOME']=saves
            start=time.monotonic()
            try:
                result=subprocess.run(command,cwd=ROOT,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=240)
                engine_errors=[line for line in result.stdout.splitlines() if re.search(r'^(SCRIPT ERROR:|ERROR:)|ObjectDB instances leaked|Resources still in use at exit',line)]
                item={'name':name,'exit_code':result.returncode or (1 if engine_errors else 0),'process_exit_code':result.returncode,
                      'engine_errors':engine_errors,'elapsed_seconds':round(time.monotonic()-start,2),'output':result.stdout[-12000:]}
            except subprocess.TimeoutExpired as e:
                item={'name':name,'exit_code':124,'output':'Verification timed out; not a pass.'}
            outcomes.append(item)
            print(('PASS' if item['exit_code']==0 else 'FAIL'),name,flush=True)
            if item['exit_code']:
                print(item['output'],flush=True)
    after=runtime_manifest()
    changed=[k for k in set(before)|set(after) if before.get(k)!=after.get(k)]
    report={'status':'passed' if not changed and all(x['exit_code']==0 for x in outcomes) else 'failed',
            'runtime_digest_sha256':hashlib.sha256(json.dumps(after,sort_keys=True,separators=(',',':')).encode()).hexdigest(),
            'runtime_files':after,'files_changed_during_verification':sorted(changed),'checks':outcomes,
            'limits':['No physical Android/iOS device was tested.','No human comprehension or subjective listening test is inferred from these results.']}
    dest=ROOT/'tests/reports/project-verification.json';dest.parent.mkdir(exist_ok=True,parents=True)
    dest.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(report['status'],dest)
    return 0 if report['status']=='passed' else 1
if __name__=='__main__':
    raise SystemExit(main())
