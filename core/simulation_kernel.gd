class_name SimulationKernel
extends RefCounted
## Authoritative 10 Hz state machine. No nodes, audio, wall clock, network or physics.
const Validator = preload("res://core/content_validator.gd")
const RULES_VERSION = "0.5.0-scientist"
const ACTIVE_PHASES = ["PERFORMANCE","REHEARSAL","RUN_RESOLUTION"]
const PLAN_PHASES = ["PLAN_SHOW","PLAN_RESOLUTION"]
const LAWS = ["M01","M02","M03"]
var definition: Dictionary = {}
var state: Dictionary = {}
var _slots: Dictionary = {}
var _entities: Dictionary = {}
var _history: Array = []
var _events: Array = []
var _rehearsal_origin: Dictionary = {}
var _action_origin: Dictionary = {}
var _initial_state: Dictionary = {}
var _event_seq: int = 0
var _phase_changes: Dictionary = {}
var _pre_observation: Dictionary = {}

func validate_definition(data: Dictionary) -> Array[String]:
	return Validator.new().validate(data)

func load_level(data: Dictionary, seed_value: int=1) -> bool:
	if seed_value<0 or not validate_definition(data).is_empty(): return false
	definition=_normalize_numbers(data)
	_slots.clear(); _entities.clear(); _history.clear(); _rehearsal_origin.clear(); _action_origin.clear()
	state={"schema_version":1,"rules_version":RULES_VERSION,"content_version":definition.content_version,
		"content_digest":JSON.stringify(_canonical(definition)).sha256_text(),"level_id":definition.level_id,
		"phase":"PLAN_SHOW","tick":0,"phase_tick":0,"seed":seed_value,"active_laws":definition.initial_active_laws.duplicate(),
		"entities":{},"witnesses":{},"proofs":{},"routes":{},"goals":{},"zones":{},"actor_reach":{},
		"deliveries":{},"occluder_enabled":{},"candidate_law":"","pending_law":"","failure_reason":"",
		"resolution_had_pending_routes":false}
	state.active_laws.sort()
	for slot in definition.slots: _slots[slot.id]=slot
	for e in definition.entities:
		_entities[e.id]=e
		state.entities[e.id]={"slot":e.initial_slot,"position":_slots[e.initial_slot].position.duplicate(),"removed":false,
			"orientation":0,"effective":{},"support":false,"folded":e.properties.get("initial_folded",false),"closed":e.properties.get("initial_closed",false),
			"open":e.properties.get("initial_open",false),"enabled":e.properties.get("enabled",true),"intact":true,
			"heat_ticks":0,"attachment_target":e.properties.get("attachment_target_entity_id",""),"secured":false,"moored":false}
		state.actor_reach[e.id]=e.properties.get("initial_reach_zone_id",_slots[e.initial_slot].zone_id)
	for wd in definition.witnesses:
		var w: Dictionary={"slot":wd.initial_view_slot,"view_progress":{},"gap_streak":{},"view_completed":{},
			"expose_streak":0,"eligible_vote":false,"exposed":false,"status":"WAITING","visible_results":0,
			"method_visible":false,"water_seen_from":{},"water_transition":{}}
		for view in wd.views:
			w.view_progress[view.id]=0; w.gap_streak[view.id]=0; w.view_completed[view.id]=false
		state.witnesses[wd.id]=w
	for proof in definition.proofs:
		state.proofs[proof.myth_id]={"ready":false,"votes":0,"sealed":false}
		if state.candidate_law.is_empty() and proof.myth_id not in state.active_laws: state.candidate_law=proof.myth_id
	for goal in definition.goals: state.goals[goal.id]=false
	for zone in definition.zones:
		if zone.kind=="WATER": state.zones[zone.id]={"phase":zone.get("initial_phase","liquid"),"thermal_charge":int(zone.get("initial_thermal_charge",0)),"neutral_ticks":0}
	for occ in definition.occluders: state.occluder_enabled[occ.id]=true
	if state.candidate_law.is_empty() or not state.active_laws.is_empty(): state.phase="PLAN_RESOLUTION"
	_recompute_effective(); _events.clear(); _initial_state=snapshot()
	return true

func snapshot() -> Dictionary:
	return state.duplicate(true)
func stable_checkpoint() -> Dictionary:
	if state.phase in PLAN_PHASES+["SUCCESS"]: return snapshot()
	if not _action_origin.is_empty(): return _action_origin.duplicate(true)
	for i in range(_history.size()-1,-1,-1):
		if _history[i].phase in PLAN_PHASES: return _history[i].duplicate(true)
	return _initial_state.duplicate(true)
func state_hash() -> String:
	return JSON.stringify(_canonical(state)).sha256_text()
func _normalize_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary={}
		for key in value: out[key]=_normalize_numbers(value[key])
		return out
	if value is Array:
		var out: Array=[]
		for child in value: out.append(_normalize_numbers(child))
		return out
	if value is float and is_finite(value) and value==floor(value): return int(value)
	return value
func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary={}; var keys: Array=value.keys(); keys.sort()
		for key in keys: out[key]=_canonical(value[key])
		return out
	if value is Array:
		var out: Array=[]
		for child in value: out.append(_canonical(child))
		return out
	return _normalize_numbers(value)
func _is_integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value==floor(value))
func _remember() -> void:
	_history.append(snapshot())
	while _history.size()>50: _history.pop_front()
	var bytes: int=0
	for saved in _history: bytes+=JSON.stringify(saved).length()
	while bytes>12*1024*1024 and _history.size()>1: bytes-=JSON.stringify(_history.pop_front()).length()
func _emit(kind: String, payload: Dictionary={}) -> void:
	_event_seq+=1
	_events.append({"event_id":"%s:%d"%[state.level_id,_event_seq],"type":kind,"tick":state.tick,"payload":payload.duplicate(true)})
func _response(ok: bool, reason: String="") -> Dictionary:
	return {"accepted":ok,"reason_code":reason,"state_hash":state_hash(),"events":_events.duplicate(true)}

func dispatch(command: Dictionary) -> Dictionary:
	_events.clear()
	if state.is_empty(): return _response(false,"NO_LEVEL")
	if command.has("precondition_hash") and command.precondition_hash!=state_hash(): return _response(false,"STALE_STATE")
	if not command.get("type") is String or not command.get("payload",{}) is Dictionary: return _response(false,"INVALID_PAYLOAD")
	var kind: String=command.type
	var p: Dictionary=command.get("payload",{})
	if kind=="Restart":
		var original: Dictionary=definition.duplicate(true); var seed_value: int=state.seed
		load_level(original,seed_value); _emit("restarted"); return _response(true)
	if kind=="Undo":
		if _history.is_empty(): return _response(false,"NO_UNDO")
		state=_history.pop_back(); _rehearsal_origin.clear(); _action_origin.clear(); _recompute_effective(); _emit("undone"); return _response(true)
	if kind in ["StopPerformance","StopRehearsal"]:
		if kind=="StopRehearsal" and _rehearsal_origin.is_empty(): return _response(false,"NOT_REHEARSING")
		if kind=="StopPerformance" and state.phase not in ["PERFORMANCE","PROOF_ACCEPTED"]: return _response(false,"WRONG_PHASE")
		var origin: Dictionary=_rehearsal_origin if kind=="StopRehearsal" else _action_origin
		# Undo can restore an accepted trial after its transient origin was cleared.
		if origin.is_empty() and kind=="StopPerformance": origin=stable_checkpoint()
		if origin.is_empty(): return _response(false,"NO_CHECKPOINT")
		state=origin.duplicate(true); _rehearsal_origin.clear(); _action_origin.clear(); _emit("rehearsal_finished" if kind=="StopRehearsal" else "show_stopped"); return _response(true)
	if kind=="StopResolution":
		if state.phase!="RUN_RESOLUTION": return _response(false,"WRONG_PHASE")
		for task in state.routes.values():
			if not task.completed: return _response(false,"ROUTE_IN_PROGRESS")
		state.phase="PLAN_RESOLUTION"; state.phase_tick=0; _action_origin.clear(); _emit("resolution_stopped"); return _response(true)
	if kind=="CancelLawSelection":
		if state.phase!="LAW_SELECTION": return _response(false,"WRONG_PHASE")
		state.pending_law=""; state.phase="PROOF_ACCEPTED"; return _response(true)
	if kind=="SetLawCandidate":
		if state.phase not in PLAN_PHASES: return _response(false,"WRONG_PHASE")
		var myth: String=p.get("myth_id","")
		if _proof(myth).is_empty() or myth in state.active_laws: return _response(false,"NO_CANDIDATE")
		_remember(); state.candidate_law=myth; return _response(true)
	if kind=="RevokeLaw":
		if state.phase not in PLAN_PHASES: return _response(false,"WRONG_PHASE")
		var myth: String=p.get("myth_id","")
		if myth not in state.active_laws: return _response(false,"LAW_NOT_ACTIVE")
		_remember(); state.active_laws.erase(myth); _recompute_effective(); _emit("law_revoked",{"myth_id":myth}); return _response(true)
	if kind=="PlaceProp": return _place(p)
	if kind=="SetWitnessSlot":
		if state.phase not in PLAN_PHASES+["PROOF_ACCEPTED"]: return _response(false,"WRONG_PHASE")
		var wid: String=p.get("witness_id",""); var sid: String=p.get("slot_id","")
		if not state.witnesses.has(wid) or not _slots.has(sid): return _response(false,"UNKNOWN_TARGET")
		if "witness" not in _slots[sid].allowed_entity_types: return _response(false,"INCOMPATIBLE_SLOT")
		if _find(definition.witnesses,wid).views.size()>1: return _response(false,"FIXED_INSPECTION_PATH")
		for other in state.witnesses:
			if other!=wid and state.witnesses[other].slot==sid: return _response(false,"SLOT_OCCUPIED")
		_remember(); _invalidate_unsealed_proof(); state.witnesses[wid].slot=sid; _emit("witness_moved",{"witness_id":wid}); return _response(true)
	if kind in ["BeginPerformance","BeginRehearsal"]:
		if state.phase not in PLAN_PHASES: return _response(false,"WRONG_PHASE")
		if state.candidate_law.is_empty() or state.candidate_law in state.active_laws: return _response(false,"NO_CANDIDATE")
		_remember(); _action_origin=snapshot()
		if kind=="BeginRehearsal": _rehearsal_origin=snapshot()
		_reset_observation(); state.phase="REHEARSAL" if kind=="BeginRehearsal" else "PERFORMANCE"; state.phase_tick=0; _emit("show_started"); return _response(true)
	if kind=="ActivateLaw": return _activate(p)
	if kind=="Interact": return _interact(p)
	if kind=="AssignRoute": return _assign_route(p)
	if kind=="RunResolution":
		if state.phase!="PLAN_RESOLUTION": return _response(false,"WRONG_PHASE")
		_remember(); _action_origin=snapshot(); state.phase="RUN_RESOLUTION"; state.phase_tick=0
		state.resolution_had_pending_routes=false
		for task in state.routes.values(): state.resolution_had_pending_routes=state.resolution_had_pending_routes or not task.completed
		_emit("resolution_started"); return _response(true)
	return _response(false,"UNSUPPORTED_COMMAND")

func _place(p: Dictionary) -> Dictionary:
	if state.phase not in PLAN_PHASES+["PROOF_ACCEPTED"]: return _response(false,"WRONG_PHASE")
	var eid: String=p.get("entity_id",""); var sid: String=p.get("slot_id","")
	if not _entities.has(eid) or not _slots.has(sid): return _response(false,"UNKNOWN_TARGET")
	var e: Dictionary=state.entities[eid]; var base: Dictionary=_entities[eid]
	if not base.movable or e.removed: return _response(false,"IMMOVABLE")
	if base.type_id not in _slots[sid].allowed_entity_types: return _response(false,"INCOMPATIBLE_SLOT")
	if not _reachable_slot(sid) or not _reachable_entity(eid): return _response(false,"OUT_OF_REACH")
	if base.mass_units>=20:
		var mode: String=p.get("move_mode",base.properties.get("move_mode","")); var hoist: String=p.get("hoist_entity_id",base.properties.get("hoist_entity_id",""))
		if mode!="hoist" or not _entities.has(hoist) or state.entities[hoist].removed or not _reachable_entity(hoist): return _response(false,"HOIST_REQUIRED")
		if int(_entities[hoist].properties.get("lift_capacity_units",0))<base.mass_units: return _response(false,"HOIST_CAPACITY")
		if sid not in _entities[hoist].properties.get("service_slot_ids",[]): return _response(false,"HOIST_CANNOT_REACH")
	for other in state.entities:
		if other!=eid and not state.entities[other].removed and state.entities[other].slot==sid: return _response(false,"SLOT_OCCUPIED")
	_remember(); _invalidate_unsealed_proof(); e.slot=sid; e.position=_slots[sid].position.duplicate(); state.actor_reach[eid]=_slots[sid].zone_id
	_recompute_effective(); _emit("prop_placed",{"entity_id":eid,"slot_id":sid}); return _response(true)

func _invalidate_unsealed_proof() -> void:
	if state.phase!="PROOF_ACCEPTED": return
	_reset_observation(); state.phase="PLAN_SHOW"; state.phase_tick=0; _action_origin.clear()
	_emit("proof_invalidated",{"myth_id":state.candidate_law})

func _activate(p: Dictionary) -> Dictionary:
	if state.phase not in ["PROOF_ACCEPTED","LAW_SELECTION"]: return _response(false,"WRONG_PHASE")
	var myth: String=p.get("myth_id","")
	if not state.proofs.has(myth) or myth!=state.candidate_law or not state.proofs[myth].ready: return _response(false,"NO_PROOF")
	if myth in state.active_laws: return _response(false,"ALREADY_ACTIVE")
	var votes: int=0
	for w in state.witnesses.values():
		if w.eligible_vote and not w.exposed: votes+=1
	if votes<int(definition.required_votes): return _response(false,"NO_PROOF")
	var replacement: Variant=p.get("replace_law_id")
	if replacement!=null and (not replacement is String or replacement not in state.active_laws): return _response(false,"INVALID_REPLACEMENT")
	if state.active_laws.size()>=int(definition.max_active_laws) and replacement==null:
		state.pending_law=myth; state.phase="LAW_SELECTION"; _emit("law_selection_required"); return _response(true)
	_remember()
	if replacement!=null: state.active_laws.erase(replacement)
	state.active_laws.append(myth); state.active_laws.sort(); state.proofs[myth].sealed=true; state.proofs[myth].ready=false
	state.pending_law=""; state.phase="PLAN_RESOLUTION"; state.phase_tick=0; _action_origin.clear(); _recompute_effective()
	_emit("law_activated",{"myth_id":myth}); return _response(true)

func _interact(p: Dictionary) -> Dictionary:
	if state.phase not in PLAN_PHASES+["PROOF_ACCEPTED"]: return _response(false,"WRONG_PHASE")
	var eid: String=p.get("entity_id",""); var action: String=p.get("action","")
	if not state.entities.has(eid): return _response(false,"UNKNOWN_TARGET")
	var e: Dictionary=state.entities[eid]; var base: Dictionary=_entities[eid]
	if e.removed: return _response(false,"ENTITY_REMOVED")
	if not _reachable_entity(eid): return _response(false,"OUT_OF_REACH")
	if action=="remove":
		if not base.movable and not base.properties.get("removable",false): return _response(false,"IMMOVABLE")
		var required_law: String=base.properties.get("remove_requires_law","")
		if not required_law.is_empty() and required_law not in state.active_laws: return _response(false,"LAW_NOT_ACTIVE")
		_remember(); _invalidate_unsealed_proof(); e.removed=true; _recompute_effective(); _emit("prop_removed",{"entity_id":eid}); return _response(true)
	if action in ["fold","unfold"]:
		if not base.properties.get("foldable",false): return _response(false,"UNSUPPORTED_ACTION")
		var next_folded: bool=action=="fold"
		if e.folded==next_folded: return _response(false,"ALREADY_IN_STATE")
		_remember(); _invalidate_unsealed_proof(); e.folded=next_folded; _recompute_effective(); _emit("prop_interacted",{"entity_id":eid,"action":action}); return _response(true)
	if action in ["enable","disable"]:
		if not base.properties.get("switchable",false): return _response(false,"UNSUPPORTED_ACTION")
		var next_enabled: bool=action=="enable"
		if e.enabled==next_enabled: return _response(false,"ALREADY_IN_STATE")
		_remember(); _invalidate_unsealed_proof(); e.enabled=next_enabled; _recompute_effective(); _emit("prop_interacted",{"entity_id":eid,"action":action}); return _response(true)
	if action in ["open","close"]:
		if not base.properties.has("initial_closed") and not base.properties.has("initial_open") and not ("gate" in base.type_id or "box" in base.type_id): return _response(false,"UNSUPPORTED_ACTION")
		_remember(); _invalidate_unsealed_proof(); e.open=action=="open"; e.closed=action=="close"; _recompute_effective(); _emit("prop_interacted",{"entity_id":eid,"action":action}); return _response(true)
	if action in ["attach","detach"]:
		if base.properties.get("attachment_kind","") not in ["clamp","mooring"]: return _response(false,"UNSUPPORTED_ACTION")
		var target: String=p.get("target_entity_id","")
		if action=="attach":
			if not _entities.has(target) or target==eid or state.entities[target].removed: return _response(false,"UNKNOWN_TARGET")
			if not _reachable_entity(target): return _response(false,"OUT_OF_REACH")
			if base.properties.has("attachable_target_types") and _entities[target].type_id not in base.properties.attachable_target_types: return _response(false,"INCOMPATIBLE_ATTACHMENT")
		_remember(); _invalidate_unsealed_proof(); e.attachment_target=target if action=="attach" else ""; _recompute_effective(); _emit("prop_interacted",{"entity_id":eid,"action":action}); return _response(true)
	return _response(false,"UNSUPPORTED_ACTION")

func _assign_route(p: Dictionary) -> Dictionary:
	if state.phase!="PLAN_RESOLUTION": return _response(false,"WRONG_PHASE")
	var eid: String=p.get("actor_id",""); var rid: String=p.get("route_id",""); var route: Dictionary=_find(definition.navigation.routes,rid)
	if not _entities.has(eid) or route.is_empty(): return _response(false,"UNKNOWN_TARGET")
	if state.entities[eid].removed: return _response(false,"ENTITY_REMOVED")
	var base: Dictionary=_entities[eid]; var props: Dictionary=base.properties
	var mode: String=props.get("transport_mode","walk")
	if props.get("locomotion","")=="sail": mode="sail"
	if base.apparent_class=="CARGO" and not props.has("transport_mode"): return _response(false,"CARRIER_REQUIRED")
	if base.apparent_class not in ["PERSON","CARGO","ANIMAL","BOAT","WEIGHT"] and props.get("locomotion","") not in ["walk","sail"] and not props.has("transport_mode"): return _response(false,"INVALID_ACTOR")
	var carrier: String=props.get("carrier_entity_id",eid)
	if not _entities.has(carrier) or state.entities[carrier].removed: return _response(false,"CARRIER_REQUIRED")
	if mode!="towed" and state.entities[carrier].position!=_find(definition.navigation.nodes,route.nodes[0]).position: return _response(false,"ROUTE_START_UNREACHABLE")
	if mode=="sail" and not _sailing_route_over_water(route): return _response(false,"SAILING_REQUIRES_WATER")
	if mode in ["carried","wheeled","towed"] and not _reachable_entity(eid): return _response(false,"OUT_OF_REACH")
	if mode=="towed":
		var rope: String=props.get("tow_rope_entity_id","")
		if not _entities.has(rope) or state.entities[rope].removed or not _reachable_entity(rope): return _response(false,"TOW_ROPE_REQUIRED")
		for node_id in route.nodes:
			if _vec(state.entities[carrier].position).distance_to(_vec(_find(definition.navigation.nodes,node_id).position))>float(_entities[rope].properties.get("rope_length_units",0)): return _response(false,"TOW_ROPE_TOO_SHORT")
	for other_id in state.routes:
		var other: Dictionary=state.routes[other_id]
		if not other.completed and (other_id==eid or other.carrier_id==carrier): return _response(false,"CARRIER_ALREADY_ASSIGNED")
	for payload_id in props.get("payload_entity_ids",[]):
		if state.entities[payload_id].removed or state.entities[payload_id].position!=state.entities[eid].position: return _response(false,"PAYLOAD_NOT_LOADED")
	_remember(); state.routes[eid]={"route_id":rid,"carrier_id":carrier,"transport_mode":mode,"progress":0,"completed":false,"waiting_for":""}
	_emit("route_assigned",{"actor_id":eid}); return _response(true)

func _sailing_route_over_water(route: Dictionary) -> bool:
	# Check the authored polyline against water geometry, without adding physics.
	# Polygon-edge intersections partition each segment into uniform inside/outside
	# intervals, so dry gaps between wet endpoints cannot pass a sampling shortcut.
	var polygons: Array[PackedVector2Array]=[]
	for zone in definition.zones:
		if zone.kind!="WATER": continue
		var polygon: PackedVector2Array=[]
		for vertex in zone.polygon: polygon.append(_vec(vertex))
		polygons.append(polygon)
	for i in range(route.nodes.size()-1):
		var a: Vector2=_vec(_find(definition.navigation.nodes,route.nodes[i]).position)
		var b: Vector2=_vec(_find(definition.navigation.nodes,route.nodes[i+1]).position)
		if not _water_contains_point(a,polygons) or not _water_contains_point(b,polygons): return false
		var delta: Vector2=b-a
		if delta.is_zero_approx(): continue
		var cuts: Array[float]=[0.0,1.0]
		for polygon in polygons:
			for edge_index in range(polygon.size()):
				var p: Vector2=polygon[edge_index]
				var q: Vector2=polygon[(edge_index+1)%polygon.size()]
				var edge: Vector2=q-p
				var denominator: float=delta.cross(edge)
				if absf(denominator)<0.000001:
					if absf((p-a).cross(delta))<0.000001:
						for endpoint in [p,q]:
							var projection: float=(endpoint-a).dot(delta)/delta.length_squared()
							if projection>0.0 and projection<1.0: cuts.append(projection)
					continue
				var t: float=(p-a).cross(edge)/denominator
				var u: float=(p-a).cross(delta)/denominator
				if t>0.0 and t<1.0 and u>=0.0 and u<=1.0: cuts.append(t)
		cuts.sort()
		for j in range(cuts.size()-1):
			if cuts[j+1]-cuts[j]<0.000001: continue
			if not _water_contains_point(a+delta*((cuts[j]+cuts[j+1])*0.5),polygons): return false
	return true

func _water_contains_point(point: Vector2,polygons: Array[PackedVector2Array]) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(point,polygon): return true
	return false

func advance_ticks(count: int) -> Array:
	_events.clear()
	for _i in range(maxi(0,count)):
		if state.phase not in ACTIVE_PHASES: break
		var rehearsal: bool=state.phase=="REHEARSAL"
		_scheduled_effects(); _observe_water_before_step(); _step_thermal(); _recompute_effective()
		if state.phase in ["PERFORMANCE","REHEARSAL"]: _step_show()
		else: _step_routes()
		if rehearsal and state.phase in PLAN_PHASES: break
		state.tick+=1; state.phase_tick+=1
	return _events.duplicate(true)

func _reset_observation() -> void:
	# Counters describe this demonstration, not a witness's beliefs or memory.
	# Repeating a trial observes its new arrangement; nobody forgets the method.
	for w in state.witnesses.values():
		w.eligible_vote=false; w.exposed=false; w.expose_streak=0; w.status="WAITING"; w.water_seen_from.clear(); w.water_transition.clear()
		for vid in w.view_progress: w.view_progress[vid]=0; w.gap_streak[vid]=0; w.view_completed[vid]=false
	for myth in state.proofs:
		state.proofs[myth].ready=false; state.proofs[myth].votes=0

func _recompute_effective() -> void:
	var ids: Array=state.entities.keys(); ids.sort()
	for eid in ids:
		var e: Dictionary=state.entities[eid]; var base: Dictionary=_entities[eid]
		e.effective=base.properties.duplicate(true); e.effective.mass_units=int(base.mass_units)
		if base.properties.has("emitter_class"): e.effective.enabled=e.enabled
		if base.material=="STONE" and "M01" in state.active_laws:
			e.effective.buoyant=true; e.effective.carry_capacity={"S":1,"M":3,"L":5}.get(base.properties.get("size","M"),3)
		if base.material=="PAPER" and "M03" in state.active_laws: e.effective.load_capacity=150; e.effective.tear_resistance=150
		if base.properties.get("emitter_class","")=="FIRE": e.effective.thermal_delta=-absi(int(base.properties.get("thermal_delta_per_tick",1))) if "M02" in state.active_laws else int(base.properties.get("thermal_delta_per_tick",1))
		e.secured=false; e.moored=false
	for eid in ids:
		var count: int=0
		for aid in ids:
			if not state.entities[aid].removed and state.entities[aid].attachment_target==eid and _entities[aid].properties.get("attachment_kind","")=="clamp": count+=1
		state.entities[eid].secured=count>=int(_entities[eid].properties.get("required_attachment_count",999))
	for eid in ids:
		var p: Dictionary=_entities[eid].properties
		if p.get("attachment_kind","")!="mooring" or state.entities[eid].removed: continue
		var target: String=state.entities[eid].attachment_target; var owner: String=p.get("mooring_owner_entity_id","")
		if state.entities.has(target) and state.entities.has(owner):
			var t: Dictionary=state.entities[target]; var tp: Dictionary=_entities[target].properties
			state.entities[owner].moored=not t.removed and not t.effective.get("buoyant",false) and (tp.get("grounded",false) or tp.get("anchored",false))
	for eid in ids: state.entities[eid].support=_stable_support(eid)

func _stable_support(eid: String) -> bool:
	if not state.entities.has(eid): return false
	var e: Dictionary=state.entities[eid]
	if e.removed or not e.intact: return false
	if _entities[eid].material=="PAPER" and _entities[eid].properties.has("span_anchor_entity_ids"): return _paper_capacity(eid)>0
	if _slots[e.slot].mount_layer=="surface" and _surface_frozen(e.position): return true
	if e.effective.get("buoyant",false): return true
	for sid in state.entities:
		var p: Dictionary=_entities[sid].properties
		if _support_source_matches(sid,eid) and int(p.get("support_capacity",_entities[eid].mass_units))>=int(_entities[eid].mass_units): return true
	return false
func _support_source_matches(source_id: String,target_id: String) -> bool:
	var source: Dictionary=state.entities[source_id]; var p: Dictionary=_entities[source_id].properties
	return not source.removed and source.intact and p.get("supports_entity","")==target_id and source.slot==p.get("support_when_slot","") and _vec(source.position)+_vec(p.get("support_offset",[0,0]))==_vec(state.entities[target_id].position)

func _step_show() -> void:
	var proof: Dictionary=_proof(state.candidate_law)
	if proof.is_empty(): _fail("NO_CANDIDATE"); return
	var eligible: bool=state.candidate_law not in state.active_laws
	for pred in proof.predicates:
		if pred.type not in ["observed_water_transition","entity_visible"]: eligible=eligible and evaluate(pred.type,pred.parameters)
	var ids: Array=state.witnesses.keys(); ids.sort()
	var votes: int=0
	for wid in ids:
		var wd: Dictionary=_find(definition.witnesses,wid); var w: Dictionary=state.witnesses[wid]; var view: Dictionary=_current_view(wd)
		if w.exposed: w.status="EXPOSED"
		elif view.is_empty(): w.expose_streak=0; w.status="MOVING_TO_VIEW"
		else:
			var diag: Dictionary=visibility_for(wid,view)
			w.visible_results=diag.visible_results; w.method_visible=diag.method_visible
			if diag.method_visible:
				w.view_progress[view.id]=0; w.expose_streak+=1; w.gap_streak[view.id]=0; w.status="SUSPICIOUS"
				if w.expose_streak>=wd.expose_ticks:
					w.exposed=true; w.eligible_vote=false; w.view_completed[view.id]=false; _emit("method_exposed",{"witness_id":wid})
			else: w.expose_streak=0
			var witness_eligible: bool=eligible
			for pred in proof.predicates:
				if pred.type=="observed_water_transition":
					var zid: String=pred.parameters.zone_id
					var before: Dictionary=_pre_observation.get(wid,{})
					if _phase_changes.get(zid,"")=="liquid:frozen" and w.water_seen_from.get(zid,false) and before.get("clear",false) and diag.visible_results>=2 and not diag.method_visible and _proof_entities_visible(wid,proof,view): w.water_transition[zid]=true
					witness_eligible=witness_eligible and w.water_transition.get(zid,false)
				if pred.type=="entity_visible": witness_eligible=witness_eligible and _entity_visible(wid,pred.parameters.entity_id,view)
			if not w.exposed and not diag.method_visible:
				if witness_eligible and diag.visible_results>=2:
					w.gap_streak[view.id]=0; w.view_progress[view.id]+=1; w.status="OBSERVING"
					if w.view_progress[view.id]>=view.clear_ticks: w.view_completed[view.id]=true
				else:
					w.gap_streak[view.id]+=1; w.status="CANNOT_SEE" if diag.visible_results<2 else "NO_MIRACLE"
					if w.gap_streak[view.id]>wd.gap_tolerance_ticks: w.view_progress[view.id]=0
		var completed: bool=not w.exposed
		for v in wd.views: completed=completed and w.view_completed[v.id]
		if completed and not w.eligible_vote: w.eligible_vote=true; _emit("witness_convinced",{"witness_id":wid})
		if w.eligible_vote:
			if w.status!="SUSPICIOUS": w.status="CONVINCED"
			votes+=1
	state.proofs[state.candidate_law].votes=votes
	if votes>=int(definition.required_votes) and eligible:
		state.proofs[state.candidate_law].ready=true
		if state.phase=="REHEARSAL": _finish_rehearsal(true)
		else: state.phase="PROOF_ACCEPTED"; _emit("proof_accepted",{"myth_id":state.candidate_law})
	elif state.phase_tick>=int(definition.get("demonstration_timeout_ticks",200))-1:
		if state.phase=="REHEARSAL": _finish_rehearsal(false)
		else:
			var reason: String="NOT_ENOUGH_WITNESSES"
			if definition.has("demonstration_timeout_ticks"):
				for w in state.witnesses.values():
					if w.exposed or w.method_visible: reason="METHOD_VISIBLE"; break
					if w.visible_results<2: reason="RESULT_OBSCURED"
			_fail(reason)
func _finish_rehearsal(passed: bool) -> void:
	state=_rehearsal_origin.duplicate(true); _rehearsal_origin.clear(); _action_origin.clear(); _emit("rehearsal_passed" if passed else "rehearsal_failed")

func _current_view(wd: Dictionary) -> Dictionary:
	for v in wd.views:
		if state.phase_tick>=v.from_tick and state.phase_tick<v.from_tick+v.duration_ticks: return v
	return {}
func witness_eye(wid: String, view: Dictionary={}) -> Vector2:
	var wd: Dictionary=_find(definition.witnesses,wid)
	if wd.is_empty(): return Vector2.ZERO
	if view.is_empty(): view=_current_view(wd)
	if view.is_empty(): view=wd.views[0]
	return _vec(view.eye_position)+_vec(_slots[state.witnesses[wid].slot].position)-_vec(_slots[wd.initial_view_slot].position)
func visibility_for(wid: String, view: Dictionary={}) -> Dictionary:
	var empty: Dictionary={"visible_results":0,"method_visible":false,"rays":[]}
	if not state.witnesses.has(wid): return empty
	var wd: Dictionary=_find(definition.witnesses,wid)
	if view.is_empty(): view=_current_view(wd)
	if view.is_empty(): view=wd.views[0]
	var proof: Dictionary=_proof(state.candidate_law)
	if proof.is_empty() and not definition.proofs.is_empty(): proof=definition.proofs[0]
	if proof.is_empty(): return empty
	var eye: Vector2=witness_eye(wid,view); var facing: Vector2=_vec(view.look_at)-eye
	for a in proof.result_anchors:
		var target: Vector2=_anchor(a); var visible: bool=not state.entities[a.entity_id].removed and _visible(eye,target,facing)
		empty.visible_results+=int(visible); empty.rays.append({"from":[eye.x,eye.y],"to":[target.x,target.y],"visible":visible,"method":false})
	for a in proof.method_anchors:
		var target: Vector2=_anchor(a); var e: Dictionary=state.entities[a.entity_id]; var p: Dictionary=_entities[a.entity_id].properties
		var visible: bool=not e.removed and e.slot==p.get("support_when_slot",e.slot) and _visible(eye,target,facing)
		empty.method_visible=empty.method_visible or visible; empty.rays.append({"from":[eye.x,eye.y],"to":[target.x,target.y],"visible":visible,"method":true})
	return empty
func diagnostics(wid: String) -> Dictionary:
	return visibility_for(wid)
func _entity_visible(wid: String,eid: String,view: Dictionary) -> bool:
	if not state.entities.has(eid) or state.entities[eid].removed: return false
	var eye: Vector2=witness_eye(wid,view)
	return _visible(eye,_vec(state.entities[eid].position),_vec(view.look_at)-eye)
func _proof_entities_visible(wid: String,proof: Dictionary,view: Dictionary) -> bool:
	for p in proof.predicates:
		if p.type=="entity_visible" and not _entity_visible(wid,p.parameters.entity_id,view): return false
	return true
func _anchor(a: Dictionary) -> Vector2:
	return _vec(state.entities[a.entity_id].position)+_vec(a.offset)
func _visible(eye: Vector2,target: Vector2,facing: Vector2) -> bool:
	var ray: Vector2=target-eye
	var distance_sq: int=int(ray.length_squared()); var facing_sq: int=int(facing.length_squared()); var dot: int=int(ray.dot(facing))
	if distance_sq>1600 or facing_sq==0: return false
	if distance_sq>0 and (dot<0 or dot*dot*100000000 < distance_sq*facing_sq*41319184): return false
	return not _occluded(eye,target,"Vision")
func _segments_intersect(a: Vector2,b: Vector2,c: Vector2,d: Vector2) -> bool:
	var o1: int=int((b-a).cross(c-a)); var o2: int=int((b-a).cross(d-a)); var o3: int=int((d-c).cross(a-c)); var o4: int=int((d-c).cross(b-c))
	if o1==0 and _on_segment(a,b,c): return true
	if o2==0 and _on_segment(a,b,d): return true
	if o3==0 and _on_segment(c,d,a): return true
	if o4==0 and _on_segment(c,d,b): return true
	return (o1>0)!=(o2>0) and (o3>0)!=(o4>0)
func _on_segment(a: Vector2,b: Vector2,p: Vector2) -> bool:
	return p.x>=minf(a.x,b.x) and p.x<=maxf(a.x,b.x) and p.y>=minf(a.y,b.y) and p.y<=maxf(a.y,b.y)
func _occluded(a: Vector2,b: Vector2,channel: String) -> bool:
	for o in definition.occluders:
		if channel not in o.channels or not state.occluder_enabled[o.id]: continue
		var owner: Dictionary=state.entities[o.owner_entity]
		if owner.removed or (o.active_slot!=null and owner.slot!=o.active_slot): continue
		var segment: Array=o.folded_segment if owner.get("folded",false) and o.has("folded_segment") else o.segment
		if _segments_intersect(a,b,_vec(segment[0]),_vec(segment[1])): return true
	return false

func evaluate(kind: String,p: Dictionary={}) -> bool:
	match kind:
		"apparent_class_is": return _entities.has(p.get("entity_id","")) and _entities[p.entity_id].apparent_class==p.get("value")
		"over_water": return state.entities.has(p.get("entity_id","")) and not state.entities[p.entity_id].removed and state.zones.has(p.get("zone_id","")) and state.zones[p.zone_id].phase=="liquid" and _point_in_zone(state.entities[p.entity_id].position,p.get("zone_id",""))
		"stable_support","support_valid": return _stable_support(p.get("entity_id",""))
		"entity_removed": return state.entities.has(p.get("entity_id","")) and state.entities[p.entity_id].removed
		"law_active": return p.get("myth_id","") in state.active_laws
		"law_inactive": return p.get("myth_id","") not in state.active_laws
		"route_completed": return state.deliveries.get(p.get("actor_id","")+":"+p.get("route_id",""),false)
		"cargo_delivered": return state.deliveries.get(p.get("entity_id","")+":"+p.get("route_id",""),false)
		"water_phase": return state.zones.has(p.get("zone_id","")) and state.zones[p.zone_id].phase==p.get("phase")
		"observed_water_transition": return state.zones.has(p.get("zone_id","")) and state.zones[p.zone_id].phase==p.get("to")
		"entity_visible": return state.entities.has(p.get("entity_id","")) and not state.entities[p.entity_id].removed
		"entity_intact": return state.entities.has(p.get("entity_id","")) and state.entities[p.entity_id].intact and not state.entities[p.entity_id].removed
		"entity_state": return state.entities.has(p.get("entity_id","")) and p.get("key") in ["open","closed","intact","moored","secured","enabled"] and state.entities[p.entity_id].get(p.key)==p.get("value")
		"span_anchors_valid": return _span_anchors_valid(p.get("entity_id",""))
		"load_contact":
			if not state.entities.has(p.get("paper_id","")) or not state.entities.has(p.get("load_id","")): return false
			var paper: Dictionary=state.entities[p.paper_id]; var load: Dictionary=state.entities[p.load_id]
			return not load.removed and not paper.removed and _slots[paper.slot].mount_layer=="surface" and load.slot in _entities[p.paper_id].properties.get("load_slot_ids",[]) and int(_entities[p.load_id].mass_units)>=int(p.get("min_mass",50)) and _paper_capacity(p.paper_id)>=int(_entities[p.load_id].mass_units) and paper.position==load.position
		"entity_at_zone": return state.entities.has(p.get("entity_id","")) and (state.actor_reach.get(p.entity_id,"")==p.get("zone_id") or _point_in_zone(state.entities[p.entity_id].position,p.get("zone_id","")))
		"actor_at_node": return state.entities.has(p.get("actor_id","")) and state.entities[p.actor_id].position==_find(definition.navigation.nodes,p.get("node_id","")).get("position",[])
	return false
func assert_predicate(text: String) -> bool:
	var parts: PackedStringArray=text.split(":")
	if parts[0]=="level_success": return state.phase=="SUCCESS"
	if parts.size()<2: return false
	match parts[0]:
		"proof_ready": return state.proofs.has(parts[1]) and state.proofs[parts[1]].ready
		"law_active": return parts[1] in state.active_laws
		"law_inactive": return parts[1] not in state.active_laws
		"entity_removed": return evaluate("entity_removed",{"entity_id":parts[1]})
		"cargo_delivered":
			if parts.size()>2: return evaluate("cargo_delivered",{"entity_id":parts[1],"route_id":parts[2]})
			for key in state.deliveries:
				if key.begins_with(parts[1]+":") and state.deliveries[key]: return true
			return false
		"route_completed": return parts.size()>2 and evaluate("route_completed",{"actor_id":parts[1],"route_id":parts[2]})
	return false

func _route_requirements(route: Dictionary) -> Array:
	var reqs: Array=route.get("requirements",[]).duplicate(true)
	if route.has("required_support_entity"): reqs.append({"type":"support","parameters":{"kind":"stone","entity_id":route.required_support_entity,"slot_id":route.required_support_slot}})
	return reqs
func _task_mass(eid: String,task: Dictionary) -> int:
	var mass: int=int(_entities[eid].mass_units)
	if task.carrier_id!=eid and task.transport_mode!="towed": mass+=int(_entities[task.carrier_id].mass_units)
	if not _entities[eid].properties.get("payload_mass_included",false):
		for payload in _entities[eid].properties.get("payload_entity_ids",[]): mass+=int(_entities[payload].mass_units)
	return mass
func _step_routes() -> void:
	var actors: Array=state.routes.keys(); actors.sort(); var shared: Dictionary={}
	for eid in actors:
		var task: Dictionary=state.routes[eid]
		if task.completed: continue
		for req in _route_requirements(_find(definition.navigation.routes,task.route_id)):
			if req.type=="support": shared[req.parameters.entity_id]=int(shared.get(req.parameters.entity_id,0))+_task_mass(eid,task)
	for eid in actors:
		var task: Dictionary=state.routes[eid]
		if task.completed: continue
		if state.entities[eid].removed or state.entities[task.carrier_id].removed: _fail("ENTITY_REMOVED"); return
		var route: Dictionary=_find(definition.navigation.routes,task.route_id); var ready: bool=true
		for req in _route_requirements(route):
			var p: Dictionary=req.parameters
			if req.type=="water_phase":
				if not evaluate("water_phase",p): ready=false; task.waiting_for="water_phase:"+p.zone_id+":"+p.phase
			elif req.type=="entity_state":
				if not evaluate("entity_state",p): _fail("ROUTE_STATE_BLOCKED"); return
			elif req.type=="support":
				var support: Dictionary=state.entities[p.entity_id]
				if support.removed or support.slot!=p.slot_id or not support.support: _fail("MISSING_FLOATING_BRIDGE"); return
				var capacity: int=_paper_capacity(p.entity_id) if p.kind=="paper" else int(support.effective.get("carry_capacity",0))
				if int(shared.get(p.entity_id,0))>capacity: _fail("OVER_CAPACITY"); return
		if not ready: continue
		task.waiting_for=""; task.progress+=1
		var segment: int=mini(int(task.progress/int(route.get("ticks_per_edge",10))),route.nodes.size()-1)
		var position: Array=_find(definition.navigation.nodes,route.nodes[segment]).position
		state.entities[eid].position=position.duplicate()
		if task.transport_mode!="towed": state.entities[task.carrier_id].position=position.duplicate()
		for payload in _entities[eid].properties.get("payload_entity_ids",[]): state.entities[payload].position=position.duplicate()
		if segment==route.nodes.size()-1:
			task.completed=true; state.deliveries[eid+":"+task.route_id]=true
			if route.has("destination_reach_zone_id"):
				state.actor_reach[eid]=route.destination_reach_zone_id
				if task.transport_mode!="towed": state.actor_reach[task.carrier_id]=route.destination_reach_zone_id
			_emit("route_completed",{"actor_id":eid})
	_evaluate_goals()
	if state.phase=="SUCCESS": _action_origin.clear(); return
	var all_done: bool=true
	for task in state.routes.values(): all_done=all_done and task.completed
	if all_done and state.resolution_had_pending_routes:
		state.phase="PLAN_RESOLUTION"; _action_origin.clear(); _emit("resolution_step_completed")
	elif state.phase_tick>=299: _fail("GOALS_INCOMPLETE")
func _evaluate_goals() -> void:
	var all_goals: bool=not definition.goals.is_empty()
	for goal in definition.goals:
		var met: bool=evaluate(goal.predicate_id,goal.parameters)
		state.goals[goal.id]=(state.goals[goal.id] or met) if goal.kind=="latched" else met
		if goal.required: all_goals=all_goals and state.goals[goal.id]
	if all_goals: state.phase="SUCCESS"; _emit("level_success")
func _fail(reason: String) -> void:
	state.phase="RECOVERABLE_FAILURE"; state.failure_reason=reason; _emit("recoverable_failure",{"reason":reason})

func _span_anchors_valid(eid: String) -> bool:
	if not state.entities.has(eid) or state.entities[eid].removed: return false
	var props: Dictionary=_entities[eid].properties; var anchors: Array=props.get("span_anchor_entity_ids",[])
	if anchors.size()<int(props.get("required_anchor_count",2)): return false
	var seen: Dictionary={}; var offsets: Array=props.get("span_anchor_offsets",props.get("span_endpoint_offsets",[[-2,0],[2,0]]))
	if offsets.size()!=anchors.size(): return false
	for i in range(anchors.size()):
		var aid: String=anchors[i]
		if seen.has(aid) or not state.entities.has(aid): return false
		seen[aid]=true
		var a: Dictionary=state.entities[aid]; var base: Dictionary=_entities[aid]
		if a.removed or not a.intact or _vec(a.position)!=_vec(state.entities[eid].position)+_vec(offsets[i]): return false
		if base.material=="STONE" and _position_over_water(a.position) and not _surface_frozen(a.position) and not a.effective.get("buoyant",false): return false
		if not base.properties.get("anchored",false) and not base.properties.get("grounded",false) and not a.effective.get("buoyant",false) and not _surface_frozen(a.position): return false
	return true
func _paper_capacity(eid: String) -> int:
	var e: Dictionary=state.entities[eid]
	if e.removed or not e.intact or _slots[e.slot].mount_layer!="surface" or not _span_anchors_valid(eid): return 0
	var capacity: int=int(e.effective.get("load_capacity",1)); var grounded_frame: bool=false
	for sid in state.entities:
		var p: Dictionary=_entities[sid].properties
		if _support_source_matches(sid,eid):
			capacity=maxi(capacity,int(p.get("support_capacity",0))); grounded_frame=grounded_frame or p.get("grounded",false)
	if grounded_frame: return capacity
	var floating: int=0; var count: int=0
	for aid in _entities[eid].properties.get("span_anchor_entity_ids",[]):
		if _position_over_water(state.entities[aid].position) and not _surface_frozen(state.entities[aid].position): count+=1; floating+=int(state.entities[aid].effective.get("carry_capacity",0))
	if count>0: capacity=mini(capacity,maxi(0,floating-int(_entities[eid].mass_units)))
	return capacity
func _reachable_slot(sid: String) -> bool:
	if not _slots.has(sid): return false
	return _reachable_zone(_slots[sid].zone_id)
func _reachable_entity(eid: String) -> bool:
	return state.entities.has(eid) and _reachable_zone(state.actor_reach.get(eid,_slots[state.entities[eid].slot].zone_id))
func _reachable_zone(target: String) -> bool:
	var reach: String=state.actor_reach.get("hero","")
	return target==reach or target in _find(definition.zones,reach).get("reachable_zone_ids",[])
func _position_over_water(position: Array) -> bool:
	for zone in definition.zones:
		if zone.kind=="WATER" and _point_in_zone(position,zone.id): return true
	return false
func _surface_frozen(position: Array) -> bool:
	for zone in definition.zones:
		if zone.kind=="WATER" and state.zones[zone.id].phase=="frozen" and _point_in_zone(position,zone.id): return true
	return false
func _point_in_zone(position: Array,zid: String) -> bool:
	var z: Dictionary=_find(definition.zones,zid)
	if not z.has("polygon"): return false
	var poly: PackedVector2Array=[]
	for p in z.polygon: poly.append(_vec(p))
	return Geometry2D.is_point_in_polygon(_vec(position),poly)
func _thermal_position(zone: Dictionary) -> Vector2:
	if zone.has("thermal_owner_entity_id"): return _vec(state.entities[zone.thermal_owner_entity_id].position)
	if zone.has("thermal_position"): return _vec(zone.thermal_position)
	var total: Vector2=Vector2.ZERO
	for p in zone.polygon: total+=_vec(p)
	return total/maxi(1,zone.polygon.size())
func _observe_water_before_step() -> void:
	_pre_observation.clear()
	if state.phase not in ["PERFORMANCE","REHEARSAL"]: return
	var proof: Dictionary=_proof(state.candidate_law)
	for wd in definition.witnesses:
		var v: Dictionary=_current_view(wd)
		if v.is_empty(): continue
		var diag: Dictionary=visibility_for(wd.id,v)
		var clear: bool=diag.visible_results>=2 and not diag.method_visible and _proof_entities_visible(wd.id,proof,v)
		_pre_observation[wd.id]={"clear":clear}
		if not clear: continue
		for pred in proof.predicates:
			if pred.type=="observed_water_transition" and state.zones[pred.parameters.zone_id].phase==pred.parameters.from: state.witnesses[wd.id].water_seen_from[pred.parameters.zone_id]=true
func _step_thermal() -> void:
	_phase_changes.clear()
	var ids: Array=state.entities.keys(); ids.sort()
	for zone in definition.zones:
		if zone.kind!="WATER": continue
		var z: Dictionary=state.zones[zone.id]
		if zone.has("thermal_owner_entity_id") and _insulated(zone.thermal_owner_entity_id): continue
		var target: Vector2=_thermal_position(zone); var delta: int=0
		for eid in ids:
			var e: Dictionary=state.entities[eid]; var p: Dictionary=_entities[eid].properties
			if e.removed or not e.enabled or not p.has("emitter_class"): continue
			if _vec(e.position).distance_to(target)>float(p.get("thermal_radius_units",0)) or _occluded(_vec(e.position),target,"Thermal"): continue
			var effect: int=int(p.get("thermal_delta_per_tick",0))
			if p.emitter_class=="FIRE" and "M02" in state.active_laws: effect=-absi(effect)
			delta+=effect
		if delta==0:
			z.neutral_ticks+=1
			if z.neutral_ticks>=5: delta=-signi(int(z.thermal_charge)); z.neutral_ticks=0
		else: z.neutral_ticks=0
		var before: String=z.phase
		z.thermal_charge=clampi(int(z.thermal_charge)+delta,-30,30)
		if z.thermal_charge<=-20: z.phase="frozen"
		elif z.thermal_charge>=10: z.phase="liquid"
		if before!=z.phase: _phase_changes[zone.id]=before+":"+z.phase; _emit("water_phase_changed",{"zone_id":zone.id,"phase":z.phase})
	for eid in ids:
		var e: Dictionary=state.entities[eid]; var p: Dictionary=_entities[eid].properties
		if e.removed or not e.intact: continue
		var subject: String=p.get("thermal_subject_zone_id","")
		if not subject.is_empty() and p.has("cold_damage_below") and state.zones[subject].thermal_charge<int(p.cold_damage_below) and not _insulated(eid): e.intact=false; _emit("entity_damaged",{"entity_id":eid})
		if not p.get("flammable",false): continue
		var heated: bool=false
		for sid in ids:
			var source: Dictionary=state.entities[sid]; var sp: Dictionary=_entities[sid].properties
			if source.removed or not source.enabled or sp.get("emitter_class","")!="FIRE" or "M02" in state.active_laws: continue
			if _vec(source.position).distance_to(_vec(e.position))<=float(sp.get("thermal_radius_units",0)) and not _occluded(_vec(source.position),_vec(e.position),"Thermal"): heated=true
		e.heat_ticks=int(e.heat_ticks)+1 if heated else 0
		if e.heat_ticks>=10: e.intact=false; _emit("entity_damaged",{"entity_id":eid})
func _insulated(eid: String) -> bool:
	var e: Dictionary=state.entities[eid]
	for bid in _entities[eid].properties.get("insulation_by_entity_ids",[]):
		var box: Dictionary=state.entities[bid]; var bp: Dictionary=_entities[bid].properties
		if not box.removed and box.closed and box.position==e.position and e.slot in bp.get("protection_slot_ids",[]) and eid in bp.get("protects_entity_ids",[eid]): return true
	return false
func _scheduled_effects() -> void:
	var ids: Array=state.entities.keys(); ids.sort()
	for eid in ids:
		var e: Dictionary=state.entities[eid]
		if e.removed: continue
		for effect in _entities[eid].properties.get("scheduled_effects",[]):
			if state.phase not in effect.phases or state.phase_tick!=effect.at_tick: continue
			if effect.operation=="move_if_unsecured" and not e.secured:
				e.slot=effect.target_slot_id; e.position=_slots[e.slot].position.duplicate(); state.actor_reach[eid]=_slots[e.slot].zone_id; _emit("prop_blown",{"entity_id":eid})
			elif effect.operation=="set_occluder_enabled": state.occluder_enabled[effect.target_occluder_id]=effect.value
func _proof(myth: String) -> Dictionary:
	for proof in definition.proofs:
		if proof.myth_id==myth: return proof
	return {}
func _find(items: Array,id: String) -> Dictionary:
	for item in items:
		if item.id==id: return item
	return {}
func _vec(a: Array) -> Vector2:
	return Vector2(float(a[0]),float(a[1]))

func restore(saved: Dictionary) -> bool:
	if not _valid_state(saved): return false
	var before: Dictionary=state
	state=_normalize_numbers(saved)
	_recompute_effective()
	# Derived properties are recomputed, never trusted from disk.
	for eid in state.entities:
		for key in ["effective","support","secured","moored"]:
			if _canonical(state.entities[eid][key])!=_canonical(saved.entities[eid][key]): state=before; return false
	return true
func _valid_state(s: Dictionary) -> bool:
	if state.is_empty() or s.get("schema_version")!=1 or s.get("rules_version")!=RULES_VERSION or s.get("content_version")!=definition.content_version or s.get("content_digest")!=state.content_digest or s.get("level_id")!=definition.level_id: return false
	if s.get("phase") not in PLAN_PHASES+ACTIVE_PHASES+["PROOF_ACCEPTED","LAW_SELECTION","SUCCESS","RECOVERABLE_FAILURE"]: return false
	for key in ["tick","phase_tick","seed"]:
		if not _is_integer(s.get(key)) or s[key]<0: return false
	if not s.get("resolution_had_pending_routes") is bool or not s.get("failure_reason") is String: return false
	if not s.get("active_laws") is Array or s.active_laws.size()>int(definition.max_active_laws): return false
	var seen: Dictionary={}
	for law in s.active_laws:
		if law not in LAWS or seen.has(law): return false
		seen[law]=true
	for key in ["entities","witnesses","proofs","goals","zones","actor_reach","occluder_enabled"]:
		if not s.get(key) is Dictionary or not _same_keys(s[key],state[key]): return false
	for key in ["deliveries","routes"]:
		if not s.get(key) is Dictionary: return false
	if not s.get("candidate_law") is String or (not s.candidate_law.is_empty() and not state.proofs.has(s.candidate_law)): return false
	if not s.get("pending_law") is String or (not s.pending_law.is_empty() and not state.proofs.has(s.pending_law)): return false
	for eid in _entities:
		var e: Variant=s.entities[eid]
		if not e is Dictionary or not e.get("slot") is String or not _slots.has(e.slot): return false
		if not Validator.new().point(e.get("position"),true): return false
		if not e.get("effective") is Dictionary or not _is_integer(e.get("orientation")) or not _is_integer(e.get("heat_ticks")) or e.heat_ticks<0: return false
		for key in ["removed","support","folded","closed","open","enabled","intact","secured","moored"]:
			if not e.get(key) is bool: return false
		if e.folded and not _entities[eid].properties.get("foldable",false): return false
		if not e.get("attachment_target") is String or (not e.attachment_target.is_empty() and not _entities.has(e.attachment_target)): return false
		if not s.actor_reach[eid] is String or _find(definition.zones,s.actor_reach[eid]).get("kind")!="REACH": return false
	for wd in definition.witnesses:
		var w: Variant=s.witnesses[wd.id]
		if not w is Dictionary or not _slots.has(w.get("slot","")): return false
		for key in ["view_progress","gap_streak","view_completed","water_seen_from","water_transition"]:
			if not w.get(key) is Dictionary: return false
		for key in ["view_progress","gap_streak","view_completed"]:
			if not _same_keys(w[key],state.witnesses[wd.id][key]): return false
		for key in ["eligible_vote","exposed","method_visible"]:
			if not w.get(key) is bool: return false
		if not _is_integer(w.get("expose_streak")) or w.expose_streak<0 or not _is_integer(w.get("visible_results")) or w.visible_results<0 or w.visible_results>3 or not w.get("status") is String: return false
		for v in wd.views:
			if not _is_integer(w.view_progress[v.id]) or w.view_progress[v.id]<0 or not _is_integer(w.gap_streak[v.id]) or w.gap_streak[v.id]<0 or not w.view_completed[v.id] is bool: return false
		for key in ["water_seen_from","water_transition"]:
			for zid in w[key]:
				if not state.zones.has(zid) or not w[key][zid] is bool: return false
		if w.exposed and w.eligible_vote: return false
		if w.eligible_vote:
			for v in wd.views:
				if not w.view_completed[v.id]: return false
	for myth in s.proofs:
		var proof: Variant=s.proofs[myth]
		if not proof is Dictionary or not proof.get("ready") is bool or not proof.get("sealed") is bool or not _is_integer(proof.get("votes")) or proof.votes<0 or proof.votes>definition.witnesses.size(): return false
	if s.phase in ["PROOF_ACCEPTED","LAW_SELECTION"]:
		if s.candidate_law.is_empty() or s.candidate_law in s.active_laws or not s.proofs[s.candidate_law].ready: return false
		var votes: int=0
		for w in s.witnesses.values():
			if w.eligible_vote and not w.exposed: votes+=1
		if votes<int(definition.required_votes) or s.proofs[s.candidate_law].votes!=votes: return false
		if s.phase=="LAW_SELECTION" and s.pending_law!=s.candidate_law: return false
	for goal in s.goals:
		if not s.goals[goal] is bool: return false
	for zid in s.zones:
		var z: Variant=s.zones[zid]
		if not z is Dictionary or z.get("phase") not in ["liquid","frozen"] or not _is_integer(z.get("thermal_charge")) or abs(z.thermal_charge)>30 or not _is_integer(z.get("neutral_ticks")) or z.neutral_ticks<0 or z.neutral_ticks>4: return false
		if (z.phase=="frozen" and z.thermal_charge>=10) or (z.phase=="liquid" and z.thermal_charge<=-20): return false
	for oid in s.occluder_enabled:
		if not s.occluder_enabled[oid] is bool: return false
	for eid in s.routes:
		var task: Variant=s.routes[eid]
		if not _entities.has(eid) or not task is Dictionary or not _entities.has(task.get("carrier_id","")) or not task.get("completed") is bool or not _is_integer(task.get("progress")) or task.progress<0 or task.get("transport_mode") not in ["walk","sail","carried","wheeled","towed"] or not task.get("waiting_for") is String: return false
		var route: Dictionary=_find(definition.navigation.routes,task.get("route_id",""))
		if route.is_empty(): return false
		var maximum: int=(route.nodes.size()-1)*int(route.get("ticks_per_edge",10))
		if task.progress>maximum or (task.completed and task.progress!=maximum): return false
	for entry in s.deliveries:
		if not entry is String or not s.deliveries[entry] is bool: return false
		var parts: PackedStringArray=entry.split(":")
		if parts.size()!=2 or not _entities.has(parts[0]) or _find(definition.navigation.routes,parts[1]).is_empty(): return false
	return true
func _same_keys(a: Dictionary,b: Dictionary) -> bool:
	if a.size()!=b.size(): return false
	for key in a:
		if not b.has(key): return false
	return true
