class_name GyroTheme
extends RefCounted

const ROBOTO_BLACK := preload("res://fonts/Roboto-Black.ttf")

static func make() -> Theme:
	var theme := Theme.new()
	var font := ROBOTO_BLACK as FontFile
	_apply_buttons(theme, font)
	_apply_line_edits(theme, font)
	_apply_labels(theme, font)
	_apply_option_buttons(theme, font)
	_apply_check_boxes(theme, font)
	_apply_panels(theme)
	_apply_scroll_containers(theme)
	_apply_progress_bars(theme)
	_apply_separators(theme)
	return theme

static func _apply_buttons(theme: Theme, font: FontFile) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = DesignTokens.COLOR_SURFACE_1
	normal.set_corner_radius_all(DesignTokens.RADIUS_MD)
	normal.content_margin_left = DesignTokens.SPACING_LG
	normal.content_margin_right = DesignTokens.SPACING_LG
	normal.content_margin_top = DesignTokens.SPACING_MD
	normal.content_margin_bottom = DesignTokens.SPACING_MD
	normal.border_width_bottom = 1
	normal.border_color = DesignTokens.COLOR_BORDER

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = DesignTokens.COLOR_SURFACE_2

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = DesignTokens.COLOR_ACCENT_SOFT
	pressed.border_color = DesignTokens.COLOR_BORDER

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = DesignTokens.COLOR_SURFACE
	disabled.border_color = DesignTokens.COLOR_BORDER

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	theme.set_font("font", "Button", font)
	theme.set_color("font_color", "Button", DesignTokens.COLOR_TEXT_PRIMARY)
	theme.set_color("font_hover_color", "Button", DesignTokens.COLOR_TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "Button", DesignTokens.COLOR_ACCENT_HOVER)
	theme.set_color("font_disabled_color", "Button", DesignTokens.COLOR_TEXT_MUTED)
	theme.set_color("icon_normal_color", "Button", DesignTokens.COLOR_TEXT_SECONDARY)
	theme.set_color("icon_hover_color", "Button", DesignTokens.COLOR_TEXT_PRIMARY)
	theme.set_color("icon_pressed_color", "Button", DesignTokens.COLOR_ACCENT)
	theme.set_color("icon_disabled_color", "Button", DesignTokens.COLOR_TEXT_MUTED)

	theme.set_font_size("font_size", "Button", DesignTokens.FONT_BODY)

static func _apply_line_edits(theme: Theme, font: FontFile) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = DesignTokens.COLOR_SURFACE
	normal.set_corner_radius_all(DesignTokens.RADIUS_MD)
	normal.border_width_bottom = 2
	normal.border_color = DesignTokens.COLOR_BORDER
	normal.content_margin_left = DesignTokens.SPACING_MD
	normal.content_margin_right = DesignTokens.SPACING_MD
	normal.content_margin_top = DesignTokens.SPACING_SM
	normal.content_margin_bottom = DesignTokens.SPACING_SM

	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = DesignTokens.COLOR_BORDER

	theme.set_stylebox("normal", "LineEdit", normal)
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_stylebox("hover", "LineEdit", normal)
	theme.set_stylebox("read_only", "LineEdit", normal)

	theme.set_font("font", "LineEdit", font)
	theme.set_color("font_color", "LineEdit", DesignTokens.COLOR_TEXT_PRIMARY)
	theme.set_color("font_placeholder_color", "LineEdit", DesignTokens.COLOR_TEXT_MUTED)
	theme.set_color("caret_color", "LineEdit", DesignTokens.COLOR_ACCENT)
	theme.set_font_size("font_size", "LineEdit", DesignTokens.FONT_BODY)

static func _apply_labels(theme: Theme, font: FontFile) -> void:
	theme.set_font("font", "Label", font)
	theme.set_color("font_color", "Label", DesignTokens.COLOR_TEXT_PRIMARY)
	theme.set_font_size("font_size", "Label", DesignTokens.FONT_BODY)

static func _apply_option_buttons(theme: Theme, font: FontFile) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = DesignTokens.COLOR_SURFACE_1
	normal.set_corner_radius_all(DesignTokens.RADIUS_MD)
	normal.border_width_bottom = 1
	normal.border_color = DesignTokens.COLOR_BORDER
	normal.content_margin_left = DesignTokens.SPACING_MD
	normal.content_margin_right = DesignTokens.SPACING_MD
	normal.content_margin_top = DesignTokens.SPACING_SM
	normal.content_margin_bottom = DesignTokens.SPACING_SM

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = DesignTokens.COLOR_SURFACE_2

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = DesignTokens.COLOR_ACCENT_SOFT
	pressed.border_color = DesignTokens.COLOR_BORDER

	theme.set_stylebox("normal", "OptionButton", normal)
	theme.set_stylebox("hover", "OptionButton", hover)
	theme.set_stylebox("pressed", "OptionButton", pressed)
	theme.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	theme.set_stylebox("disabled", "OptionButton", normal)

	theme.set_font("font", "OptionButton", font)
	theme.set_color("font_color", "OptionButton", DesignTokens.COLOR_TEXT_PRIMARY)
	theme.set_color("font_hover_color", "OptionButton", DesignTokens.COLOR_TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "OptionButton", DesignTokens.COLOR_ACCENT_HOVER)
	theme.set_font_size("font_size", "OptionButton", DesignTokens.FONT_BODY)

	var popup := StyleBoxFlat.new()
	popup.bg_color = DesignTokens.COLOR_SURFACE_1
	popup.set_corner_radius_all(DesignTokens.RADIUS_MD)
	popup.border_width_left = 1
	popup.border_width_right = 1
	popup.border_width_bottom = 1
	popup.border_color = DesignTokens.COLOR_BORDER
	popup.content_margin_left = DesignTokens.SPACING_SM
	popup.content_margin_right = DesignTokens.SPACING_SM
	popup.content_margin_top = DesignTokens.SPACING_SM
	popup.content_margin_bottom = DesignTokens.SPACING_SM
	theme.set_stylebox("panel", "PopupMenu", popup)

	theme.set_font("font", "PopupMenu", font)
	theme.set_color("font_color", "PopupMenu", DesignTokens.COLOR_TEXT_PRIMARY)
	theme.set_color("font_hover_color", "PopupMenu", DesignTokens.COLOR_ACCENT_HOVER)
	theme.set_color("font_accelerator_color", "PopupMenu", DesignTokens.COLOR_TEXT_MUTED)
	theme.set_color("font_disabled_color", "PopupMenu", DesignTokens.COLOR_TEXT_MUTED)
	theme.set_color("font_separator_color", "PopupMenu", DesignTokens.COLOR_TEXT_MUTED)

	var hover_bg := StyleBoxFlat.new()
	hover_bg.bg_color = DesignTokens.COLOR_ACCENT_SOFT
	hover_bg.set_corner_radius_all(DesignTokens.RADIUS_SM)
	theme.set_stylebox("hover", "PopupMenu", hover_bg)

static func _apply_check_boxes(theme: Theme, font: FontFile) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.content_margin_left = DesignTokens.SPACING_SM
	normal.content_margin_right = DesignTokens.SPACING_MD
	normal.content_margin_top = DesignTokens.SPACING_SM
	normal.content_margin_bottom = DesignTokens.SPACING_SM

	theme.set_stylebox("normal", "CheckBox", normal)
	theme.set_stylebox("hover", "CheckBox", normal)
	theme.set_stylebox("pressed", "CheckBox", normal)
	theme.set_stylebox("disabled", "CheckBox", normal)
	theme.set_stylebox("focus", "CheckBox", normal)

	theme.set_font("font", "CheckBox", font)
	theme.set_color("font_color", "CheckBox", DesignTokens.COLOR_TEXT_PRIMARY)
	theme.set_color("font_hover_color", "CheckBox", DesignTokens.COLOR_TEXT_PRIMARY)
	theme.set_color("font_disabled_color", "CheckBox", DesignTokens.COLOR_TEXT_MUTED)
	theme.set_color("font_pressed_color", "CheckBox", DesignTokens.COLOR_ACCENT_HOVER)
	theme.set_font_size("font_size", "CheckBox", DesignTokens.FONT_BODY)

static func _apply_panels(theme: Theme) -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = DesignTokens.PANEL_BG
	panel.set_corner_radius_all(DesignTokens.RADIUS_LG)
	panel.border_width_left = 1
	panel.border_width_right = 1
	panel.border_width_top = 1
	panel.border_width_bottom = 1
	panel.border_color = DesignTokens.PANEL_BORDER
	panel.content_margin_left = DesignTokens.SPACING_LG
	panel.content_margin_right = DesignTokens.SPACING_LG
	panel.content_margin_top = DesignTokens.SPACING_LG
	panel.content_margin_bottom = DesignTokens.SPACING_LG
	theme.set_stylebox("panel", "PanelContainer", panel)

	var shadow_panel := StyleBoxFlat.new()
	shadow_panel.bg_color = DesignTokens.PANEL_BG
	shadow_panel.set_corner_radius_all(DesignTokens.RADIUS_LG)
	shadow_panel.border_width_left = 1
	shadow_panel.border_width_right = 1
	shadow_panel.border_width_top = 1
	shadow_panel.border_width_bottom = 1
	shadow_panel.border_color = DesignTokens.PANEL_BORDER
	shadow_panel.content_margin_left = DesignTokens.SPACING_LG
	shadow_panel.content_margin_right = DesignTokens.SPACING_LG
	shadow_panel.content_margin_top = DesignTokens.SPACING_LG
	shadow_panel.content_margin_bottom = DesignTokens.SPACING_LG
	theme.set_stylebox("panel", "Panel", shadow_panel)

static func _apply_scroll_containers(theme: Theme) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	theme.set_stylebox("panel", "ScrollContainer", sb)

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(DesignTokens.COLOR_TEXT_MUTED.r, DesignTokens.COLOR_TEXT_MUTED.g, DesignTokens.COLOR_TEXT_MUTED.b, 0.3)
	grabber.set_corner_radius_all(DesignTokens.RADIUS_FULL)
	grabber.content_margin_left = 2
	grabber.content_margin_right = 2

	var grabber_highlight := grabber.duplicate() as StyleBoxFlat
	grabber_highlight.bg_color = Color(DesignTokens.COLOR_TEXT_SECONDARY.r, DesignTokens.COLOR_TEXT_SECONDARY.g, DesignTokens.COLOR_TEXT_SECONDARY.b, 0.5)

	var grabber_pressed := grabber.duplicate() as StyleBoxFlat
	grabber_pressed.bg_color = Color(DesignTokens.COLOR_ACCENT.r, DesignTokens.COLOR_ACCENT.g, DesignTokens.COLOR_ACCENT.b, 0.6)

	theme.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	theme.set_stylebox("scroll_focus", "VScrollBar", StyleBoxEmpty.new())
	theme.set_stylebox("grabber", "VScrollBar", grabber)
	theme.set_stylebox("grabber_highlight", "VScrollBar", grabber_highlight)
	theme.set_stylebox("grabber_pressed", "VScrollBar", grabber_pressed)

	theme.set_stylebox("scroll", "HScrollBar", StyleBoxEmpty.new())
	theme.set_stylebox("scroll_focus", "HScrollBar", StyleBoxEmpty.new())
	theme.set_stylebox("grabber", "HScrollBar", grabber)
	theme.set_stylebox("grabber_highlight", "HScrollBar", grabber_highlight)
	theme.set_stylebox("grabber_pressed", "HScrollBar", grabber_pressed)

	theme.set_constant("scrollbar_margin_left", "VScrollBar", 2)
	theme.set_constant("scrollbar_margin_right", "VScrollBar", 2)
	theme.set_constant("grabber_thickness", "VScrollBar", 6)

static func _apply_progress_bars(theme: Theme) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = DesignTokens.COLOR_SURFACE
	bg.set_corner_radius_all(DesignTokens.RADIUS_FULL)

	var fill := StyleBoxFlat.new()
	fill.bg_color = DesignTokens.COLOR_ACCENT
	fill.set_corner_radius_all(DesignTokens.RADIUS_FULL)

	theme.set_stylebox("background", "ProgressBar", bg)
	theme.set_stylebox("fill", "ProgressBar", fill)

static func _apply_separators(theme: Theme) -> void:
	theme.set_color("separator", "HSeparator", DesignTokens.COLOR_BORDER)
	theme.set_constant("separation", "HSeparator", DesignTokens.SPACING_MD)
