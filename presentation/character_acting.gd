extends RefCounted
## Authored cosmetic cue library. No simulation state or gameplay callbacks.
const CATALOG_PATH="res://data/character_animations.json"
const FALLBACKS={"idle":"idle","observe":"observe","suspect":"suspect","accept":"accept","reveal":"reveal_react","success":"celebrate","enter":"turn","interact":"point","move":"move"}
static var _catalog: Dictionary={}

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var parsed=JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if parsed is Dictionary and parsed.get("schema_version")==1:_catalog=parsed
	return _catalog

static func states_for(actor: String) -> Array:
	return catalog().get("actors",{}).get(actor,{}).keys()

static func definition(actor: String,state: String) -> Dictionary:
	return catalog().get("actors",{}).get(actor,{}).get(state,{})

static func pose_for(actor: String,trigger: String,variant: int=0) -> String:
	var choices: Array=catalog().get("cues",{}).get(actor,{}).get(trigger,[])
	if choices.is_empty():return FALLBACKS.get(trigger,"")
	return str(choices[posmod(variant,choices.size())])

static func is_loop(actor: String,state: String) -> bool:
	return bool(definition(actor,state).get("loop",false))
