class_name ObjectPool
extends RefCounted

var runtime: GyroEventRuntime
var host: GyroEventHost

var _white_tex: ImageTexture
var _circle_tex: ImageTexture
var _pool: Array[Node2D] = []
const MAX_POOL_SIZE := 50

func _init(rt: GyroEventRuntime) -> void:
	runtime = rt
	host = rt.host

func ensure_textures() -> void:
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

func get_white_tex() -> ImageTexture:
	ensure_textures()
	return _white_tex

func get_circle_tex() -> ImageTexture:
	ensure_textures()
	return _circle_tex

func get_from_pool() -> Node2D:
	if _pool.size() > 0:
		return _pool.pop_back()
	return Node2D.new()

func return_to_pool(node: Node2D) -> void:
	if _pool.size() >= MAX_POOL_SIZE:
		node.queue_free()
		return
	if host != null:
		host.unregister_anchor(node.name)
	var body := node.get_node_or_null(NodePath("PhysicsBody"))
	if body != null:
		node.remove_child(body)
		body.queue_free()
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
	node.name = ""
	node.position = Vector2.ZERO
	node.rotation = 0.0
	node.scale = Vector2.ONE
	node.z_index = 0
	node.modulate = Color.WHITE
	node.self_modulate = Color.WHITE
	node.visible = true
	node.set_script(null)
	for meta in node.get_meta_list():
		node.remove_meta(meta)
	_pool.append(node)

func clear() -> void:
	for node in _pool:
		if is_instance_valid(node):
			node.free()
	_pool.clear()
