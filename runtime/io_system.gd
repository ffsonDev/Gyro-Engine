class_name IOSystem
extends GyroSystem

func execute(action: GyroAction, payload: Dictionary) -> void:
	match action.type:
		"ReadFile":
			_action_read_file(action, payload)
		"WriteFile":
			_action_write_file(action, payload)
		"FileOp":
			_action_file_op(action, payload)
		"HttpRequest":
			_action_http_request(action, payload)
		"SaveValue":
			_action_save_value(action, payload)
		"LoadValue":
			_action_load_value(action, payload)

func _user_path(path: String) -> String:
	var p := str(path)
	if p.begins_with("user://"):
		return p
	if p.begins_with("/"):
		p = p.substr(1)
	return "user://" + p

func _save_file_path() -> String:
	return "user://gyro_save_" + str(runtime._project_path().get_file().get_basename()) + ".json"

func _load_save_dict() -> Dictionary:
	var f := FileAccess.open(_save_file_path(), FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}

func _write_save_dict(data: Dictionary) -> void:
	var f := FileAccess.open(_save_file_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))

func _action_read_file(action: GyroAction, payload: Dictionary) -> void:
	var variable_name := str(action.data.get("variable", ""))
	if variable_name == "":
		return
	var path := str(runtime._resolve_value(action.data.get("path", ""), payload))
	if path == "":
		return
	var resolved := path
	if not path.begins_with("user://") and not path.begins_with("res://"):
		resolved = _user_path(path)
	if not FileAccess.file_exists(resolved):
		var proj := runtime._get_project()
		if proj != null:
			for v in proj.assets:
				var a := v as GyroAsset
				if a != null and (a.id == path or a.asset_name == path):
					resolved = GyroAssetPaths.resolve_asset_path(a.path, runtime._project_path())
					break
	var f := FileAccess.open(resolved, FileAccess.READ)
	if f == null:
		return
	runtime.variables[variable_name] = f.get_as_text()

func _action_write_file(action: GyroAction, payload: Dictionary) -> void:
	var path := str(runtime._resolve_value(action.data.get("path", ""), payload))
	if path == "":
		return
	var f := FileAccess.open(_user_path(path), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(str(runtime._resolve_value(action.data.get("value", ""), payload)))

func _action_file_op(action: GyroAction, payload: Dictionary) -> void:
	var op := str(action.data.get("op", "delete"))
	var p1 := _user_path(str(runtime._resolve_value(action.data.get("path1", ""), payload)))
	var p2 := _user_path(str(runtime._resolve_value(action.data.get("path2", ""), payload)))
	match op:
		"delete":
			DirAccess.remove_absolute(p1)
		"mkdir":
			DirAccess.make_dir_recursive_absolute(p1)
		"copy":
			DirAccess.copy_absolute(p1, p2)
		"move":
			DirAccess.rename_absolute(p1, p2)

func _action_http_request(action: GyroAction, payload: Dictionary) -> void:
	if host == null or not host.is_inside_tree():
		return
	var url := str(runtime._resolve_value(action.data.get("url", ""), payload))
	if url == "":
		return
	var method_name := str(action.data.get("method", "GET")).to_upper()
	var body := str(runtime._resolve_value(action.data.get("body", ""), payload))
	var variable_name := str(action.data.get("variable", ""))
	var request := HTTPRequest.new()
	host.add_child(request)
	var method := HTTPClient.METHOD_GET
	match method_name:
		"POST":
			method = HTTPClient.METHOD_POST
		"PUT":
			method = HTTPClient.METHOD_PUT
		"PATCH":
			method = HTTPClient.METHOD_PATCH
		"DELETE":
			method = HTTPClient.METHOD_DELETE
		"HEAD":
			method = HTTPClient.METHOD_HEAD
	request.timeout = 30.0
	request.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, response_body: PackedByteArray):
		var text := response_body.get_string_from_utf8()
		if variable_name != "":
			var parsed = JSON.parse_string(text)
			runtime.variables[variable_name] = parsed if parsed != null else text
		runtime.emit_event("http_done", {"status": response_code, "body": text})
		request.queue_free()
	)
	request.request(url, ["Content-Type: application/json"], method, body)

func _action_save_value(action: GyroAction, payload: Dictionary) -> void:
	var key := str(runtime._resolve_value(action.data.get("key", ""), payload))
	if key == "":
		return
	var data := _load_save_dict()
	data[key] = runtime._resolve_value(action.data.get("value", null), payload)
	_write_save_dict(data)

func _action_load_value(action: GyroAction, payload: Dictionary) -> void:
	var key := str(runtime._resolve_value(action.data.get("key", ""), payload))
	var variable_name := str(action.data.get("variable", ""))
	if variable_name == "":
		return
	var data := _load_save_dict()
	if data.has(key):
		runtime.variables[variable_name] = data.get(key)
