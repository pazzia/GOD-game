extends SceneTree
## Independent actual touch dispatch; test-only capability flag, no production changes.
const App=preload("res://tests/pointer_app_host.gd")
const Audio=preload("res://services/audio_service.gd")
var checks: int=0
var failures: Array[String]=[]
var events: int=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1920,1080);root.content_scale_size=Vector2i(1920,1080)
	var old_touch: bool=Input.emulate_touch_from_mouse
	var old_mouse: bool=Input.emulate_mouse_from_touch
	var hardware_touch: bool=DisplayServer.is_touchscreen_available()
	Input.emulate_mouse_from_touch=true # Test mobile tap routing as well as drag capability.
	var defaults: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/settings_default.json"));defaults.audio.master_muted=true;defaults.accessibility.text_scale=1.4
	var audio=Audio.new();root.add_child(audio);audio.configure(defaults.audio)
	var app=App.new();app.audio=audio;app.settings=defaults;app.progress={"schema_version":1,"unlocked":30,"completed":{},"current_level":1};app._capture_stage="fixture"
	app.theme=preload("res://presentation/theme.gd").make_theme()
	for n in range(1,31):app.level_ids.append("L%02d"%n)
	app._load_catalog();root.add_child(app);app.start_level(30,false);app.set_process(false)
	await process_frame;await process_frame
	app._close_overlay()
	await touch_tap(app.ui.find_child("OpenObjects",true,false).get_global_rect().get_center())
	await process_frame;await process_frame
	check(is_instance_valid(app._inventory_scroll),"native touch opens the deliberate objects drawer")
	var primary: Rect2=app.primary.get_global_rect();var truth: String=app.kernel.state_hash()
	var stage_before: Rect2=app.stage.get_global_rect()
	var tray: Rect2=app._inventory_scroll.get_global_rect()
	var from: Vector2=Vector2(tray.end.x-24,tray.end.y-40)
	var to: Vector2=Vector2(tray.end.x-24,tray.position.y+40)
	Input.emulate_touch_from_mouse=false
	await drag(from,to)
	if not hardware_touch:check(app._inventory_scroll.scroll_vertical==0,"headless native ScrollContainer requires the test touch capability flag")
	app._inventory_scroll.scroll_vertical=0;Input.emulate_touch_from_mouse=true
	await drag(from,to)
	check(app._inventory_scroll.scroll_vertical>0 and app.selected.is_empty(),"native ScreenTouch/ScreenDrag scrolls the objects drawer without selecting an item")
	check(app.primary.get_global_rect()==primary and app.stage.get_global_rect()==stage_before,"touch navigation leaves the underlying full stage and main action fixed")
	check(app.kernel.state_hash()==truth and app.ui_commands.is_empty(),"scrolling cannot emit gameplay commands or change world truth")
	var inventory_row: Control=app._inventory_scroll.get_child(0)
	var button: Control=null
	for child in inventory_row.get_children():
		if child is Button and tray.encloses(child.get_global_rect()):button=child;break
	check(button!=null,"the scrolled drawer exposes a complete touch target")
	if button!=null:
		await touch_tap(button.get_global_rect().get_center())
		check(not app.selected.is_empty() and not is_instance_valid(app.overlay),"a positive ScreenTouch tap selects a real item and closes the drawer")
	# Every observer remains inspectable directly in the scene, without a permanent audience sidebar.
	app.selected="";app.stage.selected="";app._build_ui();app._update_ui()
	await process_frame;await process_frame
	for id in app.kernel.state.witnesses:
		var hit: Dictionary={}
		for candidate in app.stage._hits:
			if candidate.kind=="witness" and candidate.id==id:hit=candidate;break
		check(not hit.is_empty(),"scene exposes a visible witness hit target: "+id)
		if hit.is_empty():continue
		await touch_tap(app.stage.get_global_transform()*hit.rect.get_center())
		var witness: Dictionary=app.kernel._find(app.kernel.definition.witnesses,id)
		check(app.inspected==id and app.instruction.text.contains(app._character_name(witness.character_id)),"native touch inspection names the actual observer and live viewing status: "+id)
	check(app.kernel.state_hash()==truth and app.ui_commands.is_empty(),"inspection of every observer cannot alter world truth")
	Input.emulate_touch_from_mouse=old_touch;Input.emulate_mouse_from_touch=old_mouse
	app.free();audio.shutdown();audio.free();await create_timer(.15).timeout
	print("TOUCH CAPABILITY: %d checks; %d failures; %d native touch events"%[checks,failures.size(),events])
	for issue in failures:printerr("FAIL: "+issue)
	var f=FileAccess.open("res://tests/reports/touch-capability.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"events":events,"engine":Engine.get_version_info().string,"hardware_touch":hardware_touch,"original_emulate_touch_from_mouse":old_touch,"original_emulate_mouse_from_touch":old_mouse,"fixture_mouse_from_touch_enabled":true,"touch_capability_off_then_on":true,"only_fixture_touch_capability_enabled":true,"production_code_modified":false,"physical_device_test":false},"  "));f.close()
	quit(0 if failures.is_empty() else 1)
func touch_tap(at: Vector2) -> void:
	var down=InputEventScreenTouch.new();down.index=0;down.position=at;down.pressed=true;Input.parse_input_event(down);events+=1;await process_frame
	var up=InputEventScreenTouch.new();up.index=0;up.position=at;up.pressed=false;Input.parse_input_event(up);events+=1;await process_frame;await process_frame
func drag(from: Vector2,to: Vector2) -> void:
	var down=InputEventScreenTouch.new();down.index=0;down.position=from;down.pressed=true;Input.parse_input_event(down);events+=1;await process_frame
	var previous: Vector2=from
	for i in range(1,9):
		var at: Vector2=from.lerp(to,float(i)/8)
		var motion=InputEventScreenDrag.new();motion.index=0;motion.position=at;motion.relative=at-previous;motion.velocity=(at-previous)*60;Input.parse_input_event(motion);events+=1;previous=at;await process_frame
	var up=InputEventScreenTouch.new();up.index=0;up.position=to;up.pressed=false;Input.parse_input_event(up);events+=1;await create_timer(.12).timeout
func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message)
