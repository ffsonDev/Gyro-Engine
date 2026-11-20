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
