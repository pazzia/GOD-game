"""Export imagegen originals mechanically; no procedural painting.

Requires ImageMagick. The paired edge paintings are scaled uniformly into the
approved corner bounds. Full-canvas sources, prompts and metadata remain intact.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ART = HERE.parents[1]

def run(*args):
    subprocess.run(['magick', *map(str, args)], check=True)

def main():
    manifest = json.loads((HERE / 'generation-2026-10-25.json').read_text())
    for item in manifest['images']:
        source = HERE / item['environment_id'] / (item['layer'] + '.png')
        target = ART / 'environments' / item['environment_id'] / source.name
        target.parent.mkdir(parents=True, exist_ok=True)
        if item['layer'] not in {'midground', 'foreground'}:
            shutil.copy2(source, target)
            continue
        scale = '60%' if item['layer'] == 'midground' else '50%'
        gravity = 'North' if item['layer'] == 'midground' else 'South'
        with tempfile.TemporaryDirectory(prefix='god-environment-') as temp:
            left, right = Path(temp) / 'left.png', Path(temp) / 'right.png'
            run(source, '-crop', '768x1024+0+0', '+repage', '-resize', scale, left)
            run(source, '-crop', '768x1024+768+0', '+repage', '-resize', scale, right)
            run('-size', '1536x1024', 'canvas:none', left, '-gravity', gravity + 'West',
                '-composite', right, '-gravity', gravity + 'East', '-composite', target)
    # Fallbacks are the actual independent-layer composites, with the same fit.
    for env, name in [('ENV01', 'bg_river'), ('ENV02', 'bg_kitchen'), ('ENV03', 'bg_archive')]:
        folder = ART / 'environments' / env
        run(folder / 'backdrop.png', folder / 'floor.png', '-composite',
            folder / 'midground.png', '-composite', folder / 'foreground.png',
            '-composite', ART / 'environments' / (name + '.png'))

if __name__ == '__main__':
    main()
