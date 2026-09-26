class_name EventSystem
extends GyroSystem

var _rules_by_event := {}
var emit_depth := 0
var max_emit_depth := 32
var _logger := GyroLogger.get_instance()

func setup() -> void:
	_rebuild_index()

func _log(msg: String) -> void:
	_logger.log_info(msg)
	if OS.is_debug_build():
		print(msg)

func _rebuild_index() -> void:
	_rules_by_event.clear()
	if runtime.blueprint == null:
		return
	for rule_value in runtime.blueprint.rules:
		var rule := rule_value as GyroEventRule
		if rule == null or rule.disabled:
			continue
		var name := rule.fire_name()
		if not _rules_by_event.has(name):
			_rules_by_event[name] = []
		_rules_by_event[name].append(rule)

func has_event(event_name: String) -> bool:
	return _rules_by_event.has(event_name)

func emit_event(event_name: String, payload: Dictionary) -> void:
	if runtime.blueprint == null:
		return
	if emit_depth >= max_emit_depth:
		return
	emit_depth += 1
	var list: Array = _rules_by_event.get(event_name, [])
	for rule_value in list:
		var rule := rule_value as GyroEventRule
		if rule == null:
			continue
		if not _filter_matches(rule, event_name, payload):
			continue
		if _check_conditions(rule.conditions, payload):
			_execute_actions(rule.actions, payload)
	emit_depth -= 1

func _filter_matches(rule: GyroEventRule, event_name: String, payload: Dictionary) -> bool:
	var f := str(rule.event_filter).strip_edges()
	if f == "":
		return true
	match event_name:
		"timer", "var_changed", "widget_changed":
			return str(payload.get("name", "")) == f
		"obj_touch_begin", "obj_touch_end":
			return str(payload.get("node", "")) == f
		"collide", "collide_end":
			return str(payload.get("a", "")) == f or str(payload.get("b", "")) == f
	return true

func _check_conditions(conditions: Array, payload: Dictionary) -> bool:
	for condition_value in conditions:
		var condition := condition_value as GyroCondition
		if condition == null or condition.disabled:
			continue
		if not _check_condition(condition, payload):
			return false
	return true

func _check_condition(condition: GyroCondition, payload: Dictionary) -> bool:
	match condition.type:
		"Always":
			return true
		"VariableEquals":
			var variable_name := str(condition.data.get("name", ""))
			var expected = condition.data.get("value", null)
			return _values_equal(runtime.variables.get(variable_name, null), expected)
		"VariableGreaterThan":
			var variable_name := str(condition.data.get("name", ""))
			var expected := runtime._to_float(condition.data.get("value", 0.0))
			return runtime._to_float(runtime.variables.get(variable_name, 0.0)) > expected
		"PayloadEquals":
			var key := str(condition.data.get("key", ""))
			var expected = condition.data.get("value", null)
			return _values_equal(payload.get(key, null), expected)
		"PayloadGreaterThan":
			var key := str(condition.data.get("key", ""))
			var expected := runtime._to_float(condition.data.get("value", 0.0))
			return runtime._to_float(payload.get(key, 0.0)) > expected
	return false

func _values_equal(a: Variant, b: Variant) -> bool:
	if a == null and b == null:
		return true
	if a == null or b == null:
		return false
	if typeof(a) == typeof(b):
		return a == b
	if a is String or b is String:
		return str(a) == str(b)
	return runtime._to_float(a) == runtime._to_float(b)

func _execute_actions(actions: Array, payload: Dictionary, start_index: int = 0) -> void:
	for i in range(start_index, actions.size()):
		var action := actions[i] as GyroAction
		if action == null or action.disabled:
			continue
		if action.type == "Wait":
			var seconds := runtime._to_float(runtime._resolve_value(action.data.get("wait", 1.0), payload))
			if host != null and host.is_inside_tree():
				var rest := actions
				var pl := payload
				var next := i + 1
				host.get_tree().create_timer(maxf(0.01, seconds)).timeout.connect(func(): _execute_actions(rest, pl, next))
			return
		runtime.execute_action(action, payload)

func _execute_flow_blocks(action: GyroAction, payload: Dictionary) -> void:
	var blocks = action.data.get("blocks", [])
	if not (blocks is Array):
		return
	for b in (blocks as Array):
		var bd := b as Dictionary
		if bd.is_empty():
			continue
		var child := GyroAction.new()
		child.type = str(bd.get("type", ""))
		child.data = (bd.get("data", {}) as Dictionary).duplicate(true)
		if child.disabled:
			continue
		runtime.execute_action(child, payload)
