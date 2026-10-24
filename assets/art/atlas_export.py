"""Lossless PNG atlas extraction; writes atomic .tmp files ignored by Godot."""
from pathlib import Path
from PIL import Image
import os,json,shutil
import numpy as np
from scipy import ndimage
ROOT=Path(__file__).resolve().parent
SOURCE=ROOT/'source';SOURCE.mkdir(exist_ok=True);(SOURCE/'.gdignore').touch()
def export(src,regions):
    im=Image.open(src);im.load()
    saved=SOURCE/Path(src).name
    if Path(src).resolve()!=saved.resolve():shutil.copy2(src,saved)
    mp=ROOT/'atlas_metadata.json';meta=json.loads(mp.read_text()) if mp.exists() else {}
    for rel,box in regions.items():
        a=im.crop(box) if box else im.copy()
        # A production atlas has multiple isolated objects. Remove neighboring
        # disconnected object fragments when a bounding rectangle crosses a cell.
        if rel.startswith(('props/','characters/')) and a.mode=='RGBA':
            arr=np.array(a);labels,count=ndimage.label(arr[:,:,3]>16);sizes=np.bincount(labels.ravel());sizes[0]=0
            if sizes.max()>0:
                keep=sizes>=max(24,sizes.max()*.08);keep[0]=False;owned=ndimage.binary_dilation(keep[labels],iterations=3)
                arr[:,:,3]=np.where(owned,arr[:,:,3],0);a=Image.fromarray(arr)
        trim=a.getchannel('A').getbbox() if a.mode=='RGBA' else (0,0,*a.size)
        a=a.crop(trim);out=ROOT/rel;out.parent.mkdir(parents=True,exist_ok=True);tmp=out.with_suffix('.tmp');a.save(tmp,format='PNG');os.replace(tmp,out)
        meta[rel]={'original':saved.name,'crop':box,'alpha_trim':trim,'size':a.size,'pivot':[.5,.5 if 'plum' in rel else 1.0]}
    t=mp.with_suffix('.tmp');t.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n');os.replace(t,mp)
    print('exported',len(regions),'assets from',saved.name)
if __name__=='__main__':
    import sys
    q=json.load(sys.stdin);export(q['source'],q['regions'])
