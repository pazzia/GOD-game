extends SceneTree
## Envelope migration/header boundaries independent of the author service tests.
const Saver=preload("res://services/save_service.gd")
const Kernel=preload("res://core/simulation_kernel.gd")
var count: int=0
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var s=Saver.new();var name: String="review_schema_migration";clean(name)
	var body: String=JSON.stringify({"marker":"legacy","integer":100000,"fraction":.25})
	var legacy: Dictionary={"schema_version":1,"revision":9007199254740990,"body":body,"checksum":body.sha256_text()}
	write(name,"",legacy)
	check(s.read_slot(name).get("marker")=="legacy" and s._valid_envelope("user://"+name+".json").revision==0,"legacy body remains readable but unsigned high revision is ignored")
	check(s.write_slot(name,{"marker":"schema2","integer":100000,"fraction":.25}),"valid legacy migrates through actual atomic writer")
	var envelope: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://"+name+".json"))
	check(envelope.schema_version==2 and envelope.revision==1 and s.read_slot(name).marker=="schema2","migration emits authenticated schema2 header with safe new ordering")
	write(name,".bak",legacy)
	check(s.read_slot(name).marker=="schema2","legacy high revision cannot outrank authenticated primary")
	var numeric: Dictionary=envelope.duplicate(true);numeric.schema_version=2.0;numeric.revision=1.0;write(name,"",numeric)
	check(s.read_slot(name).marker=="schema2","equivalent parsed JSON integer/float headers verify by canonical integer representation")
	var changed: Dictionary=envelope.duplicate(true);changed.schema_version=1;write(name,"",changed)
	check(s.read_slot(name).marker=="legacy","schema header downgrade cannot preserve schema2 signature")
	changed=envelope.duplicate(true);changed.revision=1.5;write(name,"",changed)
	check(s.read_slot(name).marker=="legacy","fractional revision cannot enter recovery ordering")
	changed=envelope.duplicate(true);changed.revision=-1;write(name,"",changed)
	check(s.read_slot(name).marker=="legacy","negative revision cannot enter recovery ordering")
	changed=envelope.duplicate(true);changed.body=changed.body.replace("schema2","forged");write(name,"",changed)
	check(s.read_slot(name).marker=="legacy","changed body is rejected before it can displace last valid backup")
	write(name,"",envelope)
	var saturated: Dictionary=envelope.duplicate(true);saturated.revision=Saver.MAX_REVISION;saturated.checksum=s._signature(2,Saver.MAX_REVISION,saturated.body);write(name,"",saturated)
	var before: String=FileAccess.get_file_as_string("user://"+name+".json")
	check(not s.write_slot(name,{"marker":"overflow"}) and s.last_error=="REVISION_LIMIT" and FileAccess.get_file_as_string("user://"+name+".json")==before,"revision saturation fails safely without changing primary or backup")
	var defaults: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/settings_default.json"))
	var sanitized: Dictionary=s.sanitize_settings(JSON.parse_string(JSON.stringify(defaults)),defaults)
	check(sanitized.accessibility.text_scale is int and sanitized.schema_version is int,"settings JSON roundtrip normalizes whole numbers for typed UI usage")
	# A player may enter the story, leave before finishing L01, and resume next launch.
	var progress_name: String="review_story_progress"
	var settings_name: String="review_story_settings"
	clean(progress_name);clean(settings_name)
	var personal_settings: Dictionary=defaults.duplicate(true)
	personal_settings.locale="en";personal_settings.audio.categories.Music.volume=.18
	check(s.write_slot(settings_name,personal_settings),"existing player settings commit before progress migration")
	var settings_bytes: String=FileAccess.get_file_as_string("user://"+settings_name+".json")
	var entered: Dictionary={"schema_version":1,"unlocked":1,"completed":{},"current_level":1,"story_started":true}
	check(s.write_slot(progress_name,entered),"entering the story persists before the first completion")
	var recovered: Dictionary=s.sanitize_progress(s.read_slot(progress_name),30)
	check(recovered.get("story_started") is bool and recovered.story_started and recovered.completed.is_empty(),"next launch preserves a typed started flag with zero completed levels")
	entered.story_started=false
	check(s.sanitize_progress(entered,30).get("story_started")==false,"an explicit false flag is preserved rather than promoted")
	for malformed in ["true",1,null,{},[]]:
		entered.story_started=malformed
		check(not s.sanitize_progress(entered,30).has("story_started"),"untyped started flags are not coerced")
	var kernel=Kernel.new()
	var definition: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/L01.json"))
	check(kernel.load_level(definition),"new rules load for the saved-progress boundary")
	var old_checkpoint: Dictionary=kernel.snapshot();old_checkpoint.rules_version="0.2.0-recovered"
	var legacy_progress: Dictionary={"schema_version":1,"unlocked":7,"completed":{"L01":{"stars":3},"L04":{"stars":2}},"current_level":5,"checkpoint":old_checkpoint,"story_started":true}
	check(s.write_slot(progress_name,legacy_progress),"campaign progress with an old checkpoint is saved intact")
	recovered=s.sanitize_progress(s.read_slot(progress_name),30)
	check(not kernel.restore(recovered.checkpoint),"a checkpoint from incompatible rules rejects safely")
	check(recovered.unlocked==7 and recovered.current_level==5 and recovered.completed==legacy_progress.completed and recovered.story_started,"checkpoint rejection does not erase unlocked levels, completions or story entry")
	check(FileAccess.get_file_as_string("user://"+settings_name+".json")==settings_bytes and s.read_slot(settings_name)==personal_settings,"progress migration leaves prior player settings byte-identical")
	var no_flag: Dictionary=legacy_progress.duplicate(true);no_flag.erase("story_started")
	check(not s.sanitize_progress(no_flag,30).has("story_started") and s.sanitize_progress(no_flag,30).completed==legacy_progress.completed,"legacy saves without the optional flag retain campaign progress")
	clean(progress_name);clean(settings_name)
	clean(name)
	print("SAVE RECOVERY EDGES: %d checks; %d failures"%[count,failures.size()])
	for issue in failures:printerr("FAIL: "+issue)
	var f=FileAccess.open("res://tests/reports/save-recovery-edges.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":count,"failures":failures,"engine":Engine.get_version_info().string},"  "));f.close()
	quit(0 if failures.is_empty() else 1)
func write(name: String,suffix: String,value: Dictionary) -> void:
	var f=FileAccess.open("user://"+name+".json"+suffix,FileAccess.WRITE);f.store_string(JSON.stringify(value));f.close()
func clean(name: String) -> void:
	for suffix in [".json",".json.bak",".json.tmp"]:
		if FileAccess.file_exists("user://"+name+suffix):DirAccess.remove_absolute("user://"+name+suffix)
func check(condition: bool,message: String) -> void:
	count+=1
	if not condition:failures.append(message)
