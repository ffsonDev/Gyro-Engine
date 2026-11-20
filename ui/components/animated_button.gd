class_name AnimatedButton
extends Button

var _ripple: ColorRect
var _base_color: Color = DesignTokens.COLOR_SURFACE_1
var _hover_color: Color = DesignTokens.COLOR_SURFACE_2
var _pressed_color: Color = DesignTokens.COLOR_ACCENT_SOFT
var _corner_radius: int = DesignTokens.RADIUS_MD
var _scale_normal := Vector2.ONE
var _scale_pressed := Vector2(0.96, 0.96)
var _tween_scale: Tween
var _tween_color: Tween
var _style: StyleBoxFlat
var _current_color: Color = DesignTokens.COLOR_SURFACE_1

func _animate_color(target: Color) -> Tween:
	if _tween_color != null and _tween_color.is_valid():
		_tween_color.kill()
	var tw := create_tween()
	tw.tween_method(_apply_style, _current_color, target, DesignTokens.ANIM_FAST)
	return tw

func _apply_style(color: Color) -> void:
	_current_color = color
	if _style == null:
		_style = StyleBoxFlat.new()
		_style.set_corner_radius_all(_corner_radius)
		_style.content_margin_left = 16
		_style.content_margin_right = 16
		_style.content_margin_top = 12
		_style.content_margin_bottom = 12
		_style.border_width_bottom = 1
		add_theme_stylebox_override("normal", _style)
		add_theme_stylebox_override("hover", _style)
		add_theme_stylebox_override("pressed", _style)
	_style.bg_color = color
	_style.border_color = DesignTokens.COLOR_BUTTON_BORDER

func _ready() -> void:
	pivot_offset = size * 0.5
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	resized.connect(func(): pivot_offset = size * 0.5)
	_apply_style(_base_color)

func _on_mouse_entered() -> void:
	_tween_color = _animate_color(_hover_color)

func _on_mouse_exited() -> void:
	_tween_color = _animate_color(_base_color)

func _on_button_down() -> void:
	_animate_scale(_scale_pressed)
	_spawn_ripple()
	_tween_color = _animate_color(_pressed_color)

func _on_button_up() -> void:
	_animate_scale(_scale_normal)
	if Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
		_tween_color = _animate_color(_hover_color)
	else:
		_tween_color = _animate_color(_base_color)

func _animate_scale(target: Vector2) -> void:
	if _tween_scale != null and _tween_scale.is_valid():
		_tween_scale.kill()
	_tween_scale = create_tween()
	_tween_scale.tween_property(self, "scale", target, DesignTokens.ANIM_FAST).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _spawn_ripple() -> void:
	if _ripple != null and is_instance_valid(_ripple):
		_ripple.queue_free()
	_ripple = ColorRect.new()
	_ripple.color = Color(1, 1, 1, 0.15)
	_ripple.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ripple.clip_contents = true
	var local_pos := get_local_mouse_position()
	var ripple_size := maxf(size.x, size.y) * 2.0
	_ripple.size = Vector2(ripple_size, ripple_size)
	_ripple.position = local_pos - Vector2(ripple_size, ripple_size) * 0.5
	var mask := StyleBoxFlat.new()
	mask.set_corner_radius_all(_corner_radius)
	_ripple.add_theme_stylebox_override("panel", mask)
	add_child(_ripple)
	_ripple.modulate.a = 0.0
	var tw := _ripple.create_tween()
	tw.set_parallel(true)
	tw.tween_property(_ripple, "modulate:a", 0.3, 0.1)
	tw.tween_property(_ripple, "size", Vector2(ripple_size * 1.5, ripple_size * 1.5), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_property(_ripple, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func():
		if is_instance_valid(_ripple):
			_ripple.queue_free()
	)
