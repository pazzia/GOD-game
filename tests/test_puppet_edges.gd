extends SceneTree
## Independent transform/signal boundaries using intentionally reused fixture art.
const Puppet=preload("res://presentation/character_puppet.gd")
var count: int=0
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func fixture() -> Dictionary:
	return {"schema_version":1,"actor_id":"felix","canvas_size":[1000,1400],"feet_origin":[500,1320],"nominal_height":1320,"parts":[
		{"id":"torso","file":"felix.png","position":[500,430],"pivot":[.5,.02],"target_height":470,"z_index":0,"parent":null},
		{"id":"head","file":"felix.png","position":[500,450],"pivot":[.5,.94],"target_height":400,"z_index":10,"parent":null},
		{"id":"prop","file":"felix.png","position":[530,480],"pivot":[.5,.5],"target_height":200,"z_index":11,"parent":"head"}]}
func run() -> void:
	var p=Puppet.new();root.add_child(p)
	check(p.configure_definition(fixture(),"res://assets/art/characters/","felix",220),"fixture rig loads")
	p.animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	p.play_state("idle",true);p.animator.seek(0,true)
	var bone: Node2D=p._bones.prop
	check(bone.global_position.is_equal_approx(p.global_position+Vector2(30,-840)*(220.0/1320)),"nested part canvas joint maps through fit exactly once")
	var sprite: Sprite2D=bone.get_node("Art")
	check(is_equal_approx(sprite.texture.get_height()*sprite.scale.y*p._fit.scale.y,200.0*220/1320),"trimmed part target height respects full puppet display scale")
	p._bones.head.rotation=.5
	var expected: Vector2=p._bones.head.to_global(Vector2(30,30))
	check(bone.global_position.is_equal_approx(expected),"child accessory follows actual animated parent pivot")
	p.set_facing(-1);p.set_display_height(330)
	check(is_equal_approx(p._fit.scale.x,-.25) and is_equal_approx(p._fit.scale.y,.25) and p.position==Vector2.ZERO,"facing and resize preserve feet root")
	p.play_state("stamp",true)
	var emitted: Array=[]
	p.pose_finished.connect(func(state):
		emitted.append(state)
		if state=="stamp":p.play_state("bow",true))
	p.animator.advance(2)
	check(emitted==["stamp"] and p.current_state=="bow","completion subscriber can chain a cosmetic gesture without callback being overwritten by idle")
	p.play_state("move",true);p.animator.advance(.2)
	var at: float=p.animator.current_animation_position
	for i in range(10):p.set_reduced_motion(false)
	check(is_equal_approx(p.animator.current_animation_position,at),"repeated current accessibility setting does not reset timeline")
	var prior_bone: Node2D=p._bones.head
	var bad: Dictionary=fixture();bad.nominal_height=0
	check(not p.configure_definition(bad,"res://assets/art/characters/","felix",220) and p._bones.head==prior_bone,"zero nominal rig height is rejected before replacing accepted composition")
	bad=fixture();bad.nominal_height=-50
	check(not p.configure_definition(bad,"res://assets/art/characters/","felix",220),"negative nominal rig height is rejected instead of scaling entire actor hundreds of times")
	p.free();await process_frame
	print("PUPPET EDGES: %d checks; %d failures"%[count,failures.size()])
	for issue in failures:printerr("FAIL: "+issue)
	var f=FileAccess.open("res://tests/reports/puppet-edges.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":count,"failures":failures,"engine":Engine.get_version_info().string,"actual_art_acceptance":false,"fixtures":"same intentional whole-character texture reused per metadata part"},"  "));f.close()
	quit(0 if failures.is_empty() else 1)
func check(condition: bool,message: String) -> void:
	count+=1
	if not condition:failures.append(message)
