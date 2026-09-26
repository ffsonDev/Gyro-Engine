class_name ProjectSettingsScreen
extends Control

signal back_requested

var project: GyroProject
var save_path := ""
var updating := false

func _ready() -> void:
	%Title.add_theme_font_size_override("font_size", GyroUI.fs(28))

	%OrientationOption.add_item("авто", 0)
	%OrientationOption.add_item("портрет", 1)
	%OrientationOption.add_item("ландшафт", 2)

	%BackButton.pressed.connect(func(): back_requested.emit())
	%IconPickButton.pressed.connect(_pick_icon)

	%AppNameEdit.text_changed.connect(func(t: String):
		_change(func(): project.settings.app_name = t)
	)
	%PackageEdit.text_changed.connect(func(t: String):
		_change(func(): project.settings.package_name = t)
		%PackageEdit.modulate = Color.WHITE if _is_valid_package(t) else Color(1.0, 0.6, 0.6)
	)
	%IconEdit.text_changed.connect(func(t: String):
		_change(func(): project.settings.icon_path = t)
	)
	%VersionEdit.text_changed.connect(func(t: String):
		_change(func(): project.settings.version_name = t)
	)
	%VersionCodeEdit.text_changed.connect(func(t: String):
		_change(func(): project.settings.version_code = maxi(1, t.to_int()))
	)
	%PermsButton.pressed.connect(_open_perms)
	_setup_perms_overlay()
	%OrientationOption.item_selected.connect(func(id: int):
		_change(func():
			match id:
				1: project.settings.orientation = "portrait"
				2: project.settings.orientation = "landscape"
				_: project.settings.orientation = "auto"
		)
	)
	%KeystorePickButton.pressed.connect(_pick_keystore)
	%KeystoreEdit.text_changed.connect(func(t: String):
		_change(func(): project.settings.keystore_path = t)
	)
	%AliasEdit.text_changed.connect(func(t: String):
		_change(func(): project.settings.keystore_alias = t)
	)
	%PasswordEdit.text_changed.connect(func(t: String):
		_change(func(): project.settings.keystore_password = t)
	)
	apply_lang()

func apply_lang() -> void:
	%Title.text = GyroLang.t("project_settings")
	%AppNameLabel.text = GyroLang.t("app_name")
	%PackageLabel.text = GyroLang.t("package")
	%IconLabel.text = GyroLang.t("icon")
	%OrientLabel.text = GyroLang.t("orientation")
	%VersionLabel.text = GyroLang.t("version")
	%VersionCodeLabel.text = GyroLang.t("version_code")
	%PermsLabel.text = GyroLang.t("permissions")
	%OrientationOption.set_item_text(0, GyroLang.t("orient_auto"))
	%OrientationOption.set_item_text(1, GyroLang.t("orient_portrait"))
	%OrientationOption.set_item_text(2, GyroLang.t("orient_landscape"))
	%KeystoreLabel.text = GyroLang.t("keystore")
	%AliasLabel.text = GyroLang.t("alias")
	%PasswordLabel.text = GyroLang.t("password")

func setup(proj: GyroProject, path: String) -> void:
	project = proj
	save_path = path
	_refresh_fields()

func _refresh_fields() -> void:
	if project == null or project.settings == null:
		return

	updating = true
	%AppNameEdit.text = project.settings.app_name
	%PackageEdit.text = project.settings.package_name
	%IconEdit.text = project.settings.icon_path

	match project.settings.orientation:
		"portrait":
			%OrientationOption.select(1)
		"landscape":
			%OrientationOption.select(2)
		_:
			%OrientationOption.select(0)

	%PackageEdit.modulate = Color.WHITE if _is_valid_package(%PackageEdit.text) else Color(1.0, 0.6, 0.6)
	%VersionEdit.text = project.settings.version_name
	%VersionCodeEdit.text = str(project.settings.version_code)
	%PermsButton.text = GyroLang.t("permissions") + " (" + str(project.settings.permissions.size()) + ")"
	%KeystoreEdit.text = project.settings.keystore_path
	%AliasEdit.text = project.settings.keystore_alias
	%PasswordEdit.text = project.settings.keystore_password
	updating = false

func _change(callback: Callable) -> void:
	if updating:
		return
	callback.call()
	_save()

func _save() -> void:
	GyroUI.save_resource(project, save_path)

func _pick_icon() -> void:
	var on_selected := func(path: String):
		var ext := path.get_extension().to_lower()
		if ext == "svg":
			GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("svg_icon_error"))
			return
		var files_base := GyroAssetPaths.files_base_for_project(save_path)
		if files_base == "":
			GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("icon_path_missing"))
			return
		var dir := files_base + "icon/"
		DirAccess.make_dir_recursive_absolute(dir)
		var unique := GyroAssetPaths.make_unique_file_name(dir, path.get_file())
		var dest_abs := dir + unique
		var err := DirAccess.copy_absolute(path, dest_abs)
		if err != OK or not FileAccess.file_exists(dest_abs):
			GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("icon_copy_failed"))
			return
		var f := FileAccess.open(dest_abs, FileAccess.READ)
		if f == null:
			DirAccess.remove_absolute(dest_abs)
			GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("icon_read_failed"))
			return
		var head := f.get_buffer(12)
		var total := f.get_length()
		f.close()
		if total == 0 or not _is_image_magic(head):
			DirAccess.remove_absolute(dest_abs)
			GyroUI.alert(self, GyroLang.t("error"),
				(GyroLang.t("invalid_image_format") % [total, _hex(head)]) +
				GyroLang.t("heic_avif_warning")
			)
			return
		if path.begins_with("user://imported_"):
			DirAccess.remove_absolute(path)
		var rel := "icon/" + unique
		%IconEdit.text = rel
		project.settings.icon_path = rel
		_save()
		GyroUI.alert(self, GyroLang.t("icon"), GyroLang.t("icon_set") % rel)
	var on_failed := func(message: String):
		GyroUI.alert(self, GyroLang.t("icon"), message)
	GyroFilePicker.pick_file("sprite", on_selected, on_failed)

static func _is_image_magic(head: PackedByteArray) -> bool:
	if head.size() >= 4 and head[0] == 0x89 and head[1] == 0x50 and head[2] == 0x4E and head[3] == 0x47:
		return true # PNG
	if head.size() >= 3 and head[0] == 0xFF and head[1] == 0xD8 and head[2] == 0xFF:
		return true # JPEG
	if head.size() >= 12 and head.slice(0, 4).get_string_from_ascii() == "RIFF" and head.slice(8, 12).get_string_from_ascii() == "WEBP":
		return true # WebP
	return false

static func _hex(b: PackedByteArray) -> String:
	var s := ""
	for i in b.size():
		s += "%02X " % b[i]
	return s.strip_edges()

func _is_valid_package(value: String) -> bool:
	if value == "":
		return true

	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$")
	return regex.search(value) != null

const COMMON_PERMS := [
	"android.permission.INTERNET",
	"android.permission.ACCESS_NETWORK_STATE",
	"android.permission.VIBRATE",
	"android.permission.CAMERA",
	"android.permission.RECORD_AUDIO",
	"android.permission.ACCESS_FINE_LOCATION",
	"android.permission.ACCESS_COARSE_LOCATION",
	"android.permission.READ_MEDIA_IMAGES",
	"android.permission.READ_MEDIA_AUDIO",
	"android.permission.READ_MEDIA_VIDEO",
	"android.permission.POST_NOTIFICATIONS",
	"android.permission.WAKE_LOCK",
	"android.permission.BLUETOOTH_CONNECT",
	"android.permission.MODIFY_AUDIO_SETTINGS",
]
var perms_overlay: ColorRect
var perms_panel: PanelContainer
var perms_vbox: VBoxContainer

func _setup_perms_overlay() -> void:
	perms_overlay = ColorRect.new()
	perms_overlay.color = Color(0, 0, 0, 0.5)
	perms_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	perms_overlay.visible = false
	perms_overlay.z_index = 35
	perms_overlay.gui_input.connect(func(e: InputEvent):
		if GyroUI.is_tap(e):
			_close_perms()
	)
	add_child(perms_overlay)
	perms_panel = PanelContainer.new()
	perms_panel.visible = false
	perms_panel.z_index = 36
	GyroUI.center(perms_panel)
	add_child(perms_panel)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(GyroUI.dialog_width(480), 0)
	perms_panel.add_child(vbox)
	var top := HBoxContainer.new()
	vbox.add_child(top)
	var title := Label.new()
	title.text = GyroLang.t("permissions")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.pressed.connect(_close_perms)
	top.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, GyroUI.sz(320))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	perms_vbox = VBoxContainer.new()
	perms_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(perms_vbox)
	var ts := GyroTouchScroll.new()
	add_child(ts)
	ts.setup(scroll, [perms_overlay])

func _open_perms() -> void:
	if project == null or project.settings == null:
		return
	GyroUI.clear_children(perms_vbox)
	for perm in COMMON_PERMS:
		var cb := CheckBox.new()
		cb.text = perm.replace("android.permission.", "")
		cb.button_pressed = project.settings.permissions.has(perm)
		cb.toggled.connect(func(on: bool):
			if on and not project.settings.permissions.has(perm):
				project.settings.permissions.append(perm)
			elif not on:
				project.settings.permissions.erase(perm)
			_change(func():
				%PermsButton.text = GyroLang.t("permissions") + " (" + str(project.settings.permissions.size()) + ")"
			)
		)
		perms_vbox.add_child(cb)
	perms_overlay.visible = true
	perms_panel.visible = true

func _close_perms() -> void:
	perms_overlay.visible = false
	perms_panel.visible = false

func _pick_keystore() -> void:
	var on_selected := func(path: String):
		DirAccess.make_dir_recursive_absolute("user://keystore/")
		var dest := "user://keystore/release.p12"
		var err := DirAccess.copy_absolute(path, dest)
		if err != OK or not FileAccess.file_exists(dest):
			GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("keystore_copy_failed") % str(err))
			return
		if path.begins_with("user://imported_"):
			DirAccess.remove_absolute(path)
		%KeystoreEdit.text = dest
		project.settings.keystore_path = dest
		_save()
	var on_failed := func(message: String):
		GyroUI.alert(self, GyroLang.t("error"), message)
	GyroFilePicker.pick_file("other", on_selected, on_failed)
