class_name PhysicsSystem
extends GyroSystem

const META_OBJECT_NAME := "gyro_object_name"
const META_SHAPE := "gyro_shape"
const DEFAULT_GRAVITY := 980.0

var physics_states := {}
var physics_paused := false
var global_gravity := 0.0
var draggable := {}
var _grab_node: Node = null
var _grab_offset := Vector2.ZERO
var _contacts := {}
var _contacts_now := {}
var _pending_collide_events: Array = []

func step(delta: float) -> void:
	if host == null:
		return
	if physics_paused:
		_contacts_now.clear()
		_pending_collide_events.clear()
		return
	for key in _contacts.keys():
		if not _contacts_now.has(key):
			var parts := str(key).split("|")
			if parts.size() == 2:
				runtime.emit_event("collide_end", {"a": parts[0], "b": parts[1]})
	_contacts = _contacts_now.duplicate()
	_contacts_now = {}
	for event_payload in _pending_collide_events:
		runtime.emit_event("collide", event_payload)
	_pending_collide_events.clear()

func set_paused(on: bool) -> void:
	if physics_paused == on:
		return
	physics_paused = on
	if host != null:
		host.physics_process_callback = not on
	var stage := runtime._get_stage()
	if stage != null:
		_apply_pause_recursive(stage, on)
	_contacts.clear()
	_contacts_now.clear()
	_pending_collide_events.clear()

func _apply_pause_recursive(node: Node, on: bool) -> void:
	for child in node.get_children():
		if child is RigidBody2D:
			var rb := child as RigidBody2D
			rb.freeze = on
			if on:
				rb.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		elif child is Area2D:
			var area := child as Area2D
			area.monitoring = not on
			area.monitorable = not on
		_apply_pause_recursive(child, on)

func _ensure_physics_body(root: Node2D, mode: String) -> Node:
	var body := root.get_node_or_null(NodePath("PhysicsBody"))
	var current_mode := "none"
	if body is RigidBody2D:
		current_mode = "rigid"
	elif body is StaticBody2D:
		current_mode = "static"
	elif body is Area2D:
		current_mode = "area"
	elif body is Node2D:
		current_mode = "none"
	if current_mode == mode:
		return body

	var pivot: Node2D = null
	var direct_pivot := root.get_node_or_null(NodePath("Pivot"))
	if direct_pivot is Node2D:
		pivot = direct_pivot
	elif body != null:
		var body_pivot := body.get_node_or_null(NodePath("Pivot"))
		if body_pivot is Node2D:
			pivot = body_pivot

	var children: Array = []
	if body != null:
		for child in body.get_children():
			if child != pivot:
				children.append(child)
		_disconnect_signals(body, root.name)

	if body != null:
		for child in body.get_children():
			if child.get_parent() == body:
				body.remove_child(child)
		root.remove_child(body)
		body.queue_free()

	if pivot != null and pivot.get_parent() == root:
		root.remove_child(pivot)

	var st := _get_state(root.name)
	var new_body: Node
	match mode:
		"rigid":
			var rb := RigidBody2D.new()
			rb.gravity_scale = float(st.gravity) / DEFAULT_GRAVITY
			rb.contact_monitor = true
			rb.max_contacts_reported = 8
			rb.can_sleep = false
			rb.freeze = physics_paused
			if physics_paused:
				rb.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
			new_body = rb
		"static":
			new_body = StaticBody2D.new()
		"area":
			var area := Area2D.new()
			area.monitoring = not physics_paused
			area.monitorable = true
			new_body = area
		_:
			new_body = Node2D.new()
	new_body.name = "PhysicsBody"
	new_body.position = Vector2.ZERO
	new_body.set_meta(META_OBJECT_NAME, root.name)
	root.add_child(new_body)

	if pivot != null:
		new_body.add_child(pivot)

	for child in children:
		if child is CollisionShape2D and mode == "none":
			child.queue_free()
		else:
			new_body.add_child(child)

	if mode != "none":
		var has_shape := false
		for child in new_body.get_children():
			if child is CollisionShape2D:
				has_shape = true
				break
		if not has_shape:
			var shape := _create_collision_shape(root)
			if shape != null:
				new_body.add_child(shape)

	if new_body is RigidBody2D:
		(new_body as RigidBody2D).body_entered.connect(_on_body_entered.bind(root.name))
		(new_body as RigidBody2D).body_exited.connect(_on_body_exited.bind(root.name))
	if new_body is Area2D:
		(new_body as Area2D).body_entered.connect(_on_body_entered.bind(root.name))
		(new_body as Area2D).body_exited.connect(_on_body_exited.bind(root.name))
		(new_body as Area2D).area_entered.connect(_on_area_entered.bind(root.name))
		(new_body as Area2D).area_exited.connect(_on_area_exited.bind(root.name))
	return new_body

func _create_collision_shape(root: Node2D) -> CollisionShape2D:
	var pivot := root.get_node_or_null(NodePath("Pivot"))
	if pivot == null:
		return null
	var visual: Node = null
	for child in pivot.get_children():
		if child is CanvasItem:
			visual = child
			break
	if visual == null:
		return null
	var shape_node := CollisionShape2D.new()
	if visual is Sprite2D:
		var sp := visual as Sprite2D
		var tex_size := Vector2(100, 100)
		if sp.texture != null:
			tex_size = sp.texture.get_size()
		var size := tex_size * sp.scale
		var center_offset := Vector2.ZERO if sp.centered else size * 0.5
		var is_circle := root.has_meta(META_SHAPE) and str(root.get_meta(META_SHAPE)) == "circle"
		if is_circle:
			var circle := CircleShape2D.new()
			circle.radius = maxf(1.0, minf(size.x, size.y) * 0.5)
			shape_node.shape = circle
		else:
			var rect := RectangleShape2D.new()
			rect.size = size
			shape_node.shape = rect
		shape_node.position = center_offset
	elif visual is Label:
		var lb := visual as Label
		var size := lb.size
		shape_node.position = size * 0.5
		var rect := RectangleShape2D.new()
		rect.size = size
		shape_node.shape = rect
	elif visual is Polygon2D:
		var pg := visual as Polygon2D
		var rect := ObjectSystem._polygon_rect(pg.polygon)
		shape_node.position = rect.position + rect.size * 0.5
		var r := RectangleShape2D.new()
		r.size = rect.size
		shape_node.shape = r
	elif visual is Line2D:
		var ln := visual as Line2D
		var points := ln.points
		if points.size() >= 2:
			var p1: Vector2 = points[0]
			var p2: Vector2 = points[1]
			var length := p1.distance_to(p2)
			var center := (p1 + p2) * 0.5
			shape_node.position = center
			shape_node.rotation = (p2 - p1).angle()
			var cap := CapsuleShape2D.new()
			cap.height = length
			cap.radius = ln.width * 0.5
			shape_node.shape = cap
	return shape_node

func _disconnect_signals(body: Node, object_name: String) -> void:
	if body is RigidBody2D:
		var rb := body as RigidBody2D
		if rb.body_entered.is_connected(_on_body_entered.bind(object_name)):
			rb.body_entered.disconnect(_on_body_entered.bind(object_name))
		if rb.body_exited.is_connected(_on_body_exited.bind(object_name)):
			rb.body_exited.disconnect(_on_body_exited.bind(object_name))
	if body is Area2D:
		var area := body as Area2D
		if area.body_entered.is_connected(_on_body_entered.bind(object_name)):
			area.body_entered.disconnect(_on_body_entered.bind(object_name))
		if area.body_exited.is_connected(_on_body_exited.bind(object_name)):
			area.body_exited.disconnect(_on_body_exited.bind(object_name))
		if area.area_entered.is_connected(_on_area_entered.bind(object_name)):
			area.area_entered.disconnect(_on_area_entered.bind(object_name))
		if area.area_exited.is_connected(_on_area_exited.bind(object_name)):
			area.area_exited.disconnect(_on_area_exited.bind(object_name))

func _on_body_entered(other_body: Node, self_name: String) -> void:
	var other_name := _get_object_name(other_body)
	if other_name == "" or other_name == self_name:
		return
	var key := _contact_key(self_name, other_name)
	_contacts_now[key] = true
	if not _contacts.has(key):
		_pending_collide_events.append({"a": self_name, "b": other_name, "axis": "x"})

func _on_body_exited(other_body: Node, self_name: String) -> void:
	var other_name := _get_object_name(other_body)
	if other_name == "":
		return
	var key := _contact_key(self_name, other_name)
	_contacts_now.erase(key)

func _on_area_entered(other_area: Node, self_name: String) -> void:
	var other_name := _get_object_name(other_area)
	if other_name == "" or other_name == self_name:
		return
	var key := _contact_key(self_name, other_name)
	_contacts_now[key] = true
	if not _contacts.has(key):
		_pending_collide_events.append({"a": self_name, "b": other_name, "axis": "x"})

func _on_area_exited(other_area: Node, self_name: String) -> void:
	var other_name := _get_object_name(other_area)
	if other_name == "":
		return
	var key := _contact_key(self_name, other_name)
	_contacts_now.erase(key)

func _get_object_name(node: Node) -> String:
	var current := node
	while current != null:
		if current.has_meta(META_OBJECT_NAME):
			return str(current.get_meta(META_OBJECT_NAME))
		if current is Node2D and current.get_parent() == runtime._get_stage():
			current.set_meta(META_OBJECT_NAME, current.name)
			return current.name
		current = current.get_parent()
	return ""

func _contact_key(a: String, b: String) -> String:
	if a < b:
		return a + "|" + b
	return b + "|" + a

func execute(action: GyroAction, payload: Dictionary) -> void:
	match action.type:
		"SetVelocity":
			var object_name := runtime._name_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
			if object_name == "":
				return
			var root := runtime._get_target_node(object_name) as Node2D
			if root == null:
				return
			var body := _ensure_physics_body(root, "rigid") as RigidBody2D
			if body == null:
				return
			var velocity := body.linear_velocity
			var x_value: Variant = action.data.get("x", null)
			var y_value: Variant = action.data.get("y", null)
			if x_value != null:
				velocity.x = runtime._to_float(runtime._resolve_value(x_value, payload))
			if y_value != null:
				velocity.y = runtime._to_float(runtime._resolve_value(y_value, payload))
			body.linear_velocity = velocity
			var state := _get_state(object_name)
			state.velocity = velocity
		"AddVelocity":
			var object_name := runtime._name_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
			if object_name == "":
				return
			var root := runtime._get_target_node(object_name) as Node2D
			if root == null:
				return
			var body := _ensure_physics_body(root, "rigid") as RigidBody2D
			if body == null:
				return
			var velocity := body.linear_velocity
			var x_value: Variant = action.data.get("x", null)
			var y_value: Variant = action.data.get("y", null)
			if x_value != null:
				velocity.x += runtime._to_float(runtime._resolve_value(x_value, payload))
			if y_value != null:
				velocity.y += runtime._to_float(runtime._resolve_value(y_value, payload))
			body.linear_velocity = velocity
			var state := _get_state(object_name)
			state.velocity = velocity
		"SetGravity":
			var object_name := runtime._name_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
			if object_name == "":
				return
			var root := runtime._get_target_node(object_name) as Node2D
			if root == null:
				return
			var body := root.get_node_or_null(NodePath("PhysicsBody")) as RigidBody2D
			if body == null:
				return
			var gravity := runtime._to_float(runtime._resolve_value(action.data.get("value", 0.0), payload))
			body.gravity_scale = gravity / DEFAULT_GRAVITY
			var state := _get_state(object_name)
			state.gravity = gravity
		"SetSolid":
			var object_name := runtime._name_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
			if object_name == "":
				return
			var root := runtime._get_target_node(object_name) as Node2D
			if root == null:
				return
			var solid := runtime._to_bool(runtime._resolve_value(action.data.get("on", true), payload))
			if solid:
				_ensure_physics_body(root, "static")
			else:
				_remove_physics_body(root)
		"SetSensor":
			var object_name := runtime._name_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
			if object_name == "":
				return
			var root := runtime._get_target_node(object_name) as Node2D
			if root == null:
				return
			var sensor := runtime._to_bool(runtime._resolve_value(action.data.get("on", true), payload))
			if sensor:
				_ensure_physics_body(root, "area")
			else:
				_remove_physics_body(root)
		"SetDraggable":
			var object_name := runtime._name_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
			draggable[object_name] = runtime._to_bool(runtime._resolve_value(action.data.get("on", true), payload))
		"SetPhysicsPaused":
			set_paused(runtime._to_bool(runtime._resolve_value(action.data.get("on", true), payload)))
		"SetGlobalGravity":
			global_gravity = runtime._to_float(runtime._resolve_value(action.data.get("value", 0), payload))
			for key in physics_states.keys():
				var root := runtime._get_target_node(str(key)) as Node2D
				if root != null:
					var body := root.get_node_or_null(NodePath("PhysicsBody")) as RigidBody2D
					if body != null:
						body.gravity_scale = global_gravity / DEFAULT_GRAVITY
				physics_states[key].gravity = global_gravity

func _get_state(object_name: String) -> Dictionary:
	if not physics_states.has(object_name):
		physics_states[object_name] = {
			"velocity": Vector2.ZERO,
			"gravity": global_gravity,
			"solid": false,
			"sensor": false
		}
	return physics_states[object_name]

func _remove_physics_body(root: Node2D) -> void:
	var body := root.get_node_or_null(NodePath("PhysicsBody"))
	if body == null:
		return
	var pivot := body.get_node_or_null(NodePath("Pivot"))
	if pivot != null:
		body.remove_child(pivot)
		root.add_child(pivot)
	_disconnect_signals(body, root.name)
	root.remove_child(body)
	body.queue_free()

func try_grab(pos: Vector2) -> bool:
	var stage := runtime._get_stage()
	if stage == null:
		return false
	for child_value in stage.get_children():
		var root := child_value as Node2D
		if root == null or not root.visible:
			continue
		if not draggable.get(root.name, false):
			continue
		var aabb := runtime.object_system._get_aabb(root)
		if aabb.has_point(pos):
			_grab_node = root
			_grab_offset = pos - root.position
			var body := root.get_node_or_null(NodePath("PhysicsBody"))
			if body is RigidBody2D:
				var rb := body as RigidBody2D
				rb.freeze = true
				rb.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
				rb.linear_velocity = Vector2.ZERO
				rb.angular_velocity = 0.0
			return true
	return false

func move_grab(pos: Vector2) -> void:
	if _grab_node != null and is_instance_valid(_grab_node):
		_grab_node.position = pos - _grab_offset

func release_grab() -> void:
	if _grab_node != null and is_instance_valid(_grab_node) and _grab_node is Node2D:
		var body := (_grab_node as Node2D).get_node_or_null(NodePath("PhysicsBody"))
		if body is RigidBody2D and not physics_paused:
			var rb := body as RigidBody2D
			rb.freeze = false
			rb.linear_velocity = Vector2.ZERO
			rb.angular_velocity = 0.0
	_grab_node = null

func on_object_deleted(object_name: String) -> void:
	physics_states.erase(object_name)
	draggable.erase(object_name)
	if _grab_node != null and is_instance_valid(_grab_node) and _grab_node.name == object_name:
		_grab_node = null

func update_collision_shape(root: Node2D) -> void:
	var body := root.get_node_or_null(NodePath("PhysicsBody"))
	if body == null:
		return
	if not (body is CollisionObject2D):
		return
	var old_shape: CollisionShape2D = null
	for child in body.get_children():
		if child is CollisionShape2D:
			old_shape = child
			break
	if old_shape != null:
		body.remove_child(old_shape)
		old_shape.queue_free()
	var new_shape := _create_collision_shape(root)
	if new_shape != null:
		body.add_child(new_shape)
