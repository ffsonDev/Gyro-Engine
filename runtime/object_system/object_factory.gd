class_name ObjectFactory
extends RefCounted

var runtime: GyroEventRuntime
var pool: ObjectPool
var aabb: ObjectAABB

var last_object_name := ""
var object_counter := 0

func _init(rt: GyroEventRuntime, p: ObjectPool, a: ObjectAABB) -> void:
	runtime = rt
	pool = p
	aabb = a

func execute_create(action: GyroAction, payload: Dictionary) -> void:
	var stage := runtime._get_stage()
	if stage == null:
		return
	var obj_name := str(runtime._resolve_value(action.data.get("name", ""), payload))
	obj_name = GyroEventRuntime.sanitize_node_name(obj_name)
	if obj_name == "":
		return
	var old := runtime._get_target_node(obj_name)
	if old != null:
		runtime.object_system.on_object_deleted(obj_name)
		old.get_parent().remove_child(old)
		old.free()
	runtime.invalidate_node_cache()
	var root := pool.get_from_pool()
	root.name = obj_name
	var visual: Node = null
	var w := runtime._to_float(runtime._resolve_value(action.data.get("w", 100), payload))
	var h := runtime._to_float(runtime._resolve_value(action.data.get("h", 100), payload))
	var color := runtime._parse_color(str(runtime._resolve_value(action.data.get("color", "#ffffff"), payload)))
	var radius := int(runtime._to_float(runtime._resolve_value(action.data.get("radius", 0), payload)))
	var obj_type := str(runtime._resolve_value(action.data.get("type", "rect"), payload))
	match obj_type:
		"rect":
			if radius > 0:
				var poly := Polygon2D.new()
				poly.polygon = ObjectUtils.make_rounded_rect(w, h, radius)
				poly.color = color
				visual = poly
			else:
				var sp := Sprite2D.new()
				sp.texture = pool.get_white_tex()
				sp.centered = false
				sp.scale = Vector2(w, h)
				sp.modulate = color
				visual = sp
		"label":
			var lb := Label.new()
			lb.text = str(runtime._resolve_value(action.data.get("text", ""), payload))
			lb.add_theme_color_override("font_color", color)
			var font_ref := str(runtime._resolve_value(action.data.get("font", ""), payload))
			if font_ref != "":
				var loaded_font := runtime._load_font_ref(font_ref)
				if loaded_font != null:
					lb.add_theme_font_override("font", loaded_font)
			var fs := int(runtime._to_float(runtime._resolve_value(action.data.get("size", 24), payload)))
			if fs > 0:
				lb.add_theme_font_size_override("font_size", fs)
			lb.custom_minimum_size = Vector2(w, h)
			lb.size = Vector2(w, h)
			lb.clip_contents = true
			lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
			sp.texture = pool.get_circle_tex()
			sp.centered = true
			var r := maxf(1.0, runtime._to_float(runtime._resolve_value(action.data.get("radius", 50), payload)))
			sp.scale = Vector2(r * 2.0 / 64.0, r * 2.0 / 64.0)
			sp.modulate = color
			root.set_meta("gyro_shape", "circle")
			visual = sp
	if visual == null:
		root.queue_free()
		return
	root.add_child(visual)
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
	runtime.invalidate_node_cache()
	runtime.object_system.update_aabb(root)
	last_object_name = obj_name
	var variable_name := str(action.data.get("variable", ""))
	if variable_name != "":
		runtime.variables[variable_name] = root

func execute_create_typed(action: GyroAction, payload: Dictionary, forced_type: String, allowed: Array) -> void:
	var backup_data := action.data.duplicate(true)
	var backup_type := action.type
	var data := {}
	for key in allowed:
		if backup_data.has(key):
			data[key] = backup_data[key]
	data["type"] = forced_type
	action.data = data
	action.type = "CreateObject"
	execute_create(action, payload)
	action.type = backup_type
	action.data = backup_data

func execute_create_group(action: GyroAction, payload: Dictionary) -> void:
	var stage := runtime._get_stage()
	if stage == null:
		return
	var group_name := GyroEventRuntime.sanitize_node_name(str(runtime._resolve_value(action.data.get("name", ""), payload)))
	if group_name == "":
		return
	var old := runtime._get_target_node(group_name)
	if old != null:
		runtime.object_system.on_object_deleted(group_name)
		old.get_parent().remove_child(old)
		old.free()
	var group := pool.get_from_pool()
	group.name = group_name
	var base_pos := Vector2(
		runtime._to_float(runtime._resolve_value(action.data.get("x", 0), payload)),
		runtime._to_float(runtime._resolve_value(action.data.get("y", 0), payload))
	)
	group.position = runtime.apply_anchor(group, group_name, str(action.data.get("anchor", "free")), base_pos)
	stage.add_child(group)
	runtime.invalidate_node_cache()
	last_object_name = group_name

func execute_add_to_group(action: GyroAction, payload: Dictionary) -> void:
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

func execute_create_sprite_anim(action: GyroAction, payload: Dictionary) -> void:
	var stage := runtime._get_stage()
	if stage == null: return
	var obj_name := GyroEventRuntime.sanitize_node_name(str(runtime._resolve_value(action.data.get("name", ""), payload)))
	if obj_name == "": return
	var tex := runtime._load_texture_ref(str(runtime._resolve_value(action.data.get("sprite", ""), payload)))
	if tex == null: return
	var frame_w := maxf(1.0, runtime._to_float(runtime._resolve_value(action.data.get("frame_w", 32), payload)))
	var frame_h := maxf(1.0, runtime._to_float(runtime._resolve_value(action.data.get("frame_h", 32), payload)))
	var count := maxi(1, int(runtime._to_float(runtime._resolve_value(action.data.get("count", 1), payload))))
	var fps := maxf(1.0, runtime._to_float(runtime._resolve_value(action.data.get("fps", 8), payload)))
	var anim := str(action.data.get("anim", "default"))
	var frames := SpriteFrames.new()
	if not frames.has_animation(anim): frames.add_animation(anim)
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
		runtime.object_system.on_object_deleted(obj_name)
		old.get_parent().remove_child(old)
		old.free()
	var root := pool.get_from_pool()
	root.name = obj_name
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	root.add_child(sprite)
	var base_pos := Vector2(
		runtime._to_float(runtime._resolve_value(action.data.get("x", 0), payload)),
		runtime._to_float(runtime._resolve_value(action.data.get("y", 0), payload))
	)
	root.position = runtime.apply_anchor(root, obj_name, str(action.data.get("anchor", "free")), base_pos)
	stage.add_child(root)
	runtime.invalidate_node_cache()
	runtime.object_system.update_aabb(root)
	sprite.play(anim)
	last_object_name = obj_name

func execute_create_circle(action: GyroAction, payload: Dictionary) -> void:
	var stage := runtime._get_stage()
	if stage == null: return
	var obj_name := GyroEventRuntime.sanitize_node_name(str(runtime._resolve_value(action.data.get("name", ""), payload)))
	if obj_name == "": return
	var old := runtime._get_target_node(obj_name)
	if old != null:
		runtime.object_system.on_object_deleted(obj_name)
		old.get_parent().remove_child(old)
		old.free()
	var root := pool.get_from_pool()
	root.name = obj_name
	root.set_meta("gyro_shape", "circle")
	var sp := Sprite2D.new()
	sp.texture = pool.get_circle_tex()
	sp.centered = true
	var r := maxf(1.0, runtime._to_float(runtime._resolve_value(action.data.get("radius", 50), payload)))
	sp.scale = Vector2(r * 2.0 / 64.0, r * 2.0 / 64.0)
	sp.modulate = runtime._parse_color(str(runtime._resolve_value(action.data.get("color", "#ffffff"), payload)))
	root.add_child(sp)
	var border_w := runtime._to_float(runtime._resolve_value(action.data.get("border_w", 0), payload))
	if border_w > 0:
		var border := ObjectUtils.make_circle_border(
			r,
			runtime._parse_color(str(runtime._resolve_value(action.data.get("border_color", "#ffffff"), payload))),
			border_w
		)
		root.add_child(border)
	var base_pos := Vector2(
		runtime._to_float(runtime._resolve_value(action.data.get("x", 0), payload)),
		runtime._to_float(runtime._resolve_value(action.data.get("y", 0), payload))
	)
	root.position = runtime.apply_anchor(root, obj_name, str(action.data.get("anchor", "free")), base_pos)
	stage.add_child(root)
	runtime.invalidate_node_cache()
	last_object_name = obj_name

func execute_create_line(action: GyroAction, payload: Dictionary) -> void:
	var stage := runtime._get_stage()
	if stage == null: return
	var obj_name := GyroEventRuntime.sanitize_node_name(str(runtime._resolve_value(action.data.get("name", ""), payload)))
	if obj_name == "": return
	var old := runtime._get_target_node(obj_name)
	if old != null:
		runtime.object_system.on_object_deleted(obj_name)
		old.get_parent().remove_child(old)
		old.free()
	var root := pool.get_from_pool()
	root.name = obj_name
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
	root.add_child(line)
	root.position = runtime.apply_anchor(root, obj_name, str(action.data.get("anchor", "free")), p1)
	stage.add_child(root)
	runtime.invalidate_node_cache()
	last_object_name = obj_name

func execute_spawn(action: GyroAction, payload: Dictionary) -> void:
	if runtime.host == null:
		return
	var scene_ref := str(runtime._resolve_value(action.data.get("scene", ""), payload))
	if scene_ref == "":
		return
	var stored_path := scene_ref
	var project := runtime._get_project()
	if project != null:
		for v in project.assets:
			var a := v as GyroAsset
			if a != null and (a.id == scene_ref or a.asset_name == scene_ref):
				stored_path = a.path
				break
	var scene_path := GyroAssetPaths.resolve_asset_path(stored_path, runtime._project_path())
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
	runtime.invalidate_node_cache()
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
