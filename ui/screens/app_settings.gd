class_name AppSettingsScreen
extends Control

signal back_requested
signal lang_changed

var app_settings: GyroAppSettings

var backup_option: OptionButton
var backup_label: Label
var friction_option: OptionButton
var friction_label: Label
var about_button: Button

const APP_VERSION := "1.0.0"

const ABOUT_SCENE := preload("res://ui/screens/about_screen.tscn")
var about_screen: AboutScreen

func _ready() -> void:
	%Title.add_theme_font_size_override("font_size", GyroUI.fs(28))
	%LanguageOption.add_item("Русский", 0)
	%LanguageOption.add_item("English", 1)
	%BackButton.pressed.connect(func(): back_requested.emit())
	%LanguageOption.item_selected.connect(func(id: int):
		if app_settings == null:
			return
		app_settings.language = "ru" if id == 0 else "en"
		GyroAppSettings.save_settings(app_settings)
		GyroLang.set_language(app_settings.language)
		lang_changed.emit()
	)
	
	%VibrationCheck.toggled.connect(func(on: bool):
		if app_settings == null:
			return
		app_settings.vibration_enabled = on
		GyroAppSettings.save_settings(app_settings)
	)
	
	%LogCheck.toggled.connect(func(on: bool):
		if app_settings == null:
			return
		app_settings.show_test_log = on
		GyroAppSettings.save_settings(app_settings)
	)
	
	_build_extra_settings()
	apply_lang()

func _build_extra_settings() -> void:
	var root := get_node("Root") as VBoxContainer
	if root == null:
		return
	
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.3, 0.3, 0.3))
	root.add_child(sep)
	
	var backup_row := HBoxContainer.new()
	backup_row.layout_mode = 2
	backup_row.add_theme_constant_override("separation", 8)
	root.add_child(backup_row)
	
	backup_label = Label.new()
	backup_label.custom_minimum_size = Vector2(160, 0)
	backup_label.layout_mode = 2
	backup_row.add_child(backup_label)
	
	backup_option = OptionButton.new()
	backup_option.layout_mode = 2
	backup_option.item_selected.connect(func(id: int):
		if app_settings == null:
			return
		# id = 0 (off), 1 (1 min), 5 (5 min), 15, 30, 60
		var values := [0, 1, 5, 15, 30, 60]
		app_settings.backup_interval_minutes = values[id] if id < values.size() else 5
		GyroAppSettings.save_settings(app_settings)
	)
	backup_row.add_child(backup_option)
	
	var friction_row := HBoxContainer.new()
	friction_row.layout_mode = 2
	friction_row.add_theme_constant_override("separation", 8)
	root.add_child(friction_row)
	
	friction_label = Label.new()
	friction_label.custom_minimum_size = Vector2(160, 0)
	friction_label.layout_mode = 2
	friction_row.add_child(friction_label)
	
	friction_option = OptionButton.new()
	friction_option.layout_mode = 2
	friction_option.item_selected.connect(func(id: int):
		if app_settings == null:
			return
		match id:
			0: app_settings.scroll_friction = 0.5
			1: app_settings.scroll_friction = 1.0
			2: app_settings.scroll_friction = 2.0
		GyroAppSettings.save_settings(app_settings)
	)
	friction_row.add_child(friction_option)
	
	about_button = Button.new()
	about_button.custom_minimum_size = Vector2(0, 56)
	about_button.layout_mode = 2
	about_button.pressed.connect(_show_about)
	root.add_child(about_button)

func _show_about() -> void:
	if about_screen == null:
		about_screen = ABOUT_SCENE.instantiate()
		about_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		about_screen.z_index = 50
		about_screen.back_requested.connect(func():
			about_screen.visible = false
		)
		get_parent().add_child(about_screen)
	about_screen.visible = true

func apply_lang() -> void:
	%Title.text = GyroLang.t("settings")
	%LanguageLabel.text = GyroLang.t("language")
	%VibrationCheck.text = GyroLang.t("vibration")
	%LogCheck.text = GyroLang.t("test_log")
	
	if backup_option != null:
		backup_option.clear()
		backup_option.add_item(GyroLang.t("backups_off"), 0)
		backup_option.add_item("1 " + GyroLang.t("minute"), 1)
		backup_option.add_item("5 " + GyroLang.t("minutes"), 2)
		backup_option.add_item("15 " + GyroLang.t("minutes"), 3)
		backup_option.add_item("30 " + GyroLang.t("minutes"), 4)
		backup_option.add_item("1 " + GyroLang.t("hour"), 5)
	
	if friction_option != null:
		friction_option.clear()
		friction_option.add_item(GyroLang.t("friction_smooth"), 0)
		friction_option.add_item(GyroLang.t("friction_normal"), 1)
		friction_option.add_item(GyroLang.t("friction_fast"), 2)
	
	if about_button != null:
		about_button.text = GyroLang.t("about")
	
	if backup_label != null:
		backup_label.text = GyroLang.t("backup_interval")
	if friction_label != null:
		friction_label.text = GyroLang.t("scroll_friction")

func setup(s: GyroAppSettings) -> void:
	app_settings = s
	if app_settings == null:
		return
	%LanguageOption.selected = 0 if app_settings.language == "ru" else 1
	%VibrationCheck.set_pressed_no_signal(app_settings.vibration_enabled)
	%LogCheck.set_pressed_no_signal(app_settings.show_test_log)
	
	if backup_option != null:
		var values := [0, 1, 5, 15, 30, 60]
		var idx := values.find(app_settings.backup_interval_minutes)
		backup_option.selected = idx if idx >= 0 else 2
	
	if friction_option != null:
		if app_settings.scroll_friction <= 0.5:
			friction_option.selected = 0
		elif app_settings.scroll_friction >= 2.0:
			friction_option.selected = 2
		else:
			friction_option.selected = 1
