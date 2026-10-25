"""Capture the real native Godot renderer with Xvfb/Mesa, never an HTML mockup.

Each capture has an isolated save/config profile. --quick records the core RU
journey; the default also records EN/RU at 140%, 720x360, 844x390 and 960x540 landscape phones.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import argparse,subprocess,os,socket,time,shutil,json,tempfile
ROOT=Path(__file__).resolve().parents[1]
def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--tools-dir',type=Path,default=ROOT.parent/'tools')
 parser.add_argument('--output',type=Path,default=ROOT/'build/ui')
 parser.add_argument('--quick',action='store_true')
 parser.add_argument('--display',type=int,default=96,choices=range(90,111),help='Dedicated Xvfb display; use distinct values for parallel capture runs.')
 parser.add_argument('--campaign',action='store_true',help='Capture all30 initial and successful campaign states.')
 parser.add_argument('--jobs',type=int,default=2,choices=[1,2,3],help='Bounded parallel native viewport captures, each with isolated saves.')
 parser.add_argument('--resolution',help='Override every capture with WIDTHxHEIGHT (for landscape device review).')
 parser.add_argument('--locale',choices=['ru','en'],help='Override every capture locale.')
 parser.add_argument('--text-scale',type=float,choices=[1.0,1.2,1.4],help='Override every capture text scale.')
 parser.add_argument('--only',help='Capture only view names starting with this prefix.')
 parser.add_argument('--levels',type=int,nargs='+',help='Capture these campaign levels with --stages (1–30).')
 parser.add_argument('--stages',nargs='+',choices=['title','briefing','map','plan','show','proof','law','resolution','moving','success','settings','selection'],help='Capture these states for each --levels entry at normal RU text size.')
 args=parser.parse_args();tools=args.tools_dir.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
 godot=os.environ.get('GODOT_BIN',str(tools/'Godot_v4.7.2-stable_linux.x86_64'))
 wrapper=tools/'native/bin/Xvfb';xvfb=str(wrapper) if wrapper.exists() else shutil.which('Xvfb')
 if not xvfb:raise SystemExit('Run tools/bootstrap_native.py to provision Xvfb, or install Xvfb.')
 cases=[(1,s,'ru',1.0,'960x540') for s in ['title','briefing','map','plan','show','proof','law','resolution','moving','success','settings']]
 cases +=[(n,'plan','ru',1.0,'960x540') for n in [2,3,11,21,30]]
 cases +=[(30,'selection','ru',1.0,'960x540'),(6,'plan','ru',1.0,'960x540'),(6,'moving','ru',1.0,'960x540')]
 if not args.quick:
  cases +=[(n,s,locale,scale,res) for n,s,locale,scale,res in [(1,'plan','ru',1.4,'720x360'),(1,'plan','en',1.4,'720x360'),(1,'settings','en',1.4,'720x360'),(1,'settings','ru',1.4,'720x360'),(1,'map','en',1.4,'844x390'),(11,'plan','en',1.4,'844x390'),(21,'plan','en',1.4,'720x360'),(30,'selection','en',1.4,'844x390')]]
 cases=[(*c,'') for c in cases]

 if args.campaign:cases=[(n,stage,'ru',1.0,'844x390','') for n in range(1,31) for stage in ['plan','success']]
 if args.levels or args.stages:
  if not args.levels or not args.stages or any(n<1 or n>30 for n in args.levels):parser.error('--levels (1–30) and --stages must be supplied together.')
  cases=[(n,stage,'ru',1.0,'960x540','') for n in args.levels for stage in args.stages]
 if args.locale or args.text_scale is not None:
  cases=[(c[0],c[1],args.locale or c[2],args.text_scale if args.text_scale is not None else c[3],c[4],c[5]) for c in cases]
 if args.resolution:
  import re
  if not re.fullmatch(r'[1-9][0-9]{2,3}x[1-9][0-9]{2,3}',args.resolution):parser.error('--resolution must be WIDTHxHEIGHT.')
  cases=[(*c[:4],args.resolution,c[5]) for c in cases]
 env=os.environ.copy();env['LIBGL_ALWAYS_SOFTWARE']='1'
 env['MESA_SHADER_CACHE_DIR']=str(tools/'capture-shader-cache')
 with (out/'xvfb.log').open('w') as log:
  server=subprocess.Popen([xvfb,':'+str(args.display),'-screen','0','2400x1200x24','-ac','-nolisten','unix','-nolisten','local','-listen','tcp'],env=env,stdout=log,stderr=log)
  try:
   for _ in range(50):
    try:
     with socket.create_connection(('127.0.0.1',6000+args.display),timeout=.1):break
    except OSError:
     if server.poll() is not None:raise RuntimeError('Xvfb startup failed; see '+str(out/'xvfb.log'))
     time.sleep(.1)
   else:raise RuntimeError('Xvfb TCP listener timed out.')
   env['DISPLAY']='127.0.0.1:'+str(args.display)
   results=[]
   def capture(case):
    n,stage,locale,scale,res,scroll=case
    name=f'L{n:02d}-{stage}-{locale}-{int(scale*100)}-{res}'+('-'+scroll if scroll else '')
    if args.only and not name.startswith(args.only):return None
    image=out/(name+'.png');capture_log=out/(name+'.log')
    image.unlink(missing_ok=True) # A stale image cannot make a failed current capture pass.
    with tempfile.TemporaryDirectory(prefix='almost-god-capture-') as profile:
     local=env.copy();local['XDG_DATA_HOME']=profile+'/data';local['XDG_CONFIG_HOME']=profile+'/config';local['XDG_CACHE_HOME']=profile+'/cache'
     with capture_log.open('w') as log:
      try:
       result=subprocess.run([godot,'--windowed','--path',str(ROOT),'--audio-driver','Dummy','--resolution',res,'--','--level='+str(n),'--capture-stage='+stage,'--locale='+locale,'--text-scale='+str(scale),'--capture-scroll='+scroll,'--screenshot='+str(image)],env=local,stdout=log,stderr=log,timeout=90)
       exit_code=result.returncode
      except subprocess.TimeoutExpired:
       exit_code=124;log.write('Capture timed out; not a pass.\n')
    text=capture_log.read_text(errors='replace');errors=[line for line in text.splitlines() if line.startswith(('ERROR:','SCRIPT ERROR:')) or 'leaked at exit' in line or 'still in use at exit' in line]
    return {'view':name,'exit_code':exit_code,'screenshot':str(image),'exists':image.exists(),'errors':errors}
   with ThreadPoolExecutor(max_workers=args.jobs) as pool:
    for pending in as_completed([pool.submit(capture,c) for c in cases]):
     record=pending.result()
     if record is not None:results.append(record);print(json.dumps(record,ensure_ascii=False),flush=True)
   results.sort(key=lambda row:row['view'])
   (out/'ui-captures.json').write_text(json.dumps({'renderer':'native Godot/Mesa/Xvfb','cases':results},ensure_ascii=False,indent=2)+'\n')
   if not results:raise SystemExit('No capture views match --only.')
   if any(r['exit_code'] or not r['exists'] or r['errors'] for r in results):raise SystemExit('One or more captures failed; see ui-captures.json.')
  finally:
   server.terminate()
   try:server.wait(timeout=5)
   except subprocess.TimeoutExpired:server.kill();server.wait()
if __name__=='__main__':main()
