"""Re-export the 40 painted props from preserved imagegen atlases.
Requires ImageMagick. Only crops, resizes and transparent padding are performed.
Run from any directory. Output RGBA hashes are checked; PNG creation timestamps may differ.
"""
from pathlib import Path
import hashlib,json,subprocess,tempfile
from PIL import Image
ROOT=Path(__file__).resolve().parents[5]
SOURCE=Path(__file__).resolve().parent
manifest=json.loads((SOURCE/'props-generation-manifest.json').read_text())
with tempfile.TemporaryDirectory(prefix='god-props-export-') as scratch:
 for item in manifest['assets']:
  src=ROOT/item['source'];dst=ROOT/item['path'];dst.parent.mkdir(parents=True,exist_ok=True)
  assert hashlib.sha256(src.read_bytes()).hexdigest()==item['source_sha256'],src
  l,t,r,b=item['crop'];w,h=item['size'];cut=Path(scratch)/dst.name
  if dst.stem in {'water_surface','ice_surface'}:
   subprocess.run(['magick',str(src),'-crop',f'{r-l}x{b-t}+{l}+{t}','+repage','-resize',f'{w}x{h}!','PNG32:'+str(dst)],check=True)
  else:
   subprocess.run(['magick',str(src),'-crop',f'{r-l}x{b-t}+{l}+{t}','+repage',str(cut)],check=True)
   subprocess.run(['magick',str(cut),'-filter','Lanczos','-resize',f'{w-4}x{h-4}','-background','none','-gravity','South','-extent',f'{w}x{h}','PNG32:'+str(dst)],check=True)
  with Image.open(dst) as im:
   assert hashlib.sha256(im.convert('RGBA').tobytes()).hexdigest()==item['rgba_sha256'],dst
print('40/40 prop outputs reproduced with matching RGBA SHA-256')
