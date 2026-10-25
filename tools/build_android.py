"""Build and verify a local signed debug APK using Godot's built-in exporter.

Run bootstrap_native.py first on Linux x86_64. JDK 17+ is required. The private
AOSP signing subset is sufficient for this template export; Gradle, an emulator,
and store/release signing are deliberately outside this script. Source files and
editor profiles are never modified by the export.
"""
from pathlib import Path
import argparse,copy,hashlib,json,os,re,shutil,struct,subprocess,sys,tempfile,time,zipfile
from verify_project import runtime_manifest, engine_errors
ROOT=Path(__file__).resolve().parents[1]
VERSION='4.7.2'
MIN_SDK=29

def manifest_min_sdk(data):
 """Locate the unique integer Android minSdkVersion in bounded binary AXML.

 The official template uses an integer with no raw string. Reject other forms
 rather than guessing at string indexes or replacing unrelated occurrences.
 """
 def fail():raise RuntimeError('Unsupported or malformed binary Android manifest.')
 def unpack(fmt,at,end):
  if at<0 or at+struct.calcsize(fmt)>end:fail()
  return struct.unpack_from(fmt,data,at)
 if len(data)<8 or unpack('<HHI',0,len(data))!=(3,8,len(data)):fail()
 strings=None;resources=None;matches=[];sdk_elements=0;pos=8
 while pos<len(data):
  kind,header,size=unpack('<HHI',pos,len(data));end=pos+size
  if header<8 or size<header or end>len(data) or size%4:fail()
  if kind==1:
   if strings is not None or header<28:fail()
   count,styles,flags,start,style_start=unpack('<IIIII',pos+8,end)
   if count>size//4 or styles>size//4 or header+(count+styles)*4>start or start>size:fail()
   string_end=pos+(style_start if style_start else size)
   if string_end<pos+start or string_end>end:fail()
   strings=[]
   for index in range(count):
    at=pos+start+unpack('<I',pos+header+index*4,end)[0]
    if at>=string_end:fail()
    def length(at,utf8):
     fmt,step,mask=('<B',1,0x80) if utf8 else ('<H',2,0x8000)
     value=unpack(fmt,at,string_end)[0];at+=step
     if value&mask:
      value=((value&(mask-1))<<(8 if utf8 else 16))|unpack(fmt,at,string_end)[0];at+=step
     return value,at
    if flags&256:
     _,at=length(at,True);count_bytes,at=length(at,True);terminator=1;encoding='utf8'
    else:
     chars,at=length(at,False);count_bytes=chars*2;terminator=2;encoding='utf-16le'
    if at+count_bytes+terminator>string_end or data[at+count_bytes:at+count_bytes+terminator]!=bytes(terminator):fail()
    try:strings.append(data[at:at+count_bytes].decode(encoding))
    except UnicodeError:fail()
  elif kind==0x180:
   if resources is not None or header!=8:fail()
   resources=list(struct.unpack_from('<'+'I'*((size-header)//4),data,pos+header))
  elif kind==0x102:
   if strings is None or header!=16:fail()
   ns,name,attr_start,attr_size,attr_count=unpack('<IIHHH',pos+header,end)
   if name>=len(strings) or attr_start<20 or attr_size<20 or pos+header+attr_start+attr_size*attr_count>end:fail()
   if strings[name]=='uses-sdk':
    sdk_elements+=1
    for index in range(attr_count):
     at=pos+header+attr_start+index*attr_size
     ans,aname,raw,value_size,reserved,dtype,value=unpack('<IIIHBBI',at,end)
     if aname>=len(strings):fail()
     if strings[aname]!='minSdkVersion':continue
     if ans>=len(strings) or strings[ans]!='http://schemas.android.com/apk/res/android':fail()
     if resources is None or aname>=len(resources) or resources[aname]!=0x0101020c:fail()
     if raw!=0xffffffff or value_size!=8 or reserved!=0 or dtype!=0x10:fail()
     matches.append((at+16,value))
  pos=end
 if sdk_elements!=1 or len(matches)!=1:fail()
 return matches[0]

def patch_manifest_min_sdk(data,expected=24,target=MIN_SDK):
 if not isinstance(target,int) or not 1<=target<=1000:raise RuntimeError('Invalid target Android API level.')
 offset,current=manifest_min_sdk(data)
 if current!=expected:raise RuntimeError(f'Official template minSdkVersion changed: expected {expected}, found {current}.')
 patched=bytearray(data);struct.pack_into('<I',patched,offset,target);patched=bytes(patched)
 if manifest_min_sdk(patched)!=(offset,target) or patched[:offset]!=data[:offset] or patched[offset+4:]!=data[offset+4:]:
  raise RuntimeError('Manifest patch changed data outside minSdkVersion.')
 return patched,{'element':'uses-sdk','attribute':'android:minSdkVersion','value_offset':offset,'before':current,'after':target,'before_sha256':hashlib.sha256(data).hexdigest(),'after_sha256':hashlib.sha256(patched).hexdigest()}

def prepare_debug_template(source,destination):
 """Modify a disposable template, preserving every other decompressed ZIP entry."""
 if source.resolve()==destination.resolve():raise RuntimeError('Original export template must never be overwritten.')
 before=hashlib.sha256(source.read_bytes()).hexdigest()
 with zipfile.ZipFile(source) as original:
  names=original.namelist()
  if len(set(names))!=len(names) or names.count('AndroidManifest.xml')!=1:raise RuntimeError('Duplicate or missing template manifest/ZIP entry.')
  manifest,patch=patch_manifest_min_sdk(original.read('AndroidManifest.xml'))
  with zipfile.ZipFile(destination,'w') as custom:
   custom.comment=original.comment
   # writestr updates ZipInfo offsets/CRC; never mutate the source reader's index.
   for entry in original.infolist():custom.writestr(copy.copy(entry),manifest if entry.filename=='AndroidManifest.xml' else original.read(entry))
  with zipfile.ZipFile(destination) as custom:
   if custom.testzip() is not None or custom.namelist()!=names:raise RuntimeError('Custom template ZIP validation failed.')
   for name in names:
    expected=manifest if name=='AndroidManifest.xml' else original.read(name)
    if custom.read(name)!=expected:raise RuntimeError('Unexpected template content change: '+name)
 if hashlib.sha256(source.read_bytes()).hexdigest()!=before:raise RuntimeError('Original template changed during preparation.')
 return {'official_template':source.name,'official_template_sha256':before,'custom_template_sha256':hashlib.sha256(destination.read_bytes()).hexdigest(),'manifest_patch':patch,'other_entry_contents_unchanged':True,'original_template_unchanged':True,'temporary_unsigned_template':True}

def quoted(value):return json.dumps(str(value),ensure_ascii=False)
def run(command,log,env,timeout=600):
 with log.open('w') as output:
  result=subprocess.run([str(p) for p in command],stdout=output,stderr=subprocess.STDOUT,env=env,timeout=timeout)
 if result.returncode:raise RuntimeError(f'Command failed ({result.returncode}); see {log}')
 text=log.read_text(errors='replace')
 if engine_errors(text):raise RuntimeError(f'Godot reported errors or leaked resources; see {log}')
 return text

def signing_identity(args,java,env,output):
 """Keep the archived identity immutable; new builds opt into a separate preview app."""
 if not args.new_debug_identity:
  if args.debug_keystore:raise RuntimeError('--debug-keystore requires --new-debug-identity.')
  keystore=ROOT/'tools/signing/debug.keystore'
  if not keystore.is_file():
   raise RuntimeError('Archived debug.keystore is missing. Restore it for com.almostgod.game, or use --new-debug-identity to build the separate com.almostgod.game.preview app.')
  expected=(ROOT/'tools/signing/certificate.sha256').read_text().strip()
 else:
  keystore=(args.debug_keystore or ROOT.parent/'GOD-local-signing/preview-debug.keystore').resolve()
  if keystore.is_relative_to(ROOT):raise RuntimeError('The new preview debug key must be stored outside the source repository.')
  keystore.parent.mkdir(parents=True,exist_ok=True)
  if not keystore.exists():
   run([java/'bin/keytool','-genkeypair','-keystore',keystore,'-storepass','android','-alias','androiddebugkey','-keypass','android','-dname','CN=Almost God Preview,O=Local Development,C=US','-keyalg','RSA','-keysize','2048','-validity','10000'],output.with_suffix('.keytool.log'),env)
   keystore.chmod(0o600)
  expected=None
 certificate=subprocess.run([str(java/'bin/keytool'),'-exportcert','-keystore',str(keystore),'-storepass','android','-alias','androiddebugkey'],capture_output=True,env=env,check=True)
 actual=hashlib.sha256(certificate.stdout).hexdigest()
 if expected is not None and actual!=expected:raise RuntimeError('Existing debug key does not match the archived certificate; no APK was exported.')
 return keystore,actual

def validate_android_manifest(report,new_debug_identity):
 """Check effective APK values; exporter settings alone are not evidence."""
 nodes={row['element']:row['attributes'] for row in report['manifest']}
 manifest=nodes.get('manifest',{});sdk=nodes.get('uses-sdk',{})
 expected_package='com.almostgod.game.preview' if new_debug_identity else 'com.almostgod.game'
 if manifest.get('package')!=expected_package:raise RuntimeError('APK package does not match the selected signing mode.')
 if int(sdk.get('minSdkVersion',0))!=MIN_SDK:raise RuntimeError('APK minSdkVersion must be 29 (Android 10), as required by the game specification.')
 preset=(ROOT/'export_presets.cfg').read_text()
 expected_code=int(re.search(r'^version/code=(\d+)$',preset,re.M).group(1))
 expected_name=json.loads(re.search(r'^version/name=(.*)$',preset,re.M).group(1))
 if manifest.get('versionCode')!=expected_code or manifest.get('versionName')!=expected_name:raise RuntimeError('APK version does not match the source export preset.')

def build(args):
 tools=args.tools_dir.resolve();output=args.output.resolve();output.parent.mkdir(parents=True,exist_ok=True)
 godot=tools/f'Godot_v{VERSION}-stable_linux.x86_64'
 sdk=tools/'android-sdk';templates=tools/f'export_templates/{VERSION}.stable'
 java=args.java_home.resolve() if args.java_home else Path(shutil.which('java') or '').resolve().parents[1]
 for path in [godot,templates/'android_debug.apk',templates/'android_release.apk',sdk/'build-tools/31.0.2/apksigner',sdk/'platform-tools/adb',java/'bin/keytool']:
  if not path.is_file():raise RuntimeError(f'Missing {path}; run tools/bootstrap_native.py or supply --java-home.')
 env=os.environ.copy();env['JAVA_HOME']=str(java)
 keystore,expected_certificate=signing_identity(args,java,env,output)
 source_manifest=runtime_manifest()
 source_digest=hashlib.sha256(json.dumps(source_manifest,sort_keys=True,separators=(',',':')).encode()).hexdigest()
 started=time.monotonic()
 with tempfile.TemporaryDirectory(prefix='almost-god-export-',dir=tools) as temp_name:
  temp=Path(temp_name);staged=temp/'game'
  custom_debug=temp/'android_debug_min29.apk'
  template_provenance=prepare_debug_template(templates/'android_debug.apk',custom_debug)
  def ignore(directory,names):
   result={n for n in names if n in ('.godot','__pycache__','.git','.agents')}
   relative=Path(directory).relative_to(ROOT)
   if relative==Path('.'):result.update(n for n in names if n in ('build','tests','tools','docs','old','artifacts'))
   if relative==Path('data'):result.add('authoring')
   if relative==Path('assets'):result.add('source')
   if relative==Path('assets/art'):result.add('source')
   if relative==Path('assets/audio/production'):result.add('source')
   return result
  shutil.copytree(ROOT,staged,ignore=ignore)
  preset=(staged/'export_presets.cfg').read_text()
  values={'custom_template/debug':custom_debug,'custom_template/release':templates/'android_release.apk','gradle_build/min_sdk':'','keystore/debug':keystore,'keystore/debug_user':'androiddebugkey','keystore/debug_password':'android'}
  if args.new_debug_identity:
   values.update({'package/unique_name':'com.almostgod.game.preview','package/name':'Почти бог — Preview'})
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
 if certificate is None or certificate.group(1)!=expected_certificate:raise RuntimeError('APK signing identity does not match the selected debug key.')
 inspection=run([sys.executable,ROOT/'tools/inspect_apk.py',output,'--source-root',ROOT],output.with_suffix('.inspection.json'),env)
 report=json.loads(inspection)
 validate_android_manifest(report,args.new_debug_identity)
 report.update({'elapsed_seconds':round(time.monotonic()-started,2),'signature_verified':True,'certificate_sha256':certificate.group(1),'signing':'new local preview debug key' if args.new_debug_identity else 'archived local debug key','new_debug_identity':args.new_debug_identity,'release_store_key':False,'godot_version':VERSION,'physical_device_tested':False,'build_method':'Godot built-in template export; AOSP signing subset, no Gradle','source_runtime_digest_sha256':source_digest,'custom_template_provenance':template_provenance})
 output.with_suffix('.build.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({'apk':str(output),'size_bytes':report['size_bytes'],'sha256':report['sha256'],'signature_verified':True,'level_count':report['level_count'],'physical_device_tested':False},ensure_ascii=False,indent=2),flush=True)
 return report
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--tools-dir',type=Path,default=ROOT.parent/'tools')
 parser.add_argument('--java-home',type=Path)
 parser.add_argument('--output',type=Path,default=ROOT/'build/AlmostGod-debug.apk')
 parser.add_argument('--new-debug-identity',action='store_true',help='Use a separate local key and com.almostgod.game.preview; does not replace an archived installation.')
 parser.add_argument('--debug-keystore',type=Path,help='Persistent preview key path outside the repository (requires --new-debug-identity).')
 args=parser.parse_args()
 try:build(args)
 except (RuntimeError,subprocess.TimeoutExpired,subprocess.CalledProcessError) as error:raise SystemExit(str(error))
