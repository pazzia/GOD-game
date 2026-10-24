"""Capture actual Godot part-rig key poses for independent visual review.

These images prove only the rendered poses at the requested clip fraction.
They never automatically mark art, acting or directional animation accepted.
"""
from pathlib import Path
import argparse, json, os, shutil, socket, subprocess, tempfile, time

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actors', nargs='+')
    parser.add_argument('--phase', type=float, default=.35)
    parser.add_argument('--output', type=Path, default=ROOT/'build/rig-review')
    parser.add_argument('--tools-dir', type=Path, default=ROOT.parent/'tools')
    args = parser.parse_args()
    if not 0 <= args.phase < 1:
        parser.error('--phase must be in [0,1).')
    tools = args.tools_dir.resolve()
    godot = os.environ.get('GODOT_BIN', str(tools/'Godot_v4.7.2-stable_linux.x86_64'))
    wrapper = tools/'native/bin/Xvfb'
    xvfb = str(wrapper) if wrapper.is_file() else shutil.which('Xvfb')
    if not xvfb:
        parser.error('Provision the native tools with bootstrap_native.py first.')
    produced = {p.parent.name for p in (ROOT/'assets/art/characters/rigs').glob('*/rig.json')}
    actors = args.actors or sorted(produced)
    if not set(actors) <= produced:
        parser.error('Only produced part rigs may be reviewed; no baseline substitution.')
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(LIBGL_ALWAYS_SOFTWARE='1', DISPLAY='127.0.0.1:98')
    results = []
    with (out/'xvfb.log').open('w') as log:
        server = subprocess.Popen([xvfb, ':98', '-screen', '0', '1600x1000x24', '-ac',
                                   '-nolisten', 'unix', '-nolisten', 'local', '-listen', 'tcp'],
                                  stdout=log, stderr=log, env=env)
        try:
            for _ in range(50):
                if server.poll() is not None:
                    raise RuntimeError('Xvfb failed; inspect its log.')
                try:
                    with socket.create_connection(('127.0.0.1', 6098), timeout=.1):
                        break
                except OSError:
                    time.sleep(.1)
            else:
                raise RuntimeError('Xvfb did not become ready.')
            for actor in actors:
                image = out/(actor+'-keyposes.png')
                with tempfile.TemporaryDirectory(prefix='almost-god-rig-review-') as profile:
                    local = env.copy()
                    local['XDG_DATA_HOME'] = profile
                    result = subprocess.run([godot, '--path', str(ROOT), '--audio-driver', 'Dummy',
                        'res://tools/puppet_viewer.tscn', '--', '--sheet-actor='+actor,
                        '--sheet-phase='+str(args.phase), '--capture='+str(image)],
                        env=local, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
                (out/(actor+'.log')).write_text(result.stdout)
                errors = [line for line in result.stdout.splitlines() if line.startswith(('ERROR:', 'SCRIPT ERROR:'))
                          or 'leaked at exit' in line or 'still in use at exit' in line]
                item = dict(actor=actor, exit_code=result.returncode, image=str(image),
                            exists=image.exists(), clip_fraction=args.phase, errors=errors)
                results.append(item)
                print(json.dumps(item), flush=True)
        finally:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
    (out/'captures.json').write_text(json.dumps(dict(renderer='native Godot/Mesa/Xvfb',
        scope='Eight base poses and stamp at one clip fraction; manual visual acceptance separate.',
        cases=results), indent=2)+'\n')
    return int(any(r['exit_code'] or r['errors'] or not r['exists'] for r in results))

if __name__ == '__main__':
    raise SystemExit(main())
