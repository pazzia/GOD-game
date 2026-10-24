"""Owned Lada source export; does not mutate shared atlas metadata or runtime code."""
from pathlib import Path
from PIL import Image
from scipy import ndimage
import numpy as np
import json
import os

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / 'characters/rigs/lada'
OUT.mkdir(parents=True, exist_ok=True)

REGIONS = {
    'head': [0, 0, 475, 510], 'torso': [440, 0, 959, 510],
    'right_arm': [959, 0, 1254, 510], 'left_arm': [0, 510, 500, 850],
    'left_leg': [530, 510, 840, 850], 'right_leg': [940, 510, 1254, 850],
    'cape': [0, 850, 680, 1254], 'accessory': [680, 850, 1005, 1254],
    'prop': [1005, 850, 1254, 1254],
}
ROWS = [
    ('left_leg', [570, 1110], [.50, .04], 230, -20, None, 'leg'),
    ('right_leg', [825, 1110], [.50, .04], 230, -19, None, 'leg'),
    ('torso', [700, 600], [.50, .04], 650, 0, None, 'torso'),
    ('left_arm', [470, 670], [.88, .12], 270, -5, 'torso', 'arm'),
    ('cape', [700, 590], [.50, .05], 460, 3, 'torso', 'cape'),
    ('right_arm', [930, 670], [.16, .18], 300, 5, 'torso', 'arm'),
    ('head', [700, 600], [.53, .96], 480, 10, 'torso', 'head'),
    ('accessory', [700, 630], [.50, .20], 150, 15, 'torso', 'prop'),
    ('prop', [1190, 735], [.73, .75], 400, 15, 'right_arm', 'prop'),
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
        'schema_version': 1, 'actor_id': 'lada', 'canvas_size': [1400, 1400],
        'feet_origin': [700, 1320], 'nominal_height': 1320,
        'status': 'assembly_review_pending', 'runtime_animation_verified': False,
        'parts': [{'id': name, 'file': name + '.png', 'position': pos,
                   'pivot': pivot, 'target_height': height, 'z_index': z,
                   'parent': parent, 'role': role}
                  for name, pos, pivot, height, z, parent, role in ROWS],
        'portraits': {state: f'res://assets/art/characters/portraits/lada/{state}.png'
                     for state in ['idle', 'observe', 'suspect', 'accept',
                                   'reveal_react', 'focused', 'embarrassed', 'celebrate']},
        'angles': {},
        'notes': ['cape is her floral shawl, drawn over the bodice with an open center.',
                  'accessory is the red neck bow, parented to torso.',
                  'prop is her wooden spoon, parented to the raised screen-right hand.',
                  'Skirt and apron belong to torso. Legs are deliberately short under the skirt.'],
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
    path = ROOT.parents[1] / 'build/lada-rig-assembly.png'
    atomic_png(preview, path)
    print('Exported9 Lada parts and calibrated candidate', path)

if __name__ == '__main__':
    main()
