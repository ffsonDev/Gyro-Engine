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
			var p := runtime._to_float(runtime._resolve_value(action.data.get("percent", 100), payload)) / 100.0
			tw.tween_property(target, "scale", Vector2(p, p), time)
		"rotation":
			tw.tween_property(target, "rotation", deg_to_rad(runtime._to_float(runtime._resolve_value(action.data.get("angle", 0), payload))), time)
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
