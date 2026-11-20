class_name TweenSystem
extends GyroSystem

var tweens := {}

func execute(action: GyroAction, payload: Dictionary) -> void:
	match action.type:
		"TweenPosition":
			_action_tween(action, payload, "position")
		"TweenScale":
			_action_tween(action, payload, "scale")
		"TweenRotation":
			_action_tween(action, payload, "rotation")
		"TweenOpacity":
			_action_tween(action, payload, "opacity")
		"StopTween":
			_action_stop_tween(action, payload)

func _action_tween(action: GyroAction, payload: Dictionary, kind: String) -> void:
	var target := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if target == null:
		return
	if host == null or not host.is_inside_tree():
		return
	_stop_tween_for(target.name)
	var time := maxf(0.05, runtime._to_float(runtime._resolve_value(action.data.get("time", 1.0), payload)))
	var tw := host.create_tween()
	match str(action.data.get("ease", "linear")):
		"in":
			tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		"out":
			tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	match kind:
		"position":
			tw.tween_property(target, "position", Vector2(
				runtime._to_float(runtime._resolve_value(action.data.get("x", 0), payload)),
				runtime._to_float(runtime._resolve_value(action.data.get("y", 0), payload))
			), time)
		"scale":
			var from_p: float = 100.0
			if target is Control:
				from_p = (target as Control).scale.x * 100.0
			elif target is Node2D:
				from_p = (target as Node2D).scale.x * 100.0
			var to_p: float = runtime._to_float(runtime._resolve_value(action.data.get("percent", 100), payload))
			tw.tween_method(_apply_scale_percent.bind(target), from_p, to_p, time)
		"rotation":
			var from_a: float = rad_to_deg((target as CanvasItem).rotation)
			var to_a: float = runtime._to_float(runtime._resolve_value(action.data.get("angle", 0), payload))
			tw.tween_method(_apply_rotation_deg.bind(target), from_a, to_a, time)
		"opacity":
			tw.tween_property(target, "modulate:a", clampf(runtime._to_float(runtime._resolve_value(action.data.get("value", 100), payload)), 0.0, 100.0) / 100.0, time)
	tweens[target.name] = tw

func _stop_tween_for(object_name: String) -> void:
	var tw = tweens.get(object_name, null)
	if tw != null and is_instance_valid(tw):
		(tw as Tween).kill()
	tweens.erase(object_name)

func _action_stop_tween(action: GyroAction, payload: Dictionary) -> void:
	var object_name := runtime._name_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if object_name == "":
		for key in tweens.keys():
			_stop_tween_for(str(key))
	else:
		_stop_tween_for(object_name)

func on_object_deleted(object_name: String) -> void:
	_stop_tween_for(object_name)

func _apply_scale_percent(percent: float, target: Node) -> void:
	var p := percent / 100.0
	if target is Control:
		(target as Control).scale = Vector2(p, p)
		return
	var root := target as Node2D
	if root == null:
		return
	var piv := ObjectUtils.get_pivot(root)
	var pivot_global: Vector2 = root.to_global(piv)
	root.scale = Vector2(p, p)
	var offset: Vector2 = root.to_global(piv) - root.global_position
	root.global_position = pivot_global - offset

func _apply_rotation_deg(deg: float, target: Node) -> void:
	if target is Control:
		(target as Control).rotation = deg_to_rad(deg)
		return
	var root := target as Node2D
	if root == null:
		return
	var piv := ObjectUtils.get_pivot(root)
	var pivot_global: Vector2 = root.to_global(piv)
	root.rotation = deg_to_rad(deg)
	var offset: Vector2 = root.to_global(piv) - root.global_position
	root.global_position = pivot_global - offset
