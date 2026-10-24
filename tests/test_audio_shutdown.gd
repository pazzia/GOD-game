extends SceneTree
const Audio=preload("res://services/audio_service.gd")
var failures: Array[String]=[]
var checks: int=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok:failures.append(label)
func run() -> void:
 var defaults=JSON.parse_string(FileAccess.get_file_as_string("res://data/settings_default.json"))
 var a=Audio.new();root.add_child(a);a.configure(defaults.audio)
 a.set_chapter_theme("ENV01");a.play_music("music_album")
 await create_timer(.1).timeout
 a._process(.95) # Keep the outgoing timeline near its actual 1.2s finish.
 check(a._outgoing_index>=0,"fixture has a genuine active two-player crossfade")
 a.shutdown();var transport: Dictionary=a.conductor_state()
 check(not a.is_processing(),"shutdown disables the conductor before clearing stream arrays")
 await create_timer(.3).timeout # Service remains alive through the app grace period.
 a._process(.5)
 check(a._music_players.is_empty() and a._pool.is_empty() and a._ambience_layers.is_empty(),"alive shutdown service has no retained active stream pools")
 a.set_paused(false);a.play_music("music_menu");a.play_ambience();a.play_event("CH01.voice.accept","Voice");a.set_phase("PERFORMANCE");a.duck_music(1,-9)
 check(not a.set_chapter_theme("ENV02"),"late chapter callback rejects terminal audio lifecycle")
 check(not a.is_processing() and a.conductor_state()==transport,"late callbacks cannot restart a stopped conductor or alter its transport")
 a.shutdown();a.free();await create_timer(.15).timeout
 var file=FileAccess.open("res://tests/reports/audio-shutdown.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"engine":Engine.get_version_info().string},"  "));file.close()
 print("AUDIO SHUTDOWN: %d checks; %d failures"%[checks,failures.size()])
 for failure in failures:printerr("FAIL: "+failure)
 quit(0 if failures.is_empty() else 1)
