class_name GyroEventRuntime
extends RefCounted

var blueprint: GyroEventBlueprint
var host: Node
var variables := {}
var print_handler: Callable

var event_system: EventSystem
var object_system: ObjectSystem
var physics_system: PhysicsSystem
var audio_system: AudioSystem
var camera_system: CameraSystem
var tween_system: TweenSystem
var timer_system: TimerSystem
var tag_system: TagSystem
var variable_system: VariableSystem
var widget_system: WidgetSystem
var io_system: IOSystem
var ui_system: UISystem
var particle_system: ParticleSystem

const ALLOWED_NODE_PROPERTIES := [
	"position", "size", "custom_minimum_size", "visible",
	"modulate", "self_modulate", "z_index", "rotation", "scale",
	"text", "color", "mouse_filter", "volume_db", "pitch_scale"
]

var _var_cache := {}
var _var_cache_dirty := true

func _init() -> void:
	pass

func setup(bp: GyroEventBlueprint) -> void:
	blueprint = bp
	if blueprint == null:
		blueprint = GyroEventBlueprint.new()
	variables = blueprint.variables.duplicate(true)
	_var_cache_dirty = true
	_init_systems()
	event_system.setup()

func invalidate_var_cache() -> void:
	_var_cache_dirty = true

func _rebuild_var_cache() -> void:
	_var_cache.clear()
	for key in variables.keys():
		_var_cache["$var." + str(key)] = str(variables[key])
	_var_cache_dirty = false

func _init_systems() -> void:
	event_system = EventSystem.new()
	object_system = ObjectSystem.new()
	physics_system = PhysicsSystem.new()
	audio_system = AudioSystem.new()
	camera_system = CameraSystem.new()
	tween_system = TweenSystem.new()
	timer_system = TimerSystem.new()
	tag_system = TagSystem.new()
	variable_system = VariableSystem.new()
	widget_system = WidgetSystem.new()
	io_system = IOSystem.new()
	ui_system = UISystem.new()
	particle_system = ParticleSystem.new()

	var all_systems := [
		event_system, object_system, physics_system, audio_system,
		camera_system, tween_system, timer_system, tag_system,
		variable_system, widget_system, io_system, ui_system,
		particle_system
	]
	for system in all_systems:
		system.runtime = self
		system.host = host
		system.setup()

func has_event(event_name: String) -> bool:
	return event_system.has_event(event_name)

func apply_anchor(node: Node, obj_name: String, anchor: String, base_pos: Vector2) -> Vector2:
	var gh := host as GyroEventHost
	if gh == null:
		return base_pos
	if anchor == "" or anchor == "free":
		gh.unregister_anchor(obj_name)
		return base_pos
	gh.register_anchor(obj_name, anchor)
	gh.set_anchor_offset(obj_name, base_pos)
	return gh.anchor_point_local(gh.get_viewport_rect().size, anchor) + base_pos

func emit_event(event_name: String, payload: Dictionary) -> void:
	event_system.emit_event(event_name, payload)

func execute_action(action: GyroAction, payload: Dictionary) -> void:
	match action.type:
		"If":
			if _to_bool(_resolve_value(action.data.get("condition", "true"), payload)):
				event_system._execute_flow_blocks(action, payload)
		"Repeat":
			var count := int(_to_float(_resolve_value(action.data.get("count", 1), payload)))
			for i in range(clampi(count, 0, 1000)):
				event_system._execute_flow_blocks(action, payload)
		"Wait":
			pass
		"SetVariable", "AddToVariable", "SetTableValue", "GetTableValue", \
		"InsertArrayValue", "RemoveArrayValue", "OverwriteTable", \
		"ForEachTable", "LoopRange":
			variable_system.execute(action, payload)
			_var_cache_dirty = true
		"MoveNode", "SetNodeProperty", "SetSize", "SetText", "CreateObject", \
		"DeleteObject", "SetVisible", "SetOpacity", "SetRotation", "SetScale", \
		"ChangeLayer", "SetFontSize", "SetColor", "SetTextAlign", "SetTexture", \
		"SetCornerRadius", "SetPivot", "SetObjectMeta", "FaceObject", \
		"PlayAnimation", "StopAnimation", "CreateGroup", "AddToGroup", \
		"CreateSpriteAnim", "SetFrame", "CreateCircle", "CreateLine", \
		"SetGradient", "SetBorder", "Spawn":
			object_system.execute(action, payload)
		"SetVelocity", "AddVelocity", "SetGravity", "SetSolid", "SetSensor", \
		"SetDraggable", "SetPhysicsPaused", "SetGlobalGravity":
			physics_system.execute(action, payload)
		"PlaySound", "StopSound", "SetSoundVolume":
			audio_system.execute(action, payload)
		"SetCameraPosition", "CameraFollow", "SetParallax":
			camera_system.execute(action, payload)
		"TweenPosition", "TweenScale", "TweenRotation", "TweenOpacity", "StopTween":
			tween_system.execute(action, payload)
		"StartTimer", "StopTimer":
			timer_system.execute(action, payload)
		"AddTag", "DeleteByTag", "SetVisibleByTag", "SetPositionByTag", \
		"SetRotationByTag", "SetOpacityByTag", "SetScaleByTag", "ChangeLayerByTag":
			tag_system.execute(action, payload)
		"CreateInput", "CreateSlider", "CreateToggle", "GetWidgetText", \
		"SetSliderValue", "SetToggleState":
			widget_system.execute(action, payload)
		"ReadFile", "WriteFile", "FileOp", "HttpRequest", "SaveValue", "LoadValue":
			io_system.execute(action, payload)
		"Print", "Toast", "SetBackgroundColor", "SetOrientation", "Clipboard", \
		"OpenURL", "Quit", "RandomSeed":
			ui_system.execute(action, payload)
		"CreateParticles", "SetParticlesParam", "DeleteParticles":
			particle_system.execute(action, payload)
		"SetAnchor":
			_action_set_anchor(action, payload)
		"EmitEvent":
			var ev := str(_resolve_value(action.data.get("event", ""), payload))
			if ev != "":
				var pl: Dictionary = {}
				var parsed = JSON.parse_string(str(_resolve_value(action.data.get("payload", "{}"), payload)))
				if parsed is Dictionary:
					pl = parsed
				emit_event(ev, pl)
		_:
			_debug("execute_action: неизвестный тип " + action.type)

func _action_set_anchor(action: GyroAction, payload: Dictionary) -> void:
	var target := _node_from_value(_resolve_value(action.data.get("node", ""), payload))
	if target == null or not (target is Node2D):
		return
	if host == null:
		return
	var node_2d := target as Node2D
	var anchor := str(_resolve_value(action.data.get("anchor", "free"), payload))
	
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

func step_physics(delta: float) -> void:
	physics_system.step(delta)
	camera_system.step(delta)

func try_grab(pos: Vector2) -> bool:
	return physics_system.try_grab(pos)

func move_grab(pos: Vector2) -> void:
	physics_system.move_grab(pos)

func release_grab() -> void:
	physics_system.release_grab()

func on_timer_fired(timer_name: String) -> void:
	timer_system.on_timer_fired(timer_name)

func _get_project() -> GyroProject:
	var gyro_host := host as GyroEventHost
	if gyro_host != null:
		return gyro_host.project
	if host == null:
		return null
	var proj = host.get("project")
	return proj as GyroProject

func _project_path() -> String:
	var gyro_host := host as GyroEventHost
	if gyro_host != null and gyro_host.project_path != "":
		return gyro_host.project_path
	if host != null:
		var p = host.get("project_path")
		if p != null and str(p) != "":
			return str(p)
	var proj := _get_project()
	if proj != null:
		return proj.resource_path
	return ""

func _get_target_node(node_path: String) -> Node:
	if host == null:
		return null
	if node_path == "":
		return host
	var direct := host.get_node_or_null(NodePath(node_path))
	if direct != null:
		return direct
	var stage := _get_stage()
	if stage != null:
		var in_stage := stage.get_node_or_null(NodePath(node_path))
		if in_stage != null:
			return in_stage
		var found := _find_by_name(stage, node_path)
		if found != null:
			return found
	var ui := _get_stage_ui()
	if ui != null:
		var in_ui := ui.get_node_or_null(NodePath(node_path))
		if in_ui != null:
			return in_ui
	return null

func _find_by_name(node: Node, node_name: String) -> Node:
	for c in node.get_children():
		if c.name == node_name:
			return c
		var r := _find_by_name(c, node_name)
		if r != null:
			return r
	return null
	
func _get_stage() -> Node:
	if host == null:
		return null
	if host.has_method("get_stage"):
		return host.get_stage()
	return host.get_node_or_null(NodePath("Stage"))

func _get_stage_ui() -> Control:
	if host == null:
		return null
	var ui := host.get_node_or_null(NodePath("StageUI"))
	if ui is Control:
		return ui as Control
	return null

func _node_from_value(value: Variant) -> Node:
	if value is Node:
		return value as Node
	return _get_target_node(str(value))

func _name_from_value(value: Variant) -> String:
	if value is Node:
		return (value as Node).name
	return str(value)

func _resolve_value(value: Variant, payload: Dictionary) -> Variant:
	if value is String:
		var text := str(value)
		if text.begins_with("$payload."):
			return payload.get(text.substr(9), null)
		if text.begins_with("$var."):
			return variables.get(text.substr(5), null)
		if text.contains("$var.") or text.contains("$payload."):
			return _interpolate(text, payload)
		return text
	return value

func _interpolate(text: String, payload: Dictionary) -> String:
	if _var_cache_dirty:
		_rebuild_var_cache()

	var result := text
	for key in _var_cache.keys():
		if result.contains(key):
			result = result.replace(key, _var_cache[key])

	var payload_keys := payload.keys()
	payload_keys.sort_custom(func(a, b): return str(a).length() > str(b).length())
	for key in payload_keys:
		result = result.replace("$payload." + str(key), str(payload[key]))

	return result

func _to_float(value: Variant) -> float:
	if value == null:
		return 0.0
	if value is int or value is float:
		return float(value)
	if value is bool:
		return 1.0 if value else 0.0
	if value is String:
		return value.to_float()
	return 0.0

func _to_bool(value: Variant) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return value != 0
	if value is String:
		var t := str(value).to_lower()
		return t == "true" or t == "1" or t == "yes" or t == "да"
	return false

func _parse_color(text: String) -> Color:
	if text.begins_with("#"):
		return Color(text)
	return Color.WHITE

static func sanitize_node_name(raw: String) -> String:
	var clean := raw.strip_edges()
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		clean = clean.replace(ch, "_")
	clean = clean.replace(" ", "_")
	if clean == "":
		clean = "object"
	return clean

func _load_texture_ref(texture_ref: String) -> Texture2D:
	var stored_path := texture_ref
	var project := _get_project()
	if project != null:
		for v in project.assets:
			var a := v as GyroAsset
			if a != null and a.kind == "sprite" and (a.id == texture_ref or a.asset_name == texture_ref):
				stored_path = a.path
				break
	var resolved := GyroAssetPaths.resolve_asset_path(stored_path, _project_path())
	if resolved == "":
		return null
	return GyroMedia.load_texture(resolved)

func _debug(text: String) -> void:
	if print_handler.is_valid():
		print_handler.call(text)
	else:
		print(text)
