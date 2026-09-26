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
	make.pressed.connect(func():
		GyroBackups.make_backup_async(project.resource_path)
		_refresh_backups()
	)
	%BackupsVBox.add_child(make)

	for bp in GyroBackups.list_backups(project.resource_path):
		var row := Button.new()
		row.text = str(bp).get_file().get_basename()
		row.custom_minimum_size = Vector2(0, GyroUI.sz(56))
		row.pressed.connect(func(): _restore_backup(bp))
		%BackupsVBox.add_child(row)

func _restore_backup(bp: String) -> void:
	_close_backups()
	if GyroBackups.restore_backup(project.resource_path, bp):
		reload_requested.emit(project.resource_path)
	else:
		GyroUI.alert(self, GyroLang.t("backups"), GyroLang.t("restore_backup_failed"))

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

func _share_file(path: String) -> void:
	if OS.get_name() != "Android":
		return
	var runtime := Engine.get_singleton("AndroidRuntime")
	if runtime == null:
		return
	var activity = runtime.getActivity()
	if activity == null:
		return
	var FileClass := JavaClassWrapper.wrap("java.io.File")
	var file = FileClass.new(ProjectSettings.globalize_path(path))
	var FileProvider := JavaClassWrapper.wrap("androidx.core.content.FileProvider")
	var authority := str(activity.getPackageName()) + ".fileprovider"
	var uri = FileProvider.getUriForFile(activity, authority, file)
	if uri == null:
		return
	var Intent := JavaClassWrapper.wrap("android.content.Intent")
	var intent = Intent.new("android.intent.action.SEND")
	intent.setType("application/octet-stream")
	intent.putExtra("android.intent.extra.STREAM", uri)
	intent.addFlags(1)
	activity.startActivity(Intent.createChooser(intent, "Gyro Engine"))

var build_button: Button
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
	var err := GyroApkBuilder.build_project(project, project_path, out_path)
	if err != "":
		GyroUI.alert(self, GyroLang.t("error"), err)
		return
	var src := FileAccess.open(out_path, FileAccess.READ)
	if src == null or src.get_length() == 0:
		GyroUI.alert(self, GyroLang.t("error"), "Сборка создала пустой файл (0 байт).")
		return
	var kb := src.get_length() / 1024
	src.close()
	var saved := _save_apk_to_documents(out_path, file_name)
	if saved != "":
		GyroUI.alert(self, GyroLang.t("build_apk"), GyroLang.t("apk_saved_to") % saved + " (" + str(kb) + " КБ)")
	else:
		_share_built_apk(out_path, file_name)

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
	src.close()
	out.close()
	if copied < total:
		return ""
	return "Documents/GyroEngine/" + file_name

func _copy_to_downloads(src_abs: String, file_name: String) -> bool:
	if OS.get_name() != "Android":
		return false
	var runtime := Engine.get_singleton("AndroidRuntime")
	if runtime == null:
		return false
	var activity = runtime.getActivity()
	if activity == null:
		return false
	var ContentValues = JavaClassWrapper.wrap("android.content.ContentValues")
	var Uri = JavaClassWrapper.wrap("android.net.Uri")
	var values = ContentValues.new()
	values.put("_display_name", file_name)
	values.put("mime_type", "application/vnd.android.package-archive")
	var uri = Uri.parse("content://media/external/downloads")
	var resolver = activity.getContentResolver()
	var inserted = resolver.insert(uri, values)
	if inserted == null:
		return false
	var out = resolver.openOutputStream(inserted)
	if out == null:
		return false
	var src := FileAccess.open(src_abs, FileAccess.READ)
	if src == null:
		out.close()
		return false
	while true:
		var buf := src.get_buffer(1024 * 1024)
		if buf.is_empty():
			break
		out.write(buf)
	src.close()
	out.close()
	return true

func _share_apk(path: String) -> void:
	if OS.get_name() != "Android":
		return
	var runtime := Engine.get_singleton("AndroidRuntime")
	if runtime == null:
		return
	var activity = runtime.getActivity()
	if activity == null:
		return
	var FileClass := JavaClassWrapper.wrap("java.io.File")
	var file = FileClass.new(ProjectSettings.globalize_path(path))
	var FileProvider := JavaClassWrapper.wrap("androidx.core.content.FileProvider")
	var uri = FileProvider.getUriForFile(activity, str(activity.getPackageName()) + ".fileprovider", file)
	if uri == null:
		return
	var Intent := JavaClassWrapper.wrap("android.content.Intent")
	var intent = Intent.new("android.intent.action.SEND")
	intent.setType("application/vnd.android.package-archive")
	intent.putExtra("android.intent.extra.STREAM", uri)
	intent.addFlags(1)
	activity.startActivity(Intent.createChooser(intent, "Gyro APK"))

var _pending_apk_path := ""

func _share_built_apk(out_path: String, file_name: String) -> void:
	if OS.get_name() == "Android" and Engine.has_singleton("GodotFilePicker"):
		var picker = Engine.get_singleton("GodotFilePicker")
		if not picker.is_connected("file_saved", _on_apk_saved):
			picker.connect("file_saved", _on_apk_saved)
		_pending_apk_path = out_path
		picker.saveFileAs(ProjectSettings.globalize_path(out_path), "application/vnd.android.package-archive", file_name)
		GyroUI.alert(self, GyroLang.t("build_apk"), GyroLang.t("apk_save_hint"))
	else:
		GyroUI.alert(self, GyroLang.t("build_apk"), GyroLang.t("export_done") % out_path)

func _on_apk_saved(ok: bool, _uri: String) -> void:
	if ok:
		DirAccess.remove_absolute(_pending_apk_path)
		GyroUI.alert(self, GyroLang.t("build_apk"), GyroLang.t("apk_saved"))
	else:
		GyroUI.alert(self, GyroLang.t("build_apk"), GyroLang.t("apk_save_failed"))
	_pending_apk_path = ""

func _import_key() -> void:
	var on_selected := func(path: String):
		DirAccess.make_dir_recursive_absolute("user://keystore/")
		var dest := "user://keystore/release.p12"
		var err := DirAccess.copy_absolute(path, dest)
		if err != OK:
			GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("key_copy_failed"))
			return
		if path.begins_with("user://imported_"):
			DirAccess.remove_absolute(path)
		_ask_key_alias(dest)
	var on_failed := func(message: String):
		GyroUI.alert(self, GyroLang.t("import_key"), message)
	GyroFilePicker.pick_file("other", on_selected, on_failed)

func _ask_key_alias(key_path: String) -> void:
	var dialog := GyroInputDialog.new()
	add_child(dialog)
	dialog.open(
		GyroLang.t("key_alias"),
		GyroLang.t("key_alias_placeholder"),
		"gyro_sign",
		GyroLang.t("next"),
		GyroLang.t("cancel")
	)
	dialog.confirmed_text.connect(func(alias: String):
		dialog.queue_free()
		if alias.strip_edges() == "":
			GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("alias_empty_error"))
			return
		_ask_key_password(key_path, alias.strip_edges())
	)

func _ask_key_password(key_path: String, alias: String) -> void:
	var dialog := GyroInputDialog.new()
	add_child(dialog)
	dialog.open(
		GyroLang.t("key_password_title"),
		GyroLang.t("key_password_placeholder"),
		"",
		GyroLang.t("import"),
		GyroLang.t("cancel")
	)
	dialog.confirmed_text.connect(func(password: String):
		dialog.queue_free()
		if password.strip_edges() == "":
			GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("password_empty_error"))
			return
		_finish_import(key_path, alias, password.strip_edges())
	)

func _finish_import(key_path: String, alias: String, password: String) -> void:
	var KeyStore = JavaClassWrapper.wrap("java.security.KeyStore")
	if KeyStore == null:
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("keystore_access_error"))
		return
	var ks = KeyStore.getInstance("PKCS12")
	var JString = JavaClassWrapper.wrap("java.lang.String")
	var chars = JString.new(password).toCharArray()
	var FileInputStream = JavaClassWrapper.wrap("java.io.FileInputStream")
	var fis = FileInputStream.new(ProjectSettings.globalize_path(key_path))
	if fis == null:
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("keystore_open_error"))
		return
	ks.load(fis, chars)
	var key = ks.getKey(alias, chars)
	if key == null:
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("keystore_invalid_error"))
		DirAccess.remove_absolute(key_path)
		return
	var f := FileAccess.open("user://keystore/config.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"alias": alias, "password": password}))
		f.close()
