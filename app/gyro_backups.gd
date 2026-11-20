class_name GyroBackups
extends RefCounted

const MAX_BACKUPS := 3

class _Worker extends RefCounted:
	var thread: Thread
	var on_done: Callable
	var project_path := ""
	var force := false
	var settings: GyroAppSettings

	func run() -> void:
		var ok := GyroBackups._make_backup(project_path, force, settings)
		call_deferred("_finish", ok)

	func _finish(ok: bool) -> void:
		if thread != null and thread.is_started():
			thread.wait_to_finish()
		GyroBackups._worker = null
		if on_done.is_valid():
			on_done.call(ok)

static var _worker: _Worker = null

static func make_backup(project_path: String) -> bool:
	return _make_backup(project_path, false, GyroAppSettings.load_settings())

static func make_backup_force(project_path: String) -> bool:
	return _make_backup(project_path, true, GyroAppSettings.load_settings())

static func make_backup_async(project_path: String, force := true, on_done := Callable()) -> void:
	if _worker != null:
		if on_done.is_valid():
			on_done.call_deferred(false)
		return
	var w := _Worker.new()
	w.project_path = project_path
	w.force = force
	w.settings = GyroAppSettings.load_settings()
	w.on_done = on_done
	w.thread = Thread.new()
	_worker = w
	w.thread.start(w.run)

static func _make_backup(project_path: String, force: bool, settings: GyroAppSettings = null) -> bool:
	if project_path == "":
		return false
	if not FileAccess.file_exists(project_path):
		return false
	var now := Time.get_unix_time_from_system()
	if not force:
		if settings == null:
			settings = GyroAppSettings.load_settings()
		if not settings.backups_enabled:
			return false
		if settings.backup_interval_minutes == 0:
			return false
		var last_time := _get_last_backup_time(project_path)
		if now - last_time < float(settings.backup_interval_minutes) * 60.0:
			return false
		if not _changed_since(project_path, last_time):
			return false
	var base := project_path.get_basename()
	var backup_dir := base + ".backups"
	if DirAccess.make_dir_recursive_absolute(backup_dir) != OK:
		return false
	var dst := backup_dir + "/" + _stamp() + ".json"
	if FileAccess.file_exists(dst):
		dst = backup_dir + "/" + _stamp() + "_" + str(Time.get_ticks_msec()) + ".json"
	if DirAccess.copy_absolute(project_path, dst) != OK:
		return false
	if not _is_valid_project_json(dst):
		DirAccess.remove_absolute(dst)
		return false
	var files_dir := base + ".files"
	if DirAccess.dir_exists_absolute(files_dir):
		_copy_dir(files_dir, dst.get_basename() + ".files")
	_set_last_backup_time(project_path, now)
	_prune(backup_dir)
	return true

static func _changed_since(project_path: String, last_time: float) -> bool:
	return FileAccess.get_modified_time(project_path) > last_time

static func _stamp() -> String:
	var s := Time.get_datetime_string_from_system()
	return s.replace(":", "-").replace("T", "_").split(".")[0]

static func _is_valid_project_json(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() == 0:
		return false
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	return json.parse(text) == OK and json.data is Dictionary

static func restore_backup(project_path: String, backup_path: String) -> bool:
	if not FileAccess.file_exists(backup_path):
		return false
	if not _is_valid_project_json(backup_path):
		return false
	var base := project_path.get_basename()
	var files_dir := base + ".files"
	var backup_files := backup_path.get_basename() + ".files"
	var trash := base + ".files_restoring"
	if DirAccess.dir_exists_absolute(trash):
		_remove_dir(trash)
	var had_files := DirAccess.dir_exists_absolute(files_dir)
	if had_files:
		if DirAccess.rename_absolute(files_dir, trash) != OK:
			return false
	if DirAccess.dir_exists_absolute(backup_files):
		_copy_dir(backup_files, files_dir)
	if DirAccess.copy_absolute(backup_path, project_path) != OK:
		if had_files and not DirAccess.dir_exists_absolute(files_dir):
			DirAccess.rename_absolute(trash, files_dir)
		return false
	if DirAccess.dir_exists_absolute(trash):
		_remove_dir(trash)
	return true

static func list_backups(project_path: String) -> Array:
	var base := project_path.replace("\\", "/").get_basename()
	var dir := DirAccess.open(base + ".backups")
	var result: Array = []
	if dir == null:
		return result
	var files: Array = dir.get_files()
	files.sort()
	files.reverse()
	for f in files:
		var name := str(f)
		if name.ends_with(".json") and not name.begins_with("."):
			result.append(base + ".backups/" + name)
	return result

static func backup_info(backup_path: String) -> Dictionary:
	var size := 0
	var f := FileAccess.open(backup_path, FileAccess.READ)
	if f != null:
		size = f.get_length()
		f.close()
	size += _dir_size(backup_path.get_basename() + ".files")
	return {
		"name": backup_path.get_file().get_basename(),
		"size": size,
		"time": FileAccess.get_modified_time(backup_path),
	}

static func _dir_size(dir_path: String) -> int:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	var total := 0
	for fn in dir.get_files():
		var f := FileAccess.open(dir_path + "/" + str(fn), FileAccess.READ)
		if f != null:
			total += int(f.get_length())
			f.close()
	for dn in dir.get_directories():
		total += _dir_size(dir_path + "/" + str(dn))
	return total

static func _get_last_backup_time(project_path: String) -> float:
	var f := FileAccess.open(project_path.get_basename() + ".backups/.last_backup_time", FileAccess.READ)
	if f == null:
		return 0.0
	var text := f.get_as_text().strip_edges()
	f.close()
	return float(text) if text != "" else 0.0

static func _set_last_backup_time(project_path: String, time: float) -> void:
	var backup_dir := project_path.get_basename() + ".backups"
	DirAccess.make_dir_recursive_absolute(backup_dir)
	var f := FileAccess.open(backup_dir + "/.last_backup_time", FileAccess.WRITE)
	if f != null:
		f.store_string(str(time))
		f.close()

static func _prune(backup_dir: String) -> void:
	var dir := DirAccess.open(backup_dir)
	if dir == null:
		return
	var files: Array = []
	for f in dir.get_files():
		if str(f).ends_with(".json"):
			files.append(str(f))
	files.sort()
	while files.size() > MAX_BACKUPS:
		var old: String = files.pop_front()
		var old_path := backup_dir + "/" + old
		_remove_dir(old_path.get_basename() + ".files")
		DirAccess.remove_absolute(old_path)

static func _copy_dir(src_abs: String, dst_abs: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst_abs)
	var dir := DirAccess.open(src_abs)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.copy_absolute(src_abs + "/" + str(f), dst_abs + "/" + str(f))
	for d in dir.get_directories():
		_copy_dir(src_abs + "/" + str(d), dst_abs + "/" + str(d))

static func _remove_dir(abs_path: String) -> void:
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(abs_path + "/" + str(f))
	for d in dir.get_directories():
		_remove_dir(abs_path + "/" + str(d))
	DirAccess.remove_absolute(abs_path)
