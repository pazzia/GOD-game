extends SceneTree
const Puppet=preload("res://presentation/character_puppet.gd")
var count: int=0
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(ok: bool,why: String) -> void:
	count+=1
	if not ok:failures.append(why)
func fixture() -> Dictionary:
	return {"canvas_size":[1000,1400],"feet_origin":[500,1320],"nominal_height":1320,"parts":[
		{"id":"torso","file":"felix.png","position":[500,430],"pivot":[.5,.02],"target_height":470,"z_index":0,"parent":null},
		{"id":"head","file":"felix.png","position":[500,450],"pivot":[.5,.94],"target_height":400,"z_index":10,"parent":null},
		{"id":"right_arm","file":"felix.png","position":[650,470],"pivot":[.5,.04],"target_height":430,"z_index":5,"parent":null},
		{"id":"left_leg","file":"felix.png","position":[430,820],"pivot":[.5,.04],"target_height":500,"z_index":-20,"parent":null},
		{"id":"right_leg","file":"felix.png","position":[570,820],"pivot":[.5,.04],"target_height":500,"z_index":-19,"parent":null},
		{"id":"horns","file":"felix.png","position":[530,180],"pivot":[.5,.94],"target_height":230,"z_index":11,"parent":"head"}]}
func run() -> void:
	# This deliberately reused texture tests transform/control semantics only, never art acceptance.
	var p=Puppet.new();root.add_child(p)
	check(p.configure_definition(fixture(),"res://assets/art/characters/","felix",220),"valid separated-part metadata configures")
	check(p.rigged and p._bones.size()==6,"rigged differs from baseline fallback")
	check(is_equal_approx(p._fit.scale.y,220.0/1320),"nominal height governs predictable stage scale")
	check(p._bones.horns.get_parent()==p._bones.head,"head attachments inherit head animation")
	check(p._bones.head.position==Vector2(0,-870) and p._bones.horns.position==Vector2(30,-270),"absolute canvas pivots become correct relative joints")
	for state in Puppet.BASE_STATES:
		check(p.animator.has_animation(state),"base animation exists: "+state)
	check(p.animator.get_animation("idle").loop_mode==Animation.LOOP_LINEAR and p.animator.get_animation("stamp").loop_mode==Animation.LOOP_NONE,"idle loops and meaningful gesture ends")
	p.animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	p.play_state("move",true);p.animator.advance(.1)
	check(absf(p._bones.left_leg.rotation)>0 and absf(p._bones.right_leg.rotation)>0 and p._bones.left_leg.rotation*p._bones.right_leg.rotation<0,"walking animates opposing separated legs")
	var at: float=p.animator.current_animation_position;p.play_state("move")
	check(is_equal_approx(p.animator.current_animation_position,at),"same-state HUD updates never restart timeline")
	p.play_state("stamp",true);p.animator.advance(.225)
	check(p._bones.right_arm.rotation<-.5,"stamp has readable anticipation before downstroke")
	p.play_state("observe");check(p.current_state=="stamp","loop request cannot prematurely interrupt a one-shot")
	var finished: Array=[];p.pose_finished.connect(func(s):finished.append(s))
	p.animator.advance(1.0)
	check(finished==["stamp"] and p.current_state=="observe","completion emits once and returns to queued loop")
	p.animator.advance(.2);check(finished.size()==1,"loop does not repeat gameplay-like completion callbacks")
	var before: String=p.current_state
	check(not p.play_state("unknown") and p.current_state==before,"unknown pose is rejected without changing current state")
	p.set_facing(-1);check(p._fit.scale.x<0 and p._fit.scale.y>0,"horizontal direction preserves height and feet origin")
	p.set_display_height(330);check(is_equal_approx(absf(p._fit.scale.x),.25),"resizing preserves authored proportions")
	p.set_reduced_motion(true);var position: float=p.animator.current_animation_position
	await process_frame;await process_frame
	check(not p.animator.is_playing() and is_equal_approx(p.animator.current_animation_position,position),"reduced motion freezes cosmetic pose")
	p.set_reduced_motion(false);check(p.animator.is_playing(),"motion can resume from user setting")
	var bad: Dictionary=fixture();bad.parts[1].parent="horns"
	check(not p.configure_definition(bad,"res://assets/art/characters/") and p.rigged,"cyclic parent metadata rejected before replacing existing rig")
	bad=fixture();bad.parts[1].file="../other.png"
	check(not p.configure_definition(bad,"res://assets/art/characters/"),"part path traversal rejected")
	bad=fixture();bad.parts[0].target_height=-1
	check(not p.configure_definition(bad,"res://assets/art/characters/"),"negative part size rejected")
	bad=fixture();bad.parts[0].pivot=[2,.5]
	check(not p.configure_definition(bad,"res://assets/art/characters/"),"out-of-range pivot rejected")
	p.free()
	var produced_rigs: int=0
	for actor in ["felix","plum","marfa","semyon","nika","lada","roza","hugo","caramelka"]:
		var q=Puppet.new();root.add_child(q)
		if FileAccess.file_exists("res://assets/art/characters/rigs/"+actor+"/rig.json"):
			check(q.configure(actor) and q.rigged,"actual produced rig loads: "+actor);produced_rigs+=1
		else:check(q.configure(actor) and not q.rigged,"explicit baseline fallback remains available: "+actor)
		if actor=="plum" and q.rigged:
			q.animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			q.play_state("fly",true);q.animator.seek(.1125,true)
			var left: float=q._bones.wing_left.rotation;var right: float=q._bones.wing_right.rotation
			check(left>.5 and right<-.5,"produced Plum wings flap as opposing separate painted parts")
			q.animator.seek(.3375,true)
			check(q._bones.wing_left.rotation<-.5 and q._bones.wing_right.rotation>.5,"produced Plum wings reverse through second half of flight loop")
			check(q._bones.antenna_left.get_parent()==q._bones.head and q._bones.antenna_right.get_parent()==q._bones.head,"produced antennae follow head joint")
		if actor=="caramelka" and q.rigged:
			q.animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			q.play_state("move",true);q.animator.seek(.4,true)
			check(q._bones.front_left_leg.rotation>.2 and q._bones.hind_right_leg.rotation>.2 and q._bones.front_right_leg.rotation<-.2 and q._bones.hind_left_leg.rotation<-.2,"produced goat walk alternates both diagonal pairs of four legs")
			check(q._bones.horns.get_parent()==q._bones.head and q._bones.collar_bell.get_parent()==q._bones.head,"produced goat horns and bell stay attached to head")
		q.free()
	await process_frame
	var report={"checks":count,"failures":failures,"actual_part_rigs_loaded":produced_rigs,"engine":Engine.get_version_info().string,"limits":"Transform/state tests with deliberate texture fixtures; actual composition/animation visual acceptance is separate."}
	var f=FileAccess.open("res://tests/reports/puppet.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	print("PUPPET: %d checks; %d failures; %d actual part rigs"%[count,failures.size(),produced_rigs])
	for issue in failures:printerr("FAIL: "+issue)
	quit(0 if failures.is_empty() else 1)
