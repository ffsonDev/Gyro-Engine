extends "res://tests/framework/test_case.gd"

const Env := preload("res://tests/framework/test_env.gd")

var sink: Array = []

func suite_name() -> String:
	return "runtime_events"

func teardown() -> void:
	sink.clear()

func _host(bp: GyroEventBlueprint) -> GyroEventHost:
	return Env.make_host(parent, bp, Env.project(), Env.path("proj/events.json"), sink)

func test_ready_event_fires() -> void:
	var bp := Env.blueprint([Env.rule("ready", [Env.action("Print", {"message": "boot"})])])
	_host(bp)
	has(sink, "boot", "ready fired")

func test_emit_depth_restored() -> void:
	var bp := Env.blueprint([Env.rule("ready", [Env.action("Print", {"message": "x"})])])
	var host := _host(bp)
	eq(host.runtime.event_system.emit_depth, 0, "depth back to zero after ready")

func test_recursive_events_are_guarded() -> void:
	var a := Env.rule("custom", [Env.action("EmitEvent", {"event": "b"})], "a")
	var b := Env.rule("custom", [Env.action("EmitEvent", {"event": "a"})], "b")
	var host := _host(Env.blueprint([a, b]))
	host.emit_event("a", {})
	eq(host.runtime.event_system.emit_depth, 0, "depth restored after recursion")
	var guarded := false
	for line in sink:
		if str(line).contains("Event depth limit"):
			guarded = true
	check(guarded, "depth limit reported instead of hang")

func test_tap_deduplicated_per_frame() -> void:
	var bp := Env.blueprint([Env.rule("tap", [Env.action("Print", {"message": "tap"})])])
	var host := _host(bp)
	sink.clear()
	host.emit_event("tap", {"x": 1, "y": 1})
	host.emit_event("tap", {"x": 2, "y": 2})
	var count := 0
	for line in sink:
		if str(line) == "tap":
			count += 1
	eq(count, 1, "second tap in same frame ignored")

func test_timer_filter() -> void:
	var r := Env.rule("timer", [Env.action("Print", {"message": "fired"})])
	r.event_filter = "tick"
	var host := _host(Env.blueprint([r]))
	sink.clear()
	host.emit_event("timer", {"name": "other"})
	eq(sink.size(), 0, "wrong timer name filtered")
	host.emit_event("timer", {"name": "tick"})
	has(sink, "fired", "matching timer fires")

func test_collide_filter_matches_both_sides() -> void:
	var r := Env.rule("collide", [Env.action("Print", {"message": "hit"})])
	r.event_filter = "player"
	var host := _host(Env.blueprint([r]))
	sink.clear()
	host.emit_event("collide", {"a": "enemy", "b": "player"})
	has(sink, "hit", "filter matches payload b")

func test_variable_conditions() -> void:
	var gt := Env.rule("custom", [Env.action("Print", {"message": "gt"})], "check")
	gt.conditions.append(Env.condition("VariableGreaterThan", {"name": "hp", "value": 10}))
	var eqr := Env.rule("custom", [Env.action("Print", {"message": "eq"})], "check")
	eqr.conditions.append(Env.condition("VariableEquals", {"name": "hp", "value": 50}))
	var host := _host(Env.blueprint([gt, eqr], {"hp": 50}))
	sink.clear()
	host.emit_event("check", {})
	has(sink, "gt", "greater than true")
	has(sink, "eq", "equals true")

func test_payload_conditions() -> void:
	var r := Env.rule("custom", [Env.action("Print", {"message": "payload"})], "dmg")
	r.conditions.append(Env.condition("PayloadEquals", {"key": "source", "value": "enemy"}))
	r.conditions.append(Env.condition("PayloadGreaterThan", {"key": "amount", "value": 5}))
	var host := _host(Env.blueprint([r]))
	sink.clear()
	host.emit_event("dmg", {"source": "enemy", "amount": 10})
	has(sink, "payload", "payload conditions pass")
	sink.clear()
	host.emit_event("dmg", {"source": "enemy", "amount": 1})
	eq(sink.size(), 0, "payload greater blocks")

func test_disabled_condition_is_ignored() -> void:
	var r := Env.rule("custom", [Env.action("Print", {"message": "run"})], "go")
	var c := Env.condition("VariableEquals", {"name": "hp", "value": 999})
	c.disabled = true
	r.conditions.append(c)
	var host := _host(Env.blueprint([r], {"hp": 1}))
	sink.clear()
	host.emit_event("go", {})
	has(sink, "run", "disabled condition skipped")

func test_disabled_rule_is_ignored() -> void:
	var r := Env.rule("custom", [Env.action("Print", {"message": "no"})], "go")
	r.disabled = true
	var host := _host(Env.blueprint([r]))
	sink.clear()
	host.emit_event("go", {})
	eq(sink.size(), 0, "disabled rule not indexed")

func test_unknown_condition_blocks_rule() -> void:
	var r := Env.rule("custom", [Env.action("Print", {"message": "no"})], "go")
	r.conditions.append(Env.condition("NoSuchCondition", {}))
	var host := _host(Env.blueprint([r]))
	sink.clear()
	host.emit_event("go", {})
	eq(sink.size(), 0, "unknown condition returns false")

func test_values_equal_cross_type() -> void:
	var host := _host(Env.blueprint([]))
	var es := host.runtime.event_system
	check(es._values_equal(1, 1.0), "int vs float")
	check(es._values_equal("5", 5), "string vs number")
	check(es._values_equal(null, null), "null vs null")
	check(not es._values_equal(null, 0), "null vs zero")

func test_var_changed_event() -> void:
	var setter := Env.rule("custom", [Env.action("SetVariable", {"name": "hp", "value": 7})], "set")
	var watcher := Env.rule("var_changed", [Env.action("Print", {"message": "changed"})])
	var host := _host(Env.blueprint([setter, watcher], {"hp": 0}))
	sink.clear()
	host.emit_event("set", {})
	eq(host.runtime.variables.get("hp"), 7, "variable written")
	has(sink, "changed", "var_changed emitted")

func test_condition_variable_reference() -> void:
	skip("P1: conditions still compare raw value instead of resolving $var refs")
