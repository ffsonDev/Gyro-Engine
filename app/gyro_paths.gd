class_name GyroPaths
extends RefCounted

static func base_dir() -> String:
	if OS.get_name() == "Android":
		return OS.get_user_data_dir() + "/projects/"

	var home := OS.get_environment("HOME")
	if home == "":
		home = OS.get_environment("USERPROFILE")
	if home == "":
		return OS.get_user_data_dir() + "/projects/"

	return home + "/Gyroprojects/"

static func projects_dir() -> String:
	return base_dir()

static func ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(base_dir())

static func migrate_old() -> void:
	var old_dir := "user://projects/"

	var dir := DirAccess.open(old_dir)
	if dir == null:
		return

	var new_dir := base_dir()
	DirAccess.make_dir_recursive_absolute(new_dir)

	for f in dir.get_files():
		if not str(f).ends_with(".tres"):
			continue

		var src_abs := OS.get_user_data_dir() + "/projects/" + f
		var dst_abs := new_dir + f
		if not FileAccess.file_exists(dst_abs):
			DirAccess.copy_absolute(src_abs, dst_abs)

		var old_files := OS.get_user_data_dir() + "/projects/" + f.get_basename() + ".files"
		var new_files := new_dir + f.get_basename() + ".files"

		var old_files_dir := DirAccess.open(old_files)
		var new_files_dir := DirAccess.open(new_files)
		if old_files_dir != null and new_files_dir == null:
			_copy_dir(old_files, new_files)

static func _copy_dir(src_abs: String, dst_abs: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst_abs)

	var dir := DirAccess.open(src_abs)
	if dir == null:
		return

	for f in dir.get_files():
		DirAccess.copy_absolute(src_abs + "/" + f, dst_abs + "/" + f)
	for d in dir.get_directories():
		_copy_dir(src_abs + "/" + d, dst_abs + "/" + d)
