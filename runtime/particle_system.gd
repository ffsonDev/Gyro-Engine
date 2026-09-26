class_name ParticleSystem
extends GyroSystem

func execute(action: GyroAction, payload: Dictionary) -> void:
	match action.type:
		"CreateParticles":
			_action_create_particles(action, payload)
		"SetParticlesParam":
			_action_set_particles_param(action, payload)
		"DeleteParticles":
			_action_delete_particles(action, payload)

func _make_particle_texture() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)

func _confetti_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.2, 0.3, 1))
	g.set_color(1, Color(0.2, 0.6, 1, 1))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

func _action_create_particles(action: GyroAction, payload: Dictionary) -> void:
	var stage := runtime._get_stage()
	if stage == null:
		return
	var p_name := GyroEventRuntime.sanitize_node_name(str(runtime._resolve_value(action.data.get("name", ""), payload)))
	if p_name == "":
		return
	var old := runtime._get_target_node(p_name)
	if old != null:
		old.get_parent().remove_child(old)
		old.free()
	var p := GPUParticles2D.new()
	p.name = p_name
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(240, 10, 1)
	m.scale_min = 4.0
	m.scale_max = 4.0
	p.amount = 120
	p.lifetime = 3.0
	match str(action.data.get("preset", "snow")):
		"rain":
			m.direction = Vector3(0, 1, 0)
			m.initial_velocity_min = 500.0
			m.initial_velocity_max = 700.0
			m.gravity = Vector3(0, 300, 0)
			m.color = Color(0.6, 0.75, 1.0, 0.8)
			p.lifetime = 1.5
		"fire":
			m.direction = Vector3(0, -1, 0)
			m.initial_velocity_min = 60.0
			m.initial_velocity_max = 120.0
			m.gravity = Vector3(0, -50, 0)
			m.color = Color(1.0, 0.5, 0.1, 0.9)
			m.scale_min = 6.0
			m.scale_max = 6.0
			p.lifetime = 1.0
		"sparks":
			m.direction = Vector3(0, -1, 0)
			m.spread = 180.0
			m.initial_velocity_min = 150.0
			m.initial_velocity_max = 350.0
			m.gravity = Vector3(0, 400, 0)
			m.color = Color(1.0, 0.9, 0.3, 1.0)
			m.scale_min = 3.0
			m.scale_max = 3.0
			p.lifetime = 0.8
		"confetti":
			m.direction = Vector3(0, -1, 0)
			m.spread = 60.0
			m.initial_velocity_min = 200.0
			m.initial_velocity_max = 400.0
			m.gravity = Vector3(0, 500, 0)
			m.color_ramp = _confetti_ramp()
			m.scale_min = 5.0
			m.scale_max = 5.0
			p.lifetime = 2.5
		_:
			m.direction = Vector3(0, 1, 0)
			m.initial_velocity_min = 30.0
			m.initial_velocity_max = 60.0
			m.gravity = Vector3(0, 20, 0)
			m.color = Color(1, 1, 1, 0.9)
	p.process_material = m
	p.texture = _make_particle_texture()
	var base_pos := Vector2(
		runtime._to_float(runtime._resolve_value(action.data.get("x", 240), payload)),
		runtime._to_float(runtime._resolve_value(action.data.get("y", 0), payload))
	)
	p.position = runtime.apply_anchor(p, p_name, str(action.data.get("anchor", "free")), base_pos)
	p.emitting = true
	stage.add_child(p)
	runtime.object_system.last_object_name = p_name

func _action_set_particles_param(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target is GPUParticles2D:
		var p := target as GPUParticles2D
		var m := p.process_material as ParticleProcessMaterial
		var param := str(action.data.get("param", "speed"))
		var value := runtime._to_float(runtime._resolve_value(action.data.get("value", 0), payload))
		if m != null:
			match param:
				"speed":
					m.initial_velocity_min = value
					m.initial_velocity_max = value
				"gravity":
					m.gravity = Vector3(0, value, 0)
				"size":
					m.scale_min = value
					m.scale_max = value
		if param == "amount":
			p.amount = int(value)

func _action_delete_particles(action: GyroAction, payload: Dictionary) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target != null:
		runtime.object_system.on_object_deleted(target.name)
		target.queue_free()
