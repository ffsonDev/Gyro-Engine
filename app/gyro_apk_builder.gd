class_name GyroApkBuilder
extends RefCounted

signal progress_changed(value: float, stage: String)
signal log_added(text: String)
signal build_finished(success: bool, error: String, output_path: String)

const TEMPLATE_PATH := "res://apk_template/android_release.apk"
const CANCELLED := "__cancelled__"

var _thread: Thread = null
var _cancel_mutex := Mutex.new()
var _cancel := false

const DEBUG_KEYSTORE_PATH := "res://build/android_debug.p12"
const DEBUG_KEYSTORE_ALIAS := "androiddebugkey"
const DEBUG_KEYSTORE_PASSWORD := "android"
const DEBUG_KEYSTORE_USER_PATH := "user://keystore/debug.p12"

func is_running() -> bool:
	return _thread != null and _thread.is_alive()

func cancel() -> void:
	_cancel_mutex.lock()
	_cancel = true
	_cancel_mutex.unlock()

func _is_cancelled() -> bool:
	_cancel_mutex.lock()
	var val := _cancel
	_cancel_mutex.unlock()
	return val

func wait_finish() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null

func start(project: GyroProject, project_path: String, out_path: String) -> void:
	if is_running():
		return
	if not GyroLang.is_loaded:
		GyroLang.load_lang()
	var strings_snapshot := GyroLang.strings.duplicate()
	var st = project.settings
	
	var _ks = st.get("keystore_path")
	var _alias = st.get("keystore_alias")
	var _ks_pass_raw = st.get("keystore_password")
	var _key_pass_raw = st.get("key_password")
	
	var ks: String = str(_ks) if _ks != null else ""
	var alias: String = str(_alias) if _alias != null else ""
	var ks_pass: String = str(_ks_pass_raw) if _ks_pass_raw != null else ""
	var key_pass: String = str(_key_pass_raw) if _key_pass_raw != null and str(_key_pass_raw) != "" else ks_pass
	
	var _debug_ks_path = st.get("debug_ks_path")
	var _debug_ks_alias = st.get("debug_ks_alias")
	var _debug_ks_password = st.get("debug_ks_password")
	var _debug_key_password = st.get("debug_key_password")
	
	var _compress_tex = st.get("compress_textures")
	var _perms = st.get("permissions")
	var _icon_path = st.get("icon_path")
	var _splash_path = st.get("splash_path")
	var _package_name = st.get("package_name")
	var _app_name = st.get("app_name")
	var _version_name = st.get("version_name")
	var _version_code = st.get("version_code")
	
	var build_data = {
		"is_release": st.build_release_version,
		"ks": ks,
		"alias": alias,
		"ks_pass": ks_pass,
		"key_pass": key_pass,
		"debug_ks_path": str(_debug_ks_path) if _debug_ks_path != null else "",
		"debug_ks_alias": str(_debug_ks_alias) if _debug_ks_alias != null else "",
		"debug_ks_password": str(_debug_ks_password) if _debug_ks_password != null else "",
		"debug_key_password": str(_debug_key_password) if _debug_key_password != null else "",
		"compress_textures": true if _compress_tex == null else bool(_compress_tex),
		"permissions": PackedStringArray(_perms) if _perms != null else PackedStringArray(),
		"icon_path": str(_icon_path) if _icon_path != null else "",
		"splash_path": str(_splash_path) if _splash_path != null else "",
		"package_name": str(_package_name) if _package_name != null else "",
		"app_name": str(_app_name) if _app_name != null else "",
		"version_name": str(_version_name) if _version_name != null else "",
		"version_code": int(_version_code) if _version_code != null else 1
	}
	
	var safe_dict = GyroProjectJSON.project_to_dict(project, false)
	var project_json = JSON.stringify(safe_dict)
	
	var assets_data = []
	for v in project.assets:
		var a = v as GyroAsset
		if a != null and not a.path.begins_with("res://") and not a.path.begins_with("user://"):
			var src = GyroAssetPaths.resolve_asset_path(a.path, project_path)
			if FileAccess.file_exists(src):
				var has_gtx := FileAccess.file_exists(src + ".gtx")
				assets_data.append({"src": ProjectSettings.globalize_path(src), "name": "assets/gyro_data/files/" + a.path, "kind": a.kind, "has_gtx": has_gtx})
				if has_gtx:
					assets_data.append({"src": ProjectSettings.globalize_path(src + ".gtx"), "name": "assets/gyro_data/files/" + a.path + ".gtx", "kind": "gtx", "has_gtx": true})
	_cancel_mutex.lock()
	_cancel = false
	_cancel_mutex.unlock()
	_thread = Thread.new()
	_thread.start(_thread_main.bind(project_path, out_path, build_data, project_json, assets_data, strings_snapshot))

func _thread_main(project_path: String, out_path: String, build_data: Dictionary, project_json: String, assets_data: Array, strings: Dictionary) -> void:
	var err = _run(project_path, out_path, build_data, project_json, assets_data, strings)
	call_deferred("_emit_finished", err == "", err, out_path)

func _t(strings: Dictionary, key: String) -> String:
	var v = strings.get(key, null)
	return v if v is String else key

func _run(project_path: String, out_path: String, build_data: Dictionary, project_json: String, assets_data: Array, strings: Dictionary) -> String:
	if OS.get_name() != "Android":
		return _t(strings, "apk_build_android_only")
		
	var is_release: bool = build_data.is_release
	var ks: String = build_data.ks
	var alias: String = build_data.alias
	var ks_pass: String = build_data.ks_pass
	var key_pass: String = build_data.key_pass
	
	if not is_release:
		var debug_ks_exists := false
		if build_data.debug_ks_path != "":
			var resolved: String = build_data.debug_ks_path
			if resolved.begins_with("res://"):
				resolved = ProjectSettings.globalize_path(resolved)
			debug_ks_exists = FileAccess.file_exists(resolved)
		if debug_ks_exists:
			ks = ProjectSettings.globalize_path(build_data.debug_ks_path) if build_data.debug_ks_path.begins_with("res://") else build_data.debug_ks_path
			alias = build_data.debug_ks_alias
			ks_pass = build_data.debug_ks_password
			var debug_key_pass_raw = build_data.debug_key_password
			key_pass = str(debug_key_pass_raw) if str(debug_key_pass_raw) != "" else ks_pass
		else:
			var extracted := _ensure_debug_keystore()
			if extracted == "":
				return _t(strings, "keystore_not_found")
			ks = extracted
			alias = DEBUG_KEYSTORE_ALIAS
			ks_pass = DEBUG_KEYSTORE_PASSWORD
			key_pass = DEBUG_KEYSTORE_PASSWORD
			
	if ks == "" or alias == "" or ks_pass == "":
		return _t(strings, "keystore_credentials_missing")
	if not FileAccess.file_exists(ks):
		return _t(strings, "keystore_not_found")
		
	var tpl = "user://_build_template.apk"
	var terr = _ensure_template(tpl, strings)
	if terr != "":
		return terr
		
	var asset_paths = PackedStringArray()
	var asset_names = PackedStringArray()
	for item in assets_data:
		asset_paths.append(item.src)
		asset_names.append(item.name)
	if bool(build_data.get("compress_textures", false)):
		_remove_dir(ProjectSettings.globalize_path("user://_build_gtx"))
		DirAccess.make_dir_recursive_absolute("user://_build_gtx/")
		var gi := 0
		for item in assets_data:
			if str(item.get("kind", "")) != "sprite" or bool(item.get("has_gtx", false)):
				continue
			if str(item.src).get_extension().to_lower() == "svg":
				continue
			var tmp := "user://_build_gtx/%d.gtx" % gi
			gi += 1
			if GyroTextureCodec.build_gtx_file(str(item.src), tmp):
				asset_paths.append(ProjectSettings.globalize_path(tmp))
				asset_names.append(str(item.name) + ".gtx")
		
	var perms = build_data.permissions
		
	var icon_path = ""
	if build_data.icon_path != "":
		var resolved_icon = GyroAssetPaths.resolve_asset_path(build_data.icon_path, project_path)
		if not FileAccess.file_exists(resolved_icon):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(tpl))
			return _t(strings, "icon_not_found") + build_data.icon_path
		if resolved_icon.get_extension().to_lower() == "svg":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(tpl))
			return _t(strings, "svg_icon_error")
		icon_path = ProjectSettings.globalize_path(resolved_icon)
		
	var splash_path = ""
	var splash_ref := str(build_data.splash_path)
	if splash_ref == "" and icon_path != "":
		splash_path = icon_path
	elif splash_ref != "":
		var resolved_splash = GyroAssetPaths.resolve_asset_path(splash_ref, project_path)
		if FileAccess.file_exists(resolved_splash) and resolved_splash.get_extension().to_lower() != "svg":
			splash_path = ProjectSettings.globalize_path(resolved_splash)
			
	var pkg = build_data.package_name if build_data.package_name != "" else "com.gyro.game"
	var label = build_data.app_name if build_data.app_name != "" else "Gyro Game"
	var vname = build_data.version_name if build_data.version_name != "" else "1.0.0"
	var vcode = maxi(1, build_data.version_code)
	var work_dir = out_path + ".work"
	var global_out = ProjectSettings.globalize_path(out_path)
	var global_tpl = ProjectSettings.globalize_path(tpl)
	var global_ks = ProjectSettings.globalize_path(ks)

	var Helper = JavaClassWrapper.wrap("com.godot.game.ApkBuilderHelper")
	if Helper == null:
		_cleanup(tpl, work_dir)
		return _t(strings, "file_picker_plugin_missing")

	_log(_t(strings, "build_stage_validate"))
	call_deferred("_emit_progress", 0.05, "validate")
	var res = Helper.validate(global_tpl, global_out, pkg, label, vname, vcode, global_ks, alias, ks_pass, key_pass, icon_path, splash_path)
	var err = "" if res == null else str(res)
	if err != "":
		_cleanup(tpl, work_dir)
		return _smart_error(err, strings)
	if _is_cancelled():
		_cleanup(tpl, work_dir)
		return CANCELLED

	_log(_t(strings, "build_stage_compile"))
	call_deferred("_emit_progress", 0.25, "compile")
	res = Helper.compile(global_tpl, ProjectSettings.globalize_path(work_dir), pkg, label, icon_path, splash_path)
	err = "" if res == null else str(res)
	if err != "":
		_cleanup(tpl, work_dir)
		return _smart_error(err, strings)
	if _is_cancelled():
		_cleanup(tpl, work_dir)
		return CANCELLED

	_log(_t(strings, "build_stage_link"))
	call_deferred("_emit_progress", 0.55, "link")
	res = Helper.link(global_tpl, ProjectSettings.globalize_path(work_dir), global_out, pkg, label, vname, vcode, perms, project_json, asset_paths, asset_names)
	err = "" if res == null else str(res)
	if err != "":
		_cleanup(tpl, work_dir)
		return _smart_error(err, strings)
	if _is_cancelled():
		_cleanup(tpl, work_dir)
		return CANCELLED

	_log(_t(strings, "build_stage_sign"))
	call_deferred("_emit_progress", 0.85, "sign")
	res = Helper.sign(global_out, global_ks, alias, ks_pass, key_pass)
	err = "" if res == null else str(res)
	if err != "":
		_cleanup(tpl, work_dir)
		return _smart_error(err, strings)

	call_deferred("_emit_progress", 1.0, "done")
	_cleanup(tpl, work_dir)
	return ""

func _ensure_template(dest: String, strings: Dictionary) -> String:
	var src = FileAccess.open(TEMPLATE_PATH, FileAccess.READ)
	if src == null:
		return _t(strings, "apk_template_not_found")
	var header = src.get_buffer(4)
	if header.size() < 4 or header[0] != 0x50 or header[1] != 0x4B or header[2] != 0x03 or header[3] != 0x04:
		src.close()
		return _t(strings, "build_template_corrupt")
	src.seek(0)
	var dst = FileAccess.open(dest, FileAccess.WRITE)
	if dst == null:
		src.close()
		return _t(strings, "temp_template_create_failed")
	while true:
		var buf = src.get_buffer(1024 * 1024)
		if buf.is_empty():
			break
		dst.store_buffer(buf)
	src.close()
	dst.close()
	return ""

func _ensure_debug_keystore() -> String:
	var src := FileAccess.open(DEBUG_KEYSTORE_PATH, FileAccess.READ)
	if src == null:
		return ""
	DirAccess.make_dir_recursive_absolute("user://keystore/")
	var dst := FileAccess.open(DEBUG_KEYSTORE_USER_PATH, FileAccess.WRITE)
	if dst == null:
		src.close()
		return ""
	while true:
		var buf := src.get_buffer(1024 * 1024)
		if buf.is_empty():
			break
		dst.store_buffer(buf)
	src.close()
	dst.close()
	return ProjectSettings.globalize_path(DEBUG_KEYSTORE_USER_PATH)

func _cleanup(tpl: String, work_dir: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tpl))
	_remove_dir(ProjectSettings.globalize_path(work_dir))

func _remove_dir(abs_path: String) -> void:
	var dir = DirAccess.open(abs_path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(abs_path + "/" + str(f))
	for d in dir.get_directories():
		_remove_dir(abs_path + "/" + str(d))
	DirAccess.remove_absolute(abs_path)

func _log(text: String) -> void:
	log_added.emit(text)

func _emit_progress(val: float, stage: String) -> void:
	progress_changed.emit(val, stage)

func _emit_finished(success: bool, err: String, out_path: String) -> void:
	build_finished.emit(success, err, out_path)

func _smart_error(raw: String, strings: Dictionary) -> String:
	var parts = raw.split("|")
	if parts.size() < 3:
		return _t(strings, "build_error") + raw
	var code = parts[1]
	var detail = parts[2]
	var key = "build_err_" + code.to_lower()
	var localized = _t(strings, key)
	if localized != key:
		return localized
	return _t(strings, "build_error") + detail
