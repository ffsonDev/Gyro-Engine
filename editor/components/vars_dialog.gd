class_name VarsDialog
extends RefCounted

signal variable_picked(name: String)
signal variable_added(name: String)
signal variable_removed(name: String)
signal variable_renamed(old_name: String, new_name: String)
signal table_picked(name: String)
signal table_added(name: String)
signal table_removed(name: String)

var overlay: ColorRect
var panel: PanelContainer
var list: ScrollContainer
var name_edit: LineEdit
var add_button: Button
var title_label: Label
var close_button: Button
var rename_button: Button
var delete_button: Button
var _blueprint: GyroEventBlueprint
var _selected_var := ""
var _row_buttons := {}
var _scroll_container: ScrollContainer
var _picking := false
var _tables_mode := false
var _list_inner: VBoxContainer
var _last_tap_var := ""
var _last_tap_time := 0
var _empty_hint: Label

func setup(
	overlay_node: ColorRect,
	panel_node: PanelContainer,
	list_node: ScrollContainer,
	name_node: LineEdit,
	add_node: Button,
	title_node: Label,
	close_node: Button,
	rename_node: Button = null,
	delete_node: Button = null
) -> void:
	overlay = overlay_node
	panel = panel_node
	list = list_node
	name_edit = name_node
	add_button = add_node
	title_label = title_node
	close_button = close_node
	rename_button = rename_node
	delete_button = delete_node
	_list_inner = null
	for child in list_node.get_children():
		if child is VBoxContainer:
			_list_inner = child
			break
	if _list_inner == null:
		_list_inner = VBoxContainer.new()
		_list_inner.add_theme_constant_override("separation", DesignTokens.SPACING_SM)
		list_node.add_child(_list_inner)
	_list_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_container = list_node
	_empty_hint = Label.new()
	_empty_hint.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_MUTED)
	_empty_hint.add_theme_font_size_override("font_size", GyroUI.fs(16))
	_empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_hint.visible = false
	var list_parent := list_node.get_parent()
	if list_parent is VBoxContainer:
		list_parent.add_child(_empty_hint)
		list_parent.move_child(_empty_hint, list_node.get_index())
	else:
		_list_inner.add_child(_empty_hint)
	add_button.pressed.connect(_on_add)
	close_button.pressed.connect(close)
	if rename_button != null:
		rename_button.pressed.connect(_on_rename)
		rename_button.disabled = true
	if delete_button != null:
		delete_button.pressed.connect(_on_delete_selected)
		delete_button.disabled = true
	overlay.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event):
			close()
	)

func set_blueprint(bp: GyroEventBlueprint) -> void:
	_blueprint = bp

func set_picking(on: bool, for_table: bool = false) -> void:
	_picking = on
	if on:
		_tables_mode = for_table
	if rename_button != null:
		rename_button.disabled = on
		rename_button.visible = true
	if delete_button != null:
		delete_button.disabled = on
		delete_button.visible = true
	_update_action_buttons()

func open(for_tables: bool = false) -> void:
	_tables_mode = for_tables
	if title_label != null:
		title_label.text = GyroLang.t("section.tables") if _tables_mode else GyroLang.t("variables")
	if name_edit != null:
		name_edit.placeholder_text = GyroLang.t("name_placeholder")
		name_edit.max_length = 32
	if _empty_hint != null:
		_empty_hint.text = GyroLang.t("tables_empty_hint") if _tables_mode else GyroLang.t("variables_empty_hint")
	overlay.visible = true
	panel.visible = true
	rebuild()

func close() -> void:
	overlay.visible = false
	panel.visible = false
	_selected_var = ""
	_last_tap_var = ""
	_picking = false
	_tables_mode = false
	_update_action_buttons()

func rebuild() -> void:
	GyroUI.clear_children(_list_inner)
	_row_buttons.clear()
	_selected_var = ""
	_update_action_buttons()
	var source: Dictionary = _blueprint.tables if _tables_mode else _blueprint.variables
	var is_empty := _blueprint == null or source.is_empty()
	if _empty_hint != null:
		_empty_hint.visible = is_empty
	if is_empty:
		return
	for key in source.keys():
		_add_row(str(key))

func _add_row(var_name: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.SPACING_SM)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_list_inner.add_child(row)
	var pick := Button.new()
	pick.text = _display_name(var_name)
	pick.clip_text = true
	pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.custom_minimum_size = Vector2(0, GyroUI.sz(48))
	pick.add_theme_font_size_override("font_size", GyroUI.fs(18))
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = DesignTokens.COLOR_SURFACE_1
	btn_style.set_corner_radius_all(DesignTokens.RADIUS_MD)
	btn_style.content_margin_left = DesignTokens.SPACING_MD
	btn_style.content_margin_right = DesignTokens.SPACING_MD
	btn_style.content_margin_top = DesignTokens.SPACING_SM
	btn_style.content_margin_bottom = DesignTokens.SPACING_SM
	btn_style.border_width_bottom = 1
	btn_style.border_color = DesignTokens.COLOR_BORDER
	pick.add_theme_stylebox_override("normal", btn_style)
	var hover_style := btn_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = DesignTokens.COLOR_SURFACE_2
	pick.add_theme_stylebox_override("hover", hover_style)
	var pressed_style := btn_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = DesignTokens.COLOR_ACCENT_SOFT
	pressed_style.border_color = DesignTokens.COLOR_ACCENT
	pick.add_theme_stylebox_override("pressed", pressed_style)
	pick.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
	pick.pressed.connect(func(): _on_var_clicked(var_name, pick))
	row.add_child(pick)
	_row_buttons[var_name] = pick

func _display_name(raw: String) -> String:
	if raw.length() > 24:
		return raw.substr(0, 23) + "…"
	return raw

func _on_var_clicked(var_name: String, button: Button) -> void:
	if _picking:
		var now := Time.get_ticks_msec()
		if _last_tap_var == var_name and now - _last_tap_time < 400:
			_last_tap_var = ""
			if _tables_mode:
				table_picked.emit(var_name)
			else:
				variable_picked.emit(var_name)
			close()
			return
		_last_tap_var = var_name
		_last_tap_time = now
	_select_variable(var_name, button)

func _select_variable(var_name: String, button: Button) -> void:
	_selected_var = var_name
	for name in _row_buttons.keys():
		var btn = _row_buttons[name]
		if not is_instance_valid(btn):
			continue
		var normal_style := StyleBoxFlat.new()
		normal_style.bg_color = DesignTokens.COLOR_SURFACE_1
		normal_style.set_corner_radius_all(DesignTokens.RADIUS_MD)
		normal_style.border_width_bottom = 1
		normal_style.border_color = DesignTokens.COLOR_BORDER
		btn.add_theme_stylebox_override("normal", normal_style)
		btn.add_theme_stylebox_override("hover", normal_style)
		btn.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
	if is_instance_valid(button):
		var selected_style := StyleBoxFlat.new()
		selected_style.bg_color = DesignTokens.COLOR_ACCENT_SOFT
		selected_style.set_corner_radius_all(DesignTokens.RADIUS_MD)
		selected_style.border_width_bottom = 2
		selected_style.border_color = DesignTokens.COLOR_BORDER
		button.add_theme_stylebox_override("normal", selected_style)
		button.add_theme_stylebox_override("hover", selected_style)
		button.add_theme_color_override("font_color", DesignTokens.COLOR_ACCENT_HOVER)
	_update_action_buttons()

func _update_action_buttons() -> void:
	var has_selection := _selected_var != ""
	if rename_button != null:
		rename_button.disabled = not has_selection
	if delete_button != null:
		delete_button.disabled = not has_selection

func _on_delete_selected() -> void:
	if _selected_var == "":
		return
	if _tables_mode:
		table_removed.emit(_selected_var)
	else:
		variable_removed.emit(_selected_var)
	_selected_var = ""
	_update_action_buttons()
	rebuild()

func _on_rename() -> void:
	if _selected_var == "":
		return
	var dialog_scene := preload("res://ui/components/gyro_input_dialog.tscn")
	var dialog := dialog_scene.instantiate()
	var parent: Node = overlay.get_parent()
	if parent != null:
		parent.add_child(dialog)
	dialog.z_index = 50
	dialog.open(
		GyroLang.t("rename_variable"),
		GyroLang.t("new_name_placeholder"),
		_selected_var,
		GyroLang.t("ok"),
		GyroLang.t("cancel")
	)
	dialog.confirmed_text.connect(func(new_name: String):
		dialog.queue_free()
		var raw := new_name.strip_edges()
		if raw.length() > 32:
			raw = raw.substr(0, 32)
		var clean := GyroUI.sanitize_name(raw).replace(" ", "_")
		if GyroUI.is_bad_name(clean):
			GyroUI.alert(parent as Control, GyroLang.t("error"), GyroLang.t("enter_correct_variable"))
			return
		if clean == _selected_var:
			return
		var source: Dictionary = _blueprint.tables if _tables_mode else _blueprint.variables
		if source.has(clean):
			GyroUI.alert(parent as Control, GyroLang.t("error"), GyroLang.t("variable_exists") % clean)
			return
		variable_renamed.emit(_selected_var, clean)
		_selected_var = ""
		_update_action_buttons()
		rebuild()
	)

func _on_add() -> void:
	if name_edit == null:
		return
	var raw := name_edit.text.strip_edges()
	if raw.length() > 32:
		raw = raw.substr(0, 32)
	if _tables_mode:
		table_added.emit(raw)
	else:
		variable_added.emit(raw)
	name_edit.text = ""
