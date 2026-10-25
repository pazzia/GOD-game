extends SceneTree
## Actual professor tutorial: observed arrangement, explicit law, then useful result.
const Kernel=preload("res://core/simulation_kernel.gd")
var checks: int=0
var failures: Array[String]=[]

func _initialize() -> void:
	for front in [false,true]:
		for folded in [false,true]:
			var k=fresh("L01")
			if front: command(k,"PlaceProp",{"entity_id":"screen_a","slot_id":"screen_left"})
			if folded: command(k,"Interact",{"entity_id":"screen_a","action":"fold"})
			var view: Dictionary=k.visibility_for("w1")
			check(view.method_visible==not front,"method visibility follows the actual screen geometry")
			check((view.visible_results>=2)==(not front or folded),"a tall front screen also hides the stone")
			command(k,"BeginPerformance")
			k.advance_ticks(30)
			var valid: bool=front and folded
			check((k.state.phase=="PROOF_ACCEPTED")==valid,"four arrangements have exactly one valid demonstration")
			check(k.state.active_laws.is_empty(),"observed demonstration cannot activate a law")
			if not valid:
				check(k.state.failure_reason==("RESULT_OBSCURED" if front else "METHOD_VISIBLE"),"failed demonstration names the visible cause")
	var k=prepared()
	check(k.state.entities.stone.effective.carry_capacity<k._entities.marfa.mass_units,"small float supports the demonstration stone but cannot carry Marfa before the law")
	var before: String=k.state_hash()
	var rejected: Dictionary=k.dispatch({"type":"Interact","payload":{"entity_id":"float","action":"remove"}})
	check(not rejected.accepted and rejected.reason_code=="LAW_NOT_ACTIVE" and k.state_hash()==before,"fixed float cannot be removed before the law")
	rejected=k.dispatch({"type":"PlaceProp","payload":{"entity_id":"stone","slot_id":"stage_stone"}})
	check(not rejected.accepted and rejected.reason_code=="IMMOVABLE" and k.state_hash()==before,"tutorial stone is already in place and not a second relocation puzzle")
	rejected=k.dispatch({"type":"Interact","payload":{"entity_id":"hero","action":"fold"}})
	check(not rejected.accepted and rejected.reason_code=="UNSUPPORTED_ACTION" and k.state_hash()==before,"fold is a typed screen capability")
	rejected=k.dispatch({"type":"Interact","payload":{"entity_id":"screen_a","action":"fold"}})
	check(not rejected.accepted and rejected.reason_code=="ALREADY_IN_STATE" and k.state_hash()==before,"repeating the same fold cannot create a fake undo step")
	command(k,"BeginPerformance");k.advance_ticks(30)
	check(k.state.phase=="PROOF_ACCEPTED" and not k.state.proofs.M01.sealed,"proof awaits an explicit Atlas action")
	var accepted_hash: String=k.state_hash()
	command(k,"Interact",{"entity_id":"screen_a","action":"unfold"})
	check(k.state.phase=="PLAN_SHOW" and not k.state.proofs.M01.ready,"editing an unsealed demonstration invalidates its proof")
	rejected=k.dispatch({"type":"ActivateLaw","payload":{"myth_id":"M01"}})
	check(not rejected.accepted,"a stale observed arrangement cannot be sealed")
	command(k,"Undo")
	check(k.state_hash()==accepted_hash,"one-step undo restores both the exact arrangement and its valid unsealed proof")
	command(k,"PlaceProp",{"entity_id":"screen_a","slot_id":"tray_screen_a"})
	check(k.state.phase=="PLAN_SHOW" and not k.state.proofs.M01.ready,"moving an accepted screen invalidates the unsealed proof")
	command(k,"Undo")
	command(k,"ActivateLaw",{"myth_id":"M01"})
	check(k.state.phase=="PLAN_RESOLUTION" and k.state.proofs.M01.sealed,"Atlas sealing is a separate committed phase")
	command(k,"Interact",{"entity_id":"float","action":"remove"})
	check(k.state.entities.float.removed and k.state.entities.stone.support,"stone remains supported after the physical float is removed")
	check(k.state.entities.stone.effective.carry_capacity>=k._entities.marfa.mass_units,"new law explicitly supports Marfa's carried load")
	check(k.state.routes.is_empty() and k.state.phase!="SUCCESS","sealing and removal do not silently route the person or complete the level")
	command(k,"AssignRoute",{"actor_id":"marfa","route_id":"cross"})
	check(k.state.phase=="PLAN_RESOLUTION" and not k.state.routes.marfa.completed,"choosing the crossing does not teleport Marfa")
	command(k,"RunResolution");k.advance_ticks(100)
	check(k.state.phase=="SUCCESS" and k.assert_predicate("route_completed:marfa:cross"),"victory waits for Marfa to reach her bakery bank")
	check(k.state.entities.marfa.position==[21,12],"route ends on the authored destination bank")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(k.snapshot()))
	before=k.state_hash()
	check(k.restore(saved) and k.state_hash()==before,"new folded state survives JSON save/restore exactly")
	var bad: Dictionary=saved.duplicate(true);bad.entities.screen_a.folded="yes"
	check(not k.restore(bad) and k.state_hash()==before,"malformed saved folded state rejects atomically")
	bad=saved.duplicate(true);bad.entities.hero.folded=true
	check(not k.restore(bad) and k.state_hash()==before,"non-foldable actors cannot receive forged folded state")
	bad=saved.duplicate(true);bad.rules_version="0.2.0-recovered"
	check(not k.restore(bad) and k.state_hash()==before,"an incompatible old checkpoint cannot corrupt the new tutorial")
	# Correcting a later trial observes a new arrangement, without a belief reset.
	k=fresh("L01");command(k,"BeginPerformance");k.advance_ticks(30)
	check(k.state.witnesses.w1.exposed,"visible method fails this demonstration")
	command(k,"Undo")
	command(k,"PlaceProp",{"entity_id":"screen_a","slot_id":"screen_left"})
	command(k,"Interact",{"entity_id":"screen_a","action":"fold"})
	command(k,"BeginPerformance");k.advance_ticks(30)
	check(k.state.phase=="PROOF_ACCEPTED","the same observer can validate a corrected external arrangement")
	command(k,"Interact",{"entity_id":"screen_a","action":"unfold"})
	command(k,"Undo")
	command(k,"StopPerformance")
	check(k.state.phase=="PLAN_SHOW" and k.state.entities.screen_a.folded,"accepted-proof undo still permits returning to the exact trial preparation")
	var definition: Dictionary=read_level("L01")
	definition.occluders[0].folded_segment=[[9,10],[9,10]]
	check(not k.validate_definition(definition).is_empty(),"degenerate folded visibility geometry rejects")
	definition=read_level("L01");definition.demonstration_timeout_ticks=0
	check(not k.validate_definition(definition).is_empty(),"zero-length demonstration horizon rejects")
	definition=read_level("L01")
	for entity in definition.entities:
		if entity.id=="float":entity.properties.remove_requires_law="UNKNOWN"
	check(not k.validate_definition(definition).is_empty(),"removal requires a recognized Atlas law")
	k=fresh("L02")
	check(k.state.active_laws==["M01"] and k.state.entities.anchor.effective.buoyant,"next stage explicitly starts with the transferred stone law")
	check(not k.state.entities.boat.moored,"floating stone anchor no longer secures the boat")
	command(k,"Interact",{"entity_id":"mooring","action":"attach","target_entity_id":"bollard"})
	check(k.state.entities.boat.moored,"a rope attached to grounded wood secures the boat")
	run_replay(k,"res://tests/L02_solution.json",true)
	check(k.state.phase=="SUCCESS","anchor-first follow-up is a complete playable puzzle")
	thermal_switch_cases()
	sailing_cases()
	print("SCIENTIST KERNEL: %d checks; %d failures"%[checks,failures.size()])
	for failure in failures:printerr("FAIL: "+failure)
	DirAccess.make_dir_recursive_absolute("res://tests/reports")
	var file=FileAccess.open("res://tests/reports/scientist-kernel.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Actual L01 proof/law/crossing and undo/save guards, L02 anchor consequence, L11 controlled oven switch and thermal persistence, L18 wet sailing geometry and both authored solutions"},"  "));file.close()
	quit(0 if failures.is_empty() else 1)

func thermal_switch_cases() -> void:
	var k=fresh("L11")
	var replay: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/replays/L11_solution.json"))
	for step in replay.steps:
		if step.op=="command":
			if step.type=="ActivateLaw":break
			command(k,step.type,step.get("payload",{}))
		elif step.op=="advance_ticks":k.advance_ticks(int(step.count))
	check(k.state.phase=="PROOF_ACCEPTED" and k.state.proofs.M02.ready,"real L11 demonstration accepts before source-switch tests")
	var proof_hash: String=k.state_hash()
	var response: Dictionary=k.dispatch({"type":"Interact","payload":{"entity_id":"oven","action":"enable"}})
	check(not response.accepted and response.reason_code=="ALREADY_IN_STATE" and k.state_hash()==proof_hash,"enabling an already lit oven does not consume undo or invalidate proof")
	response=k.dispatch({"type":"Interact","payload":{"entity_id":"oven","action":"disable"}})
	var invalidated: bool=false
	for event in response.events:
		if event.type=="proof_invalidated":invalidated=true
	check(response.accepted and invalidated and not k.state.entities.oven.enabled and not k.state.entities.oven.effective.enabled,"switching the observed source is an actual typed state transition")
	check(k.state.phase=="PLAN_SHOW" and not k.state.proofs.M02.ready,"source change invalidates the unsealed demonstration")
	command(k,"Undo")
	check(k.state_hash()==proof_hash,"undo restores the exact lit source and accepted demonstration")
	command(k,"ActivateLaw",{"myth_id":"M02"})
	var sealed: Dictionary=k.snapshot()
	var sealed_hash: String=k.state_hash()
	response=k.dispatch({"type":"Interact","payload":{"entity_id":"cold_pack","action":"disable"}})
	check(not response.accepted and response.reason_code=="UNSUPPORTED_ACTION" and k.state_hash()==sealed_hash,"passive cold pack has no artificial off switch")
	response=k.dispatch({"type":"Interact","payload":{"entity_id":"hero","action":"disable"}})
	check(not response.accepted and response.reason_code=="UNSUPPORTED_ACTION" and k.state_hash()==sealed_hash,"non-emitting actors cannot be switched off")
	command(k,"Interact",{"entity_id":"oven","action":"disable"})
	check(not k.state.entities.oven.enabled and "M02" in k.state.active_laws,"post-law source can be extinguished without revoking the Atlas law")
	var disabled: Dictionary=JSON.parse_string(JSON.stringify(k.snapshot()))
	var restored=Kernel.new();check(restored.load_level(read_level("L11")) and restored.restore(disabled),"disabled source survives a real JSON checkpoint roundtrip")
	check(not restored.state.entities.oven.enabled and not restored.state.entities.oven.effective.enabled,"saved disabled source is still off after recomputing derived properties")
	var disabled_hash: String=restored.state_hash()
	var bad: Dictionary=disabled.duplicate(true);bad.entities.oven.enabled="off"
	check(not restored.restore(bad) and restored.state_hash()==disabled_hash,"malformed enabled state rejects atomically")
	var lit=Kernel.new();check(lit.load_level(read_level("L11")) and lit.restore(sealed),"load the same sealed scene for an enabled-source thermal comparison")
	var charge: int=k.state.zones.crossing_water.thermal_charge
	lit._step_thermal();k._step_thermal()
	check(lit.state.zones.crossing_water.thermal_charge<charge and k.state.zones.crossing_water.thermal_charge>=charge,"disabled M02 oven contributes no cooling where the lit oven really cools the crossing water")
	command(k,"Undo")
	check(k.state_hash()==sealed_hash and k.state.entities.oven.enabled,"undo after switching off restores source and complete pre-switch thermal state")
	command(k,"Interact",{"entity_id":"oven","action":"disable"})
	var off_hash: String=k.state_hash()
	response=k.dispatch({"type":"Interact","payload":{"entity_id":"oven","action":"disable"}})
	check(not response.accepted and response.reason_code=="ALREADY_IN_STATE" and k.state_hash()==off_hash,"repeated off command is rejected without another history step")
	command(k,"Interact",{"entity_id":"oven","action":"enable"})
	check(k.state.entities.oven.enabled and k.state.entities.oven.effective.enabled,"the controlled oven can be lit again")
	var passive=fresh("L15")
	var passive_hash: String=passive.state_hash()
	response=passive.dispatch({"type":"Interact","payload":{"entity_id":"heated_stone","action":"disable"}})
	check(not response.accepted and response.reason_code=="UNSUPPORTED_ACTION" and passive.state_hash()==passive_hash,"a heated stone has no controlled source switch")
	var running=fresh("L11");command(running,"BeginPerformance")
	var running_hash: String=running.state_hash()
	response=running.dispatch({"type":"Interact","payload":{"entity_id":"oven","action":"disable"}})
	check(not response.accepted and response.reason_code=="WRONG_PHASE" and running.state_hash()==running_hash,"source cannot be edited during a running demonstration")
	var remote_definition: Dictionary=read_level("L11")
	remote_definition.zones.append({"id":"remote_source","kind":"REACH"})
	for slot in remote_definition.slots:
		if slot.id=="oven_start":slot.zone_id="remote_source"
	var remote=Kernel.new();check(remote.load_level(remote_definition),"author a valid but unreachable controlled source")
	var remote_hash: String=remote.state_hash()
	response=remote.dispatch({"type":"Interact","payload":{"entity_id":"oven","action":"disable"}})
	check(not response.accepted and response.reason_code=="OUT_OF_REACH" and remote.state_hash()==remote_hash,"source switches respect the same reachability rule as other object actions")
	var invalid_definition: Dictionary=read_level("L11")
	for entity in invalid_definition.entities:
		if entity.id=="oven":entity.properties.switchable="yes"
	check(not k.validate_definition(invalid_definition).is_empty(),"switchable capability must be a boolean")
	for passive_id in ["cold_pack","hero"]:
		invalid_definition=read_level("L11")
		for entity in invalid_definition.entities:
			if entity.id==passive_id:entity.properties.switchable=true
		check(not k.validate_definition(invalid_definition).is_empty(),"a switch cannot be added to a passive or non-emitting object")
	invalid_definition=read_level("L15")
	for entity in invalid_definition.entities:
		if entity.id=="heated_stone":entity.properties.switchable=true
	check(not k.validate_definition(invalid_definition).is_empty(),"a passive hot stone cannot be declared a controlled fire source")

func sailing_cases() -> void:
	var definition: Dictionary=read_level("L18")
	var k=fresh("L18")
	var boat_route: Dictionary=k._find(definition.navigation.routes,"boat_route")
	check(k._point_in_zone(k.state.entities.boat.position,"boat_water"),"L18 boat starts in its real water corridor")
	var crossing: Dictionary=k._find(definition.navigation.routes,"cross")
	var pedestrian_end: Array=k._find(definition.navigation.nodes,crossing.nodes[-1]).position
	check(not k._point_in_zone(pedestrian_end,"boat_water") and not k._point_in_zone(pedestrian_end,"crossing_water"),"authored pedestrian destination remains a dry bank")
	var warm_slot: Array=k._find(definition.slots,"warm_boat").position
	check(not k._position_over_water(warm_slot),"passive heated stone warms the boat channel from a dry bank")
	for i in range(boat_route.nodes.size()-1):
		var a: Array=k._find(definition.navigation.nodes,boat_route.nodes[i]).position
		var b: Array=k._find(definition.navigation.nodes,boat_route.nodes[i+1]).position
		for fraction in [0.0,0.25,0.5,0.75,1.0]:
			var point: Array=[lerpf(float(a[0]),float(b[0]),fraction),lerpf(float(a[1]),float(b[1]),fraction)]
			check(k._point_in_zone(point,"boat_water") and not k._point_in_zone(point,"crossing_water"),"every sampled boat-route segment stays in its separate boat water")
	# Frozen water is valid for planning; the existing route requirement waits for thaw.
	command(k,"AssignRoute",{"actor_id":"boat","route_id":"boat_route"})
	var start: Array=k.state.entities.boat.position.duplicate()
	command(k,"RunResolution");k.advance_ticks(1)
	check(k.state.routes.boat.progress==0 and k.state.entities.boat.position==start and k.state.routes.boat.waiting_for=="water_phase:boat_water:liquid","planned boat waits safely for actual liquid water")
	for name in ["L18_solution.json","L18_alternative.json"]:
		k=fresh("L18")
		run_replay(k,"res://tests/replays/"+name)
		check(k.state.phase=="SUCCESS" and k.assert_predicate("route_completed:boat:boat_route"),name+" completes the actual boat crossing")
		check(k.state.entities.stone.support and k.state.zones.crossing_water.phase=="frozen" and k.state.zones.boat_water.phase=="liquid",name+" preserves pedestrian support and the separate warm boat channel together")
		check(k.state.active_laws==["M01","M02"] and k._point_in_zone(k.state.entities.boat.position,"boat_water"),name+" retains the transferred Atlas laws and finishes in water")
	# A dry endpoint is an invalid boat plan, even if a generic route is authored there.
	var dry_definition: Dictionary=definition.duplicate(true)
	var dry_route: Dictionary=boat_route.duplicate(true);dry_route.id="dry_sailing_test"
	dry_route.nodes=[boat_route.nodes[0],crossing.nodes[-1]]
	dry_definition.navigation.routes.append(dry_route)
	var dry=Kernel.new();check(dry.load_level(dry_definition),"load a structurally valid route with a dry boat destination")
	var dry_hash: String=dry.state_hash()
	var response: Dictionary=dry.dispatch({"type":"AssignRoute","payload":{"actor_id":"boat","route_id":"dry_sailing_test"}})
	check(not response.accepted and response.reason_code=="SAILING_REQUIRES_WATER" and dry.state_hash()==dry_hash,"boat cannot be assigned a dry-bank route")
	# Wet endpoints are insufficient: a straight segment may cross a concave dry gap.
	var gap_definition: Dictionary=definition.duplicate(true)
	for slot in gap_definition.slots:
		if slot.id=="boat_start":slot.position=[19,20]
	for node in gap_definition.navigation.nodes:
		if node.id==boat_route.nodes[0]:node.position=[19,20]
		if node.id==boat_route.nodes[-1]:node.position=[23,20]
	for route in gap_definition.navigation.routes:
		if route.id=="boat_route":route.nodes=[boat_route.nodes[0],boat_route.nodes[-1]]
	for zone in gap_definition.zones:
		if zone.id=="boat_water":zone.polygon=[[18,18],[24,18],[24,22],[22,22],[22,19],[20,19],[20,22],[18,22]]
	var gap=Kernel.new();check(gap.load_level(gap_definition),"load a valid concave water polygon for segment safety")
	check(gap._point_in_zone([19,20],"boat_water") and gap._point_in_zone([23,20],"boat_water") and not gap._point_in_zone([21,20],"boat_water"),"both endpoints are wet while the connecting segment crosses dry ground")
	var gap_hash: String=gap.state_hash()
	response=gap.dispatch({"type":"AssignRoute","payload":{"actor_id":"boat","route_id":"boat_route"}})
	check(not response.accepted and response.reason_code=="SAILING_REQUIRES_WATER" and gap.state_hash()==gap_hash,"sailing guard checks segment interiors, not just waypoint endpoints")

func prepared():
	var k=fresh("L01")
	command(k,"PlaceProp",{"entity_id":"screen_a","slot_id":"screen_left"})
	command(k,"Interact",{"entity_id":"screen_a","action":"fold"})
	return k
func fresh(id: String):
	var k=Kernel.new();check(k.load_level(read_level(id),42),"load authored "+id);return k
func read_level(id: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/"+id+".json"))
func command(k,type: String,payload: Dictionary={}) -> void:
	var result: Dictionary=k.dispatch({"type":type,"payload":payload})
	check(result.accepted,type+" accepted: "+result.reason_code)
func run_replay(k,path: String,skip_attach: bool=false) -> void:
	var replay: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	for step in replay.steps:
		if step.op=="command":
			if skip_attach and step.type=="Interact":continue
			command(k,step.type,step.get("payload",{}))
		elif step.op=="advance_ticks":k.advance_ticks(int(step.count))
		elif step.op=="assert":check(k.assert_predicate(step.predicate),step.predicate)
func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message)
