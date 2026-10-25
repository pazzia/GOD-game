"""Independent cross-file checks; gameplay is verified separately in Godot."""
from pathlib import Path
import json,sys,re
R=Path(__file__).resolve().parents[1];errors=[]
def check(ok,msg):
 if not ok:errors.append(msg)
def read(p):return json.loads((R/p).read_text())
def index(rows,label):
 ids=[r['id']for r in rows];check(len(ids)==len(set(ids)),label+' duplicate IDs');return{r['id']:r for r in rows}
def main():
 ru,en=read('data/localization/ru.json'),read('data/localization/en.json');check(ru.keys()==en.keys(),'RU/EN keys');check(all(isinstance(v,str)and v.strip()for v in list(ru.values())+list(en.values())),'Empty translation')
 for key in ru.keys()&en.keys():
  check(set(re.findall(r'\{([a-zA-Z0-9_]+)\}',ru[key]))==set(re.findall(r'\{([a-zA-Z0-9_]+)\}',en[key])),'Translation placeholders '+key)
  check(not re.search('[А-Яа-яЁё]',en[key]),'Untranslated English text '+key)
 for path in (R/'presentation').glob('*.gd'):
  for key in re.findall(r'\b(?:tx|_t)\("([a-zA-Z0-9_.]+)"',path.read_text()):
   if not key.endswith('.'):check(key in ru,'Missing client translation '+key)
 campaign=read('data/campaign.json');check([r['id']for r in campaign['levels']]==[f'L{i:02d}'for i in range(1,31)],'30 campaign IDs');replays=0;alternatives=0;assets=set()
 for row in campaign['levels']:
  lid=row['id'];d=read('data/levels/'+lid+'.json');es=index(d['entities'],lid+'entities');ss=index(d['slots'],lid+'slots');zs=index(d['zones'],lid+'zones');ws=index(d['witnesses'],lid+'witnesses');ns=index(d['navigation']['nodes'],lid+'nodes');rs=index(d['navigation']['routes'],lid+'routes');os=index(d['occluders'],lid+'occluders')
  check(d['level_id']==lid,lid+' identity');check(len(set(d['initial_active_laws']))==len(d['initial_active_laws'])<=d['max_active_laws']<=2,lid+' laws');check(d['title_key']in ru and set(d['hints'])<=ru.keys(),lid+' text');check(len(set(d['hints']))==3,lid+' hints')
  if 'demonstration_timeout_ticks'in d:check(type(d['demonstration_timeout_ticks'])is int and 1<=d['demonstration_timeout_ticks']<=200,lid+' demonstration horizon')
  for o in os.values():
   if 'folded_segment'in o:
    points=o['folded_segment'];check(isinstance(points,list)and len(points)==2 and all(isinstance(v,list)and len(v)==2 and all(type(n)is int and 0<=n<=m for n,m in zip(v,[24,28]))for v in points)and points[0]!=points[1],lid+' folded visibility segment')
    check(es.get(o.get('owner_entity'),{}).get('properties',{}).get('foldable')is True,lid+' folded visibility owner')
  for s in ss.values():check(s['zone_id']in zs,lid+' slot zone');check(len(s['position'])==2 and all(type(v)is int and 0<=v<=m for v,m in zip(s['position'],[24,28])),lid+' slot coordinates');check('slot.'+s['id']+'.name'in ru,lid+' slot translation '+s['id'])
  for e in es.values():
   assets.add(e['asset_id']);check(e['initial_slot']in ss,lid+' initial slot');check(e['type_id']in ss[e['initial_slot']]['allowed_entity_types'],lid+' initial slot type');check(type(e['mass_units'])is int and e['mass_units']>=0,lid+' mass');p=e['properties']
   for k in('foldable','initial_folded','removable','switchable'):
    if k in p:check(type(p[k])is bool,lid+' boolean property '+k)
   if p.get('switchable'):check(p.get('emitter_class')=='FIRE',lid+' switchable controlled emitter')
   if p.get('initial_folded'):check(p.get('foldable')is True,lid+' initial folded capability')
   if 'remove_requires_law'in p:check(p['remove_requires_law']in('M01','M02','M03'),lid+' removal law')
   for k in('supports_entity','carrier_entity_id','tow_rope_entity_id','hoist_entity_id','mooring_owner_entity_id','attachment_target_entity_id'):
    if k in p:check(p[k]in es,lid+' property reference '+k)
   for k in('span_anchor_entity_ids','insulation_by_entity_ids','protects_entity_ids','payload_entity_ids'):
    if k in p:check(len(set(p[k]))==len(p[k])and set(p[k])<=es.keys(),lid+' property IDs '+k)
   for k in('load_slot_ids','service_slot_ids','protection_slot_ids'):
    if k in p:check(set(p[k])<=ss.keys(),lid+' property slots '+k)
   if 'span_anchor_entity_ids'in p:check(len(p.get('span_anchor_offsets',[]))==len(p['span_anchor_entity_ids'])>=2,lid+' span geometry')
   if p.get('payload_mass_included'):check(e['mass_units']>=sum(es[k]['mass_units']for k in p['payload_entity_ids']),lid+' included load mass')
   if e['material']=='DECOY':check(not p.get('emitter_class'),lid+' decoy cannot emit heat')
   for effect in p.get('scheduled_effects',[]):
    if 'target_slot_id'in effect:check(effect['target_slot_id']in ss,lid+' scheduled slot')
    if 'target_occluder_id'in effect:check(effect['target_occluder_id']in os,lid+' scheduled occluder')
  for locale,catalog in [('ru',ru),('en',en)]:
   names_by_type={}
   for e in es.values():
    label=catalog.get('entity.'+e['id']+'.name',catalog.get('prop.'+e['type_id']+'.name',''))
    group=names_by_type.setdefault(e['type_id'],[]);check(bool(label) and label not in group,lid+' distinguishable '+locale+' entity name '+e['id']);group.append(label)
  for z in zs.values():
   check(set(z.get('reachable_zone_ids',[]))<=zs.keys(),lid+' reach neighbors')
   if 'thermal_owner_entity_id'in z:check(z['thermal_owner_entity_id']in es,lid+' thermal owner')
  for w in ws.values():
   check('character.'+w['character_id']+'.name'in ru,lid+' witness character translation '+w['character_id'])
   intervals=sorted((v['from_tick'],v['from_tick']+v['duration_ticks'])for v in w['views']);check(all(a[1]<=b[0]for a,b in zip(intervals,intervals[1:])),lid+' view overlap');check(all(0<=a<b<=200 for a,b in intervals),lid+' show horizon');check(all(0<v['clear_ticks']<=v['duration_ticks']for v in w['views']),lid+' clear threshold')
  check(len({w['character_id']for w in ws.values()})==len(ws),lid+' same character cannot vote twice as two witnesses')
  for route in rs.values():
   check(len(route['nodes'])>=2 and set(route['nodes'])<=ns.keys(),lid+' route nodes')
   if 'required_support_entity'in route:check(route['required_support_entity']in es and route['required_support_slot']in ss,lid+' support references')
  files=list((R/'tests/replays').glob(lid+'_*.json'))if lid not in('L01','L02','L03')else[R/'tests'/(lid+'_solution.json')]
  check(any(f.name==lid+'_solution.json'for f in files),lid+' canonical missing')
  for f in files:
   rep=json.loads(f.read_text());replays+=1;alternatives+=int('alternative'in f.name)
   for step in rep['steps']:
    if step['op']!='command':continue
    p=step.get('payload',{})
    for k in('entity_id','actor_id','target_entity_id','hoist_entity_id'):
     if k in p:check(p[k]in es,lid+' replay entity '+p[k])
    if 'slot_id'in p:check(p['slot_id']in ss,lid+' replay slot')
    if 'route_id'in p:check(p['route_id']in rs,lid+' replay route')
 check(alternatives>=10,'10 alternative solutions required')
 report=dict(kind='content_cross_file_validation',status='failed'if errors else'passed',levels=30,replays=replays,alternatives=alternatives,localization_keys_per_language=len(ru),referenced_entity_asset_ids=len(assets),errors=errors,scope='References, text and authoring contracts; no gameplay or visual acceptance')
 out=R/'tests/reports';out.mkdir(parents=True,exist_ok=True);(out/'content-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False,indent=2));return int(bool(errors))
if __name__=='__main__':sys.exit(main())
