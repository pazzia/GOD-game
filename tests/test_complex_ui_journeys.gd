extends SceneTree
## Real Control input from authored initial levels. No kernel dispatch/restore/replay fixture.
## Run with a dedicated XDG_DATA_HOME. Logical time is accelerated, not human usability timing.
const App=preload("res://tests/pointer_app_host.gd")
const Audio=preload("res://services/audio_service.gd")
var app: Control
var checks: int=0
var failures: Array[String]=[]
var pointer_events: int=0
var journeys: Array=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1920,1080);root.content_scale_size=Vector2i(1920,1080)
	Engine.time_scale=8;Engine.max_fps=120
	var defaults: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/settings_default.json"));defaults.audio.master_muted=true
	var sound=Audio.new();root.add_child(sound);sound.configure(defaults.audio)
	app=App.new();app.audio=sound;app.settings=defaults.duplicate(true)
	app.theme=preload("res://presentation/theme.gd").make_theme()
	app.progress={"schema_version":1,"unlocked":30,"completed":{},"current_level":1};app._front_menu=false;app._capture_stage=""
	for n in range(1,31):app.level_ids.append("L%02d"%n)
	app._load_catalog();root.add_child(app)
	for n in [11,21,30]:
		if not await journey(n):break
	await finish()
func journey(number: int) -> bool:
	var id: String="L%02d"%number
	app.ui_commands.clear()
	if not app.start_level(number,false):check(false,id+" initial authored level failed to load");return false
	await process_frame;await process_frame
	if not await click_text(app.tx("ui.begin","За работу")):return false
	check(app.kernel.state.tick==0 and app.kernel.state.active_laws==app.kernel.definition.initial_active_laws,id+" starts from authored initial world, not a progressed snapshot")
	var replay: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/replays/"+id+"_solution.json"))
	var before_failures: int=failures.size()
	for i in range(replay.steps.size()):
		var step: Dictionary=replay.steps[i]
		if step.op=="command":
			var first_command: int=app.ui_commands.size()
			if not await command_through_ui(step):
				check(false,id+" UI path blocked at step%d %s"%[i+1,JSON.stringify(step)]);return false
			var found: bool=false
			for command in app.ui_commands.slice(first_command):
				if command.type!=step.type or not command.accepted:continue
				var matching: bool=true
				for key in step.get("payload",{}):
					if command.payload.get(key)!=step.payload[key]:matching=false
				if matching:found=true
			check(found,id+" actual pointer input emitted accepted "+step.type+" "+JSON.stringify(step.get("payload",{})))
			if not found:return false
		elif step.op=="advance_ticks":
			var next: Dictionary=replay.steps[i+1] if i+1<replay.steps.size() else {}
			var prepare_only: bool=next.get("type","")=="StopResolution"
			if not await wait_for_client(int(step.count),prepare_only):return false
		elif step.op=="assert":
			check(app.kernel.assert_predicate(step.predicate),id+" final assertion "+step.predicate)
		if failures.size()>before_failures:return false
	for predicate in replay.get("expected_final_predicates",[]):check(app.kernel.assert_predicate(predicate),id+" expected "+predicate)
	check(app.kernel.state.phase=="SUCCESS" and app.progress.completed.has(id),id+" UI journey reaches victory and persists completion")
	journeys.append({"level":id,"success":app.kernel.state.phase=="SUCCESS","commands":app.ui_commands.duplicate(true),"tick":app.kernel.state.tick,"state_hash":app.kernel.state_hash()})
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/complex-ui-"+id+"-success.png")
	print("UI JOURNEY "+id+" actual initial→victory; "+str(app.ui_commands.size())+" UI commands")
	return failures.size()==before_failures
func command_through_ui(step: Dictionary) -> bool:
	var payload: Dictionary=step.get("payload",{})
	match step.type:
		"PlaceProp":
			if not await select_inventory(payload.entity_id):return false
			if not await click_named("ObjectContext"):return false
			if not await click_text(app.tx("ui.place_prop","Выбрать место…")):return false
			var index: int=0;var slot_label: String=""
			for slot in app.kernel.definition.slots:
				if app.kernel._entities[payload.entity_id].type_id not in slot.allowed_entity_types:continue
				if slot.id==payload.slot_id:slot_label=app._slot_name(slot,index);break
				index+=1
			if slot_label.is_empty():return false
			return await click_text(slot_label)
		"Interact":
			if not await select_inventory(payload.entity_id):return false
			if not await click_named("ObjectContext"):return false
			var action: String=payload.action
			if action=="remove":return await click_text(app.tx("ui.remove_prop","Убрать реквизит"))
			if action in ["open","close"]:return await click_text(app.tx("ui."+action,"Открыть" if action=="open" else "Закрыть"))
			check(false,"unimplemented UI test action, not product defect: "+action);return false
		"SetLawCandidate":
			if not await open_plan():return false
			if not await click_text(app.tx("ui.laws","Законы и следующий фокус")):return false
			return await click_text(app.tx("ui.prepare_show","Поставить фокус")+" · "+app._law_name(payload.myth_id))
		"BeginPerformance":
			if not await open_plan():return false
			return await click_text(app.tx("ui.perform","Показать фокус")+" · "+app._law_name(app.kernel.state.candidate_law))
		"ActivateLaw":
			await click_control(app.primary)
			if payload.get("replace_law_id")!=null:
				if app.kernel.state.phase!="LAW_SELECTION":return false
				return await click_text(app.tx("ui.replace","Заменить")+" · "+app._law_name(payload.replace_law_id))
			return true
		"AssignRoute":
			if not await open_plan():return false
			if not await click_text(("Routes" if app.settings.locale=="en" else "Маршруты")):return false
			if not await click_text(app._name(payload.actor_id)):return false
			return await click_text(app._route_name(payload.route_id))
		"RunResolution":
			if not await open_plan():return false
			return await click_text(app.tx("ui.world_run","Дать миру действовать"))
		"StopResolution":await click_control(app.primary);return true
	check(false,"unimplemented UI test command, not product defect: "+step.type);return false
func select_inventory(id: String) -> bool:
	if not await click_named("OpenObjects"):return false
	if not await click_text(app._name(id)):return false
	if app.selected!=id:check(false,"inventory button did not select expected entity "+id+"; actual="+app.selected);return false
	return true
func click_named(value: String) -> bool:
	var control=app.ui.find_child(value,true,false)
	if control==null:check(false,"semantic pointer target missing: "+value);return false
	await click_control(control);return true
func open_plan() -> bool:return await click_text(app.tx("ui.plan","План"))
func wait_for_client(ticks: int,prepare_only: bool) -> bool:
	var start: int=app.kernel.state.tick
	var deadline: int=Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<deadline:
		var phase: String=app.kernel.state.phase
		if phase in ["RECOVERABLE_FAILURE","LAW_SELECTION"]:break
		if prepare_only:
			if phase=="RUN_RESOLUTION" and app.kernel.state.tick-start>=ticks:return true
		elif phase not in ["PERFORMANCE","REHEARSAL","RUN_RESOLUTION"]:return true
		await process_frame
	check(false,"live client wait failed; phase="+app.kernel.state.phase+" tick="+str(app.kernel.state.tick)+" reason="+str(app.kernel.state.get("failure_reason","")))
	return false
func click_text(value: String) -> bool:
	var scope: Node=app.overlay if is_instance_valid(app.overlay) else app.ui
	var candidates: Array=find_buttons(scope,value)
	if candidates.size()!=1:
		check(false,"visible button path ambiguous/missing: "+value+" matches="+str(candidates.size()));return false
	await click_control(candidates[0]);return true
func find_buttons(node: Node,value: String) -> Array:
	var found: Array=[]
	if node is BaseButton and normalize(node.text)==normalize(value):found.append(node)
	for child in node.get_children():found.append_array(find_buttons(child,value))
	return found
func normalize(value: String) -> String:return " ".join(value.replace("\n"," ").split(" ",false))
func click_control(control: Control) -> void:
	# Native scroll navigation for offscreen controls; game actions still use real input dispatch.
	var ancestor: Node=control.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:ancestor.ensure_control_visible(control)
		ancestor=ancestor.get_parent()
	await process_frame;await process_frame
	var position: Vector2=control.get_global_rect().get_center()
	var move=InputEventMouseMotion.new();move.position=position;move.global_position=position;Input.parse_input_event(move)
	var press=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.position=position;press.global_position=position;press.pressed=true;Input.parse_input_event(press);pointer_events+=1
	await process_frame
	var release=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.position=position;release.global_position=position;release.pressed=false;Input.parse_input_event(release);pointer_events+=1
	await process_frame;await process_frame
func finish() -> void:
	Engine.time_scale=1
	if is_instance_valid(app):
		await create_timer(.08).timeout;app.audio.shutdown();app.audio.free();app.free()
	await create_timer(.15).timeout
	print("COMPLEX UI JOURNEYS: %d checks; %d failures; %d pointer events"%[checks,failures.size(),pointer_events])
	for issue in failures:printerr("FAIL: "+issue)
	var f=FileAccess.open("res://tests/reports/complex-ui-journeys.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"journeys":journeys,"pointer_events":pointer_events,"engine":Engine.get_version_info().string,"input":"Input.parse_input_event mouse press/release; no pressed-signal shortcut","initial_fixture":"unlocked profile30, authored load from tick0; no progressed snapshots","simulation_time_scale":8,"scroll_navigation":"native ensure_control_visible; separate touch gesture suite validates physical pan","human_usability_or_device_test":false},"  "));f.close()
	quit(0 if failures.is_empty() else 1)
func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message)
