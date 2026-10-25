extends SceneTree
const Kernel=preload("res://core/simulation_kernel.gd")
const Stage=preload("res://presentation/stage_view.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.size=Vector2i(844,390);root.content_scale_size=Vector2i(1920,1080)
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS;root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
 await process_frame
 for label in ["L01-midstone","L21-proof-stack","L21-frame-removed"]:
  var kernel=Kernel.new();var level_id: String=label.left(3)
  kernel.load_level(JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/"+level_id+".json")),48121)
  var path: String="res://tests/"+("" if level_id=="L01" else "replays/")+level_id+"_solution.json"
  var replay=JSON.parse_string(FileAccess.get_file_as_string(path))
  for step in replay.steps:
   if step.op=="command":kernel.dispatch(step)
   elif step.op=="advance_ticks":kernel.advance_ticks(int(step.count))
   if label=="L01-midstone" and step.get("type","")=="RunResolution":
    kernel.advance_ticks(12);break
   if label=="L21-proof-stack" and kernel.state.phase=="PROOF_ACCEPTED":break
   if label=="L21-frame-removed" and step.get("type","")=="Interact" and step.payload.get("entity_id","")=="frame" and step.payload.get("action","")=="remove":break
  var stage=Stage.new();stage.kernel=kernel;stage.size=root.get_visible_rect().size;root.add_child(stage)
  await process_frame;await process_frame;await process_frame
  var err=root.get_texture().get_image().save_png("/workspace/GOD-game/build/"+label+"-support-review.png")
  print(label," PNG ",err)
  if level_id=="L21":print("LAYOUT ",stage._paper_layout("paper")," WEIGHT ",stage._visual_position("weight"))
  stage.free();await process_frame
 quit(0)
