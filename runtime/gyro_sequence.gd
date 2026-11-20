class_name GyroSequence
extends RefCounted

var runtime: GyroEventRuntime
var actions: Array = []
var payload: Dictionary = {}
var params: Dictionary = {}
var index := 0
var cancelled := false

static func to_actions(blocks: Variant) -> Array:
	var out: Array = []
	if not (blocks is Array):
		return out
	for bv in (blocks as Array):
		if bv is GyroAction:
			out.append(bv)
		elif bv is Dictionary:
			var bd: Dictionary = bv
			var a := GyroAction.new()
			a.type = str(bd.get("type", ""))
			var d = bd.get("data", {})
			a.data = (d as Dictionary).duplicate(true) if d is Dictionary else {}
			a.disabled = bool(bd.get("disabled", false))
			out.append(a)
	return out

func run() -> void:
	await _walk()
	if runtime != null:
		runtime._release_sequence(self)

func cancel() -> void:
	cancelled = true

func _dead() -> bool:
	return cancelled or runtime == null or runtime._shutdown

func _push() -> void:
	if not params.is_empty():
		runtime._param_stack.append(params)

func _pop() -> void:
	if not params.is_empty():
		runtime._param_stack.pop_back()

func _resolve(value: Variant) -> Variant:
	_push()
	var r = runtime._resolve_value(value, payload)
	_pop()
	return r

func _walk() -> void:
	while index < actions.size():
		if _dead():
			return
		var a := actions[index] as GyroAction
		index += 1
		if a == null or not is_instance_valid(a) or a.disabled:
			continue
		if runtime._is_blocking_action(a):
			await _run_blocking(a)
		else:
			_push()
			runtime.execute_action(a, payload)
			_pop()

func _run_blocking(a: GyroAction) -> void:
	match a.type:
		"Wait":
			await runtime.wait_seconds(runtime._to_float(_resolve(a.data.get("wait", 1.0))))
		"WaitUntil":
			await _wait_until(a)
		"If":
			if runtime.eval_condition(str(_resolve(a.data.get("condition", "true"))), payload, params):
				await _run_body(to_actions(a.data.get("blocks", [])))
		"Repeat":
			var body := to_actions(a.data.get("blocks", []))
			var count := clampi(int(runtime._to_float(_resolve(a.data.get("count", 1)))), 0, 1000)
			for i in count:
				if _dead():
					return
				await _run_body(body)
		"ForEachTable":
			await _for_each(a)
		"LoopRange":
			await _loop_range(a)
		_:
			if str(a.type).begins_with("custom:"):
				await _run_custom(a)
			else:
				_push()
				runtime.execute_action(a, payload)
				_pop()

func _run_body(body: Array) -> void:
	if body.is_empty():
		return
	if not runtime._is_blocking_list(body):
		_push()
		for av in body:
			var a := av as GyroAction
			if a != null and is_instance_valid(a) and not a.disabled:
				runtime.execute_action(a, payload)
		_pop()
		return
	var child: Variant = runtime.spawn_sequence(body, payload, params)
	await child.run()

func _wait_until(a: GyroAction) -> void:
	var cond := str(_resolve(a.data.get("condition", "true")))
	var timeout := runtime._to_float(_resolve(a.data.get("timeout", 0.0)))
	var elapsed := 0.0
	while not _dead():
		if runtime.eval_condition(cond, payload, params):
			return
		if timeout > 0.0 and elapsed >= timeout:
			return
		if not runtime.can_await():
			return
		elapsed += await runtime.next_frame()

func _for_each(a: GyroAction) -> void:
	var t_name := str(_resolve(a.data.get("name", "")))
	if not runtime.tables.has(t_name):
		return
	var snapshot: Dictionary = (runtime.tables[t_name] as Dictionary).duplicate(true)
	var element_var := str(a.data.get("element", ""))
	var key_var := str(a.data.get("keyvar", ""))
	var prev_e = runtime.variables.get(element_var, null)
	var prev_k = runtime.variables.get(key_var, null)
	var body := to_actions(a.data.get("blocks", []))
	var i := 0
	for k in snapshot.keys():
		if _dead():
			break
		if element_var != "":
			runtime.variables[element_var] = snapshot[k]
		if key_var != "":
			runtime.variables[key_var] = k
		await _run_body(body)
		i += 1
		if i % 100 == 0:
			if not runtime.can_await():
				break
			await runtime.next_frame()
	if element_var != "":
		runtime.variables[element_var] = prev_e
	if key_var != "":
		runtime.variables[key_var] = prev_k

func _loop_range(a: GyroAction) -> void:
	var from := runtime._to_float(_resolve(a.data.get("from", 1)))
	var to := runtime._to_float(_resolve(a.data.get("to", 10)))
	var step_val := runtime._to_float(_resolve(a.data.get("step", 1)))
	if step_val == 0.0:
		step_val = 1.0
	var variable_name := str(a.data.get("variable", ""))
	var prev = runtime.variables.get(variable_name, null)
	var body := to_actions(a.data.get("blocks", []))
	var v := from
	var guard := 0
	while (step_val > 0.0 and v <= to) or (step_val < 0.0 and v >= to):
		if _dead():
			break
		if variable_name != "":
			runtime.variables[variable_name] = v
		await _run_body(body)
		v += step_val
		guard += 1
		if guard >= 100000:
			break
		if guard % 100 == 0:
			if not runtime.can_await():
				break
			await runtime.next_frame()
	if variable_name != "":
		runtime.variables[variable_name] = prev

func _run_custom(a: GyroAction) -> void:
	var id := str(a.type).substr(7)
	var def := GyroCustomRegistry.find_block(runtime._get_project(), id)
	if def == null or runtime._custom_depth >= 8:
		return
	var p := {}
	_push()
	for fv in def.fields:
		var f: Dictionary = fv
		var key := str(f.get("key", ""))
		if key != "":
			p[key] = runtime._resolve_value(a.data.get(key, f.get("default", null)), payload)
	_pop()
	runtime._custom_depth += 1
	var child: Variant = runtime.spawn_sequence(def.body, payload, p)
	await child.run()
	runtime._custom_depth -= 1
