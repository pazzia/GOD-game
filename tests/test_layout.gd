extends SceneTree
## Inspect native Label geometry after shaping actual authored campaign states.
const App=preload("res://tests/review_app_host.gd")
const Audio=preload("res://services/audio_service.gd")
var count: int=0
var failures: Array[String]=[]
var layouts: int=0
var app: Control
func _initialize() -> void:call_deferred("run")
func check(passed: bool,label: String) -> void:
	count+=1
	if not passed and failures.size()<100:failures.append(label)
func fixture():
	var game=App.new()
	game.settings=JSON.parse_string(FileAccess.get_file_as_string("res://data/settings_default.json"))
	var t=Theme.new();t.default_font=load("res://assets/fonts/DejaVuSans.ttf");game.theme=t
	game.progress={"schema_version":1,"unlocked":30,"completed":{},"current_level":1}
	game._front_menu=true;game._capture_stage="fixture"
	for n in range(1,31):game.level_ids.append("L%02d"%n)
	game.catalog=JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/ru.json"))
	var sound=Audio.new();root.add_child(sound);sound.configure(game.settings.audio);game.audio=sound
	game.size=Vector2(1080,1920);root.add_child(game)
	return game
func run() -> void:
	root.size=Vector2i(1080,1920);root.content_scale_size=Vector2i(1080,1920)
	app=fixture()
	for number in range(1,31):
		app.level_number=number
		var id: String="L%02d"%number
		var data=JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/"+id+".json"))
		if not app.kernel.load_level(data,48121):check(false,id+" content rejected");continue
		var samples: Array=[app.kernel.snapshot()];var seen: Dictionary={}
		var replay_path: String="res://tests/"+("" if number<=3 else "replays/")+id+"_solution.json"
		var replay=JSON.parse_string(FileAccess.get_file_as_string(replay_path))
		for step in replay.steps:
			if step.op=="command":
				var result: Dictionary=app.kernel.dispatch(step)
				if not result.accepted:check(false,id+" replay rejected "+step.type)
			elif step.op=="advance_ticks":app.kernel.advance_ticks(int(step.count))
			var marker: String=app.kernel.state.phase+str(app.kernel.state.active_laws)
			if not seen.has(marker):samples.append(app.kernel.snapshot());seen[marker]=true
		for locale in ["ru","en"]:
			app.settings.locale=locale;app._load_catalog()
			for scale_value in [1.0,1.4]:
				app.settings.accessibility.text_scale=scale_value
				for sample in samples:
					check(app.kernel.restore(sample),id+" snapshot restore")
					app.selected="";app.inspected="";app._build_ui();app._update_ui();app._close_overlay()
					await process_frame;await process_frame
					inspect_layout(id+" "+locale+" "+str(scale_value)+" "+app.kernel.state.phase)
	# Album targets must stay fully reachable above its sticky return action.
	for locale in ["ru","en"]:
		app.settings.locale=locale;app._load_catalog()
		for scale_value in [1.0,1.4]:
			app.settings.accessibility.text_scale=scale_value;app._open_levels()
			await process_frame;await process_frame
			var last_level: Button=null;var back: Button=null;var targets_fit: bool=true
			for child in app.overlay.get_children():
				if not child is Button:continue
				if child.text.is_valid_int():
					targets_fit=targets_fit and child.size.x>=144 and child.size.y>=144
					if child.text=="30":last_level=child
				elif child.text.replace("\n"," ")==app.tx("ui.back_game","Вернуться в игру"):back=child
			check(targets_fit,"album has48dp number targets "+locale+" "+str(scale_value))
			check(last_level!=null and back!=null and last_level.get_global_rect().end.y<=back.get_global_rect().position.y-16,"album final row stays above return action "+locale+" "+str(scale_value))
			app._close_overlay()
	# Stateful cosmetic/visibility checks must not be replaced by geometry mirrors.
	app.settings.locale="ru";app.settings.accessibility.text_scale=1.0
	app.start_level(1,false);app._close_overlay();await process_frame
	var original_stage: Control=app.stage
	app.stage.play_actor("felix","stamp");await process_frame
	var hero: Node2D=app.stage._puppets.felix
	var animation_clock: float=hero.animator.current_animation_position
	app._build_ui();app._update_ui();await process_frame
	check(app.stage==original_stage and app.stage._puppets.felix==hero,"HUD reflow reuses the exact Stage and puppet nodes")
	check(hero.current_state=="stamp" and hero.animator.current_animation_position>=animation_clock,"HUD reflow preserves an in-flight stamp")
	await create_timer(.1).timeout
	app.notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	var stage_clock: float=app.stage.clock
	animation_clock=hero.animator.current_animation_position
	await create_timer(.1).timeout
	check(app.stage.clock==stage_clock and hero.animator.current_animation_position==animation_clock,"background callback freezes Stage clock and AnimationPlayer descendants")
	app.notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	await create_timer(.05).timeout
	check(app.stage.clock>stage_clock,"returning to app resumes the cosmetic clock")
	app.audio.shutdown();app.audio.free();app.free();await create_timer(.15).timeout
	var report={"checks":count,"layouts":layouts,"failures":failures,"engine":Engine.get_version_info().string,"scope":"real native Label shaping; authored campaign phase snapshots; RU/EN at 100/140%; no physical-device claim"}
	var file=FileAccess.open("res://tests/reports/layout.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("NATIVE LAYOUT: %d checks across %d layouts; %d failures"%[count,layouts,failures.size()])
	for issue in failures:printerr("FAIL: "+issue)
	quit(0 if failures.is_empty() else 1)
func inspect_layout(context: String) -> void:
	layouts+=1
	var law: Label=app.law_label
	var body: Label=app.instruction
	check(law.get_line_count()==law.get_visible_line_count() and law.position.y+law.size.y<=body.position.y-12,context+" law text stays inside its panel")
	check(body.get_line_count()==body.get_visible_line_count() and body.position.y+body.size.y<=app.stage.position.y-16,context+" full instruction precedes the playfield")
	var names_fit: bool=true
	for card in app.witness_labels.values():
		var label: Label=card.name
		var cell: Control=label.get_parent()
		names_fit=names_fit and label.get_line_count()==label.get_visible_line_count() and label.position.x+label.size.x<=cell.size.x+1 and label.position.y+label.size.y<=cell.size.y+1
	check(names_fit,context+" witness names have complete shaped lines and reachable cards")
	var inventory_fit: bool=true
	for row in app._inventory_scroll.get_children():
		if not row is HBoxContainer:continue
		for button in row.get_children():inventory_fit=inventory_fit and button.size.y+app._inventory_scroll.get_h_scroll_bar().size.y<=app._inventory_scroll.size.y+1
	check(inventory_fit,context+" complete prop labels/icons fit above the horizontal scrollbar")
	check(is_equal_approx(app.stage.size.x/app.stage.size.y,1.5),context+" common 3:2 playfield")
	check(app.primary.get_global_rect().end.y<=root.size.y and app.primary.size.y>=144 and app._upper_scroll.get_global_rect().end.y<=app.primary.get_global_rect().position.y,context+" primary is sticky below scroll content")
