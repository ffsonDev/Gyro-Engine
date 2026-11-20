class_name VariableSystem
extends GyroSystem

func execute(action: GyroAction, payload: Dictionary) -> void:
	match action.type:
		"SetVariable":
			var variable_name := str(action.data.get("name", ""))
			var old_value = runtime.variables.get(variable_name, null)
			var value = runtime._resolve_value(action.data.get("value", null), payload)
			runtime.variables[variable_name] = value
			runtime.emit_event("var_changed", {"name": variable_name, "old": old_value, "new": value})
		"AddToVariable":
			var variable_name := str(action.data.get("name", ""))
			var old_value = runtime.variables.get(variable_name, null)
			var amount := runtime._to_float(runtime._resolve_value(action.data.get("amount", 0.0), payload))
			runtime.variables[variable_name] = runtime._to_float(runtime.variables.get(variable_name, 0.0)) + amount
			runtime.emit_event("var_changed", {"name": variable_name, "old": old_value, "new": runtime.variables[variable_name]})
		"SetTableValue":
			var t_name := str(action.data.get("name", ""))
			if t_name == "":
				return
			if not runtime.tables.has(t_name):
				runtime.tables[t_name] = {}
			(runtime.tables[t_name] as Dictionary)[str(runtime._resolve_value(action.data.get("key", ""), payload))] = runtime._resolve_value(action.data.get("value", null), payload)
		"GetTableValue":
			var variable_name := str(action.data.get("variable", ""))
			if variable_name == "":
				return
			var t_name := str(action.data.get("name", ""))
			if runtime.tables.has(t_name):
				runtime.variables[variable_name] = (runtime.tables[t_name] as Dictionary).get(str(runtime._resolve_value(action.data.get("key", ""), payload)), null)
		"InsertArrayValue":
			var t_name := str(action.data.get("name", ""))
			if t_name == "":
				return
			if not runtime.tables.has(t_name):
				runtime.tables[t_name] = {}
			var idx := int(runtime._to_float(runtime._resolve_value(action.data.get("index", 0), payload)))
			(runtime.tables[t_name] as Dictionary)[idx] = runtime._resolve_value(action.data.get("value", null), payload)
		"RemoveArrayValue":
			var t_name := str(action.data.get("name", ""))
			if runtime.tables.has(t_name):
				(runtime.tables[t_name] as Dictionary).erase(int(runtime._to_float(runtime._resolve_value(action.data.get("index", 0), payload))))
		"OverwriteTable":
			var t_name := str(action.data.get("name", ""))
			if t_name == "":
				return
			var parsed = JSON.parse_string(str(runtime._resolve_value(action.data.get("json", "{}"), payload)))
			if parsed is Dictionary:
				runtime.tables[t_name] = parsed
		"ForEachTable":
			_run_for_each(action, payload)
		"LoopRange":
			_run_loop_range(action, payload)

func _run_for_each(action: GyroAction, payload: Dictionary) -> void:
	var t_name := str(action.data.get("name", ""))
	if not runtime.tables.has(t_name):
		return
	var snapshot: Dictionary = (runtime.tables[t_name] as Dictionary).duplicate(true)
	var element_var := str(action.data.get("element", ""))
	var key_var := str(action.data.get("keyvar", ""))
	var prev_e = runtime.variables.get(element_var, null)
	var prev_k = runtime.variables.get(key_var, null)
	for k in snapshot.keys():
		if runtime._shutdown:
			break
		if element_var != "":
			runtime.variables[element_var] = snapshot[k]
		if key_var != "":
			runtime.variables[key_var] = k
		runtime.event_system._execute_flow_blocks(action, payload)
	if element_var != "":
		runtime.variables[element_var] = prev_e
	if key_var != "":
		runtime.variables[key_var] = prev_k

func _run_loop_range(action: GyroAction, payload: Dictionary) -> void:
	var from := runtime._to_float(runtime._resolve_value(action.data.get("from", 1), payload))
	var to := runtime._to_float(runtime._resolve_value(action.data.get("to", 10), payload))
	var step_val := runtime._to_float(runtime._resolve_value(action.data.get("step", 1), payload))
	if step_val == 0.0:
		step_val = 1.0
	var variable_name := str(action.data.get("variable", ""))
	var prev = runtime.variables.get(variable_name, null)
	var v := from
	var guard := 0
	while (step_val > 0.0 and v <= to) or (step_val < 0.0 and v >= to):
		if runtime._shutdown:
			break
		if variable_name != "":
			runtime.variables[variable_name] = v
		runtime.event_system._execute_flow_blocks(action, payload)
		v += step_val
		guard += 1
		if guard >= 100000:
			runtime._debug("LoopRange: iteration limit reached")
			break
	if variable_name != "":
		runtime.variables[variable_name] = prev
