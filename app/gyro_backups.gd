class_name GyroBackups
extends RefCounted

const MAX_BACKUPS := 3


static func make_backup(project_path: String) -> void:
	if project_path == "":
		return
	var settings := GyroAppSettings.load_settings()
	if not settings.backups_enabled:
		return
	if settings.backup_interval_minutes == 0:
		return

	if not FileAccess.file_exists(project_path):
		return

	var base := project_path.get_basename()
	var backup_dir := base + ".backups"
	DirAccess.make_dir_recursive_absolute(backup_dir)

	var stamp := Time.get_datetime_string_from_system()
	stamp = stamp.replace(":", "-").replace("T", "_").split(".")[0]

	var dst := backup_dir + "/" + stamp + ".tres"
	if FileAccess.file_exists(dst):
		dst = backup_dir + "/" + stamp + "_" + str(Time.get_ticks_msec()) + ".tres"

	DirAccess.copy_absolute(project_path, dst)

	var files_dir := base + ".files"
	if DirAccess.dir_exists_absolute(files_dir):
		_copy_dir(files_dir, dst.get_basename() + ".files")

	_prune(backup_dir)


static func _prune(backup_dir: String) -> void:
	var dir := DirAccess.open(backup_dir)
	if dir == null:
		return

	var files := Array(dir.get_files())
	files.sort()

	while files.size() > MAX_BACKUPS:
		var old := str(files.pop_front())
		var old_path := backup_dir + "/" + old
		_remove_dir(old_path.get_basename() + ".files")
		DirAccess.remove_absolute(old_path)


static func _copy_dir(src_abs: String, dst_abs: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst_abs)

	var dir := DirAccess.open(src_abs)
	if dir == null:
		return

	for f in dir.get_files():
		DirAccess.copy_absolute(src_abs + "/" + f, dst_abs + "/" + f)

	for d in dir.get_directories():
		_copy_dir(src_abs + "/" + d, dst_abs + "/" + d)


static func _remove_dir(abs_path: String) -> void:
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return

	for f in dir.get_files():
		DirAccess.remove_absolute(abs_path + "/" + f)

	for d in dir.get_directories():
		_remove_dir(abs_path + "/" + d)

	DirAccess.remove_absolute(abs_path)

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
		if str(f).ends_with(".tres"):
			result.append(base + ".backups/" + str(f))
	return result

static func restore_backup(project_path: String, backup_path: String) -> bool:
	if not FileAccess.file_exists(backup_path):
		return false
	var base := project_path.replace("\\", "/").get_basename()
	var files_dir := base + ".files"
	var backup_files := backup_path.get_basename() + ".files"
	_delete_dir_recursive(files_dir)
	_copy_dir_recursive(backup_files, files_dir)
	var err := DirAccess.copy_absolute(backup_path, project_path)
	return err == OK

static func _delete_dir_recursive(abs_path: String) -> void:
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(abs_path + "/" + str(f))
	for d in dir.get_directories():
		_delete_dir_recursive(abs_path + "/" + str(d))
	DirAccess.remove_absolute(abs_path)

static func _copy_dir_recursive(src_abs: String, dst_abs: String) -> void:
	var dir := DirAccess.open(src_abs)
	if dir == null:
		return
	DirAccess.make_dir_recursive_absolute(dst_abs)
	for f in dir.get_files():
		DirAccess.copy_absolute(src_abs + "/" + str(f), dst_abs + "/" + str(f))
	for d in dir.get_directories():
		_copy_dir_recursive(src_abs + "/" + str(d), dst_abs + "/" + str(d))

static func make_backup_async(project_path: String) -> void:
	var settings := GyroAppSettings.load_settings()
	if not settings.backups_enabled:
		return
	if settings.backup_interval_minutes == 0:
		return
	if not FileAccess.file_exists(project_path):
		return
	var thread := Thread.new()
	thread.start(_backup_thread.bind(project_path))

static func _backup_thread(project_path: String) -> void:
	var base := project_path.get_basename()
	var backup_dir := base + ".backups"
	DirAccess.make_dir_recursive_absolute(backup_dir)
	var stamp := Time.get_datetime_string_from_system()
	stamp = stamp.replace(":", "-").replace("T", "_").split(".")[0]
	var dst := backup_dir + "/" + stamp + ".tres"
	if FileAccess.file_exists(dst):
		dst = backup_dir + "/" + stamp + "_" + str(Time.get_ticks_msec()) + ".tres"
	DirAccess.copy_absolute(project_path, dst)
	var files_dir := base + ".files"
	if DirAccess.dir_exists_absolute(files_dir):
		_copy_dir(files_dir, dst.get_basename() + ".files")
	_prune(backup_dir)
