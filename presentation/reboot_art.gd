class_name RebootArt
extends RefCounted
## The production illustration manifest is the only atlas/crop authority.
## Texture regions never change collision, sight or simulation coordinates.
const MANIFEST_PATH: String="res://assets/art/reboot/manifest.json"
const ACTOR_IDS={"felix":"CH01","plum":"CH02","marfa":"CH03","semyon":"CH04","nika":"CH05","lada":"CH06","roza":"CH07","hugo":"CH08","caramelka":"CH09","crowd_gardener":"CROWD01","crowd_postwoman":"CROWD02","crowd_fisherman":"CROWD03","crowd_librarian":"CROWD04","crowd_merchant":"CROWD05","crowd_musician":"CROWD06"}
static var _manifest: Dictionary={}
static var _texture_cache: Dictionary={}

static func manifest() -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists(MANIFEST_PATH):
		var parsed=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if parsed is Dictionary:_manifest=parsed
	return _manifest

static func entry(category: String,key: String,variant: String="") -> Dictionary:
	var group: Dictionary=manifest().get(category,{})
	var record=group.get(key,{})
	if not record is Dictionary:return {}
	var variants: Dictionary=record.get("variants",record.get("states",{}))
	if not variant.is_empty() and variants.has(variant):
		var state=variants[variant]
		if state is Dictionary:
			var result: Dictionary=record.duplicate(true)
			result.merge(state,true)
			return result
	return record

static func actor_key(actor: String) -> String:
	return str(ACTOR_IDS.get(actor,actor))

static func has_art(category: String,key: String) -> bool:
	return not entry(category,key).is_empty()

static func texture_for(category: String,key: String,variant: String="") -> Texture2D:
	var record: Dictionary=entry(category,key,variant)
	if record.is_empty():return null
	var path: String=str(record.get("path",""))
	if not path.begins_with("res://assets/art/reboot/") or path.contains(".."):return null
	var region=record.get("region")
	var cache_key: String=path+":"+str(region)
	if _texture_cache.has(cache_key):return _texture_cache[cache_key]
	if not ResourceLoader.exists(path):return null
	var source: Texture2D=load(path)
	if source==null:return null
	var result: Texture2D=source
	if region is Array and region.size()==4:
		var rect: Rect2=Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3]))
		if rect.size.x<=0 or rect.size.y<=0 or not Rect2(Vector2.ZERO,source.get_size()).encloses(rect):return null
		var atlas=AtlasTexture.new();atlas.atlas=source;atlas.region=rect;atlas.filter_clip=true
		result=atlas
	_texture_cache[cache_key]=result
	return result
