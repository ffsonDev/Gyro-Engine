class_name DragDropController
extends RefCounted

signal drop_applied(drop: Dictionary)

var dragging := false
var drag_kind := ""
var drag_resource: Variant
var drag_rule: GyroEventRule
var drag_panel: Control
var pointer := Vector2()
var current_drop := {}
var drag_items: Array = []
var rule_wrappers := {}
var scroll: ScrollContainer
var drop_indicator: Control

var _autoscroll_acc := 0.0
var _vibrate: Callable
var _get_array_for: Callable

var _cached_rects := {}
var _rects_dirty := true
var _get_alpha_fn: Callable
var _drag_orig_alpha := 1.0

const AUTOSCROLL_ZONE := 80.0
const AUTOSCROLL_SPEED := 900.0

func setup(scroll_node: ScrollContainer, indicator: Control, vibrate_fn: Callable, get_array_fn: Callable, get_alpha_fn: Callable = Callable()) -> void:
	scroll = scroll_node
	drop_indicator = indicator
	_vibrate = vibrate_fn
	_get_array_for = get_array_fn
	_get_alpha_fn = get_alpha_fn
	if scroll != null:
		scroll.get_v_scroll_bar().value_changed.connect(_on_scroll_changed)
		scroll.get_h_scroll_bar().value_changed.connect(_on_scroll_changed)

func _on_scroll_changed(_value: float) -> void:
	_rects_dirty = true
	
func reset() -> void:
	drag_items.clear()
	rule_wrappers.clear()
	current_drop = {}
	dragging = false
	_cached_rects.clear()
	_rects_dirty = true

func register_item(item: Dictionary) -> void:
	drag_items.append(item)
	_rects_dirty = true

func register_rule(rule: GyroEventRule, panel: Control) -> void:
	rule_wrappers[rule] = panel
	_rects_dirty = true

func invalidate_rects() -> void:
	_rects_dirty = true

func start_drag(kind: String, resource: Variant, rule: GyroEventRule, panel: Control) -> void:
	dragging = true
	drag_kind = kind
	drag_resource = resource
	drag_rule = rule
	drag_panel = panel
	if panel != null:
		_drag_orig_alpha = panel.modulate.a
		panel.modulate.a = 0.5
	_autoscroll_acc = 0.0
	if _vibrate.is_valid():
		_vibrate.call(40)

func set_pointer(pos: Vector2) -> void:
	pointer = pos

func process_frame(delta: float) -> void:
	if not dragging:
		return
	_update_drop_target_throttled(delta)
	_update_autoscroll(delta)

func finish_drag() -> void:
	if not dragging:
		return
	dragging = false
	if drag_panel != null and is_instance_valid(drag_panel):
		if _get_alpha_fn.is_valid():
			drag_panel.modulate.a = _get_alpha_fn.call(drag_resource)
		else:
			drag_panel.modulate.a = _drag_orig_alpha
	if drop_indicator != null:
		drop_indicator.visible = false
	if not current_drop.is_empty():
		drop_applied.emit(current_drop)
	current_drop = {}
	drag_panel = null

func _update_autoscroll(delta: float) -> void:
	if scroll == null:
		return
	var rect := scroll.get_global_rect()
	var speed := 0.0
	if pointer.y < rect.position.y + AUTOSCROLL_ZONE:
		var t := clampf((rect.position.y + AUTOSCROLL_ZONE - pointer.y) / AUTOSCROLL_ZONE, 0.0, 1.0)
		speed = -AUTOSCROLL_SPEED * t
	elif pointer.y > rect.end.y - AUTOSCROLL_ZONE:
		var t := clampf((pointer.y - (rect.end.y - AUTOSCROLL_ZONE)) / AUTOSCROLL_ZONE, 0.0, 1.0)
		speed = AUTOSCROLL_SPEED * t
	if speed == 0.0:
		return
	_autoscroll_acc += speed * delta
	var step := int(_autoscroll_acc)
	if step != 0:
		scroll.scroll_vertical += step
		_rects_dirty = true
	_autoscroll_acc -= step

func _get_rect(control: Control) -> Rect2:
	if _rects_dirty or not _cached_rects.has(control):
		_cached_rects[control] = control.get_global_rect()
	return _cached_rects[control]

func _update_drop_target() -> void:
	current_drop = {}
	if _rects_dirty:
		_cached_rects.clear()
		_rects_dirty = false

	if drag_kind == "action":
		var best_area := -1.0
		for entry in drag_items:
			if entry.kind != "flow":
				continue
			if not is_instance_valid(entry.panel):
				continue
			var rect: Rect2 = _get_rect(entry.panel)
			if not rect.has_point(pointer):
				continue
			var area := rect.get_area()
			if best_area < 0.0 or area < best_area:
				best_area = area
				current_drop = {
					"type": "flow", "action": entry.action,
					"y": rect.end.y - 7,
					"x": rect.position.x + 6,
					"w": rect.size.x - 12,
				}

	if current_drop.is_empty():
		var py := pointer.y
		for item in drag_items:
			if item.kind != drag_kind:
				continue
			if not is_instance_valid(item.panel):
				continue
			var rect: Rect2 = _get_rect(item.panel)
			if py < rect.position.y or py > rect.end.y:
				continue
			if not rect.has_point(pointer):
				continue
			var before := pointer.y < rect.position.y + rect.size.y * 0.5
			current_drop = {
				"type": "item",
				"item": item,
				"before": before,
				"y": (rect.position.y - 6) if before else rect.end.y,
				"x": rect.position.x,
				"w": rect.size.x,
			}
			break

	if current_drop.is_empty() and drag_kind != "rule":
		for rule_key in rule_wrappers.keys():
			var panel = rule_wrappers[rule_key]
			if not is_instance_valid(panel):
				continue
			var rect: Rect2 = _get_rect(panel)
			if rect.has_point(pointer):
				var is_empty := true
				if drag_kind == "action":
					is_empty = rule_key.actions.is_empty()
				elif drag_kind == "condition":
					is_empty = rule_key.conditions.is_empty()
				if is_empty:
					current_drop = {
						"type": "rule", "rule": rule_key,
						"y": rect.end.y - 11,
						"x": rect.position.x + 10,
						"w": rect.size.x - 20,
					}
				else:
					current_drop = {
						"type": "rule", "rule": rule_key,
						"y": rect.end.y + 2,
						"x": rect.position.x + 10,
						"w": rect.size.x - 20,
					}
				break
	_place_indicator()


func _place_indicator() -> void:
	if drop_indicator == null or not is_instance_valid(drop_indicator):
		return
	if current_drop.is_empty() or scroll == null or not is_instance_valid(scroll):
		drop_indicator.visible = false
		return
	var scroll_rect := scroll.get_global_rect()
	var y := clampf(float(current_drop.get("y", 0.0)), scroll_rect.position.y + 2.0, scroll_rect.end.y - 8.0)
	var x := float(current_drop.get("x", scroll_rect.position.x + 16.0))
	var w := float(current_drop.get("w", scroll_rect.size.x - 32.0))
	drop_indicator.visible = true
	drop_indicator.global_position = Vector2(x, y)
	drop_indicator.size = Vector2(w, 6.0)
	
var _last_drop_update := 0.0

func _update_drop_target_throttled(delta: float) -> void:
	_last_drop_update += delta
	var threshold := 0.016 if _autoscroll_acc != 0.0 else 0.03
	if _last_drop_update >= threshold:
		_update_drop_target()
		_last_drop_update = 0.0
