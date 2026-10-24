extends Control
## Separate developer scene. There is deliberately no link from the player's menu.
const Model=preload("res://tools/workbench_model.gd")
const Stage=preload("res://presentation/stage_view.gd")
const Overlay=preload("res://tools/workbench_overlay.gd")
var model=Model.new()
var stage: Control
var geometry: Control
var mode: String="slots"
var selection: Dictionary={}
var list: ItemList
var level_picker: OptionButton
var mode_picker: OptionButton
var witness_picker: OptionButton
var x: SpinBox
var y: SpinBox
var target_label: Label
var state_label: Label
var diagnostic_label: Label
var trace_label: Label
var log_view: TextEdit
var status: Label
var before_button: Button
var after_button: Button
var _updating: bool=false
var _play: bool=false
var _accumulator: float=0
var _capture: String=""
var _frame: int=0
var _pending_export: String=""
func _ready() -> void:
	get_window().content_scale_size=Vector2i(1600,1000);get_window().size=Vector2i(1600,1000)
	var t=Theme.new();t.default_font=load("res://assets/fonts/DejaVuSans.ttf");t.default_font_size=17;theme=t
	_build_ui()
	var number: int=1;var steps: int=0;var run_all: bool=false;var witness: String="";var comparison: String="live";var geometry_mode: String="slots"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):number=clampi(arg.trim_prefix("--level=").to_int(),1,30)
		if arg.begins_with("--replay-step="):steps=maxi(0,arg.trim_prefix("--replay-step=").to_int())
		if arg=="--run-canonical":run_all=true
		if arg.begins_with("--capture="):_capture=arg.trim_prefix("--capture=")
		if arg.begins_with("--witness="):witness=arg.trim_prefix("--witness=")
		if arg.begins_with("--mode="):geometry_mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--compare="):comparison=arg.trim_prefix("--compare=")
	level_picker.select(number-1);_load_level(number)
	for i in range(steps):
		if not model.step_replay():break
	if run_all:model.run_canonical()
	if geometry_mode in ["slots","result_anchors","method_anchors","occluders"]:
		mode=geometry_mode;mode_picker.select(["slots","result_anchors","method_anchors","occluders"].find(mode));_refresh_targets()
	for i in range(1,witness_picker.item_count):
		if witness_picker.get_item_metadata(i)==witness:witness_picker.select(i);break
	if comparison!="live":model.show_law_comparison(comparison)
	_refresh()
func _build_ui() -> void:
	var bg=ColorRect.new();bg.color=Color("eeebe4");bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT);add_child(bg)
	var margin=MarginContainer.new();margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+edge,14)
	add_child(margin)
	var root_box=VBoxContainer.new();root_box.add_theme_constant_override("separation",10);margin.add_child(root_box)
	var header=HBoxContainer.new();root_box.add_child(header)
	var title=_label("ПОЧТИ БОГ  /  МАСТЕРСКАЯ УРОВНЕЙ",25);title.size_flags_horizontal=SIZE_EXPAND_FILL;header.add_child(title)
	header.add_child(_label("DEV ONLY",15))
	level_picker=OptionButton.new()
	for i in range(1,31):level_picker.add_item("L%02d"%i,i)
	level_picker.item_selected.connect(func(index):_load_level(index+1));header.add_child(level_picker)
	_button(header,"Открыть JSON",_open_dialog);_button(header,"Проверить",func():model.validation_errors();_refresh());_button(header,"Экспорт JSON…",_save_dialog)
	status=_label("",16);root_box.add_child(status)
	var main=HBoxContainer.new();main.size_flags_vertical=SIZE_EXPAND_FILL;main.add_theme_constant_override("separation",14);root_box.add_child(main)
	var left=VBoxContainer.new();left.size_flags_horizontal=SIZE_EXPAND_FILL;left.size_flags_stretch_ratio=2;main.add_child(left)
	var tools=HBoxContainer.new();left.add_child(tools)
	mode_picker=OptionButton.new()
	for text in ["Слоты","Точки результата","Точки механизма","Отрезки преград"]:mode_picker.add_item(text)
	mode_picker.item_selected.connect(func(index):mode=["slots","result_anchors","method_anchors","occluders"][index];_refresh_targets());tools.add_child(mode_picker)
	_button(tools,"↶ Undo",func():model.undo();_refresh_targets());_button(tools,"↷ Redo",func():model.redo();_refresh_targets())
	var note=_label("Перетащите маркер: целая сетка. Ctrl+Z — откат. Переграды имеют абсолютные координаты.",14);note.size_flags_horizontal=SIZE_EXPAND_FILL;tools.add_child(note)
	var frame=Control.new();frame.custom_minimum_size=Vector2(972,740);frame.size_flags_vertical=SIZE_EXPAND_FILL;left.add_child(frame)
	stage=Stage.new();stage.set_anchors_and_offsets_preset(PRESET_FULL_RECT);stage.kernel=model.kernel;stage.reduced_motion=true;frame.add_child(stage);stage.mouse_filter=MOUSE_FILTER_IGNORE
	geometry=Overlay.new();geometry.workbench=self;geometry.set_anchors_and_offsets_preset(PRESET_FULL_RECT);frame.add_child(geometry)
	var footer=_label("Рисунок: настоящий StageView. Сетка/лучи: авторитетная геометрия ядра. Редактор не сохраняет игровой прогресс.",14);left.add_child(footer)
	var side=VBoxContainer.new();side.custom_minimum_size.x=450;side.add_theme_constant_override("separation",9);main.add_child(side)
	side.add_child(_label("АВТОРСКИЕ ДАННЫЕ",20))
	list=ItemList.new();list.custom_minimum_size=Vector2(450,180);list.size_flags_vertical=SIZE_EXPAND_FILL;list.item_selected.connect(func(index):select_target(list.get_item_metadata(index)));side.add_child(list)
	target_label=_label("Выберите маркер",16);side.add_child(target_label)
	var xy=HBoxContainer.new();side.add_child(xy);xy.add_child(_label("X"));x=SpinBox.new();x.min_value=0;x.max_value=24;x.step=1;x.custom_minimum_size.x=90;xy.add_child(x)
	xy.add_child(_label("Y"));y=SpinBox.new();y.min_value=0;y.max_value=28;y.step=1;y.custom_minimum_size.x=90;xy.add_child(y)
	_button(xy,"Применить XY",func():apply_point([int(x.value),int(y.value)]))
	var semantic=_label("Anchor хранится как offset от предмета в текущем preview. Сдвиг слота НЕ двигает абсолютный occluder.",14);semantic.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;semantic.custom_minimum_size.y=46;side.add_child(semantic)
	side.add_child(_label("ПРОВЕРКА СВИДЕТЕЛЯ",19));witness_picker=OptionButton.new();witness_picker.item_selected.connect(func(_index):_refresh());side.add_child(witness_picker)
	diagnostic_label=_label("",15);diagnostic_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;diagnostic_label.custom_minimum_size.y=64;side.add_child(diagnostic_label)
	side.add_child(_label("КАНОНИЧЕСКИЙ TRACE",19));var replay_row=HBoxContainer.new();side.add_child(replay_row)
	_button(replay_row,"Начало",func():model.reset_preview();_refresh());_button(replay_row,"Шаг trace",func():model.step_replay();_refresh());_button(replay_row,"Весь trace",func():model.run_canonical();_refresh())
	var ticks=HBoxContainer.new();side.add_child(ticks)
	_button(ticks,"Такт +1",func():model.advance_ticks(1);_refresh());_button(ticks,"+10",func():model.advance_ticks(10);_refresh());_button(ticks,"▶ / Пауза",func():_play=not _play)
	state_label=_label("",16);state_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;side.add_child(state_label)
	trace_label=_label("",14);trace_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;trace_label.custom_minimum_size.y=62;side.add_child(trace_label)
	var compare=HBoxContainer.new();side.add_child(compare)
	before_button=_button(compare,"ДО закона",func():model.show_law_comparison("before");_refresh());after_button=_button(compare,"ПОСЛЕ",func():model.show_law_comparison("after");_refresh());_button(compare,"Live",func():model.show_law_comparison("live");_refresh())
	log_view=TextEdit.new();log_view.editable=false;log_view.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;log_view.custom_minimum_size=Vector2(450,140);log_view.size_flags_vertical=SIZE_EXPAND_FILL
	var log_style=StyleBoxFlat.new();log_style.bg_color=Color("faf8f2");log_style.border_color=Color("c9c6bc");log_style.set_border_width_all(1);log_style.content_margin_left=8;log_style.content_margin_top=6
	log_view.add_theme_stylebox_override("read_only",log_style);log_view.add_theme_color_override("font_readonly_color",Color("29283c"));side.add_child(log_view)
func _load_level(number: int) -> void:
	model.load_file("res://data/levels/L%02d.json"%number);selection.clear();_play=false;_refresh_targets();_refresh_witnesses();_refresh()
func _refresh_targets() -> void:
	list.clear();selection.clear()
	for target in model.targets(mode):var i: int=list.add_item(target.label);list.set_item_metadata(i,target)
	if list.item_count>0:list.select(0);select_target(list.get_item_metadata(0))
	_refresh()
func _refresh_witnesses() -> void:
	witness_picker.clear();witness_picker.add_item("Без лучей")
	for w in model.definition.get("witnesses",[]):witness_picker.add_item(w.id+" • "+w.character_id);witness_picker.set_item_metadata(witness_picker.item_count-1,w.id)
func select_target(target: Dictionary) -> void:
	selection=target.duplicate(true)
	for i in range(list.item_count):
		if list.get_item_metadata(i)==target:list.select(i);break
	var point: Array=model.target_point(selection)
	if point.size()==2:x.value=point[0];y.value=point[1]
	target_label.text=selection.get("label","")+" • "+str(point)
	geometry.queue_redraw()
func apply_point(point: Array) -> void:
	if selection.is_empty():return
	model.move_target(selection,point);_refresh()
	if not selection.is_empty():select_target(selection)
func _refresh() -> void:
	if stage==null or model.definition.is_empty():return
	var view: RefCounted=model.visible_kernel();stage.kernel=view
	var wid: String=str(witness_picker.get_item_metadata(witness_picker.selected)) if witness_picker.selected>0 else ""
	stage.inspected=wid
	if not wid.is_empty():
		var d: Dictionary=view.visibility_for(wid);var w: Dictionary=view.state.witnesses[wid]
		diagnostic_label.text="Result %d/3 • method %s • %s\nviews %s • vote %s"%[d.visible_results,str(d.method_visible),w.status,JSON.stringify(w.view_progress),str(w.eligible_vote)]
	else:diagnostic_label.text="Выберите свидетеля: лучи совпадают с runtime. Камера редактора на его обзор не влияет."
	state_label.text="%s  • tick %d  • laws %s"%[view.state.phase,view.state.tick,JSON.stringify(view.state.active_laws)]
	var steps: Array=model.replay.get("steps",[])
	trace_label.text="Trace %d/%d\n%s"%[model.replay_cursor,steps.size(),JSON.stringify(steps[model.replay_cursor]) if model.replay_cursor<steps.size() else "Конец trace"]
	before_button.disabled=model.before_law.is_empty();after_button.disabled=model.after_law.is_empty()
	status.text=model.source_path+"  • content "+model.definition.content_version+"  • status "+model.definition.status
	log_view.text="\n".join(model.last_errors) if not model.last_errors.is_empty() else model.last_action+"\n\n"+JSON.stringify(model.last_events,"  ")
	stage.queue_redraw();geometry.queue_redraw()
func _process(delta: float) -> void:
	_frame+=1
	if not _capture.is_empty() and _frame==12:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_capture);get_tree().quit()
	if _play and not model.definition.is_empty():
		_accumulator+=delta
		while _accumulator>=.1:
			_accumulator-=.1;model.advance_ticks(1)
			if model.kernel.state.phase not in model.kernel.ACTIVE_PHASES:_play=false;break
		_refresh()
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode==KEY_Z:model.undo();_refresh_targets();get_viewport().set_input_as_handled()
		elif event.keycode==KEY_F6:model.step_replay();_refresh();get_viewport().set_input_as_handled()
func _open_dialog() -> void:
	var d=FileDialog.new();d.access=FileDialog.ACCESS_FILESYSTEM;d.file_mode=FileDialog.FILE_MODE_OPEN_FILE;d.filters=PackedStringArray(["*.json ; Level JSON"]);add_child(d)
	d.file_selected.connect(func(path):open_author_file(path);d.queue_free())
	d.canceled.connect(d.queue_free);d.popup_centered_ratio(.7)
func open_author_file(path: String) -> bool:
	var accepted: bool=model.load_file(path)
	if accepted:
		selection.clear();_play=false;_accumulator=0
		_refresh_targets();_refresh_witnesses()
	_refresh() # Invalid imports must report their errors while retaining the prior scene.
	return accepted
func _save_dialog() -> void:
	if not model.validation_errors().is_empty():_refresh();return
	var d=FileDialog.new();d.access=FileDialog.ACCESS_FILESYSTEM;d.file_mode=FileDialog.FILE_MODE_SAVE_FILE;d.filters=PackedStringArray(["*.json ; Level JSON"]);d.current_file=model.definition.level_id+".json";add_child(d)
	d.file_selected.connect(func(path):_confirm_export(path);d.queue_free());d.canceled.connect(d.queue_free);d.popup_centered_ratio(.7)
func _confirm_export(path: String) -> void:
	_pending_export=path
	var confirm=ConfirmationDialog.new();confirm.title="Сохранить авторский JSON";confirm.dialog_text="Валидатор не нашёл ошибок.\n"+path+"\nПредыдущий пригодный файл будет сохранён как .bak.\nГеометрия меняется только явными авторскими действиями.";add_child(confirm)
	confirm.confirmed.connect(func():model.export_json(_pending_export);_refresh();confirm.queue_free());confirm.canceled.connect(confirm.queue_free);confirm.popup_centered(Vector2i(720,270))
func _label(text: String,font_size: int=17) -> Label:
	var label=Label.new();label.text=text;label.add_theme_font_size_override("font_size",font_size);label.add_theme_color_override("font_color",Color("25243b"));return label
func _button(parent: Control,text: String,callback: Callable) -> Button:
	var b=Button.new();b.text=text;b.custom_minimum_size.y=36;b.pressed.connect(callback);parent.add_child(b);return b
