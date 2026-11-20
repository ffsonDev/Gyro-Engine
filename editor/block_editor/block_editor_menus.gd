class_name BlockEditorMenus
extends RefCounted

var editor: GyroBlockEditor
var state: BlockEditorState
var undo_redo: UndoRedoManager
var save_mgr: SaveManager
var vars_dialog: VarsDialog
var expr_editor: GyroExprEditor

var color_picker_overlay: ColorRect
var color_picker_panel: PanelContainer
var color_picker: ColorPicker
var color_pick_set_cb: Callable
var color_pick_key: String = ""
var color_pick_button: Button

var _event_popup: Control
var _event_filter: LineEdit
var _event_list: VBoxContainer
var _event_button: Button
var _event_cb: Callable
var _event_key: String = ""

var obj_menu: PopupMenu
var obj_pick_key: String = ""
var obj_pick_button: Button

var asset_menu: PopupMenu
var asset_pick_key: String = ""
var asset_pick_button: Button
var asset_pick_kind: String = ""

var timer_menu: PopupMenu
var timer_pick_key: String = ""
var timer_pick_button: Button

var expr_pick_key: String = ""
var expr_pick_button: Button

var var_pick_key: String = ""
var var_pick_button: Button

var palette: GyroPalette

func _init(ed: GyroBlockEditor, st: BlockEditorState, ur: UndoRedoManager, sm: SaveManager, vd: VarsDialog, ee: GyroExprEditor) -> void:
	editor = ed
	state = st
	undo_redo = ur
	save_mgr = sm
	vars_dialog = vd
	expr_editor = ee
	_build_color_picker()
	_build_event_popup()
	_setup_obj_menu()
	_setup_asset_menu()
	_setup_timer_menu()

func _build_color_picker() -> void:
	color_picker_overlay = ColorRect.new()
	color_picker_overlay.color = Color(0, 0, 0, 0.55)
	color_picker_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color_picker_overlay.visible = false
	color_picker_overlay.z_index = 55
	color_picker_overlay.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event):
			close_color_picker()
	)
	editor.add_child(color_picker_overlay)
	color_picker_panel = PanelContainer.new()
	GyroUI.apply_glass_style(color_picker_panel)
	color_picker_panel.custom_minimum_size = Vector2(minf(220.0, editor.get_viewport_rect().size.x - 32.0), 0)
	color_picker_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	color_picker_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	GyroUI.center(color_picker_panel)
	color_picker_panel.visible = false
	color_picker_panel.z_index = 56
	editor.add_child(color_picker_panel)
	color_picker = ColorPicker.new()
	color_picker.color_mode = ColorPicker.MODE_RGB
	color_picker.edit_alpha = false
	color_picker.deferred_mode = false
	color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_picker.color_changed.connect(_on_color_changed)
	color_picker_panel.add_child(color_picker)

func _on_color_changed(c: Color) -> void:
	if color_pick_button == null or not is_instance_valid(color_pick_button):
		return
	var hex := c.to_html(false).to_upper()
	var color_str := "#" + hex
	editor._set_pick_text(color_pick_button, color_str)
	if color_pick_set_cb.is_valid():
		color_pick_set_cb.call(color_pick_key, color_str)
	save_mgr.mark_dirty()

func open_color_picker(set_callback: Callable, key: String, button: Button, initial_color: String) -> void:
	color_pick_set_cb = set_callback
	color_pick_key = key
	color_pick_button = button
	var hex := initial_color.strip_edges().trim_prefix("#")
	if hex.length() == 6:
		var valid := true
		for ch in hex:
			if not (ch in "0123456789abcdefABCDEF"):
				valid = false
				break
		if not valid:
			hex = "ffffff"
	else:
		hex = "ffffff"
	color_picker.color = Color("#" + hex)
	color_picker_overlay.visible = true
	color_picker_panel.visible = true

func close_color_picker() -> void:
	color_picker_overlay.visible = false
	color_picker_panel.visible = false
	color_pick_button = null
	color_pick_set_cb = Callable()
	color_pick_key = ""

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
	panel.custom_minimum_size = Vector2(minf(420.0, editor.get_viewport_rect().size.x - 48.0), 0)
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
	var ts := GyroTouchScroll.new()
	editor.add_child(ts)
	ts.setup(sc)
	editor.add_child(_event_popup)
	_event_popup.visible = false

func _rebuild_event_list(q: String) -> void:
	GyroUI.clear_children(_event_list)
	var ql := q.strip_edges().to_lower()
	for n in editor._event_names():
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
				editor._set_pick_text(_event_button, n)
		)
		_event_list.add_child(b)

func open_event_for(set_callback: Callable, key: String, button: Button) -> void:
	_event_cb = set_callback
	_event_button = button
	_event_filter.text = ""
	_event_key = key
	_rebuild_event_list("")
	_event_popup.visible = true

func _setup_obj_menu() -> void:
	obj_menu = PopupMenu.new()
	editor.add_child(obj_menu)
	obj_menu.id_pressed.connect(_on_obj_pick)

func open_obj_for(set_callback: Callable, key: String, button: Button) -> void:
	obj_pick_key = key
	obj_pick_button = button
	editor._field_callbacks[button] = {"resource": button, "key": key, "set_callback": set_callback}
	obj_menu.clear()
	var names := editor._object_names()
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
	var names := editor._object_names()
	if id < names.size():
		var n := str(names[id])
		editor._set_pick_text(obj_pick_button, n)
		undo_redo.push_undo()
		var cb: Dictionary = editor._field_callbacks.get(obj_pick_button, {}) as Dictionary
		if cb.has("set_callback") and cb.set_callback.is_valid():
			cb.set_callback.call(cb.key, n)
			save_mgr.mark_dirty()

func _setup_asset_menu() -> void:
	asset_menu = PopupMenu.new()
	editor.add_child(asset_menu)
	asset_menu.id_pressed.connect(_on_asset_pick)

func open_asset_for(set_callback: Callable, key: String, button: Button, kind: String) -> void:
	asset_pick_key = key
	asset_pick_button = button
	asset_pick_kind = kind
	editor._field_callbacks[button] = {"resource": button, "key": key, "set_callback": set_callback}
	asset_menu.clear()
	var list := editor._assets_of_kind(kind)
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
	var list := editor._assets_of_kind(asset_pick_kind)
	if id < list.size():
		var a: GyroAsset = list[id] as GyroAsset
		editor._set_pick_text(asset_pick_button, a.asset_name)
		undo_redo.push_undo()
		var cb: Dictionary = editor._field_callbacks.get(asset_pick_button, {}) as Dictionary
		if cb.has("set_callback") and cb.set_callback.is_valid():
			cb.set_callback.call(cb.key, a.id)
			state.mark_dirty()

func _setup_timer_menu() -> void:
	timer_menu = PopupMenu.new()
	editor.add_child(timer_menu)
	timer_menu.id_pressed.connect(_on_timer_pick)

func open_timer_for(set_callback: Callable, key: String, button: Button) -> void:
	timer_pick_key = key
	timer_pick_button = button
	editor._field_callbacks[button] = {"resource": button, "key": key, "set_callback": set_callback}
	timer_menu.clear()
	var names := editor._timer_names()
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
	var names := editor._timer_names()
	if id < names.size():
		var n := str(names[id])
		editor._set_pick_text(timer_pick_button, n)
		undo_redo.push_undo()
		var cb: Dictionary = editor._field_callbacks.get(timer_pick_button, {}) as Dictionary
		if cb.has("set_callback") and cb.set_callback.is_valid():
			cb.set_callback.call(cb.key, n)
			save_mgr.mark_dirty()

func setup_palette() -> void:
	palette = preload("res://editor/gyro_palette.tscn").instantiate()
	palette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	palette.z_index = 20
	palette.color_for = func(kind: String, type: String) -> Color:
		if kind == "custom":
			var cb := GyroCustomRegistry.find_block(editor.state.project, type)
			return cb.color if cb != null else Color(0.35, 0.35, 0.40)
		if kind == "event":
			return Color(0.11, 0.55, 0.62)
		if kind == "condition":
			return GyroBlocks.CONDITION_COLORS.get(type, Color(0.45, 0.5, 0.3))
		return GyroBlocks.ACTION_COLORS.get(type, Color(0.5, 0.5, 0.5))
	palette.item_down.connect(_on_palette_item)
	palette.item_drag_requested.connect(_on_palette_item_drag)
	editor.add_child(palette)
	palette.visible = false

func _on_palette_item(item: Dictionary) -> void:
	palette.close()
	_insert_item(item)

func _on_palette_item_drag(item: Dictionary, pos: Vector2) -> void:
	palette.close()
	editor.last_pointer = pos
	var res := _insert_item(item)
	if res.is_empty():
		return
	var panel: Control = res.get("panel", null)
	editor.drag_drop.start_drag(str(res.kind), res.resource, res.rule, panel)
	editor.drag_drop.set_pointer(pos)

func _insert_item(item: Dictionary) -> Dictionary:
	var kind: String = str(item.kind)
	if kind == "event":
		var new_rule := GyroEventRule.new()
		new_rule.event_type = str(item.type)
		if new_rule.is_named():
			var base := "event" if str(item.type) == "custom" else "func"
			var i := 1
			while editor._is_event_name_taken(base + "_" + str(i), null):
				i += 1
			new_rule.event_name = base + "_" + str(i)
		state.blueprint.rules.append(new_rule)
		state.mark_dirty()
		editor.rebuild.rebuild()
		return {"kind": "rule", "resource": new_rule, "rule": new_rule, "panel": editor.drag_drop.rule_wrappers.get(new_rule, null)}
	var rule := editor._last_rule_or_create()
	if kind == "custom":
		var def := GyroCustomRegistry.find_block(state.project, str(item.type))
		if def == null:
			return {}
		var caction := GyroAction.new()
		caction.type = "custom:" + str(item.type)
		for f in def.fields:
			caction.data[str(f.get("key", ""))] = str(f.get("default", ""))
		rule.actions.insert(rule.actions.size(), caction)
		state.mark_dirty()
		editor.rebuild.rebuild_rule_only(rule)
		return {"kind": "action", "resource": caction, "rule": rule, "panel": editor.renderer.get_block_panel(caction)}
	if kind == "action":
		var action := GyroAction.new()
		action.type = str(item.type)
		var defaults: Dictionary = editor._default_data(str(item.type))
		for key in defaults.keys():
			action.data[key] = defaults[key]
		rule.actions.insert(rule.actions.size(), action)
		if action.type == "CreateObject":
			state.last_object_name = str(action.data.get("name", ""))
		state.mark_dirty()
		editor.rebuild.rebuild_rule_only(rule)
		return {"kind": "action", "resource": action, "rule": rule, "panel": editor.renderer.get_block_panel(action)}
	if kind == "condition":
		var condition := GyroCondition.new()
		condition.type = str(item.type)
		var defaults: Dictionary = editor._default_data(str(item.type))
		for key in defaults.keys():
			condition.data[key] = defaults[key]
		rule.conditions.insert(rule.conditions.size(), condition)
		state.mark_dirty()
		editor.rebuild.rebuild_rule_only(rule)
		return {"kind": "condition", "resource": condition, "rule": rule, "panel": editor.renderer.get_block_panel(condition)}
	return {}
