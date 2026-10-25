"""Render the reviewed design prototype to PNG; does not alter its source artwork."""
from pathlib import Path
import hashlib,json
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parent
STATES=['menu','intro','setup','proof','law','crossing','success','next']
BASE='http://127.0.0.1:8765/mocks/index.html'
records=[]
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
 for width,height in [(1560,720),(844,390)]:
  page=b.new_page(viewport={'width':width,'height':height},device_scale_factor=1)
  for i,state in enumerate(STATES,1):
   page.goto(BASE+f'?capture=1&screen={state}',wait_until='networkidle');page.evaluate('document.fonts.ready')
   assert page.evaluate('[...document.images].every(i=>i.complete&&i.naturalWidth>0)')
   name=f'{i:02d}-{state}-{width}x{height}.png';target=ROOT/'exports'/name;page.screenshot(path=str(target))
   records.append({'file':'exports/'+name,'screen':state,'width':width,'height':height,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
  for label,query in [('setup-correct','screen=setup&position=front&folded=true'),('eye-correct','screen=setup&position=front&folded=true&overlay=view')]:
   page.goto(BASE+'?capture=1&'+query,wait_until='networkidle');name=f'{label}-{width}x{height}.png';target=ROOT/'exports'/name;page.screenshot(path=str(target));records.append({'file':'exports/'+name,'screen':label,'width':width,'height':height,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
  page.close()
 b.close()
for p in (ROOT/'exports').glob('draft-*.png'):p.unlink()
(ROOT/'exports'/'manifest.json').write_text(json.dumps({'kind':'Browser-rendered design mockups; not the shipped Godot application','screenshots':records,'source_sha256':{n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in ['index.html','app.js','style.css']}},ensure_ascii=False,indent=2)+'\n')
print(f'Rendered {len(records)} actual PNG screenshots.')
