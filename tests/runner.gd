extends Node

const Env := preload("res://tests/framework/test_env.gd")
const SUITES_DIR := "res://tests/suites"

var _passed := 0
var _failed := 0
var _skipped := 0
var _checks := 0
var _failures: Array = []
var _filters: Array = []
var _started_ms := 0

func _ready() -> void:
	_started_ms = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		var clean := str(arg).strip_edges()
		if clean != "":
			_filters.append(clean.to_lower())
	print("--- Gyro Engine tests ---")
	Env.begin()
	for suite_path in _suite_paths():
		await _run_suite(suite_path)
	Env.finish()
	_report()
	get_tree().quit(1 if _failed > 0 else 0)

func _suite_paths() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(SUITES_DIR)
	if dir == null:
		push_error("tests: suites directory missing")
		return out
	for f in dir.get_files():
		var file_name := str(f)
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			out.append(SUITES_DIR + "/" + file_name)
	out.sort()
	return out

func _matches(suite: String) -> bool:
	if _filters.is_empty():
		return true
	for f in _filters:
		if suite.to_lower().contains(str(f)):
			return true
	return false

func _run_suite(suite_path: String) -> void:
	var script := load(suite_path) as GDScript
	if script == null:
		_failed += 1
		_failures.append("%s: cannot load suite" % suite_path)
		return
	var probe = script.new()
	if probe == null or not probe.has_method("suite_name"):
		_failed += 1
		_failures.append("%s: suite must extend tests/framework/test_case.gd" % suite_path)
		return
	var suite: String = probe.suite_name()
	if not _matches(suite):
		return
	print("--- %s" % suite)
	for method in _test_methods(script):
		await _run_test(script, suite, method)

func _test_methods(script: GDScript) -> PackedStringArray:
	var out := PackedStringArray()
	for entry in script.get_script_method_list():
		var method_name := str(entry.get("name", ""))
		if method_name.begins_with("test_"):
			out.append(method_name)
	out.sort()
	return out

func _run_test(script: GDScript, suite: String, method: String) -> void:
	Env.reset_statics()
	var case = script.new()
	case.parent = self
	var started := Time.get_ticks_msec()
	await case.setup()
	await case.call(method)
	await case.teardown()
	Env.free_hosts()
	await get_tree().process_frame
	var elapsed := Time.get_ticks_msec() - started
	_checks += int(case.checks)
	var label := "%s.%s" % [suite, method]
	if str(case.skipped) != "":
		_skipped += 1
		print("SKIP %s (%s)" % [label, case.skipped])
		return
	if case.failures.is_empty() and int(case.checks) == 0:
		case.failures.append("test made no assertions")
	if case.failures.is_empty():
		_passed += 1
		print("PASS %s (%d checks, %d ms)" % [label, case.checks, elapsed])
		return
	_failed += 1
	print("FAIL %s (%d ms)" % [label, elapsed])
	for message in case.failures:
		print("       %s" % str(message))
		_failures.append("%s: %s" % [label, str(message)])

func _report() -> void:
	var elapsed := (Time.get_ticks_msec() - _started_ms) / 1000.0
	print("--- passed %d | failed %d | skipped %d | checks %d | %.2fs ---" % [_passed, _failed, _skipped, _checks, elapsed])
	if not _failures.is_empty():
		print("failures:")
		for f in _failures:
			print("  %s" % str(f))
