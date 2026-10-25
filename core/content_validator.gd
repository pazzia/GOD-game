extends RefCounted
## Runtime validation. Never execute content as code.
const LAWS = ["M01","M02","M03"]
const MATERIALS = ["STONE","PAPER","STEEL","WOOD","WATER","CLOTH","DECOY","ORGANIC","TERRAIN","FIRE","METAL","GLASS","ICE"]
const PREDICATES = {
	"apparent_class_is":["entity_id","value"], "over_water":["entity_id","zone_id"],
	"stable_support":["entity_id"], "entity_removed":["entity_id"], "law_active":["myth_id"], "law_inactive":["myth_id"],
	"route_completed":["actor_id","route_id"], "cargo_delivered":["entity_id","route_id"],
	"entity_visible":["entity_id"], "observed_water_transition":["zone_id","from","to"],
	"water_phase":["zone_id","phase"], "entity_intact":["entity_id"], "entity_state":["entity_id","key","value"],
	"support_valid":["entity_id"], "span_anchors_valid":["entity_id"], "load_contact":["paper_id","load_id","min_mass"],
	"entity_at_zone":["entity_id","zone_id"], "actor_at_node":["actor_id","node_id"]
}
var errors: Array[String] = []
var entities: Dictionary = {}
var slots: Dictionary = {}
var zones: Dictionary = {}
var nodes: Dictionary = {}
var routes: Dictionary = {}
var occluders: Dictionary = {}

func is_integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value))
func point(value: Variant, bounded: bool = false) -> bool:
	if not value is Array or value.size()!=2: return false
	if not is_integer(value[0]) or not is_integer(value[1]): return false
	return not bounded or (value[0]>=0 and value[0]<=24 and value[1]>=0 and value[1]<=28)
func fail(path: String, reason: String) -> void:
	errors.append(path+": "+reason)
func index(array: Variant, path: String) -> Dictionary:
	var result: Dictionary={}
	if not array is Array: fail(path,"expected array"); return result
	for i in range(array.size()):
		var item: Variant=array[i]
		if not item is Dictionary or not item.get("id") is String or item.id.is_empty(): fail(path+"[%d]"%i,"missing string id"); continue
		if result.has(item.id): fail(path+"."+item.id,"duplicate id")
		result[item.id]=item
	return result
func integer_field(d: Dictionary, key: String, path: String, minimum: int=0, maximum: int=2147483647) -> void:
	var value: Variant=d.get(key)
	if not is_integer(value) or value<minimum or value>maximum: fail(path+"."+key,"integer outside allowed range")
func references(values: Variant, target: Dictionary, path: String, unique: bool=true) -> void:
	if not values is Array: fail(path,"expected ID array"); return
	var seen: Dictionary={}
	for value in values:
		if not value is String or not target.has(value): fail(path,"unknown reference "+str(value))
		if unique and seen.has(value): fail(path,"duplicate reference "+str(value))
		seen[value]=true

func validate(data: Dictionary) -> Array[String]:
	errors=[]
	for field in ["schema_version","content_version","level_id","entities","slots","zones","witnesses","proofs","navigation","goals","available_myths","initial_active_laws","max_active_laws","required_votes","occluders"]:
		if not data.has(field): fail(field,"required")
	if not errors.is_empty(): return errors
	if data.schema_version!=1: fail("schema_version","unsupported")
	if not data.content_version is String or not data.level_id is String: fail("version/id","expected strings")
	if not data.navigation is Dictionary: fail("navigation","expected object"); return errors
	slots=index(data.slots,"slots"); entities=index(data.entities,"entities"); zones=index(data.zones,"zones")
	nodes=index(data.navigation.get("nodes"),"navigation.nodes"); routes=index(data.navigation.get("routes"),"navigation.routes")
	occluders=index(data.occluders,"occluders")
	var witnesses: Dictionary=index(data.witnesses,"witnesses")
	var goals: Dictionary=index(data.goals,"goals")
	if not data.proofs is Array or not data.available_myths is Array or not data.initial_active_laws is Array: fail("laws/proofs","expected arrays"); return errors
	for group in ["available_myths","initial_active_laws"]:
		var seen: Dictionary={}
		for law in data[group]:
			if not law is String: fail(group,"law id must be string"); continue
			if law not in LAWS: fail(group,"unknown law")
			if seen.has(law): fail(group,"duplicate law")
			seen[law]=true
	if data.has("demonstration_timeout_ticks"): integer_field(data,"demonstration_timeout_ticks","level",1,200)
	integer_field(data,"max_active_laws","level",1,2)
	integer_field(data,"required_votes","level",0 if data.proofs.is_empty() else 1,witnesses.size())
	if is_integer(data.max_active_laws) and data.initial_active_laws.size()>data.max_active_laws: fail("initial_active_laws","too many")
	for id in zones:
		var z: Dictionary=zones[id]
		if z.get("kind") not in ["REACH","WATER"]: fail("zones."+id,"unknown kind"); continue
		if z.kind=="REACH":
			references(z.get("reachable_zone_ids",[]),zones,"zones."+id+".reachable_zone_ids")
		else:
			if not z.get("polygon") is Array or z.polygon.size()<3: fail("zones."+id,"polygon requires 3 points")
			else:
				for p in z.polygon:
					if not point(p,true): fail("zones."+id+".polygon","integer point required")
			if z.get("initial_phase","liquid") not in ["liquid","frozen"]: fail("zones."+id,"phase")
			if not is_integer(z.get("initial_thermal_charge",0)) or abs(z.get("initial_thermal_charge",0))>30: fail("zones."+id,"thermal charge")
			if z.has("thermal_position") and not point(z.thermal_position,true): fail("zones."+id,"thermal position")
			if z.has("thermal_owner_entity_id") and not entities.has(z.thermal_owner_entity_id): fail("zones."+id,"thermal owner")
	for id in slots:
		var s: Dictionary=slots[id]
		if not point(s.get("position"),true): fail("slots."+id,"bounded integer position required")
		if not zones.has(s.get("zone_id","")) or zones.get(s.get("zone_id",""),{}).get("kind")!="REACH": fail("slots."+id,"unknown REACH zone")
		if not s.get("allowed_entity_types") is Array or s.allowed_entity_types.is_empty(): fail("slots."+id,"allowed_entity_types")
		if s.get("mount_layer") not in ["ground","surface","below","screen","tray"]: fail("slots."+id,"mount_layer")
	var occupied: Dictionary={}
	for id in entities:
		var e: Dictionary=entities[id]
		if not e.has_all(["type_id","initial_slot","material","properties","movable","mass_units","apparent_class"]): fail("entities."+id,"missing fields"); continue
		if not e.type_id is String or not e.apparent_class is String or not e.movable is bool: fail("entities."+id,"field types")
		if not slots.has(e.initial_slot): fail("entities."+id,"unknown initial slot")
		elif slots[e.initial_slot].get("allowed_entity_types") is Array and e.type_id not in slots[e.initial_slot].allowed_entity_types: fail("entities."+id,"incompatible initial slot")
		if occupied.has(e.initial_slot): fail("entities."+id,"occupied initial slot")
		occupied[e.initial_slot]=true
		if e.material not in MATERIALS: fail("entities."+id,"unknown material")
		integer_field(e,"mass_units","entities."+id)
		if not e.properties is Dictionary: fail("entities."+id,"properties must be object"); continue
		validate_properties(e,id)
	for id in nodes:
		if not point(nodes[id].get("position"),true): fail("nodes."+id,"integer position")
	for id in occluders:
		var o: Dictionary=occluders[id]
		if not entities.has(o.get("owner_entity","")): fail("occluders."+id,"owner")
		if o.get("active_slot")!=null and not slots.has(o.get("active_slot","")): fail("occluders."+id,"active slot")
		if not o.get("segment") is Array or o.segment.size()!=2: fail("occluders."+id,"segment")
		elif not point(o.segment[0],true) or not point(o.segment[1],true) or o.segment[0]==o.segment[1]: fail("occluders."+id,"segment points")
		if o.has("folded_segment"):
			var folded: Variant=o.folded_segment
			if not folded is Array or folded.size()!=2: fail("occluders."+id,"folded segment")
			elif not point(folded[0],true) or not point(folded[1],true) or folded[0]==folded[1]: fail("occluders."+id,"folded segment points")
			var owner_props: Variant=entities.get(o.get("owner_entity",""),{}).get("properties",{})
			if not owner_props is Dictionary or not owner_props.get("foldable",false): fail("occluders."+id,"folded segment requires foldable owner")
		if not o.get("channels") is Array: fail("occluders."+id,"channels")
		else:
			for channel in o.channels:
				if channel not in ["Vision","Thermal","Navigation"]: fail("occluders."+id,"unknown channel")
	for id in witnesses:
		var w: Dictionary=witnesses[id]
		if not slots.has(w.get("initial_view_slot","")): fail("witnesses."+id,"slot")
		integer_field(w,"expose_ticks","witnesses."+id,1,200); integer_field(w,"gap_tolerance_ticks","witnesses."+id,0,20)
		var views: Dictionary=index(w.get("views"),"witnesses."+id+".views")
		if views.is_empty(): fail("witnesses."+id,"at least one required view")
		var intervals: Array=[]
		for vid in views:
			var v: Dictionary=views[vid]
			integer_field(v,"from_tick","views."+vid,0,199); integer_field(v,"duration_ticks","views."+vid,1,200); integer_field(v,"clear_ticks","views."+vid,1,200)
			if not point(v.get("eye_position"),true) or not point(v.get("look_at"),true) or v.get("eye_position")==v.get("look_at"): fail("views."+vid,"eye/direction")
			if not v.has_all(["from_tick","duration_ticks","clear_ticks"]) or not is_integer(v.from_tick) or not is_integer(v.duration_ticks) or not is_integer(v.clear_ticks): continue
			if v.clear_ticks>v.duration_ticks or v.from_tick+v.duration_ticks>200: fail("views."+vid,"window")
			for interval in intervals:
				if v.from_tick<interval[1] and v.from_tick+v.duration_ticks>interval[0]: fail("views."+vid,"overlapping windows")
			intervals.append([v.from_tick,v.from_tick+v.duration_ticks])
	var proof_ids: Dictionary={}
	for proof in data.proofs:
		if not proof is Dictionary: fail("proofs","expected object"); continue
		if not proof.get("myth_id") is String: fail("proofs","myth id string required"); continue
		var myth: String=proof.myth_id
		if myth not in data.available_myths or proof_ids.has(myth): fail("proofs","unknown/duplicate myth")
		proof_ids[myth]=true
		for key in ["result_anchors","method_anchors"]:
			if not proof.get(key) is Array: fail("proofs."+myth,key+" array required"); continue
			if key=="result_anchors" and proof[key].size()!=3: fail("proofs."+myth,"three result anchors required")
			for a in proof[key]:
				if not a is Dictionary or not entities.has(a.get("entity_id","")) or not point(a.get("offset")): fail("proofs."+myth,"invalid anchor")
		if not proof.get("predicates") is Array: fail("proofs."+myth,"predicates required")
		else:
			for pred in proof.predicates: validate_predicate(pred,"type","proofs."+myth)
	for id in routes:
		var r: Dictionary=routes[id]
		references(r.get("nodes"),nodes,"routes."+id+".nodes",false)
		if not r.get("nodes") is Array or r.nodes.size()<2: fail("routes."+id,"two nodes required")
		if not is_integer(r.get("ticks_per_edge",10)) or r.get("ticks_per_edge",10)<1: fail("routes."+id,"ticks_per_edge")
		if r.has("destination_reach_zone_id") and not zones.has(r.destination_reach_zone_id): fail("routes."+id,"destination reach")
		if r.has("required_support_entity") and (not entities.has(r.required_support_entity) or not slots.has(r.get("required_support_slot",""))): fail("routes."+id,"legacy support")
		if not r.get("requirements",[]) is Array: fail("routes."+id,"requirements"); continue
		for req in r.get("requirements",[]):
			if not req is Dictionary or not req.get("parameters") is Dictionary: fail("routes."+id,"requirement shape"); continue
			var p: Dictionary=req.parameters
			match req.get("type",""):
				"support":
					if p.get("kind") not in ["stone","paper"] or not entities.has(p.get("entity_id","")) or not slots.has(p.get("slot_id","")): fail("routes."+id,"support requirement")
				"water_phase", "entity_state": validate_predicate(req,"type","routes."+id)
				_: fail("routes."+id,"unknown requirement")
	for id in goals:
		var g: Dictionary=goals[id]
		if g.get("kind") not in ["state","latched"] or not g.get("required") is bool: fail("goals."+id,"kind/required")
		validate_predicate(g,"predicate_id","goals."+id)
	return errors

func validate_properties(e: Dictionary, id: String) -> void:
	var p: Dictionary=e.properties
	var path: String="entities."+id+".properties"
	for key in ["supports_entity","carrier_entity_id","hoist_entity_id","mooring_owner_entity_id","attachment_target_entity_id","tow_rope_entity_id"]:
		if p.has(key) and not entities.has(p[key]): fail(path+"."+key,"unknown entity")
	for key in ["support_when_slot"]:
		if p.has(key) and not slots.has(p[key]): fail(path+"."+key,"unknown slot")
	for key in ["span_anchor_entity_ids","payload_entity_ids","insulation_by_entity_ids","protects_entity_ids"]:
		if p.has(key): references(p[key],entities,path+"."+key)
	for key in ["load_slot_ids","service_slot_ids","protection_slot_ids"]:
		if p.has(key): references(p[key],slots,path+"."+key)
	for key in ["thermal_subject_zone_id","initial_reach_zone_id"]:
		if p.has(key) and not zones.has(p[key]): fail(path+"."+key,"unknown zone")
	for key in ["carry_capacity","support_capacity","load_capacity","tear_resistance","required_anchor_count","required_attachment_count","lift_capacity_units","rope_length_units","thermal_radius_units"]:
		if p.has(key) and (not is_integer(p[key]) or p[key]<0): fail(path+"."+key,"nonnegative integer required")
	for key in ["thermal_delta_per_tick","cold_damage_below"]:
		if p.has(key) and not is_integer(p[key]): fail(path+"."+key,"integer required")
	for key in ["buoyant","hidden_method","grounded","anchored","flammable","enabled","initial_closed","initial_open","payload_mass_included","foldable","initial_folded","removable","switchable"]:
		if p.has(key) and not p[key] is bool: fail(path+"."+key,"boolean required")
	if p.get("switchable",false) and p.get("emitter_class","")!="FIRE": fail(path,"switchable requires a controlled FIRE emitter")
	if p.has("remove_requires_law") and p.remove_requires_law not in LAWS: fail(path,"unknown removal law")
	if p.get("initial_folded",false) and not p.get("foldable",false): fail(path,"folded initial state requires foldable entity")
	if p.has("size") and p.size not in ["S","M","L"]: fail(path,"unknown size")
	if p.has("transport_mode") and p.transport_mode not in ["carried","wheeled","towed"]: fail(path,"unknown transport mode")
	if p.has("emitter_class") and p.emitter_class not in ["FIRE","HEATED_OBJECT","COLD_PACK"]: fail(path,"unknown emitter class")
	if e.material=="DECOY" and p.has("emitter_class"): fail(path,"DECOY cannot be a real emitter")
	if p.has("span_anchor_offsets"):
		if not p.span_anchor_offsets is Array or p.span_anchor_offsets.size()!=p.get("span_anchor_entity_ids",[]).size(): fail(path,"anchor offsets count")
		else:
			for offset in p.span_anchor_offsets:
				if not point(offset): fail(path,"anchor offset integer point")
	if p.has("support_offset") and not point(p.support_offset): fail(path,"support_offset integer point required")
	if p.has("scheduled_effects"):
		if not p.scheduled_effects is Array: fail(path,"scheduled effects array"); return
		for effect in p.scheduled_effects:
			if not effect is Dictionary: fail(path,"effect object"); continue
			integer_field(effect,"at_tick",path,0,299)
			if not effect.get("phases") is Array: fail(path,"effect phases"); continue
			for phase in effect.phases:
				if phase not in ["PERFORMANCE","REHEARSAL","RUN_RESOLUTION"]: fail(path,"effect phase")
			match effect.get("operation",""):
				"move_if_unsecured":
					if not slots.has(effect.get("target_slot_id","")): fail(path,"effect target slot")
				"set_occluder_enabled":
					if not occluders.has(effect.get("target_occluder_id","")) or not effect.get("value") is bool: fail(path,"effect occluder/value")
				_: fail(path,"unknown effect operation")

func validate_predicate(pred: Variant, type_key: String, path: String) -> void:
	if not pred is Dictionary or not pred.get(type_key) is String or not pred.get("parameters") is Dictionary: fail(path,"predicate shape"); return
	var kind: String=pred[type_key]
	var p: Dictionary=pred.parameters
	if not PREDICATES.has(kind): fail(path,"unknown predicate "+kind); return
	for key in PREDICATES[kind]:
		if not p.has(key): fail(path,"missing predicate parameter "+key)
	for key in ["entity_id","actor_id","paper_id","load_id"]:
		if p.has(key) and not entities.has(p[key]): fail(path,"unknown entity "+str(p[key]))
	if p.has("zone_id") and not zones.has(p.zone_id): fail(path,"unknown zone")
	if p.has("route_id") and not routes.has(p.route_id): fail(path,"unknown route")
	if p.has("node_id") and not nodes.has(p.node_id): fail(path,"unknown node")
	if p.has("myth_id") and p.myth_id not in LAWS: fail(path,"unknown myth")
	if p.has("phase") and p.phase not in ["liquid","frozen"]: fail(path,"unknown phase")
	if kind=="entity_state" and (p.get("key") not in ["open","closed","intact","moored","secured","enabled"] or not p.get("value") is bool): fail(path,"unknown entity state key/value")
	if kind=="observed_water_transition" and (p.get("from")!="liquid" or p.get("to")!="frozen"): fail(path,"unsupported observation transition")
	if kind=="load_contact" and (not is_integer(p.get("min_mass")) or p.get("min_mass",0)<1): fail(path,"control load mass")
