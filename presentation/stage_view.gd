class_name StageView
extends Control
const Puppet=preload("res://presentation/character_puppet.gd")
const ThemeKit=preload("res://presentation/theme.gd")
signal target_tapped(kind: String,id: String)
var kernel: RefCounted
var translator: Callable
var selected: String=""
var inspected: String=""
var reduced_motion: bool=false
var clock: float=0
var _textures: Dictionary={}
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
const WITNESS_HEIGHT: float=112.0
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
const INK=Color("173046")
const CREAM=Color("fffcf4")
const PURPLE=Color("167a91")
const ASSETS={"PROP_STONE_M":"stone","PROP_STONE_L":"stone","PROP_STONE_S":"stone","PROP_FLOAT":"float","PROP_SCREEN":"screen","PROP_CARGO_CRATE":"crate","PROP_TICKET_BOOTH":"ticket_booth","PROP_ANCHOR":"span_anchor","PROP_STONE_ANCHOR":"stone_anchor","PROP_BOLLARD":"wooden_bollard","PROP_BOAT":"boat","PROP_ROPE":"rope","PROP_THREAD":"thread","PROP_CLAMP":"clamp","PROP_COLD_PACK":"cryopack","PROP_DECOY_FLAME":"decoy_fire","PROP_FIRE":"fire_source","PROP_WATER_BOWL":"water_bowl","PROP_HEATED_STONE":"hot_stone","PROP_INSULATED_BOX":"thermobox","PROP_BREAD":"bread","PROP_DESSERT":"dessert","PROP_HIDDEN_FRAME":"frame","PROP_PAPER_BRIDGE":"paper_bridge","PROP_CONTROL_WEIGHT":"control_weight","PROP_HOIST":"hoist","PROP_PAPER_WALL":"paper_gate","PROP_GATE":"wood_gate","PROP_FLAGS":"flags","PROP_STEAM":"steam","PROP_POSTER":"poster"}
const CHARACTERS={"CH01":"felix","CH02":"plum","CH03":"marfa","CH04":"semyon","CH05":"nika","CH06":"lada","CH07":"roza","CH08":"hugo","CH09":"caramelka","CROWD01":"crowd_gardener","CROWD02":"crowd_postwoman","CROWD03":"crowd_fisherman","CROWD04":"crowd_librarian","CROWD05":"crowd_merchant","CROWD06":"crowd_musician"}
func _ready() -> void:
	mouse_filter=MOUSE_FILTER_PASS;clip_contents=true;texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
	_capacity_overlay=Node2D.new();_capacity_overlay.name="CapacityBadges";add_child(_capacity_overlay)
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
	if _puppets.has(key):
		if _puppets[key].get_meta("actor","")==actor:return
		_puppets[key].visible=false;_puppets[key].queue_free();_puppets.erase(key)
	var puppet=Puppet.new();puppet.name="Puppet_"+key.replace(":","_");add_child(puppet)
	if puppet.configure(actor,height) and puppet.rigged:
		puppet.set_meta("actor",actor);_puppets[key]=puppet
	else:puppet.queue_free() # Pending actors retain their explicit painted baseline.
func _route_motion(entity_id: String) -> Dictionary:
	var result: Dictionary={"moving":false,"facing":1,"waiting":false}
	for actor_id in kernel.state.routes:
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
	var normal: float=minf(260,size.y*.4)
	if kernel!=null and not kernel.state.is_empty() and _shared_start_group("hero",["CH01_RIG","CH09_RIG"]).size()>1:return minf(normal,170)
	return normal
func _visual_position(id: String) -> Vector2:
	var exact: Vector2=_entity_position(id)
	var definition: Dictionary=kernel._entities[id]
	var offset: Vector2=Vector2.ZERO
	if definition.asset_id in ["CH01_RIG","CH09_RIG"] and _shared_start_group(id,["CH01_RIG","CH09_RIG"]).size()>1:
		offset=Vector2(-72,-6) if definition.asset_id=="CH01_RIG" else Vector2(58,-6)
	elif definition.asset_id=="PROP_CARGO_CRATE":
		var group: Array=_shared_start_group(id,["PROP_CARGO_CRATE"])
		if group.size()>1:offset=Vector2((group.find(id)-(group.size()-1)*.5)*108,18)
	if offset==Vector2.ZERO:return exact
	# Arrange coincident painted silhouettes around the same logical start point.
	# The offset eases away as a confirmed route leaves that point; geometry,
	# witness rays, supports, slots and the kernel remain completely unchanged.
	var start: Vector2=world(kernel._slots[definition.initial_slot].position)
	var weight: float=1.0-clampf(exact.distance_to(start)/80.0,0,1)
	return exact+offset*weight

func _sync_puppets() -> void:
	if kernel==null or kernel.state.is_empty():
		for puppet in _puppets.values():puppet.visible=false
		return
	var signature: String=str(kernel.get_instance_id())+":"+str(kernel.state.get("content_digest",""))
	var height: float=_hero_display_height()
	_ensure_puppet("felix","felix",height);_ensure_puppet("plum","plum",height*.364)
	var wanted: Array=["felix","plum"]
	for witness in kernel.definition.witnesses:
		var actor: String=CHARACTERS.get(witness.character_id,"")
		if actor in ["marfa","semyon","nika","lada","roza","hugo"]:
			var key: String="witness:"+witness.id;wanted.append(key);_ensure_puppet(key,actor,WITNESS_HEIGHT)
	for id in kernel.state.entities:
		if kernel._entities[id].asset_id=="CH09_RIG":
			var key: String="entity:"+id;wanted.append(key);_ensure_puppet(key,"caramelka",144)
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
			puppet.set_display_height(height*.364);puppet.position+=Vector2(height*.73,-height*.59+sin(clock*3)*height*.04)
			loop="fly" if motion.moving else ("cheer" if kernel.state.phase=="SUCCESS" else "hover")
		else:
			puppet.set_display_height(144)
			if motion.moving:loop="walk"
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
	puppet.set_display_height(WITNESS_HEIGHT);puppet.set_reduced_motion(reduced_motion)
	# This is a drawing offset only. Sight rays still use kernel.witness_eye exactly.
	puppet.position=world([eye.x,eye.y])+Vector2(0,WITNESS_HEIGHT*.78)
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
	if kernel==null or kernel.state.is_empty():return size.y*.30
	var frame: Dictionary=_scene_frame(kernel.definition.get("scene_id","ENV01"))
	# The authored first audience row is grid y=3. Its visual feet must meet the
	# plate's actual floor, while the logical eye/ray anchors stay authoritative.
	var ground: float=float(frame.ground_y)+12
	var horizon: float=(ground-WITNESS_HEIGHT*.78-(size.y-68)*3.0/28.0)*28.0/25.0
	return clampf(horizon,size.y*.20,size.y*.48)
func world(p: Array) -> Vector2:
	var horizon: float=_play_horizon()
	return Vector2(56+float(p[0])*maxf(1,size.x-112)/24.0,horizon+float(p[1])*maxf(1,size.y-horizon-68)/28.0)
func unworld(point: Vector2) -> Vector2:
	# The editor uses the exact inverse of the presentation projection.
	var horizon: float=_play_horizon()
	return Vector2((point.x-56)*24.0/maxf(1,size.x-112),(point.y-horizon)*28.0/maxf(1,size.y-horizon-68))
func _vec(p: Array) -> Vector2:return Vector2(float(p[0]),float(p[1]))
func texture(path: String) -> Texture2D:
	if not _textures.has(path):_textures[path]=load(path) if ResourceLoader.exists(path) else null
	return _textures[path]
func asset_path(entity_id: String) -> String:
	var d: Dictionary=kernel._entities[entity_id]
	if d.asset_id=="CH09_RIG":return "res://assets/art/characters/caramelka.png"
	var stem: String=ASSETS.get(d.asset_id,"crate")
	var entity: Dictionary=kernel.state.entities[entity_id]
	if stem=="fire_source" and "M02" in kernel.state.active_laws:stem="fire_source_cold"
	if stem=="paper_bridge" and "M03" in kernel.state.active_laws:stem="paper_reinforced"
	if stem=="water_bowl":
		var zone: String=d.properties.get("thermal_subject_zone_id","")
		if kernel.state.get("zones",{}).get(zone,{}).get("phase","")=="frozen":stem="water_bowl_frozen"
	return "res://assets/art/props/"+stem+".png"
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
	if definition.material=="STONE":return {"S":80,"M":114,"L":140}.get(definition.properties.get("size","M"),114)
	if definition.apparent_class=="SCREEN" or definition.asset_id in ["PROP_FIRE","PROP_HOIST","PROP_TICKET_BOOTH"]:return 180
	if definition.asset_id=="PROP_FLOAT":return 65
	if definition.asset_id=="CH09_RIG":return 144
	if definition.asset_id=="PROP_CARGO_CRATE" and _shared_start_group(id,["PROP_CARGO_CRATE"]).size()>1:return 86
	return 115
func _draw() -> void:
	_hits.clear()
	if kernel==null or kernel.state.is_empty():return
	var st: Dictionary=kernel.state
	var scene: String=kernel.definition.get("scene_id","ENV01")
	_draw_environment(scene)
	var overlay: Texture2D=texture("res://assets/art/scenes/"+str(st.get("level_id",""))+"/overlay.png")
	# Chapter plates supply the cohesive diorama. Authored level accents remain a
	# subtle foreground layer, rather than covering the playable area with a frame.
	if overlay!=null:draw_texture_rect(overlay,Rect2(Vector2.ZERO,size),false,Color(1,1,1,.24))
	for zone in kernel.definition.get("zones",[]):
		if zone.kind!="WATER" or not zone.has("polygon"):continue
		var points: PackedVector2Array=[]
		for p in zone.polygon:points.append(world(p))
		var frozen: bool=st.get("zones",{}).get(zone.id,{}).get("phase","")=="frozen"
		var surface: Texture2D=texture("res://assets/art/props/"+("ice_surface" if frozen else "water_surface")+".png")
		var uv: PackedVector2Array=[]
		for point in points:uv.append(point/700.0)
		draw_colored_polygon(points,Color("b6e9f1") if frozen else Color("3bb7ce"))
		if surface!=null:draw_polygon(points,PackedColorArray([Color(1,1,1,.42)]),uv,surface)
		var rim: PackedVector2Array=points.duplicate();rim.append(points[0])
		draw_polyline(rim,Color(.08,.34,.42,.38),12,true)
		draw_polyline(rim,Color(.92,.98,.94,.92),6,true)
		draw_polyline(rim,Color(.30,.75,.84,.85),2,true)
		if not selected.is_empty() or not inspected.is_empty():
			for i in range(points.size()):draw_dashed_line(points[i],points[(i+1)%points.size()],Color(.84,.96,.91,.65),2,12,true)
		for i in range(3):
			var at: Vector2=points[0]+Vector2(26+i*51,28+i*35)
			draw_line(at,at+Vector2(29+sin(clock+i)*5,0),Color(.82,.95,.94,.65),3,true)
	# Slots preserve the exact geometry used by visibility and navigation.
	for slot in kernel.definition.slots:
		if slot.mount_layer=="tray":continue
		var valid: bool=false
		if selected.begins_with("w:"):valid="witness" in slot.allowed_entity_types
		elif st.entities.has(selected):valid=kernel._entities[selected].type_id in slot.allowed_entity_types and not st.entities[selected].removed
		if valid:
			var pos: Vector2=world(slot.position)
			draw_circle(pos,40,Color(.94,.98,.98,.8))
			draw_arc(pos,40,0,TAU,48,PURPLE,4,true)
			draw_circle(pos,10,Color("f1b44c"))
			_hits.append({"kind":"slot","id":slot.id,"rect":Rect2(pos-Vector2(72,72),Vector2(144,144))})
	var ids: Array=st.entities.keys()
	ids.sort_custom(func(a,b):return world(st.entities[a].position).y<world(st.entities[b].position).y)
	for id in ids:
		var e: Dictionary=st.entities[id]
		var d: Dictionary=kernel._entities[id]
		if e.removed or id=="hero" or kernel._slots[e.slot].mount_layer=="tray":continue
		var pos: Vector2=_visual_position(id)
		var height: float=_prop_height(id)
		if d.apparent_class=="SCREEN":pos.y+=60
		elif d.asset_id=="PROP_FLOAT":pos.y+=22
		if e.effective.get("buoyant",false) and kernel._position_over_water(e.position):pos.y+=sin(clock*2)*3
		_contact_shadow(pos,height*.36,.09 if kernel._position_over_water(e.position) else .15)
		if not _puppets.has("entity:"+id):_art(asset_path(id),pos,height,sin(clock*2)*.01 if d.asset_id=="CH09_RIG" else 0)
		if not e.get("intact",true):
			draw_line(pos-Vector2(25,60),pos+Vector2(25,-10),Color("a84148"),5,true)
		if selected==id:
			draw_arc(pos,54,0,TAU,48,CREAM,10,true)
			draw_arc(pos,54,0,TAU,48,PURPLE,5,true)
		var hit_width: float=144
		var hit_texture: Texture2D=texture(asset_path(id))
		if hit_texture!=null:hit_width=maxf(144,height*float(hit_texture.get_width())/hit_texture.get_height())
		var hit_size: Vector2=Vector2(hit_width,maxf(144,height+35))
		var hit_center: Vector2=pos-Vector2(0,height*.5)
		_hits.append({"kind":"entity","id":id,"rect":Rect2(hit_center-hit_size/2,hit_size),"anchor":hit_center})
	# Eye anchors remain true; generous cards below the stage select the same witness.
	for i in range(kernel.definition.witnesses.size()):
		var wd: Dictionary=kernel.definition.witnesses[i]
		var w: Dictionary=st.witnesses[wd.id]
		var eye: Vector2=kernel.witness_eye(wd.id)
		var pos: Vector2=world([eye.x,eye.y])
		_contact_shadow(pos+Vector2(0,WITNESS_HEIGHT*.78),WITNESS_HEIGHT*.3,.12)
		if not _puppets.has("witness:"+wd.id):
			var actor: String=CHARACTERS.get(wd.character_id,"")
			if not actor.is_empty():_art("res://assets/art/characters/"+actor+".png",pos+Vector2(0,WITNESS_HEIGHT*.78),WITNESS_HEIGHT)
		var color: Color=Color("276b5c") if w.eligible_vote else (Color("a84148") if w.exposed else CREAM)
		var badge: Vector2=pos-Vector2(0,54)
		draw_circle(badge+Vector2(0,3),30,Color(.15,.14,.23,.2));draw_circle(badge,28,color);draw_arc(badge,28,0,TAU,40,INK,2,true)
		_label(str(i+1),badge+Vector2(-12,15),42,CREAM if w.eligible_vote or w.exposed else INK)
		_hits.append({"kind":"witness","id":wd.id,"rect":Rect2(pos-Vector2(72,48),Vector2(144,144)),"anchor":pos})
	var hero_pos: Vector2=_visual_position("hero")
	var hero_height: float=_hero_display_height()
	_contact_shadow(hero_pos,hero_height*.28,.16)
	if not _puppets.has("felix"):_art("res://assets/art/characters/felix.png",hero_pos,hero_height,sin(clock*2.1)*.012)
	if not _puppets.has("plum"):_art("res://assets/art/characters/plum.png",hero_pos+Vector2(hero_height*.73,-hero_height*.59+sin(clock*3)*hero_height*.04),hero_height*.364,sin(clock*5)*.09)
	if not inspected.is_empty() and st.witnesses.has(inspected):
		var diagnostics: Dictionary=kernel.visibility_for(inspected)
		for ray in diagnostics.rays:
			var color: Color=Color(.15,.5,.35,.75) if ray.visible else Color(.66,.25,.29,.6)
			if ray.method and not ray.visible:color=Color(.36,.26,.65,.55)
			draw_line(world(ray.from),world(ray.to),color,3,true);draw_circle(world(ray.to),7,color)
		_rounded(Rect2(18,size.y-86,size.x-36,72),CREAM)
		_label(_t("stage.vision","Обзор {visible}/3 · Механизм {method}").format({"visible":diagnostics.visible_results,"method":_t("stage.visible","виден") if diagnostics.method_visible else _t("stage.hidden","скрыт")}),Vector2(36,size.y-36),42)
func _capacity_badge_layout() -> Array:
	# Labels are a presentation pass: never relocate props or their input anchors.
	var badges: Array=[]
	if kernel==null or kernel.state.is_empty():return badges
	var ids: Array=kernel.state.entities.keys();ids.sort()
	for id in ids:
		var entity: Dictionary=kernel.state.entities[id]
		var definition: Dictionary=kernel._entities[id]
		if entity.removed or kernel._slots[entity.slot].mount_layer=="tray" or definition.material!="STONE" or not definition.properties.has("size"):continue
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
		var style=StyleBoxFlat.new();style.bg_color=INK;style.set_corner_radius_all(11)
		_capacity_overlay.draw_style_box(style,badge.rect)
		_capacity_overlay.draw_string(_font,badge.rect.position+Vector2(16,47),badge.text,HORIZONTAL_ALIGNMENT_LEFT,-1,42,CREAM)
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
func _target_at(position: Vector2) -> Dictionary:
	var nearest: Dictionary={};var distance: float=INF
	for target in _hits:
		if target.kind=="slot" and target.rect.has_point(position):
			var d: float=target.rect.get_center().distance_squared_to(position)
			if d<distance:nearest=target;distance=d
	if not nearest.is_empty():return nearest
	for i in range(_hits.size()-1,-1,-1):
		var target: Dictionary=_hits[i]
		if target.kind=="slot" or not target.rect.has_point(position):continue
		var d: float=target.get("anchor",target.rect.get_center()).distance_squared_to(position)
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
