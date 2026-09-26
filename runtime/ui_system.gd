class_name UISystem
extends GyroSystem

func execute(action: GyroAction, payload: Dictionary) -> void:
	match action.type:
		"Print":
			var message = runtime._resolve_value(action.data.get("message", ""), payload)
			if runtime.print_handler.is_valid():
				runtime.print_handler.call(message)
			else:
				print(message)
		"Toast":
			_action_toast(action, payload)
		"SetBackgroundColor":
			_action_set_background_color(action, payload)
		"SetOrientation":
			GyroUI.set_orientation(str(runtime._resolve_value(action.data.get("mode", "portrait"), payload)))
		"Clipboard":
			_action_clipboard(action, payload)
		"OpenURL":
			OS.shell_open(str(runtime._resolve_value(action.data.get("url", ""), payload)))
		"Quit":
			if host != null and host.is_inside_tree():
				host.get_tree().quit()
		"RandomSeed":
			seed(int(runtime._to_float(runtime._resolve_value(action.data.get("seed", 0), payload))))

func _action_toast(action: GyroAction, payload: Dictionary) -> void:
	if host == null or not host.is_inside_tree():
		return
	var label := Label.new()
	label.text = str(runtime._resolve_value(action.data.get("text", ""), payload))
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.9)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(label)
	host.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position.y -= 90
	panel.modulate.a = 0.0
	var tw := host.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.0)
	tw.tween_property(panel, "modulate:a", 0.0, 0.3)
	tw.tween_callback(panel.queue_free)

func _action_set_background_color(action: GyroAction, payload: Dictionary) -> void:
	if host == null:
		return
	var color := runtime._parse_color(str(runtime._resolve_value(action.data.get("color", "#000000"), payload)))
	var bg := host.get_node_or_null(NodePath("GyroBackground")) as ColorRect
	if bg == null:
		bg = ColorRect.new()
		bg.name = "GyroBackground"
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.z_index = 0
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(bg)
		host.move_child(bg, 0)
	bg.color = color

func _action_clipboard(action: GyroAction, payload: Dictionary) -> void:
	if str(action.data.get("mode", "set")) == "get":
		var variable_name := str(action.data.get("variable", ""))
		if variable_name != "":
			runtime.variables[variable_name] = DisplayServer.clipboard_get()
	else:
		DisplayServer.clipboard_set(str(runtime._resolve_value(action.data.get("text", ""), payload)))
