extends SceneTree
const Audio=preload("res://services/audio_service.gd")
var failures: Array[String]=[]
var count: int=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var defaults: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/settings_default.json"))
	var audio=Audio.new();root.add_child(audio);audio.configure(defaults.audio)
	audio.play_music("music_menu")
	check(audio.set_chapter_theme("ENV01"),"chapter music initializes")
	var timeline_id: int=audio.music.stream.get_instance_id()
	check(audio._music_players.size()==2,"two Music players provide bounded chapter crossfade")
	check(audio.conductor_state().crossfade_seconds>=1 and audio.conductor_state().crossfade_seconds<=1.5,"chapter fade duration is within one to one-and-a-half seconds")
	audio._process(.6)
	var weights: Array=audio.conductor_state().weights
	check(is_equal_approx(weights[0],sqrt(.5)) and is_equal_approx(weights[1],sqrt(.5)),"both chapter timelines are audible halfway through equal-power fade")
	audio._process(.59)
	check(audio._outgoing_index>=0,"outgoing chapter is retained until fade completes")
	audio._process(.01)
	check(audio._outgoing_index==-1 and is_equal_approx(audio.conductor_state().crossfade_elapsed,1.2),"chapter fade releases outgoing timeline at 1.2 seconds")
	check(audio.music.stream.get_instance_id()==timeline_id,"crossfade preserves incoming synchronized timeline")
	audio.set_phase("PERFORMANCE")
	var scheduled: float=audio.conductor_state().next_bar_mix_at
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/audio_catalog.json"))
	var expected_bar: float=0
	for track in catalog.files:
		if track.id=="MUS_RIVER_BED":expected_bar=float(track.meter[0])*60.0/float(track.tempo_bpm)
	check(expected_bar>0 and is_equal_approx(scheduled,expected_bar),"river conductor schedules the next bar from the authored music tempo and meter")
	audio._process(scheduled-audio._transport_seconds-.01)
	check(is_zero_approx(audio.conductor_state().mix[2]),"tension remains silent before the scheduled bar")
	audio._process(.01)
	check(audio.conductor_state().mix[2]>0 and audio.conductor_state().mix[2]<.1,"phase fade begins at the next bar")
	audio._process(.21)
	check(audio.conductor_state().mix[2]>.25 and audio.conductor_state().mix[2]<.5,"phase intensity changes gradually rather than stepping")
	audio._process(.23)
	check(is_equal_approx(audio.conductor_state().mix[2],.75),"phase fade reaches its target after 450 milliseconds")
	check(audio.conductor_state().stem_fade_seconds>=.3 and audio.conductor_state().stem_fade_seconds<=.6,"stem fade meets the 300–600 millisecond range")
	check(audio.music.stream.get_instance_id()==timeline_id,"phase changes do not restart the shared sample clock")
	check(audio.set_chapter_theme("ENV02"),"new chapter starts a crossfade")
	var kitchen_id: int=audio.music.stream.get_instance_id()
	audio.play_music("music_album");audio.play_music("music_menu")
	check(audio.conductor_state().queued and audio.music.stream.get_instance_id()==kitchen_id,"rapid navigation queues only the latest request during a live fade")
	audio._process(1.2)
	check(audio.conductor_state().active=="music_menu" and not audio.conductor_state().queued,"last queued request starts when the previous fade completes")
	audio.settings.categories.Music.enabled=false;audio.apply_settings()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")),"chapter transitions respect independent Music mute")
	for player in audio._music_players:check(player.bus=="Music","each chapter timeline routes through Music")
	var before: Dictionary=audio.conductor_state();audio.set_paused(true);audio._process(.5)
	check(audio.conductor_state()==before,"pause freezes bar clock, fade envelopes and queue")
	audio.set_paused(false)
	await create_timer(.06).timeout
	audio.shutdown();audio.free()
	await create_timer(.15).timeout
	print("AUDIO CONDUCTOR: %d checks; %d failures"%[count,failures.size()])
	for issue in failures:printerr("FAIL: "+issue)
	var report=FileAccess.open("res://tests/reports/audio-conductor.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":count,"failures":failures,"engine":Engine.get_version_info().string,"chapter_fade_seconds":1.2,"stem_fade_seconds":.45,"timing_checks":"simulated conductor clock plus actual AudioStream players; listening not performed"},"  "));report.close()
	quit(0 if failures.is_empty() else 1)
func check(passed: bool,message: String) -> void:
	count+=1
	if not passed:failures.append(message)
