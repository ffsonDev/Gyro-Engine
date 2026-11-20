class_name GyroPalette
extends Control

signal item_down(item: Dictionary)
signal create_block_confirmed(block_name: String, pack_name: String)
signal create_pack_confirmed(pack_name: String)
signal import_requested
signal edit_block_requested(block_id: String)
signal edit_pack_requested(pack_name: String)

var color_for: Callable
var project: GyroProject
var edit_mode := false
var search_edit: LineEdit
var list_vbox: VBoxContainer
var categories_button: Button
var categories_overlay: ColorRect
var categories_panel: PanelContainer
var categories_vbox: VBoxContainer
var categories_scroll: ScrollContainer
var _touch_scroll: GyroTouchScroll
var _down_button: Button = null
var bottom_bar: HBoxContainer
var create_btn: Button
var edit_btn: Button
var import_btn: Button
var _create_overlay: ColorRect
var _create_panel: PanelContainer
var _choice_overlay: ColorRect
var _choice_panel: PanelContainer
var _current_category := ""
var _favorites: Array = []
var _star_buttons: Dictionary = {}
var _empty_center: Control
var _empty_label: Label
var _press_pos := Vector2.ZERO
var _press_active := false
var _long_fired := false
var _press_token := 0
const LONG_PRESS_SEC := 0.35
const PRESS_MOVE_CANCEL := 24.0
const FAVORITES_PATH := "user://gyro_favorites.json"
const CATEGORY_ALL := "__all__"
const CATEGORY_FAVORITES := "__favorites__"
const CATEGORY_CUSTOM := "__custom__"
const STAR_SIZE := 36
const STAR_ICON_SIZE := 20
signal item_drag_requested(item: Dictionary, pos: Vector2)


func _ready() -> void:
	search_edit = %SearchEdit as LineEdit
	list_vbox = %ListVBox as VBoxContainer
	categories_button = %CategoriesButton as Button
	categories_overlay = %CategoriesOverlay as ColorRect
	categories_panel = %CategoriesPanel as PanelContainer
	categories_scroll = %CategoriesScroll as ScrollContainer
	categories_vbox = %CategoriesVBox as VBoxContainer

	var back_btn := %BackButton as Button
	back_btn.pressed.connect(close)

	if search_edit != null:
		search_edit.placeholder_text = GyroLang.t("search")
		search_edit.text_changed.connect(func(_t: String): _rebuild_list(search_edit.text))

	if categories_button != null:
		categories_button.custom_minimum_size = Vector2(GyroUI.sz(50), GyroUI.sz(56))
		categories_button.add_theme_font_size_override("font_size", GyroUI.fs(24))
		categories_button.pressed.connect(_open_categories)

	if categories_overlay != null:
		categories_overlay.gui_input.connect(func(event: InputEvent):
			if GyroUI.is_tap(event):
				_close_categories()
		)

	_empty_center = Control.new()
	_empty_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_empty_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_center.visible = false
	add_child(_empty_center)
	_empty_label = Label.new()
	_empty_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_empty_label.offset_left = 40
	_empty_label.offset_right = -40
	_empty_label.offset_top = 72
	_empty_label.offset_bottom = -24
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.add_theme_color_override("font_color", Color(0.55, 0.58, 0.63))
	_empty_label.add_theme_font_size_override("font_size", GyroUI.fs(16))
	_empty_center.add_child(_empty_label)

	_build_bottom_bar()
	_build_create_panel()
	_load_favorites()
	_rebuild_categories_list()

	var scroll := %Scroll as ScrollContainer
	if scroll != null:
		_touch_scroll = GyroTouchScroll.new()
		add_child(_touch_scroll)
		_touch_scroll.setup(scroll, [categories_overlay, _create_overlay, _choice_overlay])

	apply_lang()

func _process(_delta: float) -> void:
	if _touch_scroll != null and _touch_scroll.dragged:
		_release_down()

func _release_down() -> void:
	if _down_button != null and is_instance_valid(_down_button):
		_down_button.modulate.a = 1.0
	_down_button = null
	_press_active = false

func _build_bottom_bar() -> void:
	var root := %Root as VBoxContainer
	if root == null:
		return
	bottom_bar = HBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", 8)
	bottom_bar.visible = false
	root.add_child(bottom_bar)
	create_btn = Button.new()
	create_btn.custom_minimum_size = Vector2(0, GyroUI.sz(64))
	create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_btn.pressed.connect(func(): _open_create_panel())
	bottom_bar.add_child(create_btn)
	edit_btn = Button.new()
	edit_btn.custom_minimum_size = Vector2(0, GyroUI.sz(64))
	edit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_btn.pressed.connect(func():
		edit_mode = not edit_mode
		_rebuild_list(search_edit.text if search_edit != null else "")
	)
	bottom_bar.add_child(edit_btn)
	import_btn = Button.new()
	import_btn.custom_minimum_size = Vector2(0, GyroUI.sz(64))
	import_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_btn.visible = false
	import_btn.pressed.connect(func(): import_requested.emit())
	bottom_bar.add_child(import_btn)


func _build_create_panel() -> void:
	_create_overlay = ColorRect.new()
	_create_overlay.color = Color(0, 0, 0, 0.5)
	_create_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_create_overlay.visible = false
	_create_overlay.z_index = 32
	_create_overlay.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event):
			_create_overlay.visible = false
			_create_panel.visible = false
	)
	add_child(_create_overlay)
	_create_panel = PanelContainer.new()
	GyroUI.apply_glass_style(_create_panel)
	_create_panel.custom_minimum_size = Vector2(GyroUI.dialog_width(320), 0)
	GyroUI.center(_create_panel)
	_create_panel.visible = false
	_create_panel.z_index = 33
	add_child(_create_panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_create_panel.add_child(vbox)
	var b_block := Button.new()
	b_block.custom_minimum_size = Vector2(0, GyroUI.sz(56))
	b_block.pressed.connect(func():
		_create_overlay.visible = false
		_create_panel.visible = false
		_ask_name(GyroLang.t("custom_block_choice"), func(block_name: String):
			if project != null and not project.custom_packs.is_empty():
				_open_pack_choice(func(pack_name: String):
					create_block_confirmed.emit(block_name, pack_name)
				)
			else:
				create_block_confirmed.emit(block_name, "")
		)
	)
	vbox.add_child(b_block)
	var b_pack := Button.new()
	b_pack.custom_minimum_size = Vector2(0, GyroUI.sz(56))
	b_pack.pressed.connect(func():
		_create_overlay.visible = false
		_create_panel.visible = false
		_ask_name(GyroLang.t("custom_pack_choice"), func(pack_name: String):
			create_pack_confirmed.emit(pack_name)
		)
	)
	vbox.add_child(b_pack)
	_choice_overlay = ColorRect.new()
	_choice_overlay.color = Color(0, 0, 0, 0.5)
	_choice_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_choice_overlay.visible = false
	_choice_overlay.z_index = 34
	_choice_overlay.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event):
			_choice_overlay.visible = false
			_choice_panel.visible = false
	)
	add_child(_choice_overlay)
	_choice_panel = PanelContainer.new()
	GyroUI.apply_glass_style(_choice_panel)
	_choice_panel.custom_minimum_size = Vector2(GyroUI.dialog_width(320), 0)
	GyroUI.center(_choice_panel)
	_choice_panel.visible = false
	_choice_panel.z_index = 35
	add_child(_choice_panel)


func _open_create_panel() -> void:
	var vbox := _create_panel.get_child(0) as VBoxContainer
	if vbox != null:
		var b0 := vbox.get_child(0) as Button
		var b1 := vbox.get_child(1) as Button
		if b0 != null:
			b0.text = GyroLang.t("custom_block_choice")
		if b1 != null:
			b1.text = GyroLang.t("custom_pack_choice")
	_create_overlay.visible = true
	_create_panel.visible = true


func _open_pack_choice(on_pick: Callable) -> void:
	for child in _choice_panel.get_children():
		child.queue_free()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, GyroUI.sz(280))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choice_panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)
	var mine := Button.new()
	mine.text = GyroLang.t("custom_my_blocks")
	mine.custom_minimum_size = Vector2(0, GyroUI.sz(48))
	mine.pressed.connect(func():
		_choice_overlay.visible = false
		_choice_panel.visible = false
		on_pick.call("")
	)
	vbox.add_child(mine)
	if project != null:
		for pkv in project.custom_packs:
			var pk := pkv as GyroCustomPack
			if pk == null:
				continue
			var btn := Button.new()
			btn.text = pk.pack_name
			btn.custom_minimum_size = Vector2(0, GyroUI.sz(48))
			btn.pressed.connect(func():
				_choice_overlay.visible = false
				_choice_panel.visible = false
				on_pick.call(pk.pack_name)
			)
			vbox.add_child(btn)
	_choice_overlay.visible = true
	_choice_panel.visible = true


func _ask_name(title: String, on_ok: Callable) -> void:
	var dialog := preload("res://ui/components/gyro_input_dialog.tscn").instantiate()
	add_child(dialog)
	dialog.z_index = 40
	dialog.open(title, GyroLang.t("name_placeholder"), "", GyroLang.t("ok"), GyroLang.t("cancel"))
	dialog.confirmed_text.connect(func(text: String):
		dialog.queue_free()
		var clean := GyroUI.sanitize_name(text)
		if GyroUI.is_bad_name(clean):
			return
		on_ok.call(clean)
	)


func refresh() -> void:
	_rebuild_categories_list()
	_rebuild_list(search_edit.text if search_edit != null else "")


func _open_categories() -> void:
	if categories_overlay == null or categories_panel == null:
		return
	_rebuild_categories_list()
	categories_overlay.visible = true
	categories_panel.visible = true
	var tw := categories_panel.create_tween()
	categories_panel.pivot_offset = categories_panel.size * 0.5
	categories_panel.scale = Vector2(0.9, 0.9)
	categories_panel.modulate.a = 0.0
	tw.set_parallel(true)
	tw.tween_property(categories_panel, "scale", Vector2.ONE, DesignTokens.ANIM_SPRING).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(categories_panel, "modulate:a", 1.0, DesignTokens.ANIM_NORMAL)


func _close_categories() -> void:
	if categories_overlay == null or categories_panel == null:
		return
	categories_overlay.visible = false
	categories_panel.visible = false


func _rebuild_categories_list() -> void:
	if categories_vbox == null:
		return
	GyroUI.clear_children(categories_vbox)
	_add_category_button(CATEGORY_ALL, GyroLang.t("palette_all_blocks"), Color(0.35, 0.45, 0.60))
	_add_category_button(CATEGORY_FAVORITES, GyroLang.t("palette_favorites"), Color(0.65, 0.50, 0.20))
	_add_category_button(CATEGORY_CUSTOM, GyroLang.t("palette_custom_blocks"), Color(0.55, 0.40, 0.60))
	for section in GyroBlocks.palette_sections():
		var title: String = str(section.title)
		_add_category_button(title, title, Color(0, 0, 0, 0))


func _add_category_button(category_id: String, label: String, _accent: Color) -> void:
	var btn := Button.new()
	btn.text = "  " + label
	btn.custom_minimum_size = Vector2(0, GyroUI.sz(48))
	btn.add_theme_font_size_override("font_size", GyroUI.fs(18))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.flat = true
	var selected := (_current_category == category_id)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.55, 0.62) if selected else Color(0, 0, 0, 0)
	style.set_corner_radius_all(GyroUI.sz(8))
	style.content_margin_left = 12
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.08, 0.45, 0.52)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color.WHITE if selected else Color(0.85, 0.85, 0.85))
	btn.pressed.connect(func():
		_current_category = category_id
		_close_categories()
		_rebuild_list(search_edit.text if search_edit != null else "")
	)
	categories_vbox.add_child(btn)


func close() -> void:
	visible = false
	if search_edit != null:
		search_edit.text = ""
	_current_category = ""
	edit_mode = false
	_rebuild_list("")


func apply_lang() -> void:
	if search_edit != null:
		search_edit.placeholder_text = GyroLang.t("search")
	if create_btn != null:
		create_btn.text = GyroLang.t("custom_create")
	if import_btn != null:
		import_btn.text = GyroLang.t("custom_import_pack")
	_rebuild_list(search_edit.text if search_edit != null else "")


func _rebuild_list(query: String) -> void:
	if list_vbox == null:
		return
	GyroUI.clear_children(list_vbox)
	_star_buttons.clear()
	_hide_empty_hint()
	if edit_btn != null:
		edit_btn.text = GyroLang.t("custom_done") if edit_mode else GyroLang.t("custom_edit")
	if import_btn != null:
		import_btn.visible = edit_mode
	if bottom_bar != null:
		bottom_bar.visible = (_current_category == CATEGORY_CUSTOM)
		create_btn.visible = not edit_mode
	var q := query.strip_edges().to_lower()
	if _current_category == CATEGORY_ALL:
		_rebuild_all_blocks(q)
		return
	if _current_category == CATEGORY_FAVORITES:
		_rebuild_favorites(q)
		return
	if _current_category == CATEGORY_CUSTOM:
		_rebuild_custom(q)
		return
	var found := false
	for section in GyroBlocks.palette_sections():
		var section_title: String = str(section.title)
		if _current_category != "" and _current_category != section_title:
			continue
		var visible_items: Array = []
		for item in section.items:
			if q == "" or str(item.name).to_lower().contains(q):
				visible_items.append(item)
		if visible_items.is_empty():
			continue
		found = true
		var header := Label.new()
		header.text = section_title
		header.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
		header.add_theme_font_size_override("font_size", GyroUI.fs(16))
		list_vbox.add_child(header)
		for item in visible_items:
			list_vbox.add_child(_make_item_button(item))
	if not found:
		_show_empty_hint(GyroLang.t("palette_no_blocks"))


func _custom_groups(q: String) -> Array:
	var groups: Array = []
	if project == null:
		return groups
	var mine: Array = []
	for bv in project.custom_blocks:
		var b := bv as GyroCustomBlock
		if b != null and (q == "" or b.block_name.to_lower().contains(q)):
			mine.append({"kind": "custom", "type": b.block_id, "name": b.block_name})
	if not mine.is_empty():
		groups.append({"title": GyroLang.t("custom_my_blocks"), "pack": null, "items": mine})
	for pkv in project.custom_packs:
		var pk := pkv as GyroCustomPack
		if pk == null:
			continue
		var items: Array = []
		for bv in pk.blocks:
			var b := bv as GyroCustomBlock
			if b != null and (q == "" or b.block_name.to_lower().contains(q)):
				items.append({"kind": "custom", "type": b.block_id, "name": b.block_name})
		if not items.is_empty() or q == "":
			groups.append({"title": pk.pack_name, "pack": pk, "items": items})
	return groups


func _rebuild_custom(q: String) -> void:
	var groups := _custom_groups(q)
	for g in groups:
		if edit_mode and g.pack != null:
			var hbtn := Button.new()
			hbtn.text = " " + str(g.title)
			hbtn.custom_minimum_size = Vector2(0, GyroUI.sz(48))
			hbtn.flat = true
			hbtn.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
			hbtn.add_theme_font_size_override("font_size", GyroUI.fs(16))
			hbtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			hbtn.pressed.connect(func():
				if _touch_scroll != null and _touch_scroll.dragged:
					return
				edit_pack_requested.emit(str(g.pack.pack_name))
			)
			list_vbox.add_child(hbtn)
		else:
			var header := Label.new()
			header.text = str(g.title)
			header.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
			header.add_theme_font_size_override("font_size", GyroUI.fs(16))
			list_vbox.add_child(header)
		for item in g.items:
			if edit_mode:
				list_vbox.add_child(_make_edit_row(item))
			else:
				list_vbox.add_child(_make_item_button(item))
	if groups.is_empty():
		_show_empty_hint(GyroLang.t("custom_no_packs"))


func _make_edit_row(item: Dictionary) -> Button:
	var btn := Button.new()
	btn.text = "  " + str(item.name)
	btn.custom_minimum_size = Vector2(0, GyroUI.sz(56))
	btn.add_theme_font_size_override("font_size", GyroUI.fs(18))
	btn.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9))
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(func():
		if _touch_scroll != null and _touch_scroll.dragged:
			return
		edit_block_requested.emit(str(item.type))
	)	
	return btn


func _rebuild_all_blocks(q: String) -> void:
	var found := false
	for section in GyroBlocks.palette_sections():
		var visible_items: Array = []
		for item in section.items:
			if q == "" or str(item.name).to_lower().contains(q):
				visible_items.append(item)
		if visible_items.is_empty():
			continue
		found = true
		var header := Label.new()
		header.text = str(section.title)
		header.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
		header.add_theme_font_size_override("font_size", GyroUI.fs(16))
		list_vbox.add_child(header)
		for item in visible_items:
			list_vbox.add_child(_make_item_button(item))
	for g in _custom_groups(q):
		found = true
		var pheader := Label.new()
		pheader.text = str(g.title)
		pheader.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
		pheader.add_theme_font_size_override("font_size", GyroUI.fs(16))
		list_vbox.add_child(pheader)
		for item in g.items:
			list_vbox.add_child(_make_item_button(item))
	if not found:
		_show_empty_hint(GyroLang.t("palette_no_blocks"))


func _rebuild_favorites(q: String) -> void:
	if _favorites.is_empty():
		_show_empty_hint(GyroLang.t("palette_favorites_empty"))
		return
	var matched: Array = []
	for section in GyroBlocks.palette_sections():
		for item in section.items:
			if not _favorites.has(_fav_key(item)):
				continue
			if q != "" and not str(item.name).to_lower().contains(q):
				continue
			matched.append(item)
	for item in _custom_items(q):
		if not _favorites.has(_fav_key(item)):
			continue
		matched.append(item)
	if matched.is_empty():
		_show_empty_hint(GyroLang.t("palette_no_blocks"))
		return
	var header := Label.new()
	header.text = GyroLang.t("palette_favorites")
	header.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	header.add_theme_font_size_override("font_size", GyroUI.fs(16))
	list_vbox.add_child(header)
	for item in matched:
		list_vbox.add_child(_make_item_button(item))


func _custom_items(q: String) -> Array:
	var out: Array = []
	for g in _custom_groups(q):
		for item in g.items:
			out.append(item)
	return out


func _fav_key(item: Dictionary) -> String:
	return str(item.kind) + ":" + str(item.type)


func _is_favorite(item: Dictionary) -> bool:
	return _favorites.has(_fav_key(item))


func _make_item_button(item: Dictionary) -> Button:
	var button := Button.new()
	button.text = str(item.name)
	button.custom_minimum_size = Vector2(0, GyroUI.sz(64))
	button.add_theme_font_size_override("font_size", GyroUI.fs(18))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	var side_margin := GyroUI.sz(STAR_SIZE) + 12
	var style := StyleBoxFlat.new()
	style.bg_color = _color_for(item)
	style.set_corner_radius_all(10)
	style.content_margin_left = side_margin
	style.content_margin_right = side_margin
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.focus_mode = Control.FOCUS_NONE
	button.button_down.connect(func():
		_down_button = button
		button.modulate.a = 0.7
		_press_pos = button.get_global_mouse_position()
		_press_active = true
		_long_fired = false
		_press_token += 1
		var token := _press_token
		var wr: WeakRef = weakref(button)
		get_tree().create_timer(LONG_PRESS_SEC).timeout.connect(func():
			if token != _press_token or not _press_active:
				return
			var b := wr.get_ref() as Button
			if b == null or not is_instance_valid(b):
				return
			_press_active = false
			_long_fired = true
			b.modulate.a = 1.0
			if _down_button == b:
				_down_button = null
			if OS.get_name() == "Android" or OS.get_name() == "iOS":
				Input.vibrate_handheld(25)
			item_drag_requested.emit(item, b.get_global_mouse_position())
		)
	)
	button.button_up.connect(_release_down)
	button.gui_input.connect(func(event: InputEvent):
		if not _press_active:
			return
		if event is InputEventScreenDrag or event is InputEventMouseMotion:
			var g := button.get_global_mouse_position()
			if (g - _press_pos).length() > PRESS_MOVE_CANCEL:
				_press_active = false
		elif event is InputEventScreenTouch or event is InputEventMouseButton:
			if not event.pressed:
				_press_active = false
	)
	button.pressed.connect(func():
		_press_active = false
		if _long_fired:
			_long_fired = false
			return
		if _touch_scroll != null and _touch_scroll.dragged:
			return
		item_down.emit(item)
	)
	button.add_child(_make_star_button(item))
	return button


func _make_star_button(item: Dictionary) -> Button:
	var star := Button.new()
	star.flat = true
	star.focus_mode = Control.FOCUS_NONE
	star.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	star.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	star.offset_left = -GyroUI.sz(STAR_SIZE) - 6
	star.offset_top = -GyroUI.sz(STAR_SIZE) * 0.5
	star.offset_right = -6
	star.offset_bottom = GyroUI.sz(STAR_SIZE) * 0.5
	var icon_rect := TextureRect.new()
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var side := GyroUI.sz(STAR_ICON_SIZE)
	icon_rect.set_anchors_preset(Control.PRESET_CENTER)
	icon_rect.offset_left = -side * 0.5
	icon_rect.offset_top = -side * 0.5
	icon_rect.offset_right = side * 0.5
	icon_rect.offset_bottom = side * 0.5
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star.add_child(icon_rect)
	_update_star_icon(icon_rect, item)
	var key := _fav_key(item)
	if not _star_buttons.has(key):
		_star_buttons[key] = []
	(_star_buttons[key] as Array).append(icon_rect)
	star.pressed.connect(func():
		if _touch_scroll != null and _touch_scroll.dragged:
			return
		_toggle_favorite(item)
	)
	return star


func _update_star_icon(icon_rect: TextureRect, item: Dictionary) -> void:
	if icon_rect == null or not is_instance_valid(icon_rect):
		return
	if _is_favorite(item):
		icon_rect.texture = load("res://ui/icons/star_filled.svg")
		icon_rect.modulate = Color.WHITE
	else:
		icon_rect.texture = load("res://ui/icons/star_empty.svg")
		icon_rect.modulate = Color(0.7, 0.7, 0.7)


func _toggle_favorite(item: Dictionary) -> void:
	var key := _fav_key(item)
	if _favorites.has(key):
		_favorites.erase(key)
	else:
		_favorites.append(key)
	_save_favorites()
	_refresh_star_icons(key, item)
	if _current_category == CATEGORY_FAVORITES:
		_rebuild_list(search_edit.text if search_edit != null else "")


func _refresh_star_icons(key: String, item: Dictionary) -> void:
	if not _star_buttons.has(key):
		return
	for icon_rect in (_star_buttons[key] as Array):
		if is_instance_valid(icon_rect):
			_update_star_icon(icon_rect, item)


func _color_for(item: Dictionary) -> Color:
	if color_for.is_valid():
		return color_for.call(str(item.kind), str(item.type))
	if item.kind == "event":
		return GyroBlocks.COLOR_EVENT
	if item.kind == "condition":
		return GyroBlocks.CONDITION_COLORS.get(item.type, Color(0.45, 0.5, 0.3))
	return GyroBlocks.ACTION_COLORS.get(item.type, Color(0.5, 0.5, 0.5))


func _show_empty_hint(text: String) -> void:
	if _empty_label == null or _empty_center == null:
		return
	_empty_label.text = text
	_empty_center.visible = true


func _hide_empty_hint() -> void:
	if _empty_center != null:
		_empty_center.visible = false


func _load_favorites() -> void:
	_favorites.clear()
	var f := FileAccess.open(FAVORITES_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Array:
		for item in (parsed as Array):
			if item is String:
				_favorites.append(str(item))


func _save_favorites() -> void:
	var f := FileAccess.open(FAVORITES_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_favorites))
	f.close()
