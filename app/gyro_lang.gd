class_name GyroLang
extends RefCounted

static var lang := "ru"
static var strings: Dictionary = {}
static var is_loaded := false

const LANG_FILES := {
	"ru": "Русский",
	"en": "English",
}

static func load_lang() -> void:
	var file_name: String = LANG_FILES.get(lang, "Русский")
	var path := "res://lang/%s.json" % file_name
	if not FileAccess.file_exists(path):
		path = "res://lang/Русский.json"
		lang = "ru"
	var file := FileAccess.open(path, FileAccess.READ)
	if file:
		var json_text := file.get_as_text()
		var json := JSON.new()
		var err := json.parse(json_text)
		if err == OK and json.data is Dictionary:
			strings = json.data
		else:
			push_error("GyroLang: JSON parse error in %s" % path)
			strings = {}
	else:
		push_error("GyroLang: Cannot open %s" % path)
		strings = {}
	is_loaded = true

static func t(key: String) -> String:
	if not is_loaded:
		load_lang()
	var val = strings.get(key, null)
	if val is String:
		return val
	return key

static func set_language(new_lang: String) -> void:
	if new_lang == "Русский":
		new_lang = "ru"
	elif new_lang == "English":
		new_lang = "en"
	if lang != new_lang:
		lang = new_lang
		is_loaded = false
		load_lang()
