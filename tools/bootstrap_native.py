"""Fetch pinned Godot/AOSP tools into a private cache. No sudo or system installs.

Linux x86_64 only. JDK 17+ and dpkg-deb are prerequisites. This provisions the
built-in Godot APK export/signing path, not the Gradle or complete Android SDK.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse,hashlib,http.client,json,os,platform,shutil,socket,subprocess,sys,time,urllib.error,urllib.request,urllib.parse,zipfile
ROOT=Path(__file__).resolve().parents[1]
VERSION='4.7.2'
GODOT_BASE=f'https://github.com/godotengine/godot/releases/download/{VERSION}-stable/'
def digest(path,algorithm='sha512'):
 h=hashlib.new(algorithm)
 with path.open('rb') as f:
  for chunk in iter(lambda:f.read(4*1024*1024),b''):h.update(chunk)
 return h.hexdigest()
def retryable_fetch_error(error):
 if isinstance(error,urllib.error.HTTPError):return error.code in (408,429) or 500<=error.code<600
 if isinstance(error,urllib.error.URLError):
  reason=error.reason
  return isinstance(reason,(TimeoutError,ConnectionError)) or isinstance(reason,socket.gaierror) and reason.errno==socket.EAI_AGAIN
 return isinstance(error,(TimeoutError,ConnectionError,http.client.IncompleteRead))
def fetch(url,path,expected,algorithm='sha512'):
 if path.exists() and digest(path,algorithm)==expected:return path
 path.parent.mkdir(parents=True,exist_ok=True)
 temp=path.with_suffix(path.suffix+'.partial')
 for attempt in range(3):
  try:
   with urllib.request.urlopen(url,timeout=90) as source,temp.open('wb') as out:
    while chunk:=source.read(4*1024*1024):out.write(chunk)
   break
  except (urllib.error.URLError,TimeoutError,ConnectionError,http.client.IncompleteRead) as error:
   temp.unlink(missing_ok=True)
   if not retryable_fetch_error(error) or attempt==2:raise
   print(f'Retrying pinned download {path.name} after a transient transport error ({attempt+1}/3).',flush=True)
   time.sleep(2**attempt)
 if digest(temp,algorithm)!=expected:
  temp.unlink();raise RuntimeError('Checksum mismatch: '+path.name)
 temp.replace(path)
 return path
def executable(path,text):
 path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text);path.chmod(0o755)
def setup(tools,graphics=True,android=True):
 if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'):
  raise RuntimeError('This optional bootstrap supports Linux x86_64; use installed Godot/Android SDK on other hosts.')
 if not shutil.which('dpkg-deb'):raise RuntimeError('dpkg-deb is required to extract the pinned AOSP packages.')
 tools.mkdir(parents=True,exist_ok=True)
 sums={line.split()[-1]:line.split()[0] for line in (ROOT/'tools/godot-4.7.2.SHA512-SUMS.txt').read_text().splitlines() if line.strip()}
 archives=[f'Godot_v{VERSION}-stable_linux.x86_64.zip',f'Godot_v{VERSION}-stable_export_templates.tpz']
 targets=[tools/f'Godot_v{VERSION}-stable_linux.x86_64',tools/f'export_templates/{VERSION}.stable/android_debug.apk']
 for name,target in zip(archives,targets):
  if not target.exists():
   archive=fetch(GODOT_BASE+name,tools/name,sums[name])
   with zipfile.ZipFile(archive) as z:
    for entry in z.namelist():
     if name.endswith('.zip') or entry.endswith(('android_debug.apk','android_release.apk')):
      dest=tools/Path(entry).name if name.endswith('.zip') else tools/f'export_templates/{VERSION}.stable'/Path(entry).name
      dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(z.read(entry));dest.chmod(0o755)
 lock=json.loads((ROOT/'tools/native_packages.lock.json').read_text())
 graphics_names={'xvfb','xserver-common','libxfont2','x11-xkb-utils','libxkbfile1'}
 entries=[entry for entry in lock['packages'] if (graphics or entry['filename'].split('_')[0] not in graphics_names) and (android or entry['filename'].split('_')[0] in graphics_names)]
 def package(entry):
  original_name=urllib.parse.unquote(entry['filename'])
  cached=tools/'packages'/original_name
  if not cached.exists():
   existing=tools/original_name
   if existing.exists() and digest(existing,entry['algorithm'])==entry['digest']:
    cached.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(existing,cached)
  return fetch(entry['url'],cached,entry['digest'],entry['algorithm'])
 with ThreadPoolExecutor(max_workers=4) as pool:packages=list(pool.map(package,entries))
 aosp=tools/'aosp';aosp.mkdir(exist_ok=True)
 for package_path in packages:subprocess.run(['dpkg-deb','-x',str(package_path),str(aosp)],check=True)
 lib_code="env['LD_LIBRARY_PATH']=':'.join(str(aosp/p) for p in ['usr/lib','usr/lib/x86_64-linux-gnu','usr/lib/x86_64-linux-gnu/android'])+':'+env.get('LD_LIBRARY_PATH','')\n"
 if graphics:
  xvfb=aosp/'usr/bin/Xvfb';data=xvfb.read_bytes()
  if data.count(b'/usr/bin\0')!=1:raise RuntimeError('Unexpected Xvfb compiler-path layout.')
  portable=xvfb.with_name('Xvfb-portable');portable.write_bytes(data.replace(b'/usr/bin\0',b'./bin___\0'));portable.chmod(0o755)
  bindir=aosp/'usr/bin___'
  if not bindir.exists():bindir.symlink_to('bin',target_is_directory=True)
  executable(tools/'native/bin/Xvfb',"#!/usr/bin/env python3\nfrom pathlib import Path\nimport os,sys\nroot=Path(__file__).resolve().parents[2]\naosp=root/'aosp'\nenv=os.environ.copy()\n"+lib_code+"os.chdir(aosp/'usr')\nos.execve(str(aosp/'usr/bin/Xvfb-portable'),['Xvfb',*sys.argv[1:]],env)\n")
 if android:
  sdk=tools/'android-sdk'
  executable(sdk/'platform-tools/adb',"#!/usr/bin/env python3\nfrom pathlib import Path\nimport os,sys\nroot=Path(__file__).resolve().parents[2]\naosp=root/'aosp'\nenv=os.environ.copy()\n"+lib_code+"os.execve(str(aosp/'usr/bin/adb'),['adb',*sys.argv[1:]],env)\n")
  executable(sdk/'build-tools/31.0.2/apksigner',"#!/usr/bin/env python3\nfrom pathlib import Path\nimport os,sys,shutil\nroot=Path(__file__).resolve().parents[3]\njava=os.environ.get('JAVA_HOME','')\njava=str(Path(java)/'bin/java') if java else shutil.which('java')\nif not java:raise SystemExit('JDK 17+ is required')\nos.execv(java,[java,'-jar',str(root/'aosp/usr/share/java/apksigner.jar'),*sys.argv[1:]])\n")
  (sdk/'build-tools/31.0.2/source.properties').write_text('Pkg.Desc=AOSP signing tools (31.0.2), not a complete Android SDK\nPkg.Revision=31.0.2\n')
 report={'godot_version':VERSION,'godot':str(targets[0]),'templates':str(targets[1].parent),'android_sdk_signing_root':str(tools/'android-sdk') if android else None,'graphics_wrapper':str(tools/'native/bin/Xvfb') if graphics else None,'package_count':len(entries),'licenses':'Upstream package copyright/license files retained under aosp/usr/share/doc.','limits':['No Gradle or emulator provisioning.','No store deployment or signing credentials are supplied.']}
 (tools/'native-toolchain.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(report,indent=2),flush=True)
 return report
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--tools-dir',type=Path,default=ROOT.parent/'tools')
 parser.add_argument('--no-graphics',action='store_true');parser.add_argument('--no-android',action='store_true')
 args=parser.parse_args();setup(args.tools_dir.resolve(),not args.no_graphics,not args.no_android)
