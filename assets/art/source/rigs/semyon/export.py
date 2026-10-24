"""Lossless original Semyon parts-atlas export and mechanical composition check."""
from pathlib import Path
from PIL import Image
import numpy as np
from scipy import ndimage
import json
import os

SOURCE = Path(__file__).resolve().parent
ART = SOURCE.parents[2]
OUT = ART / 'characters/rigs/semyon'
OUT.mkdir(parents=True, exist_ok=True)
IM = Image.open(SOURCE / 'parts.png').convert('RGBA')
IM.load()
REGIONS = {
    'head': [0, 0, 440, 415], 'torso': [450, 0, 810, 420],
    'right_arm': [820, 0, 1254, 415], 'left_arm': [0, 420, 450, 795],
    'left_leg': [500, 420, 805, 870], 'right_leg': [900, 420, 1254, 870],
    'cape': [0, 820, 420, 1254], 'accessory': [420, 870, 820, 1254],
    'prop': [830, 880, 1254, 1254],
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
    ('cape', [660, 440], [.5, .04], 420, -30, 'torso', 'cape'),
    ('left_leg', [600, 805], [.5, .04], 550, -20, None, 'leg'),
    ('right_leg', [760, 805], [.5, .04], 550, -19, None, 'leg'),
    ('torso', [660, 440], [.5, .04], 420, 0, None, 'torso'),
    ('left_arm', [495, 525], [.50, .12], 390, 6, 'torso', 'arm'),
    ('right_arm', [815, 525], [.16, .12], 370, 5, 'torso', 'arm'),
    ('head', [660, 470], [.40, .94], 400, 10, 'torso', 'head'),
    ('accessory', [650, 785], [.5, .20], 280, 8, 'torso', 'prop'),
    ('prop', [690, 700], [.04, .88], 300, 15, 'right_arm', 'prop'),
]
rig = {'schema_version': 1, 'actor_id': 'semyon', 'canvas_size': [1400, 1400],
       'feet_origin': [700, 1320], 'nominal_height': 1320,
       'status': 'assembly_review_pending', 'runtime_animation_verified': False,
       'parts': [{'id': name, 'file': name + '.png', 'position': position,
                  'pivot': pivot, 'target_height': height, 'z_index': z,
                  'parent': parent, 'role': role}
                 for name, position, pivot, height, z, parent, role in rows],
       'portraits': {state: f'res://assets/art/characters/portraits/semyon/{state}.png'
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
dest = ART.parents[1] / 'build/semyon-rig-assembly.png'
temp = dest.with_suffix('.tmp'); canvas.save(temp, format='PNG')
with temp.open('rb') as file: os.fsync(file.fileno())
with Image.open(temp) as check: check.load()
os.replace(temp, dest)
print('Exported 9 Semyon parts and actual assembly preview:', dest)
