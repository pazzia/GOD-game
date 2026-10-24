from pathlib import Path
from PIL import Image
from atlas_export import export,ROOT
import json,os

def felix():
 src=ROOT/'source/bibles/felix_parts_v2.png';i=Image.open(src);i.load();w,h=i.size
 # Authored regions from inspecting this atlas, not arbitrary equal slices.
 def B(x1,y1,x2,y2):return [round(x1*w/1254),round(y1*h/1254),round(x2*w/1254),round(y2*h/1254)]
 regions={'head':B(0,0,500,420),'torso':B(500,0,890,420),'right_arm':B(890,0,1254,420),'left_arm':B(0,420,435,835),'left_leg':B(435,420,835,840),'right_leg':B(835,420,1254,840),'cape':B(0,835,700,1254),'accessory':B(700,840,940,1254),'prop':B(940,840,1254,1254)}
 export(src,{f'characters/rigs/felix/{k}.png':box for k,box in regions.items()})
 rows=[
 ('cape',[700,435],[.49,.03],770,-30,'torso','cape'),
 ('left_leg',[630,820],[.66,.06],530,-20,None,'leg'),
 ('right_leg',[770,820],[.32,.06],530,-19,None,'leg'),
 ('torso',[700,430],[.50,.04],470,0,None,'torso'),
 ('left_arm',[530,555],[.83,.12],430,-5,'torso','arm'),
 ('right_arm',[870,555],[.17,.14],430,5,'torso','arm'),
 ('head',[700,450],[.51,.96],400,10,'torso','head'),
 ('accessory',[1113,855],[.5,.92],200,15,'right_arm','prop'),
 ('prop',[268,904],[.5,.55],300,15,'left_arm','prop')]
 rig={'schema_version':1,'actor_id':'felix','canvas_size':[1400,1400],'feet_origin':[700,1320],'nominal_height':1320,'status':'assembly_review_pending','parts':[{'id':id,'file':id+'.png','position':pos,'pivot':pv,'target_height':height,'z_index':z,'parent':parent,'role':role} for id,pos,pv,height,z,parent,role in rows],'portraits':{s:f'res://assets/art/characters/portraits/felix/{s}.png' for s in ['idle','observe','suspect','accept','reveal_react','focused','embarrassed','celebrate']},'angles':{}}
 out=ROOT/'characters/rigs/felix/rig.json';tmp=out.with_suffix('.tmp');tmp.write_text(json.dumps(rig,ensure_ascii=False,indent=2)+'\n');os.replace(tmp,out)
 # Mechanical assembled preview, same absolute-canvas contract as runtime.
 c=Image.new('RGBA',(1400,1400),'#FFF5DE')
 for p in sorted(rig['parts'],key=lambda p:p['z_index']):
  a=Image.open(out.parent/p['file']);a.load();scale=p['target_height']/a.height;a=a.resize((round(a.width*scale),round(a.height*scale)),Image.Resampling.LANCZOS);x=round(p['position'][0]-p['pivot'][0]*a.width);y=round(p['position'][1]-p['pivot'][1]*a.height);c.alpha_composite(a,(x,y))
 dest=ROOT.parents[1]/'build/felix-rig-assembly.png';dest.parent.mkdir(exist_ok=True);c.save(dest);print('felix',w,h,'rig parts exported',dest)
if __name__=='__main__':felix()
