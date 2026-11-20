class_name SkeletonLoader
extends PanelContainer

var _tween: Tween
var _base_color: Color = DesignTokens.COLOR_SURFACE_2

func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = _base_color
	style.set_corner_radius_all(DesignTokens.RADIUS_MD)
	add_theme_stylebox_override("panel", style)
	_start_pulse()

func _start_pulse() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_loops()
	_tween.tween_property(self, "modulate:a", 0.5, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func stop_and_free() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	queue_free()
