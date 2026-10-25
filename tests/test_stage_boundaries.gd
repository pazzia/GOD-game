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
	root.size=Vector2i(1920,1080);root.content_scale_size=Vector2i(1920,1080)
	var defaults: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/settings_default.json"))
	defaults.audio.master_muted=true
	var a=Audio.new();root.add_child(a);a.configure(defaults.audio)
	var app=App.new();app.settings=defaults.duplicate(true);app.audio=a
	app.theme=preload("res://presentation/theme.gd").make_theme()
	for n in range(1,31):app.level_ids.append("L%02d"%n)
	app.progress={"schema_version":1,"completed":{},"unlocked":1,"current_level":1};app._capture_stage="plan";root.add_child(app);app.set_process(false)
	app.start_level(1,false);await process_frame;await process_frame
	var stage: Control=app.stage
	check(stage._puppets.has("felix") and stage._puppets.felix.visual_mode=="illustrated_cutout" and stage._puppets.felix.source_art_key=="CH01","approved professor illustration is integrated into production Stage")
	if not stage._puppets.has("felix"):
		app.free();a.shutdown();a.free();finish();return
	var hero: Node2D=stage._puppets.felix
	var animator: AnimationPlayer=hero.animator
	var initial_actor_ids: Dictionary=actor_ids(stage)
	check(initial_actor_ids.has("plum") and initial_actor_ids.size()==3 and puppet_nodes(stage).size()==3 and find_actor(stage,"plum").visual_mode=="illustrated_cutout" and stage._puppets.has("entity:marfa") and not stage._puppets.has("witness:w1"),"L01 has professor, Plum and one Marfa body shared with the observer")
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
	check(stage.size.x>stage.size.y and Rect2(Vector2.ZERO,stage.size).has_point(stage.world([0,0])) and Rect2(Vector2.ZERO,stage.size).has_point(stage.world([24,28])) and stage.world([24,28]).x>stage.size.x*.85,"landscape projection fills the stage while keeping authored grid endpoints inside")
	check(stage.unworld(stage.world([0,0])).is_equal_approx(Vector2.ZERO) and stage.unworld(stage.world([24,28])).is_equal_approx(Vector2(24,28)),"landscape picking inverts the same authoritative projection at both grid bounds")
	var art=preload("res://presentation/reboot_art.gd")
	for scene_id in ["ENV01","ENV02","ENV03"]:
		var plate: Texture2D=art.texture_for("environments",scene_id)
		check(plate!=null and plate.get_width()>1000 and str(art.entry("environments",scene_id).get("path","")).begins_with("res://assets/art/reboot/"),"new illustrated chapter plate loads: "+scene_id)
	app.settings.accessibility.text_scale=1;app.settings.locale="ru";app._load_catalog();app._build_ui();app._update_ui()
	app._command("PlaceProp",{"entity_id":"screen_a","slot_id":"screen_left"});app._command("Interact",{"entity_id":"screen_a","action":"fold"})
	var folded_height: float=stage._prop_height("screen_a")
	check(folded_height>=190 and folded_height<=210,"folded screen keeps the agreed 190–210px display range; painted sight plausibility is reviewed separately")
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
	app._command("PlaceProp",{"entity_id":"screen_a","slot_id":"screen_left"});app._command("Interact",{"entity_id":"screen_a","action":"fold"})
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
	await capacity_badge_cases()
	await support_surface_cases()
	await shoreline_thread_cases()
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
	check(goat!=null and goat.visual_mode=="illustrated_cutout" and goat.source_art_key=="CH09" and goat.position.is_equal_approx(view._visual_position("goat")) and actor_ids(view).size()==6 and puppet_nodes(view).size()==6,"entity goat binds one actual Caramelka illustration alongside professor, Plum and three observers")
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
	var task: Dictionary=walk.state.routes.marfa;var route: Dictionary=walk._find(walk.definition.navigation.routes,task.route_id)
	var start: Array=walk._find(walk.definition.navigation.nodes,route.nodes[0]).position
	var next: Array=walk._find(walk.definition.navigation.nodes,route.nodes[1]).position
	var expected: Vector2=view.world(start).lerp(view.world(next),float(task.progress)/int(route.get("ticks_per_edge",10)))
	check(view._puppets["entity:marfa"].current_state=="move" and view._puppets["entity:marfa"].position.is_equal_approx(expected) and view._puppets.felix.position.is_equal_approx(view._visual_position("hero")) and walk.state_hash()==truth,"Marfa follows her confirmed crossing while the professor stays ashore without mutating truth")
	await process_frame
	goat=find_actor(view,"caramelka")
	check(goat==null or not goat.is_visible_in_tree(),"switching to level without goat leaves no stale visible Caramelka")
	view.free();await process_frame
func capacity_badge_cases() -> void:
	# Real regressions: two adjacent stones in L07/L24, and Felix over L17's label.
	for number in [7,17,24]:
		var id: String="L%02d"%number
		var k=Kernel.new();k.load_level(JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/"+id+".json")),48121)
		var view=Stage.new();view.kernel=k;view.size=Vector2(984,656);root.add_child(view);view.set_process(false)
		check(view._capacity_badge_layout().is_empty(),id+" capacity numbers stay out of the scene until an object or explicit overlay is selected")
		view.show_capacity=true
		for phase in ["before","after"]:
			if phase=="after":
				var replay: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/replays/"+id+"_solution.json"))
				for step in replay.steps:
					if step.op=="command":k.dispatch(step)
					elif step.op=="advance_ticks":k.advance_ticks(int(step.count))
			view._sync_puppets()
			var truth: String=k.state_hash()
			for locale in ["ru","en"]:
				var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/"+locale+".json"))
				view.translator=func(key,fallback):return catalog.get(key,fallback)
				var badges: Array=view._capacity_badge_layout()
				var readable: bool=not badges.is_empty()
				for i in range(badges.size()):
					readable=readable and Rect2(Vector2.ZERO,view.size).encloses(badges[i].rect)
					for j in range(i):readable=readable and not badges[i].rect.grow(4).intersects(badges[j].rect)
				check(readable,id+" "+phase+" "+locale+" capacity badges fit the stage and have a visible gap")
				check(k.state_hash()==truth,id+" "+phase+" "+locale+" capacity layout cannot mutate simulation")
			check(view._capacity_overlay.get_index()==view.get_child_count()-1 and view._capacity_overlay.z_index==0,id+" "+phase+" badges render after all puppets without escaping sibling modal order")
		view.free();await process_frame

func support_surface_cases() -> void:
	var walking=Kernel.new();walking.load_level(JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/L01.json")),48121)
	var walking_replay: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/L01_solution.json"))
	for step in walking_replay.steps:
		if step.op=="command":walking.dispatch(step)
		elif step.op=="advance_ticks":walking.advance_ticks(int(step.count))
		if step.get("type","")=="RunResolution":break
	walking.advance_ticks(12)
	var view=Stage.new();view.kernel=walking;view.size=Vector2(1920,1080);root.add_child(view);view.set_process(false)
	view._sync_puppets();await process_frame
	var truth: String=walking.state_hash()
	var ground: Vector2=view._entity_position("marfa")
	var painted: Vector2=view._visual_position("marfa")
	check(ground.y-painted.y>60 and ground.y-painted.y<90,"Marfa's painted feet rise onto the stone surface at the real route midpoint")
	check(view._puppets["entity:marfa"].position.is_equal_approx(painted),"walking puppet uses the same elevated display anchor as interaction geometry")
	var center: Vector2=view.world(walking.state.entities.stone.position)
	var stone_width: float=view._prop_rect("stone",center,view._prop_height("stone")).size.x
	var edge_far: float=view._surface_lift("marfa",center+Vector2(stone_width*.75,0))
	var edge_near: float=view._surface_lift("marfa",center+Vector2(stone_width*.45,0))
	var middle: float=view._surface_lift("marfa",center)
	check(is_zero_approx(edge_far) and edge_near>edge_far and middle>edge_near,"support elevation blends on approach instead of teleporting the walker vertically")
	check(walking.state_hash()==truth,"painted support elevation never changes route progress or kernel truth")
	view.free();await process_frame
	for number in [21,24,30]:
		var kernel=Kernel.new();kernel.load_level(JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/L%02d.json"%number)),48121)
		var replay: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/replays/L%02d_solution.json"%number))
		view=Stage.new();view.kernel=kernel;view.size=Vector2(1920,1080);root.add_child(view);view.set_process(false)
		var checked: bool=false
		var preserved: bool=false
		for step in replay.steps:
			var before: Dictionary=view._paper_layout("paper")
			if step.op=="command":kernel.dispatch(step)
			elif step.op=="advance_ticks":kernel.advance_ticks(int(step.count))
			var layout: Dictionary=view._paper_layout("paper")
			if layout.is_empty():continue
			var load: Dictionary={}
			var load_id: String=""
			for entity_id in kernel.state.entities:
				var candidate: Dictionary=view._paper_under_load(entity_id)
				if not candidate.is_empty():load=candidate;load_id=entity_id;break
			if not checked and not load.is_empty():
				var paper_rect: Rect2=view._prop_rect("paper",view._visual_position("paper"),view._prop_height("paper"))
				var load_rect: Rect2=view._prop_rect(load_id,view._visual_position(load_id),view._prop_height(load_id))
				var frame_rect: Rect2=view._paper_frame_layout("frame")
				check(paper_rect.size.x>=layout.first.distance_to(layout.last) and paper_rect.size.y<paper_rect.size.x*.30,"L%02d paper spans both authored anchors as a thin visible beam"%number)
				check(is_equal_approx(load_rect.end.y,float(layout.surface_y)),"L%02d load bottom rests on the painted top surface instead of sharing the ground pivot"%number)
				check(frame_rect.has_area() and frame_rect.position.y>=paper_rect.position.y+paper_rect.size.y*.60 and frame_rect.end.y>=float(layout.ground.y),"L%02d temporary steel frame sits below the paper and meets the floor"%number)
				var occlusion: Rect2=paper_rect.intersection(load_rect)
				check(occlusion.size.x<paper_rect.size.x*.70 and view._prop_draw_priority("frame")<view._prop_draw_priority("paper") and view._prop_draw_priority("paper")<view._prop_draw_priority(load_id),"L%02d draw order and exposed paper width preserve the visible proof"%number)
				checked=true
			if step.get("type","")=="Interact" and step.get("payload",{}).get("entity_id","")=="frame" and step.payload.get("action","")=="remove" and not before.is_empty():
				check(layout.rect==before.rect and layout.surface_y==before.surface_y,"L%02d removing the hidden frame leaves paper on the same support plane"%number)
				preserved=true
		check(checked and preserved,"L%02d real replay exercises the complete staged-load/removal pipeline"%number)
		view.free();await process_frame

func shoreline_thread_cases() -> void:
	var definition: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/L08.json"))
	var kernel=Kernel.new();kernel.load_level(definition,48121)
	var view=Stage.new();view.kernel=kernel;view.size=Vector2(1920,1080);root.add_child(view);view.set_process(false)
	var truth: String=kernel.state_hash()
	var mount: Dictionary=view._shoreline_mount("thread")
	var anchor: Vector2=view.world(kernel.state.entities.thread.position)
	check(kernel._position_over_water(kernel.state.entities.thread.position) and not mount.is_empty(),"L08 boundary remains WATER while its immediately adjacent bank can host the thread footing")
	check(mount.rect.position.x>=anchor.x and view._prop_rect("thread",view._visual_position("thread"),view._prop_height("thread")).position.x>=anchor.x and not kernel._position_over_water([view.unworld(mount.rect.get_center()).x,view.unworld(mount.rect.get_center()).y]),"thread footing and painted body stay entirely on the dry right side of the boundary")
	check(view._safety_thread_ends("thread").is_empty() and kernel.state_hash()==truth,"unprepared hidden support draws no fictional thread connection and changes no truth")
	kernel.dispatch({"type":"PlaceProp","payload":{"entity_id":"stone","slot_id":"stage_stone"}})
	var ends: Array=view._safety_thread_ends("thread")
	check(ends.size()==2 and view._prop_rect("thread",view._visual_position("thread"),view._prop_height("thread")).has_point(ends[0]) and view._prop_rect("stone",view._visual_position("stone"),view._prop_height("stone")).has_point(ends[1]),"a real matching support_offset draws the thread between the painted spool and stone")
	var inside: Dictionary=definition.duplicate(true)
	for slot in inside.slots:
		if slot.id=="thread_start":slot.position=[14,12]
	var interior=Kernel.new();interior.load_level(inside,48121);view.kernel=interior
	check(view._shoreline_mount("thread").is_empty(),"a thread in the interior of water cannot invent a dry footing")
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
