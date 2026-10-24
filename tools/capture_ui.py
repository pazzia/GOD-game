"""Capture the real native Godot renderer with Xvfb/Mesa, never an HTML mockup.

Each capture has an isolated save/config profile. --quick records the core RU
journey; the default also records EN/RU at 140%, 360x640 and tall 360x800.
"""
from pathlib import Path
import argparse,subprocess,os,socket,time,shutil,json,tempfile
ROOT=Path(__file__).resolve().parents[1]
def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--tools-dir',type=Path,default=ROOT.parent/'tools')
 parser.add_argument('--output',type=Path,default=ROOT/'build/ui')
 parser.add_argument('--quick',action='store_true')
 parser.add_argument('--only',help='Capture only view names starting with this prefix.')
 args=parser.parse_args();tools=args.tools_dir.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
 godot=os.environ.get('GODOT_BIN',str(tools/'Godot_v4.7.2-stable_linux.x86_64'))
 wrapper=tools/'native/bin/Xvfb';xvfb=str(wrapper) if wrapper.exists() else shutil.which('Xvfb')
 if not xvfb:raise SystemExit('Run tools/bootstrap_native.py to provision Xvfb, or install Xvfb.')
 cases=[(1,s,'ru',1.0,'540x960') for s in ['title','map','plan','show','proof','law','resolution','moving','success','settings']]
 cases +=[(n,'plan','ru',1.0,'540x960') for n in [2,3,11,21,30]]
 cases +=[(30,'selection','ru',1.0,'540x960'),(6,'plan','ru',1.0,'540x960'),(6,'moving','ru',1.0,'540x960')]
 if not args.quick:
  cases +=[(n,s,locale,scale,res) for n,s,locale,scale,res in [(1,'plan','ru',1.4,'360x640'),(1,'plan','en',1.4,'360x640'),(1,'settings','en',1.4,'360x640'),(1,'settings','ru',1.4,'360x640'),(1,'map','en',1.4,'360x800'),(11,'plan','en',1.4,'360x800'),(21,'plan','en',1.4,'360x640'),(30,'selection','en',1.4,'360x800')]]
 env=os.environ.copy();env['LIBGL_ALWAYS_SOFTWARE']='1'
 with (out/'xvfb.log').open('w') as log:
  server=subprocess.Popen([xvfb,':96','-screen','0','1080x2400x24','-ac','-nolisten','unix','-nolisten','local','-listen','tcp'],env=env,stdout=log,stderr=log)
  try:
   for _ in range(50):
    try:
     with socket.create_connection(('127.0.0.1',6096),timeout=.1):break
    except OSError:
     if server.poll() is not None:raise RuntimeError('Xvfb startup failed; see '+str(out/'xvfb.log'))
     time.sleep(.1)
   else:raise RuntimeError('Xvfb TCP listener timed out.')
   env['DISPLAY']='127.0.0.1:96'
   results=[]
   cases=[(*c,'') for c in cases]
   if not args.quick:cases +=[(1,'plan','ru',1.4,'360x640','audience'),(1,'plan','en',1.4,'360x640','audience'),(21,'plan','ru',1.4,'360x640','audience'),(1,'plan','ru',1.4,'360x640','audience_end'),(1,'plan','ru',1.4,'360x640','inventory_end')]
   for n,stage,locale,scale,res,scroll in cases:
    name=f'L{n:02d}-{stage}-{locale}-{int(scale*100)}-{res}'+('-'+scroll if scroll else '')
    if args.only and not name.startswith(args.only):continue
    image=out/(name+'.png');capture_log=out/(name+'.log')
    with tempfile.TemporaryDirectory(prefix='almost-god-capture-') as profile:
     local=env.copy();local['XDG_DATA_HOME']=profile+'/data';local['XDG_CONFIG_HOME']=profile+'/config';local['XDG_CACHE_HOME']=profile+'/cache'
     with capture_log.open('w') as log:
      result=subprocess.run([godot,'--path',str(ROOT),'--audio-driver','Dummy','--resolution',res,'--','--level='+str(n),'--capture-stage='+stage,'--locale='+locale,'--text-scale='+str(scale),'--capture-scroll='+scroll,'--screenshot='+str(image)],env=local,stdout=log,stderr=log,timeout=60)
    text=capture_log.read_text(errors='replace');errors=[line for line in text.splitlines() if line.startswith(('ERROR:','SCRIPT ERROR:')) or 'leaked at exit' in line or 'still in use at exit' in line]
    record={'view':name,'exit_code':result.returncode,'screenshot':str(image),'exists':image.exists(),'errors':errors}
    results.append(record);print(json.dumps(record,ensure_ascii=False),flush=True)
   (out/'ui-captures.json').write_text(json.dumps({'renderer':'native Godot/Mesa/Xvfb','cases':results},ensure_ascii=False,indent=2)+'\n')
   if not results:raise SystemExit('No capture views match --only.')
   if any(r['exit_code'] or not r['exists'] or r['errors'] for r in results):raise SystemExit('One or more captures failed; see ui-captures.json.')
  finally:
   server.terminate()
   try:server.wait(timeout=5)
   except subprocess.TimeoutExpired:server.kill();server.wait()
if __name__=='__main__':main()
