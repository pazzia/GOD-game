"""Map the original571 planned asset rows to real implementation files.

Presence is deliberately distinct from runtime integration and human acceptance.
"""
from pathlib import Path
import csv, hashlib, json, re
from collections import Counter
from PIL import Image
R=Path(__file__).resolve().parents[1]
ACTORS=['felix','plum','marfa','semyon','nika','lada','roza','hugo','caramelka']
CROWD=['crowd_gardener','crowd_postwoman','crowd_fisherman','crowd_librarian','crowd_merchant','crowd_musician']
def acting_traceability(text):
 """Read the maintained source-dispatch table; this is not playthrough evidence."""
 result={}
 for line in text.splitlines():
  cells=[cell.strip() for cell in line.strip().strip('|').split('|')]
  if line.startswith('|') and len(cells)==5 and cells[0] in ACTORS:
   result[(cells[0],cells[1])]={'dispatch':cells[3],'intent':cells[4],
                              'campaign_reachable':'NOT REACHABLE' not in cells[3]}
 return result

def inspect_overlays():
 """Verify actual unique RGBA canvases rather than counting manifest promises."""
 manifest_path=R/'assets/art/scenes/manifest.json'
 if not manifest_path.is_file():return {},[]
 manifest=json.loads(manifest_path.read_text());result={};errors=[];hashes={}
 for entry in manifest.get('entries',[]):
  lid=entry.get('level_id','');path=f'assets/art/scenes/{lid}/overlay.png'
  issues=[]
  if not re.fullmatch(r'L\d{2}',lid) or entry.get('file')!='res://'+path:
   errors.append('Unsafe/mismatched overlay manifest path: '+str(lid));continue
  if lid in result:errors.append('Duplicate overlay manifest entry: '+lid);continue
  try:
   raw=(R/path).read_bytes()
   if hashlib.sha256(raw).hexdigest()!=entry.get('sha256'):issues.append('file SHA-256 mismatch')
   with Image.open(R/path) as im:
    im.load()
    if im.mode!='RGBA' or im.size!=(1536,1024):issues.append('1536x1024 RGBA canvas required')
    rgba=im.convert('RGBA');alpha=rgba.getchannel('A')
    if not alpha.getbbox() or alpha.getextrema()[0]!=0:issues.append('nonempty transparent decoration required')
    if alpha.crop((230,0,1306,1024)).getbbox():issues.append('center70percent must stay transparent')
    pixel_hash=hashlib.sha256(rgba.tobytes()).hexdigest()
    if pixel_hash!=entry.get('rgba_sha256'):issues.append('decoded RGBA SHA-256 mismatch')
    if pixel_hash in hashes:
     issues.append('duplicate decoded pixels with '+hashes[pixel_hash])
     result[hashes[pixel_hash]]['issues'].append('duplicate decoded pixels with '+lid)
    else:hashes[pixel_hash]=lid
  except (OSError,ValueError) as exc:issues.append(str(exc))
  result[lid]={'path':path,'source_atlas':entry.get('source_atlas',''),
               'decoration':entry.get('decoration',''),'issues':issues}
 for lid,item in result.items():errors.extend(lid+': '+issue for issue in item['issues'])
 return result,errors

def main():
 rows=list(csv.DictReader((R/'docs/spec/ASSET_MANIFEST.csv').open()))
 audio={x['id']:x for x in json.loads((R/'data/audio_catalog.json').read_text())['files']}
 stage=(R/'presentation/stage_view.gd').read_text()
 prop_map=json.loads(re.search(r'const ASSETS=(\{.*\})',stage).group(1))
 acting_path=R/'data/character_animations.json'
 acting=json.loads(acting_path.read_text()).get('actors',{}) if acting_path.is_file() else {}
 acting_doc=R/'docs/ANIMATION_ACTING.md'
 traces=acting_traceability(acting_doc.read_text()) if acting_doc.is_file() else {}
 overlays,integrity_errors=inspect_overlays()
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
    elif (R/(base+'portraits/'+actor+'/idle.png')).is_file():
     status='partial_portraits_model_sheet_pending';files=[base+'portraits/'+actor+'/'];note='Existing expression cutouts are useful reference; a full direction/wardrobe/height model sheet and its source master remain unproduced.'
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
    clip=acting.get(actor,{}).get(state)
    if isinstance(clip,dict) and clip.get('duration',0)>0 and len(clip.get('times',[]))>1 and clip.get('rotations'):
     trace=traces.get((actor,state))
     status='authored_body_clip_dispatch_unreviewed'
     if trace:status='authored_body_clip_campaign_cue_review_pending' if trace['campaign_reachable'] else 'authored_body_clip_manual_only_review_pending'
     files=['data/character_animations.json','presentation/character_acting.gd','presentation/character_puppet.gd','presentation/stage_view.gd','docs/ANIMATION_ACTING.md']
     note=f'Actor-specific body timeline: {actor}/{state}, {clip["duration"]}s. '
     note+=(trace['dispatch']+'. Intent: '+trace['intent']+'. ') if trace else 'Campaign dispatch has not been documented. '
     note+='Source-level dispatch is not an observed campaign playthrough. Direction art, literal facial/hand-prop detail, timing/composition and device review remain separate; no gameplay state is changed.'
    elif implemented:
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
  elif cat=='scene_overlay':
   lid=aid.split('_')[1];overlay=overlays.get(lid)
   if overlay:
    status='painted_overlay_integrity_failed' if overlay['issues'] else 'unique_painted_overlay_runtime_review_pending'
    files=[overlay['path'],'assets/art/scenes/manifest.json','presentation/stage_view.gd']
    if overlay['source_atlas'] and (R/overlay['source_atlas']).is_file():files.append(overlay['source_atlas'])
    note='Unique peripheral decoration: '+overlay['decoration']+'. '
    note+=('; '.join(overlay['issues'])+'. ') if overlay['issues'] else 'File and decoded RGBA hashes,1536x1024 canvas, nonempty alpha and clear central70percent verified. '
    note+='Drawn before authoritative water/props; no gameplay geometry or occlusion. Full scene staging, native visual review and phone readability remain pending.'
   else:note='Unique painted alpha overlay has not been verified from a current manifest and actual file.'
  elif cat=='ui_theme':status='implemented_native_theme';files=['presentation/game.gd','presentation/resources/'];note='Theme generated by native controls;100/140 text-flow visual acceptance still required.'
  elif cat=='font':status='font_and_license_present';files=['assets/fonts/DejaVuSans.ttf','assets/fonts/DejaVuSans-Bold.ttf','assets/fonts/LICENSE.txt']
  elif cat=='key_art':status='partial_composed_title';files=['presentation/game.gd','assets/art/ui/app_icon_1024.png'];note='Original character/background title composition and app icon; not a separately painted marketing master.'
  elif cat=='vfx':status='partial_runtime_effects';files=['presentation/game.gd','presentation/stage_view.gd'];note='Flash, ripple, state variants and vote indicators exist. Full authored effect catalog/timing/masks still needs dedicated acceptance.'
  out.append({'asset_id':aid,'category':cat,'stage':row['stage'],'description':row['description'],
              'implementation_status':status,'actual_files':';'.join(files),'remaining_or_limits':note,
              'planned_runtime_path':row['runtime_path'],'planned_source_path':row['source_path']})
 with (R/'docs/ASSET_STATUS.csv').open('w',newline='')as f:
  w=csv.DictWriter(f,fieldnames=list(out[0]),lineterminator='\n');w.writeheader();w.writerows(out)
 counts={s:sum(x['implementation_status']==s for x in out)for s in sorted({x['implementation_status']for x in out})}
 additional=[x for x in out if x['implementation_status'].startswith('authored_body_clip_')]
 manual=[x['asset_id']for x in additional if x['implementation_status']=='authored_body_clip_manual_only_review_pending']
 unresolved=[x['asset_id']for x in out if x['implementation_status']=='planned_not_produced']
 partial=Counter(x['category']for x in out if x['implementation_status'].startswith(('partial_','baseline_','controller_clip_')) or x['category']=='character_rig')
 report={'planned_rows':len(rows),'statuses':counts,
         'new_production_evidence':{'authored_body_clips':len(additional),
          'campaign_cue_conditions_documented':sum(x['implementation_status']=='authored_body_clip_campaign_cue_review_pending' for x in additional),
          'manual_only_clip_ids':manual,'dispatch_evidence':'docs/ANIMATION_ACTING.md source-level traceability, not observed campaign playthrough',
          'unique_rgba_overlays_verified':sum(not x['issues'] for x in overlays.values()),
          'poster_status':next((x['implementation_status'] for x in out if x['asset_id']=='PROP_POSTER'),'not_in_plan')},
         'remaining':{'planned_not_produced_ids':unresolved,'partial_or_art_dependent_rows_by_category':dict(sorted(partial.items())),
          'manual_only_campaign_integration_ids':manual,
          'acceptance_pending':['Full direction/wardrobe/height model sheets; portrait cutouts are not those sheets.',
           'Directional rig artwork, crowd rigs/acting, and literal facial/accessory/hand-prop details.',
           'Native composition/timing and physical-device acceptance, subjective audio review, full VFX/key-art scope.']},
         'integrity_errors':integrity_errors,
         'limits':'File presence, authored timelines, source-level cue conditions and decoded overlay integrity do not imply final visual, listening, directional-animation or device acceptance. Zero planned_not_produced rows would not mean complete art production.'}
 (R/'tests/reports/asset-inventory.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(report,indent=2))
 return int(bool(integrity_errors))
if __name__=='__main__':raise SystemExit(main())
