extends SceneTree
## Native rendered-pixel regression for rig z-order; colored fixtures are not character art.
const Puppet=preload("res://presentation/character_puppet.gd")
var count: int=0
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.content_scale_size=Vector2i(400,250);root.size=Vector2i(400,250)
	var background=ColorRect.new();background.color=Color.WHITE;background.size=Vector2(400,250);root.add_child(background)
	var p=Puppet.new();root.add_child(p)
	var data: Dictionary={"canvas_size":[100,100],"feet_origin":[0,0],"nominal_height":100,"parts":[
		{"id":"leg","file":"felix.png","position":[0,0],"pivot":[0,0],"target_height":20,"z_index":-20,"parent":null},
		{"id":"torso","file":"felix.png","position":[20,0],"pivot":[0,0],"target_height":20,"z_index":0,"parent":null},
		{"id":"head","file":"felix.png","position":[40,0],"pivot":[0,0],"target_height":20,"z_index":10,"parent":null}]}
	check(p.configure_definition(data,"res://assets/art/characters/","felix",100),"flat layer fixture loads")
	p.position=Vector2(100,100);p.animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;p.play_state("idle",true);p.animator.seek(0,true)
	var colors: Dictionary={"leg":Color.RED,"torso":Color.BLUE,"head":Color.GREEN}
	for record in p._render_parts:
		var img=Image.create(20,20,false,Image.FORMAT_RGBA8);img.fill(colors[record.bone.name])
		record.sprite.texture=ImageTexture.create_from_image(img);record.sprite.scale=Vector2.ONE;record.sprite.position=Vector2.ZERO
	var modal=ColorRect.new();modal.color=Color.CYAN;modal.position=Vector2(140,100);modal.size=Vector2(20,20);root.add_child(modal)
	p.queue_redraw()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var frame: Image=root.get_texture().get_image()
	check(near(frame.get_pixel(105,105),Color.RED),"negative internal leg z remains visible above previously drawn stage background")
	check(near(frame.get_pixel(125,105),Color.BLUE),"bone and sprite transforms draw torso at actual authored location")
	check(near(frame.get_pixel(145,105),Color.CYAN),"positive internal head z cannot escape puppet group above later modal overlay")
	p.set_facing(-1);modal.hide();p.queue_redraw()
	await process_frame;await RenderingServer.frame_post_draw
	frame=root.get_texture().get_image()
	check(near(frame.get_pixel(95,105),Color.RED) and near(frame.get_pixel(75,105),Color.BLUE) and near(frame.get_pixel(55,105),Color.GREEN),"actual draw transform mirrors all parts and preserves group position")
	frame.save_png("res://build/puppet-layer-order.png")
	print("PUPPET NATIVE: %d checks; %d failures"%[count,failures.size()])
	for issue in failures:printerr("FAIL: "+issue)
	var f=FileAccess.open("res://tests/reports/puppet-native.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":count,"failures":failures,"engine":Engine.get_version_info().string,"native_rendered_pixels":true,"fixture":"colored blocks, not finished character art","art_acceptance":false},"  "));f.close()
	p.queue_free();modal.queue_free();background.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
func near(actual: Color,wanted: Color) -> bool:return absf(actual.r-wanted.r)<.02 and absf(actual.g-wanted.g)<.02 and absf(actual.b-wanted.b)<.02
func check(condition: bool,message: String) -> void:
	count+=1
	if not condition:failures.append(message)
