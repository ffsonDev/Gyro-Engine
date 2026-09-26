class_name WidgetSystem
extends GyroSystem

func execute(action: GyroAction, payload: Dictionary) -> void:
	match action.type:
		"CreateInput": _action_create_input(action, payload)
		"CreateSlider": _action_create_slider(action, payload)
		"CreateToggle": _action_create_toggle(action, payload)
		"GetWidgetText": _action_get_widget(action, payload)
		"SetSliderValue": _action_set_slider(action, payload)
		"SetToggleState": _action_set_toggle(action, payload)

func _action_create_input(action: GyroAction, payload: Dictionary) -> void:
	var stage := runtime._get_stage_ui()
	if stage == null:
		return
	var widget_name := GyroEventRuntime.sanitize_node_name(str(runtime._resolve_value(action.data.get("name", ""), payload)))
	if widget_name == "":
		return
	var old := stage.get_node_or_null(NodePath(widget_name))
	if old != null:
		stage.remove_child(old)
		old.free()
	var w := runtime._to_float(runtime._resolve_value(action.data.get("w", 240), payload))
	var pos := Vector2(
		runtime._to_float(runtime._resolve_value(action.data.get("x", 0), payload)),
		runtime._to_float(runtime._resolve_value(action.data.get("y", 0), payload))
	)
	var node: Control
	if runtime._to_bool(runtime._resolve_value(action.data.get("multiline", false), payload)):
		var text_edit := TextEdit.new()
		text_edit.text = str(runtime._resolve_value(action.data.get("text", ""), payload))
		text_edit.text_changed.connect(func():
			runtime.emit_event("widget_changed", {"name": widget_name, "value": text_edit.text})
		)
		node = text_edit
	else:
		var line_edit := LineEdit.new()
		line_edit.text = str(runtime._resolve_value(action.data.get("text", ""), payload))
		line_edit.secret = runtime._to_bool(runtime._resolve_value(action.data.get("secret", false), payload))
		line_edit.text_changed.connect(func(_t: String):
			runtime.emit_event("widget_changed", {"name": widget_name, "value": line_edit.text})
		)
		node = line_edit
	node.name = widget_name
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	node.size = Vector2(w, 48)
	node.position = runtime.apply_anchor(node, widget_name, str(action.data.get("anchor", "free")), pos)
	stage.add_child(node)
	runtime.object_system.last_object_name = widget_name

func _action_create_slider(action: GyroAction, payload: Dictionary) -> void:
	var stage: Control = runtime._get_stage_ui()
	if stage == null:
		return
	var widget_name := GyroEventRuntime.sanitize_node_name(str(runtime._resolve_value(action.data.get("name", ""), payload)))
	if widget_name == "":
		return
	var old: Node = stage.get_node_or_null(NodePath(widget_name))
	if old != null:
		stage.remove_child(old)
		old.free()
	var vertical := runtime._to_bool(runtime._resolve_value(action.data.get("vertical", false), payload))
	var slider: Slider = VSlider.new() if vertical else HSlider.new()
	slider.max_value = 100.0
	slider.value = runtime._to_float(runtime._resolve_value(action.data.get("value", 50), payload))
	slider.name = widget_name
	slider.mouse_filter = Control.MOUSE_FILTER_STOP
	slider.custom_minimum_size = Vector2(48, 200) if vertical else Vector2(200, 48)
	slider.position = runtime.apply_anchor(slider, widget_name, str(action.data.get("anchor", "free")), Vector2(
		runtime._to_float(runtime._resolve_value(action.data.get("x", 0), payload)),
		runtime._to_float(runtime._resolve_value(action.data.get("y", 0), payload))
	))
	slider.value_changed.connect(func(v: float):
		runtime.emit_event("widget_changed", {"name": widget_name, "value": v})
	)
	stage.add_child(slider)
	runtime.object_system.last_object_name = widget_name

func _action_create_toggle(action: GyroAction, payload: Dictionary) -> void:
	var stage := runtime._get_stage_ui()
	if stage == null:
		return
	var widget_name := GyroEventRuntime.sanitize_node_name(str(runtime._resolve_value(action.data.get("name", ""), payload)))
	if widget_name == "":
		return
	var old := stage.get_node_or_null(NodePath(widget_name))
	if old != null:
		stage.remove_child(old)
		old.free()
	var check := CheckBox.new()
	check.button_pressed = runtime._to_bool(runtime._resolve_value(action.data.get("on", false), payload))
	check.name = widget_name
	check.mouse_filter = Control.MOUSE_FILTER_STOP
	check.position = Vector2(
		runtime._to_float(runtime._resolve_value(action.data.get("x", 0), payload)),
		runtime._to_float(runtime._resolve_value(action.data.get("y", 0), payload))
	)
	check.toggled.connect(func(v: bool):
		runtime.emit_event("widget_changed", {"name": widget_name, "value": v})
	)
	stage.add_child(check)
	runtime.object_system.last_object_name = widget_name

func _action_get_widget(action: GyroAction, payload: Dictionary) -> void:
	var variable_name := str(action.data.get("variable", ""))
	if variable_name == "":
		return
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("widget", ""), payload))
	if target == null:
		return
	if "text" in target:
		runtime.variables[variable_name] = target.get("text")
	elif "value" in target:
		runtime.variables[variable_name] = target.get("value")
	elif "button_pressed" in target:
		runtime.variables[variable_name] = target.get("button_pressed")

func _action_set_slider(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("widget", ""), payload))
	if target != null and "value" in target:
		target.set("value", runtime._to_float(runtime._resolve_value(action.data.get("value", 0), payload)))

func _action_set_toggle(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("widget", ""), payload))
	if target != null and "button_pressed" in target:
		target.set("button_pressed", runtime._to_bool(runtime._resolve_value(action.data.get("on", true), payload)))

func on_object_deleted(object_name: String) -> void:
	runtime.physics_system.on_object_deleted(object_name)
	runtime.tag_system.cleanup_tags(object_name)
	var gh := runtime.host as GyroEventHost
	if gh != null:
		gh.unregister_anchor(object_name)

func _get_stage_ui() -> Control:
	if host == null:
		return null
	var ui := host.get_node_or_null(NodePath("StageUI"))
	if ui is Control:
		return ui as Control
	return null
