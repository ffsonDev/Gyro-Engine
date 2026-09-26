extends Node
var _selected_callback: Callable
var _failed_callback: Callable
var _save_callback: Callable
var _save_failed_callback: Callable
var _file_dialog: FileDialog
var _plugin: Object
var _plugin_connected := false
var last_picked_file := ""

func pick_file(kind: String, on_selected: Callable, on_failed: Callable) -> void:
	_selected_callback = on_selected
	_failed_callback = on_failed
	if OS.get_name() == "Android":
		_pick_android(kind)
	else:
		_pick_desktop(kind)

func save_file(source_path: String, kind: String, title: String, on_saved: Callable, on_failed: Callable) -> void:
	_save_callback = on_saved
	_save_failed_callback = on_failed
	if OS.get_name() == "Android":
		_save_android(source_path, kind, title)
	else:
		_save_desktop(source_path, kind, title)

func _pick_android(kind: String) -> void:
	if not Engine.has_singleton("GodotFilePicker"):
		_emit_failed(GyroLang.t("file_pick_plugin_missing"))
		return
	_plugin = Engine.get_singleton("GodotFilePicker")
	if not _plugin_connected:
		_plugin.connect("file_picked", _on_file_picked)
		_plugin.connect("file_saved", _on_file_saved)
		_plugin_connected = true
	_plugin.call("openFilePicker", _mime_for_kind(kind))

func _save_android(source_path: String, kind: String, title: String) -> void:
	if not Engine.has_singleton("GodotFilePicker"):
		_emit_save_failed(GyroLang.t("file_pick_plugin_missing"))
		return
	_plugin = Engine.get_singleton("GodotFilePicker")
	if not _plugin_connected:
		_plugin.connect("file_picked", _on_file_picked)
		_plugin.connect("file_saved", _on_file_saved)
		_plugin_connected = true
	var global_path := ProjectSettings.globalize_path(source_path)
	_plugin.call("saveFileAs", global_path, _mime_for_kind(kind), title)

func _on_file_picked(temp_path: String, mime_type: String) -> void:
	if temp_path == "":
		_emit_failed(GyroLang.t("file_pick_cancelled"))
		return
	var original := _extract_original_name(temp_path.get_file())
	if original.get_extension() == "":
		var ext := _ext_for_mime(mime_type)
		original = (original.get_basename() + "." + ext) if original != "" else ("file." + ext) if ext != "" else original
	last_picked_file = original
	var stamp := int(Time.get_unix_time_from_system() * 1000.0)
	var dest := "user://imported_" + str(stamp) + "_" + (original if original != "" else temp_path.get_file())
	var err := DirAccess.copy_absolute(temp_path, ProjectSettings.globalize_path(dest))
	if err != OK:
		_emit_failed(GyroLang.t("asset_copy_failed"))
		return
	DirAccess.remove_absolute(temp_path)
	_emit_selected(dest)

static func _extract_original_name(base: String) -> String:
	var m := RegEx.create_from_string("^picked_\\d+_(.+)$").search(base)
	if m != null:
		return m.get_string(1)
	return ""

static func _ext_for_mime(mime: String) -> String:
	match mime.to_lower():
		"image/png": return "png"
		"image/jpeg": return "jpg"
		"image/webp": return "webp"
		"image/svg+xml": return "svg"
		"audio/mpeg": return "mp3"
		"audio/ogg": return "ogg"
		"audio/wav", "audio/x-wav": return "wav"
		"video/webm": return "webm"
		"video/ogg": return "ogv"
		"font/ttf", "application/font-sfnt": return "ttf"
		"font/otf", "application/vnd.ms-opentype": return "otf"
		"font/woff2", "font/woff": return "woff2"
	return ""

func _mime_for_kind(kind: String) -> String:
	match kind:
		"sprite": return "image/*"
		"sound": return "audio/*"
		"video": return "video/*"
		"font": return "font/*"
		"apk": return "application/vnd.android.package-archive"
		_: return "*/*"

func _extension_for_mime(mime: String) -> String:
	match mime:
		"image/png":
			return ".png"
		"image/jpeg", "image/jpg":
			return ".jpg"
		"image/webp":
			return ".webp"
		"image/svg+xml":
			return ".svg"
		"audio/mpeg":
			return ".mp3"
		"audio/ogg":
			return ".ogg"
		"audio/wav", "audio/x-wav":
			return ".wav"
		"video/webm":
			return ".webm"
		"video/ogg":
			return ".ogv"
		"font/ttf", "application/font-sfnt":
			return ".ttf"
		"font/otf":
			return ".otf"
		"font/woff2":
			return ".woff2"
	return ""

func _on_file_saved(ok: bool, uri_string: String) -> void:
	if ok:
		if _save_callback.is_valid():
			_save_callback.call(uri_string)
	else:
		_emit_save_failed(GyroLang.t("file_save_cancelled"))
	_clear_save_callbacks()

func _pick_desktop(kind: String) -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.file_selected.connect(func(path: String):
			_emit_selected(path)
		)
		_file_dialog.canceled.connect(func():
			_emit_failed(GyroLang.t("asset_copy_failed"))
		)
		add_child(_file_dialog)
	if _file_dialog.visible:
		_file_dialog.hide()
	_file_dialog.clear_filters()
	for filter in _filters_for_kind(kind):
		_file_dialog.add_filter(filter)
	_file_dialog.popup_centered_ratio(0.8)

func _save_desktop(source_path: String, kind: String, title: String) -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.file_selected.connect(func(path: String):
			DirAccess.copy_absolute(source_path, path)
			if _save_callback.is_valid():
				_save_callback.call(path)
			_clear_save_callbacks()
		)
		_file_dialog.canceled.connect(func():
			_emit_save_failed(GyroLang.t("file_save_cancelled"))
		)
		add_child(_file_dialog)
	if _file_dialog.visible:
		_file_dialog.hide()
	_file_dialog.clear_filters()
	for filter in _filters_for_kind(kind):
		_file_dialog.add_filter(filter)
	_file_dialog.current_file = title
	_file_dialog.popup_centered_ratio(0.8)

func _emit_selected(path: String) -> void:
	if _selected_callback.is_valid():
		_selected_callback.call(path)
	_clear_callbacks()

func _emit_failed(message: String) -> void:
	if _failed_callback.is_valid():
		_failed_callback.call(message)
	_clear_callbacks()

func _emit_save_failed(message: String) -> void:
	if _save_failed_callback.is_valid():
		_save_failed_callback.call(message)
	_clear_save_callbacks()

func _clear_callbacks() -> void:
	_selected_callback = Callable()
	_failed_callback = Callable()

func _clear_save_callbacks() -> void:
	_save_callback = Callable()
	_save_failed_callback = Callable()

func _filters_for_kind(kind: String) -> Array:
	match kind:
		"sprite":
			return ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.svg"]
		"sound":
			return ["*.mp3", "*.ogg", "*.wav"]
		"font":
			return ["*.ttf", "*.otf", "*.woff2"]
		"video":
			return ["*.mp4", "*.webm"]
		"apk":
			return ["*.apk"]
		_:
			return ["*.*"]
