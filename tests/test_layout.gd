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
					# A wrapped observer context must not consume the48dp footer touch targets.
					var observer_ids: Array=app.kernel.state.witnesses.keys()
					if not observer_ids.is_empty():
						app.selected="w:"+str(observer_ids[0]);app.inspected=str(observer_ids[0]);app._build_ui();app._update_ui()
						await process_frame;await process_frame
						var context_button: Control=app.ui.find_child("ObjectContext",true,false)
						check(context_button!=null and app.get_viewport_rect().encloses(context_button.get_global_rect()),"observer context stays visible "+locale+" "+str(scale_value)+" "+str(resolution))
						if context_button!=null:
							var context_bounds: Rect2=context_button.get_global_rect()
							var no_footer_overlap: bool=not context_bounds.intersects(app.primary.get_global_rect())
							for control_name in ["OpenObjects","OpenPlan"]:
								no_footer_overlap=no_footer_overlap and not context_bounds.intersects(app.ui.find_child(control_name,true,false).get_global_rect())
							check(no_footer_overlap,"wrapped observer context preserves all fixed footer touch targets "+locale+" "+str(scale_value)+" "+str(resolution))
				# The album remains navigable; lower rows may scroll, the return action stays visible.
				app._open_levels();await process_frame;await process_frame
				var last_level: Button=null;var back: Button=null;var targets_fit: bool=true
				for child in all_buttons(app.overlay):
					if child.has_meta("level_number"):
						targets_fit=targets_fit and child.size.x>=144 and child.size.y>=144
						if int(child.get_meta("level_number"))==30:last_level=child
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
	check(screen.encloses(stage_bounds) and stage_bounds.get_area()>=screen.get_area()*.98,context+" illustrated stage fills the native viewport")
	check(screen.encloses(action_bounds) and app.primary.size.y>=144,context+" main phase action stays visible with48dp native touch height")
	check(app.instruction.get_line_count()==app.instruction.get_visible_line_count(),context+" next-action instruction has complete shaped lines")
	check(screen.encloses(app.instruction.get_parent().get_global_rect()),context+" next-action ticket stays inside the screen")
	var headline: Label=app._goal_headline
	var objective: Control=app.ui.find_child("ObjectiveTicket",true,false)
	check(not headline.text.strip_edges().is_empty() and headline.get_line_count()==headline.get_visible_line_count(),context+" compact current goal has a visible complete line")
	check(objective!=null and screen.encloses(objective.get_global_rect()) and objective.tooltip_text.contains(str(app._hud_copy().objective)),context+" objective ticket exposes the full authored goal")
	check(app.law_label.get_line_count()==app.law_label.get_visible_line_count(),context+" active law context has complete shaped lines")
	var objects: Control=app.ui.find_child("OpenObjects",true,false)
	var plan: Control=app.ui.find_child("OpenPlan",true,false)
	check(objects!=null and plan!=null and screen.encloses(objects.get_global_rect()) and screen.encloses(plan.get_global_rect()),context+" objects and plan are deliberate reachable drawers")
	if objects!=null and plan!=null:
		check(not objects.get_global_rect().intersects(action_bounds) and not plan.get_global_rect().intersects(action_bounds),context+" phase action never overlaps object or plan input")
	check(not is_instance_valid(app._inventory_scroll) and not is_instance_valid(app._audience_scroll) and not is_instance_valid(app._upper_scroll),context+" closed drawers do not leave the rejected permanent sidebar")
	for child in app.ui.get_children():
		if not child is Button or child.text.is_empty():continue
		var icon_space: float=float(child.get_theme_constant("icon_max_width"))+float(child.get_theme_constant("h_separation")) if child.icon!=null else 0.0
		var available: float=child.size.x-child.get_theme_stylebox("normal").get_minimum_size().x-icon_space
		var text_fits: bool=true
		for line in child.text.split("\n"):
			text_fits=text_fits and child.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,child.get_theme_font_size("font_size")).x<=available+1
		check(text_fits,context+" "+str(child.name)+" text fits its actual font, icon and content padding")
func all_buttons(node: Node) -> Array:
	var result: Array=[]
	if node is Button:result.append(node)
	for child in node.get_children():result.append_array(all_buttons(child))
	return result
