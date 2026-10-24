from atlas_export import export,ROOT
from pathlib import Path
from PIL import Image
import json
raw=Path('/workspace/scratch/585c9249475c/generated_images')
export(raw/'exec-37afd372-07bb-496c-9d8e-2ad38e732731.png',{'environments/bg_kitchen.png':None})
export(raw/'exec-a470db49-910a-4bec-a3b2-0399e1568188.png',{'environments/bg_archive.png':None})
jobs=[('exec-60afd313-51e3-4e25-a048-4fc5bb23e5be.png',{
 'stone':(0,0,540,341),'float':(540,0,1024,341),'screen':(1024,0,1536,350),
 'crate':(0,341,540,674),'rope':(540,341,1024,674),'wooden_bollard':(1024,350,1536,680),
 'boat':(0,674,570,1024),'ticket_booth':(570,674,980,1024),'dock':(980,680,1536,1024)}),
 ('exec-5143bd65-bef2-4603-9e0c-7d4004e479d4.png',{
 'decoy_fire':(0,0,520,345),'cryopack':(520,0,1024,350),'water_bowl':(1024,0,1536,340),
 'fire_source':(0,312,520,680),'hot_stone':(520,350,1024,680),'thermobox':(1024,340,1536,680),
 'bread':(0,680,565,1024),'dessert':(565,680,1024,1024),'steam':(1024,660,1536,1024)}),
 ('exec-cdf10bd6-be72-4575-8f53-4964418073c8.png',{
 'paper_bridge':(0,0,565,341),'paper_gate':(565,0,1024,341),'wood_gate':(1024,0,1536,341),
 'control_weight':(0,341,545,680),'frame':(545,341,1024,680),'hoist':(1024,341,1536,680),
 'clamp':(0,680,535,1024),'thread':(535,680,1024,1024),'flags':(1024,680,1536,1024)})]
for src,regs in jobs:export(raw/src,{f'props/{key}.png':box for key,box in regs.items()})
src=raw/'exec-2a2f431d-f3c8-4ad3-8ac9-49b77fec20b1.png';im=Image.open(src);w,h=im.size;names=['stone_anchor','fire_source_cold','water_bowl_frozen','paper_reinforced','miracle_stamp','paper_sheet','kettle','sandbag','thermal_screen']
regions={
'props/stone_anchor.png':(0,0,435,446),'props/fire_source_cold.png':(435,0,875,445),'props/water_bowl_frozen.png':(875,0,w,442),
'props/paper_reinforced.png':(0,445,435,790),'props/miracle_stamp.png':(435,445,875,790),'props/paper_sheet.png':(875,442,w,804),
'props/kettle.png':(0,790,435,h),'props/sandbag.png':(435,790,875,h),'props/thermal_screen.png':(875,780,w,h)}
export(src,regions)
print('baseline:3ENV9CH36props')
