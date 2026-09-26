class_name GyroAppSettings
extends Resource

@export var backups_enabled := true
@export var language := "ru"
@export var vibration_enabled := true
@export var show_test_log := true
@export var backup_interval_minutes := 5
@export var scroll_friction := 1.0
@export var show_test_close_button := true

const PATH := "user://gyro_settings.tres"

static func load_settings() -> GyroAppSettings:
	if ResourceLoader.exists(PATH):
		var loaded := ResourceLoader.load(PATH)
		if loaded is GyroAppSettings:
			if loaded.language == "Русский":
				loaded.language = "ru"
				save_settings(loaded)
			elif loaded.language == "English":
				loaded.language = "en"
				save_settings(loaded)
			return loaded
	
	var settings := GyroAppSettings.new()
	var locale := OS.get_locale().to_lower()
	var lang_code := OS.get_locale_language().to_lower()
	
	if locale.begins_with("ru") or lang_code.begins_with("ru"):
		settings.language = "ru"
	elif locale.begins_with("en") or lang_code.begins_with("en"):
		settings.language = "en"
	else:
		settings.language = "en"
	
	save_settings(settings)
	return settings

static func save_settings(s: GyroAppSettings) -> void:
	ResourceSaver.save(s, PATH)
