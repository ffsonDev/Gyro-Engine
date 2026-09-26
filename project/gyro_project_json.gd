class_name GyroProjectJSON
extends RefCounted

static func project_to_dict(p: GyroProject, include_secrets: bool = true) -> Dictionary:
	var scripts: Array = []
	for s in p.scripts:
		if s == null:
			continue
		scripts.append({
			"script_name": s.script_name,
			"folder": s.folder,
			"blueprint": blueprint_to_dict(s.blueprint)
		})
	var assets: Array = []
	for a in p.assets:
		if a == null:
			continue
		assets.append({"kind": a.kind, "asset_name": a.asset_name, "path": a.path, "folder": a.folder, "id": a.id})
	var st := p.settings
	return {
		"format_version": p.format_version,
		"scripts": scripts,
		"folders": p.folders.duplicate(),
		"asset_folders": p.asset_folders.duplicate(),
		"assets": assets,
		"settings": {
			"app_name": st.app_name if st else "",
			"package_name": st.package_name if st else "",
			"orientation": st.orientation if st else "auto",
			"icon_path": st.icon_path if st else "",
			"version_code": st.version_code if st else 1,
			"version_name": st.version_name if st else "1.0.0",
			"permissions": st.permissions.duplicate() if st else [],
			"keystore_path": (st.keystore_path if st else "") if include_secrets else "",
			"keystore_alias": (st.keystore_alias if st else "") if include_secrets else "",
			"keystore_password": (st.keystore_password if st else "") if include_secrets else "",
			"key_password": (st.key_password if st else "") if include_secrets else "",
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
		"timers": timers,
	}

static func dict_to_project(d: Dictionary) -> GyroProject:
	var p := GyroProject.new()
	p.format_version = int(d.get("format_version", 1))
	for sv in d.get("scripts", []):
		var s := GyroScript.new()
		s.script_name = str(sv.get("script_name", "Main"))
		s.folder = str(sv.get("folder", ""))
		s.blueprint = dict_to_blueprint(sv.get("blueprint", {}))
		p.scripts.append(s)
	p.folders = Array(d.get("folders", []))
	p.asset_folders = Array(d.get("asset_folders", []))
	for av in d.get("assets", []):
		var a := GyroAsset.new()
		a.kind = str(av.get("kind", "other"))
		a.asset_name = str(av.get("asset_name", "asset"))
		a.path = str(av.get("path", ""))
		a.folder = str(av.get("folder", ""))
		a.id = str(av.get("id", ""))
		p.assets.append(a)
	var st := GyroProjectSettings.new()
	var sd: Dictionary = d.get("settings", {})
	st.app_name = str(sd.get("app_name", ""))
	st.package_name = str(sd.get("package_name", ""))
	st.orientation = str(sd.get("orientation", "auto"))
	st.icon_path = str(sd.get("icon_path", ""))
	st.version_code = maxi(1, int(sd.get("version_code", 1)))
	st.version_name = str(sd.get("version_name", "1.0.0"))
	st.permissions = Array(sd.get("permissions", []))
	st.keystore_path = str(sd.get("keystore_path", ""))
	st.keystore_alias = str(sd.get("keystore_alias", ""))
	st.keystore_password = str(sd.get("keystore_password", ""))
	st.key_password = str(sd.get("key_password", ""))
	p.settings = st
	return p

static func dict_to_blueprint(d: Dictionary) -> GyroEventBlueprint:
	var bp := GyroEventBlueprint.new()
	for rv in d.get("rules", []):
		var r := GyroEventRule.new()
		r.event_type = str(rv.get("event_type", "ready"))
		r.event_name = str(rv.get("event_name", ""))
		r.note = str(rv.get("note", ""))
		r.disabled = bool(rv.get("disabled", false))
		r.event_filter = str(rv.get("event_filter", ""))
		for cv in rv.get("conditions", []):
			var c := GyroCondition.new()
			c.type = str(cv.get("type", ""))
			c.data = (cv.get("data", {}) as Dictionary).duplicate(true)
			c.disabled = bool(cv.get("disabled", false))
			r.conditions.append(c)
		for av in rv.get("actions", []):
			var a := GyroAction.new()
			a.type = str(av.get("type", ""))
			a.data = (av.get("data", {}) as Dictionary).duplicate(true)
			a.disabled = bool(av.get("disabled", false))
			r.actions.append(a)
		bp.rules.append(r)
	bp.variables = (d.get("variables", {}) as Dictionary).duplicate(true)
	bp.variable_types = (d.get("variable_types", {}) as Dictionary).duplicate(true)
	for tv in d.get("timers", []):
		var t := GyroTimerConfig.new()
		t.timer_name = str(tv.get("timer_name", ""))
		t.wait_time = float(tv.get("wait_time", 1.0))
		t.one_shot = bool(tv.get("one_shot", false))
		t.autostart = bool(tv.get("autostart", true))
		bp.timers.append(t)
		bp.migrate_event_names()
	return bp
