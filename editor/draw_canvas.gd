extends Control

var polygons: Array = []
var selected_polygon: int = -1
var zoom_level: float = 1.0
var texture_position: Vector2 = Vector2.ZERO
var current_scale: float = 1.0

func _draw() -> void:
	for i in polygons.size():
		var polygon = polygons[i]
		var color := Color(0.2, 0.8, 0.9) if i == selected_polygon else Color(0.4, 0.6, 0.8)
		_draw_polygon(polygon, color, i == selected_polygon)

func _draw_polygon(polygon: Dictionary, color: Color, fill: bool) -> void:
	var points: Array = polygon["points"]
	if points.size() < 3:
		return
	
	var p2d := PackedVector2Array()
	for p in points:
		p2d.append(Vector2(p[0], p[1]) * current_scale + texture_position)
	
	if fill and _is_valid_polygon(p2d):
		draw_colored_polygon(p2d, Color(color.r, color.g, color.b, 0.3))
	
	for i in p2d.size():
		var next := (i + 1) % p2d.size()
		draw_line(p2d[i], p2d[next], color, 2.0)
	
	for i in p2d.size():
		draw_circle(p2d[i], 6.0, Color.WHITE)

func _is_valid_polygon(points: PackedVector2Array) -> bool:
	if points.size() < 3:
		return false
	
	var area := 0.0
	for i in points.size():
		var j := (i + 1) % points.size()
		area += points[i].x * points[j].y
		area -= points[j].x * points[i].y
	
	return absf(area) > 0.5
