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
 check(not has_slot_targets(),"ordinary inspection does not silently enter placement mode")
 stage.placement_entity="stone";stage.queue_redraw();await process_frame;await process_frame
 await tap(logical)
 check(targets.size()==4 and targets[-1]=={"kind":"slot","id":"stage_stone"},"selected valid placement slot keeps priority over intersecting prop targets")
 await tap(Vector2(970,600))
 check(targets[-1]=={"kind":"placement_invalid","id":"stone"} and stage.selected=="stone" and stage.placement_entity=="stone","invalid placement reports the current item without selecting a neighbouring prop")
 stage.hud_safe_top=240;stage.ui_text_scale=1.4
 stage.queue_redraw();await process_frame;await process_frame
 var label: Dictionary=stage._selection_label_layout()
 check(not label.is_empty() and label.rect.position.y>=252 and Rect2(Vector2.ZERO,stage.size).encloses(label.rect),"selected item name remains below the actual HUD at large text size")
 check(str(label.get("text","")).contains("Вмещает"),"selected stone label retains its real carrying capacity")
 check(kernel.state_hash()==hash,"hit expansion and every pointer event preserve all authored simulation geometry and state")
 for target in stage._hits:
  if target.kind=="witness":
   var eye: Vector2=kernel.witness_eye(target.id)
   check(target.rect.size.x>=144 and target.rect.size.y>=144 and target.anchor.is_equal_approx(stage.world([eye.x,eye.y])),"witness touch targets meet 48dp while their anchors stay at actual viewing points")
 stage.free();await process_frame
 var harbor=Kernel.new();check(harbor.load_level(JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/L02.json")),48121),"harbor interaction fixture loads")
 var harbor_hash: String=harbor.state_hash()
 stage=Stage.new();stage.size=Vector2(2337.2308,1080);stage.kernel=harbor;stage.target_tapped.connect(func(kind,id):targets.append({"kind":kind,"id":id}));root.add_child(stage)
 await process_frame;await process_frame
 var hull: Dictionary=hit("boat")
 await tap(hull.anchor)
 check(targets[-1]=={"kind":"entity","id":"boat"},"painted hull center chooses the boat rather than an enlarged neighbouring rope target")
 var rope: Dictionary=hit("mooring")
 check(rope.has("polyline"),"actual mooring endpoints provide a painted rope target")
 await tap(rope.polyline[12])
 check(targets[-1]=={"kind":"entity","id":"mooring"},"visible foreground rope chooses the rope at its actual line")
 stage.selected="cargo";stage.queue_redraw();await process_frame;await process_frame
 var cargo: Dictionary=hit("cargo")
 check(cargo.body_rect.get_center().x<stage.world(harbor._slots.hero_start.position).x-150,"harbor cargo has its own visible silhouette to the left of the scientist")
 check(not stage._selection_label_layout().is_empty(),"selected harbor cargo receives a visible name label")
 check(harbor.state_hash()==harbor_hash,"all harbor hit/render aids preserve authored simulation positions and state")
 stage.free();await process_frame
 await witness_mode_cases()
 var file=FileAccess.open("res://tests/reports/stage-targets.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"native_mouse_clicks":12},"  "));file.close()
 print("STAGE TARGETS: %d checks; %d failures"%[checks,failures.size()])
 for failure in failures:printerr("FAIL: "+failure)
 quit(0 if failures.is_empty() else 1)
func witness_mode_cases() -> void:
 var observers=Kernel.new();check(observers.load_level(JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/L30.json")),48121),"three single-view observer fixture loads")
 var truth: String=observers.state_hash()
 stage=Stage.new();stage.size=Vector2(1920,1080);stage.kernel=observers;stage.target_tapped.connect(_observe_fixture_target);root.add_child(stage)
 await process_frame;await process_frame
 for witness in observers.definition.witnesses:
  var target: Dictionary=witness_hit(str(witness.id))
  await tap(target.rect.get_center())
  check(targets[-1]=={"kind":"witness","id":witness.id} and stage.selected=="w:"+str(witness.id),"ordinary inspection can select the next observer after a previous single-view observer: "+str(witness.id))
  check(stage._placement_subject().is_empty() and not has_slot_targets(),"inspection does not silently advertise moving positions: "+str(witness.id))
 stage.selected="w:w1";stage.placement_entity="w:w1";stage.queue_redraw();await process_frame;await process_frame
 check(stage._placement_subject()=="w:w1" and has_slot_targets(),"explicit witness placement still advertises its real allowed places")
 var slot_id: String=str(observers.definition.witnesses[0].initial_view_slot)
 await tap(stage.world(observers._slots[slot_id].position))
 check(targets[-1]=={"kind":"slot","id":slot_id},"explicit witness placement keeps slot priority over the observer body")
 stage.placement_entity=""
 var next: Dictionary=witness_hit("w3")
 await tap(next.rect.get_center())
 check(targets[-1]=={"kind":"witness","id":"w3"} and stage._placement_subject().is_empty(),"canceling explicit witness placement immediately restores ordinary observer inspection")
 check(observers.state_hash()==truth,"inspection and placement target routing cannot move observers or alter the kernel")
 stage.free();await process_frame
func _observe_fixture_target(kind: String,id: String) -> void:
 targets.append({"kind":kind,"id":id})
 if kind=="witness":
  stage.selected="w:"+id;stage.inspected=id;stage.queue_redraw()
func witness_hit(id: String) -> Dictionary:
 for target in stage._hits:
  if target.kind=="witness" and target.id==id:return target
 return {}
func hit(id: String) -> Dictionary:
 for target in stage._hits:
  if target.kind=="entity" and target.id==id:return target
 return {}
func has_slot_targets() -> bool:
 for target in stage._hits:
  if target.kind=="slot":return true
 return false
func tap(position: Vector2) -> void:
 var motion=InputEventMouseMotion.new();motion.position=position;motion.global_position=position;Input.parse_input_event(motion)
 var press=InputEventMouseButton.new();press.position=position;press.global_position=position;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;Input.parse_input_event(press)
 await process_frame
 var release=InputEventMouseButton.new();release.position=position;release.global_position=position;release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;Input.parse_input_event(release)
 await process_frame;await process_frame
