extends RefCounted
## Developer-only authoring state. Definition edits never change the normal player save.
const Kernel=preload("res://core/simulation_kernel.gd")
var definition: Dictionary={}
var source_path: String=""
var kernel=Kernel.new()
var comparison_kernel: RefCounted
var replay: Dictionary={}
var replay_cursor: int=0
var before_law: Dictionary={}
var after_law: Dictionary={}
var last_errors: Array[String]=[]
var last_events: Array=[]
var last_action: String=""
var export_log: Array=[]
var _undo: Array=[]
var _redo: Array=[]
var _preview_journal: Array=[]
var _comparison: String="live"

func load_file(path: String) -> bool:
	last_errors.clear()
	var parsed: Dictionary=_read_json(path)
	if parsed.is_empty() and not last_errors.is_empty():return false
	if load_definition(parsed,path):return true
	for i in range(last_errors.size()):last_errors[i]=path+": "+last_errors[i]
	return false
func load_definition(data: Dictionary,path: String="") -> bool:
	var errors: Array[String]=Kernel.new().validate_definition(data)
	if not errors.is_empty():last_errors=errors;return false
	var candidate=Kernel.new()
	if not candidate.load_level(data,48121):last_errors=["Kernel rejected definition"];return false
	definition=candidate.definition.duplicate(true);kernel=candidate;source_path=path
	replay=_load_replay();replay_cursor=0;before_law.clear();after_law.clear();comparison_kernel=null;_comparison="live";_preview_journal.clear()
	_undo.clear();_redo.clear();last_errors.clear();last_events.clear();last_action="Loaded "+definition.level_id
	return true
func visible_kernel() -> RefCounted:
	return comparison_kernel if comparison_kernel!=null else kernel
func validation_errors() -> Array[String]:
	last_errors=Kernel.new().validate_definition(definition)
	return last_errors.duplicate()
func targets(mode: String) -> Array:
	var result: Array=[]
	if mode=="slots":
		for slot in definition.get("slots",[]):result.append({"kind":"slot","id":slot.id,"label":slot.id})
	elif mode in ["result_anchors","method_anchors"]:
		for proof in definition.get("proofs",[]):
			for i in range(proof[mode].size()):
				result.append({"kind":"anchor","myth_id":proof.myth_id,"group":mode,"index":i,"label":"%s %s[%d] • %s"%[proof.myth_id,"result" if mode=="result_anchors" else "method",i,proof[mode][i].entity_id]})
	elif mode=="occluders":
		for occ in definition.get("occluders",[]):
			for group in ["segment","folded_segment"]:
				if not occ.has(group):continue
				for i in range(2):result.append({"kind":"occluder","id":occ.id,"segment_key":group,"index":i,"label":occ.id+" • "+("folded " if group=="folded_segment" else "tall ")+"endpoint"+str(i+1)})
	return result
func target_point(target: Dictionary) -> Array:
	if definition.is_empty():return []
	match target.get("kind",""):
		"slot":return _find(definition.slots,target.id).get("position",[]).duplicate()
		"occluder":return _find(definition.occluders,target.id)[target.get("segment_key","segment")][int(target.index)].duplicate()
		"anchor":
			var proof: Dictionary=_proof(target.myth_id)
			if proof.is_empty():return []
			var anchor: Dictionary=proof[target.group][int(target.index)]
			var position: Array=visible_kernel().state.entities[anchor.entity_id].position
			return [int(position[0])+int(anchor.offset[0]),int(position[1])+int(anchor.offset[1])]
	return []
func move_target(target: Dictionary,position: Array) -> bool:
	last_errors.clear()
	if position.size()!=2 or not _integer(position[0]) or not _integer(position[1]) or position[0]<0 or position[0]>24 or position[1]<0 or position[1]>28:
		last_errors=["Authoring point must be on integer grid x0..24/y0..28"];return false
	if not _target_valid(target):last_errors=["Unknown authoring target"];return false
	var checkpoint: Dictionary=_author_snapshot()
	var old_point: Array=target_point(target)
	match target.kind:
		"slot":_find(definition.slots,target.id).position=[int(position[0]),int(position[1])]
		"occluder":_find(definition.occluders,target.id)[target.get("segment_key","segment")][int(target.index)]=[int(position[0]),int(position[1])]
		"anchor":
			var anchor: Dictionary=_proof(target.myth_id)[target.group][int(target.index)]
			var base: Array=visible_kernel().state.entities[anchor.entity_id].position
			anchor.offset=[int(position[0])-int(base[0]),int(position[1])-int(base[1])]
	definition.status="layout_seed"
	var errors: Array[String]=Kernel.new().validate_definition(definition)
	if not errors.is_empty():definition=checkpoint.definition;last_errors=errors;return false
	_undo.append(checkpoint)
	if _undo.size()>50:_undo.pop_front()
	_redo.clear();comparison_kernel=null
	_rebuild_preview(checkpoint.journal)
	if checkpoint.comparison!="live" and last_errors.is_empty():show_law_comparison(checkpoint.comparison)
	last_action="Move %s %s → %s; dependent geometry unchanged"%[target.get("label",target.kind),str(old_point),str(position)]
	return true
func undo() -> bool:
	if _undo.is_empty():last_errors=["No authoring undo"];return false
	_redo.append(_author_snapshot());_restore_author_snapshot(_undo.pop_back());last_action="Authoring undo";return true
func redo() -> bool:
	if _redo.is_empty():last_errors=["No authoring redo"];return false
	_undo.append(_author_snapshot());_restore_author_snapshot(_redo.pop_back());last_action="Authoring redo";return true
func reset_preview() -> void:
	kernel=Kernel.new();kernel.load_level(definition,48121);replay_cursor=0;before_law.clear();after_law.clear();comparison_kernel=null;_comparison="live";_preview_journal.clear();last_errors.clear();last_events.clear()
func step_replay() -> bool:
	comparison_kernel=null;_comparison="live";last_errors.clear()
	if replay_cursor>=replay.get("steps",[]).size():last_errors=["Replay complete/no next step"];return false
	var step: Dictionary=replay.steps[replay_cursor]
	var ok: bool=_perform_replay_step(step)
	if ok:_preview_journal.append({"kind":"trace","index":replay_cursor});replay_cursor+=1
	last_action="Trace %d/%d • %s"%[replay_cursor,replay.steps.size(),JSON.stringify(step)]
	return ok
func advance_ticks(count: int) -> Array:
	comparison_kernel=null;_comparison="live";last_errors.clear();last_events=kernel.advance_ticks(count);last_action="Manual +%d ticks • tick%d • %s"%[count,kernel.state.tick,kernel.state.phase]
	if count>0:
		if not _preview_journal.is_empty() and _preview_journal[-1].kind=="ticks":_preview_journal[-1].count+=count
		else:_preview_journal.append({"kind":"ticks","count":count})
	return last_events.duplicate(true)
func run_canonical() -> bool:
	reset_preview()
	if replay.get("steps",[]).is_empty():last_errors=["Canonical replay unavailable"];return false
	while replay_cursor<replay.steps.size():
		if not step_replay():return false
	for predicate in replay.get("expected_final_predicates",[]):
		if not kernel.assert_predicate(predicate):last_errors=["Final assertion failed: "+predicate];return false
	last_action="Canonical trace passed • "+definition.level_id
	return true
func show_law_comparison(which: String) -> bool:
	if which=="live":comparison_kernel=null;_comparison="live";return true
	if which not in ["before","after"]:last_errors=["Unknown law comparison"];return false
	var snap: Dictionary=before_law if which=="before" else after_law
	if snap.is_empty():last_errors=["Step a successful ActivateLaw first"];return false
	var view=Kernel.new();view.load_level(definition,48121)
	if not view.restore(snap):last_errors=["Comparison snapshot rejected"];return false
	comparison_kernel=view;_comparison=which;return true
func export_json(path: String) -> bool:
	last_errors=Kernel.new().validate_definition(definition)
	if not last_errors.is_empty():return false
	if path.is_empty() or not path.to_lower().ends_with(".json"):last_errors=["Choose an explicit .json file"];return false
	var folder: String=path.get_base_dir()
	if not folder.is_empty() and DirAccess.make_dir_recursive_absolute(folder)!=OK and not DirAccess.dir_exists_absolute(folder):last_errors=["Cannot create export directory"];return false
	var text: String=JSON.stringify(definition,"  ")
	var f=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if f==null:last_errors=["Cannot write export temp file"];return false
	f.store_string(text);f.flush();f.close()
	var candidate: Dictionary=_read_json(path+".tmp")
	if candidate.is_empty() or not Kernel.new().validate_definition(candidate).is_empty() or _canonical(candidate)!=_canonical(definition):last_errors=["Export readback/validation mismatch"];return false
	if FileAccess.file_exists(path):
		var old: Dictionary=_read_json(path)
		if not old.is_empty() and Kernel.new().validate_definition(old).is_empty():
			if FileAccess.file_exists(path+".bak"):DirAccess.remove_absolute(path+".bak")
			if DirAccess.rename_absolute(path,path+".bak")!=OK:last_errors=["Cannot preserve previous valid export"];return false
		else:
			if DirAccess.remove_absolute(path)!=OK:last_errors=["Cannot replace invalid export"];return false
	if DirAccess.rename_absolute(path+".tmp",path)!=OK:last_errors=["Cannot commit export; backup retained"];return false
	export_log.append({"path":path,"content_digest":kernel.state.content_digest,"edits":_undo.size()})
	last_errors.clear();last_action="Validated export saved: "+path
	return true
func _perform_replay_step(step: Dictionary) -> bool:
	match step.get("op",""):
		"command":
			var before: Dictionary=kernel.snapshot()
			var response: Dictionary=kernel.dispatch(step)
			last_events=response.events
			if not response.accepted:last_errors=["Replay command "+step.get("type","")+": "+response.reason_code];return false
			if step.type=="ActivateLaw" and kernel.state.phase=="PLAN_RESOLUTION":before_law=before;after_law=kernel.snapshot()
		"advance_ticks":last_events=kernel.advance_ticks(int(step.get("count",0)))
		"assert":
			if not kernel.assert_predicate(step.get("predicate","")):last_errors=["Replay assertion failed: "+step.get("predicate","")+" • "+kernel.state.phase];return false
		_:last_errors=["Unknown replay operation"];return false
	return true
func _rebuild_preview(journal: Array) -> void:
	reset_preview()
	for entry in journal:
		if entry.kind=="trace":
			if not step_replay():break
		elif entry.kind=="ticks":advance_ticks(int(entry.count))
func _author_snapshot() -> Dictionary:
	return {"definition":definition.duplicate(true),"preview":kernel.snapshot(),"cursor":replay_cursor,"before":before_law.duplicate(true),"after":after_law.duplicate(true),"journal":_preview_journal.duplicate(true),"comparison":_comparison}
func _restore_author_snapshot(saved: Dictionary) -> void:
	definition=saved.definition.duplicate(true);kernel=Kernel.new();kernel.load_level(definition,48121);kernel.restore(saved.preview)
	replay_cursor=saved.cursor;before_law=saved.before.duplicate(true);after_law=saved.after.duplicate(true);comparison_kernel=null;_comparison="live";_preview_journal=saved.journal.duplicate(true);last_errors.clear()
	if saved.comparison!="live":show_law_comparison(saved.comparison)
func _target_valid(t: Dictionary) -> bool:
	if t.get("kind")=="slot":return not _find(definition.slots,t.get("id","")).is_empty()
	if t.get("kind")=="occluder":
		var occluder: Dictionary=_find(definition.occluders,t.get("id",""))
		var group: Variant=t.get("segment_key","segment")
		return not occluder.is_empty() and group in ["segment","folded_segment"] and occluder.has(group) and t.get("index",-1) in [0,1]
	if t.get("kind")=="anchor":
		var p: Dictionary=_proof(t.get("myth_id",""));var group: String=t.get("group","")
		return not p.is_empty() and group in ["result_anchors","method_anchors"] and t.get("index",-1)>=0 and t.index<p[group].size()
	return false
func _load_replay() -> Dictionary:
	var name: String=str(definition.get("canonical_solution_ref",definition.level_id+"_solution.json")).get_file()
	if not name.begins_with(definition.level_id+"_") or not name.ends_with(".json"):return {}
	for folder in ["res://tests/","res://tests/replays/"]:
		if FileAccess.file_exists(folder+name):return _read_json(folder+name)
	return {}
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):last_errors=[path+": file not found"];return {}
	var parser=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK:last_errors=[path+": line%d "%parser.get_error_line()+parser.get_error_message()];return {}
	if not parser.data is Dictionary:last_errors=[path+": JSON object required"];return {}
	return parser.data
func _proof(id: String) -> Dictionary:
	for p in definition.get("proofs",[]):
		if p.myth_id==id:return p
	return {}
func _find(items: Array,id: String) -> Dictionary:
	for item in items:
		if item.id==id:return item
	return {}
func _integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value==floor(value))
func _canonical(value: Variant) -> Variant:
	return Kernel.new()._canonical(value)
