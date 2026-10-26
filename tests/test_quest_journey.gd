extends SceneTree
## The guide must explain the real authored phases without advancing or solving them.
const Kernel=preload("res://core/simulation_kernel.gd")
const Guide=preload("res://presentation/quest_guide.gd")
var checks: int=0
var failures: Array[String]=[]
var states_checked: int=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
	guidance_regressions()
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

func load_fixture(id: String,heavy_cargo: bool=false):
	var definition: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/"+id+".json"))
	if heavy_cargo:
		for entity in definition.entities:
			if entity.id=="cargo":entity.mass_units=50
	var kernel=Kernel.new()
	check(kernel.load_level(definition,48121),id+" guidance fixture loads")
	return kernel

func guidance_regressions() -> void:
	var tutorial=load_fixture("L01")
	for locale in ["ru","en"]:
		var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/"+locale+".json"))
		var before: String=tutorial.state_hash()
		var first: Dictionary=Guide.describe(tutorial,locale,1,30,"",catalog)
		check(first.short_body.contains("Objects") if locale=="en" else first.short_body.contains("Предметы"),"PLR001 initial instruction names the actual closed inventory "+locale)
		var chosen: Dictionary=Guide.describe(tutorial,locale,1,30,"screen_a",catalog)
		check(chosen.short_body.contains("highlighted") if locale=="en" else chosen.short_body.contains("подсвеченного"),"PLR001 selected tray screen requests actual placement "+locale)
		check(tutorial.state_hash()==before,"tutorial guidance is read-only "+locale)
	check(tutorial.dispatch({"type":"PlaceProp","payload":{"entity_id":"screen_a","slot_id":"screen_left"}}).accepted,"tutorial screen is placed through real command")
	check(Guide.describe(tutorial,"ru",1,30).short_body.contains("сложите верх"),"placed tall screen now teaches folding")
	check(tutorial.dispatch({"type":"Interact","payload":{"entity_id":"screen_a","action":"fold"}}).accepted,"tutorial screen folds through real command")
	check(Guide.describe(tutorial,"en",1,30).short_body.contains("Marfa"),"placed folded screen directs observation rather than repeating placement")
	for heavy in [false,true]:
		var kernel=load_fixture("L03",heavy)
		var replay: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/L03_solution.json"))
		for step in replay.steps:
			if step.op=="command":
				if not heavy and step.type=="PlaceProp" and step.payload.entity_id=="stone" and step.payload.slot_id=="bridge":continue
				check(kernel.dispatch(step).accepted,"L03 failing fixture accepts real "+str(step.type))
			elif step.op=="advance_ticks":kernel.advance_ticks(int(step.count))
			if kernel.state.phase=="RECOVERABLE_FAILURE":break
		check(kernel.state.phase=="RECOVERABLE_FAILURE","L03 bad preparation reaches an actual recoverable failure")
		check(kernel.state.failure_reason==("OVER_CAPACITY" if heavy else "MISSING_FLOATING_BRIDGE"),"fixture failure distinguishes capacity from support location")
		for locale in ["ru","en"]:
			var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/"+locale+".json"))
			var before: String=kernel.state_hash()
			var guide: Dictionary=Guide.describe(kernel,locale,3,30,"cargo",catalog)
			var help: Dictionary=Guide.hint(kernel,locale,2,catalog)
			check(guide.short_body.contains("overloaded") if heavy and locale=="en" else guide.short_body.contains("перегружена") if heavy else guide.short_body.contains("away from the route") if locale=="en" else guide.short_body.contains("не на маршруте"),"PLR006 short HUD explains actual distinct route failure "+locale)
			check(guide.get("blocking_entity_id","")=="stone","failure identifies the actual support for inspection "+locale)
			check(help.context=="resolution" and not help.body.contains("Семён") and not help.body.contains("Semyon"),"PLR006 hint after the law belongs to application, not the old observer step "+locale)
			if not heavy:check(help.body.contains("position") if locale=="en" else help.body.contains("позиции"),"L03 second application hint explains demonstration vs crossing positions "+locale)
			check(kernel.state_hash()==before,"diagnostics and contextual hints do not mutate/solve the bad plan "+locale)
		if not heavy:
			check(kernel.dispatch({"type":"Undo","payload":{}}).accepted,"failed run is undone without deleting setup")
			check(kernel.dispatch({"type":"PlaceProp","payload":{"entity_id":"stone","slot_id":"bridge"}}).accepted,"actual support is moved after explanation")
			check(kernel.dispatch({"type":"RunResolution","payload":{}}).accepted,"corrected plan runs")
			kernel.advance_ticks(100)
			check(kernel.state.phase=="SUCCESS","correcting only the support position completes the actual level")
	var mooring=load_fixture("L02")
	check(mooring.dispatch({"type":"AssignRoute","payload":{"actor_id":"cargo","route_id":"unload"}}).accepted,"unmoored fixture assigns actual unloading")
	check(mooring.dispatch({"type":"RunResolution","payload":{}}).accepted,"unmoored fixture runs")
	mooring.advance_ticks(10)
	check(mooring.state.failure_reason=="ROUTE_STATE_BLOCKED","unmoored route has a different authoritative failure")
	check(Guide.describe(mooring,"ru",2,30).short_body.contains("причала"),"state-blocked explanation names mooring rather than an unrelated stone")
	var rigid=load_fixture("L03")
	check(not rigid._entities.screen_a.properties.get("foldable",false),"PLR005 rigid screen remains mechanically rigid")
	for locale in ["ru","en"]:
		var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/"+locale+".json"))
		check(Guide._entity_name(rigid,"screen_a",catalog,locale).contains("rigid") if locale=="en" else Guide._entity_name(rigid,"screen_a",catalog,locale).contains("жёсткий"),"PLR005 rigid equipment is explicitly distinguished "+locale)
		check(Guide.briefing(rigid,locale,3,30,catalog).contains("do not fold") if locale=="en" else Guide.briefing(rigid,locale,3,30,catalog).contains("не складываются"),"PLR005 briefing explains transfer of the earlier folding lesson "+locale)

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
