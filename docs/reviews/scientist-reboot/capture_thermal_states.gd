extends SceneTree
const Kernel=preload("res://core/simulation_kernel.gd")
const Stage=preload("res://presentation/stage_view.gd")
var stage: Control
var kernel: RefCounted
var observations: Array=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(844,390);root.content_scale_size=Vector2i(1920,1080)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS;root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	kernel=Kernel.new()
	if not kernel.load_level(JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/L11.json")),48121):push_error("L11 rejected");quit(1);return
	var replay: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/replays/L11_solution.json"))
	for step in replay.steps:
		if step.op=="command":
			var result: Dictionary=kernel.dispatch(step)
			if not result.accepted:push_error("Rejected "+step.type);quit(1);return
		elif step.op=="advance_ticks":kernel.advance_ticks(int(step.count))
		if step.get("type","")=="ActivateLaw" and "M02" in kernel.state.active_laws:break
	stage=Stage.new();stage.kernel=kernel;stage.size=root.get_visible_rect().size;root.add_child(stage)
	await capture("L11-M02-oven-on")
	var response: Dictionary=kernel.dispatch({"type":"Interact","payload":{"entity_id":"oven","action":"disable"}})
	if not response.accepted:push_error("Disable rejected "+str(response));quit(1);return
	await capture("L11-M02-oven-off")
	var f=FileAccess.open("res://build/scientist-qa-thermal/state-observations.json",FileAccess.WRITE);f.store_string(JSON.stringify(observations,"  "));f.close()
	stage.free();await process_frame;quit()
func capture(label: String) -> void:
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
	var path: String="res://build/scientist-qa-thermal/"+label+".png"
	var error: int=root.get_texture().get_image().save_png(path)
	var record: Dictionary={"label":label,"screenshot":path,"save_error":error,"phase":kernel.state.phase,"laws":kernel.state.active_laws,"demo_water":kernel.state.zones.demo_water.phase,"crossing_water":kernel.state.zones.crossing_water.phase,"oven_enabled":kernel.state.entities.oven.enabled,"oven_asset_id":kernel._entities.oven.asset_id,"oven_variant":stage._prop_variant("oven"),"bowl_variant":stage._prop_variant("bowl"),"decoy_asset_id":kernel._entities.flame.asset_id,"decoy_enabled":kernel.state.entities.flame.enabled}
	observations.append(record);print(JSON.stringify(record))
