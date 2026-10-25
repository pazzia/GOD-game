extends SceneTree
## Native developer-tool acceptance. Input is synthetic; no human usability claim.
const Model=preload("res://tools/workbench_model.gd")
const Workbench=preload("res://tools/level_workbench.tscn")
var failures: Array[String]=[]
var checks: int=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
	model_cases();await scene_cases()
	print("WORKBENCH: %d checks; %d failures"%[checks,failures.size()])
	for issue in failures:printerr("FAIL: "+issue)
	var f=FileAccess.open("res://tests/reports/workbench.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"native_tool":true,"human_usability_test":false},"  "));f.close()
	quit(0 if failures.is_empty() else 1)
func model_cases() -> void:
	var m=Model.new()
	check(m.load_file("res://data/levels/L01.json"),"load actual authored level")
	check(m.targets("slots").size()==m.definition.slots.size() and m.targets("result_anchors").size()==3 and m.targets("method_anchors").size()==1 and m.targets("occluders").size()==4,"all logical authoring markers, including both screen forms, are available")
	var screen: Dictionary={"kind":"slot","id":"screen_left","label":"screen_left"}
	var old_definition: Variant=m._canonical(m.definition)
	var occ_before: Array=m.definition.occluders[0].segment.duplicate(true)
	var anchor_before: Array=m.definition.proofs[0].result_anchors.duplicate(true)
	check(m.move_target(screen,[10,6]) and m.target_point(screen)==[10,6],"slot move snaps to integer authored coordinate")
	check(m.definition.occluders[0].segment==occ_before and m.definition.proofs[0].result_anchors==anchor_before,"slot edit never silently translates absolute occluder or relative anchors")
	check(m.undo() and m._canonical(m.definition)==old_definition,"authoring undo restores exact definition")
	check(m.redo() and m.target_point(screen)==[10,6],"authoring redo restores edited coordinate")
	var edited: Variant=m._canonical(m.definition)
	check(not m.move_target(screen,[10.5,6]) and m._canonical(m.definition)==edited,"fractional author point rejected atomically")
	check(not m.move_target(screen,[-1,6]) and not m.move_target(screen,[25,6]) and not m.move_target(screen,[10,29]),"out of stage edits rejected")
	check(not m.move_target({"kind":"slot","id":"missing"},[1,1]),"unknown authoring target rejected")
	m.load_file("res://data/levels/L01.json")
	var endpoint: Dictionary={"kind":"occluder","id":"left_screen","index":0}
	var screen_before: Array=m.target_point(screen)
	check(not m.move_target(endpoint,occ_before[1]) and m.definition.occluders[0].segment==occ_before,"degenerate occluder edit rejected with prior geometry retained")
	check(m.move_target(endpoint,[10,10]) and m.definition.occluders[0].segment[0]==[10,10] and m.target_point(screen)==screen_before,"occluder endpoint can be edited explicitly without moving its slot")
	m.load_file("res://data/levels/L01.json")
	check(m.step_replay() and m.step_replay() and m.replay_cursor==2,"actual screen placement and folding commands step against the core")
	var preview_hash: String=m.kernel.state_hash()
	var anchor: Dictionary={"kind":"anchor","myth_id":"M01","group":"result_anchors","index":0}
	check(m.target_point(anchor)==[13,14],"result marker tracks stage entity position after replay commands")
	check(m.move_target(anchor,[13,15]) and m.definition.proofs[0].result_anchors[0].offset==[-1,3] and m.replay_cursor==2 and m.target_point(anchor)==[13,15],"anchor edit derives offset from current preview pose and rebuilds to same trace cursor")
	check(m.undo() and m.replay_cursor==2 and m.kernel.state_hash()==preview_hash,"geometry undo restores preview state and trace position")
	check(m.kernel.visibility_for("w1").has("visible_results"),"witness diagnostics are authoritative core visibility")
	check(m.step_replay(),"step BeginPerformance")
	var tick_before: int=m.kernel.state.tick;m.advance_ticks(1)
	check(m.kernel.state.tick==tick_before+1 and m.replay_cursor==3,"manual single tick advances simulation without consuming canonical step")
	check(m.move_target({"kind":"slot","id":"tray_screen_a"},[3,24]) and m.kernel.state.tick==tick_before+1 and m.replay_cursor==3,"authoring edit replays interleaved manual ticks without jumping back in time")
	m.undo()
	check(m.run_canonical() and m.kernel.assert_predicate("level_success"),"full canonical trace and final predicates execute")
	check(not m.before_law.is_empty() and not m.after_law.is_empty() and m.before_law.active_laws.is_empty() and m.after_law.active_laws==["M01"],"successful law commit captures both actual states")
	var live_hash: String=m.kernel.state_hash();var cursor: int=m.replay_cursor
	check(m.show_law_comparison("before") and m.visible_kernel().state.active_laws.is_empty() and m.kernel.state_hash()==live_hash and m.replay_cursor==cursor,"before-law view never mutates live timeline")
	check(m.show_law_comparison("after") and m.visible_kernel().state.active_laws==["M01"] and m.kernel.state_hash()==live_hash,"after-law view is an independent restored core")
	check(m.move_target({"kind":"slot","id":"tray_screen_a"},[3,24]) and m.comparison_kernel!=null and m.visible_kernel().state.active_laws==["M01"] and m.replay_cursor==cursor,"author edit retains before-after comparison while rebuilding actual timeline")
	m.undo()
	check(m.show_law_comparison("live") and m.visible_kernel()==m.kernel,"return to live state")
	var valid_before: Variant=m._canonical(m.definition)
	var invalid: Dictionary=m.definition.duplicate(true);invalid.entities[0].initial_slot="missing-slot"
	check(not m.load_definition(invalid) and m._canonical(m.definition)==valid_before and m.kernel.state_hash()==live_hash,"invalid imported references preserve loaded definition and preview")
	var export_path: String="user://workbench-review/L01.json"
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(export_path+suffix):DirAccess.remove_absolute(export_path+suffix)
	check(m.export_json(export_path),"validated explicit JSON export")
	var reloaded=Model.new()
	check(reloaded.load_file(export_path) and reloaded._canonical(reloaded.definition)==valid_before,"export reload retains full canonical definition")
	check(m.move_target(screen,[10,6]) and m.export_json(export_path),"subsequent validated author save")
	var backup=Model.new()
	check(backup.load_file(export_path+".bak") and backup._canonical(backup.definition)==valid_before,"previous valid author file is recoverable backup")
	var raw_before: String=FileAccess.get_file_as_string(export_path)
	m.definition.entities[0].initial_slot="missing-slot"
	check(not m.export_json(export_path) and FileAccess.get_file_as_string(export_path)==raw_before,"invalid reference cannot overwrite prior valid export")
	m.load_file(export_path)
	var corrupted=FileAccess.open(export_path,FileAccess.WRITE);corrupted.store_string("broken");corrupted.close()
	check(m.export_json(export_path) and backup.load_file(export_path+".bak") and backup._canonical(backup.definition)==valid_before,"replacing invalid primary retains last valid author backup")
	var folding=Model.new();check(folding.load_file("res://data/levels/L01.json"),"load the actual foldable tutorial for authoring")
	var folded_endpoint: Dictionary={"kind":"occluder","id":"left_screen","segment_key":"folded_segment","index":1}
	var tall_before: Array=folding.definition.occluders[0].segment.duplicate(true)
	check(folding.target_point(folded_endpoint)==[9,12] and folding.move_target(folded_endpoint,[9,11]),"folded-screen endpoint is independently editable")
	check(folding.definition.occluders[0].segment==tall_before and folding.run_canonical(),"folded visibility edit preserves tall geometry and remains playable")
	var folded_before: Array=folding.definition.occluders[0].folded_segment.duplicate(true)
	check(not folding.move_target(folded_endpoint,folded_before[0]) and folding.definition.occluders[0].folded_segment==folded_before,"degenerate folded endpoint is rejected atomically")
	check(not folding.move_target({"kind":"occluder","id":"left_screen","segment_key":"channels","index":0},[1,1]),"authoring target cannot overwrite a non-geometry field")
	var folded_path: String="user://workbench-review/L01-folded.json"
	check(folding.export_json(folded_path),"actual folded-screen author edit exports through validation")
	var folded_reload=Model.new()
	check(folded_reload.load_file(folded_path) and folded_reload.definition.occluders[0].folded_segment==folded_before and folded_reload.run_canonical(),"folded geometry survives export/reload and its canonical demonstration")
	for n in range(1,31):
		var campaign=Model.new()
		check(campaign.load_file("res://data/levels/L%02d.json"%n) and campaign.run_canonical(),"native preview executes actual canonical L%02d"%n)
func scene_cases() -> void:
	var progress_path: String="user://progress.json"
	var progress_before: String=FileAccess.get_file_as_string(progress_path) if FileAccess.file_exists(progress_path) else "<absent>"
	var tool=Workbench.instantiate();root.add_child(tool)
	await process_frame;await process_frame
	check(tool.stage.kernel==tool.model.kernel and tool.geometry.size.x>900 and tool.geometry.size.y>600,"native tool uses actual laid out production StageView")
	check(tool.geometry.grid(tool.geometry.pixel([14,12]))==[14,12],"overlay inverse transform matches production world transform")
	var target: Dictionary={"kind":"slot","id":"screen_left","label":"screen_left"}
	var old: Array=tool.model.target_point(target)
	var start: Vector2=tool.geometry.pixel(old)
	var end: Vector2=tool.geometry.pixel([10,6])+Vector2(8,3)
	var down=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=start
	tool.geometry._gui_input(down)
	var motion=InputEventMouseMotion.new();motion.position=end;tool.geometry._gui_input(motion)
	check(tool.geometry.dragging and tool.geometry.ghost==[10,6],"native drag handler previews snapped grid destination")
	var up=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.pressed=false;up.position=end;tool.geometry._gui_input(up)
	check(not tool.geometry.dragging and tool.model.target_point(target)==[10,6],"native mouse release commits explicit author edit")
	var undo=InputEventKey.new();undo.keycode=KEY_Z;undo.ctrl_pressed=true;undo.pressed=true;tool._input(undo)
	check(tool.model.target_point(target)==old,"native Ctrl+Z restores dragged marker")
	tool.witness_picker.select(1);tool._refresh()
	check(tool.stage.inspected=="w1" and tool.diagnostic_label.text.contains("Result"),"witness selector exposes actual diagnostic rays")
	tool.model.run_canonical();tool.model.show_law_comparison("before");tool._refresh()
	check(tool.stage.kernel==tool.model.comparison_kernel and tool.state_label.text.contains("PROOF_ACCEPTED"),"native before-law selector presents captured comparison world")
	var current: String=tool.model.kernel.state_hash()
	var bad_path: String="user://workbench-review/invalid.json"
	var bad_definition: Dictionary=tool.model.definition.duplicate(true);bad_definition.entities[0].initial_slot="missing-slot"
	var bad=FileAccess.open(bad_path,FileAccess.WRITE);bad.store_string(JSON.stringify(bad_definition));bad.close()
	check(not tool.open_author_file(bad_path) and tool.model.kernel.state_hash()==current and tool.log_view.text.contains("unknown initial slot") and tool.log_view.text.contains(bad_path) and tool.log_view.text.contains("entities."),"native invalid-file opening displays file/path/reference error and retains prior world")
	var empty_path: String="user://workbench-review/empty-level.json"
	var empty=FileAccess.open(empty_path,FileAccess.WRITE);empty.store_string("{}");empty.close()
	check(not tool.open_author_file(empty_path) and tool.model.kernel.state_hash()==current and tool.log_view.text.contains(empty_path) and tool.log_view.text.contains("schema_version: required") and not tool.log_view.text.contains("unknown initial slot"),"empty-object import reports its own missing-fields diagnostic instead of reusing previous error")
	tool.queue_free();await process_frame
	var progress_after: String=FileAccess.get_file_as_string(progress_path) if FileAccess.file_exists(progress_path) else "<absent>"
	check(progress_after==progress_before,"developer tool lifecycle leaves player progress untouched")
func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message)
