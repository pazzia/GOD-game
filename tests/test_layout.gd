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
	game.theme=preload("res://presentation/theme.gd").make_theme()
	game.progress={"schema_version":1,"unlocked":30,"completed":{},"current_level":1}
	game._front_menu=true;game._capture_stage="fixture"
	for n in range(1,31):game.level_ids.append("L%02d"%n)
	game.catalog=JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/ru.json"))
	var sound=Audio.new();root.add_child(sound);sound.configure(game.settings.audio);game.audio=sound
	game.size=Vector2(1920,1080);root.add_child(game)
	return game
func run() -> void:
	root.size=Vector2i(1920,1080);root.content_scale_size=Vector2i(1920,1080)
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
	# Physical landscape profiles: the stage stays dominant at both text sizes.
	for resolution in [Vector2i(720,360),Vector2i(844,390),Vector2i(960,540)]:
		root.size=resolution;root.content_scale_size=Vector2i(1920,1080)
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
		await process_frame;await process_frame
		for locale in ["ru","en"]:
			app.settings.locale=locale;app._load_catalog()
			for scale_value in [1.0,1.4]:
				app.settings.accessibility.text_scale=scale_value
				for number in [1,11,21,30]:
					app.start_level(number,false);app._close_overlay();await process_frame;await process_frame
					inspect_layout("L%02d %s %s %s"%[number,locale,str(scale_value),str(resolution)])
					var pixel_scale: float=float(resolution.y)/app.get_viewport_rect().size.y
					check(app.primary.size.y*pixel_scale>=47.5,"primary keeps48px touch height at "+str(resolution))
				# The album remains navigable; lower rows may scroll, the return action stays visible.
				app._open_levels();await process_frame;await process_frame
				var last_level: Button=null;var back: Button=null;var targets_fit: bool=true
				for child in all_buttons(app.overlay):
					if child.text.is_valid_int():
						targets_fit=targets_fit and child.size.x>=144 and child.size.y>=144
						if child.text=="30":last_level=child
					elif child.text.replace("\n"," ")==app.tx("ui.back_game","Вернуться в игру"):back=child
				check(targets_fit,"album has48dp number targets "+locale+" "+str(scale_value))
				check(last_level!=null and back!=null,"album exposes last level and return action")
				if last_level!=null and back!=null:
					var ancestor: Node=last_level.get_parent()
					while ancestor!=null:
						if ancestor is ScrollContainer:ancestor.ensure_control_visible(last_level)
						ancestor=ancestor.get_parent()
					await process_frame;await process_frame
					check(last_level.get_global_rect().end.y<=back.get_global_rect().position.y-8,"album final row is reachable above fixed return action "+locale+" "+str(scale_value))
				app._close_overlay()
	root.size=Vector2i(1920,1080);root.content_scale_size=Vector2i(1920,1080)
	await process_frame;await process_frame
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
	var screen: Rect2=app.get_viewport_rect()
	var stage_bounds: Rect2=app.stage.get_global_rect()
	var action_bounds: Rect2=app.primary.get_global_rect()
	var body: Label=app.instruction
	var law: Label=app.law_label
	check(screen.encloses(stage_bounds) and stage_bounds.size.x>stage_bounds.size.y,context+" entire landscape stage is visible")
	var large_text: bool=float(app.settings.accessibility.text_scale)>=1.4
	check(stage_bounds.get_area()>=screen.get_area()*(.40 if large_text else .43) and stage_bounds.size.y>=screen.size.y*(.58 if large_text else .62),context+" game world remains dominant, allowing space for accessibility text")
	check(not stage_bounds.intersects(action_bounds) and screen.encloses(action_bounds) and app.primary.size.y>=144,context+" main action is visible, large and outside the scene")
	check(body.get_line_count()==body.get_visible_line_count(),context+" quest instruction contains complete shaped lines")
	var headline: Label=app._goal_headline
	var scroll_bounds: Rect2=app._upper_scroll.get_global_rect()
	check(not headline.text.strip_edges().is_empty() and headline.get_line_count()==headline.get_visible_line_count(),context+" current objective has complete shaped text")
	check(headline.get_global_rect().end.y<=body.get_global_rect().position.y and scroll_bounds.encloses(headline.get_global_rect()),context+" current objective is visible above instructions before any scrolling")
	check(law.get_line_count()==law.get_visible_line_count(),context+" phase title contains complete shaped lines")
	var names_fit: bool=true
	for card in app.witness_labels.values():
		var label: Label=card.name
		var cell: Control=label.get_parent()
		if label.visible:names_fit=names_fit and label.get_line_count()==label.get_visible_line_count() and label.position.x+label.size.x<=cell.size.x+1 and label.position.y+label.size.y<=cell.size.y+1
		names_fit=names_fit and app._audience_scroll.get_global_rect().encloses(cell.get_global_rect())
	check(names_fit,context+" witness names have complete shaped lines and every card is visible without panning")
	var inventory_fit: bool=true;var inventory_text_fit: bool=true;var inventory_color_preserved: bool=true
	for row in app._inventory_scroll.get_children():
		if not row is HBoxContainer:continue
		for button in row.get_children():
			inventory_fit=inventory_fit and button.size.y+(app._inventory_scroll.get_h_scroll_bar().size.y if app._inventory_scroll.get_h_scroll_bar().visible else 0.0)<=app._inventory_scroll.size.y+1
			var icon_space: float=0
			if button.icon!=null:
				icon_space=float(button.get_theme_constant("icon_max_width"))+float(button.get_theme_constant("h_separation"))
				inventory_color_preserved=inventory_color_preserved and button.get_theme_color("icon_normal_color").is_equal_approx(Color.WHITE)
			var available: float=button.size.x-button.get_theme_stylebox("normal").get_minimum_size().x-icon_space
			for line in button.text.split("\n"):
				var measured: float=button.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
				inventory_text_fit=inventory_text_fit and measured<=available+1
	check(inventory_fit,context+" complete prop labels/icons fit above the horizontal scrollbar")
	check(inventory_text_fit,context+" every inventory word fits its actual font, icon and content padding")
	check(inventory_color_preserved,context+" colored prop illustrations retain their authored colors")
	check(screen.encloses(app._inventory_scroll.get_global_rect()),context+" inventory remains visible without scrolling the scene")
func all_buttons(node: Node) -> Array:
	var result: Array=[]
	if node is Button:result.append(node)
	for child in node.get_children():result.append_array(all_buttons(child))
	return result
