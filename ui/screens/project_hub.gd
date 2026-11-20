class_name ProjectHubScreen
extends Control

signal back_requested
signal open_structure
signal open_resources
signal open_settings
signal reload_requested(path: String)

var project: GyroProject
var project_path := ""
var test_runner: TestRunner

func setup(proj: GyroProject, title: String, path: String) -> void:
	project = proj
	project_path = path
	%Title.text = title

func _ready() -> void:
	%Title.add_theme_font_size_override("font_size", GyroUI.fs(30))

	%BackButton.pressed.connect(func(): back_requested.emit())
	%StructureButton.pressed.connect(func(): open_structure.emit())
	%ResourcesButton.pressed.connect(func(): open_resources.emit())
	%SettingsButton.pressed.connect(func(): open_settings.emit())
	%BackupsButton.pressed.connect(_open_backups)
	%ExportButton.pressed.connect(_export_project)
	%PlayButton.pressed.connect(_play)
	_setup_build_button()

	%BackupsOverlay.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event):
			_close_backups()
	)
	
	test_runner = TestRunner.new()
	test_runner.setup(self, _get_merged_blueprint)
	test_runner.stopped.connect(_on_test_stopped)

	apply_lang()
	_animate_in()
	GyroUI.apply_background(self)
	_apply_glass_style(%BackupsPanel)

func _animate_in() -> void:
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, DesignTokens.ANIM_NORMAL).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func apply_lang() -> void:
	%StructureButton.text = GyroLang.t("structure")
	%ResourcesButton.text = GyroLang.t("resources")
	%SettingsButton.text = GyroLang.t("settings")
	%BackupsButton.text = GyroLang.t("backups")
	%ExportButton.text = GyroLang.t("export")

func _play() -> void:
	if project == null:
		return
	
	var orient = "portrait"
	if project.settings != null:
		orient = project.settings.orientation
	
	GyroUI.set_orientation(orient)
	
	%Root.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	test_runner.start(project, project_path)

func _on_test_stopped() -> void:
	%Root.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	GyroUI.set_orientation("portrait")

func stop_test() -> void:
	if test_runner != null:
		test_runner.stop()

func _get_merged_blueprint() -> GyroEventBlueprint:
	if project == null:
		return GyroEventBlueprint.new()
	return project.merge_blueprints()

func _stop() -> void:
	if test_runner != null:
		test_runner.stop()

func _open_backups() -> void:
	_refresh_backups()
	%BackupsOverlay.visible = true
	%BackupsPanel.visible = true

func _close_backups() -> void:
	%BackupsOverlay.visible = false
	%BackupsPanel.visible = false

func _refresh_backups() -> void:
	GyroUI.clear_children(%BackupsVBox)
	var make := Button.new()
	make.text = GyroLang.t("make_backup")
	make.custom_minimum_size = Vector2(0, GyroUI.sz(56))
	make.pressed.connect(func(): _create_backup_now(make))
	%BackupsVBox.add_child(make)
	for bp in GyroBackups.list_backups(project_path):
		var info := GyroBackups.backup_info(bp)
		var row := Button.new()
		row.text = "%s · %s" % [str(info.name), _fmt_size(int(info.size))]
		row.custom_minimum_size = Vector2(0, GyroUI.sz(56))
		row.pressed.connect(func(): _restore_backup(bp))
		%BackupsVBox.add_child(row)

func _create_backup_now(btn: Button) -> void:
	btn.disabled = true
	btn.text = GyroLang.t("backup_in_progress")
	GyroBackups.make_backup_async(project_path, true, func(ok: bool):
		if not is_instance_valid(btn):
			return
		btn.disabled = false
		btn.text = GyroLang.t("make_backup")
		_refresh_backups()
		GyroUI.alert(self, GyroLang.t("backups"),
			GyroLang.t("backup_created") if ok else GyroLang.t("backup_failed"))
	)

func _restore_backup(bp: String) -> void:
	_close_backups()
	if GyroBackups.restore_backup(project_path, bp):
		GyroUI.alert(self, GyroLang.t("backups"), GyroLang.t("backup_restored"))
		reload_requested.emit(project_path)
	else:
		GyroUI.alert(self, GyroLang.t("backups"), GyroLang.t("restore_backup_failed"))

func _fmt_size(bytes: int) -> String:
	if bytes >= 1048576:
		return "%.1f MB" % (bytes / 1048576.0)
	return "%d KB" % maxi(1, bytes / 1024)

func _export_project() -> void:
	if project == null or project_path == "":
		return
	var base := project_path.get_file().get_basename()
	var tmp := "user://_tmp_export.gyroproj"
	if not GyroProjectArchive.export_project(project_path, tmp):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("export_failed"))
		return
	
	GyroFilePicker.save_file(tmp, "other", base + ".gyroproj",
		func(saved_path):
			DirAccess.remove_absolute(tmp)
			GyroUI.alert(self, GyroLang.t("export"), GyroLang.t("export_success")),
		func(message):
			DirAccess.remove_absolute(tmp)
			GyroUI.alert(self, GyroLang.t("error"), message)
	)

var build_button: Button
var _build_dialog: GyroBuildDialog = null
var key_button: Button

func _setup_build_button() -> void:
	build_button = Button.new()
	build_button.name = "BuildApkButton"
	build_button.custom_minimum_size = Vector2(0, 72)
	build_button.text = GyroLang.t("build_apk")
	var anchor: Control = %ExportButton
	var parent: Node = anchor.get_parent()
	parent.add_child(build_button)
	parent.move_child(build_button, anchor.get_index() + 1)
	build_button.pressed.connect(_build_apk)

func _builds_dir() -> String:
	if OS.get_name() == "Android":
		return OS.get_user_data_dir() + "/builds/"
	var home := OS.get_environment("HOME")
	if home == "":
		home = OS.get_environment("USERPROFILE")
	if home == "":
		return OS.get_user_data_dir() + "/builds/"
	return home + "/Gyroprojects/builds/"

func _build_apk() -> void:
	if project == null:
		return
	DirAccess.make_dir_recursive_absolute("user://builds/")
	var pkg := project.settings.package_name
	if pkg == "":
		pkg = "com.gyro.game"
	var file_name := pkg + "-" + str(project.settings.version_name) + ".apk"
	var out_path := "user://builds/" + file_name

	if _build_dialog == null:
		_build_dialog = preload("res://ui/components/gyro_build_dialog.tscn").instantiate()
		add_child(_build_dialog)
		_build_dialog.build_completed.connect(_on_build_completed)

	_build_dialog.start_build(project, project_path, out_path)

func _on_build_completed(success: bool, output_path: String) -> void:
	if not success:
		return
	var src := FileAccess.open(output_path, FileAccess.READ)
	if src == null or src.get_length() == 0:
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("apk_empty_error"))
		return
	var kb := src.get_length() / 1024
	src.close()
	var file_name := output_path.get_file()
	var saved := await _save_apk_to_documents(output_path, file_name)
	if saved != "":
		GyroUI.alert(self, GyroLang.t("build_apk"), GyroLang.t("apk_saved_to") % saved + " (" + str(kb) + " " + GyroLang.t("kb") + ")")
	else:
		_share_built_apk(output_path, file_name)

func _save_apk_to_documents(src_path: String, file_name: String) -> String:
	if OS.get_name() != "Android":
		return ""
	var runtime := Engine.get_singleton("AndroidRuntime")
	if runtime == null:
		return ""
	var activity = runtime.getActivity()
	if activity == null:
		return ""
	var pre := FileAccess.open(src_path, FileAccess.READ)
	if pre == null or pre.get_length() == 0:
		return ""
	pre.close()
	var ContentValues := JavaClassWrapper.wrap("android.content.ContentValues")
	var MediaStoreFiles := JavaClassWrapper.wrap("android.provider.MediaStore$Files")
	var values = ContentValues.new()
	values.put("_display_name", file_name)
	values.put("mime_type", "application/vnd.android.package-archive")
	values.put("relative_path", "Documents/GyroEngine/")
	var uri = MediaStoreFiles.getContentUri("external")
	var resolver = activity.getContentResolver()
	var result_uri = resolver.insert(uri, values)
	if result_uri == null:
		return ""
	var out = resolver.openOutputStream(result_uri)
	if out == null:
		return ""
	var src := FileAccess.open(src_path, FileAccess.READ)
	if src == null:
		out.close()
		return ""
	var total := src.get_length()
	var copied := 0
	var chunk_size := 1024 * 1024
	while copied < total:
		var buf := src.get_buffer(mini(chunk_size, total - copied))
		if buf.size() == 0:
			break
		out.write(buf)
		copied += buf.size()
		await get_tree().process_frame
		if not is_instance_valid(self):
			src.close()
			out.close()
			return ""
	src.close()
	out.close()
	if copied < total:
		return ""
	return "Documents/GyroEngine/" + file_name	

var _pending_apk_path := ""

func _share_built_apk(out_path: String, file_name: String) -> void:
	if OS.get_name() == "Android" and Engine.has_singleton("GodotFilePicker"):
		var picker = Engine.get_singleton("GodotFilePicker")
		if not picker.is_connected("file_saved", _on_apk_saved):
			picker.connect("file_saved", _on_apk_saved)
		_pending_apk_path = out_path
		picker.saveFileAs(ProjectSettings.globalize_path(out_path), "application/vnd.android.package-archive", file_name)

func _exit_tree() -> void:
	if OS.get_name() == "Android" and Engine.has_singleton("GodotFilePicker"):
		var picker = Engine.get_singleton("GodotFilePicker")
		if picker.is_connected("file_saved", _on_apk_saved):
			picker.disconnect("file_saved", _on_apk_saved)
	if test_runner != null:
		test_runner.stop()

func _on_apk_saved(ok: bool, _uri: String) -> void:
	if ok:
		DirAccess.remove_absolute(_pending_apk_path)
	_pending_apk_path = ""

func add_move_node_action(obj_name: String, pos: Vector2) -> void:
	if project == null:
		return
	var changed := false
	for rule in _get_merged_blueprint().rules:
		if rule == null:
			continue
		for a_value in rule.actions:
			var a := a_value as GyroAction
			if a == null:
				continue
			if GyroBlockEditor.OBJECT_CREATING_ACTIONS.has(a.type) and str(a.data.get("name", "")) == obj_name:
				a.data["x"] = pos.x
				a.data["y"] = pos.y
				if a.data.has("anchor"):
					a.data["anchor"] = "free"
				changed = true
			elif a.type == "MoveNode" and str(a.data.get("mode", "delta")) == "set" and str(a.data.get("node", "")) == obj_name:
				a.data["x"] = pos.x
				a.data["y"] = pos.y
				changed = true
	if changed:
		GyroProjectJSON.save_to_file(project, project_path)

func _apply_glass_style(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = DesignTokens.PANEL_BG
	style.set_corner_radius_all(DesignTokens.RADIUS_XL)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = DesignTokens.PANEL_BORDER
	style.content_margin_left = DesignTokens.SPACING_XL
	style.content_margin_right = DesignTokens.SPACING_XL
	style.content_margin_top = DesignTokens.SPACING_XL
	style.content_margin_bottom = DesignTokens.SPACING_XL
	panel.add_theme_stylebox_override("panel", style)
