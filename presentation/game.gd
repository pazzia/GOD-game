extends Control
const Kernel=preload("res://core/simulation_kernel.gd")
const Stage=preload("res://presentation/stage_view.gd")
const Saver=preload("res://services/save_service.gd")
const Audio=preload("res://services/audio_service.gd")
const QuestGuide=preload("res://presentation/quest_guide.gd")
const ThemeKit=preload("res://presentation/theme.gd")
const Art=preload("res://presentation/reboot_art.gd")
const INK=ThemeKit.INK
const CREAM=ThemeKit.CREAM
const PURPLE=ThemeKit.PURPLE
const GREEN=ThemeKit.GREEN
# 1080 landscape reference height maps to 360 dp: 48px is readable 16sp.
const BODY_FONT_SIZE: int=ThemeKit.BODY_FONT_SIZE
const DISABLED_TEXT=ThemeKit.DISABLED_TEXT
const CHARACTER_NAMES={"CH01":"Профессор Феликс","CH02":"Плюм","CH03":"Марфа","CH04":"Семён","CH05":"Ника","CH06":"Лада","CH07":"Роза","CH08":"Гюго","CH09":"Карамелька"}
const PROP_NAMES={"stone_m":"Камень M","stone_l":"Камень L","stone_s":"Камень S","float":"Поплавок","screen":"Ширма","cargo_crate":"Ящик","clamp":"Зажим","cold_pack":"Криопак","control_weight":"Контрольный груз","decoy_flame":"Бутафорский огонь","oven":"Жаровня","bowl":"Чаша","heated_stone":"Тёплый камень","insulated_box":"Термокороб","bread":"Хлеб","dessert":"Десерт","hidden_frame":"Тайная рама","paper_span":"Бумажный мост","paper_wall":"Бумажная преграда","paper_flags":"Флажки","hoist":"Таль","boat":"Лодка","mooring_rope":"Причальная верёвка","tow_rope":"Буксирная верёвка","safety_thread":"Страховочная нить","span_anchor":"Опора","stone_anchor":"Каменный якорь","bollard":"Деревянный кнехт","wooden_gate":"Калитка","ticket_booth":"Билетная будка","steam_cloud":"Пар","actor_felix":"Феликс","actor_goat":"Карамелька"}
var kernel=Kernel.new()
var saver=Saver.new()
var audio: Node
var settings: Dictionary={}
var progress: Dictionary={}
var catalog: Dictionary={}
var campaign: Dictionary={}
var level_ids: Array[String]=[]
var level_number: int=1
var ui: Control
var overlay: Control
var stage: Control
var primary: Button
var instruction: Label
var _goal_headline: Label
var law_label: Label
var witness_labels: Dictionary={}
var selected: String=""
var inspected: String=""
var _hint_index: int=0
var _accumulator: float=0
var _last_phase: String=""
var _app_paused: bool=false
var _capture_stage: String=""
var _screenshot: String=""
var _capture_scroll: String=""
var _frame: int=0
var _flash: ColorRect
var _transformation: float=0
var _quitting: bool=false
var _front_menu: bool=false
var _checkpoint_reset_pending: bool=false
var _invalid_levels: Dictionary={}
signal haptic_requested(milliseconds: int)
var _sheet_content_top: float=366
var _caption_panel: Panel
var _caption_label: Label
var _caption_remaining: float=0
var _caption_queue: Array=[]
var _layout_law_height: float=0
var _layout_instruction_height: float=0
var _upper_scroll: ScrollContainer
var _audience_scroll: ScrollContainer
var _inventory_scroll: ScrollContainer
var _text_measure_cache: Dictionary={}
var _sheet_rect: Rect2
var _sheet_inner: Rect2
var _layout_copy_key: String=""
var _layout_screen: Vector2=Vector2.ZERO

func _ready() -> void:
	theme=ThemeKit.make_theme()
	if OS.has_feature("android") or OS.has_feature("ios"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	var defaults: Dictionary=_json("res://data/settings_default.json")
	settings=saver.sanitize_settings(saver.read_slot("settings",defaults),defaults)
	progress=saver.read_slot("progress",{"schema_version":1,"unlocked":1,"completed":{},"current_level":1})
	if not progress.get("completed") is Dictionary:progress={"schema_version":1,"unlocked":1,"completed":{},"current_level":1}
	audio=Audio.new();add_child(audio);audio.configure(settings.audio)
	_load_catalog()
	campaign=_json("res://data/campaign.json")
	if campaign.has("levels"):
		for entry in campaign.levels:
			if FileAccess.file_exists(entry.path if entry.path.begins_with("res://") else "res://"+entry.path):level_ids.append(entry.id)
	if level_ids.is_empty():
		for n in range(1,31):
			var id: String="L%02d" % n
			if FileAccess.file_exists("res://data/levels/"+id+".json"):level_ids.append(id)
	progress=saver.sanitize_progress(progress,level_ids.size())
	level_number=clampi(int(progress.get("current_level",1)),1,maxi(1,level_ids.size()))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):level_number=clampi(arg.trim_prefix("--level=").to_int(),1,maxi(1,level_ids.size()))
		if arg.begins_with("--screenshot="):_screenshot=arg.trim_prefix("--screenshot=")
		if arg.begins_with("--capture-stage="):_capture_stage=arg.trim_prefix("--capture-stage=")
		if arg.begins_with("--capture-scroll="):_capture_scroll=arg.trim_prefix("--capture-scroll=")
		if arg.begins_with("--locale=") and arg.trim_prefix("--locale=") in ["ru","en"]:settings.locale=arg.trim_prefix("--locale=")
		if arg.begins_with("--text-scale="):
			var capture_scale: float=arg.trim_prefix("--text-scale=").to_float()
			if capture_scale in [1.0,1.2,1.4]:settings.accessibility.text_scale=capture_scale
	_load_catalog()
	_front_menu=_capture_stage.is_empty()
	if not start_level(level_number,true):return
	get_tree().auto_accept_quit=false
	if not _capture_stage.is_empty():_prepare_capture()
	else:_show_title()
func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return {}
	var parser=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK:return {}
	return parser.data if parser.data is Dictionary else {}
func _load_catalog() -> void:catalog=_json("res://data/localization/"+settings.get("locale","ru")+".json")
func tx(key: String,fallback: String) -> String:return catalog.get(key,fallback)
func txf(key: String,fallback: String,values: Dictionary) -> String:return tx(key,fallback).format(values)
func _key(suffix: String) -> String:return "level."+level_ids[level_number-1]+"."+suffix
func _name(entity_id: String) -> String:
	var d: Dictionary=kernel._entities[entity_id]
	return tx("entity."+entity_id+".name",tx("prop."+d.type_id+".name",PROP_NAMES.get(d.type_id,"Реквизит")))
func _law_name(id: String) -> String:return tx("law."+id+".name",{"M01":"Камни плавают","M02":"Огонь замораживает","M03":"Бумага прочнее стали"}.get(id,"Чудо"))
func _route_name(id: String) -> String:return tx("route."+id+".name",{"cross":"Переправа","to_island":"На остров","to_far":"На дальний берег","unload":"Разгрузить лодку","dry_delivery":"Доставка по суше","return_to_hoist":"Вернуться к тали","boat_route":"Лодочная протока","detour":"В обход","first_delivery":"Первая доставка","final_cross":"Финальная переправа"}.get(id,"Путь"))
func _character_name(id: String) -> String:return tx("character."+id+".name",CHARACTER_NAMES.get(id,"Зритель"))
func start_level(number: int,resume: bool=false) -> bool:
	if number<1 or number>level_ids.size():
		_level_load_failed("")
		return false
	if not resume:_checkpoint_reset_pending=false
	var id: String=level_ids[number-1]
	var definition: Dictionary=_json("res://data/levels/"+id+".json")
	if not kernel.load_level(definition,48121):
		_level_load_failed(id)
		return false
	level_number=number
	_invalid_levels.erase(id)
	var checkpoint=progress.get("checkpoint")
	if resume and checkpoint is Dictionary and checkpoint.get("level_id","")==id:
		_checkpoint_reset_pending=not kernel.restore(checkpoint)
	selected="";inspected="";_hint_index=0;_accumulator=0;_last_phase="";_caption_remaining=0;_caption_queue.clear()
	_build_ui();_update_ui();_save_progress()
	if not _front_menu:audio.set_chapter_theme(definition.get("scene_id","ENV01"),id=="L30")
	if (not resume or not progress.completed.has(id)) and _capture_stage.is_empty():_briefing()
	return true
func _level_load_failed(id: String) -> void:
	if not id.is_empty():_invalid_levels[id]=true
	var had_level: bool=not kernel.state.is_empty()
	_modal(tx("ui.level_unavailable","Это чудо пока недоступно"),tx("ui.level_load_error","Не удалось открыть эту сцену. Можно выбрать другое чудо и продолжить игру."),tx("ui.back_game","Вернуться в игру") if had_level else tx("ui.album","Альбом уровней"),func():
		if not had_level:_open_levels())

func _box(parent: Control,rect: Rect2,color: Color,radius: int=24) -> Panel:
	var panel=Panel.new();panel.position=rect.position;panel.size=rect.size
	var style=ThemeKit.panel_style("surface",radius);style.bg_color=color;panel.add_theme_stylebox_override("panel",style);panel.mouse_filter=MOUSE_FILTER_IGNORE;parent.add_child(panel);return panel
func _text(parent: Control,value: String,rect: Rect2,font_size: int=BODY_FONT_SIZE,color: Color=INK) -> Label:
	var label=Label.new();label.position=rect.position;label.size=rect.size;label.text=value
	label.add_theme_font_size_override("font_size",int(font_size*float(settings.get("accessibility",{}).get("text_scale",1))))
	if font_size>=56:label.add_theme_font_override("font",ThemeKit.heading_font())
	label.add_theme_color_override("font_color",color);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;label.mouse_filter=MOUSE_FILTER_IGNORE;parent.add_child(label);return label
func _button(parent: Control,value: String,rect: Rect2,callback: Callable,filled: bool=false,font_size: int=BODY_FONT_SIZE,icon: String="") -> Button:
	var b=Button.new();b.mouse_filter=MOUSE_FILTER_PASS;b.position=rect.position;b.size=rect.size;b.clip_text=true;b.text=value;b.add_theme_font_size_override("font_size",int(font_size*float(settings.get("accessibility",{}).get("text_scale",1))))
	b.add_theme_color_override("font_color",INK);b.add_theme_color_override("font_hover_color",INK if filled else ThemeKit.GREEN);b.add_theme_color_override("font_pressed_color",INK if filled else ThemeKit.GREEN)
	b.add_theme_color_override("font_focus_color",INK)
	for color_name in ["icon_normal_color","icon_hover_color","icon_pressed_color","icon_focus_color"]:b.add_theme_color_override(color_name,INK)
	b.add_theme_color_override("font_disabled_color",DISABLED_TEXT);b.add_theme_color_override("icon_disabled_color",DISABLED_TEXT)
	for state_name in ["normal","hover","pressed","focus","disabled"]:
		b.add_theme_stylebox_override(state_name,ThemeKit.button_style(state_name,filled))
	if not icon.is_empty() and ResourceLoader.exists("res://assets/art/ui/"+icon+".svg"):
		var icon_only: bool=icon=="settings" and value.is_empty()
		b.icon=load("res://assets/art/ui/"+icon+".svg");b.expand_icon=true;b.add_theme_constant_override("icon_max_width",72 if icon_only else 48);b.add_theme_constant_override("h_separation",14)
		if icon_only:b.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(func():audio.play("tap","UI");callback.call());parent.add_child(b);_wrap_button(b);return b
func _hud_copy() -> Dictionary:
	return QuestGuide.describe(kernel,str(settings.get("locale","ru")),level_number,level_ids.size(),selected,catalog)

func _text_height(value: String,width: float,font_size: int,heading: bool=false) -> float:
	# Label shaping includes its own word-boundary and line-spacing rules.
	# Measure the same native control, rather than an approximate Font string box.
	var key: String=str(heading)+":"+str(font_size)+":"+str(width)+":"+value
	if _text_measure_cache.has(key):return _text_measure_cache[key]
	var probe=Label.new();probe.visible=false;probe.theme=theme
	probe.add_theme_font_override("font",ThemeKit.heading_font() if heading else get_theme_font("font"));probe.add_theme_font_size_override("font_size",font_size)
	probe.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;probe.size=Vector2(width,0);probe.text=value;add_child(probe)
	var height: float=ceilf(probe.get_minimum_size().y);probe.free()
	_text_measure_cache[key]=height
	return height
func _build_ui() -> void:
	var previous_caption: String=_caption_label.text if is_instance_valid(_caption_label) else ""
	var previous_remaining: float=_caption_remaining
	var previous_queue: Array=_caption_queue.duplicate()
	var reusable_stage: Control=stage if is_instance_valid(stage) else null
	if reusable_stage!=null and reusable_stage.get_parent()!=null:reusable_stage.get_parent().remove_child(reusable_stage)
	if is_instance_valid(ui):ui.queue_free()
	_close_overlay();ui=Control.new();ui.name="ResearchHUD";ui.mouse_filter=MOUSE_FILTER_IGNORE;add_child(ui)
	var screen: Vector2=get_viewport_rect().size
	ui.position=Vector2.ZERO;ui.size=screen;_layout_screen=screen
	var copy: Dictionary=_hud_copy()
	_layout_copy_key=_copy_key(copy)
	var text_scale: float=clampf(float(settings.accessibility.text_scale),1.0,1.4)
	var font_size: int=int(BODY_FONT_SIZE*text_scale)
	var margin: float=36
	var safe_left: float=margin;var safe_right: float=margin;var safe_top: float=28;var safe_bottom: float=24
	if DisplayServer.get_name()!="headless":
		var safe: Rect2i=DisplayServer.get_display_safe_area()
		var window: Vector2i=DisplayServer.window_get_size()
		if window.x>0 and window.y>0 and safe.size.x>0 and safe.size.y>0:
			var factor: Vector2=screen/Vector2(window)
			safe_left=maxf(margin,safe.position.x*factor.x+12);safe_right=maxf(margin,(window.x-safe.end.x)*factor.x+12)
			safe_top=maxf(safe_top,safe.position.y*factor.y+12);safe_bottom=maxf(safe_bottom,(window.y-safe.end.y)*factor.y+12)
	stage=reusable_stage if reusable_stage!=null else Stage.new();stage.name="ResearchStage";stage.kernel=kernel;stage.translator=tx;stage.selected=selected;stage.inspected=inspected
	stage.position=Vector2.ZERO;stage.size=screen;stage.reduced_motion=settings.accessibility.reduced_motion;stage.ui_text_scale=float(settings.accessibility.text_scale);stage.process_mode=Node.PROCESS_MODE_DISABLED if _app_paused else Node.PROCESS_MODE_INHERIT;ui.add_child(stage)
	if not stage.target_tapped.is_connected(_on_target):stage.target_tapped.connect(_on_target)
	# A short objective ticket is the entry to the complete journal; the world keeps the full canvas.
	var goal_width: float=minf(screen.x-540-safe_left-safe_right,1160)
	var goal_button: Button=_button(ui,"",Rect2(safe_left,safe_top,goal_width,144),_open_objective,false,BODY_FONT_SIZE)
	goal_button.name="ObjectiveTicket"
	_text(goal_button,"%02d" % level_number,Rect2(20,12,100,112),58,INK).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var headline: Dictionary=copy.get("goal_headline",{"label":copy.get("objective",""),"done":false})
	var headline_text: String=("✓  " if headline.get("done",false) else "")+str(headline.get("label",""))
	_text(goal_button,tx(_key("title"),"Новое открытие"),Rect2(144,10,goal_width-170,40),28,ThemeKit.GREEN)
	_goal_headline=_text(goal_button,headline_text,Rect2(144,48,goal_width-170,84),BODY_FONT_SIZE,INK);_goal_headline.name="CurrentGoal"
	_goal_headline.autowrap_mode=TextServer.AUTOWRAP_OFF;_goal_headline.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;_goal_headline.clip_text=true
	goal_button.tooltip_text=str(copy.get("objective",""))+"\n"+str(copy.get("body",""))
	var right: float=screen.x-safe_right
	_button(ui,"",Rect2(right-144,safe_top,144,144),_open_settings,false,BODY_FONT_SIZE,"settings").name="PauseSettings"
	_button(ui,"",Rect2(right-308,safe_top,144,144),_hint,false,BODY_FONT_SIZE,"hint").name="AskPlum"
	var undo_button: Button=_button(ui,"",Rect2(right-472,safe_top,144,144),func():_command("Undo"),false,BODY_FONT_SIZE,"undo")
	undo_button.name="UndoAction";undo_button.disabled=kernel._history.is_empty()
	var instruction_text: String=_short_instruction(copy)
	var instruction_width: float=minf(goal_width,1200)
	var instruction_h: float=maxf(96,_text_height(instruction_text,instruction_width-48,font_size)+28)
	var note: Panel=_box(ui,Rect2(safe_left,safe_top+164,instruction_width,instruction_h),Color("252647e8"),20)
	instruction=_text(note,instruction_text,Rect2(24,12,instruction_width-48,instruction_h-24),BODY_FONT_SIZE,CREAM);instruction.name="NextActionHint"
	# The active law is optional context, with all details available in the Atlas sheet.
	var law_text: String=_compact_law_text()
	var law_width: float=700 if text_scale>=1.4 else 610
	var law_height: float=maxf(88,_text_height(law_text,law_width-44,int(40*text_scale))+28)
	var law_badge: Panel=_box(ui,Rect2(screen.x-safe_right-law_width,safe_top+164,law_width,law_height),Color("fff2d8f2"),22)
	law_badge.name="ActiveLawBadge";law_badge.visible=not law_text.is_empty()
	law_label=_text(law_badge,law_text,Rect2(22,12,law_width-44,law_height-24),40,INK);law_label.name="CurrentLaw"
	witness_labels.clear();_upper_scroll=null;_audience_scroll=null;_inventory_scroll=null
	var bottom: float=screen.y-safe_bottom-144
	var objects_text: String=QuestGuide._t(str(settings.locale),"Предметы","Objects")
	var plan_text: String=tx("ui.plan","План")
	var objects_width: float=_button_content_width(objects_text,font_size,"props",320)
	var plan_width: float=_button_content_width(plan_text,font_size,"route",240)
	_button(ui,objects_text,Rect2(safe_left,bottom,objects_width,144),_open_inventory,false,BODY_FONT_SIZE,"props").name="OpenObjects"
	_button(ui,plan_text,Rect2(safe_left+objects_width+20,bottom,plan_width,144),_plan_menu,false,BODY_FONT_SIZE,"route").name="OpenPlan"
	var primary_width: float=700 if text_scale>=1.4 else 620
	var primary_text: String=str(copy.get("primary",""))
	var primary_font: int=font_size
	var primary_lines: String=_wrap_words(primary_text,primary_width-72,primary_font)
	var primary_h: float=maxf(144,(primary_lines.count("\n")+1)*get_theme_font("font").get_height(primary_font)+28)
	primary=_button(ui,primary_text,Rect2(screen.x-safe_right-primary_width,screen.y-safe_bottom-primary_h,primary_width,primary_h),_primary,true,BODY_FONT_SIZE)
	primary.name="PrimaryAction";primary.disabled=bool(copy.get("primary_disabled",false))
	if not selected.is_empty():_build_context_button(screen,copy,safe_left,safe_right,safe_top)
	_caption_panel=_box(ui,Rect2(screen.x*.25,screen.y-336,screen.x*.5,124),Color("fff2d8f2"),24)
	_caption_panel.name="CharacterCaption";_caption_panel.visible=previous_remaining>0 and settings.accessibility.subtitles
	_caption_label=_text(_caption_panel,previous_caption,Rect2(24,12,_caption_panel.size.x-48,100),BODY_FONT_SIZE)
	_caption_remaining=previous_remaining;_caption_queue=previous_queue
	if not previous_caption.is_empty():_fit_caption()
	_flash=ColorRect.new();_flash.size=screen;_flash.color=Color(1,.94,.68,0);_flash.mouse_filter=MOUSE_FILTER_IGNORE;ui.add_child(_flash)

func _button_content_width(value: String,font_size: int,icon: String,minimum: float) -> float:
	var text_width: float=0
	for line in value.split("\n"):
		text_width=maxf(text_width,get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)
	var icon_width: float=62 if not icon.is_empty() and ResourceLoader.exists("res://assets/art/ui/"+icon+".svg") else 0
	var padding: float=ThemeKit.button_style("normal").get_minimum_size().x
	return maxf(minimum,ceilf(text_width+icon_width+padding+12))

func _compact_law_text() -> String:
	var names: Array[String]=[]
	for law in kernel.state.get("active_laws",[]):names.append(_law_name(str(law)))
	return "\n".join(names)

func _copy_key(copy: Dictionary) -> String:
	return str(copy.get("stage_title",""))+"|"+str(copy.get("law",""))+"|"+str(copy.get("body",""))+"|"+str(copy.get("short_body",""))+"|"+str(copy.get("primary",""))+"|"+str(copy.get("primary_intent",""))+"|"+selected+"|"+JSON.stringify(copy.get("goals",[]))

func _short_instruction(copy: Dictionary) -> String:
	if not selected.is_empty():
		if selected.begins_with("w:"):
			var wd: Dictionary=kernel._find(kernel.definition.witnesses,selected.trim_prefix("w:"))
			return _character_name(str(wd.get("character_id","")))+" · "+str(copy.get("witness_status",{}).get(selected.trim_prefix("w:"),""))
		return _name(selected)+QuestGuide._t(str(settings.locale)," · выберите место или действия."," · choose a place or actions.")
	if not str(copy.get("short_body","")).is_empty():return str(copy.short_body)
	var tips: Dictionary={
		"PLAN_SHOW":QuestGuide._t(str(settings.locale),"Коснитесь предмета, чтобы подготовить опыт.","Tap an object to prepare the experiment."),
		"PERFORMANCE":QuestGuide._t(str(settings.locale),"Результат должен быть виден, механизм — скрыт.","Keep the result visible and its mechanism hidden."),
		"REHEARSAL":QuestGuide._t(str(settings.locale),"Проверьте опыт: результат виден, механизм скрыт.","Test the experiment: show the result, hide its mechanism."),
		"PROOF_ACCEPTED":QuestGuide._t(str(settings.locale),"Демонстрация удалась. Теперь измените закон.","The demonstration worked. Now change the law."),
		"LAW_SELECTION":QuestGuide._t(str(settings.locale),"Атлас хранит два закона. Выберите замену.","The Atlas holds two laws. Choose one to replace."),
		"PLAN_RESOLUTION":QuestGuide._t(str(settings.locale),"Новый закон действует. Примените его к задаче.","The new law is active. Use it to solve the task."),
		"RUN_RESOLUTION":QuestGuide._t(str(settings.locale),"План выполняется. Откат вернёт начало проверки.","The plan is running. Undo restores its starting point."),
		"RECOVERABLE_FAILURE":QuestGuide._t(str(settings.locale),"План нужно поправить. Откат бесплатный.","Adjust the plan. Undo is always free."),
		"SUCCESS":QuestGuide._t(str(settings.locale),"Задача решена. Впереди следующее открытие.","Task complete. Your next discovery awaits.")}
	return str(tips.get(str(kernel.state.phase),str(copy.get("body",""))))

func _build_context_button(screen: Vector2,copy: Dictionary,left: float,right: float,top: float) -> void:
	var is_witness: bool=selected.begins_with("w:")
	var point: Vector2=Vector2(screen.x*.55,screen.y*.61)
	if is_witness and stage.has_method("witness_display_position"):point=stage.witness_display_position(selected.trim_prefix("w:"))
	elif not is_witness and stage.has_method("entity_display_position"):point=stage.entity_display_position(selected)
	var width: float=400
	point.x=clampf(point.x-width/2,left,screen.x-right-width)
	point.y=clampf(point.y+72,top+340,screen.y-340)
	var selected_id: String=selected
	var callback: Callable=func():
		if is_witness:_witness_menu(selected_id.trim_prefix("w:"))
		else:_object_menu(selected_id)
	var label: String=QuestGuide._t(str(settings.locale),"Проверить обзор","Check view") if is_witness else QuestGuide._t(str(settings.locale),"Действия","Actions")
	var context: Button=_button(ui,label,Rect2(point,Vector2(width,144)),callback,false,BODY_FONT_SIZE,"eye" if is_witness else "props")
	context.name="ObjectContext";context.tooltip_text=str(copy.get("body",""))
	# Wrapped localized text can raise the native minimum after _button assigns it.
	# Clamp against the real footer and real resulting height, not the 144px target.
	context.size=context.size.max(context.get_combined_minimum_size())
	var footer_top: float=screen.y
	for action_name in ["OpenObjects","OpenPlan","PrimaryAction"]:
		var action: Control=ui.find_child(action_name,true,false)
		if is_instance_valid(action):footer_top=minf(footer_top,action.position.y)
	context.position.x=clampf(context.position.x,left,screen.x-right-context.size.x)
	context.position.y=minf(context.position.y,footer_top-24-context.size.y)

func _open_objective() -> void:
	var copy: Dictionary=_hud_copy()
	var body: String=str(copy.get("objective",""))+"\n\n"+str(copy.get("body",""))+"\n\n"
	for goal in copy.get("goals",[]):body+=("✓  " if goal.get("done",false) else "○  ")+str(goal.get("label",""))+"\n"
	body+="\n"+str(copy.get("law",""))
	_modal(tx(_key("title"),"Задача опыта"),body,tx("ui.back_game","Вернуться в игру"),func():pass)

func _open_inventory() -> void:
	_sheet(QuestGuide._t(str(settings.locale),"Предметы опыта","Experiment objects"))
	var scroll: ScrollContainer=_sheet_scroll();_inventory_scroll=scroll
	var rows=VBoxContainer.new();rows.mouse_filter=MOUSE_FILTER_PASS;rows.custom_minimum_size=Vector2(_sheet_inner.size.x-24,0);rows.add_theme_constant_override("separation",16);scroll.add_child(rows)
	for entity in kernel.definition.entities:
		var props: Dictionary=entity.properties
		if not entity.movable and props.get("attachment_kind","").is_empty() and not props.get("removable",false) and not props.get("foldable",false) and not props.has("emitter_class") and entity.apparent_class not in ["PERSON","CARGO","ANIMAL"]:continue
		var id: String=entity.id
		if kernel.state.entities[id].removed:continue
		var button: Button=_button(rows,_name(id),Rect2(0,0,_sheet_inner.size.x-24,144),func():_close_overlay();_select(id),selected==id,BODY_FONT_SIZE)
		button.name="Object_"+id;button.set_meta("entity_id",id);button.custom_minimum_size=Vector2(_sheet_inner.size.x-24,144)
		if stage.has_method("asset_texture"):
			button.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS;button.icon=stage.asset_texture(id);button.expand_icon=true;button.add_theme_constant_override("icon_max_width",110)
			for color_name in ["icon_normal_color","icon_hover_color","icon_pressed_color","icon_focus_color"]:button.add_theme_color_override(color_name,Color.WHITE)
		_wrap_button(button)
	_sheet_action(tx("ui.back_game","Вернуться в игру"),_dismiss_overlay)

func _witness_menu(id: String) -> void:
	var wd: Dictionary=kernel._find(kernel.definition.witnesses,id)
	var choices: Array=[]
	var fixed_path: bool=wd.get("views",[]).size()>1
	var can_move: bool=kernel.state.phase in Kernel.PLAN_PHASES+["PROOF_ACCEPTED"] and not fixed_path
	if can_move:
		for slot in kernel.definition.slots:
			if "witness" not in slot.get("allowed_entity_types",[]):continue
			choices.append({"label":_slot_name(slot,choices.size()),"action":func():_command("SetWitnessSlot",{"witness_id":id,"slot_id":slot.id})})
	if choices.is_empty():
		var explanation: String=QuestGuide._t(str(settings.locale),"Обзор показан линиями на сцене. Вернитесь к опыту, чтобы изменить предметы.","The scene shows the viewing rays. Return to the experiment to adjust its objects.")
		if fixed_path:explanation=QuestGuide._t(str(settings.locale),"Этот участник сам меняет точку наблюдения и проверяет опыт с нескольких сторон. Его маршрут проверки задан; обзор показан на сцене.","This observer checks the experiment from several viewpoints along a fixed inspection route. Their current view is shown in the scene.")
		elif not can_move:explanation=QuestGuide._t(str(settings.locale),"Сейчас идёт проверка опыта. Обзор показан на сцене; менять позиции можно после возвращения к подготовке.","The experiment is being checked. Its viewing rays remain visible; return to preparation to change viewpoints.")
		_modal(_character_name(str(wd.get("character_id",""))),str(_hud_copy().get("witness_status",{}).get(id,""))+"\n\n"+explanation,tx("ui.back_game","Вернуться в игру"),func():pass)
	else:_choices(_character_name(str(wd.get("character_id",""))),choices)

func _process(delta: float) -> void:
	if is_instance_valid(ui) and not kernel.state.is_empty() and get_viewport_rect().size!=_layout_screen:
		var was_title: bool=_front_menu
		_build_ui();_update_ui()
		if was_title:_show_title()
	_frame+=1
	if _frame==10:
		if _capture_scroll=="settings_end" and is_instance_valid(overlay):
			for child in overlay.get_children():
				if child is ScrollContainer:child.scroll_vertical=int(child.get_v_scroll_bar().max_value)
		if _capture_scroll.begins_with("audience") and is_instance_valid(_audience_scroll):
			if _upper_scroll.is_ancestor_of(_audience_scroll):_upper_scroll.ensure_control_visible(_audience_scroll)
			if _capture_scroll=="audience_end":_audience_scroll.scroll_horizontal=int(_audience_scroll.get_h_scroll_bar().max_value)
		if _capture_scroll.begins_with("inventory") and is_instance_valid(_inventory_scroll):
			if _upper_scroll.is_ancestor_of(_inventory_scroll):_upper_scroll.ensure_control_visible(_inventory_scroll)
			if _capture_scroll=="inventory_end":_inventory_scroll.scroll_horizontal=int(_inventory_scroll.get_h_scroll_bar().max_value)
	if not _screenshot.is_empty() and _frame==12:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_screenshot)
		# Allow queued native mixer starts to settle before automated capture shutdown.
		await get_tree().create_timer(.12).timeout
		_quit_gracefully();return
	if kernel.state.is_empty() or _app_paused:return
	_advance_caption(delta)
	if _transformation>0:
		_transformation=maxf(0,_transformation-delta);_flash.color.a=sin(_transformation/1.2*PI)*.5 if not settings.accessibility.reduced_motion else 0
	if is_instance_valid(overlay) or not _capture_stage.is_empty():return
	if kernel.state.phase in Kernel.ACTIVE_PHASES:
		_accumulator+=minf(delta,.25)
		while _accumulator>=.1:
			_accumulator-=.1;_events(kernel.advance_ticks(1));_update_ui()
	else:_accumulator=0
	if _last_phase!=kernel.state.phase:
		_last_phase=kernel.state.phase;_save_progress();_update_ui()
		if kernel.state.phase=="SUCCESS":_victory()
func _command(kind: String,payload: Dictionary={}) -> bool:
	var response: Dictionary=kernel.dispatch({"type":kind,"payload":payload,"precondition_hash":kernel.state_hash()})
	if not response.accepted:_toast(_reason(response.reason_code));return false
	_events(response.events);selected="";stage.selected="";_update_ui();_save_progress()
	if kernel.state.phase=="LAW_SELECTION":_replacement_menu()
	return true
func _events(events: Array) -> void:
	for event in events:
		var payload: Dictionary=event.get("payload",{})
		match event.type:
			"prop_placed":audio.play_event(_prop_sound(payload.get("entity_id","")));_haptic(22)
			"prop_removed":audio.play_event("SFX_PROP_FLOAT_REMOVE" if payload.get("entity_id","")=="float" else "SFX_PROP_ROPE_RELEASE")
			"prop_interacted":
				var id: String=payload.get("entity_id","")
				var action: String=payload.get("action","")
				var type_id: String=kernel._entities.get(id,{}).get("type_id","")
				audio.play_event("SFX_PROP_CLAMP" if type_id=="clamp" else ("SFX_PROP_ROPE_RELEASE" if action=="detach" else ("SFX_PROP_ROPE_TENSION" if action=="attach" else ("SFX_PROP_SCREEN_OPEN" if action=="open" else "SFX_PROP_SCREEN_CLOSE"))))
			"prop_blown":audio.play_event("SFX_ACTOR_CLOTH")
			"water_phase_changed":audio.play_event("SFX_LAW_WATER_FREEZE" if payload.get("phase","")=="frozen" else "SFX_LAW_WATER_THAW")
			"show_started":stage.play_actor("felix","show_begin");stage.play_actor("plum","point");audio.set_phase(kernel.state.phase);_voice("CH01","curious")
			"witness_convinced":
				audio.play_event("SFX_WITNESS_ACCEPT")
				var witness: Dictionary=kernel._find(kernel.definition.witnesses,payload.get("witness_id",""))
				var character: String=witness.get("character_id","")
				if character.begins_with("CH"):_voice(character,"accept")
				if character=="CH08":audio.play_event("SFX_GUGO_RIBBON")
			"method_exposed":
				stage.play_actor("felix","reveal_react");stage.play_actor("plum","reveal_react");stage.play_actor("caramelka","reveal_react")
				audio.play_event("SFX_WITNESS_REVEAL");audio.play("stinger_reveal","Music")
				var witness: Dictionary=kernel._find(kernel.definition.witnesses,payload.get("witness_id",""))
				var character: String=witness.get("character_id","")
				if character.begins_with("CH"):_voice(character,"doubt","exposed")
			"proof_accepted":stage.play_actor("felix","accept");stage.play_actor("plum","accept");stage.play_actor("caramelka","accept");audio.play("stinger_proof","Music")
			"law_activated":
				stage.play_actor("felix","stamp");stage.play_actor("plum","reveal_react")
				_haptic(65)
				audio.play_event("SFX_LAW_STAMP");audio.duck_music(1.2,-9);audio.play("stinger_law","Music");_voice("CH02","surprise");_transformation=1.2
				audio.play_event({"M01":"SFX_LAW_STONE_BUOYANCY","M02":"SFX_LAW_FROST","M03":"SFX_LAW_PAPER_STRONG"}.get(payload.get("myth_id",""),"SFX_LAW_WAVE"))
			"law_revoked":audio.play_event("SFX_LAW_WAVE")
			"route_completed":audio.play_event("SFX_GOAL_COMPLETE")
			"undone":audio.play_event("SFX_UI_UNDO")
			"level_success":stage.play_actor("felix","bow");stage.play_actor("plum","cheer");stage.play_actor("caramelka","celebrate");audio.play_event("SFX_CROWD_CLAP");_voice("CH01","joy");audio.play("stinger_final" if kernel.state.get("level_id","")=="L30" else "success","Music")
			"recoverable_failure":audio.play_event("SFX_FAIL_RECOVERABLE")
			"rehearsal_passed":_toast(tx("ui.rehearsal_passed","Репетиция удалась. Теперь — настоящий показ!"))
			"rehearsal_failed":_toast(tx("ui.rehearsal_failed","Репетиция закончилась. Вернулись к исходному плану."))
		stage.react_to_event(event.type,payload)
func _prop_sound(id: String) -> String:
	if not kernel._entities.has(id):return "SFX_UI_DROP_VALID"
	var d: Dictionary=kernel._entities[id]
	if d.material=="STONE":return "SFX_PROP_STONE_WATER" if kernel._position_over_water(kernel.state.entities[id].position) else "SFX_PROP_STONE_DRY"
	if d.material=="PAPER":return "SFX_PROP_PAPER"
	return {"screen":"SFX_PROP_SCREEN_OPEN","clamp":"SFX_PROP_CLAMP","hidden_frame":"SFX_PROP_FRAME","control_weight":"SFX_PROP_WEIGHT","cold_pack":"SFX_PROP_CRYO","oven":"SFX_PROP_FIRE_START","bowl":"SFX_PROP_KETTLE","boat":"SFX_BOAT_DOCK","tow_rope":"SFX_PROP_ROPE_TENSION","mooring_rope":"SFX_PROP_ROPE_TENSION"}.get(d.type_id,"SFX_UI_DROP_VALID")
func _reason(code: String) -> String:
	return tx("reason."+code,{"WRONG_PHASE":"Сначала закончи показ или вернись к плану.","NO_UNDO":"Мы ещё ничего не изменили.","INCOMPATIBLE_SLOT":"Этому предмету нужно другое место.","SLOT_OCCUPIED":"Место уже занято.","OUT_OF_REACH":"Отсюда не дотянуться. Сначала пройди к следующему берегу.","CARRIER_NOT_AT_START":"Перевозчик должен вернуться к началу пути.","CARRIER_ALREADY_ASSIGNED":"Этот перевозчик уже занят другим путём.","PAYLOAD_NOT_LOADED":"Сначала погрузи все части доставки рядом с ящиком.","HOIST_REQUIRED":"Для тяжёлого груза нужна таль.","HOIST_CAPACITY":"Таль не поднимет этот вес.","HOIST_CANNOT_REACH":"Таль не достаёт до этого места.","OVER_CAPACITY":"Общий груз тяжелее опоры. Раздели перевозку.","MISSING_FLOATING_BRIDGE":"Опора отсутствует или перестала работать.","NOT_ENOUGH_WITNESSES":"Убедились не все зрители. Проверь их обзор.","ROUTE_IN_PROGRESS":"Путь ещё не завершён. Можно бесплатно откатить весь запуск.","GOALS_INCOMPLETE":"За это время план не выполнил все цели.","FIXED_INSPECTION_PATH":"Инспектор сам выбирает ракурсы для проверки."}.get(code,tx("reason.GENERIC","Действие сейчас недоступно. Проверь план или сделай откат.")))
func _select(id: String) -> void:
	if kernel.state.entities[id].removed:_toast(tx("ui.prop_removed","Этот предмет уже убран. Бесплатный откат вернёт его."));return
	selected="" if selected==id else id;stage.selected=selected;_update_ui()
func _inspect(id: String) -> void:
	inspected="" if inspected==id else id;stage.inspected=inspected;selected="w:"+id if not inspected.is_empty() else "";stage.selected=selected;_update_ui()
func _on_target(kind: String,id: String) -> void:
	if kind=="slot":
		if selected.begins_with("w:"):_command("SetWitnessSlot",{"witness_id":selected.trim_prefix("w:"),"slot_id":id})
		elif not selected.is_empty():
			var payload: Dictionary={"entity_id":selected,"slot_id":id}
			var props: Dictionary=kernel._entities[selected].properties
			if props.get("move_mode","")=="hoist":payload.move_mode="hoist";payload.hoist_entity_id=props.get("hoist_entity_id","")
			_command("PlaceProp",payload)
	elif kind=="entity":_select(id)
	elif kind=="witness":_inspect(id)
func _update_ui() -> void:
	if not is_instance_valid(primary):return
	var copy: Dictionary=_hud_copy()
	if _layout_copy_key!=_copy_key(copy):_build_ui()
	var undo_button: Button=ui.find_child("UndoAction",true,false)
	if is_instance_valid(undo_button):undo_button.disabled=kernel._history.is_empty()
	law_label.text=_compact_law_text()
	primary.text=str(copy.get("primary",""));primary.disabled=bool(copy.get("primary_disabled",false))
	instruction.text=_short_instruction(copy)
	audio.set_phase(kernel.state.phase)
	_wrap_button(primary)

func _primary() -> void:
	var state: Dictionary=kernel.state
	var copy: Dictionary=_hud_copy()
	match str(copy.get("primary_intent","")):
		"remove_l01_float":
			_command("Interact",{"entity_id":"float","action":"remove"});return
		"cross_l01_marfa":
			if not state.get("routes",{}).has("marfa"):
				if not _command("AssignRoute",{"actor_id":"marfa","route_id":"cross"}):return
			_command("RunResolution");return
		"begin_required_experiment":
			var law: String=str(copy.get("required_experiment",""))
			if not law.is_empty() and str(state.get("candidate_law",""))!=law:
				if not _command("SetLawCandidate",{"myth_id":law}):return
			_command("BeginPerformance");return
	match state.phase:
		"PLAN_SHOW":_command("BeginPerformance")
		"PERFORMANCE":_command("StopPerformance")
		"REHEARSAL":_command("StopRehearsal")
		"PROOF_ACCEPTED":_command("ActivateLaw",{"myth_id":state.candidate_law,"replace_law_id":null})
		"LAW_SELECTION":_replacement_menu()
		"PLAN_RESOLUTION":_command("RunResolution")
		"RUN_RESOLUTION":_command("StopResolution")
		"RECOVERABLE_FAILURE":_command("Undo")
		"SUCCESS":_next_level()

func _save_progress() -> void:
	if kernel.state.is_empty():return
	progress.current_level=level_number;progress.checkpoint=kernel.stable_checkpoint()
	if kernel.state.phase=="SUCCESS":progress.completed[kernel.state.level_id]={"stars":1};progress.unlocked=maxi(int(progress.get("unlocked",1)),mini(level_number+1,level_ids.size()))
	saver.write_slot("progress",progress)
func _close_overlay() -> void:
	if is_instance_valid(overlay):overlay.queue_free()
	overlay=null
func _sheet(title: String) -> Control:
	_close_overlay();overlay=Control.new();overlay.size=get_viewport_rect().size;overlay.position=Vector2.ZERO;add_child(overlay)
	var shade=ColorRect.new();shade.size=overlay.size;shade.color=Color(.04,.13,.19,.66);overlay.add_child(shade)
	var panel_size: Vector2=Vector2(minf(1440,overlay.size.x-96),overlay.size.y-80)
	_sheet_rect=Rect2((overlay.size-panel_size)/2,panel_size)
	_box(overlay,_sheet_rect,CREAM,36)
	_sheet_inner=Rect2(_sheet_rect.position+Vector2(48,36),_sheet_rect.size-Vector2(96,72))
	var font_size: int=int(60*float(settings.accessibility.text_scale))
	var title_height: float=maxf(96,_text_height(title,_sheet_inner.size.x,font_size,true)+16)
	_text(overlay,title,Rect2(_sheet_inner.position.x,_sheet_inner.position.y,_sheet_inner.size.x,title_height),60,PURPLE)
	_sheet_content_top=_sheet_inner.position.y+title_height+20
	return overlay
func _sheet_scroll(bottom_reserve: float=168) -> ScrollContainer:
	var scroll=ScrollContainer.new();scroll.mouse_filter=MOUSE_FILTER_PASS;scroll.position=Vector2(_sheet_inner.position.x,_sheet_content_top)
	scroll.size=Vector2(_sheet_inner.size.x,maxf(144,_sheet_inner.end.y-bottom_reserve-_sheet_content_top));scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;overlay.add_child(scroll);return scroll
func _sheet_action(value: String,callback: Callable) -> Button:
	return _button(overlay,value,Rect2(_sheet_inner.position.x,_sheet_inner.end.y-144,_sheet_inner.size.x,144),callback,true,BODY_FONT_SIZE)

func _modal(title: String,body: String,confirm: String,callback: Callable) -> void:
	_sheet(title)
	var scroll: ScrollContainer=_sheet_scroll()
	var width: float=_sheet_inner.size.x-24
	var label: Label=_text(scroll,body,Rect2(0,0,width,0),BODY_FONT_SIZE);label.custom_minimum_size=Vector2(width,0)
	_sheet_action(confirm,func():_close_overlay();callback.call())

func _choices(title: String,choices: Array) -> void:
	_sheet(title)
	var scroll: ScrollContainer=_sheet_scroll()
	var width: float=_sheet_inner.size.x-24
	var rows=VBoxContainer.new();rows.mouse_filter=MOUSE_FILTER_PASS;rows.custom_minimum_size=Vector2(width,0);rows.add_theme_constant_override("separation",16);scroll.add_child(rows)
	for choice in choices:
		var b: Button=_button(rows,choice.label,Rect2(0,0,width,144),func():_close_overlay();choice.action.call(),choice.get("primary",false),BODY_FONT_SIZE)
		b.custom_minimum_size=Vector2(width,maxf(144,(b.text.count("\n")+1)*b.get_theme_font_size("font_size")*1.25+32))
		b.disabled=bool(choice.get("disabled",false))
		b.tooltip_text=str(choice.get("help",""))
	_sheet_action(tx("ui.close","Вернуться"),_dismiss_overlay)

func _toast(message: String) -> void:_modal(tx("ui.plum_help","Плюм подсказывает"),message,tx("ui.understood","Понятно"),func():pass)
func _briefing() -> void:
	var body: String=QuestGuide.briefing(kernel,str(settings.get("locale","ru")),level_number,level_ids.size(),catalog)
	_modal(tx(_key("title"),"Новое чудо"),body,tx("ui.begin","За работу"),func():audio.play("voice_felix","Voice"))

func _hint() -> void:
	_hint_index=mini(_hint_index+1,3);audio.play("hint","UI")
	_modal(txf("ui.hint_stage","Подсказка {number} из 3",{"number":_hint_index}),tx(_key("hint%d" % _hint_index),"Проверь обзор зрителей и состояние опор."),tx("ui.try","Попробую"),func():pass)
func _object_menu(id: String) -> void:
	var d: Dictionary=kernel._entities[id];var props: Dictionary=d.properties;var e: Dictionary=kernel.state.entities[id];var choices: Array=[]
	if kernel.state.phase not in Kernel.PLAN_PHASES and kernel.state.phase!="PROOF_ACCEPTED":
		_modal(_name(id),QuestGuide._t(str(settings.locale),"Сейчас идёт проверка опыта. Вернитесь к подготовке, чтобы изменить предметы; наблюдать сцену можно в любой момент.","The experiment is being checked. Return to preparation to adjust objects; you can inspect the scene at any time."),tx("ui.back_game","Вернуться в игру"),func():pass);return
	if d.movable:choices.append({"label":tx("ui.place_prop","Выбрать место…"),"action":func():_slot_menu(id)})
	if props.get("foldable",false):
		var folded: bool=bool(e.get("folded",false))
		choices.append({"label":QuestGuide._t(str(settings.locale),"Развернуть ширму" if folded else "Сложить ширму","Unfold screen" if folded else "Fold screen"),"action":func():_command("Interact",{"entity_id":id,"action":"unfold" if folded else "fold"}),"primary":true})
	if d.movable or props.get("removable",false):
		var required_law: String=str(props.get("remove_requires_law",""))
		var removal_locked: bool=not required_law.is_empty() and required_law not in kernel.state.active_laws
		var remove_label: String=tx("ui.remove_prop","Убрать реквизит")
		if removal_locked:remove_label+=QuestGuide._t(str(settings.locale)," · после изменения закона"," · after changing the law")
		choices.append({"label":remove_label,"action":func():_command("Interact",{"entity_id":id,"action":"remove"}),"disabled":removal_locked})
	if props.has("initial_open") or props.has("initial_closed"):
		for action in ["open","close"]:
			choices.append({"label":tx("ui."+action,"Открыть" if action=="open" else "Закрыть"),"action":func():_command("Interact",{"entity_id":id,"action":action})})
	if not props.get("attachment_kind","").is_empty():
		choices.append({"label":tx("ui.attach","Прикрепить к предмету…"),"action":func():_attachment_menu(id)})
		if not e.get("attachment_target","").is_empty():choices.append({"label":tx("ui.detach","Отсоединить"),"action":func():_command("Interact",{"entity_id":id,"action":"detach"})})
	if props.get("switchable",false):
		choices.append({"label":tx("ui.disable","Выключить источник") if e.get("enabled",true) else tx("ui.enable","Включить источник"),"action":func():_command("Interact",{"entity_id":id,"action":"disable" if e.get("enabled",true) else "enable"})})
	if kernel.state.phase=="PLAN_RESOLUTION" and (d.apparent_class in ["CARGO","PERSON","ANIMAL"] or props.has("locomotion")):choices.append({"label":tx("ui.assign_route","Назначить маршрут…"),"action":func():_route_menu(id)})
	if choices.is_empty():
		var description: String=tx("entity."+id+".description",tx("prop."+str(d.type_id)+".description",QuestGuide._t(str(settings.locale),"Этот предмет — часть опыта. Его положение закреплено; учитывайте его свойства при выборе действий.","This object is part of the experiment. Its position is fixed; account for its properties when choosing your actions.")))
		_modal(_name(id),description,tx("ui.back_game","Вернуться в игру"),func():pass)
	else:_choices(_name(id),choices)
func _attachment_menu(tool_id: String) -> void:
	var choices: Array=[]
	for id in kernel.state.entities:
		if id==tool_id or kernel.state.entities[id].removed:continue
		var props: Dictionary=kernel._entities[tool_id].properties
		if props.has("attachable_target_types") and kernel._entities[id].type_id not in props.attachable_target_types:continue
		choices.append({"label":_name(id),"action":func():_command("Interact",{"entity_id":tool_id,"action":"attach","target_entity_id":id})})
	_choices(tx("ui.attachment_target","К чему прикрепить?"),choices)
func _actor_menu() -> void:
	var choices: Array=[]
	for d in kernel.definition.entities:
		if kernel.state.entities[d.id].removed:continue
		if d.apparent_class in ["PERSON","CARGO","ANIMAL"] or d.properties.has("locomotion"):choices.append({"label":_name(d.id),"action":func():_route_menu(d.id)})
	_choices(tx("ui.choose_actor","Кто отправится в путь?"),choices)
func _route_menu(actor_id: String) -> void:
	var choices: Array=[]
	for route in kernel.definition.navigation.routes:choices.append({"label":_route_name(route.id),"action":func():_command("AssignRoute",{"actor_id":actor_id,"route_id":route.id})})
	_choices(_name(actor_id)+" · "+tx("ui.route","Маршрут"),choices)
func _law_menu() -> void:
	var choices: Array=[]
	for proof in kernel.definition.proofs:
		if proof.myth_id not in kernel.state.active_laws:
			choices.append({"label":tx("ui.prepare_show","Поставить фокус")+" · "+_law_name(proof.myth_id),"action":func():_command("SetLawCandidate",{"myth_id":proof.myth_id})})
	for law in kernel.state.active_laws:choices.append({"label":tx("ui.revoke_law","Отменить закон")+" · "+_law_name(law),"action":func():_confirm_revoke(law)})
	_choices(tx("ui.laws","Законы мира"),choices)
func _confirm_revoke(law: String) -> void:
	_modal(tx("ui.revoke_law","Отменить закон"),_law_name(law)+"\n\n"+tx("ui.revoke_help","Свойства опор изменятся. Уже доставленный груз останется на месте. Бесплатный откат доступен."),tx("ui.revoke_confirm","Отменить этот закон"),func():_command("RevokeLaw",{"myth_id":law}))
func _replacement_menu() -> void:
	var choices: Array=[]
	for law in kernel.state.active_laws:choices.append({"label":tx("ui.replace","Заменить")+" · "+_law_name(law),"action":func():_command("ActivateLaw",{"myth_id":kernel.state.candidate_law,"replace_law_id":law})})
	choices.append({"label":tx("ui.cancel","Отмена"),"action":func():_command("CancelLawSelection")})
	_choices(tx("ui.two_laws","Можно сохранить два закона"),choices)
func _plan_menu() -> void:
	var choices: Array=[]
	var phase: String=kernel.state.phase
	if phase in Kernel.PLAN_PHASES:
		if phase=="PLAN_RESOLUTION":choices.append({"label":QuestGuide._t(str(settings.locale),"Маршруты","Routes"),"action":_actor_menu})
		choices.append({"label":tx("ui.laws","Законы и следующий фокус"),"action":_law_menu})
		if not kernel.state.get("candidate_law","").is_empty() and kernel.state.candidate_law not in kernel.state.active_laws:
			choices.append({"label":tx("ui.perform","Показать фокус")+" · "+_law_name(kernel.state.candidate_law),"action":func():_command("BeginPerformance"),"primary":true})
			choices.append({"label":tx("ui.rehearsal","Репетиция"),"action":func():_command("BeginRehearsal")})
		if phase=="PLAN_RESOLUTION":choices.append({"label":tx("ui.world_run","Дать миру действовать"),"action":func():_command("RunResolution")})
	elif phase=="REHEARSAL":choices.append({"label":tx("ui.stop_rehearsal","Остановить репетицию"),"action":func():_command("StopRehearsal")})
	elif phase=="RUN_RESOLUTION":
		var pending_routes: bool=false
		for task in kernel.state.get("routes",{}).values():pending_routes=pending_routes or not bool(task.get("completed",false))
		if pending_routes:choices.append({"label":tx("ui.undo_short","Откат"),"action":func():_command("Undo"),"disabled":kernel._history.is_empty()})
		else:choices.append({"label":tx("ui.stop_resolution","Вернуться к плану"),"action":func():_command("StopResolution")})
	choices.append({"label":tx("ui.album","Альбом уровней"),"action":_open_levels})
	_choices(tx("ui.plan","План"),choices)
func _victory() -> void:
	_save_progress()
	var next_title: String=tx("level."+level_ids[level_number]+".title","") if level_number<level_ids.size() else ""
	var copy: Dictionary=QuestGuide.victory(kernel,str(settings.get("locale","ru")),level_number,level_ids.size(),catalog,next_title)
	_modal(copy.title,copy.body,copy.primary,_next_level)

func _next_level() -> void:
	_front_menu=false
	_close_overlay()
	if level_number<level_ids.size():start_level(level_number+1)
	else:_show_credits()

func _open_levels() -> void:
	audio.play_music("music_album")
	_sheet(tx("ui.album","Альбом невозможного"))
	var scroll: ScrollContainer=_sheet_scroll()
	var width: float=_sheet_inner.size.x-24
	var rows=VBoxContainer.new();rows.name="ChapterJourney";rows.mouse_filter=MOUSE_FILTER_PASS;rows.custom_minimum_size=Vector2(width,0);rows.add_theme_constant_override("separation",20);scroll.add_child(rows)
	var chapter_names: Array=[QuestGuide._t(str(settings.locale),"01  Солнечный квартал","01  The Sunlit District"),QuestGuide._t(str(settings.locale),"02  Праздничная кухня","02  The Festival Kitchen"),QuestGuide._t(str(settings.locale),"03  Бумажная мастерская","03  The Paper Workshop")]
	for i in range(level_ids.size()):
		if i%10==0:
			var chapter: Label=_text(rows,chapter_names[i/10],Rect2(0,0,width,112),52,ThemeKit.GREEN);chapter.custom_minimum_size=Vector2(width,112)
		var n: int=i+1
		var done: bool=progress.completed.has(level_ids[i])
		var locked: bool=n>int(progress.get("unlocked",1)) or _invalid_levels.has(level_ids[i])
		var number: String=("✓  " if done else "%02d  " % n)
		var label: String=number+tx("level."+level_ids[i]+".title",QuestGuide._t(str(settings.locale),"Опыт %d","Experiment %d") % n)
		if locked:label+="  ·  "+QuestGuide._t(str(settings.locale),"После предыдущего опыта","Complete the previous experiment")
		var button: Button=_button(rows,label,Rect2(0,0,width,144),func():_front_menu=false;_close_overlay();start_level(n),n==level_number,BODY_FONT_SIZE)
		button.name="Level_"+level_ids[i];button.set_meta("level_number",n);button.custom_minimum_size=Vector2(width,maxf(144,(button.text.count("\n")+1)*button.get_theme_font_size("font_size")*1.25+32));button.disabled=locked
	_sheet_action(tx("ui.back_game","Вернуться в игру"),_dismiss_overlay)

func _toggle(parent: Control,label: String,rect: Rect2,value: bool,callback: Callable) -> CheckButton:
	var check=CheckButton.new();check.mouse_filter=MOUSE_FILTER_PASS;check.position=rect.position;check.size=rect.size;check.button_pressed=value
	var font_size: int=int(BODY_FONT_SIZE*float(settings.accessibility.text_scale))
	check.add_theme_font_size_override("font_size",font_size)
	check.text=_wrap_words(label,maxf(80,rect.size.x-136),font_size)
	var label_height: float=get_theme_font("font").get_height(font_size)*(check.text.count("\n")+1)+24
	check.custom_minimum_size=Vector2(rect.size.x,maxf(rect.size.y,label_height))
	check.add_theme_icon_override("checked",load("res://presentation/resources/toggle_on.svg"));check.add_theme_icon_override("unchecked",load("res://presentation/resources/toggle_off.svg"))
	for color_name in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_disabled_color"]:check.add_theme_color_override(color_name,INK)
	parent.add_child(check);check.toggled.connect(callback);return check
func _open_settings() -> void:
	_sheet(tx("ui.settings","Настройки"))
	var scroll: ScrollContainer=_sheet_scroll()
	var width: float=_sheet_inner.size.x-24
	var rows=VBoxContainer.new();rows.mouse_filter=MOUSE_FILTER_PASS;rows.custom_minimum_size=Vector2(width,0);rows.add_theme_constant_override("separation",16);scroll.add_child(rows)
	var toggles=Control.new();toggles.mouse_filter=MOUSE_FILTER_PASS;toggles.custom_minimum_size=Vector2(width,288);rows.add_child(toggles)
	_toggle(toggles,tx("ui.all_sound","Весь звук"),Rect2(0,0,width,144),not settings.audio.master_muted,func(v):settings.audio.master_muted=not v;_apply_audio())
	_toggle(toggles,tx("ui.sound","Звуки"),Rect2(0,144,width,144),settings.audio.sound_enabled,func(v):settings.audio.sound_enabled=v;_apply_audio())
	var cats: Array=["Master","Music","SFX","Ambience","Voice","UI"]
	var cat_names: Array=[tx("ui.volume","Общая громкость"),tx("ui.music","Музыка"),tx("ui.sfx","Эффекты"),tx("ui.ambience","Окружение"),tx("ui.voice","Голоса"),tx("ui.interface","Интерфейс")]
	for i in range(cats.size()):
		var category: String=cats[i]
		var card=Control.new();card.mouse_filter=MOUSE_FILTER_PASS
		var label_width: float=width if category=="Master" else width-300
		var heading_height: float=_text_height(cat_names[i],label_width,int(BODY_FONT_SIZE*float(settings.accessibility.text_scale)))
		var slider_y: float=maxf(144,heading_height)+16
		card.custom_minimum_size=Vector2(width,slider_y+160);rows.add_child(card)
		_text(card,cat_names[i],Rect2(0,0,label_width,maxf(82,heading_height)),BODY_FONT_SIZE)
		if category!="Master":_toggle(card,tx("ui.enabled","Вкл"),Rect2(width-280,0,280,144),settings.audio.categories[category].enabled,func(v):settings.audio.categories[category].enabled=v;_apply_audio())
		var slider=HSlider.new();slider.position=Vector2(8,slider_y);slider.size=Vector2(width-220,144);slider.min_value=0;slider.max_value=1;slider.step=.01;slider.add_theme_icon_override("grabber",load("res://presentation/resources/slider_knob.svg"));slider.add_theme_icon_override("grabber_highlight",load("res://presentation/resources/slider_knob.svg"));slider.value=settings.audio.master_volume if category=="Master" else settings.audio.categories[category].volume;card.add_child(slider)
		var percent: Label=_text(card,"%d%%" % int(slider.value*100),Rect2(width-204,slider_y+32,204,96),BODY_FONT_SIZE)
		slider.value_changed.connect(func(v):
			if category=="Master":settings.audio.master_volume=v
			else:settings.audio.categories[category].volume=v
			percent.text="%d%%" % int(v*100);_apply_audio())
	var access=VBoxContainer.new();access.mouse_filter=MOUSE_FILTER_PASS;access.custom_minimum_size=Vector2(width,0);access.add_theme_constant_override("separation",8);rows.add_child(access)
	_toggle(access,tx("ui.reduced_motion","Уменьшить движение"),Rect2(0,0,width,144),settings.accessibility.reduced_motion,_set_reduced_motion)
	_toggle(access,tx("ui.subtitles","Субтитры"),Rect2(0,144,width,144),settings.accessibility.subtitles,_set_subtitles)
	_toggle(access,tx("ui.haptics","Вибрация"),Rect2(0,288,width,144),settings.accessibility.haptics,func(v):settings.accessibility.haptics=v;saver.write_slot("settings",settings))
	var scale_row=HBoxContainer.new();scale_row.mouse_filter=MOUSE_FILTER_PASS;rows.add_child(scale_row)
	for scale_value in [1.0,1.2,1.4]:
		var b: Button=_button(scale_row,"%d%%" % int(scale_value*100),Rect2(0,0,(width-32)/3,144),func():settings.accessibility.text_scale=scale_value;saver.write_slot("settings",settings);_build_ui();_update_ui();_open_settings(),false,BODY_FONT_SIZE)
		b.custom_minimum_size=Vector2((width-32)/3,144)
	var lang: Button=_button(rows,tx("ui.language","Язык")+": "+settings.locale.to_upper(),Rect2(0,0,width,144),func():settings.locale="en" if settings.locale=="ru" else "ru";_load_catalog();saver.write_slot("settings",settings);_build_ui();_update_ui();_open_settings(),false,BODY_FONT_SIZE);lang.custom_minimum_size=Vector2(width,144)
	var restart: Button=_button(rows,tx("ui.restart","Заново"),Rect2(0,0,width,144),func():_close_overlay();_command("Restart"),false,BODY_FONT_SIZE);restart.custom_minimum_size=Vector2(width,144)
	var menu: Button=_button(rows,QuestGuide._t(str(settings.locale),"Главное меню","Main menu"),Rect2(0,0,width,144),func():_save_progress();_show_title(),false,BODY_FONT_SIZE);menu.custom_minimum_size=Vector2(width,144)
	var album: Button=_button(rows,tx("ui.album","Альбом уровней"),Rect2(0,0,width,144),_open_levels,false,BODY_FONT_SIZE);album.custom_minimum_size=Vector2(width,144)
	_sheet_action(tx("ui.back_game","Вернуться в игру"),_dismiss_overlay)
func _apply_audio() -> void:audio.settings=settings.audio;audio.apply_settings();saver.write_slot("settings",settings)
func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(overlay):_dismiss_overlay()
		else:_open_settings()
	if what==NOTIFICATION_APPLICATION_PAUSED:
		_app_paused=true
		if is_instance_valid(stage):stage.process_mode=Node.PROCESS_MODE_DISABLED
		if is_instance_valid(audio):audio.set_paused(true)
		if not kernel.state.is_empty():_save_progress()
	if what==NOTIFICATION_APPLICATION_RESUMED:
		_app_paused=false
		if is_instance_valid(stage):stage.process_mode=Node.PROCESS_MODE_INHERIT
		if is_instance_valid(audio):audio.set_paused(false)
		if not kernel.state.is_empty() and kernel.state.phase in Kernel.ACTIVE_PHASES:kernel.restore(kernel.stable_checkpoint());_accumulator=0;_update_ui()
	if what==NOTIFICATION_WM_CLOSE_REQUEST:_quit_gracefully()
func _quit_gracefully() -> void:
	if _quitting:return
	_quitting=true;_app_paused=true
	if not kernel.state.is_empty():_save_progress()
	if not settings.is_empty():saver.write_slot("settings",settings)
	var released: bool=true
	if is_instance_valid(audio):released=await audio.shutdown_and_wait()
	if not released:push_error("Audio playback did not release before shutdown")
	get_tree().quit(0 if released else 1)
func _prepare_capture() -> void:
	_close_overlay();kernel.load_level(_json("res://data/levels/"+level_ids[level_number-1]+".json"),48121)
	if _capture_stage=="title":_show_title()
	elif _capture_stage=="briefing":_briefing()
	elif _capture_stage=="settings":_open_settings()
	elif _capture_stage=="map":_open_levels()
	elif _capture_stage!="plan":
		var id: String=level_ids[level_number-1]
		var path: String="res://tests/"+("" if level_number<=3 else "replays/")+id+"_solution.json"
		var replay: Dictionary=_json(path)
		for step in replay.get("steps",[]):
			if step.op=="command":kernel.dispatch(step)
			elif step.op=="advance_ticks":kernel.advance_ticks(int(step.count))
			if _capture_stage=="moving" and step.get("type","")=="RunResolution":
				kernel.advance_ticks(5);break
			if _capture_stage=="show" and step.get("type","")=="BeginPerformance":
				kernel.advance_ticks(12);break
			if _capture_stage=="selection" and kernel.state.phase=="PROOF_ACCEPTED" and kernel.state.active_laws.size()==2:
				kernel.dispatch({"type":"ActivateLaw","payload":{"myth_id":kernel.state.candidate_law,"replace_law_id":null}});break
			if _capture_stage=="proof" and kernel.state.phase=="PROOF_ACCEPTED":break
			if _capture_stage=="law" and step.get("type","")=="ActivateLaw":break
			if _capture_stage=="resolution" and step.get("type","")=="AssignRoute":break
		_update_ui()
		if _capture_stage=="success":_victory()
		if _capture_stage=="selection":_replacement_menu()
	stage.kernel=kernel
	if _capture_stage in ["show","proof","law","success"]:stage.play_actor("felix",{"show":"show_begin","proof":"accept","law":"stamp","success":"bow"}[_capture_stage])

func _dismiss_overlay() -> void:
	_close_overlay()
	if kernel.state.is_empty():_show_title();return
	if kernel.state.get("phase","")=="LAW_SELECTION":_command("CancelLawSelection")
	if _front_menu:_show_title()
	else:audio.set_chapter_theme(kernel.definition.get("scene_id","ENV01"),kernel.state.get("level_id","")=="L30")
func _show_title() -> void:
	_close_overlay();_front_menu=true
	overlay=Control.new();overlay.name="ScientistMainMenu";overlay.size=get_viewport_rect().size;overlay.position=Vector2.ZERO;add_child(overlay)
	var screen: Vector2=overlay.size
	var sx: float=screen.x/1560.0;var sy: float=screen.y/720.0
	var background=TextureRect.new();background.size=screen;background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;background.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;background.mouse_filter=MOUSE_FILTER_IGNORE;background.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS;background.texture=Art.texture_for("environments","ENV01");overlay.add_child(background)
	var gradient=Gradient.new();gradient.offsets=PackedFloat32Array([0,.23,.42,.68,1]);gradient.colors=PackedColorArray([Color("20243af5"),Color("252647ee"),Color("25264795"),Color("25264700"),Color("25264700")])
	var gradient_texture=GradientTexture2D.new();gradient_texture.gradient=gradient;gradient_texture.width=1024;gradient_texture.height=2;gradient_texture.fill_from=Vector2.ZERO;gradient_texture.fill_to=Vector2(1,0)
	var shade=TextureRect.new();shade.texture=gradient_texture;shade.size=screen;shade.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;shade.mouse_filter=MOUSE_FILTER_IGNORE;overlay.add_child(shade)
	_menu_art(overlay,Art.texture_for("characters","CH01"),Rect2(770*sx,15*sy,620*sx,705*sy),"ProfessorPortrait")
	_menu_art(overlay,Art.texture_for("characters","CH02"),Rect2(1272*sx,104*sy,236*sx,205*sy),"PlumPortrait")
	var text_x: float=70*sx
	var is_en: bool=str(settings.locale)=="en"
	var eyebrow: Label=_text(overlay,tx("ui.title_eyebrow","МИР НЕВОЗМОЖНЫХ ОТКРЫТИЙ"),Rect2(text_x,75*sy,780*sx,40*sy),int(23*sy),ThemeKit.GOLD)
	eyebrow.add_theme_font_size_override("font_size",int(23*sy));eyebrow.text=eyebrow.text.to_upper();eyebrow.autowrap_mode=TextServer.AUTOWRAP_OFF
	var title: Label=_text(overlay,"ALMOST" if is_en else "ПОЧТИ",Rect2(text_x,115*sy,820*sx,132*sy),int((100 if is_en else 116)*sy),CREAM)
	title.name="MenuWordmarkFirst";title.add_theme_font_size_override("font_size",int((100 if is_en else 116)*sy));title.autowrap_mode=TextServer.AUTOWRAP_OFF
	var second=RichTextLabel.new();second.name="MenuWordmarkSecond";second.position=Vector2(text_x,221*sy);second.size=Vector2(800*sx,170*sy);second.mouse_filter=MOUSE_FILTER_IGNORE;second.bbcode_enabled=true;second.scroll_active=false
	second.add_theme_font_override("normal_font",ThemeKit.heading_font());second.add_theme_font_size_override("normal_font_size",int(172*sy));second.add_theme_color_override("default_color",CREAM)
	second.text="G[color=#F16C65]O[/color]D" if is_en else "Б[color=#F16C65]О[/color]Г";overlay.add_child(second)
	var description: String=tx("ui.title_line1","Сначала — смелый опыт.")+"\n"+tx("ui.title_line2","Потом — совсем другой мир.")
	var description_label: Label=_text(overlay,description,Rect2(text_x,410*sy,760*sx,100*sy),48,CREAM)
	description_label.name="MenuPromise"
	var has_started: bool=bool(progress.get("story_started",false)) or not progress.get("completed",{}).is_empty() or kernel.state!=kernel._initial_state
	var play_label: String=tx("ui.continue_story","Продолжить историю") if has_started else tx("ui.begin_story","Начать историю")
	var button_w: float=maxf(600,465*sx)
	var menu_lines: String=_wrap_words(play_label,button_w-120,int(BODY_FONT_SIZE*float(settings.accessibility.text_scale)))
	var button_h: float=maxf(144,(menu_lines.count("\n")+1)*get_theme_font("font").get_height(int(BODY_FONT_SIZE*float(settings.accessibility.text_scale)))+32)
	var play: Button=_button(overlay,play_label,Rect2(text_x,516*sy,button_w,button_h),_enter_game,true,BODY_FONT_SIZE,"play");play.name="EnterStory"
	var pair: String=tx("ui.title_pair","Профессор Феликс и Плюм")+"  ·  "+tx("ui.title_adventure","Первое открытие")
	var foot: Label=_text(overlay,pair,Rect2(text_x,maxf(634*sy,516*sy+button_h+18),880*sx,50*sy),int(27*sy),CREAM)
	foot.add_theme_font_size_override("font_size",int(27*sy));foot.modulate.a=.75;foot.autowrap_mode=TextServer.AUTOWRAP_OFF
	_button(overlay,"",Rect2(screen.x-180,42,144,144),_open_settings,false,BODY_FONT_SIZE,"settings").name="MenuSettings"
	var motto: Label=_text(overlay,tx("ui.title_motto","НЕВОЗМОЖНОЕ ВОЗМОЖНО"),Rect2(screen.x-650,screen.y-88,610,64),28,CREAM)
	motto.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;motto.add_theme_font_size_override("font_size",28);motto.text=motto.text.to_upper()
	audio.play_music("music_menu")

func _menu_art(parent: Control,texture: Texture2D,rect: Rect2,node_name: String) -> TextureRect:
	var figure=TextureRect.new();figure.name=node_name;figure.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS;figure.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;figure.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;figure.texture=texture;figure.position=rect.position;figure.size=rect.size;figure.mouse_filter=MOUSE_FILTER_IGNORE;parent.add_child(figure);return figure

func _show_credits() -> void:
	audio.play_music("music_credits")
	_modal(tx("ui.credits","Занавес? Почти."),tx("ui.credits_text","Феликс, Плам, Марфа, Семён, Ника, Лада, Роза, Гюго и Карамелька благодарят вас.

Теперь в этом мире знают: даже невозможное начинается с хорошо продуманного плана.

Музыка и иллюстрации созданы специально для игры."),tx("ui.album","Альбом уровней"),_open_levels)

func _slot_name(slot: Dictionary,index: int) -> String:
	var names: Dictionary={"bridge":"Переправа","stage_stone":"Камень на сцене","stage_float":"Под камнем на сцене","stage_cold":"Под чашей","stage_paper":"Пролёт моста","stage_frame":"Под пролётом","stage_weight":"Испытательный стенд","weight_start":"К тали","screen_left":"Левый край сцены","screen_right":"Правый край сцены","near_support":"Ближняя опора","middle_support":"Опора у острова","far_support":"Дальняя опора","bread_box":"В термокороб","bread_delivery":"В доставку","dessert_delivery":"В доставку","box_delivery":"В доставку","thermal_block":"Защитить от тепла","oven_far":"Убрать от воды","warm_boat":"Нагреть протоку","warm_sample":"Нагреть образец","stone_away":"Отнести от образца"}
	var fallback: String=names.get(slot.id,"В реквизит" if slot.mount_layer=="tray" else "Место %d" % (index+1))
	return tx("slot."+slot.id+".name",fallback)
func _slot_menu(entity_id: String) -> void:
	var choices: Array=[]
	var count: int=0
	for slot in kernel.definition.slots:
		if kernel._entities[entity_id].type_id not in slot.allowed_entity_types:continue
		var payload: Dictionary={"entity_id":entity_id,"slot_id":slot.id}
		var props: Dictionary=kernel._entities[entity_id].properties
		if props.get("move_mode","")=="hoist":payload.move_mode="hoist";payload.hoist_entity_id=props.get("hoist_entity_id","")
		choices.append({"label":_slot_name(slot,count),"action":func():_command("PlaceProp",payload)})
		count+=1
	choices.append({"label":tx("ui.choose_on_stage","Выбрать место на сцене"),"action":func():selected=entity_id;stage.selected=entity_id;_update_ui()})
	_choices(_name(entity_id)+" · "+tx("ui.place","Место"),choices)

func _set_reduced_motion(value: bool) -> void:
	settings.accessibility.reduced_motion=value
	if is_instance_valid(stage):stage.reduced_motion=value
	saver.write_slot("settings",settings)
func _haptic(milliseconds: int) -> void:
	if settings.get("accessibility",{}).get("haptics",false):
		haptic_requested.emit(milliseconds)
		Input.vibrate_handheld(milliseconds)
func _enter_game() -> void:
	if kernel.state.is_empty():_open_levels();return
	_front_menu=false;_close_overlay();progress.story_started=true;_save_progress()
	audio.set_chapter_theme(kernel.definition.get("scene_id","ENV01"),kernel.state.get("level_id","")=="L30")
	if _checkpoint_reset_pending:
		_checkpoint_reset_pending=false
		_modal(QuestGuide._t(str(settings.locale),"Опыт обновлён","Experiment updated"),QuestGuide._t(str(settings.locale),"Правила опыта обновлены. Начинаем текущую задачу заново; открытые уровни сохранены.","The experiment rules have changed. This task starts again; your unlocked levels are preserved."),tx("ui.begin","За работу"),_briefing)
	elif kernel.state.phase=="SUCCESS":_victory()
	else:_briefing()

func _wrap_words(value: String,width: float,font_size: int) -> String:
	var font: Font=get_theme_font("font")
	var lines: Array[String]=[]
	for paragraph in value.split("\n"):
		var line: String=""
		for word in paragraph.split(" ",false):
			var candidate: String=word if line.is_empty() else line+" "+word
			if not line.is_empty() and font.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>width:
				lines.append(line);line=word
			else:line=candidate
		lines.append(line)
	return "\n".join(lines)
func _wrap_button(button: Button) -> void:
	if not is_instance_valid(button):return
	var icon_space: float=button.get_theme_constant("icon_max_width")+button.get_theme_constant("h_separation") if button.icon!=null else 0
	var padding: float=button.get_theme_stylebox("normal").get_minimum_size().x
	button.text=_wrap_words(button.text,maxf(80,button.size.x-padding-icon_space),button.get_theme_font_size("font_size"))
func _voice(character: String,emotion: String,caption_emotion: String="") -> void:
	audio.play_event(character+".voice."+emotion,"Voice")
	_caption(character,emotion if caption_emotion.is_empty() else caption_emotion)
func _caption(character: String,emotion: String) -> void:
	if not settings.accessibility.subtitles:return
	var fallback: String={"curious":"заинтересованно мычит","accept":"одобрительно хмыкает","surprise":"удивлённо ахает","joy":"радостно восклицает","exposed":"недовольно ахает"}.get(emotion,"отзывается")
	_caption_queue.append(_character_name(character)+": "+tx("subtitle."+emotion,fallback))
	if _caption_queue.size()>4:_caption_queue.pop_front()
	if _caption_remaining<=0:_next_caption()
func _next_caption() -> void:
	if not is_instance_valid(_caption_panel) or _caption_queue.is_empty():return
	_caption_label.text=_caption_queue.pop_front();_fit_caption();_caption_panel.visible=true;_caption_remaining=2.2
func _fit_caption() -> void:
	var width: float=_caption_panel.size.x-48
	var height: float=maxf(112,_text_height(_caption_label.text,width,_caption_label.get_theme_font_size("font_size"))+24)
	_caption_panel.size.y=height;_caption_panel.position.y=maxf(stage.position.y+320,stage.position.y+stage.size.y-height-200)
	_caption_label.size=Vector2(width,height-24)

func _advance_caption(delta: float) -> void:
	if not settings.accessibility.subtitles:
		_caption_remaining=0;_caption_queue.clear()
		if is_instance_valid(_caption_panel):_caption_panel.visible=false
		return
	if _caption_remaining>0:
		_caption_remaining=maxf(0,_caption_remaining-delta)
		if _caption_remaining<=0:
			if is_instance_valid(_caption_panel):_caption_panel.visible=false
			_next_caption()
func _set_subtitles(value: bool) -> void:
	settings.accessibility.subtitles=value
	_advance_caption(0)
	saver.write_slot("settings",settings)

func _inventory_item_width(label: String,scale_value: float) -> float:
	var font: Font=get_theme_font("font")
	var size_px: int=int(BODY_FONT_SIZE*scale_value)
	var words: PackedStringArray=label.split(" ",false)
	# Choose a width that can hold the complete authored label on at most two
	# lines; a fixed tray must not grow below the display for long prop names.
	var text_width: float=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x
	for split_at in range(1,words.size()):
		var first: String=" ".join(words.slice(0,split_at))
		var second: String=" ".join(words.slice(split_at))
		var candidate: float=maxf(font.get_string_size(first,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x,font.get_string_size(second,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x)
		text_width=minf(text_width,candidate)
	var padding: float=ThemeKit.button_style("normal").get_minimum_size().x
	return maxf(316*scale_value,text_width+80*scale_value+16+padding+8)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(overlay):_dismiss_overlay()
		else:_open_settings()
		get_viewport().set_input_as_handled()
