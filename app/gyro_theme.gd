class_name GyroTheme
extends RefCounted

static func make() -> Theme:
	var theme := Theme.new()

	var button_normal := StyleBoxFlat.new()
	button_normal.bg_color = Color(0.22, 0.24, 0.28)
	button_normal.set_corner_radius_all(10)
	button_normal.content_margin_left = 16
	button_normal.content_margin_right = 16
	button_normal.content_margin_top = 12
	button_normal.content_margin_bottom = 12

	var button_hover := button_normal.duplicate() as StyleBoxFlat
	button_hover.bg_color = Color(0.27, 0.29, 0.34)

	var button_pressed := button_normal.duplicate() as StyleBoxFlat
	button_pressed.bg_color = Color(0.17, 0.42, 0.47)

	theme.set_stylebox("normal", "Button", button_normal)
	theme.set_stylebox("hover", "Button", button_hover)
	theme.set_stylebox("pressed", "Button", button_pressed)
	theme.set_stylebox("disabled", "Button", button_normal.duplicate() as StyleBoxFlat)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color(0.55, 0.58, 0.62))
	theme.set_color("icon_disabled_color", "Button", Color(0.55, 0.58, 0.62))
	theme.set_font_size("font_size", "Button", GyroUI.fs(20))

	var line_normal := StyleBoxFlat.new()
	line_normal.bg_color = Color(0, 0, 0, 0)
	line_normal.border_width_bottom = 2
	line_normal.border_color = Color(0.1, 0.1, 0.12)

	theme.set_stylebox("normal", "LineEdit", line_normal)
	theme.set_stylebox("focus", "LineEdit", line_normal.duplicate() as StyleBoxFlat)
	theme.set_color("font_color", "LineEdit", Color.WHITE)
	theme.set_color("caret_color", "LineEdit", Color.WHITE)
	theme.set_color("font_placeholder_color", "LineEdit", Color(0.6, 0.6, 0.6, 0.7))
	theme.set_font_size("font_size", "LineEdit", GyroUI.fs(16))

	theme.set_color("font_color", "Label", Color.WHITE)

	theme.set_color("font_color", "OptionButton", Color.WHITE)
	var cb_style := StyleBoxFlat.new()
	cb_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	cb_style.content_margin_left = 4
	cb_style.content_margin_right = 8
	cb_style.content_margin_top = 4
	cb_style.content_margin_bottom = 4

	theme.set_stylebox("normal", "CheckBox", cb_style)
	theme.set_stylebox("hover", "CheckBox", cb_style)
	theme.set_stylebox("pressed", "CheckBox", cb_style)
	theme.set_stylebox("disabled", "CheckBox", cb_style)
	theme.set_stylebox("focus", "CheckBox", cb_style)

	theme.set_color("font_color", "CheckBox", Color.WHITE)
	theme.set_color("font_disabled_color", "CheckBox", Color(0.55, 0.58, 0.62))
	theme.set_font_size("font_size", "CheckBox", GyroUI.fs(18))

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.16, 0.17, 0.20)
	panel.set_corner_radius_all(12)
	panel.content_margin_left = 16
	panel.content_margin_right = 16
	panel.content_margin_top = 16
	panel.content_margin_bottom = 16
	theme.set_stylebox("panel", "PanelContainer", panel)

	return theme
