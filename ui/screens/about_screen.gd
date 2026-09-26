class_name AboutScreen
extends Control

signal back_requested
signal docs_requested

const APP_VERSION := "1.0.0"

func _ready() -> void:
	%BackButton.pressed.connect(func(): back_requested.emit())
	%TelegramButton.pressed.connect(func(): OS.shell_open("https://t.me/GyroEngine"))
	%DocsButton.pressed.connect(func(): docs_requested.emit())
	
	_apply_styles()
	_apply_lang()

func _apply_styles() -> void:
	%BackButton.add_theme_color_override("icon_normal_color", Color(0.7, 0.72, 0.76))
	%BackButton.add_theme_color_override("icon_hover_color", Color.WHITE)
	%BackButton.add_theme_color_override("icon_pressed_color", Color.WHITE)
	
	var link_style := StyleBoxFlat.new()
	link_style.bg_color = Color(0.12, 0.13, 0.15)
	link_style.set_corner_radius_all(12)
	link_style.content_margin_left = 16
	link_style.content_margin_right = 16
	link_style.content_margin_top = 14
	link_style.content_margin_bottom = 14
	
	for btn: Button in [%TelegramButton, %DocsButton]:
		btn.add_theme_stylebox_override("normal", link_style)
		
		var hover_style := link_style.duplicate() as StyleBoxFlat
		hover_style.bg_color = Color(0.14, 0.15, 0.18)
		btn.add_theme_stylebox_override("hover", hover_style)
		
		var pressed_style := link_style.duplicate() as StyleBoxFlat
		pressed_style.bg_color = Color(0.16, 0.17, 0.20)
		btn.add_theme_stylebox_override("pressed", pressed_style)
		
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.add_theme_font_size_override("font_size", GyroUI.fs(15))
		btn.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9))
		btn.add_theme_color_override("icon_normal_color", Color(0.85, 0.87, 0.9))

func _apply_lang() -> void:
	$Header/HeaderTitle.text = GyroLang.t("about")
	%AppName.text = "Gyro Engine"
	%VersionLabel.text = GyroLang.t("version") + " " + APP_VERSION
	%DescriptionLabel.text = GyroLang.t("about_description")
	
	%LinksTitle.text = GyroLang.t("links")
	%TelegramButton.text = GyroLang.t("telegram_community")
	%DocsButton.text = GyroLang.t("documentation")
	
	%LicenseTitle.text = GyroLang.t("license")
	%LicenseText.text = GyroLang.t("copyright")
