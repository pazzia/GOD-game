"""Lossless actor-private atlas extraction and mechanical assembly preview."""
from pathlib import Path
import os,json
import numpy as np
from PIL import Image
from scipy import ndimage

BASE=Path(__file__).resolve().parent
ART=BASE.parents[2]
GAME=ART.parents[1]
def atomic_png(image,path):
    path.parent.mkdir(parents=True,exist_ok=True)
    temporary=path.with_suffix('.tmp')
    image.save(temporary,format='PNG')
    with temporary.open('rb') as stream:os.fsync(stream.fileno())
    with Image.open(temporary) as verified:verified.load()
    os.replace(temporary,path)

def main():
    config=json.loads((BASE/'config.json').read_text())
    actor=config['actor_id'];dest=ART/'characters/rigs'/actor
    image=Image.open(BASE/config.get('source','parts.png')).convert('RGBA');image.load()
    metadata={}
    for part,box in config['regions'].items():
        scaled=[round(box[0]*image.width/1254),round(box[1]*image.height/1254),round(box[2]*image.width/1254),round(box[3]*image.height/1254)]
        cut=image.crop(scaled)
        pixels=np.array(cut);labels,count=ndimage.label(pixels[:,:,3]>16)
        sizes=np.bincount(labels.ravel());sizes[0]=0
        if sizes.max()>0:
            keep=sizes>=max(24,sizes.max()*.08);keep[0]=False
            owned=ndimage.binary_dilation(keep[labels],iterations=3)
            pixels[:,:,3]=np.where(owned,pixels[:,:,3],0)
            cut=Image.fromarray(pixels)
        trim=cut.getchannel('A').getbbox()
        if trim is None:raise RuntimeError('Empty part '+part)
        cut=cut.crop(trim);atomic_png(cut,dest/(part+'.png'))
        metadata[part]={'source':config.get('source','parts.png'),'authored_crop':scaled,'alpha_trim':trim,'size':cut.size}
    rig={key:config[key] for key in ['actor_id','canvas_size','feet_origin','nominal_height','parts']}
    rig.update({'schema_version':1,'status':config.get('assembly_status','assembly_review_pending'),'runtime_animation_verified':False,'assembly_notes':config.get('assembly_notes',''),'directional_animation_complete':False,'angles':{},
                'portraits':{state:f'res://assets/art/characters/portraits/{actor}/{state}.png' for state in ['idle','observe','suspect','accept','reveal_react','focused','embarrassed','celebrate']}})
    temp=dest/'rig.tmp';temp.write_text(json.dumps(rig,ensure_ascii=False,indent=2)+'\n');os.replace(temp,dest/'rig.json')
    (BASE/'parts_metadata.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n')
    assembly=Image.new('RGBA',tuple(rig['canvas_size']),'#FFF5DE')
    for part in sorted(rig['parts'],key=lambda part:part['z_index']):
        piece=Image.open(dest/part['file']).convert('RGBA');piece.load()
        scale=part['target_height']/piece.height
        piece=piece.resize((round(piece.width*scale),round(piece.height*scale)),Image.Resampling.LANCZOS)
        x=round(part['position'][0]-part['pivot'][0]*piece.width)
        y=round(part['position'][1]-part['pivot'][1]*piece.height)
        assembly.alpha_composite(piece,(x,y))
    preview=GAME/'build'/(actor+'-rig-assembly.png');atomic_png(assembly,preview)
    print(actor,len(rig['parts']),'parts exported',preview)
if __name__=='__main__':main()
