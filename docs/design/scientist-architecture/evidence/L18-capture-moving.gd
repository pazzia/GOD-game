extends SceneTree
const App=preload("res://tests/review_app_host.gd")
const Audio=preload("res://services/audio_service.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.size=Vector2i(844,390);root.content_scale_size=Vector2i(1920,1080)
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS;root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
 await process_frame
 var settings: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/settings_default.json"));settings.audio.master_muted=true
 var audio=Audio.new();root.add_child(audio);audio.configure(settings.audio)
 var app=App.new();app.settings=settings;app.audio=audio;app.theme=preload("res://presentation/theme.gd").make_theme()
 app.progress={"schema_version":1,"completed":{},"unlocked":30,"current_level":18};app._capture_stage="plan"
 for n in range(1,31):app.level_ids.append("L%02d"%n)
 root.add_child(app);app.set_process(false);app._load_catalog();app.start_level(18,false);app._close_overlay()
 var replay=JSON.parse_string(FileAccess.get_file_as_string("res://tests/replays/L18_solution.json"))
 for step in replay.steps:
  if step.op=="command":app.kernel.dispatch(step)
  elif step.op=="advance_ticks":app.kernel.advance_ticks(int(step.count))
  if step.get("type","")=="RunResolution" and app.kernel.state.routes.has("boat"):
   app.kernel.advance_ticks(10);break
 app._update_ui();app.stage._sample_presentation(0);app.stage._sync_puppets();app.stage.process_mode=Node.PROCESS_MODE_DISABLED
 await process_frame;await process_frame;await process_frame
 var err=root.get_texture().get_image().save_png("/workspace/GOD-game/build/scientist-boat-review/L18-moving-ru-100-844x390.png")
 print("BOAT_MOVE_CAPTURE ",err," ROUTE ",app.kernel.state.routes.boat," STATE ",app.kernel.state.entities.boat.position)
 app.free();await audio.shutdown_and_wait();audio.free();await process_frame
 quit(int(err))
