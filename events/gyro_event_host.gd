class_name GyroEventHost
extends Control

@export var blueprint: GyroEventBlueprint
@export var blueprint_path := ""
@export var emit_ready_event := true
@export var emit_input_events := true
@export var emit_tap_events := true
@export var timer_configs: Array[GyroTimerConfig] = []
@export var emit_update_events := true

var runtime := GyroEventRuntime.new()
var project: GyroProject
var project_path := ""
var _last_touch_name := ""
var _app_paused := false

var _stage_ui: Control

var _stage: Node2D

var physics_process_callback := true
const DESIGN_SIZE := Vector2(480, 720)
var world_offset := Vector2.ZERO
var _anchors := {}
var _anchor_offsets := {}
var _last_vp_size := Vector2.ZERO
var _layout_active := false

static func anchor_point(size: Vector2, anchor: String) -> Vector2:
	var hx := 0.5
	var hy := 0.5
	match anchor:
		"tl": hx = 0; hy = 0
		"tc": hx = 0.5; hy = 0
		"tr": hx = 1; hy = 0
		"ml": hx = 0; hy = 0.5
		"c":  hx = 0.5; hy = 0.5
		"mr": hx = 1; hy = 0.5
		"bl": hx = 0; hy = 1
		"bc": hx = 0.5; hy = 1
		"br": hx = 1; hy = 1
		_: return size * 0.5
	return Vector2(size.x * hx, size.y * hy)

func register_anchor(obj_name: String, anchor: String) -> void:
	if anchor == "" or anchor == "free":
		_anchors.erase(obj_name)
		_anchor_offsets.erase(obj_name)
	else:
		_anchors[obj_name] = anchor

func unregister_anchor(obj_name: String) -> void:
	_anchors.erase(obj_name)
	_anchor_offsets.erase(obj_name)

func set_anchor_offset(obj_name: String, offset: Vector2) -> void:
	if _anchors.has(obj_name):
		_anchor_offsets[obj_name] = offset

func anchor_point_local(size: Vector2, anchor: String) -> Vector2:
	return anchor_point(size, anchor) - world_offset

func _reapply_anchors(size: Vector2) -> void:
	for name in _anchors.keys():
		var node := get_node_or_null(NodePath("Stage/" + str(name)))
		if node == null:
			node = get_node_or_null(NodePath("StageUI/" + str(name)))
		if node == null:
			continue
		node.position = anchor_point_local(size, _anchors[name]) + _anchor_offsets.get(name, Vector2.ZERO)

func set_layout_mode(on: bool) -> void:
	_layout_active = on
	get_tree().paused = on

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if project_path == "" and project != null:
		project_path = project.resource_path

	_load_blueprint()

	runtime.host = self
	if blueprint == null:
		blueprint = GyroEventBlueprint.new()
	runtime.setup(blueprint)

	emit_update_events = runtime.has_event("update")
	emit_input_events = runtime.has_event("input") or runtime.has_event("tap")

	_setup_timers()

	var bg := ColorRect.new()
	bg.name = "GyroBackground"
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_stage = Node2D.new()
	_stage.name = "Stage"
	add_child(_stage)

	_stage_ui = Control.new()
	_stage_ui.name = "StageUI"
	_stage_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage_ui.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_stage_ui)
	
	_update_layout()

	if emit_ready_event:
		emit_event("ready", {})

	var camera := Camera2D.new()
	camera.name = "GameCamera"
	camera.zoom = Vector2(1, 1)
	_stage.add_child(camera)
	camera.make_current()
	
	var logger := GyroLogger.get_instance()
	logger.enable()
	logger.log_info("Project started: " + project.settings.app_name)


	if not get_viewport().size_changed.is_connected(_update_layout):
		get_viewport().size_changed.connect(_update_layout)

	_last_vp_size = get_viewport_rect().size
	camera.position = _last_vp_size * 0.5
	
	_update_layout()
	
	_update_layout.call_deferred()

	get_viewport().size_changed.connect(_on_vp_size_changed)

func emit_event(type: String, payload: Dictionary) -> void:
	var logger := GyroLogger.get_instance()
	logger.log_debug("Event: " + type)
	runtime.emit_event(type, payload)

func _exit_tree() -> void:
	var logger := GyroLogger.get_instance()
	logger.disable()
	runtime.host = null

func _on_vp_size_changed() -> void:
	var new_size := get_viewport_rect().size
	if _last_vp_size == new_size:
		return
	_last_vp_size = new_size
	_reapply_anchors(new_size)

func refresh_layout() -> void:
	_update_layout()

func _update_layout() -> void:
	var vs := get_viewport_rect().size

	position = Vector2.ZERO
	size = vs

	var bg := get_node_or_null(NodePath("GyroBackground")) as ColorRect
	if bg != null:
		bg.position = Vector2.ZERO
		bg.size = vs

	world_offset = (vs - DESIGN_SIZE) * 0.5
	if _stage != null:
		_stage.position = world_offset
		var cam := _stage.get_node_or_null(NodePath("GameCamera")) as Camera2D
		if cam != null:
			cam.position = DESIGN_SIZE * 0.5
	if _stage_ui != null:
		_stage_ui.position = world_offset
		_stage_ui.size = vs

func screen_to_design(pos: Vector2) -> Vector2:
	return pos - world_offset


func _process(delta: float) -> void:
	if _app_paused:
		_app_paused = false
		emit_event("app_resumed", {})
	runtime.step_physics(delta)
	if emit_update_events:
		emit_event("update", {"delta": delta})

func _physics_process(_delta: float) -> void:
	pass

func _input(event: InputEvent) -> void:
	if get_meta("gyro_layout_active", false):
		return
	if event is InputEventKey:
		if emit_input_events:
			_emit_input_event(event)
		return
	if event is InputEventScreenDrag:
		runtime.move_grab(screen_to_design(event.position))
		if runtime.has_event("drag"):
			var dpos := screen_to_design(event.position)
			emit_event("drag", {"x": dpos.x, "y": dpos.y, "dx": event.relative.x, "dy": event.relative.y})
		return
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		var pressed := false
		var pos := Vector2.ZERO
		if event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			pressed = touch.pressed
			pos = touch.position
		else:
			var mouse := event as InputEventMouseButton
			if mouse.button_index != MOUSE_BUTTON_LEFT:
				return
			pressed = mouse.pressed
			pos = mouse.position
		if not pressed:
			runtime.release_grab()
			if _last_touch_name != "":
				var dpos := screen_to_design(pos)
				emit_event("obj_touch_end", {"node": _last_touch_name, "x": dpos.x, "y": dpos.y})
				_last_touch_name = ""
			return
		if _is_ui_click(pos):
			return
		if runtime.try_grab(pos):
			return
		if runtime.has_event("obj_touch_begin"):
			var touched := _top_object_at(pos)
			if touched != "":
				_last_touch_name = touched
				var dpos := screen_to_design(pos)
				emit_event("obj_touch_begin", {"node": touched, "x": dpos.x, "y": dpos.y})
		if emit_input_events:
			_emit_input_event(event)
		if emit_tap_events:
			_emit_tap_event(event)

func _is_ui_click(pos: Vector2) -> bool:
	if _stage_ui == null:
		return false
	for child in _stage_ui.get_children():
		if child is Control:
			var control := child as Control
			if control.visible and control.get_global_rect().has_point(pos):
				return true
	return false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_app_paused = true
		emit_event("app_paused", {})

func _top_object_at(pos: Vector2) -> String:
	if _stage == null:
		return ""
	var best_z := -9999
	var best_name := ""
	for child in _stage.get_children():
		if child is Node2D and child.name != "GameCamera" and child.visible:
			var node := child as Node2D
			var aabb := runtime.object_system._get_aabb(node)
			if aabb.has_point(pos):
				if node.z_index >= best_z:
					best_z = node.z_index
					best_name = node.name
	return best_name

func add_timer(timer_name: String, wait_time: float, one_shot: bool, autostart: bool) -> void:
	if timer_name == "":
		return
	var timer := Timer.new()
	timer.wait_time = wait_time
	timer.one_shot = one_shot
	timer.set_meta("gyro_timer_name", timer_name)
	timer.timeout.connect(_on_timer_timeout.bind(timer_name))
	add_child(timer)
	if autostart:
		timer.start()

func start_timer(timer_name: String, wait_time: float, one_shot: bool) -> void:
	stop_timer(timer_name)
	add_timer(timer_name, wait_time, one_shot, true)

func stop_timer(timer_name: String) -> void:
	for child in get_children():
		var timer := child as Timer
		if timer != null and timer.has_meta("gyro_timer_name") and str(timer.get_meta("gyro_timer_name")) == timer_name:
			timer.stop()
			timer.queue_free()

func _load_blueprint() -> void:
	if blueprint_path == "":
		return
	if not ResourceLoader.exists(blueprint_path):
		return
	var loaded := ResourceLoader.load(blueprint_path)
	if loaded is GyroEventBlueprint:
		blueprint = loaded

func _setup_timers() -> void:
	for config_value in timer_configs:
		var config := config_value as GyroTimerConfig
		if config == null:
			continue
		add_timer(config.timer_name, config.wait_time, config.one_shot, config.autostart)
	if blueprint != null:
		for config_value in blueprint.timers:
			var config := config_value as GyroTimerConfig
			if config == null:
				continue
			add_timer(config.timer_name, config.wait_time, config.one_shot, config.autostart)

func _on_timer_timeout(timer_name: String) -> void:
	runtime.on_timer_fired(timer_name)
	emit_event("timer", {"name": timer_name})

func _emit_input_event(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed:
			emit_event("input", {"type": "key", "keycode": key.keycode, "unicode": key.unicode, "text": key.as_text()})
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed:
			var dpos := screen_to_design(mouse.position)
			emit_event("input", {"type": "mouse_button", "button": mouse.button_index, "x": dpos.x, "y": dpos.y})
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			var dpos := screen_to_design(touch.position)
			emit_event("input", {"type": "touch", "x": dpos.x, "y": dpos.y})


func _emit_tap_event(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			var dpos := screen_to_design(touch.position)
			emit_event("tap", {"x": dpos.x, "y": dpos.y})
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			var dpos := screen_to_design(mouse.position)
			emit_event("tap", {"x": dpos.x, "y": dpos.y})

func get_stage() -> Node2D:
	return _stage

func get_stage_ui() -> Control:
	return _stage_ui
