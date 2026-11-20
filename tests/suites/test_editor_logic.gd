extends "res://tests/framework/test_case.gd"

const Env := preload("res://tests/framework/test_env.gd")

func suite_name() -> String:
	return "editor_logic"

func test_flow_handler_cache_and_sync() -> void:
	var flow := FlowHandler.new()
	var parent := Env.action("If", {"condition": "true", "blocks": [
		{"type": "Print", "data": {"message": "a"}, "disabled": false},
	]})
	var arr := flow.get_array(parent)
	eq(arr.size(), 1, "child parsed")
	check(flow.get_array(parent) == arr, "array cached")
	var child := arr[0] as GyroAction
	child.disabled = true
	child.data["message"] = "b"
	flow.sync(parent)
	var blocks: Array = parent.data.get("blocks", [])
	eq(bool((blocks[0] as Dictionary).get("disabled")), true, "disabled written back")
	eq(str(((blocks[0] as Dictionary).get("data") as Dictionary).get("message")), "b", "data written back")
	flow.clear()
	eq(flow.get_array(parent).size(), 1, "rebuild after clear")

func test_flow_handler_keeps_nested_blocks() -> void:
	var flow := FlowHandler.new()
	var parent := Env.action("Repeat", {"count": 2, "blocks": [
		{"type": "If", "data": {"condition": "true", "blocks": [
			{"type": "Print", "data": {"message": "deep"}, "disabled": false},
		]}, "disabled": false},
	]})
	flow.sync(parent)
	var outer: Array = parent.data.get("blocks", [])
	var inner: Array = ((outer[0] as Dictionary).get("data") as Dictionary).get("blocks", [])
	eq(inner.size(), 1, "nested level preserved")

func test_undo_redo_cycle() -> void:
	var state := {"value": 0}
	var ur := UndoRedoManager.new()
	ur.setup(func(): return {"value": state.value}, func(s): state.value = int(s.value))
	ur.push_undo()
	state.value = 1
	ur.push_undo()
	state.value = 2
	ur.undo()
	eq(state.value, 1, "undo restores previous")
	ur.undo()
	eq(state.value, 0, "second undo")
	ur.redo()
	eq(state.value, 1, "redo")

func test_undo_stack_trimmed() -> void:
	var state := {"value": 0}
	var ur := UndoRedoManager.new()
	ur.setup(func(): return {"value": state.value}, func(s): state.value = int(s.value))
	for i in 80:
		state.value = i
		ur.push_undo()
	check(ur.undo_stack.size() <= UndoRedoManager.MAX_STEPS, "stack capped")

func test_pending_snapshot_skipped_when_unchanged() -> void:
	var state := {"value": 5}
	var ur := UndoRedoManager.new()
	ur.setup(func(): return {"value": state.value}, func(s): state.value = int(s.value))
	ur.mark_field_focus()
	ur.commit_pending()
	eq(ur.undo_stack.size(), 0, "no-op edit does not create undo step")
	state.value = 6
	ur.mark_field_focus()
	state.value = 7
	ur.commit_pending()
	eq(ur.undo_stack.size(), 1, "real edit creates undo step")

func test_default_data_covers_schema() -> void:
	for type in GyroBlocks.ACTION_SCHEMAS.keys():
		var data := GyroBlocks.default_data(str(type))
		for field in (GyroBlocks.ACTION_SCHEMAS[type] as Array):
			check(data.has(str((field as Array)[0])), "%s default has %s" % [type, str((field as Array)[0])])

func test_normalize_action_data_recursive() -> void:
	var data := {"blocks": [{"type": "SetTableValue", "data": {"table": "inv"}}]}
	GyroBlocks.normalize_action_data("If", data)
	var inner := ((data.get("blocks") as Array)[0] as Dictionary).get("data") as Dictionary
	eq(str(inner.get("name")), "inv", "nested legacy key normalized")

func test_custom_registry_usage_and_purge() -> void:
	var project := Env.project()
	var b := GyroCustomBlock.new()
	b.block_id = "blast"
	b.block_name = "Blast"
	project.custom_blocks.append(b)
	var script := GyroScript.new()
	script.blueprint = GyroEventBlueprint.new()
	var rule := Env.rule("ready", [
		Env.action("custom:blast", {}),
		Env.action("If", {"condition": "true", "blocks": [
			{"type": "custom:blast", "data": {}, "disabled": false},
		]}),
	])
	script.blueprint.rules.append(rule)
	project.scripts.append(script)
	eq(GyroCustomRegistry.count_usages(project, "blast"), 1, "usage counted per rule")
	GyroCustomRegistry.remove_block_everywhere(project, "blast")
	eq(project.custom_blocks.size(), 0, "block removed")
	eq(rule.actions.size(), 1, "top level usage purged")
	var nested: Array = rule.actions[0].data.get("blocks", [])
	eq(nested.size(), 0, "nested usage purged")

func test_sanitize_and_bad_names() -> void:
	eq(GyroUI.sanitize_name("  a/b:c  "), "a_b_c", "forbidden chars replaced")
	eq(GyroUI.sanitize_name("a__b"), "a_b", "double underscore collapsed")
	eq(GyroUI.sanitize_name("_name_"), "name", "underscores trimmed")
	check(GyroUI.is_bad_name(""), "empty is bad")
	check(GyroUI.is_bad_name("..."), "dots only is bad")
	check(not GyroUI.is_bad_name("My.Game"), "dots inside allowed")

func test_lang_lookup() -> void:
	GyroLang.set_language("ru")
	eq(GyroLang.t("ok"), "ОК", "russian lookup")
	GyroLang.set_language("en")
	eq(GyroLang.t("ok"), "OK", "english lookup")
	eq(GyroLang.t("no_such_key_here"), "no_such_key_here", "missing key returns key")
	GyroLang.set_language("ru")
