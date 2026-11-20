class_name CustomBlockEditorScreen
extends Control

signal back_requested
signal open_body(block: GyroCustomBlock)
signal changed

var project: GyroProject
var pack: GyroCustomPack
var block: GyroCustomBlock
var save_path := ""
var name_edit: LineEdit
var color_pick: ColorPickerButton
var fields_vbox: VBoxContainer
var logic_btn: Button
var export_btn: Button
var gear_btn: Button
var gear_overlay: ColorRect
var gear_panel: PanelContainer
var _rows: Array = []

const TYPE_PICKS := ["", "", "", "color", "obj", "var", "sprite", "sound", "event"]

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
	var title := Label.new()
	title.text = GyroLang.t("custom_new_block")
	title.add_theme_font_size_override("font_size", GyroUI.fs(28))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	gear_btn = GyroUI.icon_button("res://ui/icons/gear.svg", GyroUI.fs(28))
	gear_btn.pressed.connect(_open_gear)
	header.add_child(gear_btn)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = GyroLang.t("custom_block_name")
	root.add_child(name_edit)
	color_pick = ColorPickerButton.new()
	color_pick.custom_minimum_size = Vector2(0, GyroUI.sz(48))
	root.add_child(color_pick)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	fields_vbox = VBoxContainer.new()
	fields_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(fields_vbox)
	var ts := GyroTouchScroll.new()
	add_child(ts)
	ts.setup(scroll)
	var add_field := Button.new()
	add_field.text = "+ " + GyroLang.t("custom_add_field")
	add_field.custom_minimum_size = Vector2(0, GyroUI.sz(56))
	add_field.pressed.connect(func(): _add_row({"key": "", "label": "", "pick": "", "default": ""}))
	root.add_child(add_field)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	root.add_child(bottom)
	logic_btn = Button.new()
	logic_btn.custom_minimum_size = Vector2(0, GyroUI.sz(72))
	logic_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	logic_btn.pressed.connect(func():
		_commit()
		open_body.emit(block)
	)
	bottom.add_child(logic_btn)
	export_btn = Button.new()
	export_btn.text = GyroLang.t("export")
	export_btn.custom_minimum_size = Vector2(0, GyroUI.sz(72))
	export_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_btn.pressed.connect(_export)
	bottom.add_child(export_btn)
	_build_gear()

func _build_gear() -> void:
	gear_overlay = ColorRect.new()
	gear_overlay.color = Color(0, 0, 0, 0.5)
	gear_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gear_overlay.visible = false
	gear_overlay.z_index = 36
	gear_overlay.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event):
			_close_gear()
	)
	add_child(gear_overlay)
	gear_panel = PanelContainer.new()
	GyroUI.apply_glass_style(gear_panel)
	gear_panel.custom_minimum_size = Vector2(GyroUI.dialog_width(320), 0)
	GyroUI.center(gear_panel)
	gear_panel.visible = false
	gear_panel.z_index = 37
	add_child(gear_panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	gear_panel.add_child(vbox)
	var dup := Button.new()
	dup.text = GyroLang.t("duplicate")
	dup.custom_minimum_size = Vector2(0, GyroUI.sz(56))
	dup.pressed.connect(func():
		_close_gear()
		_commit()
		var nb := GyroCustomRegistry.duplicate_block(project, block)
		_save()
		changed.emit()
		setup(project, pack, nb, save_path)
	)
	vbox.add_child(dup)
	var del := Button.new()
	del.text = GyroLang.t("delete")
	del.custom_minimum_size = Vector2(0, GyroUI.sz(56))
	del.add_theme_color_override("font_color", Color(0.94, 0.54, 0.53))
	del.pressed.connect(func():
		_close_gear()
		_confirm_delete()
	)
	vbox.add_child(del)

func _open_gear() -> void:
	gear_overlay.visible = true
	gear_panel.visible = true

func _close_gear() -> void:
	gear_overlay.visible = false
	gear_panel.visible = false

func _confirm_delete() -> void:
	_commit()
	var count := GyroCustomRegistry.count_usages(project, block.block_id)
	var body := GyroLang.t("delete_block_q")
	if count > 0:
		body += "\n" + GyroLang.t("custom_used_in_rules") % count
	var dialog := preload("res://ui/components/gyro_dialog.tscn").instantiate()
	add_child(dialog)
	dialog.z_index = 40
	dialog.open(GyroLang.t("delete"), body, GyroLang.t("delete"), GyroLang.t("cancel"))
	dialog.confirmed.connect(func():
		dialog.queue_free()
		GyroCustomRegistry.remove_block_everywhere(project, block.block_id)
		_save()
		changed.emit()
		back_requested.emit()
	)

func _export() -> void:
	_commit()
	var tmp := "user://_tmp_pack.gyropack"
	if not GyroCustomRegistry.export_single_block(block, tmp):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("export_failed"))
		return
	GyroFilePicker.save_file(tmp, "other", block.block_name + ".gyropack",
		func(_p): DirAccess.remove_absolute(tmp),
		func(_m): DirAccess.remove_absolute(tmp)
	)

func setup(proj: GyroProject, pk: GyroCustomPack, b: GyroCustomBlock, path: String) -> void:
	project = proj
	pack = pk
	block = b
	save_path = path
	_fill()

func _fill() -> void:
	if block == null:
		return
	name_edit.text = block.block_name
	color_pick.color = block.color
	GyroUI.clear_children(fields_vbox)
	_rows.clear()
	for f in block.fields:
		_add_row((f as Dictionary).duplicate(true))
	if logic_btn != null:
		logic_btn.text = GyroLang.t("custom_logic")

func _add_row(f: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	fields_vbox.add_child(row)
	var key_edit := LineEdit.new()
	key_edit.text = str(f.get("key", ""))
	key_edit.placeholder_text = "key"
	key_edit.custom_minimum_size = Vector2(GyroUI.sz(90), 0)
	row.add_child(key_edit)
	var label_edit := LineEdit.new()
	label_edit.text = str(f.get("label", ""))
	label_edit.placeholder_text = GyroLang.t("custom_field_label")
	label_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label_edit)
	var type_opt := OptionButton.new()
	for i in 9:
		type_opt.add_item(GyroLang.t("f_type_" + str(i)), i)
	var pick := str(f.get("pick", ""))
	type_opt.selected = TYPE_PICKS.find(pick) if TYPE_PICKS.has(pick) else 0
	row.add_child(type_opt)
	var def_edit := LineEdit.new()
	def_edit.text = str(f.get("default", ""))
	def_edit.placeholder_text = GyroLang.t("custom_field_default")
	def_edit.custom_minimum_size = Vector2(GyroUI.sz(70), 0)
	row.add_child(def_edit)
	var del := GyroUI.icon_button("res://ui/icons/close.svg", GyroUI.fs(16))
	del.pressed.connect(func():
		row.queue_free()
		_rows.erase(row)
	)
	row.add_child(del)
	_rows.append(row)

func _commit() -> void:
	if block == null:
		return
	var clean_name := GyroUI.sanitize_name(name_edit.text)
	block.block_name = clean_name if not GyroUI.is_bad_name(clean_name) else "Block"
	block.color = color_pick.color
	var new_fields: Array = []
	var seen: Array = []
	for row in _rows.duplicate():
		if not is_instance_valid(row):
			continue
		var key_edit: LineEdit = row.get_child(0)
		var label_edit: LineEdit = row.get_child(1)
		var type_opt: OptionButton = row.get_child(2)
		var def_edit: LineEdit = row.get_child(3)
		var key := GyroUI.sanitize_name(key_edit.text).to_lower().replace(" ", "_")
		if key == "" or seen.has(key):
			continue
		seen.append(key)
		var label := label_edit.text
		new_fields.append({
			"key": key,
			"label": label if label != "" else key,
			"pick": TYPE_PICKS[type_opt.selected],
			"default": def_edit.text,
		})
	block.fields = new_fields
	_save()

func _save() -> void:
	if project != null and save_path != "":
		GyroProjectJSON.save_to_file(project, save_path)

func _on_back() -> void:
	_commit()
	changed.emit()
	back_requested.emit()
