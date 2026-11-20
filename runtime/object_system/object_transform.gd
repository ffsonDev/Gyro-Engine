class_name ObjectTransform
extends RefCounted

var runtime: GyroEventRuntime
var aabb: ObjectAABB

func _init(rt: GyroEventRuntime, a: ObjectAABB) -> void:
	runtime = rt
	aabb = a

func execute_move_node(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null or not (target is Node2D):
		return
	var mode := str(action.data.get("mode", "delta"))
	var x_value = action.data.get("x", null)
	var y_value = action.data.get("y", null)
	var current: Vector2 = target.position
	var new_x: float = current.x
	var new_y: float = current.y
	if x_value != null:
		new_x = runtime._to_float(runtime._resolve_value(x_value, payload))
	if y_value != null:
		new_y = runtime._to_float(runtime._resolve_value(y_value, payload))
	if mode == "set":
		target.position = Vector2(new_x, new_y)
		target.set_meta("gyro_anchor", "")
		target.set_meta("gyro_anchor_offset", Vector2.ZERO)
		runtime.host.unregister_anchor(target.name)
	else:
		target.position = current + Vector2(new_x, new_y)
	aabb.update_aabb(target)
	if target.has_meta("gyro_anchor") and str(target.get_meta("gyro_anchor")) != "":
		var anchor := str(target.get_meta("gyro_anchor"))
		var vp: Variant = runtime.host.get_viewport_rect().size
		var anchor_pt: Variant = runtime.host.anchor_point(vp, anchor)
		target.set_meta("gyro_anchor_offset", target.position - anchor_pt)

func execute_set_node_property(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var property_name := str(action.data.get("property", ""))
	if property_name == "" or not runtime.ALLOWED_NODE_PROPERTIES.has(property_name):
		return
	var value = runtime._resolve_value(action.data.get("value", null), payload)
	match property_name:
		"position":
			var current: Vector2 = target.position
			var x_value = action.data.get("x", null)
			var y_value = action.data.get("y", null)
			if x_value != null:
				current.x = runtime._to_float(runtime._resolve_value(x_value, payload))
			if y_value != null:
				current.y = runtime._to_float(runtime._resolve_value(y_value, payload))
			if x_value == null and y_value == null and value is Vector2:
				current = value
			target.position = current
			target.set_meta("gyro_anchor", "")
			target.set_meta("gyro_anchor_offset", Vector2.ZERO)
			runtime.host.unregister_anchor(target.name)
			aabb.update_aabb(target)
		"size":
			execute_set_size(action, payload)
		"visible":
			target.visible = runtime._to_bool(value)
		"z_index":
			target.z_index = int(runtime._to_float(value))
		"rotation":
			target.rotation = float(runtime._to_float(value))
			aabb.update_aabb(target)
		"scale":
			if value is Vector2:
				target.scale = value
			elif value is String:
				var parts := str(value).split(",")
				if parts.size() == 2:
					target.scale = Vector2(float(parts[0]), float(parts[1]))
			elif value is Dictionary:
				var d := value as Dictionary
				target.scale = Vector2(float(d.get("x", 1)), float(d.get("y", 1)))
			aabb.update_aabb(target)
		"modulate":
			if value is Color:
				target.modulate = value
			elif value is String:
				target.modulate = runtime._parse_color(str(value))
		"text":
			var lb := ObjectUtils.get_label(target)
			if lb != null:
				lb.text = str(value)
		"color":
			var color_value = action.data.get("value", action.data.get("color", "#ffffff"))
			var color := runtime._parse_color(str(runtime._resolve_value(color_value, payload)))
			var visual := ObjectUtils.get_visual(target)
			if visual == null:
				return
			if visual is Sprite2D:
				(visual as Sprite2D).modulate = color
			elif visual is Label:
				(visual as Label).add_theme_color_override("font_color", color)
			elif visual is Polygon2D:
				(visual as Polygon2D).color = color

func execute_set_size(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var visual := ObjectUtils.get_visual(target)
	if visual == null:
		return
	var node_2d := target as Node2D
	if node_2d == null:
		return
	var pivot_global: Vector2 = node_2d.to_global(ObjectUtils.get_pivot(node_2d))
	var old_bounds: Dictionary = ObjectUtils.get_visual_bounds(visual)
	var old_size: Vector2 = old_bounds["size"]
	var w_value: Variant = action.data.get("w", null)
	var h_value: Variant = action.data.get("h", null)
	var new_w: float = old_size.x
	var new_h: float = old_size.y
	if w_value != null:
		new_w = runtime._to_float(runtime._resolve_value(w_value, payload))
	if h_value != null:
		new_h = runtime._to_float(runtime._resolve_value(h_value, payload))
	if visual is Sprite2D:
		var sp := visual as Sprite2D
		var tex_size: Vector2 = sp.texture.get_size() if sp.texture != null else Vector2(1, 1)
		sp.scale = Vector2(new_w / maxf(1.0, tex_size.x), new_h / maxf(1.0, tex_size.y))
	elif visual is Label:
		var lb := visual as Label
		lb.custom_minimum_size = Vector2(new_w, new_h)
		lb.size = Vector2(new_w, new_h)
		lb.clip_contents = true
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	elif visual is Polygon2D:
		var pg := visual as Polygon2D
		var sx: float = new_w / maxf(1.0, old_size.x)
		var sy: float = new_h / maxf(1.0, old_size.y)
		var new_poly := PackedVector2Array()
		for p in pg.polygon:
			new_poly.append(p * Vector2(sx, sy))
		pg.polygon = new_poly
	if old_size.x > 0.0 and old_size.y > 0.0:
		var piv2 := ObjectUtils.get_pivot(node_2d)
		var offset: Vector2 = node_2d.to_global(piv2) - node_2d.global_position
		node_2d.global_position = pivot_global - offset
	if runtime.physics_system != null:
		runtime.physics_system.update_collision_shape(node_2d)

func execute_set_rotation(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null or not (target is Node2D):
		return
	var root := target as Node2D
	var angle := runtime._to_float(runtime._resolve_value(action.data.get("angle", 0), payload))
	var mode := str(action.data.get("mode", "set"))
	if mode == "add":
		angle += rad_to_deg(root.rotation)
	var piv := ObjectUtils.get_pivot(root)
	var pivot_global: Vector2 = root.to_global(piv)
	root.rotation = deg_to_rad(angle)
	var offset: Vector2 = root.to_global(piv) - root.global_position
	root.global_position = pivot_global - offset
	aabb.update_aabb(root)

func execute_set_scale(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null or not (target is Node2D):
		return
	var root := target as Node2D
	var visual := ObjectUtils.get_visual(target)
	if visual == null:
		return
	var piv := ObjectUtils.get_pivot(root)
	var pivot_global: Vector2 = root.to_global(piv)
	var old_scale: Vector2 = visual.scale
	var percent: Variant = action.data.get("percent", null)
	var xv: Variant = action.data.get("x", null)
	var yv: Variant = action.data.get("y", null)
	var new_scale: Vector2 = root.scale
	if percent != null and str(percent) != "":
		var p := runtime._to_float(runtime._resolve_value(percent, payload)) / 100.0
		new_scale = Vector2(p, p)
	else:
		if xv != null and str(xv) != "":
			new_scale.x = runtime._to_float(runtime._resolve_value(xv, payload)) / 100.0
		if yv != null and str(yv) != "":
			new_scale.y = runtime._to_float(runtime._resolve_value(yv, payload)) / 100.0
	root.scale = new_scale
	var offset: Vector2 = root.to_global(piv) - root.global_position
	root.global_position = pivot_global - offset
	aabb.update_aabb(root)
	if runtime.physics_system != null:
		runtime.physics_system.update_collision_shape(root)

func execute_change_layer(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null or not (target is Node2D):
		return
	var dir := int(runtime._to_float(runtime._resolve_value(action.data.get("dir", 1), payload)))
	target.z_index = int(target.z_index) + dir

func execute_set_pivot(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null or not (target is Node2D):
		return
	var root := target as Node2D
	var visual := ObjectUtils.get_visual(root)
	if visual == null:
		return
	var bounds: Dictionary = ObjectUtils.get_visual_bounds(visual)
	var w: float = bounds["size"].x
	var h: float = bounds["size"].y
	var origin: Vector2 = bounds["origin"]
	if w <= 0.0 or h <= 0.0:
		return
	var px := runtime._to_float(runtime._resolve_value(action.data.get("x", 50), payload)) / 100.0
	var py := runtime._to_float(runtime._resolve_value(action.data.get("y", 50), payload)) / 100.0
	ObjectUtils.set_pivot(root, origin + Vector2(w * px, h * py))
	if runtime.physics_system != null:
		runtime.physics_system.update_collision_shape(root)

func execute_face_object(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	var other := runtime._node_from_value(runtime._resolve_value(action.data.get("target", ""), payload))
	if target == null or other == null or not (target is Node2D) or not (other is Node2D):
		return
	var d: Vector2 = (other as Node2D).position - (target as Node2D).position
	(target as Node2D).rotation = atan2(d.y, d.x)
