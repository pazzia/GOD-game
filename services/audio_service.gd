class_name GameAudio
extends Node
const CATEGORIES=["Music","SFX","Ambience","Voice","UI"]
var settings: Dictionary={}
var catalog: Dictionary={}
var music: AudioStreamPlayer
var ambience: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer]=[]
var _next: int=0
var _event_variants: Dictionary={}
var _event_counts: Dictionary={}
var _ambience_layers: Array[AudioStreamPlayer]=[]
var _ambient_names: Array=[]
var _music_name: String=""
var _sync: AudioStreamSynchronized
var _chapter_theme: String=""
var _phase: String="PLAN_SHOW"
var _mix: Array[float]=[1.0,0.5,0.0]
var _target_mix: Array[float]=[1.0,0.5,0.0]
var _duck_remaining: float=0.0
var _duck_level: float=-4.0
var last_error: String=""
var _paused: bool=false
const CHAPTER_FADE_SECONDS=1.2
const STEM_FADE_SECONDS=.45
var _music_players: Array[AudioStreamPlayer]=[]
var _music_weights: Array[float]=[1.0,0.0]
var _incoming_index: int=0
var _outgoing_index: int=-1
var _chapter_fade_elapsed: float=CHAPTER_FADE_SECONDS
var _outgoing_start: float=1.0
var _queued_music: Dictionary={}
var _requested_music_name: String=""
var _transport_seconds: float=0.0
var _tempo_bpm: float=96.0
var _beats_per_bar: int=4
var _next_mix_at: float=-1.0
var _pending_mix: Array[float]=[]
var _mix_from: Array[float]=[1.0,.5,0.0]
var _mix_fade_elapsed: float=STEM_FADE_SECONDS
var _duck_db: float=0.0
var _track_metadata: Dictionary={}
var _closed: bool=false
var _retiring_playbacks: Array[WeakRef]=[]
func configure(values: Dictionary) -> void:
	if _closed:last_error="AUDIO_SHUTDOWN";return
	settings=values.duplicate(true)
	apply_settings() # before creating or starting a player
	for path in ["res://assets/audio/production/runtime_catalog.json","res://assets/audio/runtime_catalog.json"]:
		if FileAccess.file_exists(path):
			var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:catalog=parsed
	if FileAccess.file_exists("res://data/audio_catalog.json"):
		var metadata=JSON.parse_string(FileAccess.get_file_as_string("res://data/audio_catalog.json"))
		if metadata is Dictionary:
			_event_variants=metadata.get("events",{})
			for entry in metadata.get("files",[]):
				if entry is Dictionary and entry.get("id") is String:
					_track_metadata[entry.id]=entry
					if entry.get("path") is String:_track_metadata[entry.path]=entry
	for i in range(2):
		var player=AudioStreamPlayer.new();player.bus="Music";add_child(player);_music_players.append(player)
	music=_music_players[0]
	for i in range(2):
		var layer=AudioStreamPlayer.new();layer.bus="Ambience";add_child(layer);_ambience_layers.append(layer)
	ambience=_ambience_layers[0]
	for i in range(16):
		var player=AudioStreamPlayer.new();add_child(player);_pool.append(player)
func apply_settings() -> void:
	var gain: float=float(settings.get("master_volume",.8))
	AudioServer.set_bus_mute(0,gain<=0 or settings.get("master_muted",false))
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(gain*gain,.00001)))
	for category in CATEGORIES:
		var index: int=AudioServer.get_bus_index(category)
		if index<0:continue
		var entry: Dictionary=settings.get("categories",{}).get(category,{"volume":.7,"enabled":true})
		var volume: float=float(entry.volume)
		AudioServer.set_bus_mute(index,not entry.enabled or volume<=0 or (category!="Music" and not settings.get("sound_enabled",true)))
		AudioServer.set_bus_volume_db(index,linear_to_db(maxf(volume*volume,.00001)))
func _entry(name: String) -> Dictionary:
	if catalog.has(name) and catalog[name] is Dictionary:return catalog[name]
	for collection in ["events","sounds","tracks","assets"]:
		var data=catalog.get(collection,{})
		if data is Dictionary and data.has(name):return data[name]
		if data is Array:
			for item in data:
				if item.get("id",item.get("name",""))==name:return item
	return {}
func _path(name: String) -> String:
	var entry: Dictionary=_entry(name)
	var path: String=entry.get("path",entry.get("file",""))
	if path.is_empty():path="res://assets/audio/"+name+".wav"
	elif not path.begins_with("res://"):path="res://assets/audio/production/"+path
	return path
func _loop_stream(path: String) -> AudioStream:
	var stream=load(path).duplicate()
	if stream is AudioStreamWAV:
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;stream.loop_begin=0;stream.loop_end=int(stream.get_length()*stream.mix_rate)
	elif stream is AudioStreamOggVorbis:stream.loop=true
	return stream
func play_music(name: String) -> void:
	if _closed or _music_players.size()!=2:return
	if _requested_music_name==name:return
	var path: String=_path(name)
	if not ResourceLoader.exists(path):return
	var metadata: Dictionary=_track_metadata.get(name,_track_metadata.get(path,{}))
	var meter: Array=metadata.get("meter",[4,4])
	_request_music({"name":name,"stream":_loop_stream(path),"sync":null,"chapter":"","tempo":float(metadata.get("tempo_bpm",64)),"meter":int(meter[0])})
func _request_music(request: Dictionary) -> void:
	if _closed or _music_players.size()!=2:return
	if request.name==_music_name:
		_queued_music.clear();_requested_music_name=request.name
		return
	_requested_music_name=request.name
	if _chapter_fade_elapsed<CHAPTER_FADE_SECONDS:
		# Fast navigation keeps at most two live timelines and queues only the last choice.
		_queued_music=request
		return
	_start_music(request)
func _start_music(request: Dictionary) -> void:
	if _closed or _music_players.size()!=2:return
	var old_index: int=_incoming_index
	var has_old: bool=_music_players[old_index].stream!=null
	if has_old:_incoming_index=1-old_index
	var incoming: AudioStreamPlayer=_music_players[_incoming_index]
	_stop_player(incoming);incoming.stream=request.stream;incoming.volume_db=-80
	music=incoming
	_sync=request.sync;_chapter_theme=request.chapter;_music_name=request.name
	_tempo_bpm=request.tempo;_beats_per_bar=request.meter
	_transport_seconds=0;_next_mix_at=-1;_pending_mix.clear()
	_mix=_phase_mix(_phase);_target_mix=_mix.duplicate();_mix_from=_mix.duplicate();_mix_fade_elapsed=STEM_FADE_SECONDS
	if _sync!=null:
		for i in range(3):_sync.set_sync_stream_volume(i,linear_to_db(maxf(_mix[i],.00001)))
	if has_old:
		_outgoing_index=old_index;_outgoing_start=_music_weights[old_index]
		_music_weights[_incoming_index]=0;_chapter_fade_elapsed=0
	else:
		_outgoing_index=-1;_music_weights[_incoming_index]=1;_chapter_fade_elapsed=CHAPTER_FADE_SECONDS
	incoming.play();incoming.stream_paused=_paused
	_apply_music_gains()
func play_ambience(name: String="river_ambience") -> void:
	if _closed:return
	var path: String=_path(name)
	if ResourceLoader.exists(path):_stop_player(ambience);ambience.stream=_loop_stream(path);ambience.play();ambience.stream_paused=_paused
func play(name: String,category: String="SFX",pitch: float=1) -> void:
	if _closed:return
	var path: String=_path(name)
	if not ResourceLoader.exists(path) or _pool.is_empty():return
	var entry: Dictionary=_entry(name)
	var leaf: String=entry.get("bus",category)
	if leaf not in CATEGORIES:last_error="INVALID_LEAF_BUS";return
	var player: AudioStreamPlayer=_pool[_next];_next=(_next+1)%_pool.size()
	_stop_player(player);player.bus=leaf;player.stream=load(path);player.pitch_scale=clampf(pitch,.8,1.2);player.play();player.stream_paused=_paused
	if player.bus=="Voice" and _audible("Voice"):duck_music(.65,-4.0)
func set_paused(value: bool) -> void:
	if _closed:return
	_paused=value
	set_process(not value)
	for player in _music_players:player.stream_paused=value
	for layer in _ambience_layers:layer.stream_paused=value
	for player in _pool:player.stream_paused=value
func _stop_player(player: AudioStreamPlayer) -> void:
	# Godot retires stopped playback on its mixer thread, then releases it during
	# AudioServer.update(). A cleared player.stream is not evidence of that release.
	if player.has_stream_playback():_retiring_playbacks.append(weakref(player.get_stream_playback()))
	player.stop()
func _prune_retiring_playbacks() -> void:
	for i in range(_retiring_playbacks.size()-1,-1,-1):
		if _retiring_playbacks[i].get_ref()==null:_retiring_playbacks.remove_at(i)
func shutdown_complete() -> bool:
	_prune_retiring_playbacks()
	return _closed and _retiring_playbacks.is_empty()
func shutdown_and_wait(timeout_seconds: float=2.0) -> bool:
	shutdown()
	var deadline: int=Time.get_ticks_msec()+int(maxf(0,timeout_seconds)*1000)
	while not shutdown_complete():
		if not is_inside_tree() or Time.get_ticks_msec()>=deadline:
			last_error="AUDIO_SHUTDOWN_TIMEOUT"
			return false
		await get_tree().process_frame
	if last_error=="AUDIO_SHUTDOWN_TIMEOUT":last_error=""
	return true
func shutdown() -> void:
	_closed=true;set_process(false)
	_sync=null
	for player in _music_players:
		if is_instance_valid(player):player.stream_paused=false;_stop_player(player);player.stream=null
	_queued_music.clear();_music_players.clear()
	for layer in _ambience_layers:
		if is_instance_valid(layer):layer.stream_paused=false;_stop_player(layer);layer.stream=null
	_ambience_layers.clear()
	for player in _pool:
		if is_instance_valid(player):player.stream_paused=false;_stop_player(player);player.stream=null
	_pool.clear()
func _exit_tree() -> void:shutdown()

func set_chapter_theme(scene_id: String,finale: bool=false) -> bool:
	if _closed or _music_players.size()!=2:return false
	_set_ambience(scene_id)
	var prefix: String="FINALE" if finale else {"ENV01":"RIVER","ENV02":"KITCHEN","ENV03":"ARCHIVE"}.get(scene_id,"RIVER")
	var requested_name: String="chapter_"+prefix
	if _requested_music_name==requested_name:return true
	var synchronized=AudioStreamSynchronized.new();synchronized.stream_count=3
	var stems: Array=["BED","CURIOSITY","TENSION"]
	for i in range(3):
		var path: String=_path("MUS_"+prefix+"_"+stems[i])
		if not ResourceLoader.exists(path):return false
		synchronized.set_sync_stream(i,_loop_stream(path))
	var metadata: Dictionary=_track_metadata.get("MUS_"+prefix+"_BED",{})
	var meter: Array=metadata.get("meter",[4,4])
	_request_music({"name":requested_name,"stream":synchronized,"sync":synchronized,"chapter":prefix,"tempo":float(metadata.get("tempo_bpm",96)),"meter":int(meter[0])})
	return true
func _phase_mix(value: String) -> Array[float]:
	if value in ["PERFORMANCE","REHEARSAL"]:return [0.8,0.25,0.75]
	if value=="RUN_RESOLUTION":return [1.0,0.35,0.2]
	if value in ["PROOF_ACCEPTED","LAW_SELECTION"]:return [0.75,0.6,0.0]
	return [1.0,0.55,0.0]
func set_phase(value: String) -> void:
	if _closed:return
	if _phase==value:return
	_phase=value
	_pending_mix=_phase_mix(value)
	var bar: float=_beats_per_bar*60.0/_tempo_bpm
	_next_mix_at=(floor(_transport_seconds/bar)+1)*bar
func duck_music(seconds: float,decibels: float=-9.0) -> void:
	if _closed:return
	_duck_remaining=maxf(_duck_remaining,seconds);_duck_level=minf(_duck_level,decibels)
func _process(delta: float) -> void:
	if _closed or not is_processing():return
	_prune_retiring_playbacks()
	_transport_seconds+=maxf(0,delta)
	if _sync!=null:
		if _next_mix_at>=0 and _transport_seconds>=_next_mix_at:
			_mix_from=_mix.duplicate();_target_mix=_pending_mix.duplicate();_mix_fade_elapsed=0
			_pending_mix.clear();_next_mix_at=-1
		if _mix_fade_elapsed<STEM_FADE_SECONDS:
			_mix_fade_elapsed=minf(STEM_FADE_SECONDS,_mix_fade_elapsed+delta)
			var alpha: float=_mix_fade_elapsed/STEM_FADE_SECONDS
			for i in range(3):_mix[i]=lerpf(_mix_from[i],_target_mix[i],alpha)
		for i in range(3):_sync.set_sync_stream_volume(i,linear_to_db(maxf(_mix[i],.00001)))
	if _chapter_fade_elapsed<CHAPTER_FADE_SECONDS:
		_chapter_fade_elapsed=minf(CHAPTER_FADE_SECONDS,_chapter_fade_elapsed+delta)
		var alpha: float=_chapter_fade_elapsed/CHAPTER_FADE_SECONDS
		_music_weights[_incoming_index]=sin(alpha*PI*.5)
		if _outgoing_index>=0:_music_weights[_outgoing_index]=_outgoing_start*cos(alpha*PI*.5)
		if _chapter_fade_elapsed>=CHAPTER_FADE_SECONDS and _outgoing_index>=0:
			_stop_player(_music_players[_outgoing_index]);_music_players[_outgoing_index].stream=null
			_music_weights[_outgoing_index]=0;_outgoing_index=-1
	if _duck_remaining>0:_duck_remaining=maxf(0,_duck_remaining-delta)
	_duck_db=move_toward(_duck_db,_duck_level if _duck_remaining>0 else 0.0,delta*18)
	if _duck_remaining<=0:_duck_level=-4.0
	_apply_music_gains()
	if _chapter_fade_elapsed>=CHAPTER_FADE_SECONDS and not _queued_music.is_empty():
		var request: Dictionary=_queued_music;_queued_music={};_start_music(request)
func _apply_music_gains() -> void:
	for i in range(_music_players.size()):_music_players[i].volume_db=linear_to_db(maxf(_music_weights[i],.00001))+_duck_db
func conductor_state() -> Dictionary:
	return {"active":_music_name,"requested":_requested_music_name,"queued":not _queued_music.is_empty(),"crossfade_seconds":CHAPTER_FADE_SECONDS,"crossfade_elapsed":_chapter_fade_elapsed,"weights":_music_weights.duplicate(),"transport":_transport_seconds,"tempo":_tempo_bpm,"next_bar_mix_at":_next_mix_at,"mix":_mix.duplicate(),"stem_fade_seconds":STEM_FADE_SECONDS,"stem_fade_elapsed":_mix_fade_elapsed}

func play_event(id: String,category: String="SFX") -> String:
	if _closed:return ""
	var variants: Array=_event_variants.get(id,[])
	if variants.is_empty():play(id,category);return id
	var index: int=int(_event_counts.get(id,0))%variants.size()
	_event_counts[id]=index+1
	play(variants[index],category)
	return variants[index]
func _set_ambience(scene_id: String) -> void:
	var names: Array={"ENV01":["AMB_RIVER_WATER","AMB_RIVER_WIND"],"ENV02":["AMB_KITCHEN_HOUSE","AMB_KITCHEN_STEAM"],"ENV03":["AMB_ARCHIVE_PAPER","AMB_ARCHIVE_WIND"]}.get(scene_id,["AMB_RIVER_WATER","AMB_RIVER_WIND"])
	if _ambient_names==names:return
	_ambient_names=names.duplicate()
	for i in range(_ambience_layers.size()):
		var path: String=_path(names[i])
		_stop_player(_ambience_layers[i])
		if ResourceLoader.exists(path):_ambience_layers[i].stream=_loop_stream(path);_ambience_layers[i].volume_db=-6.0 if i==1 else -2.0;_ambience_layers[i].play();_ambience_layers[i].stream_paused=_paused

func _audible(category: String) -> bool:
	var bus: int=AudioServer.get_bus_index(category)
	return bus>=0 and not AudioServer.is_bus_mute(0) and not AudioServer.is_bus_mute(bus) and AudioServer.get_bus_volume_db(0)>-80 and AudioServer.get_bus_volume_db(bus)>-80
