"""Read-only HTML contact sheets of actual native captures; original PNGs stay intact."""
from pathlib import Path
import hashlib,json,subprocess,sys
from playwright.sync_api import sync_playwright

ROOT=Path(__file__).resolve().parents[3]
CAPTURES=ROOT/'build/scientist-final-gallery'
OUT=ROOT/'build/scientist-qa-contact-sheets'
OUT.mkdir(parents=True,exist_ok=True)
records=[]
for chapter in range(1,4):
 for state in ['plan','success']:
  cards=[]
  for number in range((chapter-1)*10+1,chapter*10+1):
   name=f'L{number:02d}-{state}-ru-100-844x390.png'
   source=CAPTURES/name
   if not source.is_file():raise SystemExit('Missing native screenshot '+str(source))
   cards.append(f'<article><div>L{number:02d} · {state}</div><img src="../scientist-final-gallery/{name}" width="844" height="390"></article>')
  name=f'chapter-{chapter}-{state}'
  html='<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:#252647;font:18px Arial;color:#fff2d8}.gallery{display:grid;grid-template-columns:844px 844px;gap:8px;padding:8px;width:max-content}article{margin:0}article>div{height:28px;line-height:28px;padding-left:10px}img{display:block}</style><main class="gallery">'+''.join(cards)+'</main>'
  (OUT/(name+'.html')).write_text(html)
  records.append({'name':name,'source_kind':'HTML composition of actual Godot captures; no source-art changes','native_views':10})
server=subprocess.Popen([sys.executable,'-m','http.server','8790','--bind','127.0.0.1','--directory',str(ROOT/'build')],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
try:
 with sync_playwright() as p:
  browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
  page=browser.new_page(viewport={'width':1712,'height':2140},device_scale_factor=1)
  for record in records:
   page.goto('http://127.0.0.1:8790/scientist-qa-contact-sheets/'+record['name']+'.html',wait_until='networkidle')
   if not page.evaluate('[...document.images].every(i=>i.complete&&i.naturalWidth===844)'):raise RuntimeError('A native capture did not load')
   path=OUT/(record['name']+'.png');page.locator('.gallery').screenshot(path=str(path))
   record['sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
  browser.close()
finally:
 server.terminate();server.wait(timeout=5)
(OUT/'manifest.json').write_text(json.dumps({'kind':'Read-only QA contact sheets; originals are native Godot screenshots','sheets':records},indent=2)+'\n')
print('Rendered6contact sheets from60native captures.')
