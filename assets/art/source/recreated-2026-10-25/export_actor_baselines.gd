extends SceneTree
## Native export of the same authored cutout rig used in the game.
const Puppet=preload("res://presentation/character_puppet.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var directory: String="res://assets/art/source/recreated-2026-10-25/native-baselines"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="):directory=arg.trim_prefix("--output-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	for actor in ["semyon","roza"]:
		var viewport=SubViewport.new()
		viewport.size=Vector2i(1600,1500)
		viewport.transparent_bg=true
		viewport.disable_3d=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var puppet=Puppet.new()
		viewport.add_child(puppet)
		if not puppet.configure(actor,1320) or not puppet.rigged:
			push_error("Cannot export missing rig "+actor)
			quit(1);return
		puppet.position=Vector2(800,1400)
		puppet.play_state("idle",true)
		puppet.animator.pause()
		puppet.animator.seek(0,true)
		await process_frame
		await RenderingServer.frame_post_draw
		var captured: Image=viewport.get_texture().get_image()
		var error: Error=captured.save_png(directory+"/"+actor+".png")
		if error!=OK:
			push_error("PNG export failed "+actor+" "+str(error))
			quit(1);return
		print("EXPORTED "+actor+" "+str(captured.get_size()))
		viewport.queue_free()
		await process_frame
	quit()
