class_name GyroApkBuilder
extends RefCounted

const TEMPLATE_PATH := "res://apk_template/android_release.apk"

static func build_project(project: GyroProject, project_path: String, out_path: String) -> String:
	if OS.get_name() != "Android":
		return GyroLang.t("build_not_android")
	var st := project.settings
	if st == null:
		return GyroLang.t("keystore_no_settings")
	if st.keystore_alias == "" or st.keystore_password == "":
		return GyroLang.t("keystore_no_alias")
	var ks := st.keystore_path
	if ks == "" or not FileAccess.file_exists(ks):
		if FileAccess.file_exists("user://keystore/release.p12"):
			ks = "user://keystore/release.p12"
		else:
			return GyroLang.t("keystore_not_found")
	var tpl := "user://_build_template.apk"
	var terr := _ensure_template(tpl)
	if terr != "":
		return terr
	
	var asset_paths := PackedStringArray()
	var asset_names := PackedStringArray()
	
	for v in project.assets:
		var a := v as GyroAsset
		if a == null or a.path.begins_with("res://") or a.path.begins_with("user://"):
			continue
		var src := GyroAssetPaths.resolve_asset_path(a.path, project_path)
		if FileAccess.file_exists(src):
			asset_paths.append(ProjectSettings.globalize_path(src))
			asset_names.append("assets/gyro_data/files/" + a.path)
	
	var Helper = JavaClassWrapper.wrap("com.godot.game.ApkBuilderHelper")
	if Helper == null:
		return GyroLang.t("build_helper_missing")
	
	var perms := PackedStringArray(st.permissions)
	if not perms.has("android.permission.INTERNET"):
		perms.append("android.permission.INTERNET")
	
	var icon_path := ""
	if st.icon_path != "":
		var resolved := GyroAssetPaths.resolve_asset_path(st.icon_path, project_path)
		if not FileAccess.file_exists(resolved):
			return GyroLang.t("build_icon_missing") % st.icon_path
		if resolved.get_extension().to_lower() == "svg":
			return GyroLang.t("build_icon_svg")
		
	var splash_path := icon_path
	if st.splash_path != "":
		var resolved := GyroAssetPaths.resolve_asset_path(st.splash_path, project_path)
		if FileAccess.file_exists(resolved):
			splash_path = ProjectSettings.globalize_path(resolved)


	var res = Helper.buildApk(
		ProjectSettings.globalize_path(tpl),
		ProjectSettings.globalize_path(out_path),
		st.package_name if st.package_name != "" else "com.gyro.game",
		st.app_name if st.app_name != "" else "Gyro Game",
		st.version_name if st.version_name != "" else "1.0.0",
		maxi(1, st.version_code),
		perms,
		JSON.stringify(_project_to_dict(project)),
		asset_paths,
		asset_names,
		ProjectSettings.globalize_path(ks),
		st.keystore_alias,
		st.keystore_password,
		st.keystore_password,
		icon_path,
		splash_path
		)
	
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tpl))
	
	var msg := "" if res == null else str(res)
	if msg != "":
		return GyroLang.t("build_error") % msg
	
	return ""

static func _ensure_template(dest: String) -> String:
	var src := FileAccess.open(TEMPLATE_PATH, FileAccess.READ)
	if src == null:
		return GyroLang.t("build_template_missing")
	var dst := FileAccess.open(dest, FileAccess.WRITE)
	if dst == null:
		return GyroLang.t("build_temp_failed")
	while true:
		var buf := src.get_buffer(1024 * 1024)
		if buf.is_empty():
			break
		dst.store_buffer(buf)
	return ""

static func _project_to_dict(project: GyroProject) -> Dictionary:
	return GyroProjectJSON.project_to_dict(project, false)
