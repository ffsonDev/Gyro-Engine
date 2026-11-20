class_name ObjectVisual
extends RefCounted

var runtime: GyroEventRuntime
var pool: ObjectPool
var aabb: ObjectAABB

func _init(rt: GyroEventRuntime, p: ObjectPool, a: ObjectAABB) -> void:
	runtime = rt
	pool = p
	aabb = a

func execute_set_visible(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	target.visible = runtime._to_bool(runtime._resolve_value(action.data.get("on", true), payload))

func execute_set_opacity(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var v := clampf(runtime._to_float(runtime._resolve_value(action.data.get("value", 100), payload)), 0.0, 100.0) / 100.0
	var c: Color = target.modulate
	c.a = v
	target.modulate = c

func execute_set_font_size(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var lb := ObjectUtils.get_label(target)
	if lb == null and target is Label:
		lb = target as Label
	if lb != null:
		lb.add_theme_font_size_override("font_size", int(runtime._to_float(runtime._resolve_value(action.data.get("size", 24), payload))))
		aabb.update_aabb(target)

func execute_set_color(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var color := runtime._parse_color(str(runtime._resolve_value(action.data.get("color", "#ffffff"), payload)))
	var visual := ObjectUtils.get_visual(target)
	if visual == null:
		return
	if visual is Sprite2D:
		(visual as Sprite2D).modulate = color
	elif visual is Label:
		(visual as Label).add_theme_color_override("font_color", color)
	elif visual is Polygon2D:
		(visual as Polygon2D).color = color

func execute_set_text(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var lb := ObjectUtils.get_label(target)
	if lb != null:
		lb.text = str(runtime._resolve_value(action.data.get("text", ""), payload))

func execute_set_text_align(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var lb := ObjectUtils.get_label(target)
	if lb != null:
		var align := str(runtime._resolve_value(action.data.get("align", "center"), payload))
		lb.horizontal_alignment = 1 if align == "center" else (2 if align == "right" else 0)

func execute_set_texture(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var sp := ObjectUtils.get_sprite(target)
	if sp != null:
		var ref := str(runtime._resolve_value(action.data.get("texture", ""), payload))
		if ref != "":
			var tex := runtime._load_texture_ref(ref)
			if tex != null:
				sp.texture = tex
	if runtime.physics_system != null:
		runtime.physics_system.update_collision_shape(target)

func execute_set_corner_radius(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var radius := int(runtime._to_float(runtime._resolve_value(action.data.get("radius", 0), payload)))
	var old_visual := ObjectUtils.get_visual(target)
	var w := 100.0
	var h := 100.0
	var color := Color.WHITE
	if old_visual is Sprite2D:
		var sp := old_visual as Sprite2D
		if sp.texture != null:
			w = sp.texture.get_width() * sp.scale.x
			h = sp.texture.get_height() * sp.scale.y
			color = sp.modulate
	elif old_visual is Polygon2D:
		var pg := old_visual as Polygon2D
		var rect: Rect2 = ObjectUtils.polygon_rect(pg.polygon)
		w = rect.size.x
		h = rect.size.y
		color = pg.color
	var was_centered := false
	if old_visual is Sprite2D:
		was_centered = (old_visual as Sprite2D).centered
	if old_visual != null:
		target.remove_child(old_visual)
		old_visual.queue_free()
	if radius > 0:
		var poly := Polygon2D.new()
		poly.polygon = ObjectUtils.make_rounded_rect(w, h, radius)
		poly.color = color
		if was_centered:
			poly.position = Vector2(-w / 2.0, -h / 2.0)
		target.add_child(poly)
	else:
		var sp := Sprite2D.new()
		sp.texture = pool.get_white_tex()
		sp.centered = was_centered
		sp.scale = Vector2(w, h)
		sp.modulate = color
		target.add_child(sp)
	if runtime.physics_system != null:
		runtime.physics_system.update_collision_shape(target)

func execute_set_object_meta(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	target.set_meta(str(action.data.get("key", "")), runtime._resolve_value(action.data.get("value", null), payload))

func execute_set_gradient(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var old_visual := ObjectUtils.get_visual(target)
	var w := 100.0
	var h := 100.0
	var was_centered := false
	if old_visual is Sprite2D:
		var sp := old_visual as Sprite2D
		was_centered = sp.centered
		if sp.texture != null:
			w = sp.texture.get_width() * sp.scale.x
			h = sp.texture.get_height() * sp.scale.y
	elif old_visual is Polygon2D:
		var rect: Rect2 = ObjectUtils.polygon_rect((old_visual as Polygon2D).polygon)
		w = rect.size.x
		h = rect.size.y
	elif old_visual is Label:
		w = (old_visual as Label).size.x
		h = (old_visual as Label).size.y
	var c1 := runtime._parse_color(str(runtime._resolve_value(action.data.get("color1", "#ffffff"), payload)))
	var c2 := runtime._parse_color(str(runtime._resolve_value(action.data.get("color2", "#000000"), payload)))
	var mode := str(action.data.get("mode", "linear"))
	var tex := ObjectUtils.make_gradient_texture(maxi(2, int(w)), maxi(2, int(h)), c1, c2, mode)
	if old_visual != null:
		target.remove_child(old_visual)
		old_visual.queue_free()
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.centered = was_centered
	target.add_child(sp)
	if runtime.physics_system != null:
		runtime.physics_system.update_collision_shape(target)

func execute_set_border(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var old_border: Line2D = null
	for child in target.get_children():
		if child is Line2D and child.has_meta("gyro_border"):
			old_border = child as Line2D
			break
	var visual := ObjectUtils.get_visual(target)
	var w := 100.0
	var h := 100.0
	if visual is Sprite2D:
		var sp := visual as Sprite2D
		if sp.texture != null:
			w = sp.texture.get_width() * sp.scale.x
			h = sp.texture.get_height() * sp.scale.y
	elif visual is Polygon2D:
		var rect: Rect2 = ObjectUtils.polygon_rect((visual as Polygon2D).polygon)
		w = rect.size.x
		h = rect.size.y
	var color := runtime._parse_color(str(runtime._resolve_value(action.data.get("color", "#ffffff"), payload)))
	var width := runtime._to_float(runtime._resolve_value(action.data.get("width", 4), payload))
	if old_border != null:
		target.remove_child(old_border)
		old_border.queue_free()
	if width <= 0:
		return
	var offset := Vector2.ZERO
	if visual is Sprite2D and (visual as Sprite2D).centered:
		offset = Vector2(-w / 2.0, -h / 2.0)
	var line := Line2D.new()
	line.set_meta("gyro_border", true)
	line.width = width
	line.default_color = color
	line.add_point(offset)
	line.add_point(offset + Vector2(w, 0))
	line.add_point(offset + Vector2(w, h))
	line.add_point(offset + Vector2(0, h))
	line.add_point(offset)
	target.add_child(line)

func execute_delete_object(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target != null and target != runtime.host:
		runtime.object_system.on_object_deleted(target.name)
		if target is Node2D:
			var parent := target.get_parent()
			if parent != null:
				parent.remove_child(target)
			pool.return_to_pool(target as Node2D)
		else:
			target.queue_free()
		runtime.invalidate_node_cache()
