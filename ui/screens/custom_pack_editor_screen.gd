class_name CustomPackEditorScreen
extends Control

signal back_requested
signal edit_block(block: GyroCustomBlock)
signal changed

var project: GyroProject
var pack: GyroCustomPack
var save_path := ""
var name_edit: LineEdit
var author_edit: LineEdit
var list_vbox: VBoxContainer
var add_btn: Button
var export_btn: Button
var gear_btn: Button
var gear_overlay: ColorRect
var gear_panel: PanelContainer
var add_overlay: ColorRect
var add_panel: PanelContainer

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
	back.pressed.connect(func():
		_commit()
		changed.emit()
		back_requested.emit()
	)
	header.add_child(back)
	var title := Label.new()
	title.text = GyroLang.t("custom_pack")
	title.add_theme_font_size_override("font_size", GyroUI.fs(28))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	gear_btn = GyroUI.icon_button("res://ui/icons/gear.svg", GyroUI.fs(28))
	gear_btn.pressed.connect(func():
		_open_gear()
	)
	header.add_child(gear_btn)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = GyroLang.t("custom_pack")
	root.add_child(name_edit)
	author_edit = LineEdit.new()
	author_edit.placeholder_text = GyroLang.t("custom_author")
	root.add_child(author_edit)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	list_vbox = VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(list_vbox)
	var ts := GyroTouchScroll.new()
	add_child(ts)
	ts.setup(scroll, [gear_overlay_placeholder()])
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	root.add_child(bottom)
	add_btn = Button.new()
	add_btn.text = "+ " + GyroLang.t("custom_add_block")
	add_btn.custom_minimum_size = Vector2(0, GyroUI.sz(64))
	add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_btn.pressed.connect(_open_add)
	bottom.add_child(add_btn)
	export_btn = Button.new()
	export_btn.text = GyroLang.t("export")
	export_btn.custom_minimum_size = Vector2(0, GyroUI.sz(64))
	export_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_btn.pressed.connect(_export)
	bottom.add_child(export_btn)
	_build_gear()
	_build_add()

func gear_overlay_placeholder() -> Control:
	return Control.new()

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
	gear_panel.custom_minimum_size = Vector2(GyroUI.dialog_width(360), 0)
	GyroUI.center(gear_panel)
	gear_panel.visible = false
	gear_panel.z_index = 37
	add_child(gear_panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	gear_panel.add_child(vbox)
	var dup := Button.new()
	dup.text = GyroLang.t("custom_duplicate_pack")
	dup.custom_minimum_size = Vector2(0, GyroUI.sz(56))
	dup.pressed.connect(_duplicate_pack)
	vbox.add_child(dup)
	var del_keep := Button.new()
	del_keep.text = GyroLang.t("custom_delete_keep_blocks")
	del_keep.custom_minimum_size = Vector2(0, GyroUI.sz(56))
	del_keep.add_theme_color_override("font_color", Color(0.96, 0.62, 0.04))
	del_keep.pressed.connect(func():
		_close_gear()
		_delete_pack(false)
	)
	vbox.add_child(del_keep)
	var del_all := Button.new()
	del_all.text = GyroLang.t("custom_delete_with_blocks")
	del_all.custom_minimum_size = Vector2(0, GyroUI.sz(56))
	del_all.add_theme_color_override("font_color", Color(0.94, 0.54, 0.53))
	del_all.pressed.connect(func():
		_close_gear()
		_delete_pack(true)
	)
	vbox.add_child(del_all)

func _build_add() -> void:
	add_overlay = ColorRect.new()
	add_overlay.color = Color(0, 0, 0, 0.5)
	add_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_overlay.visible = false
	add_overlay.z_index = 38
	add_overlay.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event):
			_close_add()
	)
	add_child(add_overlay)
	add_panel = PanelContainer.new()
	GyroUI.apply_glass_style(add_panel)
	add_panel.custom_minimum_size = Vector2(GyroUI.dialog_width(360), 0)
	GyroUI.center(add_panel)
	add_panel.visible = false
	add_panel.z_index = 39
	add_child(add_panel)

func _open_gear() -> void:
	gear_overlay.visible = true
	gear_panel.visible = true

func _close_gear() -> void:
	gear_overlay.visible = false
	gear_panel.visible = false

func _open_add() -> void:
	for child in add_panel.get_children():
		child.queue_free()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, GyroUI.sz(320))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)
	var found := false
	for bv in project.custom_blocks:
		var b := bv as GyroCustomBlock
		if b == null:
			continue
		found = true
		vbox.add_child(_candidate_row(b, GyroLang.t("custom_my_blocks")))
	for pkv in project.custom_packs:
		var pk := pkv as GyroCustomPack
		if pk == null or pk == pack:
			continue
		for bv in pk.blocks:
			var b := bv as GyroCustomBlock
			if b == null:
				continue
			found = true
			vbox.add_child(_candidate_row(b, pk.pack_name))
	if not found:
		var empty := Label.new()
		empty.text = GyroLang.t("palette_no_blocks")
		empty.add_theme_color_override("font_color", Color(0.55, 0.58, 0.63))
		vbox.add_child(empty)
	add_overlay.visible = true
	add_panel.visible = true

func _close_add() -> void:
	add_overlay.visible = false
	add_panel.visible = false

func _candidate_row(b: GyroCustomBlock, source: String) -> Button:
	var btn := Button.new()
	btn.text = "  " + b.block_name + " · " + source
	btn.custom_minimum_size = Vector2(0, GyroUI.sz(48))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.flat = true
	btn.pressed.connect(func():
		_close_add()
		_move_block_here(b)
	)
	return btn

func _move_block_here(b: GyroCustomBlock) -> void:
	_commit()
	if project.custom_blocks.has(b):
		project.custom_blocks.erase(b)
	else:
		var old_pk := GyroCustomRegistry.find_pack_of(project, b.block_id)
		if old_pk != null:
			old_pk.blocks.erase(b)
	pack.blocks.append(b)
	_save()
	_refresh_list()
	changed.emit()

func _duplicate_pack() -> void:
	_close_gear()
	_commit()
	var np := GyroCustomPack.new()
	np.pack_name = GyroCustomRegistry.make_unique_pack_name(project, pack.pack_name + "_copy")
	np.author = pack.author
	for bv in pack.blocks:
		var b := bv as GyroCustomBlock
		if b == null:
			continue
		var nb := GyroCustomBlock.new()
		nb.block_id = GyroCustomRegistry.make_unique_id(project, b.block_id)
		nb.block_name = b.block_name
		nb.author = b.author
		nb.color = b.color
		nb.fields = b.fields.duplicate(true)
		nb.body = b.body.duplicate(true)
		np.blocks.append(nb)
	project.custom_packs.append(np)
	_save()
	changed.emit()
	setup(project, np, save_path)

func _delete_pack(with_blocks: bool) -> void:
	_commit()
	if with_blocks:
		for bv in pack.blocks.duplicate():
			var b := bv as GyroCustomBlock
			if b != null:
				GyroCustomRegistry.remove_block_everywhere(project, b.block_id)
	else:
		for bv in pack.blocks.duplicate():
			var b := bv as GyroCustomBlock
			if b != null:
				project.custom_blocks.append(b)
		pack.blocks.clear()
	project.custom_packs.erase(pack)
	_save()
	changed.emit()
	back_requested.emit()

func _export() -> void:
	_commit()
	var tmp := "user://_tmp_pack.gyropack"
	if not GyroCustomRegistry.export_pack(pack, tmp):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("export_failed"))
		return
	GyroFilePicker.save_file(tmp, "other", pack.pack_name + ".gyropack",
		func(_p): DirAccess.remove_absolute(tmp),
		func(_m): DirAccess.remove_absolute(tmp)
	)

func setup(proj: GyroProject, pk: GyroCustomPack, path: String) -> void:
	project = proj
	pack = pk
	save_path = path
	if pack != null:
		name_edit.text = pack.pack_name
		author_edit.text = pack.author
	_refresh_list()

func _refresh_list() -> void:
	GyroUI.clear_children(list_vbox)
	if pack == null:
		return
	for bv in pack.blocks:
		var b := bv as GyroCustomBlock
		if b == null:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		list_vbox.add_child(row)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(GyroUI.sz(14), GyroUI.sz(48))
		swatch.color = b.color
		row.add_child(swatch)
		var label := Label.new()
		label.text = b.block_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", GyroUI.fs(18))
		row.add_child(label)
		var open := Button.new()
		open.text = GyroLang.t("open")
		open.pressed.connect(func(): edit_block.emit(b))
		row.add_child(open)
		var remove := GyroUI.icon_button("res://ui/icons/close.svg", GyroUI.fs(18))
		remove.pressed.connect(func():
			pack.blocks.erase(b)
			project.custom_blocks.append(b)
			_save()
			_refresh_list()
			changed.emit()
		)
		row.add_child(remove)

func _commit() -> void:
	if pack == null:
		return
	var clean := GyroUI.sanitize_name(name_edit.text)
	pack.pack_name = clean if not GyroUI.is_bad_name(clean) else pack.pack_name
	pack.author = author_edit.text
	_save()

func _save() -> void:
	if project != null and save_path != "":
		GyroProjectJSON.save_to_file(project, save_path)
