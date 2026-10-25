extends SceneTree
## Real AnimationPlayer timelines; fixture textures prove motion, never art quality.
const Puppet=preload("res://presentation/character_puppet.gd")
const Acting=preload("res://presentation/character_acting.gd")
const ACTORS=["felix","plum","marfa","semyon","nika","lada","roza","hugo","caramelka"]
var count: int=0
var failures: Array[String]=[]
var clips_checked: int=0
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	count+=1
	if not condition:failures.append(message)
func fixture(actor: String) -> Dictionary:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/characters/rigs/"+actor+"/rig.json"))
	for part in data.parts:part.file="star.svg"
	return data
func run() -> void:
	var actual: bool="--actual-rigs" in OS.get_cmdline_user_args()
	var fingerprints: Dictionary={}
	var expected: Dictionary={}
	var csv=FileAccess.open("res://docs/spec/ASSET_MANIFEST.csv",FileAccess.READ)
	var header: PackedStringArray=csv.get_csv_line()
	var id_col: int=header.find("asset_id")
	while not csv.eof_reached():
		var row: PackedStringArray=csv.get_csv_line()
		if row.size()!=header.size() or not row[id_col].begins_with("CH") or not row[id_col].contains("_ANIM_"):continue
		var asset: String=row[id_col];var actor: String=ACTORS[int(asset.substr(2,2))-1]
		var state: String=asset.substr(10).to_lower()
		if state in Puppet.BASE_STATES or state in Puppet.EXTRA_STATES:continue
		if not expected.has(actor):expected[actor]=[]
		expected[actor].append(state)
	csv.close()
	for actor in ACTORS:
		var puppet=Puppet.new();root.add_child(puppet)
		var configured: bool=puppet.configure(actor) if actual else puppet.configure_definition(fixture(actor),"res://assets/art/ui/",actor)
		check(configured and puppet.rigged,"part rig configures: "+actor)
		if not configured:puppet.free();continue
		puppet.animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var owned: Array=puppet.special_states();var wanted: Array=expected.get(actor,[])
		owned.sort();wanted.sort();check(owned==wanted,"exact authored missing-animation IDs: "+actor)
		var reachable: Array=[]
		var cues: Dictionary=Acting.catalog().cues[actor]
		for trigger in cues:
			for variant in range(cues[trigger].size()):
				var state: String=Acting.pose_for(actor,trigger,variant)
				reachable.append(state)
				check(puppet.animator.has_animation(state),"cue resolves to installed animation: "+actor+"/"+trigger)
		for state in owned:
			clips_checked+=1
			check(state in reachable,"special clip has a reachable cue: "+actor+"/"+state)
			var definition: Dictionary=Acting.definition(actor,state)
			var signature: Dictionary=definition.duplicate(true);signature.erase("description")
			var fingerprint: String=JSON.stringify(signature)
			check(not fingerprints.has(fingerprint),"distinct authored motion: "+actor+"/"+state)
			fingerprints[fingerprint]=actor+"/"+state
			for bone in definition.rotations:check(puppet._bones.has(bone),"animation targets a real rig part: "+actor+"/"+state+"/"+bone)
			check(puppet.play_state(state,true),"special clip plays: "+actor+"/"+state)
			var moved: bool=false
			var poses: Array=[]
			for fraction in [.0,.16,.36,.56,.78]:
				puppet.animator.seek(float(definition.duration)*fraction,true)
				var pose: Array=[puppet._pose.position,puppet._pose.scale]
				for bone in puppet._bones.values():pose.append(bone.rotation)
				if not poses.is_empty() and poses[-1]!=pose:moved=true
				poses.append(pose)
			check(moved,"real evaluated transforms change over timeline: "+actor+"/"+state)
			if not puppet.is_loop_state(state):
				puppet.play_state(state,true);puppet.play_state("observe")
				check(puppet.current_state==state,"one-shot survives routine loop refresh: "+actor+"/"+state)
				puppet.animator.advance(float(definition.duration)*2+1)
				check(puppet.current_state=="observe","one-shot returns to queued loop: "+actor+"/"+state)
			puppet.play_state("idle",true);puppet.animator.seek(0,true)
			check(puppet._pose.position.is_equal_approx(Vector2.ZERO) and puppet._pose.scale.is_equal_approx(Vector2.ONE) and is_zero_approx(puppet._pose.rotation),"root pose resets after special: "+actor+"/"+state)
			var reset: bool=true
			for bone in puppet._bones.values():reset=reset and is_zero_approx(bone.rotation)
			check(reset,"all bone rotations reset after special: "+actor+"/"+state)
		for other in ACTORS:
			if other==actor:continue
			for foreign in Acting.states_for(other):
				check(not puppet.animator.has_animation(foreign),"other actor's special is absent: "+actor+"/"+foreign)
		puppet.play_state(owned[0],true);puppet.set_reduced_motion(true)
		var frozen: float=puppet.animator.current_animation_position
		puppet.play_state("observe");await process_frame;await process_frame
		check(not puppet.animator.is_playing() and is_equal_approx(puppet.animator.current_animation_position,frozen),"reduced motion preserves representative pose during routine refresh: "+actor)
		puppet.set_reduced_motion(false)
		check(puppet.animator.is_playing(),"motion resumes after accessibility toggle: "+actor)
		check(not puppet.play_cue("unknown"),"unknown cue is rejected: "+actor)
		puppet.free()
	check(clips_checked==47,"all 47 formerly absent special clips evaluated")
	await process_frame
	var report={"checks":count,"failures":failures,"special_clips_evaluated":clips_checked,"actual_rig_textures":actual,"engine":Engine.get_version_info().string,"limits":"Transform and cue-contract verification. Human visual and facial/art acceptance remains separate."}
	DirAccess.make_dir_recursive_absolute("res://tests/reports")
	var file=FileAccess.open("res://tests/reports/character-acting.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("CHARACTER ACTING: %d checks; %d failures; %d special clips"%[count,failures.size(),clips_checked])
	for issue in failures:printerr("FAIL: "+issue)
	quit(0 if failures.is_empty() else 1)
