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
	var steps: Array=[
		{"button":app._name("float")},{"slot":"stage_float"},
		{"button":app._name("stone")},{"slot":"stage_stone"},
		{"button":app._name("screen_a")},{"slot":"screen_left"},
		{"primary":true}]
	for step in steps:
		if step.has("button"):
			if not await click_text(step.button):await finish();return
		elif step.has("slot"):await tap_slot(step.slot)
		else:await click_control(app.primary)
	check(app.kernel.state.entities.float.slot=="stage_float" and app.kernel.state.entities.stone.slot=="stage_stone" and app.kernel.state.entities.screen_a.slot=="screen_left","L01 pointer placement uses the three selected stage slots")
	if not await wait_phase("PROOF_ACCEPTED",6):await finish();return
	check(app.kernel.state.proofs.M01.votes==3,"L01 live show gathers three genuine witness votes")
	check(app.primary.text=="Закрепить чудо" and (app.instruction.text.contains("не закончено") or app.instruction.text.contains("ещё не победа")),"after the first trick the player sees that the quest still needs sealing and a real goal")
	await click_control(app.primary)
	check(app.kernel.state.active_laws==["M01"] and app.kernel.state.phase=="PLAN_RESOLUTION","pointer seal commits M01 before cosmetic transformation")
	check(app.instruction.text.contains("Маршруты") and app.instruction.text.contains("Феликс"),"after sealing the guide identifies the route menu and the actor who must cross")
	if not await click_text(app._name("float")):await finish();return
	await click_control(app.primary)
	if not await click_text(app.tx("ui.remove_prop","Убрать реквизит")):await finish();return
	check(app.kernel.state.entities.float.removed,"context-menu pointer removes the obsolete hidden method")
	if not await click_text(app._name("stone")):await finish();return
	await tap_slot("bridge")
	if not await click_text(app.tx("ui.plan","План")):await finish();return
	if not await click_text(("Routes" if app.settings.locale=="en" else "Маршруты")):await finish();return
	if not await click_text(app._name("hero")):await finish();return
	if not await click_text(app._route_name("cross")):await finish();return
	check(app.kernel.state.routes.has("hero"),"actor and route menus bind the requested route")
	await click_control(app.primary)
	if not await wait_phase("SUCCESS",7):await finish();return
	check(app.kernel.evaluate("route_completed",{"actor_id":"hero","route_id":"cross"}) and app.kernel.state.goals.float_removed,"L01 completes actual navigation and mandatory construction goals")
	check(app.progress.completed.has("L01") and app.progress.unlocked==2,"successful pointer journey unlocks the next level")
	check(is_instance_valid(app.overlay),"victory panel is visible after the completed journey")
	_commands_l01=app.ui_commands.duplicate(true)
	if not await click_text("Начать уровень 2"):await finish();return
	check(app.level_number==2 and app.kernel.state.level_id=="L02" and app.kernel.state.phase=="PLAN_SHOW","victory next-level button starts a fresh L02 quest")
	var saved_progress: Dictionary=app.saver.read_slot("progress")
	check(saved_progress.current_level==2 and saved_progress.completed.has("L01") and int(saved_progress.unlocked)>=2,"L01 completion and L02 transition survive a save reload")
	check(is_instance_valid(app.overlay),"next scene opens its own understandable briefing")

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
	# Mobile touch drags reach the compact audience and inventory without selecting
	# the buttons under the finger. The sticky controls never join that scroll.
	Input.emulate_touch_from_mouse=true;Input.emulate_mouse_from_touch=true
	check(DisplayServer.is_touchscreen_available(),"headless fixture enables the engine touchscreen capability before genuine touch events")
	app.settings.accessibility.text_scale=1.4;app.start_level(30,false);app._close_overlay();await process_frame;await process_frame
	var primary_rect: Rect2=app.primary.get_global_rect()
	var stage_rect: Rect2=app.stage.get_global_rect()
	var dock_rect: Rect2=app._upper_scroll.get_global_rect()
	var initial_scroll: int=app._upper_scroll.scroll_vertical
	await touch_drag(dock_rect.get_center()+Vector2(0,80),dock_rect.get_center()-Vector2(0,200))
	var dock_bar: VScrollBar=app._upper_scroll.get_v_scroll_bar()
	if dock_bar.max_value>dock_bar.page:
		check(app._upper_scroll.scroll_vertical>initial_scroll,"real mobile vertical drag reveals overflowing quest details")
	check(app.primary.get_global_rect()==primary_rect and app.stage.get_global_rect()==stage_rect,"stage and primary remain fixed while quest details scroll")
	var audience_rect: Rect2=app._audience_scroll.get_global_rect()
	var witnesses_visible: bool=true
	for card in app.witness_labels.values():witnesses_visible=witnesses_visible and audience_rect.encloses(card.name.get_parent().get_global_rect())
	check(witnesses_visible and app._audience_scroll.scroll_horizontal==0,"all three witnesses and their status badges are visible together without panning")
	await process_frame;await process_frame
	var tray_rect: Rect2=app._inventory_scroll.get_global_rect()
	check(tray_rect.position.y>=0 and tray_rect.end.y<=app.get_viewport_rect().size.y+1,"landscape inventory is visible without moving the stage")
	await touch_drag(Vector2(tray_rect.end.x-80,tray_rect.get_center().y),Vector2(tray_rect.position.x+80,tray_rect.get_center().y))
	check(app._inventory_scroll.scroll_horizontal>0 and app.selected.is_empty(),"mobile inventory pan scrolls without accidentally selecting a prop")
	# Settings wrappers pass vertical touch scroll too; a drag over an option must
	# not toggle it, and 140% labels/slider rows keep their separate hit areas.
	app._open_settings();await process_frame;await process_frame
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
	await finish()
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
	if is_instance_valid(app):
		await create_timer(.08).timeout
		app.audio.shutdown();app.audio.free();app.free()
	await create_timer(.15).timeout
	print("NATIVE POINTER UI: %d checks; %d failures; %d pointer events"%[count,failures.size(),_pointer_events])
	for issue in failures:printerr("FAIL: "+issue)
	var report=FileAccess.open("res://tests/reports/ui-pointer.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":count,"failures":failures,"pointer_events":_pointer_events,"touch_events":_touch_events,"L01_ui_commands":_commands_l01,"L30_scope":"actual pointer cancel/close after authored third-proof fixture; not a full L30 pointer journey","engine":Engine.get_version_info().string},"  "));report.close()
	quit(0 if failures.is_empty() else 1)
func check(passed: bool,message: String) -> void:
	count+=1
	if not passed:failures.append(message)
