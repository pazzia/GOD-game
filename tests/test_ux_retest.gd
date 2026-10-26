extends SceneTree
## UX regressions through native Control input, with explicit known-state fixtures.
## This is not a fresh-player, physical Android or full-campaign playtest.
const App=preload("res://tests/pointer_app_host.gd")
const Audio=preload("res://services/audio_service.gd")
const Guide=preload("res://presentation/quest_guide.gd")
var app: Control
var count: int=0
var failures: Array[String]=[]
var pointer_events: int=0
var key_events: int=0
func _initialize() -> void:call_deferred("run")
func fixture() -> Control:
	var game=App.new()
	game.settings=JSON.parse_string(FileAccess.get_file_as_string("res://data/settings_default.json"))
	game.theme=preload("res://presentation/theme.gd").make_theme()
	game.progress={"schema_version":1,"unlocked":30,"completed":{},"current_level":1,"story_started":true}
	game._capture_stage="fixture"
	for number in range(1,31):game.level_ids.append("L%02d"%number)
	game.catalog=JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/ru.json"))
	var sound=Audio.new();root.add_child(sound);sound.configure(game.settings.audio);game.audio=sound
	game.size=Vector2(1920,1080);root.add_child(game)
	return game
func run() -> void:
	root.size=Vector2i(1920,1080);root.content_scale_size=Vector2i(1920,1080)
	app=fixture()
	if not await placement_flow():await finish();return
	if not await plan_flow():await finish();return
	if not await blocked_plan_and_help():await finish();return
	if not await pause_and_accessibility():await finish();return
	await number_layouts()
	await finish()
func fresh(number: int) -> void:
	app._capture_stage="fixture";app.start_level(number,false);app._close_overlay()
	await process_frame;await process_frame
func placement_flow() -> bool:
	await fresh(1)
	check(app.instruction.text.contains("Предмет"),"PLR-001 first instruction names the closed objects drawer before a screen exists on stage")
	var truth: String=app.kernel.state_hash()
	Guide.describe(app.kernel,"ru",1,30,"",app.catalog)
	check(truth==app.kernel.state_hash(),"explaining the next action cannot solve or change the experiment")
	if not await select_object("screen_a"):return false
	check(app.stage.placement_entity=="screen_a","tray selection enters an explicit placement mode")
	truth=app.kernel.state_hash()
	await tap(app.stage.get_global_transform()*app.stage.entity_display_position("stone"))
	check(app.kernel.state_hash()==truth and app.selected=="screen_a" and app.stage.placement_entity=="screen_a","PLR-004 invalid placement preserves the chosen object and puzzle state")
	check(is_instance_valid(app.overlay) and not collect_text(app.overlay).strip_edges().is_empty(),"invalid placement gives a visible explanation rather than silently selecting the stone")
	if is_instance_valid(app.overlay):await escape_key()
	await tap_slot("screen_left")
	check(app.kernel.state.entities.screen_a.slot=="screen_left","a real valid marker click places the chosen screen")
	check(app.stage.placement_entity.is_empty(),"accepted placement leaves explicit placement mode")
	if not await click_named("UndoAction"):return false
	check(app.kernel.state.entities.screen_a.slot=="tray_screen_a","free undo restores the actual pre-placement state")
	check(app.instruction.text.contains("Предмет"),"PLR-001 instruction returns to the available first step after undo")
	# Occupied painted objects must not steal a valid placement marker.
	await fresh(3)
	if not await select_object("float"):return false
	await tap_slot("stage_float")
	if not await select_object("stone"):return false
	await tap_slot("stage_stone")
	check(app.kernel.state.entities.stone.slot=="stage_stone" and app.kernel.state.entities.float.slot=="stage_float","PLR-004 stone can be placed over its already positioned support by real marker input")
	check(app.stage.placement_entity.is_empty(),"placing on an occupied valid position exits placement mode without changing selection to the support")
	var intro: String=app.tx("level.L03.intro","").to_lower()
	check((intro.contains("щит") or intro.contains("жёстк")) and intro.contains("не складыв"),"PLR-005 the real L03 briefing explains why its rigid screens differ from the tutorial")
	return true
func plan_flow() -> bool:
	await fresh(2)
	var truth: String=app.kernel.state_hash()
	if not await click_named("OpenPlan"):return false
	check(find_named("PlanSummary") is Label,"PLR-003 plan opens an authoritative summary before choosing another actor")
	check(truth==app.kernel.state_hash(),"opening a plan summary cannot execute or assign an action")
	if not await click_named("PlanRoutes"):return false
	if not await click_text(app._name("cargo")):return false
	if not await click_text(app._route_name("unload")):return false
	check(app.kernel.state.routes.has("cargo") and not app.kernel.state.routes.cargo.completed,"real route-menu clicks assign unloading without declaring the delivery complete")
	var prior_attachment: String=str(app.kernel.state.entities.mooring.get("attachment_target",""))
	if not await select_object("mooring"):return false
	if not await click_named("ObjectContext"):return false
	if not await click_text(app.tx("ui.attach","Прикрепить к предмету…")):return false
	if not await click_text(app._name("bollard")):return false
	check(app.kernel.state.entities.boat.moored,"real attachment choices moor the actual boat")
	truth=app.kernel.state_hash()
	if not await click_named("OpenPlan"):return false
	var summary: Node=find_named("PlanSummary")
	if not check(summary is Label,"plan retains a readable summary after preparation"):return false
	check(summary.text.contains(app._name("cargo")) and summary.text.contains(app._route_name("unload")),"PLR-003 summary names the actual assigned actor and destination")
	check(find_named("PlanRoute_cargo")!=null and find_named("PlanAttachment_mooring")!=null,"summary offers editing the existing route and attachment directly")
	check(truth==app.kernel.state_hash() and not app.kernel.state.routes.cargo.completed,"viewing prepared links preserves the unexecuted world")
	await escape_key()
	if not await click_named("UndoAction"):return false
	check(not app.kernel.state.entities.boat.moored and app.kernel.state.routes.has("cargo"),"undo reverses only the newest attachment, retaining the earlier route")
	if not await click_named("OpenPlan"):return false
	summary=find_named("PlanSummary")
	var tool_line: String=""
	for line in summary.text.split("\n"):
		if line.begins_with(app._name("mooring")+" · "):tool_line=line
	var restored_label: String="Не закреплено" if prior_attachment.is_empty() else app._name(prior_attachment)
	check(str(app.kernel.state.entities.mooring.get("attachment_target",""))==prior_attachment and tool_line.contains(restored_label) and find_named("PlanRoute_cargo")!=null,"PLR-003 summary restores the actual previous attachment after undo, retaining the route")
	await escape_key()
	return true
func blocked_plan_and_help() -> bool:
	await fresh(3)
	# Consume two show hints first. A later delivery hint must start its own context.
	for i in range(2):
		if not await click_named("AskPlum"):return false
		await escape_key()
	# Known-state fixture: genuine authored demonstration and law, but leave the
	# stone at the place of the experiment. No saved-state or entity-field edits.
	var replay: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/L03_solution.json"))
	for step in replay.steps:
		if step.op=="command":
			if step.type=="PlaceProp" and step.payload.entity_id=="stone" and step.payload.slot_id=="bridge":break
			var result: Dictionary=app.kernel.dispatch(step)
			if not check(result.accepted,"L03 fixture accepts authored "+str(step.type)):return false
		elif step.op=="advance_ticks":app.kernel.advance_ticks(int(step.count))
	app._update_ui();await process_frame
	check(app.kernel.state.phase=="PLAN_RESOLUTION" and "M01" in app.kernel.state.active_laws and app.kernel.state.entities.float.removed,"fixture reaches real delivery planning after law and support removal")
	var truth: String=app.kernel.state_hash()
	if not await click_named("AskPlum"):return false
	var hint_text: String=collect_text(app.overlay)
	check(hint_text.contains("1") and not hint_text.contains("Семён") and not hint_text.contains("остановку"),"PLR-006 first delivery hint resets its context instead of returning to the inspector's second view")
	check(app.kernel.state_hash()==truth,"opening delivery help does not alter the route or law")
	await escape_key()
	if not await click_named("OpenPlan"):return false
	if not await click_named("PlanRoutes"):return false
	if not await click_text(app._name("cargo")):return false
	if not await click_text(app._route_name("cross")):return false
	app._capture_stage=""
	await click_control(app.primary)
	Engine.time_scale=6
	if not await wait_phase("RECOVERABLE_FAILURE",8):return false
	check(not app.kernel.state.routes.cargo.completed,"the known misplaced support really prevents delivery")
	var reason: String=app.instruction.text.to_lower()
	check((reason.contains("опор") or reason.contains("кам") or reason.contains("переправ")) and reason!="план можно поправить. отмените запуск без штрафа.","PLR-006 visible short guidance explains the actual support/path problem")
	await click_control(app.primary)
	check(app.kernel.state.phase=="PLAN_RESOLUTION" and "M01" in app.kernel.state.active_laws and app.kernel.state.entities.float.removed,"free cancellation preserves law and preparation")
	if not await select_object("stone"):return false
	if not await click_named("ObjectContext"):return false
	if not await click_text(app.tx("ui.place_prop","Выбрать место…")):return false
	if not await click_text(app._slot_name(app.kernel._slots.bridge,0)):return false
	check(app.kernel.state.entities.stone.slot=="bridge","real contextual placement moves the support to the crossing")
	await click_control(app.primary)
	if not await wait_phase("SUCCESS",8):return false
	check(app.kernel.state.routes.cargo.completed and app.progress.completed.has("L03"),"same delivery succeeds after correcting only the support's real position")
	await escape_key()
	Engine.time_scale=1
	return true
func pause_and_accessibility() -> bool:
	var truth: String=app.kernel.state_hash()
	if not await click_named("PauseSettings"):return false
	for id in ["PauseContinue","PauseSettingsMenu","PauseMainMenu"]:
		var control: Control=find_named(id)
		check(control!=null and fully_visible(control),"PLR-007 pause exposes "+id+" without scrolling audio channels")
	if not await click_named("PauseSettingsMenu",false):return false
	check(find_named("SettingsAccessibility")!=null and find_named("SettingsAudio")!=null,"settings expose both sections immediately")
	if not await click_named("SettingsAccessibility",false):return false
	for scale in [100,120,140]:
		if not await click_named("TextScale_"+str(scale),false):return false
		check(is_equal_approx(float(app.settings.accessibility.text_scale),float(scale)/100),"real text-size choice applies "+str(scale))
		check(find_named("TextScale_140")!=null and fully_visible(find_named("TextScale_140")),"PLR-007 changing scale preserves the accessibility section")
		check(is_equal_approx(float(app.saver.read_slot("settings").accessibility.text_scale),float(scale)/100),"text-size choice persists "+str(scale))
	check(app.kernel.state_hash()==truth,"pause/accessibility navigation preserves the completed puzzle")
	for button in all_buttons(app.overlay):
		if button is CheckButton:
			for color_name in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color"]:
				var color: Color=button.get_theme_color(color_name)
				check(color.get_luminance()<.5,"PLR-009 accessibility toggle keeps dark text for "+color_name)
	await escape_key()
	check(find_named("PauseContinue")!=null,"back from settings returns to pause rather than reopening audio settings")
	if not await click_named("PauseContinue",false):return false
	return true
func number_layouts() -> void:
	root.size=Vector2i(844,390);root.content_scale_size=Vector2i(1920,1080)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS;root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame;await process_frame
	for number in [3,4]:
		for scale in [1.0,1.2,1.4]:
			app.settings.accessibility.text_scale=scale
			await fresh(number)
			var label: Label=find_named("ObjectiveLevelNumber")
			if not check(label!=null,"level badge has a semantic label"):continue
			var expected: String="%02d"%number
			var font: Font=label.get_theme_font("font");var font_size: int=label.get_theme_font_size("font_size")
			var actual_text_width: float=font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
			check(label.text==expected and label.size.x+1>=actual_text_width,"PLR-008 both digits fit the real shaped badge at "+str(number)+"/"+str(scale))
			check(app.get_viewport_rect().encloses(app.primary.get_global_rect()),"main action stays inside the phone viewport at "+str(number)+"/"+str(scale))
func check(passed: bool,message: String) -> bool:
	count+=1
	if not passed:failures.append(message)
	return passed
func find_named(value: String):
	if is_instance_valid(app.overlay):
		var found: Node=app.overlay.find_child(value,true,false)
		if found!=null:return found
	return app.ui.find_child(value,true,false)
func fully_visible(control: Control) -> bool:
	if control==null or not control.is_visible_in_tree():return false
	var bounds: Rect2=control.get_global_rect()
	if not app.get_viewport_rect().encloses(bounds):return false
	var parent: Node=control.get_parent()
	while parent!=null:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(bounds):return false
		parent=parent.get_parent()
	return true
func select_object(id: String) -> bool:
	if not await click_named("OpenObjects"):return false
	if not await click_text(app._name(id)):return false
	return check(app.selected==id,"real objects drawer selects "+id)
func collect_text(node: Node) -> String:
	var text: String=node.text if node is Label or node is BaseButton else ""
	for child in node.get_children():text+="\n"+collect_text(child)
	return text
func all_buttons(node: Node) -> Array:
	var result: Array=[]
	if node is BaseButton:result.append(node)
	for child in node.get_children():result.append_array(all_buttons(child))
	return result
func normalized(value: String) -> String:return " ".join(value.replace("\n"," ").split(" ",false))
func click_text(value: String) -> bool:
	var scope: Node=app.overlay if is_instance_valid(app.overlay) else app.ui
	for button in all_buttons(scope):
		if normalized(button.text)==normalized(value):await click_control(button);return true
	return check(false,"visible pointer target missing: "+value)
func click_named(value: String,allow_scroll: bool=true) -> bool:
	var control: Control=find_named(value)
	if not check(control!=null,"semantic pointer target exists: "+value):return false
	if not allow_scroll and not check(fully_visible(control),"target is reachable without scrolling: "+value):return false
	await click_control(control,allow_scroll);return true
func click_control(control: Control,allow_scroll: bool=true) -> void:
	if allow_scroll:
		var parent: Node=control.get_parent()
		while parent!=null:
			if parent is ScrollContainer:parent.ensure_control_visible(control)
			parent=parent.get_parent()
	await process_frame;await process_frame
	await tap(control.get_global_rect().get_center())
func tap_slot(id: String) -> void:
	await process_frame;await process_frame
	await tap(app.stage.get_global_transform()*app.stage.world(app.kernel._slots[id].position))
func tap(point: Vector2) -> void:
	var move=InputEventMouseMotion.new();move.position=point;move.global_position=point;Input.parse_input_event(move)
	var press=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.position=point;press.global_position=point;press.pressed=true;Input.parse_input_event(press);pointer_events+=1
	await process_frame
	var release=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.position=point;release.global_position=point;release.pressed=false;Input.parse_input_event(release);pointer_events+=1
	await process_frame;await process_frame
func escape_key() -> void:
	var press=InputEventKey.new();press.keycode=KEY_ESCAPE;press.physical_keycode=KEY_ESCAPE;press.pressed=true;Input.parse_input_event(press);key_events+=1
	await process_frame
	var release=InputEventKey.new();release.keycode=KEY_ESCAPE;release.physical_keycode=KEY_ESCAPE;release.pressed=false;Input.parse_input_event(release);key_events+=1
	await process_frame;await process_frame
func wait_phase(wanted: String,timeout_seconds: float) -> bool:
	var deadline: int=Time.get_ticks_msec()+int(timeout_seconds*1000)
	while app.kernel.state.phase!=wanted and Time.get_ticks_msec()<deadline:await process_frame
	return check(app.kernel.state.phase==wanted,"client reaches "+wanted+"; actual="+app.kernel.state.phase)
func finish() -> void:
	Engine.time_scale=1
	if is_instance_valid(app):
		var sound=app.audio
		app.free()
		check(await sound.shutdown_and_wait(),"test releases real native audio playback before process exit")
		sound.free()
		await process_frame
	print("UX RETEST: %d checks; %d failures; %d pointer and %d key events"%[count,failures.size(),pointer_events,key_events])
	for message in failures:printerr("FAIL: "+message)
	var report=FileAccess.open("res://tests/reports/ux-retest.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":count,"failures":failures,"pointer_events":pointer_events,"key_events":key_events,"scope":"Known-state native Control regressions; genuine authored L03 preparation fixture; no pressed-signal emission; not a blind, physical Android, or full-campaign test","engine":Engine.get_version_info().string},"  "));report.close()
	quit(0 if failures.is_empty() else 1)
