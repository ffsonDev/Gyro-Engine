class_name AudioSystem
extends GyroSystem

const MAX_PLAYERS := 24
const MAX_POLYPHONY := 4
const MAX_CACHE_SIZE := 64

var stream_cache := {}
var _players := {}
var _volumes := {}
var _total_players := 0

func execute(action: GyroAction, payload: Dictionary) -> void:
	match action.type:
		"PlaySound":
			_action_play_sound(action, payload)
		"StopSound":
			_action_stop_sound(action, payload)
		"SetSoundVolume":
			_action_set_sound_volume(action, payload)

func _sound_stored_path_by_name(sound_ref: String) -> String:
	var project := runtime._get_project()
	if project == null:
		return ""
	for v in project.assets:
		var a := v as GyroAsset
		if a != null and a.kind == "sound" and (a.id == sound_ref or a.asset_name == sound_ref):
			return a.path
	return ""

func _load_stream(resolved: String, want_loop: bool) -> AudioStream:
	var key := resolved + ("|loop" if want_loop else "")
	var cached = stream_cache.get(key, null)
	if cached != null:
		return cached as AudioStream
	var base := GyroMedia.load_audio(resolved)
	if base == null:
		return null
	var stream := base
	if want_loop:
		stream = base.duplicate() as AudioStream
		if "loop" in stream:
			stream.set("loop", true)
		elif "loop_mode" in stream:
			stream.set("loop_mode", 1)
	stream_cache[key] = stream
	_prune_cache()
	return stream

func _prune_cache() -> void:
	if stream_cache.size() <= MAX_CACHE_SIZE:
		return
	var used := {}
	for list in _players.values():
		for p in list:
			if is_instance_valid(p) and p.stream != null:
				used[p.stream] = true
	for key in stream_cache.keys():
		if stream_cache.size() <= MAX_CACHE_SIZE:
			break
		if not used.has(stream_cache[key]):
			stream_cache.erase(key)

func _get_player(sound_ref: String) -> AudioStreamPlayer:
	var list: Array = _players.get(sound_ref, [])
	for p in list:
		if is_instance_valid(p) and not p.playing:
			return p
	if list.size() < MAX_POLYPHONY and _total_players < MAX_PLAYERS:
		var player := AudioStreamPlayer.new()
		if host != null:
			host.add_child(player)
		list.append(player)
		_players[sound_ref] = list
		_total_players += 1
		return player
	for p in list:
		if is_instance_valid(p):
			list.erase(p)
			list.append(p)
			_players[sound_ref] = list
			return p
	return null

func _action_play_sound(action: GyroAction, payload: Dictionary) -> void:
	var sound_ref := str(runtime._resolve_value(action.data.get("sound", ""), payload))
	if sound_ref == "":
		runtime._debug("PlaySound: empty sound name")
		return
	var stored_path := _sound_stored_path_by_name(sound_ref)
	if stored_path == "":
		stored_path = sound_ref
	var resolved := GyroAssetPaths.resolve_asset_path(stored_path, runtime._project_path())
	if resolved == "":
		runtime._debug("PlaySound: cannot resolve path")
		return
	var want_loop := runtime._to_bool(runtime._resolve_value(action.data.get("loop", false), payload))
	var stream := _load_stream(resolved, want_loop)
	if stream == null:
		runtime._debug("PlaySound: cannot load audio: " + resolved)
		return
	var player := _get_player(sound_ref)
	if player == null:
		runtime._debug("PlaySound: player limit reached")
		return
	player.stream = stream
	var volume_value = action.data.get("volume", null)
	var volume := clampf(runtime._to_float(runtime._resolve_value(volume_value, payload)), 0.0, 1.0) if volume_value != null else float(_volumes.get(sound_ref, 1.0))
	player.volume_db = -80.0 if volume <= 0.0 else linear_to_db(volume)
	player.play()

func _action_stop_sound(action: GyroAction, payload: Dictionary) -> void:
	var sound_ref := str(runtime._resolve_value(action.data.get("sound", ""), payload))
	if sound_ref == "":
		for list in _players.values():
			for p in list:
				if is_instance_valid(p):
					p.stop()
		return
	for p in _players.get(sound_ref, []):
		if is_instance_valid(p):
			p.stop()

func _action_set_sound_volume(action: GyroAction, payload: Dictionary) -> void:
	var sound_ref := str(runtime._resolve_value(action.data.get("sound", ""), payload))
	var volume := clampf(runtime._to_float(runtime._resolve_value(action.data.get("volume", 100), payload)), 0.0, 100.0) / 100.0
	var db := -80.0 if volume <= 0.0 else linear_to_db(volume)
	if sound_ref == "":
		for key in _players.keys():
			_volumes[key] = volume
			for p in _players[key]:
				if is_instance_valid(p):
					p.volume_db = db
		return
	_volumes[sound_ref] = volume
	for p in _players.get(sound_ref, []):
		if is_instance_valid(p):
			p.volume_db = db

func cleanup() -> void:
	for list in _players.values():
		for p in list:
			if is_instance_valid(p):
				p.stop()
				p.queue_free()
	_players.clear()
	_volumes.clear()
	stream_cache.clear()
	_total_players = 0
