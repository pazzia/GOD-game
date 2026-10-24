extends SceneTree
const Kernel=preload("res://core/simulation_kernel.gd")
var failures: Array[String]=[]
var count: int=0
func _initialize() -> void:
	var k=fresh("L01")
	check(k._segments_intersect(Vector2(0,0),Vector2(10,0),Vector2(3,0),Vector2(6,0)),"collinear opaque overlap blocks")
	check(k._segments_intersect(Vector2(0,0),Vector2(5,0),Vector2(5,0),Vector2(5,5)),"target touching opaque endpoint blocks")
	check(k._segments_intersect(Vector2(0,0),Vector2(5,5),Vector2(0,0),Vector2(0,5)),"eye on opaque boundary blocks")
	var before: String=k.state_hash()
	var r: Dictionary=k.dispatch({"type":"PlaceProp","payload":{"entity_id":"float","slot_id":"stage_float"},"precondition_hash":"stale"})
	check(not r.accepted and k.state_hash()==before,"stale command rejects atomically")
	k=prepared();k.dispatch({"type":"BeginPerformance"});k.advance_ticks(10)
	check(k.state.witnesses.w1.view_progress.front==10,"ten clear ticks accumulate")
	k.state.entities.screen_a.removed=true;k.advance_ticks(1)
	check(k.state.witnesses.w1.view_progress.front==0,"one visible method tick clears unconfirmed progress")
	k=prepared();k.state.entities.stone.removed=true;k.state.entities.screen_a.removed=true;k.dispatch({"type":"BeginPerformance"});k.advance_ticks(5)
	check(k.state.witnesses.w1.exposed,"visible method exposes even with invalid result")
	var d: Dictionary=data("L01")
	d.witnesses[0].views=[{"id":"early","eye_position":[3,3],"look_at":[14,14],"from_tick":0,"duration_ticks":3,"clear_ticks":3},{"id":"late","eye_position":[3,3],"look_at":[14,14],"from_tick":10,"duration_ticks":20,"clear_ticks":10}]
	k=Kernel.new();k.load_level(d)
	for pair in [["float","stage_float"],["stone","stage_stone"]]:place(k,pair[0],pair[1])
	k.dispatch({"type":"BeginPerformance"});k.advance_ticks(12)
	check(not k.state.witnesses.w1.exposed,"MOVING interval resets exposure streak")
	k=prepared();before=k.state_hash();k.dispatch({"type":"BeginRehearsal"});k.advance_ticks(100)
	check(k.state_hash()==before,"rehearsal restores exact semantic hash")
	var saved: Dictionary=k.snapshot();var parsed: Dictionary=JSON.parse_string(JSON.stringify(saved))
	check(k.restore(parsed) and k.state_hash()==before,"JSON snapshot roundtrip preserves hash")
	parsed.rules_version="unsupported";check(not k.restore(parsed),"unsupported rules version rejects")
	# A short loss of result preserves progress; the third gap tick resets it.
	d=data("L01");d.occluders.append({"id":"test_result_wall","owner_entity":"screen_a","active_slot":"screen_left","segment":[[8,13],[19,13]],"channels":["Vision"]})
	k=Kernel.new();k.load_level(d)
	for pair in [["float","stage_float"],["stone","stage_stone"],["screen_a","screen_left"]]:place(k,pair[0],pair[1])
	k.state.occluder_enabled.test_result_wall=false;k.dispatch({"type":"BeginPerformance"});k.advance_ticks(10);k.state.occluder_enabled.test_result_wall=true;k.advance_ticks(2)
	check(k.state.witnesses.w1.view_progress.front==10,"two missing-result ticks preserve progress")
	k.advance_ticks(1);check(k.state.witnesses.w1.view_progress.front==0,"third missing-result tick resets progress")
	k=fresh("L03")
	for pair in [["float","stage_float"],["stone","stage_stone"],["screen_a","screen_left"],["screen_b","screen_right"]]:place(k,pair[0],pair[1])
	k.dispatch({"type":"BeginPerformance"});k.advance_ticks(40)
	check(not k.state.witnesses.w3.eligible_vote and k.state.proofs.M01.votes==2,"inspector needs all required views")
	k.advance_ticks(10);check(k.state.witnesses.w3.status=="MOVING_TO_VIEW","inspector travels without observing")
	k.advance_ticks(35);check(k.state.phase=="PROOF_ACCEPTED" and k.state.phase_tick==85,"second required view finishes at exact85 ticks")
	before=k.state_hash();k.advance_ticks(100);check(k.state_hash()==before,"paused proof phase does not advance time")
	k=prepared();before=k.state_hash();place(k,"stone","tray_stone");k.dispatch({"type":"Undo"});check(k.state_hash()==before,"undo restores complete semantic state")
	var own: Dictionary=k.snapshot();own.entities.stone.removed=true;check(not k.state.entities.stone.removed,"snapshot does not alias live state")
	r=k.dispatch({"type":"RunUnknownCode","payload":{}});check(not r.accepted and k.state_hash()==before,"unknown command rejects without mutation")
	var hashes: Array=[]
	for fps in [30,60,120]:hashes.append(clock_replay(fps,data("L01")))
	check(hashes[0]==hashes[1] and hashes[1]==hashes[2],"same replay through actual30/60/120 render-delta adapters yields same hash")
	check(clock_replay(60,reverse_keys(data("L01")))==hashes[1],"dictionary insertion order does not change logic/content hash")
	# Checkpoint saves pre-action state until a law has really committed.
	k=prepared();before=k.state_hash();k.dispatch({"type":"BeginPerformance"});k.advance_ticks(12)
	check(JSON.stringify(k._canonical(k.stable_checkpoint())).sha256_text()==before,"active show exports pre-action checkpoint")
	k.advance_ticks(30);k.dispatch({"type":"ActivateLaw","payload":{"myth_id":"M01"}})
	check(k.stable_checkpoint().active_laws==["M01"] and k.stable_checkpoint().phase=="PLAN_RESOLUTION","law commit exports new stable checkpoint")
	# Frozen water remains a solid support after M01 is revoked; it is not open-water proof.
	k=fresh("L01");place(k,"stone","stage_stone")
	k.state.zones.demo_pool.phase="frozen";k.state.zones.demo_pool.thermal_charge=-20;k._recompute_effective()
	check(k.state.entities.stone.support,"ordinary stone is supported by frozen surface")
	check(not k.evaluate("over_water",{"entity_id":"stone","zone_id":"demo_pool"}),"ice is not open-water evidence for M01")
	k.state.active_laws=["M01"];k._recompute_effective();k.state.active_laws=[];k._recompute_effective()
	check(k.state.entities.stone.support,"revoking M01 leaves stone on ice supported")
	k.state.zones.demo_pool.phase="liquid";k.state.zones.demo_pool.thermal_charge=10;k._recompute_effective()
	check(not k.state.entities.stone.support,"thaw removes support from ordinary stone without float")
	# Suspension is a real second support, with explicit geometry and capacity.
	d=data("L08")
	for e in d.entities:
		if e.id=="thread":e.properties.support_offset=[-4,3]
	k=Kernel.new();k.load_level(d,9);place(k,"stone","stage_stone");k.state.entities.float.removed=true;k._recompute_effective()
	check(k.state.entities.stone.support,"correctly offset thread supports stone without float")
	k._entities.thread.properties.support_offset=[-3,3];k._recompute_effective()
	check(not k.state.entities.stone.support,"wrong suspension offset is not support")
	k._entities.thread.properties.support_offset=[-4,3];k._entities.thread.properties.support_capacity=2;k._recompute_effective()
	check(not k.state.entities.stone.support,"thread below stone mass capacity is not support")
	print("KERNEL TESTS: %d checks; %d failures"%[count,failures.size()])
	for issue in failures:printerr("FAIL: "+issue)
	DirAccess.make_dir_recursive_absolute("res://tests/reports")
	var file=FileAccess.open("res://tests/reports/kernel.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":count,"failures":failures,"engine":Engine.get_version_info().string,"fresh_run":true},"  "));file.close()
	quit(0 if failures.is_empty() else 1)
func clock_replay(fps: int,d: Dictionary) -> String:
	var k=Kernel.new();k.load_level(d,42)
	var replay: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/L01_solution.json"))
	for step in replay.steps:
		if step.op=="command":k.dispatch(step)
		elif step.op=="advance_ticks":
			var accumulator: float=0
			for frame in range(int(step.count*fps/10)+2):
				accumulator+=1.0/fps
				while accumulator>=.1:
					accumulator-=.1;k.advance_ticks(1)
	return k.state_hash()
func reverse_keys(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary={};var keys: Array=value.keys();keys.reverse()
		for key in keys:result[key]=reverse_keys(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item in value:result.append(reverse_keys(item))
		return result
	return value
func prepared():
	var k=fresh("L01")
	for pair in [["float","stage_float"],["stone","stage_stone"],["screen_a","screen_left"]]:place(k,pair[0],pair[1])
	return k
func fresh(id: String):var k=Kernel.new();k.load_level(data(id),9);return k
func data(id: String) -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/"+id+".json"))
func place(k,eid: String,sid: String) -> void:
	var result: Dictionary=k.dispatch({"type":"PlaceProp","payload":{"entity_id":eid,"slot_id":sid}})
	if not result.accepted:failures.append("fixture place "+eid+": "+result.reason_code)
func check(ok: bool,message: String) -> void:
	count+=1
	if not ok:failures.append(message)
