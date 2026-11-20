extends "res://tests/framework/test_case.gd"

func suite_name() -> String:
	return "expression"

func _eval(text: String, vars := {}, payload := {}, params := {}) -> Variant:
	var out: Array = []
	if not GyroExpression.try_eval(text, vars, payload, Callable(), out, params):
		return null
	return out[0]

func _num(text: String, vars := {}, payload := {}, params := {}) -> float:
	var v = _eval(text, vars, payload, params)
	return float(v) if v != null else NAN

func _ok(text: String, vars := {}, payload := {}, params := {}) -> bool:
	var out: Array = []
	return GyroExpression.try_eval(text, vars, payload, Callable(), out, params)

func test_precedence() -> void:
	eq(_eval("2 + 3 * 4"), 14, "mul before add")
	eq(_eval("(2 + 3) * 4"), 20, "parentheses")
	eq(_eval("10 - 2 - 3"), 5, "left assoc minus")
	eq(_eval("100 / 10 / 2"), 5, "left assoc div")
	eq(_eval("7 % 4"), 3, "modulo")

func test_unary() -> void:
	eq(_eval("-5 + 2"), -3, "unary minus")
	eq(_eval("not false"), true, "not word")
	eq(_eval("!0"), true, "bang")
	eq(_eval("--3"), 3, "double minus")

func test_division_by_zero_is_safe() -> void:
	eq(_eval("1 / 0"), 0, "div zero")
	eq(_eval("5 % 0"), 0, "mod zero")

func test_numeric_comparison() -> void:
	eq(_eval("10 > 9"), true, "gt")
	eq(_eval("9 >= 9"), true, "gte")
	eq(_eval("2 != 3"), true, "neq")
	eq(_eval("2 == 2.0"), true, "int float equality")

func test_string_comparison_is_lexicographic() -> void:
	eq(_eval('"10" < "9"'), true, "strings compare as text")
	eq(_eval('"abc" == "abc"'), true, "string equality")

func test_logic_operators() -> void:
	eq(_eval("true && false"), false, "and symbol")
	eq(_eval("true and true"), true, "and word")
	eq(_eval("false || true"), true, "or symbol")
	eq(_eval("false or false"), false, "or word")

func test_references() -> void:
	eq(_eval("$var.hp + 10", {"hp": 5}), 15, "var ref")
	eq(_eval("$payload.x * 2", {}, {"x": 4}), 8, "payload ref")
	eq(_eval("$param.k - 1", {}, {}, {"k": 9}), 8, "param ref")
	eq(_eval("$var.nope + 1"), 1, "missing var defaults to zero")

func test_string_concat() -> void:
	eq(_eval('"hp: " + 5'), "hp: 5", "concat number")
	eq(_eval('"a" + "b"'), "ab", "concat strings")

func test_integer_normalization() -> void:
	check(_eval("4 / 2") is int, "whole float becomes int")
	check(_eval("1 / 2") is float, "fraction stays float")

func test_builtin_functions() -> void:
	eq(_eval("min(3, 7)"), 3, "min")
	eq(_eval("max(3, 7)"), 7, "max")
	eq(_eval("abs(-4)"), 4, "abs")
	eq(_eval("round(2.6)"), 3, "round")
	eq(_eval("floor(2.9)"), 2, "floor")
	eq(_eval("ceil(2.1)"), 3, "ceil")
	eq(_eval("clamp(15, 0, 10)"), 10, "clamp")
	eq(_eval("len(\"hello\")"), 5, "len")
	eq(_eval("num(\"12.5\")"), 12.5, "num")
	eq(_eval("text(3)"), "3", "text")
	eq(_eval("sqrt(9)"), 3, "sqrt")
	eq(_eval("pow(2, 5)"), 32, "pow")
	eq(_eval("sign(-3)"), -1, "sign")
	eq(_eval("lerp(0, 10, 0.5)"), 5, "lerp")
	eq(_eval("upper(\"ab\")"), "AB", "upper")
	eq(_eval("lower(\"AB\")"), "ab", "lower")
	eq(_eval("contains(\"abc\", \"b\")"), true, "contains")
	eq(_eval("substr(\"abcdef\", 1, 3)"), "bcd", "substr")
	eq(_eval("text_round(3.14159, 2)"), "3.14", "text_round")

func test_trigonometry_uses_degrees() -> void:
	approx(_num("sin(90)"), 1.0, "sin 90")
	approx(_num("cos(0)"), 1.0, "cos 0")
	approx(_num("atan2(1, 0)"), 90.0, "atan2 degrees")

func test_map_degenerate_range() -> void:
	eq(_eval("map(5, 2, 2, 10, 20)"), 10, "equal input range returns low output")
	eq(_eval("map(5, 0, 10, 0, 100)"), 50, "linear map")

func test_unknown_function_fails() -> void:
	check(not _ok("definitely_missing(1)"), "unknown call is an error")

func test_custom_function_hook() -> void:
	GyroExpression.custom_fn = func(fname: String, args: Array) -> Variant:
		return 42.0 if fname == "answer" else null
	eq(_eval("answer()"), 42, "custom hook resolved")
	check(not _ok("other()"), "hook returning null is an error")

func test_syntax_errors() -> void:
	for bad in ["", "   ", "1 +", "(1", "1)", "min(1,)", "$var.", "$foo.x", "abc", "1 2", "\"open"]:
		check(not _ok(str(bad)), "must not parse: [%s]" % str(bad))

func test_depth_limit() -> void:
	var deep := "(".repeat(80) + "1" + ")".repeat(80)
	check(not _ok(deep), "deep nesting rejected")

func test_source_length_limit() -> void:
	var long_expr := "1+".repeat(2100) + "1"
	check(not _ok(long_expr), "overlong source rejected")

func test_is_valid_syntax() -> void:
	check(GyroExpression.is_valid_syntax("1 + 1"), "valid syntax")
	check(not GyroExpression.is_valid_syntax("1 +"), "invalid syntax")
	check(not GyroExpression.is_valid_syntax(""), "empty syntax")

func test_ast_cache_does_not_freeze_values() -> void:
	eq(_eval("$var.a + 1", {"a": 1}), 2, "first eval")
	eq(_eval("$var.a + 1", {"a": 10}), 11, "cached ast re-evaluated")

func test_fail_cache_is_per_expression() -> void:
	check(not _ok("bad("), "bad expression cached")
	eq(_eval("1 + 1"), 2, "other expression still works")
