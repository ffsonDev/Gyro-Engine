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

const DRAG_THRESHOLD := 24.0

func setup(target: ScrollContainer, blocks: Array = []) -> void:
	scroll = target
	block_nodes = blocks

func _input(event: InputEvent) -> void:
	if scroll == null or not scroll.is_visible_in_tree():
		active = false
		return
	var friction := 1.0
	var settings := GyroAppSettings.load_settings()
	if settings != null:
		friction = settings.scroll_friction
	if event is InputEventScreenTouch:
		if event.pressed:
			active = _allowed() and scroll.get_global_rect().has_point(event.position) and not _blocked(event.position)
			last_y = event.position.y
			last_x = event.position.x
			dragged = false
			_drag_dist = 0.0
		else:
			active = false
	elif event is InputEventScreenDrag:
		if active and _allowed():
			if horizontal:
				var dx = event.position.x - last_x
				last_x = event.position.x
				_drag_dist += absf(dx)
				scroll.scroll_horizontal = int(scroll.scroll_horizontal - dx * friction)
			else:
				var delta = event.position.y - last_y
				last_y = event.position.y
				_drag_dist += absf(delta)
				scroll.scroll_vertical = int(scroll.scroll_vertical - delta * friction)
			if _drag_dist > DRAG_THRESHOLD:
				dragged = true

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
