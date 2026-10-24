extends SceneTree
## Independent service review. Run with a dedicated XDG_DATA_HOME test profile.
const Audio=preload("res://services/audio_service.gd")
const Saver=preload("res://services/save_service.gd")
const App=preload("res://tests/review_app_host.gd")
var failures: Array[String]=[]
var count: int=0
var defaults: Dictionary={}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	defaults=JSON.parse_string(FileAccess.get_file_as_string("res://data/settings_default.json"))
	save_cases();await audio_cases();await glue_cases()
	print("INDEPENDENT SERVICE BOUNDARIES: %d checks; %d failures; audio clock simulated1200s, not listening"%[count,failures.size()])
	for issue in failures:printerr("REVIEW FAIL: "+issue)
	DirAccess.make_dir_recursive_absolute("res://tests/reports")
	var f=FileAccess.open("res://tests/reports/service-boundaries.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":count,"failures":failures,"engine":Engine.get_version_info().string,"simulated_audio_seconds":1200,"real_20_minute_listening":false},"  "));f.close()
	await create_timer(.15).timeout
	quit(0 if failures.is_empty() else 1)
func save_cases() -> void:
	var s=Saver.new();var name: String="review_header_integrity";clean(name)
	s.write_slot(name,{"marker":"A"});s.write_slot(name,{"marker":"B"})
	var backup: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://"+name+".json.bak"));backup.revision=1000
	write_text("user://"+name+".json.bak",JSON.stringify(backup))
	check(s.read_slot(name).get("marker","")=="B","corrupt revision metadata cannot promote an older backup")
	clean(name);s.write_slot(name,{"marker":"A"});s.write_slot(name,{"marker":"B"})
	var newer: String=FileAccess.get_file_as_string("user://"+name+".json");var older: String=FileAccess.get_file_as_string("user://"+name+".json.bak")
	write_text("user://"+name+".json",older);write_text("user://"+name+".json.bak",newer)
	check(s.read_slot(name).get("marker","")=="B","newest valid backup wins over older valid primary")
	check(s.write_slot(name,{"marker":"C"}) and s._valid_envelope("user://"+name+".json").revision>2,"write after newest-backup recovery is monotonic")
	write_text("user://"+name+".json","broken")
	check(s.read_slot(name).get("marker","")=="B","newest valid backup survives writing over older primary")
	clean(name)
	var sanitized: Dictionary=s.sanitize_settings({"locale":"unsupported","accessibility":{"text_scale":-2},"audio":{"categories":{"Music":{"volume":2,"enabled":"yes"}}}},defaults)
	check(sanitized.locale in ["ru","en"],"unsupported settings locale falls back to supported language")
	check(sanitized.accessibility.text_scale in [1,1.2,1.4],"invalid text scale cannot create negative font sizes")
	check(sanitized.audio.categories.Music.volume==defaults.audio.categories.Music.volume and sanitized.audio.categories.Music.enabled is bool,"invalid nested audio values fall back independently")
func audio_cases() -> void:
	var a=Audio.new();root.add_child(a)
	var settings: Dictionary=defaults.audio.duplicate(true);settings.categories.Music.enabled=false;settings.sound_enabled=false
	a.configure(settings);a.play_music("music_menu")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")),"Music off is applied before initial playback")
	var same_resource: bool=true;var equal_lengths: bool=true
	for scene in ["ENV01","ENV02","ENV03","FINALE"]:
		var ok: bool=a.set_chapter_theme(scene,scene=="FINALE");check(ok,"chapter conductor initializes "+scene)
		if not ok:continue
		var sync: AudioStreamSynchronized=a.music.stream
		equal_lengths=equal_lengths and is_equal_approx(sync.get_sync_stream(0).get_length(),sync.get_sync_stream(1).get_length()) and is_equal_approx(sync.get_sync_stream(1).get_length(),sync.get_sync_stream(2).get_length())
		var id: int=sync.get_instance_id()
		for i in range(3000):
			if i%100==0:a.set_phase("PERFORMANCE" if i%200==0 else "PLAN_RESOLUTION")
			if i%500==0:a.duck_music(1.2,-9)
			a._process(.1)
		same_resource=same_resource and a.music.stream.get_instance_id()==id
	check(equal_lengths,"all chapter/finale stem loop lengths match")
	check(same_resource,"phase fades never replace synchronized timeline during simulated1200s")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) and AudioServer.is_bus_mute(AudioServer.get_bus_index("Voice")),"phase fades and duck never override category mute")
	a.settings.categories.Music.enabled=true;a.settings.sound_enabled=true;a.settings.categories.Voice.enabled=false;a.apply_settings();a._duck_remaining=0
	a.play("voice_marfa","Voice")
	check(a._duck_remaining==0,"user-muted Voice does not duck audible Music")
	a.settings.categories.Music.enabled=false;a.apply_settings();a.catalog["review_bad_bus"]={"path":a._path("stinger_law"),"bus":"Master"}
	var next: int=a._next;a.play("review_bad_bus","Music")
	check(a._next==next,"invalid leaf bus cannot bypass category mute through Master")
	a.duck_music(1,-9);var remaining: float=a._duck_remaining;a.set_paused(true)
	await create_timer(.05).timeout
	check(a.music.stream_paused and a._duck_remaining==remaining,"background pauses conductor/duck clock")
	a.set_paused(false);check(not a.music.stream_paused,"resume unpauses actual music player")
	a.shutdown();a.free();await process_frame
func glue_cases() -> void:
	var s=Saver.new();var a=Audio.new();root.add_child(a);a.configure(defaults.audio);a.play_ambience()
	var app=App.new();app.settings=defaults.duplicate(true);app.audio=a;app.level_ids.clear()
	for n in range(1,31):app.level_ids.append("L%02d"%n)
	app.progress={"schema_version":1,"completed":{},"unlocked":1,"current_level":1};app._capture_stage="plan";root.add_child(app)
	app.start_level(11,false);var wanted=load(a._path("AMB_KITCHEN_HOUSE"))
	check(same_audio(a.ambience.stream,wanted),"ENV02 switches river ambience to kitchen")
	app.start_level(21,false);wanted=load(a._path("AMB_ARCHIVE_PAPER"))
	check(same_audio(a.ambience.stream,wanted),"ENV03 switches ambience to archive")
	app.start_level(1,false);var before: String=app.kernel.state_hash()
	for i in range(20):app._update_ui()
	check(app.kernel.state_hash()==before,"UI status updates do not mutate gameplay")
	for pair in [["float","stage_float"],["stone","stage_stone"],["screen_a","screen_left"]]:app._command("PlaceProp",{"entity_id":pair[0],"slot_id":pair[1]})
	var plan: String=app.kernel.state_hash();app._command("BeginPerformance");app.kernel.advance_ticks(12);app._notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	var progress: Dictionary=s.read_slot("progress")
	check(progress.checkpoint.phase=="PLAN_SHOW" and progress.checkpoint.active_laws.is_empty(),"background saves pre-show plan")
	app._notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED);check(app.kernel.state_hash()==plan,"resume restores exact stable plan")
	app._command("BeginPerformance");app._events(app.kernel.advance_ticks(100));app._command("ActivateLaw",{"myth_id":"M01"});progress=s.read_slot("progress")
	check(progress.checkpoint.active_laws==["M01"] and progress.checkpoint.phase=="PLAN_RESOLUTION","law persists before transformation animation")
	app._notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED);app._notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	check(app.kernel.state.active_laws==["M01"],"background after commit preserves law")
	app.progress=s.read_slot("progress");app.start_level(1,true);check(app.kernel.state.active_laws==["M01"],"reopen restores committed law")
	app.free();a.shutdown();a.free();await process_frame
	a=Audio.new();root.add_child(a);a.configure(defaults.audio)
	app=App.new();app.settings=defaults.duplicate(true);app.audio=a;app.level_ids.clear();app.level_ids.append("L01");app._capture_stage="plan"
	app.progress={"schema_version":1,"completed":{"L01":{"stars":1}},"unlocked":2,"current_level":1,"checkpoint":"broken"};root.add_child(app);app.start_level(1,true)
	check(is_instance_valid(app.ui) and app.progress.completed.has("L01"),"malformed checkpoint falls back without losing campaign")
	app.free();a.shutdown();a.free();await process_frame
func same_audio(a: AudioStream,b: AudioStream) -> bool:
	if a is AudioStreamOggVorbis and b is AudioStreamOggVorbis:return a.packet_sequence==b.packet_sequence
	if a is AudioStreamWAV and b is AudioStreamWAV:return a.data==b.data
	return false
func write_text(path: String,value: String) -> void:
	var f=FileAccess.open(path,FileAccess.WRITE);f.store_string(value);f.close()
func clean(name: String) -> void:
	for suffix in [".json",".json.bak",".json.tmp"]:
		if FileAccess.file_exists("user://"+name+suffix):DirAccess.remove_absolute("user://"+name+suffix)
func check(ok: bool,message: String) -> void:
	count+=1
	if not ok:failures.append(message)
