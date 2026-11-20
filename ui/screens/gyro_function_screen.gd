class_name GyroFunctionScreen
extends Control

signal back_requested

var project: GyroProject
var _list_panel: VBoxContainer
var _edit_panel: VBoxContainer
var _list: VBoxContainer
var _title: Label
var _name_edit: LineEdit
var _params_edit: LineEdit
var _expr_edit: LineEdit
var _test_box: VBoxContainer
var _result: Label
var _hint: Label
var _expr_editor: GyroExprEditor
var _current: GyroCustomFunction = null
var _test_edits: Array = []

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = DesignTokens.COLOR_SURFACE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.z_index = -1
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 20
	root.offset_top = 16
	root.offset_right = -20
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)
	var back := GyroUI.icon_button("res://ui/icons/arrow_left.svg", GyroUI.fs(30))
	back.pressed.connect(_on_back)
	header.add_child(back)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", GyroUI.fs(28))
	header.add_child(_title)
	_build_list(root)
	_build_edit(root)
	_expr_editor = preload("res://editor/gyro_expr_editor.tscn").instantiate()
	add_child(_expr_editor)
	_expr_editor.accepted.connect(func(text: String):
		_expr_edit.text = text
	)
	apply_lang()
	_show_list()

func _build_list(root: VBoxContainer) -> void:
	_list_panel = VBoxContainer.new()
	_list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_panel.add_theme_constant_override("separation", 10)
	root.add_child(_list_panel)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_MUTED)
	_hint.add_theme_font_size_override("font_size", GyroUI.fs(14))
	_list_panel.add_child(_hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_panel.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	var ts := GyroTouchScroll.new()
	add_child(ts)
	ts.setup(scroll)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	_list_panel.add_child(bottom)
	var add_btn := Button.new()
	add_btn.custom_minimum_size = Vector2(0, GyroUI.sz(64))
	add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_btn.pressed.connect(func(): _open_edit(null))
	add_btn.set_meta("lang_key", "function_new")
	bottom.add_child(add_btn)
	var import_btn := Button.new()
	import_btn.custom_minimum_size = Vector2(0, GyroUI.sz(64))
	import_btn.pressed.connect(_import)
	import_btn.set_meta("lang_key", "import")
	bottom.add_child(import_btn)

func _build_edit(root: VBoxContainer) -> void:
	_edit_panel = VBoxContainer.new()
	_edit_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_edit_panel.add_theme_constant_override("separation", 10)
	root.add_child(_edit_panel)
	_name_edit = LineEdit.new()
	_name_edit.set_meta("lang_key", "function_name")
	_edit_panel.add_child(_name_edit)
	_params_edit = LineEdit.new()
	_params_edit.set_meta("lang_key", "function_params")
	_params_edit.text_changed.connect(func(_t: String): _rebuild_test_fields())
	_edit_panel.add_child(_params_edit)
	var expr_row := HBoxContainer.new()
	expr_row.add_theme_constant_override("separation", 8)
	_edit_panel.add_child(expr_row)
	_expr_edit = LineEdit.new()
	_expr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_expr_edit.set_meta("lang_key", "function_expression")
	expr_row.add_child(_expr_edit)
	var body_btn := Button.new()
	body_btn.text = "…"
	body_btn.custom_minimum_size = Vector2(GyroUI.sz(56), 0)
	body_btn.pressed.connect(_open_expr_editor)
	expr_row.add_child(body_btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_edit_panel.add_child(scroll)
	_test_box = VBoxContainer.new()
	_test_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_test_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_test_box)
	var ts2 := GyroTouchScroll.new()
	add_child(ts2)
	ts2.setup(scroll)
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.add_theme_font_size_override("font_size", GyroUI.fs(16))
	_edit_panel.add_child(_result)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_edit_panel.add_child(row)
	var test_btn := Button.new()
	test_btn.custom_minimum_size = Vector2(0, GyroUI.sz(64))
	test_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	test_btn.pressed.connect(_run_test)
	test_btn.set_meta("lang_key", "function_test")
	row.add_child(test_btn)
	var save_btn := Button.new()
	save_btn.custom_minimum_size = Vector2(0, GyroUI.sz(64))
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_save_current)
	save_btn.set_meta("lang_key", "save")
	row.add_child(save_btn)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	_edit_panel.add_child(row2)
	var export_btn := Button.new()
	export_btn.custom_minimum_size = Vector2(0, GyroUI.sz(56))
	export_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_btn.pressed.connect(_export)
	export_btn.set_meta("lang_key", "export")
	row2.add_child(export_btn)
	var del_btn := Button.new()
	del_btn.custom_minimum_size = Vector2(0, GyroUI.sz(56))
	del_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	del_btn.add_theme_color_override("font_color", DesignTokens.COLOR_ERROR)
	del_btn.pressed.connect(_confirm_delete)
	del_btn.set_meta("lang_key", "delete")
	row2.add_child(del_btn)

func setup(proj: GyroProject) -> void:
	project = proj
	_show_list()

func apply_lang() -> void:
	_title.text = GyroLang.t("functions_title")
	_hint.text = GyroLang.t("function_empty_hint")
	for node in [_name_edit, _params_edit, _expr_edit]:
		node.placeholder_text = GyroLang.t(str(node.get_meta("lang_key")))
	for btn in _find_buttons(self):
		if btn.has_meta("lang_key"):
			btn.text = GyroLang.t(str(btn.get_meta("lang_key")))
	if _expr_editor != null:
		_expr_editor.apply_lang()

func _find_buttons(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_find_buttons(c))
	return out

func _show_list() -> void:
	_list_panel.visible = true
	_edit_panel.visible = false
	GyroUI.clear_children(_list)
	var list := GyroFunctions.items()
	_hint.visible = list.is_empty()
	for v in list:
		var f := v as GyroCustomFunction
		if f == null:
			continue
		var btn := Button.new()
		btn.text = "%s(%s)" % [f.func_name, ", ".join(f.params.map(func(x): return str(x)))]
		btn.custom_minimum_size = Vector2(0, GyroUI.sz(56))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(func(): _open_edit(f))
		_list.add_child(btn)

func _open_edit(f: GyroCustomFunction) -> void:
	_current = f
	_list_panel.visible = false
	_edit_panel.visible = true
	_name_edit.text = f.func_name if f != null else ""
	_params_edit.text = ", ".join(f.params.map(func(x): return str(x))) if f != null else ""
	_expr_edit.text = f.expression if f != null else ""
	_result.text = ""
	_rebuild_test_fields()

func _param_names() -> Array:
	var out: Array = []
	for part in _params_edit.text.split(","):
		var p := part.strip_edges()
		if p != "":
			out.append(p)
	return out

func _rebuild_test_fields() -> void:
	GyroUI.clear_children(_test_box)
	_test_edits.clear()
	for p in _param_names():
		var edit := LineEdit.new()
		edit.placeholder_text = str(p)
		edit.set_meta("param_name", str(p))
		_test_box.add_child(edit)
		_test_edits.append(edit)

func _run_test() -> void:
	var params := {}
	for edit in _test_edits:
		var raw := str(edit.text).strip_edges()
		var parsed = JSON.parse_string(raw)
		params[str(edit.get_meta("param_name"))] = parsed if parsed != null else raw
	var vars := {}
	if project != null:
		vars = project.merge_blueprints().variables
	var out: Array = []
	if GyroExpression.try_eval(_expr_edit.text, vars, {}, Callable(), out, params):
		_result.add_theme_color_override("font_color", DesignTokens.COLOR_SUCCESS)
		_result.text = GyroLang.t("function_result") % str(out[0])
	else:
		_result.add_theme_color_override("font_color", DesignTokens.COLOR_ERROR)
		_result.text = GyroLang.t("function_error") % GyroLang.t("function_bad_expr")

func _open_expr_editor() -> void:
	var names: Array = []
	if project != null:
		names = project.merge_blueprints().variables.keys()
	_expr_editor.open(_expr_edit.text, names, _param_names())

func _save_current() -> void:
	var fname := _name_edit.text.strip_edges()
	var params := _param_names()
	var expr := _expr_edit.text.strip_edges()
	var err := GyroFunctions.validate(fname, params, expr, _current)
	if err != "":
		var msg := GyroLang.t(err)
		if err == "function_exists":
			msg = msg % fname
		GyroUI.alert(self, GyroLang.t("error"), msg)
		return
	if _current == null:
		var f := GyroCustomFunction.new()
		f.func_name = fname
		f.params = params
		f.expression = expr
		GyroFunctions.add(f)
	else:
		_current.func_name = fname
		_current.params = params
		_current.expression = expr
		GyroFunctions.save()
	_show_list()

func _confirm_delete() -> void:
	if _current == null:
		_show_list()
		return
	var dialog := preload("res://ui/components/gyro_dialog.tscn").instantiate()
	add_child(dialog)
	dialog.z_index = 40
	dialog.open(GyroLang.t("delete"), GyroLang.t("function_delete_q") % _current.func_name + "\n" + GyroLang.t("function_used_hint"), GyroLang.t("delete"), GyroLang.t("cancel"))
	dialog.confirmed.connect(func():
		dialog.queue_free()
		GyroFunctions.remove(_current)
		_current = null
		_show_list()
	)

func _export() -> void:
	if _current == null:
		return
	var tmp := "user://_tmp_fn.gyrofunc"
	if not GyroFunctions.export_function(_current, tmp):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("export_failed"))
		return
	GyroFilePicker.save_file(tmp, "other", _current.func_name + ".gyrofunc",
		func(_p): DirAccess.remove_absolute(tmp),
		func(_m): DirAccess.remove_absolute(tmp)
	)

func _import() -> void:
	GyroFilePicker.pick_file("other", func(path: String):
		var res := GyroFunctions.import_function(path)
		if path.begins_with("user://imported_"):
			DirAccess.remove_absolute(path)
		if not bool(res.get("ok", false)):
			GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("function_import_failed"))
			return
		_show_list()
	, func(message: String):
		GyroUI.alert(self, GyroLang.t("error"), message)
	)

func _on_back() -> void:
	if _edit_panel.visible:
		_show_list()
		return
	back_requested.emit()
