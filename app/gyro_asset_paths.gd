class_name GyroAssetPaths
extends RefCounted


static func files_base_for_project(project_path: String) -> String:
	var p := project_path.replace("\\", "/")
	if p == "":
		return ""

	return p.get_basename() + ".files/"


static func normalize_asset_path(path: String, project_path: String) -> String:
	var p := path.replace("\\", "/")
	if p == "":
		return ""

	if p.begins_with("res://") or p.begins_with("user://"):
		return p

	var files_base := files_base_for_project(project_path)
	if files_base != "" and p.begins_with(files_base):
		return p.substr(files_base.length())

	var marker := ".files/"
	var idx := p.find(marker)
	if idx != -1:
		return p.substr(idx + marker.length())

	return p


static func resolve_asset_path(stored_path: String, project_path: String) -> String:
	var p := stored_path.replace("\\", "/")
	if p == "":
		return ""

	if p.begins_with("res://") or p.begins_with("user://"):
		return p

	if p.is_absolute_path():
		return p

	if p.begins_with(".files/"):
		p = p.substr(7)

	var files_base := files_base_for_project(project_path)
	if files_base == "":
		return p

	return files_base + p


static func make_unique_file_name(dir_abs: String, desired: String) -> String:
	var dir := dir_abs.replace("\\", "/")
	if not dir.ends_with("/"):
		dir += "/"

	var file_name := desired.replace("\\", "/").get_file()
	if file_name == "":
		file_name = "asset"

	var base := file_name.get_basename()
	var ext := file_name.get_extension()

	if base == "":
		base = "asset"

	var candidate := file_name
	var i := 1

	while FileAccess.file_exists(dir + candidate):
		if ext == "":
			candidate = base + "_" + str(i)
		else:
			candidate = base + "_" + str(i) + "." + ext
		i += 1

	return candidate


static func migrate_project(project: GyroProject, project_path: String) -> bool:
	if project == null:
		return false

	var changed := false

	for v in project.assets:
		var a := v as GyroAsset
		if a == null:
			continue

		var normalized := normalize_asset_path(a.path, project_path)
		if normalized != a.path:
			a.path = normalized
			changed = true

	return changed
