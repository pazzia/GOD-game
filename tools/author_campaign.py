"""Original authored campaign, deterministic data and command replays.
Rebuilding data is not a playability check; run the Godot replay suite.
"""
from pathlib import Path
from copy import deepcopy
import json
R=Path(__file__).resolve().parents[1]
CARDS=json.loads((R/'data/authoring/level_blueprints.json').read_text())['levels']
def find(rows,eid):return next(x for x in rows if x['id']==eid)
def slot(l,sid,pos,types,layer='ground',zone='near'):
 l['slots'].append(dict(id=sid,position=list(pos),zone_id=zone,mount_layer=layer,allowed_entity_types=types));return sid
def entity(l,eid,tid,mat,apparent,pos,asset=None,movable=True,mass=1,props=None,sid=None,layer='ground',zone='near'):
 sid=sid or eid+'_start'
 if not any(x['id']==sid for x in l['slots']):slot(l,sid,pos,[tid],layer,zone)
 e=dict(id=eid,type_id=tid,asset_id=asset or 'PROP_'+tid.upper(),material=mat,apparent_class=apparent,initial_slot=sid,movable=movable,mass_units=mass,properties=props or {})
 l['entities'].append(e);return e
def water(l,zid,p,phase='liquid',charge=0,radius=2):
 x,y=p;l['zones'].append(dict(id=zid,kind='WATER',thermal_position=list(p),polygon=[[x-radius,y-radius],[x+radius,y-radius],[x+radius,y+radius],[x-radius,y+radius]],initial_phase=phase,initial_thermal_charge=charge))
def goal(l,gid,pred,params,latched=False,required=True):l['goals'].append(dict(id=gid,kind='latched'if latched else'state',predicate_id=pred,parameters=params,required=required))
def cmd(t,**p):return dict(op='command',type=t,payload=p)
def ticks(n=180):return dict(op='advance_ticks',count=n)
def place(e,s):return cmd('PlaceProp',entity_id=e,slot_id=s)
def interact(e,a,target=None):
 p=dict(entity_id=e,action=a)
 if target is not None:p['target_entity_id']=target
 return dict(op='command',type='Interact',payload=p)
def req(e='stone',s='bridge',kind='stone'):return dict(type='support',parameters=dict(kind=kind,entity_id=e,slot_id=s))
def phase(z,p):return dict(type='water_phase',parameters=dict(zone_id=z,phase=p))
def est(e,k,v=True):return dict(type='entity_state',parameters=dict(entity_id=e,key=k,value=v))
def route(l,rid,points,requirements=None,support=None,reach=None):
 ns=[]
 for i,p in enumerate(points):
  nid=f'{rid}_{i}';l['navigation']['nodes'].append(dict(id=nid,position=list(p)));ns.append(nid)
 r=dict(id=rid,nodes=ns,ticks_per_edge=10,requirements=requirements or [])
 if support:r.update(required_support_entity=support[0],required_support_slot=support[1])
 if reach:r['destination_reach_zone_id']=reach
 l['navigation']['routes'].append(r);return r
def base(n):
 c=CARDS[n-1];lid=c['id']
 l=dict(schema_version=1,content_version='0.2.0',status='layout_seed',level_id=lid,chapter=c['chapter'],title_key=f'level.{lid}.title',scene_id=f"ENV{c['chapter']:02d}",available_myths=list(dict.fromkeys(c['initial_active_laws']+c['candidate_laws'])),initial_active_laws=c['initial_active_laws'],max_active_laws=c['max_active_laws'],required_votes=3,entities=[],slots=[],zones=[dict(id='near',kind='REACH')],occluders=[],witnesses=[],proofs=[],navigation=dict(nodes=[],routes=[]),goals=[],hints=[f'level.{lid}.hint{i}'for i in (1,2,3)],presentation=dict(layout_asset_id=f'SCENE_{lid}_LAYOUT',overlay_asset_id=f'SCENE_{lid}_OVERLAY'),canonical_solution_ref=lid+'_solution.json')
 entity(l,'hero','actor_felix','ORGANIC','PERSON',[6,20],'CH01_RIG',False,2,dict(locomotion='walk',initial_reach_zone_id='near'))
 for i,(x,ch)in enumerate(((3,'CH03'),(4,'CH05'),(5,'CROWD01')),1):
  sid=slot(l,f'audience_{i}',[x,3],['witness'])
  l['witnesses'].append(dict(id=f'w{i}',character_id=ch,initial_view_slot=sid,views=[dict(id='front',eye_position=[x,3],from_tick=0,duration_ticks=180,clear_ticks=25,look_at=[14,14])],expose_ticks=5,gap_tolerance_ticks=2))
 return l
def screen(l,e='screen_a',s='screen_left',p=(9,6),seg=((9,5),(9,7)),channels=None):
 entity(l,e,'screen','CLOTH','SCREEN',[2+len(l['entities']),25],'PROP_SCREEN',layer='tray');slot(l,s,p,['screen'],'screen')
 l['occluders'].append(dict(id=e+'_occluder',owner_entity=e,active_slot=s,segment=[list(v)for v in seg],channels=channels or['Vision']))
def inspector(l,ch='CH04',start=70,clear=35):
 w=l['witnesses'][2];w['character_id']=ch;w['views'][0].update(duration_ticks=60,clear_ticks=clear)
 w['views'].append(dict(id='back',eye_position=[21,3],from_tick=start,duration_ticks=60,clear_ticks=clear,look_at=[14,14]));screen(l,'screen_b','screen_right',(18,6),((18,4),(18,7)))
def cargo(l,e='cargo',mass=2,pos=(6,20),mode='carried'):
 p=dict(transport_mode=mode,carrier_entity_id='hero')
 if mode=='towed':p['tow_rope_entity_id']='tow_rope'
 return entity(l,e,'cargo_crate','WOOD','CARGO',pos,'PROP_CARGO_CRATE',mass=mass,props=p)
def river(l,size='L',proof=True):
 water(l,'demo_pool',[14,12],radius=4);water(l,'crossing_water',[12,20])
 e=entity(l,'stone','stone_'+size.lower(),'STONE','STONE',[2,24],'PROP_STONE_'+size,mass={'S':1,'M':3,'L':5}[size],layer='tray',props=dict(size=size,carry_capacity={'S':1,'M':3,'L':5}[size],buoyant=False))
 slot(l,'stage_stone',[14,12],[e['type_id']],'surface');slot(l,'bridge',[12,20],[e['type_id']],'surface')
 if proof:
  entity(l,'float','float','WOOD','FLOAT',[4,24],'PROP_FLOAT',layer='tray',props=dict(supports_entity='stone',support_when_slot='stage_float',hidden_method=True));slot(l,'stage_float',[14,12],['float'],'below');screen(l)
  l['proofs'].append(dict(myth_id='M01',result_anchors=[dict(entity_id='stone',offset=p)for p in[[-1,2],[0,3],[1,2]]],method_anchors=[dict(entity_id='float',offset=[0,-3])],predicates=[dict(type='apparent_class_is',parameters=dict(entity_id='stone',value='STONE')),dict(type='over_water',parameters=dict(entity_id='stone',zone_id='demo_pool')),dict(type='stable_support',parameters=dict(entity_id='stone'))]))
 route(l,'cross',[[6,20],[9,20],[12,20],[15,20],[18,20]],support=('stone','bridge'))
def prove1(extra=None):return [place('float','stage_float'),place('stone','stage_stone'),place('screen_a','screen_left')]+(extra or[])+[cmd('SetLawCandidate',myth_id='M01'),cmd('BeginPerformance'),ticks(),cmd('ActivateLaw',myth_id='M01',replace_law_id=None),interact('float','remove')]
def emitter(l,e,p,cls='FIRE',delta=1,radius=5):return entity(l,e,'oven'if cls=='FIRE'else'heated_stone','FIRE'if cls=='FIRE'else'STONE',cls,p,'PROP_FIRE'if cls=='FIRE'else'PROP_HEATED_STONE',mass=3,props=dict(emitter_class=cls,thermal_delta_per_tick=delta,thermal_radius_units=radius,enabled=True))
def cold_demo(l,p=(14,12),flame=(15,14),screenid='screen_a',screenslot='screen_left',seg=((9,5),(9,7))):
 water(l,'demo_water',p)
 entity(l,'bowl','bowl','WOOD','WATER_BOWL',p,'PROP_WATER_BOWL',False,props=dict(thermal_subject_zone_id='demo_water'))
 entity(l,'flame','decoy_flame','DECOY','FIRE',flame,'PROP_DECOY_FLAME',False)
 entity(l,'cold_pack','cold_pack','STEEL','COLD_PACK',[2,25],'PROP_COLD_PACK',props=dict(emitter_class='COLD_PACK',thermal_delta_per_tick=-1,thermal_radius_units=3,enabled=True,hidden_method=True,support_when_slot='stage_cold'))
 slot(l,'stage_cold',p,['cold_pack'],'below');screen(l,screenid,screenslot,(seg[0][0],seg[0][1]+1),seg)
 l['proofs'].append(dict(myth_id='M02',result_anchors=[dict(entity_id='bowl',offset=o)for o in[[-1,2],[0,3],[1,2]]],method_anchors=[dict(entity_id='cold_pack',offset=[0,-3])],predicates=[dict(type='apparent_class_is',parameters=dict(entity_id='flame',value='FIRE')),dict(type='observed_water_transition',parameters=dict(zone_id='demo_water',**{'from':'liquid','to':'frozen'})),dict(type='entity_visible',parameters=dict(entity_id='flame'))]))
def thermal(l,proof=True,inspect=False):
 water(l,'crossing_water',[12,20]);emitter(l,'oven',[12,17]);slot(l,'oven_far',[3,22],['oven'])
 if proof:
  cold_demo(l)
  if inspect:inspector(l)
 route(l,'cross',[[6,20],[9,20],[12,20],[15,20],[18,20]],[phase('crossing_water','frozen')])
def prove2(extra=None,replace=None):return[place('cold_pack','stage_cold'),place('screen_a','screen_left')]+(extra or[])+[cmd('SetLawCandidate',myth_id='M02'),cmd('BeginPerformance'),ticks(),cmd('ActivateLaw',myth_id='M02',replace_law_id=replace)]
def paper(l,proof=True,inspect=False):
 find(l['slots'],'hero_start')['position']=[6,12]
 for eid,p in(('anchor_a',[12,12]),('anchor_b',[16,12])):entity(l,eid,'span_anchor','WOOD','ANCHOR',p,'PROP_ANCHOR',False,props=dict(anchored=True,grounded=True))
 entity(l,'paper','paper_span','PAPER','PAPER',[2,24],'PROP_PAPER_BRIDGE',props=dict(span_anchor_entity_ids=['anchor_a','anchor_b'],span_anchor_offsets=[[-2,0],[2,0]],span_endpoint_offsets=[[-2,0],[2,0]],required_anchor_count=2,load_slot_ids=['stage_weight'],load_capacity=1,tear_resistance=1,flammable=True))
 slot(l,'stage_paper',[14,12],['paper_span'],'surface')
 entity(l,'weight','control_weight','STEEL','CARGO',[6,12],'PROP_CONTROL_WEIGHT',mass=50,props=dict(transport_mode='wheeled',carrier_entity_id='hero',move_mode='hoist',hoist_entity_id='hoist'))
 slot(l,'stage_weight',[14,12],['control_weight'])
 entity(l,'hoist','hoist','WOOD','HOIST',[8,12],'PROP_HOIST',False,0,dict(lift_capacity_units=60,service_slot_ids=['stage_weight','weight_start']))
 if proof:
  entity(l,'frame','hidden_frame','STEEL','FRAME',[4,24],'PROP_HIDDEN_FRAME',props=dict(supports_entity='paper',support_when_slot='stage_frame',support_capacity=150,hidden_method=True,grounded=True));slot(l,'stage_frame',[14,12],['hidden_frame'],'below');screen(l)
  l['proofs'].append(dict(myth_id='M03',result_anchors=[dict(entity_id='paper',offset=o)for o in[[-1,2],[0,3],[1,2]]],method_anchors=[dict(entity_id='frame',offset=[0,-3])],predicates=[dict(type='apparent_class_is',parameters=dict(entity_id='paper',value='PAPER')),dict(type='load_contact',parameters=dict(paper_id='paper',load_id='weight',min_mass=50)),dict(type='span_anchors_valid',parameters=dict(entity_id='paper'))]))
  if inspect:inspector(l,'CH07')
 route(l,'cross',[[6,12],[10,12],[14,12],[18,12],[21,12]],[req('paper','stage_paper','paper')])
def prove3(extra=None,replace=None):return[place('paper','stage_paper'),place('frame','stage_frame'),place('weight','stage_weight'),place('screen_a','screen_left')]+(extra or[])+[cmd('SetLawCandidate',myth_id='M03'),cmd('BeginPerformance'),ticks(),cmd('ActivateLaw',myth_id='M03',replace_law_id=replace),interact('frame','remove'),place('weight','weight_start')]
def transport(s,e='hero',r='cross',n=150):s.extend([cmd('AssignRoute',actor_id=e,route_id=r),cmd('RunResolution'),ticks(n)])
def arrived(l,e='hero',r='cross'):
 pred='route_completed'if e=='hero'or find(l['entities'],e)['apparent_class']in('ANIMAL','VEHICLE')else'cargo_delivered'
 goal(l,'arrived_'+e,pred,dict(**({'actor_id':e}if pred=='route_completed'else{'entity_id':e}),route_id=r),True)
def mooring(l):
 entity(l,'boat','boat','WOOD','BOAT',[8,21],'PROP_BOAT',False,3)
 entity(l,'anchor','stone_anchor','STONE','ANCHOR',[10,22],'PROP_STONE_ANCHOR',False,props=dict(size='S',buoyant=False,grounded=True,anchored=True))
 entity(l,'bollard','bollard','WOOD','BOLLARD',[7,22],'PROP_BOLLARD',False,props=dict(grounded=True,anchored=True))
 entity(l,'mooring','mooring_rope','WOOD','ROPE',[7,21],'PROP_ROPE',mass=0,props=dict(attachment_kind='mooring',mooring_owner_entity_id='boat',attachment_target_entity_id='anchor',rope_length_units=24))
 goal(l,'boat_held','entity_state',dict(entity_id='boat',key='moored',value=True))
def food(l):
 for zid,p,charge,owner in(('dessert_zone',[16,20],0,'dessert'),('bread_zone',[15,20],10,'bread')):
  water(l,zid,p,charge=charge);find(l['zones'],zid)['thermal_owner_entity_id']=owner
 entity(l,'bread','bread','ORGANIC','FOOD',[15,20],'PROP_BREAD',props=dict(thermal_subject_zone_id='bread_zone',cold_damage_below=-10,insulation_by_entity_ids=['box']))
 entity(l,'dessert','dessert','ORGANIC','FOOD',[16,20],'PROP_DESSERT',props=dict(thermal_subject_zone_id='dessert_zone'))
 entity(l,'box','insulated_box','WOOD','BOX',[5,24],'PROP_INSULATED_BOX',mass=0,props=dict(protects_entity_ids=['bread'],protection_slot_ids=['bread_box','bread_delivery'],initial_closed=False))
 slot(l,'bread_box',[5,24],['bread'],'below')
 for eid,t in(('bread','bread'),('dessert','dessert'),('box','insulated_box')):slot(l,eid+'_delivery',[6,20],[t],'below')
 emitter(l,'food_oven',[16,17]);goal(l,'dessert_frozen','water_phase',dict(zone_id='dessert_zone',phase='frozen'));goal(l,'bread_preserved','entity_intact',dict(entity_id='bread'))
def heat_screen(l,waterid='boat_water'):
 water(l,waterid,[20,20]);emitter(l,'boat_oven',[20,16]);slot(l,'boat_oven_far',[3,22],['oven']);screen(l,'thermal_screen','thermal_block',(20,18),((18,18),(22,18)),['Thermal'])
def write(l,s,alt=None):
 lid=l['level_id'];d=R/'data/levels'/(lid+'.json');d.parent.mkdir(parents=True,exist_ok=True);d.write_text(json.dumps(l,ensure_ascii=False,indent=2)+'\n')
 out=R/'tests/replays';out.mkdir(parents=True,exist_ok=True)
 def replay(steps):return dict(schema_version=1,level_id=lid,verification='not_run',steps=steps+[dict(op='assert',predicate='level_success')],expected_final_predicates=['level_success'])
 (out/(lid+'_solution.json')).write_text(json.dumps(replay(s),ensure_ascii=False,indent=2)+'\n')
 if alt is not None:(out/(lid+'_alternative.json')).write_text(json.dumps(replay(alt),ensure_ascii=False,indent=2)+'\n')
def one():
 l=base(4);river(l,'M');find(l['entities'],'screen_a')['properties']=dict(required_attachment_count=2,scheduled_effects=[dict(at_tick=15,phases=['PERFORMANCE','REHEARSAL'],operation='move_if_unsecured',target_slot_id='screen_blown')]);slot(l,'screen_blown',[4,7],['screen'],'screen')
 for i in(1,2):entity(l,f'clamp_{i}','clamp','STEEL','CLAMP',[7+i,25],'PROP_CLAMP',props=dict(attachment_kind='clamp',attachable_target_types=['screen']))
 goal(l,'screen_secured','entity_state',dict(entity_id='screen_a',key='secured',value=True));goal(l,'float_removed','entity_removed',dict(entity_id='float'));arrived(l)
 s=prove1([interact('clamp_1','attach','screen_a'),interact('clamp_2','attach','screen_a')])+[place('stone','bridge')];transport(s);write(l,s)
 l=base(5);mooring(l);cargo(l);route(l,'unload',[[6,20],[9,20],[12,20],[15,20],[18,20]],[est('boat','moored')]);arrived(l,'cargo','unload');s=[interact('mooring','attach','bollard')];transport(s,'cargo','unload');write(l,s)
 l=base(6);river(l,'M',False);find(l['entities'],'stone')['initial_slot']='bridge';entity(l,'goat','actor_goat','ORGANIC','ANIMAL',[6,20],'CH09_RIG',False,2,dict(locomotion='walk'));entity(l,'small_stone','stone_s','STONE','STONE',[12,23],'PROP_STONE_S',props=dict(size='S',carry_capacity=1,buoyant=False));slot(l,'small_bridge',[12,23],['stone_s'],'surface');find(l['entities'],'small_stone')['initial_slot']='small_bridge'
 entity(l,'tow_rope','tow_rope','WOOD','ROPE',[6,22],'PROP_ROPE',props=dict(rope_length_units=30))
 for i in(1,2):cargo(l,f'crate_{i}',1,(6,23),'towed')
 route(l,'small_cross',[[6,23],[9,23],[12,23],[15,23],[18,23]],support=('small_stone','small_bridge'));s=[]
 for e,r in(('goat','cross'),('crate_1','small_cross'),('crate_2','small_cross')):arrived(l,e,r);transport(s,e,r)
 write(l,s)
 l=base(7);l['zones']=[dict(id='near',kind='REACH',reachable_zone_ids=['middle']),dict(id='middle',kind='REACH',reachable_zone_ids=['near','far']),dict(id='far',kind='REACH',reachable_zone_ids=['middle'])];water(l,'wide_river',[12,20],radius=5)
 for e,p in(('stone_a',[2,24]),('stone_b',[4,24])):entity(l,e,'stone_m','STONE','STONE',p,'PROP_STONE_M',mass=3,props=dict(size='M',carry_capacity=3,buoyant=False))
 for sid,p,z in(('near_support',[9,20],'near'),('middle_support',[12,20],'middle'),('far_support',[15,20],'far')):slot(l,sid,p,['stone_m'],'surface',z)
 route(l,'to_island',[[6,20],[9,20],[12,20]],[req('stone_a','near_support'),req('stone_b','middle_support')],reach='middle');route(l,'to_far',[[12,20],[15,20],[18,20]],[req('stone_a','far_support'),req('stone_b','middle_support')],reach='far');arrived(l,'hero','to_far');s=[place('stone_a','near_support'),place('stone_b','middle_support')];transport(s,'hero','to_island');s.append(place('stone_a','far_support'));transport(s,'hero','to_far');write(l,s)
 l=base(8);river(l,'M');entity(l,'thread','safety_thread','CLOTH','THREAD',[18,9],'PROP_THREAD',props=dict(supports_entity='stone',support_when_slot='thread_start',support_capacity=3,support_offset=[-4,3],hidden_method=True));l['proofs'][0]['method_anchors'].append(dict(entity_id='thread',offset=[0,0]));goal(l,'thread_removed','entity_removed',dict(entity_id='thread'));goal(l,'float_removed','entity_removed',dict(entity_id='float'));arrived(l);s=[interact('thread','remove')]+prove1()+[place('stone','bridge')];transport(s);write(l,s)
 l=base(9);river(l);inspector(l,start=100);cargo(l);arrived(l,'cargo');goal(l,'float_removed','entity_removed',dict(entity_id='float'));s=prove1([place('screen_b','screen_right')])+[place('stone','bridge')];transport(s,'cargo');write(l,s)
 l=base(10);river(l);mooring(l);cargo(l);entity(l,'goat','actor_goat','ORGANIC','ANIMAL',[6,20],'CH09_RIG',False,2,dict(locomotion='walk'));arrived(l,'cargo');arrived(l,'goat');goal(l,'float_removed','entity_removed',dict(entity_id='float'));s=[interact('mooring','attach','bollard')]+prove1()+[place('stone','bridge')];transport(s,'cargo');transport(s,'goat');write(l,s)
def two():
 l=base(11);thermal(l);arrived(l);s=prove2();transport(s);write(l,s)
 l=base(12);food(l);e=cargo(l,'delivery',2);e['properties'].update(payload_entity_ids=['bread','dessert','box'],payload_mass_included=True);route(l,'cross',[[6,20],[10,20],[14,20],[18,20]],[phase('dessert_zone','frozen'),est('bread','intact')]);arrived(l,'delivery');s=[place('bread','bread_box'),interact('box','close'),cmd('RunResolution'),ticks(60),cmd('StopResolution'),place('bread','bread_delivery'),place('dessert','dessert_delivery'),place('box','box_delivery')];transport(s,'delivery');write(l,s)
 l=base(13);thermal(l);heat_screen(l);goal(l,'boat_water_liquid','water_phase',dict(zone_id='boat_water',phase='liquid'));arrived(l);s=[place('thermal_screen','thermal_block')]+prove2();transport(s);write(l,s)
 l=base(14);thermal(l,inspect=True);arrived(l);s=prove2([place('screen_b','screen_right')]);transport(s);write(l,s)
 l=base(15);thermal(l,False);find(l['zones'],'crossing_water').update(initial_phase='frozen',initial_thermal_charge=-20);heat_screen(l,'bowl_water');find(l['zones'],'bowl_water').update(initial_phase='frozen',initial_thermal_charge=-20);emitter(l,'heated_stone',[2,25],'HEATED_OBJECT',radius=3);slot(l,'warm_bowl',[20,19],['heated_stone']);goal(l,'bowl_thawed','water_phase',dict(zone_id='bowl_water',phase='liquid'));goal(l,'crossing_kept','water_phase',dict(zone_id='crossing_water',phase='frozen'));write(l,[place('thermal_screen','thermal_block'),place('heated_stone','warm_bowl'),cmd('RunResolution'),ticks(150)])
 l=base(16);thermal(l);e=find(l['entities'],'screen_a');e.update(type_id='steam_cloud',asset_id='PROP_STEAM');e['properties']=dict(scheduled_effects=[dict(at_tick=120,phases=['PERFORMANCE','REHEARSAL'],operation='set_occluder_enabled',target_occluder_id='screen_a_occluder',value=False),dict(at_tick=10,phases=['RUN_RESOLUTION'],operation='set_occluder_enabled',target_occluder_id='screen_a_occluder',value=False)])
 for sl in l['slots']:sl['allowed_entity_types']=['steam_cloud'if t=='screen'else t for t in sl['allowed_entity_types']]
 arrived(l);s=prove2();transport(s);write(l,s)
 l=base(17);thermal(l);entity(l,'stone','stone_l','STONE','STONE',[2,24],'PROP_STONE_L',mass=5,props=dict(size='L',carry_capacity=5,buoyant=False));slot(l,'bridge',[12,20],['stone_l'],'surface');l['navigation']['routes'][0]['requirements'].append(req());goal(l,'stone_law_kept','law_active',dict(myth_id='M01'));goal(l,'cold_law_added','law_active',dict(myth_id='M02'));arrived(l);s=[place('stone','bridge')]+prove2();transport(s);write(l,s)
 l=base(18);thermal(l,False);heat_screen(l);find(l['zones'],'boat_water').update(initial_phase='frozen',initial_thermal_charge=-20);emitter(l,'heated_stone',[2,25],'HEATED_OBJECT',radius=3);slot(l,'warm_boat',[20,19],['heated_stone']);entity(l,'boat','boat','WOOD','VEHICLE',[6,20],'PROP_BOAT',False,3,dict(locomotion='sail'));entity(l,'stone','stone_m','STONE','STONE',[12,20],'PROP_STONE_M',mass=3,props=dict(size='M',buoyant=False));route(l,'boat_route',[[6,20],[10,20],[14,20],[18,20]],[phase('boat_water','liquid')]);goal(l,'pedestrian_support','support_valid',dict(entity_id='stone'));arrived(l,'boat','boat_route');s=[place('thermal_screen','thermal_block'),place('heated_stone','warm_boat'),cmd('RunResolution'),ticks(60),cmd('StopResolution')];transport(s,'boat','boat_route');write(l,s)
 l=base(19);river(l);find(l['zones'],'crossing_water').update(initial_phase='frozen',initial_thermal_charge=-20);emitter(l,'oven',[12,17]);cargo(l);goal(l,'ordinary_heat','water_phase',dict(zone_id='crossing_water',phase='liquid'));goal(l,'cold_law_revoked','law_inactive',dict(myth_id='M02'));arrived(l,'cargo');s=prove1()+[place('stone','bridge'),cmd('RevokeLaw',myth_id='M02')];transport(s,'cargo');write(l,s)
 l=base(20);thermal(l);food(l);entity(l,'stone','stone_l','STONE','STONE',[2,24],'PROP_STONE_L',mass=5,props=dict(size='L',carry_capacity=5,buoyant=False));slot(l,'bridge',[12,20],['stone_l'],'surface');l['navigation']['routes'][0]['requirements']=[req(),phase('dessert_zone','frozen'),est('bread','intact')];e=cargo(l,'feast',2);e['properties'].update(payload_entity_ids=['bread','dessert','box'],payload_mass_included=True);arrived(l,'feast');s=[place('bread','bread_box'),interact('box','close'),place('stone','bridge')]+prove2()+[cmd('RunResolution'),ticks(60),cmd('StopResolution'),place('bread','bread_delivery'),place('dessert','dessert_delivery'),place('box','box_delivery')];transport(s,'feast');write(l,s)
def three():
 l=base(21);paper(l);goal(l,'frame_removed','entity_removed',dict(entity_id='frame'));arrived(l,'weight');s=prove3();transport(s,'weight');write(l,s)
 l=base(22);entity(l,'paper','paper_wall','PAPER','PAPER',[12,12],'PROP_PAPER_WALL',False,props=dict(load_capacity=1,tear_resistance=1,flammable=True));entity(l,'goat','actor_goat','ORGANIC','ANIMAL',[6,20],'CH09_RIG',False,2,dict(locomotion='walk'));entity(l,'gate','wooden_gate','WOOD','GATE',[12,22],'PROP_GATE',False,props=dict(initial_open=False));route(l,'detour',[[6,20],[9,22],[12,22],[16,22],[18,20]],[est('gate','open')]);arrived(l,'goat','detour');goal(l,'paper_preserved','entity_intact',dict(entity_id='paper'));s=[interact('gate','open')];transport(s,'goat','detour');write(l,s)
 l=base(23);paper(l,False);find(l['entities'],'paper')['initial_slot']='stage_paper';emitter(l,'oven',[14,9]);screen(l,'thermal_screen','thermal_block',(14,10),((11,10),(17,10)),['Thermal']);goal(l,'paper_preserved','entity_intact',dict(entity_id='paper'));arrived(l,'weight');s=[place('thermal_screen','thermal_block')];transport(s,'weight');write(l,s)
 l=base(24);paper(l)
 for aid in('anchor_a','anchor_b'):
  e=find(l['entities'],aid);e.update(type_id='stone_m',material='STONE',asset_id='PROP_STONE_M',mass_units=3);e['properties']=dict(size='M',buoyant=False,carry_capacity=3);find(l['slots'],e['initial_slot'])['allowed_entity_types']=['stone_m']
 water(l,'span_water',[14,12],radius=4);find(l['entities'],'weight')['mass_units']=3;entity(l,'test_weight','control_weight','STEEL','WEIGHT',[4,12],'PROP_CONTROL_WEIGHT',mass=50,props=dict(move_mode='hoist',hoist_entity_id='hoist'));slot(l,'test_weight_stage',[14,12],['control_weight']);find(l['entities'],'hoist')['properties']['service_slot_ids']+=['test_weight_start','test_weight_stage'];find(l['entities'],'paper')['properties']['load_slot_ids']=['test_weight_stage'];l['proofs'][0]['predicates'][1]['parameters']['load_id']='test_weight';arrived(l,'weight');goal(l,'paper_preserved','entity_intact',dict(entity_id='paper'))
 s=[place('paper','stage_paper'),place('frame','stage_frame'),place('test_weight','test_weight_stage'),place('screen_a','screen_left'),cmd('SetLawCandidate',myth_id='M03'),cmd('BeginPerformance'),ticks(),cmd('ActivateLaw',myth_id='M03',replace_law_id=None),place('test_weight','test_weight_start'),interact('frame','remove')];transport(s,'weight');write(l,s)
 l=base(25);paper(l,inspect=True);arrived(l,'weight');goal(l,'frame_removed','entity_removed',dict(entity_id='frame'));s=prove3([place('screen_b','screen_right')]);transport(s,'weight');write(l,s)
 l=base(26);paper(l);cargo(l,'first_cargo',1,(6,12));entity(l,'stone','stone_m','STONE','STONE',[8,12],'PROP_STONE_M',mass=3,props=dict(size='M',buoyant=False,carry_capacity=3));water(l,'first_water',[8,12],radius=1);route(l,'dry_delivery',[[6,12],[8,12],[10,12]],[req('stone','stone_start')]);arrived(l,'first_cargo','dry_delivery');find(l['slots'],'weight_start')['position']=[10,12];find(l['navigation']['nodes'],'cross_0')['position']=[10,12];find(l['navigation']['nodes'],'cross_1')['position']=[12,12];emitter(l,'oven',[14,9]);arrived(l,'weight');goal(l,'paper_preserved','entity_intact',dict(entity_id='paper'));s=[];transport(s,'first_cargo','dry_delivery');s+=prove3(replace='M01');transport(s,'weight');write(l,s)
 l=base(27);paper(l,False);find(l['entities'],'paper')['initial_slot']='stage_paper';emitter(l,'oven',[14,9]);slot(l,'oven_far',[3,24],['oven']);entity(l,'flags','paper_flags','PAPER','FLAGS',[14,11],'PROP_FLAGS',False,props=dict(flammable=True,load_capacity=1,tear_resistance=1));screen(l,'thermal_screen','thermal_block',(14,10),((11,10),(17,10)),['Thermal']);goal(l,'paper_preserved','entity_intact',dict(entity_id='paper'));goal(l,'flags_preserved','entity_intact',dict(entity_id='flags'));arrived(l,'weight');s=[place('oven','oven_far')];transport(s,'weight');a=[place('thermal_screen','thermal_block')];transport(a,'weight');write(l,s,a)
 l=base(28);paper(l,inspect=True);e=find(l['entities'],'anchor_a');e.update(material='STONE',asset_id='PROP_STONE_M',mass_units=3,movable=True);e['properties'].update(size='M',buoyant=False,carry_capacity=3,grounded=True);slot(l,'anchor_a_water',[12,20],['span_anchor'],'surface');e['initial_slot']='anchor_a_water';water(l,'support_water',[12,20]);goal(l,'frame_removed','entity_removed',dict(entity_id='frame'));arrived(l,'weight');s=[place('anchor_a','anchor_a_start')]+prove3([place('screen_b','screen_right')]);transport(s,'weight');write(l,s)
 l=base(29);thermal(l);find(l['zones'],'demo_water').update(initial_phase='frozen',initial_thermal_charge=-20);emitter(l,'heated_stone',[2,25],'HEATED_OBJECT',radius=3);slot(l,'warm_sample',[14,12],['heated_stone'],'below');slot(l,'stone_away',[3,25],['heated_stone'],'tray');arrived(l);s=[place('heated_stone','warm_sample'),cmd('RunResolution'),ticks(60),cmd('StopResolution'),place('heated_stone','stone_away')]+prove2();transport(s);write(l,s)
 final()
def final():
 l=base(30);river(l);cargo(l,'first_cargo',1);arrived(l,'first_cargo');l['witnesses'][2]['character_id']='CH07';l['witnesses'][2]['views'][0]['clear_ticks']=35
 cold_demo(l,(18,12),(19,14),'screen_cold','screen_cold_slot',((9,4),(9,6)));water(l,'cold_passage',[20,20],radius=1);emitter(l,'oven',[20,17],radius=4)
 for e,p in(('anchor_a',[18,20]),('anchor_b',[22,20])):entity(l,e,'span_anchor','WOOD','ANCHOR',p,'PROP_ANCHOR',False,props=dict(grounded=True,anchored=True))
 entity(l,'paper','paper_span','PAPER','PAPER',[4,26],'PROP_PAPER_BRIDGE',props=dict(span_anchor_entity_ids=['anchor_a','anchor_b'],span_anchor_offsets=[[-2,0],[2,0]],span_endpoint_offsets=[[-2,0],[2,0]],required_anchor_count=2,load_slot_ids=['stage_weight'],load_capacity=1,tear_resistance=1,flammable=True));slot(l,'stage_paper',[20,20],['paper_span'],'surface')
 entity(l,'frame','hidden_frame','STEEL','FRAME',[6,26],'PROP_HIDDEN_FRAME',props=dict(supports_entity='paper',support_when_slot='stage_frame',support_capacity=150,grounded=True,hidden_method=True));slot(l,'stage_frame',[20,20],['hidden_frame'],'below')
 entity(l,'weight','control_weight','STEEL','CARGO',[18,20],'PROP_CONTROL_WEIGHT',mass=50,props=dict(transport_mode='wheeled',carrier_entity_id='hero',move_mode='hoist',hoist_entity_id='hoist'));slot(l,'stage_weight',[20,20],['control_weight']);entity(l,'hoist','hoist','WOOD','HOIST',[22,18],'PROP_HOIST',False,0,dict(lift_capacity_units=60,service_slot_ids=['weight_start','stage_weight']));screen(l,'screen_paper','screen_paper_slot',(9,7),((9,6),(9,8)))
 l['proofs'].append(dict(myth_id='M03',result_anchors=[dict(entity_id='paper',offset=p)for p in[[-1,2],[0,3],[1,2]]],method_anchors=[dict(entity_id='frame',offset=[0,-3])],predicates=[dict(type='apparent_class_is',parameters=dict(entity_id='paper',value='PAPER')),dict(type='load_contact',parameters=dict(paper_id='paper',load_id='weight',min_mass=50)),dict(type='span_anchors_valid',parameters=dict(entity_id='paper'))]))
 route(l,'final_cross',[[18,20],[20,20],[22,20]],[req('paper','stage_paper','paper'),phase('cold_passage','frozen')]);arrived(l,'weight','final_cross');goal(l,'cold_law_kept','law_active',dict(myth_id='M02'),required=False);goal(l,'paper_law_added','law_active',dict(myth_id='M03'));goal(l,'frame_removed','entity_removed',dict(entity_id='frame'));goal(l,'paper_intact','entity_intact',dict(entity_id='paper'))
 s=prove1()+[place('stone','bridge')];transport(s,'first_cargo');s+=[interact('screen_a','remove'),place('cold_pack','stage_cold'),place('screen_cold','screen_cold_slot'),cmd('SetLawCandidate',myth_id='M02'),cmd('BeginPerformance'),ticks(),cmd('ActivateLaw',myth_id='M02',replace_law_id=None),cmd('RunResolution'),ticks(60),cmd('StopResolution'),place('paper','stage_paper'),place('frame','stage_frame'),place('weight','stage_weight'),place('screen_paper','screen_paper_slot'),cmd('SetLawCandidate',myth_id='M03'),cmd('BeginPerformance'),ticks(),cmd('ActivateLaw',myth_id='M03',replace_law_id='M01'),interact('frame','remove'),place('weight','weight_start')];transport(s,'weight','final_cross');write(l,s)
def alternatives():
 def read(n):
  lid=f'L{n:02d}';return json.loads((R/'data/levels'/(lid+'.json')).read_text()),json.loads((R/'tests/replays'/(lid+'_solution.json')).read_text())['steps'][:-1]
 for n in(4,9,11,14,21,24,25,28):
  l,s=read(n);slot(l,'screen_left_alt',[10,7],['screen'],'screen');l['occluders'].append(dict(id='left_screen_alt',owner_entity='screen_a',active_slot='screen_left_alt',segment=[[10,6],[10,8]],channels=['Vision']));a=deepcopy(s)
  for step in a:
   if step.get('type')=='PlaceProp'and step['payload'].get('entity_id')=='screen_a':step['payload']['slot_id']='screen_left_alt'
  write(l,s,a)
 for n in(13,15,18):
  l,s=read(n);a=deepcopy(s)
  for step in a:
   if step.get('type')=='PlaceProp'and step['payload'].get('entity_id')=='thermal_screen':step['payload']=dict(entity_id='boat_oven',slot_id='boat_oven_far')
  write(l,s,a)
 l,s=read(8);screen(l,'thread_screen','thread_screen_slot',(10,5),((10,4),(10,6)));a=[place('stone','stage_stone'),place('thread_screen','thread_screen_slot'),cmd('SetLawCandidate',myth_id='M01'),cmd('BeginPerformance'),ticks(),cmd('ActivateLaw',myth_id='M01',replace_law_id=None),interact('thread','remove'),interact('float','remove'),place('stone','bridge')];transport(a);write(l,s,a)
 l,s=read(16);screen(l,'permanent_screen','permanent_screen_slot',(10,7),((10,6),(10,8)));a=deepcopy(s)
 for step in a:
  if step.get('type')=='PlaceProp'and step['payload'].get('entity_id')=='screen_a':step['payload']=dict(entity_id='permanent_screen',slot_id='permanent_screen_slot')
 write(l,s,a)
 l,s=read(23);cold_demo(l,(20,8),(21,10),'cold_screen','cold_screen_slot',((9,3),(9,4)));a=[place('paper','paper_start'),place('cold_pack','stage_cold'),place('cold_screen','cold_screen_slot'),cmd('SetLawCandidate',myth_id='M02'),cmd('BeginPerformance'),ticks(),cmd('ActivateLaw',myth_id='M02',replace_law_id=None),place('paper','stage_paper')];transport(a,'weight');write(l,s,a)
 l,s=read(30);screen(l,'thermal_screen','thermal_block',(20,18),((18,18),(22,18)),['Thermal']);a=deepcopy(s)
 for st in a:
  if st.get('type')=='ActivateLaw'and st['payload'].get('myth_id')=='M03':st['payload']['replace_law_id']='M02'
 i=next(i for i,st in enumerate(a)if st.get('type')=='SetLawCandidate'and st['payload'].get('myth_id')=='M03');a.insert(i,place('thermal_screen','thermal_block'));write(l,s,a)
def apply_character_cast():
 source=json.loads((R/'data/authoring/character_cast.json').read_text())
 for lid,cast in source['overrides'].items():
  p=R/'data/levels'/(lid+'.json');level=json.loads(p.read_text())
  for witness_id,character_id in cast.items():find(level['witnesses'],witness_id)['character_id']=character_id
  assert len({w['character_id']for w in level['witnesses']})==len(level['witnesses']),lid+' duplicate person in one audience'
  p.write_text(json.dumps(level,ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':
 one();two();three();alternatives();apply_character_cast();print('Authored 27 levels and 16 alternatives, applied campaign cast; actual replay checks still required.')
