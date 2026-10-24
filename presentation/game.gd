extends Control
const Kernel=preload("res://core/simulation_kernel.gd")
const Stage=preload("res://presentation/stage_view.gd")
const Saver=preload("res://services/save_service.gd")
const Audio=preload("res://services/audio_service.gd")
const INK=Color("25243b")
const CREAM=Color("fff5de")
const PURPLE=Color("5d43a7")
const GREEN=Color("276b5c")
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

func _ready() -> void:
	var global_theme=Theme.new();global_theme.default_font=load("res://assets/fonts/DejaVuSans.ttf");global_theme.default_font_size=40;theme=global_theme
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
	var style=StyleBoxFlat.new();style.bg_color=color;style.set_corner_radius_all(radius);panel.add_theme_stylebox_override("panel",style);panel.mouse_filter=MOUSE_FILTER_IGNORE;parent.add_child(panel);return panel
func _text(parent: Control,value: String,rect: Rect2,font_size: int=42,color: Color=INK) -> Label:
	var label=Label.new();label.position=rect.position;label.size=rect.size;label.text=value
	label.add_theme_font_size_override("font_size",int(font_size*float(settings.get("accessibility",{}).get("text_scale",1))))
	label.add_theme_color_override("font_color",color);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;label.mouse_filter=MOUSE_FILTER_IGNORE;parent.add_child(label);return label
func _button(parent: Control,value: String,rect: Rect2,callback: Callable,filled: bool=false,font_size: int=36,icon: String="") -> Button:
	var b=Button.new();b.mouse_filter=MOUSE_FILTER_PASS;b.position=rect.position;b.size=rect.size;b.clip_text=true;b.text=value;b.add_theme_font_size_override("font_size",int(font_size*float(settings.get("accessibility",{}).get("text_scale",1))))
	b.add_theme_color_override("font_color",CREAM if filled else INK);b.add_theme_color_override("font_hover_color",CREAM if filled else PURPLE);b.add_theme_color_override("font_pressed_color",CREAM if filled else PURPLE)
	for state_name in ["normal","hover","pressed","focus","disabled"]:
		var style=StyleBoxFlat.new();style.bg_color=PURPLE if filled else Color("f4e8cd");style.set_corner_radius_all(22);style.border_color=Color("d4c8ac");style.set_border_width_all(2)
		if state_name=="hover":style.bg_color=Color("6a4eb9") if filled else Color("ebddbd")
		if state_name=="pressed":style.bg_color=Color("493283") if filled else Color("ddcaa2")
		if state_name=="disabled":style.bg_color=Color("d1c9b9")
		if state_name=="focus":style.border_color=Color("d7aa47");style.set_border_width_all(5)
		b.add_theme_stylebox_override(state_name,style)
	if not icon.is_empty() and ResourceLoader.exists("res://assets/art/ui/"+icon+".svg"):
		b.icon=load("res://assets/art/ui/"+icon+".svg");b.expand_icon=true;b.add_theme_constant_override("icon_max_width",48);b.add_theme_constant_override("h_separation",14)
	b.pressed.connect(func():audio.play("tap","UI");callback.call());parent.add_child(b);_wrap_button(b);return b
func _hud_copy() -> Dictionary:
	var names: Array=[]
	for law in kernel.state.active_laws:names.append(_law_name(law))
	var law_text: String=tx("ui.law_scope","В этой сцене")+": "+(" · ".join(names) if not names.is_empty() else tx("ui.ordinary_world","Мир пока обыкновенный"))
	var body: String=tx(_key("objective"),"Измени план и проверь результат.")
	match kernel.state.phase:
		"PLAN_SHOW":body=tx(_key("plan_tip"),body)
		"PERFORMANCE","REHEARSAL":body=tx("ui.observation_help","Зрители должны видеть результат. Карточки показывают, кто уже убедился.")
		"PROOF_ACCEPTED":body=tx("ui.proof_accepted","Они поверили! Печать сделает чудо новым законом этой сцены.")
		"RUN_RESOLUTION":
			var waiting: bool=false
			for task in kernel.state.routes.values():waiting=waiting or not str(task.get("waiting_for","")).is_empty()
			body=tx("ui.wait_water","Ждём замерзания или оттаивания. Персонажи стоят на безопасном месте.") if waiting else tx("ui.world_acts","Мир действует по новым правилам. Можно остановить время после завершения путей.")
		"RECOVERABLE_FAILURE":body=_reason(kernel.state.get("failure_reason",""))
	if not selected.is_empty() and kernel.state.phase in Kernel.PLAN_PHASES:
		body=tx("ui.vision_help","Зелёные лучи видят результат. Луч к механизму выдаёт фокус. Зрителю можно выбрать свободное место.") if selected.begins_with("w:") else tx("ui.place_help","Коснись подсвеченного места для предмета. Кнопка ниже откроет его действия.")
	return {"law":law_text,"body":body}
func _text_height(value: String,width: float,font_size: int) -> float:
	# Label shaping includes its own word-boundary and line-spacing rules.
	# Measure the same native control, rather than an approximate Font string box.
	var key: String=str(font_size)+":"+str(width)+":"+value
	if _text_measure_cache.has(key):return _text_measure_cache[key]
	var probe=Label.new();probe.visible=false;probe.theme=theme
	probe.add_theme_font_override("font",get_theme_font("font"));probe.add_theme_font_size_override("font_size",font_size)
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
	ui.position=Vector2(maxf(0,(screen.x-1080)/2),0);ui.size=Vector2(1080,screen.y)
	var text_scale: float=clampf(float(settings.accessibility.text_scale),1.0,1.4)
	var font_size: int=int(42*text_scale)
	var copy: Dictionary=_hud_copy()
	var safe_top: float=40;var safe_bottom: float=40
	if DisplayServer.get_name()!="headless":
		var safe: Rect2i=DisplayServer.get_display_safe_area()
		var window: Vector2i=DisplayServer.window_get_size()
		if window.x>0:safe_top=maxf(40,float(safe.position.y)*screen.x/window.x+16)
		if window.y>0:safe_bottom=maxf(40,float(window.y-safe.end.y)*screen.y/window.y+16)
	var heading: String="%02d   %s" % [level_number,tx(_key("title"),"Новое чудо")]
	var title_h: float=maxf(144,_text_height(heading,804,int(48*text_scale))+16)
	var law_h: float=maxf(108,_text_height(copy.law,924,font_size)+24)
	var instruction_h: float=maxf(144,_text_height(copy.body,916,font_size)+24)
	_layout_law_height=law_h;_layout_instruction_height=instruction_h
	var n: int=kernel.definition.witnesses.size()
	var card_width: float=maxf(972.0/maxi(n,1)-10,316*text_scale)
	var font: Font=get_theme_font("font")
	for wd in kernel.definition.witnesses:
		for word in _character_name(wd.character_id).split(" ",false):card_width=maxf(card_width,font.get_string_size(word,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x+32)
	var name_h: float=0
	for wd in kernel.definition.witnesses:name_h=maxf(name_h,_text_height(_character_name(wd.character_id),card_width-24,font_size))
	var witness_h: float=maxf(144*text_scale,80*text_scale+name_h+16)
	if n==0:witness_h=maxf(144*text_scale,_text_height(tx("ui.no_audience","Закон уже действует. Собери план и проверь последствия."),922,font_size)+24)
	var button_h: float=144*text_scale
	var inventory_h: float=button_h
	for entity in kernel.definition.entities:
		if not entity.movable and entity.properties.get("attachment_kind","").is_empty():continue
		var label_width: float=maxf(80,_inventory_item_width(_name(entity.id),text_scale)-48-64*text_scale-12)
		inventory_h=maxf(inventory_h,_text_height(_wrap_words(_name(entity.id),label_width,font_size),label_width,font_size)+32)
	var tray_h: float=inventory_h+16
	var instruction_y: float=safe_top+title_h+16+law_h+16
	var stage_y: float=instruction_y+instruction_h+16
	var stage_h: float=984.0*2.0/3.0
	var witness_y: float=stage_y+stage_h+16
	var tray_y: float=witness_y+witness_h+16
	var footer_y: float=screen.y-safe_bottom-button_h
	var primary_y: float=footer_y-16-button_h
	var paper=ColorRect.new();paper.position=-ui.position;paper.size=screen;paper.color=CREAM;paper.mouse_filter=MOUSE_FILTER_IGNORE;ui.add_child(paper)
	_upper_scroll=ScrollContainer.new();_upper_scroll.size=Vector2(1080,primary_y-16);_upper_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;_upper_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;ui.add_child(_upper_scroll);_upper_scroll.set_deferred("scroll_vertical",previous_scroll)
	var content=Control.new();content.mouse_filter=MOUSE_FILTER_PASS;content.custom_minimum_size=Vector2(1080,tray_y+tray_h+12);_upper_scroll.add_child(content)
	_text(content,heading,Rect2(54,safe_top,804,title_h),48)
	_button(content,"",Rect2(882,safe_top,144,title_h),_open_settings,false,48,"settings")
	_box(content,Rect2(54,safe_top+title_h+16,972,law_h),Color("e5dded"),22)
	law_label=_text(content,copy.law,Rect2(78,safe_top+title_h+28,924,law_h-24),42,PURPLE)
	stage=reusable_stage if reusable_stage!=null else Stage.new();stage.kernel=kernel;stage.translator=tx;stage.selected=selected;stage.inspected=inspected;stage.position=Vector2(48,stage_y);stage.size=Vector2(984,stage_h);stage.reduced_motion=settings.accessibility.reduced_motion;stage.process_mode=Node.PROCESS_MODE_DISABLED if _app_paused else Node.PROCESS_MODE_INHERIT;content.add_child(stage)
	if not stage.target_tapped.is_connected(_on_target):stage.target_tapped.connect(_on_target)
	_caption_panel=_box(content,Rect2(68,stage_y+stage_h-maxf(132,84*text_scale+40),944,maxf(132,84*text_scale+40)),Color(.99,.96,.87,.94),20)
	_caption_panel.visible=previous_remaining>0 and settings.accessibility.subtitles
	_caption_label=_text(_caption_panel,previous_caption,Rect2(24,12,896,_caption_panel.size.y-24),38)
	_caption_remaining=previous_remaining;_caption_queue=previous_queue
	_box(content,Rect2(54,instruction_y,972,instruction_h),Color("f3e8cf"),24)
	instruction=_text(content,copy.body,Rect2(82,instruction_y+12,916,instruction_h-24),42)
	witness_labels.clear();_audience_scroll=null
	if n==0:
		_box(content,Rect2(54,witness_y,972,witness_h),Color("e5ecdd"),24)
		_text(content,tx("ui.no_audience","Закон уже действует. Собери план и проверь последствия."),Rect2(78,witness_y+12,922,witness_h-24),42,GREEN)
	else:
		var audience_scroll=ScrollContainer.new();_audience_scroll=audience_scroll;audience_scroll.mouse_filter=MOUSE_FILTER_PASS;audience_scroll.position=Vector2(54,witness_y);audience_scroll.size=Vector2(972,witness_h+12);audience_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;audience_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;content.add_child(audience_scroll)
		var audience=HBoxContainer.new();audience.mouse_filter=MOUSE_FILTER_PASS;audience.add_theme_constant_override("separation",10);audience_scroll.add_child(audience)
		for wd in kernel.definition.witnesses:
			var cell=Control.new();cell.mouse_filter=MOUSE_FILTER_PASS;cell.custom_minimum_size=Vector2(card_width,witness_h);audience.add_child(cell)
			_button(cell,"",Rect2(0,0,card_width,witness_h),func():_inspect(wd.id))
			var char_name: String=Stage.CHARACTERS.get(wd.character_id,"crowd_gardener")
			var path: String="res://assets/art/characters/"+char_name+".png"
			var portrait: TextureRect=null
			if ResourceLoader.exists(path):
				portrait=TextureRect.new();portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.custom_minimum_size=Vector2.ZERO
				var tex: Texture2D=load(path);var crop=AtlasTexture.new();crop.atlas=tex;crop.region=Rect2(tex.get_width()*.18,tex.get_height()*.015,tex.get_width()*.64,tex.get_height()*.28);portrait.texture=crop
				portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;portrait.position=Vector2(12,8);portrait.size=Vector2(72,72)*text_scale;portrait.mouse_filter=MOUSE_FILTER_IGNORE;cell.add_child(portrait)
			var status_label: Label=_text(cell,"0%",Rect2(32+72*text_scale,8,card_width-44-72*text_scale,72*text_scale),42)
			var name_label: Label=_text(cell,_character_name(wd.character_id),Rect2(12,80*text_scale,card_width-24,witness_h-80*text_scale-8),42)
			witness_labels[wd.id]={"name":name_label,"status":status_label,"portrait":portrait,"character":char_name}
			if is_instance_valid(portrait):portrait.set_meta("fallback",portrait.texture)
	var inventory=ScrollContainer.new();_inventory_scroll=inventory;inventory.mouse_filter=MOUSE_FILTER_PASS;inventory.position=Vector2(54,tray_y);inventory.size=Vector2(972,tray_h);inventory.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;inventory.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;content.add_child(inventory)
	var row=HBoxContainer.new();row.mouse_filter=MOUSE_FILTER_PASS;row.add_theme_constant_override("separation",12);inventory.add_child(row)
	for entity in kernel.definition.entities:
		if not entity.movable and entity.properties.get("attachment_kind","").is_empty():continue
		var id: String=entity.id
		var item_width: float=_inventory_item_width(_name(id),text_scale)
		var b: Button=_button(row,_name(id),Rect2(0,0,item_width,inventory_h),func():_select(id),false,42)
		b.custom_minimum_size=Vector2(item_width,inventory_h)
		var path: String=stage.asset_path(id)
		if ResourceLoader.exists(path):b.icon=load(path);b.expand_icon=true;b.add_theme_constant_override("icon_max_width",int(64*text_scale));b.add_theme_constant_override("h_separation",12)
		_wrap_button(b)
	primary=_button(ui,"",Rect2(54,primary_y,972,button_h),_primary,true,42,"play")
	_button(ui,tx("ui.undo_short","Откат"),Rect2(54,footer_y,282,button_h),func():_command("Undo"),false,42,"undo")
	_button(ui,tx("ui.hint_short","Совет"),Rect2(352,footer_y,352,button_h),_hint,false,42,"hint")
	_button(ui,tx("ui.plan","План"),Rect2(720,footer_y,306,button_h),_plan_menu,false,42,"rehearsal")
	_flash=ColorRect.new();_flash.size=screen;_flash.color=Color(1,.94,.68,0);_flash.mouse_filter=MOUSE_FILTER_IGNORE;ui.add_child(_flash)
func _process(delta: float) -> void:
	_frame+=1
	if _frame==10:
		if _capture_scroll.begins_with("audience") and is_instance_valid(_audience_scroll):
			_upper_scroll.ensure_control_visible(_audience_scroll)
			if _capture_scroll=="audience_end":_audience_scroll.scroll_horizontal=int(_audience_scroll.get_h_scroll_bar().max_value)
		if _capture_scroll.begins_with("inventory") and is_instance_valid(_inventory_scroll):
			_upper_scroll.ensure_control_visible(_inventory_scroll)
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
	var font_size: int=int(42*float(settings.accessibility.text_scale))
	if _layout_law_height!=maxf(108,_text_height(copy.law,924,font_size)+24) or _layout_instruction_height!=maxf(144,_text_height(copy.body,916,font_size)+24):_build_ui()
	var state: Dictionary=kernel.state
	law_label.text=copy.law
	for wd in kernel.definition.witnesses:
		var w: Dictionary=state.witnesses[wd.id]
		var total: int=0;var required: int=0
		for view in wd.views:total+=mini(int(w.view_progress[view.id]),int(view.clear_ticks));required+=int(view.clear_ticks)
		var suffix: String="✓" if w.eligible_vote else ("!" if w.exposed else "%d%%" % int(100.0*total/maxi(1,required)))
		var card: Dictionary=witness_labels[wd.id]
		var emotion: String="celebrate" if state.phase=="SUCCESS" else ("reveal_react" if w.exposed else ("accept" if w.eligible_vote else ("suspect" if inspected==wd.id else ("observe" if state.phase in ["PERFORMANCE","REHEARSAL"] else "idle"))))
		var portrait_path: String="res://assets/art/characters/portraits/"+card.character+"/"+emotion+".png"
		if is_instance_valid(card.portrait):card.portrait.texture=load(portrait_path) if ResourceLoader.exists(portrait_path) else card.portrait.get_meta("fallback")
		witness_labels[wd.id].name.text=_character_name(wd.character_id)
		witness_labels[wd.id].status.text=suffix
		witness_labels[wd.id].status.add_theme_color_override("font_color",GREEN if w.eligible_vote else INK)
	primary.disabled=false
	var phase: String=state.phase
	audio.set_phase(phase)
	instruction.text=tx(_key("objective"),"Измени план и проверь результат.")
	match phase:
		"PLAN_SHOW":
			primary.text=tx("ui.perform","Показать фокус")
			instruction.text=tx(_key("plan_tip"),instruction.text)
		"PLAN_RESOLUTION":primary.text=tx("ui.execute_plan","Разыграть план")
		"PERFORMANCE","REHEARSAL":
			primary.text=tx("ui.witness_check","Зрители проверяют…");primary.disabled=true
			instruction.text=tx("ui.observation_help","Зрители должны видеть результат. Карточки показывают, кто уже убедился.")
		"PROOF_ACCEPTED":primary.text=tx("ui.seal","Закрепить чудо");instruction.text=tx("ui.proof_accepted","Они поверили! Печать сделает чудо новым законом этой сцены.")
		"LAW_SELECTION":primary.text=tx("ui.replace_law","Выбрать замену закону")
		"RUN_RESOLUTION":
			primary.text=tx("ui.stop_resolution","Вернуться к плану")
			var waiting: bool=false
			for task in state.routes.values():waiting=waiting or not str(task.get("waiting_for","")).is_empty()
			instruction.text=tx("ui.wait_water","Ждём замерзания или оттаивания. Персонажи стоят на безопасном месте.") if waiting else tx("ui.world_acts","Мир действует по новым правилам. Можно остановить время после завершения путей.")
		"RECOVERABLE_FAILURE":primary.text=tx("ui.back_to_plan","Вернуться к плану");instruction.text=_reason(state.get("failure_reason",""))
		"SUCCESS":primary.text=tx("ui.next","Следующее чудо")
	if not selected.is_empty() and phase in Kernel.PLAN_PHASES:
		if selected.begins_with("w:"):instruction.text=tx("ui.vision_help","Зелёные лучи видят результат. Луч к механизму выдаёт фокус. Зрителю можно выбрать свободное место.")
		else:primary.text=tx("ui.prop_actions","Действия");instruction.text=tx("ui.place_help","Коснись подсвеченного места для предмета. Кнопка ниже откроет его действия.")
	instruction.text=copy.body
	_wrap_button(primary)
func _primary() -> void:
	var state: Dictionary=kernel.state
	if state.phase in Kernel.PLAN_PHASES and not selected.is_empty() and not selected.begins_with("w:"):_object_menu(selected);return
	match state.phase:
		"PLAN_SHOW":_command("BeginPerformance")
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
	_close_overlay();overlay=Control.new();overlay.size=Vector2(1080,1920);overlay.position=(get_viewport_rect().size-overlay.size)/2;add_child(overlay)
	var shade=ColorRect.new();shade.position=-overlay.position;shade.size=get_viewport_rect().size;shade.color=Color(.1,.08,.15,.68);overlay.add_child(shade)
	_box(overlay,Rect2(54,160,972,1600),CREAM,36)
	var font_size: int=int(54*float(settings.accessibility.text_scale))
	var wrapped: String=_wrap_words(title,864,font_size)
	var title_height: float=maxf(120,(wrapped.count("\n")+1)*font_size*1.24)
	_text(overlay,wrapped,Rect2(108,208,864,title_height),54,PURPLE)
	_sheet_content_top=maxf(366,208+title_height+32)
	return overlay
func _modal(title: String,body: String,confirm: String,callback: Callable) -> void:
	_sheet(title)
	var scroll=ScrollContainer.new();scroll.position=Vector2(108,_sheet_content_top);scroll.size=Vector2(864,1480-_sheet_content_top);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;overlay.add_child(scroll)
	var label: Label=_text(scroll,body,Rect2(0,0,842,0),48);label.custom_minimum_size=Vector2(842,0)
	_button(overlay,confirm,Rect2(108,1536,864,144),func():_close_overlay();callback.call(),true,40)
func _choices(title: String,choices: Array) -> void:
	_sheet(title)
	var scroll=ScrollContainer.new();scroll.position=Vector2(108,_sheet_content_top);scroll.size=Vector2(864,1486-_sheet_content_top);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;overlay.add_child(scroll)
	var rows=VBoxContainer.new();rows.mouse_filter=MOUSE_FILTER_PASS;rows.custom_minimum_size=Vector2(842,0);rows.add_theme_constant_override("separation",16);scroll.add_child(rows)
	for choice in choices:
		var b: Button=_button(rows,choice.label,Rect2(0,0,842,144),func():_close_overlay();choice.action.call(),choice.get("primary",false),42)
		b.custom_minimum_size=Vector2(842,maxf(144,(b.text.count("\n")+1)*b.get_theme_font_size("font_size")*1.25+32))
	_button(overlay,tx("ui.close","Вернуться"),Rect2(108,1536,864,144),_dismiss_overlay,true,42)
func _toast(message: String) -> void:_modal(tx("ui.plum_help","Плам подсказывает"),message,tx("ui.understood","Понятно"),func():pass)
func _briefing() -> void:_modal(tx(_key("title"),"Новое чудо"),tx(_key("intro"),"Сначала поставь фокус. Затем преврати его в настоящий закон.")+"\n\n"+tx(_key("objective"),""),tx("ui.begin","За работу"),func():audio.play("voice_felix","Voice"))
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
		choices.append({"label":tx("ui.assign_route","Назначить маршрут…"),"action":_actor_menu})
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
	_save_progress();_modal(tx("ui.victory","Чудо принято!"),tx(_key("success"),"Мир стал немного невозможнее.")+"\n\n"+tx(_key("joke"),"")+"\n\n★ "+tx("ui.main_goal_done","Основная цель выполнена"),tx("ui.next","Следующее чудо"),_next_level)
func _next_level() -> void:
	if level_number<level_ids.size():start_level(level_number+1)
	else:_show_credits()
func _open_levels() -> void:
	audio.play_music("music_album")
	_sheet(tx("ui.album","Альбом невозможного"))
	_text(overlay,tx("ui.level_select_help","Каждый эксперимент можно повторить бесплатно."),Rect2(108,340,864,100),36)
	for i in range(level_ids.size()):
		var n: int=i+1;var x: float=108+(i%5)*174;var y: float=470+int(i/5)*158
		var label: String=str(n)+( " ★" if progress.completed.has(level_ids[i]) else "")
		var b: Button=_button(overlay,label,Rect2(x,y,154,144),func():_front_menu=false;_close_overlay();start_level(n),n==level_number,42)
		b.disabled=n>int(progress.get("unlocked",1)) or _invalid_levels.has(level_ids[i])
	_button(overlay,tx("ui.back_game","Вернуться в игру"),Rect2(108,1536,864,144),_dismiss_overlay,true,39)
func _toggle(parent: Control,label: String,rect: Rect2,value: bool,callback: Callable) -> CheckButton:
	var check=CheckButton.new();check.mouse_filter=MOUSE_FILTER_PASS;check.text=label;check.position=rect.position;check.size=rect.size;check.button_pressed=value
	check.add_theme_font_size_override("font_size",int(42*float(settings.accessibility.text_scale)))
	check.add_theme_icon_override("checked",load("res://presentation/resources/toggle_on.svg"));check.add_theme_icon_override("unchecked",load("res://presentation/resources/toggle_off.svg"))
	for color_name in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_disabled_color"]:check.add_theme_color_override(color_name,INK)
	parent.add_child(check);check.toggled.connect(callback);return check
func _open_settings() -> void:
	_sheet(tx("ui.settings","Настройки"))
	var scroll=ScrollContainer.new();scroll.position=Vector2(108,350);scroll.size=Vector2(864,1160);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;overlay.add_child(scroll)
	var rows=VBoxContainer.new();rows.mouse_filter=MOUSE_FILTER_PASS;rows.custom_minimum_size=Vector2(840,0);rows.add_theme_constant_override("separation",16);scroll.add_child(rows)
	var toggles=Control.new();toggles.mouse_filter=MOUSE_FILTER_PASS;toggles.custom_minimum_size=Vector2(840,288);rows.add_child(toggles)
	_toggle(toggles,tx("ui.all_sound","Весь звук"),Rect2(0,0,840,144),not settings.audio.master_muted,func(v):settings.audio.master_muted=not v;_apply_audio())
	_toggle(toggles,tx("ui.sound","Звуки"),Rect2(0,144,840,144),settings.audio.sound_enabled,func(v):settings.audio.sound_enabled=v;_apply_audio())
	var cats: Array=["Master","Music","SFX","Ambience","Voice","UI"]
	var cat_names: Array=[tx("ui.volume","Общая громкость"),tx("ui.music","Музыка"),tx("ui.sfx","Эффекты"),tx("ui.ambience","Окружение"),tx("ui.voice","Голоса"),tx("ui.interface","Интерфейс")]
	for i in range(cats.size()):
		var category: String=cats[i]
		var card=Control.new();card.mouse_filter=MOUSE_FILTER_PASS
		var label_width: float=840 if category=="Master" else 580
		var heading_height: float=_text_height(cat_names[i],label_width,int(42*float(settings.accessibility.text_scale)))
		var slider_y: float=maxf(144,heading_height)+16
		card.custom_minimum_size=Vector2(840,slider_y+160);rows.add_child(card)
		_text(card,cat_names[i],Rect2(0,0,label_width,maxf(82,heading_height)),42)
		if category!="Master":_toggle(card,tx("ui.enabled","Вкл"),Rect2(600,0,240,144),settings.audio.categories[category].enabled,func(v):settings.audio.categories[category].enabled=v;_apply_audio())
		var slider=HSlider.new();slider.position=Vector2(8,slider_y);slider.size=Vector2(620,144);slider.min_value=0;slider.max_value=1;slider.step=.01;slider.add_theme_icon_override("grabber",load("res://presentation/resources/slider_knob.svg"));slider.add_theme_icon_override("grabber_highlight",load("res://presentation/resources/slider_knob.svg"));slider.value=settings.audio.master_volume if category=="Master" else settings.audio.categories[category].volume;card.add_child(slider)
		var percent: Label=_text(card,"%d%%" % int(slider.value*100),Rect2(638,slider_y+32,202,96),42)
		slider.value_changed.connect(func(v):
			if category=="Master":settings.audio.master_volume=v
			else:settings.audio.categories[category].volume=v
			percent.text="%d%%" % int(v*100);_apply_audio())
	var access=Control.new();access.mouse_filter=MOUSE_FILTER_PASS;access.custom_minimum_size=Vector2(840,432);rows.add_child(access)
	_toggle(access,tx("ui.reduced_motion","Уменьшить движение"),Rect2(0,0,840,144),settings.accessibility.reduced_motion,_set_reduced_motion)
	_toggle(access,tx("ui.subtitles","Субтитры"),Rect2(0,144,840,144),settings.accessibility.subtitles,_set_subtitles)
	_toggle(access,tx("ui.haptics","Вибрация"),Rect2(0,288,840,144),settings.accessibility.haptics,func(v):settings.accessibility.haptics=v;saver.write_slot("settings",settings))
	var scale_row=HBoxContainer.new();scale_row.mouse_filter=MOUSE_FILTER_PASS;rows.add_child(scale_row)
	for scale_value in [1.0,1.2,1.4]:
		var b: Button=_button(scale_row,"%d%%" % int(scale_value*100),Rect2(0,0,268,144),func():settings.accessibility.text_scale=scale_value;saver.write_slot("settings",settings);_build_ui();_update_ui();_open_settings(),false,42)
		b.custom_minimum_size=Vector2(272,144)
	var lang: Button=_button(rows,tx("ui.language","Язык")+": "+settings.locale.to_upper(),Rect2(0,0,840,144),func():settings.locale="en" if settings.locale=="ru" else "ru";_load_catalog();saver.write_slot("settings",settings);_build_ui();_update_ui();_open_settings(),false,42);lang.custom_minimum_size=Vector2(840,144)
	var restart: Button=_button(rows,tx("ui.restart","Заново"),Rect2(0,0,840,144),func():_close_overlay();_command("Restart"),false,42);restart.custom_minimum_size=Vector2(840,144)
	var album: Button=_button(rows,tx("ui.album","Альбом уровней"),Rect2(0,0,840,144),_open_levels,false,42);album.custom_minimum_size=Vector2(840,144)
	_button(overlay,tx("ui.back_game","Вернуться в игру"),Rect2(108,1576,864,144),_dismiss_overlay,true,42)
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
	if is_instance_valid(audio):audio.shutdown()
	await get_tree().create_timer(.15).timeout
	get_tree().quit()
func _prepare_capture() -> void:
	_close_overlay();kernel.load_level(_json("res://data/levels/"+level_ids[level_number-1]+".json"),48121)
	if _capture_stage=="title":_show_title()
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
	overlay=Control.new();overlay.size=Vector2(1080,1920);overlay.position=(get_viewport_rect().size-overlay.size)/2;add_child(overlay)
	var background=TextureRect.new();background.position=Vector2.ZERO;background.size=overlay.size;background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;background.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;background.mouse_filter=MOUSE_FILTER_IGNORE
	var bg_path: String="res://assets/art/environments/bg_river.png"
	if ResourceLoader.exists(bg_path):background.texture=load(bg_path)
	overlay.add_child(background)
	_box(overlay,Rect2(54,80,972,520),Color(.99,.96,.87,.94),36)
	_text(overlay,tx("ui.game_title","ПОЧТИ БОГ"),Rect2(108,130,864,190),90,PURPLE)
	_text(overlay,tx("ui.title_subtitle","Маленькое чудо.
Большие последствия."),Rect2(108,338,864,172),52)
	for item in [{"name":"felix","rect":Rect2(90,660,460,680)},{"name":"plum","rect":Rect2(570,690,200,180)}]:
		var path: String="res://assets/art/characters/"+item.name+".png"
		if not ResourceLoader.exists(path):continue
		var figure=TextureRect.new();figure.position=item.rect.position;figure.size=item.rect.size;figure.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;figure.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;figure.texture=load(path);figure.mouse_filter=MOUSE_FILTER_IGNORE;overlay.add_child(figure)
	_box(overlay,Rect2(54,1280,972,570),Color(.99,.96,.87,.96),36)
	_button(overlay,tx("ui.play","Играть"),Rect2(108,1320,864,144),_enter_game,true,52,"play")
	_button(overlay,tx("ui.album","Альбом уровней"),Rect2(108,1490,864,144),_open_levels,false,44)
	_button(overlay,tx("ui.settings","Настройки"),Rect2(108,1660,864,144),_open_settings,false,44,"settings")
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
	_briefing()

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
	button.text=_wrap_words(button.text,maxf(80,button.size.x-48-icon_space),button.get_theme_font_size("font_size"))
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
	_caption_label.text=_caption_queue.pop_front();_caption_panel.visible=true;_caption_remaining=2.2
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
	var widest: float=0
	for word in label.split(" "):widest=maxf(widest,font.get_string_size(word,HORIZONTAL_ALIGNMENT_LEFT,-1,int(42*scale_value)).x)
	return maxf(316*scale_value,widest+124*scale_value)
