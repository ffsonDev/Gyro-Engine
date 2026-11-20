class_name IOSystem
extends GyroSystem

const MAX_HTTP_BODY := 4194304
const RES_PREFIX := "res://gyro_data/"
const USER_DENY := [
	"projects/", "keystore/", "gyro_code_cache/", "builds/",
	"gyro_settings.tres", "gyro_favorites.json",
	"gyro_global_blocks.json", "gyro_functions.json", "gyro_secret.salt",
	"_build_", "_tmp_"
]

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

func _safe_path(raw: String, allow_res: bool) -> String:
	var p := str(raw).replace("\\", "/").strip_edges()
	if p == "":
		return ""
	var body := p
	if p.begins_with("user://"):
		body = p.substr(7)
	elif p.begins_with("res://"):
		body = p.substr(6)
	if body.contains("..") or body.contains("//") or body.contains(":"):
		return ""
	if p.begins_with("res://"):
		if allow_res and p.begins_with(RES_PREFIX):
			return p
		return ""
	if p.begins_with("user://"):
		for denied in USER_DENY:
			if body.begins_with(denied):
				return ""
		return p
	if p.is_absolute_path():
		return ""
	return "user://" + p

func _fail(op: String, path: String, reason: String) -> void:
	runtime._debug("IO " + op + ": " + reason + " (" + path + ")")
	runtime.emit_event("io_error", {"op": op, "path": path, "error": reason})

func _write_text_atomic(path: String, text: String) -> String:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "open_failed_" + str(FileAccess.get_open_error())
	f.store_string(text)
	f.flush()
	var err := f.get_error()
	f.close()
	if err != OK:
		DirAccess.remove_absolute(tmp)
		return "write_failed_" + str(err)
	var rename_err := DirAccess.rename_absolute(tmp, path)
	if rename_err != OK and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		rename_err = DirAccess.rename_absolute(tmp, path)
	if rename_err != OK:
		DirAccess.remove_absolute(tmp)
		return "rename_failed_" + str(rename_err)
	return ""

func _resolve_asset(ref: String) -> String:
	var proj := runtime._get_project()
	if proj == null:
		return ""
	for v in proj.assets:
		var a := v as GyroAsset
		if a != null and (a.id == ref or a.asset_name == ref):
			var resolved := GyroAssetPaths.resolve_asset_path(a.path, runtime._project_path())
			if FileAccess.file_exists(resolved):
				return resolved
	return ""

func _save_file_path() -> String:
	return "user://gyro_save_" + str(runtime._project_path().get_file().get_basename()) + ".json"

func _load_save_dict() -> Dictionary:
	var f := FileAccess.open(_save_file_path(), FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

func _write_save_dict(data: Dictionary) -> void:
	var err := _write_text_atomic(_save_file_path(), JSON.stringify(data))
	if err != "":
		_fail("save_value", _save_file_path(), err)

func _action_read_file(action: GyroAction, payload: Dictionary) -> void:
	var variable_name := str(action.data.get("variable", ""))
	var raw := str(runtime._resolve_value(action.data.get("path", ""), payload))
	if raw == "":
		return
	var resolved := _safe_path(raw, true)
	if resolved == "":
		resolved = _resolve_asset(raw)
	if resolved == "":
		if variable_name != "":
			runtime.variables[variable_name] = ""
		_fail("read", raw, "path_denied")
		return
	if not FileAccess.file_exists(resolved):
		if variable_name != "":
			runtime.variables[variable_name] = ""
		_fail("read", raw, "not_found")
		return
	var f := FileAccess.open(resolved, FileAccess.READ)
	if f == null:
		if variable_name != "":
			runtime.variables[variable_name] = ""
		_fail("read", raw, "open_failed_" + str(FileAccess.get_open_error()))
		return
	var text := f.get_as_text()
	f.close()
	if variable_name != "":
		runtime.variables[variable_name] = text

func _action_write_file(action: GyroAction, payload: Dictionary) -> void:
	var raw := str(runtime._resolve_value(action.data.get("path", ""), payload))
	var path := _safe_path(raw, false)
	if path == "":
		_fail("write", raw, "path_denied")
		return
	var text := str(runtime._resolve_value(action.data.get("value", ""), payload))
	var err := _write_text_atomic(path, text)
	if err != "":
		_fail("write", raw, err)

func _action_file_op(action: GyroAction, payload: Dictionary) -> void:
	var op := str(action.data.get("op", "delete"))
	var raw1 := str(runtime._resolve_value(action.data.get("path1", ""), payload))
	var p1 := _safe_path(raw1, false)
	if p1 == "":
		_fail(op, raw1, "path_denied")
		return
	var err := OK
	match op:
		"delete":
			err = DirAccess.remove_absolute(p1)
		"mkdir":
			err = DirAccess.make_dir_recursive_absolute(p1)
			if err == ERR_ALREADY_EXISTS:
				err = OK
		"copy", "move":
			var raw2 := str(runtime._resolve_value(action.data.get("path2", ""), payload))
			var p2 := _safe_path(raw2, false)
			if p2 == "":
				_fail(op, raw2, "path_denied")
				return
			err = DirAccess.copy_absolute(p1, p2) if op == "copy" else DirAccess.rename_absolute(p1, p2)
		_:
			_fail(op, raw1, "unknown_op")
			return
	if err != OK:
		_fail(op, raw1, "failed_" + str(err))

func _action_http_request(action: GyroAction, payload: Dictionary) -> void:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return
	var url := str(runtime._resolve_value(action.data.get("url", ""), payload)).strip_edges()
	var variable_name := str(action.data.get("variable", ""))
	if url == "" or (not url.begins_with("http://") and not url.begins_with("https://")):
		if variable_name != "":
			runtime.variables[variable_name] = ""
		runtime.emit_event("http_done", {"status": -1, "body": "", "error": "invalid_url"})
		return
	var method := HTTPClient.METHOD_GET
	match str(action.data.get("method", "GET")).to_upper():
		"POST": method = HTTPClient.METHOD_POST
		"PUT": method = HTTPClient.METHOD_PUT
		"PATCH": method = HTTPClient.METHOD_PATCH
		"DELETE": method = HTTPClient.METHOD_DELETE
		"HEAD": method = HTTPClient.METHOD_HEAD
	var body := str(runtime._resolve_value(action.data.get("body", ""), payload))
	var request := HTTPRequest.new()
	request.timeout = 30.0
	request.body_size_limit = MAX_HTTP_BODY
	host.add_child(request)
	var weak_request: Variant = weakref(request)
	request.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, response_body: PackedByteArray):
		var r = weak_request.get_ref()
		if r == null:
			return
		if runtime == null or runtime._shutdown:
			r.queue_free()
			return
		var text := response_body.get_string_from_utf8()
		var failed := result != HTTPRequest.RESULT_SUCCESS
		if variable_name != "":
			var parsed = JSON.parse_string(text)
			runtime.variables[variable_name] = parsed if parsed != null else text
		runtime.emit_event("http_done", {
			"status": -1 if failed else response_code,
			"body": text,
			"error": "network_" + str(result) if failed else ""
		})
		r.queue_free()
	)
	var request_err := request.request(url, ["Content-Type: application/json"], method, body)
	if request_err != OK:
		request.queue_free()
		if variable_name != "":
			runtime.variables[variable_name] = ""
		runtime.emit_event("http_done", {"status": -1, "body": "", "error": "send_" + str(request_err)})

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
	runtime.variables[variable_name] = data.get(key, null)
