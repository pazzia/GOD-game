extends SceneTree
## Native mixer ownership, including rapid replacement, pause and a retained owner.
const Audio=preload("res://services/audio_service.gd")
var checks: int=0
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message)
func run() -> void:
	var defaults: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/settings_default.json"))
	defaults.audio.master_muted=true
	for paused in [false,true]:
		var a=Audio.new();root.add_child(a);a.configure(defaults.audio)
		for index in range(12):
			a.set_chapter_theme(["ENV01","ENV02","ENV03"][index%3]);a._process(1.3)
			a.play("tap","UI");a.play_ambience()
		a.set_paused(paused)
		check(await a.shutdown_and_wait(),"real mixer releases every retired playback after rapid replacement; paused="+str(paused))
		check(a.shutdown_complete() and a._retiring_playbacks.is_empty(),"terminal service retains no native playback; paused="+str(paused))
		a.free()
	var retained=Audio.new();root.add_child(retained);retained.configure(defaults.audio);retained.set_chapter_theme("ENV01")
	var external_owner: AudioStreamPlayback=retained.music.get_stream_playback()
	check(not await retained.shutdown_and_wait(.01),"an external playback owner must prevent a false successful shutdown")
	check(retained.last_error=="AUDIO_SHUTDOWN_TIMEOUT" and not retained.shutdown_complete(),"bounded drain reports timeout instead of hiding an unreleased playback")
	external_owner=null
	check(await retained.shutdown_and_wait(),"drain completes when the final external owner releases playback")
	check(retained.shutdown_complete() and retained.last_error.is_empty(),"successful retry clears only the shutdown timeout")
	retained.free();await process_frame
	print("AUDIO SHUTDOWN DRAIN: %d checks; %d failures"%[checks,failures.size()])
	for message in failures:printerr("FAIL: "+message)
	quit(0 if failures.is_empty() else 1)
