import json, hashlib, datetime
from pathlib import Path
from playwright.sync_api import sync_playwright
OUT=Path('/workspace/design-review')
BASE='http://127.0.0.1:8765/mocks/index.html'
results=[]; browser_errors=[]; resource_errors=[]
def check(name, ok, detail=None):
 results.append({'name':name,'passed':bool(ok),'detail':detail})
 if not ok: print('FAIL',name,detail,flush=True)
def state(page): return page.evaluate('({...window.mockup.state})')
def click(page,action):
 page.locator('[data-action="'+action+'"]').first.click()
 page.wait_for_timeout(80)
def screenshot(page,name):
 page.locator('#game-frame').screenshot(path=str(OUT/(name+'.png')),animations='disabled')
with sync_playwright() as pw:
 browser=pw.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
 page=browser.new_page(viewport={'width':1560,'height':720},device_scale_factor=1)
 page.on('pageerror',lambda e:browser_errors.append(str(e)))
 page.on('console',lambda m:browser_errors.append(m.text) if m.type=='error' else None)
 page.on('requestfailed',lambda r:resource_errors.append({'url':r.url,'error':r.failure}))
 page.goto(BASE+'?screen=menu',wait_until='networkidle')
 page.wait_for_function('window.mockup && Array.from(document.images).every(i=>i.complete)')
 check('boot_menu',state(page)['screen']=='menu')
 click(page,'start');check('start_intro',state(page)['screen']=='intro')
 click(page,'help-marfa');check('intro_setup',state(page)['screen']=='setup')
 click(page,'perform');check('wrong_side_recoverable',state(page)['screen']=='setup' and state(page)['error']=='float')
 screenshot(page,'error-float-1560')
 click(page,'place');click(page,'place-front')
 click(page,'perform');check('tall_screen_hides_stone',state(page)['screen']=='setup' and state(page)['error']=='stone')
 screenshot(page,'error-stone-1560')
 click(page,'fold');check('fold_keeps_front_position',state(page)['position']=='front' and state(page)['folded'])
 click(page,'view');check('eye_preview_open',state(page)['overlay']=='view')
 screenshot(page,'eye-preview-1560')
 click(page,'close-overlay');check('eye_preview_preserves_setup',state(page)['screen']=='setup' and state(page)['folded'] and state(page)['position']=='front')
 click(page,'perform');check('valid_trick_proof',state(page)['screen']=='proof')
 click(page,'make-law');check('manual_law_transition',state(page)['screen']=='law')
 click(page,'cross');check('crossing_not_premature_victory',state(page)['screen']=='crossing')
 page.wait_for_function('window.mockup.state.screen===\"success\"',timeout=6000);check('automatic_arrival_success',state(page)['screen']=='success')
 click(page,'next-chapter');check('next_consequence_visible',state(page)['screen']=='next')
 click(page,'next-detail');check('next_detail_open',state(page)['overlay']=='next-detail')
 click(page,'restart');check('restart_menu',state(page)['screen']=='menu')
 page.evaluate('window.mockup.show("setup")')
 click(page,'select-screen');click(page,'place');click(page,'place-front');click(page,'fold')
 undo_count=page.locator('[data-action="undo"]').count()
 check('undo_control_present',undo_count>0)
 if undo_count:
  click(page,'undo');check('undo_restores_previous_fold_state',state(page)['position']=='front' and not state(page)['folded'])
 before=state(page)
 click(page,'pause');check('pause_open',state(page)['overlay']=='pause')
 screenshot(page,'pause-1560')
 click(page,'close-overlay');after=state(page)
 check('pause_resume_keeps_placement',before['position']==after['position'] and before['folded']==after['folded'] and after['overlay'] is None)
 captures=[]
 for width,height in [(1560,720),(844,390)]:
  page.set_viewport_size({'width':width,'height':height})
  page.goto(BASE+'?capture=1&screen=menu',wait_until='networkidle')
  for screen in ['menu','intro','setup','proof','law','crossing','success','next']:
   page.evaluate('id=>window.mockup.show(id)',screen);page.wait_for_timeout(60)
   page.wait_for_function('Array.from(document.images).every(i=>i.complete)')
   missing=page.evaluate('Array.from(document.images).filter(i=>!i.naturalWidth).map(i=>i.src)')
   check(f'{screen}_{width}_assets',not missing,missing)
   screenshot(page,f'{screen}-{width}')
   errors=page.evaluate("() => Array.from(document.querySelectorAll('.game-button,.objective-ribbon,.caption-ribbon,.speech,.story-copy,.win-copy,.overlay-panel')).flatMap(e=>{const box=e.getBoundingClientRect();if(!box.width||!box.height)return [];const w=document.createTreeWalker(e,NodeFilter.SHOW_TEXT);let n;const bad=[];while(n=w.nextNode()){if(!n.textContent.trim())continue;const r=document.createRange();r.selectNodeContents(n);for(const x of r.getClientRects()){if(x.left<box.left-2||x.right>box.right+2||x.top<box.top-2||x.bottom>box.bottom+2)bad.push(n.textContent)}}return bad.length?[{class:e.className,text:e.innerText,bad}]:[]})")
   check(f'{screen}_{width}_text_boxes',not errors,errors)
   captures.append({'screen':screen,'viewport':[width,height],'image':f'{screen}-{width}.png'})
 check('no_browser_errors',not browser_errors,browser_errors)
 check('no_failed_requests',not resource_errors,resource_errors)
 browser.close()
report={'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'url':BASE,'results':results,'browser_errors':browser_errors,'resource_errors':resource_errors,'captures':captures}
(OUT/'browser-results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'checks':len(results),'passed':sum(r['passed'] for r in results),'failed':sum(not r['passed'] for r in results),'captures':len(captures)},ensure_ascii=False))
