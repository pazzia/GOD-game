"""Owned Hugo source export; no shared art metadata/runtime writes."""
from pathlib import Path
from PIL import Image
from scipy import ndimage
import numpy as np
import json
import os

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / 'characters/rigs/hugo'
OUT.mkdir(parents=True, exist_ok=True)
REGIONS = {
    'head': [0, 0, 480, 385], 'torso': [480, 0, 800, 390],
    'right_arm': [800, 0, 1254, 385], 'left_arm': [0, 390, 440, 800],
    'left_leg': [440, 385, 820, 845], 'right_leg': [870, 385, 1254, 845],
    'cape': [0, 805, 535, 1254], 'accessory': [530, 845, 950, 1254],
    'prop': [950, 845, 1254, 1254],
}
ROWS = [
    ('cape', [700, 435], [.50, .04], 850, -30, 'torso', 'cape'),
    ('accessory', [590, 225], [.92, .15], 550, -25, 'head', 'cape'),
    ('left_leg', [630, 810], [.60, .04], 530, -20, None, 'leg'),
    ('right_leg', [800, 810], [.40, .04], 530, -19, None, 'leg'),
    ('torso', [700, 430], [.50, .04], 500, 0, None, 'torso'),
    ('left_arm', [550, 540], [.50, .10], 340, 5, 'torso', 'arm'),
    ('right_arm', [850, 540], [.12, .72], 320, 6, 'torso', 'arm'),
    ('head', [700, 480], [.51, .96], 400, 10, 'torso', 'head'),
    ('prop', [700, 505], [.50, .20], 150, 15, 'torso', 'prop'),
]

def atomic_png(image, path):
    temp = path.with_suffix('.tmp')
    image.save(temp, format='PNG')
    with temp.open('rb') as f:
        os.fsync(f.fileno())
    with Image.open(temp) as check:
        check.load()
    temp.replace(path)

def main():
    source = Image.open(HERE / 'parts.png').convert('RGBA')
    source.load()
    metadata = {}
    for part, region in REGIONS.items():
        box = [round(v * source.size[i % 2] / 1254) for i, v in enumerate(region)]
        image = source.crop(box)
        array = np.array(image)
        labels, count = ndimage.label(array[:, :, 3] > 16)
        sizes = np.bincount(labels.ravel())
        sizes[0] = 0
        keep = sizes >= max(24, sizes.max() * .08)
        keep[0] = False
        owned = ndimage.binary_dilation(keep[labels], iterations=3)
        array[:, :, 3] = np.where(owned, array[:, :, 3], 0)
        image = Image.fromarray(array)
        trim = image.getchannel('A').getbbox()
        image = image.crop(trim)
        atomic_png(image, OUT / (part + '.png'))
        metadata[part] = {'source': 'parts.png', 'crop': box, 'alpha_trim': trim,
                          'size': image.size}
    rig = {
        'schema_version': 1, 'actor_id': 'hugo', 'canvas_size': [1400, 1400],
        'feet_origin': [700, 1320], 'nominal_height': 1320,
        'status': 'assembly_review_pending', 'runtime_animation_verified': False,
        'parts': [{'id': name, 'file': name + '.png', 'position': pos,
                   'pivot': pivot, 'target_height': height, 'z_index': z,
                   'parent': parent, 'role': role}
                  for name, pos, pivot, height, z, parent, role in ROWS],
        'portraits': {state: f'res://assets/art/characters/portraits/hugo/{state}.png'
                     for state in ['idle', 'observe', 'suspect', 'accept',
                                   'reveal_react', 'focused', 'embarrassed', 'celebrate']},
        'angles': {},
        'notes': ['accessory is his long golden hat ribbon, parented to head.',
                  'prop is a clothing part: the red neck bow, parented to torso.',
                  'Hugo has presenting hands; no wand or invented handheld prop.',
                  'Cape and hat ribbon have independent cloth pivots.'],
    }
    temp = OUT / 'rig.tmp'
    temp.write_text(json.dumps(rig, ensure_ascii=False, indent=2) + '\n')
    temp.replace(OUT / 'rig.json')
    (HERE / 'extraction_metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    preview = Image.new('RGBA', (1400, 1400), '#fff5de')
    for part in sorted(rig['parts'], key=lambda part: part['z_index']):
        image = Image.open(OUT / part['file']).convert('RGBA')
        scale = part['target_height'] / image.height
        image = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
        x = round(part['position'][0] - part['pivot'][0] * image.width)
        y = round(part['position'][1] - part['pivot'][1] * image.height)
        preview.alpha_composite(image, (x, y))
    path = ROOT.parents[1] / 'build/hugo-rig-assembly.png'
    atomic_png(preview, path)
    print('Exported9 Hugo parts and calibrated candidate', path)

if __name__ == '__main__':
    main()
