class_name HomeScreen
extends Control

signal manager_pressed
signal doc_pressed
signal settings_pressed

func _ready() -> void:
	%ManagerButton.pressed.connect(func(): manager_pressed.emit())
	%DocButton.pressed.connect(func(): doc_pressed.emit())
	%SettingsButton.pressed.connect(func(): settings_pressed.emit())
	apply_lang()

func apply_lang() -> void:
	%ManagerButton.text = GyroLang.t("manager")
	%DocButton.text = GyroLang.t("doc")
	%SettingsButton.text = GyroLang.t("settings")
