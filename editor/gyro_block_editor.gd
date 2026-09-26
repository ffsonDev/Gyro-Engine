class_name GyroBlockEditor
extends Control

const PALETTE_SCENE := preload("res://editor/gyro_palette.tscn")
const EXPR_SCENE := preload("res://editor/gyro_expr_editor.tscn")
const DIALOG_SCENE := preload("res://ui/components/gyro_dialog.tscn")
const DOC_SCENE := preload("res://ui/screens/doc_screen.tscn")
const COLOR_EVENT := Color(0.11, 0.55, 0.62)

signal back_pressed

var doc_screen: DocScreen
var renderer: BlockRenderer
var drag_drop: DragDropController
var undo_redo: UndoRedoManager
var save_mgr: SaveManager
var vars_dialog: VarsDialog
var flow_handler: FlowHandler
var test_runner: TestRunner

var blueprint := GyroEventBlueprint.new()
var project: GyroProject
var current_script: GyroScript
var save_path := ""

var rule_collapsed := {}
var block_collapsed := {}
var last_object_name := ""
var object_counter := 0
var editor_root: Node

var events_vbox: VBoxContainer
var scroll: ScrollContainer
var title_label: Label
var ui_root: Control
var drop_indicator: PanelContainer

var _field_callbacks := {}
var expr_editor: GyroExprEditor
var expr_pick_key := ""
var expr_pick_button: Button
var obj_menu: PopupMenu
var obj_pick_key := ""
var obj_pick_button: Button
var asset_menu: PopupMenu
var asset_pick_key := ""
var asset_pick_button: Button
var asset_pick_kind := ""
var var_pick_key := ""
var var_pick_button: Button

var palette: GyroPalette

var press_active := false
var press_position := Vector2()
var press_item := {}
var press_start := 0
var last_pointer := Vector2()

var _rebuild_timer: Timer
var _rebuild_pending := false
var _merged_cache: GyroEventBlueprint
var _merged_dirty := true
var _rule_sigs := {}

var _menu_overlay: ColorRect = null
var _menu_panel: PanelContainer = null
var timer_menu: PopupMenu
var timer_pick_key := ""
var timer_pick_button: Button

func _setup_timer_menu() -> void:
	timer_menu = PopupMenu.new()
	add_child(timer_menu)
	timer_menu.id_pressed.connect(_on_timer_pick)

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
	_setup_palette()
	_setup_obj_menu()
	_setup_timer_menu()
	_setup_asset_menu()
	apply_lang()
	_rebuild()

func _input(event: InputEvent) -> void:
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

func _open_timer_for(set_callback: Callable, key: String, button: Button) -> void:
	timer_pick_key = key
	timer_pick_button = button
	_field_callbacks[button] = {"resource": button, "key": key, "set_callback": set_callback}
	timer_menu.clear()
	var names := _timer_names()
	if names.is_empty():
		timer_menu.add_item(GyroLang.t("no_timers"), -1)
	else:
		for i in names.size():
			timer_menu.add_item(str(names[i]), i)
	timer_menu.position = button.global_position + Vector2(0, button.size.y)
	timer_menu.popup()

func _on_timer_pick(id: int) -> void:
	if timer_pick_button == null or id < 0:
		return
	var names := _timer_names()
	if id < names.size():
		var n := str(names[id])
		_set_pick_text(timer_pick_button, n)
		var cb: Dictionary = _field_callbacks.get(timer_pick_button, {}) as Dictionary
		if cb.has("set_callback") and cb.set_callback.is_valid():
			undo_redo.push_undo()
			cb.set_callback.call(cb.key, n)
			save_mgr.mark_dirty()

func _timer_names() -> Array:
	var names: Array = []
	if blueprint != null:
		for t in blueprint.timers:
			var tn := str(t.timer_name)
			if tn != "" and not names.has(tn):
				names.append(tn)
	for rule_value in blueprint.rules:
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

func _schedule_rebuild() -> void:
	if not _rebuild_pending:
		_rebuild_pending = true
		_rebuild_timer.start()

func _do_rebuild() -> void:
	_rebuild_pending = false
	_rebuild_diff()

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
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.17, 0.20)
	style.set_corner_radius_all(12)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	_menu_panel.add_theme_stylebox_override("panel", style)
	GyroUI.center(_menu_panel)
	_menu_panel.z_index = 71
	add_child(_menu_panel)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(minf(360.0, get_viewport_rect().size.x - 48.0), 0)
	vbox.add_theme_constant_override("separation", 8)
	_menu_panel.add_child(vbox)
	var hidden: bool = rule_collapsed.get(rule, false) if kind == "rule" else block_collapsed.get(resource, false)
	var dis: bool = bool(resource.get("disabled"))
	_menu_button(vbox, "? " + GyroLang.t("doc"), target, _open_help_for_target, Color(0.4, 0.7, 0.95))
	_menu_button(vbox, GyroLang.t("duplicate"), target, _duplicate_target)
	_menu_button(vbox, GyroLang.t("block_show") if hidden else GyroLang.t("block_hide"), target, _toggle_hide_target)
	_menu_button(vbox, GyroLang.t("block_enable") if dis else GyroLang.t("block_disable"), target, _toggle_disable_target)
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

func _duplicate_target(t: Dictionary) -> void:
	if t.is_empty():
		return
	undo_redo.push_undo()
	var kind: String = str(t.get("kind", ""))
	var resource: Variant = t.get("resource", null)
	var rule: GyroEventRule = t.get("rule", null)
	if kind == "rule":
		var index := blueprint.rules.find(resource)
		var copy := (resource as GyroEventRule).duplicate(true) as GyroEventRule
		blueprint.rules.insert(index + 1, copy)
		_mark_dirty()
		_schedule_rebuild()
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
	_mark_dirty()
	_rebuild_rule_only(rule)

func _toggle_hide_target(t: Dictionary) -> void:
	if t.is_empty():
		return
	var kind: String = str(t.get("kind", ""))
	var resource: Variant = t.get("resource", null)
	var rule: GyroEventRule = t.get("rule", null)
	if kind == "rule":
		rule_collapsed[resource] = not rule_collapsed.get(resource, false)
		_toggle_rule_collapse(resource)
	else:
		block_collapsed[resource] = not block_collapsed.get(resource, false)
		if rule != null:
			_rebuild_rule_only(rule)

func _toggle_disable_target(t: Dictionary) -> void:
	if t.is_empty():
		return
	undo_redo.push_undo()
	var kind: String = str(t.get("kind", ""))
	var resource: Variant = t.get("resource", null)
	var rule: GyroEventRule = t.get("rule", null)
	resource.disabled = not bool(resource.get("disabled"))
	flow_handler.sync_all()
	_mark_dirty()
	if kind == "rule":
		_apply_rule_alpha(rule)
	else:
		_apply_block_alpha(resource)

func _apply_block_alpha(resource: Variant) -> void:
	var panel = renderer.get_block_panel(resource)
	if panel != null:
		panel.modulate.a = 0.45 if bool(resource.get("disabled")) else 1.0

func _apply_rule_alpha(rule: GyroEventRule) -> void:
	var wrapper = drag_drop.rule_wrappers.get(rule)
	if wrapper != null and is_instance_valid(wrapper):
		wrapper.modulate.a = 0.45 if rule.disabled else 1.0

func _confirm_delete(t: Dictionary) -> void:
	var dialog := DIALOG_SCENE.instantiate()
	add_child(dialog)
	dialog.z_index = 72
	dialog.open(GyroLang.t("delete"), GyroLang.t("delete_block_q"), GyroLang.t("delete"), GyroLang.t("cancel"))
	dialog.confirmed.connect(func(): _delete_target(t))
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)

func _delete_target(t: Dictionary) -> void:
	if t.is_empty():
		return
	undo_redo.push_undo()
	var kind: String = str(t.get("kind", ""))
	var resource: Variant = t.get("resource", null)
	var rule: GyroEventRule = t.get("rule", null)
	if kind == "rule":
		blueprint.rules.erase(resource)
		_remove_rule_wrapper(resource)
		_mark_dirty()
		_schedule_rebuild()
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
	_mark_dirty()
	_rebuild_rule_only(rule)

# ===== Rebuild =====
func _rule_signature(rule: GyroEventRule) -> String:
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

func _rebuild_diff() -> void:
	var rules := blueprint.rules
	for rule_key in drag_drop.rule_wrappers.keys().duplicate():
		if not rules.has(rule_key):
			_remove_rule_wrapper(rule_key)
			_rule_sigs.erase(rule_key)
	for i in rules.size():
		var rule: GyroEventRule = rules[i]
		var wrapper = drag_drop.rule_wrappers.get(rule)
		if wrapper == null or not is_instance_valid(wrapper):
			_add_rule_wrapper_at(rule, i)
		else:
			_move_wrapper_to_index(wrapper, i)
		var sig := _rule_signature(rule)
		if str(_rule_sigs.get(rule, "")) != sig:
			_rebuild_rule_only(rule)
	for key in _rule_sigs.keys().duplicate():
		if not rules.has(key):
			_rule_sigs.erase(key)

func _add_rule_wrapper_at(rule: GyroEventRule, index: int) -> VBoxContainer:
	var wrapper: VBoxContainer = renderer.build_event_block(events_vbox, rule, rule_collapsed.get(rule, false))
	_move_wrapper_to_index(wrapper, index)
	drag_drop.register_rule(rule, wrapper)
	drag_drop.register_item({"kind": "rule", "resource": rule, "rule": rule, "panel": wrapper})
	_apply_rule_alpha(rule)
	_rule_sigs[rule] = _rule_signature(rule)
	return wrapper

func _move_wrapper_to_index(wrapper: Control, index: int) -> void:
	if wrapper.get_parent() == null:
		events_vbox.add_child(wrapper)
	if wrapper.get_index() != index:
		events_vbox.move_child(wrapper, index)

func _init_components() -> void:
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
		%VarTypeOption, %VarAddButton, %VarsTitle, %VarsCloseButton,
		%VarsRenameButton, %VarsDeleteButton
	)
	vars_dialog.variable_picked.connect(_pick_variable)
	vars_dialog.variable_added.connect(_add_variable)
	vars_dialog.variable_removed.connect(_remove_variable)
	vars_dialog.variable_renamed.connect(_rename_variable)

	test_runner = TestRunner.new()
	test_runner.setup(self, _merged_blueprint)
	test_runner.stopped.connect(_on_test_stopped)

	expr_editor = EXPR_SCENE.instantiate()
	add_child(expr_editor)
	expr_editor.accepted.connect(_on_expr_accepted)

	var touch_scroll := GyroTouchScroll.new()
	add_child(touch_scroll)
	touch_scroll.setup(scroll, [palette if palette != null else Control.new(), %VarsOverlay, expr_editor])
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
		_mark_dirty()
	)
	renderer.event_pick_requested.connect(_open_event_for)
	renderer.note_changed.connect(func(rule: GyroEventRule, text: String):
		undo_redo.mark_field_focus()
		rule.note = text
		_mark_dirty()
	)
	renderer.collapse_rule_requested.connect(func(rule: GyroEventRule):
		rule_collapsed[rule] = not rule_collapsed.get(rule, false)
		_toggle_rule_collapse(rule)
	)
	renderer.field_focus_entered.connect(func(): undo_redo.mark_field_focus())
	renderer.expr_pick_requested.connect(_open_expr_for)
	renderer.var_pick_requested.connect(_open_vars_for)
	renderer.obj_pick_requested.connect(_open_obj_for)
	renderer.asset_pick_requested.connect(_open_asset_for)

func _is_event_name_taken(name: String, exclude: GyroEventRule) -> bool:
	if project != null:
		for s in project.scripts:
			if s == null or s.blueprint == null:
				continue
			for r in s.blueprint.rules:
				if r != null and r != exclude and r.is_named() and r.event_name == name:
					return true
		return false
	for r in blueprint.rules:
		if r != null and r != exclude and r.is_named() and r.event_name == name:
			return true
	return false

func _rename_variable(old_name: String, new_name: String) -> void:
	if old_name == new_name:
		return
	undo_redo.push_undo()
	if blueprint.variables.has(old_name):
		blueprint.variables[new_name] = blueprint.variables[old_name]
		blueprint.variables.erase(old_name)
	if blueprint.variable_types.has(old_name):
		blueprint.variable_types[new_name] = blueprint.variable_types[old_name]
		blueprint.variable_types.erase(old_name)
	for rule_value in blueprint.rules:
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
	_mark_dirty()
	vars_dialog.rebuild()

func _rename_in_data(data: Dictionary, old_name: String, new_name: String) -> void:
	for key in data.keys():
		var value = data[key]
		if value is String:
			if value == "$var." + old_name:
				data[key] = "$var." + new_name
			elif value == old_name:
				data[key] = new_name

func open_script(proj: GyroProject, script: GyroScript, path: String) -> void:
	project = proj
	current_script = script
	save_path = path

	if script.blueprint == null:
		script.blueprint = GyroEventBlueprint.new()
	blueprint = script.blueprint
	title_label.text = script.script_name
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.clip_contents = true

	rule_collapsed.clear()
	block_collapsed.clear()
	_field_callbacks.clear()
	flow_handler.clear()
	undo_redo.clear()
	_merged_cache = null
	_merged_dirty = true 
	save_mgr.dirty = false
	vars_dialog.set_blueprint(blueprint)
	_rebuild()

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
	if palette != null:
		palette.apply_lang()
	if expr_editor != null:
		expr_editor.apply_lang()
	_rule_sigs.clear()
	_schedule_rebuild()

func _rebuild() -> void:
	_field_callbacks.clear()
	_rule_sigs.clear()
	drag_drop.reset()
	flow_handler.clear()
	renderer.clear_field_cache()
	GyroUI.clear_children(events_vbox)

	for rule in blueprint.rules:
		var wrapper: VBoxContainer = renderer.build_event_block(events_vbox, rule, rule_collapsed.get(rule, false))
		drag_drop.register_rule(rule, wrapper)
		drag_drop.register_item({"kind": "rule", "resource": rule, "rule": rule, "panel": wrapper})
		_apply_rule_alpha(rule)
		_rule_sigs[rule] = _rule_signature(rule)

func _rebuild_rule_only(rule: GyroEventRule) -> void:
	var wrapper = drag_drop.rule_wrappers.get(rule)
	if wrapper == null or not is_instance_valid(wrapper):
		_schedule_rebuild()
		return

	var body_panel = wrapper.get_child(1) as PanelContainer
	if body_panel == null or body_panel.get_child_count() == 0:
		_schedule_rebuild()
		return

	var body = body_panel.get_child(0) as VBoxContainer

	var items_to_remove: Array = []
	for item in drag_drop.drag_items:
		if item.has("rule") and item.rule == rule:
			items_to_remove.append(item)
	for item in items_to_remove:
		drag_drop.drag_items.erase(item)

	GyroUI.clear_children(body)
	renderer._build_rule_body(body, rule)
	_apply_rule_alpha(rule)
	_rule_sigs[rule] = _rule_signature(rule)

func _add_rule_wrapper(rule: GyroEventRule) -> void:
	var collapsed: Variant = rule_collapsed.get(rule, false)
	var wrapper: VBoxContainer = renderer.build_event_block(events_vbox, rule, collapsed)
	drag_drop.register_rule(rule, wrapper)
	drag_drop.register_item({"kind": "rule", "resource": rule, "rule": rule, "panel": wrapper})
	_apply_rule_alpha(rule)
	_rule_sigs[rule] = _rule_signature(rule)

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
	var collapsed: bool = rule_collapsed.get(rule, false)
	body_panel.visible = not collapsed
	var header: Control = wrapper.get_child(0)
	if header != null:
		for child in header.get_children():
			if child is Button and child.get_meta("is_collapse_btn", false):
				GyroUI.set_icon(child,
					"res://ui/icons/chevron_down.svg" if collapsed else "res://ui/icons/chevron_up.svg")

func _drag_register(kind: String, resource: Variant, rule: GyroEventRule, panel: Control, owner_array: Array) -> void:
	drag_drop.register_item({
		"kind": kind, "resource": resource, "rule": rule, "panel": panel,
		"array": owner_array if not owner_array.is_empty() else _array_for(rule, kind)
	})

func _drag_register_flow(action: GyroAction, panel: Control) -> void:
	drag_drop.register_item({"kind": "flow", "action": action, "panel": panel})

func _start_drag_from_rule(rule: GyroEventRule, panel: Control) -> void:
	drag_drop.start_drag("rule", rule, rule, panel)
	drag_drop.set_pointer(last_pointer)

func _start_drag_from_panel(kind: String, resource: Variant, rule: GyroEventRule, panel: Control) -> void:
	drag_drop.start_drag(kind, resource, rule, panel)
	drag_drop.set_pointer(last_pointer)

func _get_array_for(rule: GyroEventRule, kind: String) -> Array:
	return rule.actions if kind == "action" else rule.conditions

func _array_for(rule: GyroEventRule, kind: String) -> Array:
	return _get_array_for(rule, kind)

func _apply_drop(drop: Dictionary) -> void:
	if drop.is_empty():
		return

	if drag_drop.drag_kind == "rule":
		if drop.get("type") != "item":
			return
		var rules: Array = blueprint.rules
		var from_index: int = rules.find(drag_drop.drag_resource)
		var to_index: int = rules.find(drop.get("item").get("resource"))
		if from_index < 0 or to_index < 0:
			return
		if not drop.get("before", false):
			to_index += 1
		undo_redo.push_undo()
		rules.remove_at(from_index)
		if to_index > from_index:
			to_index -= 1
		rules.insert(to_index, drag_drop.drag_resource)
		_mark_dirty()
		var wrapper = drag_drop.rule_wrappers.get(drag_drop.drag_resource)
		if wrapper != null and is_instance_valid(wrapper):
			if wrapper.get_parent() != null:
				wrapper.get_parent().remove_child(wrapper)
			
			events_vbox.add_child(wrapper)
			if to_index >= 0 and to_index < events_vbox.get_child_count():
				events_vbox.move_child(wrapper, to_index)
		return

	var source_array: Array = _find_source_array()
	var target_array: Array = []
	var drop_type: String = drop.get("type", "")

	if drop_type == "item":
		var item_dict: Dictionary = drop.get("item", {})
		target_array = item_dict.get("array", _array_for(drop.get("item").get("rule"), drag_drop.drag_kind))
	elif drop_type == "flow":
		target_array = flow_handler.get_array(drop.get("action"))
	else:
		target_array = _array_for(drop.get("rule"), drag_drop.drag_kind)

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

	undo_redo.push_undo()
	source_array.remove_at(from_index)

	if is_same(source_array, target_array) and to_index > from_index:
		to_index -= 1

	target_array.insert(to_index, drag_drop.drag_resource)
	flow_handler.sync_all()
	_mark_dirty()

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
		for r_value in blueprint.rules:
			var r := r_value as GyroEventRule
			if r != null and r.actions.has(flow_action) and not changed_rules.has(r):
				changed_rules.append(r)
				break

	for r in changed_rules:
		_rebuild_rule_only(r)
	if changed_rules.is_empty():
		_schedule_rebuild()

func _find_source_array() -> Array:
	for entry in drag_drop.drag_items:
		if entry.has("resource") and entry.resource == drag_drop.drag_resource and entry.has("array"):
			return entry.array
	return _array_for(drag_drop.drag_rule, drag_drop.drag_kind)

func _mark_dirty() -> void:
	save_mgr.mark_dirty()
	_merged_dirty = true
	if project != null:
		project.mark_merged_dirty()

func _flush_save() -> void:
	save_mgr.force_save()

func _do_save() -> void:
	flow_handler.sync_all()
	if save_path == "":
		return
	var target: Resource = project if project != null else blueprint
	GyroUI.save_resource(target, save_path)

func _snapshot() -> Dictionary:
	flow_handler.sync_all()
	var rules: Array = []
	for rule_value in blueprint.rules:
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
		var actions: Array = []
		for a_value in rule.actions:
			var a := a_value as GyroAction
			if a == null:
				continue
			actions.append({
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
			"actions": actions
		})
	return {
		"variables": blueprint.variables.duplicate(true),
		"variable_types": blueprint.variable_types.duplicate(true),
		"rules": rules,
		"timers": blueprint.timers.map(func(t):
			return {
				"timer_name": t.timer_name,
				"wait_time": t.wait_time,
				"one_shot": t.one_shot,
				"autostart": t.autostart
			}
	)}

func _sync_resources_in_place(existing: Array, snapshot: Array, make_fn: Callable, same_fn: Callable) -> void:
	while existing.size() > snapshot.size():
		existing.pop_back()
	for i in snapshot.size():
		var d: Dictionary = snapshot[i]
		if i < existing.size() and bool(same_fn.call(existing[i], d)):
			continue
		var created = make_fn.call(d)
		if i < existing.size():
			existing[i] = created
		else:
			existing.append(created)

func _restore(snapshot: Dictionary) -> void:
	blueprint.variables = (snapshot.get("variables", {}) as Dictionary).duplicate(true)
	blueprint.variable_types = (snapshot.get("variable_types", {}) as Dictionary).duplicate(true)

	blueprint.rules.clear()
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
		blueprint.rules.append(rule)

	blueprint.timers.clear()
	for t_value in snapshot.get("timers", []):
		var t_data: Dictionary = t_value as Dictionary
		var t := GyroTimerConfig.new()
		t.timer_name = str(t_data.get("timer_name", ""))
		t.wait_time = float(t_data.get("wait_time", 1.0))
		t.one_shot = bool(t_data.get("one_shot", false))
		t.autostart = bool(t_data.get("autostart", true))
		blueprint.timers.append(t)

	flow_handler.clear()
	_merged_dirty = true
	if project != null:
		project.mark_merged_dirty()
	save_mgr.mark_dirty()
	_rebuild()

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

func _setup_palette() -> void:
	palette = PALETTE_SCENE.instantiate()
	palette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	palette.z_index = 20
	palette.color_for = func(kind: String, type: String) -> Color:
		if kind == "event":
			return COLOR_EVENT
		if kind == "condition":
			return GyroBlocks.CONDITION_COLORS.get(type, Color(0.45, 0.5, 0.3))
		return GyroBlocks.ACTION_COLORS.get(type, Color(0.5, 0.5, 0.5))
	palette.item_down.connect(_on_palette_item)
	add_child(palette)
	palette.visible = false

func _open_palette() -> void:
	palette.apply_lang()
	palette.visible = true

func _on_palette_item(item: Dictionary) -> void:
	palette.close()
	var kind: String = item.kind
	var rule := _last_rule_or_create()
	last_pointer = get_global_mouse_position()
	
	if kind == "event":
		var new_rule := GyroEventRule.new()
		new_rule.event_type = item.type
		if new_rule.is_named():
			var base := "event" if item.type == "custom" else "func"
			var i := 1
			while _is_event_name_taken(base + "_" + str(i), null):
				i += 1
			new_rule.event_name = base + "_" + str(i)
		blueprint.rules.append(new_rule)
		_mark_dirty()
		_schedule_rebuild()
		return
	
	var new_resource: Variant = null
	if kind == "action":
		var action := GyroAction.new()
		action.type = item.type
		var defaults: Dictionary = _default_data(item.type)
		for key in defaults.keys():
			action.data[key] = defaults[key]
		rule.actions.append(action)
		new_resource = action
		if item.type == "CreateObject":
			last_object_name = str(action.data.get("name", ""))
	elif kind == "condition":
		var condition := GyroCondition.new()
		condition.type = item.type
		var defaults: Dictionary = _default_data(item.type)
		for key in defaults.keys():
			condition.data[key] = defaults[key]
		rule.conditions.append(condition)
		new_resource = condition
	
	_mark_dirty()
	_rebuild_rule_only(rule)
	
	var panel = renderer.get_block_panel(new_resource)
	if panel != null and is_instance_valid(panel):
		drag_drop.start_drag(kind, new_resource, rule, panel)
		drag_drop.set_pointer(last_pointer)

var _event_popup: Control
var _event_filter: LineEdit
var _event_list: VBoxContainer
var _event_button: Button
var _event_cb: Callable
var _event_key := ""

func _open_event_for(set_callback: Callable, key: String, button: Button) -> void:
	_event_cb = set_callback
	_event_button = button
	if _event_popup == null:
		_build_event_popup()
	_event_filter.text = ""
	_event_key = key
	_rebuild_event_list("")
	_event_popup.visible = true

func _build_event_popup() -> void:
	_event_popup = Control.new()
	_event_popup.z_index = 45
	_event_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.gui_input.connect(func(e: InputEvent):
		if GyroUI.is_tap(e):
			_event_popup.visible = false
	)
	_event_popup.add_child(overlay)
	var panel := PanelContainer.new()
	GyroUI.center(panel)
	panel.custom_minimum_size = Vector2(minf(420.0, get_viewport_rect().size.x - 48.0), 0)
	_event_popup.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	_event_filter = LineEdit.new()
	_event_filter.placeholder_text = GyroLang.t("search")
	_event_filter.text_changed.connect(func(q: String): _rebuild_event_list(q))
	vbox.add_child(_event_filter)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, GyroUI.sz(300))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(sc)
	_event_list = VBoxContainer.new()
	_event_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_event_list)
	add_child(_event_popup)
	_event_popup.visible = false

func _event_names() -> Array:
	var names: Array = []
	for b in GyroBlocks.BUILTIN_EVENTS:
		names.append(str(b))
	if project != null:
		for s in project.scripts:
			if s == null or s.blueprint == null:
				continue
			for r in s.blueprint.rules:
				if r != null and r.is_named() and r.event_name != "" and not names.has(r.event_name):
					names.append(r.event_name)
	names.sort()
	return names

func _rebuild_event_list(q: String) -> void:
	GyroUI.clear_children(_event_list)
	var ql := q.strip_edges().to_lower()
	for n in _event_names():
		if ql != "" and not str(n).to_lower().contains(ql):
			continue
		var b := Button.new()
		b.text = str(n)
		b.custom_minimum_size = Vector2(0, GyroUI.sz(48))
		b.pressed.connect(func():
			_event_popup.visible = false
			undo_redo.push_undo()
			_event_cb.call(_event_key, n)
			save_mgr.mark_dirty()
			if _event_button != null and is_instance_valid(_event_button):
				_set_pick_text(_event_button, n)
		)
		_event_list.add_child(b)

func _last_rule_or_create() -> GyroEventRule:
	if blueprint.rules.size() > 0:
		return blueprint.rules[blueprint.rules.size() - 1] as GyroEventRule
	var rule := GyroEventRule.new()
	rule.event_type = "ready"
	blueprint.rules.append(rule)
	return rule

func _play() -> void:
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
	if project != null and project.settings != null:
		GyroUI.set_orientation(project.settings.orientation)
	ui_root.visible = false
	test_runner.start(project, save_path)

func _on_test_stopped() -> void:
	ui_root.visible = true
	GyroUI.set_orientation("portrait")

func _open_vars_for(set_callback: Callable, key: String, button: Button, resource: Variant) -> void:
	var_pick_key = key
	var_pick_button = button
	_field_callbacks[button] = {"resource": button, "key": key, "set_callback": set_callback}
	vars_dialog.set_picking(true)
	vars_dialog.open()

func _pick_variable(var_name: String) -> void:
	if var_pick_button != null and is_instance_valid(var_pick_button):
		_set_pick_text(var_pick_button, var_name)
	var cb: Dictionary = _field_callbacks.get(var_pick_button, {}) as Dictionary
	if cb.has("set_callback") and cb.set_callback.is_valid():
		undo_redo.push_undo()
		cb.set_callback.call(cb.key, var_name)
		save_mgr.mark_dirty()
	vars_dialog.set_picking(false)
	vars_dialog.close()

func _add_variable(var_name: String, type_id: int) -> void:
	var raw := var_name.strip_edges()
	if raw.length() > 32:
		raw = raw.substr(0, 32)
	var clean := GyroUI.sanitize_name(raw).replace(" ", "_")
	if GyroUI.is_bad_name(clean):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("enter_correct_variable"))
		return
	if blueprint.variables.has(clean):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("variable_exists") % clean)
		return
	undo_redo.push_undo()
	var type_name := "number" if type_id == 0 else ("text" if type_id == 1 else ("bool" if type_id == 2 else "table"))
	blueprint.variable_types[clean] = type_name
	if type_name == "number":
		blueprint.variables[clean] = 0.0
	elif type_name == "text":
		blueprint.variables[clean] = ""
	elif type_name == "bool":
		blueprint.variables[clean] = false
	else:
		blueprint.variables[clean] = {}
	_mark_dirty()
	vars_dialog.rebuild()

func _remove_variable(var_name: String) -> void:
	var raw := var_name.strip_edges()
	if raw.length() > 32:
		raw = raw.substr(0, 32)
	undo_redo.push_undo()
	blueprint.variables.erase(var_name)
	blueprint.variable_types.erase(var_name)
	_mark_dirty()
	vars_dialog.rebuild()

func _open_expr_for(set_callback: Callable, key: String, button: Button) -> void:
	expr_pick_key = key
	expr_pick_button = button
	_field_callbacks[button] = {"resource": button, "key": key, "set_callback": set_callback}

	var initial := ""
	var raw = button.get_meta("expr_raw", null)
	if raw != null:
		initial = str(raw)

	var names: Array = []
	for k in blueprint.variables.keys():
		names.append(str(k))
	expr_editor.open(initial, names)

func _on_expr_accepted(text: String) -> void:
	if expr_pick_button != null and is_instance_valid(expr_pick_button):
		expr_pick_button.set_meta("expr_raw", text)
		_set_pick_text(expr_pick_button, text)
		var cb: Dictionary = _field_callbacks.get(expr_pick_button, {}) as Dictionary
		if cb.has("set_callback") and cb.set_callback.is_valid():
			undo_redo.push_undo()
			cb.set_callback.call(cb.key, _parse_field(text))
			save_mgr.mark_dirty()
	expr_pick_button = null

func _setup_obj_menu() -> void:
	obj_menu = PopupMenu.new()
	add_child(obj_menu)
	obj_menu.id_pressed.connect(_on_obj_pick)

func _open_obj_for(set_callback: Callable, key: String, button: Button) -> void:
	if obj_menu == null:
		_setup_obj_menu()
	obj_pick_key = key
	obj_pick_button = button
	_field_callbacks[button] = {"resource": button, "key": key, "set_callback": set_callback}

	obj_menu.clear()
	var names := _object_names()
	if names.is_empty():
		obj_menu.add_item(GyroLang.t("no_objects"), -1)
	else:
		for i in names.size():
			obj_menu.add_item(str(names[i]), i)

	obj_menu.position = button.global_position + Vector2(0, button.size.y)
	obj_menu.popup()

func _on_obj_pick(id: int) -> void:
	if obj_pick_button == null or id < 0:
		return
	var names := _object_names()
	if id < names.size():
		var n := str(names[id])
		_set_pick_text(obj_pick_button, n)
		var cb: Dictionary = _field_callbacks.get(obj_pick_button, {}) as Dictionary
		if cb.has("set_callback") and cb.set_callback.is_valid():
			undo_redo.push_undo()
			cb.set_callback.call(cb.key, n)
			save_mgr.mark_dirty()

func _setup_asset_menu() -> void:
	asset_menu = PopupMenu.new()
	add_child(asset_menu)
	asset_menu.id_pressed.connect(_on_asset_pick)

func _open_asset_for(set_callback: Callable, key: String, button: Button, kind: String) -> void:
	if asset_menu == null:
		_setup_asset_menu()
	asset_pick_key = key
	asset_pick_button = button
	asset_pick_kind = kind
	_field_callbacks[button] = {"resource": button, "key": key, "set_callback": set_callback}

	asset_menu.clear()
	var list := _assets_of_kind(kind)
	if list.is_empty():
		asset_menu.add_item(GyroLang.t("no_assets"), -1)
	else:
		for i in list.size():
			asset_menu.add_item(str((list[i] as GyroAsset).asset_name), i)

	asset_menu.position = button.global_position + Vector2(0, button.size.y)
	asset_menu.popup()

func _on_asset_pick(id: int) -> void:
	if asset_pick_button == null or id < 0:
		return
	var list := _assets_of_kind(asset_pick_kind)
	if id < list.size():
		var a: GyroAsset = list[id] as GyroAsset
		_set_pick_text(asset_pick_button, a.asset_name)
		var cb: Dictionary = _field_callbacks.get(asset_pick_button, {}) as Dictionary
		if cb.has("set_callback") and cb.set_callback.is_valid():
			undo_redo.push_undo()
			cb.set_callback.call(cb.key, a.id)
			_mark_dirty()

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
		return value
	if value is Dictionary or value is Array:
		return JSON.stringify(value)
	if value is float:
		var f: float = float(value)
		if f == floorf(f):
			return str(int(f))
		return str(f)
	return str(value)

func _asset_display(ref: Variant) -> String:
	var s := str(ref)
	if s == "" or project == null:
		return s
	for v in project.assets:
		var a: GyroAsset = v as GyroAsset
		if a != null and (a.id == s or a.asset_name == s):
			return a.asset_name
	return s

func _object_names() -> Array:
	var names: Array = []
	for rule_value in blueprint.rules:
		var rule := rule_value as GyroEventRule
		if rule == null:
			continue
		for a_value in rule.actions:
			var a := a_value as GyroAction
			if a == null:
				continue
			if a.type == "CreateObject" or a.type == "CreateInput" or a.type == "CreateSlider" or a.type == "CreateToggle" or a.type == "CreateGroup" or a.type == "CreateSpriteAnim" or a.type == "CreateParticles" or a.type == "CreateCircle":
				var n := str(a.data.get("name", ""))
				if n != "" and not names.has(n):
					names.append(n)
	return names

func _assets_of_kind(kind: String) -> Array:
	var result: Array = []
	if project == null:
		return result
	for v in project.assets:
		var a: GyroAsset = v as GyroAsset
		if a != null and a.kind == kind:
			result.append(a)
	return result

func _merged_blueprint() -> GyroEventBlueprint:
	if project == null:
		return blueprint
	if _merged_dirty or _merged_cache == null:
		_merged_cache = project.merge_blueprints()
		_merged_dirty = false
	return _merged_cache

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
			object_counter += 1
			return {"name": "obj" + str(object_counter), "type": "rect", "x": 100, "y": 100, "w": 80, "h": 80, "color": "#ffffff", "radius": 0, "text": "", "texture": "", "font": 24, "variable": ""}
		"DeleteObject":
			return {"node": last_object_name}
		"MoveNode":
			return {"node": last_object_name, "mode": "delta", "x": 10, "y": 0}
		"SetNodeProperty":
			return {"node": last_object_name, "property": "position", "x": 100, "y": 100, "value": ""}
		"SetSize":
			return {"node": last_object_name, "w": 80, "h": 80}
		"SetText":
			return {"node": last_object_name, "text": GyroLang.t("default_text")}
		"SetVisible":
			return {"node": last_object_name, "on": true}
		"SetOpacity":
			return {"node": last_object_name, "value": 100}
		"SetRotation":
			return {"node": last_object_name, "mode": "set", "angle": 0}
		"SetScale":
			return {"node": last_object_name, "percent": 100, "x": 100, "y": 100}
		"ChangeLayer":
			return {"node": last_object_name, "dir": 1}
		"SetFontSize":
			return {"node": last_object_name, "size": 24}
		"SetColor":
			return {"node": last_object_name, "color": "#ffffff"}
		"SetTextAlign":
			return {"node": last_object_name, "align": "center"}
		"SetTexture":
			return {"node": last_object_name, "texture": ""}
		"SetCornerRadius":
			return {"node": last_object_name, "radius": 10}
		"SetPivot":
			return {"node": last_object_name, "x": 50, "y": 50}
		"SetObjectMeta":
			return {"node": last_object_name, "key": "hp", "value": 0}
		"FaceObject":
			return {"node": last_object_name, "target": last_object_name}
		"PlayAnimation":
			return {"node": last_object_name, "animation": "idle"}
		"StopAnimation":
			return {"node": last_object_name}
		"SetSolid":
			return {"node": last_object_name, "on": true}
		"SetSensor":
			return {"node": last_object_name, "on": true}
		"SetDraggable":
			return {"node": last_object_name, "on": true}
		"Spawn":
			return {"scene": "", "parent": "", "x": 0, "y": 0, "variable": ""}
		"CreateGroup":
			object_counter += 1
			return {"name": "group" + str(object_counter), "x": 0, "y": 0, "w": 480, "h": 720}
		"AddToGroup":
			return {"node": last_object_name, "group": ""}
		"CreateCircle":
			object_counter += 1
			return {"name": "circle" + str(object_counter), "radius": 50, "color": "#ffffff", "border_w": 0, "border_color": "#ffffff", "x": 100, "y": 100}
		"CreateLine":
			object_counter += 1
			return {"name": "line" + str(object_counter), "x": 0, "y": 0, "x2": 100, "y2": 100, "color": "#ffffff", "width": 4}
		"SetGradient":
			return {"node": last_object_name, "mode": "linear", "color1": "#ffffff", "color2": "#000000"}
		"SetBorder":
			return {"node": last_object_name, "color": "#ffffff", "width": 4}
		"CreateSpriteAnim":
			object_counter += 1
			return {"name": "anim" + str(object_counter), "sprite": "", "frame_w": 32, "frame_h": 32, "count": 4, "fps": 8, "anim": "default", "x": 100, "y": 100}
		"SetFrame":
			return {"node": last_object_name, "frame": 0}
		"CreateParticles":
			object_counter += 1
			return {"name": "fx" + str(object_counter), "preset": "snow", "x": 240, "y": 0}
		"SetParticlesParam":
			return {"node": "", "param": "speed", "value": 100}
		"DeleteParticles":
			return {"node": ""}
		"SetParallax":
			return {"node": last_object_name, "x": 50, "y": 50}
		"SetVelocity":
			return {"node": last_object_name, "x": 0, "y": 0}
		"AddVelocity":
			return {"node": last_object_name, "x": 0, "y": -700}
		"SetGravity":
			return {"node": last_object_name, "value": 1500}
		"SetGlobalGravity":
			return {"value": 1500}
		"SetPhysicsPaused":
			return {"on": true}
		"SetVariable":
			return {"name": _first_var(), "value": 0}
		"AddToVariable":
			return {"name": _first_var(), "amount": 1}
		"SetTableValue":
			return {"name": _first_var(), "key": "KEY", "value": 0}
		"GetTableValue":
			return {"name": _first_var(), "key": "KEY", "variable": _first_var()}
		"InsertArrayValue":
			return {"name": _first_var(), "index": 0, "value": 0}
		"RemoveArrayValue":
			return {"name": _first_var(), "index": 0}
		"OverwriteTable":
			return {"name": _first_var(), "json": "{}"}
		"ForEachTable":
			return {"name": _first_var(), "element": "item", "keyvar": "k", "blocks": []}
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
			return {"node": last_object_name, "smooth": 5}
		"TweenPosition":
			return {"node": last_object_name, "x": 100, "y": 100, "time": 1.0, "ease": "linear"}
		"TweenScale":
			return {"node": last_object_name, "percent": 150, "time": 1.0, "ease": "out"}
		"TweenRotation":
			return {"node": last_object_name, "angle": 360, "time": 1.0, "ease": "linear"}
		"TweenOpacity":
			return {"node": last_object_name, "value": 0, "time": 1.0, "ease": "linear"}
		"StopTween":
			return {"node": last_object_name}
		"AddTag":
			return {"node": last_object_name, "tag": "enemy"}
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
			object_counter += 1
			return {"name": "input" + str(object_counter), "text": "", "multiline": false, "secret": false, "x": 100, "y": 100, "w": 240}
		"CreateSlider":
			object_counter += 1
			return {"name": "slider" + str(object_counter), "vertical": false, "value": 50, "x": 100, "y": 100}
		"CreateToggle":
			object_counter += 1
			return {"name": "toggle" + str(object_counter), "on": false, "x": 100, "y": 100}
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
			return {"node": last_object_name, "anchor": "c"}
		_:
			return {}

func _first_var() -> String:
	var keys := blueprint.variables.keys()
	if keys.is_empty():
		return "var"
	return str(keys[0])

func add_move_node_action(obj_name: String, pos: Vector2) -> void:
	var ready_rule: GyroEventRule = null
	for r in blueprint.rules:
		if r.event_type == "ready" and r.event_name == "":
			ready_rule = r
			break
	
	if ready_rule == null:
		ready_rule = GyroEventRule.new()
		ready_rule.event_type = "ready"
		blueprint.rules.append(ready_rule)
	
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
		
	_mark_dirty()
	_rebuild_rule_only(ready_rule)
