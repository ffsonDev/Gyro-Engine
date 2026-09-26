class_name TagSystem
extends GyroSystem

var tags := {}

func execute(action: GyroAction, payload: Dictionary) -> void:
	match action.type:
		"AddTag":
			_action_add_tag(action, payload)
		"DeleteByTag":
			_for_each_tag(action, payload, func(n: Node): _delete_node(n))
		"SetVisibleByTag":
			_for_each_tag(action, payload, func(n: Node): n.visible = runtime._to_bool(runtime._resolve_value(action.data.get("on", true), payload)))
		"SetPositionByTag":
			_for_each_tag(action, payload, func(n: Node): _apply_position_tag(n, action, payload))
		"SetRotationByTag":
			_for_each_tag(action, payload, func(n: Node):
				if "rotation" in n:
					n.set("rotation", deg_to_rad(runtime._to_float(runtime._resolve_value(action.data.get("angle", 0), payload)))))
		"SetOpacityByTag":
			_for_each_tag(action, payload, func(n: Node):
				var c: Color = n.modulate
				c.a = clampf(runtime._to_float(runtime._resolve_value(action.data.get("value", 100), payload)), 0.0, 100.0) / 100.0
				n.modulate = c
			)
		"SetScaleByTag":
			_for_each_tag(action, payload, func(n: Node):
				if "scale" in n:
					var p := runtime._to_float(runtime._resolve_value(action.data.get("percent", 100), payload)) / 100.0
					n.set("scale", Vector2(p, p))
			)
		"ChangeLayerByTag":
			_for_each_tag(action, payload, func(n: Node):
				if "z_index" in n:
					n.set("z_index", int(n.get("z_index")) + int(runtime._to_float(runtime._resolve_value(action.data.get("dir", 1), payload))))
			)

func _action_add_tag(action: GyroAction, payload: Dictionary) -> void:
	var object_name := runtime._name_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	var tag := str(runtime._resolve_value(action.data.get("tag", ""), payload))
	if object_name == "" or tag == "":
		return
	if not tags.has(tag):
		tags[tag] = []
	if not (tags[tag] as Array).has(object_name):
		(tags[tag] as Array).append(object_name)

func cleanup_tags(object_name: String) -> void:
	for key in tags.keys():
		(tags[key] as Array).erase(object_name)

func _delete_node(n: Node) -> void:
	runtime.object_system.on_object_deleted(n.name)
	n.queue_free()

func _for_each_tag(action: GyroAction, payload: Dictionary, fn: Callable) -> void:
	var tag := str(runtime._resolve_value(action.data.get("tag", ""), payload))
	var names: Array = (tags.get(tag, []) as Array).duplicate()
	for name_value in names:
		var n := runtime._get_target_node(str(name_value))
		if n != null:
			fn.call(n)

func _apply_position_tag(n: Node, action: GyroAction, payload: Dictionary) -> void:
	var current_value = n.get("position")
	if not (current_value is Vector2):
		return
	var current := current_value as Vector2
	var x := runtime._to_float(runtime._resolve_value(action.data.get("x", 0), payload))
	var y := runtime._to_float(runtime._resolve_value(action.data.get("y", 0), payload))
	if str(action.data.get("mode", "set")) == "add":
		n.set("position", current + Vector2(x, y))
	else:
		n.set("position", Vector2(x, y))
