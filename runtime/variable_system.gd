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
			var t = runtime.variables.get(str(action.data.get("name", "")), null)
			if t is Dictionary:
				(t as Dictionary)[str(runtime._resolve_value(action.data.get("key", ""), payload))] = runtime._resolve_value(action.data.get("value", null), payload)
		"GetTableValue":
			var variable_name := str(action.data.get("variable", ""))
			if variable_name == "":
				return
			var t = runtime.variables.get(str(action.data.get("name", "")), null)
			if t is Dictionary:
				runtime.variables[variable_name] = (t as Dictionary).get(str(runtime._resolve_value(action.data.get("key", ""), payload)), null)
		"InsertArrayValue":
			var t = runtime.variables.get(str(action.data.get("name", "")), null)
			if t is Dictionary:
				var idx := int(runtime._to_float(runtime._resolve_value(action.data.get("index", 0), payload)))
				(t as Dictionary)[idx] = runtime._resolve_value(action.data.get("value", null), payload)
		"RemoveArrayValue":
			var t = runtime.variables.get(str(action.data.get("name", "")), null)
			if t is Dictionary:
				(t as Dictionary).erase(int(runtime._to_float(runtime._resolve_value(action.data.get("index", 0), payload))))
		"OverwriteTable":
			var name := str(action.data.get("name", ""))
			if name == "":
				return
			var parsed = JSON.parse_string(str(runtime._resolve_value(action.data.get("json", "{}"), payload)))
			if parsed is Dictionary:
				runtime.variables[name] = parsed
		"ForEachTable":
			var t = runtime.variables.get(str(action.data.get("name", "")), null)
			if not (t is Dictionary):
				return
			var element_var := str(action.data.get("element", ""))
			var key_var := str(action.data.get("keyvar", ""))
			for k in (t as Dictionary).keys():
				if element_var != "":
					runtime.variables[element_var] = (t as Dictionary)[k]
				if key_var != "":
					runtime.variables[key_var] = k
				runtime.event_system._execute_flow_blocks(action, payload)
		"LoopRange":
			var from := runtime._to_float(runtime._resolve_value(action.data.get("from", 1), payload))
			var to := runtime._to_float(runtime._resolve_value(action.data.get("to", 10), payload))
			var step := runtime._to_float(runtime._resolve_value(action.data.get("step", 1), payload))
			if step == 0.0:
				step = 1.0
			var variable_name := str(action.data.get("variable", ""))
			var v := from
			var guard := 0
			while (step > 0.0 and v <= to) or (step < 0.0 and v >= to):
				if variable_name != "":
					runtime.variables[variable_name] = v
				runtime.event_system._execute_flow_blocks(action, payload)
				v += step
				guard += 1
				if guard > 10000:
					break
