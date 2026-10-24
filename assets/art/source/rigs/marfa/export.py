"""Lossless original Marfa parts-atlas export and mechanical composition check."""
from pathlib import Path
from PIL import Image
import numpy as np
from scipy import ndimage
import json
import os

SOURCE = Path(__file__).resolve().parent
ART = SOURCE.parents[2]
OUT = ART / 'characters/rigs/marfa'
OUT.mkdir(parents=True, exist_ok=True)
IM = Image.open(SOURCE / 'parts.png').convert('RGBA')
IM.load()
REGIONS = {
    'head': [0, 0, 440, 410], 'torso': [440, 0, 915, 470],
    'right_arm': [920, 0, 1254, 410], 'left_arm': [0, 420, 430, 800],
    'left_leg': [440, 480, 790, 800], 'right_leg': [880, 480, 1240, 800],
    'cape': [0, 800, 480, 1254], 'accessory': [490, 850, 920, 1254],
    'prop': [950, 790, 1254, 1254],
}
metadata = {}
for name, authored in REGIONS.items():
    box = [round(authored[0] * IM.width / 1254), round(authored[1] * IM.height / 1254),
           round(authored[2] * IM.width / 1254), round(authored[3] * IM.height / 1254)]
    part = IM.crop(box)
    arr = np.array(part)
    labels, count = ndimage.label(arr[:, :, 3] > 16)
    sizes = np.bincount(labels.ravel()); sizes[0] = 0
    if sizes.max() > 0:
        keep = sizes >= max(24, sizes.max() * .08); keep[0] = False
        owned = ndimage.binary_dilation(keep[labels], iterations=3)
        arr[:, :, 3] = np.where(owned, arr[:, :, 3], 0)
    part = Image.fromarray(arr)
    trim = part.getchannel('A').getbbox()
    part = part.crop(trim)
    temp = OUT / (name + '.tmp'); part.save(temp, format='PNG')
    with Image.open(temp) as check: check.load()
    os.replace(temp, OUT / (name + '.png'))
    metadata[name] = {'source': 'parts.png', 'crop': box, 'alpha_trim': trim, 'size': part.size}

rows = [
    ('cape', [700, 470], [.5, .04], 650, -30, 'torso', 'cape'),
    ('left_leg', [565, 1000], [.5, .04], 330, -20, None, 'leg'),
    ('right_leg', [835, 1000], [.5, .04], 330, -19, None, 'leg'),
    ('torso', [700, 470], [.5, .04], 650, 0, None, 'torso'),
    ('left_arm', [455, 580], [.80, .10], 340, -5, 'torso', 'arm'),
    ('right_arm', [945, 580], [.20, .12], 320, 5, 'torso', 'arm'),
    ('head', [700, 500], [.60, .96], 420, 10, 'torso', 'head'),
    ('accessory', [730, 790], [.5, .10], 260, 8, 'torso', 'prop'),
    ('prop', [1135, 855], [.52, .05], 430, 15, 'right_arm', 'prop'),
]
rig = {'schema_version': 1, 'actor_id': 'marfa', 'canvas_size': [1400, 1400],
       'feet_origin': [700, 1320], 'nominal_height': 1320,
       'status': 'assembly_review_pending', 'runtime_animation_verified': False,
       'parts': [{'id': name, 'file': name + '.png', 'position': position,
                  'pivot': pivot, 'target_height': height, 'z_index': z,
                  'parent': parent, 'role': role}
                 for name, position, pivot, height, z, parent, role in rows],
       'portraits': {state: f'res://assets/art/characters/portraits/marfa/{state}.png'
                    for state in ['idle','observe','suspect','accept','reveal_react','focused','embarrassed','celebrate']},
       'angles': {}}
for path, data in [(OUT / 'rig.json', rig), (SOURCE / 'export_metadata.json', metadata)]:
    temp = path.with_suffix('.tmp'); temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n'); os.replace(temp, path)
canvas = Image.new('RGBA', (1400, 1400), '#FFF5DE')
for part in sorted(rig['parts'], key=lambda p: p['z_index']):
    image = Image.open(OUT / part['file']).convert('RGBA')
    scale = part['target_height'] / image.height
    image = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
    x = round(part['position'][0] - part['pivot'][0] * image.width)
    y = round(part['position'][1] - part['pivot'][1] * image.height)
    canvas.alpha_composite(image, (x, y))
dest = ART.parents[1] / 'build/marfa-rig-assembly.png'
temp = dest.with_suffix('.tmp'); canvas.save(temp, format='PNG')
with temp.open('rb') as file: os.fsync(file.fileno())
with Image.open(temp) as check: check.load()
os.replace(temp, dest)
print('Exported 9 Marfa parts and actual assembly preview:', dest)
