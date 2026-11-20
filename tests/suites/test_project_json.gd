extends "res://tests/framework/test_case.gd"

const Env := preload("res://tests/framework/test_env.gd")

func suite_name() -> String:
	return "project_json"

func _fixture() -> GyroProject:
	var p := Env.project("Round")
	p.settings.permissions.append("android.permission.VIBRATE")
	p.settings.keystore_path = "user://keystore/release.p12"
	p.settings.keystore_alias = "gyro"
	p.settings.keystore_password = "secret"
	p.settings.icon_path = "icon/app.png"
	var s := GyroScript.new()
	s.script_name = "Main"
	s.folder = "logic"
	s.blueprint = GyroEventBlueprint.new()
	s.blueprint.variables = {"hp": 100, "hero": "bob"}
	s.blueprint.variable_types = {"hp": "number"}
	s.blueprint.tables = {"inv": {"gold": 5}}
	var r := Env.rule("custom", [], "hit")
	r.note = "note"
	r.event_filter = ""
	r.conditions.append(Env.condition("VariableGreaterThan", {"name": "hp", "value": 0}))
	var inner := {"type": "Print", "data": {"message": "x"}, "disabled": true}
	var repeat := {"type": "Repeat", "data": {"count": 2, "blocks": [inner]}, "disabled": false}
	r.actions.append(Env.action("If", {"condition": "true", "blocks": [repeat]}))
	s.blueprint.rules.append(r)
	var t := GyroTimerConfig.new()
	t.timer_name = "tick"
	t.wait_time = 0.5
	t.one_shot = false
	t.autostart = true
	s.blueprint.timers.append(t)
	p.scripts.append(s)
	var a := GyroAsset.new()
	a.id = "a1"
	a.kind = "sprite"
	a.asset_name = "hero"
	a.path = "sprite/hero.png"
	a.folder = "sprite/chars"
	p.assets.append(a)
	p.asset_folders.append("sprite/chars")
	p.folders.append("logic")
	return p

func test_round_trip_structure() -> void:
	var src := _fixture()
	var dst := GyroProjectJSON.dict_to_project(GyroProjectJSON.project_to_dict(src))
	not_null(dst, "loaded project")
	eq(dst.scripts.size(), 1, "script count")
	eq(dst.scripts[0].script_name, "Main", "script name")
	eq(dst.scripts[0].folder, "logic", "script folder")
	eq(dst.folders, ["logic"], "folders")
	eq(dst.asset_folders, ["sprite/chars"], "asset folders")
	eq(dst.assets.size(), 1, "asset count")
	eq(dst.assets[0].id, "a1", "asset id")
	eq(dst.assets[0].folder, "sprite/chars", "asset folder")

func test_round_trip_blueprint() -> void:
	var src := _fixture()
	var dst := GyroProjectJSON.dict_to_project(GyroProjectJSON.project_to_dict(src))
	var bp := dst.scripts[0].blueprint
	eq(bp.variables, {"hp": 100, "hero": "bob"}, "variables")
	eq(bp.tables, {"inv": {"gold": 5}}, "tables")
	eq(bp.timers.size(), 1, "timers")
	eq(bp.timers[0].timer_name, "tick", "timer name")
	eq(bp.timers[0].one_shot, false, "timer one_shot")
	var r := bp.rules[0]
	eq(r.event_type, "custom", "event type")
	eq(r.event_name, "hit", "event name")
	eq(r.note, "note", "rule note")
	eq(r.conditions.size(), 1, "conditions")
	eq(r.conditions[0].type, "VariableGreaterThan", "condition type")

func test_round_trip_nested_blocks() -> void:
	var src := _fixture()
	var dst := GyroProjectJSON.dict_to_project(GyroProjectJSON.project_to_dict(src))
	var flow := dst.scripts[0].blueprint.rules[0].actions[0]
	eq(flow.type, "If", "flow type")
	var blocks: Array = flow.data.get("blocks", [])
	eq(blocks.size(), 1, "nested level 1")
	var repeat: Dictionary = blocks[0]
	eq(str(repeat.get("type")), "Repeat", "nested type")
	var inner: Array = (repeat.get("data", {}) as Dictionary).get("blocks", [])
	eq(inner.size(), 1, "nested level 2")
	eq(bool((inner[0] as Dictionary).get("disabled", false)), true, "nested disabled flag survives")

func test_round_trip_settings() -> void:
	var src := _fixture()
	var dst := GyroProjectJSON.dict_to_project(GyroProjectJSON.project_to_dict(src))
	eq(dst.settings.app_name, "Round", "app name")
	eq(dst.settings.package_name, "com.test.app", "package")
	eq(dst.settings.permissions, ["android.permission.VIBRATE"], "permissions")
	eq(dst.settings.orientation, "auto", "orientation default")

func test_secrets_stripped_on_export_dict() -> void:
	var d := GyroProjectJSON.project_to_dict(_fixture(), false)
	var st: Dictionary = d.get("settings", {})
	eq(str(st.get("keystore_password")), "", "keystore password stripped")
	eq(str(st.get("keystore_path")), "", "keystore path stripped")
	eq(str(st.get("keystore_alias")), "", "keystore alias stripped")

func test_custom_omitted_when_requested() -> void:
	var d := GyroProjectJSON.project_to_dict(_fixture(), true, false)
	eq((d.get("custom_blocks", []) as Array).size(), 0, "custom blocks omitted")
	eq((d.get("custom_packs", []) as Array).size(), 0, "custom packs omitted")

func test_missing_format_version_rejected() -> void:
	is_null(GyroProjectJSON.dict_to_project({"scripts": []}), "no format_version")
	is_null(GyroProjectJSON.dict_to_project({"format_version": 0}), "zero format_version")

func test_newer_format_still_loads() -> void:
	var p := GyroProjectJSON.dict_to_project({"format_version": 99})
	not_null(p, "newer format loads")
	eq(p.format_version, 99, "version preserved")

func test_legacy_table_migration() -> void:
	var bp := GyroProjectJSON.dict_to_blueprint({
		"variables": {"inv": {"a": 1}, "hp": 3},
		"variable_types": {"inv": "table"},
	})
	eq(bp.tables, {"inv": {"a": 1}}, "table extracted")
	eq(bp.variables, {"hp": 3}, "scalar kept")

func test_legacy_action_keys_normalized() -> void:
	var bp := GyroProjectJSON.dict_to_blueprint({
		"rules": [{
			"event_type": "ready",
			"actions": [{"type": "ForEachTable", "data": {"table": "inv", "variable": "item"}}],
		}],
	})
	var data := bp.rules[0].actions[0].data
	eq(str(data.get("name")), "inv", "table key renamed to name")
	eq(str(data.get("element")), "item", "variable renamed to element")
	check(not data.has("table"), "legacy table key removed")

func test_event_name_migration() -> void:
	var bp := GyroProjectJSON.dict_to_blueprint({
		"rules": [{"event_type": "ready", "event_name": "tap"}],
	})
	eq(bp.rules[0].event_type, "tap", "builtin name migrated to type")
	eq(bp.rules[0].event_name, "", "name cleared")

func test_file_round_trip() -> void:
	var path := Env.path("proj/round.json")
	var src := _fixture()
	check(GyroProjectJSON.save_to_file(src, path), "save ok")
	check(FileAccess.file_exists(path), "file written")
	check(not FileAccess.file_exists(path + ".tmp"), "temp file cleaned")
	var dst := GyroProjectJSON.load_from_file(path)
	not_null(dst, "load ok")
	eq(dst.scripts.size(), 1, "scripts survived file")
	eq(dst.assets.size(), 1, "assets survived file")

func test_corrupt_file_returns_null() -> void:
	var path := Env.path("proj/broken.json")
	Env.write_text(path, "{not json")
	is_null(GyroProjectJSON.load_from_file(path), "corrupt json")
	is_null(GyroProjectJSON.load_from_file(Env.path("proj/absent.json")), "missing file")

func test_peek_helpers() -> void:
	var path := Env.path("proj/peek.json")
	GyroProjectJSON.save_to_file(_fixture(), path)
	eq(GyroProjectJSON.peek_icon_path(path), "icon/app.png", "peek icon")
	eq(GyroProjectJSON.peek_icon_path(Env.path("proj/absent.json")), "", "peek missing")
	eq(GyroProjectJSON.peek_custom_functions(path).size(), 0, "peek functions empty")
