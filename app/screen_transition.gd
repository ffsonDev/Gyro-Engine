class_name ScreenTransition
extends RefCounted

var _root: Control
var _current_screen: Control
var _transition_overlay: ColorRect

func setup(root: Control) -> void:
	_root = root
	_transition_overlay = ColorRect.new()
	_transition_overlay.color = Color(0, 0, 0, 0)
	_transition_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_overlay.z_index = 100
	_root.add_child(_transition_overlay)

func show_screen(new_screen: Control, old_screen: Control = null) -> void:
	if old_screen == new_screen:
		return

	if old_screen != null:
		_animate_out(old_screen)
		new_screen.visible = true
		new_screen.modulate.a = 0.0
		new_screen.position.y = 40.0
		_animate_in(new_screen)
	else:
		new_screen.visible = true

func _animate_out(screen: Control) -> void:
	if screen == null or not is_instance_valid(screen):
		return
	var tw := screen.create_tween()
	tw.set_parallel(true)
	tw.tween_property(screen, "modulate:a", 0.0, DesignTokens.ANIM_FAST)
	tw.tween_property(screen, "position:y", -20.0, DesignTokens.ANIM_FAST)
	tw.set_parallel(false)
	tw.tween_callback(func():
		if is_instance_valid(screen):
			screen.visible = false
			screen.position.y = 0.0
			screen.modulate.a = 1.0
	)

func _animate_in(screen: Control) -> void:
	if screen == null or not is_instance_valid(screen):
		return
	var tw := screen.create_tween()
	tw.set_parallel(true)
	tw.tween_property(screen, "modulate:a", 1.0, DesignTokens.ANIM_SLOW).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(screen, "position:y", 0.0, DesignTokens.ANIM_SLOW).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func animate_dialog_in(dialog: Control) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return
	dialog.scale = Vector2(0.9, 0.9)
	dialog.modulate.a = 0.0
	dialog.pivot_offset = dialog.size * 0.5
	var tw := dialog.create_tween()
	tw.set_parallel(true)
	tw.tween_property(dialog, "scale", Vector2.ONE, DesignTokens.ANIM_SPRING).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(dialog, "modulate:a", 1.0, DesignTokens.ANIM_NORMAL).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func animate_dialog_out(dialog: Control) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return
	dialog.pivot_offset = dialog.size * 0.5
	var tw := dialog.create_tween()
	tw.set_parallel(true)
	tw.tween_property(dialog, "scale", Vector2(0.9, 0.9), DesignTokens.ANIM_FAST).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(dialog, "modulate:a", 0.0, DesignTokens.ANIM_FAST).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.set_parallel(false)
	tw.tween_callback(func():
		if is_instance_valid(dialog):
			dialog.visible = false
			dialog.scale = Vector2.ONE
			dialog.modulate.a = 1.0
	)

func stagger_children(parent: Control, delay_per_item: float = 0.04) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var i := 0
	for child in parent.get_children():
		if child is Control:
			var c := child as Control
			var original_y := c.position.y
			c.modulate.a = 0.0
			c.position.y = original_y + 20.0
			var tw := c.create_tween()
			tw.set_parallel(true)
			tw.tween_property(c, "modulate:a", 1.0, DesignTokens.ANIM_NORMAL).set_delay(float(i) * delay_per_item).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(c, "position:y", original_y, DesignTokens.ANIM_SLOW).set_delay(float(i) * delay_per_item).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			i += 1
