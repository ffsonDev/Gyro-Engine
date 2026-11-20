class_name AboutScreen
extends Control

signal back_requested
signal docs_requested

func _ready() -> void:
	%BackButton.pressed.connect(func(): back_requested.emit())
	%TelegramButton.pressed.connect(func(): OS.shell_open("https://t.me/GyroEngine"))
	%DocsButton.pressed.connect(func(): docs_requested.emit())
	
	_apply_styles()
	_apply_lang()
	_animate_in()

func _animate_in() -> void:
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, DesignTokens.ANIM_NORMAL).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _apply_styles() -> void:
	%BackButton.add_theme_color_override("icon_normal_color", DesignTokens.COLOR_TEXT_SECONDARY)
	%BackButton.add_theme_color_override("icon_hover_color", DesignTokens.COLOR_TEXT_PRIMARY)
	%BackButton.add_theme_color_override("icon_pressed_color", DesignTokens.COLOR_ACCENT)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = DesignTokens.COLOR_SURFACE_1
	btn_style.set_corner_radius_all(DesignTokens.RADIUS_MD)
	btn_style.content_margin_left = DesignTokens.SPACING_LG
	btn_style.content_margin_right = DesignTokens.SPACING_LG
	btn_style.content_margin_top = DesignTokens.SPACING_MD
	btn_style.content_margin_bottom = DesignTokens.SPACING_MD
	btn_style.border_width_bottom = 1
	btn_style.border_color = DesignTokens.COLOR_BORDER
	for btn: Button in [%TelegramButton, %DocsButton]:
		btn.add_theme_stylebox_override("normal", btn_style)
		var hover_style := btn_style.duplicate() as StyleBoxFlat
		hover_style.bg_color = DesignTokens.COLOR_SURFACE_2
		btn.add_theme_stylebox_override("hover", hover_style)
		var pressed_style := btn_style.duplicate() as StyleBoxFlat
		pressed_style.bg_color = DesignTokens.COLOR_ACCENT_SOFT
		pressed_style.border_color = DesignTokens.COLOR_ACCENT
		btn.add_theme_stylebox_override("pressed", pressed_style)
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
		btn.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
		btn.add_theme_color_override("font_hover_color", DesignTokens.COLOR_TEXT_PRIMARY)
		btn.add_theme_color_override("font_pressed_color", DesignTokens.COLOR_ACCENT_HOVER)
		btn.add_theme_color_override("icon_normal_color", DesignTokens.COLOR_TEXT_SECONDARY)
		btn.add_theme_color_override("icon_hover_color", DesignTokens.COLOR_TEXT_PRIMARY)
		btn.add_theme_color_override("icon_pressed_color", DesignTokens.COLOR_ACCENT)

func _apply_lang() -> void:
	$Header/HeaderTitle.text = GyroLang.t("about")
	%AppName.text = "Gyro Engine"
	%VersionLabel.text = GyroLang.t("version") + " " + GyroVersion.APP_VERSION
	%DescriptionLabel.text = GyroLang.t("about_description")
	
	%LinksTitle.text = GyroLang.t("links")
	%TelegramButton.text = GyroLang.t("telegram_community")
	%DocsButton.text = GyroLang.t("documentation")
	
	%LicenseTitle.text = GyroLang.t("license")
	%LicenseText.text = GyroLang.t("copyright")
