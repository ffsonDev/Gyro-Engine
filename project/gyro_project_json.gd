class_name GyroProjectJSON
extends RefCounted

static func project_to_dict(p: GyroProject, include_secrets: bool = true, include_custom: bool = true) -> Dictionary:
	var scripts: Array = []
	for s in p.scripts:
		if s == null:
			continue
		scripts.append({
			"script_name": s.script_name,
			"folder": s.folder,
			"disabled": s.disabled,
			"is_code": s.is_code,
			"code": s.code,
			"blueprint": blueprint_to_dict(s.blueprint)
		})
	var assets: Array = []
	for a in p.assets:
		if a == null:
			continue
		assets.append({
			"kind": a.kind,
			"asset_name": a.asset_name,
			"path": a.path,
			"folder": a.folder,
			"id": a.id,
			"hitbox_polygons": a.hitbox_polygons.duplicate(true),
			"atlas_slices": a.atlas_slices.duplicate(true)
		})
	var st := p.settings
	return {
		"format_version": p.format_version,
		"last_modified": p.last_modified,
		"scripts": scripts,
		"folders": p.folders.duplicate(),
		"asset_folders": p.asset_folders.duplicate(),
		"assets": assets,
		"custom_packs": GyroCustomRegistry.packs_to_dict(p.custom_packs) if include_custom else [],
		"custom_blocks": GyroCustomRegistry.blocks_to_dict(p.custom_blocks) if include_custom else [],
		"custom_functions": GyroFunctions.to_array(GyroFunctions.items()) if include_custom else [],		"settings": {
			"app_name": st.app_name if st else "",
			"package_name": st.package_name if st else "",
			"orientation": st.orientation if st else "auto",
			"icon_path": st.icon_path if st else "",
			"version_code": st.version_code if st else 1,
			"version_name": st.version_name if st else "1.0.0",
			"permissions": st.permissions.duplicate() if st else [],
			"compress_textures": st.compress_textures if st else true,
			"build_release_version": st.build_release_version if st else false,
			"splash_path": st.splash_path if st else "",
			"keystore_path": (st.keystore_path if st else "") if include_secrets else "",
			"keystore_alias": (st.keystore_alias if st else "") if include_secrets else "",
			"keystore_password": GyroSecrets.encrypt(st.keystore_password) if st and include_secrets else "",
			"debug_ks_path": (st.debug_ks_path if st else "") if include_secrets else "",
			"debug_ks_alias": (st.debug_ks_alias if st else "") if include_secrets else "",
			"debug_ks_password": GyroSecrets.encrypt(st.debug_ks_password) if st and include_secrets else "",
		}
	}

static func blueprint_to_dict(bp: GyroEventBlueprint) -> Dictionary:
	if bp == null:
		return {}
	var rules: Array = []
	for r in bp.rules:
		if r == null:
			continue
		var conds: Array = []
		for c in r.conditions:
			if c == null:
				continue
			conds.append({"type": c.type, "data": c.data.duplicate(true), "disabled": c.disabled})
		var acts: Array = []
		for a in r.actions:
			if a == null:
				continue
			acts.append({"type": a.type, "data": a.data.duplicate(true), "disabled": a.disabled})
		rules.append({
			"event_type": r.event_type,
			"event_name": r.event_name,
			"note": r.note,
			"conditions": conds,
			"actions": acts,
			"disabled": r.disabled,
			"event_filter": r.event_filter
		})
	var timers: Array = []
	for t in bp.timers:
		if t == null:
			continue
		timers.append({"timer_name": t.timer_name, "wait_time": t.wait_time, "one_shot": t.one_shot, "autostart": t.autostart})
	return {
		"rules": rules,
		"variables": bp.variables.duplicate(true),
		"variable_types": bp.variable_types.duplicate(true),
		"tables": bp.tables.duplicate(true),
		"timers": timers,
	}

static func dict_to_project(d: Dictionary) -> GyroProject:
	var version := int(d.get("format_version", 0))
	if version == 0:
		push_error("GyroProjectJSON: missing or zero format_version")
		return null
	if version > GyroProject.FORMAT_VERSION:
		push_warning("GyroProjectJSON: format %d > supported %d" % [version, GyroProject.FORMAT_VERSION])
	var p := GyroProject.new()
	p.format_version = version
	p.last_modified = float(d.get("last_modified", 0.0))
	var scripts_raw = d.get("scripts", [])
	if scripts_raw is Array:
		for sv in scripts_raw:
			if not (sv is Dictionary):
				continue
			var s := GyroScript.new()
			s.script_name = str(sv.get("script_name", "Script")).strip_edges()
			if s.script_name == "":
				s.script_name = "Script"
			s.folder = str(sv.get("folder", ""))
			s.disabled = bool(sv.get("disabled", false))
			s.is_code = bool(sv.get("is_code", false))
			s.code = str(sv.get("code", ""))
			var bp_data = sv.get("blueprint", {})
			if bp_data is Dictionary:
				s.blueprint = dict_to_blueprint(bp_data)
			else:
				s.blueprint = GyroEventBlueprint.new()
			p.scripts.append(s)
	var folders_raw = d.get("folders", [])
	if folders_raw is Array:
		var folders_arr: Array[String] = []
		for f in folders_raw:
			var fs := str(f)
			if fs != "":
				folders_arr.append(fs)
		p.folders = folders_arr
	var af_raw = d.get("asset_folders", [])
	if af_raw is Array:
		var af_arr: Array[String] = []
		for f in af_raw:
			var fs := str(f)
			if fs != "":
				af_arr.append(fs)
		p.asset_folders = af_arr
	var assets_raw = d.get("assets", [])
	if assets_raw is Array:
		for av in assets_raw:
			if not (av is Dictionary):
				continue
			var a := GyroAsset.new()
			a.kind = str(av.get("kind", "other"))
			a.asset_name = str(av.get("asset_name", "asset")).strip_edges()
			if a.asset_name == "":
				a.asset_name = "asset"
			a.path = str(av.get("path", ""))
			a.folder = str(av.get("folder", ""))
			a.id = str(av.get("id", ""))
			var hp = av.get("hitbox_polygons", [])
			a.hitbox_polygons = (hp as Array).duplicate(true) if hp is Array else []
			var slices = av.get("atlas_slices", [])
			a.atlas_slices = (slices as Array).duplicate(true) if slices is Array else []
			p.assets.append(a)
	p.custom_packs = GyroCustomRegistry.dict_to_packs(d.get("custom_packs", []))
	p.custom_blocks = GyroCustomRegistry.dict_to_blocks(d.get("custom_blocks", []))
	var st := GyroProjectSettings.new()
	var sd_raw = d.get("settings", {})
	var sd: Dictionary = sd_raw if sd_raw is Dictionary else {}
	st.app_name = str(sd.get("app_name", ""))
	st.package_name = str(sd.get("package_name", ""))
	st.orientation = str(sd.get("orientation", "auto"))
	if not ["auto", "portrait", "landscape"].has(st.orientation):
		st.orientation = "auto"
	st.icon_path = str(sd.get("icon_path", ""))
	st.version_code = maxi(1, int(sd.get("version_code", 1)))
	st.version_name = str(sd.get("version_name", "1.0.0"))
	var perms_raw = sd.get("permissions", [])
	if perms_raw is Array:
		var perms_arr: Array[String] = []
		for perm in perms_raw:
			var ps := str(perm)
			if ps != "":
				perms_arr.append(ps)
		st.permissions = perms_arr
	st.compress_textures = bool(sd.get("compress_textures", true))
	st.build_release_version = bool(sd.get("build_release_version", false))
	st.splash_path = str(sd.get("splash_path", ""))
	st.keystore_path = str(sd.get("keystore_path", ""))
	st.keystore_alias = str(sd.get("keystore_alias", ""))
	st.keystore_password = GyroSecrets.decrypt(str(sd.get("keystore_password", "")))
	st.debug_ks_path = str(sd.get("debug_ks_path", GyroApkBuilder.DEBUG_KEYSTORE_PATH))
	st.debug_ks_alias = str(sd.get("debug_ks_alias", GyroApkBuilder.DEBUG_KEYSTORE_ALIAS))
	st.debug_ks_password = GyroSecrets.decrypt(str(sd.get("debug_ks_password", GyroApkBuilder.DEBUG_KEYSTORE_PASSWORD)))
	p.settings = st
	return p

static func dict_to_blueprint(d: Dictionary) -> GyroEventBlueprint:
	var bp := GyroEventBlueprint.new()
	var rules_raw = d.get("rules", [])
	if rules_raw is Array:
		for rv in rules_raw:
			if not (rv is Dictionary):
				continue
			var r := GyroEventRule.new()
			r.event_type = str(rv.get("event_type", "ready"))
			r.event_name = str(rv.get("event_name", ""))
			r.note = str(rv.get("note", ""))
			r.disabled = bool(rv.get("disabled", false))
			r.event_filter = str(rv.get("event_filter", ""))
			var conds_raw = rv.get("conditions", [])
			if conds_raw is Array:
				for cv in conds_raw:
					if not (cv is Dictionary):
						continue
					var c := GyroCondition.new()
					c.type = str(cv.get("type", ""))
					var cd = cv.get("data", {})
					c.data = (cd as Dictionary).duplicate(true) if cd is Dictionary else {}
					c.disabled = bool(cv.get("disabled", false))
					r.conditions.append(c)
			var acts_raw = rv.get("actions", [])
			if acts_raw is Array:
				for av in acts_raw:
					if not (av is Dictionary):
						continue
					var a := GyroAction.new()
					a.type = str(av.get("type", ""))
					var ad = av.get("data", {})
					a.data = (ad as Dictionary).duplicate(true) if ad is Dictionary else {}
					a.disabled = bool(av.get("disabled", false))
					GyroBlocks.normalize_action_data(a.type, a.data)
					r.actions.append(a)
			bp.rules.append(r)
	var vars_raw = d.get("variables", {})
	if vars_raw is Dictionary:
		var types_raw = d.get("variable_types", {})
		var types: Dictionary = types_raw if types_raw is Dictionary else {}
		for key in vars_raw.keys():
			if str(types.get(key, "")) == "table":
				bp.tables[key] = (vars_raw[key] as Dictionary).duplicate(true) if vars_raw[key] is Dictionary else {}
			else:
				bp.variables[key] = vars_raw[key]
	var tables_raw = d.get("tables", {})
	if tables_raw is Dictionary:
		for key in tables_raw.keys():
			bp.tables[key] = tables_raw[key]
	var timers_raw = d.get("timers", [])
	if timers_raw is Array:
		for tv in timers_raw:
			if not (tv is Dictionary):
				continue
			var t := GyroTimerConfig.new()
			t.timer_name = str(tv.get("timer_name", ""))
			t.wait_time = float(tv.get("wait_time", 1.0))
			t.one_shot = bool(tv.get("one_shot", false))
			t.autostart = bool(tv.get("autostart", true))
			bp.timers.append(t)
	bp.migrate_event_names()
	return bp

static func save_to_file(project: GyroProject, path: String, include_custom: bool = false) -> bool:
	if project == null or path == "":
		return false
	GyroGlobalBlocks.sync_from(project)
	var json_string := JSON.stringify(project_to_dict(project, true, include_custom), "  ")
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(json_string)
	file.flush()
	var write_err := file.get_error()
	file.close()
	if write_err != OK:
		DirAccess.remove_absolute(tmp_path)
		return false
	var rename_err := DirAccess.rename_absolute(tmp_path, path)
	if rename_err != OK and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		rename_err = DirAccess.rename_absolute(tmp_path, path)
	if rename_err != OK:
		DirAccess.remove_absolute(tmp_path)
		return false
	return true

static func load_from_file(path: String) -> GyroProject:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var json_string := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_string)
	if err != OK or not (json.data is Dictionary):
		return null
	return dict_to_project(json.data)

static func peek_icon_path(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	f.close()
	if err != OK or not (json.data is Dictionary):
		return ""
	var settings: Variant = json.data.get("settings", {})
	if not (settings is Dictionary):
		return ""
	return str(settings.get("icon_path", ""))

static func peek_custom_functions(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return []
	var raw = (parsed as Dictionary).get("custom_functions", [])
	return raw if raw is Array else []
