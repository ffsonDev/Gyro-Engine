class_name TestRunner
extends RefCounted

signal print_received(message: Variant)
signal stopped

var host: GyroEventHost
var log_label: Label
var _editor: Control
var _merged_blueprint: Callable
var _log_lines: Array = []
var layout: LayoutMode
var _test_bg: ColorRect
var _prev_clear_color := Color.BLACK

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
	
	layout = LayoutMode.new()
	layout.setup(host)
	layout.object_moved.connect(_on_layout_object_moved)
	host.add_child(layout)
	
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
	
	var stop_btn := GyroUI.icon_button("res://ui/icons/close.svg", GyroUI.fs(26))
	stop_btn.name = "TestStopButton"
	stop_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stop_btn.offset_left = -84
	stop_btn.offset_top = 8
	stop_btn.offset_right = -8
	stop_btn.offset_bottom = 64
	stop_btn.z_index = 300
	stop_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	stop_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	
	stop_btn.pressed.connect(_on_stop_pressed)
	host.add_child(stop_btn)
	
	GyroUI.set_orientation(project.settings.orientation if project != null and project.settings != null else "portrait")
	host.refresh_layout.call_deferred()

func _on_stop_pressed() -> void:
	if layout != null and layout.active:
		layout.exit()
	else:
		stop()
		
func _on_layout_object_moved(obj_name: String, pos: Vector2) -> void:
	if _editor != null and _editor.has_method("add_move_node_action"):
		_editor.add_move_node_action(obj_name, pos)

func stop() -> void:
	if layout != null:
		layout.cleanup()
		layout = null
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
