class_name HomeScreen
extends Control

signal open_requested(path: String)
signal doc_pressed
signal settings_pressed

var projects_dir := ""
var selected_path := ""
var last_tap_path := ""
var last_tap_time := 0
var _icon_round_shader: Shader
var _sort_mode := 1
var _search_query := ""
var _search_edit: LineEdit
var _sort_button: Button

func _ready() -> void:
	projects_dir = GyroPaths.projects_dir()
	GyroPaths.ensure_dirs()
	
	%Title.add_theme_font_size_override("font_size", GyroUI.fs(30))
	%Title.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
	%EmptyTitle.add_theme_font_size_override("font_size", GyroUI.fs(26))
	%EmptyTitle.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_SECONDARY)
	%EmptyHint.add_theme_font_size_override("font_size", GyroUI.fs(14))
	%EmptyHint.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_MUTED)
	
	%DocButton.pressed.connect(func(): doc_pressed.emit())
	%SettingsButton.pressed.connect(func(): settings_pressed.emit())
	
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
			var p := selected_path
			_close_project_panel()
			open_requested.emit(p)
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
			refresh(false)
	)
	
	var touch_scroll := GyroTouchScroll.new()
	add_child(touch_scroll)
	touch_scroll.setup(%Scroll, [%ProjectPanelOverlay, %CreateDialog, %RenameDialog, %ConfirmDialog])
	
	var shader_code := "
shader_type canvas_item;
uniform vec2 size;
uniform float radius;
void fragment() {
	vec2 pos = UV * size;
	vec2 half_size = size * 0.5;
	vec2 d = abs(pos - half_size) - (half_size - vec2(radius));
	float dist = length(max(d, 0.0)) - radius;
	float alpha = 1.0 - smoothstep(-0.5, 0.5, dist);
	COLOR.a *= alpha;
}"
	_icon_round_shader = Shader.new()
	_icon_round_shader.code = shader_code

	_build_search_and_sort()
	apply_lang()
	_animate_in()
	refresh()
	GyroUI.apply_background(self)
	GyroUI.apply_glass_style(%ProjectPanel)

func _animate_in() -> void:
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, DesignTokens.ANIM_NORMAL).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func apply_lang() -> void:
	%Title.text = "Gyro Engine"
	%EmptyTitle.text = GyroLang.t("empty_projects")
	%EmptyHint.text = GyroLang.t("empty_hint")
	%OpenButton.text = GyroLang.t("open")
	%RenameButton.text = GyroLang.t("rename")
	%DuplicateButton.text = GyroLang.t("duplicate")
	%DeleteButton.text = GyroLang.t("delete")

func refresh(animate := true) -> void:
	GyroUI.clear_children(%ListVBox)
	%ListVBox.add_theme_constant_override("separation", DesignTokens.SPACING_MD)
	if selected_path != "" and not FileAccess.file_exists(selected_path):
		selected_path = ""
	GyroPaths.ensure_dirs()
	var count := 0
	var dir := DirAccess.open(projects_dir)
	if dir != null:
		var files := dir.get_files()
		var projects := []
		for file in files:
			if not str(file).ends_with(".json"):
				continue
			var base := str(file).get_basename()
			if base.contains("."):
				continue
			var path := projects_dir + str(file)
			var mod_time := FileAccess.get_modified_time(path)
			projects.append({"path": path, "file": str(file), "mod_time": mod_time})

		match _sort_mode:
			0: # Name
				projects.sort_custom(func(a, b): return a.file < b.file)
			1: # Last modified
				projects.sort_custom(func(a, b): return a.mod_time > b.mod_time)

		if _search_query != "":
			var q := _search_query.to_lower()
			projects = projects.filter(func(p): return p.file.to_lower().contains(q))

		for p in projects:
			_add_row(p.file)
			count += 1
			
	%EmptyState.visible = count == 0
	if count > 0 and animate:
		GyroUI.stagger_children(%ListVBox, 0.05)

func _add_row(file: String) -> void:
	var path := projects_dir + file
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.custom_minimum_size = Vector2(0, GyroUI.sz(90))
	
	var style := GyroUI.row_style(path == selected_path)
	card.add_theme_stylebox_override("panel", style)
	
	var hover_style := GyroUI.row_style(false).duplicate() as StyleBoxFlat
	hover_style.bg_color = DesignTokens.COLOR_SURFACE_2
	card.set_meta("hover_style", hover_style)
	card.set_meta("normal_style", style)
	
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.SPACING_MD)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	
	var icon_panel := PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(GyroUI.sz(60), GyroUI.sz(60))
	icon_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = DesignTokens.COLOR_ACCENT_SOFT
	icon_style.set_corner_radius_all(DesignTokens.RADIUS_MD)
	icon_panel.add_theme_stylebox_override("panel", icon_style)
	row.add_child(icon_panel)
	
	var project_icon := _load_project_icon(path)
	var icon_node: Node
	if project_icon != null:
		var texture_rect := TextureRect.new()
		texture_rect.texture = project_icon
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		texture_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mat := ShaderMaterial.new()
		mat.shader = _icon_round_shader
		var panel_size := Vector2(GyroUI.sz(60), GyroUI.sz(60))
		mat.set_shader_parameter("size", panel_size)
		mat.set_shader_parameter("radius", float(DesignTokens.RADIUS_MD))
		texture_rect.material = mat
		icon_node = texture_rect
	else:
		var icon_label := Label.new()
		icon_label.text = _get_project_letter(path)
		icon_label.add_theme_font_size_override("font_size", GyroUI.fs(24))
		icon_label.add_theme_color_override("font_color", DesignTokens.COLOR_ACCENT_HOVER)
		icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon_node = icon_label
	icon_panel.add_child(icon_node)
	
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_vbox.add_theme_constant_override("separation", 4)
	row.add_child(info_vbox)
	info_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var name_label := Label.new()
	name_label.text = file.get_basename()
	name_label.add_theme_font_size_override("font_size", GyroUI.fs(20))
	name_label.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info_vbox.add_child(name_label)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var more_wrap := CenterContainer.new()
	more_wrap.custom_minimum_size = Vector2(GyroUI.sz(48), GyroUI.sz(48))
	more_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	more_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(more_wrap)
	
	var more_btn := GyroUI.icon_button("res://ui/icons/more.svg", GyroUI.fs(24), 8)
	more_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	more_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	more_btn.pressed.connect(func(): _on_more_tapped(path))
	more_wrap.add_child(more_btn)
	
	%ListVBox.add_child(card)
	GyroUI.attach_tap(card, func(): _on_row_tapped(path))
	card.mouse_entered.connect(func():
		card.add_theme_stylebox_override("panel", card.get_meta("hover_style"))
	)
	card.mouse_exited.connect(func():
		card.add_theme_stylebox_override("panel", card.get_meta("normal_style"))
	)

func _get_project_letter(path: String) -> String:
	var name := path.get_file().get_basename()
	if name != "":
		return name.substr(0, 1).to_upper()
	return "?"

func _build_search_and_sort() -> void:
	_search_edit = %SearchEdit
	_search_edit.visible = true
	_search_edit.placeholder_text = GyroLang.t("search")
	_search_edit.text_changed.connect(func(text: String):
		_search_query = text
		refresh(false)
	)
	_sort_button = %SortButton
	_sort_button.visible = true
	_sort_button.pressed.connect(_toggle_sort)
	_update_sort_button_text()

func _toggle_sort() -> void:
	_sort_mode = (_sort_mode + 1) % 2
	_update_sort_button_text()
	refresh(false)

func _update_sort_button_text() -> void:
	if _sort_button == null:
		return
	var text := GyroLang.t("sort_by") + ": "
	match _sort_mode:
		0: text += GyroLang.t("sort_name")
		1: text += GyroLang.t("sort_modified")
	_sort_button.text = text

func _on_row_tapped(path: String) -> void:
	var now := Time.get_ticks_msec()
	if last_tap_path == path and now - last_tap_time < 400:
		last_tap_path = ""
		open_requested.emit(path)
		return
	selected_path = path
	last_tap_path = path
	last_tap_time = now
	refresh(false)

func _on_more_tapped(path: String) -> void:
	selected_path = path
	_open_project_panel()

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
	var path := projects_dir + clean + ".json"
	if FileAccess.file_exists(path):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("project_exists"))
		return
	var proj := GyroProject.new()
	proj.settings = GyroProjectSettings.new()
	proj.settings.app_name = clean
	var sanitized := ""
	for i in clean.length():
		var ch := clean[i]
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_":
			sanitized += ch
		elif ch == " " or ch == "-":
			sanitized += "_"
	while sanitized.length() > 0 and (sanitized[0] >= "0" and sanitized[0] <= "9" or sanitized[0] == "_"):
		sanitized = sanitized.substr(1)
	if sanitized == "":
		sanitized = "app"
	proj.settings.package_name = "com.example." + sanitized
	if GyroProjectJSON.save_to_file(proj, path):
		selected_path = path
		refresh(false)
	else:
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("create_failed"))

func _rename_project(name_text: String) -> void:
	if selected_path == "":
		return
	var clean := GyroUI.sanitize_name(name_text)
	if GyroUI.is_bad_name(clean):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("enter_correct_project_name"))
		return
	var new_path := selected_path.get_base_dir() + "/" + clean + ".json"
	if new_path == selected_path:
		refresh(false)
		return
	if FileAccess.file_exists(new_path):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("project_exists"))
		return
	if GyroProjectJSON.load_from_file(selected_path) == null:
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("rename_load_failed"))
		return
	var old_dir := _files_dir_for_path(selected_path)
	var new_dir := _files_dir_for_path(new_path)
	var old_backups := _backups_dir_for_path(selected_path)
	var new_backups := _backups_dir_for_path(new_path)
	var moved_files := false
	var moved_backups := false
	if DirAccess.dir_exists_absolute(old_dir):
		if DirAccess.rename_absolute(old_dir, new_dir) != OK:
			GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("rename_failed"))
			return
		moved_files = true
	if DirAccess.dir_exists_absolute(old_backups):
		if DirAccess.rename_absolute(old_backups, new_backups) != OK:
			if moved_files:
				DirAccess.rename_absolute(new_dir, old_dir)
			GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("rename_failed"))
			return
		moved_backups = true
	if DirAccess.rename_absolute(selected_path, new_path) != OK:
		if moved_backups:
			DirAccess.rename_absolute(new_backups, old_backups)
		if moved_files:
			DirAccess.rename_absolute(new_dir, old_dir)
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("rename_failed"))
		return
	for suffix in [".structure_ui.json", ".resources_ui.json"]:
		var old_ui: String = selected_path.get_basename() + suffix
		if FileAccess.file_exists(old_ui):
			DirAccess.rename_absolute(old_ui, new_path.get_basename() + suffix)
	selected_path = new_path
	refresh(false)

func _duplicate_project() -> void:
	if selected_path == "":
		return
	var base := selected_path.get_file().get_basename()
	var dir_path := selected_path.get_base_dir()
	var candidate := base + "_copy"
	var i := 2
	while FileAccess.file_exists(dir_path + "/" + candidate + ".json"):
		candidate = base + "_copy" + str(i)
		i += 1
	var dst_path := dir_path + "/" + candidate + ".json"
	var old_dir := _files_dir_for_path(selected_path)
	var new_dir := _files_dir_for_path(dst_path)
	if DirAccess.dir_exists_absolute(old_dir):
		if not _copy_dir_recursive(old_dir, new_dir):
			_remove_dir_recursive(new_dir)
			GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("duplicate_failed"))
			return
	if DirAccess.copy_absolute(selected_path, dst_path) != OK:
		_remove_dir_recursive(new_dir)
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("duplicate_failed"))
		return
	_close_project_panel()
	refresh(false)

func _do_delete() -> void:
	if selected_path != "":
		_remove_dir_recursive(_files_dir_for_path(selected_path))
		_remove_dir_recursive(_backups_dir_for_path(selected_path))
		for suffix in [".structure_ui.json", ".resources_ui.json"]:
			DirAccess.remove_absolute(selected_path.get_basename() + suffix)
		DirAccess.remove_absolute(selected_path)
		selected_path = ""
		_close_project_panel()
		refresh(false)

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

func _copy_dir_recursive(src_abs: String, dst_abs: String) -> bool:
	var err := DirAccess.make_dir_recursive_absolute(dst_abs)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return false
	var dir := DirAccess.open(src_abs)
	if dir == null:
		return false
	for f in dir.get_files():
		if DirAccess.copy_absolute(src_abs + "/" + str(f), dst_abs + "/" + str(f)) != OK:
			return false
	for d in dir.get_directories():
		if not _copy_dir_recursive(src_abs + "/" + str(d), dst_abs + "/" + str(d)):
			return false
	return true

func _do_import_archive(path: String) -> void:
	if path.ends_with(".json"):
		var loaded := GyroProjectJSON.load_from_file(path)
		var name := ""
		if loaded != null and loaded.settings != null and loaded.settings.app_name != "":
			name = GyroUI.sanitize_name(loaded.settings.app_name)
		if name == "" or GyroUI.is_bad_name(name):
			var file_base := path.get_file().get_basename()
			var m := RegEx.create_from_string("^imported_\\d+_(.+)$").search(file_base)
			if m != null:
				name = GyroUI.sanitize_name(m.get_string(1))
			else:
				name = file_base
		var base := name
		var i := 1
		while FileAccess.file_exists(projects_dir + base + ".json"):
			base = name + "_" + str(i)
			i += 1
		var copy_err := DirAccess.copy_absolute(path, projects_dir + base + ".json")
		if copy_err != OK:
			GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("import_failed"))
			return
		var src_files := path.get_basename() + ".files"
		if DirAccess.dir_exists_absolute(src_files):
			_copy_dir_recursive(src_files, projects_dir + base + ".files")
		if path.begins_with("user://imported_"):
			DirAccess.remove_absolute(path)
		refresh(false)
		return
	var raw_name := GyroProjectArchive.read_project_name(path)
	var base := GyroUI.sanitize_name(raw_name) if raw_name != "" else ""
	if base == "" or GyroUI.is_bad_name(base):
		var file_base := path.get_file().get_basename()
		var m := RegEx.create_from_string("^imported_\\d+_(.+)$").search(file_base)
		if m != null:
			base = GyroUI.sanitize_name(m.get_string(1))
		else:
			base = file_base
	if base.ends_with(".gyroproj"):
		base = base.substr(0, base.length() - 9)
	base = GyroUI.sanitize_name(base)
	if base == "" or GyroUI.is_bad_name(base):
		base = "imported"
	var candidate := base
	var i := 1
	while FileAccess.file_exists(projects_dir + candidate + ".json"):
		candidate = base + "_" + str(i)
		i += 1
	var result := GyroProjectArchive.import_project(path, projects_dir, candidate)
	if result == "":
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("import_failed"))
		return
	if path.begins_with("user://imported_"):
		DirAccess.remove_absolute(path)
	refresh(false)

func _load_project_icon(project_path: String) -> Texture2D:
	var icon_path := GyroProjectJSON.peek_icon_path(project_path)
	if icon_path == "":
		return null
	var resolved := GyroAssetPaths.resolve_asset_path(icon_path, project_path)
	if resolved == "" or not FileAccess.file_exists(resolved):
		return null
	return GyroMedia.load_texture(resolved)
