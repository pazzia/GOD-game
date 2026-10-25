extends SceneTree
## Independent release/cancel/overlap checks through actual native input dispatch.
const Kernel=preload("res://core/simulation_kernel.gd")
const Stage=preload("res://presentation/stage_view.gd")
var checks: int=0
var failures: Array[String]=[]
var selected: Array=[]
var events: int=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1920,1080);root.content_scale_size=Vector2i(1920,1080)
	# L04 retains genuinely movable overlapping stone/float props; the new L01
	# stone is deliberately fixed and must not advertise a placement target.
	var k=Kernel.new();k.load_level(JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/L04.json")),48121)
	k.dispatch({"type":"PlaceProp","payload":{"entity_id":"float","slot_id":"stage_float"}});k.dispatch({"type":"PlaceProp","payload":{"entity_id":"stone","slot_id":"stage_stone"}})
	var stage=Stage.new();stage.kernel=k;stage.size=Vector2(984,656);stage.target_tapped.connect(func(kind,id):selected.append({"kind":kind,"id":id}));root.add_child(stage)
	await process_frame;await process_frame
	var truth: String=k.state_hash();var geometry: Variant=k._canonical(k.definition)
	var all_large: bool=true
	for target in stage._hits:
		if target.kind=="entity":all_large=all_large and target.rect.size.x>=144 and target.rect.size.y>=144 and target.rect.has_point(target.anchor)
	check(all_large,"all actual small-prop targets enclose painted center and minimum144×144")
	var at: Vector2=entity_hit(stage,"float").anchor+Vector2(66,0)
	await button(at,true)
	check(selected.is_empty(),"expanded-target press alone never commits selection")
	await button(at,false)
	check(selected==[{"kind":"entity","id":"float"}],"release at expanded-only edge chooses nearest float through native dispatch")
	var before: int=selected.size();at=entity_hit(stage,"stone").anchor
	await button(at,true);await button(at,false,true)
	check(selected.size()==before,"canceled native release cannot select an overlapping prop")
	await button(at,true)
	var motion=InputEventMouseMotion.new();motion.position=at+Vector2(25,0);motion.global_position=motion.position;Input.parse_input_event(motion);events+=1;await process_frame
	await button(at+Vector2(25,0),false)
	check(selected.size()==before,"movement beyond tap threshold cancels even inside enlarged rectangle")
	stage.selected="stone";stage.queue_redraw();await process_frame;await process_frame
	var slot: Vector2=stage.world(k._slots.stage_stone.position)
	await button(slot,true);await button(slot,false)
	check(selected[-1]=={"kind":"slot","id":"stage_stone"},"compatible selected slot has priority over both enlarged overlapping props")
	check(k.state_hash()==truth and k._canonical(k.definition)==geometry,"input hit expansion never mutates logical positions or visibility geometry")
	stage.free();await process_frame
	print("STAGE INPUT EDGES: %d checks; %d failures; %d native input events"%[checks,failures.size(),events])
	for issue in failures:printerr("FAIL: "+issue)
	var f=FileAccess.open("res://tests/reports/stage-input-edges.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"events":events,"engine":Engine.get_version_info().string,"input":"native Input.parse_input_event, no signal shortcut","physical_device_test":false},"  "));f.close()
	quit(0 if failures.is_empty() else 1)
func entity_hit(stage: Control,id: String) -> Dictionary:
	for target in stage._hits:
		if target.kind=="entity" and target.id==id:return target
	return {}
func button(at: Vector2,down: bool,canceled: bool=false) -> void:
	var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.global_position=at;event.pressed=down;event.canceled=canceled;Input.parse_input_event(event);events+=1;await process_frame;await process_frame
func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message)
