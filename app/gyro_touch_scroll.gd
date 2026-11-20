class_name GyroTouchScroll
extends Node

var scroll: ScrollContainer
var block_nodes: Array = []
var gate: Callable
var active := false
var last_y := 0.0
var last_x := 0.0
var horizontal := false
var dragged := false
var _drag_dist := 0.0
var _acc := 0.0

const DRAG_THRESHOLD := 24.0

func setup(target: ScrollContainer, blocks: Array = []) -> void:
	scroll = target
	block_nodes = blocks

func _current_friction() -> float:
	var settings := GyroAppSettings.load_settings()
	return settings.scroll_friction if settings != null else 1.0

func _input(event: InputEvent) -> void:
	if scroll == null or not scroll.is_visible_in_tree():
		active = false
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null and focus_owner is LineEdit:
		return
	var friction := _current_friction()
	if event is InputEventScreenTouch:
		if event.pressed:
			active = _allowed() and scroll.get_global_rect().has_point(event.position) and not _blocked(event.position)
			last_y = event.position.y
			last_x = event.position.x
			dragged = false
			_drag_dist = 0.0
			_acc = 0.0
		else:
			active = false
	elif event is InputEventScreenDrag:
		if active and _allowed():
			if horizontal:
				var dx = event.position.x - last_x
				last_x = event.position.x
				_drag_dist += absf(dx)
				if _drag_dist < DRAG_THRESHOLD:
					return
				dragged = true
				_acc -= dx * friction
				var step := int(_acc)
				if step != 0:
					scroll.scroll_horizontal += step
					_acc -= step
			else:
				var delta = event.position.y - last_y
				last_y = event.position.y
				_drag_dist += absf(delta)
				if _drag_dist < DRAG_THRESHOLD:
					return
				dragged = true
				_acc -= delta * friction
				var step := int(_acc)
				if step != 0:
					scroll.scroll_vertical += step
					_acc -= step

func _allowed() -> bool:
	if scroll != null and scroll.get_meta("gyro_layout_blocked", false):
		return false
	if gate.is_valid():
		return bool(gate.call())
	return true

func _blocked(pos: Vector2) -> bool:
	for node in block_nodes:
		var c := node as Control
		if c != null and c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			return true
	return false
