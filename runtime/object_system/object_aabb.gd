class_name ObjectAABB
extends RefCounted

var runtime: GyroEventRuntime
var _cache := {}

func _init(rt: GyroEventRuntime) -> void:
	runtime = rt

func get_aabb(node: Node) -> Rect2:
	if node == null:
		return Rect2()
	if _cache.has(node.name):
		return _cache[node.name]
	var rect := _calculate(node)
	_cache[node.name] = rect
	return rect

func update_aabb(node: Node) -> void:
	if node == null:
		return
	_cache[node.name] = _calculate(node)
	var body := node.get_node_or_null(NodePath("PhysicsBody"))
	if body is CollisionObject2D and runtime.physics_system != null:
		runtime.physics_system.update_collision_shape(node)

func erase(object_name: String) -> void:
	_cache.erase(object_name)

func clear() -> void:
	_cache.clear()

func _calculate(node: Node) -> Rect2:
	if node == null:
		return Rect2()
	var visual: Node = null
	for child in node.get_children():
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
		var sz: Vector2 = tex_size * sp.scale * node.scale
		var offset: Vector2 = -sz * 0.5 if sp.centered else Vector2.ZERO
		return Rect2(node.global_position + offset, sz)
	elif visual is AnimatedSprite2D:
		var abounds := ObjectUtils.get_visual_bounds(visual)
		var asz: Vector2 = (abounds["size"] as Vector2) * node.scale
		var aorigin: Vector2 = (abounds["origin"] as Vector2) * node.scale
		return Rect2(node.global_position + aorigin, asz)
	elif visual is Label:
		var lb := visual as Label
		var lsz: Vector2 = lb.size * node.scale
		return Rect2(node.global_position, lsz)
	elif visual is Polygon2D:
		var pg := visual as Polygon2D
		var psz: Vector2 = ObjectUtils.polygon_rect(pg.polygon).size * node.scale
		return Rect2(node.global_position, psz)
	elif visual is Line2D:
		var ln := visual as Line2D
		var rect := ObjectUtils.polygon_rect(ln.points)
		var half_w := ln.width * 0.5
		rect = rect.grow(half_w)
		var lnsz: Vector2 = rect.size * node.scale
		return Rect2(node.global_position, lnsz)
	return Rect2(node.global_position, Vector2.ZERO)
