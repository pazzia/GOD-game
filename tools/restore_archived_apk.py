"""Restore the existing archived APK; does not build, deploy or publish anything."""
from pathlib import Path
import argparse
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
PARTS = ROOT / 'artifacts/android/0.2.0-build3'

def restore(output):
    manifest = json.loads((PARTS/'manifest.json').read_text())
    if output.exists():
        if hashlib.sha256(output.read_bytes()).hexdigest() == manifest['sha256']:
            print('APK already restored:', output)
            return
        raise SystemExit('Output exists with different bytes; choose --output PATH.')
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name+'.partial')
    digest = hashlib.sha256()
    size = 0
    try:
        with temporary.open('xb') as target:
            for part in manifest['parts']:
                if Path(part['file']).name != part['file']:
                    raise ValueError('Invalid part path')
                data = (PARTS/part['file']).read_bytes()
                if len(data) != part['size'] or hashlib.sha256(data).hexdigest() != part['sha256']:
                    raise ValueError('Part verification failed: '+part['file'])
                target.write(data)
                digest.update(data)
                size += len(data)
        if size != manifest['size'] or digest.hexdigest() != manifest['sha256']:
            raise ValueError('Restored APK checksum mismatch')
        temporary.rename(output)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise
    print('APK restored and SHA-256 verified:', output)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT/'build/Almost-God-0.2.0-debug.apk')
    restore(parser.parse_args().output.resolve())
