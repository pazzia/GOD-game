"""Package a portable source checkpoint, without engine/SDK binaries or credentials.

Runtime assets, editable art/audio sources, team skills and test reports are kept.
Historical reference art in old/ remains in Git and is included only with
--include-old. build/ previews, binaries and logs are excluded from source ZIPs.
The output is validated and atomically replaced, preserving an existing archive
if creation fails. The default destination is beside the project in deliverables/.
"""
from pathlib import Path
import argparse
import os
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXCLUDE_DIRECTORIES = {'.godot', '.git', '__pycache__', 'node_modules', 'build', 'dist', 'deliverables', 'localkeys', 'local-keys', 'GOD-local-signing'}
EXCLUDE_SUFFIXES = {'.tmp', '.pyc', '.pyo', '.apk', '.aab', '.apks', '.idsig', '.keystore', '.jks', '.key', '.p12', '.pfx'}


def package(output: Path, include_old: bool = False) -> tuple[int, int]:
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=output.name + '.', suffix='.tmp', dir=output.parent)
    os.close(descriptor)
    staged = Path(temporary_name)
    count = 0
    try:
        with zipfile.ZipFile(staged, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for path in sorted(ROOT.rglob('*')):
                relative = path.relative_to(ROOT)
                if path.is_symlink() or not path.is_file() or path in (output, staged):
                    continue
                if any(part in EXCLUDE_DIRECTORIES for part in relative.parts):
                    continue
                if relative.parts[0] == 'old' and not include_old:
                    continue
                if path.suffix.lower() in EXCLUDE_SUFFIXES or any(part.startswith('.env') for part in relative.parts) or path.name == 'local.properties':
                    continue
                if (relative.parts[0] == 'docs' or relative.parts[:2] == ('data', 'authoring')) and (path.suffix == '.translation' or path.name.endswith('.csv.import')):
                    continue
                archive.write(path, 'almost-god/' + relative.as_posix())
                count += 1
        with zipfile.ZipFile(staged) as archive:
            invalid = archive.testzip()
            if invalid is not None:
                raise RuntimeError('Archive checksum failed: ' + invalid)
        staged.replace(output)
    finally:
        staged.unlink(missing_ok=True)
    return count, output.stat().st_size


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT.parent / 'deliverables/Almost-God-Project.zip', help='ZIP destination; replaced atomically after CRC validation.')
    parser.add_argument('--include-old', action='store_true', help='Include historical old/ reference art (already retained in Git).')
    args = parser.parse_args()
    count, size = package(args.output, args.include_old)
    print(f'{args.output.resolve()} — {count} files, {size} bytes; old/ included: {args.include_old}')


if __name__ == '__main__':
    main()
