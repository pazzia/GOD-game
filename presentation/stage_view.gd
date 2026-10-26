class_name StageView
extends Control
const Puppet=preload("res://presentation/character_puppet.gd")
const ThemeKit=preload("res://presentation/theme.gd")
const Art=preload("res://presentation/reboot_art.gd")
signal target_tapped(kind: String,id: String)
var kernel: RefCounted
var translator: Callable
var selected: String=""
var placement_entity: String=""
var inspected: String=""
var hud_safe_top: float=184.0
var reduced_motion: bool=false
var show_capacity: bool=false
var ui_text_scale: float=1.0
var clock: float=0
var _textures: Dictionary={}
var _pick_images: Dictionary={}
var _hits: Array=[]
var _puppets: Dictionary={}
var _capacity_overlay: Node2D
var _kernel_signature: String=""
var _witness_poses: Dictionary={}
var _cue_counts: Dictionary={}
var _business_beat: int=-1
var _animal_poses: Dictionary={}
var _last_inspected: String=""
var _last_selected_actor: String=""
const WITNESS_HEIGHT: float=234.0
var _environments: Dictionary={}
var _route_frames: Dictionary={}
var _render_tick: int=-1
var _render_phase: String=""
var _route_signature: String=""
var _tick_elapsed: float=.1
var _pointer_active: bool=false
var _pointer_origin: Vector2
var _tap_cancelled: bool=false
var _pressed_target: Dictionary={}
var _font: Font=ThemeKit.body_font()
const INK=Color("252647")
const CREAM=Color("fff2d8")
const PURPLE=Color("40b8b3")
const ASSETS={"PROP_STONE_M":"stone","PROP_STONE_L":"stone","PROP_STONE_S":"stone","PROP_FLOAT":"float","PROP_SCREEN":"screen","PROP_CARGO_CRATE":"crate","PROP_TICKET_BOOTH":"ticket_booth","PROP_ANCHOR":"span_anchor","PROP_STONE_ANCHOR":"stone_anchor","PROP_BOLLARD":"wooden_bollard","PROP_BOAT":"boat","PROP_ROPE":"rope","PROP_THREAD":"thread","PROP_CLAMP":"clamp","PROP_COLD_PACK":"cryopack","PROP_DECOY_FLAME":"decoy_fire","PROP_FIRE":"fire_source","PROP_WATER_BOWL":"water_bowl","PROP_HEATED_STONE":"hot_stone","PROP_INSULATED_BOX":"thermobox","PROP_BREAD":"bread","PROP_DESSERT":"dessert","PROP_HIDDEN_FRAME":"frame","PROP_PAPER_BRIDGE":"paper_bridge","PROP_CONTROL_WEIGHT":"control_weight","PROP_HOIST":"hoist","PROP_PAPER_WALL":"paper_gate","PROP_GATE":"wood_gate","PROP_FLAGS":"flags","PROP_STEAM":"steam","PROP_POSTER":"poster"}
const CHARACTERS={"CH01":"felix","CH02":"plum","CH03":"marfa","CH04":"semyon","CH05":"nika","CH06":"lada","CH07":"roza","CH08":"hugo","CH09":"caramelka","CROWD01":"crowd_gardener","CROWD02":"crowd_postwoman","CROWD03":"crowd_fisherman","CROWD04":"crowd_librarian","CROWD05":"crowd_merchant","CROWD06":"crowd_musician"}
func _ready() -> void:
	mouse_filter=MOUSE_FILTER_PASS;clip_contents=true;texture_repeat=CanvasItem.TEXTURE_REPEAT_DISABLED
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_capacity_overlay=Node2D.new();_capacity_overlay.name="CapacityBadges";add_child(_capacity_overlay)
	_capacity_overlay.draw.connect(_draw_interaction_overlay)
	_capacity_overlay.draw.connect(_draw_capacity_badges)
	_sample_presentation(0)
	_sync_puppets()
func _process(delta: float) -> void:
	if not reduced_motion:clock+=delta
	_sample_presentation(delta)
	_sync_puppets()
	queue_redraw()
	if is_instance_valid(_capacity_overlay):_capacity_overlay.queue_redraw()
func _ensure_puppet(key: String,actor: String,height: float) -> void:
	var art_key: String=Art.actor_key(actor)
	var illustrated: bool=Art.has_art("characters",art_key)
	if _puppets.has(key):
		if _puppets[key].get_meta("actor","")==actor and (_puppets[key].visual_mode=="illustrated_cutout")==illustrated:return
		_puppets[key].visible=false;_puppets[key].queue_free();_puppets.erase(key)
	var puppet=Puppet.new();puppet.name="Puppet_"+key.replace(":","_");add_child(puppet)
	var configured: bool=puppet.configure_illustrated(actor,height) if illustrated else puppet.configure(actor,height)
	if configured:
		puppet.set_meta("actor",actor);_puppets[key]=puppet
	else:puppet.queue_free()
func _route_motion(entity_id: String) -> Dictionary:
	var result: Dictionary={"moving":false,"facing":1,"waiting":false}
	var routes: Array=kernel.state.routes.keys();routes.reverse()
	for actor_id in routes:
		var task: Dictionary=kernel.state.routes[actor_id]
		if actor_id!=entity_id and (task.carrier_id!=entity_id or task.get("transport_mode","")=="towed"):continue
		var route: Dictionary=kernel._find(kernel.definition.navigation.routes,task.route_id)
		result.facing=1 if kernel._find(kernel.definition.navigation.nodes,route.nodes[-1]).position[0]>=kernel._find(kernel.definition.navigation.nodes,route.nodes[0]).position[0] else -1
		result.waiting=not str(task.get("waiting_for","")).is_empty()
		result.moving=task.progress<(route.nodes.size()-1)*int(route.get("ticks_per_edge",10)) and str(task.get("waiting_for","")).is_empty() and kernel.state.phase=="RUN_RESOLUTION"
	return result
func _shared_start_group(id: String,asset_ids: Array) -> Array:
	var members: Array=[]
	if not kernel._entities.has(id):return members
	var start: Array=kernel._slots[kernel._entities[id].initial_slot].position
	for other in kernel._entities:
		var definition: Dictionary=kernel._entities[other]
		if definition.asset_id in asset_ids and kernel._slots[definition.initial_slot].position==start:members.append(other)
	members.sort()
	return members
func _hero_display_height() -> float:
	var normal: float=minf(338,size.y*.34)
	if kernel!=null and not kernel.state.is_empty() and _shared_start_group("hero",["CH01_RIG","CH09_RIG"]).size()>1:return minf(normal,270)
	return normal

func _entity_actor(id: String) -> String:
	var asset: String=str(kernel._entities[id].asset_id)
	if asset.ends_with("_RIG"):return str(CHARACTERS.get(asset.trim_suffix("_RIG"),""))
	return ""

func _actor_height(actor: String,base: float) -> float:
	return base*float(Art.entry("characters",Art.actor_key(actor)).get("height_ratio",1.0))

func _plum_offset(height: float) -> Vector2:
	var tutorial: bool=not str(kernel.definition.get("presentation",{}).get("observer_actor_id","")).is_empty()
	return Vector2(-height*.50 if tutorial else height*.66,-height*.72+sin(clock*3)*height*.025)

func _witness_entity(witness_id: String) -> String:
	var actor_id: String=str(kernel.definition.get("presentation",{}).get("observer_actor_id",""))
	if actor_id.is_empty() or not kernel._entities.has(actor_id):return ""
	var witness: Dictionary=kernel._find(kernel.definition.witnesses,witness_id)
	return actor_id if str(witness.get("character_id",""))==str(kernel._entities[actor_id].asset_id).trim_suffix("_RIG") else ""

func entity_display_position(id: String) -> Vector2:
	return _visual_position(id) if kernel!=null and kernel.state.entities.has(id) else Vector2.ZERO

func witness_display_position(id: String) -> Vector2:
	var entity_id: String=_witness_entity(id)
	if not entity_id.is_empty():return _visual_position(entity_id)
	var eye: Vector2=kernel.witness_eye(id)
	return world([eye.x,eye.y])
func _visual_position(id: String) -> Vector2:
	var exact: Vector2=_entity_position(id)
	exact.y-=_surface_lift(id,exact)
	var definition: Dictionary=kernel._entities[id]
	var attachment: String=str(kernel.state.entities[id].get("attachment_target",""))
	if definition.properties.get("attachment_kind","")=="clamp" and kernel.state.entities.has(attachment) and not kernel.state.entities[attachment].removed:
		var siblings: Array=[]
		for other in kernel.state.entities:
			if not kernel.state.entities[other].removed and kernel.state.entities[other].get("attachment_target","")==attachment and kernel._entities[other].properties.get("attachment_kind","")=="clamp":siblings.append(other)
		siblings.sort()
		var side: float=-1 if siblings.find(id)%2==0 else 1
		var target_height: float=_prop_height(attachment)
		return _entity_position(attachment)+Vector2(target_height*.38*side,-target_height*.14)
	var offset: Vector2=Vector2.ZERO
	if id=="hero" and not str(kernel.definition.get("presentation",{}).get("observer_actor_id","")).is_empty():
		# The tutorial scientist observes beside Marfa, rather than occluding her
		# face from the player's camera. His planar simulation location is intact.
		offset=Vector2(-230,-8)
	elif definition.asset_id in ["CH01_RIG","CH09_RIG"] and _shared_start_group(id,["CH01_RIG","CH09_RIG"]).size()>1:
		offset=Vector2(-110,-6) if definition.asset_id=="CH01_RIG" else Vector2(110,-6)
	elif definition.asset_id=="PROP_CARGO_CRATE":
		var group: Array=_shared_start_group(id,["PROP_CARGO_CRATE"])
		if group.size()>1:offset=Vector2((group.find(id)-(group.size()-1)*.5)*140,18)
		elif kernel.state.get("level_id","")=="L02":offset=Vector2(-215,18)
	if offset==Vector2.ZERO:return exact
	# Arrange coincident painted silhouettes around the same logical start point.
	# The offset eases away as a confirmed route leaves that point; geometry,
	# witness rays, supports, slots and the kernel remain completely unchanged.
	var start: Vector2=world(kernel._slots[definition.initial_slot].position)
	var weight: float=1.0-clampf(exact.distance_to(start)/80.0,0,1)
	return exact+offset*weight

func _paper_layout(id: String) -> Dictionary:
	if not kernel.state.entities.has(id) or kernel.state.entities[id].removed:return {}
	var definition: Dictionary=kernel._entities[id]
	if definition.type_id!="paper_span":return {}
	var anchors: Array=definition.properties.get("span_anchor_entity_ids",[])
	if anchors.size()<2:return {}
	var entity: Dictionary=kernel.state.entities[id]
	var endpoint_offsets: Array=definition.properties.get("span_endpoint_offsets",[])
	if endpoint_offsets.size()<2:return {}
	for index in range(2):
		if not kernel.state.entities.has(anchors[index]) or kernel.state.entities[anchors[index]].removed:return {}
		var expected: Vector2=_vec(entity.position)+_vec(endpoint_offsets[index])
		if expected!=_vec(kernel.state.entities[anchors[index]].position):return {}
	var first: Vector2=world(kernel.state.entities[anchors[0]].position)
	var last: Vector2=world(kernel.state.entities[anchors[1]].position)
	var ground: Vector2=world(entity.position)
	var width: float=maxf(180,first.distance_to(last)+24)
	var thickness: float=clampf(width*.16,56,80)
	# A workshop span is supported above its ground-plane anchor, not painted
	# on the same foot pivot as the load and the temporary frame.
	var support_height: float=minf(_prop_height(anchors[0]),_prop_height(anchors[1]))*.76
	var beam_top: float=ground.y-support_height-thickness*.20
	var rect: Rect2=Rect2(ground.x-width*.5,beam_top,width,thickness)
	# In the painted accordion span the central standing plane is below the
	# silhouette's upper folds. Align the material base, not its transparent box
	# with those crests; this also supplies the same plane to walking actors.
	var surface: float=beam_top+thickness*.55
	var elevation: float=ground.y-surface
	return {"id":id,"rect":rect,"surface_y":surface,"ground":ground,"first":first,"last":last,"elevation":elevation}

func _paper_under_load(id: String) -> Dictionary:
	if not kernel.state.entities.has(id):return {}
	var entity: Dictionary=kernel.state.entities[id]
	for paper_id in kernel.state.entities:
		var paper: Dictionary=kernel._entities[paper_id]
		if paper.type_id!="paper_span" or entity.slot not in paper.properties.get("load_slot_ids",[]):continue
		var layout: Dictionary=_paper_layout(paper_id)
		if not layout.is_empty() and entity.position==kernel.state.entities[paper_id].position:return layout
	return {}

func _route_support(route: Dictionary) -> String:
	if route.has("required_support_entity"):return str(route.required_support_entity)
	for requirement in route.get("requirements",[]):
		if requirement.type=="support":return str(requirement.parameters.get("entity_id",""))
	return ""

func _surface_lift(id: String,at: Vector2) -> float:
	var prepared: Dictionary=_paper_under_load(id)
	if not prepared.is_empty():
		var radius: float=float(prepared.rect.size.x)*.52
		var blend: float=clampf((radius-absf(at.x-float(prepared.ground.x)))/maxf(1,radius*.32),0,1)
		return float(prepared.elevation)*blend*blend*(3-2*blend)
	var routes: Array=kernel.state.routes.keys();routes.reverse()
	for actor_id in routes:
		var task: Dictionary=kernel.state.routes[actor_id]
		var payloads: Array=kernel._entities[actor_id].properties.get("payload_entity_ids",[])
		if actor_id!=id and (task.carrier_id!=id or task.get("transport_mode","")=="towed") and id not in payloads:continue
		var route: Dictionary=kernel._find(kernel.definition.navigation.routes,task.route_id)
		var support_id: String=_route_support(route)
		if not kernel.state.entities.has(support_id) or kernel.state.entities[support_id].removed:continue
		var support: Dictionary=kernel._entities[support_id]
		var center: Vector2=world(kernel.state.entities[support_id].position)
		var radius: float=0
		var lift: float=0
		if support.type_id=="paper_span":
			var layout: Dictionary=_paper_layout(support_id)
			if layout.is_empty():continue
			radius=float(layout.rect.size.x)*.52;lift=float(layout.elevation)
		elif support.material=="STONE":
			var height: float=_prop_height(support_id)
			var tex: Texture2D=asset_texture(support_id)
			if tex==null:continue
			radius=height*float(tex.get_width())/tex.get_height()*.53;lift=height*.50
		else:continue
		if absf(at.y-center.y)>maxf(64,size.y*.07):continue
		var blend: float=clampf((radius-absf(at.x-center.x))/maxf(1,radius*.32),0,1)
		return lift*blend*blend*(3-2*blend)
	return 0

func _paper_frame_layout(id: String) -> Rect2:
	var definition: Dictionary=kernel._entities[id]
	if definition.type_id!="hidden_frame":return Rect2()
	var target: String=str(definition.properties.get("supports_entity",""))
	if kernel.state.entities[id].slot!=definition.properties.get("support_when_slot",""):return Rect2()
	var layout: Dictionary=_paper_layout(target)
	if layout.is_empty():return Rect2()
	var width: float=float(layout.rect.size.x)*.88
	var top: float=float(layout.rect.end.y)-8
	return Rect2(float(layout.ground.x)-width*.5,top,width,maxf(28,float(layout.ground.y)-top+6))

func _prop_draw_priority(id: String) -> int:
	var definition: Dictionary=kernel._entities[id]
	if definition.type_id=="hidden_frame" or kernel._slots[kernel.state.entities[id].slot].mount_layer=="below":return 0
	if definition.type_id=="span_anchor":return 1
	if definition.type_id=="paper_span":return 2
	if not _paper_under_load(id).is_empty():return 3
	return 2

func _sync_puppets() -> void:
	if kernel==null or kernel.state.is_empty():
		for puppet in _puppets.values():puppet.visible=false
		return
	var signature: String=str(kernel.get_instance_id())+":"+str(kernel.state.get("content_digest",""))
	var height: float=_hero_display_height()
	_ensure_puppet("felix","felix",height);_ensure_puppet("plum","plum",_actor_height("plum",height))
	var wanted: Array=["felix","plum"]
	for witness in kernel.definition.witnesses:
		var actor: String=CHARACTERS.get(witness.character_id,"")
		if not actor.is_empty() and _witness_entity(witness.id).is_empty():
			var key: String="witness:"+witness.id;wanted.append(key);_ensure_puppet(key,actor,_actor_height(actor,WITNESS_HEIGHT))
	for id in kernel.state.entities:
		var actor: String=_entity_actor(id)
		if not actor.is_empty() and actor!="felix":
			var key: String="entity:"+id;wanted.append(key);_ensure_puppet(key,actor,_actor_height(actor,300))
	for key in _puppets.keys():
		if key not in wanted:
			_puppets[key].visible=false;_puppets[key].queue_free();_puppets.erase(key)
	if signature!=_kernel_signature:
		for puppet in _puppets.values():puppet.play_state("idle",true)
		_kernel_signature=signature
		_witness_poses.clear();_animal_poses.clear();_cue_counts.clear();_business_beat=-1
		_last_inspected="";_last_selected_actor=""
		_play_cue("plum","enter")
	for key in _puppets:
		var puppet: Node2D=_puppets[key]
		if key.begins_with("witness:"):
			_sync_witness_puppet(key,puppet)
			continue
		var id: String="hero" if key in ["felix","plum"] else key.trim_prefix("entity:")
		var entity: Dictionary=kernel.state.entities[id]
		puppet.visible=not entity.removed and kernel._slots[entity.slot].mount_layer!="tray"
		puppet.process_mode=Node.PROCESS_MODE_INHERIT if puppet.visible else Node.PROCESS_MODE_DISABLED
		puppet.position=_visual_position(id);puppet.set_reduced_motion(reduced_motion)
		var motion: Dictionary=_route_motion(id);puppet.set_facing(motion.facing)
		var loop: String="move" if motion.moving else ("celebrate" if kernel.state.phase=="SUCCESS" else ("observe" if kernel.state.phase in ["PERFORMANCE","REHEARSAL"] else "idle"))
		if key=="felix":puppet.set_display_height(height)
		elif key=="plum":
			puppet.set_display_height(_actor_height("plum",height));puppet.position+=_plum_offset(height)
			loop="fly" if motion.moving else ("cheer" if kernel.state.phase=="SUCCESS" else "hover")
		else:
			puppet.set_display_height(_actor_height(puppet.actor_id,300))
			if motion.moving:loop="walk" if puppet.actor_id=="caramelka" else "move"
		var keep_idle_acting: bool=puppet.current_state in ["idle_chew","sleepy"] and loop in ["idle","hover"] and kernel.state.phase in ["PLAN_SHOW","PLAN_RESOLUTION"]
		if not keep_idle_acting:puppet.play_state(loop)
		if key.begins_with("entity:"):
			var mood: String="move" if motion.moving else ("suspect" if motion.waiting else ("success" if kernel.state.phase=="SUCCESS" else ("observe" if kernel.state.phase in ["PERFORMANCE","REHEARSAL"] else "idle")))
			if _animal_poses.get(key,"")!=mood:
				_animal_poses[key]=mood;_play_cue(key,mood)
	if inspected!=_last_inspected:
		_last_inspected=inspected
		if not inspected.is_empty():_play_cue("witness:"+inspected,"interact")
	if selected!=_last_selected_actor:
		_last_selected_actor=selected
		if _puppets.has("entity:"+selected):
			var near_paper: bool=false
			for id in kernel.state.entities:
				if kernel._entities[id].material=="PAPER" and not kernel.state.entities[id].removed:
					var a: Array=kernel.state.entities[selected].position;var b: Array=kernel.state.entities[id].position
					near_paper=near_paper or Vector2(a[0],a[1]).distance_to(Vector2(b[0],b[1]))<=5
			_play_cue("entity:"+selected,"interact" if near_paper else "observe")
	_actor_business()
	var order: Array=_puppets.keys()
	order.sort_custom(func(a,b):return _puppets[a].position.y<_puppets[b].position.y)
	for key in order:move_child(_puppets[key],get_child_count()-1) # Tree order, never z above sibling modal UI.
	# This overlay follows every actor, but keeps z=0 so sibling modals still cover it.
	if is_instance_valid(_capacity_overlay):move_child(_capacity_overlay,get_child_count()-1)
func _sync_witness_puppet(key: String,puppet: Node2D) -> void:
	var id: String=key.trim_prefix("witness:")
	var witness: Dictionary=kernel.state.witnesses[id]
	var eye: Vector2=kernel.witness_eye(id)
	puppet.visible=true;puppet.process_mode=Node.PROCESS_MODE_INHERIT
	puppet.set_display_height(_actor_height(puppet.actor_id,WITNESS_HEIGHT));puppet.set_reduced_motion(reduced_motion)
	# Logical XY is the ground-plane observation position. Painted eyes sit above
	# the ground pin; never shift the feet away from the authored walking surface.
	puppet.position=world([eye.x,eye.y])
	puppet.set_facing(1 if eye.x<12 else -1)
	var mood: String="success" if kernel.state.phase=="SUCCESS" else ("reveal" if witness.exposed else ("accept" if witness.eligible_vote else ("suspect" if int(witness.get("expose_streak",0))>0 else ("observe" if kernel.state.phase in ["PERFORMANCE","REHEARSAL"] else "idle"))))
	var loop: String={"success":"celebrate","reveal":"suspect","accept":"observe"}.get(mood,mood)
	puppet.play_state(loop)
	if _witness_poses.get(key,"")!=mood:
		var first: bool=not _witness_poses.has(key)
		_witness_poses[key]=mood
		_play_cue(key,"enter" if first else mood)

func _play_cue(key: String,trigger: String) -> void:
	if not _puppets.has(key):return
	var counter: String=key+":"+trigger
	var index: int=int(_cue_counts.get(counter,0))
	if _puppets[key].play_cue(trigger,index,true):_cue_counts[counter]=index+1

func _actor_business() -> void:
	# Occasional character business uses only a cosmetic clock. It cannot advance rules.
	if reduced_motion or kernel.state.phase not in ["PLAN_SHOW","PLAN_RESOLUTION","SUCCESS"]:return
	var beat: int=int(clock/8.0)
	if beat==_business_beat:return
	_business_beat=beat
	if beat==0:return
	for key in _puppets:
		var puppet: Node2D=_puppets[key]
		if not puppet.is_loop_state(puppet.current_state):continue
		var trigger: String="success" if kernel.state.phase=="SUCCESS" else "idle"
		_play_cue(key,trigger)

func react_to_event(event_type: String,payload: Dictionary) -> void:
	_sync_puppets()
	match event_type:
		"prop_placed":
			if _puppets.has("felix"):_puppets.felix.play_state("place_prop",true)
			_play_cue("plum","interact")
		"prop_interacted","prop_removed":
			_play_cue("felix","interact");_play_cue("plum","interact")
		"method_exposed":
			_play_cue("felix","reveal");_play_cue("plum","reveal")
			for key in _puppets:
				if key.begins_with("entity:"):_play_cue(key,"reveal")
		"prop_blown","recoverable_failure":
			_play_cue("felix","suspect");_play_cue("plum","reveal")
		"route_completed":
			var id: String=payload.get("actor_id","")
			_play_cue("entity:"+id,"success")
			_play_cue("felix","success")
		"water_phase_changed":
			_play_cue("plum","suspect" if payload.get("phase","")=="frozen" else "accept")
		"witness_moved":_play_cue("witness:"+str(payload.get("witness_id","")),"move")

func play_actor(actor: String,animation: String) -> void:
	_sync_puppets()
	for key in _puppets:
		if key==actor or _puppets[key].get_meta("actor","")==actor:_puppets[key].play_state(animation,true)
func _environment(scene: String) -> Dictionary:
	if _environments.has(scene):return _environments[scene]
	var path: String="res://assets/art/environments/"+scene+"/layers.json"
	var data: Dictionary={}
	if FileAccess.file_exists(path):
		var parser=JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path))==OK and parser.data is Dictionary:data=parser.data
	var valid: bool=data.get("layers") is Array and data.layers.size()==5
	if valid:
		for layer in data.layers:
			if not layer is Dictionary or not layer.get("file") is String or layer.file.contains("..") or texture("res://assets/art/environments/"+scene+"/"+layer.file)==null:valid=false;break
	if not valid:data={}
	_environments[scene]=data
	return data
func _draw_environment(scene: String) -> void:
	var illustration: Texture2D=Art.texture_for("environments",scene)
	if illustration!=null:
		var factor: float=maxf(size.x/illustration.get_width(),size.y/illustration.get_height())
		var crop: Vector2=size/factor
		var source: Rect2=Rect2(Vector2((illustration.get_width()-crop.x)*.5,0),crop)
		draw_texture_rect_region(illustration,Rect2(Vector2.ZERO,size),source)
		return
	var data: Dictionary=_environment(scene)
	var landscape: Dictionary=data.get("landscape_background",{})
	if not landscape.is_empty():
		var plate: Texture2D=texture("res://assets/art/environments/"+scene+"/"+str(landscape.file))
		if plate!=null:
			# Preserve the distant architecture and sky. The projection below starts
			# below that horizon; the world is a scene rather than a cropped floor.
			var frame: Dictionary=_scene_frame(scene)
			draw_texture_rect_region(plate,Rect2(Vector2.ZERO,size),frame.region)
			return
	if not data.is_empty():
		# Full-canvas landscape layers share the exact same 3:2 play rectangle.
		# They all precede authoritative water, props, actors and witness eye pins.
		for layer in data.layers:
			var tex: Texture2D=texture("res://assets/art/environments/"+scene+"/"+layer.file)
			draw_texture_rect(tex,Rect2(Vector2.ZERO,size),false,Color(1,1,1,float(layer.get("opacity",1))))
		return
	var env_name: String={"ENV01":"bg_river","ENV02":"bg_kitchen","ENV03":"bg_archive"}.get(scene,"bg_river")
	var bg: Texture2D=texture("res://assets/art/environments/"+env_name+".png")
	if bg!=null:
		var fitted: Vector2=bg.get_size()*maxf(size.x/bg.get_width(),size.y/bg.get_height())
		draw_texture_rect(bg,Rect2((size-fitted)/2,fitted),false)
	else:draw_rect(Rect2(Vector2.ZERO,size),Color("dce5d1"))
func _scene_frame(scene: String) -> Dictionary:
	var data: Dictionary=_environment(scene)
	var landscape: Dictionary=data.get("landscape_background",{})
	var canvas: Array=data.get("canvas_size",[1536,1024])
	var source_size: Vector2=Vector2(float(canvas[0]),float(canvas[1]))
	var factor: float=maxf(size.x/source_size.x,size.y/source_size.y)
	var crop: Vector2=size/maxf(factor,.001)
	var floor_y: float=float(landscape.get("ground_source_y",400))*factor
	# Preserve the upper scene, but prevent wide-phone cover scaling from pushing
	# all playable floor below the screen. The same crop drives ground projection.
	var offset_y: float=clampf((floor_y-size.y*.56)/maxf(factor,.001),0,maxf(0,source_size.y-crop.y))
	return {"region":Rect2(Vector2((source_size.x-crop.x)*.5,offset_y),crop),"ground_y":floor_y-offset_y*factor}
func _play_horizon() -> float:
	if kernel!=null and Art.has_art("environments",str(kernel.definition.get("scene_id","ENV01"))):
		return size.y*lerpf(.58,.66,clampf((ui_text_scale-1.0)/.4,0,1))
	if kernel==null or kernel.state.is_empty():return size.y*.30
	var frame: Dictionary=_scene_frame(kernel.definition.get("scene_id","ENV01"))
	# The authored first audience row is grid y=3. Its visual feet must meet the
	# plate's actual floor, while the logical eye/ray anchors stay authoritative.
	var ground: float=float(frame.ground_y)+12
	var horizon: float=(ground-WITNESS_HEIGHT*.78-(size.y-68)*3.0/28.0)*28.0/25.0
	return clampf(horizon,size.y*.20,size.y*.48)
func _illustrated_stage() -> bool:
	return kernel!=null and not kernel.state.is_empty() and Art.has_art("environments",str(kernel.definition.get("scene_id","ENV01")))
func world(p: Array) -> Vector2:
	var horizon: float=_play_horizon()
	var margin: float=maxf(56,size.x*.05)
	var floor_bottom: float=size.y*.84 if _illustrated_stage() else size.y-68
	return Vector2(margin+float(p[0])*maxf(1,size.x-margin*2)/24.0,horizon+float(p[1])*maxf(1,floor_bottom-horizon)/28.0)
func unworld(point: Vector2) -> Vector2:
	# The editor uses the exact inverse of the presentation projection.
	var horizon: float=_play_horizon()
	var margin: float=maxf(56,size.x*.05)
	var floor_bottom: float=size.y*.84 if _illustrated_stage() else size.y-68
	return Vector2((point.x-margin)*24.0/maxf(1,size.x-margin*2),(point.y-horizon)*28.0/maxf(1,floor_bottom-horizon))
func _vec(p: Array) -> Vector2:return Vector2(float(p[0]),float(p[1]))
func texture(path: String) -> Texture2D:
	if not _textures.has(path):_textures[path]=load(path) if ResourceLoader.exists(path) else null
	return _textures[path]
func asset_path(entity_id: String) -> String:
	var d: Dictionary=kernel._entities[entity_id]
	var illustrated: Dictionary=Art.entry("props",str(d.asset_id),_prop_variant(entity_id))
	if not illustrated.is_empty():return str(illustrated.path)
	if d.asset_id=="CH09_RIG":return "res://assets/art/characters/caramelka.png"
	var stem: String=ASSETS.get(d.asset_id,"crate")
	var entity: Dictionary=kernel.state.entities[entity_id]
	if stem=="fire_source" and "M02" in kernel.state.active_laws:stem="fire_source_cold"
	if stem=="paper_bridge" and "M03" in kernel.state.active_laws:stem="paper_reinforced"
	if stem=="water_bowl":
		var zone: String=d.properties.get("thermal_subject_zone_id","")
		if kernel.state.get("zones",{}).get(zone,{}).get("phase","")=="frozen":stem="water_bowl_frozen"
	return "res://assets/art/props/"+stem+".png"

func _prop_variant(entity_id: String) -> String:
	var e: Dictionary=kernel.state.entities[entity_id]
	var d: Dictionary=kernel._entities[entity_id]
	if d.asset_id=="PROP_SCREEN" and bool(e.get("folded",false)):return "folded"
	if d.asset_id=="PROP_FIRE" and not bool(e.get("enabled",true)):return "off"
	if d.asset_id=="PROP_FIRE" and "M02" in kernel.state.active_laws:return "cold"
	if d.asset_id=="PROP_HEATED_STONE" and not bool(e.get("enabled",true)):return "cold"
	if d.asset_id=="PROP_PAPER_BRIDGE" and "M03" in kernel.state.active_laws:return "reinforced"
	if d.asset_id=="PROP_WATER_BOWL":
		var zone: String=str(d.properties.get("thermal_subject_zone_id",""))
		if kernel.state.get("zones",{}).get(zone,{}).get("phase","")=="frozen":return "frozen"
	return ""

func asset_texture(entity_id: String) -> Texture2D:
	var d: Dictionary=kernel._entities[entity_id]
	var actor: String=_entity_actor(entity_id)
	if not actor.is_empty():return Art.texture_for("characters",Art.actor_key(actor))
	var illustrated: Texture2D=Art.texture_for("props",str(d.asset_id),_prop_variant(entity_id))
	return illustrated if illustrated!=null else texture(asset_path(entity_id))

func _prop_rect(id: String,at: Vector2,height: float) -> Rect2:
	var paper_layout: Dictionary=_paper_layout(id)
	if not paper_layout.is_empty():return paper_layout.rect
	var frame_layout: Rect2=_paper_frame_layout(id)
	if frame_layout.has_area():return frame_layout
	var tex: Texture2D=asset_texture(id)
	if tex==null:return Rect2(at-Vector2(height*.5,height),Vector2.ONE*height)
	var base: Texture2D=Art.texture_for("props",str(kernel._entities[id].asset_id))
	var aspect: float=float(tex.get_width())/tex.get_height()
	if base!=null and kernel._entities[id].asset_id!="PROP_SCREEN":aspect=float(base.get_width())/base.get_height()
	var dimensions: Vector2=Vector2(height*aspect,height)
	var actor: String=_entity_actor(id)
	var data: Dictionary=Art.entry("characters",Art.actor_key(actor)) if not actor.is_empty() else Art.entry("props",str(kernel._entities[id].asset_id),_prop_variant(id))
	var values: Array=data.get("pivot",[.5,1.0])
	if actor.is_empty() and not _paper_under_load(id).is_empty():values=[.5,1.0]
	var shore: Dictionary=_shoreline_mount(id)
	if not shore.is_empty() and shore.direction.x!=0:
		# A fixed shoreline mount uses the bank edge as its attachment origin.
		# Its painted body extends into the dry side, never into the canal.
		values=[0.0 if shore.direction.x>0 else 1.0,float(values[1])]
	return Rect2(at-dimensions*Vector2(float(values[0]),float(values[1])),dimensions)

func _draw_illustrated_prop(id: String,at: Vector2,height: float) -> void:
	var tex: Texture2D=asset_texture(id)
	if tex!=null:draw_texture_rect(tex,_prop_rect(id,at,height),false)

func _terrain_art(key: String,rect: Rect2,opacity: float=1) -> void:
	var tex: Texture2D=Art.texture_for("props",key)
	if tex!=null:draw_texture_rect(tex,rect,false,Color(1,1,1,opacity))

func _shoreline_mount(id: String) -> Dictionary:
	var e: Dictionary=kernel.state.entities[id]
	var d: Dictionary=kernel._entities[id]
	if e.removed or d.type_id!="safety_thread" or kernel._slots[e.slot].mount_layer not in ["ground","surface"]:return {}
	var at: Vector2=world(e.position)
	if not kernel._position_over_water(e.position):return {"rect":Rect2(at-Vector2(125,52),Vector2(250,128)),"direction":Vector2.ZERO}
	# A boundary point counts as WATER in the kernel. Only a mounting that has
	# dry ground immediately beside it can acquire a shore-side footing. Never
	# put a platform around a source that is in the interior of the water zone.
	for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP]:
		var beside: Vector2=_vec(e.position)+direction*.01
		if kernel._position_over_water([beside.x,beside.y]):continue
		var rect: Rect2
		if direction==Vector2.RIGHT:rect=Rect2(at+Vector2(0,-52),Vector2(250,128))
		elif direction==Vector2.LEFT:rect=Rect2(at+Vector2(-250,-52),Vector2(250,128))
		elif direction==Vector2.DOWN:rect=Rect2(at+Vector2(-125,0),Vector2(250,128))
		else:rect=Rect2(at+Vector2(-125,-128),Vector2(250,128))
		return {"rect":rect,"direction":direction}
	return {}

func _draw_ground_supports(scene: String) -> void:
	# The baked canal illustration is only the distant setting. Small authored
	# dock/terrace cutouts put actual ground starts and route banks on a surface.
	# No support is painted through a water polygon or under a floating object.
	if scene!="ENV01":return
	for id in kernel.state.entities:
		var mount: Dictionary=_shoreline_mount(id)
		if not mount.is_empty():_terrain_art("SCENE_DOCK",mount.rect)
	var points: Array[Vector2]=[]
	for route in kernel.definition.get("navigation",{}).get("routes",[]):
		if route.nodes.is_empty():continue
		for edge in range(route.nodes.size()-1):
			var start: Dictionary=kernel._find(kernel.definition.navigation.nodes,route.nodes[edge])
			var finish: Dictionary=kernel._find(kernel.definition.navigation.nodes,route.nodes[edge+1])
			if start.is_empty() or finish.is_empty():continue
			var middle: Vector2=_vec(start.position).lerp(_vec(finish.position),.5)
			if kernel._position_over_water([middle.x,middle.y]):continue
			var first: Vector2=world(start.position);var last: Vector2=world(finish.position)
			var left: float=minf(first.x,last.x)-50
			var width: float=maxf(180,absf(first.x-last.x)+100)
			_terrain_art("SCENE_DOCK",Rect2(left,minf(first.y,last.y)-58,width,130+absf(first.y-last.y)))
		for node_id in [route.nodes[0],route.nodes[-1]]:
			var node: Dictionary=kernel._find(kernel.definition.navigation.nodes,node_id)
			if not node.is_empty() and not kernel._position_over_water(node.position):points.append(world(node.position))
	for id in kernel.state.entities:
		var e: Dictionary=kernel.state.entities[id]
		if e.removed or kernel._slots[e.slot].mount_layer!="ground" or kernel._position_over_water(e.position):continue
		points.append(_visual_position(id))
	for witness in kernel.definition.witnesses:
		if not _witness_entity(witness.id).is_empty():continue
		var eye: Vector2=kernel.witness_eye(witness.id)
		if not kernel._position_over_water([eye.x,eye.y]):points.append(world([eye.x,eye.y]))
	var placed: Array[Vector2]=[]
	for point in points:
		var covered: bool=false
		for prior in placed:
			if point.distance_to(prior)<95:covered=true;break
		if covered:continue
		placed.append(point)
		var width: float=clampf(size.x*.17,230,350)
		_terrain_art("SCENE_DOCK",Rect2(point-Vector2(width*.5,64),Vector2(width,142)))

func _draw_water_zone(zone: Dictionary) -> void:
	# Thermal subjects are not extra pools on the plaza. Bowl water is drawn
	# inside the bowl artwork, while bread/dessert zones track their contents.
	if zone.has("thermal_owner_entity_id"):return
	for entity_id in kernel._entities:
		var definition: Dictionary=kernel._entities[entity_id]
		if definition.asset_id=="PROP_WATER_BOWL" and definition.properties.get("thermal_subject_zone_id","")==zone.id:return
	var points: PackedVector2Array=[]
	for p in zone.polygon:points.append(world(p))
	if points.size()<3:return
	var frozen: bool=kernel.state.get("zones",{}).get(zone.id,{}).get("phase","")=="frozen"
	var bounds: Rect2=Rect2(points[0],Vector2.ZERO)
	for point in points:bounds=bounds.expand(point)
	if zone.id=="bowl_water":
		var bowl: Texture2D=Art.texture_for("props","PROP_WATER_BOWL","frozen" if frozen else "")
		if bowl!=null:
			var height: float=156
			var base_bowl: Texture2D=Art.texture_for("props","PROP_WATER_BOWL")
			var dimensions: Vector2=Vector2(height*base_bowl.get_width()/base_bowl.get_height(),height)
			var center: Vector2=bounds.get_center()
			_contact_shadow(center,dimensions.x*.27,.16)
			draw_texture_rect(bowl,Rect2(center-dimensions*Vector2(.5,.9),dimensions),false)
		return
	var surface: Texture2D=Art.texture_for("props","SCENE_ICE" if frozen else "SCENE_WATER")
	if surface!=null:
		# Sources have painted irregular alpha edges; geometry remains the exact
		# author polygon, with a quiet sight/placement outline only on inspection.
		draw_texture_rect(surface,bounds.grow(10),false,Color(1,1,1,.96))
	else:
		draw_colored_polygon(points,Color(.34,.75,.78,.18) if not frozen else Color(.70,.91,.94,.75))
	for i in range(4):
		var at: Vector2=Vector2(bounds.position.x+bounds.size.x*(.18+i*.19),bounds.position.y+bounds.size.y*(.32+fmod(i*.23,.48)))
		var reach: float=minf(46,bounds.size.x*.12)
		if frozen:
			draw_line(at-Vector2(reach*.4,5),at+Vector2(reach*.6,3),Color(.96,1,1,.8),2,true)
			draw_line(at,at+Vector2(5,12),Color(.96,1,1,.65),2,true)
		else:draw_arc(at,reach,.12,PI-.2,18,Color(.94,.99,.91,.45),2,true)
	if not selected.is_empty() or not inspected.is_empty():
		for i in range(points.size()):draw_dashed_line(points[i],points[(i+1)%points.size()],Color(.94,.99,.91,.52),2,12,true)

func _mooring_ends(id: String) -> Array:
	var d: Dictionary=kernel._entities[id]
	if d.properties.get("attachment_kind","")!="mooring":return []
	var target: String=str(kernel.state.entities[id].get("attachment_target",""))
	var owner: String=str(d.properties.get("mooring_owner_entity_id",""))
	if not kernel.state.entities.has(target) or not kernel.state.entities.has(owner):return []
	if kernel.state.entities[target].removed or kernel.state.entities[owner].removed:return []
	return [_visual_position(owner)-Vector2(0,_prop_height(owner)*.38),_visual_position(target)-Vector2(0,_prop_height(target)*.55)]

func _rope_points(first: Vector2,last: Vector2,taut: bool=false) -> PackedVector2Array:
	var line: PackedVector2Array=[]
	var sag: float=9 if taut else minf(42,first.distance_to(last)*.12)
	for i in range(25):
		var progress: float=float(i)/24
		line.append(first.lerp(last,progress)+Vector2(0,sin(progress*PI)*sag))
	return line

func _draw_rope(first: Vector2,last: Vector2,taut: bool=false,canvas: CanvasItem=null) -> void:
	var drawer: CanvasItem=self if canvas==null else canvas
	var line: PackedVector2Array=_rope_points(first,last,taut)
	drawer.draw_polyline(line,Color(.12,.10,.18,.24),11,true)
	drawer.draw_polyline(line,Color("b78246"),7,true)
	drawer.draw_polyline(line,Color("e6c58a"),3,true)
	for i in range(2,line.size()-2,3):
		var tangent: Vector2=(line[i+1]-line[i-1]).normalized()
		var across: Vector2=Vector2(-tangent.y,tangent.x)*3.5
		drawer.draw_line(line[i]-across-tangent*2,line[i]+across+tangent*2,Color("976336"),1.5,true)

func _draw_connections() -> void:
	for id in kernel.state.entities:
		if kernel.state.entities[id].removed:continue
		var thread: Array=_safety_thread_ends(id)
		if thread.size()==2:
			draw_line(thread[0]+Vector2(0,2),thread[1]+Vector2(0,2),Color(.12,.10,.18,.27),5,true)
			draw_line(thread[0],thread[1],CREAM,2.5,true)
		# Mooring is a foreground interaction layer, so its real endpoints remain
		# visible on the boat and bollard instead of disappearing behind props.
	for id in kernel.state.routes:
		var task: Dictionary=kernel.state.routes[id]
		if task.get("transport_mode","")!="towed" or task.completed:continue
		var carrier: String=str(task.carrier_id)
		_draw_rope(_visual_position(carrier)-Vector2(0,_hero_display_height()*.40),_visual_position(id)-Vector2(0,_prop_height(id)*.45),true)

func _safety_thread_ends(id: String) -> Array:
	var source: Dictionary=kernel.state.entities[id]
	var definition: Dictionary=kernel._entities[id]
	var target: String=str(definition.properties.get("supports_entity",""))
	if source.removed or definition.type_id!="safety_thread" or not kernel.state.entities.has(target) or not kernel._support_source_matches(id,target):return []
	var body: Rect2=_prop_rect(id,_visual_position(id),_prop_height(id))
	return [body.get_center()+Vector2(0,body.size.y*.15),_visual_position(target)-Vector2(0,_prop_height(target)*.22)]
func _art(path: String,pivot: Vector2,height: float,sway: float=0) -> bool:
	var tex: Texture2D=texture(path)
	if tex==null:return false
	var width: float=height*float(tex.get_width())/float(tex.get_height())
	draw_set_transform(pivot,sway)
	draw_texture_rect(tex,Rect2(-width/2,-height,width,height),false)
	draw_set_transform(Vector2.ZERO)
	return true
func _label(value: String,at: Vector2,font_size: int=24,color: Color=INK) -> void:draw_string(_font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
func _rounded(rect: Rect2,color: Color,radius: int=14) -> void:
	var style=StyleBoxFlat.new();style.bg_color=color;style.set_corner_radius_all(radius);draw_style_box(style,rect)
func _contact_shadow(at: Vector2,radius: float,strength: float=.13) -> void:
	# Cosmetic contact only. Never an occluder, collision body or hidden method.
	draw_set_transform(at+Vector2(5,3),0,Vector2(1,.27))
	for ring in range(3,0,-1):
		draw_circle(Vector2.ZERO,radius*(.62+ring*.16),Color(.07,.18,.23,strength/float(ring+1)))
	draw_set_transform(Vector2.ZERO)
func _prop_height(id: String) -> float:
	var definition: Dictionary=kernel._entities[id]
	var actor: String=_entity_actor(id)
	if not actor.is_empty():return _actor_height(actor,300)
	var paper_layout: Dictionary=_paper_layout(id)
	if not paper_layout.is_empty():return float(paper_layout.rect.size.y)
	var frame_layout: Rect2=_paper_frame_layout(id)
	if frame_layout.has_area():return frame_layout.size.y
	if definition.asset_id=="PROP_CLAMP" and not str(kernel.state.entities[id].get("attachment_target","")).is_empty():return 80
	if definition.material=="STONE":return {"S":104,"M":145,"L":175}.get(definition.properties.get("size","M"),145)
	if definition.apparent_class=="SCREEN":return 200 if bool(kernel.state.entities[id].get("folded",false)) else 270
	if definition.asset_id in ["PROP_FIRE","PROP_HOIST","PROP_TICKET_BOOTH"]:return 240
	if definition.asset_id=="PROP_FLOAT":return 88
	if definition.asset_id=="PROP_BOAT":return 185
	if definition.asset_id=="CH09_RIG":return 200
	if definition.asset_id=="PROP_CARGO_CRATE" and _shared_start_group(id,["PROP_CARGO_CRATE"]).size()>1:return 116
	return 156

func _placement_subject() -> String:
	if kernel==null or kernel.state.is_empty():return ""
	if selected.begins_with("w:") and placement_entity==selected:
		var witness: Dictionary=kernel._find(kernel.definition.witnesses,selected.trim_prefix("w:"))
		return selected if kernel.state.phase in ["PLAN_SHOW","PLAN_RESOLUTION","PROOF_ACCEPTED"] and witness.get("views",[]).size()==1 else ""
	if kernel.state.phase not in ["PLAN_SHOW","PLAN_RESOLUTION"]:return ""
	if kernel.state.entities.has(placement_entity) and kernel._entities[placement_entity].get("movable",false) and not kernel.state.entities[placement_entity].removed:return placement_entity
	return ""

func _placement_slots() -> Array:
	var result: Array=[]
	var subject: String=_placement_subject()
	if subject.is_empty():return result
	for slot in kernel.definition.slots:
		if slot.mount_layer=="tray":continue
		var valid: bool="witness" in slot.allowed_entity_types if subject.begins_with("w:") else kernel._entities[subject].type_id in slot.allowed_entity_types
		if valid:result.append(slot)
	return result

func _draw() -> void:
	_hits.clear()
	if kernel==null or kernel.state.is_empty():return
	var st: Dictionary=kernel.state
	var scene: String=kernel.definition.get("scene_id","ENV01")
	_draw_environment(scene)
	_draw_ground_supports(scene)
	for zone in kernel.definition.get("zones",[]):
		if zone.kind!="WATER" or not zone.has("polygon"):continue
		_draw_water_zone(zone)
	_draw_connections()
	# The marker hit area keeps the real slot position. Its drawing is deferred
	# until after puppets, so an occupied but compatible place remains visible.
	for slot in _placement_slots():
		var pos: Vector2=world(slot.position)
		_hits.append({"kind":"slot","id":slot.id,"rect":Rect2(pos-Vector2(72,72),Vector2(144,144))})
	var ids: Array=st.entities.keys()
	ids.sort_custom(func(a,b):
		var depth_a: float=world(st.entities[a].position).y
		var depth_b: float=world(st.entities[b].position).y
		return _prop_draw_priority(a)<_prop_draw_priority(b) if is_equal_approx(depth_a,depth_b) else depth_a<depth_b)
	for id in ids:
		var e: Dictionary=st.entities[id]
		var d: Dictionary=kernel._entities[id]
		if e.removed or id=="hero" or kernel._slots[e.slot].mount_layer=="tray":continue
		var pos: Vector2=_visual_position(id)
		var height: float=_prop_height(id)
		if d.apparent_class=="SCREEN":pos.y+=30
		elif d.asset_id=="PROP_FLOAT":pos.y+=32
		var rope_ends: Array=_mooring_ends(id)
		if rope_ends.size()==2:
			height=48;pos=(rope_ends[0]+rope_ends[1])*.5+Vector2(0,height*.4)
		if e.effective.get("buoyant",false) and kernel._position_over_water(e.position):pos.y+=sin(clock*2)*3
		if rope_ends.is_empty():_contact_shadow(Vector2(_prop_rect(id,pos,height).get_center().x,pos.y),height*.36,.09 if kernel._position_over_water(e.position) else .15)
		if not _puppets.has("entity:"+id) and rope_ends.is_empty():_draw_illustrated_prop(id,pos,height)
		if d.material=="STONE" and e.effective.get("buoyant",false) and kernel._position_over_water(e.position):
			# The new law has a persistent visible consequence, even with no debug
			# inspector: a quiet turquoise support ripple beneath the stone.
			draw_set_transform(pos+Vector2(0,12),0,Vector2(1,.24))
			draw_arc(Vector2.ZERO,height*.69,0,TAU,48,Color(.73,.97,.92,.65),5,true)
			draw_set_transform(Vector2.ZERO)
		if d.material=="PAPER" and "M03" in st.active_laws:
			var paper_rect: Rect2=_prop_rect(id,pos,height)
			draw_line(paper_rect.position+Vector2(12,paper_rect.size.y*.8),paper_rect.end-Vector2(12,paper_rect.size.y*.2),Color(.97,.84,.38,.8),4,true)
		if not e.get("intact",true):
			draw_line(pos-Vector2(25,60),pos+Vector2(25,-10),Color("a84148"),5,true)
		var body_rect: Rect2=_prop_rect(id,pos,height)
		var hit_width: float=maxf(144,body_rect.size.x)
		var hit_size: Vector2=Vector2(hit_width,maxf(144,height+35))
		var hit_center: Vector2=body_rect.get_center()
		var target: Dictionary={"kind":"entity","id":id,"rect":Rect2(hit_center-hit_size/2,hit_size),"anchor":hit_center,"body_rect":body_rect}
		if rope_ends.size()==2:
			var owner: String=str(d.properties.get("mooring_owner_entity_id",""))
			target.polyline=_rope_points(rope_ends[0],rope_ends[1],bool(st.entities[owner].get("moored",false)))
			var line_bounds: Rect2=Rect2(rope_ends[0],Vector2.ZERO).expand(rope_ends[1]).grow(72)
			target.rect=line_bounds
		_hits.append(target)
	# Eye anchors remain true; generous cards below the stage select the same witness.
	for i in range(kernel.definition.witnesses.size()):
		var wd: Dictionary=kernel.definition.witnesses[i]
		var w: Dictionary=st.witnesses[wd.id]
		var eye: Vector2=kernel.witness_eye(wd.id)
		var pos: Vector2=witness_display_position(wd.id)
		var entity_id: String=_witness_entity(wd.id)
		if entity_id.is_empty():_contact_shadow(pos,WITNESS_HEIGHT*.3,.12)
		if entity_id.is_empty() and not _puppets.has("witness:"+wd.id):
			var actor: String=CHARACTERS.get(wd.character_id,"")
			if not actor.is_empty():_art("res://assets/art/characters/"+actor+".png",pos+Vector2(0,WITNESS_HEIGHT*.78),WITNESS_HEIGHT)
		var color: Color=Color("276b5c") if w.eligible_vote else (Color("a84148") if w.exposed else CREAM)
		var body_height: float=_prop_height(entity_id) if not entity_id.is_empty() else _actor_height(str(CHARACTERS.get(wd.character_id,"")),WITNESS_HEIGHT)
		var badge: Vector2=pos-Vector2(0,body_height+28)
		if inspected==wd.id or selected=="w:"+wd.id:
			draw_circle(badge+Vector2(0,3),25,Color(.15,.14,.23,.2));draw_circle(badge,23,color)
			_label(str(i+1),badge+Vector2(-10,12),32,CREAM if w.eligible_vote or w.exposed else INK)
		var observer_anchor: Vector2=world([eye.x,eye.y])
		var face: Vector2=pos-Vector2(0,body_height*.84)
		_hits.append({"kind":"witness","id":wd.id,"rect":Rect2(face-Vector2(72,72),Vector2(144,144)),"anchor":observer_anchor,"pick_anchor":face})
	var hero_pos: Vector2=_visual_position("hero")
	var hero_height: float=_hero_display_height()
	_contact_shadow(hero_pos,hero_height*.28,.16)
	if not _puppets.has("felix"):_art("res://assets/art/characters/felix.png",hero_pos,hero_height,sin(clock*2.1)*.012)
	if not _puppets.has("plum"):_art("res://assets/art/characters/plum.png",hero_pos+Vector2(hero_height*.73,-hero_height*.59+sin(clock*3)*hero_height*.04),hero_height*.364,sin(clock*5)*.09)
	# The Atlas is a physical object beside the professor, linking the separate
	# 'make law' action to the source of the transformation.
	var atlas: Texture2D=Art.texture_for("props","ATLAS")
	if atlas!=null:
		var atlas_size: Vector2=Vector2(128,100)
		var atlas_at: Vector2=hero_pos+Vector2(-hero_height*.39,-14)
		_contact_shadow(atlas_at+Vector2(0,30),42,.12)
		draw_texture_rect(atlas,Rect2(atlas_at-atlas_size*.5,atlas_size),false)
	if not inspected.is_empty() and st.witnesses.has(inspected) and st.phase in ["PLAN_SHOW","PERFORMANCE","REHEARSAL","PROOF_ACCEPTED"]:
		var diagnostics: Dictionary=kernel.visibility_for(inspected)
		for ray in diagnostics.rays:
			var color: Color=Color(.15,.5,.35,.75) if ray.visible else Color(.66,.25,.29,.6)
			if ray.method and not ray.visible:color=Color(.36,.26,.65,.55)
			draw_line(world(ray.from),world(ray.to),color,3,true);draw_circle(world(ray.to),7,color)
		# Diagnostic text belongs to the measured HUD component. Only the genuine
		# viewing rays stay on the world; no fixed label can hide under the HUD.

func _entity_label(id: String) -> String:
	var type_id: String=str(kernel._entities[id].type_id)
	var fallback: String=_t("entity."+id+".name",_t("prop."+type_id+".name",type_id))
	return _t("level."+str(kernel.state.get("level_id",""))+".entity."+id+".name",fallback)

func _selection_label_layout() -> Dictionary:
	if kernel==null or not kernel.state.get("entities",{}).has(selected):return {}
	var entity: Dictionary=kernel.state.entities[selected]
	if entity.removed or kernel._slots[entity.slot].mount_layer=="tray":return {}
	var target: Dictionary={}
	for item in _hits:
		if item.kind=="entity" and item.id==selected:target=item;break
	if target.is_empty():return {}
	var text: String=_entity_label(selected)
	if placement_entity==selected:text=_t("ui.placing_prop","Разместить: {name}").format({"name":text})
	var definition: Dictionary=kernel._entities[selected]
	if definition.material=="STONE" and definition.properties.has("size"):
		text+=" · "+_t("stage.load","Вмещает: {capacity}").format({"capacity":int(entity.effective.get("carry_capacity",0))})
	var font_size: int=int(38*clampf(ui_text_scale,1,1.4))
	var height: float=font_size+28
	var width: float=minf(size.x-48,_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x+40)
	var body: Rect2=target.body_rect
	var left: float=clampf(body.get_center().x-width*.5,24,maxf(24,size.x-width-24))
	var minimum_y: float=minf(maxf(12,hud_safe_top+12),size.y-height-184)
	var top: float=clampf(body.position.y-height-14,minimum_y,maxf(minimum_y,size.y-height-184))
	return {"id":selected,"text":text,"rect":Rect2(left,top,width,height),"body_rect":body,"font_size":font_size}

func _draw_interaction_overlay() -> void:
	if kernel==null or kernel.state.is_empty():return
	for id in kernel.state.entities:
		if kernel.state.entities[id].removed:continue
		var ends: Array=_mooring_ends(id)
		if ends.size()!=2:continue
		var owner: String=str(kernel._entities[id].properties.get("mooring_owner_entity_id",""))
		var taut: bool=bool(kernel.state.entities[owner].get("moored",false))
		_draw_rope(ends[0],ends[1],taut,_capacity_overlay)
		if taut or selected in [id,owner,str(kernel.state.entities[id].get("attachment_target",""))]:
			for point in ends:
				_capacity_overlay.draw_circle(point,13,CREAM)
				_capacity_overlay.draw_circle(point,8,PURPLE)
	for slot in _placement_slots():
		var at: Vector2=world(slot.position)
		_capacity_overlay.draw_circle(at,42,Color("252647"))
		_capacity_overlay.draw_circle(at,36,CREAM)
		_capacity_overlay.draw_arc(at,36,0,TAU,48,PURPLE,5,true)
		_capacity_overlay.draw_circle(at,10,Color("f7d760"))
	var label: Dictionary=_selection_label_layout()
	if label.is_empty():return
	var outline=StyleBoxFlat.new();outline.bg_color=Color(0,0,0,0);outline.border_color=CREAM;outline.set_border_width_all(7);outline.set_corner_radius_all(18)
	_capacity_overlay.draw_style_box(outline,label.body_rect.grow(8))
	outline.border_color=PURPLE;outline.set_border_width_all(3)
	_capacity_overlay.draw_style_box(outline,label.body_rect.grow(8))
	var panel=StyleBoxFlat.new();panel.bg_color=CREAM;panel.border_color=PURPLE;panel.set_border_width_all(2);panel.set_corner_radius_all(16)
	_capacity_overlay.draw_style_box(panel,label.rect)
	_capacity_overlay.draw_string(_font,label.rect.position+Vector2(20,int(label.font_size)+5),label.text,HORIZONTAL_ALIGNMENT_LEFT,label.rect.size.x-40,int(label.font_size),INK)

func _capacity_badge_layout() -> Array:
	# Labels are a presentation pass: never relocate props or their input anchors.
	var badges: Array=[]
	if kernel==null or kernel.state.is_empty():return badges
	var ids: Array=kernel.state.entities.keys();ids.sort()
	for id in ids:
		var entity: Dictionary=kernel.state.entities[id]
		var definition: Dictionary=kernel._entities[id]
		if entity.removed or kernel._slots[entity.slot].mount_layer=="tray" or definition.material!="STONE" or not definition.properties.has("size"):continue
		if selected==id and not _selection_label_layout().is_empty():continue # The selected name already includes its real capacity.
		if not show_capacity and selected!=id and inspected!=id:continue
		var pos: Vector2=_visual_position(id)
		var height: float=_prop_height(id)
		if entity.effective.get("buoyant",false) and kernel._position_over_water(entity.position):pos.y+=sin(clock*2)*3
		var value: String=_t("stage.load","Вмещает: {capacity}").format({"capacity":int(entity.effective.get("carry_capacity",0))})
		var extent: Vector2=Vector2(_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,42).x+32,64)
		var desired: Vector2=pos-Vector2(extent.x/2,height+72)
		var rect: Rect2=Rect2(Vector2(clampf(desired.x,6,maxf(6,size.x-extent.x-6)),clampf(desired.y,6,maxf(6,size.y-extent.y-6))),extent)
		var origin: Vector2=rect.position
		# Stable vertical lanes preserve each label's horizontal link to its stone.
		# Try the nearest free lane first, above then below the preferred position.
		for lane in range(kernel.state.entities.size()+1):
			var found: bool=false
			for direction in [-1,1]:
				var candidate: Rect2=Rect2(origin+Vector2(0,lane*76*direction),extent)
				if candidate.position.y<6 or candidate.end.y>size.y-6:continue
				var free: bool=true
				for prior in badges:
					if candidate.grow(4).intersects(prior.rect):free=false;break
				if free:rect=candidate;found=true;break
			if found:break
		badges.append({"id":id,"text":value,"rect":rect,"anchor":pos-Vector2(0,height*.8)})
	return badges
func _draw_capacity_badges() -> void:
	var badges: Array=_capacity_badge_layout()
	# Lines precede every badge, so another label never loses digits to a leader.
	for badge in badges:
		var rect: Rect2=badge.rect
		var anchor: Vector2=badge.anchor
		var edge: Vector2=Vector2(clampf(anchor.x,rect.position.x+8,rect.end.x-8),clampf(anchor.y,rect.position.y+8,rect.end.y-8))
		_capacity_overlay.draw_line(anchor,edge,CREAM,5,true)
		_capacity_overlay.draw_line(anchor,edge,INK,2,true)
	for badge in badges:
		var style=StyleBoxFlat.new();style.bg_color=CREAM;style.set_corner_radius_all(18)
		style.shadow_color=Color(.15,.14,.28,.15);style.shadow_size=4;style.shadow_offset=Vector2(0,4)
		_capacity_overlay.draw_style_box(style,badge.rect)
		_capacity_overlay.draw_string(_font,badge.rect.position+Vector2(16,47),badge.text,HORIZONTAL_ALIGNMENT_LEFT,-1,42,INK)
func _sample_presentation(delta: float) -> void:
	if kernel==null or kernel.state.is_empty():
		_route_frames.clear();_render_tick=-1;_render_phase="";_route_signature="";_tick_elapsed=.1;return
	var signature: String=str(kernel.get_instance_id())+":"+str(kernel.state.get("content_digest",""))
	var tick: int=int(kernel.state.tick);var phase: String=kernel.state.phase
	if phase!="RUN_RESOLUTION":
		_route_frames.clear();_tick_elapsed=.1
	elif signature!=_route_signature or phase!=_render_phase or tick!=_render_tick or _route_frames.size()!=kernel.state.routes.size():
		var next: Dictionary={}
		for id in kernel.state.routes:
			var task: Dictionary=kernel.state.routes[id]
			var current: int=int(task.progress);var previous: int=current
			var old: Dictionary=_route_frames.get(id,{})
			var continuous: bool=signature==_route_signature and _render_phase==phase and tick==_render_tick+1 and old.get("route_id","")==task.route_id and str(task.get("waiting_for","")).is_empty() and not task.completed
			if continuous:previous=int(old.get("current",current))
			next[id]={"route_id":task.route_id,"previous":previous,"current":current,"waiting":str(task.get("waiting_for",""))}
		_route_frames=next;_tick_elapsed=0
	else:_tick_elapsed=minf(.1,_tick_elapsed+maxf(delta,0))
	_route_signature=signature;_render_tick=tick;_render_phase=phase
func _entity_position(entity_id: String,render_alpha: float=-1) -> Vector2:
	var pos: Vector2=world(kernel.state.entities[entity_id].position)
	for actor_id in kernel.state.routes:
		var task: Dictionary=kernel.state.routes[actor_id]
		if actor_id==entity_id or (task.carrier_id==entity_id and task.get("transport_mode","")!="towed"):
			pos=_route_position(task,actor_id,render_alpha)
		elif entity_id in kernel._entities[actor_id].properties.get("payload_entity_ids",[]):pos=_route_position(task,actor_id,render_alpha)+Vector2(0,-70)
	return pos
func _route_position(task: Dictionary,actor_id: String="",render_alpha: float=-1) -> Vector2:
	var route: Dictionary=kernel._find(kernel.definition.navigation.routes,task.route_id)
	var edge_ticks: int=int(route.get("ticks_per_edge",10))
	var progress: float=float(task.progress)
	var frame: Dictionary=_route_frames.get(actor_id,{})
	if not frame.is_empty() and frame.route_id==task.route_id and int(frame.current)==int(task.progress) and kernel.state.phase=="RUN_RESOLUTION":
		var alpha: float=clampf(render_alpha if render_alpha>=0 else _tick_elapsed/.1,0,1)
		progress=lerpf(float(frame.previous),float(frame.current),alpha)
	var segment: int=mini(int(progress/edge_ticks),route.nodes.size()-1)
	var from: Array=kernel._find(kernel.definition.navigation.nodes,route.nodes[segment]).position
	var to: Array=kernel._find(kernel.definition.navigation.nodes,route.nodes[mini(segment+1,route.nodes.size()-1)]).position
	return world(from).lerp(world(to),fmod(progress,float(edge_ticks))/edge_ticks)
func _notification(what: int) -> void:
	if what==NOTIFICATION_SCROLL_BEGIN:_tap_cancelled=true

func _painted_hit(target: Dictionary,position: Vector2) -> bool:
	if target.has("polyline"):
		var line: PackedVector2Array=target.polyline
		for index in range(line.size()-1):
			if Geometry2D.get_closest_point_to_segment(position,line[index],line[index+1]).distance_to(position)<=18:return true
		return false
	var body: Rect2=target.get("body_rect",target.rect)
	if not body.has_point(position):return false
	if target.kind!="entity":return true
	# A visible hull beats a neighbouring rope's invisible enlarged touch area.
	# Transparent corners are not painted ownership; the full 144px target is
	# still used below when no actual silhouette occupies the tapped point.
	var id: String=str(target.id)
	var key: String=str(kernel._entities[id].asset_id)+":"+_prop_variant(id)
	if not _pick_images.has(key):
		var tex: Texture2D=asset_texture(id)
		var image: Image=tex.get_image() if tex!=null else null
		if image!=null and image.is_compressed() and image.decompress()!=OK:image=null
		_pick_images[key]=image
	var picture: Image=_pick_images[key]
	if picture==null or picture.is_empty():return true
	var uv: Vector2=(position-body.position)/body.size
	return picture.get_pixel(clampi(int(uv.x*picture.get_width()),0,picture.get_width()-1),clampi(int(uv.y*picture.get_height()),0,picture.get_height()-1)).a>.12

func _target_at(position: Vector2) -> Dictionary:
	var nearest: Dictionary={};var distance: float=INF
	# Mode can change between two rendered frames. Derive current slot targets
	# from the current explicit subject, never from a stale previous selection.
	var subject: String=_placement_subject()
	for slot in _placement_slots():
		var center: Vector2=world(slot.position)
		var rect: Rect2=Rect2(center-Vector2(72,72),Vector2(144,144))
		if rect.has_point(position):
			var d: float=center.distance_squared_to(position)
			if d<distance:nearest={"kind":"slot","id":slot.id,"rect":rect};distance=d
	if not nearest.is_empty():return nearest
	if not subject.is_empty():return {"kind":"placement_invalid","id":subject}
	# Prefer actual ink to an expanded neighbour. Where two silhouettes really
	# overlap, the nearest painted center wins; ties keep the frontmost target.
	for i in range(_hits.size()-1,-1,-1):
		var target: Dictionary=_hits[i]
		if target.kind=="slot" or not _painted_hit(target,position):continue
		var d: float=target.get("pick_anchor",target.get("anchor",target.rect.get_center())).distance_squared_to(position)
		if d<distance:nearest=target;distance=d
	if not nearest.is_empty():return nearest
	for i in range(_hits.size()-1,-1,-1):
		var target: Dictionary=_hits[i]
		if target.kind=="slot" or not target.rect.has_point(position):continue
		var d: float=target.get("pick_anchor",target.get("anchor",target.rect.get_center())).distance_squared_to(position)
		if d<distance:nearest=target;distance=d # Equal-distance ties keep the visually frontmost target.
	return nearest
func _gui_input(event: InputEvent) -> void:
	# Release commits a tap. Press/motion bubble to the containing ScrollContainer,
	# whose native scroll-begin notification cancels taps and descendant buttons.
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pointer_active=true;_pointer_origin=event.position;_tap_cancelled=false;_pressed_target=_target_at(event.position)
		else:
			var activate: bool=_pointer_active and not _tap_cancelled and not event.canceled and _pointer_origin.distance_to(event.position)<=20 and not _pressed_target.is_empty()
			_pointer_active=false
			if activate:target_tapped.emit(_pressed_target.kind,_pressed_target.id)
	elif event is InputEventMouseMotion and _pointer_active and _pointer_origin.distance_to(event.position)>20:_tap_cancelled=true

func _t(key: String,fallback: String) -> String:
	return translator.call(key,fallback) if translator.is_valid() else fallback
