"""Build and verify a local signed debug APK using Godot's built-in exporter.

Run bootstrap_native.py first on Linux x86_64. JDK 17+ is required. The private
AOSP signing subset is sufficient for this template export; Gradle, an emulator,
and store/release signing are deliberately outside this script. Source files and
editor profiles are never modified by the export.
"""
from pathlib import Path
import argparse,hashlib,json,os,re,shutil,subprocess,sys,tempfile,time
from verify_project import runtime_manifest
ROOT=Path(__file__).resolve().parents[1]
VERSION='4.7.2'
def quoted(value):return json.dumps(str(value),ensure_ascii=False)
def run(command,log,env,timeout=600):
 with log.open('w') as output:
  result=subprocess.run([str(p) for p in command],stdout=output,stderr=subprocess.STDOUT,env=env,timeout=timeout)
 if result.returncode:raise RuntimeError(f'Command failed ({result.returncode}); see {log}')
 text=log.read_text(errors='replace')
 if 'SCRIPT ERROR:' in text or re.search(r'^ERROR:',text,re.M):raise RuntimeError(f'Godot reported errors; see {log}')
 return text

def build(args):
 tools=args.tools_dir.resolve();output=args.output.resolve();output.parent.mkdir(parents=True,exist_ok=True)
 godot=tools/f'Godot_v{VERSION}-stable_linux.x86_64'
 sdk=tools/'android-sdk';templates=tools/f'export_templates/{VERSION}.stable'
 java=args.java_home.resolve() if args.java_home else Path(shutil.which('java') or '').resolve().parents[1]
 for path in [godot,templates/'android_debug.apk',templates/'android_release.apk',sdk/'build-tools/31.0.2/apksigner',sdk/'platform-tools/adb',java/'bin/keytool']:
  if not path.is_file():raise RuntimeError(f'Missing {path}; run tools/bootstrap_native.py or supply --java-home.')
 keystore=ROOT/'tools/signing/debug.keystore'
 keystore.parent.mkdir(parents=True,exist_ok=True)
 env=os.environ.copy();env['JAVA_HOME']=str(java)
 if not keystore.exists():
  run([java/'bin/keytool','-genkeypair','-keystore',keystore,'-storepass','android','-alias','androiddebugkey','-keypass','android','-dname','CN=Android Debug,O=Local Development,C=US','-keyalg','RSA','-keysize','2048','-validity','10000'],output.with_suffix('.keytool.log'),env)
 source_manifest=runtime_manifest()
 source_digest=hashlib.sha256(json.dumps(source_manifest,sort_keys=True,separators=(',',':')).encode()).hexdigest()
 started=time.monotonic()
 with tempfile.TemporaryDirectory(prefix='almost-god-export-',dir=tools) as temp_name:
  temp=Path(temp_name);staged=temp/'game'
  def ignore(directory,names):
   result={n for n in names if n in ('.godot','__pycache__','.git')}
   relative=Path(directory).relative_to(ROOT)
   if relative==Path('.'):result.update(n for n in names if n in ('build','tests','tools','docs'))
   if relative==Path('data'):result.add('authoring')
   if relative==Path('assets'):result.add('source')
   if relative==Path('assets/art'):result.add('source')
   if relative==Path('assets/audio/production'):result.add('source')
   return result
  shutil.copytree(ROOT,staged,ignore=ignore)
  preset=(staged/'export_presets.cfg').read_text()
  values={'custom_template/debug':templates/'android_debug.apk','custom_template/release':templates/'android_release.apk','keystore/debug':keystore,'keystore/debug_user':'androiddebugkey','keystore/debug_password':'android'}
  for key,value in values.items():preset=re.sub(r'^'+re.escape(key)+r'=.*$',key+'='+quoted(value),preset,flags=re.M)
  (staged/'export_presets.cfg').write_text(preset)
  env['XDG_DATA_HOME']=str(temp/'data');env['XDG_CONFIG_HOME']=str(temp/'config');env['XDG_CACHE_HOME']=str(temp/'cache')
  config=temp/'config/godot';config.mkdir(parents=True)
  properties={'export/android/java_sdk_path':java,'export/android/android_sdk_path':sdk,'export/android/debug_keystore':keystore,'export/android/debug_keystore_user':'androiddebugkey','export/android/debug_keystore_pass':'android'}
  settings='[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'+'\n'.join(key+' = '+quoted(value) for key,value in properties.items())+'\n'
  (config/'editor_settings-4.7.tres').write_text(settings)
  print('Importing isolated native project…',flush=True)
  run([godot,'--headless','--editor','--path',staged,'--import','--quit'],output.with_suffix('.import.log'),env)
  print('Exporting signed arm64 debug APK…',flush=True)
  run([godot,'--headless','--path',staged,'--export-debug','Android',output],output.with_suffix('.export.log'),env)
 if not output.is_file():raise RuntimeError('Exporter produced no APK.')
 if runtime_manifest()!=source_manifest:raise RuntimeError('Runtime source changed during export; this artifact is not a verified frozen build.')
 signature=run([sdk/'build-tools/31.0.2/apksigner','verify','--verbose','--print-certs',output],output.with_suffix('.signature.log'),env)
 certificate=re.search(r'Signer #1 certificate SHA-256 digest: ([a-f0-9]+)',signature)
 expected=(ROOT/'tools/signing/certificate.sha256').read_text().strip()
 if certificate is None or certificate.group(1)!=expected:raise RuntimeError('APK test signing identity does not match the durable debug certificate.')
 inspection=run([sys.executable,ROOT/'tools/inspect_apk.py',output,'--source-root',ROOT],output.with_suffix('.inspection.json'),env)
 report=json.loads(inspection)
 report.update({'elapsed_seconds':round(time.monotonic()-started,2),'signature_verified':True,'certificate_sha256':certificate.group(1),'signing':'local debug key; not a release/store key','godot_version':VERSION,'physical_device_tested':False,'build_method':'Godot built-in template export; AOSP signing subset, no Gradle','source_runtime_digest_sha256':source_digest})
 output.with_suffix('.build.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({'apk':str(output),'size_bytes':report['size_bytes'],'sha256':report['sha256'],'signature_verified':True,'level_count':report['level_count'],'physical_device_tested':False},ensure_ascii=False,indent=2),flush=True)
 return report
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--tools-dir',type=Path,default=ROOT.parent/'tools')
 parser.add_argument('--java-home',type=Path)
 parser.add_argument('--output',type=Path,default=ROOT/'build/AlmostGod-debug.apk')
 args=parser.parse_args()
 try:build(args)
 except (RuntimeError,subprocess.TimeoutExpired) as error:raise SystemExit(str(error))
