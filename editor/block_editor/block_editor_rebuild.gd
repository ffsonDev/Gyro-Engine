class_name BlockEditorRebuild
extends RefCounted

var editor: GyroBlockEditor
var state: BlockEditorState
var renderer: BlockRenderer
var drag_drop: DragDropController
var flow_handler: FlowHandler
var events_vbox: VBoxContainer

func _init(ed: GyroBlockEditor, st: BlockEditorState, rnd: BlockRenderer, dd: DragDropController, fh: FlowHandler, ev: VBoxContainer) -> void:
	editor = ed
	state = st
	renderer = rnd
	drag_drop = dd
	flow_handler = fh
	events_vbox = ev

func rule_signature(rule: GyroEventRule) -> String:
	var conds: Array = []
	for c_value in rule.conditions:
		var c := c_value as GyroCondition
		if c != null:
			conds.append({"type": c.type, "data": c.data, "d": c.disabled})
	var acts: Array = []
	for a_value in rule.actions:
		var a := a_value as GyroAction
		if a != null:
			acts.append({"type": a.type, "data": a.data, "d": a.disabled})
	return JSON.stringify({"t": rule.event_type, "e": rule.event_name, "n": rule.note, "rd": rule.disabled, "c": conds, "a": acts})

func rebuild() -> void:
	state._rule_sigs.clear()
	drag_drop.reset()
	flow_handler.clear()
	renderer.clear_field_cache()
	editor._field_callbacks.clear()
	GyroUI.clear_children(events_vbox)
	for rule in state.blueprint.rules:
		var wrapper: VBoxContainer = renderer.build_event_block(events_vbox, rule, state.rule_collapsed.get(rule, false))
		drag_drop.register_rule(rule, wrapper)
		drag_drop.register_item({"kind": "rule", "resource": rule, "rule": rule, "panel": wrapper})
		editor._apply_rule_alpha(rule)
		state._rule_sigs[rule] = rule_signature(rule)

func rebuild_rule_only(rule: GyroEventRule) -> void:
	var wrapper = drag_drop.rule_wrappers.get(rule)
	if wrapper == null or not is_instance_valid(wrapper):
		editor._schedule_rebuild()
		return
	var body_panel = wrapper.get_child(1) as PanelContainer
	if body_panel == null or body_panel.get_child_count() == 0:
		editor._schedule_rebuild()
		return
	var body = body_panel.get_child(0) as VBoxContainer
	var items_to_remove: Array = []
	for item in drag_drop.drag_items:
		if item.has("rule") and item.rule == rule:
			items_to_remove.append(item)
	for item in items_to_remove:
		drag_drop.drag_items.erase(item)
	var dead_keys := []
	for key in editor._field_callbacks:
		if not is_instance_valid(key):
			dead_keys.append(key)
	for key in dead_keys:
		editor._field_callbacks.erase(key)
	GyroUI.clear_children(body)
	renderer._build_rule_body(body, rule)
	editor._apply_rule_alpha(rule)
	state._rule_sigs[rule] = rule_signature(rule)

func rebuild_diff() -> void:
	var rules := state.blueprint.rules
	for rule_key in drag_drop.rule_wrappers.keys().duplicate():
		if not rules.has(rule_key):
			editor._remove_rule_wrapper(rule_key)
			state._rule_sigs.erase(rule_key)
	for i in rules.size():
		var rule: GyroEventRule = rules[i]
		var wrapper = drag_drop.rule_wrappers.get(rule)
		if wrapper == null or not is_instance_valid(wrapper):
			_add_rule_wrapper_at(rule, i)
		else:
			_move_wrapper_to_index(wrapper, i)
		var sig := rule_signature(rule)
		if str(state._rule_sigs.get(rule, "")) != sig:
			rebuild_rule_only(rule)
	for key in state._rule_sigs.keys().duplicate():
		if not rules.has(key):
			state._rule_sigs.erase(key)

func _add_rule_wrapper_at(rule: GyroEventRule, index: int) -> VBoxContainer:
	var wrapper: VBoxContainer = renderer.build_event_block(events_vbox, rule, state.rule_collapsed.get(rule, false))
	_move_wrapper_to_index(wrapper, index)
	drag_drop.register_rule(rule, wrapper)
	drag_drop.register_item({"kind": "rule", "resource": rule, "rule": rule, "panel": wrapper})
	editor._apply_rule_alpha(rule)
	state._rule_sigs[rule] = rule_signature(rule)
	return wrapper

func _move_wrapper_to_index(wrapper: Control, index: int) -> void:
	if wrapper.get_parent() == null:
		events_vbox.add_child(wrapper)
	if wrapper.get_index() != index:
		events_vbox.move_child(wrapper, index)

func apply_drop(drop: Dictionary) -> void:
	if drop.is_empty():
		return
	if drag_drop.drag_kind == "rule":
		if drop.get("type") != "item":
			return
		var rules: Array = state.blueprint.rules
		var from_index: int = rules.find(drag_drop.drag_resource)
		var to_index: int = rules.find(drop.get("item").get("resource"))
		if from_index < 0 or to_index < 0:
			return
		if not drop.get("before", false):
			to_index += 1
		editor.undo_redo.push_undo()
		rules.remove_at(from_index)
		if to_index > from_index:
			to_index -= 1
		rules.insert(to_index, drag_drop.drag_resource)
		state.mark_dirty()
		var wrapper = drag_drop.rule_wrappers.get(drag_drop.drag_resource)
		if wrapper != null and is_instance_valid(wrapper):
			if wrapper.get_parent() != null:
				wrapper.get_parent().remove_child(wrapper)
			events_vbox.add_child(wrapper)
			if to_index >= 0 and to_index < events_vbox.get_child_count():
				events_vbox.move_child(wrapper, to_index)
		return

	var source_array: Array = editor._find_source_array()
	var target_array: Array = []
	var drop_type: String = drop.get("type", "")
	if drop_type == "item":
		var item_dict: Dictionary = drop.get("item", {})
		target_array = item_dict.get("array", editor._array_for(drop.get("item").get("rule"), drag_drop.drag_kind))
	elif drop_type == "flow":
		target_array = flow_handler.get_array(drop.get("action"))
	else:
		target_array = editor._array_for(drop.get("rule"), drag_drop.drag_kind)

	var from_index: int = source_array.find(drag_drop.drag_resource)
	var to_index: int = 0
	if drop_type == "item":
		to_index = target_array.find(drop.get("item").get("resource"))
		if to_index < 0:
			to_index = 0
		elif not drop.get("before", false):
			to_index += 1
	elif drop_type == "rule":
		to_index = target_array.size()

	if from_index < 0:
		return

	var existing_index_in_target: int = target_array.find(drag_drop.drag_resource)
	if existing_index_in_target >= 0 and not is_same(source_array, target_array):
		target_array.remove_at(existing_index_in_target)
		if existing_index_in_target < to_index:
			to_index -= 1

	editor.undo_redo.push_undo()
	source_array.remove_at(from_index)
	if is_same(source_array, target_array) and to_index > from_index:
		to_index -= 1

	target_array.insert(to_index, drag_drop.drag_resource)
	flow_handler.sync_all()
	state.mark_dirty()

	var changed_rules: Array = []
	if drag_drop.drag_rule != null and drag_drop.drag_rule is GyroEventRule:
		changed_rules.append(drag_drop.drag_rule)
	var target_rule = drop.get("rule", null)
	if target_rule == null and drop_type == "item":
		var item_dict: Dictionary = drop.get("item", {})
		target_rule = item_dict.get("rule", null)
	if target_rule != null and target_rule is GyroEventRule and not changed_rules.has(target_rule):
		changed_rules.append(target_rule)
	if drop_type == "flow":
		var flow_action = drop.get("action", null)
		for r_value in state.blueprint.rules:
			var r := r_value as GyroEventRule
			if r != null and r.actions.has(flow_action) and not changed_rules.has(r):
				changed_rules.append(r)
				break

	for r in changed_rules:
		rebuild_rule_only(r)
	if changed_rules.is_empty():
		editor._schedule_rebuild()
