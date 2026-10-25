extends Control
const Kernel=preload("res://core/simulation_kernel.gd")
const Stage=preload("res://presentation/stage_view.gd")
const Saver=preload("res://services/save_service.gd")
const Audio=preload("res://services/audio_service.gd")
const QuestGuide=preload("res://presentation/quest_guide.gd")
const ThemeKit=preload("res://presentation/theme.gd")
const INK=ThemeKit.INK
const CREAM=ThemeKit.CREAM
const PURPLE=ThemeKit.PURPLE
const GREEN=ThemeKit.GREEN
# 1080 landscape reference height maps to 360 dp: 48px is readable 16sp.
const BODY_FONT_SIZE: int=ThemeKit.BODY_FONT_SIZE
const DISABLED_TEXT=ThemeKit.DISABLED_TEXT
const CHARACTER_NAMES={"CH01":"Феликс","CH02":"Плам","CH03":"Марфа","CH04":"Семён","CH05":"Ника","CH06":"Лада","CH07":"Роза","CH08":"Гюго","CH09":"Карамелька"}
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
	var id: String=level_ids[number-1]
	var definition: Dictionary=_json("res://data/levels/"+id+".json")
	if not kernel.load_level(definition,48121):
		_level_load_failed(id)
		return false
	level_number=number
	_invalid_levels.erase(id)
	var checkpoint=progress.get("checkpoint")
	if resume and checkpoint is Dictionary and checkpoint.get("level_id","")==id:kernel.restore(checkpoint)
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
	b.add_theme_color_override("font_color",CREAM if filled else INK);b.add_theme_color_override("font_hover_color",CREAM if filled else PURPLE);b.add_theme_color_override("font_pressed_color",CREAM if filled else PURPLE)
	b.add_theme_color_override("font_focus_color",CREAM if filled else INK)
	for color_name in ["icon_normal_color","icon_hover_color","icon_pressed_color","icon_focus_color"]:b.add_theme_color_override(color_name,CREAM if filled else INK)
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
	var previous_scroll: int=_upper_scroll.scroll_vertical if is_instance_valid(_upper_scroll) else 0
	var reusable_stage: Control=stage if is_instance_valid(stage) else null
	if reusable_stage!=null and reusable_stage.get_parent()!=null:reusable_stage.get_parent().remove_child(reusable_stage)
	if is_instance_valid(ui):ui.queue_free()
	_close_overlay();ui=Control.new();add_child(ui)
	var screen: Vector2=get_viewport_rect().size
	ui.position=Vector2.ZERO;ui.size=screen;_layout_screen=screen
	var text_scale: float=clampf(float(settings.accessibility.text_scale),1.0,1.4)
	var font_size: int=int(BODY_FONT_SIZE*text_scale)
	var copy: Dictionary=_hud_copy()
	var next_copy_key: String=str(copy.get("stage_title",""))+"|"+copy.law+"|"+copy.body+"|"+JSON.stringify(copy.get("goals",[]))
	if next_copy_key!=_layout_copy_key:previous_scroll=0
	_layout_copy_key=next_copy_key
	var margin: float=12
	var safe_left: float=margin;var safe_right: float=margin;var safe_top: float=margin;var safe_bottom: float=margin
	if DisplayServer.get_name()!="headless":
		var safe: Rect2i=DisplayServer.get_display_safe_area()
		var window: Vector2i=DisplayServer.window_get_size()
		if window.x>0 and window.y>0 and safe.size.x>0 and safe.size.y>0:
			var factor: Vector2=screen/Vector2(window)
			safe_left=maxf(margin,safe.position.x*factor.x+12);safe_right=maxf(margin,(window.x-safe.end.x)*factor.x+12)
			safe_top=maxf(margin,safe.position.y*factor.y+12);safe_bottom=maxf(margin,(window.y-safe.end.y)*factor.y+12)
	var dock_w: float=512
	var gap: float=16
	var left_w: float=screen.x-safe_left-safe_right-dock_w-gap
	var dock_x: float=screen.x-safe_right-dock_w
	var header_h: float=144
	var stage_y: float=safe_top+header_h
	var tray_h: float=maxf(144,get_theme_font("font").get_height(font_size)*2+24)+20
	var tray_y: float=screen.y-safe_bottom-tray_h
	var stage_h: float=tray_y-stage_y-8
	var paper=ColorRect.new();paper.size=screen;paper.color=ThemeKit.SKY;paper.mouse_filter=MOUSE_FILTER_IGNORE;ui.add_child(paper)
	var heading: String="%02d  %s" % [level_number,tx(_key("title"),"Новое чудо")]
	var title_label: Label=_text(ui,heading,Rect2(safe_left+12,safe_top,maxf(300,left_w-704),header_h-16),48,INK)
	title_label.autowrap_mode=TextServer.AUTOWRAP_OFF;title_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;title_label.clip_text=true;title_label.tooltip_text=heading
	_button(ui,tx("ui.undo_short","Откат"),Rect2(safe_left+left_w-672,safe_top,240,144),func():_command("Undo"),false,BODY_FONT_SIZE)
	_button(ui,tx("ui.hint_short","Совет"),Rect2(safe_left+left_w-420,safe_top,240,144),_hint,false,BODY_FONT_SIZE)
	_button(ui,"",Rect2(safe_left+left_w-156,safe_top,144,144),_open_settings,false,BODY_FONT_SIZE,"settings")
	_button(ui,tx("ui.plan","План"),Rect2(dock_x,safe_top,dock_w,144),_plan_menu,false,BODY_FONT_SIZE,"route")
	stage=reusable_stage if reusable_stage!=null else Stage.new();stage.kernel=kernel;stage.translator=tx;stage.selected=selected;stage.inspected=inspected
	stage.position=Vector2(safe_left,stage_y);stage.size=Vector2(left_w,stage_h);stage.reduced_motion=settings.accessibility.reduced_motion;stage.process_mode=Node.PROCESS_MODE_DISABLED if _app_paused else Node.PROCESS_MODE_INHERIT;ui.add_child(stage)
	if not stage.target_tapped.is_connected(_on_target):stage.target_tapped.connect(_on_target)
	_caption_panel=_box(ui,Rect2(stage.position.x+24,stage.position.y+stage.size.y-148,stage.size.x-48,124),Color(.99,1,1,.96),20)
	_caption_panel.visible=previous_remaining>0 and settings.accessibility.subtitles
	_caption_label=_text(_caption_panel,previous_caption,Rect2(24,12,_caption_panel.size.x-48,100),BODY_FONT_SIZE)
	_caption_remaining=previous_remaining;_caption_queue=previous_queue
	if not previous_caption.is_empty():_fit_caption()
	_box(ui,Rect2(dock_x,stage_y,dock_w,screen.y-safe_bottom-stage_y),Color("f1f8f8"),28)
	var primary_lines: String=_wrap_words(copy.get("primary",""),dock_w-72,font_size)
	var primary_h: float=maxf(160,(primary_lines.count("\n")+1)*get_theme_font("font").get_height(font_size)+32)
	var primary_y: float=screen.y-safe_bottom-primary_h
	var witness_h: float=208
	var witness_y: float=primary_y-witness_h-24
	_upper_scroll=ScrollContainer.new();_upper_scroll.mouse_filter=MOUSE_FILTER_PASS;_upper_scroll.position=Vector2(dock_x+24,stage_y+20);_upper_scroll.size=Vector2(dock_w-48,witness_y-stage_y-36);_upper_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;_upper_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;ui.add_child(_upper_scroll);_upper_scroll.set_deferred("scroll_vertical",previous_scroll)
	var content=Control.new();content.mouse_filter=MOUSE_FILTER_PASS;_upper_scroll.add_child(content)
	var text_width: float=dock_w-72
	var guide_y: float=0
	var phase_title: String=copy.get("stage_title",tx("ui.objective","Задача"))
	var phase_height: float=_text_height(phase_title,text_width,int(42*text_scale))+16
	_text(content,phase_title,Rect2(0,guide_y,text_width,phase_height),42,PURPLE);guide_y+=phase_height+16
	var body_h: float=_text_height(copy.body,text_width,font_size)+16
	var headline: Dictionary=copy.get("goal_headline",{"id":"","label":copy.get("objective",""),"done":false})
	var headline_text: String=("✓  " if headline.get("done",false) else "")+str(headline.get("label",""))
	var headline_h: float=_text_height(headline_text,text_width-32,font_size)+32
	for block in (["goal","body"] if selected.is_empty() else ["body","goal"]):
		if block=="goal":
			_box(content,Rect2(0,guide_y,text_width,headline_h),Color("e0f4ee"),20)
			_goal_headline=_text(content,headline_text,Rect2(16,guide_y+16,text_width-32,headline_h-32),BODY_FONT_SIZE,GREEN);guide_y+=headline_h+16
		else:
			instruction=_text(content,copy.body,Rect2(0,guide_y,text_width,body_h),BODY_FONT_SIZE);guide_y+=body_h+24
	for goal in copy.get("goals",[]):
		if not str(headline.get("id","")).is_empty() and goal.get("id","")==headline.id and str(goal.get("label",""))==str(headline.get("label","")):continue
		var goal_text: String=("✓  " if goal.get("done",false) else "○  ")+str(goal.get("label",""))
		var goal_h: float=_text_height(goal_text,text_width,font_size)+16
		_text(content,goal_text,Rect2(0,guide_y,text_width,goal_h),BODY_FONT_SIZE,GREEN if goal.get("done",false) else INK);guide_y+=goal_h+12
	var law_h: float=_text_height(copy.law,text_width,font_size)+16
	law_label=_text(content,copy.law,Rect2(0,guide_y,text_width,law_h),BODY_FONT_SIZE,PURPLE);guide_y+=law_h+8
	content.custom_minimum_size=Vector2(text_width,guide_y)
	_layout_law_height=law_h;_layout_instruction_height=body_h
	witness_labels.clear();_audience_scroll=null
	var n: int=kernel.definition.witnesses.size()
	if n>0:
		var audience_scroll=ScrollContainer.new();_audience_scroll=audience_scroll;audience_scroll.mouse_filter=MOUSE_FILTER_PASS;audience_scroll.position=Vector2(dock_x+12,witness_y);audience_scroll.size=Vector2(dock_w-24,witness_h);audience_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;audience_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;ui.add_child(audience_scroll)
		var audience=HBoxContainer.new();audience.mouse_filter=MOUSE_FILTER_PASS;audience.add_theme_constant_override("separation",12);audience_scroll.add_child(audience)
		var card_w: float=maxf(144,floorf((dock_w-24-12*maxi(0,n-1))/maxi(1,n)))
		var large_text: bool=text_scale>=1.4
		for wd in kernel.definition.witnesses:
			var cell=Control.new();cell.mouse_filter=MOUSE_FILTER_PASS;cell.custom_minimum_size=Vector2(card_w,witness_h);audience.add_child(cell)
			var hit: Button=_button(cell,"",Rect2(0,0,card_w,witness_h),func():_inspect(wd.id));hit.tooltip_text=_character_name(wd.character_id)
			var char_name: String=Stage.CHARACTERS.get(wd.character_id,"crowd_gardener")
			var path: String="res://assets/art/characters/portraits/"+char_name+"/idle.png"
			var portrait: TextureRect=null
			var name_h: float=get_theme_font("font").get_height(int(42*text_scale))
			var status_font: int=BODY_FONT_SIZE if large_text else 42
			var status_h: float=get_theme_font("font").get_height(int(status_font*text_scale))
			var portrait_h: float=witness_h-status_h-12 if large_text else witness_h-name_h-status_h-12
			var portrait_texture: Texture2D=null
			if ResourceLoader.exists(path):portrait_texture=load(path)
			else:
				var baseline_path: String="res://assets/art/characters/"+char_name+".png"
				if ResourceLoader.exists(baseline_path):
					var baseline: Texture2D=load(baseline_path);var crop=AtlasTexture.new();crop.atlas=baseline
					crop.region=Rect2(baseline.get_width()*.12,baseline.get_height()*.01,baseline.get_width()*.76,baseline.get_height()*.34);portrait_texture=crop
			if portrait_texture!=null:
				portrait=TextureRect.new();portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.texture=portrait_texture;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;portrait.position=Vector2(6,4);portrait.size=Vector2(card_w-12,portrait_h);portrait.mouse_filter=MOUSE_FILTER_IGNORE;cell.add_child(portrait)
			var status_label: Label=_text(cell,"?",Rect2(6,witness_h-status_h-4,card_w-12,status_h),status_font);status_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			var name_label: Label=_text(cell,_character_name(wd.character_id),Rect2(6,portrait_h+8,card_w-12,name_h),42);name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;name_label.visible=not large_text;name_label.autowrap_mode=TextServer.AUTOWRAP_OFF;name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;name_label.clip_text=true
			witness_labels[wd.id]={"name":name_label,"status":status_label,"portrait":portrait,"character":char_name,"button":hit}
			if is_instance_valid(portrait):portrait.set_meta("fallback",portrait.texture)
	else:
		_text(ui,tx("ui.no_audience_short","Закон действует"),Rect2(dock_x+24,witness_y,dock_w-48,witness_h),BODY_FONT_SIZE,GREEN)
	var inventory=ScrollContainer.new();_inventory_scroll=inventory;inventory.mouse_filter=MOUSE_FILTER_PASS;inventory.position=Vector2(safe_left,tray_y);inventory.size=Vector2(left_w,tray_h);inventory.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;inventory.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;ui.add_child(inventory)
	var row=HBoxContainer.new();row.mouse_filter=MOUSE_FILTER_PASS;row.add_theme_constant_override("separation",16);inventory.add_child(row)
	for entity in kernel.definition.entities:
		if not entity.movable and entity.properties.get("attachment_kind","").is_empty():continue
		var id: String=entity.id
		var item_width: float=_inventory_item_width(_name(id),text_scale)
		var b: Button=_button(row,_name(id),Rect2(0,0,item_width,tray_h-20),func():_select(id),selected==id,BODY_FONT_SIZE)
		b.set_meta("entity_id",id);b.custom_minimum_size=Vector2(item_width,tray_h-20)
		var path: String=stage.asset_path(id)
		if ResourceLoader.exists(path):
			b.icon=load(path);b.expand_icon=true;b.add_theme_constant_override("icon_max_width",int(80*text_scale));b.add_theme_constant_override("h_separation",16)
			for color_name in ["icon_normal_color","icon_hover_color","icon_pressed_color","icon_focus_color"]:b.add_theme_color_override(color_name,Color.WHITE)
			b.add_theme_color_override("icon_disabled_color",Color(1,1,1,.5))
		b.text=_name(id);_wrap_button(b)
	primary=_button(ui,"",Rect2(dock_x+12,primary_y,dock_w-24,primary_h),_primary,true,BODY_FONT_SIZE)
	_flash=ColorRect.new();_flash.size=screen;_flash.color=Color(1,.94,.68,0);_flash.mouse_filter=MOUSE_FILTER_IGNORE;ui.add_child(_flash)

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
	var font_size: int=int(BODY_FONT_SIZE*float(settings.accessibility.text_scale))
	if _layout_copy_key!=str(copy.get("stage_title",""))+"|"+copy.law+"|"+copy.body+"|"+JSON.stringify(copy.get("goals",[])):_build_ui()
	var state: Dictionary=kernel.state
	law_label.text=copy.law
	for wd in kernel.definition.witnesses:
		var w: Dictionary=state.witnesses[wd.id]
		var total: int=0;var required: int=0
		for view in wd.views:total+=mini(int(w.view_progress[view.id]),int(view.clear_ticks));required+=int(view.clear_ticks)
		var suffix: String="✓" if w.eligible_vote else ("!" if w.exposed else ("…" if state.phase in ["PERFORMANCE","REHEARSAL"] else "?"))
		var card: Dictionary=witness_labels[wd.id]
		var emotion: String="celebrate" if state.phase=="SUCCESS" else ("reveal_react" if w.exposed else ("accept" if w.eligible_vote else ("suspect" if inspected==wd.id else ("observe" if state.phase in ["PERFORMANCE","REHEARSAL"] else "idle"))))
		var portrait_path: String="res://assets/art/characters/portraits/"+card.character+"/"+emotion+".png"
		if is_instance_valid(card.portrait):card.portrait.texture=load(portrait_path) if ResourceLoader.exists(portrait_path) else card.portrait.get_meta("fallback")
		witness_labels[wd.id].name.text=_character_name(wd.character_id)
		witness_labels[wd.id].status.text=suffix
		witness_labels[wd.id].status.tooltip_text=copy.get("witness_status",{}).get(wd.id,"")
		witness_labels[wd.id].button.tooltip_text=_character_name(wd.character_id)+": "+copy.get("witness_status",{}).get(wd.id,"")
		witness_labels[wd.id].status.add_theme_color_override("font_color",GREEN if w.eligible_vote else INK)
	primary.text=copy.primary
	primary.disabled=copy.primary_disabled
	audio.set_phase(state.phase)
	instruction.text=copy.body
	_wrap_button(primary)

func _primary() -> void:
	var state: Dictionary=kernel.state
	if state.phase in Kernel.PLAN_PHASES and not selected.is_empty() and not selected.begins_with("w:"):_object_menu(selected);return
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
	_sheet_action(tx("ui.close","Вернуться"),_dismiss_overlay)

func _toast(message: String) -> void:_modal(tx("ui.plum_help","Плам подсказывает"),message,tx("ui.understood","Понятно"),func():pass)
func _briefing() -> void:
	var body: String=QuestGuide.briefing(kernel,str(settings.get("locale","ru")),level_number,level_ids.size(),catalog)
	_modal(tx(_key("title"),"Новое чудо"),body,tx("ui.begin","За работу"),func():audio.play("voice_felix","Voice"))

func _hint() -> void:
	_hint_index=mini(_hint_index+1,3);audio.play("hint","UI")
	_modal(txf("ui.hint_stage","Подсказка {number} из 3",{"number":_hint_index}),tx(_key("hint%d" % _hint_index),"Проверь обзор зрителей и состояние опор."),tx("ui.try","Попробую"),func():pass)
func _object_menu(id: String) -> void:
	var d: Dictionary=kernel._entities[id];var props: Dictionary=d.properties;var e: Dictionary=kernel.state.entities[id];var choices: Array=[]
	choices.append({"label":tx("ui.place_prop","Выбрать место…"),"action":func():_slot_menu(id)})
	if d.movable:choices.append({"label":tx("ui.remove_prop","Убрать реквизит"),"action":func():_command("Interact",{"entity_id":id,"action":"remove"})})
	if props.has("initial_open") or props.has("initial_closed"):
		for action in ["open","close"]:
			choices.append({"label":tx("ui."+action,"Открыть" if action=="open" else "Закрыть"),"action":func():_command("Interact",{"entity_id":id,"action":action})})
	if not props.get("attachment_kind","").is_empty():
		choices.append({"label":tx("ui.attach","Прикрепить к предмету…"),"action":func():_attachment_menu(id)})
		if not e.get("attachment_target","").is_empty():choices.append({"label":tx("ui.detach","Отсоединить"),"action":func():_command("Interact",{"entity_id":id,"action":"detach"})})
	if props.has("emitter_class"):
		choices.append({"label":tx("ui.disable","Выключить источник") if e.get("enabled",true) else tx("ui.enable","Включить источник"),"action":func():_command("Interact",{"entity_id":id,"action":"disable" if e.get("enabled",true) else "enable"})})
	if d.apparent_class in ["CARGO","PERSON","ANIMAL"] or props.has("locomotion"):choices.append({"label":tx("ui.assign_route","Назначить маршрут…"),"action":func():_route_menu(id)})
	_choices(_name(id),choices)
func _attachment_menu(tool_id: String) -> void:
	var choices: Array=[]
	for id in kernel.state.entities:
		if id==tool_id or kernel.state.entities[id].removed:continue
		var props: Dictionary=kernel._entities[tool_id].properties
		if props.get("attachment_kind","")=="clamp" and kernel._entities[id].type_id not in props.get("attachable_target_types",[]):continue
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
		choices.append({"label":QuestGuide._t(str(settings.locale),"Маршруты","Routes"),"action":_actor_menu})
		choices.append({"label":tx("ui.laws","Законы и следующий фокус"),"action":_law_menu})
		if not kernel.state.get("candidate_law","").is_empty() and kernel.state.candidate_law not in kernel.state.active_laws:
			choices.append({"label":tx("ui.perform","Показать фокус")+" · "+_law_name(kernel.state.candidate_law),"action":func():_command("BeginPerformance"),"primary":true})
			choices.append({"label":tx("ui.rehearsal","Репетиция"),"action":func():_command("BeginRehearsal")})
		choices.append({"label":tx("ui.world_run","Дать миру действовать"),"action":func():_command("RunResolution")})
	elif phase=="REHEARSAL":choices.append({"label":tx("ui.stop_rehearsal","Остановить репетицию"),"action":func():_command("StopRehearsal")})
	elif phase=="RUN_RESOLUTION":choices.append({"label":tx("ui.stop_resolution","Вернуться к плану"),"action":func():_command("StopResolution")})
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
	var rows=VBoxContainer.new();rows.mouse_filter=MOUSE_FILTER_PASS;rows.custom_minimum_size=Vector2(_sheet_inner.size.x-24,0);rows.add_theme_constant_override("separation",24);scroll.add_child(rows)
	var help_text: String=tx("ui.level_select_help","Опыты можно повторять бесплатно.")
	var help_height: float=_text_height(help_text,_sheet_inner.size.x-24,int(BODY_FONT_SIZE*float(settings.accessibility.text_scale)))
	var help: Label=_text(rows,help_text,Rect2(0,0,_sheet_inner.size.x-24,help_height),BODY_FONT_SIZE);help.custom_minimum_size=Vector2(_sheet_inner.size.x-24,help_height)
	var grid=GridContainer.new();grid.name="LevelGrid";grid.columns=8;grid.add_theme_constant_override("h_separation",16);grid.add_theme_constant_override("v_separation",16);rows.add_child(grid)
	for i in range(level_ids.size()):
		var n: int=i+1
		var b: Button=_button(grid,str(n),Rect2(0,0,148,144),func():_front_menu=false;_close_overlay();start_level(n),n==level_number,BODY_FONT_SIZE);b.custom_minimum_size=Vector2(148,144)
		if progress.completed.has(level_ids[i]):_text(b,"★",Rect2(100,4,40,40),26,CREAM if n==level_number else GREEN)
		b.disabled=n>int(progress.get("unlocked",1)) or _invalid_levels.has(level_ids[i])
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
	var album: Button=_button(rows,tx("ui.album","Альбом уровней"),Rect2(0,0,width,144),_open_levels,false,BODY_FONT_SIZE);album.custom_minimum_size=Vector2(width,144)
	_sheet_action(tx("ui.back_game","Вернуться в игру"),_dismiss_overlay)
func _apply_audio() -> void:audio.settings=settings.audio;audio.apply_settings();saver.write_slot("settings",settings)
func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(overlay):_dismiss_overlay()
		else:_plan_menu()
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
	overlay=Control.new();overlay.size=get_viewport_rect().size;overlay.position=Vector2.ZERO;add_child(overlay)
	var screen: Vector2=overlay.size
	var background=TextureRect.new();background.size=screen;background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;background.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;background.mouse_filter=MOUSE_FILTER_IGNORE
	var bg_path: String="res://assets/art/environments/ENV01/landscape.png"
	if ResourceLoader.exists(bg_path):background.texture=load(bg_path)
	overlay.add_child(background)
	var shade=ColorRect.new();shade.size=screen;shade.color=Color(.03,.16,.24,.24);shade.mouse_filter=MOUSE_FILTER_IGNORE;overlay.add_child(shade)
	var card_w: float=760;var card_x: float=screen.x-card_w-72
	_box(overlay,Rect2(card_x,64,card_w,screen.y-128),Color(.99,1,.99,.96),40)
	_text(overlay,tx("ui.game_title","ПОЧТИ БОГ"),Rect2(card_x+52,100,card_w-104,144),88,PURPLE)
	_text(overlay,tx("ui.title_subtitle","Маленькое чудо.\nБольшие последствия."),Rect2(card_x+52,264,card_w-104,184),52)
	var button_w: float=card_w-104
	var play_label: String=QuestGuide._t(str(settings.locale),"Начать путешествие","Begin the journey") if progress.completed.is_empty() else QuestGuide._t(str(settings.locale),"Продолжить · уровень %d","Continue · level %d") % level_number
	_button(overlay,play_label,Rect2(card_x+52,screen.y-564,button_w,144),_enter_game,true,52)
	_button(overlay,tx("ui.album","Альбом уровней"),Rect2(card_x+52,screen.y-396,button_w,144),_open_levels,false,BODY_FONT_SIZE)
	_button(overlay,tx("ui.settings","Настройки"),Rect2(card_x+52,screen.y-228,button_w,144),_open_settings,false,BODY_FONT_SIZE,"settings")
	for item in [{"name":"felix","rect":Rect2(110,screen.y-850,520,800)},{"name":"plum","rect":Rect2(600,screen.y-740,280,280)}]:
		var path: String="res://assets/art/characters/"+item.name+".png"
		if not ResourceLoader.exists(path):continue
		var figure=TextureRect.new();figure.position=item.rect.position;figure.size=item.rect.size;figure.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;figure.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;figure.texture=load(path);figure.mouse_filter=MOUSE_FILTER_IGNORE;overlay.add_child(figure)
	audio.play_music("music_menu")

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
	_front_menu=false;_close_overlay()
	audio.set_chapter_theme(kernel.definition.get("scene_id","ENV01"),kernel.state.get("level_id","")=="L30")
	if kernel.state.phase=="SUCCESS":_victory()
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
	_caption_panel.size.y=height;_caption_panel.position.y=stage.position.y+stage.size.y-height-12
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
