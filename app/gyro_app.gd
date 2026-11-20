class_name GyroApp
extends Control

var current_project: GyroProject
var current_project_path := ""
var home_ui: HomeScreen
const HOME_SCENE := preload("res://ui/screens/home_screen.tscn")
var app_settings_screen: AppSettingsScreen
const APP_SETTINGS_SCENE := preload("res://ui/screens/app_settings.tscn")
var hub: ProjectHubScreen
const HUB_SCENE := preload("res://ui/screens/project_hub.tscn")
var structure: ProjectStructureScreen
const STRUCTURE_SCENE := preload("res://ui/screens/project_structure.tscn")
var resources: ProjectResourcesScreen
const RESOURCES_SCENE := preload("res://ui/screens/project_resources.tscn")
var settings_screen: ProjectSettingsScreen
const SETTINGS_SCENE := preload("res://ui/screens/project_settings.tscn")
var editor: GyroBlockEditor
const EDITOR_SCENE := preload("res://editor/gyro_block_editor.tscn")
var app_settings: GyroAppSettings
var player_host: GyroEventHost = null
var about_screen: AboutScreen
const ABOUT_SCENE := preload("res://ui/screens/about_screen.tscn")
var doc_screen: DocScreen
const DOC_SCENE := preload("res://ui/screens/doc_screen.tscn")
var custom_pack_screen: CustomPackEditorScreen
var custom_block_screen: CustomBlockEditorScreen
var _block_return: Control = null
var _about_return: Control = null
var _backup_timer: Timer
var function_screen: GyroFunctionScreen

func _ready() -> void:
	get_tree().quit_on_go_back = false
	_apply_square_stretch()
	GyroFunctions.install()
	if _try_player_mode():
		return
	GyroFunctions.load_library()
	get_tree().quit_on_go_back = false
	app_settings = GyroAppSettings.load_settings()
	GyroLang.lang = app_settings.language
	GyroLang.load_lang()
	GyroLang.add_lang_changed_callback(_on_lang_changed)
	GyroUI.init_scale(get_viewport_rect().size)
	theme = GyroTheme.make()
	get_tree().root.size_changed.connect(func():
		_apply_square_stretch()
		GyroUI.init_scale(get_viewport_rect().size)
		theme = GyroTheme.make()
	)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = DesignTokens.COLOR_SURFACE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build_home()
	editor = EDITOR_SCENE.instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor.visible = false
	add_child(editor)
	settings_screen = SETTINGS_SCENE.instantiate()
	settings_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_screen.visible = false
	add_child(settings_screen)
	resources = RESOURCES_SCENE.instantiate()
	resources.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resources.visible = false
	add_child(resources)
	structure = STRUCTURE_SCENE.instantiate()
	structure.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	structure.visible = false
	add_child(structure)
	hub = HUB_SCENE.instantiate()
	hub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hub.visible = false
	add_child(hub)
	app_settings_screen = APP_SETTINGS_SCENE.instantiate()
	app_settings_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app_settings_screen.visible = false
	add_child(app_settings_screen)
	app_settings_screen.back_requested.connect(func(): _show(home_ui))
	app_settings_screen.lang_changed.connect(func(): GyroLang.set_language(app_settings.language))
	app_settings_screen.about_requested.connect(func():
		_about_return = app_settings_screen
		_show(about_screen)
	)
	doc_screen = DOC_SCENE.instantiate()
	doc_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	doc_screen.visible = false
	add_child(doc_screen)
	doc_screen.back_requested.connect(func(): _show(home_ui))
	about_screen = ABOUT_SCENE.instantiate()
	about_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	about_screen.visible = false
	add_child(about_screen)
	about_screen.back_requested.connect(func():
		var target: Control = _about_return if _about_return != null and is_instance_valid(_about_return) else home_ui
		_about_return = null
		_show(target)
	)
	home_ui.open_requested.connect(_open_project)
	hub.back_requested.connect(func():
		hub.stop_test()
		home_ui.refresh()
		_show(home_ui)
	)
	hub.reload_requested.connect(_open_project)
	hub.open_structure.connect(func():
		if current_project == null:
			return
		structure.setup(current_project, current_project_path)
		_show(structure)
	)
	hub.open_resources.connect(func():
		if current_project == null:
			return
		resources.setup(current_project, current_project_path)
		_show(resources)
	)
	hub.open_settings.connect(func():
		if current_project == null:
			return
		settings_screen.setup(current_project, current_project_path)
		_show(settings_screen)
	)
	structure.back_requested.connect(func(): _show(hub))
	structure.open_script.connect(func(s: GyroScript):
		editor.open_script(current_project, s, current_project_path)
		_show(editor)
	)
	resources.back_requested.connect(func(): _show(hub))
	settings_screen.back_requested.connect(func(): _show(hub))
	editor.back_pressed.connect(func():
		if current_project == null:
			_show(home_ui)
			return
		var sid := ""
		if editor.state.current_script != null:
			sid = str(editor.state.current_script.get_meta("gyro_custom_block_id", ""))
		if sid != "":
			editor.state.custom_param_names = []
			var cb := GyroCustomRegistry.find_block(current_project, sid)
			var cpk := GyroCustomRegistry.find_pack_of(current_project, sid)
			if cb != null:
				var scr := editor.state.current_script
				if scr != null and scr.blueprint != null and scr.blueprint.rules.size() > 0:
					var body_rule := scr.blueprint.rules[0] as GyroEventRule
					if body_rule != null:
						cb.body.clear()
						for av in body_rule.actions:
							var aa := av as GyroAction
							if aa != null:
								cb.body.append(aa)
				scr.set_meta("gyro_custom_block_id", "")
				editor.state.custom_param_names = []
			GyroProjectJSON.save_to_file(current_project, current_project_path)
			_refresh_palette()
			if _block_return != null and is_instance_valid(_block_return):
				_show(_block_return)
			else:
				structure.setup(current_project, current_project_path)
				_show(structure)
			return
		structure.setup(current_project, current_project_path)
		_show(structure)
	)
	custom_pack_screen = CustomPackEditorScreen.new()
	custom_pack_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_pack_screen.visible = false
	add_child(custom_pack_screen)
	custom_pack_screen.back_requested.connect(func():
		_refresh_palette()
		_show(editor)
	)
	custom_pack_screen.edit_block.connect(func(b: GyroCustomBlock):
		_block_return = custom_pack_screen
		custom_block_screen.setup(current_project, custom_pack_screen.pack, b, current_project_path)
		_show(custom_block_screen)
	)
	custom_pack_screen.changed.connect(func(): _refresh_palette())
	custom_block_screen = CustomBlockEditorScreen.new()
	custom_block_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_block_screen.visible = false
	add_child(custom_block_screen)
	custom_block_screen.back_requested.connect(func():
		_refresh_palette()
		if _block_return != null:
			_show(_block_return)
		elif current_project != null:
			structure.setup(current_project, current_project_path)
			_show(structure)
		else:
			_show(home_ui)
	)
	custom_block_screen.open_body.connect(_open_custom_body)
	custom_block_screen.changed.connect(func(): _refresh_palette())
	function_screen = GyroFunctionScreen.new()
	function_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	function_screen.visible = false
	add_child(function_screen)
	function_screen.back_requested.connect(func(): _show(editor))
	editor.expr_editor.functions_requested.connect(func():
		function_screen.setup(current_project)
		_show(function_screen)
	)
	editor.menus.palette.create_block_confirmed.connect(_on_create_block)
	editor.menus.palette.create_pack_confirmed.connect(_on_create_pack)
	editor.menus.palette.import_requested.connect(_on_import_pack)
	editor.menus.palette.edit_block_requested.connect(_on_edit_block)
	editor.menus.palette.edit_pack_requested.connect(_on_edit_pack)
	GyroUI.transition = ScreenTransition.new()
	GyroUI.transition.setup(self)
	_backup_timer = Timer.new()
	_backup_timer.wait_time = 60.0
	_backup_timer.autostart = true
	_backup_timer.timeout.connect(func(): _backup_now(false))
	add_child(_backup_timer)

func _backup_now(force: bool) -> void:
	if current_project_path == "":
		return
	_flush_open_editors()
	if force:
		GyroBackups.make_backup_force(current_project_path)
	else:
		GyroBackups.make_backup(current_project_path)

func _flush_open_editors() -> void:
	if editor != null and editor.visible:
		editor.flush_save()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_backup_now(false)

func _apply_square_stretch() -> void:
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size = Vector2(480, 480)

func _try_player_mode() -> bool:
	var pj := "res://gyro_data/project.json"
	if not FileAccess.file_exists(pj):
		return false
	var f := FileAccess.open(pj, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is not Dictionary:
		return false
	GyroFunctions.install_from_array((parsed as Dictionary).get("custom_functions", []))
	var proj := GyroProjectJSON.dict_to_project(parsed)
	if proj == null:
		return false
	for v in proj.assets:
		var a := v as GyroAsset
		if a == null:
			continue
		if not a.path.begins_with("res://") and not a.path.begins_with("user://"):
			a.path = "res://gyro_data/files/" + a.path
	var merged := proj.merge_blueprints()
	var bg := ColorRect.new()
	bg.name = "GyroBackground"
	bg.color = Color(0, 0, 0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if proj.settings != null:
		GyroUI.set_orientation(proj.settings.orientation)
	player_host = GyroEventHost.new()
	player_host.blueprint = merged
	player_host.project = proj
	player_host.project_path = "res://gyro_data/project.tres"
	add_child(player_host)
	return true

func _build_home() -> void:
	home_ui = HOME_SCENE.instantiate()
	home_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(home_ui)
	home_ui.doc_pressed.connect(func(): _show(doc_screen))
	home_ui.settings_pressed.connect(func():
		app_settings_screen.setup(app_settings)
		_show(app_settings_screen)
	)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_release_focus_outside(event.position)
	elif event is InputEventMouseButton and event.pressed:
		_release_focus_outside(event.position)

func _release_focus_outside(pos: Vector2) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null:
		return
	if focused.get_global_rect().has_point(pos):
		return
	get_viewport().gui_release_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_handle_back()
		get_viewport().set_input_as_handled()

func _handle_back() -> void:
	if player_host != null:
		if player_host.runtime.has_event("back"):
			player_host.emit_event("back", {})
		else:
			get_tree().quit()
		return
	if editor.visible:
		editor.editor_back()
	elif app_settings_screen.visible:
		_show(home_ui)
	elif doc_screen.visible:
		_show(home_ui)
	elif structure.visible or resources.visible or settings_screen.visible:
		if resources.visible and resources.is_preview_open():
			resources.close_preview()
			return
		if resources.visible and resources.drag_asset != null:
			resources.drag_asset = null
			resources.drop_indicator.visible = false
			return
		if structure.visible and structure.drag_script != null:
			structure.drag_script = null
			structure.drop_indicator.visible = false
			return
		if current_project != null:
			_show(hub)
		else:
			_show(home_ui)
	elif function_screen.visible:
		_show(editor)
	elif hub.visible:
		if hub.test_runner != null and hub.test_runner.is_running and hub.test_runner.host != null and hub.test_runner.host.runtime.has_event("back"):
			hub.test_runner.host.emit_event("back", {})
		else:
			hub.stop_test()
			home_ui.refresh()
			_show(home_ui)
	elif home_ui.visible:
		get_tree().quit()

func _show(node: Control) -> void:
	if hub != null:
		hub.stop_test()
	if editor != null:
		editor.stop_test()
	var old_screen: Control = null
	if home_ui.visible: old_screen = home_ui
	elif hub.visible: old_screen = hub
	elif structure.visible: old_screen = structure
	elif resources.visible: old_screen = resources
	elif settings_screen.visible: old_screen = settings_screen
	elif editor.visible: old_screen = editor
	elif app_settings_screen.visible: old_screen = app_settings_screen
	elif doc_screen.visible: old_screen = doc_screen
	elif about_screen.visible: old_screen = about_screen
	elif custom_pack_screen.visible: old_screen = custom_pack_screen
	elif custom_block_screen.visible: old_screen = custom_block_screen
	elif function_screen.visible: old_screen = function_screen
	home_ui.visible = false
	hub.visible = false
	structure.visible = false
	resources.visible = false
	settings_screen.visible = false
	editor.visible = false
	app_settings_screen.visible = false
	doc_screen.visible = false
	about_screen.visible = false
	custom_pack_screen.visible = false
	custom_block_screen.visible = false
	function_screen.visible = false
	node.visible = true
	if GyroUI.transition != null and old_screen != null:
		GyroUI.transition.show_screen(node, old_screen)

func _open_custom_body(b: GyroCustomBlock) -> void:
	if b == null or current_project == null:
		return
	var script := GyroScript.new()
	script.script_name = b.block_name
	script.set_meta("gyro_custom_block_id", b.block_id)
	script.blueprint = GyroEventBlueprint.new()
	var rule := GyroEventRule.new()
	rule.event_type = "ready"
	for av in b.body:
		var src := av as GyroAction
		if src == null:
			continue
		var copy := GyroAction.new()
		copy.type = src.type
		copy.data = src.data.duplicate(true)
		copy.disabled = src.disabled
		rule.actions.append(copy)
	script.blueprint.rules.append(rule)
	var params: Array = []
	for f in b.fields:
		params.append(str(f.get("key", "")))
	editor.open_script(current_project, script, current_project_path, params)
	_show(editor)

func _refresh_palette() -> void:
	if editor != null and editor.menus != null and editor.menus.palette != null:
		editor.menus.palette.refresh()

func _on_create_block(block_name: String, pack_name: String) -> void:
	if current_project == null:
		return
	var b := GyroCustomBlock.new()
	b.block_id = GyroCustomRegistry.make_unique_id(current_project, "block")
	b.block_name = block_name
	var pk: GyroCustomPack = null
	if pack_name != "":
		pk = GyroCustomRegistry.find_pack_by_name(current_project, pack_name)
	if pk != null:
		b.author = pk.author
		pk.blocks.append(b)
	else:
		b.author = current_project.settings.app_name if current_project.settings != null else ""
		current_project.custom_blocks.append(b)
	GyroProjectJSON.save_to_file(current_project, current_project_path)
	_refresh_palette()
	_block_return = editor
	custom_block_screen.setup(current_project, pk, b, current_project_path)
	_show(custom_block_screen)

func _on_create_pack(pack_name: String) -> void:
	if current_project == null:
		return
	var pk := GyroCustomPack.new()
	pk.pack_name = pack_name
	pk.author = current_project.settings.app_name if current_project.settings != null else ""
	current_project.custom_packs.append(pk)
	GyroProjectJSON.save_to_file(current_project, current_project_path)
	_refresh_palette()

func _on_import_pack() -> void:
	if current_project == null:
		return
	var on_selected := func(path: String):
		var res := GyroCustomRegistry.import_pack(current_project, path)
		if path.begins_with("user://imported_"):
			DirAccess.remove_absolute(path)
		if not bool(res.get("ok", false)):
			GyroUI.alert(self, GyroLang.t("error"), str(res.get("report", ["?"])))
			return
		GyroProjectJSON.save_to_file(current_project, current_project_path)
		_refresh_palette()
		var report: Array = res.get("report", [])
		if not report.is_empty():
			GyroUI.alert(self, GyroLang.t("custom_import_pack"), "\n".join(report.map(func(x): return str(x))))
	var on_failed := func(message: String):
		GyroUI.alert(self, GyroLang.t("error"), message)
	GyroFilePicker.pick_file("other", on_selected, on_failed)

func _on_edit_block(block_id: String) -> void:
	if current_project == null:
		return
	var b := GyroCustomRegistry.find_block(current_project, block_id)
	if b == null:
		return
	var pk := GyroCustomRegistry.find_pack_of(current_project, block_id)
	_block_return = editor
	custom_block_screen.setup(current_project, pk, b, current_project_path)
	_show(custom_block_screen)

func _on_edit_pack(pack_name: String) -> void:
	if current_project == null:
		return
	var pk := GyroCustomRegistry.find_pack_by_name(current_project, pack_name)
	if pk == null:
		return
	custom_pack_screen.setup(current_project, pk, current_project_path)
	_show(custom_pack_screen)

func _open_project(path: String) -> void:
	GyroMedia.clear_texture_cache()
	var loaded: GyroProject = null
	if path.ends_with(".json"):
		loaded = GyroProjectJSON.load_from_file(path)
	else:
		loaded = ResourceLoader.load(path) as GyroProject
	if loaded == null:
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("open_project_failed") % path)
		return
	current_project = loaded
	if GyroAssetPaths.migrate_project(current_project, path):
		GyroUI.save_resource(current_project, path)
	elif current_project.settings == null:
		current_project.settings = GyroProjectSettings.new()
	_validate_project(current_project)
	var fn_report := GyroFunctions.adopt(GyroProjectJSON.peek_custom_functions(path))
	if not fn_report.is_empty():
		GyroUI.alert(self, GyroLang.t("functions_title"), "\n".join(fn_report.map(func(x): return str(x))))
	GyroGlobalBlocks.adopt(current_project)
	if current_project.migrate_event_names():
		GyroUI.save_resource(current_project, path)
	if current_project.format_version > GyroProject.FORMAT_VERSION:
		GyroUI.alert(self, GyroLang.t("warning"), GyroLang.t("newer_version_warning"))
	current_project_path = path
	if current_project.format_version < GyroProject.FORMAT_VERSION:
		current_project.format_version = GyroProject.FORMAT_VERSION
	if current_project.last_modified == 0.0:
		current_project.last_modified = Time.get_unix_time_from_system()
	GyroUI.save_resource(current_project, path)
	hub.setup(current_project, path.get_file().get_basename(), path)
	_show(hub)
	await get_tree().process_frame
	GyroBackups.make_backup(path)

func _validate_project(proj: GyroProject) -> void:
	for s in proj.scripts:
		if s == null:
			continue
		if s.script_name == "":
			s.script_name = "Script"
		if s.blueprint == null:
			s.blueprint = GyroEventBlueprint.new()
	for a in proj.assets:
		if a == null:
			continue
		if a.kind == "":
			a.kind = "other"
		if a.asset_name == "":
			a.asset_name = "asset"
		if a.id == "":
			a.id = "a" + str(Time.get_unix_time_from_system()) + str(randi() % 100000)

func _on_lang_changed() -> void:
	if home_ui != null:
		home_ui.apply_lang()
	if hub != null:
		hub.apply_lang()
	if structure != null:
		structure.apply_lang()
	if resources != null:
		resources.apply_lang()
	if settings_screen != null:
		settings_screen.apply_lang()
	if app_settings_screen != null:
		app_settings_screen.apply_lang()
	if editor != null:
		editor.apply_lang()
	if doc_screen != null:
		doc_screen.apply_lang()
	if function_screen != null:
		function_screen.apply_lang()
