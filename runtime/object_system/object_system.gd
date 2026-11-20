class_name ObjectSystem
extends GyroSystem

var last_object_name: String:
	get: return factory.last_object_name
	set(v): factory.last_object_name = v

var object_counter: int:
	get: return factory.object_counter
	set(v): factory.object_counter = v

var pool: ObjectPool
var aabb: ObjectAABB
var factory: ObjectFactory
var transform: ObjectTransform
var visual: ObjectVisual
var animation: ObjectAnimation

func _init() -> void:
	pass

func setup() -> void:
	pool = ObjectPool.new(runtime)
	aabb = ObjectAABB.new(runtime)
	factory = ObjectFactory.new(runtime, pool, aabb)
	transform = ObjectTransform.new(runtime, aabb)
	visual = ObjectVisual.new(runtime, pool, aabb)
	animation = ObjectAnimation.new(runtime)

func execute(action: GyroAction, payload: Dictionary) -> void:
	pool.ensure_textures()
	match action.type:
		"CreateObject": factory.execute_create(action, payload)
		"CreateSprite": factory.execute_create_typed(action, payload, "sprite", ["name", "x", "y", "w", "h", "texture"])
		"CreateText": factory.execute_create_typed(action, payload, "label", ["name", "x", "y", "w", "h", "text", "size", "font"])
		"CreateGroup": factory.execute_create_group(action, payload)
		"AddToGroup": factory.execute_add_to_group(action, payload)
		"CreateSpriteAnim": factory.execute_create_sprite_anim(action, payload)
		"CreateCircle": factory.execute_create_circle(action, payload)
		"CreateLine": factory.execute_create_line(action, payload)
		"Spawn": factory.execute_spawn(action, payload)
		"DeleteObject": visual.execute_delete_object(action, payload)
		"MoveNode": transform.execute_move_node(action, payload)
		"SetNodeProperty": transform.execute_set_node_property(action, payload)
		"SetSize": transform.execute_set_size(action, payload)
		"SetRotation": transform.execute_set_rotation(action, payload)
		"SetScale": transform.execute_set_scale(action, payload)
		"ChangeLayer": transform.execute_change_layer(action, payload)
		"SetPivot": transform.execute_set_pivot(action, payload)
		"FaceObject": transform.execute_face_object(action, payload)
		"SetVisible": visual.execute_set_visible(action, payload)
		"SetOpacity": visual.execute_set_opacity(action, payload)
		"SetFontSize": visual.execute_set_font_size(action, payload)
		"SetColor": visual.execute_set_color(action, payload)
		"SetText": visual.execute_set_text(action, payload)
		"SetTextAlign": visual.execute_set_text_align(action, payload)
		"SetTexture": visual.execute_set_texture(action, payload)
		"SetCornerRadius": visual.execute_set_corner_radius(action, payload)
		"SetObjectMeta": visual.execute_set_object_meta(action, payload)
		"SetGradient": visual.execute_set_gradient(action, payload)
		"SetBorder": visual.execute_set_border(action, payload)
		"PlayAnimation": animation.execute_play_animation(action, payload)
		"StopAnimation": animation.execute_stop_animation(action, payload)
		"SetFrame": animation.execute_set_frame(action, payload)
		"SetAnchor": pass

func get_aabb(node: Node) -> Rect2:
	return aabb.get_aabb(node)

func update_aabb(node: Node) -> void:
	aabb.update_aabb(node)

func get_visual_bounds(visual_node: Node) -> Dictionary:
	return ObjectUtils.get_visual_bounds(visual_node)

func get_visual(node: Node) -> Node:
	return ObjectUtils.get_visual(node)

func get_label(node: Node) -> Label:
	return ObjectUtils.get_label(node)

func get_sprite(node: Node) -> Sprite2D:
	return ObjectUtils.get_sprite(node)

func get_body(node: Node) -> CollisionObject2D:
	return ObjectUtils.get_body(node)

func get_collision_shape(body: Node) -> CollisionShape2D:
	return ObjectUtils.get_collision_shape(body)

func polygon_rect(poly: PackedVector2Array) -> Rect2:
	return ObjectUtils.polygon_rect(poly)

func on_object_deleted(object_name: String) -> void:
	var node := runtime._get_target_node(object_name)
	if node != null:
		runtime.forget_node(node)
	aabb.erase(object_name)
	var gh := runtime.host as GyroEventHost
	if gh != null:
		gh.unregister_anchor(object_name)
	if runtime.physics_system != null:
		runtime.physics_system.on_object_deleted(object_name)
	if runtime.tag_system != null:
		runtime.tag_system.cleanup_tags(object_name)
	if runtime.tween_system != null:
		runtime.tween_system.on_object_deleted(object_name)

func return_to_pool(node: Node2D) -> void:
	pool.return_to_pool(node)

func clear_pool() -> void:
	pool.clear()

func cleanup() -> void:
	if pool != null:
		pool.clear()
