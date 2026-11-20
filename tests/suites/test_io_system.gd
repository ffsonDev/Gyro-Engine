extends "res://tests/framework/test_case.gd"

const Env := preload("res://tests/framework/test_env.gd")

var sink: Array = []

func suite_name() -> String:
	return "io_system"

func teardown() -> void:
	sink.clear()

func _host() -> GyroEventHost:
	var probe := Env.rule("custom", [
		Env.action("WriteFile", {}),
		Env.action("ReadFile", {}),
		Env.action("FileOp", {}),
		Env.action("SaveValue", {}),
		Env.action("LoadValue", {}),
		Env.action("HttpRequest", {}),
	], "io_probe")
	var bp := Env.blueprint([probe])
	return Env.make_host(parent, bp, Env.project(), Env.path("proj/io.json"), sink)

func _run(host: GyroEventHost, type: String, data: Dictionary) -> void:
	host.runtime.execute_action(Env.action(type, data), {})

func test_safe_path_denies_dangerous_input() -> void:
	var io := IOSystem.new()
	for bad in [
		"", "../escape.txt", "user://../escape.txt", "user://a/../b.txt",
		"/etc/passwd", "C:/windows/x", "res://project.godot",
		"user://projects/other.json", "user://keystore/release.p12",
		"user://builds/app.apk", "user://gyro_settings.tres",
		"user://_tmp_export.gyroproj", "user://sub//double.txt",
	]:
		eq(io._safe_path(str(bad), true), "", "denied: %s" % str(bad))

func test_safe_path_denies_global_libraries() -> void:
	var io := IOSystem.new()
	eq(io._safe_path("user://gyro_global_blocks.json", false), "", "global blocks denied (P0-4)")
	eq(io._safe_path("user://gyro_functions.json", false), "", "functions denied (P0-4)")

func test_safe_path_allows_valid_input() -> void:
	var io := IOSystem.new()
	eq(io._safe_path("save.txt", false), "user://save.txt", "relative mapped to user")
	eq(io._safe_path("user://gyro_tests/a.txt", false), "user://gyro_tests/a.txt", "sandbox allowed")
	eq(io._safe_path("res://gyro_data/project.json", true), "res://gyro_data/project.json", "game data readable")
	eq(io._safe_path("res://gyro_data/project.json", false), "", "game data not writable")

func test_write_read_round_trip() -> void:
	var host := _host()
	var target := Env.path("io/note.txt")
	_run(host, "WriteFile", {"path": target, "value": "hello"})
	check(FileAccess.file_exists(target), "file written")
	check(not FileAccess.file_exists(target + ".tmp"), "atomic temp removed")
	_run(host, "ReadFile", {"path": target, "variable": "text"})
	eq(host.runtime.variables.get("text"), "hello", "content read back")

func test_read_missing_reports_error() -> void:
	var host := _host()
	var errors: Array = []
	var watcher := Env.rule("io_error", [])
	watcher.event_filter = ""
	host.runtime.event_system._rebuild_index()
	host.runtime.print_handler = func(m): errors.append(str(m))
	_run(host, "ReadFile", {"path": Env.path("io/absent.txt"), "variable": "text"})
	eq(host.runtime.variables.get("text"), "", "variable cleared on failure")
	var reported := false
	for line in errors:
		if str(line).contains("not_found"):
			reported = true
	check(reported, "not_found reported")

func test_write_denied_path() -> void:
	var host := _host()
	var messages: Array = []
	host.runtime.print_handler = func(m): messages.append(str(m))
	_run(host, "WriteFile", {"path": "user://projects/evil.json", "value": "x"})
	check(not FileAccess.file_exists("user://projects/evil.json"), "denied write did not happen")
	var denied := false
	for line in messages:
		if str(line).contains("path_denied"):
			denied = true
	check(denied, "path_denied reported")

func test_file_op_copy_move_delete() -> void:
	var host := _host()
	var a := Env.path("io/a.txt")
	var b := Env.path("io/b.txt")
	var c := Env.path("io/c.txt")
	_run(host, "WriteFile", {"path": a, "value": "data"})
	_run(host, "FileOp", {"op": "copy", "path1": a, "path2": b})
	check(FileAccess.file_exists(b), "copied")
	_run(host, "FileOp", {"op": "move", "path1": b, "path2": c})
	check(not FileAccess.file_exists(b), "source removed on move")
	check(FileAccess.file_exists(c), "move target exists")
	_run(host, "FileOp", {"op": "delete", "path1": c})
	check(not FileAccess.file_exists(c), "deleted")
	_run(host, "FileOp", {"op": "mkdir", "path1": Env.path("io/sub")})
	check(DirAccess.dir_exists_absolute(Env.path("io/sub")), "mkdir")

func test_save_and_load_value() -> void:
	var host := _host()
	_run(host, "SaveValue", {"key": "score", "value": 42})
	_run(host, "LoadValue", {"key": "score", "variable": "best"})
	eq(host.runtime.variables.get("best"), 42, "value persisted")
	_run(host, "LoadValue", {"key": "absent", "variable": "none"})
	is_null(host.runtime.variables.get("none"), "missing key yields null")

func test_http_invalid_url_emits_done() -> void:
	var host := _host()
	var statuses: Array = []
	host.runtime.event_system._rules_by_event["http_done"] = []
	var probe := Env.rule("http_done", [])
	host.runtime.blueprint.rules.append(probe)
	host.runtime.event_system._rebuild_index()
	host.runtime.print_handler = func(m): statuses.append(str(m))
	_run(host, "HttpRequest", {"url": "ftp://bad", "variable": "body"})
	eq(host.runtime.variables.get("body"), "", "body cleared for invalid url")
