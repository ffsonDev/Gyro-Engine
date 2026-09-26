class_name AudioSystem
extends GyroSystem

var sound_players := {}
var stream_cache := {}

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

func _action_play_sound(action: GyroAction, payload: Dictionary) -> void:
	var sound_ref := str(runtime._resolve_value(action.data.get("sound", ""), payload))
	if sound_ref == "":
		runtime._debug("PlaySound: пустое имя звука")
		return
	var stored_path := _sound_stored_path_by_name(sound_ref)
	if stored_path == "":
		stored_path = sound_ref
	var resolved := GyroAssetPaths.resolve_asset_path(stored_path, runtime._project_path())
	if resolved == "":
		runtime._debug("PlaySound: не удалось вычислить путь звука")
		return
	var want_loop := runtime._to_bool(runtime._resolve_value(action.data.get("loop", false), payload))
	var cache_key := resolved + ("|loop" if want_loop else "")
	var stream: AudioStream = stream_cache.get(cache_key, null)
	if stream == null:
		var base := GyroMedia.load_audio(resolved)
		if base != null:
			if want_loop and "loop" in base:
				stream = base.duplicate() as AudioStream
				stream.set("loop", true)
			else:
				stream = base
			stream_cache[cache_key] = stream
	if stream == null:
		runtime._debug("PlaySound: не удалось загрузить аудио: " + resolved)
		return
	var player: AudioStreamPlayer = sound_players.get(sound_ref, null)
	if player == null or not is_instance_valid(player):
		player = AudioStreamPlayer.new()
		if host != null:
			host.add_child(player)
		sound_players[sound_ref] = player
	player.stream = stream
	var volume := clampf(runtime._to_float(runtime._resolve_value(action.data.get("volume", 1.0), payload)), 0.0, 1.0)
	if volume <= 0.0:
		player.volume_db = -80.0
	else:
		player.volume_db = linear_to_db(volume)
	player.play()

func _action_stop_sound(action: GyroAction, payload: Dictionary) -> void:
	var sound_ref := str(runtime._resolve_value(action.data.get("sound", ""), payload))
	if sound_ref == "":
		for key in sound_players.keys():
			var p: AudioStreamPlayer = sound_players[key]
			if is_instance_valid(p):
				p.stop()
		return
	var player: AudioStreamPlayer = sound_players.get(sound_ref, null)
	if player != null and is_instance_valid(player):
		player.stop()

func _action_set_sound_volume(action: GyroAction, payload: Dictionary) -> void:
	var sound_ref := str(runtime._resolve_value(action.data.get("sound", ""), payload))
	var volume := clampf(runtime._to_float(runtime._resolve_value(action.data.get("volume", 100), payload)), 0.0, 100.0) / 100.0
	var db := -80.0 if volume <= 0.0 else linear_to_db(volume)
	if sound_ref == "":
		for key in sound_players.keys():
			var p: AudioStreamPlayer = sound_players[key]
			if is_instance_valid(p):
				p.volume_db = db
		return
	var player: AudioStreamPlayer = sound_players.get(sound_ref, null)
	if player != null and is_instance_valid(player):
		player.volume_db = db
