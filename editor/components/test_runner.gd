class_name TestRunner
extends RefCounted

signal print_received(message: Variant)
signal stopped

const FAB_SIZE := 44.0
const ITEM_SIZE := 40.0
const GAP := 6.0
const PANEL_W := 52.0
const CLOSED_H := 56.0
const OPEN_H := 150.0

var host: GyroEventHost
var log_label: Label
var _editor: Control
var _merged_blueprint: Callable
var _log_lines: Array = []
var layout
var _test_bg: ColorRect
var _prev_clear_color := Color.BLACK

var _fab_panel: Control
var _bar_bg: PanelContainer
var _fab_button: Button
var _layout_btn: Button
var _exit_btn: Button
var _menu_overlay: ColorRect
var _menu_open := false
var _tween: Tween

func setup(editor_node: Node, merged_fn: Callable) -> void:
	_editor = editor_node
	_merged_blueprint = merged_fn

var is_running: bool:
	get: return host != null

func start(project: GyroProject, project_path: String) -> void:
	stop()
	if _editor == null or not _editor.is_inside_tree():
		return
	
	host = GyroEventHost.new()
	if _merged_blueprint.is_valid():
		host.blueprint = _merged_blueprint.call()
	host.project = project
	host.project_path = project_path
	host.runtime.print_handler = _on_print
	
	var root := _editor.get_tree().root
	root.add_child(host)
	host.z_index = 100
	host.refresh_layout()
	
	_prev_clear_color = RenderingServer.get_default_clear_color()
	RenderingServer.set_default_clear_color(Color.BLACK)
	
	var layout_script = load("res://editor/components/layout_mode.gd")
	if layout_script:
		layout = layout_script.new()
		if layout and layout.has_method("setup"):
			layout.call("setup", host)
		if layout and layout.has_signal("object_moved"):
			layout.connect("object_moved", _on_layout_object_moved)
		if layout:
			host.add_child(layout)
			_hide_layout_toolbar()
	
	log_label = Label.new()
	log_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	log_label.add_theme_font_size_override("font_size", GyroUI.fs(18))
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_label.z_index = 150
	host.add_child(log_label)
	log_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_label.offset_left = 8
	log_label.offset_right = -8
	log_label.offset_top = -180
	log_label.offset_bottom = -8
	log_label.visible = GyroAppSettings.load_settings().show_test_log
	log_label.text = ""
	
	_build_fab()
	
	GyroUI.set_orientation(project.settings.orientation if project != null and project.settings != null else "portrait")
	host.refresh_layout.call_deferred()

func _build_fab() -> void:
	_menu_overlay = ColorRect.new()
	_menu_overlay.color = Color(0, 0, 0, 0)
	_menu_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_overlay.visible = false
	_menu_overlay.z_index = 299
	_menu_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton or event is InputEventScreenTouch:
			if event.pressed:
				_close_menu()
	)
	host.add_child(_menu_overlay)
	
	_fab_panel = Control.new()
	_fab_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fab_panel.offset_left = -PANEL_W - 12
	_fab_panel.offset_top = 12
	_fab_panel.offset_right = -12
	_fab_panel.offset_bottom = 12 + OPEN_H
	_fab_panel.z_index = 300
	_fab_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_fab_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(_fab_panel)
	
	_bar_bg = PanelContainer.new()
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.10, 0.11, 0.14, 0.85)
	bar_style.set_corner_radius_all(22)
	_bar_bg.add_theme_stylebox_override("panel", bar_style)
	_bar_bg.position = Vector2.ZERO
	_bar_bg.size = Vector2(PANEL_W, CLOSED_H)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fab_panel.add_child(_bar_bg)
	
	_fab_button = _make_round_button("res://ui/icons/burger.svg", FAB_SIZE, Color(0.16, 0.18, 0.22))
	_fab_button.position = Vector2((PANEL_W - FAB_SIZE) * 0.5, GAP)
	_fab_button.pressed.connect(_toggle_menu)
	_fab_panel.add_child(_fab_button)
	
	_layout_btn = _make_round_button("res://ui/icons/layout.svg", ITEM_SIZE, Color(0.22, 0.25, 0.30))
	_layout_btn.position = Vector2((PANEL_W - ITEM_SIZE) * 0.5, GAP + FAB_SIZE + GAP)
	_layout_btn.pressed.connect(_on_layout_pressed)
	_fab_panel.add_child(_layout_btn)
	
	_exit_btn = _make_round_button("res://ui/icons/close.svg", ITEM_SIZE, Color(0.72, 0.22, 0.22))
	_exit_btn.position = Vector2((PANEL_W - ITEM_SIZE) * 0.5, GAP + FAB_SIZE + GAP + ITEM_SIZE + GAP)
	_exit_btn.pressed.connect(_on_exit_pressed)
	_fab_panel.add_child(_exit_btn)
	
	for btn in [_layout_btn, _exit_btn]:
		btn.scale = Vector2.ZERO
		btn.modulate.a = 0
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _make_round_button(icon_path: String, side: float, base: Color) -> Button:
	var btn := Button.new()
	btn.size = Vector2(side, side)
	btn.pivot_offset = Vector2(side, side) * 0.5
	btn.icon = load(icon_path)
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.add_theme_constant_override("icon_max_width", int(side * 0.55))
	_apply_round_style(btn, base, side * 0.5)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	return btn

func _apply_round_style(btn: Button, base: Color, radius: float) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(base.r, base.g, base.b, 0.90)
	normal.set_corner_radius_all(int(radius))
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = base.lightened(0.1)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = base.darkened(0.2)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("icon_normal_color", Color(0.95, 0.95, 0.95))
	btn.add_theme_color_override("icon_hover_color", Color.WHITE)
	btn.add_theme_color_override("icon_pressed_color", Color.WHITE)

func _hide_layout_toolbar() -> void:
	if layout == null:
		return
	if "toolbar" in layout and layout.toolbar != null:
		layout.toolbar.visible = false
		layout.toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _refresh_layout_btn() -> void:
	if _layout_btn == null:
		return
	var active = layout != null and "active" in layout and bool(layout.active)
	_apply_round_style(_layout_btn, Color(0.11, 0.55, 0.62) if active else Color(0.22, 0.25, 0.30), ITEM_SIZE * 0.5)

func _toggle_menu() -> void:
	if _menu_open:
		_close_menu()
	else:
		_open_menu()

func _open_menu() -> void:
	if _menu_open:
		return
	_menu_open = true
	_refresh_layout_btn()
	_menu_overlay.visible = true
	_layout_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_exit_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_kill_tween()
	_tween = _editor.get_tree().create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_parallel(true)
	_tween.tween_property(_menu_overlay, "color:a", 0.3, 0.2)
	_tween.tween_property(_bar_bg, "size:y", OPEN_H, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_fab_button, "rotation", PI * 0.5, 0.2)
	var items := [_layout_btn, _exit_btn]
	for i in items.size():
		var btn: Button = items[i]
		var d := 0.06 + float(i) * 0.05
		_tween.tween_property(btn, "scale", Vector2.ONE, 0.22).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(btn, "modulate:a", 1.0, 0.15).set_delay(d)

func _close_menu() -> void:
	if not _menu_open:
		return
	_menu_open = false
	_kill_tween()
	_tween = _editor.get_tree().create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_parallel(true)
	_tween.tween_property(_menu_overlay, "color:a", 0.0, 0.15)
	_tween.tween_property(_bar_bg, "size:y", CLOSED_H, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_fab_button, "rotation", 0.0, 0.2)
	var items := [_exit_btn, _layout_btn]
	for i in items.size():
		var btn: Button = items[i]
		var d := float(i) * 0.03
		_tween.tween_property(btn, "scale", Vector2.ZERO, 0.15).set_delay(d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_tween.tween_property(btn, "modulate:a", 0.0, 0.12).set_delay(d)
	_tween.chain().tween_callback(func():
		_menu_overlay.visible = false
		_layout_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_exit_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	)

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

func _on_exit_pressed() -> void:
	_close_menu()
	stop()

func _on_layout_pressed() -> void:
	_close_menu()
	if layout == null:
		return
	if "active" in layout and bool(layout.active):
		if layout.has_method("exit"):
			layout.call("exit")
	else:
		if layout.has_method("enter"):
			layout.call("enter")
	_refresh_layout_btn()
	_hide_layout_toolbar()

func _on_layout_object_moved(obj_name: String, pos: Vector2) -> void:
	if _editor != null and _editor.has_method("add_move_node_action"):
		_editor.add_move_node_action(obj_name, pos)

func stop() -> void:
	_kill_tween()
	if layout != null:
		if layout.has_method("cleanup"):
			layout.call("cleanup")
		layout = null
	if _fab_panel != null:
		_fab_panel.queue_free()
		_fab_panel = null
		_bar_bg = null
		_fab_button = null
		_layout_btn = null
		_exit_btn = null
	if _menu_overlay != null:
		_menu_overlay.queue_free()
		_menu_overlay = null
	if host != null:
		if host.get_parent() != null:
			host.get_parent().remove_child(host)
		host.queue_free()
		host = null
	if log_label != null:
		log_label.queue_free()
		log_label = null
	RenderingServer.set_default_clear_color(_prev_clear_color)
	GyroUI.set_orientation("portrait")
	stopped.emit()

func _on_runtime_print(message: Variant) -> void:
	if log_label == null:
		return
	_log_lines.append(str(message))
	while _log_lines.size() > 10:
		_log_lines.pop_front()
	log_label.text = "\n".join(_log_lines)

func _on_print(message: Variant) -> void:
	var text := str(message) + "\n"
	if log_label != null:
		log_label.text = log_label.text + text
	print_received.emit(message)

func emit_back() -> void:
	if host != null and host.runtime.has_event("back"):
		host.emit_event("back", {})
	else:
		stop()
