class_name GyroEventRuntime
extends RefCounted

var blueprint: GyroEventBlueprint
var host: Node
var variables := {}
var tables := {}
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
var _timing_enabled := false
var _action_registry := {}
var _node_cache := {}
var _node_cache_dirty := true
var _param_stack: Array = []
var _custom_depth := 0
var _expr_extra_cb: Callable
var _interpolate_regex: RegEx = null
var _start_time_ms := 0
var _shutdown := false
var _sequences: Array = []
var _blocking_cache := {}
var _blocking_custom := {}

const BLOCKING_TYPES := ["Wait", "WaitUntil"]
const FLOW_TYPES := ["If", "Repeat", "ForEachTable", "LoopRange"]

const ALLOWED_NODE_PROPERTIES := [
	"position", "size", "custom_minimum_size", "visible",
	"modulate", "self_modulate", "z_index", "rotation", "scale",
	"text", "color", "mouse_filter", "volume_db", "pitch_scale"
]

func _init() -> void:
	_expr_extra_cb = Callable(self, "_expr_extra")

func setup(bp: GyroEventBlueprint) -> void:
	_shutdown = false
	_sequences.clear()
	_blocking_cache.clear()
	_blocking_custom.clear()
	blueprint = bp
	if blueprint == null:
		blueprint = GyroEventBlueprint.new()
	variables = blueprint.variables.duplicate(true)
	tables = blueprint.tables.duplicate(true) if blueprint.tables != null else {}
	_start_time_ms = Time.get_ticks_msec()
	_init_systems()
	event_system.setup()

func _init_systems() -> void:
	var needed := _scan_needed_systems()
	event_system = EventSystem.new()
	object_system = ObjectSystem.new()
	physics_system = PhysicsSystem.new() if needed.has("physics") else null
	audio_system = AudioSystem.new() if needed.has("audio") else null
	camera_system = CameraSystem.new() if needed.has("camera") else null
	tween_system = TweenSystem.new() if needed.has("tween") else null
	timer_system = TimerSystem.new()
	tag_system = TagSystem.new() if needed.has("tag") else null
	variable_system = VariableSystem.new() if needed.has("variable") else null
	widget_system = WidgetSystem.new() if needed.has("widget") else null
	io_system = IOSystem.new() if needed.has("io") else null
	ui_system = UISystem.new() if needed.has("ui") else null
	particle_system = ParticleSystem.new() if needed.has("particle") else null
	var all_systems := [
		event_system, object_system, physics_system, audio_system,
		camera_system, tween_system, timer_system, tag_system,
		variable_system, widget_system, io_system, ui_system,
		particle_system
	]
	for system in all_systems:
		if system != null:
			system.runtime = self
			system.host = host
			system.setup()
	_register_actions()

func _scan_needed_systems() -> Dictionary:
	var needed := {}
	if blueprint == null:
		return needed
	for rule in blueprint.rules:
		for action in rule.actions:
			_scan_action_type(action.type, needed)
			_scan_nested_blocks(action, needed)
	return needed

func _scan_nested_blocks(action: GyroAction, needed: Dictionary) -> void:
	var blocks = action.data.get("blocks", [])
	if blocks is Array:
		for b in (blocks as Array):
			var bd := b as Dictionary
			if bd.is_empty():
				continue
			var type := str(bd.get("type", ""))
			_scan_action_type(type, needed)
			var child := GyroAction.new()
			child.type = type
			child.data = (bd.get("data", {}) as Dictionary).duplicate(true)
			_scan_nested_blocks(child, needed)

func _scan_action_type(type: String, needed: Dictionary) -> void:
	match type:
		"SetVelocity", "AddVelocity", "SetGravity", "SetSolid", "SetSensor", "SetDraggable", "SetPhysicsPaused", "SetGlobalGravity":
			needed["physics"] = true
		"PlaySound", "StopSound", "SetSoundVolume":
			needed["audio"] = true
		"SetCameraPosition", "CameraFollow", "SetParallax":
			needed["camera"] = true
		"TweenPosition", "TweenScale", "TweenRotation", "TweenOpacity", "StopTween":
			needed["tween"] = true
		"AddTag", "DeleteByTag", "SetVisibleByTag", "SetPositionByTag", "SetRotationByTag", "SetOpacityByTag", "SetScaleByTag", "ChangeLayerByTag":
			needed["tag"] = true
		"SetVariable", "AddToVariable", "SetTableValue", "GetTableValue", "InsertArrayValue", "RemoveArrayValue", "OverwriteTable", "ForEachTable", "LoopRange":
			needed["variable"] = true
		"CreateInput", "CreateSlider", "CreateToggle", "GetWidgetText", "SetSliderValue", "SetToggleState":
			needed["widget"] = true
		"ReadFile", "WriteFile", "FileOp", "HttpRequest", "SaveValue", "LoadValue":
			needed["io"] = true
		"Print", "Toast", "SetBackgroundColor", "SetOrientation", "Clipboard", "OpenURL", "Quit", "RandomSeed":
			needed["ui"] = true
		"CreateParticles", "SetParticlesParam", "DeleteParticles":
			needed["particle"] = true
		_:
			if type.begins_with("custom:"):
				_scan_custom_type(type, needed)

func _scan_custom_type(type: String, needed: Dictionary) -> void:
	var guard := "seen_" + type
	if needed.has(guard):
		return
	needed[guard] = true
	var def := GyroCustomRegistry.find_block(_get_project(), type.substr(7))
	if def == null:
		return
	for av in def.body:
		var act := av as GyroAction
		if act == null:
			continue
		_scan_action_type(act.type, needed)
		_scan_nested_blocks(act, needed)

func _register_actions() -> void:
	_action_registry.clear()
	var reg := func(types: Array, system: GyroSystem) -> void:
		if system == null:
			return
		for t in types:
			_action_registry[t] = system
	reg.call(["SetVariable", "AddToVariable", "SetTableValue", "GetTableValue", "InsertArrayValue", "RemoveArrayValue", "OverwriteTable", "ForEachTable", "LoopRange"], variable_system)
	reg.call(["MoveNode", "SetNodeProperty", "SetSize", "SetText", "CreateObject", "CreateSprite", "CreateText", "DeleteObject", "SetVisible", "SetOpacity", "SetRotation", "SetScale", "ChangeLayer", "SetFontSize", "SetColor", "SetTextAlign", "SetTexture", "SetCornerRadius", "SetPivot", "SetObjectMeta", "FaceObject", "PlayAnimation", "StopAnimation", "CreateGroup", "AddToGroup", "CreateSpriteAnim", "SetFrame", "CreateCircle", "CreateLine", "SetGradient", "SetBorder", "Spawn"], object_system)
	reg.call(["SetVelocity", "AddVelocity", "SetGravity", "SetSolid", "SetSensor", "SetDraggable", "SetPhysicsPaused", "SetGlobalGravity"], physics_system)
	reg.call(["PlaySound", "StopSound", "SetSoundVolume"], audio_system)
	reg.call(["SetCameraPosition", "CameraFollow", "SetParallax"], camera_system)
	reg.call(["TweenPosition", "TweenScale", "TweenRotation", "TweenOpacity", "StopTween"], tween_system)
	reg.call(["StartTimer", "StopTimer"], timer_system)
	reg.call(["AddTag", "DeleteByTag", "SetVisibleByTag", "SetPositionByTag", "SetRotationByTag", "SetOpacityByTag", "SetScaleByTag", "ChangeLayerByTag"], tag_system)
	reg.call(["CreateInput", "CreateSlider", "CreateToggle", "GetWidgetText", "SetSliderValue", "SetToggleState"], widget_system)
	reg.call(["ReadFile", "WriteFile", "FileOp", "HttpRequest", "SaveValue", "LoadValue"], io_system)
	reg.call(["Print", "Toast", "SetBackgroundColor", "SetOrientation", "Clipboard", "OpenURL", "Quit", "RandomSeed"], ui_system)
	reg.call(["CreateParticles", "SetParticlesParam", "DeleteParticles"], particle_system)

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
	var off := gh.world_offset
	if node.get_parent() == gh.get_stage():
		off = gh.get_stage().position
	return gh.anchor_point(gh.get_viewport_rect().size, anchor) - off + base_pos

func emit_event(event_name: String, payload: Dictionary) -> void:
	if _shutdown:
		return
	event_system.emit_event(event_name, payload)

func spawn_sequence(actions: Array, payload: Dictionary, params: Dictionary = {}) -> GyroSequence:
	var seq := GyroSequence.new()
	seq.runtime = self
	seq.actions = actions
	seq.payload = payload
	seq.params = params
	_sequences.append(seq)
	return seq

func start_sequence(actions: Array, payload: Dictionary, params: Dictionary = {}) -> GyroSequence:
	var seq := spawn_sequence(actions, payload, params)
	seq.run()
	return seq

func _release_sequence(seq: GyroSequence) -> void:
	_sequences.erase(seq)

func can_await() -> bool:
	return host != null and is_instance_valid(host) and host.is_inside_tree() and host.get_tree() != null

func wait_seconds(seconds: float) -> void:
	if not can_await():
		return
	await host.get_tree().create_timer(maxf(0.01, seconds), false).timeout

func next_frame() -> float:
	if not can_await():
		return 0.0
	await host.get_tree().process_frame
	if not can_await():
		return 0.0
	return host.get_process_delta_time()

func eval_condition(text: String, payload: Dictionary, params: Dictionary = {}) -> bool:
	var out: Array = []
	if GyroExpression.try_eval(text, variables, payload, _expr_extra_cb, out, params):
		return _to_bool(out[0])
	return _to_bool(text)

func _is_blocking_list(arr: Array) -> bool:
	for v in arr:
		if v is GyroAction:
			if _is_blocking_action(v as GyroAction):
				return true
		elif v is Dictionary:
			var d: Dictionary = v
			if _is_blocking_type(str(d.get("type", "")), d.get("data", {})):
				return true
	return false

func _is_blocking_action(a: GyroAction) -> bool:
	if a == null:
		return false
	if _blocking_cache.has(a):
		return bool(_blocking_cache[a])
	var r := _is_blocking_type(a.type, a.data)
	_blocking_cache[a] = r
	return r

func _is_blocking_type(type: String, data: Variant) -> bool:
	if BLOCKING_TYPES.has(type):
		return true
	var d: Dictionary = data if data is Dictionary else {}
	if FLOW_TYPES.has(type):
		var b = d.get("blocks", [])
		return b is Array and _is_blocking_list(b as Array)
	if type.begins_with("custom:"):
		return _custom_blocking(type.substr(7), {})
	return false

func _custom_blocking(id: String, seen: Dictionary) -> bool:
	if seen.has(id):
		return false
	if _blocking_custom.has(id):
		return bool(_blocking_custom[id])
	seen[id] = true
	var def := GyroCustomRegistry.find_block(_get_project(), id)
	if def == null:
		return false
	var result := false
	for av in def.body:
		var a := av as GyroAction
		if a == null:
			continue
		if BLOCKING_TYPES.has(a.type):
			result = true
			break
		if FLOW_TYPES.has(a.type):
			var b = a.data.get("blocks", [])
			if b is Array and _is_blocking_list(b as Array):
				result = true
				break
		elif str(a.type).begins_with("custom:") and _custom_blocking(str(a.type).substr(7), seen):
			result = true
			break
	if seen.size() <= 1:
		_blocking_custom[id] = result
	return result

func execute_action(action: GyroAction, payload: Dictionary) -> void:
	if _shutdown:
		return
	var start_usec := 0
	if _timing_enabled:
		start_usec = Time.get_ticks_usec()
	if str(action.type).begins_with("custom:"):
		_execute_custom(action, payload)
		return
	match action.type:
		"If":
			if eval_condition(str(_resolve_value(action.data.get("condition", "true"), payload)), payload):
				event_system._execute_flow_blocks(action, payload)
		"Repeat":
			var count := int(_to_float(_resolve_value(action.data.get("count", 1), payload)))
			for i in range(clampi(count, 0, 1000)):
				event_system._execute_flow_blocks(action, payload)
		"Wait", "WaitUntil":
			pass
		"EmitEvent":
			var ev := str(_resolve_value(action.data.get("event", ""), payload))
			if ev != "":
				var pl: Dictionary = {}
				var parsed = JSON.parse_string(str(_resolve_value(action.data.get("payload", "{}"), payload)))
				if parsed is Dictionary:
					pl = parsed
				emit_event(ev, pl)
		"SetAnchor":
			_action_set_anchor(action, payload)
		_:
			var system = _action_registry.get(action.type)
			if system == null:
				_debug("execute_action: неизвестный тип " + action.type)
				return
			system.execute(action, payload)

func _execute_custom(action: GyroAction, payload: Dictionary) -> void:
	var id := str(action.type).substr(7)
	if _custom_depth >= 8:
		_debug("Custom depth limit: " + id)
		return
	var def := GyroCustomRegistry.find_block(_get_project(), id)
	if def == null:
		_debug("Unknown custom block: " + id)
		return
	var params := {}
	for f in def.fields:
		var key := str(f.get("key", ""))
		if key == "":
			continue
		params[key] = _resolve_value(action.data.get(key, f.get("default", null)), payload)
	_param_stack.append(params)
	_custom_depth += 1
	for av in def.body:
		var act := av as GyroAction
		if act == null or act.disabled:
			continue
		execute_action(act, payload)
	_custom_depth -= 1
	_param_stack.pop_back()

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
	var off: Variant = host.world_offset
	if node_2d.get_parent() == host.get_stage():
		off = host.get_stage().position
	var anchor_pt: Vector2 = host.anchor_point(vp_size, anchor) - off
	node_2d.set_meta("gyro_anchor", anchor)
	node_2d.set_meta("gyro_anchor_offset", Vector2.ZERO)
	host.register_anchor(node_2d.name, anchor)
	host.set_anchor_offset(node_2d.name, Vector2.ZERO)
	node_2d.position = anchor_pt

func step_physics(delta: float) -> void:
	if physics_system != null:
		physics_system.step(delta)
	if camera_system != null:
		camera_system.step(delta)

func try_grab(pos: Vector2) -> bool:
	if physics_system == null:
		return false
	return physics_system.try_grab(pos)

func move_grab(pos: Vector2) -> void:
	if physics_system != null:
		physics_system.move_grab(pos)

func release_grab() -> void:
	if physics_system != null:
		physics_system.release_grab()

func enable_timing() -> void:
	_timing_enabled = true

func disable_timing() -> void:
	_timing_enabled = false

func on_timer_fired(timer_name: String) -> void:
	if timer_system != null:
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

func invalidate_node_cache() -> void:
	_node_cache_dirty = true
	_node_cache.clear()

func _get_target_node(node_path: String) -> Node:
	if host == null:
		return null
	if node_path == "":
		return host
	if not _node_cache_dirty and _node_cache.has(node_path):
		var cached = _node_cache[node_path]
		if is_instance_valid(cached):
			return cached
		_node_cache.erase(node_path)
	var direct := host.get_node_or_null(NodePath(node_path))
	if direct != null:
		_node_cache[node_path] = direct
		return direct
	var stage := _get_stage()
	if stage != null:
		var in_stage := stage.get_node_or_null(NodePath(node_path))
		if in_stage != null:
			_node_cache[node_path] = in_stage
			return in_stage
	var found := _find_by_name(stage, node_path)
	if found != null:
		_node_cache[node_path] = found
		return found
	var ui := _get_stage_ui()
	if ui != null:
		var in_ui := ui.get_node_or_null(NodePath(node_path))
		if in_ui != null:
			_node_cache[node_path] = in_ui
			return in_ui
	return null

const MAX_FIND_DEPTH := 20

func _find_by_name(node: Node, node_name: String, depth: int = 0) -> Node:
	if depth > MAX_FIND_DEPTH:
		return null
	for c in node.get_children():
		if c.name == node_name:
			return c
		var r := _find_by_name(c, node_name, depth + 1)
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
		var node := value as Node
		return node if is_instance_valid(node) else null
	return _get_target_node(str(value))

func forget_node(node: Node) -> void:
	for key in variables.keys():
		var v = variables[key]
		if v is Node:
			if not is_instance_valid(v) or v == node:
				variables[key] = null

func _name_from_value(value: Variant) -> String:
	if value is Node:
		return (value as Node).name
	return str(value)

func _resolve_value(value: Variant, payload: Dictionary) -> Variant:
	if value is String:
		var text := str(value)
		if _is_full_ref(text, "$var."):
			return variables.get(text.substr(5), null)
		if _is_full_ref(text, "$payload."):
			return payload.get(text.substr(9), null)
		if _is_full_ref(text, "$param."):
			if _param_stack.is_empty():
				return null
			return (_param_stack.back() as Dictionary).get(text.substr(7), null)
		var has_ref := text.contains("$var.") or text.contains("$payload.") or text.contains("$param.")
		var is_expr := text.begins_with("=") or text.contains("(") or (has_ref and _has_operators(text))
		if is_expr:
			var expr := text.substr(1) if text.begins_with("=") else text
			var out: Array = []
			var params := {}
			if not _param_stack.is_empty():
				params = _param_stack.back()
			if GyroExpression.try_eval(expr, variables, payload, _expr_extra_cb, out, params):
				return out[0]
		if has_ref:
			return _interpolate(text, payload)
		return text
	return value

static func _is_full_ref(text: String, prefix: String) -> bool:
	if not text.begins_with(prefix):
		return false
	var rest := text.substr(prefix.length())
	if rest.is_empty():
		return false
	for i in rest.length():
		var c := rest[i]
		var ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_"
		if not ok:
			return false
	return true

static func _has_operators(text: String) -> bool:
	for ch in ["+", "-", "*", "/", "%", ">", "<", "=", "!", "&", "|"]:
		if text.contains(ch):
			return true
	return false

func _interpolate(text: String, payload: Dictionary) -> String:
	if not (text.contains("$var.") or text.contains("$payload.")):
		return text
	var result := text
	if _interpolate_regex == null:
		_interpolate_regex = RegEx.new()
		_interpolate_regex.compile("\\$(var|payload)\\.([a-zA-Z0-9_]+)")
	var matches := _interpolate_regex.search_all(text)
	var replacements := {}
	for m in matches:
		var full := m.get_string(0)
		var prefix := m.get_string(1)
		var var_name := m.get_string(2)
		if prefix == "var":
			if variables.has(var_name):
				replacements[full] = str(variables[var_name])
		elif prefix == "payload":
			if payload.has(var_name):
				replacements[full] = str(payload[var_name])
	var keys := replacements.keys()
	keys.sort_custom(func(a, b): return a.length() > b.length())
	for k in keys:
		result = result.replace(k, replacements[k])
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

func _expr_extra(name: String, args: Array) -> Variant:
	var gh := host as GyroEventHost
	match name:
		"screen_w", "screen_x":
			if gh != null:
				return gh.get_viewport_rect().size.x
			return 0.0
		"screen_h", "screen_y":
			if gh != null:
				return gh.get_viewport_rect().size.y
			return 0.0
		"design_w":
			if gh != null:
				return gh.design_size.x
			return 0.0
		"design_h":
			if gh != null:
				return gh.design_size.y
			return 0.0
		"offset_x":
			if gh != null:
				return -gh.stage_shift().x
			return 0.0
		"offset_y":
			if gh != null:
				return -gh.stage_shift().y
			return 0.0
		"center_x":
			if gh != null:
				return gh.get_viewport_rect().size.x * 0.5 - gh.stage_shift().x
			return 0.0
		"center_y":
			if gh != null:
				return gh.get_viewport_rect().size.y * 0.5 - gh.stage_shift().y
			return 0.0
		"pointer_x":
			if gh != null:
				return gh.screen_to_design(gh.last_pointer).x
			return 0.0
		"pointer_y":
			if gh != null:
				return gh.screen_to_design(gh.last_pointer).y
			return 0.0
		"time":
			return (Time.get_ticks_msec() - _start_time_ms) / 1000.0
		"now":
			return Time.get_unix_time_from_system()
		"obj_x", "obj_y", "obj_w", "obj_h", "obj_rot", "dist", "angle_to", "exists", "vel_x", "vel_y":
			return _expr_object_fn(name, args)
	return null


func _expr_object_fn(name: String, args: Array) -> Variant:
	if args.size() < 1:
		return null
	if name == "exists":
		return _get_target_node(str(args[0])) != null
	var node := _get_target_node(str(args[0])) as Node2D
	if node == null:
		return null
	match name:
		"obj_x":
			return node.position.x
		"obj_y":
			return node.position.y
		"obj_rot":
			return rad_to_deg(node.rotation)
		"obj_w", "obj_h":
			if object_system == null:
				return 0.0
			var r := object_system.get_aabb(node)
			return r.size.x if name == "obj_w" else r.size.y
		"vel_x", "vel_y":
			var body := node.get_node_or_null(NodePath("PhysicsBody"))
			if body is RigidBody2D:
				var lv: Vector2 = (body as RigidBody2D).linear_velocity
				return lv.x if name == "vel_x" else lv.y
			return 0.0
		"dist", "angle_to":
			if args.size() < 2:
				return null
			var other := _get_target_node(str(args[1])) as Node2D
			if other == null:
				return null
			var d: Vector2 = other.position - node.position
			return d.length() if name == "dist" else rad_to_deg(d.angle())
	return null

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

func _load_font_ref(font_ref: String) -> Font:
	var stored_path := font_ref
	var project := _get_project()
	if project != null:
		for v in project.assets:
			var a := v as GyroAsset
			if a != null and a.kind == "font" and (a.id == font_ref or a.asset_name == font_ref):
				stored_path = a.path
				break
	var resolved := GyroAssetPaths.resolve_asset_path(stored_path, _project_path())
	if resolved == "":
		return null
	if ResourceLoader.exists(resolved):
		var loaded := load(resolved)
		if loaded is Font:
			return loaded
	if FileAccess.file_exists(resolved):
		var ff := FontFile.new()
		if ff.load_dynamic_font(resolved) == OK:
			return ff
	return null

func _debug(text: String) -> void:
	if print_handler.is_valid():
		print_handler.call(text)
	else:
		print(text)

func shutdown() -> void:
	_shutdown = true
	for sv in _sequences.duplicate():
		var seq := sv as GyroSequence
		if seq != null:
			seq.cancel()
	_sequences.clear()
	_blocking_cache.clear()
	_blocking_custom.clear()
	for system in [event_system, object_system, physics_system, audio_system,
		camera_system, tween_system, timer_system, tag_system,
		variable_system, widget_system, io_system, ui_system, particle_system]:
		if system != null:
			system.cleanup()
