class_name CameraSystem
extends GyroSystem

var camera_2d: Camera2D
var camera_follow := ""
var camera_smooth := 5.0
var parallax := {}
var _manual_pos := Vector2.ZERO
var _has_manual := false

func setup() -> void:
	if host == null:
		return
	if camera_2d == null:
		camera_2d = Camera2D.new()
		camera_2d.name = "GyroCamera"
		camera_2d.position_smoothing_enabled = false
		host.add_child(camera_2d)

func step(delta: float) -> void:
	if camera_2d == null:
		return
	if camera_follow != "":
		var target := runtime._get_target_node(camera_follow) as Node2D
		if target != null:
			var desired := target.position
			camera_2d.position = camera_2d.position.lerp(desired, clampf(camera_smooth * delta, 0.0, 1.0))
	elif _has_manual:
		camera_2d.position = camera_2d.position.lerp(_manual_pos, clampf(camera_smooth * delta, 0.0, 1.0))
	for key in parallax.keys():
		var layer := runtime._get_target_node(str(key)) as Node2D
		if layer != null:
			var f: Vector2 = parallax[key]
			layer.position = camera_2d.position * (Vector2.ONE - f)

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
