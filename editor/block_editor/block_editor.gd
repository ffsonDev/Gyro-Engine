class_name GyroBlockEditor
extends Control

const PALETTE_SCENE := preload("res://editor/gyro_palette.tscn")
const EXPR_SCENE := preload("res://editor/gyro_expr_editor.tscn")
const DIALOG_SCENE := preload("res://ui/components/gyro_dialog.tscn")
const DOC_SCENE := preload("res://ui/screens/doc_screen.tscn")

const OBJECT_CREATING_ACTIONS := [
	"CreateObject", "CreateSprite", "CreateText", "CreateCircle",
	"CreateLine", "CreateGroup", "CreateSpriteAnim",
	"CreateParticles", "CreateInput", "CreateSlider", "CreateToggle",
]

signal back_pressed

var state: BlockEditorState
var rebuild: BlockEditorRebuild
var actions: BlockEditorActions
var menus: BlockEditorMenus

var renderer: BlockRenderer
var drag_drop: DragDropController
var undo_redo: UndoRedoManager
var save_mgr: SaveManager
var vars_dialog: VarsDialog
var flow_handler: FlowHandler
var test_runner: TestRunner
var doc_screen: DocScreen
var expr_editor: GyroExprEditor

var editor_root: Node
var events_vbox: VBoxContainer
var scroll: ScrollContainer
var title_label: Label
var ui_root: Control
var drop_indicator: PanelContainer

var _field_callbacks := {}
var _rebuild_timer: Timer
var _rebuild_pending := false
var last_pointer := Vector2()

var _menu_overlay: ColorRect = null
var _menu_panel: PanelContainer = null

func _ready() -> void:
	editor_root = get_tree().get_root()
	ui_root = %Root
	title_label = %Title
	title_label.add_theme_font_size_override("font_size", GyroUI.fs(30))
	title_label.add_theme_color_override("font_color", Color.WHITE)
	scroll = %Scroll
	events_vbox = %EventsVBox

	doc_screen = DOC_SCENE.instantiate()
	doc_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	doc_screen.visible = false
	doc_screen.z_index = 50
	doc_screen.back_requested.connect(func(): _show(self))
	add_child(doc_screen)

	_rebuild_timer = Timer.new()
	_rebuild_timer.one_shot = true
	_rebuild_timer.wait_time = 0.05
	_rebuild_timer.timeout.connect(_do_rebuild)
	add_child(_rebuild_timer)

	_init_components()
	_connect_signals()
	apply_lang()
	rebuild.rebuild()

func _init_components() -> void:
	state = BlockEditorState.new()

	flow_handler = FlowHandler.new()
	renderer = BlockRenderer.new()
	renderer.setup(self, flow_handler)
	drag_drop = DragDropController.new()

	drop_indicator = PanelContainer.new()
	var indicator_style := StyleBoxFlat.new()
	indicator_style.bg_color = Color(0.2, 0.8, 0.9, 0.9)
	indicator_style.set_corner_radius_all(3)
	indicator_style.content_margin_left = 0
	indicator_style.content_margin_right = 0
	indicator_style.content_margin_top = 0
	indicator_style.content_margin_bottom = 0
	drop_indicator.add_theme_stylebox_override("panel", indicator_style)
	drop_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_indicator.z_index = 15
	drop_indicator.visible = false
	add_child(drop_indicator)

	drag_drop.setup(scroll, drop_indicator, _vibrate, _get_array_for, func(res: Variant) -> float:
		return 0.45 if bool(res.get("disabled")) else 1.0
	)
	drag_drop.drop_applied.connect(_apply_drop)

	undo_redo = UndoRedoManager.new()
	undo_redo.setup(_snapshot, _restore)

	save_mgr = SaveManager.new()
	save_mgr.setup(self, _do_save)

	vars_dialog = VarsDialog.new()
	vars_dialog.setup(
		%VarsOverlay, %VarsPanel, %VarsList, %VarNameEdit,
		%VarAddButton, %VarsTitle, %VarsCloseButton,
		%VarsRenameButton, %VarsDeleteButton
	)
	var vars_ts := GyroTouchScroll.new()
	add_child(vars_ts)
	vars_ts.setup(%VarsList)

	test_runner = TestRunner.new()
	test_runner.setup(self, _merged_blueprint)
	test_runner.stopped.connect(_on_test_stopped)

	expr_editor = EXPR_SCENE.instantiate()
	add_child(expr_editor)
	expr_editor.accepted.connect(_on_expr_accepted)

	menus = BlockEditorMenus.new(self, state, undo_redo, save_mgr, vars_dialog, expr_editor)
	menus.setup_palette()
	actions = BlockEditorActions.new(self, state, renderer, drag_drop, flow_handler, vars_dialog, undo_redo, save_mgr)
	rebuild = BlockEditorRebuild.new(self, state, renderer, drag_drop, flow_handler, events_vbox)

	var touch_scroll := GyroTouchScroll.new()
	add_child(touch_scroll)
	touch_scroll.setup(scroll, [menus.palette if menus.palette != null else Control.new(), %VarsOverlay, expr_editor, menus._event_popup])
	touch_scroll.gate = func(): return not drag_drop.dragging and not test_runner.is_running

func _connect_signals() -> void:
	%BackButton.pressed.connect(_on_back)
	%UndoButton.pressed.connect(undo_redo.undo)
	%RedoButton.pressed.connect(undo_redo.redo)
	%PlusButton.pressed.connect(_open_palette)
	%PlayButton.pressed.connect(_play)

	renderer.block_menu_requested.connect(func(kind: String, resource: Variant, rule: GyroEventRule):
		_open_block_menu(kind, resource, rule)
	)
	renderer.event_name_changed.connect(func(rule: GyroEventRule, text: String):
		undo_redo.mark_field_focus()
		var clean := text.strip_edges()
		if clean == "" or GyroBlocks.BUILTIN_EVENTS.has(clean) or _is_event_name_taken(clean, rule):
			renderer.mark_rule_name_invalid(rule, true)
			return
		renderer.mark_rule_name_invalid(rule, false)
		rule.event_name = clean
		renderer.refresh_rule_title(rule)
		state.mark_dirty()
	)
	renderer.event_pick_requested.connect(menus.open_event_for)
	renderer.note_changed.connect(func(rule: GyroEventRule, text: String):
		undo_redo.mark_field_focus()
		rule.note = text
		state.mark_dirty()
	)
	renderer.collapse_rule_requested.connect(func(rule: GyroEventRule):
		state.rule_collapsed[rule] = not state.rule_collapsed.get(rule, false)
		_toggle_rule_collapse(rule)
	)
	renderer.field_focus_entered.connect(func(): undo_redo.mark_field_focus())
	renderer.expr_pick_requested.connect(_open_expr_for)
	renderer.var_pick_requested.connect(_open_vars_for)
	renderer.table_pick_requested.connect(_open_tables_for)
	renderer.obj_pick_requested.connect(menus.open_obj_for)
	renderer.asset_pick_requested.connect(menus.open_asset_for)
	renderer.color_pick_requested.connect(menus.open_color_picker)

	vars_dialog.variable_picked.connect(_pick_variable)
	vars_dialog.variable_added.connect(actions.add_variable)
	vars_dialog.variable_removed.connect(actions.remove_variable)
	vars_dialog.variable_renamed.connect(actions.rename_variable)
	vars_dialog.table_picked.connect(_pick_table)
	vars_dialog.table_added.connect(actions.add_table)
	vars_dialog.table_removed.connect(actions.remove_table)

func _input(event: InputEvent) -> void:
	if test_runner != null and test_runner.is_running:
		return
	if drag_drop.dragging and (event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag):
		drag_drop.pointer = event.position
	if drag_drop.dragging:
		var is_release := false
		if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			is_release = true
		elif event is InputEventScreenTouch and not event.pressed:
			is_release = true
		if is_release:
			drag_drop.finish_drag()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		if drag_drop.dragging:
			drag_drop.finish_drag()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if test_runner.is_running:
		return
	if drag_drop.dragging:
		drag_drop.pointer = get_viewport().get_mouse_position()
	drag_drop.process_frame(delta)

func _schedule_rebuild() -> void:
	if not _rebuild_pending:
		_rebuild_pending = true
		_rebuild_timer.start()

func _do_rebuild() -> void:
	_rebuild_pending = false
	rebuild.rebuild_diff()

func _open_block_menu(kind: String, resource: Variant, rule: GyroEventRule) -> void:
	_close_block_menu()
	var target := {"kind": kind, "resource": resource, "rule": rule}
	_menu_overlay = ColorRect.new()
	_menu_overlay.color = Color(0, 0, 0, 0.5)
	_menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_overlay.z_index = 70
	_menu_overlay.gui_input.connect(func(e: InputEvent):
		if GyroUI.is_tap(e):
			_close_block_menu()
	)
	add_child(_menu_overlay)
	_menu_panel = PanelContainer.new()
	GyroUI.apply_glass_style(_menu_panel)
	GyroUI.center(_menu_panel)
	_menu_panel.z_index = 71
	add_child(_menu_panel)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(minf(360.0, get_viewport_rect().size.x - 48.0), 0)
	vbox.add_theme_constant_override("separation", 8)
	_menu_panel.add_child(vbox)
	var hidden: bool = state.rule_collapsed.get(rule, false) if kind == "rule" else state.block_collapsed.get(resource, false)
	var dis: bool = bool(resource.get("disabled"))
	_menu_button(vbox, "? " + GyroLang.t("doc"), target, _open_help_for_target, Color(0.4, 0.7, 0.95))
	_menu_button(vbox, GyroLang.t("duplicate"), target, actions.duplicate_target)
	_menu_button(vbox, GyroLang.t("block_show") if hidden else GyroLang.t("block_hide"), target, actions.toggle_hide_target)
	_menu_button(vbox, GyroLang.t("block_enable") if dis else GyroLang.t("block_disable"), target, actions.toggle_disable_target)
	_menu_button(vbox, GyroLang.t("delete"), target, _confirm_delete, Color(0.946, 0.544, 0.532, 1.0))

func _open_help_for_target(t: Dictionary) -> void:
	if t.is_empty():
		return
	var kind: String = str(t.get("kind", ""))
	var resource: Variant = t.get("resource", null)
	var block_type := ""
	if kind == "action" and resource is GyroAction:
		block_type = (resource as GyroAction).type
	elif kind == "condition" and resource is GyroCondition:
		block_type = (resource as GyroCondition).type
	elif kind == "rule" and resource is GyroEventRule:
		block_type = (resource as GyroEventRule).event_type
	if block_type != "" and doc_screen != null:
		doc_screen.open_section_by_block_type(block_type)
		_show(doc_screen)

func _show(node: Control) -> void:
	if node == doc_screen:
		if ui_root != null:
			ui_root.visible = false
		doc_screen.visible = true
	else:
		if ui_root != null:
			ui_root.visible = true
		if doc_screen != null:
			doc_screen.visible = false
		visible = true
		node.visible = true

func _menu_button(vbox: VBoxContainer, text: String, target: Dictionary, cb: Callable, color: Color = Color.WHITE) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, GyroUI.sz(56))
	b.add_theme_font_size_override("font_size", GyroUI.fs(18))
	b.add_theme_color_override("font_color", color)
	b.pressed.connect(func():
		_close_block_menu()
		cb.call(target)
	)
	vbox.add_child(b)

func _close_block_menu() -> void:
	if _menu_overlay != null and is_instance_valid(_menu_overlay):
		_menu_overlay.queue_free()
	_menu_overlay = null
	if _menu_panel != null and is_instance_valid(_menu_panel):
		_menu_panel.queue_free()
	_menu_panel = null

func _confirm_delete(t: Dictionary) -> void:
	_close_block_menu()
	var dialog := DIALOG_SCENE.instantiate()
	add_child(dialog)
	dialog.z_index = 72
	dialog.open(GyroLang.t("delete"), GyroLang.t("delete_block_q"), GyroLang.t("delete"), GyroLang.t("cancel"))
	dialog.confirmed.connect(func(): actions.delete_target(t))
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)

func flush_save() -> void:
	_flush_save()

func _apply_block_alpha(resource: Variant) -> void:
	var panel = renderer.get_block_panel(resource)
	if panel != null:
		panel.modulate.a = 0.45 if bool(resource.get("disabled")) else 1.0

func _apply_rule_alpha(rule: GyroEventRule) -> void:
	var wrapper = drag_drop.rule_wrappers.get(rule)
	if wrapper != null and is_instance_valid(wrapper):
		wrapper.modulate.a = 0.45 if rule.disabled else 1.0

func _remove_rule_wrapper(rule: GyroEventRule) -> void:
	var wrapper = drag_drop.rule_wrappers.get(rule)
	if wrapper != null and is_instance_valid(wrapper):
		wrapper.queue_free()
	drag_drop.rule_wrappers.erase(rule)
	var items_to_remove: Array = []
	for item in drag_drop.drag_items:
		if item.has("rule") and item.rule == rule:
			items_to_remove.append(item)
	for item in items_to_remove:
		drag_drop.drag_items.erase(item)

func _toggle_rule_collapse(rule: GyroEventRule) -> void:
	var wrapper = drag_drop.rule_wrappers.get(rule)
	if wrapper == null or not is_instance_valid(wrapper) or wrapper.get_child_count() < 2:
		return
	var body_panel = wrapper.get_child(1) as PanelContainer
	if body_panel == null:
		return
	var collapsed: bool = state.rule_collapsed.get(rule, false)
	body_panel.visible = not collapsed
	var header: Control = wrapper.get_child(0)
	if header != null:
		for child in header.get_children():
			if child is Button and child.get_meta("is_collapse_btn", false):
				GyroUI.set_icon(child,
					"res://ui/icons/chevron_down.svg" if collapsed else "res://ui/icons/chevron_up.svg")

func _get_array_for(rule: GyroEventRule, kind: String) -> Array:
	return rule.actions if kind == "action" else rule.conditions

func _array_for(rule: GyroEventRule, kind: String) -> Array:
	return _get_array_for(rule, kind)

func _apply_drop(drop: Dictionary) -> void:
	rebuild.apply_drop(drop)

func _start_drag_from_rule(rule: GyroEventRule, panel: Control) -> void:
	drag_drop.start_drag("rule", rule, rule, panel)
	drag_drop.set_pointer(last_pointer)

func _start_drag_from_panel(kind: String, resource: Variant, rule: GyroEventRule, panel: Control) -> void:
	drag_drop.start_drag(kind, resource, rule, panel)
	drag_drop.set_pointer(last_pointer)

func _find_source_array() -> Array:
	for entry in drag_drop.drag_items:
		if entry.has("resource") and entry.resource == drag_drop.drag_resource and entry.has("array"):
			return entry.array
	return _array_for(drag_drop.drag_rule, drag_drop.drag_kind)

func _mark_dirty() -> void:
	state.mark_dirty()
	save_mgr.mark_dirty()

func _flush_save() -> void:
	save_mgr.force_save()

func _do_save() -> void:
	flow_handler.sync_all()
	if state.save_path == "":
		return
	if state.project != null:
		GyroProjectJSON.save_to_file(state.project, state.save_path)

func _snapshot() -> Dictionary:
	flow_handler.sync_all()
	var rules: Array = []
	for rule_value in state.blueprint.rules:
		var rule := rule_value as GyroEventRule
		if rule == null:
			continue
		var conditions: Array = []
		for c_value in rule.conditions:
			var c := c_value as GyroCondition
			if c == null:
				continue
			conditions.append({
				"type": c.type,
				"data": c.data.duplicate(true),
				"disabled": c.disabled
			})
		var actions_arr: Array = []
		for a_value in rule.actions:
			var a := a_value as GyroAction
			if a == null:
				continue
			actions_arr.append({
				"type": a.type,
				"data": a.data.duplicate(true),
				"disabled": a.disabled
			})
		rules.append({
			"event_type": rule.event_type,
			"event_name": rule.event_name,
			"note": rule.note,
			"disabled": rule.disabled,
			"conditions": conditions,
			"actions": actions_arr
		})
	return {
		"variables": state.blueprint.variables.duplicate(true),
		"variable_types": state.blueprint.variable_types.duplicate(true),
		"tables": state.blueprint.tables.duplicate(true),
		"rules": rules,
		"timers": state.blueprint.timers.map(func(t: GyroTimerConfig):
			return {
				"timer_name": t.timer_name,
				"wait_time": t.wait_time,
				"one_shot": t.one_shot,
				"autostart": t.autostart
			})
	}

func _restore(snapshot: Dictionary) -> void:
	state.blueprint.variables = (snapshot.get("variables", {}) as Dictionary).duplicate(true)
	state.blueprint.variable_types = (snapshot.get("variable_types", {}) as Dictionary).duplicate(true)
	state.blueprint.tables = (snapshot.get("tables", {}) as Dictionary).duplicate(true)
	state.blueprint.rules.clear()
	for rv in snapshot.get("rules", []):
		var rd: Dictionary = rv as Dictionary
		var rule := GyroEventRule.new()
		_apply_rule_dict(rule, rd)
		for cv in rd.get("conditions", []):
			var d: Dictionary = cv as Dictionary
			var c := GyroCondition.new()
			c.type = str(d.get("type", ""))
			c.data = (d.get("data", {}) as Dictionary).duplicate(true)
			c.disabled = bool(d.get("disabled", false))
			rule.conditions.append(c)
		for av in rd.get("actions", []):
			var d2: Dictionary = av as Dictionary
			var a := GyroAction.new()
			a.type = str(d2.get("type", ""))
			a.data = (d2.get("data", {}) as Dictionary).duplicate(true)
			a.disabled = bool(d2.get("disabled", false))
			rule.actions.append(a)
		state.blueprint.rules.append(rule)
	state.blueprint.timers.clear()
	for t_value in snapshot.get("timers", []):
		var t_data: Dictionary = t_value as Dictionary
		var t := GyroTimerConfig.new()
		t.timer_name = str(t_data.get("timer_name", ""))
		t.wait_time = float(t_data.get("wait_time", 1.0))
		t.one_shot = bool(t_data.get("one_shot", false))
		t.autostart = bool(t_data.get("autostart", true))
		state.blueprint.timers.append(t)
	flow_handler.clear()
	state.mark_dirty()
	save_mgr.mark_dirty()
	rebuild.rebuild()

func _apply_rule_dict(rule: GyroEventRule, rd: Dictionary) -> void:
	if rd.has("event_type"):
		rule.event_type = str(rd.get("event_type", "ready"))
		rule.event_name = str(rd.get("event_name", ""))
	else:
		var old := str(rd.get("event_name", ""))
		if GyroBlocks.BUILTIN_EVENTS.has(old):
			rule.event_type = old
			rule.event_name = ""
		elif old.begins_with("func_"):
			rule.event_type = "func"
			rule.event_name = old
		else:
			rule.event_type = "custom"
			rule.event_name = old
	rule.note = str(rd.get("note", ""))
	rule.disabled = bool(rd.get("disabled", false))

func _on_flow_changed() -> void:
	_mark_dirty()
	_schedule_rebuild()

func _open_palette() -> void:
	if menus.palette != null:
		menus.palette.project = state.project
		menus.palette.apply_lang()
		menus.palette.visible = true

func _last_rule_or_create() -> GyroEventRule:
	if state.blueprint.rules.size() > 0:
		return state.blueprint.rules[state.blueprint.rules.size() - 1] as GyroEventRule
	var rule := GyroEventRule.new()
	rule.event_type = "ready"
	state.blueprint.rules.append(rule)
	return rule

func _play() -> void:
	if _is_custom_body():
		return
	var seen := {}
	var dups: Array = []
	for r in _merged_blueprint().rules:
		if r == null:
			continue
		if not r.is_named():
			continue
		var fn := r.fire_name()
		if fn.strip_edges() == "":
			if not dups.has(GyroLang.t("event_name_placeholder")):
				dups.append(GyroLang.t("event_name_placeholder"))
			continue
		if seen.has(fn):
			if not dups.has(fn):
				dups.append(fn)
		else:
			seen[fn] = true
	if dups.size() > 0:
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("duplicate_events") % ", ".join(dups))
		return
	if state.project != null and state.project.settings != null:
		GyroUI.set_orientation(state.project.settings.orientation)
	ui_root.visible = false
	test_runner.start(state.project, state.save_path)

func _is_custom_body() -> bool:
	var s := state.current_script
	return s != null and str(s.get_meta("gyro_custom_block_id", "")) != ""

func _update_play_visibility() -> void:
	var btn := get_node_or_null("%PlayButton") as Button
	if btn != null:
		btn.visible = not _is_custom_body()

func _on_test_stopped() -> void:
	ui_root.visible = true
	GyroUI.set_orientation("portrait")

func _open_vars_for(set_callback: Callable, key: String, button: Button, resource: Variant) -> void:
	menus.var_pick_key = key
	menus.var_pick_button = button
	_field_callbacks[button] = {"resource": button, "key": key, "set_callback": set_callback}
	vars_dialog.set_picking(true)
	vars_dialog.open(false)

func _open_tables_for(set_callback: Callable, key: String, button: Button) -> void:
	menus.var_pick_key = key
	menus.var_pick_button = button
	_field_callbacks[button] = {"resource": button, "key": key, "set_callback": set_callback}
	vars_dialog.set_picking(true, true)
	vars_dialog.open(true)

func _pick_variable(var_name: String) -> void:
	if menus.var_pick_button != null and is_instance_valid(menus.var_pick_button):
		_set_pick_text(menus.var_pick_button, var_name)
	var cb: Dictionary = _field_callbacks.get(menus.var_pick_button, {}) as Dictionary
	if cb.has("set_callback") and cb.set_callback.is_valid():
		undo_redo.push_undo()
		cb.set_callback.call(cb.key, var_name)
		save_mgr.mark_dirty()
	vars_dialog.set_picking(false)
	vars_dialog.close()

func _pick_table(table_name: String) -> void:
	if menus.var_pick_button != null and is_instance_valid(menus.var_pick_button):
		_set_pick_text(menus.var_pick_button, table_name)
		var cb: Dictionary = _field_callbacks.get(menus.var_pick_button, {}) as Dictionary
		if cb.has("set_callback") and cb.set_callback.is_valid():
			undo_redo.push_undo()
			cb.set_callback.call(cb.key, table_name)
			save_mgr.mark_dirty()
	vars_dialog.set_picking(false)
	vars_dialog.close()

func _open_expr_for(set_callback: Callable, key: String, button: Button) -> void:
	menus.expr_pick_key = key
	menus.expr_pick_button = button
	_field_callbacks[button] = {"resource": button, "key": key, "set_callback": set_callback}
	var initial := ""
	if button.has_meta("expr_raw"):
		initial = _display_value(button.get_meta("expr_raw"))
	var names: Array = []
	for k in state.blueprint.variables.keys():
		names.append(str(k))
	expr_editor.open(initial, names, state.custom_param_names)

func _on_expr_accepted(text: String) -> void:
	if menus.expr_pick_button != null and is_instance_valid(menus.expr_pick_button):
		menus.expr_pick_button.set_meta("expr_raw", text)
		_set_pick_text(menus.expr_pick_button, text)
		var cb: Dictionary = _field_callbacks.get(menus.expr_pick_button, {}) as Dictionary
		if cb.has("set_callback") and cb.set_callback.is_valid():
			undo_redo.push_undo()
			cb.set_callback.call(cb.key, _parse_field(text))
			save_mgr.mark_dirty()
		menus.expr_pick_button = null

func _parse_field(text: String) -> Variant:
	var trimmed := text.strip_edges()
	if trimmed == "":
		return ""
	var json := JSON.new()
	var err := json.parse(trimmed)
	if err == OK:
		return json.data
	return trimmed

func _set_pick_text(button: Button, text: String) -> void:
	if button.get_child_count() > 0:
		var label: Label = button.get_child(0) as Label
		if label != null:
			label.text = _short(text)

func _short(text: String, max_chars: int = 24) -> String:
	if text.length() > max_chars:
		return text.substr(0, max_chars - 1) + "…"
	return text

func _display_value(value: Variant) -> String:
	if value == null:
		return ""
	if value is String:
		return str(value)
	if value is Dictionary or value is Array:
		return JSON.stringify(value)
	if value is float:
		var f: float = float(value)
		if f == floorf(f):
			return str(int(f))
		return str(f)
	if value is int:
		return str(value)
	if value is bool:
		return str(value)
	return str(value)

func _object_names() -> Array:
	var names: Array = []
	for rule_value in state.blueprint.rules:
		var rule := rule_value as GyroEventRule
		if rule == null:
			continue
		for a_value in rule.actions:
			var a := a_value as GyroAction
			if a == null:
				continue
			if OBJECT_CREATING_ACTIONS.has(a.type):
				var n := str(a.data.get("name", ""))
				if n != "" and not names.has(n):
					names.append(n)
	return names

func _assets_of_kind(kind: String) -> Array:
	var result: Array = []
	if state.project == null:
		return result
	for v in state.project.assets:
		var a: GyroAsset = v as GyroAsset
		if a != null and a.kind == kind:
			result.append(a)
	return result

func _merged_blueprint() -> GyroEventBlueprint:
	return state.merged_blueprint()

func _vibrate(ms: int) -> void:
	var os_name := OS.get_name()
	if os_name == "Android" or os_name == "iOS":
		Input.vibrate_handheld(ms)

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.pressed and event.keycode == KEY_ESCAPE:
		if test_runner.is_running and test_runner.layout != null and test_runner.layout.is_active():
			test_runner.layout.exit()
			get_viewport().set_input_as_handled()
			return
		if test_runner.is_running:
			test_runner.emit_back()
		else:
			_on_back()
		get_viewport().set_input_as_handled()
		return
	if not event.pressed or not event.ctrl_pressed:
		return
	if event.keycode == KEY_Z:
		if event.shift_pressed:
			undo_redo.redo()
		else:
			undo_redo.undo()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_Y:
		undo_redo.redo()
		get_viewport().set_input_as_handled()

func _on_back() -> void:
	_flush_save()
	back_pressed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		_flush_save()

func _default_data(block_type: String) -> Dictionary:
	match block_type:
		"CreateObject":
			state.object_counter += 1
			return {"name": "obj" + str(state.object_counter), "type": "rect", "x": 100, "y": 100, "w": 80, "h": 80, "color": "#ffffff", "radius": 0, "text": "", "texture": "", "font": 24, "variable": ""}
		"CreateSprite":
			state.object_counter += 1
			return {"name": "sprite" + str(state.object_counter), "x": 100, "y": 100, "w": 100, "h": 100, "texture": ""}
		"CreateText":
			state.object_counter += 1
			return {"name": "text" + str(state.object_counter), "x": 100, "y": 100, "w": 200, "h": 60, "text": "Текст", "font": "", "size": 24}
		"DeleteObject":
			return {"node": state.last_object_name}
		"MoveNode":
			return {"node": state.last_object_name, "mode": "delta", "x": 10, "y": 0}
		"SetNodeProperty":
			return {"node": state.last_object_name, "property": "position", "x": 100, "y": 100, "value": ""}
		"SetSize":
			return {"node": state.last_object_name, "w": 80, "h": 80}
		"SetText":
			return {"node": state.last_object_name, "text": GyroLang.t("default_text")}
		"SetVisible":
			return {"node": state.last_object_name, "on": true}
		"SetOpacity":
			return {"node": state.last_object_name, "value": 100}
		"SetRotation":
			return {"node": state.last_object_name, "mode": "set", "angle": 0}
		"SetScale":
			return {"node": state.last_object_name, "percent": 100, "x": 100, "y": 100}
		"ChangeLayer":
			return {"node": state.last_object_name, "dir": 1}
		"SetFontSize":
			return {"node": state.last_object_name, "size": 24}
		"SetColor":
			return {"node": state.last_object_name, "color": "#ffffff"}
		"SetTextAlign":
			return {"node": state.last_object_name, "align": "center"}
		"SetTexture":
			return {"node": state.last_object_name, "texture": ""}
		"SetCornerRadius":
			return {"node": state.last_object_name, "radius": 10}
		"SetPivot":
			return {"node": state.last_object_name, "x": 50, "y": 50}
		"SetObjectMeta":
			return {"node": state.last_object_name, "key": "hp", "value": 0}
		"FaceObject":
			return {"node": state.last_object_name, "target": state.last_object_name}
		"PlayAnimation":
			return {"node": state.last_object_name, "animation": "idle"}
		"StopAnimation":
			return {"node": state.last_object_name}
		"SetSolid":
			return {"node": state.last_object_name, "on": true}
		"SetSensor":
			return {"node": state.last_object_name, "on": true}
		"SetDraggable":
			return {"node": state.last_object_name, "on": true}
		"Spawn":
			return {"scene": "", "parent": "", "x": 0, "y": 0, "variable": ""}
		"CreateGroup":
			state.object_counter += 1
			return {"name": "group" + str(state.object_counter), "x": 0, "y": 0, "w": 480, "h": 720}
		"AddToGroup":
			return {"node": state.last_object_name, "group": ""}
		"CreateCircle":
			state.object_counter += 1
			return {"name": "circle" + str(state.object_counter), "radius": 50, "color": "#ffffff", "border_w": 0, "border_color": "#ffffff", "x": 100, "y": 100}
		"CreateLine":
			state.object_counter += 1
			return {"name": "line" + str(state.object_counter), "x": 0, "y": 0, "x2": 100, "y2": 100, "color": "#ffffff", "width": 4}
		"SetGradient":
			return {"node": state.last_object_name, "mode": "linear", "color1": "#ffffff", "color2": "#000000"}
		"SetBorder":
			return {"node": state.last_object_name, "color": "#ffffff", "width": 4}
		"CreateSpriteAnim":
			state.object_counter += 1
			return {"name": "anim" + str(state.object_counter), "sprite": "", "frame_w": 32, "frame_h": 32, "count": 4, "fps": 8, "anim": "default", "x": 100, "y": 100}
		"SetFrame":
			return {"node": state.last_object_name, "frame": 0}
		"CreateParticles":
			state.object_counter += 1
			return {"name": "fx" + str(state.object_counter), "preset": "snow", "x": 240, "y": 0}
		"SetParticlesParam":
			return {"node": "", "param": "speed", "value": 100}
		"DeleteParticles":
			return {"node": ""}
		"SetParallax":
			return {"node": state.last_object_name, "x": 50, "y": 50}
		"SetVelocity":
			return {"node": state.last_object_name, "x": 0, "y": 0}
		"AddVelocity":
			return {"node": state.last_object_name, "x": 0, "y": -700}
		"SetGravity":
			return {"node": state.last_object_name, "value": 1500}
		"SetGlobalGravity":
			return {"value": 1500}
		"SetPhysicsPaused":
			return {"on": true}
		"SetVariable":
			return {"name": _first_var(), "value": 0}
		"AddToVariable":
			return {"name": _first_var(), "amount": 1}
		"SetTableValue":
			return {"name": _first_table(), "key": "KEY", "value": 0}
		"GetTableValue":
			return {"name": _first_table(), "key": "KEY", "variable": _first_var()}
		"InsertArrayValue":
			return {"name": _first_table(), "index": 0, "value": 0}
		"RemoveArrayValue":
			return {"name": _first_table(), "index": 0}
		"OverwriteTable":
			return {"name": _first_table(), "json": "{}"}
		"ForEachTable":
			return {"name": _first_table(), "element": "item", "keyvar": "k", "blocks": []}
		"LoopRange":
			return {"from": 1, "to": 10, "step": 1, "variable": _first_var(), "blocks": []}
		"PlaySound":
			return {"sound": "", "volume": 1.0, "loop": false}
		"StopSound":
			return {"sound": ""}
		"SetSoundVolume":
			return {"sound": "", "volume": 100}
		"StartTimer":
			return {"name": "timer_1", "wait": 1.0, "one_shot": true, "repeat": 1}
		"StopTimer":
			return {"name": "timer_1"}
		"SetCameraPosition":
			return {"x": 0, "y": 0}
		"CameraFollow":
			return {"node": state.last_object_name, "smooth": 5}
		"TweenPosition":
			return {"node": state.last_object_name, "x": 100, "y": 100, "time": 1.0, "ease": "linear"}
		"TweenScale":
			return {"node": state.last_object_name, "percent": 150, "time": 1.0, "ease": "out"}
		"TweenRotation":
			return {"node": state.last_object_name, "angle": 360, "time": 1.0, "ease": "linear"}
		"TweenOpacity":
			return {"node": state.last_object_name, "value": 0, "time": 1.0, "ease": "linear"}
		"StopTween":
			return {"node": state.last_object_name}
		"AddTag":
			return {"node": state.last_object_name, "tag": "enemy"}
		"DeleteByTag":
			return {"tag": "enemy"}
		"SetVisibleByTag":
			return {"tag": "enemy", "on": false}
		"SetPositionByTag":
			return {"tag": "enemy", "mode": "set", "x": 0, "y": 0}
		"SetRotationByTag":
			return {"tag": "enemy", "angle": 0}
		"SetOpacityByTag":
			return {"tag": "enemy", "value": 100}
		"SetScaleByTag":
			return {"tag": "enemy", "percent": 100}
		"ChangeLayerByTag":
			return {"tag": "enemy", "dir": 1}
		"CreateInput":
			state.object_counter += 1
			return {"name": "input" + str(state.object_counter), "text": "", "multiline": false, "secret": false, "x": 100, "y": 100, "w": 240}
		"CreateSlider":
			state.object_counter += 1
			return {"name": "slider" + str(state.object_counter), "vertical": false, "value": 50, "x": 100, "y": 100}
		"CreateToggle":
			state.object_counter += 1
			return {"name": "toggle" + str(state.object_counter), "on": false, "x": 100, "y": 100}
		"GetWidgetText":
			return {"widget": "", "variable": _first_var()}
		"SetSliderValue":
			return {"widget": "", "value": 50}
		"SetToggleState":
			return {"widget": "", "on": true}
		"ReadFile":
			return {"path": "save.txt", "variable": _first_var()}
		"WriteFile":
			return {"path": "save.txt", "value": "текст"}
		"FileOp":
			return {"op": "delete", "path1": "file.txt", "path2": ""}
		"HttpRequest":
			return {"url": "https://", "method": "GET", "body": "", "variable": _first_var()}
		"SaveValue":
			return {"key": "score", "value": 0}
		"LoadValue":
			return {"key": "score", "variable": _first_var()}
		"Print":
			return {"message": "текст"}
		"Toast":
			return {"text": "текст"}
		"SetBackgroundColor":
			return {"color": "#000000"}
		"SetOrientation":
			return {"mode": "portrait"}
		"Clipboard":
			return {"mode": "set", "text": "", "variable": _first_var()}
		"OpenURL":
			return {"url": "https://"}
		"RandomSeed":
			return {"seed": 0}
		"Quit":
			return {}
		"EmitEvent":
			return {"event": "custom", "payload": "{}"}
		"Wait":
			return {"wait": 1.0}
		"WaitUntil":
			return {"condition": "$var.flag == true", "timeout": 5}
		"If":
			return {"condition": "true", "blocks": []}
		"Repeat":
			return {"count": 3, "blocks": []}
		"Always":
			return {}
		"VariableEquals":
			return {"name": _first_var(), "value": 0}
		"VariableGreaterThan":
			return {"name": _first_var(), "value": 0}
		"PayloadEquals":
			return {"key": "a", "value": ""}
		"PayloadGreaterThan":
			return {"key": "x", "value": 0}
		"SetAnchor":
			return {"node": state.last_object_name, "anchor": "c"}
		_:
			return GyroBlocks.default_data(block_type)

func _first_var() -> String:
	var keys := state.blueprint.variables.keys()
	if keys.is_empty():
		return "var"
	return str(keys[0])

func _first_table() -> String:
	var keys := state.blueprint.tables.keys()
	if keys.is_empty():
		return "table"
	return str(keys[0])

func open_script(proj: GyroProject, script: GyroScript, path: String, params: Array = []) -> void:
	state.project = proj
	state.current_script = script
	state.save_path = path
	if script.blueprint == null:
		script.blueprint = GyroEventBlueprint.new()
	state.blueprint = script.blueprint
	state.custom_param_names = params.duplicate()
	title_label.text = script.script_name
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.clip_contents = true
	state.clear()
	flow_handler.clear()
	undo_redo.clear()
	save_mgr.dirty = false
	vars_dialog.set_blueprint(state.blueprint)
	_update_play_visibility()
	rebuild.rebuild()

func editor_back() -> void:
	if test_runner.is_running and test_runner.layout != null and test_runner.layout.is_active():
		test_runner.layout.exit()
		return
	if test_runner.is_running:
		test_runner.emit_back()
		return
	_flush_save()
	back_pressed.emit()

func stop_test() -> void:
	test_runner.stop()

func apply_lang() -> void:
	if menus.palette != null:
		menus.palette.apply_lang()
	if expr_editor != null:
		expr_editor.apply_lang()
	state._rule_sigs.clear()
	_schedule_rebuild()

func _is_event_name_taken(name: String, exclude: GyroEventRule) -> bool:
	if state.project != null:
		for s in state.project.scripts:
			if s == null or s.blueprint == null:
				continue
			for r in s.blueprint.rules:
				if r != null and r != exclude and not r.disabled and r.is_named() and r.event_name == name:
					return true
		return false
	for r in state.blueprint.rules:
		if r != null and r != exclude and not r.disabled and r.is_named() and r.event_name == name:
			return true
	return false

func _event_names() -> Array:
	var names: Array = []
	for b in GyroBlocks.BUILTIN_EVENTS:
		names.append(str(b))
	if state.project != null:
		for s in state.project.scripts:
			if s == null or s.blueprint == null:
				continue
			for r in s.blueprint.rules:
				if r != null and r.is_named() and r.event_name != "" and not names.has(r.event_name):
					names.append(r.event_name)
	names.sort()
	return names

func _timer_names() -> Array:
	var names: Array = []
	if state.blueprint != null:
		for t in state.blueprint.timers:
			var tn := str(t.timer_name)
			if tn != "" and not names.has(tn):
				names.append(tn)
	for rule_value in state.blueprint.rules:
		var rule := rule_value as GyroEventRule
		if rule == null:
			continue
		for a_value in rule.actions:
			var a := a_value as GyroAction
			if a != null and a.type == "StartTimer":
				var tn := str(a.data.get("name", ""))
				if tn != "" and not names.has(tn):
					names.append(tn)
	return names

func add_move_node_action(obj_name: String, pos: Vector2) -> void:
	var changed_rules: Array = []
	for rule_value in state.blueprint.rules:
		var rule := rule_value as GyroEventRule
		if rule == null:
			continue
		if _apply_layout_position(rule.actions, obj_name, pos):
			changed_rules.append(rule)
	if changed_rules.is_empty():
		var ready_rule: GyroEventRule = null
		for r in state.blueprint.rules:
			if r.event_type == "ready" and r.event_name == "":
				ready_rule = r
				break
		if ready_rule == null:
			ready_rule = GyroEventRule.new()
			ready_rule.event_type = "ready"
			state.blueprint.rules.append(ready_rule)
		var existing_action: GyroAction = null
		for a in ready_rule.actions:
			if a.type == "MoveNode" and str(a.data.get("node", "")) == obj_name:
				existing_action = a
				break
		if existing_action == null:
			existing_action = GyroAction.new()
			existing_action.type = "MoveNode"
			existing_action.data = {
				"node": obj_name,
				"mode": "set",
				"x": pos.x,
				"y": pos.y
			}
			ready_rule.actions.append(existing_action)
		else:
			existing_action.data["mode"] = "set"
			existing_action.data["x"] = pos.x
			existing_action.data["y"] = pos.y
		changed_rules.append(ready_rule)
	var h := test_runner.host
	if h != null:
		h.unregister_anchor(obj_name)
	state.mark_dirty()
	save_mgr.mark_dirty()
	for r in changed_rules:
		rebuild.rebuild_rule_only(r)

func _apply_layout_position(actions: Array, obj_name: String, pos: Vector2) -> bool:
	var changed := false
	for a_value in actions:
		var a := a_value as GyroAction
		if a == null:
			continue
		if OBJECT_CREATING_ACTIONS.has(a.type) and str(a.data.get("name", "")) == obj_name:
			a.data["x"] = pos.x
			a.data["y"] = pos.y
			if a.data.has("anchor"):
				a.data["anchor"] = "free"
			changed = true
		elif a.type == "MoveNode" and str(a.data.get("mode", "delta")) == "set" and str(a.data.get("node", "")) == obj_name:
			a.data["x"] = pos.x
			a.data["y"] = pos.y
			changed = true
	return changed
