class_name ObjectUtils
extends RefCounted

static func get_visual(node: Node) -> Node:
	for child in node.get_children():
		if child is CanvasItem:
			return child
	return null

static func get_label(node: Node) -> Label:
	var v := get_visual(node)
	if v is Label:
		return v as Label
	return null

static func get_sprite(node: Node) -> Sprite2D:
	var v := get_visual(node)
	if v is Sprite2D:
		return v as Sprite2D
	return null

static func get_body(node: Node) -> CollisionObject2D:
	for child in node.get_children():
		if child is CollisionObject2D:
			return child as CollisionObject2D
	return null

static func get_collision_shape(body: Node) -> CollisionShape2D:
	for child in body.get_children():
		if child is CollisionShape2D:
			return child as CollisionShape2D
	return null

static func polygon_rect(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var min_v := poly[0]
	var max_v := poly[0]
	for i in range(1, poly.size()):
		var p: Vector2 = poly[i]
		if p.x < min_v.x: min_v.x = p.x
		if p.y < min_v.y: min_v.y = p.y
		if p.x > max_v.x: max_v.x = p.x
		if p.y > max_v.y: max_v.y = p.y
	return Rect2(min_v, max_v - min_v)

static func get_visual_bounds(visual: Node) -> Dictionary:
	if visual is Sprite2D:
		var sp := visual as Sprite2D
		var size := Vector2.ZERO
		if sp.texture != null:
			size = sp.texture.get_size() * Vector2(absf(sp.scale.x), absf(sp.scale.y))
		var origin := Vector2.ZERO if not sp.centered else -size * 0.5
		return {"size": size, "origin": origin}
	elif visual is AnimatedSprite2D:
		var asp := visual as AnimatedSprite2D
		var size := Vector2.ZERO
		if asp.sprite_frames != null and asp.animation != "" and asp.sprite_frames.has_animation(asp.animation):
			var tex := asp.sprite_frames.get_frame_texture(asp.animation, 0)
			if tex != null:
				size = tex.get_size() * Vector2(absf(asp.scale.x), absf(asp.scale.y))
		var origin := Vector2.ZERO if not asp.centered else -size * 0.5
		return {"size": size, "origin": origin}
	elif visual is Label:
		var lb := visual as Label
		return {"size": lb.size, "origin": Vector2.ZERO}
	elif visual is Polygon2D:
		var pg := visual as Polygon2D
		var rect := polygon_rect(pg.polygon)
		return {"size": rect.size, "origin": rect.position}
	elif visual is Line2D:
		var ln := visual as Line2D
		var rect := polygon_rect(ln.points)
		return {"size": rect.size, "origin": rect.position}
	return {"size": Vector2.ZERO, "origin": Vector2.ZERO}

static func make_rounded_rect(w: float, h: float, r: int) -> PackedVector2Array:
	r = mini(r, int(minf(w, h) / 2.0))
	if r <= 0:
		return PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
	var points: PackedVector2Array = PackedVector2Array()
	const CORNER_STEPS := 6
	var steps := CORNER_STEPS
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

static func make_circle_border(r: float, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	const BORDER_STEPS := 48
	var steps := BORDER_STEPS
	for i in steps + 1:
		var a := TAU * float(i) / float(steps)
		line.add_point(Vector2(cos(a) * r, sin(a) * r))
	return line

static func make_gradient_texture(w: int, h: int, c1: Color, c2: Color, mode: String) -> ImageTexture:
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
	else:
		for x in w:
			var t := float(x) / maxf(1.0, float(w - 1))
			img.fill_rect(Rect2(x, 0, 1, h), c1.lerp(c2, t))
	return ImageTexture.create_from_image(img)

static func get_pivot(node: Node) -> Vector2:
	if node == null:
		return Vector2.ZERO
	if node is Control:
		return (node as Control).pivot_offset
	var fraction: Vector2 = Vector2(0.5, 0.5)
	if node.has_meta("gyro_pivot"):
		fraction = node.get_meta("gyro_pivot")
	var visual := get_visual(node)
	if visual == null:
		return Vector2.ZERO
	var bounds: Dictionary = get_visual_bounds(visual)
	var size: Vector2 = bounds.get("size", Vector2.ZERO)
	var origin: Vector2 = bounds.get("origin", Vector2.ZERO)
	return origin + Vector2(size.x * fraction.x, size.y * fraction.y)

static func set_pivot(node: Node, value: Vector2) -> void:
	if node == null:
		return
	if node is Control:
		(node as Control).pivot_offset = value
		return
	var visual := get_visual(node)
	if visual == null:
		return
	var bounds: Dictionary = get_visual_bounds(visual)
	var size: Vector2 = bounds.get("size", Vector2.ZERO)
	var origin: Vector2 = bounds.get("origin", Vector2.ZERO)
	var f := Vector2.ZERO
	if size.x > 0.0:
		f.x = (value.x - origin.x) / size.x
	if size.y > 0.0:
		f.y = (value.y - origin.y) / size.y
	node.set_meta("gyro_pivot", f)
