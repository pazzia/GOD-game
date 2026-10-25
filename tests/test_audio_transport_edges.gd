extends SceneTree
## Independent conductor boundaries. Mock elapsed time is not device audio listening.
const Audio=preload("res://services/audio_service.gd")
var count: int=0
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var defaults: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/settings_default.json"))
	var a=Audio.new();root.add_child(a);a.configure(defaults.audio);a.set_chapter_theme("ENV01")
	var identity: int=a.music.stream.get_instance_id()
	a._process(.8);a.set_phase("PERFORMANCE")
	var boundary: float=a.conductor_state().next_bar_mix_at
	for i in range(100):
		a.set_phase("PERFORMANCE");a._process(.01)
	check(is_equal_approx(a.conductor_state().next_bar_mix_at,boundary) and is_zero_approx(a.conductor_state().mix[2]),"repeated HUD phase updates do not postpone scheduled bar or start fade early")
	a.set_phase("RUN_RESOLUTION");a.set_phase("LAW_SELECTION")
	check(is_equal_approx(a.conductor_state().next_bar_mix_at,boundary),"last new phase before same boundary does not defer to a later bar")
	a._process(boundary-a._transport_seconds);a._process(.45)
	check(a.conductor_state().mix==a._phase_mix("LAW_SELECTION") and a._pending_mix.is_empty() and a.music.stream.get_instance_id()==identity,"last pre-bar phase wins on same synchronized timeline")
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/audio_catalog.json"))
	var bar_seconds: float=0
	for track in catalog.files:
		if track.id=="MUS_RIVER_BED":bar_seconds=float(track.meter[0])*60.0/float(track.tempo_bpm)
	check(bar_seconds>0,"river theme declares valid meter and tempo")
	var exact_bar: float=2*bar_seconds
	a._process(exact_bar-a._transport_seconds);a.set_phase("PERFORMANCE")
	check(a.conductor_state().next_bar_mix_at>exact_bar and is_equal_approx(a.conductor_state().next_bar_mix_at,exact_bar+bar_seconds),"phase requested exactly on already reached bar schedules following bar")
	a._process(.2);a.set_phase("PLAN_SHOW");a.set_phase("PERFORMANCE")
	check(a._pending_mix==a._phase_mix("PERFORMANCE") and is_equal_approx(a.conductor_state().next_bar_mix_at,exact_bar+bar_seconds),"multiple same-clock requests retain final phase for one future boundary")
	a.set_chapter_theme("ENV02");var incoming: int=a.music.stream.get_instance_id()
	a.set_chapter_theme("ENV03");a.set_chapter_theme("ENV02")
	a._process(1.2)
	check(a.music.stream.get_instance_id()==incoming and not a.conductor_state().queued and a.conductor_state().active=="chapter_KITCHEN","reselecting current incoming chapter cancels stale queued navigation without restarting music")
	a.set_chapter_theme("ENV01");a.set_chapter_theme("ENV03")
	a.settings.categories.Music.enabled=false;a.apply_settings();a.set_paused(true)
	var frozen: Dictionary=a.conductor_state()
	var every_paused: bool=true
	for p in a._music_players:every_paused=every_paused and p.stream_paused and p.bus=="Music"
	a._process(8)
	check(every_paused and a.conductor_state()==frozen and a._music_players.size()==2,"background freezes both crossfade players and pending navigation")
	# Request can arrive in the same native frame as background notification.
	a.set_chapter_theme("ENV02")
	var same_clock_paused: bool=true
	for p in a._music_players:same_clock_paused=same_clock_paused and p.stream_paused
	check(same_clock_paused,"chapter request while paused never unpauses incoming timeline")
	a.set_paused(false)
	for i in range(100):
		a.set_chapter_theme(["ENV01","ENV02","ENV03"][i%3]);a._process(.1)
	var live: int=0
	for p in a._music_players:
		if p.stream!=null:live+=1
	check(live<=2 and a._music_players.size()==2 and AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")),"rapid chapter replacement remains bounded to two Music-routed timelines under mute")
	a._process(3);a._process(1.2)
	check(not a.conductor_state().queued and a.conductor_state().active=="chapter_RIVER" and a._outgoing_index==-1,"latest rapid chapter request converges and releases outgoing player")
	a.settings.categories.Music.enabled=true;a.settings.categories.Music.volume=0;a.apply_settings();a.set_phase("RUN_RESOLUTION");a.duck_music(.7,-18)
	for i in range(100):a._process(.1)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")),"stem fade and duck release never bypass zero-volume mute")
	a.shutdown();a.free();await process_frame
	var paused=Audio.new();root.add_child(paused);paused.configure(defaults.audio);paused.set_chapter_theme("ENV01")
	await create_timer(.08).timeout # Establish a real AudioServer playback before backgrounding.
	paused.set_paused(true)
	paused.set_chapter_theme("ENV02")
	var new_timeline_paused: bool=true
	for p in paused._music_players:new_timeline_paused=new_timeline_paused and p.stream_paused
	check(new_timeline_paused and not paused.is_processing(),"new chapter created after pause inherits pause on both timelines")
	paused.play_event("CH01.voice.accept","Voice");paused.play_ambience()
	var event_players_paused: bool=true
	for p in paused._ambience_layers:event_players_paused=event_players_paused and p.stream_paused
	for p in paused._pool:
		if p.stream!=null:event_players_paused=event_players_paused and p.stream_paused
	check(event_players_paused,"ambience and event callbacks in same background frame retain pause")
	await create_timer(.08).timeout # Drain queued native start requests while still paused.
	paused.shutdown();paused.free();await process_frame
	print("AUDIO TRANSPORT EDGES: %d checks; %d failures"%[count,failures.size()])
	for issue in failures:printerr("FAIL: "+issue)
	var f=FileAccess.open("res://tests/reports/audio-transport-edges.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":count,"failures":failures,"engine":Engine.get_version_info().string,"timing":"simulated conductor clock with real AudioStreamPlayer nodes","listening_performed":false},"  "));f.close()
	await create_timer(.15).timeout # Let AudioServer release real stream references.
	quit(0 if failures.is_empty() else 1)
func check(condition: bool,message: String) -> void:
	count+=1
	if not condition:failures.append(message)
