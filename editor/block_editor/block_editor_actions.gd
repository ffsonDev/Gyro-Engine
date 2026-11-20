class_name BlockEditorActions
extends RefCounted

var editor: GyroBlockEditor
var state: BlockEditorState
var renderer: BlockRenderer
var drag_drop: DragDropController
var flow_handler: FlowHandler
var vars_dialog: VarsDialog
var undo_redo: UndoRedoManager
var save_mgr: SaveManager

func _init(ed: GyroBlockEditor, st: BlockEditorState, rnd: BlockRenderer, dd: DragDropController, fh: FlowHandler, vd: VarsDialog, ur: UndoRedoManager, sm: SaveManager) -> void:
	editor = ed
	state = st
	renderer = rnd
	drag_drop = dd
	flow_handler = fh
	vars_dialog = vd
	undo_redo = ur
	save_mgr = sm

func duplicate_target(t: Dictionary) -> void:
	if t.is_empty():
		return
	undo_redo.push_undo()
	var kind: String = str(t.get("kind", ""))
	var resource: Variant = t.get("resource", null)
	var rule: GyroEventRule = t.get("rule", null)
	if kind == "rule":
		var index := state.blueprint.rules.find(resource)
		var copy := (resource as GyroEventRule).duplicate(true) as GyroEventRule
		state.blueprint.rules.insert(index + 1, copy)
		state.mark_dirty()
		editor._schedule_rebuild()
		return
	if rule == null:
		return
	if kind == "action":
		var idx := rule.actions.find(resource)
		if idx >= 0:
			rule.actions.insert(idx + 1, (resource as GyroAction).duplicate(true))
		else:
			for a in rule.actions:
				var fa: Array = flow_handler.get_array(a)
				var fi := fa.find(resource)
				if fi >= 0:
					fa.insert(fi + 1, (resource as GyroAction).duplicate(true))
					flow_handler.sync(a)
					break
	else:
		var ci := rule.conditions.find(resource)
		if ci >= 0:
			rule.conditions.insert(ci + 1, (resource as GyroCondition).duplicate(true))
	state.mark_dirty()
	editor.rebuild.rebuild_rule_only(rule)

func toggle_hide_target(t: Dictionary) -> void:
	if t.is_empty():
		return
	var kind: String = str(t.get("kind", ""))
	var resource: Variant = t.get("resource", null)
	var rule: GyroEventRule = t.get("rule", null)
	if kind == "rule":
		state.rule_collapsed[resource] = not state.rule_collapsed.get(resource, false)
		editor._toggle_rule_collapse(resource)
	else:
		state.block_collapsed[resource] = not state.block_collapsed.get(resource, false)
		if rule != null:
			editor.rebuild.rebuild_rule_only(rule)

func toggle_disable_target(t: Dictionary) -> void:
	if t.is_empty():
		return
	undo_redo.push_undo()
	var kind: String = str(t.get("kind", ""))
	var resource: Variant = t.get("resource", null)
	resource.disabled = not bool(resource.get("disabled"))
	flow_handler.sync_all()
	state.mark_dirty()
	if kind == "rule":
		editor._apply_rule_alpha(resource as GyroEventRule)
	else:
		editor._apply_block_alpha(resource)

func delete_target(t: Dictionary) -> void:
	if t.is_empty():
		return
	undo_redo.push_undo()
	var kind: String = str(t.get("kind", ""))
	var resource: Variant = t.get("resource", null)
	var rule: GyroEventRule = t.get("rule", null)
	if kind == "rule":
		state.blueprint.rules.erase(resource)
		editor._remove_rule_wrapper(resource)
		state.mark_dirty()
		editor._schedule_rebuild()
		return
	if rule == null:
		return
	if kind == "action":
		var idx := rule.actions.find(resource)
		if idx >= 0:
			rule.actions.remove_at(idx)
		else:
			for a in rule.actions:
				var fa: Array = flow_handler.get_array(a)
				var fi := fa.find(resource)
				if fi >= 0:
					fa.remove_at(fi)
					flow_handler.sync(a)
					break
	else:
		var ci := rule.conditions.find(resource)
		if ci >= 0:
			rule.conditions.remove_at(ci)
	state.mark_dirty()
	editor.rebuild.rebuild_rule_only(rule)

func rename_variable(old_name: String, new_name: String) -> void:
	if old_name == new_name:
		return
	undo_redo.push_undo()
	if state.blueprint.variables.has(old_name):
		state.blueprint.variables[new_name] = state.blueprint.variables[old_name]
		state.blueprint.variables.erase(old_name)
	if state.blueprint.variable_types.has(old_name):
		state.blueprint.variable_types[new_name] = state.blueprint.variable_types[old_name]
		state.blueprint.variable_types.erase(old_name)
	if state.blueprint.tables.has(old_name):
		state.blueprint.tables[new_name] = state.blueprint.tables[old_name]
		state.blueprint.tables.erase(old_name)
	for rule_value in state.blueprint.rules:
		var rule := rule_value as GyroEventRule
		if rule == null:
			continue
		for action_value in rule.actions:
			var action := action_value as GyroAction
			if action == null:
				continue
			_rename_in_data(action.data, old_name, new_name)
		for condition_value in rule.conditions:
			var condition := condition_value as GyroCondition
			if condition == null:
				continue
			_rename_in_data(condition.data, old_name, new_name)
	state.mark_dirty()
	vars_dialog.rebuild()

func _rename_in_data(data: Dictionary, old_name: String, new_name: String) -> void:
	for key in data.keys():
		var value = data[key]
		if value is String:
			if value == "$var." + old_name:
				data[key] = "$var." + new_name
			elif value == old_name:
				data[key] = new_name

func add_variable(var_name: String) -> void:
	var raw := var_name.strip_edges()
	if raw.length() > 32:
		raw = raw.substr(0, 32)
	var clean := GyroUI.sanitize_name(raw).replace(" ", "_")
	if GyroUI.is_bad_name(clean):
		GyroUI.alert(editor, GyroLang.t("error"), GyroLang.t("enter_correct_variable"))
		return
	if state.blueprint.variables.has(clean):
		GyroUI.alert(editor, GyroLang.t("error"), GyroLang.t("variable_exists") % clean)
		return
	undo_redo.push_undo()
	state.blueprint.variables[clean] = null
	state.mark_dirty()
	vars_dialog.rebuild()

func remove_variable(var_name: String) -> void:
	undo_redo.push_undo()
	state.blueprint.variables.erase(var_name)
	state.mark_dirty()
	vars_dialog.rebuild()

func add_table(table_name: String) -> void:
	var raw := table_name.strip_edges()
	if raw.length() > 32:
		raw = raw.substr(0, 32)
	var clean := GyroUI.sanitize_name(raw).replace(" ", "_")
	if GyroUI.is_bad_name(clean):
		GyroUI.alert(editor, GyroLang.t("error"), GyroLang.t("enter_correct_variable"))
		return
	if state.blueprint.tables.has(clean):
		GyroUI.alert(editor, GyroLang.t("error"), GyroLang.t("variable_exists") % clean)
		return
	undo_redo.push_undo()
	state.blueprint.tables[clean] = {}
	state.mark_dirty()
	vars_dialog.rebuild()

func remove_table(table_name: String) -> void:
	undo_redo.push_undo()
	state.blueprint.tables.erase(table_name)
	state.mark_dirty()
	vars_dialog.rebuild()
