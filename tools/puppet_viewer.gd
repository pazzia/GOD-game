extends Control
## Native production review scene, deliberately absent from the player menu.
const Puppet=preload("res://presentation/character_puppet.gd")
const ACTORS=["felix","plum","marfa","semyon","nika","lada","roza","hugo","caramelka"]
const NAMES=["Феликс","Плюм","Марфа","Семён","Ника","Лада","Роза","Гуго","Карамелька"]
var puppets: Array=[]
var choice: OptionButton
var capture_path: String=""
var frame: int=0
var sheet_actor: String=""
var sheet_phase: float=.35
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sheet-actor="):sheet_actor=arg.trim_prefix("--sheet-actor=")
		if arg.begins_with("--sheet-phase="):sheet_phase=clampf(arg.trim_prefix("--sheet-phase=").to_float(),0,.999)
	get_window().content_scale_size=Vector2i(1600,1000);get_window().size=Vector2i(1600,1000)
	var t=Theme.new();t.default_font=load("res://assets/fonts/DejaVuSans.ttf");t.default_font_size=19;theme=t
	var bg=ColorRect.new();bg.color=Color("fff5de");bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT);add_child(bg)
	var title=Label.new();title.text="ПОЧТИ БОГ  ·  ПРОВЕРКА ПЕРСОНАЖЕЙ";title.position=Vector2(32,16);title.add_theme_color_override("font_color",Color("25243b"));add_child(title)
	choice=OptionButton.new();choice.position=Vector2(650,16);choice.size=Vector2(240,44)
	for state in Puppet.BASE_STATES+Puppet.EXTRA_STATES:choice.add_item(state)
	choice.item_selected.connect(func(i):set_pose(choice.get_item_text(i)));add_child(choice)
	var motion=CheckButton.new();motion.position=Vector2(930,16);motion.size=Vector2(290,44);motion.text="Reduced motion";motion.add_theme_color_override("font_color",Color("25243b"));motion.toggled.connect(func(v):
		for p in puppets:p.set_reduced_motion(v))
	add_child(motion)
	var flip=Button.new();flip.position=Vector2(1270,16);flip.size=Vector2(290,44);flip.text="Повернуть направление";flip.pressed.connect(func():
		for p in puppets:p.set_facing(-p.facing))
	add_child(flip)
	for i in range(ACTORS.size()):
		var x: float=32+(i%3)*520;var y: float=82+int(i/3)*300
		var card=Panel.new();card.position=Vector2(x,y);card.size=Vector2(496,280)
		var style=StyleBoxFlat.new();style.bg_color=Color("eee2c7");style.set_corner_radius_all(20);card.add_theme_stylebox_override("panel",style);add_child(card)
		var p=Puppet.new();p.position=Vector2(x+248,y+225);add_child(p)
		var actor: String=ACTORS[i] if sheet_actor.is_empty() else sheet_actor
		var height: float=184
		if actor=="plum":height=140
		elif actor=="caramelka":height=140
		p.configure(actor,height);puppets.append(p)
		var label=Label.new();label.position=Vector2(x+18,y+228);label.size=Vector2(460,42);label.add_theme_color_override("font_color",Color("25243b"));label.text=NAMES[i]+(" · раздельные части" if p.rigged else " · базовый спрайт")
		if not sheet_actor.is_empty():
			var state: String=(Puppet.BASE_STATES+["stamp"])[i];p.play_state(state,true)
			p.animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			p.animator.seek(p.animator.current_animation_length*sheet_phase,true)
			label.text=sheet_actor+" · "+state+" · "+str(roundi(sheet_phase*100))+"%"
		add_child(label)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):capture_path=arg.trim_prefix("--capture=")
		if arg.begins_with("--pose="):set_pose(arg.trim_prefix("--pose="))
func set_pose(state: String) -> void:
	for p in puppets:p.play_state(state,true)
	for i in range(choice.item_count):
		if choice.get_item_text(i)==state:choice.select(i)
func _process(_delta: float) -> void:
	frame+=1
	if not capture_path.is_empty() and frame==36:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture_path)
		get_tree().quit()
