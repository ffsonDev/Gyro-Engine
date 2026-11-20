class_name ObjectAnimation
extends RefCounted

var runtime: GyroEventRuntime

func _init(rt: GyroEventRuntime) -> void:
	runtime = rt

func _resolve_target(target: Node) -> Node:
	if target is AnimatedSprite2D or target is AnimationPlayer:
		return target
	for child in target.get_children():
		if child is AnimatedSprite2D or child is AnimationPlayer:
			return child
	return target

func execute_play_animation(action: GyroAction, payload: Dictionary) -> void:
	var raw := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if raw == null:
		return
	var animation := str(runtime._resolve_value(action.data.get("animation", ""), payload))
	if animation == "":
		return
	var target := _resolve_target(raw)
	if target is AnimationPlayer:
		var player := target as AnimationPlayer
		if player.has_animation(animation):
			player.play(animation)
	elif target is AnimatedSprite2D:
		var sprite := target as AnimatedSprite2D
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(animation):
			sprite.play(animation)
	elif target.has_method("play"):
		target.call("play", animation)

func execute_stop_animation(action: GyroAction, payload: Dictionary) -> void:
	var raw := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if raw == null:
		return
	var target := _resolve_target(raw)
	if target is AnimatedSprite2D:
		(target as AnimatedSprite2D).stop()
	elif target is AnimationPlayer:
		(target as AnimationPlayer).stop()

func execute_set_frame(action: GyroAction, payload: Dictionary) -> void:
	var raw := runtime._node_from_value(runtime._resolve_value(action.data.get("node", ""), payload))
	if raw == null:
		return
	var target := _resolve_target(raw)
	if target is AnimatedSprite2D:
		(target as AnimatedSprite2D).frame = int(runtime._to_float(runtime._resolve_value(action.data.get("frame", 0), payload)))
