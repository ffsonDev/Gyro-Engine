extends Node

enum Mode { NONE, PICK, SAVE }

var last_picked_file := ""
var _mode: int = Mode.NONE
var _selected_callback: Callable
var _failed_callback: Callable
var _save_callback: Callable
var _save_failed_callback: Callable
var _pending_save_source := ""
var _file_dialog: FileDialog
var _plugin: Object
var _plugin_connected := false

func pick_file(kind: String, on_selected: Callable, on_failed: Callable) -> void:
	if _mode != Mode.NONE:
		if on_failed.is_valid():
			on_failed.call_deferred(GyroLang.t("file_picker_busy"))
		return
	_mode = Mode.PICK
	_selected_callback = on_selected
	_failed_callback = on_failed
	if OS.get_name() == "Android":
		if not _ensure_plugin():
			_emit_failed(GyroLang.t("file_pick_plugin_missing"))
			return
		_plugin.call("openFilePicker", _mime_for_kind(kind))
	else:
		var dialog := _ensure_dialog()
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_prepare_dialog(dialog, kind, "")

func save_file(source_path: String, kind: String, title: String, on_saved: Callable, on_failed: Callable) -> void:
	if _mode != Mode.NONE:
		if on_failed.is_valid():
			on_failed.call_deferred(GyroLang.t("file_picker_busy"))
		return
	_mode = Mode.SAVE
	_save_callback = on_saved
	_save_failed_callback = on_failed
	_pending_save_source = source_path
	if OS.get_name() == "Android":
		if not _ensure_plugin():
			_emit_save_failed(GyroLang.t("file_pick_plugin_missing"))
			return
		_plugin.call("saveFileAs", ProjectSettings.globalize_path(source_path), _mime_for_kind(kind), title)
	else:
		var dialog := _ensure_dialog()
		dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_prepare_dialog(dialog, kind, title)

func _ensure_plugin() -> bool:
	if not Engine.has_singleton("GodotFilePicker"):
		return false
	_plugin = Engine.get_singleton("GodotFilePicker")
	if not _plugin_connected:
		_plugin.connect("file_picked", _on_file_picked)
		_plugin.connect("file_saved", _on_file_saved)
		_plugin_connected = true
	return true

func _ensure_dialog() -> FileDialog:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.file_selected.connect(_on_dialog_file_selected)
		_file_dialog.canceled.connect(_on_dialog_canceled)
		add_child(_file_dialog)
	return _file_dialog

func _prepare_dialog(dialog: FileDialog, kind: String, title: String) -> void:
	if dialog.visible:
		dialog.hide()
	dialog.clear_filters()
	for filter in _filters_for_kind(kind):
		dialog.add_filter(filter)
	dialog.current_file = title
	dialog.popup_centered_ratio(0.8)

func _on_dialog_file_selected(path: String) -> void:
	if _mode == Mode.PICK:
		last_picked_file = path.get_file()
		_emit_selected(path)
	elif _mode == Mode.SAVE:
		var err := DirAccess.copy_absolute(_pending_save_source, path)
		if err != OK:
			_emit_save_failed(GyroLang.t("file_copy_failed"))
			return
		var cb := _save_callback
		_clear_save()
		if cb.is_valid():
			cb.call(path)
	else:
		_mode = Mode.NONE

func _on_dialog_canceled() -> void:
	if _mode == Mode.PICK:
		_emit_failed(GyroLang.t("file_pick_cancelled"))
	elif _mode == Mode.SAVE:
		_emit_save_failed(GyroLang.t("file_save_cancelled"))

func _on_file_picked(temp_path: String, mime_type: String) -> void:
	if _mode != Mode.PICK:
		return
	if temp_path == "":
		_emit_failed(GyroLang.t("file_pick_cancelled"))
		return
	var base := temp_path.get_file()
	var original := _extract_original_name(base)
	if original == "":
		original = base
	if original.get_extension() == "":
		var ext := _ext_for_mime(mime_type)
		original = (original.get_basename() + "." + ext) if ext != "" else original
	last_picked_file = original
	var stamp := int(Time.get_unix_time_from_system() * 1000.0)
	var dest := "user://imported_" + str(stamp) + "_" + original
	if DirAccess.copy_absolute(temp_path, dest) != OK:
		_emit_failed(GyroLang.t("asset_copy_failed"))
		return
	DirAccess.remove_absolute(temp_path)
	_emit_selected(dest)

func _on_file_saved(ok: bool, uri_string: String) -> void:
	if _mode != Mode.SAVE:
		return
	if not ok:
		_emit_save_failed(GyroLang.t("file_save_cancelled"))
		return
	var cb := _save_callback
	_clear_save()
	if cb.is_valid():
		cb.call(uri_string)

func _emit_selected(path: String) -> void:
	var cb := _selected_callback
	_clear_pick()
	if cb.is_valid():
		cb.call(path)

func _emit_failed(message: String) -> void:
	var cb := _failed_callback
	_clear_pick()
	if cb.is_valid():
		cb.call(message)

func _emit_save_failed(message: String) -> void:
	var cb := _save_failed_callback
	_clear_save()
	if cb.is_valid():
		cb.call(message)

func _clear_pick() -> void:
	_mode = Mode.NONE
	_selected_callback = Callable()
	_failed_callback = Callable()

func _clear_save() -> void:
	_mode = Mode.NONE
	_save_callback = Callable()
	_save_failed_callback = Callable()
	_pending_save_source = ""

static func _extract_original_name(base: String) -> String:
	var m := RegEx.create_from_string("^picked_\\d+_(.+)$").search(base)
	if m != null:
		return m.get_string(1)
	var m2 := RegEx.create_from_string("^imported_\\d+_(.+)$").search(base)
	if m2 != null:
		return m2.get_string(1)
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

func _filters_for_kind(kind: String) -> Array:
	match kind:
		"sprite": return ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.svg"]
		"sound": return ["*.mp3", "*.ogg", "*.wav"]
		"font": return ["*.ttf", "*.otf", "*.woff2"]
		"video": return ["*.mp4", "*.webm", "*.ogv"]
		"apk": return ["*.apk"]
		_: return ["*.*"]

func _exit_tree() -> void:
	if _plugin != null and _plugin_connected:
		if _plugin.is_connected("file_picked", _on_file_picked):
			_plugin.disconnect("file_picked", _on_file_picked)
		if _plugin.is_connected("file_saved", _on_file_saved):
			_plugin.disconnect("file_saved", _on_file_saved)
		_plugin_connected = false
