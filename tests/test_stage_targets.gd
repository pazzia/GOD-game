extends SceneTree
## Native clicks on real overlapping props; interaction rectangles, never world geometry.
const Kernel=preload("res://core/simulation_kernel.gd")
const Stage=preload("res://presentation/stage_view.gd")
var checks: int=0
var failures: Array[String]=[]
var targets: Array=[]
var stage: Control
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok:failures.append(label)
func run() -> void:
 root.size=Vector2i(1920,1080);root.content_scale_size=Vector2i(1920,1080)
 var kernel=Kernel.new();check(kernel.load_level(JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/L04.json")),48121),"authored small prop fixture loads")
 check(kernel.dispatch({"type":"PlaceProp","payload":{"entity_id":"float","slot_id":"stage_float"}}).accepted,"float placed on its genuine method slot")
 check(kernel.dispatch({"type":"PlaceProp","payload":{"entity_id":"stone","slot_id":"stage_stone"}}).accepted,"stone and float overlap at the authored proof position")
 stage=Stage.new();stage.size=Vector2(984,656);stage.kernel=kernel;stage.target_tapped.connect(func(kind,id):targets.append({"kind":kind,"id":id}));root.add_child(stage)
 await process_frame;await process_frame
 var hash: String=kernel.state_hash()
 var stone=hit("stone");var floating=hit("float")
 check(stone.rect.size.x>=144 and stone.rect.size.y>=144 and floating.rect.size.x>=144 and floating.rect.size.y>=144,"small object interaction rectangles satisfy the full 144 by 144 minimum")
 var logical: Vector2=stage.world(kernel._slots.stage_stone.position)
 await tap(stone.anchor)
 check(targets.size()==1 and targets[-1]=={"kind":"entity","id":"stone"},"overlap tap on painted stone center selects the nearest stone")
 await tap(floating.anchor)
 check(targets.size()==2 and targets[-1]=={"kind":"entity","id":"float"},"overlap tap on painted float center selects the nearest float")
 # This point was outside the former 96px width, and is inside the new target.
 await tap(floating.anchor+Vector2(65,0))
 check(targets.size()==3 and targets[-1]=={"kind":"entity","id":"float"},"expanded small prop target accepts a native edge tap")
 stage.selected="stone";stage.queue_redraw();await process_frame;await process_frame
 await tap(logical)
 check(targets.size()==4 and targets[-1]=={"kind":"slot","id":"stage_stone"},"selected valid placement slot keeps priority over intersecting prop targets")
 check(kernel.state_hash()==hash,"hit expansion and every pointer event preserve all authored simulation geometry and state")
 for target in stage._hits:
  if target.kind=="witness":
   var eye: Vector2=kernel.witness_eye(target.id)
   check(target.rect.size.x>=144 and target.rect.size.y>=144 and target.anchor.is_equal_approx(stage.world([eye.x,eye.y])),"witness touch targets meet 48dp while their anchors stay at actual viewing points")
 stage.free();await process_frame
 var file=FileAccess.open("res://tests/reports/stage-targets.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"native_mouse_clicks":4},"  "));file.close()
 print("STAGE TARGETS: %d checks; %d failures"%[checks,failures.size()])
 for failure in failures:printerr("FAIL: "+failure)
 quit(0 if failures.is_empty() else 1)
func hit(id: String) -> Dictionary:
 for target in stage._hits:
  if target.kind=="entity" and target.id==id:return target
 return {}
func tap(position: Vector2) -> void:
 var motion=InputEventMouseMotion.new();motion.position=position;motion.global_position=position;Input.parse_input_event(motion)
 var press=InputEventMouseButton.new();press.position=position;press.global_position=position;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;Input.parse_input_event(press)
 await process_frame
 var release=InputEventMouseButton.new();release.position=position;release.global_position=position;release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;Input.parse_input_event(release)
 await process_frame;await process_frame
