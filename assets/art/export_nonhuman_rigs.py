"""Export calibrated nonhuman puppet parts from original production atlases.

The full-body reference positions are authored after looking at the assembled art.
They are not atlas cell centers. PNG exports retain true alpha and use atomic writes.
"""
from pathlib import Path
from PIL import Image
from atlas_export import export, ROOT
import json
import os
import sys


def save_rig(actor, rows, canvas, feet, nominal_height):
    rig = {
        'schema_version': 1, 'actor_id': actor,
        'canvas_size': canvas, 'feet_origin': feet,
        'nominal_height': nominal_height,
        'status': 'assembly_review_pending',
        'runtime_animation_verified': False,
        'parts': [
            {'id': part_id, 'file': part_id + '.png', 'position': position,
             'pivot': pivot, 'target_height': height, 'z_index': z,
             'parent': parent, 'role': role}
            for part_id, position, pivot, height, z, parent, role in rows
        ],
        'portraits': {state: f'res://assets/art/characters/portraits/{actor}/{state}.png'
                     for state in ['idle', 'observe', 'suspect', 'accept',
                                   'reveal_react', 'focused', 'embarrassed', 'celebrate']},
        'angles': {},
    }
    path = ROOT / f'characters/rigs/{actor}/rig.json'
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(rig, ensure_ascii=False, indent=2) + '\n')
    os.replace(temp, path)
    canvas_image = Image.new('RGBA', tuple(canvas), '#FFF5DE')
    for part in sorted(rig['parts'], key=lambda part: part['z_index']):
        image = Image.open(path.parent / part['file']).convert('RGBA')
        scale = part['target_height'] / image.height
        image = image.resize((round(image.width * scale), round(image.height * scale)),
                             Image.Resampling.LANCZOS)
        x = round(part['position'][0] - part['pivot'][0] * image.width)
        y = round(part['position'][1] - part['pivot'][1] * image.height)
        canvas_image.alpha_composite(image, (x, y))
    preview = ROOT.parents[1] / f'build/{actor}-rig-assembly.png'
    preview.parent.mkdir(exist_ok=True)
    preview_temp = preview.with_suffix('.tmp')
    canvas_image.save(preview_temp, format='PNG')
    with preview_temp.open('rb') as file:
        os.fsync(file.fileno())
    with Image.open(preview_temp) as verified:
        verified.load()
    os.replace(preview_temp, preview)
    print(f'{actor}: {len(rows)} parts; {preview}')


def plum():
    source = ROOT / 'source/bibles/plum_parts.png'
    image = Image.open(source)
    w, h = image.size
    def region(x1, y1, x2, y2):
        return [round(x1 * w / 1254), round(y1 * h / 1254),
                round(x2 * w / 1254), round(y2 * h / 1254)]
    regions = {
        'head': region(0, 0, 430, 445),
        'body': region(440, 0, 820, 495),
        'wing_left': region(820, 0, 1254, 485),
        'wing_right': region(0, 445, 440, 880),
        'antenna_left': region(445, 485, 820, 885),
        'antenna_right': region(840, 485, 1240, 885),
        'bag': region(0, 860, 460, 1254),
        'foot_left': region(500, 900, 760, 1254),
        'foot_right': region(890, 900, 1150, 1254),
    }
    export(source, {f'characters/rigs/plum/{key}.png': box for key, box in regions.items()})
    rows = [
        ('wing_left', [620, 750], [.95, .59], 650, -20, 'body', 'wing'),
        ('wing_right', [820, 750], [.05, .60], 480, -19, 'body', 'wing'),
        ('foot_left', [640, 1020], [.50, .04], 190, -10, 'body', 'leg'),
        ('foot_right', [745, 1010], [.50, .04], 190, -9, 'body', 'leg'),
        ('body', [720, 815], [.50, .50], 500, 0, None, 'torso'),
        ('head', [780, 670], [.50, .90], 370, 10, 'body', 'head'),
        ('antenna_left', [705, 390], [.72, .96], 220, 11, 'head', 'antenna'),
        ('antenna_right', [850, 390], [.28, .96], 220, 12, 'head', 'antenna'),
        ('bag', [650, 860], [.50, .55], 400, 8, 'body', 'prop'),
    ]
    save_rig('plum', rows, [1400, 1400], [700, 1200], 1050)


def caramelka():
    source = ROOT / 'source/bibles/caramelka_parts.png'
    image = Image.open(source)
    w, h = image.size
    def region(x1, y1, x2, y2):
        return [round(x1 * w / 1254), round(y1 * h / 1254),
                round(x2 * w / 1254), round(y2 * h / 1254)]
    regions = {
        'torso': region(0, 0, 515, 450),
        'head': region(510, 0, 875, 470),
        'horns': region(865, 0, 1254, 470),
        'front_left_leg': region(0, 450, 418, 840),
        'front_right_leg': region(418, 450, 836, 840),
        'hind_left_leg': region(836, 450, 1254, 840),
        'hind_right_leg': region(0, 840, 420, 1254),
        'tail': region(420, 840, 835, 1254),
        'collar_bell': region(835, 840, 1254, 1254),
    }
    export(source, {f'characters/rigs/caramelka/{key}.png': box
                    for key, box in regions.items()})
    rows = [
        ('tail', [325, 445], [.94, .65], 200, -20, 'torso', 'tail'),
        ('hind_right_leg', [500, 610], [.50, .04], 340, -14, None, 'leg'),
        ('front_right_leg', [950, 610], [.50, .04], 340, -13, None, 'leg'),
        ('hind_left_leg', [420, 610], [.50, .04], 340, -12, None, 'leg'),
        ('front_left_leg', [870, 610], [.50, .04], 340, -11, None, 'leg'),
        ('torso', [625, 500], [.50, .50], 450, 0, None, 'torso'),
        ('head', [1010, 510], [.50, .80], 430, 10, 'torso', 'head'),
        ('horns', [1005, 220], [.69, .94], 200, 11, 'head', 'horn'),
        ('collar_bell', [1000, 500], [.50, .20], 220, 20, 'head', 'prop'),
    ]
    save_rig('caramelka', rows, [1400, 1000], [700, 940], 940)


if __name__ == '__main__':
    globals()[sys.argv[1] if len(sys.argv) > 1 else 'plum']()
