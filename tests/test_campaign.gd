extends SceneTree
const Kernel=preload("res://core/simulation_kernel.gd")
var failures: Array[String]=[]
var count: int=0
var levels: int=0
var alternatives: int=0

func _initialize() -> void:
	for number in range(1,31):
		var id: String="L%02d"%number
		var replay_path: String="res://tests/"+id+"_solution.json" if number<=3 else "res://tests/replays/"+id+"_solution.json"
		run_case(id,replay_path)
		levels+=1
	var dir=DirAccess.open("res://tests/replays")
	if dir!=null:
		var names: PackedStringArray=dir.get_files(); names.sort()
		for name in names:
			if name.ends_with("_alternative.json"):
				run_case(name.substr(0,3),"res://tests/replays/"+name); alternatives+=1
	print("CAMPAIGN TESTS: %d levels; %d alternatives; %d checks; %d failures"%[levels,alternatives,count,failures.size()])
	for issue in failures: printerr("FAIL: "+issue)
	var report: Dictionary={"engine":Engine.get_version_info().string,"levels":levels,"alternatives":alternatives,"checks":count,"failures":failures,"fresh_run":true}
	DirAccess.make_dir_recursive_absolute("res://tests/reports")
	var file=FileAccess.open("res://tests/reports/campaign.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")); file.close()
	quit(0 if failures.is_empty() else 1)
func run_case(id: String,path: String) -> void:
	var d: Dictionary=read_json("res://data/levels/"+id+".json")
	var replay: Dictionary=read_json(path)
	var k=Kernel.new()
	if not check(k.load_level(d,42),path+": load "+str(k.validate_definition(d))): return
	if not check(replay.get("steps") is Array,path+": replay steps"): return
	for step in replay.steps:
		if step.op=="command":
			var result: Dictionary=k.dispatch(step)
			if not check(result.accepted,path+": "+step.type+" "+result.reason_code+" phase="+k.state.phase): return
		elif step.op=="advance_ticks": k.advance_ticks(int(step.count))
		elif step.op=="assert":
			if not check(k.assert_predicate(step.predicate),path+": "+step.predicate+" phase="+k.state.phase+" reason="+k.state.failure_reason): return
	for predicate in replay.get("expected_final_predicates",[]): check(k.assert_predicate(predicate),path+": final "+predicate)
	var saved: Dictionary=JSON.parse_string(JSON.stringify(k.snapshot()))
	var before: String=k.state_hash()
	check(k.restore(saved) and k.state_hash()==before,path+": JSON snapshot/restore hash")
	var b=Kernel.new(); b.load_level(d,42)
	for step in replay.steps:
		if step.op=="command": b.dispatch(step)
		elif step.op=="advance_ticks": b.advance_ticks(int(step.count))
	check(b.state_hash()==k.state_hash(),path+": deterministic replay")
func check(ok: bool,message: String) -> bool:
	count+=1
	if not ok: failures.append(message)
	return ok
func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
