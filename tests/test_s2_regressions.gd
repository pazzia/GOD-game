extends SceneTree
const Kernel=preload("res://core/simulation_kernel.gd")
var failures: Array[String]=[]
var count: int=0
func _initialize() -> void:
	paper_cases(); thermal_cases(); witness_cases(); vote_grace(); law_cases(); food_cases()
	print("S2 REGRESSIONS: %d checks; %d failures"%[count,failures.size()])
	for issue in failures: printerr("FAIL: "+issue)
	DirAccess.make_dir_recursive_absolute("res://tests/reports")
	var file=FileAccess.open("res://tests/reports/s2-regressions.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":count,"failures":failures,"engine":Engine.get_version_info().string,"fresh_run":true},"  "));file.close()
	quit(0 if failures.is_empty() else 1)
func paper_cases() -> void:
	var k=fresh("L21");place(k,"paper","stage_paper")
	check(k._paper_capacity("paper")==1,"baseline paper capacity1")
	place(k,"weight","stage_weight")
	check(not k.evaluate("load_contact",{"paper_id":"paper","load_id":"weight","min_mass":50}),"baseline paper cannot hold50")
	place(k,"frame","stage_frame")
	check(k.evaluate("load_contact",{"paper_id":"paper","load_id":"weight","min_mass":50}),"real frame and contact support50")
	place(k,"weight","weight_start")
	check(not k.evaluate("load_contact",{"paper_id":"paper","load_id":"weight","min_mass":50}),"nearby weight without contact is not proof")
	k.state.active_laws=["M03"];k.state.entities.frame.removed=true;k._recompute_effective()
	check(k.state.entities.paper.effective.load_capacity==150 and k._paper_capacity("paper")==150,"M03 capacity150 without frame on solid anchors")
	check(k.state.entities.paper.effective.flammable,"M03 does not remove flammability")
	k.state.entities.anchor_a.removed=true;k._recompute_effective()
	check(k._paper_capacity("paper")==0,"one missing anchor invalidates span")
	var d: Dictionary=data("L21");entity(d,"paper").properties.span_anchor_entity_ids=["anchor_a","anchor_a"]
	var kd=Kernel.new();var accepted: bool=kd.load_level(d)
	if accepted: place(kd,"paper","stage_paper")
	check(not accepted or not kd._span_anchors_valid("paper"),"duplicate anchor is never two anchors")
	d=data("L21");var sid: String=entity(d,"anchor_a").initial_slot
	for s in d.slots:
		if s.id==sid:s.position=[1,27]
	var kr=Kernel.new();accepted=kr.load_level(d)
	if accepted:place(kr,"paper","stage_paper")
	check(not accepted or not kr._span_anchors_valid("paper"),"remote anchor cannot support this span")
	d=data("L24");d.initial_active_laws=["M01","M03"]
	var kf=Kernel.new();kf.load_level(d);place(kf,"paper","stage_paper")
	check(kf._paper_capacity("paper")==5,"two M3 floating anchors minus paper1 leave load5")
	place(kf,"frame","stage_frame")
	check(kf._paper_capacity("paper")>=50,"grounded frame bypasses floating capacity for demonstration")
	entity(kf.definition,"frame").properties.grounded=false;kf._recompute_effective()
	check(kf._paper_capacity("paper")==5,"ungrounded frame does not bypass underlying capacity")
func thermal_cases() -> void:
	var k=fresh("L11");k.state.entities.oven.position=[14,17];k._step_thermal()
	check(k.state.zones.demo_water.thermal_charge==1,"heat at inclusive radius boundary")
	k=fresh("L11");k.state.entities.oven.position=[14,18];k._step_thermal()
	check(k.state.zones.demo_water.thermal_charge==0,"no heat outside radius")
	var d: Dictionary=data("L11")
	d.occluders.append({"id":"test_wall","owner_entity":"screen_a","active_slot":"screen_left","segment":[[10,14],[18,14]],"channels":["Thermal"]})
	var kb=Kernel.new();kb.load_level(d);place(kb,"screen_a","screen_left");kb.state.entities.oven.position=[14,17];kb._step_thermal()
	check(kb.state.zones.demo_water.thermal_charge==0,"Thermal wall blocks heat")
	d.occluders[-1].channels=["Vision"];kb=Kernel.new();kb.load_level(d);place(kb,"screen_a","screen_left");kb.state.entities.oven.position=[14,17];kb._step_thermal()
	check(kb.state.zones.demo_water.thermal_charge==1,"Vision-only wall does not block heat")
	k=fresh("L11");k.state.active_laws=["M02"];k.state.entities.oven.position=[14,17];k._recompute_effective();k._step_thermal()
	check(k.state.zones.demo_water.thermal_charge==-1,"M02 reverses real FIRE")
	d=data("L11");d.initial_active_laws=["M02"];entity(d,"oven").properties.emitter_class="HEATED_OBJECT"
	var kh=Kernel.new();kh.load_level(d);kh.state.entities.oven.position=[14,17];kh._step_thermal()
	check(kh.state.zones.demo_water.thermal_charge==1,"M02 does not reverse HEATED_OBJECT")
	k=fresh("L11");k.state.entities.oven.enabled=false;k.state.zones.demo_water.phase="frozen";k.state.zones.demo_water.thermal_charge=-1;k._step_thermal()
	check(k.state.zones.demo_water.phase=="frozen","neutral drift retains frozen hysteresis")
	k.state.entities.oven.enabled=true;k.state.entities.oven.position=[14,17];k.state.zones.demo_water.thermal_charge=9;k._step_thermal()
	check(k.state.zones.demo_water.phase=="liquid","thaw at positive10")
func witness_cases() -> void:
	var d: Dictionary=data("L11");d.witnesses=[d.witnesses[0]];d.required_votes=1
	d.witnesses[0].views=[{"id":"early","eye_position":[3,3],"look_at":[14,14],"from_tick":0,"duration_ticks":5,"clear_ticks":1},{"id":"late","eye_position":[3,3],"look_at":[14,14],"from_tick":50,"duration_ticks":50,"clear_ticks":1}]
	var k=Kernel.new();k.load_level(d);place(k,"cold_pack","stage_cold");place(k,"screen_a","screen_left");k.dispatch({"type":"BeginPerformance"});k.advance_ticks(60)
	check(not k.state.proofs.M02.ready,"liquid then unseen transition then ice is not proof")
	check(not k.state.witnesses.w1.water_transition.get("demo_water",false),"transition missed during MOVING is not recorded")
	d=data("L11");d.witnesses=[d.witnesses[0]];d.required_votes=1
	d.occluders.append({"id":"hidden_transition","owner_entity":"screen_a","active_slot":"screen_left","segment":[[8,13],[19,13]],"channels":["Vision"]})
	entity(d,"screen_a").properties.scheduled_effects=[]
	for pair in [[0,false],[10,true],[30,false]]:entity(d,"screen_a").properties.scheduled_effects.append({"at_tick":pair[0],"phases":["PERFORMANCE"],"operation":"set_occluder_enabled","target_occluder_id":"hidden_transition","value":pair[1]})
	var ku=Kernel.new();ku.load_level(d);place(ku,"cold_pack","stage_cold");place(ku,"screen_a","screen_left");ku.dispatch({"type":"BeginPerformance"});ku.advance_ticks(100)
	check(not ku.state.proofs.M02.ready,"timed occluder hiding actual freeze cannot manufacture proof later")
	d=data("L11")
	for z in d.zones:
		if z.id=="demo_water":z.initial_phase="frozen";z.initial_thermal_charge=-25
	var ki=Kernel.new();ki.load_level(d);place(ki,"cold_pack","stage_cold");place(ki,"screen_a","screen_left");ki.dispatch({"type":"BeginPerformance"});ki.advance_ticks(150)
	check(not ki.state.proofs.M02.ready,"initial frozen water is not proof")
func vote_grace() -> void:
	var k=fresh("L03")
	for pair in [["float","stage_float"],["stone","stage_stone"],["screen_a","screen_left"],["screen_b","screen_right"]]:place(k,pair[0],pair[1])
	k.dispatch({"type":"BeginPerformance"});k.advance_ticks(40);k.state.entities.screen_a.removed=true;k.advance_ticks(4)
	check(k.state.witnesses.w1.eligible_vote,"confirmed voice survives four suspicious ticks")
	k.advance_ticks(1)
	check(not k.state.witnesses.w1.eligible_vote and k.state.witnesses.w1.exposed,"fifth consecutive exposure invalidates voice")
func law_cases() -> void:
	var k=fresh("L26");k.state.phase="PROOF_ACCEPTED";k.state.proofs.M03.ready=true;k.state.proofs.M03.votes=3
	for w in k.state.witnesses.values():
		w.eligible_vote=true
		for vid in w.view_completed:w.view_completed[vid]=true
	var before: String=k.state_hash();var laws: Array=k.state.active_laws.duplicate();var props: Dictionary=k.state.entities.paper.effective.duplicate(true)
	var r: Dictionary=k.dispatch({"type":"ActivateLaw","payload":{"myth_id":"M03","replace_law_id":null}})
	check(r.accepted and k.state.phase=="LAW_SELECTION" and k.state.active_laws==laws and laws.size()==2,"third law requests replacement with two old laws intact")
	check(k.state.entities.paper.effective==props,"selection leaves properties unchanged")
	k.dispatch({"type":"CancelLawSelection"});check(k.state_hash()==before,"cancel returns exact logical hash")
	r=k.dispatch({"type":"ActivateLaw","payload":{"myth_id":"M03","replace_law_id":"missing_law"}})
	check(not r.accepted and k.state_hash()==before,"invalid replacement rejects atomically")
	r=k.dispatch({"type":"ActivateLaw","payload":{"myth_id":"M03","replace_law_id":"M01"}})
	check(r.accepted and k.state.active_laws==["M02","M03"],"valid replacement commits exactly two laws")
	before=k.state_hash();r=k.dispatch({"type":"ActivateLaw","payload":{"myth_id":"M03"}})
	check(not r.accepted and k.state_hash()==before,"active-law reapplication has no effects")
func food_cases() -> void:
	var k=fresh("L12");place(k,"bread","bread_box");k.dispatch({"type":"Interact","payload":{"entity_id":"box","action":"close"}});k.state.entities.food_oven.position=[5,22]
	var charge: int=k.state.zones.bread_zone.thermal_charge
	for i in range(30):k._step_thermal()
	check(k.state.zones.bread_zone.thermal_charge==charge and k.state.entities.bread.intact,"closed box blocks actual cooling of ownerzone")
	k.dispatch({"type":"Interact","payload":{"entity_id":"box","action":"open"}})
	for i in range(30):k._step_thermal()
	check(k.state.zones.bread_zone.thermal_charge< -10 and not k.state.entities.bread.intact,"open box permits cooling and damage")
	k.dispatch({"type":"Interact","payload":{"entity_id":"box","action":"close"}});check(not k.state.entities.bread.intact,"closing after damage does not resurrect food")
	k=fresh("L12");var before: String=k.state_hash();var r: Dictionary=k.dispatch({"type":"AssignRoute","payload":{"actor_id":"delivery","route_id":"cross"}})
	check(not r.accepted and k.state_hash()==before,"unloaded food cannot teleport into payload")
	check(k._task_mass("delivery",{"carrier_id":"hero","transport_mode":"carried"})==4,"included crate mass2 plus hero2 counts exactly once")
func fresh(id: String):
	var k=Kernel.new()
	if not k.load_level(data(id)):failures.append("fixture load "+id+": "+str(k.validate_definition(data(id))))
	return k
func data(id: String) -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/"+id+".json"))
func entity(d: Dictionary,id: String) -> Dictionary:
	for e in d.entities:
		if e.id==id:return e
	return {}
func place(k,eid: String,sid: String) -> void:
	var r: Dictionary=k.dispatch({"type":"PlaceProp","payload":{"entity_id":eid,"slot_id":sid}})
	if not r.accepted:failures.append("fixture place "+eid+": "+r.reason_code)
func check(ok: bool,message: String) -> void:
	count+=1
	if not ok:failures.append(message)
