class_name GyroCircle
extends Control

var radius := 50.0
var fill_color := Color.WHITE
var border_width := 0.0
var border_color := Color.WHITE

func set_radius(r: float) -> void:
	radius = r
	size = Vector2(r * 2.0, r * 2.0)
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, radius, fill_color)
	if border_width > 0.0:
		draw_arc(center, radius, 0.0, TAU, 48, border_color, border_width)
