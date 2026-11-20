class_name GyroDialog
extends Control

signal confirmed

func _ready() -> void:
	_apply_styles()
	%Overlay.color = Color(0, 0, 0, 0)
	%Overlay.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event):
			_animate_out()
	)
	%OkButton.pressed.connect(func():
		_animate_out(func(): confirmed.emit())
	)
	%CancelButton.pressed.connect(_animate_out)

func _apply_styles() -> void:
	GyroUI.apply_glass_style(%Panel)

	%TitleLabel.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
	%TitleLabel.add_theme_font_size_override("font_size", DesignTokens.FONT_TITLE)
	%BodyLabel.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_SECONDARY)
	%BodyLabel.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = DesignTokens.COLOR_SURFACE_1
	btn_style.set_corner_radius_all(DesignTokens.RADIUS_MD)
	btn_style.content_margin_left = DesignTokens.SPACING_LG
	btn_style.content_margin_right = DesignTokens.SPACING_LG
	btn_style.content_margin_top = DesignTokens.SPACING_MD
	btn_style.content_margin_bottom = DesignTokens.SPACING_MD
	var btn_hover := btn_style.duplicate() as StyleBoxFlat
	btn_hover.bg_color = DesignTokens.COLOR_SURFACE_2
	var btn_pressed := btn_style.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = DesignTokens.COLOR_ACCENT_SOFT
	btn_pressed.border_width_bottom = 1
	btn_pressed.border_color = DesignTokens.COLOR_BORDER
	for btn in [%OkButton, %CancelButton]:
		btn.add_theme_stylebox_override("normal", btn_style)
		btn.add_theme_stylebox_override("hover", btn_hover)
		btn.add_theme_stylebox_override("pressed", btn_pressed)
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
		btn.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)

func open(title: String, body: String, ok_text: String = "", cancel_text: String = "") -> void:
	if ok_text == "":
		ok_text = GyroLang.t("ok")
	if cancel_text == "":
		cancel_text = GyroLang.t("cancel")
	%TitleLabel.text = title
	%BodyLabel.text = body
	%OkButton.text = ok_text
	%CancelButton.text = cancel_text
	visible = true
	_animate_in()

func _animate_in() -> void:
	%Panel.pivot_offset = %Panel.size * 0.5
	%Panel.scale = Vector2(0.9, 0.9)
	%Panel.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(%Overlay, "color:a", 0.6, DesignTokens.ANIM_NORMAL)
	tw.tween_property(%Panel, "scale", Vector2.ONE, DesignTokens.ANIM_SPRING).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(%Panel, "modulate:a", 1.0, DesignTokens.ANIM_NORMAL).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _animate_out(callback: Callable = Callable()) -> void:
	%Panel.pivot_offset = %Panel.size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(%Overlay, "color:a", 0.0, DesignTokens.ANIM_FAST)
	tw.tween_property(%Panel, "scale", Vector2(0.9, 0.9), DesignTokens.ANIM_FAST).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(%Panel, "modulate:a", 0.0, DesignTokens.ANIM_FAST)
	tw.set_parallel(false)
	tw.tween_callback(func():
		visible = false
		%Panel.scale = Vector2.ONE
		%Panel.modulate.a = 1.0
		if callback.is_valid():
			callback.call()
	)
