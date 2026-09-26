class_name ObjectSystem
extends GyroSystem

var last_object_name := ""
var object_counter := 0


var _white_tex: ImageTexture
var _circle_tex: ImageTexture

func _ensure_textures() -> void:
	if _white_tex != null:
		return
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_white_tex = ImageTexture.create_from_image(img)
	var size := 64
	var cimg := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var r := size / 2.0
	for x in size:
		for y in size:
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= r:
				cimg.set_pixel(x, y, Color.WHITE)
	_circle_tex = ImageTexture.create_from_image(cimg)

func execute(action: GyroAction, payload: Dictionary) -> void:
	_ensure_textures()
	match action.type:
		"MoveNode": _action_move_node(action, payload)
		"SetNodeProperty": _action_set_node_property(action, payload)
		"SetSize": _action_set_size(action, payload)
		"SetText": _action_set_text(action, payload)
		"CreateObject": _action_create_object(action, payload)
		"DeleteObject": _action_delete_object(action, payload)
		"SetVisible": _action_set_visible(action, payload)
		"SetOpacity": _action_set_opacity(action, payload)
		"SetRotation": _action_set_rotation(action, payload)
		"SetScale": _action_set_scale(action, payload)
		"ChangeLayer": _action_change_layer(action, payload)
		"SetFontSize": _action_set_font_size(action, payload)
		"SetColor": _action_set_color(action, payload)
		"SetTextAlign": _action_set_text_align(action, payload)
		"SetTexture": _action_set_texture(action, payload)
		"SetCornerRadius": _action_set_corner_radius(action, payload)
		"SetPivot": _action_set_pivot(action, payload)
		"SetObjectMeta": _action_set_object_meta(action, payload)
		"FaceObject": _action_face_object(action, payload)
		"PlayAnimation": _action_play_animation(action, payload)
		"StopAnimation": _action_stop_animation(action, payload)
		"CreateGroup": _action_create_group(action, payload)
		"AddToGroup": _action_add_to_group(action, payload)
		"CreateSpriteAnim": _action_create_sprite_anim(action, payload)
		"SetFrame": _action_set_frame(action, payload)
		"CreateCircle": _action_create_circle(action, payload)
		"CreateLine": _action_create_line(action, payload)
		"SetGradient": _action_set_gradient(action, payload)
		"SetBorder": _action_set_border(action, payload)
		"Spawn": _action_spawn(action, payload)
		"SetAnchor": _action_set_anchor(action, payload)

func _get_visual(node: Node) -> Node:
	var pivot := node.get_node_or_null(NodePath("Pivot"))
	if pivot == null:
		return null
	for child in pivot.get_children():
		if child is CanvasItem:
			return child
	return null

func _get_pivot(node: Node) -> Node2D:
	return node.get_node_or_null(NodePath("Pivot")) as Node2D

func _get_label(node: Node) -> Label:
	var v := _get_visual(node)
	if v is Label:
		return v as Label
	return null

func _get_sprite(node: Node) -> Sprite2D:
	var v := _get_visual(node)
	if v is Sprite2D:
		return v as Sprite2D
	return null

func _get_body(node: Node) -> CollisionObject2D:
	for child in node.get_children():
		if child is CollisionObject2D:
			return child as CollisionObject2D
	return null

func _get_aabb(node: Node) -> Rect2:
	if node == null:
		return Rect2()

	var pivot := node.get_node_or_null(NodePath("Pivot"))
	if pivot == null:
		var body := node.get_node_or_null(NodePath("PhysicsBody"))
		if body != null:
			pivot = body.get_node_or_null(NodePath("Pivot"))
		if pivot == null:
			return Rect2(node.global_position, Vector2.ZERO)

	var visual: Node = null
	for child in pivot.get_children():
		if child is CanvasItem:
			visual = child
			break

	if visual == null:
		return Rect2(node.global_position, Vector2.ZERO)

	if visual is Sprite2D:
		var sp := visual as Sprite2D
		var tex_size := Vector2.ZERO
		if sp.texture != null:
			tex_size = sp.texture.get_size()
		var size: Variant = tex_size * sp.scale * node.scale
		var offset: Variant = -size * 0.5 if sp.centered else Vector2.ZERO
		return Rect2(node.global_position + offset, size)
	elif visual is Label:
		var lb := visual as Label
		var size: Variant = lb.size * node.scale
		return Rect2(node.global_position, size)
	elif visual is Polygon2D:
		var pg := visual as Polygon2D
		var size: Variant = _polygon_rect(pg.polygon).size * node.scale
		return Rect2(node.global_position, size)
	elif visual is Line2D:
		var ln := visual as Line2D
		var rect := _polygon_rect(ln.points)
		var half_w := ln.width * 0.5
		rect = rect.grow(half_w)
		return Rect2(node.global_position, rect.size * node.scale)
	else:
		return Rect2(node.global_position, Vector2.ZERO)

# CreateObject

func _action_create_object(action: GyroAction, payload: Dictionary) -> void:
	var stage := runtime._get_stage()
	if stage == null:
		return
	var obj_name := str(runtime._resolve_value(action.data.get("name", ""), payload))
	obj_name = GyroEventRuntime.sanitize_node_name(obj_name)
	if obj_name == "":
		return
	var old := runtime._get_target_node(obj_name)
	if old != null:
		old.get_parent().remove_child(old)
		old.queue_free()
	runtime.physics_system.on_object_deleted(obj_name)

	var obj_type := str(action.data.get("type", "rect"))
	var root := Node2D.new()
	root.name = obj_name
	var pivot := Node2D.new()
	pivot.name = "Pivot"
	root.add_child(pivot)

	var visual: Node = null
	var w := runtime._to_float(runtime._resolve_value(action.data.get("w", 100), payload))
	var h := runtime._to_float(runtime._resolve_value(action.data.get("h", 100), payload))
	var color := runtime._parse_color(str(runtime._resolve_value(action.data.get("color", "#ffffff"), payload)))
	var radius := int(runtime._to_float(runtime._resolve_value(action.data.get("radius", 0), payload)))

	match obj_type:
		"rect":
			if radius > 0:
				var poly := Polygon2D.new()
				poly.polygon = _make_rounded_rect(w, h, radius)
				poly.color = color
				visual = poly
			else:
				var sp := Sprite2D.new()
				sp.texture = _white_tex
				sp.centered = false
				sp.scale = Vector2(w, h)
				sp.modulate = color
				visual = sp
		"label":
			var lb := Label.new()
			lb.text = str(runtime._resolve_value(action.data.get("text", ""), payload))
			lb.add_theme_color_override("font_color", color)
			var fs := int(runtime._to_float(runtime._resolve_value(action.data.get("font", 24), payload)))
			lb.add_theme_font_size_override("font_size", fs)
			lb.custom_minimum_size = Vector2(w, h)
			lb.size = Vector2(w, h)
			lb.clip_contents = true
			visual = lb
		"sprite":
			var sp := Sprite2D.new()
			sp.centered = false
			var texture_ref := str(runtime._resolve_value(action.data.get("texture", ""), payload))
			if texture_ref != "":
				var tex := runtime._load_texture_ref(texture_ref)
				if tex != null:
					sp.texture = tex
					if w > 0 and h > 0:
						sp.scale = Vector2(w / maxf(1.0, tex.get_width()), h / maxf(1.0, tex.get_height()))
			sp.modulate = color
			visual = sp
		"circle":
			var sp := Sprite2D.new()
			sp.texture = _circle_tex
			sp.centered = true
			var r := maxf(1.0, runtime._to_float(runtime._resolve_value(action.data.get("radius", 50), payload)))
			sp.scale = Vector2(r * 2.0 / 64.0, r * 2.0 / 64.0)
			sp.modulate = color
			root.set_meta("gyro_shape", "circle")
			visual = sp

	if visual == null:
		root.queue_free()
		return

	pivot.add_child(visual)

	var base_pos := Vector2(
		runtime._to_float(runtime._resolve_value(action.data.get("x", 0), payload)),
		runtime._to_float(runtime._resolve_value(action.data.get("y", 0), payload))
	)
	root.position = runtime.apply_anchor(root, obj_name, str(action.data.get("anchor", "free")), base_pos)
	var anchor_str := str(action.data.get("anchor", "free"))
	if anchor_str != "" and anchor_str != "free":
		root.set_meta("gyro_anchor", anchor_str)
		var vp: Variant = runtime.host.get_viewport_rect().size
		var anchor_pt: Variant = runtime.host.anchor_point(vp, anchor_str)
		root.set_meta("gyro_anchor_offset", base_pos)
	stage.add_child(root)

	last_object_name = obj_name
	var variable_name := str(action.data.get("variable", ""))
	if variable_name != "":
		runtime.variables[variable_name] = root

func _make_rounded_rect(w: float, h: float, r: int) -> PackedVector2Array:
	r = mini(r, int(minf(w, h) / 2.0))
	if r <= 0:
		return PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
	var points: PackedVector2Array = PackedVector2Array()
	var steps := 6
	var corners := [
		Vector2(r, r), Vector2(w - r, r),
		Vector2(w - r, h - r), Vector2(r, h - r)
	]
	var start_angles := [PI, 1.5 * PI, 0.0, PI * 0.5]
	for ci in 4:
		var center: Vector2 = corners[ci]
		var sa: float = start_angles[ci]
		for i in steps + 1:
			var a: float = sa + PI * 0.5 * float(i) / float(steps)
			points.append(center + Vector2(cos(a), sin(a)) * r)
	return points

# Delete

func _action_delete_object(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target != null and target != runtime.host:
		runtime.physics_system.on_object_deleted(target.name)
		runtime.tag_system.cleanup_tags(target.name)
		target.queue_free()

func on_object_deleted(object_name: String) -> void:
	runtime.physics_system.on_object_deleted(object_name)
	runtime.tag_system.cleanup_tags(object_name)

# Move / Property

func _action_move_node(action: GyroAction, payload: Dictionary) -> void:
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
		if target.has_meta("gyro_anchor") and str(target.get_meta("gyro_anchor")) != "":
			var anchor := str(target.get_meta("gyro_anchor"))
			var vp: Variant = runtime.host.get_viewport_rect().size
			var anchor_pt: Variant = runtime.host.anchor_point(vp, anchor)
			target.set_meta("gyro_anchor_offset", target.position - anchor_pt)

func _action_set_node_property(action: GyroAction, payload: Dictionary) -> void:
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
		"size":
			_action_set_size(action, payload)
		"visible":
			target.visible = runtime._to_bool(value)
		"z_index":
			target.z_index = int(runtime._to_float(value))
		"rotation":
			target.rotation = float(runtime._to_float(value))
		"scale":
			if value is Vector2:
				target.scale = value
		"modulate":
			if value is Color:
				target.modulate = value
		"text":
			var lb := _get_label(target)
			if lb != null:
				lb.text = str(value)
		"color":
			_action_set_color(action, payload)

func _action_set_size(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var visual := _get_visual(target)
	if visual == null:
		return
	var w_value: Variant = action.data.get("w", null)
	var h_value: Variant = action.data.get("h", null)
	if visual is Sprite2D:
		var sp := visual as Sprite2D
		var current_size := Vector2.ZERO
		if sp.texture != null:
			current_size = sp.texture.get_size() * sp.scale
		var new_w := current_size.x
		var new_h := current_size.y
		if w_value != null:
			new_w = runtime._to_float(runtime._resolve_value(w_value, payload))
		if h_value != null:
			new_h = runtime._to_float(runtime._resolve_value(h_value, payload))
		var tex_size := sp.texture.get_size() if sp.texture != null else Vector2(1, 1)
		sp.scale = Vector2(new_w / maxf(1.0, tex_size.x), new_h / maxf(1.0, tex_size.y))
	elif visual is Label:
		var lb := visual as Label
		var current := lb.size
		if w_value != null:
			current.x = runtime._to_float(runtime._resolve_value(w_value, payload))
		if h_value != null:
			current.y = runtime._to_float(runtime._resolve_value(h_value, payload))
		lb.custom_minimum_size = current
		lb.size = current
	elif visual is Polygon2D:
		var pg := visual as Polygon2D
		var old_rect: Rect2 = _polygon_rect(pg.polygon)
		var current_w: float = old_rect.size.x
		var current_h: float = old_rect.size.y
		var new_w: float = current_w
		var new_h: float = current_h
		if w_value != null:
			new_w = runtime._to_float(runtime._resolve_value(w_value, payload))
		if h_value != null:
			new_h = runtime._to_float(runtime._resolve_value(h_value, payload))
		var sx: float = new_w / maxf(1.0, current_w)
		var sy: float = new_h / maxf(1.0, current_h)
		var new_poly := PackedVector2Array()
		for p in pg.polygon:
			new_poly.append(p * Vector2(sx, sy))
		pg.polygon = new_poly
	runtime.physics_system.update_collision_shape(target)

func _action_set_text(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var lb := _get_label(target)
	if lb != null:
		lb.text = str(runtime._resolve_value(action.data.get("text", ""), payload))

# Visual

func _action_set_visible(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	target.visible = runtime._to_bool(runtime._resolve_value(action.data.get("on", true), payload))

func _action_set_opacity(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var v := clampf(runtime._to_float(runtime._resolve_value(action.data.get("value", 100), payload)), 0.0, 100.0) / 100.0
	var c: Color = target.modulate
	c.a = v
	target.modulate = c

func _action_set_rotation(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null or not (target is Node2D):
		return
	var angle := runtime._to_float(runtime._resolve_value(action.data.get("angle", 0), payload))
	if str(action.data.get("mode", "set")) == "add":
		angle += rad_to_deg(target.rotation)
	target.rotation = deg_to_rad(angle)

func _action_set_scale(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null or not (target is Node2D):
		return
	var s: Vector2 = target.scale
	var percent = action.data.get("percent", null)
	if percent != null and str(percent) != "":
		var p := runtime._to_float(runtime._resolve_value(percent, payload)) / 100.0
		s = Vector2(p, p)
	else:
		var xv = action.data.get("x", null)
		if xv != null and str(xv) != "":
			s.x = runtime._to_float(runtime._resolve_value(xv, payload)) / 100.0
		var yv = action.data.get("y", null)
		if yv != null and str(yv) != "":
			s.y = runtime._to_float(runtime._resolve_value(yv, payload)) / 100.0
	target.scale = s

func _action_change_layer(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null or not (target is Node2D):
		return
	var dir := int(runtime._to_float(runtime._resolve_value(action.data.get("dir", 1), payload)))
	target.z_index = int(target.z_index) + dir

func _action_set_font_size(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var lb := _get_label(target)
	if lb != null:
		lb.add_theme_font_size_override("font_size", int(runtime._to_float(runtime._resolve_value(action.data.get("size", 24), payload))))

func _action_set_color(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var color := runtime._parse_color(str(runtime._resolve_value(action.data.get("color", "#ffffff"), payload)))
	var visual := _get_visual(target)
	if visual == null:
		return
	if visual is Sprite2D:
		(visual as Sprite2D).modulate = color
	elif visual is Label:
		(visual as Label).add_theme_color_override("font_color", color)
	elif visual is Polygon2D:
		(visual as Polygon2D).color = color

func _action_set_text_align(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var lb := _get_label(target)
	if lb != null:
		var align := str(runtime._resolve_value(action.data.get("align", "center"), payload))
		lb.horizontal_alignment = 1 if align == "center" else (2 if align == "right" else 0)

func _action_set_texture(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var sp := _get_sprite(target)
	if sp != null:
		var ref := str(runtime._resolve_value(action.data.get("texture", ""), payload))
		if ref != "":
			var tex := runtime._load_texture_ref(ref)
			if tex != null:
				sp.texture = tex
	runtime.physics_system.update_collision_shape(target)

func _action_set_corner_radius(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var radius := int(runtime._to_float(runtime._resolve_value(action.data.get("radius", 0), payload)))
	var pivot := _get_pivot(target)
	if pivot == null:
		return
	var old_visual := _get_visual(target)
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
		var rect: Rect2 = _polygon_rect(pg.polygon)
		w = rect.size.x
		h = rect.size.y
		color = pg.color
	if old_visual != null:
		pivot.remove_child(old_visual)
		old_visual.queue_free()
	if radius > 0:
		var poly := Polygon2D.new()
		poly.polygon = _make_rounded_rect(w, h, radius)
		poly.color = color
		pivot.add_child(poly)
	else:
		var sp := Sprite2D.new()
		sp.texture = _white_tex
		sp.centered = false
		sp.scale = Vector2(w, h)
		sp.modulate = color
		pivot.add_child(sp)
	runtime.physics_system.update_collision_shape(target)

func _action_set_pivot(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var pivot := _get_pivot(target)
	if pivot == null:
		return
	var visual := _get_visual(target)
	var w := 0.0
	var h := 0.0
	if visual is Sprite2D:
		var sp := visual as Sprite2D
		if sp.texture != null:
			w = sp.texture.get_width() * sp.scale.x
			h = sp.texture.get_height() * sp.scale.y
	elif visual is Label:
		w = (visual as Label).size.x
		h = (visual as Label).size.y
	elif visual is Polygon2D:
		var rect: Rect2 = _polygon_rect((visual as Polygon2D).polygon)
		w = rect.size.x
		h = rect.size.y
	var px := runtime._to_float(runtime._resolve_value(action.data.get("x", 50), payload)) / 100.0
	var py := runtime._to_float(runtime._resolve_value(action.data.get("y", 50), payload)) / 100.0
	pivot.position = Vector2(-w * px, -h * py)

func _action_set_object_meta(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	target.set_meta(str(action.data.get("key", "")), runtime._resolve_value(action.data.get("value", null), payload))

func _action_face_object(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	var other := runtime._node_from_value(runtime._resolve_value(action.data.get("target", ""), payload))
	if target == null or other == null or not (target is Node2D) or not (other is Node2D):
		return
	var d: Vector2 = (other as Node2D).position - (target as Node2D).position
	(target as Node2D).rotation = atan2(d.y, d.x)

# Animation

func _action_play_animation(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var animation := str(runtime._resolve_value(action.data.get("animation", ""), payload))
	if animation == "":
		return
	if target is AnimationPlayer:
		var player := target as AnimationPlayer
		if player.has_animation(animation):
			player.play(animation)
	elif target is AnimatedSprite2D:
		var sprite := target as AnimatedSprite2D
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(animation):
			sprite.play(animation)
	elif target.has_method("play"):
		target.call("play", animation)

func _action_stop_animation(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target is AnimatedSprite2D:
		(target as AnimatedSprite2D).stop()
	elif target is AnimationPlayer:
		(target as AnimationPlayer).stop()

# Group

func _action_create_group(action: GyroAction, payload: Dictionary) -> void:
	var stage := runtime._get_stage()
	if stage == null:
		return
	var group_name := GyroEventRuntime.sanitize_node_name(str(runtime._resolve_value(action.data.get("name", ""), payload)))
	if group_name == "":
		return
	var old := runtime._get_target_node(group_name)
	if old != null:
		old.get_parent().remove_child(old)
		old.free()
		runtime.physics_system.on_object_deleted(group_name)
	var group := Node2D.new()
	group.name = group_name
	var base_pos := Vector2(
		runtime._to_float(runtime._resolve_value(action.data.get("x", 0), payload)),
		runtime._to_float(runtime._resolve_value(action.data.get("y", 0), payload))
	)
	group.position = runtime.apply_anchor(group, group_name, str(action.data.get("anchor", "free")), base_pos)
	stage.add_child(group)
	last_object_name = group_name

func _action_add_to_group(action: GyroAction, payload: Dictionary) -> void:
	var node := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	var group := runtime._node_from_value(runtime._resolve_value(action.data.get("group", ""), payload))
	if node == null or group == null or node == group:
		return
	if not (node is Node2D) or not (group is Node2D):
		return
	var gp := (node as Node2D).global_position
	var parent := node.get_parent()
	if parent == null:
		return
	parent.remove_child(node)
	group.add_child(node)
	(node as Node2D).global_position = gp

# SpriteAnim

func _action_create_sprite_anim(action: GyroAction, payload: Dictionary) -> void:
	var stage := runtime._get_stage()
	if stage == null:
		return
	var obj_name := GyroEventRuntime.sanitize_node_name(str(runtime._resolve_value(action.data.get("name", ""), payload)))
	if obj_name == "":
		return
	var tex := runtime._load_texture_ref(str(runtime._resolve_value(action.data.get("sprite", ""), payload)))
	if tex == null:
		return
	var frame_w := maxf(1.0, runtime._to_float(runtime._resolve_value(action.data.get("frame_w", 32), payload)))
	var frame_h := maxf(1.0, runtime._to_float(runtime._resolve_value(action.data.get("frame_h", 32), payload)))
	var count := maxi(1, int(runtime._to_float(runtime._resolve_value(action.data.get("count", 1), payload))))
	var fps := maxf(1.0, runtime._to_float(runtime._resolve_value(action.data.get("fps", 8), payload)))
	var anim := str(action.data.get("anim", "default"))
	var frames := SpriteFrames.new()
	if not frames.has_animation(anim):
		frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, true)
	var cols := maxi(1, int(tex.get_width() / frame_w))
	for i in range(count):
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(float(i % cols) * frame_w, float(i / cols) * frame_h, frame_w, frame_h)
		frames.add_frame(anim, atlas)
	var old := runtime._get_target_node(obj_name)
	if old != null:
		old.get_parent().remove_child(old)
		old.free()
		runtime.physics_system.on_object_deleted(obj_name)
	var sprite := AnimatedSprite2D.new()
	sprite.name = obj_name
	sprite.sprite_frames = frames
	var base_pos := Vector2(
		runtime._to_float(runtime._resolve_value(action.data.get("x", 0), payload)),
		runtime._to_float(runtime._resolve_value(action.data.get("y", 0), payload))
	)
	sprite.position = runtime.apply_anchor(sprite, obj_name, str(action.data.get("anchor", "free")), base_pos)
	stage.add_child(sprite)
	sprite.play(anim)
	last_object_name = obj_name

func _action_set_frame(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target is AnimatedSprite2D:
		(target as AnimatedSprite2D).frame = int(runtime._to_float(runtime._resolve_value(action.data.get("frame", 0), payload)))

# Circle / Line

func _action_create_circle(action: GyroAction, payload: Dictionary) -> void:
	var stage := runtime._get_stage()
	if stage == null:
		return
	var obj_name := GyroEventRuntime.sanitize_node_name(str(runtime._resolve_value(action.data.get("name", ""), payload)))
	if obj_name == "":
		return
	var old := runtime._get_target_node(obj_name)
	if old != null:
		old.get_parent().remove_child(old)
		old.free()
	runtime.physics_system.on_object_deleted(obj_name)
	var root := Node2D.new()
	root.name = obj_name
	var pivot := Node2D.new()
	pivot.name = "Pivot"
	root.add_child(pivot)
	root.set_meta("gyro_shape", "circle")
	var sp := Sprite2D.new()
	sp.texture = _circle_tex
	sp.centered = true
	var r := maxf(1.0, runtime._to_float(runtime._resolve_value(action.data.get("radius", 50), payload)))
	sp.scale = Vector2(r * 2.0 / 64.0, r * 2.0 / 64.0)
	sp.modulate = runtime._parse_color(str(runtime._resolve_value(action.data.get("color", "#ffffff"), payload)))
	pivot.add_child(sp)
	var border_w := runtime._to_float(runtime._resolve_value(action.data.get("border_w", 0), payload))
	if border_w > 0:
		var border := _make_circle_border(r, runtime._parse_color(str(runtime._resolve_value(action.data.get("border_color", "#ffffff"), payload))), border_w)
		pivot.add_child(border)
	var base_pos := Vector2(
		runtime._to_float(runtime._resolve_value(action.data.get("x", 0), payload)),
		runtime._to_float(runtime._resolve_value(action.data.get("y", 0), payload))
	)
	root.position = runtime.apply_anchor(root, obj_name, str(action.data.get("anchor", "free")), base_pos)
	stage.add_child(root)
	last_object_name = obj_name

func _make_circle_border(r: float, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	var steps := 48
	for i in steps + 1:
		var a := TAU * float(i) / float(steps)
		line.add_point(Vector2(cos(a) * r, sin(a) * r))
	return line

# CreateLine
func _action_create_line(action: GyroAction, payload: Dictionary) -> void:
	var stage := runtime._get_stage()
	if stage == null:
		return
	var obj_name := GyroEventRuntime.sanitize_node_name(str(runtime._resolve_value(action.data.get("name", ""), payload)))
	if obj_name == "":
		return
	var old := runtime._get_target_node(obj_name)
	if old != null:
		old.get_parent().remove_child(old)
		old.free()
		runtime.physics_system.on_object_deleted(obj_name)
	var root := Node2D.new()
	root.name = obj_name
	var pivot := Node2D.new()
	pivot.name = "Pivot"
	root.add_child(pivot)

	var line := Line2D.new()
	var p1 := Vector2(
		runtime._to_float(runtime._resolve_value(action.data.get("x", 0), payload)),
		runtime._to_float(runtime._resolve_value(action.data.get("y", 0), payload))
	)
	var p2 := Vector2(
		runtime._to_float(runtime._resolve_value(action.data.get("x2", 100), payload)),
		runtime._to_float(runtime._resolve_value(action.data.get("y2", 100), payload))
	)
	line.add_point(Vector2.ZERO)
	line.add_point(p2 - p1)
	line.default_color = runtime._parse_color(str(runtime._resolve_value(action.data.get("color", "#ffffff"), payload)))
	line.width = maxf(1.0, runtime._to_float(runtime._resolve_value(action.data.get("width", 4), payload)))
	pivot.add_child(line)

	root.position = runtime.apply_anchor(root, obj_name, str(action.data.get("anchor", "free")), p1)
	stage.add_child(root)
	last_object_name = obj_name

# Gradient / Border
func _action_set_gradient(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var pivot := _get_pivot(target)
	if pivot == null:
		return
	var old_visual := _get_visual(target)
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
		var rect: Rect2 = _polygon_rect((old_visual as Polygon2D).polygon)
		w = rect.size.x
		h = rect.size.y
	elif old_visual is Label:
		w = (old_visual as Label).size.x
		h = (old_visual as Label).size.y
	var c1 := runtime._parse_color(str(runtime._resolve_value(action.data.get("color1", "#ffffff"), payload)))
	var c2 := runtime._parse_color(str(runtime._resolve_value(action.data.get("color2", "#000000"), payload)))
	var mode := str(action.data.get("mode", "linear"))
	var tex := _make_gradient_texture(maxi(2, int(w)), maxi(2, int(h)), c1, c2, mode)
	if old_visual != null:
		pivot.remove_child(old_visual)
		old_visual.queue_free()
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.centered = was_centered
	pivot.add_child(sp)
	runtime.physics_system.update_collision_shape(target)

func _make_gradient_texture(w: int, h: int, c1: Color, c2: Color, mode: String) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	if mode == "radial":
		var center := Vector2(w * 0.5, h * 0.5)
		var max_r := maxf(1.0, minf(w, h) * 0.5)
		for y in h:
			for x in w:
				var t := clampf(Vector2(x + 0.5, y + 0.5).distance_to(center) / max_r, 0.0, 1.0)
				img.set_pixel(x, y, c1.lerp(c2, t))
	elif mode == "vertical":
		for y in h:
			var t := float(y) / maxf(1.0, float(h - 1))
			img.fill_rect(Rect2(0, y, w, 1), c1.lerp(c2, t))
	else: # linear (горизонтальный)
		for x in w:
			var t := float(x) / maxf(1.0, float(w - 1))
			img.fill_rect(Rect2(x, 0, 1, h), c1.lerp(c2, t))
	return ImageTexture.create_from_image(img)

func _action_set_border(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	var pivot := _get_pivot(target)
	if pivot == null:
		return
	var old_border: Line2D = null
	for child in pivot.get_children():
		if child is Line2D and child.has_meta("gyro_border"):
			old_border = child as Line2D
			break
	var visual := _get_visual(target)
	var w := 100.0
	var h := 100.0
	if visual is Sprite2D:
		var sp := visual as Sprite2D
		if sp.texture != null:
			w = sp.texture.get_width() * sp.scale.x
			h = sp.texture.get_height() * sp.scale.y
	elif visual is Polygon2D:
		var rect: Rect2 = _polygon_rect((visual as Polygon2D).polygon)
		w = rect.size.x
		h = rect.size.y
	var color := runtime._parse_color(str(runtime._resolve_value(action.data.get("color", "#ffffff"), payload)))
	var width := runtime._to_float(runtime._resolve_value(action.data.get("width", 4), payload))
	if old_border != null:
		pivot.remove_child(old_border)
		old_border.queue_free()
	if width <= 0:
		return
	var line := Line2D.new()
	line.set_meta("gyro_border", true)
	line.width = width
	line.default_color = color
	line.add_point(Vector2(0, 0))
	line.add_point(Vector2(w, 0))
	line.add_point(Vector2(w, h))
	line.add_point(Vector2(0, h))
	line.add_point(Vector2(0, 0))
	pivot.add_child(line)

# === Spawn ===

func _action_spawn(action: GyroAction, payload: Dictionary) -> void:
	if runtime.host == null:
		return
	var scene_path := str(runtime._resolve_value(action.data.get("scene", ""), payload))
	if scene_path == "":
		return
	scene_path = GyroAssetPaths.resolve_asset_path(scene_path, runtime._project_path())
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var instance := packed.instantiate()
	var parent_path := str(action.data.get("parent", ""))
	var parent: Node = null
	if parent_path == "":
		if runtime.host.is_inside_tree() and runtime.host.get_tree().current_scene != null:
			parent = runtime.host.get_tree().current_scene
		else:
			parent = runtime.host
	else:
		parent = runtime.host.get_node_or_null(NodePath(parent_path))
	if parent == null:
		parent = runtime.host
	parent.add_child(instance)
	var x_value = action.data.get("x", null)
	var y_value = action.data.get("y", null)
	if instance is Node2D:
		var node_2d := instance as Node2D
		if x_value != null or y_value != null:
			var pv := node_2d.position
			if x_value != null:
				pv.x = runtime._to_float(runtime._resolve_value(x_value, payload))
			if y_value != null:
				pv.y = runtime._to_float(runtime._resolve_value(y_value, payload))
			node_2d.position = pv
	var variable_name := str(action.data.get("variable", ""))
	if variable_name != "":
		runtime.variables[variable_name] = instance

static func _polygon_rect(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var min_v := poly[0]
	var max_v := poly[0]
	for i in range(1, poly.size()):
		var p: Vector2 = poly[i]
		if p.x < min_v.x:
			min_v.x = p.x
		if p.y < min_v.y:
			min_v.y = p.y
		if p.x > max_v.x:
			max_v.x = p.x
		if p.y > max_v.y:
			max_v.y = p.y
	return Rect2(min_v, max_v - min_v)

func _action_set_anchor(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null or not (target is Node2D):
		return
	if host == null:
		return
	var node_2d := target as Node2D
	var anchor := str(runtime._resolve_value(action.data.get("anchor", "free"), payload))

	if anchor == "" or anchor == "free":
		node_2d.set_meta("gyro_anchor", "")
		node_2d.set_meta("gyro_anchor_offset", Vector2.ZERO)
		host.unregister_anchor(node_2d.name)
		return

	var vp_size: Vector2 = host.get_viewport_rect().size
	var anchor_pt: Vector2 = host.anchor_point(vp_size, anchor) - host.world_offset

	var offset: Vector2 = node_2d.position - anchor_pt
	node_2d.set_meta("gyro_anchor", anchor)
	node_2d.set_meta("gyro_anchor_offset", offset)
	host.register_anchor(node_2d.name, anchor)
