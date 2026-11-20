class_name ProjectResourcesScreen
extends Control

signal back_requested

var project: GyroProject
var save_path := ""
var selected_asset: GyroAsset
var selected_scope := ""
var expanded: Dictionary = {}
var _icon_round_shader: Shader

var drag_asset: GyroAsset
var drag_panel: Control
var drag_folder := ""
var drop_zones: Array = []
var current_drop: Dictionary = {}
var pointer := Vector2()
var drop_indicator: ColorRect

var picked_path := ""
var importing := false
var name_mode := ""
var name_target: Variant = null
var confirm_mode := ""
var confirm_asset: GyroAsset
var confirm_folder_path := ""
var preview_overlay: Control = null
var preview_audio: AudioStreamPlayer = null
var preview_video: VideoStreamPlayer = null
var _last_tap_asset: GyroAsset = null
var _last_tap_time := 0
var _touch_scroll: GyroTouchScroll
var preview_slider: HSlider = null
var preview_play_btn: Button = null
var preview_time_label: Label = null
var preview_len_label: Label = null
var _preview_len := 0.0
var _preview_seeking := false
var _imported_regex := RegEx.create_from_string("^imported_\\d+_(.+)$")
var _picked_regex := RegEx.create_from_string("^picked_\\d+_(.+)$")

func setup(proj: GyroProject, path: String) -> void:
	project = proj
	save_path = path
	selected_asset = null
	selected_scope = ""
	_load_ui_state()
	_refresh()
	GyroUI.apply_background(self)

func _ready() -> void:
	%Title.add_theme_font_size_override("font_size", GyroUI.fs(30))
	%EmptyTitle.add_theme_color_override("font_color", Color(0.55, 0.58, 0.63))
	%EmptyHint.add_theme_color_override("font_color", Color(0.42, 0.45, 0.49))

	%KindOption.add_item(GyroLang.t("kind_sprite"), 0)
	%KindOption.add_item(GyroLang.t("kind_sound"), 1)
	%KindOption.add_item(GyroLang.t("kind_font"), 2)
	%KindOption.add_item(GyroLang.t("kind_video"), 3)
	%KindOption.add_item(GyroLang.t("kind_other"), 4)
	
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

	drop_indicator = ColorRect.new()
	drop_indicator.color = Color(0.2, 0.8, 0.9)
	drop_indicator.visible = false
	drop_indicator.z_index = 5
	drop_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(drop_indicator)

	%BackButton.pressed.connect(func(): back_requested.emit())
	%GearButton.pressed.connect(_open_gear)
	%PlusButton.pressed.connect(_open_add_menu)

	%AddMenuOverlay.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event):
			_close_add_menu()
	)
	%AddMenuFolderButton.pressed.connect(func():
		_close_add_menu()
		_open_new_folder()
	)
	%AddMenuFileButton.pressed.connect(func():
		_close_add_menu()
		_open_add_panel()
	)

	%AddPanelOverlay.gui_input.connect(func(event: InputEvent):
		if not importing and GyroUI.is_tap(event):
			_close_add_panel()
	)
	%GearPanelOverlay.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event):
			_close_gear()
	)

	%PickButton.pressed.connect(_browse)
	%AddButton.pressed.connect(_add_asset)
	%CancelAddButton.pressed.connect(_close_add_panel)

	%GearRenameButton.pressed.connect(func():
		_close_gear()
		if selected_asset != null:
			_open_name_dialog("rename_asset", selected_asset)
		elif _is_folder_scope():
			_open_name_dialog("rename_folder", selected_scope)
	)
	%GearDeleteButton.pressed.connect(func():
		_close_gear()
		if selected_asset != null:
			_open_confirm_asset(selected_asset)
		elif _is_folder_scope():
			_open_confirm_folder(selected_scope)
	)

	%NameDialog.confirmed_text.connect(_apply_name)
	%ConfirmDialog.confirmed.connect(_do_confirm)

	var touch_scroll := GyroTouchScroll.new()
	add_child(touch_scroll)
	touch_scroll.setup(%Scroll, [%AddPanelOverlay, %GearPanelOverlay, %ImportOverlay, %NameDialog, %ConfirmDialog])
	_touch_scroll = touch_scroll 
	touch_scroll.gate = func(): return drag_asset == null
	
	visibility_changed.connect(func():
		if not visible:
			close_preview()
	)

	apply_lang()
	GyroUI.apply_glass_style(%AddPanel)
	GyroUI.apply_glass_style(%AddMenuPanel)
	GyroUI.apply_glass_style(%GearPanel)
	GyroUI.apply_glass_style(%ImportPanel)

func _process(_delta: float) -> void:
	if preview_overlay == null or not is_instance_valid(preview_overlay):
		return
	var player: Node = preview_audio if preview_audio != null else preview_video
	if player == null or not is_instance_valid(player):
		return
	var pos := float(player.call("get_playback_position"))
	if preview_slider != null and not _preview_seeking:
		preview_slider.value = clampf(pos, 0.0, maxf(0.001, _preview_len))
	if preview_time_label != null:
		preview_time_label.text = _fmt_time(pos)

func _open_new_folder() -> void:
	if selected_scope == "":
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("select_category"))
		return
	_open_name_dialog("folder", null)

func _open_add_menu() -> void:
	%AddMenuFolderButton.text = GyroLang.t("add_folder")
	%AddMenuFileButton.text = GyroLang.t("add_file")
	%AddMenuOverlay.visible = true
	%AddMenuPanel.visible = true

func _close_add_menu() -> void:
	%AddMenuOverlay.visible = false
	%AddMenuPanel.visible = false

func apply_lang() -> void:
	%Title.text = GyroLang.t("resources")
	%EmptyTitle.text = GyroLang.t("no_resources")
	%EmptyHint.text = GyroLang.t("no_resources_hint")
	%AddButton.text = GyroLang.t("add")
	%KindOption.set_item_text(0, GyroLang.t("kind_sprite"))
	%KindOption.set_item_text(1, GyroLang.t("kind_sound"))
	%KindOption.set_item_text(2, GyroLang.t("kind_font"))
	%KindOption.set_item_text(3, GyroLang.t("kind_video"))
	%KindOption.set_item_text(4, GyroLang.t("kind_other"))
	%CancelAddButton.text = GyroLang.t("cancel")
	%GearRenameButton.text = GyroLang.t("rename")
	%GearDeleteButton.text = GyroLang.t("delete")
	if picked_path == "":
		%PickButton.text = GyroLang.t("pick_file")

func _refresh(animate := true) -> void:
	GyroUI.clear_children(%ListVBox)
	drop_zones.clear()
	if project != null:
		for kind in ["sprite", "sound", "font", "video", "other"]:
			_build_category(kind)
	%EmptyState.visible = project == null or (project.assets.is_empty() and project.asset_folders.is_empty())
	%GearButton.disabled = selected_asset == null and not _is_folder_scope()
	_save_ui_state()
	if %ListVBox.get_child_count() > 0 and animate:
		GyroUI.stagger_children(%ListVBox, 0.03)

func _build_category(kind: String) -> void:
	var is_open: bool = expanded.get(kind, true)
	
	var outer := PanelContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.custom_minimum_size = Vector2(0, GyroUI.sz(56))
	outer.add_theme_stylebox_override("panel", GyroUI.row_style(selected_scope == kind, true))
	
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	outer.add_child(inner)
	
	var arrow := _make_arrow_button(expanded.get(kind, false))
	arrow.pressed.connect(func():
		expanded[kind] = not expanded.get(kind, false)
		_refresh(false)
	)
	inner.add_child(arrow)
	
	var ctitle := Label.new()
	ctitle.text = _kind_title(kind)
	ctitle.add_theme_font_size_override("font_size", GyroUI.fs(20))
	ctitle.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	ctitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(ctitle)
	
	%ListVBox.add_child(outer)
	
	GyroUI.attach_tap(outer, func(): _on_category_tapped(kind))
	
	drop_zones.append({"type": "kind", "path": kind, "control": outer})
	
	if is_open:
		_build_level(%ListVBox, kind, 1)
	
func _make_arrow_button(is_open: bool) -> Button:
	var path := "res://ui/icons/chevron_up.svg" if is_open else "res://ui/icons/chevron_down.svg"
	var btn := GyroUI.icon_button(path, GyroUI.fs(22), 10)
	btn.custom_minimum_size = Vector2(GyroUI.sz(48), GyroUI.sz(48))
	return btn

func _on_category_tapped(kind: String) -> void:
	selected_scope = kind
	selected_asset = null
	_refresh(false)

func _build_level(parent: Control, scope: String, depth: int) -> void:
	for folder_name in _subfolders_of(scope):
		var fp := scope + "/" + str(folder_name)
		var frow := HBoxContainer.new()
		frow.add_theme_constant_override("separation", 6)
		frow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if depth > 1:
			frow.add_child(GyroUI.make_guide(depth - 1, GyroUI.sz(56), false))

		var outer := PanelContainer.new()
		outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		outer.custom_minimum_size = Vector2(0, GyroUI.sz(56))
		outer.add_theme_stylebox_override("panel", GyroUI.row_style(selected_scope == fp, true))

		var inner := HBoxContainer.new()
		inner.add_theme_constant_override("separation", 8)
		outer.add_child(inner)

		var arrow := _make_arrow_button(expanded.get(fp, false))
		arrow.pressed.connect(func():
			expanded[fp] = not expanded.get(fp, false)
			_refresh(false)
		)
		inner.add_child(arrow)

		inner.add_child(GyroUI.icon("res://ui/icons/folder.svg", GyroUI.fs(18)))

		var name_label := Label.new()
		name_label.text = folder_name
		name_label.add_theme_font_size_override("font_size", GyroUI.fs(22))
		name_label.add_theme_color_override("font_color", Color.WHITE)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(name_label)
		
		GyroUI.attach_hold_drag(outer, func(): _start_folder_drag(fp, outer))

		frow.add_child(outer)
		parent.add_child(frow)

		GyroUI.attach_tap(outer, func(): _on_folder_tapped(fp))
		drop_zones.append({"type": "folder", "path": fp, "control": outer})

		if expanded.get(fp, false):
			_build_level(parent, fp, depth + 1)

	for v in project.assets:
		var a := v as GyroAsset
		if a == null:
			continue
		var in_scope := false
		if scope.contains("/"):
			in_scope = a.folder == scope
		else:
			in_scope = a.kind == scope and (a.folder == "" or a.folder == scope)
		if not in_scope:
			continue
		_build_asset_row(parent, a, depth)

func _build_asset_row(parent: Control, a: GyroAsset, depth: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if depth > 1:
		row.add_child(GyroUI.make_guide(depth - 1, GyroUI.sz(72), true))
		
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, GyroUI.sz(72))
	panel.add_theme_stylebox_override("panel", GyroUI.row_style(selected_asset == a, true))
	
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	panel.add_child(inner)
	
	var icon_panel := PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(GyroUI.sz(60), GyroUI.sz(60))
	icon_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = _asset_type_color(a.kind)
	icon_style.set_corner_radius_all(DesignTokens.RADIUS_MD)
	icon_panel.add_theme_stylebox_override("panel", icon_style)
	inner.add_child(icon_panel)
	
	var icon_node := _make_asset_icon(a)
	icon_panel.add_child(icon_node)
	
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_vbox.add_theme_constant_override("separation", 4)
	inner.add_child(info_vbox)
	
	info_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := Label.new()
	name_label.text = a.asset_name
	name_label.add_theme_font_size_override("font_size", GyroUI.fs(22))
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info_vbox.add_child(name_label)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	GyroUI.attach_hold_drag(panel, func(): _start_asset_drag(a, panel))
	
	row.add_child(panel)
	parent.add_child(row)
	
	GyroUI.attach_tap(panel, func(): _on_asset_tapped(a))
	drop_zones.append({"type": "asset", "asset": a, "control": panel})

func _on_folder_tapped(fp: String) -> void:
	selected_scope = fp
	selected_asset = null
	_refresh(false)

func _on_asset_tapped(a: GyroAsset) -> void:
	var now := Time.get_ticks_msec()
	if _last_tap_asset == a and now - _last_tap_time < 400:
		_last_tap_asset = null
		_open_preview(a)
		return
	_last_tap_asset = a
	_last_tap_time = now
	selected_asset = a
	_refresh(false)

func _is_folder_scope() -> bool:
	return selected_scope != "" and selected_scope.contains("/")

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		pointer = event.position
	if event is InputEventScreenTouch and not event.pressed:
		if drag_asset != null:
			_finish_drag()
		elif drag_folder != "":
			_finish_folder_drag()
	elif event is InputEventMouseButton and not event.pressed:
		if drag_asset != null:
			_finish_drag()
		elif drag_folder != "":
			_finish_folder_drag()
	if drag_asset != null or drag_folder != "":
		_update_drop_target()

func _start_asset_drag(a: GyroAsset, panel: Control) -> void:
	drag_asset = a
	drag_panel = panel
	panel.modulate.a = 0.5
	_update_drop_target()

func _start_folder_drag(fp: String, panel: Control) -> void:
	drag_folder = fp
	drag_panel = panel
	panel.modulate.a = 0.5
	_update_drop_target()

func _finish_folder_drag() -> void:
	if drag_panel != null and is_instance_valid(drag_panel):
		drag_panel.modulate.a = 1.0
	%Scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	if drag_folder != "" and not current_drop.is_empty():
		if current_drop.type == "folder":
			var target_fp: String = current_drop.path
			if target_fp != drag_folder and not target_fp.begins_with(drag_folder + "/"):
				_move_folder(drag_folder, target_fp)
				_save_project()
				_refresh(false)
	current_drop = {}
	drag_folder = ""
	drag_panel = null
	drop_indicator.visible = false

func _move_folder(old_fp: String, new_parent: String) -> void:
	var folder_name := old_fp.get_file()
	var new_fp := _join(new_parent, folder_name)
	if new_fp == old_fp or project.asset_folders.has(new_fp):
		return
	var prefix := old_fp + "/"
	var new_folders: Array = []
	for f in project.asset_folders:
		if str(f) == old_fp:
			new_folders.append(new_fp)
		elif str(f).begins_with(prefix):
			new_folders.append(new_fp + "/" + str(f).substr(prefix.length()))
		else:
			new_folders.append(f)
	project.asset_folders.clear()
	for f in new_folders:
		project.asset_folders.append(f)
	for v in project.assets:
		var a := v as GyroAsset
		if a == null:
			continue
		if a.folder == old_fp:
			a.folder = new_fp
		elif a.folder.begins_with(prefix):
			a.folder = new_fp + "/" + a.folder.substr(prefix.length())
	if selected_scope == old_fp:
		selected_scope = new_fp
	expanded.erase(old_fp)
	expanded[new_fp] = true

func _update_drop_target() -> void:
	current_drop = {}
	
	var is_dragging_folder := drag_folder != ""
	var is_dragging_asset := drag_asset != null
	
	for zone in drop_zones:
		var rect: Rect2 = zone.control.get_global_rect()
		if not rect.has_point(pointer):
			continue
		
		if zone.type == "kind":
			if is_dragging_folder:
				continue
			elif is_dragging_asset:
				if zone.path != drag_asset.kind:
					continue
				current_drop = {"type": "kind", "path": zone.path, "x": rect.position.x, "y": rect.end.y - 2, "w": rect.size.x}
		elif zone.type == "folder":
			if is_dragging_folder:
				if zone.path == drag_folder:
					break
				if zone.path.begins_with(drag_folder + "/"):
					break
				current_drop = {"type": "folder", "path": zone.path, "x": rect.position.x, "y": rect.end.y - 2, "w": rect.size.x}
			elif is_dragging_asset:
				if not str(zone.path).begins_with(drag_asset.kind + "/"):
					continue
				current_drop = {"type": "folder", "path": zone.path, "x": rect.position.x, "y": rect.end.y - 2, "w": rect.size.x}
		elif zone.type == "asset" and is_dragging_asset:
			if zone.asset == drag_asset or zone.asset.kind != drag_asset.kind:
				continue
			var before := pointer.y < rect.position.y + rect.size.y * 0.5
			current_drop = {"type": "asset", "asset": zone.asset, "before": before, "x": rect.position.x, "y": rect.position.y if before else rect.end.y, "w": rect.size.x}
		
		if not current_drop.is_empty():
			break
	
	if current_drop.is_empty():
		drop_indicator.visible = false
	else:
		drop_indicator.visible = true
		drop_indicator.global_position = Vector2(current_drop.x, current_drop.y - 2)
		drop_indicator.size = Vector2(current_drop.w, 4)

func _finish_drag() -> void:
	if drag_panel != null and is_instance_valid(drag_panel):
		drag_panel.modulate.a = 1.0
	%Scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	if drag_asset != null and not current_drop.is_empty():
		if current_drop.type == "kind":
			if current_drop.path == drag_asset.kind and drag_asset.folder != "":
				drag_asset.folder = ""
				_save_project()
				_refresh(false)
		elif current_drop.type == "folder":
			var fp: String = current_drop.path
			if fp.begins_with(drag_asset.kind + "/") and drag_asset.folder != fp:
				drag_asset.folder = fp
				expanded[fp] = true
				_save_project()
				_refresh(false)
		else:
			var target: GyroAsset = current_drop.asset
			var from_index := project.assets.find(drag_asset)
			if from_index >= 0:
				project.assets.remove_at(from_index)
				var to_index := project.assets.find(target)
				if to_index >= 0:
					if not current_drop.before:
						to_index += 1
					drag_asset.folder = _folder_for_drop(target)
					project.assets.insert(to_index, drag_asset)
					_save_project()
					_refresh(false)
	current_drop = {}
	drag_asset = null
	drag_panel = null
	drop_indicator.visible = false

func _folder_for_drop(target: GyroAsset) -> String:
	if drag_asset == null:
		return target.folder
	if target.folder.begins_with(drag_asset.kind + "/"):
		return target.folder
	return ""

func _open_add_panel() -> void:
	picked_path = ""
	%PickButton.text = GyroLang.t("pick_file")
	%NameEdit.text = ""
	if selected_scope != "":
		var kind_part := selected_scope.split("/")[0]
		for i in 5:
			if _kind_by_id(i) == kind_part:
				%KindOption.select(i)
				break
	%AddPanelOverlay.visible = true
	%AddPanel.visible = true

func _close_add_panel() -> void:
	%AddPanelOverlay.visible = false
	%AddPanel.visible = false

func _browse() -> void:
	var kind := _kind_by_id(%KindOption.selected)
	var on_selected := func(path: String):
		picked_path = path
		if %NameEdit.text == "":
			%NameEdit.text = _clean_pick_name(path)
	var on_failed := func(message: String):
		GyroUI.alert(self, GyroLang.t("pick_file"), message)
	GyroFilePicker.pick_file(kind, on_selected, on_failed)

func _clean_pick_name(path: String) -> String:
	var f := GyroFilePicker.last_picked_file
	if f == "":
		f = path.get_file()
	var m := _imported_regex.search(f)
	if m != null:
		f = m.get_string(1)
	var m2 := _picked_regex.search(f)
	if m2 != null:
		f = m2.get_string(1)
	return f.get_basename()

func _add_asset() -> void:
	if importing:
		return
	var kind := _kind_by_id(%KindOption.selected)
	var src := picked_path
	var clean := GyroUI.sanitize_name(%NameEdit.text)
	if clean == "":
		clean = src.get_file().get_basename() if src != "" else "asset"
	if GyroUI.is_bad_name(clean):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("enter_correct_asset_name"))
		return
	if _has_asset_name(clean, kind, null):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("asset_exists"))
		return
	if save_path == "":
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("error"))
		return
	var files_base := GyroAssetPaths.files_base_for_project(save_path)
	if files_base == "":
		GyroUI.alert(self, GyroLang.t("project_error"), GyroLang.t("project_path_missing"))
		return
	var stored_relative := ""
	if src != "" and src.begins_with(files_base):
		var rel := GyroAssetPaths.normalize_asset_path(src, save_path)
		if FileAccess.file_exists(src) and rel.begins_with(kind + "/"):
			stored_relative = rel
	if stored_relative == "":
		if src == "" or not FileAccess.file_exists(src):
			GyroUI.alert(self, GyroLang.t("file_not_found"), GyroLang.t("source_file_not_found") % src)
			return
		var abs_dir := files_base + kind + "/"
		var dir_err := DirAccess.make_dir_recursive_absolute(abs_dir)
		if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
			GyroUI.alert(self, GyroLang.t("access_error"), GyroLang.t("assets_folder_create_failed_path") % abs_dir)
			return
		var desired := GyroFilePicker.last_picked_file if GyroFilePicker.last_picked_file != "" else src.get_file()
		var unique_name := GyroAssetPaths.make_unique_file_name(abs_dir, desired)
		var dest_abs := abs_dir + unique_name
		_set_importing(true, GyroLang.t("copying_file"))
		var ok := await _copy_file_with_progress(src, dest_abs)
		_set_importing(false)
		if not ok:
			return
		if kind == "sprite" and project != null and project.settings != null and project.settings.compress_textures:
			_set_importing(true, GyroLang.t("compressing"))
			await get_tree().process_frame
			var cres := GyroTextureCodec.process_sprite_file(dest_abs)
			if cres.ok and str(cres.new_path) != "":
				dest_abs = str(cres.new_path)
				unique_name = dest_abs.get_file()
			if cres.ok and OS.get_name() == "Android":
				GyroTextureCodec.build_gtx_file(dest_abs, dest_abs + ".gtx")
			_set_importing(false)
		if src.begins_with("user://imported_"):
			DirAccess.remove_absolute(src)
		stored_relative = kind + "/" + unique_name
	var folder := ""
	if selected_scope.begins_with(kind + "/"):
		folder = selected_scope
	var asset := GyroAsset.new()
	asset.id = _new_asset_id()
	asset.kind = kind
	asset.asset_name = clean
	asset.path = stored_relative
	asset.folder = folder
	project.assets.append(asset)
	expanded[kind] = true
	if folder != "":
		expanded[folder] = true
	_close_add_panel()
	_save_project()
	_refresh(false)

func _set_importing(active: bool, text: String = "") -> void:
	importing = active
	if text != "":
		%ImportLabel.text = text
	%ImportProgress.value = 0.0
	%ImportOverlay.visible = active
	%ImportPanel.visible = active
	
	if active:
		var skeleton := SkeletonLoader.new()
		skeleton.name = "ImportSkeleton"
		skeleton.custom_minimum_size = Vector2(0, GyroUI.sz(24))
		skeleton.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		%ImportVBox.add_child(skeleton)
	else:
		var old_skel = %ImportVBox.get_node_or_null("ImportSkeleton")
		if old_skel:
			old_skel.stop_and_free()

func _copy_file_with_progress(src: String, dst: String) -> bool:
	var src_file := FileAccess.open(src, FileAccess.READ)
	if src_file == null:
		return false
	var dst_file := FileAccess.open(dst, FileAccess.WRITE)
	if dst_file == null:
		src_file.close()
		return false
	var total := src_file.get_length()
	if total <= 0:
		src_file.close()
		dst_file.close()
		return false
	var copied := 0
	var failed := false
	var chunk_size := 1024 * 1024
	while copied < total:
		var read_size := mini(chunk_size, total - copied)
		var buffer := src_file.get_buffer(read_size)
		if buffer.size() == 0:
			failed = true
			break
		dst_file.store_buffer(buffer)
		copied += buffer.size()
		%ImportProgress.value = float(copied) / float(total)
		await get_tree().process_frame
	src_file.close()
	dst_file.close()
	if failed or copied < total:
		DirAccess.remove_absolute(dst)
		return false
	return true

func _open_gear() -> void:
	if selected_asset != null:
		%GearTitle.text = GyroLang.t("resource_prefix") + selected_asset.asset_name
	elif selected_scope != "":
		%GearTitle.text = GyroLang.t("folder_prefix") + selected_scope
	%GearPanelOverlay.visible = true
	%GearPanel.visible = true

func _close_gear() -> void:
	%GearPanelOverlay.visible = false
	%GearPanel.visible = false

func _open_name_dialog(mode: String, target: Variant) -> void:
	name_mode = mode
	name_target = target
	var title := ""
	var initial := ""
	match mode:
		"folder":
			title = GyroLang.t("new_folder")
		"rename_asset":
			title = GyroLang.t("rename")
			initial = (target as GyroAsset).asset_name
		"rename_folder":
			title = GyroLang.t("rename")
			var parts := String(target).split("/")
			initial = parts[parts.size() - 1]
	%NameDialog.open(title, GyroLang.t("name_placeholder"), initial)

func _apply_name(name_text: String) -> void:
	var clean := GyroUI.sanitize_name(name_text)
	if GyroUI.is_bad_name(clean):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("enter_correct_name"))
		return
	match name_mode:
		"folder":
			var fp := selected_scope + "/" + clean
			if project.asset_folders.has(fp):
				GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("folder_exists"))
				return
			project.asset_folders.append(fp)
			expanded[selected_scope] = true
			expanded[fp] = true
		"rename_asset":
			var target := name_target as GyroAsset
			if target != null:
				if clean != target.asset_name and _has_asset_name(clean, target.kind, target):
					GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("asset_exists"))
					return
				target.asset_name = clean
		"rename_folder":
			var old_fp := String(name_target)
			var parent := _parent_of(old_fp)
			var new_fp := _join(parent, clean)
			if new_fp != old_fp and project.asset_folders.has(new_fp):
				GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("folder_exists"))
				return
			if new_fp != old_fp:
				_rename_folder_recursive(old_fp, new_fp)
	_save_project()
	_refresh(false)

func _rename_folder_recursive(old_fp: String, new_fp: String) -> void:
	var prefix := old_fp + "/"
	var new_folders: Array = []
	for f in project.asset_folders:
		if str(f) == old_fp:
			new_folders.append(new_fp)
		elif str(f).begins_with(prefix):
			new_folders.append(new_fp + "/" + str(f).substr(prefix.length()))
		else:
			new_folders.append(f)
	project.asset_folders.clear()
	for f in new_folders:
		project.asset_folders.append(f)
	for v in project.assets:
		var a := v as GyroAsset
		if a == null:
			continue
		if a.folder == old_fp:
			a.folder = new_fp
		elif a.folder.begins_with(prefix):
			a.folder = new_fp + "/" + a.folder.substr(prefix.length())
	if selected_scope == old_fp:
		selected_scope = new_fp

func _open_confirm_asset(a: GyroAsset) -> void:
	confirm_mode = "asset"
	confirm_asset = a
	%ConfirmDialog.open(GyroLang.t("delete"), GyroLang.t("delete_asset_q") % a.asset_name, GyroLang.t("delete"), GyroLang.t("cancel"))

func _open_confirm_folder(fp: String) -> void:
	confirm_mode = "folder"
	confirm_folder_path = fp
	%ConfirmDialog.open(GyroLang.t("delete"), GyroLang.t("delete_folder_q") % fp, GyroLang.t("delete"), GyroLang.t("cancel"))

func _do_confirm() -> void:
	if confirm_mode == "asset" and confirm_asset != null:
		GyroMedia.invalidate_texture(GyroAssetPaths.resolve_asset_path(confirm_asset.path, save_path))
		project.assets.erase(confirm_asset)
		if selected_asset == confirm_asset:
			selected_asset = null
		confirm_asset = null
	elif confirm_mode == "folder" and confirm_folder_path != "":
		_delete_folder(confirm_folder_path)
		if selected_scope == confirm_folder_path:
			selected_scope = ""
		confirm_folder_path = ""
	confirm_mode = ""
	_save_project()
	_refresh(false)

func _delete_folder(fp: String) -> void:
	var parent_scope := _parent_of(fp)
	var prefix := fp + "/"
	for v in project.assets:
		var a := v as GyroAsset
		if a == null:
			continue
		if a.folder == fp:
			if parent_scope == a.kind:
				a.folder = ""
			else:
				a.folder = parent_scope
		elif a.folder.begins_with(prefix):
			var rest := a.folder.substr(prefix.length())
			a.folder = parent_scope + "/" + rest
	var to_remove: Array = []
	for f in project.asset_folders:
		if str(f) == fp or str(f).begins_with(prefix):
			to_remove.append(f)
	for f in to_remove:
		project.asset_folders.erase(f)
	expanded.erase(fp)

func _has_asset_name(asset_name: String, kind: String, exclude: GyroAsset) -> bool:
	for v in project.assets:
		var a := v as GyroAsset
		if a == null or a == exclude:
			continue
		if a.kind == kind and a.asset_name == asset_name:
			return true
	return false

func _subfolders_of(scope: String) -> Array:
	var result: Array = []
	var prefix := scope + "/"
	var all: Array = []
	for f in project.asset_folders:
		if str(f) != "" and not all.has(f):
			all.append(f)
	for v in project.assets:
		var a := v as GyroAsset
		if a != null and a.folder != "" and not all.has(a.folder):
			all.append(a.folder)
	for f in all:
		if str(f).begins_with(prefix):
			var rest := str(f).substr(prefix.length())
			var first := rest.split("/")[0]
			if first != "" and not result.has(first):
				result.append(first)
	result.sort()
	return result

func _kind_title(kind: String) -> String:
	return GyroLang.t("kinds_" + kind)

func _kind_by_id(id: int) -> String:
	match id:
		0:
			return "sprite"
		1:
			return "sound"
		2:
			return "font"
		3:
			return "video"
	return "other"

func _new_asset_id() -> String:
	return "a" + str(Time.get_unix_time_from_system()) + str(randi() % 100000)

func _save_project() -> void:
	if project != null and save_path != "":
		GyroProjectJSON.save_to_file(project, save_path)

func _ui_state_path() -> String:
	if save_path == "":
		return ""
	return save_path.get_basename() + ".resources_ui.json"

func _legacy_ui_state_path() -> String:
	if save_path == "":
		return ""
	return save_path.get_basename()

func _load_ui_state() -> void:
	expanded = {}
	if save_path == "":
		return
	var path := _ui_state_path()
	if not FileAccess.file_exists(path) and FileAccess.file_exists(_legacy_ui_state_path()):
		path = _legacy_ui_state_path()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and parsed.has("state"):
		var state: Variant = parsed["state"]
		for k in state.keys():
			expanded[str(k)] = bool(state[k])

func _save_ui_state() -> void:
	if save_path == "":
		return
	var state := {}
	for kind in ["sprite", "sound", "font", "video", "other"]:
		state[kind] = expanded.get(kind, true)
	for k in expanded.keys():
		if expanded[k] and not state.has(k):
			state[k] = true
	var f := FileAccess.open(_ui_state_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"state": state}))
	f.close()

func _parent_of(fp: String) -> String:
	var idx := fp.rfind("/")
	if idx < 0:
		return ""
	return fp.substr(0, idx)

func _join(parent: String, child: String) -> String:
	if parent == "":
		return child
	return parent + "/" + child

func is_preview_open() -> bool:
	return preview_overlay != null and is_instance_valid(preview_overlay)

func close_preview() -> void:
	if preview_audio != null and is_instance_valid(preview_audio):
		preview_audio.stop()
		preview_audio.queue_free()
		preview_audio = null
	if preview_video != null and is_instance_valid(preview_video):
		preview_video.stop()
		preview_video.queue_free()
		preview_video = null
	if preview_overlay != null and is_instance_valid(preview_overlay):
		preview_overlay.queue_free()
		preview_overlay = null

func _open_preview(a: GyroAsset) -> void:
	_close_preview()
	var resolved := GyroAssetPaths.resolve_asset_path(a.path, save_path)
	
	var ext := resolved.get_extension().to_lower()
	var kind := a.kind
	
	if kind == "sprite" and ext in ["png", "jpg", "jpeg", "webp", "svg"]:
		pass
	elif kind == "sound" and ext in ["mp3", "ogg", "wav"]:
		pass
	elif kind == "font" and ext in ["ttf", "otf", "woff2"]:
		pass
	elif kind == "video" and ext in ["webm", "ogv"]:
		pass
	else:
		if ext in ["png", "jpg", "jpeg", "webp", "svg"]:
			kind = "sprite"
		elif ext in ["mp3", "ogg", "wav"]:
			kind = "sound"
		elif ext in ["ttf", "otf", "woff2"]:
			kind = "font"
		elif ext in ["webm", "ogv"]:
			kind = "video"
	
	preview_overlay = Control.new()
	preview_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_overlay.z_index = 70
	
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_overlay.add_child(bg)

	var title := Label.new()
	title.text = a.asset_name
	title.add_theme_font_size_override("font_size", GyroUI.fs(22))
	title.add_theme_color_override("font_color", Color.WHITE)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_left = 64
	title.offset_right = -64
	title.offset_top = 16
	title.offset_bottom = 56
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_overlay.add_child(title)

	var close_btn := GyroUI.icon_button("res://ui/icons/close.svg", GyroUI.fs(32))
	close_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_btn.offset_left = -64
	close_btn.offset_top = 8
	close_btn.offset_right = -8
	close_btn.offset_bottom = 64
	close_btn.pressed.connect(_close_preview)
	preview_overlay.add_child(close_btn)

	var content := Control.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 16
	content.offset_right = -16
	content.offset_top = 64
	content.offset_bottom = -96
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_overlay.add_child(content)

	match kind:
		"sprite":
			_preview_sprite(content, resolved)
		"font":
			_preview_font(content, resolved)
		"video":
			_preview_video(content, resolved)
		"sound":
			_preview_sound(content, resolved)
		_:
			_preview_unsupported(content, a.kind)

	if preview_audio != null or preview_video != null:
		_build_preview_controls()

	add_child(preview_overlay)

	if _touch_scroll != null:
		_touch_scroll.block_nodes.append(preview_overlay)

func _close_preview() -> void:
	if preview_audio != null and is_instance_valid(preview_audio):
		preview_audio.stop()
		preview_audio.stream = null
		preview_audio.queue_free()
	preview_audio = null
	if preview_video != null and is_instance_valid(preview_video):
		preview_video.stop()
		preview_video.stream = null
		preview_video.queue_free()
	preview_video = null
	if preview_overlay != null and is_instance_valid(preview_overlay):
		if _touch_scroll != null:
			_touch_scroll.block_nodes.erase(preview_overlay)
		preview_overlay.queue_free()
	preview_overlay = null
	preview_slider = null
	preview_play_btn = null
	preview_time_label = null
	preview_len_label = null
	_preview_len = 0.0
	_preview_seeking = false

func _preview_sprite(content: Control, resolved: String) -> void:
	var tex := GyroMedia.load_texture(resolved)
	if tex == null:
		_preview_unsupported(content, "sprite")
		return
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(rect)

func _preview_font(content: Control, resolved: String) -> void:
	var font: Font = null
	if ResourceLoader.exists(resolved):
		font = ResourceLoader.load(resolved) as Font
	elif FileAccess.file_exists(resolved):
		var ff := FontFile.new()
		if ff.load_dynamic_font(resolved) == OK:
			font = ff
	if font == null:
		_preview_unsupported(content, "font")
		return
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	content.add_child(vbox)
	var samples := [
		[GyroUI.fs(34), "Aa Bb Cc 0123"],
		[GyroUI.fs(22), "Съешь ещё этих мягких французских булок"],
		[GyroUI.fs(15), "The quick brown fox jumps over the lazy dog"],
	]
	for s in samples:
		var l := Label.new()
		l.text = str(s[1])
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", int(s[0]))
		l.add_theme_color_override("font_color", Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(l)

func _preview_video(content: Control, resolved: String) -> void:
	var stream: VideoStream = null
	if ResourceLoader.exists(resolved):
		stream = ResourceLoader.load(resolved) as VideoStream
	elif FileAccess.file_exists(resolved):
		var ext := resolved.get_extension().to_lower()
		if ext == "ogv":
			var th := VideoStreamTheora.new()
			th.file = resolved
			stream = th
		elif ext == "webm" and ClassDB.class_exists("VideoStreamWebM"):
			stream = ClassDB.instantiate("VideoStreamWebM") as VideoStream
			stream.set("file", resolved)
	if stream == null:
		_preview_unsupported(content, "video")
		return
	preview_video = VideoStreamPlayer.new()
	preview_video.stream = stream
	preview_video.expand = true
	_play_when_in_tree(preview_video)
	preview_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(preview_video)
	_preview_len = stream.get_length()

func _preview_sound(content: Control, resolved: String) -> void:
	var stream := GyroMedia.load_audio(resolved)
	if stream == null:
		_preview_unsupported(content, "sound")
		return
	preview_audio = AudioStreamPlayer.new()
	preview_audio.stream = stream
	preview_overlay.add_child(preview_audio)
	_preview_len = stream.get_length()
	_play_when_in_tree(preview_audio)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(center)
	center.add_child(GyroUI.icon("res://ui/icons/play.svg", GyroUI.fs(64), Color(0.6, 0.62, 0.66)))

func _preview_unsupported(content: Control, kind: String) -> void:
	var key := "preview_unsupported_video" if kind == "video" else "preview_unsupported"
	var label := Label.new()
	label.text = GyroLang.t(key)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", GyroUI.fs(16))
	label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(label)

func _build_preview_controls() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 16
	bar.offset_right = -16
	bar.offset_top = -72
	bar.offset_bottom = -16
	bar.add_theme_constant_override("separation", 10)
	preview_overlay.add_child(bar)
	preview_play_btn = GyroUI.icon_button("res://ui/icons/pause.svg", GyroUI.fs(26), 8)
	preview_play_btn.pressed.connect(_toggle_preview_play)
	bar.add_child(preview_play_btn)
	preview_time_label = Label.new()
	preview_time_label.text = _fmt_time(0.0)
	preview_time_label.add_theme_font_size_override("font_size", GyroUI.fs(14))
	preview_time_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	bar.add_child(preview_time_label)
	preview_slider = HSlider.new()
	preview_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_slider.min_value = 0.0
	preview_slider.max_value = maxf(0.001, _preview_len)
	preview_slider.step = 0.05
	preview_slider.value = 0.0
	if preview_video != null and not preview_video.has_method("seek_playback"):
		preview_slider.editable = false
	preview_slider.drag_started.connect(func(): _preview_seeking = true)
	preview_slider.drag_ended.connect(func(_changed: bool):
		_preview_seeking = false
		_apply_preview_seek(preview_slider.value)
	)
	bar.add_child(preview_slider)
	preview_len_label = Label.new()
	preview_len_label.text = _fmt_time(_preview_len)
	preview_len_label.add_theme_font_size_override("font_size", GyroUI.fs(14))
	preview_len_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	bar.add_child(preview_len_label)

func _toggle_preview_play() -> void:
	var player: Node = preview_audio if preview_audio != null else preview_video
	if player == null or not is_instance_valid(player):
		return
	var new_paused := not bool(player.get("stream_paused"))
	player.set("stream_paused", new_paused)
	GyroUI.set_icon(preview_play_btn, "res://ui/icons/play.svg" if new_paused else "res://ui/icons/pause.svg")

func _apply_preview_seek(pos: float) -> void:
	if preview_audio != null and is_instance_valid(preview_audio):
		var was_paused := preview_audio.stream_paused
		preview_audio.play(pos)
		preview_audio.stream_paused = was_paused
	elif preview_video != null and is_instance_valid(preview_video) and preview_video.has_method("seek_playback"):
		preview_video.seek_playback(pos)

func _play_when_in_tree(player: Node) -> void:
	if player.is_inside_tree():
		player.call("play")
	else:
		player.tree_entered.connect(func(): player.call("play"), CONNECT_ONE_SHOT)

static func _fmt_time(sec: float) -> String:
	var s := maxi(0, int(sec))
	var m := s / 60
	var r := s % 60
	return str(m) + ":" + ("0" + str(r) if r < 10 else str(r))

func _asset_type_color(kind: String) -> Color:
	return DesignTokens.COLOR_ACCENT_SOFT

func _asset_type_icon(kind: String) -> String:
	match kind:
		"sound": return "res://ui/icons/sound.svg"
		"video": return "res://ui/icons/play.svg"
		"other": return "res://ui/icons/script_visual.svg"
	return ""

func _asset_type_symbol(kind: String) -> String:
	if kind == "font":
		return "Aa"
	return ""

func _make_asset_icon(a: GyroAsset) -> Node:
	if a.kind == "sprite":
		var resolved := GyroAssetPaths.resolve_asset_path(a.path, save_path)
		var tex := GyroMedia.load_texture(resolved)
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var mat := ShaderMaterial.new()
			mat.shader = _icon_round_shader
			var panel_size := Vector2(GyroUI.sz(60), GyroUI.sz(60))
			mat.set_shader_parameter("size", panel_size)
			mat.set_shader_parameter("radius", float(DesignTokens.RADIUS_MD))
			tr.material = mat
			return tr
	
	var icon_path := _asset_type_icon(a.kind)
	if icon_path != "" and FileAccess.file_exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.modulate = DesignTokens.COLOR_TEXT_PRIMARY
		icon.custom_minimum_size = Vector2(GyroUI.sz(32), GyroUI.sz(32))
		return icon
	
	var label := Label.new()
	label.text = _asset_type_symbol(a.kind)
	label.add_theme_font_size_override("font_size", GyroUI.fs(24))
	label.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
