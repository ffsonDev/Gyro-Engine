extends "res://tests/framework/test_case.gd"

const Env := preload("res://tests/framework/test_env.gd")

func suite_name() -> String:
	return "functions"

func _fn(fname: String, params: Array, expr: String) -> GyroCustomFunction:
	var f := GyroCustomFunction.new()
	f.func_name = fname
	f.params = params
	f.expression = expr
	return f

func test_validation_rules() -> void:
	eq(GyroFunctions.validate("damage", ["a"], "$param.a * 2"), "", "valid function")
	eq(GyroFunctions.validate("2bad", [], "1"), "function_bad_name", "leading digit")
	eq(GyroFunctions.validate("имя", [], "1"), "function_bad_name", "non latin")
	eq(GyroFunctions.validate("min", [], "1"), "function_reserved", "reserved name")
	eq(GyroFunctions.validate("f", ["a", "a"], "1"), "function_bad_params", "duplicate param")
	eq(GyroFunctions.validate("f", ["1a"], "1"), "function_bad_params", "bad param name")
	eq(GyroFunctions.validate("f", [], ""), "function_bad_expr", "empty body")
	eq(GyroFunctions.validate("f", [], "1 +"), "function_bad_expr", "broken body")
	eq(GyroFunctions.validate("f", [], "1+".repeat(600) + "1"), "function_bad_expr", "overlong body")

func test_duplicate_name_rejected() -> void:
	GyroFunctions.add(_fn("dup", [], "1"))
	eq(GyroFunctions.validate("dup", [], "2"), "function_exists", "duplicate rejected")
	eq(GyroFunctions.unique_name("dup"), "dup_2", "unique name suggested")

func test_save_and_reload_library() -> void:
	GyroFunctions.add(_fn("triple", ["x"], "$param.x * 3"))
	GyroFunctions.save()
	GyroFunctions._loaded = false
	GyroFunctions._items = []
	var found := GyroFunctions.find("triple")
	not_null(found, "function reloaded from disk")
	eq(found.expression, "$param.x * 3", "body persisted")

func test_resolve_with_params() -> void:
	GyroFunctions.install()
	GyroFunctions.add(_fn("triple", ["x"], "$param.x * 3"))
	var out: Array = []
	check(GyroExpression.try_eval("triple(4)", {}, {}, Callable(), out), "call resolved")
	eq(out[0], 12, "computed value")

func test_recursive_function_is_guarded() -> void:
	GyroFunctions.install()
	GyroFunctions.add(_fn("loop", ["x"], "loop($param.x)"))
	var out: Array = []
	check(not GyroExpression.try_eval("loop(1)", {}, {}, Callable(), out), "recursion returns error, not hang")
	eq(GyroFunctions._depth, 0, "depth restored")
	check(GyroFunctions._active.is_empty(), "active set cleared")

func test_export_import_round_trip() -> void:
	var f := _fn("quad", ["x"], "$param.x * 4")
	var path := Env.path("fn/quad.gyrofunc")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	check(GyroFunctions.export_function(f, path), "exported")
	var result := GyroFunctions.import_function(path)
	check(bool(result.get("ok", false)), "imported")
	eq(str(result.get("name")), "quad", "name kept")
	not_null(GyroFunctions.find("quad"), "present in library")

func test_import_duplicate_renamed() -> void:
	GyroFunctions.add(_fn("quad", ["x"], "$param.x * 4"))
	var path := Env.path("fn/quad2.gyrofunc")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	GyroFunctions.export_function(_fn("quad", ["x"], "$param.x * 5"), path)
	var result := GyroFunctions.import_function(path)
	check(bool(result.get("ok", false)), "import ok")
	eq(str(result.get("name")), "quad_2", "renamed on conflict")

func test_import_rejects_corrupt() -> void:
	var bad := Env.path("fn/bad.gyrofunc")
	Env.write_text(bad, "NOPE")
	check(not bool(GyroFunctions.import_function(bad).get("ok", false)), "bad magic")
	var truncated := Env.path("fn/trunc.gyrofunc")
	var f := FileAccess.open(truncated, FileAccess.WRITE)
	f.store_string("GYROFN1")
	f.store_64(10)
	f.store_64(999999)
	f.store_8(0)
	f.close()
	check(not bool(GyroFunctions.import_function(truncated).get("ok", false)), "truncated")
