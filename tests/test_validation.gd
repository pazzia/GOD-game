extends SceneTree
const Kernel=preload("res://core/simulation_kernel.gd")
var failures: Array[String]=[]
var count: int=0
func _initialize() -> void:
	var d: Dictionary=read_level("L01");var k=Kernel.new();k.load_level(d)
	var bad: Dictionary=d.duplicate(true);bad.slots[0].position[0]=2.5;reject_definition(k,bad,"fractional slot")
	bad=d.duplicate(true);bad.entities[0].mass_units=-1;reject_definition(k,bad,"negative mass")
	bad=d.duplicate(true);bad.witnesses[0].views.append(bad.witnesses[0].views[0].duplicate(true));reject_definition(k,bad,"duplicate overlapping views")
	bad=d.duplicate(true);bad.proofs[0].predicates[1].parameters.zone_id="missing_water";reject_definition(k,bad,"missing proof zone")
	bad=d.duplicate(true);bad.goals[0].parameters.actor_id="missing_actor";reject_definition(k,bad,"missing goal actor")
	bad=d.duplicate(true);bad.navigation.routes[0].nodes=[];reject_definition(k,bad,"empty route")
	bad=d.duplicate(true);bad.max_active_laws=2;bad.initial_active_laws=["M01","M01"];reject_definition(k,bad,"duplicate initial law")
	var saved: Dictionary=k.snapshot()
	bad=saved.duplicate(true);bad.tick=1.5;reject_state(k,bad,"fractional tick")
	bad=saved.duplicate(true);bad.tick=-1;reject_state(k,bad,"negative tick")
	bad=saved.duplicate(true);bad.proofs.clear();reject_state(k,bad,"missing proof state")
	bad=saved.duplicate(true);bad.routes={"hero":{"route_id":"absent","carrier_id":"missing","completed":false,"progress":0,"transport_mode":"walk","waiting_for":""}};reject_state(k,bad,"invalid saved route/carrier")
	# S2 fields introduced after the original eleven failures require equally strict restore guards.
	bad=saved.duplicate(true);bad.zones.clear();reject_state(k,bad,"missing zones")
	bad=saved.duplicate(true);bad.erase("candidate_law");reject_state(k,bad,"missing candidate")
	bad=saved.duplicate(true);bad.entities.hero.erase("intact");reject_state(k,bad,"missing entity intact")
	bad=saved.duplicate(true);bad.witnesses.w1.erase("water_seen_from");reject_state(k,bad,"missing water observation ledger")
	bad=saved.duplicate(true);bad.witnesses.w1.expose_streak="five";reject_state(k,bad,"invalid witness counter")
	bad=saved.duplicate(true);bad.occluder_enabled.clear();reject_state(k,bad,"missing occluder flags")
	bad=saved.duplicate(true);bad.actor_reach.hero="unknown";reject_state(k,bad,"invalid reach zone")
	bad=saved.duplicate(true);bad.phase="LAW_SELECTION";reject_state(k,bad,"selection without ready proof")
	bad=saved.duplicate(true);bad.zones.demo_pool.thermal_charge="cold";reject_state(k,bad,"thermal string")
	bad=saved.duplicate(true);bad.zones.demo_pool.phase="frozen";bad.zones.demo_pool.thermal_charge=15;reject_state(k,bad,"inconsistent hysteresis phase")
	bad=d.duplicate(true);bad.occluders[0].segment[0][0]+=1
	var changed=Kernel.new();changed.load_level(bad);check(not changed.restore(saved),"content digest rejects different geometry")
	bad=d.duplicate(true);bad.navigation.routes[0].requirements=[{"type":"execute_code","parameters":{}}];reject_definition(k,bad,"unknown route requirement")
	bad=d.duplicate(true);bad.proofs[0].predicates[0].type="eval";reject_definition(k,bad,"unknown predicate")
	bad=d.duplicate(true);bad.entities[0].properties.scheduled_effects=[{"at_tick":2,"phases":["PERFORMANCE"],"operation":"eval"}];reject_definition(k,bad,"unknown scheduled operation")
	bad=d.duplicate(true);bad.slots[0].position=[100,100];reject_definition(k,bad,"out of stage coordinate")
	print("VALIDATION TESTS: %d checks; %d failures"%[count,failures.size()])
	for issue in failures:printerr("FAIL: "+issue)
	DirAccess.make_dir_recursive_absolute("res://tests/reports")
	var file=FileAccess.open("res://tests/reports/validation.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":count,"failures":failures,"engine":Engine.get_version_info().string,"fresh_run":true},"  "));file.close()
	quit(0 if failures.is_empty() else 1)
func reject_definition(k,bad: Dictionary,label: String) -> void:
	var before: String=k.state_hash()
	check(not k.validate_definition(bad).is_empty() and not k.load_level(bad) and k.state_hash()==before,label+" rejected atomically")
func reject_state(k,bad: Dictionary,label: String) -> void:
	var before: String=k.state_hash();check(not k.restore(bad) and k.state_hash()==before,label+" rejected atomically")
func read_level(id: String) -> Dictionary:
	var path: String="res://tests/fixtures/kernel-baseline-L01.json" if id=="L01" else "res://data/levels/"+id+".json"
	return JSON.parse_string(FileAccess.get_file_as_string(path))
func check(ok: bool,message: String) -> void:
	count+=1
	if not ok:failures.append(message)
