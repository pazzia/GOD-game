class_name CharacterPuppet
extends Node2D
## Cosmetic cutout rig. No kernel reference, gameplay callbacks or wall-clock rules.
signal pose_finished(state: String)
const Acting=preload("res://presentation/character_acting.gd")
const BASE_STATES=["idle","move","turn","observe","suspect","accept","reveal_react","celebrate"]
const EXTRA_STATES=["show_begin","stamp","bow","hover","fly","point","shiver","cheer"]
const LOOP_STATES=["idle","move","observe","suspect","celebrate","hover","fly","shiver","cheer"]
const TEMPO={"felix":1.0,"plum":1.2,"marfa":.83,"semyon":.8,"nika":1.12,"lada":1.0,"roza":.75,"hugo":1.08,"caramelka":.95}
var actor_id: String=""
var rigged: bool=false
var last_error: String=""
var current_state: String="idle"
var reduced_motion: bool=false
var facing: int=1
var animator: AnimationPlayer
var _fit: Node2D
var _pose: Node2D
var _bones: Dictionary={}
var _render_parts: Array=[]
var _height: float=220
var _natural_height: float=1320
var _queued_loop: String="idle"

func configure(actor: String,display_height: float=220) -> bool:
	_clear()
	actor_id=actor;_height=maxf(display_height,1);last_error=""
	var root_path: String="res://assets/art/characters/rigs/"+actor+"/"
	var file_path: String=root_path+"rig.json"
	if FileAccess.file_exists(file_path):
		var parser=JSON.new()
		if parser.parse(FileAccess.get_file_as_string(file_path))==OK and parser.data is Dictionary:
			if configure_definition(parser.data,root_path,actor,display_height):return true
			_clear()
		else:last_error="Invalid rig JSON"
	# Baseline fallback remains deliberately distinguishable from an accepted part rig.
	_make_nodes()
	var path: String="res://assets/art/characters/"+actor+".png"
	if not ResourceLoader.exists(path):last_error="No rig or fallback image for "+actor;return false
	var sprite=Sprite2D.new();sprite.name="Baseline";sprite.texture=load(path)
	sprite.centered=false;sprite.position=Vector2(-sprite.texture.get_width()/2.0,-sprite.texture.get_height())
	_pose.add_child(sprite);_natural_height=sprite.texture.get_height();rigged=false
	_install_animations();set_display_height(display_height);play_state("idle",true)
	return true

func configure_definition(data: Dictionary,base_path: String,actor: String="felix",display_height: float=220) -> bool:
	last_error=""
	if not data.get("parts") is Array or data.parts.size()<3:last_error="Rig needs at least three separated parts";return false
	if not _point(data.get("canvas_size")) or not _point(data.get("feet_origin")):last_error="Invalid reference canvas/origin";return false
	if data.canvas_size[0]<=0 or data.canvas_size[1]<=0:last_error="Empty reference canvas";return false
	if not _number(data.get("nominal_height")) or data.nominal_height<=0:last_error="Nominal height must be finite and positive";return false
	var identifier=RegEx.new();identifier.compile("^[a-z][a-z0-9_]*$")
	var known: Dictionary={}
	for part in data.parts:
		if not part is Dictionary or not part.get("id") is String or part.id.is_empty() or known.has(part.id):last_error="Invalid/duplicate part ID";return false
		if identifier.search(part.id)==null:last_error="Part ID must be a lowercase identifier";return false
		if not part.get("file") is String or part.file.contains("..") or part.file.begins_with("/"):last_error="Invalid part filename";return false
		if not _point(part.get("position")) or not _point(part.get("pivot")):last_error="Invalid part position/pivot";return false
		if part.pivot[0]<0 or part.pivot[0]>1 or part.pivot[1]<0 or part.pivot[1]>1:last_error="Pivot must be normalized";return false
		if not (part.get("target_height") is float or part.get("target_height") is int) or not is_finite(float(part.target_height)) or part.target_height<=0:last_error="Invalid part height";return false
		var z=part.get("z_index",0)
		if not _number(z) or z!=floor(z) or z<-4096 or z>4096:last_error="Invalid part draw order";return false
		if not ResourceLoader.exists(base_path+part.file):last_error="Missing part "+part.file;return false
		var texture: Resource=load(base_path+part.file)
		if not texture is Texture2D or texture.get_height()<=0:last_error="Part must be a nonempty texture";return false
		known[part.id]=part
	for id in known:
		var seen: Dictionary={};var cursor: String=id
		while not cursor.is_empty():
			if seen.has(cursor) or not known.has(cursor):last_error="Invalid/cyclic part parent";return false
			seen[cursor]=true
			var parent=known[cursor].get("parent")
			if parent!=null and not parent is String:last_error="Parent must be a part ID or null";return false
			cursor="" if parent==null else parent
	_clear();actor_id=actor;_height=display_height;rigged=true;_make_nodes()
	var origin=Vector2(data.feet_origin[0],data.feet_origin[1]);var top: float=origin.y
	for part in data.parts:
		var bone=Node2D.new();bone.name=part.id;bone.z_index=int(part.get("z_index",0));_bones[part.id]=bone
	for part in data.parts:
		var bone: Node2D=_bones[part.id]
		var parent=part.get("parent")
		var parent_node: Node2D=_pose if parent==null or parent=="" else _bones[parent]
		parent_node.add_child(bone)
		var absolute=Vector2(part.position[0],part.position[1])
		var parent_origin: Vector2=origin if parent==null or parent=="" else Vector2(known[parent].position[0],known[parent].position[1])
		bone.position=absolute-parent_origin
		var sprite=Sprite2D.new();sprite.name="Art";sprite.texture=load(base_path+part.file);sprite.centered=false
		var scale_factor: float=float(part.target_height)/sprite.texture.get_height()
		sprite.scale=Vector2.ONE*scale_factor
		sprite.position=-Vector2(part.pivot[0]*sprite.texture.get_width(),part.pivot[1]*sprite.texture.get_height())*scale_factor
		# Draw every part within this one CanvasItem. Negative rig z-order must not
		# put legs/cape behind the stage background, or arms above modal dialogs.
		sprite.visible=false;bone.add_child(sprite)
		_render_parts.append({"bone":bone,"sprite":sprite,"z":int(part.get("z_index",0)),"order":_render_parts.size()})
		top=minf(top,absolute.y-float(part.pivot[1])*float(part.target_height))
	_render_parts.sort_custom(func(a,b):return a.z<b.z if a.z!=b.z else a.order<b.order)
	_natural_height=maxf(float(data.get("nominal_height",origin.y-top)),1)
	_install_animations();set_display_height(display_height);play_state("idle",true)
	return true

func set_display_height(value: float) -> void:
	_height=maxf(value,1)
	if is_instance_valid(_fit):_fit.scale=Vector2(float(facing),1)*(_height/_natural_height)
	queue_redraw()
func set_facing(direction: int) -> void:
	facing=-1 if direction<0 else 1;set_display_height(_height)
func set_reduced_motion(value: bool) -> void:
	if reduced_motion==value:return
	reduced_motion=value
	if not is_instance_valid(animator):return
	if value:
		animator.pause();animator.seek(animator.current_animation_length*.5,true)
	else:
		animator.play(current_state);animator.speed_scale=TEMPO.get(actor_id,1.0)
	queue_redraw()
func special_states() -> Array:
	return Acting.states_for(actor_id)
func play_cue(trigger: String,variant: int=0,force: bool=false) -> bool:
	return play_state(Acting.pose_for(actor_id,trigger,variant),force)
func is_loop_state(state: String) -> bool:
	return state in LOOP_STATES or Acting.is_loop(actor_id,state)
func play_state(state: String,force: bool=false) -> bool:
	if not is_instance_valid(animator) or not animator.has_animation(state):return false
	if state==current_state and not force:return true
	if not force and not is_loop_state(current_state) and (animator.is_playing() or reduced_motion):
		if is_loop_state(state):_queued_loop=state;return true
	current_state=state
	if is_loop_state(state):_queued_loop=state
	animator.play(state);animator.speed_scale=TEMPO.get(actor_id,1.0);animator.advance(0)
	if reduced_motion:animator.pause();animator.seek(animator.current_animation_length*.5,true)
	queue_redraw()
	return true
func _process(_delta: float) -> void:
	if not reduced_motion:queue_redraw()
func _draw() -> void:
	for record in _render_parts:
		var bone: Node2D=record.bone
		var sprite: Sprite2D=record.sprite
		var local: Transform2D=global_transform.affine_inverse()*bone.global_transform*sprite.transform
		draw_set_transform_matrix(local)
		draw_texture(sprite.texture,Vector2.ZERO,sprite.modulate)
	draw_set_transform_matrix(Transform2D.IDENTITY)
func _finished(name: StringName) -> void:
	if not is_loop_state(String(name)):play_state(_queued_loop,true)
	# Observers may chain another cosmetic action or free this node in the signal.
	pose_finished.emit(String(name))
func _make_nodes() -> void:
	_fit=Node2D.new();_fit.name="Fit";add_child(_fit)
	_pose=Node2D.new();_pose.name="Pose";_fit.add_child(_pose)
	animator=AnimationPlayer.new();animator.name="AnimationPlayer";animator.root_node=NodePath("..");add_child(animator)
	animator.animation_finished.connect(_finished)
func _clear() -> void:
	if is_instance_valid(animator):animator.stop();animator.free()
	if is_instance_valid(_fit):_fit.free()
	animator=null;_fit=null;_pose=null;_bones.clear();_render_parts.clear();rigged=false;current_state="idle";_queued_loop="idle"
func _install_animations() -> void:
	var library=AnimationLibrary.new()
	for state in BASE_STATES+EXTRA_STATES:library.add_animation(state,_make_animation(state))
	for state in special_states():library.add_animation(state,_make_authored_animation(state))
	animator.add_animation_library("",library)
func _make_authored_animation(state: String) -> Animation:
	var definition: Dictionary=Acting.definition(actor_id,state)
	var animation=Animation.new();animation.length=float(definition.duration)
	animation.loop_mode=Animation.LOOP_LINEAR if bool(definition.loop) else Animation.LOOP_NONE
	var times: Array=definition.times
	var positions: Array=[];var scales: Array=[]
	for value in definition.positions:positions.append(Vector2(value[0],value[1]))
	for value in definition.scales:scales.append(Vector2(value[0],value[1]))
	_authored_track(animation,"Fit/Pose:position",times,positions)
	_authored_track(animation,"Fit/Pose:scale",times,scales)
	_authored_track(animation,"Fit/Pose:rotation",times,definition.root_rotation)
	# Every clip owns all rotations, including neutral tracks, so returning from
	# an actor-specific pose never leaves a prop, head or limb in the previous pose.
	for id in _bones:
		var values: Array=definition.rotations.get(id,[0.0,0.0,0.0,0.0,0.0,0.0])
		var relative: String=String(_pose.get_path_to(_bones[id]))
		_authored_track(animation,"Fit/Pose/"+relative+":rotation",times,values)
	return animation
func _authored_track(animation: Animation,path: String,times: Array,values: Array) -> void:
	var index: int=animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(index,NodePath(path))
	# Linear keys preserve deliberately held poses and cannot overshoot limb bounds.
	animation.track_set_interpolation_type(index,Animation.INTERPOLATION_LINEAR)
	for key in range(times.size()):animation.track_insert_key(index,animation.length*float(times[key]),values[key])
func _make_animation(state: String) -> Animation:
	var a=Animation.new()
	a.length={"idle":3.2,"move":.8,"turn":.65,"observe":2.6,"suspect":2.0,"accept":1.0,"reveal_react":.85,"celebrate":1.25,"show_begin":1.3,"stamp":.9,"bow":1.2,"hover":1.2,"fly":.45,"point":1.0,"shiver":.4,"cheer":1.0}.get(state,1.0)
	a.loop_mode=Animation.LOOP_LINEAR if state in LOOP_STATES else Animation.LOOP_NONE
	var positions: Array=[Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO]
	var scales: Array=[Vector2.ONE,Vector2.ONE,Vector2.ONE,Vector2.ONE,Vector2.ONE]
	var rotations: Dictionary={}
	for id in _bones:rotations[id]=[0.0,0.0,0.0,0.0,0.0]
	match state:
		"idle","hover":
			positions=[Vector2.ZERO,Vector2(0,-5),Vector2(0,-8),Vector2(0,-5),Vector2.ZERO]
			scales=[Vector2.ONE,Vector2(1.005,.996),Vector2(1.008,.992),Vector2(1.005,.996),Vector2.ONE]
			_pose_rot(rotations,["head"],[0,-.012,-.02,-.012,0]);_pose_rot(rotations,["cape","tail"],[0,.018,0,-.018,0]);_wings(rotations,.18)
		"move","fly":
			positions=[Vector2.ZERO,Vector2(0,-18),Vector2.ZERO,Vector2(0,-18),Vector2.ZERO]
			_pose_rot(rotations,["left_leg","front_left_leg","hind_right_leg"],[-.22,0,.22,0,-.22]);_pose_rot(rotations,["right_leg","front_right_leg","hind_left_leg"],[.22,0,-.22,0,.22])
			_pose_rot(rotations,["left_arm"],[.18,0,-.18,0,.18]);_pose_rot(rotations,["right_arm"],[-.18,0,.18,0,-.18]);_pose_rot(rotations,["cape","tail"],[.02,.1,.02,-.08,.02]);_wings(rotations,.65)
		"turn":
			# A short anticipation, followed by the caller's direction change.
			# Preserve the painted silhouette until proper direction art is available.
			scales=[Vector2.ONE,Vector2(.94,1),Vector2(.84,1),Vector2(.94,1),Vector2.ONE];_pose_rot(rotations,["head"],[0,.06,.12,.06,0])
		"observe":
			_pose_rot(rotations,["head"],[.05,.08,.09,.08,.05]);_pose_rot(rotations,["torso","body"],[.02,.035,.04,.035,.02]);_wings(rotations,.06)
		"suspect":
			_pose_rot(rotations,["head"],[-.08,-.12,.02,.08,-.08]);_pose_rot(rotations,["left_arm"],[.2,.3,.3,.2,.2]);_pose_rot(rotations,["tail"],[0,.2,0,-.2,0])
		"accept":_pose_rot(rotations,["head"],[0,.17,0,.12,0]);_pose_rot(rotations,["right_arm"],[0,-.22,-.3,-.2,0])
		"reveal_react":
			positions=[Vector2.ZERO,Vector2(0,-40),Vector2(0,-48),Vector2(0,7),Vector2.ZERO];_pose_rot(rotations,["head"],[0,-.18,-.12,.04,0]);_pose_rot(rotations,["left_arm"],[0,.55,.65,.22,0]);_pose_rot(rotations,["right_arm"],[0,-.55,-.65,-.22,0]);_wings(rotations,.9)
		"celebrate","cheer":
			positions=[Vector2.ZERO,Vector2(0,-30),Vector2.ZERO,Vector2(0,-14),Vector2.ZERO];_pose_rot(rotations,["left_arm"],[.35,.6,.4,.6,.35]);_pose_rot(rotations,["right_arm"],[-.35,-.6,-.4,-.6,-.35]);_pose_rot(rotations,["head"],[0,-.05,.04,-.05,0]);_wings(rotations,.5)
		"show_begin","point":_pose_rot(rotations,["left_arm"],[0,.15,.6,.5,0]);_pose_rot(rotations,["right_arm"],[0,-.2,-.85,-.8,0]);_pose_rot(rotations,["head"],[0,-.06,.04,-.03,0]);_pose_rot(rotations,["cape"],[0,.08,.15,.08,0])
		"stamp":
			positions=[Vector2.ZERO,Vector2(0,-3),Vector2(0,18),Vector2(0,5),Vector2.ZERO];_pose_rot(rotations,["right_arm"],[0,-1.0,.4,.16,0]);_pose_rot(rotations,["head"],[0,-.05,.12,.05,0]);_pose_rot(rotations,["accessory","prop"],[0,-.15,.2,.06,0])
		"bow":_pose_rot(rotations,["head"],[0,.15,.28,.2,0]);_pose_rot(rotations,["torso","body"],[0,.08,.18,.1,0]);positions=[Vector2.ZERO,Vector2(0,7),Vector2(0,16),Vector2(0,7),Vector2.ZERO]
		"shiver":positions=[Vector2.ZERO,Vector2(-10,0),Vector2(8,0),Vector2(-6,0),Vector2.ZERO];_wings(rotations,.15)
	_track(a,"Fit/Pose:position",positions)
	_track(a,"Fit/Pose:scale",scales)
	_track(a,"Fit/Pose:rotation",[0.0,0.0,0.0,0.0,0.0])
	for id in _bones:
		var relative: String=String(_pose.get_path_to(_bones[id]));_track(a,"Fit/Pose/"+relative+":rotation",rotations[id])
	return a
func _pose_rot(values: Dictionary,ids: Array,keys: Array) -> void:
	for id in ids:
		if values.has(id):values[id]=keys.duplicate()
func _wings(values: Dictionary,amount: float) -> void:
	_pose_rot(values,["wing_left","left_wing"],[0,amount,0,-amount,0]);_pose_rot(values,["wing_right","right_wing"],[0,-amount,0,amount,0])
func _track(a: Animation,path: String,values: Array) -> void:
	var i: int=a.add_track(Animation.TYPE_VALUE);a.track_set_path(i,NodePath(path));a.track_set_interpolation_type(i,Animation.INTERPOLATION_CUBIC)
	for k in range(values.size()):a.track_insert_key(i,a.length*k/(values.size()-1),values[k])
func _point(value: Variant) -> bool:
	return value is Array and value.size()==2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float) and is_finite(float(value[0])) and is_finite(float(value[1]))
func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
