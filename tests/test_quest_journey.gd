extends SceneTree
## The guide must explain the real authored phases without advancing or solving them.
const Kernel=preload("res://core/simulation_kernel.gd")
const Guide=preload("res://presentation/quest_guide.gd")
var checks: int=0
var failures: Array[String]=[]
var states_checked: int=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for number in range(1,31):
		var id: String="L%02d"%number
		var kernel=Kernel.new()
		var definition: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/"+id+".json"))
		check(kernel.load_level(definition,48121),id+" loads authoritative data")
		var path: String="res://tests/"+("" if number<=3 else "replays/")+id+"_solution.json"
		var replay: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		inspect_guide(kernel,number)
		for step in replay.steps:
			if step.op=="command":
				var result: Dictionary=kernel.dispatch(step)
				check(result.accepted,id+" accepts authored action "+step.type)
			elif step.op=="advance_ticks":kernel.advance_ticks(int(step.count))
			inspect_guide(kernel,number)
		check(kernel.state.phase=="SUCCESS",id+" completes the actual puzzle before next-level guidance")
		for locale in ["ru","en"]:
			var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/"+locale+".json"))
			var victory: Dictionary=Guide.victory(kernel,locale,number,30,catalog,"Next scene")
			if number<30:
				check(victory.primary.contains(str(number+1)),id+" victory names the next level "+locale)
			else:
				check(not victory.primary.contains("31"),"finale does not offer a nonexistent level31 "+locale)
	print("QUEST JOURNEY: %d checks; %d real states; %d failures"%[checks,states_checked,failures.size()])
	for issue in failures:printerr("FAIL: "+issue)
	var file=FileAccess.open("res://tests/reports/quest-journey.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"states":states_checked,"failures":failures,"scope":"30 actual authored solutions; guide goals, phase semantics and mutation isolation in RU/EN; L01 real pointer advancement is covered in test_ui"},"  "));file.close()
	quit(0 if failures.is_empty() else 1)
func inspect_guide(kernel,number: int) -> void:
	states_checked+=1
	for locale in ["ru","en"]:
		var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/"+locale+".json"))
		var before: String=kernel.state_hash()
		var guide: Dictionary=Guide.describe(kernel,locale,number,30,"",catalog)
		var context: String="L%02d %s %s"%[number,kernel.state.phase,locale]
		check(kernel.state_hash()==before,context+" explanation cannot mutate or solve the puzzle")
		check(not guide.body.is_empty() and not guide.objective.is_empty() and not guide.primary.is_empty(),context+" has goal, next instruction and action")
		check(guide.witness_status.size()==kernel.state.witnesses.size(),context+" accounts for every witness")
		var ids: Array=[];var all_done: bool=true;var labels_valid: bool=true
		for row in guide.goals:
			ids.append(row.id)
			if row.required:all_done=all_done and row.done
			labels_valid=labels_valid and not row.label.is_empty() and not row.label.contains("{") and not row.label.contains("predicate")
		var expected: Array=[]
		for goal in kernel.definition.goals:expected.append(goal.id)
		ids.sort();expected.sort()
		check(ids==expected and labels_valid,context+" names every authored condition without raw data placeholders")
		match str(kernel.state.phase):
			"PROOF_ACCEPTED":
				check(guide.stage_number==2 and not guide.primary_disabled,context+" proof remains an observed demonstration with an enabled separate law action")
				check(guide.primary==("Make it a law" if locale=="en" else "Сделать законом"),context+" requires explicit sealing")
				check(guide.body.contains("not finished") if locale=="en" else (guide.body.contains("не закончено") or guide.body.contains("ещё не победа")),context+" explains that a successful trick is not the level finish")
			"PLAN_RESOLUTION","RUN_RESOLUTION":
				check(guide.stage_number==3 and not guide.goals.is_empty(),context+" applies the law to the actual goal checklist")
			"SUCCESS":
				check(guide.stage_number==4 and all_done,context+" completion agrees with every required world condition")
func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition and failures.size()<100:failures.append(message)
