class_name GyroUI
extends RefCounted

const MIN_FONT_SIZE := 10
const MIN_CONTROL_SIZE := 26

static var ui_scale := 1.0
static var viewport_size := Vector2(1280.0, 720.0)
static var transition: ScreenTransition

static var _glass_style: StyleBoxFlat = null
static var _row_style_cache := {}
static var _guide_cache := {}

static func init_scale(size: Vector2) -> void:
	viewport_size = size
	var base := Vector2(480.0, 480.0)
	ui_scale = clampf(minf(size.x / base.x, size.y / base.y), 0.85, 1.75)

static func fs(base: int) -> int:
	return maxi(MIN_FONT_SIZE, int(base * ui_scale))

static func sz(base: int) -> int:
	return maxi(MIN_CONTROL_SIZE, int(base * ui_scale))

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
		return false
	if path == "":
		return false
	if res.has_method("mark_modified"):
		res.mark_modified()
	if path.ends_with(".json"):
		return GyroProjectJSON.save_to_file(res as GyroProject, path)
	var err := ResourceSaver.save(res, path)
	if err != OK:
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
		return
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 60
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dialog := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = DesignTokens.PANEL_BG
	style.set_corner_radius_all(DesignTokens.RADIUS_XL)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = DesignTokens.PANEL_BORDER
	style.content_margin_left = DesignTokens.SPACING_XL
	style.content_margin_right = DesignTokens.SPACING_XL
	style.content_margin_top = DesignTokens.SPACING_XL
	style.content_margin_bottom = DesignTokens.SPACING_XL
	dialog.add_theme_stylebox_override("panel", style)
	center(dialog)
	dialog.z_index = 61
	dialog.modulate.a = 0.0
	dialog.scale = Vector2(0.9, 0.9)
	dialog.pivot_offset = Vector2(230, 100)

	var vbox := VBoxContainer.new()
	var max_width := root.get_viewport_rect().size.x - 48.0
	vbox.custom_minimum_size = Vector2(minf(460.0, max_width), 0)
	vbox.add_theme_constant_override("separation", DesignTokens.SPACING_MD)
	dialog.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
	title.add_theme_font_size_override("font_size", DesignTokens.FONT_TITLE)
	vbox.add_child(title)

	var body := Label.new()
	body.text = body_text
	body.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_SECONDARY)
	body.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)

	var ok := Button.new()
	ok.text = GyroLang.t("ok")
	ok.custom_minimum_size = Vector2(0, GyroUI.sz(56))
	vbox.add_child(ok)

	root.add_child(overlay)
	root.add_child(dialog)

	var close := func():
		var tw_out := dialog.create_tween()
		tw_out.set_parallel(true)
		tw_out.tween_property(dialog, "scale", Vector2(0.9, 0.9), DesignTokens.ANIM_FAST).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw_out.tween_property(dialog, "modulate:a", 0.0, DesignTokens.ANIM_FAST)
		tw_out.tween_property(overlay, "color:a", 0.0, DesignTokens.ANIM_FAST)
		tw_out.set_parallel(false)
		tw_out.tween_callback(func():
			overlay.queue_free()
			dialog.queue_free()
		)

	ok.pressed.connect(close)
	overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventScreenTouch and event.pressed:
			close.call()
		elif event is InputEventMouseButton and event.pressed:
			close.call()
	)

	var tw_in := dialog.create_tween()
	tw_in.set_parallel(true)
	tw_in.tween_property(overlay, "color:a", 0.6, DesignTokens.ANIM_NORMAL)
	tw_in.tween_property(dialog, "scale", Vector2.ONE, DesignTokens.ANIM_SPRING).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_in.tween_property(dialog, "modulate:a", 1.0, DesignTokens.ANIM_NORMAL).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

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
	button.button_down.connect(func():
		var tw := rect.create_tween()
		tw.tween_property(rect, "modulate", Color(0.55, 0.55, 0.55), DesignTokens.ANIM_FAST)
	)
	button.button_up.connect(func():
		var tw := rect.create_tween()
		tw.tween_property(rect, "modulate", Color.WHITE, DesignTokens.ANIM_FAST)
	)
	return button

static func bar_button(icon_path: String, callback: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, sz(72))
	var style := StyleBoxFlat.new()
	style.bg_color = DesignTokens.COLOR_SURFACE_1
	style.set_corner_radius_all(DesignTokens.RADIUS_LG)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = DesignTokens.COLOR_BORDER
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = DesignTokens.COLOR_SURFACE_2
	button.add_theme_stylebox_override("hover", hover)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = DesignTokens.COLOR_ACCENT_SOFT
	pressed.border_color = DesignTokens.COLOR_ACCENT
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

const HOLD_DRAG_DELAY := 0.5

static func attach_tap(control: Control, on_tap: Callable, move_threshold := 24.0) -> void:
	var press_pos := Vector2()
	var moved := false
	control.gui_input.connect(func(event: InputEvent):
		if event is InputEventScreenTouch:
			if event.pressed:
				press_pos = event.position
				moved = false
			elif not moved:
				if control.get_meta("gyro_hold_fired", false):
					control.set_meta("gyro_hold_fired", false)
					return
				on_tap.call()
		elif event is InputEventScreenDrag:
			if (event.position - press_pos).length() > move_threshold:
				moved = true
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				press_pos = event.position
				moved = false
			elif not moved:
				if control.get_meta("gyro_hold_fired", false):
					control.set_meta("gyro_hold_fired", false)
					return
				on_tap.call()
	)

static func attach_hold_drag(control: Control, on_start: Callable, delay := HOLD_DRAG_DELAY, move_threshold := 24.0) -> void:
	var state := {"active": false, "pos": Vector2.ZERO, "token": 0}
	var wr: WeakRef = weakref(control)
	control.gui_input.connect(func(event: InputEvent):
		var c := wr.get_ref() as Control
		if c == null or not is_instance_valid(c):
			return
		if event is InputEventScreenTouch:
			if event.pressed:
				state.active = true
				state.pos = event.position
				state.token += 1
				var token: int = state.token
				c.get_tree().create_timer(delay).timeout.connect(func():
					if token != state.token or not state.active:
						return
					var cc := wr.get_ref() as Control
					if cc == null or not is_instance_valid(cc):
						return
					state.active = false
					cc.set_meta("gyro_hold_fired", true)
					on_start.call()
				)
			else:
				state.active = false
		elif event is InputEventScreenDrag:
			if state.active and (event.position - state.pos).length() > move_threshold:
				state.active = false
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				state.active = true
				state.pos = event.position
				state.token += 1
				var token: int = state.token
				c.get_tree().create_timer(delay).timeout.connect(func():
					if token != state.token or not state.active:
						return
					var cc := wr.get_ref() as Control
					if cc == null or not is_instance_valid(cc):
						return
					state.active = false
					cc.set_meta("gyro_hold_fired", true)
					on_start.call()
				)
			else:
				state.active = false
		elif event is InputEventMouseMotion:
			if state.active and (event.position - state.pos).length() > move_threshold:
				state.active = false
	)

static func stagger_children(parent: Control, delay_per_item: float = 0.04) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var i := 0
	for child in parent.get_children():
		if child is Control:
			var c := child as Control
			c.modulate.a = 0.0
			c.scale = Vector2(0.95, 0.95)
			var tw := c.create_tween()
			tw.set_parallel(true)
			tw.tween_property(c, "modulate:a", 1.0, DesignTokens.ANIM_NORMAL).set_delay(float(i) * delay_per_item).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(c, "scale", Vector2.ONE, DesignTokens.ANIM_SLOW).set_delay(float(i) * delay_per_item).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			i += 1

static func apply_background(parent: Control) -> void:
	var old_bg := parent.get_node_or_null("Background")
	if old_bg != null:
		parent.remove_child(old_bg)
		old_bg.queue_free()
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = DesignTokens.COLOR_SURFACE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.z_index = -1
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	parent.move_child(bg, 0)

static func glass_panel_style() -> StyleBoxFlat:
	if _glass_style == null:
		_glass_style = StyleBoxFlat.new()
		_glass_style.bg_color = DesignTokens.PANEL_BG
		_glass_style.set_corner_radius_all(DesignTokens.RADIUS_XL)
		_glass_style.border_width_left = 2
		_glass_style.border_width_right = 2
		_glass_style.border_width_top = 2
		_glass_style.border_width_bottom = 2
		_glass_style.border_color = DesignTokens.PANEL_BORDER
		_glass_style.content_margin_left = DesignTokens.SPACING_XL
		_glass_style.content_margin_right = DesignTokens.SPACING_XL
		_glass_style.content_margin_top = DesignTokens.SPACING_XL
		_glass_style.content_margin_bottom = DesignTokens.SPACING_XL
	return _glass_style

static func apply_glass_style(panel: PanelContainer) -> void:
	panel.add_theme_stylebox_override("panel", glass_panel_style())

static func row_style(selected: bool, with_shadow: bool = false) -> StyleBoxFlat:
	var key := "sel_%s_sh_%s" % [str(selected), str(with_shadow)]
	if _row_style_cache.has(key):
		return (_row_style_cache[key] as StyleBoxFlat).duplicate() as StyleBoxFlat
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(DesignTokens.RADIUS_LG)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	if selected:
		style.bg_color = DesignTokens.COLOR_ACCENT_SOFT
		style.border_color = DesignTokens.COLOR_BORDER
	else:
		style.bg_color = DesignTokens.COLOR_SURFACE_1
		style.border_color = DesignTokens.COLOR_BORDER
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	if with_shadow:
		style.shadow_offset = Vector2(0, 3)
	_row_style_cache[key] = style
	return style.duplicate() as StyleBoxFlat

static func make_guide(depth: int, row_height: int, with_stub: bool) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := float(row_height) * 0.5
	for i in depth:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(14, row_height)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vline := ColorRect.new()
		vline.color = Color(0.35, 0.37, 0.40)
		vline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vline.anchor_top = 0.0
		vline.anchor_bottom = 1.0
		vline.anchor_left = 0.0
		vline.anchor_right = 0.0
		vline.offset_left = 6.0
		vline.offset_right = 8.0
		slot.add_child(vline)
		if i == depth - 1 and with_stub:
			var hline := ColorRect.new()
			hline.color = Color(0.35, 0.37, 0.40)
			hline.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hline.anchor_top = 0.0
			hline.anchor_bottom = 0.0
			hline.anchor_left = 0.0
			hline.anchor_right = 0.0
			hline.offset_left = 6.0
			hline.offset_right = 14.0
			hline.offset_top = center - 1.0
			hline.offset_bottom = center + 1.0
			slot.add_child(hline)
		box.add_child(slot)
	return box

static func set_orientation(mode: String) -> void:
	match mode:
		"landscape":
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
		"portrait":
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
		_:
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
	var tree := Engine.get_main_loop()
	if tree == null:
		return
	_notify_hosts_recursive(tree.root, mode)

static func _notify_hosts_recursive(node: Node, mode: String) -> void:
	if node == null:
		return
	if node is GyroEventHost and node.has_method("set_orientation"):
		node.set_orientation(mode)
	for child in node.get_children():
		_notify_hosts_recursive(child, mode)
