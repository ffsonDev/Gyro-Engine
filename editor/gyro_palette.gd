class_name GyroPalette
extends Control
signal item_down(item: Dictionary)

var color_for: Callable
var search_edit: LineEdit
var list_vbox: VBoxContainer

func _ready() -> void:
	search_edit = get_node_or_null("%SearchEdit") as LineEdit
	if search_edit == null:
		search_edit = get_node_or_null("Header/SearchEdit") as LineEdit
	list_vbox = get_node_or_null("%ListVBox") as VBoxContainer
	if list_vbox == null:
		list_vbox = get_node_or_null("Scroll/ListVBox") as VBoxContainer
	var back_btn = get_node_or_null("%BackButton") as Button
	if back_btn == null:
		back_btn = get_node_or_null("Header/BackButton") as Button
	if back_btn != null:
		back_btn.pressed.connect(close)
	if search_edit != null:
		search_edit.placeholder_text = GyroLang.t("search")
		search_edit.text_changed.connect(func(_t: String): _rebuild_list(search_edit.text))
	var scroll = get_node_or_null("%Scroll") as ScrollContainer
	if scroll == null:
		scroll = get_node_or_null("Scroll") as ScrollContainer
	if scroll != null:
		var touch_scroll := GyroTouchScroll.new()
		add_child(touch_scroll)
		touch_scroll.setup(scroll)
	apply_lang()

func close() -> void:
	visible = false
	if search_edit != null:
		search_edit.text = ""
	_rebuild_list("")

func apply_lang() -> void:
	_rebuild_list("")

func _rebuild_list(query: String) -> void:
	if list_vbox == null:
		return
	GyroUI.clear_children(list_vbox)
	var q := query.strip_edges().to_lower()
	for section in GyroBlocks.palette_sections():
		var visible_items: Array = []
		for item in section.items:
			if q == "" or str(item.name).to_lower().contains(q):
				visible_items.append(item)
		if visible_items.is_empty():
			continue
		var header := Label.new()
		header.text = str(section.title)
		header.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
		header.add_theme_font_size_override("font_size", GyroUI.fs(16))
		list_vbox.add_child(header)
		for item in visible_items:
			list_vbox.add_child(_make_item_button(item))

func _make_item_button(item: Dictionary) -> Button:
	var button := Button.new()
	button.text = "  " + str(item.name)
	button.custom_minimum_size = Vector2(0, GyroUI.sz(64))
	button.add_theme_font_size_override("font_size", GyroUI.fs(18))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	
	var style := StyleBoxFlat.new()
	style.bg_color = _color_for(item)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	var pressed_style := style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = style.bg_color.darkened(0.2)
	button.add_theme_stylebox_override("pressed", pressed_style)
	
	button.pressed.connect(func():
		item_down.emit(item)
	)
	return button

func _color_for(item: Dictionary) -> Color:
	if color_for.is_valid():
		return color_for.call(str(item.kind), str(item.type))
	if item.kind == "event":
		return GyroBlocks.COLOR_EVENT
	if item.kind == "condition":
		return GyroBlocks.CONDITION_COLORS.get(item.type, Color(0.45, 0.5, 0.3))
	return GyroBlocks.ACTION_COLORS.get(item.type, Color(0.5, 0.5, 0.5))
