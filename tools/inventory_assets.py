"""Map the original571 planned asset rows to real implementation files.

Presence is deliberately distinct from runtime integration and human acceptance.
"""
from pathlib import Path
import csv, hashlib, json, re
R=Path(__file__).resolve().parents[1]
ACTORS=['felix','plum','marfa','semyon','nika','lada','roza','hugo','caramelka']
CROWD=['crowd_gardener','crowd_postwoman','crowd_fisherman','crowd_librarian','crowd_merchant','crowd_musician']
def main():
 rows=list(csv.DictReader((R/'docs/spec/ASSET_MANIFEST.csv').open()))
 audio={x['id']:x for x in json.loads((R/'data/audio_catalog.json').read_text())['files']}
 stage=(R/'presentation/stage_view.gd').read_text()
 prop_map=json.loads(re.search(r'const ASSETS=(\{.*\})',stage).group(1))
 out=[]
 for row in rows:
  aid=row['asset_id'];cat=row['category'];status='planned_not_produced';files=[];note=''
  if aid in audio:
   status='produced_measured_mix_review_pending';files=[audio[aid]['path'].removeprefix('res://')];note='Catalog hash/length/peak/seam measured. Phone playback, interruptions and subjective listening separate.'
  elif aid.startswith('CH'):
   actor=ACTORS[int(aid[2:4])-1];base='assets/art/characters/'
   if cat=='portrait':
    path=base+'portraits/'+actor+'/idle.png'
    if (R/path).exists():status='runtime_portraits_present';files=[base+'portraits/'+actor+'/'];note='Nine actual face cutouts. Source dimensions tracked by designer; no claim of a separate512px painted master.'
   elif cat=='model_sheet':
    path='assets/art/source/bibles/'+actor+'_expressions.png'
    if (R/path).exists():status='partial_emotions_model_bible';files=[path];note='Expression sheet present; full direction/wardrobe/height lineup is a separate requirement.'
   elif cat=='character_rig':
    path=base+'rigs/'+actor+'/rig.json'
    if (R/path).exists():
     data=json.loads((R/path).read_text());status='part_rig_present_review_pending';files=[path,'presentation/character_puppet.gd'];note='Designer status: '+data.get('status','unreviewed')+'. Directional parts and runtime acceptance tracked separately.'
     review=data.get('native_keypose_review',{});evidence=R/review.get('evidence','')
     if review.get('accepted_for_integration') and evidence.is_file() and hashlib.sha256(evidence.read_bytes()).hexdigest()==review.get('sha256'):
      status='part_rig_keyposes_reviewed_direction_pending';files.append(review['evidence']);note=review.get('scope','Native key poses reviewed.')+' Continuous acting, direction art and event integration remain separately tracked.'
    else:status='baseline_only_rig_pending';files=[base+actor+'.png'];note='Whole-character baseline is not a separated rig.'
   elif cat=='animation':
    state=aid.split('_ANIM_',1)[1].lower()
    implemented=state in ['idle','move','turn','observe','suspect','accept','reveal_react','celebrate','show_begin','stamp','bow','hover','fly','point','shiver','cheer']
    if implemented:
     status='controller_clip_assets_partial';files=['presentation/character_puppet.gd'];note='Real AnimationPlayer clip; requires accepted actor parts, direction art and per-event staging. Shared clip is not final actor-specific acting.'
  elif aid.startswith('CROWD'):
   stem=CROWD[int(aid[5:7])-1]
   path='assets/art/characters/'+stem+'.png'
   if (R/path).exists():status='baseline_crowd_only';files=[path];note='Distinct transparent cutout. Shared segmented crowd rig/acting is not yet produced.'
  elif cat=='environment_layer':
   env,suffix=aid.split('_',1);stem={'FAR':'backdrop','MID':'midground','SURFACE':'floor','FOREGROUND':'foreground','LIGHT':'atmosphere'}[suffix]
   path=f'assets/art/environments/{env}/{stem}.png'
   if (R/path).exists():status='painted_layer_present_review_pending';files=[path];note='Independently generated layer; inspect assembled placement, masks and final runtime geometry.'
   else:note='Existing whole background plate does not count as this independent layer.'
  elif cat=='prop':
   stem=prop_map.get(aid)
   if not stem:
    candidate=row['description'].split(':',1)[0]
    if (R/('assets/art/props/'+candidate+'.png')).exists():stem=candidate
   if stem:
    path='assets/art/props/'+stem+'.png'
    if (R/path).exists():
     status='runtime_prop_present' if stem in prop_map.values() else 'prop_art_present_not_runtime_mapped'
     files=[path];note='Material/scale variants may share original artwork; actual placement/masks remain level data.'
  elif cat=='ui_icon':
   path='assets/art/ui/'+aid.removeprefix('UI_').lower()+'.svg'
   if (R/path).exists():status='vector_source_present';files=[path];note='Resolution-independent SVG is scaled natively, without redundant64/128/256 PNG files.'
  elif cat=='scene_layout':
   lid=aid.split('_')[1];status='authored_logic_layout';files=['data/levels/'+lid+'.json'];note='Authored geometry and props, canonical trace passed. Dedicated painted overlay and complete visual acceptance separate.'
  elif cat=='scene_overlay':note='Dynamic props are separate, but no unique painted alpha overlay is claimed from them.'
  elif cat=='ui_theme':status='implemented_native_theme';files=['presentation/game.gd','presentation/resources/'];note='Theme generated by native controls;100/140 text-flow visual acceptance still required.'
  elif cat=='font':status='font_and_license_present';files=['assets/fonts/DejaVuSans.ttf','assets/fonts/DejaVuSans-Bold.ttf','assets/fonts/LICENSE.txt']
  elif cat=='key_art':status='partial_composed_title';files=['presentation/game.gd','assets/art/ui/app_icon_1024.png'];note='Original character/background title composition and app icon; not a separately painted marketing master.'
  elif cat=='vfx':status='partial_runtime_effects';files=['presentation/game.gd','presentation/stage_view.gd'];note='Flash, ripple, state variants and vote indicators exist. Full authored effect catalog/timing/masks still needs dedicated acceptance.'
  out.append({'asset_id':aid,'category':cat,'stage':row['stage'],'description':row['description'],
              'implementation_status':status,'actual_files':';'.join(files),'remaining_or_limits':note,
              'planned_runtime_path':row['runtime_path'],'planned_source_path':row['source_path']})
 with (R/'docs/ASSET_STATUS.csv').open('w',newline='')as f:
  w=csv.DictWriter(f,fieldnames=list(out[0]));w.writeheader();w.writerows(out)
 counts={s:sum(x['implementation_status']==s for x in out)for s in sorted({x['implementation_status']for x in out})}
 report={'planned_rows':len(rows),'statuses':counts,'limits':'File presence and controller support never imply final visual, listening, directional-animation or device acceptance.'}
 (R/'tests/reports/asset-inventory.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(report,indent=2))
if __name__=='__main__':main()
