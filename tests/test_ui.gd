extends SceneTree
## Native Control input: real pointer events, no pressed-signal shortcut or core replay for L01.
const App=preload("res://tests/pointer_app_host.gd")
const Audio=preload("res://services/audio_service.gd")
var failures: Array[String]=[]
var count: int=0
var app: Control
var _pointer_events: int=0
var _touch_events: int=0
var _commands_l01: Array=[]
var _commands_l02: Array=[]
func _initialize() -> void:call_deferred("run")
func fixture():
	var game=App.new()
	game.settings=JSON.parse_string(FileAccess.get_file_as_string("res://data/settings_default.json"))
	game.theme=preload("res://presentation/theme.gd").make_theme()
	var player=Audio.new();root.add_child(player);player.configure(game.settings.audio);game.audio=player
	game.progress={"schema_version":1,"unlocked":1,"completed":{},"current_level":1}
	game._capture_stage="fixture"
	for n in range(1,31):game.level_ids.append("L%02d"%n)
	game.catalog=JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/ru.json"))
	game.size=Vector2(1920,1080);root.add_child(game)
	return game
func run() -> void:
	root.size=Vector2i(1920,1080);root.content_scale_size=Vector2i(1920,1080)
	app=fixture();app.start_level(1,false);app._close_overlay();app._capture_stage=""
	await process_frame;await process_frame
	if not await click_named("ObjectiveTicket"):await finish();return
	check(collect_text(app.overlay).contains("Марф"),"objective journal gives the concrete bakery task before manipulation")
	if not await click_last_action():await finish();return
	# A shared observer/actor body must expose inspection without a precise eye-pin tap.
	var observer_truth: String=app.kernel.state_hash()
	var observer_position: Array=app.kernel.state.entities.marfa.position.duplicate()
	await tap(app.stage.get_global_transform()*(app.stage.entity_display_position("marfa")+Vector2(0,-130)))
	check(app.selected=="marfa","shared Marfa body pointer input selects the actor, not an unrelated prop")
	if not await click_named("ObjectContext"):await finish();return
	var observer_view=find_button(app.overlay,"Проверить обзор")
	check(observer_view!=null,"shared actor context exposes the observer view advertised by onboarding")
	if observer_view==null:await finish();return
	await click_control(observer_view)
	check(app.inspected=="w1" and app.stage.inspected=="w1" and app.instruction.text.contains("Марф"),"actor context enables the real witness rays and visible diagnostic")
	check(app.kernel.state_hash()==observer_truth and app.kernel.state.entities.marfa.position==observer_position and app.kernel.state.routes.is_empty(),"observer inspection neither moves the actor nor changes proof or route state")
	# A visible mechanism must fail, preserving a recoverable task and a truthful explanation.
	await click_control(app.primary)
	if not await click_named("PauseSettings"):await finish();return
	var paused_tick: int=app.kernel.state.tick
	await create_timer(.15).timeout
	check(app.kernel.state.tick==paused_tick,"opening settings pauses an active demonstration at its current logical time")
	if not await click_last_action():await finish();return
	Engine.time_scale=6
	if not await wait_phase("RECOVERABLE_FAILURE",7):await finish();return
	check(app.kernel.state.failure_reason=="METHOD_VISIBLE","first failed trial names the visible float, not belief or a generic penalty")
	await click_control(app.primary)
	check(app.kernel.state.phase=="PLAN_SHOW" and not app.kernel.state.entities.float.removed,"free undo restores the exact preparation")
	if not await select_object("screen_a"):await finish();return
	await tap_slot("screen_left")
	check(app.kernel.state.entities.screen_a.slot=="screen_left","real stage slot tap places the screen in front")
	await click_control(app.primary)
	if not await wait_phase("RECOVERABLE_FAILURE",7):await finish();return
	check(app.kernel.state.failure_reason=="RESULT_OBSCURED","tall screen failure explains that the stone is also hidden")
	await click_control(app.primary)
	if not await select_object("screen_a"):await finish();return
	if not await click_named("ObjectContext"):await finish();return
	if not await click_text(app._uxt("fold_top","Сложить верх","Fold the top")):await finish();return
	check(app.kernel.state.entities.screen_a.folded,"context action folds only the selected screen")
	if not await click_named("UndoAction"):await finish();return
	check(not app.kernel.state.entities.screen_a.folded and app.kernel.state.entities.screen_a.slot=="screen_left","one undo reverses folding, retaining previous placement")
	if not await select_object("screen_a"):await finish();return
	if not await click_named("ObjectContext"):await finish();return
	if not await click_text(app._uxt("fold_top","Сложить верх","Fold the top")):await finish();return
	await click_control(app.primary)
	if not await wait_phase("PROOF_ACCEPTED",7):await finish();return
	check(app.kernel.state.proofs.M01.votes==1 and app.kernel.state.active_laws.is_empty(),"one genuine observer validates the trial without silently changing the law")
	check(app._hud_copy().stage_number==2 and not app.primary.disabled,"successful demonstration exposes a separate enabled law action")
	await click_control(app.primary)
	check(app.kernel.state.active_laws==["M01"] and app.kernel.state.phase=="PLAN_RESOLUTION","explicit law button changes the world before any crossing")
	check(not app.kernel.state.entities.float.removed and app.kernel.state.routes.is_empty(),"sealing cannot hide the old support or route Marfa automatically")
	await tap(app.stage.get_global_transform()*(app.stage.entity_display_position("marfa")+Vector2(0,-130)))
	if not await click_named("ObjectContext"):await finish();return
	check(find_button(app.overlay,"Проверить обзор")!=null and find_button(app.overlay,app.tx("ui.assign_route","Назначить маршрут…"))!=null,"the shared actor retains both view inspection and legitimate route actions during application")
	if not await click_last_action():await finish();return
	check(str(app._hud_copy().get("primary_intent",""))=="remove_l01_float","guide names removal as the next actual action")
	await click_control(app.primary)
	check(app.kernel.state.entities.float.removed and app.kernel.state.entities.stone.support,"explicit support removal leaves the magic stone supported")
	check(app.kernel.state.routes.is_empty() and app.kernel.state.phase!="SUCCESS","support check remains separate from useful crossing")
	await click_control(app.primary)
	check(app.kernel.state.routes.has("marfa") and app.kernel.state.phase=="RUN_RESOLUTION","explicit crossing button starts the real Marfa route")
	if not await wait_phase("SUCCESS",7):await finish();return
	check(app.kernel.evaluate("route_completed",{"actor_id":"marfa","route_id":"cross"}) and app.kernel.state.goals.float_removed,"victory requires the actual Marfa navigation and support removal")
	check(app.progress.completed.has("L01") and app.progress.unlocked==2,"successful pointer journey persists progress and unlocks level2")
	check(is_instance_valid(app.overlay),"victory panel appears only after the completed journey")
	_commands_l01=app.ui_commands.duplicate(true)
	if not await click_last_action():await finish();return
	check(app.level_number==2 and app.kernel.state.level_id=="L02" and app.kernel.state.active_laws==["M01"],"victory transition starts the anchor follow-up with its explicitly transferred law")
	var saved_progress: Dictionary=app.saver.read_slot("progress")
	check(saved_progress.current_level==2 and saved_progress.completed.has("L01") and int(saved_progress.unlocked)>=2,"L01 completion and L02 transition survive a save reload")
	check(is_instance_valid(app.overlay),"the new anchor task opens a concrete briefing")
	if not await click_last_action():await finish();return
	if not await select_object("mooring"):await finish();return
	if not await click_named("ObjectContext"):await finish();return
	if not await click_text(app.tx("ui.attach","Прикрепить к предмету…")):await finish();return
	if not await click_text(app._name("bollard")):await finish();return
	check(app.kernel.state.entities.boat.moored,"real context input ties the boat to grounded wood after the stone anchor floated")
	if not await click_named("OpenPlan"):await finish();return
	if not await click_text("Маршруты"):await finish();return
	if not await click_text(app._name("cargo")):await finish();return
	if not await click_text(app._route_name("unload")):await finish();return
	await click_control(app.primary)
	if not await wait_phase("SUCCESS",7):await finish();return
	check(app.progress.completed.has("L02") and app.progress.unlocked==3,"anchor task is playable to victory and opens the third experiment")
	_commands_l02=app.ui_commands.slice(_commands_l01.size())

	# Only a typed switchable source advertises a real toggle; heated objects are not switches.
	app._capture_stage="fixture";app.start_level(11,false);app._close_overlay()
	if not await select_object("oven"):await finish();return
	if not await click_named("ObjectContext"):await finish();return
	check(find_button(app.overlay,app.tx("ui.disable","Выключить источник"))!=null,"switchable oven exposes a reachable native disable action")
	if not await click_text(app.tx("ui.disable","Выключить источник")):await finish();return
	check(not app.kernel.state.entities.oven.enabled,"native advertised disable action changes the authoritative source")
	check(not app.saver.read_slot("progress").checkpoint.entities.oven.enabled,"source switch state is committed to a real saved checkpoint")
	if not await select_object("oven"):await finish();return
	if not await click_named("ObjectContext"):await finish();return
	if not await click_text(app.tx("ui.enable","Включить источник")):await finish();return
	check(app.kernel.state.entities.oven.enabled,"native context changes to the inverse enable action")
	if not await click_named("UndoAction"):await finish();return
	check(not app.kernel.state.entities.oven.enabled,"one native undo restores the prior switched source state")
	if not await select_object("cold_pack"):await finish();return
	if not await click_named("ObjectContext"):await finish();return
	check(find_button(app.overlay,app.tx("ui.disable","Выключить источник"))==null and find_button(app.overlay,app.tx("ui.enable","Включить источник"))==null,"chemical cold pack has no invented power switch")
	app._close_overlay();app.start_level(15,false);app._close_overlay()
	if not await select_object("heated_stone"):await finish();return
	if not await click_named("ObjectContext"):await finish();return
	check(find_button(app.overlay,app.tx("ui.disable","Выключить источник"))==null and find_button(app.overlay,app.tx("ui.enable","Включить источник"))==null,"a warm stone is inspected or moved, never switched off by an unsupported command")
	app._close_overlay()

	await phase_type_contract()

	# L30 cancellation fixture reaches its real third proof through authored commands.
	app._capture_stage="fixture";app.start_level(30,false);app._close_overlay()
	var replay: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/replays/L30_solution.json"))
	for step in replay.steps:
		if step.op=="command":
			if step.type=="ActivateLaw" and step.payload.myth_id=="M03":break
			var response: Dictionary=app.kernel.dispatch(step)
			if not response.accepted:check(false,"L30 fixture command rejected "+step.type);await finish();return
		elif step.op=="advance_ticks":app.kernel.advance_ticks(int(step.count))
	app._update_ui();await process_frame
	check(app.kernel.state.phase=="PROOF_ACCEPTED" and app.kernel.state.active_laws.size()==2,"L30 fixture contains a real accepted third proof and two active laws")
	var before: String=app.kernel.state_hash()
	await click_control(app.primary)
	check(app.kernel.state.phase=="LAW_SELECTION" and is_instance_valid(app.overlay),"pointer seal opens explicit replacement selection")
	if not await click_text(app.tx("ui.cancel","Отмена")):await finish();return
	check(app.kernel.state_hash()==before,"pointer Cancel preserves the exact previous law world")
	await click_control(app.primary)
	if not await click_text(app.tx("ui.close","Вернуться")):await finish();return
	check(app.kernel.state_hash()==before,"generic dialog close also cancels law selection atomically")
	# Both text sizes retain minimum touch targets and readable wrapped option labels.
	for scale_value in [1.0,1.4]:
		app.settings.accessibility.text_scale=scale_value;app._build_ui();app._update_ui();app._close_overlay();await process_frame
		check(app.primary.size.y>=144,"primary hit target remains at least 144 units at text scale "+str(scale_value))
		app._slot_menu("weight");await process_frame
		var buttons: Array=all_buttons(app.overlay)
		var wrapped_ok: bool=true
		for button in buttons:
			wrapped_ok=wrapped_ok and button.size.y>=144 and not button.text.contains("{capacity}")
		check(wrapped_ok,"localized options have full touch targets at text scale "+str(scale_value))
		app._close_overlay()
	app._set_subtitles(false);app._set_subtitles(true)
	app._caption("CH03","accept")
	check(app._caption_panel.visible and app._caption_label.text.contains(app._character_name("CH03")),"subtitles show the speaking character and vocal reaction")
	var caption_before: String=app._caption_label.text
	app._build_ui();app._update_ui()
	check(app._caption_label.text==caption_before and app._caption_panel.visible,"HUD reflow preserves an active subtitle and its display clock")
	var instruction_before: String=app.instruction.text
	app._set_subtitles(false)
	check(not app._caption_panel.visible and app.instruction.text==instruction_before,"subtitles off hides captions while preserving gameplay instructions")
	# The modern HUD retains a full scene; long inventory moves into a deliberate drawer.
	Input.emulate_touch_from_mouse=true;Input.emulate_mouse_from_touch=true
	check(DisplayServer.is_touchscreen_available(),"test fixture enables native touch capability")
	app.settings.accessibility.text_scale=1.4;app.start_level(30,false);app._close_overlay();await process_frame;await process_frame
	var primary_rect: Rect2=app.primary.get_global_rect()
	var stage_rect: Rect2=app.stage.get_global_rect()
	check(stage_rect==app.get_viewport_rect(),"new stage occupies the full native canvas")
	if not await click_named("OpenObjects"):await finish();return
	await process_frame;await process_frame
	var tray_rect: Rect2=app._inventory_scroll.get_global_rect()
	var truth: String=app.kernel.state_hash()
	await touch_drag(Vector2(tray_rect.end.x-20,tray_rect.end.y-60),Vector2(tray_rect.end.x-20,tray_rect.position.y+40))
	check(app._inventory_scroll.scroll_vertical>0 and app.selected.is_empty(),"native vertical inventory drag scrolls without selecting an item")
	check(app.kernel.state_hash()==truth and app.primary.get_global_rect()==primary_rect and app.stage.get_global_rect()==stage_rect,"drawer scrolling preserves world truth and underlying fixed scene/action")
	app._close_overlay()
	# Settings wrappers pass vertical touch scroll too; a drag over an option must
	# not toggle it, and 140% labels/slider rows keep their separate hit areas.
	app._open_settings("audio");await process_frame;await process_frame
	var settings_scroll: ScrollContainer=null
	for child in app.overlay.get_children():
		if child is ScrollContainer:settings_scroll=child
	var previous_audio: Dictionary=app.settings.audio.duplicate(true)
	var bounds_ok: bool=true
	for slider in find_sliders(app.overlay):
		var card: Control=slider.get_parent()
		for sibling in card.get_children():
			if sibling is CheckButton:bounds_ok=bounds_ok and sibling.position.y+sibling.size.y<=slider.position.y
			if sibling is Label and sibling.position.y==0:bounds_ok=bounds_ok and sibling.position.y+sibling.size.y<=slider.position.y
	check(bounds_ok,"settings 140% category labels/toggles never overlap slider touch targets")
	var panel_rect: Rect2=settings_scroll.get_global_rect()
	await touch_drag(Vector2(panel_rect.end.x-20,panel_rect.position.y+panel_rect.size.y*.8),Vector2(panel_rect.end.x-20,panel_rect.position.y+panel_rect.size.y*.2))
	check(settings_scroll.scroll_vertical>0,"real vertical touch drag scrolls the settings sheet")
	check(app.settings.audio==previous_audio,"scrolling settings on its right margin does not accidentally change audio values")
	var settings_truth: String=app.kernel.state_hash()
	var was_muted: bool=app.settings.audio.master_muted
	if not await click_text(app.tx("ui.all_sound","Весь звук")):await finish();return
	check(app.settings.audio.master_muted!=was_muted and app.saver.read_slot("settings").audio.master_muted==app.settings.audio.master_muted,"native sound toggle applies and persists the player's actual audio choice")
	if not await click_text(app.tx("ui.all_sound","Весь звук")):await finish();return
	if not await click_text(app._uxt("settings_text_tab","Текст","Text")):await finish();return
	check(app._settings_section=="accessibility" and find_button(app.overlay,"140%")!=null,"accessibility opens directly without scrolling audio channels")
	if not await click_text(app.tx("ui.reduced_motion","Уменьшить движение")):await finish();return
	check(app.settings.accessibility.reduced_motion and app.stage.reduced_motion,"native reduced-motion toggle reaches the illustrated stage")
	check(app.kernel.state_hash()==settings_truth,"settings changes cannot mutate puzzle truth")
	# An incompatible checkpoint restarts only the current task, preserving completed levels.
	app._capture_stage="fixture";app.start_level(2,false);app._close_overlay()
	var old_checkpoint: Dictionary=app.kernel.snapshot();old_checkpoint.rules_version="0.2.0-recovered"
	app.progress={"schema_version":1,"unlocked":3,"completed":{"L01":{"stars":1}},"current_level":2,"checkpoint":old_checkpoint,"story_started":true}
	check(app.start_level(2,true) and app._checkpoint_reset_pending,"incompatible old checkpoint is detected during actual resume")
	app._show_title();await process_frame
	var enter=app.overlay.find_child("EnterStory",true,false)
	check(enter!=null and normalize(enter.text).contains("Продолжить"),"resuming player sees Continue in the real menu")
	if enter!=null:await click_control(enter)
	check(is_instance_valid(app.overlay) and collect_text(app.overlay).contains("открытые уровни сохранены"),"resume visibly explains current experiment restart")
	check(app.progress.unlocked==3 and app.progress.completed.has("L01") and app.kernel.state.tick==0,"checkpoint migration preserves unlocked/completed progression")
	await finish()
func collect_text(node: Node) -> String:
	var result: String=node.text if node is Label else ""
	for child in node.get_children():result+="\n"+collect_text(child)
	return result
func select_object(id: String) -> bool:
	if not await click_named("OpenObjects"):return false
	if not await click_text(app._name(id)):return false
	check(app.selected==id,"objects drawer selects "+id)
	return app.selected==id
func click_named(value: String) -> bool:
	var control=app.ui.find_child(value,true,false)
	if control==null:check(false,"semantic target missing: "+value);return false
	await click_control(control);return true
func click_last_action() -> bool:
	var buttons: Array=all_buttons(app.overlay)
	if buttons.is_empty():check(false,"modal has no reachable main action");return false
	await click_control(buttons[-1]);return true
func phase_type_contract() -> void:
	# Inspect actual native choices, keeping puzzle errors distinct from impossible API calls.
	app.start_level(11,false);app._close_overlay();app._plan_menu();await process_frame
	check(app.ui.find_child("UndoAction",true,false).disabled,"fresh experiment disables Undo while authoritative history is empty")
	check(find_button(app.overlay,"Маршруты")==null and find_button(app.overlay,app.tx("ui.world_run","Дать миру действовать"))==null,"preparation offers no routes or resolution command that the kernel forbids in PLAN_SHOW")
	app._close_overlay();app._object_menu("hero");await process_frame
	check(find_button(app.overlay,app.tx("ui.assign_route","Назначить маршрут…"))==null,"a planning-stage person context does not advertise AssignRoute")
	app._close_overlay();app._witness_menu("w1");await process_frame
	check(witness_slot_choice_exists(),"a regular observer can still choose a declared view during preparation")
	app._close_overlay();check(app._command("BeginPerformance"),"phase matrix starts a real demonstration")
	app._witness_menu("w1");await process_frame
	check(not witness_slot_choice_exists(),"an active demonstration exposes viewing information without forbidden reseating")
	app._close_overlay();app.start_level(3,false);app._close_overlay()
	var fixed_id: String=""
	for witness in app.kernel.definition.witnesses:
		if witness.views.size()>1:fixed_id=witness.id;break
	check(not fixed_id.is_empty(),"authored multi-view inspector exists in L03")
	if not fixed_id.is_empty():
		app._witness_menu(fixed_id);await process_frame
		check(not witness_slot_choice_exists(),"a fixed multi-view inspection route is read-only rather than an unsupported seat command")
	app._close_overlay();app.start_level(2,false);app._close_overlay();app._plan_menu();await process_frame
	check(find_button(app.overlay,"Маршруты")!=null and find_button(app.overlay,app.tx("ui.world_run","Дать миру действовать"))!=null,"resolution retains both useful routes and the actual world-run action")
	app._close_overlay();app._object_menu("cargo");await process_frame
	check(find_button(app.overlay,app.tx("ui.assign_route","Назначить маршрут…"))!=null,"resolution cargo keeps its real route action")
	app._close_overlay();app._attachment_menu("mooring");await process_frame
	var types: Array=app.kernel._entities.mooring.properties.get("attachable_target_types",[])
	for id in app.kernel._entities:
		if id=="mooring" or app.kernel.state.entities[id].removed:continue
		var expected: bool=types.is_empty() or app.kernel._entities[id].type_id in types
		check((find_button(app.overlay,app._name(id))!=null)==expected,"mooring native choices respect declared target types: "+str(id))
	app._close_overlay()
	check(app._command("Interact",{"entity_id":"mooring","action":"attach","target_entity_id":"bollard"}) and app._command("AssignRoute",{"actor_id":"cargo","route_id":"unload"}) and app._command("RunResolution"),"pending-route fixture uses valid authored commands")
	app._plan_menu();await process_frame
	check(find_button(app.overlay,app.tx("ui.stop_resolution","Вернуться к плану"))==null and find_button(app.overlay,app.tx("ui.undo_short","Откат"))!=null,"pending route exposes valid free Undo instead of forbidden StopResolution")
	if await click_text(app.tx("ui.undo_short","Откат")):
		check(app.kernel.state.phase=="PLAN_RESOLUTION","native pending-run Undo actually returns to a stable resolution plan")
	app._close_overlay()
func witness_slot_choice_exists() -> bool:
	var index: int=0
	for slot in app.kernel.definition.slots:
		if "witness" not in slot.allowed_entity_types:continue
		if find_button(app.overlay,app._slot_name(slot,index))!=null:return true
		index+=1
	return false
func find_sliders(node: Node) -> Array:
	var result: Array=[]
	if node is HSlider:result.append(node)
	for child in node.get_children():result.append_array(find_sliders(child))
	return result
func touch_drag(from: Vector2,to: Vector2) -> void:
	var press=InputEventScreenTouch.new();press.index=0;press.position=from;press.pressed=true;Input.parse_input_event(press);_touch_events+=1
	await process_frame
	var previous: Vector2=from
	for i in range(1,9):
		var point: Vector2=from.lerp(to,float(i)/8)
		var drag=InputEventScreenDrag.new();drag.index=0;drag.position=point;drag.relative=point-previous;drag.velocity=(point-previous)*60;Input.parse_input_event(drag);_touch_events+=1;previous=point
		await process_frame
	var release=InputEventScreenTouch.new();release.index=0;release.position=to;release.pressed=false;Input.parse_input_event(release);_touch_events+=1
	await create_timer(.12).timeout
func wait_phase(wanted: String,timeout: float) -> bool:
	var deadline: int=Time.get_ticks_msec()+int(timeout*1000)
	while app.kernel.state.phase!=wanted and Time.get_ticks_msec()<deadline:await process_frame
	var passed: bool=app.kernel.state.phase==wanted
	check(passed,"live client reaches "+wanted+" before timeout; actual="+app.kernel.state.phase)
	return passed
func click_text(value: String) -> bool:
	var scope: Node=app.overlay if is_instance_valid(app.overlay) else app.ui
	var button=find_button(scope,value)
	if button==null:
		check(false,"pointer target not found: "+value)
		return false
	await click_control(button)
	return true
func find_button(node: Node,value: String):
	if node is BaseButton and normalize(node.text)==normalize(value):return node
	for child in node.get_children():
		var found=find_button(child,value)
		if found!=null:return found
	return null
func normalize(value: String) -> String:return " ".join(value.replace("\n"," ").split(" ",false))
func all_buttons(node: Node) -> Array:
	var result: Array=[]
	if node is BaseButton:result.append(node)
	for child in node.get_children():result.append_array(all_buttons(child))
	return result
func click_control(control: Control) -> void:
	var ancestor: Node=control.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:ancestor.ensure_control_visible(control)
		ancestor=ancestor.get_parent()
	await process_frame;await process_frame
	await tap(control.get_global_rect().get_center())
func tap_slot(id: String) -> void:
	await process_frame;await process_frame
	await tap(app.stage.get_global_transform()*app.stage.world(app.kernel._slots[id].position))
func tap(position: Vector2) -> void:
	var move=InputEventMouseMotion.new();move.position=position;move.global_position=position;Input.parse_input_event(move)
	var press=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.position=position;press.global_position=position;press.pressed=true;Input.parse_input_event(press);_pointer_events+=1
	await process_frame
	var release=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.position=position;release.global_position=position;release.pressed=false;Input.parse_input_event(release);_pointer_events+=1
	await process_frame;await process_frame
func finish() -> void:
	Engine.time_scale=1
	if is_instance_valid(app):
		await create_timer(.08).timeout
		app.audio.shutdown();app.audio.free();app.free()
	await create_timer(.15).timeout
	print("NATIVE POINTER UI: %d checks; %d failures; %d pointer events"%[count,failures.size(),_pointer_events])
	for issue in failures:printerr("FAIL: "+issue)
	var report=FileAccess.open("res://tests/reports/ui-pointer.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":count,"failures":failures,"pointer_events":_pointer_events,"touch_events":_touch_events,"L01_ui_commands":_commands_l01,"L02_ui_commands":_commands_l02,"contract_matrix":"Native menu choices with explicit isolated kernel setup; separate from the full L01/L02 pointer journey","L30_scope":"actual pointer cancel/close after authored third-proof fixture; not a full L30 pointer journey","engine":Engine.get_version_info().string},"  "));report.close()
	quit(0 if failures.is_empty() else 1)
func check(passed: bool,message: String) -> void:
	count+=1
	if not passed:failures.append(message)
