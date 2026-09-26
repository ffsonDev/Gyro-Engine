class_name DocScreen
extends Control

signal back_requested
signal section_opened(section_id: String)

var current_section_id := ""
var current_category_id := ""
var doc_data: Dictionary = {}
var search_edit: LineEdit
var sidebar_scroll: ScrollContainer
var sidebar_vbox: VBoxContainer
var content_rich: RichTextLabel
var content_vbox: VBoxContainer
var breadcrumbs: HBoxContainer
var menu_button: Button
var sidebar_visible := false
var _code_buttons: Array = []

const DOC_DATA_PATH := "res://docs/doc_data.json"

func _ready() -> void:
	%Title.add_theme_font_size_override("font_size", GyroUI.fs(28))
	%BackButton.pressed.connect(func(): back_requested.emit())
	
	%MenuButton.icon = load("res://ui/icons/burger.svg")
	%MenuButton.pressed.connect(_toggle_sidebar)
	
	sidebar_scroll = %SidebarScroll
	sidebar_vbox = %SidebarVBox
	content_vbox = %ContentVBox
	breadcrumbs = %Breadcrumbs
	
	%Dim.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event):
			_toggle_sidebar()
	)
	
	var ts_sidebar := GyroTouchScroll.new()
	add_child(ts_sidebar)
	ts_sidebar.setup(%SidebarScroll)
	
	var ts_content := GyroTouchScroll.new()
	add_child(ts_content)
	ts_content.setup(%ContentScroll)
	
	_load_doc_data()
	apply_lang()
	
	if current_section_id == "":
		call_deferred("open_section", "intro")

func _load_doc_data() -> void:
	if not FileAccess.file_exists(DOC_DATA_PATH):
		push_error("DocScreen: doc_data.json not found at " + DOC_DATA_PATH)
		return
	var f := FileAccess.open(DOC_DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	f.close()
	if err == OK and json.data is Dictionary:
		doc_data = json.data

func apply_lang() -> void:
	%Title.text = GyroLang.t("doc")
	if search_edit != null:
		search_edit.placeholder_text = GyroLang.t("search")
	_build_sidebar(search_edit.text if search_edit != null else "")
	if current_section_id != "":
		var section_data := _find_section(current_section_id)
		if not section_data.is_empty():
			_update_breadcrumbs()
			_render_content(section_data)

func _build_sidebar(filter: String = "") -> void:
	GyroUI.clear_children(sidebar_vbox)
	var q := filter.strip_edges().to_lower()
	
	for cat_value in doc_data.get("categories", []):
		var cat: Dictionary = cat_value
		var cat_sections: Array = []
		
		for sec_value in cat.get("sections", []):
			var sec: Dictionary = sec_value
			var title := GyroLang.t(sec.get("title_key", sec.id))
			var tags: Array = sec.get("tags", [])
			var show := q == ""
			
			if not show:
				if title.to_lower().contains(q):
					show = true
				else:
					for tag in tags:
						if str(tag).to_lower().contains(q):
							show = true
							break
			
			if not show and sec.has("content"):
				if str(sec.content).to_lower().contains(q):
					show = true
			
			if show:
				cat_sections.append(sec)
		
		if cat_sections.is_empty():
			continue
		
		var cat_label := Label.new()
		cat_label.text = GyroLang.t(cat.get("title_key", cat.id)).to_upper()
		cat_label.add_theme_font_size_override("font_size", GyroUI.fs(14))
		cat_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
		cat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sidebar_vbox.add_child(cat_label)
		_spacer(4)
		
		for sec in cat_sections:
			var btn := Button.new()
			btn.text = "  " + GyroLang.t(sec.get("title_key", sec.id))
			btn.custom_minimum_size = Vector2(0, GyroUI.sz(48))
			btn.add_theme_font_size_override("font_size", GyroUI.fs(16))
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.flat = true
			
			var selected = (sec.id == current_section_id)
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.11, 0.55, 0.62) if selected else Color(0, 0, 0, 0)
			style.set_corner_radius_all(GyroUI.sz(8))
			style.content_margin_left = 12
			btn.add_theme_stylebox_override("normal", style)
			btn.add_theme_stylebox_override("hover", style)
			
			var pressed := style.duplicate() as StyleBoxFlat
			pressed.bg_color = Color(0.08, 0.45, 0.52)
			btn.add_theme_stylebox_override("pressed", pressed)
			
			btn.add_theme_color_override("font_color", Color.WHITE if selected else Color(0.85, 0.85, 0.85))
			
			btn.pressed.connect(func():
				open_section(sec.id)
				sidebar_visible = false
				%SidebarLayer.visible = false
			)
			
			sidebar_vbox.add_child(btn)
		_spacer(12)

func open_section(section_id: String) -> void:
	current_section_id = section_id
	var section_data := _find_section(section_id)
	if section_data.is_empty():
		return
	
	current_category_id = section_data.get("category_id", "")
	_build_sidebar(search_edit.text if search_edit != null else "")
	_update_breadcrumbs()
	_render_content(section_data)
	%ContentScroll.scroll_vertical = 0

func _find_section(section_id: String) -> Dictionary:
	for cat_value in doc_data.get("categories", []):
		var cat: Dictionary = cat_value
		for sec_value in cat.get("sections", []):
			var sec: Dictionary = sec_value
			if sec.id == section_id:
				var result := sec.duplicate()
				result["category_id"] = cat.id
				result["category_title_key"] = cat.get("title_key", cat.id)
				return result
	return {}

func _update_breadcrumbs() -> void:
	GyroUI.clear_children(breadcrumbs)
	
	if current_category_id != "":
		var cat_data := _find_category(current_category_id)
		if not cat_data.is_empty():
			var cat_btn := Button.new()
			cat_btn.text = GyroLang.t(cat_data.get("title_key", current_category_id))
			cat_btn.flat = true
			cat_btn.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
			cat_btn.add_theme_font_size_override("font_size", GyroUI.fs(14))
			breadcrumbs.add_child(cat_btn)
	
	if current_section_id != "":
		var sec_data := _find_section(current_section_id)
		if not sec_data.is_empty():
			if breadcrumbs.get_child_count() > 0:
				var sep := Label.new()
				sep.text = " › "
				sep.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5))
				sep.add_theme_font_size_override("font_size", GyroUI.fs(14))
				breadcrumbs.add_child(sep)
			
			var sec_btn := Button.new()
			sec_btn.text = GyroLang.t(sec_data.get("title_key", current_section_id))
			sec_btn.flat = true
			sec_btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
			sec_btn.add_theme_font_size_override("font_size", GyroUI.fs(14))
			breadcrumbs.add_child(sec_btn)

func _find_category(category_id: String) -> Dictionary:
	for cat_value in doc_data.get("categories", []):
		var cat: Dictionary = cat_value
		if cat.id == category_id:
			return cat
	return {}

func _render_content(section_data: Dictionary) -> void:
	GyroUI.clear_children(content_vbox)
	_code_buttons.clear()
	
	var lang := GyroLang.lang
	var content_key := "content_" + lang
	var content := ""
	if section_data.has(content_key):
		content = str(section_data.get(content_key, ""))
	elif section_data.has("content"):
		content = str(section_data.get("content", ""))
	
	if content == "":
		return
	
	var lines := content.split("\n")
	var current_paragraph := ""
	var in_code := false
	var code_text := ""
	var code_lang := ""
	
	for line in lines:
		if line.strip_edges() == "[code]":
			in_code = true
			code_text = ""
			if current_paragraph != "":
				_add_paragraph(current_paragraph)
				current_paragraph = ""
			continue
		
		if line.strip_edges() == "[/code]":
			in_code = false
			_add_code_block(code_text, code_lang)
			code_text = ""
			code_lang = ""
			continue
		
		if in_code:
			if code_text != "":
				code_text += "\n"
			code_text += line
			continue
		
		var stripped := line.strip_edges()
		if stripped == "":
			if current_paragraph != "":
				_add_paragraph(current_paragraph)
				current_paragraph = ""
			continue
		
		if stripped.begins_with("# "):
			if current_paragraph != "":
				_add_paragraph(current_paragraph)
				current_paragraph = ""
			_add_header(stripped.substr(2), 1)
		elif stripped.begins_with("## "):
			if current_paragraph != "":
				_add_paragraph(current_paragraph)
				current_paragraph = ""
			_add_header(stripped.substr(3), 2)
		elif stripped.begins_with("### "):
			if current_paragraph != "":
				_add_paragraph(current_paragraph)
				current_paragraph = ""
			_add_header(stripped.substr(4), 3)
		elif stripped.begins_with("> "):
			if current_paragraph != "":
				_add_paragraph(current_paragraph)
				current_paragraph = ""
			_add_note(stripped.substr(2))
		elif stripped.begins_with("* "):
			_add_bullet(stripped.substr(2))
		elif stripped.begins_with("[link="):
			if current_paragraph != "":
				_add_paragraph(current_paragraph)
				current_paragraph = ""
			_add_link(stripped)
		else:
			if current_paragraph != "":
				current_paragraph += " "
			current_paragraph += line
	
	if current_paragraph != "":
		_add_paragraph(current_paragraph)
	
	if in_code:
		_add_code_block(code_text, code_lang)

func _add_header(text: String, level: int) -> void:
	var label := Label.new()
	label.text = text
	var size := 28 if level == 1 else (22 if level == 2 else 18)
	var color := Color(0.95, 0.95, 0.95) if level == 1 else (Color(0.85, 0.85, 0.85) if level == 2 else Color(0.75, 0.85, 0.9))
	label.add_theme_font_size_override("font_size", GyroUI.fs(size))
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_vbox.add_child(label)
	_spacer(8 if level == 1 else 6)

func _add_paragraph(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", GyroUI.fs(16))
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	content_vbox.add_child(label)
	_spacer(6)

func _add_note(text: String) -> void:
	var note_type := "note"
	var note_color := Color(0.4, 0.7, 0.95)
	var note_title := GyroLang.t("doc_note")
	
	if text.begins_with("Совет: ") or text.begins_with("Tip: "):
		note_type = "tip"
		note_color = Color(0.4, 0.8, 0.5)
		note_title = GyroLang.t("doc_tip")
		text = text.substr(7 if text.begins_with("Совет: ") else 5)
	elif text.begins_with("Внимание: ") or text.begins_with("Warning: "):
		note_type = "warning"
		note_color = Color(0.95, 0.7, 0.3)
		note_title = GyroLang.t("doc_warning")
		text = text.substr(10 if text.begins_with("Внимание: ") else 9)
	elif text.begins_with("Аналогия: ") or text.begins_with("Analogy: "):
		note_type = "analogy"
		note_color = Color(0.7, 0.5, 0.9)
		note_title = GyroLang.t("doc_analogy")
		text = text.substr(10 if text.begins_with("Аналогия: ") else 9)
	elif text.begins_with("Заметка: ") or text.begins_with("Note: "):
		text = text.substr(9 if text.begins_with("Заметка: ") else 6)
	
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(note_color.r, note_color.g, note_color.b, 0.15)
	style.border_width_left = 4
	style.border_color = note_color
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	
	var title_label := Label.new()
	title_label.text = note_title
	title_label.add_theme_font_size_override("font_size", GyroUI.fs(16))
	title_label.add_theme_color_override("font_color", note_color)
	vbox.add_child(title_label)
	
	var text_label := Label.new()
	text_label.text = text
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.add_theme_font_size_override("font_size", GyroUI.fs(14))
	text_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	vbox.add_child(text_label)
	
	content_vbox.add_child(panel)
	_spacer(6)

func _add_bullet(text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	
	var bullet := Label.new()
	bullet.text = "•"
	bullet.add_theme_font_size_override("font_size", GyroUI.fs(18))
	bullet.add_theme_color_override("font_color", Color(0.4, 0.7, 0.95))
	bullet.custom_minimum_size = Vector2(20, 0)
	row.add_child(bullet)
	
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", GyroUI.fs(16))
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	row.add_child(label)
	
	content_vbox.add_child(row)
	_spacer(4)

func _add_code_block(code: String, lang: String) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	
	var label := Label.new()
	label.text = code
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", GyroUI.fs(14))
	label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.75))
	row.add_child(label)
	
	# Кнопка копирования
	var copy_btn := GyroUI.icon_button("res://ui/icons/copy.svg", GyroUI.fs(20), 4)
	copy_btn.pressed.connect(func():
		DisplayServer.clipboard_set(code)
		var orig_text := copy_btn.tooltip_text
		copy_btn.tooltip_text = "Скопировано!"
		await get_tree().create_timer(1.5).timeout
		copy_btn.tooltip_text = orig_text
	)
	copy_btn.tooltip_text = "Копировать код"
	row.add_child(copy_btn)
	
	_code_buttons.append(copy_btn)
	content_vbox.add_child(panel)
	_spacer(6)

func _add_link(text: String) -> void:
	var regex := RegEx.new()
	regex.compile("\\[link=([^\\]]+)\\]([^\\[]+)\\[/link\\]")
	var match := regex.search(text)
	if match == null:
		return
	
	var section_id := match.get_string(1)
	var link_text := match.get_string(2)
	
	var btn := Button.new()
	btn.text = "→ " + link_text
	btn.flat = true
	btn.add_theme_color_override("font_color", Color(0.4, 0.7, 0.95))
	btn.add_theme_font_size_override("font_size", GyroUI.fs(14))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(func(): open_section(section_id))
	content_vbox.add_child(btn)
	_spacer(4)

func _on_meta_clicked(meta: Variant) -> void:
	if meta is String:
		open_section(meta)

func _toggle_sidebar() -> void:
	sidebar_visible = not sidebar_visible
	%SidebarLayer.visible = sidebar_visible

func _spacer(size: int) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, size)
	content_vbox.add_child(spacer)

func open_section_by_block_type(block_type: String) -> void:
	var mapping := {
		"MoveNode": "objects", "SetNodeProperty": "objects", "SetSize": "objects",
		"SetText": "objects", "CreateObject": "objects", "DeleteObject": "objects",
		"SetVisible": "objects", "SetOpacity": "objects", "SetRotation": "objects",
		"SetScale": "objects", "ChangeLayer": "objects", "SetFontSize": "objects",
		"SetColor": "objects", "SetTextAlign": "objects", "SetTexture": "objects",
		"SetObjectMeta": "transforms",
		
		"CreateGroup": "groups", "AddToGroup": "groups",
		"SetAnchor": "anchors",
		
		"CreateCircle": "shapes", "CreateLine": "shapes",
		"SetGradient": "styles", "SetBorder": "styles", "SetCornerRadius": "styles",
		
		"SetPivot": "transforms", "FaceObject": "transforms",
		
		"CreateSpriteAnim": "sprite_anim", "SetFrame": "sprite_anim",
		"PlayAnimation": "sprite_anim", "StopAnimation": "sprite_anim",
		
		"SetDraggable": "draggable",
		
		"Spawn": "spawn",
		
		"SetVelocity": "physics", "AddVelocity": "physics", "SetGravity": "physics",
		"SetSolid": "physics", "SetSensor": "physics",
		"SetPhysicsPaused": "advanced_physics", "SetGlobalGravity": "advanced_physics",
		
		"PlaySound": "sound", "StopSound": "sound", "SetSoundVolume": "sound",
		
		"TweenPosition": "tweens", "TweenScale": "tweens",
		"TweenRotation": "tweens", "TweenOpacity": "tweens", "StopTween": "tweens",
		
		"SetCameraPosition": "camera", "CameraFollow": "camera", "SetParallax": "camera",
		
		"CreateParticles": "particles", "SetParticlesParam": "particles", "DeleteParticles": "particles",
		
		"SetVariable": "vars", "AddToVariable": "vars", "SetTableValue": "vars",
		"GetTableValue": "vars", "InsertArrayValue": "vars", "RemoveArrayValue": "vars",
		"OverwriteTable": "vars", "ForEachTable": "vars", "LoopRange": "vars",
		
		"AddTag": "tags", "DeleteByTag": "tags", "SetVisibleByTag": "tags",
		"SetPositionByTag": "tags", "SetRotationByTag": "tags",
		"SetOpacityByTag": "tags", "SetScaleByTag": "tags", "ChangeLayerByTag": "tags",
		
		"CreateInput": "widgets", "CreateSlider": "widgets", "CreateToggle": "widgets",
		"GetWidgetText": "widgets", "SetSliderValue": "widgets", "SetToggleState": "widgets",
		
		"ReadFile": "advanced_files", "WriteFile": "advanced_files",
		"FileOp": "advanced_files", "HttpRequest": "advanced_files",
		"SaveValue": "advanced_files", "LoadValue": "advanced_files",
		
		"Print": "system_actions", "Toast": "system_actions",
		"SetBackgroundColor": "system_actions", "SetOrientation": "system_actions",
		"Clipboard": "system_actions", "OpenURL": "system_actions",
		"Quit": "system_actions", "RandomSeed": "system_actions",
		
		"EmitEvent": "custom_events", "StartTimer": "events", "StopTimer": "events",
		
		"If": "conditions", "Repeat": "conditions", "Wait": "actions",
		
		"Always": "conditions", "VariableEquals": "conditions",
		"VariableGreaterThan": "conditions", "PayloadEquals": "conditions",
		"PayloadGreaterThan": "conditions"
	}
	var section_id = mapping.get(block_type, "")
	if section_id != "":
		open_section(section_id)
