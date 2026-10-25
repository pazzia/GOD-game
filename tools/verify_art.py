"""Inspect real raster/vector exports and metadata, without claiming visual quality."""
from pathlib import Path
import hashlib,json,sys,xml.etree.ElementTree as ET
from PIL import Image
from verify_reboot_art import validate as validate_reboot
R=Path(__file__).resolve().parents[1];A=R/'assets/art'
ACTORS=['felix','plum','marfa','semyon','nika','lada','roza','hugo','caramelka']
STATES=['idle','observe','suspect','accept','reveal_react','focused','embarrassed','celebrate','extra']
def main():
 errors=[];images=[];svg_count=0
 for p in sorted(A.rglob('*.png')):
  if 'source' in p.relative_to(A).parts:continue
  try:
   with Image.open(p)as im:im.verify()
   with Image.open(p)as im:
    im.load();w,h=im.size;alpha=im.convert('RGBA').getchannel('A')
    if not w or not h or not alpha.getbbox():errors.append(str(p.relative_to(R))+': empty image')
    surface_texture=p.parent.name=='props' and p.name in {'water_surface.png','ice_surface.png'}
    if ('characters' in p.relative_to(A).parts or 'props' in p.relative_to(A).parts) and not surface_texture:
     if alpha.getextrema()[0]==255:errors.append(str(p.relative_to(R))+': cutout has no transparent pixels')
    images.append({'path':str(p.relative_to(R)),'width':w,'height':h,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
  except Exception as e:errors.append(str(p.relative_to(R))+': '+str(e))
 for p in sorted(A.rglob('*.svg')):
  try:
   root=ET.parse(p).getroot()
   if not root.tag.endswith('svg'):errors.append(str(p.relative_to(R))+': SVG root required')
   svg_count+=1
  except Exception as e:errors.append(str(p.relative_to(R))+': '+str(e))
 metadata=json.loads((A/'atlas_metadata.json').read_text())
 for path,item in metadata.items():
  p=A/path
  if '..'in Path(path).parts or not p.is_file():errors.append('Missing/invalid atlas output '+path);continue
  if p.suffix=='.png':
   with Image.open(p)as im:
    if list(im.size)!=item.get('size'):errors.append('Atlas output dimensions changed without metadata '+path)
 for actor in ACTORS:
  hashes=[]
  if not (A/f'characters/{actor}.png').is_file():errors.append('Missing baseline '+actor)
  for state in STATES:
   p=A/f'characters/portraits/{actor}/{state}.png'
   if not p.exists():errors.append('Missing emotion '+actor+'/'+state)
   else:hashes.append(hashlib.sha256(p.read_bytes()).hexdigest())
  if len(set(hashes))!=len(STATES):errors.append('Repeated/missing portrait exports '+actor)
 layers=[]
 for env in ['ENV01','ENV02','ENV03']:
  p=A/f'environments/{env}/layers.json'
  if p.exists():
   value=json.loads(p.read_text());layers.append({'scene':env,'metadata':str(p.relative_to(R)),'value':value})
   entries=value.get('layers',[])
   if [x.get('id')for x in entries]!=['backdrop','floor','midground','foreground','atmosphere']:errors.append(env+': complete ordered five-layer stack required')
   for entry in entries:
    filename=entry.get('file','');target=p.parent/filename
    if not filename or Path(filename).name!=filename or not target.is_file():errors.append(env+': missing/unsafe layer '+filename);continue
    with Image.open(target)as im:
     if list(im.size)!=value.get('canvas_size'):errors.append(env+': layer canvas differs from common fit '+filename)
   if not value.get('draw_stage_content_after_layers') or value.get('water',{}).get('render')!='exact_authoritative_polygon_above_floor':errors.append(env+': layers must preserve authoritative stage water/geometry')
 reboot=validate_reboot(R)
 errors.extend('reboot: '+message for message in reboot['errors'])
 report={'kind':'art_file_integrity','status':'passed'if not errors else'failed','raster_exports':len(images),'svg_exports':svg_count,'reboot':reboot,
         'portrait_exports':9*len(STATES),'layer_stacks_with_metadata':len(layers),'errors':errors,'images':images,
         'limits':'Decoding, alpha, dimensions, distinct files and references only. Does not prove composition, expression quality, animation or phone readability.'}
 dest=R/'tests/reports/art-files.json';dest.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({k:v for k,v in report.items()if k!='images'},ensure_ascii=False,indent=2))
 return int(bool(errors))
if __name__=='__main__':raise SystemExit(main())
