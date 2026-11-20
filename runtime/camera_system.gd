class_name CameraSystem
extends GyroSystem
var camera_follow := ""
var camera_smooth := 5.0
var parallax := {}
var _manual_pos := Vector2.ZERO
var _has_manual := false
var _design := Vector2.ZERO

func setup() -> void:
	if host != null:
		_design = host.design_size * 0.5

func step(delta: float) -> void:
	if host == null:
		return
	var stage := runtime._get_stage()
	if stage == null:
		return
	var center := host.design_size * 0.5
	var desired := center
	var active := false
	if camera_follow != "":
		var target := runtime._get_target_node(camera_follow) as Node2D
		if target != null:
			desired = target.position
			active = true
	elif _has_manual:
		desired = _manual_pos
		active = true
	_design = _design.lerp(desired, clampf(camera_smooth * delta, 0.0, 1.0))
	stage.position = host.world_offset + (center - _design)
	for key in parallax.keys():
		var layer := runtime._get_target_node(str(key)) as Node2D
		if layer != null:
			var f: Vector2 = parallax[key]
			layer.position = (_design - center) * (Vector2.ONE - f)
			
func execute(action: GyroAction, payload: Dictionary) -> void:
	match action.type:
		"SetCameraPosition":
			camera_follow = ""
			_has_manual = true
			_manual_pos = Vector2(
				runtime._to_float(runtime._resolve_value(action.data.get("x", 0), payload)),
				runtime._to_float(runtime._resolve_value(action.data.get("y", 0), payload))
			)
		"CameraFollow":
			camera_follow = str(runtime._resolve_value(action.data.get("node", ""), payload))
			camera_smooth = runtime._to_float(runtime._resolve_value(action.data.get("smooth", 5), payload))
			_has_manual = false
		"SetParallax":
			var object_name := runtime._name_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
			if object_name == "":
				return
			parallax[object_name] = Vector2(
				clampf(runtime._to_float(runtime._resolve_value(action.data.get("x", 100), payload)), 0.0, 100.0) / 100.0,
				clampf(runtime._to_float(runtime._resolve_value(action.data.get("y", 100), payload)), 0.0, 100.0) / 100.0
			)
