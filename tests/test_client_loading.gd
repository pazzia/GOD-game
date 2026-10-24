extends SceneTree
const App=preload("res://tests/load_error_host.gd")
const Audio=preload("res://services/audio_service.gd")
var failures: Array[String]=[]
var count: int=0
func _initialize() -> void:call_deferred("run")
func fixture():
	var app=App.new()
	app.settings=JSON.parse_string(FileAccess.get_file_as_string("res://data/settings_default.json"))
	var player=Audio.new();root.add_child(player);player.configure(app.settings.audio);app.audio=player
	app.progress={"schema_version":1,"unlocked":11,"completed":{"L01":{"stars":1}},"current_level":1}
	app._capture_stage="plan"
	for number in range(1,31):app.level_ids.append("L%02d"%number)
	app.catalog=JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/ru.json"))
	root.add_child(app)
	return app
func run() -> void:
	var app=fixture()
	check(app.start_level(1,false),"valid initial scene opens")
	var before: String=app.kernel.state_hash()
	var progress_before: String=JSON.stringify(app.progress)
	app.blocked_level="L11"
	check(not app.start_level(11,false),"invalid scene rejects before committing new level number")
	check(app.level_number==1 and app.kernel.state.level_id=="L01" and app.kernel.state_hash()==before,"rejected scene preserves previous game and number")
	check(JSON.stringify(app.progress)==progress_before,"rejected scene preserves campaign progress")
	check(is_instance_valid(app.ui) and is_instance_valid(app.overlay),"rejected scene shows usable localized recovery panel")
	check(app._invalid_levels.has("L11"),"bad scene is marked unavailable in the album")
	var haptics: Array=[]
	app.haptic_requested.connect(func(milliseconds):haptics.append(milliseconds))
	app.settings.accessibility.haptics=false;app._haptic(22)
	check(haptics.is_empty(),"disabled haptics send no platform request")
	app.settings.accessibility.haptics=true;app._haptic(65)
	check(haptics==[65],"enabled haptics send the requested duration")
	# Let the audio server consume this frame before tearing down newly-started streams.
	await create_timer(.06).timeout
	app.audio.shutdown();app.audio.free();app.free()
	await process_frame
	app=fixture();app.blocked_level="L01"
	check(not app.start_level(1,true),"invalid initial scene rejects safely")
	check(app.kernel.state.is_empty() and is_instance_valid(app.overlay),"invalid boot has a recovery panel rather than an empty screen")
	app._open_levels()
	var first=find_button(app.overlay,"1")
	check(first!=null and first.disabled,"album disables the scene known to be invalid")
	check(app.progress.completed.has("L01"),"invalid checkpoint/scene does not erase past completions")
	# Let the audio server consume this frame before tearing down newly-started streams.
	await create_timer(.06).timeout
	app.audio.shutdown();app.audio.free();app.free()
	await create_timer(.15).timeout
	print("CLIENT LOADING: %d checks; %d failures"%[count,failures.size()])
	for message in failures:printerr("FAIL: "+message)
	var file=FileAccess.open("res://tests/reports/client-loading.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":count,"failures":failures,"engine":Engine.get_version_info().string},"  "));file.close()
	quit(0 if failures.is_empty() else 1)
func find_button(node: Node,text: String):
	if node is Button and node.text.split(" ")[0]==text:return node
	for child in node.get_children():
		var found=find_button(child,text)
		if found!=null:return found
	return null
func check(passed: bool,message: String) -> void:
	count+=1
	if not passed:failures.append(message)
