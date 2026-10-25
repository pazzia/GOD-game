import json,datetime
from pathlib import Path
from playwright.sync_api import sync_playwright
OUT=Path('/workspace/design-review');BASE='http://127.0.0.1:8765/mocks/index.html'
checks=[];errors=[];bad_http=[];small_targets=[]
def check(name,ok,detail=None):
 checks.append({'name':name,'passed':bool(ok),'detail':detail})
 if not ok:print('FAIL',name,detail,flush=True)
TEXTCHECK="""() => Array.from(document.querySelectorAll('.game-button,.objective-ribbon,.caption-ribbon,.speech,.story-copy,.win-copy,.overlay-panel')).flatMap(e=>{const box=e.getBoundingClientRect();if(!box.width||!box.height)return [];const w=document.createTreeWalker(e,NodeFilter.SHOW_TEXT);let n;const bad=[];while(n=w.nextNode()){if(!n.textContent.trim())continue;const r=document.createRange();r.selectNodeContents(n);for(const x of r.getClientRects()){if(x.left<box.left-2||x.right>box.right+2||x.top<box.top-2||x.bottom>box.bottom+2)bad.push(n.textContent)}}return bad.length?[{class:e.className,text:e.innerText,bad}]:[]})"""
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox']);page=b.new_page(viewport={'width':1560,'height':720})
 page.on('pageerror',lambda e:errors.append(str(e)));page.on('console',lambda m:errors.append({'text':m.text,'location':m.location}) if m.type=='error' else None)
 page.on('response',lambda r:bad_http.append({'status':r.status,'url':r.url}) if r.status>=400 else None)
 for width,height in [(1560,720),(844,390)]:
  page.set_viewport_size({'width':width,'height':height});page.goto(BASE+'?capture=1&screen=menu',wait_until='networkidle')
  for screen in ['menu','intro','setup','proof','law','crossing','success','next']:
   page.evaluate('id=>window.mockup.show(id)',screen);page.wait_for_function('Array.from(document.images).every(i=>i.complete)')
   missing=page.evaluate('Array.from(document.images).filter(i=>!i.naturalWidth).map(i=>i.src)');check(f'{screen}_{width}_assets',not missing,missing)
   bad=page.evaluate(TEXTCHECK);check(f'{screen}_{width}_text_bounds',not bad,bad)
   page.locator('#game-frame').screenshot(path=str(OUT/f'{screen}-{width}.png'),animations='disabled')
   if width==844:
    small=page.locator('#game-frame button').evaluate_all('(es)=>es.filter(e=>!e.disabled).map(e=>({text:e.innerText,label:e.getAttribute("aria-label"),action:e.dataset.action,w:e.getBoundingClientRect().width,h:e.getBoundingClientRect().height})).filter(e=>e.w<44||e.h<44)')
    small_targets.extend([dict(x,screen=screen) for x in small])
 page.set_viewport_size({'width':1560,'height':720})
 page.goto(BASE+'?capture=1&screen=setup',wait_until='networkidle')
 truths=[]
 for placement,folded in [('side',False),('side',True),('front',False),('front',True)]:
  page.evaluate('x=>{window.mockup.show("setup");Object.assign(window.mockup.state,{position:x[0],folded:x[1]});window.mockup.render()}',[placement,folded])
  page.locator('[data-action="view"]').click()
  stone=page.locator('.marfa-view .prop-stone').count()>0;float_=page.locator('.marfa-view .prop-float').count()>0
  want_stone=not(placement=='front' and not folded);want_float=placement=='side'
  check(f'eye_{placement}_{folded}',stone==want_stone and float_==want_float,{'stone':stone,'float':float_})
  page.locator('#game-frame').screenshot(path=str(OUT/f'eye-{placement}-{str(folded).lower()}.png'),animations='disabled')
  truths.append({'placement':placement,'folded':folded,'stone_visible':stone,'float_visible':float_})
 check('touch_targets_844_min44',not small_targets,small_targets)
 check('no_console_errors_after_favicon_fix',not errors,errors);check('no_http_errors',not bad_http,bad_http)
 b.close()
(OUT/'visual-recheck.json').write_text(json.dumps({'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'checks':checks,'eye_truths':truths,'small_targets':small_targets,'console_errors':errors,'http_errors':bad_http},ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'checks':len(checks),'passed':sum(x['passed'] for x in checks),'failed':sum(not x['passed'] for x in checks)},ensure_ascii=False))
