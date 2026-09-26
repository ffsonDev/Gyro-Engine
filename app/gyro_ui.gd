class_name GyroUI
extends RefCounted

static var ui_scale := 1.0
static var viewport_size := Vector2(1280.0, 720.0)

static func init_scale(size: Vector2) -> void:
	viewport_size = size
	var base := Vector2(480.0, 720.0)
	ui_scale = clampf(minf(size.x / base.x, size.y / base.y), 0.85, 1.75)

static func fs(base: int) -> int:
	return maxi(10, int(base * ui_scale))

static func sz(base: int) -> int:
	return maxi(26, int(base * ui_scale))

static func dialog_width(base: int) -> int:
	return int(minf(float(base), viewport_size.x - 32.0))

static func clear_children(parent: Control) -> void:
	if parent == null:
		return
	var children := parent.get_children()
	for child in children:
		parent.remove_child(child)
		child.queue_free()

static func save_resource(res: Resource, path: String) -> bool:
	if res == null:
		push_error("GyroUI.save_resource: ресурс равен null.")
		return false
	if path == "":
		push_error("GyroUI.save_resource: пустой путь сохранения.")
		return false
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("GyroUI.save_resource: не удалось сохранить '%s', ошибка: %s" % [path, error_string(err)])
		return false
	return true

static func sanitize_name(raw: String) -> String:
	var clean := raw.strip_edges()
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		clean = clean.replace(ch, "_")
	while clean.contains("__"):
		clean = clean.replace("__", "_")
	clean = clean.trim_prefix("_")
	clean = clean.trim_suffix("_")
	return clean

static func is_bad_name(clean: String) -> bool:
	if clean == "":
		return true
	if clean.replace(".", "") == "":
		return true
	return false

static func alert(root: Control, title_text: String, body_text: String) -> void:
	if root == null:
		push_error("%s: %s" % [title_text, body_text])
		return

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 60

	var dialog := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.17, 0.20)
	style.set_corner_radius_all(12)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	dialog.add_theme_stylebox_override("panel", style)
	center(dialog)
	dialog.z_index = 61

	var vbox := VBoxContainer.new()
	var max_width := root.get_viewport_rect().size.x - 48.0
	vbox.custom_minimum_size = Vector2(minf(460.0, max_width), 0)
	dialog.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	var body := Label.new()
	body.text = body_text
	body.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	body.add_theme_font_size_override("font_size", 16)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)

	var ok := Button.new()
	ok.text = "ОК"
	ok.custom_minimum_size = Vector2(0, 56)
	vbox.add_child(ok)

	root.add_child(overlay)
	root.add_child(dialog)

	var close := func():
		overlay.queue_free()
		dialog.queue_free()
	ok.pressed.connect(close)
	overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventScreenTouch and event.pressed:
			close.call()
		elif event is InputEventMouseButton and event.pressed:
			close.call()
	)

static func icon(path: String, size: int, mod: Color = Color.WHITE) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = load(path)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(size, size)
	rect.size = Vector2(size, size)
	rect.modulate = mod
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

static func icon_button(path: String, size: int, pad: int = 24) -> Button:
	var button := Button.new()
	button.flat = true
	button.custom_minimum_size = Vector2(size + pad, size + pad)

	var rect := TextureRect.new()
	rect.texture = load(path)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.anchor_left = 0.5
	rect.anchor_top = 0.5
	rect.anchor_right = 0.5
	rect.anchor_bottom = 0.5
	rect.offset_left = -float(size) / 2.0
	rect.offset_top = -float(size) / 2.0
	rect.offset_right = float(size) / 2.0
	rect.offset_bottom = float(size) / 2.0
	button.add_child(rect)

	button.button_down.connect(func(): rect.modulate = Color(0.55, 0.55, 0.55))
	button.button_up.connect(func(): rect.modulate = Color.WHITE)
	return button

static func bar_button(icon_path: String, callback: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, sz(72))

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.17, 0.19)
	style.set_corner_radius_all(sz(12))
	button.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.22, 0.23, 0.26)
	button.add_theme_stylebox_override("hover", hover)

	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.10, 0.11, 0.13)
	button.add_theme_stylebox_override("pressed", pressed)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(row)
	row.add_child(icon(icon_path, fs(30)))

	button.pressed.connect(callback)
	return button

static func center(dialog: Control) -> void:
	dialog.anchor_left = 0.5
	dialog.anchor_top = 0.5
	dialog.anchor_right = 0.5
	dialog.anchor_bottom = 0.5
	dialog.offset_left = 0.0
	dialog.offset_top = 0.0
	dialog.offset_right = 0.0
	dialog.offset_bottom = 0.0
	dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialog.grow_vertical = Control.GROW_DIRECTION_BOTH

static func tap_to_close(overlay: ColorRect, callback: Callable) -> void:
	overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventScreenTouch and event.pressed:
			callback.call()
		elif event is InputEventMouseButton and event.pressed:
			callback.call()
	)

static func set_icon(button: Button, path: String) -> void:
	if button.get_child_count() > 0:
		var rect := button.get_child(0) as TextureRect
		if rect != null:
			rect.texture = load(path)

static func styled(button: Button, color: Color, radius: int = 12) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(radius)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.08)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = color.darkened(0.2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)

static func is_tap(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return event.pressed
	if event is InputEventMouseButton:
		return event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	return false

static func attach_tap(control: Control, on_tap: Callable, move_threshold := 24.0) -> void:
	var press_pos := Vector2()
	var moved := false
	control.gui_input.connect(func(event: InputEvent):
		if event is InputEventScreenTouch:
			if event.pressed:
				press_pos = event.position
				moved = false
			elif not moved:
				on_tap.call()
		elif event is InputEventScreenDrag:
			if (event.position - press_pos).length() > move_threshold:
				moved = true
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				press_pos = event.position
				moved = false
			elif not moved:
				on_tap.call()
	)

static func set_orientation(mode: String) -> void:
	match mode:
		"landscape":
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
		"portrait":
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
		_:
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
