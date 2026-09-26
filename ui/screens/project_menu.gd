class_name ProjectMenuScreen
extends Control

signal open_requested(path: String)
signal back_requested

var projects_dir := ""
var selected_path := ""
var last_tap_path := ""
var last_tap_time := 0

var _style_cache := {}

func _ready() -> void:
	projects_dir = GyroPaths.projects_dir()
	GyroPaths.ensure_dirs()
	GyroPaths.migrate_old()
	%Title.add_theme_font_size_override("font_size", GyroUI.fs(40))
	%EmptyTitle.add_theme_font_size_override("font_size", GyroUI.fs(26))
	%EmptyHint.add_theme_font_size_override("font_size", GyroUI.fs(14))
	%BackButton.pressed.connect(func(): back_requested.emit())
	%GearButton.pressed.connect(_open_project_panel)
	%PlusButton.pressed.connect(func():
		%CreateDialog.open(GyroLang.t("new_project"), GyroLang.t("title_placeholder"), "")
	)
	%ImportButton.pressed.connect(func():
		var on_selected := func(path: String): _do_import_archive(path)
		var on_failed := func(message: String): GyroUI.alert(self, GyroLang.t("error"), message)
		GyroFilePicker.pick_file("other", on_selected, on_failed)
	)
	%ProjectPanelOverlay.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event):
			_close_project_panel()
	)
	%OpenButton.pressed.connect(func():
		if selected_path != "":
			open_requested.emit(selected_path)
	)
	%RenameButton.pressed.connect(func():
		_close_project_panel()
		if selected_path != "":
			%RenameDialog.open(GyroLang.t("rename"), GyroLang.t("title_placeholder"), selected_path.get_file().get_basename())
	)
	%DuplicateButton.pressed.connect(_duplicate_project)
	%DeleteButton.pressed.connect(func():
		_close_project_panel()
		if selected_path != "":
			%ConfirmDialog.open(GyroLang.t("delete"), GyroLang.t("delete_project_q") % selected_path.get_file().get_basename(), GyroLang.t("delete"), GyroLang.t("cancel"))
	)
	%CreateDialog.confirmed_text.connect(_create_project)
	%RenameDialog.confirmed_text.connect(_rename_project)
	%ConfirmDialog.confirmed.connect(_do_delete)
	%Scroll.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event) and selected_path != "":
			selected_path = ""
			last_tap_path = ""
			refresh()
	)
	var touch_scroll := GyroTouchScroll.new()
	add_child(touch_scroll)
	touch_scroll.setup(%Scroll, [%ProjectPanelOverlay, %CreateDialog, %RenameDialog, %ConfirmDialog])
	%EmptyTitle.add_theme_color_override("font_color", Color(0.55, 0.58, 0.63))
	%EmptyHint.add_theme_color_override("font_color", Color(0.42, 0.45, 0.49))
	apply_lang()
	refresh()

func apply_lang() -> void:
	%Title.text = GyroLang.t("projects")
	%EmptyTitle.text = GyroLang.t("empty_projects")
	%EmptyHint.text = GyroLang.t("empty_hint")
	%OpenButton.text = GyroLang.t("open")
	%RenameButton.text = GyroLang.t("rename")
	%DuplicateButton.text = GyroLang.t("duplicate")
	%DeleteButton.text = GyroLang.t("delete")

func _get_style(selected: bool) -> StyleBoxFlat:
	var key := "sel_" + str(selected)
	if _style_cache.has(key):
		return _style_cache[key]
	var style := StyleBoxFlat.new()
	if selected:
		style.bg_color = Color(0.11, 0.55, 0.62)
	else:
		style.bg_color = Color(0.22, 0.24, 0.28)
	style.set_corner_radius_all(10)
	_style_cache[key] = style
	return style

func refresh() -> void:
	GyroUI.clear_children(%ListVBox)
	if selected_path != "" and not FileAccess.file_exists(selected_path):
		selected_path = ""
	GyroPaths.ensure_dirs()
	var count := 0
	var dir := DirAccess.open(projects_dir)
	if dir != null:
		var files := dir.get_files()
		files.sort()
		for file in files:
			if not str(file).ends_with(".tres"):
				continue
			_add_row(str(file))
			count += 1
	%EmptyState.visible = count == 0
	%GearButton.disabled = selected_path == ""

func _add_row(file: String) -> void:
	var path := projects_dir + file
	var button := Button.new()
	button.text = "  " + file.get_basename()
	button.clip_text = true
	button.custom_minimum_size = Vector2(0, GyroUI.sz(72))
	button.add_theme_font_size_override("font_size", GyroUI.fs(26))
	button.add_theme_color_override("font_color", Color.WHITE)
	var style := _get_style(path == selected_path)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = style.bg_color.darkened(0.2)
	button.add_theme_stylebox_override("pressed", pressed)
	GyroUI.attach_tap(button, func(): _on_row_tapped(path))
	%ListVBox.add_child(button)

func _on_row_tapped(path: String) -> void:
	var now := Time.get_ticks_msec()
	if last_tap_path == path and now - last_tap_time < 400:
		last_tap_path = ""
		open_requested.emit(path)
		return
	selected_path = path
	last_tap_path = path
	last_tap_time = now
	refresh()

func _open_project_panel() -> void:
	if selected_path == "":
		%PanelTitle.text = GyroLang.t("create")
	else:
		%PanelTitle.text = GyroLang.t("project_prefix") + selected_path.get_file().get_basename()
	%ProjectPanelOverlay.visible = true
	%ProjectPanel.visible = true

func _close_project_panel() -> void:
	%ProjectPanelOverlay.visible = false
	%ProjectPanel.visible = false

func _create_project(name_text: String) -> void:
	var clean := GyroUI.sanitize_name(name_text)
	if GyroUI.is_bad_name(clean):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("enter_correct_project_name"))
		return
	var path := projects_dir + clean + ".tres"
	if FileAccess.file_exists(path) or ResourceLoader.exists(path):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("project_exists"))
		return
	var proj := GyroProject.new()
	proj.settings = GyroProjectSettings.new()
	if GyroUI.save_resource(proj, path):
		selected_path = path
		refresh()
	else:
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("create_failed"))

func _rename_project(name_text: String) -> void:
	if selected_path == "":
		return
	var clean := GyroUI.sanitize_name(name_text)
	if GyroUI.is_bad_name(clean):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("enter_correct_project_name_msg"))
		return
	var new_path := selected_path.get_base_dir() + "/" + clean + ".tres"
	if new_path == selected_path:
		refresh()
		return
	if FileAccess.file_exists(new_path):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("project_exists_msg"))
		return
	var loaded := ResourceLoader.load(selected_path)
	if loaded == null:
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("rename_load_failed_msg"))
		return
	if loaded is GyroProject:
		GyroAssetPaths.migrate_project(loaded, selected_path)
		loaded.take_over_path(new_path)
		if not GyroUI.save_resource(loaded, new_path):
			GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("rename_failed_msg"))
			return
	var old_dir := _files_dir_for_path(selected_path)
	var new_dir := _files_dir_for_path(new_path)
	if DirAccess.dir_exists_absolute(old_dir):
		var err := DirAccess.rename_absolute(old_dir, new_dir)
		if err != OK:
			push_error("ProjectMenu: rename dirs failed: %s -> %s" % [old_dir, new_dir])
	var old_backups := _backups_dir_for_path(selected_path)
	var new_backups := _backups_dir_for_path(new_path)
	if DirAccess.dir_exists_absolute(old_backups):
		var backups_err := DirAccess.rename_absolute(old_backups, new_backups)
		if backups_err != OK:
			push_error("ProjectMenu: rename backups failed: %s -> %s" % [old_backups, new_backups])
	var remove_err := DirAccess.remove_absolute(selected_path)
	if remove_err != OK:
		push_error("ProjectMenu: remove old project failed: %s" % selected_path)
	selected_path = new_path
	refresh()

func _duplicate_project() -> void:
	if selected_path == "":
		return
	var base := selected_path.get_file().get_basename()
	var dir_path := selected_path.get_base_dir()
	var candidate := base + "_copy"
	var i := 2
	while FileAccess.file_exists(dir_path + "/" + candidate + ".tres"):
		candidate = base + "_copy" + str(i)
		i += 1
	var loaded := ResourceLoader.load(selected_path)
	if loaded == null:
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("duplicate_load_failed_msg"))
		return
	if not (loaded is GyroProject):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("duplicate_failed_msg"))
		return
	var copy := loaded.duplicate(true) as GyroProject
	if copy == null:
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("duplicate_failed_msg"))
		return
	GyroAssetPaths.migrate_project(copy, selected_path)
	var dst_path := dir_path + "/" + candidate + ".tres"
	copy.take_over_path(dst_path)
	if not GyroUI.save_resource(copy, dst_path):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("duplicate_failed_msg"))
		return
	var old_dir := _files_dir_for_path(selected_path)
	var new_dir := _files_dir_for_path(dst_path)
	if DirAccess.dir_exists_absolute(old_dir):
		_copy_dir_recursive(old_dir, new_dir)
	_close_project_panel()
	refresh()

func _do_delete() -> void:
	if selected_path != "":
		_remove_dir_recursive(_files_dir_for_path(selected_path))
		_remove_dir_recursive(_backups_dir_for_path(selected_path))
		DirAccess.remove_absolute(selected_path)
		selected_path = ""
		_close_project_panel()
		refresh()

func _files_dir_for_path(project_path: String) -> String:
	return project_path.replace("\\", "/").get_basename() + ".files"

func _backups_dir_for_path(project_path: String) -> String:
	return project_path.replace("\\", "/").get_basename() + ".backups"

func _remove_dir_recursive(abs_path: String) -> void:
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(abs_path + "/" + str(f))
	for d in dir.get_directories():
		_remove_dir_recursive(abs_path + "/" + str(d))
	DirAccess.remove_absolute(abs_path)

func _copy_dir_recursive(src_abs: String, dst_abs: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst_abs)
	var dir := DirAccess.open(src_abs)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.copy_absolute(src_abs + "/" + str(f), dst_abs + "/" + str(f))
	for d in dir.get_directories():
		_copy_dir_recursive(src_abs + "/" + str(d), dst_abs + "/" + str(d))

func _do_import_archive(path: String) -> void:
	if path.ends_with(".tres"):
		var loaded := ResourceLoader.load(path) as GyroProject
		var name := ""
		if loaded != null and loaded.settings != null and loaded.settings.app_name != "":
			name = GyroUI.sanitize_name(loaded.settings.app_name)
		if name == "" or GyroUI.is_bad_name(name):
			name = path.get_file().get_basename()
		
		var base := name
		var i := 1
		while FileAccess.file_exists(projects_dir + base + ".tres"):
			base = name + "_" + str(i)
			i += 1
		DirAccess.copy_absolute(path, projects_dir + base + ".tres")
		refresh()
		return
	
	# Читаем оригинальное название из архива
	var raw_name := GyroProjectArchive.read_project_name(path)
	var base := GyroUI.sanitize_name(raw_name) if raw_name != "" else ""
	
	if base == "" or GyroUI.is_bad_name(base):
		base = path.get_file().get_basename()
		if base.ends_with(".gyroproj"):
			base = base.substr(0, base.length() - 9)
		base = GyroUI.sanitize_name(base)
		if base == "" or GyroUI.is_bad_name(base):
			base = "imported"
	
	var result := GyroProjectArchive.import_project(path, projects_dir, base)
	if result == "":
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("import_failed"))
		return
	
	if path.begins_with("user://imported_"):
		DirAccess.remove_absolute(path)
	refresh()
