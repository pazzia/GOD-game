extends SceneTree
## Independent integration acceptance; production App/Stage/Puppet, isolated user profile.
const App=preload("res://tests/review_app_host.gd")
const Audio=preload("res://services/audio_service.gd")
const Kernel=preload("res://core/simulation_kernel.gd")
const Stage=preload("res://presentation/stage_view.gd")
const Puppet=preload("res://presentation/character_puppet.gd")
var checks: int=0
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var defaults: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/settings_default.json"))
	defaults.audio.master_muted=true
	var a=Audio.new();root.add_child(a);a.configure(defaults.audio)
	var app=App.new();app.settings=defaults.duplicate(true);app.audio=a
	var t=Theme.new();t.default_font=load("res://assets/fonts/DejaVuSans.ttf");t.default_font_size=40;app.theme=t
	for n in range(1,31):app.level_ids.append("L%02d"%n)
	app.progress={"schema_version":1,"completed":{},"unlocked":1,"current_level":1};app._capture_stage="plan";root.add_child(app);app.set_process(false)
	app.start_level(1,false);await process_frame;await process_frame
	var stage: Control=app.stage
	check(stage._puppets.has("felix") and stage._puppets.felix.rigged,"actual Felix part rig is integrated into production Stage")
	if not stage._puppets.has("felix"):
		app.free();a.shutdown();a.free();finish();return
	var hero: Node2D=stage._puppets.felix
	var animator: AnimationPlayer=hero.animator
	var initial_actor_ids: Dictionary=actor_ids(stage)
	check(initial_actor_ids.has("plum") and initial_actor_ids.size()==2 and puppet_nodes(stage).size()==2 and find_actor(stage,"plum").rigged,"L01 has exactly one real Felix and one real Plum rig")
	animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var stage_id: int=stage.get_instance_id();var hero_id: int=hero.get_instance_id();var animator_id: int=animator.get_instance_id()
	var original_definition: Variant=app.kernel._canonical(app.kernel.definition)
	var original_hash: String=app.kernel.state_hash()
	stage.play_actor("felix","stamp");animator.advance(.23)
	var at: float=animator.current_animation_position
	for pair in [[1.4,"en"],[1.0,"ru"],[1.2,"en"]]:
		app.settings.accessibility.text_scale=pair[0];app.settings.locale=pair[1];app._load_catalog();app._build_ui();app._update_ui()
	check(app.stage.get_instance_id()==stage_id and app.stage._puppets.felix.get_instance_id()==hero_id and hero.animator.get_instance_id()==animator_id and actor_ids(stage)==initial_actor_ids,"HUD reflow reuses exact Stage and every actor/AnimationPlayer instance")
	check(hero.current_state=="stamp" and animator.is_playing() and is_equal_approx(animator.current_animation_position,at),"reparent during HUD reflow preserves active one-shot state and clock")
	await process_frame;await process_frame
	check(count_script(app,Stage)==1 and count_script(app,Puppet)==initial_actor_ids.size() and stage.target_tapped.get_connections().size()==1,"repeated reflow leaves one Stage, one rig per actor and one target callback")
	check(app.kernel.state_hash()==original_hash and app.kernel._canonical(app.kernel.definition)==original_definition,"text scale and locale reflow do not mutate gameplay or authored geometry")
	check(stage.size==Vector2(984,656) and stage.world([0,0])==Vector2(20,36) and stage.world([24,28])==Vector2(932,592),"measured HUD retains original grid transform and3:2 stage rectangle")
	var layers: Dictionary=stage._environment("ENV01")
	var authored_layers: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/environments/ENV01/layers.json"))
	check(layers==authored_layers and layers.get("layers",[]).size()==5,"runtime preserves complete authored layer metadata")
	var all_textures: bool=true
	for layer in layers.get("layers",[]):all_textures=all_textures and stage.texture("res://assets/art/environments/ENV01/"+layer.file)!=null
	check(all_textures and layers.get("water",{}).get("render","")=="exact_authoritative_polygon_above_floor","five layer textures load and water retains authoritative polygon contract")
	app.settings.accessibility.text_scale=1;app.settings.locale="ru";app._load_catalog();app._build_ui();app._update_ui()
	for pair in [["float","stage_float"],["stone","stage_stone"],["screen_a","screen_left"]]:app._command("PlaceProp",{"entity_id":pair[0],"slot_id":pair[1]})
	var plan_hash: String=app.kernel.state_hash()
	check(app._command("BeginPerformance") and hero.current_state=="show_begin","real show_started event selects show_begin once")
	animator.advance(.2);at=animator.current_animation_position
	for i in range(20):app._update_ui();stage._sync_puppets()
	check(hero.current_state=="show_begin" and is_equal_approx(animator.current_animation_position,at),"HUD and pose synchronization do not restart show_begin")
	app._events(app.kernel.advance_ticks(100));app._update_ui()
	check(hero.current_state=="accept" and app.kernel.state.phase=="PROOF_ACCEPTED","real proof_accepted event selects accept")
	check(app._command("ActivateLaw",{"myth_id":"M01"}) and hero.current_state=="stamp","atomic law commit maps once to stamp")
	animator.advance(.23);at=animator.current_animation_position
	var committed: Dictionary=app.kernel.snapshot();var committed_hash: String=app.kernel.state_hash()
	for i in range(20):app._update_ui();stage._sync_puppets()
	check(hero.current_state=="stamp" and is_equal_approx(animator.current_animation_position,at) and app.kernel.state_hash()==committed_hash,"stamp keeps clock through repeated HUD updates and never drives law state")
	var comparison=Kernel.new();comparison.load_level(app.kernel.definition,48121);comparison.restore(committed)
	stage.kernel=comparison;stage._sync_puppets()
	check(stage._puppets.felix.get_instance_id()==hero_id and comparison.state_hash()==committed_hash and app.kernel.state_hash()==committed_hash,"author preview kernel swap reuses actor without mutating either simulation")
	stage.kernel=app.kernel;stage._sync_puppets()
	app.start_level(1,false)
	for pair in [["float","stage_float"],["stone","stage_stone"],["screen_a","screen_left"]]:app._command("PlaceProp",{"entity_id":pair[0],"slot_id":pair[1]})
	plan_hash=app.kernel.state_hash();app._command("BeginPerformance")
	animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	app._caption_remaining=.9;app._transformation=1.2;app.set_process(true)
	await create_timer(.08).timeout # Actual SceneTree clocks, not manually invoked _process.
	app._notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	var paused_truth: String=app.kernel.state_hash();var paused_clock: float=stage.clock;var paused_poses: Dictionary=actor_clocks(stage)
	var paused_caption: float=app._caption_remaining;var paused_flash: float=app._transformation;var paused_audio: Dictionary=a.conductor_state()
	await create_timer(.08).timeout
	check(not stage.can_process() and all_actors_paused(stage) and is_equal_approx(stage.clock,paused_clock) and actor_clocks(stage)==paused_poses,"background freezes actual Stage and every child AnimationPlayer clock")
	check(app.kernel.state_hash()==paused_truth and app._caption_remaining==paused_caption and app._transformation==paused_flash and a.conductor_state()==paused_audio,"background freezes simulation/caption/transformation/audio clocks")
	var saved: Dictionary=app.saver.read_slot("progress")
	check(saved.get("checkpoint",{}).get("phase","")=="PLAN_SHOW" and saved.checkpoint.active_laws.is_empty(),"background persists pre-show truth rather than cosmetic gesture phase")
	app._build_ui();app._update_ui();await create_timer(.04).timeout
	check(app.stage.get_instance_id()==stage_id and not stage.can_process() and not animator.can_process() and stage.clock==paused_clock,"HUD rebuild while backgrounded preserves disabled scene processing")
	app._notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	check(app.kernel.state_hash()==plan_hash and stage.can_process() and hero.can_process(),"return restores exact pre-show checkpoint and resumes cosmetic tree")
	await create_timer(.06).timeout
	check(stage.clock>paused_clock and a.conductor_state().transport>paused_audio.transport and AudioServer.is_bus_mute(0),"resume advances cosmetic/audio clocks without raising user volume")
	app._set_reduced_motion(true);await process_frame;await process_frame
	var still_clock: float=stage.clock;var still_poses: Dictionary=actor_clocks(stage);var still_hash: String=app.kernel.state_hash()
	await create_timer(.06).timeout
	check(stage.clock==still_clock and actor_clocks(stage)==still_poses and app.kernel.state_hash()==still_hash,"reduced motion stops every visual clock and pose while leaving gameplay unchanged")
	app.set_process(false)
	app.free();a.shutdown();a.free();await process_frame
	await route_view_cases()
	await create_timer(.15).timeout
	finish()
func route_view_cases() -> void:
	var definition: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/L06.json"))
	var k=Kernel.new();k.load_level(definition,48121)
	var view=Stage.new();view.kernel=k;view.size=Vector2(984,656);root.add_child(view)
	var first: Dictionary=k.dispatch({"type":"AssignRoute","payload":{"actor_id":"goat","route_id":"cross"}})
	var run: Dictionary=k.dispatch({"type":"RunResolution","payload":{}});k.advance_ticks(5);view._sync_puppets()
	check(first.accepted and run.accepted and view._puppets.felix.current_state=="idle" and view._entity_position("hero")==view.world(k.state.entities.hero.position),"independently walking animal does not animate or move carrier hero")
	var goat=find_actor(view,"caramelka")
	check(goat!=null and goat.rigged and goat.position.is_equal_approx(view._entity_position("goat")) and actor_ids(view).size()==3 and puppet_nodes(view).size()==3,"entity goat binds one actual Caramelka rig alongside Felix and Plum")
	var frozen: Dictionary=actor_clocks(view);view.process_mode=Node.PROCESS_MODE_DISABLED;await create_timer(.04).timeout
	check(all_actors_paused(view) and actor_clocks(view)==frozen,"all three rig clocks freeze through parent Stage processing mode")
	view.process_mode=Node.PROCESS_MODE_INHERIT
	k.advance_ticks(150);k.dispatch({"type":"AssignRoute","payload":{"actor_id":"crate_1","route_id":"small_cross"}});k.dispatch({"type":"RunResolution","payload":{}});k.advance_ticks(5);view._sync_puppets()
	check(view._puppets.felix.current_state=="idle" and view._entity_position("hero")==view.world(k.state.entities.hero.position) and view._entity_position("crate_1")!=view.world(k.state.entities.crate_1.position),"towed route interpolates cargo while hero stays on authored shore")
	var walk=Kernel.new();walk.load_level(JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/L01.json")),48121)
	var replay: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/L01_solution.json"))
	for step in replay.steps:
		if step.op=="command":walk.dispatch(step)
		elif step.op=="advance_ticks":walk.advance_ticks(int(step.count))
		if step.get("type","")=="RunResolution":break
	walk.advance_ticks(5);var truth: String=walk.state_hash();view.kernel=walk;view._sync_puppets()
	var task: Dictionary=walk.state.routes.hero;var route: Dictionary=walk._find(walk.definition.navigation.routes,task.route_id)
	var start: Array=walk._find(walk.definition.navigation.nodes,route.nodes[0]).position
	var next: Array=walk._find(walk.definition.navigation.nodes,route.nodes[1]).position
	var expected: Vector2=view.world(start).lerp(view.world(next),float(task.progress)/int(route.get("ticks_per_edge",10)))
	check(view._puppets.felix.current_state=="move" and view._puppets.felix.position.is_equal_approx(expected) and walk.state_hash()==truth,"actual hero route selects move and interpolates authoritative progress without mutating truth")
	await process_frame
	goat=find_actor(view,"caramelka")
	check(goat==null or not goat.is_visible_in_tree(),"switching to level without goat leaves no stale visible Caramelka")
	view.free();await process_frame
func puppet_nodes(node: Node) -> Array:
	var found: Array=[]
	if node.get_script()==Puppet:found.append(node)
	for child in node.get_children():found.append_array(puppet_nodes(child))
	return found
func actor_ids(node: Node) -> Dictionary:
	var result: Dictionary={}
	for actor in puppet_nodes(node):result[actor.actor_id]=[actor.get_instance_id(),actor.animator.get_instance_id()]
	return result
func actor_clocks(node: Node) -> Dictionary:
	var result: Dictionary={}
	for actor in puppet_nodes(node):result[actor.get_instance_id()]=actor.animator.current_animation_position
	return result
func find_actor(node: Node,id: String):
	for actor in puppet_nodes(node):
		if actor.actor_id==id:return actor
	return null
func all_actors_paused(node: Node) -> bool:
	for actor in puppet_nodes(node):
		if actor.can_process() or actor.animator.can_process():return false
	return true
func count_script(node: Node,script: Script) -> int:
	var total: int=1 if node.get_script()==script else 0
	for child in node.get_children():total+=count_script(child,script)
	return total
func finish() -> void:
	print("STAGE BOUNDARIES: %d checks; %d failures"%[checks,failures.size()])
	for issue in failures:printerr("FAIL: "+issue)
	var f=FileAccess.open("res://tests/reports/stage-boundaries.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"actual_scene_tree_clocks":true,"device_or_art_acceptance":false},"  "));f.close()
	quit(0 if failures.is_empty() else 1)
func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message)
