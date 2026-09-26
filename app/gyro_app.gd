class_name GyroApp
extends Control

var current_project: GyroProject
var current_project_path := ""
var home_ui: HomeScreen

const HOME_SCENE := preload("res://ui/screens/home_screen.tscn")
var app_settings_screen: AppSettingsScreen

const APP_SETTINGS_SCENE := preload("res://ui/screens/app_settings.tscn")
var menu: ProjectMenuScreen

const MENU_SCENE := preload("res://ui/screens/project_menu.tscn")
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

func _ready() -> void:
	get_tree().quit_on_go_back = false
	if _try_player_mode():
		return
	get_tree().quit_on_go_back = false
	app_settings = GyroAppSettings.load_settings()
	GyroLang.lang = app_settings.language
	GyroLang.load_lang()
	GyroUI.init_scale(get_viewport_rect().size)
	theme = GyroTheme.make()
	get_tree().root.size_changed.connect(func():
		GyroUI.init_scale(get_viewport_rect().size)
		theme = GyroTheme.make()
	)

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.10, 0.12)
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
	
	menu = MENU_SCENE.instantiate()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.visible = false
	add_child(menu)

	app_settings_screen = APP_SETTINGS_SCENE.instantiate()
	app_settings_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app_settings_screen.visible = false
	add_child(app_settings_screen)
	app_settings_screen.back_requested.connect(func(): _show(home_ui))
	app_settings_screen.lang_changed.connect(_refresh_lang)

	doc_screen = DOC_SCENE.instantiate()
	doc_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	doc_screen.visible = false
	add_child(doc_screen)
	doc_screen.back_requested.connect(func(): _show(home_ui))
	
	about_screen = ABOUT_SCENE.instantiate()
	about_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	about_screen.visible = false
	add_child(about_screen)

	about_screen.back_requested.connect(func(): _show(home_ui))

	menu.open_requested.connect(_open_project)
	menu.back_requested.connect(func(): _show(home_ui))

	hub.back_requested.connect(func():
		hub.stop_test()
		menu.refresh()
		_show(menu)
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
			_show(menu)
			return
		structure.setup(current_project, current_project_path)
		_show(structure)
	)

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
	var proj := GyroProjectJSON.dict_to_project(parsed)
	if proj == null:
		return false
	# ассеты лежат в APK по адресу res://gyro_data/files/...
	for v in proj.assets:
		var a := v as GyroAsset
		if a == null:
			continue
		if not a.path.begins_with("res://") and not a.path.begins_with("user://"):
			a.path = "res://gyro_data/files/" + a.path
	# объединяем blueprint всех скриптов
	var merged := GyroEventBlueprint.new()
	for s_value in proj.scripts:
		var s := s_value as GyroScript
		if s == null or s.blueprint == null:
			continue
		for key in s.blueprint.variables.keys():
			merged.variables[key] = s.blueprint.variables[key]
		for rule in s.blueprint.rules:
			merged.rules.append(rule)
		for t_value in s.blueprint.timers:
			var t := t_value as GyroTimerConfig
			if t != null:
				merged.timers.append(t)
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
	home_ui.manager_pressed.connect(_show_manager)
	home_ui.doc_pressed.connect(func(): _show(doc_screen))
	home_ui.settings_pressed.connect(func():
		app_settings_screen.setup(app_settings)
		_show(app_settings_screen)
	)

func _home_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(GyroUI.sz(12))
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

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

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()

func _handle_back() -> void:
	if player_host != null:
		if player_host.runtime.has_event("back"):
			player_host.emit_event("back", {})
		else:
			get_tree().quit()
		return
	if editor.visible:
		editor.editor_back()
	elif structure.visible or resources.visible or settings_screen.visible:
		if current_project != null:
			_show(hub)
	elif hub.visible:
		if hub.test_host != null and hub.test_host.runtime.has_event("back"):
			hub.test_host.emit_event("back", {})
		else:
			hub.stop_test()
			menu.refresh()
			_show(menu)
	elif menu.visible:
		_show(home_ui)
	elif app_settings_screen.visible:
		_show(home_ui)
	elif home_ui.visible:
		get_tree().quit()
	elif doc_screen.visible:
		_show(home_ui)
	elif structure.visible or resources.visible or settings_screen.visible:
		if resources.visible and resources.is_preview_open():
			resources.close_preview()
			return
		if current_project != null:
			_show(hub)
	else:
		_show(home_ui)

func _show(node: Control) -> void:
	if hub != null:
		hub.stop_test()
	if editor != null:
		editor.stop_test()

	home_ui.visible = false
	menu.visible = false
	hub.visible = false
	structure.visible = false
	resources.visible = false
	settings_screen.visible = false
	editor.visible = false
	app_settings_screen.visible = false
	doc_screen.visible = false
	node.visible = true
	

func _show_manager() -> void:
	menu.refresh()
	_show(menu)


func _open_project(path: String) -> void:
	var loaded := ResourceLoader.load(path)

	if loaded == null:
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("open_project_failed") % path)
		return

	if loaded is GyroProject:
		current_project = loaded

		if GyroAssetPaths.migrate_project(current_project, path):
			GyroUI.save_resource(current_project, path)

	elif loaded is GyroEventBlueprint:
		current_project = GyroProject.new()

		var s := GyroScript.new()
		s.script_name = "Main"
		s.blueprint = loaded
		current_project.scripts.append(s)

	else:
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("not_gyro_project") % path)
		return

	if current_project.settings == null:
		current_project.settings = GyroProjectSettings.new()

	_validate_project(current_project)
	
	if current_project.migrate_event_names():
		GyroUI.save_resource(current_project, path)

	if current_project.format_version > GyroProject.FORMAT_VERSION:
		GyroUI.alert(self, GyroLang.t("warning"), GyroLang.t("newer_version_warning"))

	current_project_path = path
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

func _refresh_lang() -> void:
	GyroLang.set_language(app_settings.language) 
	if home_ui != null:
		home_ui.apply_lang()
	if menu != null:
		menu.apply_lang()
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
