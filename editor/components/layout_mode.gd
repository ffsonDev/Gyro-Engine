class_name LayoutMode
extends Node

var host: GyroEventHost
var active := false
var overlay: Control
var toolbar: HBoxContainer
var bars: Array = []
var frame: Array = []
var guide_v: ColorRect
var guide_h: ColorRect
var badge: Label
var dots_root: Control
var sel_edges: Array = []
var selected: Node = null
var sel_name := ""
var _dragging := false
var _drag_last := Vector2()
var _drag_off := Vector2()
var layout_rect := Rect2()
var _dots: Array = []
signal object_moved(obj_name: String, pos: Vector2)

const SNAP := 24.0

func setup(h: GyroEventHost) -> void:
	host = h
	process_mode = Node.PROCESS_MODE_ALWAYS
	build_toolbar()

func build_toolbar() -> void:
	if is_instance_valid(toolbar):
		return  # уже создан
	
	toolbar = HBoxContainer.new()
	toolbar.name = "LayoutToolbar"
	toolbar.add_theme_constant_override("separation", 4)
	toolbar.z_index = 250
	toolbar.visible = true
	toolbar.custom_minimum_size = Vector2(192, 40)
	host.add_child(toolbar)

	var layout_btn := GyroUI.icon_button("res://ui/icons/layout.svg", GyroUI.fs(24), 8)
	layout_btn.pressed.connect(toggle)
	toolbar.add_child(layout_btn)
	
	_place_toolbar()

func _build_overlay() -> void:
	if is_instance_valid(overlay):
		overlay.queue_free()
		overlay = null
	
	overlay = Control.new()
	overlay.name = "LayoutOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	overlay.z_index = 200
	host.add_child(overlay)
	
	for i in 4:
		var b := ColorRect.new()
		b.color = Color(0, 0, 0, 0.55)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.visible = false
		overlay.add_child(b)
		bars.append(b)
	
	for i in 4:
		var f := ColorRect.new()
		f.color = Color(0.2, 0.8, 0.9, 1)
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		f.visible = false
		overlay.add_child(f)
		frame.append(f)
	
	guide_v = _mk_line()
	guide_h = _mk_line()
	badge = Label.new()
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", Color(1, 0.7, 0.3))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	overlay.add_child(badge)
	
	for i in 4:
		var e := ColorRect.new()
		e.color = Color(1, 0.8, 0.2, 1)
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		e.visible = false
		overlay.add_child(e)
		sel_edges.append(e)
	
	dots_root = Control.new()
	dots_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dots_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dots_root)

func _place_toolbar() -> void:
	if not is_instance_valid(toolbar):
		return
	toolbar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	toolbar.offset_left = -110
	toolbar.offset_right = -110
	toolbar.offset_top = 8
	toolbar.offset_bottom = 64
	toolbar.size_flags_horizontal = Control.SIZE_SHRINK_END
	toolbar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

func _mk_line() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.2, 0.8, 0.9, 0.8)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.visible = false
	overlay.add_child(c)
	return c

func toggle() -> void:
	if active:
		exit()
	else:
		enter()
		
func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null and focus_owner is LineEdit:
		return
	
	var pressed := false
	var released := false
	var pos := Vector2.ZERO
	
	if event is InputEventScreenTouch:
		pressed = event.pressed
		released = not event.pressed
		pos = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = event.pressed
		released = not event.pressed
		pos = event.position
	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and _dragging):
		if _dragging and selected != null:
			_move_to(event.position)
			get_viewport().set_input_as_handled()
		return
	else:
		return
	
	if pressed:
		if _over_own_ui(pos):
			return
		var node := _pick_node(pos)
		_select(node)
		_dragging = node != null
		if _dragging:
			_drag_off = pos - selected.global_position
		get_viewport().set_input_as_handled()
	elif released:
		_dragging = false

func _over_own_ui(pos: Vector2) -> bool:
	if host != null:
		for child in host.get_children():
			if child is Button and child.name == "TestStopButton":
				if child.visible and child.get_global_rect().has_point(pos):
					return true
	
	if toolbar != null and is_instance_valid(toolbar) and toolbar.get_global_rect().has_point(pos):
		return true
		
	for d in _dots:
		if d != null and is_instance_valid(d) and d.visible and d.get_global_rect().has_point(pos):
			return true
			
	return false

func enter() -> void:
	if active:
		return
	active = true
	get_tree().paused = true
	host.set_meta("gyro_layout_active", true)
	host.set_layout_mode(true)
	_build_overlay()
	overlay.visible = true
	
	for child in host.get_children():
		if child is Button and child.name == "TestStopButton":
			host.move_child(child, host.get_child_count() - 1)
			break
	
	layout_rect = Rect2(Vector2.ZERO, host.get_viewport_rect().size)
	
	_update_bars()
	_select(null)
	for child in host.get_children():
		if child is GyroTouchScroll:
			child.set_meta("gyro_layout_blocked", true)

func exit() -> void:
	if not active:
		return
	active = false
	get_tree().paused = false
	host.set_meta("gyro_layout_active", false)
	host.set_layout_mode(false)
	_select(null)
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()
		overlay = null
	_dots.clear()
	for child in host.get_children():
		if child is GyroTouchScroll:
			child.set_meta("gyro_layout_blocked", false)

func cleanup() -> void:
	if active:
		exit()
	if is_instance_valid(toolbar):
		toolbar.queue_free()
		toolbar = null


func _move_to(pos: Vector2) -> void:
	if selected == null:
		return
	selected.position = pos - _drag_off
	_apply_snap()
	_update_guides()
	_update_badge()
	object_moved.emit(selected.name, selected.position)

func _pick_node(pos: Vector2) -> Node:
	var sui := host.get_node_or_null(NodePath("StageUI")) as Control
	if sui != null:
		for i in range(sui.get_child_count() - 1, -1, -1):
			var ch := sui.get_child(i) as Control
			if ch != null and ch.visible and ch.get_global_rect().has_point(pos):
				return ch
				
	var stage := host.get_node_or_null(NodePath("Stage")) as Node2D
	if stage == null:
		return null
		
	var best: Node = null
	var best_z := -9999
	for child in stage.get_children():
		var n := child as Node2D
		if n == null or not n.visible or n.name == "GameCamera":
			continue
		var aabb := host.runtime.object_system._get_aabb(n)
		if aabb.has_point(pos) and n.z_index >= best_z:
			best_z = n.z_index
			best = n
	return best

func _select(n: Node) -> void:
	selected = n
	sel_name = str(n.name) if n != null else ""
	_build_dots()
	_update_guides()
	_update_badge()

func _apply_snap() -> void:
	if selected == null:
		return
	var bb := _sel_rect()
	var lc := layout_rect.get_center()
	var c := bb.get_center()
	
	if absf(c.x - lc.x) < SNAP:
		selected.position.x += lc.x - c.x
	if absf(c.y - lc.y) < SNAP:
		selected.position.y += lc.y - c.y
		
	bb = _sel_rect()
	if bb.position.x - layout_rect.position.x < SNAP:
		selected.position.x += layout_rect.position.x - bb.position.x
		bb = _sel_rect()
	if layout_rect.end.x - bb.end.x < SNAP:
		selected.position.x += layout_rect.end.x - bb.end.x
		bb = _sel_rect()
	if bb.position.y - layout_rect.position.y < SNAP:
		selected.position.y += layout_rect.position.y - bb.position.y
		bb = _sel_rect()
	if layout_rect.end.y - bb.end.y < SNAP:
		selected.position.y += layout_rect.end.y - bb.end.y

func _sel_rect() -> Rect2:
	if selected is Control:
		return (selected as Control).get_global_rect()
	return host.runtime.object_system._get_aabb(selected)

func _update_guides() -> void:
	if selected == null:
		for e in sel_edges:
			e.visible = false
		guide_v.visible = false
		guide_h.visible = false
		return
		
	var bb := _sel_rect()
	guide_v.visible = true
	guide_v.global_position = Vector2(layout_rect.get_center().x - 1, layout_rect.position.y)
	guide_v.size = Vector2(2, layout_rect.size.y)
	
	guide_h.visible = true
	guide_h.global_position = Vector2(layout_rect.position.x, layout_rect.get_center().y - 1)
	guide_h.size = Vector2(layout_rect.size.x, 2)
	
	sel_edges[0].visible = true
	sel_edges[0].global_position = Vector2(bb.position.x - 2, bb.position.y - 2)
	sel_edges[0].size = Vector2(bb.size.x + 4, 2)
	
	sel_edges[1].visible = true
	sel_edges[1].global_position = Vector2(bb.position.x - 2, bb.end.y)
	sel_edges[1].size = Vector2(bb.size.x + 4, 2)
	
	sel_edges[2].visible = true
	sel_edges[2].global_position = Vector2(bb.position.x - 2, bb.position.y)
	sel_edges[2].size = Vector2(2, bb.size.y)
	
	sel_edges[3].visible = true
	sel_edges[3].global_position = Vector2(bb.end.x, bb.position.y)
	sel_edges[3].size = Vector2(2, bb.size.y)

func _update_badge() -> void:
	if selected == null:
		badge.visible = false
		return
	var over := _has_position_override(sel_name)
	badge.visible = over
	if over:
		badge.text = GyroLang.t("layout_override")
		badge.global_position = Vector2(layout_rect.position.x + 8, layout_rect.position.y + 8)

func _has_position_override(nm: String) -> bool:
	if host == null or host.runtime == null or host.runtime.blueprint == null:
		return false
	for r in host.runtime.blueprint.rules:
		for a in r.actions:
			if str(a.data.get("node", "")) == nm and (a.type == "MoveNode" or a.type == "TweenPosition" or (a.type == "SetNodeProperty" and str(a.data.get("property", "")) == "position")):
				return true
	return false

func _build_dots() -> void:
	for c in dots_root.get_children():
		c.queue_free()
	_dots.clear()
	
	if selected == null:
		return
		
	for anchor in ["tl", "tc", "tr", "ml", "c", "mr", "bl", "bc", "br"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(28, 28)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.2, 0.8, 0.9, 0.95)
		st.set_corner_radius_all(14)
		b.add_theme_stylebox_override("normal", st)
		b.position = _anchor_pt(anchor) - Vector2(14, 14)
		b.pressed.connect(func(): _apply_anchor(anchor))
		dots_root.add_child(b)
		_dots.append(b)

func _anchor_pt(anchor: String) -> Vector2:
	var hx := 0.5
	var hy := 0.5
	match anchor:
		"tl": hx = 0; hy = 0
		"tc": hx = 0.5; hy = 0
		"tr": hx = 1; hy = 0
		"ml": hx = 0; hy = 0.5
		"c": hx = 0.5; hy = 0.5
		"mr": hx = 1; hy = 0.5
		"bl": hx = 0; hy = 1
		"bc": hx = 0.5; hy = 1
		"br": hx = 1; hy = 1
	return layout_rect.position + Vector2(layout_rect.size.x * hx, layout_rect.size.y * hy)

func _apply_anchor(anchor: String) -> void:
	if selected == null:
		return
	selected.set_meta("gyro_anchor", anchor)
	host.register_anchor(sel_name, anchor)
	host.set_anchor_offset(sel_name, Vector2.ZERO)
	selected.position = _anchor_pt(anchor) - host.world_offset
	_update_guides()

func _update_bars() -> void:
	for i in 4:
		if i < bars.size():
			bars[i].visible = false
		if i < frame.size():
			frame[i].visible = false
