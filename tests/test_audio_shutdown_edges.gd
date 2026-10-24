extends SceneTree
## Independent terminal lifecycle: real player node remains alive after shutdown.
const Audio=preload("res://services/audio_service.gd")
var checks: int=0
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var defaults: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/settings_default.json"));defaults.audio.master_muted=true
	for paused in [false,true]:
		var a=Audio.new();root.add_child(a);a.configure(defaults.audio);a.play_music("music_menu");a.set_chapter_theme("ENV01")
		await create_timer(.08).timeout # Real AudioServer startup, not an accelerated fake frame.
		a.set_paused(paused)
		a.shutdown()
		var closed: Dictionary=a.conductor_state()
		check(is_instance_valid(a) and not a.is_processing() and all_players_stopped(a),"shutdown stops processing and releases every actual player; paused="+str(paused))
		a.shutdown()
		check(a.conductor_state()==closed and all_players_stopped(a),"repeated shutdown is idempotent while node remains alive; paused="+str(paused))
		await create_timer(.25).timeout
		check(a.conductor_state()==closed and not a.is_processing(),"native frames after close cannot finish an old crossfade or advance clocks; paused="+str(paused))
		var children: int=a.get_child_count()
		a.set_phase("PERFORMANCE");a.set_chapter_theme("ENV02");a.play_music("music_menu");a.play_ambience();a.play("voice_marfa","Voice");a.play_event("SFX_LAW_STAMP");a.duck_music(2,-12);a.set_paused(false)
		a._process(.5)
		await create_timer(.08).timeout
		check(not a.is_processing() and a.get_child_count()==children and all_players_stopped(a) and a.conductor_state()==closed,"late phase/theme/play/duck/resume callbacks cannot resurrect terminal service; paused="+str(paused))
		a.free();await process_frame
	await create_timer(.15).timeout
	print("AUDIO SHUTDOWN EDGES: %d checks; %d failures"%[checks,failures.size()])
	for issue in failures:printerr("FAIL: "+issue)
	var f=FileAccess.open("res://tests/reports/audio-shutdown-edges.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"node_kept_alive_after_shutdown":true,"actual_short_audio_lifecycle":true,"listening_or_device_test":false},"  "));f.close()
	quit(0 if failures.is_empty() else 1)
func all_players_stopped(a: Node) -> bool:
	for child in a.get_children():
		if child is AudioStreamPlayer and (child.stream!=null or child.playing):return false
	return true
func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message)
