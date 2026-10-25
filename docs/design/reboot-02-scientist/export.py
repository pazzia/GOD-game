"""Capture the scientist menu design; never modifies image pixels."""
from pathlib import Path
from hashlib import sha256
import json
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent
BASE = 'http://127.0.0.1:8772/reboot-02-scientist/menu.html'
records = []
with sync_playwright() as p:
    browser = p.chromium.launch(executable_path='/usr/bin/chromium', headless=True, args=['--no-sandbox'])
    for width, height in [(1560, 720), (844, 390)]:
        page = browser.new_page(viewport={'width': width, 'height': height}, device_scale_factor=1)
        errors = []
        failed = []
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.on('requestfailed', lambda r: failed.append(r.url))
        page.goto(BASE, wait_until='networkidle')
        page.evaluate('document.fonts.ready')
        checks = page.evaluate('''() => {
          const frame=document.querySelector('.game-frame').getBoundingClientRect();
          const texts=[...document.querySelectorAll('.menu-copy .eyebrow,h1,.menu-description,.menu-footnote span,.game-button span,.menu-emblem')];
          return {
            images:[...document.images].map(i=>({src:i.getAttribute('src'),loaded:i.complete&&i.naturalWidth>0})),
            fontsLoaded:document.fonts.check('900 32px Onest'),
            texts:texts.map(e=>{
              const range=document.createRange();range.selectNodeContents(e);
              const rects=[...range.getClientRects()];
              const p=e.getBoundingClientRect();
              return {text:e.innerText,insideFrame:rects.every(r=>r.left>=frame.left-.5&&r.top>=frame.top-.5&&r.right<=frame.right+.5&&r.bottom<=frame.bottom+.5),insideOwnBlock:rects.every(r=>r.left>=p.left-1&&r.right<=p.right+1)};
            }),
            cta:document.querySelector('.game-button').getBoundingClientRect().toJSON(),
            scientist:document.querySelector('.scientist-cutout').getBoundingClientRect().toJSON()
          };
        }''')
        assert not errors, errors
        assert not failed, failed
        assert checks['fontsLoaded']
        assert all(i['loaded'] for i in checks['images'])
        assert all(t['insideFrame'] and t['insideOwnBlock'] for t in checks['texts']), checks['texts']
        assert checks['cta']['height'] >= 48
        name = f'menu-scientist-{width}x{height}.png'
        page.screenshot(path=str(ROOT / name))
        records.append({'file': name, 'width': width, 'height': height, 'sha256': sha256((ROOT/name).read_bytes()).hexdigest(), 'checks': checks, 'pageErrors': errors, 'failedRequests': failed})
        page.close()
    browser.close()
(ROOT/'export-report.json').write_text(json.dumps({'status':'passed', 'scope':'Static design menu, not shipped gameplay or owner acceptance', 'captures':records}, ensure_ascii=False, indent=2)+'\n')
print('PASS: 2 menu captures; all images/fonts load, text fits and CTA height is at least 48 px.')
