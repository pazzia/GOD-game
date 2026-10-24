extends Control
## Logical geometry painted over the production StageView; no duplicate visibility implementation.
var workbench: Control
var dragging: bool=false
var ghost: Array=[]
var _font: Font=preload("res://assets/fonts/DejaVuSans.ttf")
func _ready() -> void:mouse_filter=MOUSE_FILTER_STOP;clip_contents=true
func _process(_delta: float) -> void:queue_redraw()
func pixel(point: Array) -> Vector2:return workbench.stage.world(point)
func grid(point: Vector2) -> Array:
	return [clampi(roundi((point.x-20)/38.0),0,24),clampi(roundi((point.y-36)*28.0/maxf(1,size.y-100)),0,28)]
func _draw() -> void:
	if workbench==null or workbench.model.definition.is_empty():return
	for x in range(25):draw_line(pixel([x,0]),pixel([x,28]),Color(.12,.15,.22,.13),1)
	for y in range(29):draw_line(pixel([0,y]),pixel([24,y]),Color(.12,.15,.22,.13),1)
	for occ in workbench.model.definition.occluders:
		draw_line(pixel(occ.segment[0]),pixel(occ.segment[1]),Color(.9,.48,.08,.9),4,true)
	for target in workbench.model.targets(workbench.mode):
		var point: Array=workbench.model.target_point(target)
		if point.is_empty():continue
		var pos: Vector2=pixel(point)
		var active: bool=target==workbench.selection
		var color: Color=Color("5642a2") if target.kind=="slot" else (Color("b6474c") if target.get("group","")=="method_anchors" else Color("17785a"))
		if target.kind=="occluder":color=Color("bc681b")
		draw_circle(pos,10 if active else 6,Color(1,1,.96,.95));draw_arc(pos,11 if active else 7,0,TAU,24,color,3,true)
		draw_line(pos-Vector2(14,0),pos+Vector2(14,0),color,1);draw_line(pos-Vector2(0,14),pos+Vector2(0,14),color,1)
		if active:draw_string(_font,pos+Vector2(15,-13),target.label+" "+str(point),HORIZONTAL_ALIGNMENT_LEFT,-1,17,color)
	if dragging and not ghost.is_empty():
		var pos: Vector2=pixel(ghost);draw_circle(pos,15,Color(.99,.78,.25,.45));draw_arc(pos,16,0,TAU,28,Color("5d43a7"),3,true)
		draw_string(_font,pos+Vector2(18,20),"snap "+str(ghost),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("25243b"))
func _gui_input(event: InputEvent) -> void:
	if workbench.model.definition.is_empty():return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			var best: Dictionary={};var distance: float=20*20
			for target in workbench.model.targets(workbench.mode):
				var point: Array=workbench.model.target_point(target)
				if point.is_empty():continue
				var d: float=pixel(point).distance_squared_to(event.position)
				if d<distance:distance=d;best=target
			if not best.is_empty():workbench.select_target(best);dragging=true;ghost=grid(event.position);accept_event()
		elif dragging:
			dragging=false;ghost=grid(event.position);workbench.apply_point(ghost);ghost=[];accept_event()
	elif event is InputEventMouseMotion and dragging:
		ghost=grid(event.position);accept_event()
