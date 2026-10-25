class_name SaveService
extends RefCounted
## Checksummed schema-2 headers, atomic commits and the last valid backup.
const ROOT="user://"
const ENVELOPE_SCHEMA=2
const MAX_REVISION=9007199254740990
var last_error: String=""
func _signature(schema: int,revision: int,body: String) -> String:
	return ("%d:%d:%s"%[schema,revision,body]).sha256_text()
func _valid_envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return {}
	var parser=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK:return {}
	var e=parser.data
	if e is not Dictionary:return {}
	var schema=e.get("schema_version",0)
	if not (schema is int or schema is float) or not is_finite(float(schema)) or schema!=floor(schema) or int(schema) not in [1,ENVELOPE_SCHEMA]:return {}
	if not e.get("body") is String or not e.get("checksum") is String:return {}
	var rev=e.get("revision",0)
	if not (rev is int or rev is float) or not is_finite(float(rev)) or rev<0 or rev>MAX_REVISION or rev!=floor(rev):return {}
	if e.schema_version==ENVELOPE_SCHEMA:
		if _signature(ENVELOPE_SCHEMA,int(rev),e.body)!=e.checksum:return {}
	else:
		# Version 1 did not authenticate its revision. Migrate its body, never trust that ordering header.
		if e.body.sha256_text()!=e.checksum:return {}
		rev=0
	var content=JSON.new()
	if content.parse(e.body)!=OK or not content.data is Dictionary:return {}
	return {"revision":int(rev),"payload":content.data,"body":e.body,"schema_version":e.schema_version}
func write_slot(name: String,payload: Dictionary) -> bool:
	last_error=""
	if not _safe_name(name):last_error="INVALID_SLOT";return false
	var path: String=ROOT+name+".json"
	var temp: String=path+".tmp"
	var backup: String=path+".bak"
	var old: Dictionary=_valid_envelope(path)
	var previous: Dictionary=_valid_envelope(backup)
	var revision: int=maxi(int(old.get("revision",0)),int(previous.get("revision",0)))+1
	if revision>MAX_REVISION:last_error="REVISION_LIMIT";return false
	var body: String=JSON.stringify(payload)
	var text: String=JSON.stringify({"schema_version":ENVELOPE_SCHEMA,"revision":revision,"body":body,"checksum":_signature(ENVELOPE_SCHEMA,revision,body)})
	var file=FileAccess.open(temp,FileAccess.WRITE)
	if file==null:last_error="WRITE_FAILED";return false
	file.store_string(text);file.flush();file.close()
	var verified: Dictionary=_valid_envelope(temp)
	if verified.is_empty() or verified.body!=body:last_error="VERIFY_FAILED";return false
	if FileAccess.file_exists(path):
		if not old.is_empty() and int(old.revision)>=int(previous.get("revision",-1)):
			if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup)!=OK:last_error="BACKUP_REMOVE_FAILED";return false
			if DirAccess.rename_absolute(path,backup)!=OK:last_error="BACKUP_FAILED";return false
		elif DirAccess.remove_absolute(path)!=OK:last_error="REMOVE_INVALID_FAILED";return false
	if DirAccess.rename_absolute(temp,path)!=OK:last_error="COMMIT_FAILED";return false
	return true
func read_slot(name: String,fallback: Dictionary={}) -> Dictionary:
	if not _safe_name(name):return fallback.duplicate(true)
	var primary: Dictionary=_valid_envelope(ROOT+name+".json")
	var backup: Dictionary=_valid_envelope(ROOT+name+".json.bak")
	var newest: Dictionary=primary if int(primary.get("revision",-1))>=int(backup.get("revision",-1)) else backup
	return fallback.duplicate(true) if newest.is_empty() else newest.payload.duplicate(true)
func _safe_name(name: String) -> bool:
	if name.is_empty() or name.length()>64:return false
	for character in name:
		if character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":return false
	return true
func sanitize_settings(value: Dictionary,defaults: Dictionary) -> Dictionary:
	var result: Dictionary=defaults.duplicate(true)
	for key in defaults:
		if not value.has(key):continue
		var candidate=value[key]
		if defaults[key] is Dictionary:
			if candidate is Dictionary:result[key]=sanitize_settings(candidate,defaults[key])
		elif defaults[key] is bool:
			if candidate is bool:result[key]=candidate
		elif defaults[key] is int or defaults[key] is float:
			if not (candidate is float or candidate is int) or not is_finite(float(candidate)):continue
			if key.contains("volume") and (candidate<0 or candidate>1):continue
			if key=="text_scale" and candidate not in [1,1.2,1.4]:continue
			if key=="schema_version" and candidate!=defaults[key]:continue
			result[key]=candidate
		elif defaults[key] is String and candidate is String:
			if key=="locale" and candidate not in ["ru","en"]:continue
			result[key]=candidate
	return _normalize_numbers(result)
func _normalize_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary={}
		for key in value:out[key]=_normalize_numbers(value[key])
		return out
	if value is Array:
		var out: Array=[]
		for child in value:out.append(_normalize_numbers(child))
		return out
	if value is float and is_finite(value) and value==floor(value):return int(value)
	return value
func sanitize_progress(value: Dictionary,maximum_level: int) -> Dictionary:
	var result: Dictionary={"schema_version":1,"unlocked":1,"completed":{},"current_level":1}
	# This records entering the story even before the first puzzle is completed.
	# Keep it optional for legacy saves; malformed values must not enable resume.
	if value.get("story_started") is bool:result.story_started=value.story_started
	for key in ["unlocked","current_level"]:
		var candidate=value.get(key)
		if (candidate is int or candidate is float) and is_finite(float(candidate)) and candidate==floor(candidate):result[key]=clampi(int(candidate),1,maxi(1,maximum_level))
	if value.get("completed") is Dictionary:
		for id in value.completed:
			if not id is String or not value.completed[id] is Dictionary:continue
			var stars=value.completed[id].get("stars")
			if (stars is int or stars is float) and is_finite(float(stars)) and stars==floor(stars) and stars>=1 and stars<=3:result.completed[id]={"stars":int(stars)}
	if value.get("checkpoint") is Dictionary:result.checkpoint=value.checkpoint.duplicate(true)
	return result
