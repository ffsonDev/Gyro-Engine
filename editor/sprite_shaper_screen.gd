class_name SpriteShaperScreen
extends Control

signal back_requested
signal asset_saved(asset: GyroAsset)

var current_asset: GyroAsset
var save_path := ""
var mode := "hitbox"
var snap_enabled := false
var snap_size := 8

var selected_polygon := -1
var selected_point := -1
var dragging_point := false
var drag_offset := Vector2.ZERO

var texture: Texture2D
var texture_rect: TextureRect
var draw_canvas: Control
var zoom_level := 1.0
var pan_offset := Vector2.ZERO
var current_scale := 1.0

@onready var title_label: Label = %Title
@onready var mode_hitbox_btn: Button = %ModeHitboxBtn
@onready var mode_atlas_btn: Button = %ModeAtlasBtn
@onready var snap_check: CheckBox = %SnapCheck
@onready var add_polygon_btn: Button = %AddPolygonBtn
@onready var add_point_btn: Button = %AddPointBtn
@onready var clear_btn: Button = %ClearBtn
@onready var save_btn: Button = %SaveBtn
@onready var back_btn: Button = %BackButton
@onready var zoom_slider: HSlider = %ZoomSlider
@onready var polygon_list: VBoxContainer = %PolygonListInner

func _ready() -> void:
	title_label.add_theme_font_size_override("font_size", GyroUI.fs(28))
	title_label.add_theme_color_override("font_color", Color.WHITE)
	
	mode_hitbox_btn.pressed.connect(func(): _set_mode("hitbox"))
	mode_atlas_btn.pressed.connect(func(): _set_mode("atlas"))
	snap_check.toggled.connect(func(on): snap_enabled = on)
	add_polygon_btn.pressed.connect(_add_polygon)
	add_point_btn.pressed.connect(_add_point_to_selected)
	clear_btn.pressed.connect(_clear_all)
	save_btn.pressed.connect(_save)
	back_btn.pressed.connect(func(): back_requested.emit())
	zoom_slider.value_changed.connect(func(v): _set_zoom(v))
	
	draw_canvas = %DrawCanvas
	texture_rect = %TextureRect
	
	apply_lang()
	_update_ui_state()

func open(asset: GyroAsset, path: String) -> void:
	current_asset = asset
	save_path = path
	title_label.text = "Редактор: " + asset.asset_name
	
	texture = GyroMedia.load_texture(GyroAssetPaths.resolve_asset_path(asset.path, path))
	if texture:
		texture_rect.texture = texture
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_center_texture()
	
	_load_from_asset()
	_update_polygon_list()
	redraw()

func apply_lang() -> void:
	mode_hitbox_btn.text = "Хитбоксы"
	mode_atlas_btn.text = "Атлас"
	snap_check.text = "Сетка"
	add_polygon_btn.text = "+ Полигон"
	add_point_btn.text = "+ Точка"
	clear_btn.text = "Очистить"
	save_btn.text = "Сохранить"

func _set_mode(new_mode: String) -> void:
	mode = new_mode
	mode_hitbox_btn.flat = (mode != "hitbox")
	mode_atlas_btn.flat = (mode != "atlas")
	selected_polygon = -1
	selected_point = -1
	_update_ui_state()
	_update_polygon_list()
	redraw()

func _update_ui_state() -> void:
	var is_hitbox := (mode == "hitbox")
	add_polygon_btn.visible = is_hitbox
	add_point_btn.visible = is_hitbox
	polygon_list.visible = is_hitbox

func _center_texture() -> void:
	if texture:
		var container := %CanvasContainer as Control
		if container == null:
			return
		var available := container.size
		var tex_size := texture.get_size()
		if tex_size.x == 0 or tex_size.y == 0:
			return
		var scale_x := available.x / tex_size.x
		var scale_y := available.y / tex_size.y
		current_scale = minf(scale_x, scale_y) * zoom_level
		texture_rect.size = tex_size * current_scale
		texture_rect.position = (available - texture_rect.size) * 0.5

func _set_zoom(value: float) -> void:
	zoom_level = value
	_center_texture()
	redraw()

func _load_from_asset() -> void:
	if mode == "hitbox":
		current_asset.hitbox_polygons = current_asset.hitbox_polygons.duplicate(true)
	else:
		current_asset.atlas_slices = current_asset.atlas_slices.duplicate(true)

func _add_polygon() -> void:
	if mode != "hitbox":
		return
	
	var initial_points := []
	var center := Vector2(texture.get_size() / 2.0)
	var size := Vector2(64, 64)
	
	initial_points.append([center.x - size.x/2, center.y - size.y/2])
	initial_points.append([center.x + size.x/2, center.y - size.y/2])
	initial_points.append([center.x + size.x/2, center.y + size.y/2])
	initial_points.append([center.x - size.x/2, center.y + size.y/2])
	
	current_asset.hitbox_polygons.append({"points": initial_points})
	selected_polygon = current_asset.hitbox_polygons.size() - 1
	selected_point = -1
	_update_polygon_list()
	redraw()

func _add_point_to_selected() -> void:
	if mode != "hitbox" or selected_polygon < 0:
		return
	
	var polygons := current_asset.hitbox_polygons
	if selected_polygon >= polygons.size():
		return
	
	var points: Array = polygons[selected_polygon]["points"]
	if points.size() < 3:
		return
	
	var last_point := Vector2(points[points.size() - 1][0], points[points.size() - 1][1])
	var new_point := last_point + Vector2(20, 0)
	
	if snap_enabled:
		new_point.x = roundf(new_point.x / snap_size) * snap_size
		new_point.y = roundf(new_point.y / snap_size) * snap_size
	
	points.append([new_point.x, new_point.y])
	_update_polygon_list()
	redraw()

func _clear_all() -> void:
	if mode == "hitbox":
		current_asset.hitbox_polygons.clear()
	else:
		current_asset.atlas_slices.clear()
	selected_polygon = -1
	selected_point = -1
	_update_polygon_list()
	redraw()

func _update_polygon_list() -> void:
	GyroUI.clear_children(polygon_list)
	
	if mode != "hitbox":
		return
	
	var polygons := current_asset.hitbox_polygons
	for i in polygons.size():
		var btn := Button.new()
		btn.text = "Полигон " + str(i + 1) + " (" + str(polygons[i]["points"].size()) + " точек)"
		btn.custom_minimum_size = Vector2(0, GyroUI.sz(40))
		btn.flat = (i != selected_polygon)
		btn.pressed.connect(func(): _select_polygon(i))
		polygon_list.add_child(btn)

func _select_polygon(index: int) -> void:
	selected_polygon = index
	selected_point = -1
	_update_polygon_list()
	redraw()

func _save() -> void:
	if current_asset:
		GyroUI.save_resource(current_asset, save_path)
		asset_saved.emit(current_asset)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(event.position)
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			dragging_point = false
	
	elif event is InputEventMouseMotion:
		if dragging_point and selected_polygon >= 0 and selected_point >= 0:
			_handle_drag(event.position)

func _handle_click(pos: Vector2) -> void:
	if mode != "hitbox" or texture == null or texture_rect == null:
		return
	var local_pos := pos - texture_rect.global_position
	var tex_pos := local_pos / current_scale
	
	if tex_pos.x < 0 or tex_pos.x > texture.get_width() or tex_pos.y < 0 or tex_pos.y > texture.get_height():
		return
	
	if snap_enabled:
		tex_pos.x = roundf(tex_pos.x / snap_size) * snap_size
		tex_pos.y = roundf(tex_pos.y / snap_size) * snap_size
	
	var polygons := current_asset.hitbox_polygons
	
	if selected_polygon >= 0 and selected_polygon < polygons.size():
		var points: Array = polygons[selected_polygon]["points"]
		
		for i in points.size():
			var p := Vector2(points[i][0], points[i][1])
			if p.distance_to(tex_pos) < 10.0 / current_scale:
				selected_point = i
				dragging_point = true
				drag_offset = p - tex_pos
				redraw()
				return
		
		points.append([tex_pos.x, tex_pos.y])
		selected_point = points.size() - 1
		_update_polygon_list()
		redraw()

func _handle_drag(pos: Vector2) -> void:
	if selected_polygon < 0 or selected_point < 0:
		return
	
	var local_pos := pos - texture_rect.global_position
	var tex_pos := local_pos / current_scale + drag_offset
	
	if snap_enabled:
		tex_pos.x = roundf(tex_pos.x / snap_size) * snap_size
		tex_pos.y = roundf(tex_pos.y / snap_size) * snap_size
	
	var polygons := current_asset.hitbox_polygons
	if selected_polygon < polygons.size():
		var points: Array = polygons[selected_polygon]["points"]
		if selected_point < points.size():
			points[selected_point] = [tex_pos.x, tex_pos.y]
			redraw()

func redraw() -> void:
	if not is_instance_valid(draw_canvas):
		return
	draw_canvas.polygons = current_asset.hitbox_polygons
	draw_canvas.selected_polygon = selected_polygon
	draw_canvas.zoom_level = zoom_level
	draw_canvas.texture_position = texture_rect.position
	draw_canvas.current_scale = current_scale
	draw_canvas.queue_redraw()
