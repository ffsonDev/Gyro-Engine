class_name ProjectStructureScreen
extends Control

signal back_requested
signal open_script(script: GyroScript)

var project: GyroProject
var save_path := ""
var selected_script: GyroScript
var selected_folder := ""
var expanded: Dictionary = {}
var last_tap_script: GyroScript
var last_tap_time := 0

var drag_script: GyroScript
var drag_panel: Control
var drop_zones: Array = []
var current_drop: Dictionary = {}
var pointer := Vector2()
var drop_indicator: ColorRect

var name_mode := ""
var name_target: Variant = null
var confirm_mode := ""
var confirm_target: GyroScript
var confirm_folder_path := ""

var _style_cache := {}

func setup(proj: GyroProject, path: String) -> void:
	project = proj
	save_path = path
	selected_script = null
	selected_folder = ""
	_load_ui_state()
	_refresh()

func _ready() -> void:
	%Title.add_theme_font_size_override("font_size", GyroUI.fs(30))
	%EmptyTitle.add_theme_color_override("font_color", Color(0.55, 0.58, 0.63))
	%EmptyHint.add_theme_color_override("font_color", Color(0.42, 0.45, 0.49))

	drop_indicator = ColorRect.new()
	drop_indicator.color = Color(0.2, 0.8, 0.9)
	drop_indicator.visible = false
	drop_indicator.z_index = 5
	drop_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(drop_indicator)

	%BackButton.pressed.connect(func(): back_requested.emit())
	%GearButton.pressed.connect(_open_gear)
	%PlusButton.pressed.connect(_open_add_panel)

	%AddPanelOverlay.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event):
			_close_add_panel()
	)
	%GearPanelOverlay.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event):
			_close_gear()
	)

	%AddFolderButton.pressed.connect(func():
		_close_add_panel()
		_open_name_dialog("folder", null)
	)
	%AddScriptButton.pressed.connect(func():
		_close_add_panel()
		_open_name_dialog("script", null)
	)

	%GearRenameButton.pressed.connect(func():
		_close_gear()
		if selected_script != null:
			_open_name_dialog("rename", selected_script)
		elif selected_folder != "":
			_open_name_dialog("rename_folder", selected_folder)
	)
	%GearDeleteButton.pressed.connect(func():
		_close_gear()
		if selected_script != null:
			_open_confirm_script(selected_script)
		elif selected_folder != "":
			_open_confirm_folder(selected_folder)
	)

	%NameDialog.confirmed_text.connect(_apply_name)
	%ConfirmDialog.confirmed.connect(_do_confirm)

	var touch_scroll := GyroTouchScroll.new()
	add_child(touch_scroll)
	touch_scroll.setup(%Scroll, [%AddPanelOverlay, %GearPanelOverlay, %NameDialog, %ConfirmDialog])
	touch_scroll.gate = func(): return drag_script == null

	apply_lang()

func apply_lang() -> void:
	%Title.text = GyroLang.t("structure")
	%EmptyTitle.text = GyroLang.t("empty_structure")
	%EmptyHint.text = GyroLang.t("empty_structure_hint")
	%AddFolderButton.text = GyroLang.t("add_folder")
	%AddScriptButton.text = GyroLang.t("add_script")
	%GearRenameButton.text = GyroLang.t("rename")
	%GearDeleteButton.text = GyroLang.t("delete")

func _row_style(selected: bool) -> StyleBoxFlat:
	var key := "sel_" + str(selected)
	if _style_cache.has(key):
		return _style_cache[key]
	var style := StyleBoxFlat.new()
	if selected:
		style.bg_color = Color(0.11, 0.55, 0.62)
	else:
		style.bg_color = Color(0.22, 0.24, 0.28)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_style_cache[key] = style
	return style

func _refresh() -> void:
	GyroUI.clear_children(%ListVBox)
	drop_zones.clear()
	if project != null:
		_build_level(%ListVBox, "", 0)
	%EmptyState.visible = project == null or (project.scripts.is_empty() and project.folders.is_empty())
	%GearButton.disabled = selected_script == null and selected_folder == ""
	_save_ui_state()

func _build_level(parent: Control, path: String, depth: int) -> void:
	for folder_name in _subfolders_of(path):
		var fp := _join(path, folder_name)
		var frow := HBoxContainer.new()
		frow.add_theme_constant_override("separation", 6)
		frow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if depth > 0:
			frow.add_child(_make_guide(depth, GyroUI.sz(56), false))

		var outer := PanelContainer.new()
		outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		outer.custom_minimum_size = Vector2(0, GyroUI.sz(56))
		outer.add_theme_stylebox_override("panel", _row_style(selected_folder == fp))

		var inner := HBoxContainer.new()
		inner.add_theme_constant_override("separation", 8)
		outer.add_child(inner)

		var arrow := _make_arrow_button(expanded.get(fp, false))
		arrow.pressed.connect(func():
			expanded[fp] = not expanded.get(fp, false)
			_refresh()
		)
		inner.add_child(arrow)

		inner.add_child(GyroUI.icon("res://ui/icons/folder.svg", GyroUI.fs(18)))

		var name_label := Label.new()
		name_label.text = folder_name
		name_label.add_theme_font_size_override("font_size", GyroUI.fs(24))
		name_label.add_theme_color_override("font_color", Color.WHITE)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(name_label)

		frow.add_child(outer)
		parent.add_child(frow)

		GyroUI.attach_tap(outer, func(): _on_folder_tapped(fp))
		drop_zones.append({"type": "folder", "path": fp, "control": outer})

		if expanded.get(fp, false):
			_build_level(parent, fp, depth + 1)

	for s_value in project.scripts:
		var s := s_value as GyroScript
		if s == null or s.folder != path:
			continue
		_build_script_row(parent, s, depth)

func _make_arrow_button(is_open: bool) -> Button:
	var path := "res://ui/icons/chevron_up.svg" if is_open else "res://ui/icons/chevron_down.svg"
	var btn := GyroUI.icon_button(path, GyroUI.fs(22), 10)
	btn.custom_minimum_size = Vector2(GyroUI.sz(48), GyroUI.sz(48))
	return btn

func _build_script_row(parent: Control, s: GyroScript, depth: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if depth > 0:
		row.add_child(_make_guide(depth, GyroUI.sz(64), true))

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, GyroUI.sz(64))
	panel.add_theme_stylebox_override("panel", _row_style(selected_script == s))

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	panel.add_child(inner)

	var handle := Button.new()
	handle.icon = load("res://ui/icons/burger.svg")
	handle.flat = true
	handle.custom_minimum_size = Vector2(GyroUI.sz(44), GyroUI.sz(44))
	handle.add_theme_constant_override("icon_max_width", 25)
	handle.add_theme_color_override("font_color", Color(0.7, 0.72, 0.76))
	handle.button_down.connect(func(): _start_script_drag(s, panel))
	inner.add_child(handle)

	var name_label := Label.new()
	name_label.text = s.script_name
	name_label.add_theme_font_size_override("font_size", GyroUI.fs(24))
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(name_label)

	row.add_child(panel)
	parent.add_child(row)

	GyroUI.attach_tap(panel, func(): _on_script_tapped(s))
	drop_zones.append({"type": "script", "script": s, "control": panel})

func _on_folder_tapped(fp: String) -> void:
	selected_folder = fp
	selected_script = null
	last_tap_script = null
	_refresh()

func _on_script_tapped(s: GyroScript) -> void:
	var now := Time.get_ticks_msec()
	if last_tap_script == s and now - last_tap_time < 400:
		last_tap_script = null
		open_script.emit(s)
		return
	selected_script = s
	selected_folder = ""
	last_tap_script = s
	last_tap_time = now
	_refresh()

func _make_guide(depth: int, row_height: int, with_stub: bool) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := float(row_height) * 0.5
	for i in depth:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(14, row_height)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vline := ColorRect.new()
		vline.color = Color(0.35, 0.37, 0.40)
		vline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vline.anchor_top = 0.0
		vline.anchor_bottom = 1.0
		vline.anchor_left = 0.0
		vline.anchor_right = 0.0
		vline.offset_left = 6.0
		vline.offset_right = 8.0
		slot.add_child(vline)
		if i == depth - 1 and with_stub:
			var hline := ColorRect.new()
			hline.color = Color(0.35, 0.37, 0.40)
			hline.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hline.anchor_top = 0.0
			hline.anchor_bottom = 0.0
			hline.anchor_left = 0.0
			hline.anchor_right = 0.0
			hline.offset_left = 6.0
			hline.offset_right = 14.0
			hline.offset_top = center - 1.0
			hline.offset_bottom = center + 1.0
			slot.add_child(hline)
		box.add_child(slot)
	return box

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		pointer = event.position
	if event is InputEventScreenTouch and not event.pressed and drag_script != null:
		_finish_drag()
	elif event is InputEventMouseButton and not event.pressed and drag_script != null:
		_finish_drag()
	if drag_script != null:
		_update_drop_target()

func _start_script_drag(s: GyroScript, panel: Control) -> void:
	drag_script = s
	drag_panel = panel
	panel.modulate.a = 0.5
	%Scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_update_drop_target()

func _update_drop_target() -> void:
	current_drop = {}
	for zone in drop_zones:
		var rect: Rect2 = zone.control.get_global_rect()
		if not rect.has_point(pointer):
			continue
		if zone.type == "folder":
			current_drop = {"type": "folder", "path": zone.path, "x": rect.position.x, "y": rect.end.y - 2, "w": rect.size.x}
		else:
			if zone.script == drag_script:
				break
			var before := pointer.y < rect.position.y + rect.size.y * 0.5
			current_drop = {"type": "script", "script": zone.script, "before": before, "x": rect.position.x, "y": rect.position.y if before else rect.end.y, "w": rect.size.x}
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
	if drag_script != null and not current_drop.is_empty():
		if current_drop.type == "folder":
			var fp: String = current_drop.path
			if drag_script.folder != fp:
				drag_script.folder = fp
				expanded[fp] = true
				_save_project()
				_refresh()
		else:
			var target: GyroScript = current_drop.script
			var from_index := project.scripts.find(drag_script)
			if from_index >= 0:
				project.scripts.remove_at(from_index)
				var to_index := project.scripts.find(target)
				if to_index >= 0:
					if not current_drop.before:
						to_index += 1
					drag_script.folder = target.folder
					project.scripts.insert(to_index, drag_script)
					_save_project()
					_refresh()
	current_drop = {}
	drag_script = null
	drag_panel = null
	drop_indicator.visible = false

func _open_add_panel() -> void:
	%AddPanelOverlay.visible = true
	%AddPanel.visible = true

func _close_add_panel() -> void:
	%AddPanelOverlay.visible = false
	%AddPanel.visible = false

func _open_gear() -> void:
	if selected_script != null:
		%GearTitle.text = GyroLang.t("script_prefix") + selected_script.script_name
	elif selected_folder != "":
		%GearTitle.text = GyroLang.t("folder_prefix") + selected_folder
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
		"script":
			title = GyroLang.t("new_script")
		"rename":
			title = GyroLang.t("rename")
			initial = (target as GyroScript).script_name
		"rename_folder":
			title = GyroLang.t("rename")
			var parts := String(target).split("/")
			initial = parts[parts.size() - 1]
	%NameDialog.open(title, "имя ", initial)

func _apply_name(name_text: String) -> void:
	var clean := GyroUI.sanitize_name(name_text)
	if GyroUI.is_bad_name(clean):
		GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("enter_correct_name"))
		return
	match name_mode:
		"folder":
			var fp := _join(selected_folder, clean)
			if project.folders.has(fp):
				GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("folder_exists"))
				return
			project.folders.append(fp)
			expanded[selected_folder] = true
			expanded[fp] = true
		"script":
			if _has_script_name(clean, selected_folder, null):
				GyroUI.alert(self, GyroLang.t("error"), GyroLang.t("script_exists"))
				return
			var s := GyroScript.new()
			s.script_name = clean
			s.folder = selected_folder
			s.blueprint = GyroEventBlueprint.new()
			project.scripts.append(s)
			expanded[selected_folder] = true
		"rename":
			var target := name_target as GyroScript
			if target != null:
				if clean != target.script_name and _has_script_name(clean, target.folder, target):
					GyroUI.alert(self, "Ошибка", "Скрипт с таким именем уже есть в той папке.")
					return
				target.script_name = clean
		"rename_folder":
			var old_fp := String(name_target)
			var parent := _parent_of(old_fp)
			var new_fp := _join(parent, clean)
			if new_fp != old_fp and project.folders.has(new_fp):
				GyroUI.alert(self, "Ошибка", "Папка с таким именем уже существует.")
				return
			if new_fp != old_fp:
				_rename_folder_recursive(old_fp, new_fp)
	_save_project()
	_refresh()

func _rename_folder_recursive(old_fp: String, new_fp: String) -> void:
	var prefix := old_fp + "/"
	var new_folders: Array = []
	for f in project.folders:
		if str(f) == old_fp:
			new_folders.append(new_fp)
		elif str(f).begins_with(prefix):
			new_folders.append(new_fp + "/" + str(f).substr(prefix.length()))
		else:
			new_folders.append(f)
	project.folders.clear()
	for f in new_folders:
		project.folders.append(f)
	for s_value in project.scripts:
		var s := s_value as GyroScript
		if s == null:
			continue
		if s.folder == old_fp:
			s.folder = new_fp
		elif s.folder.begins_with(prefix):
			s.folder = new_fp + "/" + s.folder.substr(prefix.length())
	if selected_folder == old_fp:
		selected_folder = new_fp

func _open_confirm_script(s: GyroScript) -> void:
	confirm_mode = "script"
	confirm_target = s
	%ConfirmDialog.open(GyroLang.t("delete"), GyroLang.t("delete_script_q") % s.script_name, GyroLang.t("delete"), GyroLang.t("cancel"))

func _open_confirm_folder(fp: String) -> void:
	confirm_mode = "folder"
	confirm_folder_path = fp
	%ConfirmDialog.open(GyroLang.t("delete"), GyroLang.t("delete_folder_q") % fp, GyroLang.t("delete"), GyroLang.t("cancel"))

func _do_confirm() -> void:
	if confirm_mode == "script" and confirm_target != null:
		project.scripts.erase(confirm_target)
		if selected_script == confirm_target:
			selected_script = null
		confirm_target = null
	elif confirm_mode == "folder" and confirm_folder_path != "":
		_delete_folder(confirm_folder_path)
		if selected_folder == confirm_folder_path:
			selected_folder = ""
		confirm_folder_path = ""
	confirm_mode = ""
	_save_project()
	_refresh()

func _delete_folder(fp: String) -> void:
	var parent := _parent_of(fp)
	var prefix := fp + "/"
	for s_value in project.scripts:
		var s := s_value as GyroScript
		if s == null:
			continue
		if s.folder == fp:
			s.folder = parent
		elif s.folder.begins_with(prefix):
			s.folder = parent + "/" + s.folder.substr(prefix.length())
	var to_remove: Array = []
	for f in project.folders:
		if str(f) == fp or str(f).begins_with(prefix):
			to_remove.append(f)
	for f in to_remove:
		project.folders.erase(f)
	expanded.erase(fp)

func _has_script_name(script_name: String, folder: String, exclude: GyroScript) -> bool:
	for s in project.scripts:
		if s == null or s == exclude:
			continue
		if s.folder == folder and s.script_name == script_name:
			return true
	return false

func _subfolders_of(path: String) -> Array:
	var result: Array = []
	var prefix := ""
	if path != "":
		prefix = path + "/"
	var all: Array = []
	for f in project.folders:
		if str(f) != "" and not all.has(f):
			all.append(f)
	for s_value in project.scripts:
		var s := s_value as GyroScript
		if s != null and s.folder != "" and not all.has(s.folder):
			all.append(s.folder)
	for f in all:
		if str(f).begins_with(prefix):
			var rest := str(f).substr(prefix.length())
			var first := rest.split("/")[0]
			if first != "" and not result.has(first):
				result.append(first)
	result.sort()
	return result

func _join(parent: String, child: String) -> String:
	if parent == "":
		return child
	return parent + "/" + child

func _save_project() -> void:
	GyroUI.save_resource(project, save_path)

func _ui_state_path() -> String:
	return save_path.get_basename() + ".structure_ui.json"

func _load_ui_state() -> void:
	expanded = {}
	if save_path == "":
		return
	var f := FileAccess.open(_ui_state_path(), FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and parsed.has("open"):
		for k in parsed["open"]:
			expanded[str(k)] = true

func _save_ui_state() -> void:
	if save_path == "":
		return
	var open_list: Array = []
	for k in expanded.keys():
		if expanded[k]:
			open_list.append(k)
	var f := FileAccess.open(_ui_state_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"open": open_list}))
	f.close()

func _parent_of(fp: String) -> String:
	var idx := fp.rfind("/")
	if idx < 0:
		return ""
	return fp.substr(0, idx)
