extends SceneTree
## Production illustrations remain presentation-only through level/view transitions.
const Kernel=preload("res://core/simulation_kernel.gd")
const Stage=preload("res://presentation/stage_view.gd")
var checks: int=0
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label)
func run() -> void:
	var stage=Stage.new();stage.size=Vector2(984,656);root.add_child(stage)
	var seen: Dictionary={}
	for number in range(1,31):
		var kernel=Kernel.new()
		check(kernel.load_level(JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/L%02d.json"%number)),48121),"load authored L%02d"%number)
		stage.kernel=kernel;stage._sample_presentation(0);stage._sync_puppets();await process_frame
		var original: String=kernel.state_hash()
		var definition: String=JSON.stringify(kernel._canonical(kernel.definition))
		var expected: int=2
		for entity_id in kernel.state.entities:
			var entity_actor: String=stage._entity_actor(entity_id)
			if not entity_actor.is_empty() and entity_actor!="felix":expected+=1
		for witness in kernel.definition.witnesses:
			var actor: String=Stage.CHARACTERS.get(witness.character_id,"")
			if actor.is_empty():continue
			var entity_id: String=stage._witness_entity(witness.id)
			if entity_id.is_empty():expected+=1
			var key: String="entity:"+entity_id if not entity_id.is_empty() else "witness:"+witness.id
			check(stage._puppets.has(key),"L%02d observer illustration %s"%[number,actor])
			if not stage._puppets.has(key):continue
			var puppet=stage._puppets[key];seen[actor]=true
			check(puppet.visual_mode=="illustrated_cutout" and not puppet.rigged and puppet.actor_id==actor and puppet.source_art_key==witness.character_id,"observer identity uses exact new manifest artwork without pretending to have separated limbs")
			var eye: Vector2=kernel.witness_eye(witness.id)
			check(puppet.position.is_equal_approx(stage.world([eye.x,eye.y])),"painted feet follow the exact ground-plane observation position")
			if actor in ["marfa","semyon","nika","lada","roza","hugo"]:check(puppet.special_states().size()>=4,"named observer retains individual authored cue timing")
			puppet.animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			puppet.play_cue("accept",0,true)
			check(not puppet.is_loop_state(puppet.current_state),"accept cue selects a one-shot for every observer")
			puppet.animator.advance(.2)
			var state: String=puppet.current_state;var position: float=puppet.animator.current_animation_position
			stage._sync_puppets();stage._sync_puppets()
			check(puppet.current_state==state and is_equal_approx(puppet.animator.current_animation_position,position),"observer one-shot survives repeated HUD sync without restarting")
		check(stage._puppets.size()==expected,"no stale witness actors after level transition")
		stage.react_to_event("prop_placed",{"entity_id":"stone"})
		check(stage._puppets.felix.current_state=="place_prop","placing actual props triggers Felix placement gesture")
		stage.reduced_motion=true;stage._sync_puppets()
		for puppet in stage._puppets.values():check(puppet.reduced_motion and not puppet.animator.is_playing(),"reduced motion reaches every integrated actor")
		stage.reduced_motion=false;stage._sync_puppets()
		check(kernel.state_hash()==original and JSON.stringify(kernel._canonical(kernel.definition))==definition,"all cues and visual sync preserve authoritative state and geometry")
	check(["marfa","semyon","nika","lada","roza","hugo"].all(func(actor):return seen.has(actor)),"all six named observers have new illustrated representations across the full campaign")
	var moving=Kernel.new();moving.load_level(JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/L03.json")),48121)
	stage.kernel=moving;stage._sample_presentation(0);stage._sync_puppets()
	var replay=JSON.parse_string(FileAccess.get_file_as_string("res://tests/L03_solution.json"))
	for step in replay.steps:
		if step.op!="command":break
		check(moving.dispatch(step).accepted,"L03 setup "+step.type)
	moving.advance_ticks(55);stage._sync_puppets()
	var inspector=stage._puppets.get("witness:w3")
	var eye: Vector2=moving.witness_eye("w3")
	check(inspector!=null and eye.x==21 and inspector.facing==-1 and inspector.position.is_equal_approx(stage.world([eye.x,eye.y])),"inspector follows the authored second view, facing the stage")
	var crowded=Kernel.new();crowded.load_level(JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/L06.json")),48121)
	stage.kernel=crowded;stage._sample_presentation(0);stage._sync_puppets()
	var crowded_hash: String=crowded.state_hash()
	var hero_anchor: Vector2=stage._entity_position("hero")
	check(hero_anchor==stage._entity_position("goat"),"L06 shared logical actor position is unchanged")
	check(stage._visual_position("goat").x-stage._visual_position("hero").x==220 and is_equal_approx(stage._hero_display_height(),minf(270,stage.size.y*.34)),"L06 goat and professor have separate readable silhouettes")
	check(stage._visual_position("crate_2").x-stage._visual_position("crate_1").x==140,"L06 coincident cargo crates are separately visible")
	check(stage._entity_position("crate_1")==stage._entity_position("crate_2") and crowded.state_hash()==crowded_hash,"display packing does not change cargo positions or gameplay")
	check(Stage.ASSETS.get("PROP_POSTER","")=="poster","produced poster resolves through the normal asset catalog")
	stage.free();await process_frame
	var report={"checks":checks,"failures":failures,"integrated_witness_actors":seen.keys(),"engine":Engine.get_version_info().string,"limits":"Manifest illustration integration, animated cue timing and logical isolation; no separated-limb or device acceptance claim."}
	var f=FileAccess.open("res://tests/reports/character-animation-contract.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	print("CHARACTER ANIMATION CONTRACT: %d checks; %d failures"%[checks,failures.size()])
	for issue in failures:printerr("FAIL: "+issue)
	quit(0 if failures.is_empty() else 1)
