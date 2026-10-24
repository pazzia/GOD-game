"""Read binary Android manifest and verify ZIP/ELF page alignment, no Android SDK dependency."""
import zipfile,struct,json,sys,hashlib,argparse,re
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("apk",type=Path)
parser.add_argument("--source-root",type=Path)
args=parser.parse_args()
p=args.apk
def u16(b,p):return struct.unpack_from('<H',b,p)[0]
def u32(b,p):return struct.unpack_from('<I',b,p)[0]
def length8(b,p):
 n=b[p];return ((n&127)<<8|b[p+1],p+2) if n&128 else (n,p+1)
def length16(b,p):
 n=u16(b,p);return ((n&32767)<<16|u16(b,p+2),p+4) if n&32768 else (n,p+2)
def manifest(data):
 strings=[];nodes=[];pos=8
 while pos<len(data):
  kind,header,size=struct.unpack_from('<HHI',data,pos)
  if kind==1:
   count,styles,flags,start,style_start=struct.unpack_from('<IIIII',data,pos+8)
   for i in range(count):
    at=pos+start+u32(data,pos+header+i*4)
    if flags&256:
     _,at=length8(data,at);n,at=length8(data,at);strings.append(data[at:at+n].decode('utf8'))
    else:
     n,at=length16(data,at);strings.append(data[at:at+n*2].decode('utf-16le'))
  if kind==258:
   ns,name,attr_start,attr_size,attr_count=struct.unpack_from('<IIHHH',data,pos+16)
   attrs={}
   for i in range(attr_count):
    at=pos+16+attr_start+i*attr_size
    ans,aname,raw,typed_size,res0,dtype,val=struct.unpack_from('<IIIHBBI',data,at)
    attrs[strings[aname]]=strings[val] if dtype==3 else bool(val) if dtype==18 else val
   nodes.append({'element':strings[name],'attributes':attrs})
  if size<=0:break
  pos+=size
 return nodes
report={'filename':p.name,'size_bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
with zipfile.ZipFile(p) as z:
 report['manifest']=manifest(z.read('AndroidManifest.xml'))
 report['level_count']=len([n for n in z.namelist()if n.startswith('assets/data/levels/L')and n.endswith('.json')])
 report['runtime_rig_metadata']=[n for n in z.namelist() if n.startswith('assets/assets/art/characters/rigs/') and n.endswith('/rig.json')]
 report['portrait_resource_count']=len([n for n in z.namelist() if n.startswith('assets/assets/art/characters/portraits/') and n.endswith(('.png','.png.remap','.png.import'))])
 if args.source_root:
  root=args.source_root.resolve();missing=[];mismatched=[]
  metadata=[p for p in (root/'data').rglob('*.json') if 'authoring' not in p.relative_to(root).parts]+list((root/'assets/art/characters/rigs').glob('*/rig.json'))+list((root/'assets/art/environments').glob('*/layers.json'))
  portraits=list((root/'assets/art/characters/portraits').glob('*/*.png'))
  textures=[p for p in (root/'assets/art').rglob('*.png') if 'source' not in p.relative_to(root).parts]
  audio=[p for p in (root/'assets/audio').rglob('*') if p.suffix in ('.ogg','.wav') and 'source' not in p.relative_to(root).parts]
  for source in metadata:
   packed='assets/'+source.relative_to(root).as_posix()
   if packed not in z.namelist():missing.append(packed)
   elif z.read(packed)!=source.read_bytes():mismatched.append(packed)
  for source in textures+audio:
   packed='assets/'+source.relative_to(root).as_posix()
   if packed in z.namelist():
    if z.read(packed)!=source.read_bytes():mismatched.append(packed)
    continue
   imported=next((n for n in [packed+'.import',packed+'.remap'] if n in z.namelist()),None)
   if imported is None:missing.append(packed);continue
   destinations=re.findall(r'path="res://([^"]+)"',z.read(imported).decode('utf8',errors='replace'))
   if not destinations or any('assets/'+target not in z.namelist() for target in destinations):missing.append(packed+' (missing imported resource)')
  report['source_verification']={'metadata_expected':len(metadata),'portraits_expected':len(portraits),'textures_expected':len(textures),'audio_resources_expected':len(audio),'environment_layers_expected':len(list((root/'assets/art/environments').glob('*/*.png'))),'missing':missing,'mismatched':mismatched}
 report['extract_native_libraries']=next((e['attributes'].get('extractNativeLibs',True) for e in report['manifest'] if e['element']=='application'),True)
 report['native_libraries']=[]
 raw=p.read_bytes()
 for n in z.namelist():
  if not n.startswith('lib/')or not n.endswith('.so'):continue
  e=z.getinfo(n);offset=e.header_offset+30+u16(raw,e.header_offset+26)+u16(raw,e.header_offset+28)
  lib=z.read(n);aligns=[]
  if lib[:4]==b'\x7fELF' and lib[4]==2:
   phoff=struct.unpack_from('<Q',lib,32)[0];entsize=u16(lib,54);count=u16(lib,56)
   for i in range(count):
    at=phoff+i*entsize
    if u32(lib,at)==1:aligns.append(struct.unpack_from('<Q',lib,at+48)[0])
  report['native_libraries'].append({'path':n,'zip_compression':e.compress_type,'data_offset':offset,'zip_16k_aligned':offset%16384==0,'elf_load_alignments':aligns,'elf_16k_compatible':bool(aligns) and all(a>=16384 for a in aligns),'installation_16k_compatible':bool(aligns) and all(a>=16384 for a in aligns) and ((e.compress_type!=0 and report['extract_native_libraries']) or (e.compress_type==0 and offset%16384==0))})
print(json.dumps(report,ensure_ascii=False,indent=2))
errors=[]
if report['level_count']!=30:errors.append('Expected all 30 authored levels.')
if any(not e['installation_16k_compatible'] for e in report['native_libraries']):errors.append('Native library extraction/alignment is invalid.')
if not report['native_libraries']:errors.append('No native libraries in APK.')
verification=report.get('source_verification',{})
if verification.get('missing') or verification.get('mismatched'):errors.append('APK runtime assets do not match source.')
if errors:raise SystemExit(' '.join(errors))
