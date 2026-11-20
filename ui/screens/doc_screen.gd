class_name DocScreen
extends Control

signal back_requested
signal section_opened(section_id: String)

var current_section_id := ""
var current_category_id := ""
var guide_data: Dictionary = {}
var glossary_data: Dictionary = {}
var search_edit: LineEdit
var sidebar_vbox: VBoxContainer
var content_vbox: VBoxContainer
var breadcrumbs: HBoxContainer
var sidebar_visible := false
var _code_buttons: Array = []
var _mode := "guide"
var _mode_buttons: Array = []
var _ref_search := ""
var _ref_category := ""

const GUIDE_PATH := "res://docs/doc_guide.json"
const GLOSSARY_PATH := "res://docs/doc_glossary.json"

func _ready() -> void:
	%Title.add_theme_font_size_override("font_size", GyroUI.fs(28))
	%BackButton.pressed.connect(func(): back_requested.emit())
	%MenuButton.icon = load("res://ui/icons/burger.svg")
	%MenuButton.pressed.connect(_toggle_sidebar)
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
	_build_mode_switcher()
	_load_data()
	apply_lang()
	if current_section_id == "":
		call_deferred("open_section", "ch1_intro")
	_animate_in()

func _animate_in() -> void:
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, DesignTokens.ANIM_NORMAL).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _build_mode_switcher() -> void:
	var bar := HBoxContainer.new()
	bar.name = "ModeBar"
	bar.add_theme_constant_override("separation", 4)
	bar.custom_minimum_size = Vector2(0, GyroUI.sz(44))
	var content_area := %ContentScroll.get_parent() as VBoxContainer
	content_area.add_child(bar)
	content_area.move_child(bar, 0)
	var modes := [["guide", "doc_mode_guide"], ["reference", "doc_mode_reference"]]
	for m in modes:
		var btn := Button.new()
		btn.text = GyroLang.t(str(m[1]))
		btn.custom_minimum_size = Vector2(0, GyroUI.sz(40))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", GyroUI.fs(14))
		btn.pressed.connect(func(): _switch_mode(str(m[0])))
		bar.add_child(btn)
		_mode_buttons.append({"btn": btn, "mode": str(m[0])})
	_update_mode_buttons()

func _update_mode_buttons() -> void:
	for entry in _mode_buttons:
		var btn: Button = entry.btn
		var mode: String = entry.mode
		var selected := (mode == _mode)
		var style := StyleBoxFlat.new()
		style.bg_color = DesignTokens.PANEL_BG if selected else Color(0, 0, 0, 0)
		style.set_corner_radius_all(DesignTokens.RADIUS_MD)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		var pressed := style.duplicate() as StyleBoxFlat
		pressed.bg_color = DesignTokens.COLOR_SURFACE_1
		btn.add_theme_stylebox_override("pressed", pressed)
		btn.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY if selected else DesignTokens.COLOR_TEXT_MUTED)

func _switch_mode(mode: String) -> void:
	if _mode == mode:
		return
	_mode = mode
	_update_mode_buttons()
	match mode:
		"guide":
			%MenuButton.visible = true
			if current_section_id != "":
				var sd := _find_section(current_section_id)
				if not sd.is_empty():
					_render_content(sd)
			else:
				open_section("ch1_intro")
		"reference":
			%MenuButton.visible = false
			_render_reference()

func _load_data() -> void:
	if FileAccess.file_exists(GUIDE_PATH):
		var f := FileAccess.open(GUIDE_PATH, FileAccess.READ)
		if f != null:
			var json := JSON.new()
			var err := json.parse(f.get_as_text())
			f.close()
			if err == OK and json.data is Dictionary:
				guide_data = json.data
	if FileAccess.file_exists(GLOSSARY_PATH):
		var f := FileAccess.open(GLOSSARY_PATH, FileAccess.READ)
		if f != null:
			var json := JSON.new()
			var err := json.parse(f.get_as_text())
			f.close()
			if err == OK and json.data is Dictionary:
				glossary_data = json.data

func apply_lang() -> void:
	%Title.text = GyroLang.t("doc")
	for entry in _mode_buttons:
		var btn: Button = entry.btn
		var mode: String = entry.mode
		match mode:
			"guide": btn.text = GyroLang.t("doc_mode_guide")
			"reference": btn.text = GyroLang.t("doc_mode_reference")
	_build_sidebar("")
	if _mode == "guide" and current_section_id != "":
		var section_data := _find_section(current_section_id)
		if not section_data.is_empty():
			_update_breadcrumbs()
			_render_content(section_data)
	elif _mode == "reference":
		_render_reference()

func _build_sidebar(filter: String = "") -> void:
	GyroUI.clear_children(sidebar_vbox)
	if _mode != "guide":
		return
	var q := filter.strip_edges().to_lower()
	for chapter in guide_data.get("chapters", []):
		var ch: Dictionary = chapter
		var ch_title := GyroLang.t(str(ch.get("title_key", "")))
		var sections: Array = ch.get("sections", [])
		var visible_sections: Array = []
		for sec in sections:
			var s: Dictionary = sec
			var title := GyroLang.t(str(s.get("title_key", "")))
			if q == "" or title.to_lower().contains(q):
				visible_sections.append(s)
		if visible_sections.is_empty():
			continue
		var cat_label := Label.new()
		cat_label.text = ch_title.to_upper()
		cat_label.add_theme_font_size_override("font_size", GyroUI.fs(13))
		cat_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
		cat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sidebar_vbox.add_child(cat_label)
		_spacer(4)
		for sec in visible_sections:
			var sid: String = sec.get("id", "")
			var btn := Button.new()
			btn.text = "  " + GyroLang.t(str(sec.get("title_key", "")))
			btn.custom_minimum_size = Vector2(0, GyroUI.sz(44))
			btn.add_theme_font_size_override("font_size", GyroUI.fs(15))
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.flat = true
			var selected = (sid == current_section_id)
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
				open_section(sid)
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
	current_category_id = str(section_data.get("chapter_title_key", ""))
	_build_sidebar("")
	_update_breadcrumbs()
	_render_content(section_data)
	%ContentScroll.scroll_vertical = 0

func _find_section(section_id: String) -> Dictionary:
	for chapter in guide_data.get("chapters", []):
		var ch: Dictionary = chapter
		for sec in ch.get("sections", []):
			var s: Dictionary = sec
			if str(s.get("id", "")) == section_id:
				var result := s.duplicate()
				result["chapter_title_key"] = ch.get("title_key", "")
				return result
	return {}

func _update_breadcrumbs() -> void:
	GyroUI.clear_children(breadcrumbs)
	if _mode != "guide":
		return
	if current_category_id != "":
		var cat_btn := Button.new()
		cat_btn.text = GyroLang.t(current_category_id)
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
			sec_btn.text = GyroLang.t(str(sec_data.get("title_key", "")))
			sec_btn.flat = true
			sec_btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
			sec_btn.add_theme_font_size_override("font_size", GyroUI.fs(14))
			breadcrumbs.add_child(sec_btn)

func _render_section(section: Dictionary) -> String:
	var md := ""
	var keys: Array = section.get("content_keys", [])
	for item in keys:
		var type: String = str(item.get("type", "paragraph"))
		if type == "block_example":
			md += "%%BLOCK_EXAMPLE%%\n"
			continue
		match type:
			"paragraph":
				md += GyroLang.t(str(item.get("key", ""))) + "\n"
			"heading":
				var level: int = int(item.get("level", 2))
				var prefix := "#".repeat(level) + " "
				md += prefix + GyroLang.t(str(item.get("key", ""))) + "\n"
			"quote":
				var label_key: String = str(item.get("label_key", ""))
				var label := ""
				if label_key != "":
					label = GyroLang.t(label_key) + ": "
				md += "> " + label + GyroLang.t(str(item.get("key", ""))) + "\n"
			"list":
				var items: Array = item.get("items", [])
				for list_key in items:
					md += "* " + GyroLang.t(str(list_key)) + "\n"
				md += "\n"
			"code":
				md += "```\n" + GyroLang.t(str(item.get("key", ""))) + "\n```\n"
			"link":
				var target_id: String = str(item.get("target", ""))
				var text_key: String = str(item.get("text_key", "doc_see_also"))
				var link_text := GyroLang.t(text_key)
				var target_section := _find_section(target_id)
				if not target_section.is_empty():
					var target_title := GyroLang.t(str(target_section.get("title_key", "")))
					if link_text != "":
						link_text += " " + target_title
					else:
						link_text = target_title
				md += "[link=" + target_id + "]" + link_text + "[/link]\n"
	return md

func _render_content(section_data: Dictionary) -> void:
	GyroUI.clear_children(content_vbox)
	_code_buttons.clear()
	var content := _render_section(section_data)
	if content == "":
		return
	var block_queue: Array = []
	for item in section_data.get("content_keys", []):
		if str(item.get("type", "")) == "block_example":
			block_queue.append(item.get("blocks", []))
	var block_idx := 0
	var lines := content.split("\n")
	var current_paragraph := ""
	var in_code := false
	var code_text := ""
	for line in lines:
		if line.strip_edges() == "%%BLOCK_EXAMPLE%%":
			if current_paragraph != "":
				_add_paragraph(current_paragraph)
				current_paragraph = ""
			if in_code:
				_add_code_block(code_text)
				code_text = ""
				in_code = false
			if block_idx < block_queue.size():
				_add_block_example(block_queue[block_idx])
				block_idx += 1
			continue
		if line.strip_edges() == "```":
			if in_code:
				in_code = false
				_add_code_block(code_text)
				code_text = ""
			else:
				in_code = true
				code_text = ""
			if current_paragraph != "":
				_add_paragraph(current_paragraph)
				current_paragraph = ""
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
		_add_code_block(code_text)
	while block_idx < block_queue.size():
		_add_block_example(block_queue[block_idx])
		block_idx += 1

func _render_reference() -> void:
	GyroUI.clear_children(content_vbox)
	GyroUI.clear_children(breadcrumbs)
	_code_buttons.clear()
	var header := Label.new()
	header.text = GyroLang.t("doc_mode_reference")
	header.add_theme_font_size_override("font_size", GyroUI.fs(24))
	header.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	content_vbox.add_child(header)
	_spacer(12)
	var terms: Array = glossary_data.get("terms", [])
	for t in terms:
		var td: Dictionary = t
		var term := GyroLang.t(str(td.get("term_key", "")))
		var def := GyroLang.t(str(td.get("def_key", "")))
		var see: String = str(td.get("see", ""))
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.11, 0.14)
		style.set_corner_radius_all(10)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		panel.add_theme_stylebox_override("panel", style)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_vbox.add_child(panel)
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		panel.add_child(vbox)
		var term_label := Label.new()
		term_label.text = term
		term_label.add_theme_font_size_override("font_size", GyroUI.fs(17))
		term_label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
		vbox.add_child(term_label)
		var def_label := Label.new()
		def_label.text = def
		def_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		def_label.add_theme_font_size_override("font_size", GyroUI.fs(14))
		def_label.add_theme_color_override("font_color", Color(0.72, 0.74, 0.78))
		vbox.add_child(def_label)
		if see != "":
			var target := _find_section(see)
			if not target.is_empty():
				var target_title := GyroLang.t(str(target.get("title_key", "")))
				var see_btn := Button.new()
				see_btn.text = "→ " + GyroLang.t("doc_see_also") + " " + target_title
				see_btn.flat = true
				see_btn.add_theme_color_override("font_color", Color(0.4, 0.7, 0.95))
				see_btn.add_theme_font_size_override("font_size", GyroUI.fs(13))
				see_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
				see_btn.pressed.connect(func():
					_switch_mode("guide")
					open_section(see)
				)
				vbox.add_child(see_btn)
		_spacer(8)

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
	var note_color := Color(0.4, 0.7, 0.95)
	var note_title := GyroLang.t("doc_note")
	if text.begins_with("Совет: ") or text.begins_with("Tip: "):
		note_color = Color(0.4, 0.8, 0.5)
		note_title = GyroLang.t("doc_tip")
		text = text.substr(7 if text.begins_with("Совет: ") else 5)
	elif text.begins_with("Внимание: ") or text.begins_with("Warning: "):
		note_color = Color(0.95, 0.7, 0.3)
		note_title = GyroLang.t("doc_warning")
		text = text.substr(10 if text.begins_with("Внимание: ") else 9)
	elif text.begins_with("Аналогия: ") or text.begins_with("Analogy: "):
		note_color = Color(0.7, 0.5, 0.9)
		note_title = GyroLang.t("doc_analogy")
		text = text.substr(10 if text.begins_with("Аналогия: ") else 9)
	elif text.begins_with("Заметка: ") or text.begins_with("Note: "):
		text = text.substr(9 if text.begins_with("Заметка: ") else 6)
	var panel := PanelContainer.new()
	var style := GyroUI.glass_panel_style().duplicate() as StyleBoxFlat
	style.bg_color = Color(note_color.r, note_color.g, note_color.b, 0.15)
	style.border_width_left = 4
	style.border_width_right = 0
	style.border_width_top = 0
	style.border_width_bottom = 0
	style.border_color = note_color
	style.set_corner_radius_all(8)
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

func _add_code_block(code: String) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8
	style.content_margin_right = 12
	style.content_margin_top = 4
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
	var copy_btn := Button.new()
	copy_btn.flat = true
	copy_btn.icon = load("res://ui/icons/copy.svg")
	copy_btn.add_theme_constant_override("icon_max_width", 20)
	copy_btn.custom_minimum_size = Vector2(36, 36)
	var gray_color := Color(0.5, 0.5, 0.5)
	var white_color := Color(1.0, 1.0, 1.0)
	copy_btn.add_theme_color_override("icon_normal_color", gray_color)
	copy_btn.add_theme_color_override("icon_hover_color", white_color)
	copy_btn.add_theme_color_override("icon_pressed_color", white_color)
	copy_btn.pressed.connect(func():
		DisplayServer.clipboard_set(code)
		copy_btn.add_theme_color_override("icon_normal_color", white_color)
		await get_tree().create_timer(1.5).timeout
		copy_btn.add_theme_color_override("icon_normal_color", gray_color)
	)
	row.add_child(copy_btn)
	_code_buttons.append(copy_btn)
	content_vbox.add_child(panel)
	_spacer(6)

func _add_block_example(blocks_data: Array) -> void:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 2)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(wrapper)
	_spacer(4)
	for i in blocks_data.size():
		var bd: Dictionary = blocks_data[i]
		var kind: String = str(bd.get("kind", "action"))
		var type: String = str(bd.get("type", ""))
		var fields: Array = bd.get("fields", [])
		var depth: int = int(bd.get("depth", 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		wrapper.add_child(row)
		if depth > 0:
			var indent := Control.new()
			indent.custom_minimum_size = Vector2(20 * depth, 0)
			row.add_child(indent)
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style := StyleBoxFlat.new()
		var color := _block_color(kind, type)
		style.bg_color = color
		if depth == 0:
			style.corner_radius_top_left = 8
			style.corner_radius_top_right = 8
			style.corner_radius_bottom_left = 0 if i < blocks_data.size() - 1 else 8
			style.corner_radius_bottom_right = 0 if i < blocks_data.size() - 1 else 8
		else:
			style.set_corner_radius_all(6)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		panel.add_theme_stylebox_override("panel", style)
		row.add_child(panel)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 2)
		panel.add_child(inner)
		var title_label := Label.new()
		title_label.text = _block_title(kind, type)
		title_label.add_theme_font_size_override("font_size", GyroUI.fs(13))
		title_label.add_theme_color_override("font_color", Color.WHITE)
		inner.add_child(title_label)
		for fv in fields:
			var fd: Dictionary = fv
			var frow := HBoxContainer.new()
			frow.add_theme_constant_override("separation", 6)
			inner.add_child(frow)
			var fname := Label.new()
			fname.text = GyroLang.t(str(fd.get("label", "")))
			fname.add_theme_font_size_override("font_size", GyroUI.fs(11))
			fname.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
			fname.custom_minimum_size = Vector2(GyroUI.sz(80), 0)
			frow.add_child(fname)
			var fval := Label.new()
			fval.text = str(fd.get("value", ""))
			fval.add_theme_font_size_override("font_size", GyroUI.fs(11))
			fval.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
			frow.add_child(fval)
	_spacer(6)

func _block_color(kind: String, type: String) -> Color:
	if kind == "event":
		return GyroBlocks.COLOR_EVENT
	if kind == "condition":
		return GyroBlocks.CONDITION_COLORS.get(type, Color(0.45, 0.5, 0.3))
	return GyroBlocks.ACTION_COLORS.get(type, Color(0.5, 0.5, 0.5))

func _block_title(kind: String, type: String) -> String:
	if kind == "event":
		return GyroBlocks.event_name(type)
	if kind == "condition":
		return GyroBlocks.condition_name(type)
	return GyroBlocks.action_name(type)

func _add_link(text: String) -> void:
	var regex := RegEx.new()
	regex.compile("\\[link=([^\\]]+)\\]([^\\[]+)\\[/link\\]")
	var match := regex.search(text)
	if match == null:
		return
	var section_id := match.get_string(1)
	var link_text := match.get_string(2)
	var btn := Button.new()
	btn.text = "› " + link_text
	btn.flat = true
	btn.add_theme_color_override("font_color", Color(0.4, 0.7, 0.95))
	btn.add_theme_font_size_override("font_size", GyroUI.fs(14))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(func(): open_section(section_id))
	content_vbox.add_child(btn)
	_spacer(4)

func _toggle_sidebar() -> void:
	sidebar_visible = not sidebar_visible
	%SidebarLayer.visible = sidebar_visible

func _spacer(size: int) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, size)
	content_vbox.add_child(spacer)

func open_section_by_block_type(block_type: String) -> void:
	var mapping := {
		"MoveNode": "ch3_objects", "SetNodeProperty": "ch3_objects", "SetSize": "ch3_objects",
		"SetText": "ch3_objects", "CreateObject": "ch3_objects", "DeleteObject": "ch3_objects",
		"SetVisible": "ch3_objects", "SetOpacity": "ch3_objects", "SetRotation": "ch3_transforms",
		"SetScale": "ch3_transforms", "ChangeLayer": "ch3_objects", "SetFontSize": "ch3_styles",
		"SetColor": "ch3_styles", "SetTextAlign": "ch3_styles", "SetTexture": "ch3_styles",
		"SetObjectMeta": "ch3_transforms",
		"CreateGroup": "ch3_groups", "AddToGroup": "ch3_groups",
		"SetAnchor": "ch3_anchors",
		"CreateCircle": "ch3_shapes", "CreateLine": "ch3_shapes",
		"SetGradient": "ch3_styles", "SetBorder": "ch3_styles", "SetCornerRadius": "ch3_styles",
		"SetPivot": "ch3_transforms", "FaceObject": "ch3_transforms",
		"CreateSpriteAnim": "ch5_sprite_anim", "SetFrame": "ch5_sprite_anim",
		"PlayAnimation": "ch5_sprite_anim", "StopAnimation": "ch5_sprite_anim",
		"SetDraggable": "ch4_draggable",
		"Spawn": "ch3_spawn",
		"SetVelocity": "ch4_physics", "AddVelocity": "ch4_physics", "SetGravity": "ch4_physics",
		"SetSolid": "ch4_physics", "SetSensor": "ch4_physics",
		"SetPhysicsPaused": "ch4_physics", "SetGlobalGravity": "ch4_physics",
		"PlaySound": "ch5_sound", "StopSound": "ch5_sound", "SetSoundVolume": "ch5_sound",
		"TweenPosition": "ch3_tweens", "TweenScale": "ch3_tweens",
		"TweenRotation": "ch3_tweens", "TweenOpacity": "ch3_tweens", "StopTween": "ch3_tweens",
		"SetCameraPosition": "ch5_camera", "CameraFollow": "ch5_camera", "SetParallax": "ch5_camera",
		"CreateParticles": "ch5_particles", "SetParticlesParam": "ch5_particles", "DeleteParticles": "ch5_particles",
		"SetVariable": "ch6_vars", "AddToVariable": "ch6_vars", "SetTableValue": "ch6_tables",
		"GetTableValue": "ch6_tables", "InsertArrayValue": "ch6_tables", "RemoveArrayValue": "ch6_tables",
		"OverwriteTable": "ch6_tables", "ForEachTable": "ch6_tables", "LoopRange": "ch6_tables",
		"AddTag": "ch6_tags", "DeleteByTag": "ch6_tags", "SetVisibleByTag": "ch6_tags",
		"SetPositionByTag": "ch6_tags", "SetRotationByTag": "ch6_tags",
		"SetOpacityByTag": "ch6_tags", "SetScaleByTag": "ch6_tags", "ChangeLayerByTag": "ch6_tags",
		"CreateInput": "ch6_widgets", "CreateSlider": "ch6_widgets", "CreateToggle": "ch6_widgets",
		"GetWidgetText": "ch6_widgets", "SetSliderValue": "ch6_widgets", "SetToggleState": "ch6_widgets",
		"ReadFile": "ch7_files", "WriteFile": "ch7_files",
		"FileOp": "ch7_files", "HttpRequest": "ch7_files",
		"SaveValue": "ch7_files", "LoadValue": "ch7_files",
		"Print": "ch7_system", "Toast": "ch7_system",
		"SetBackgroundColor": "ch7_system", "SetOrientation": "ch7_system",
		"Clipboard": "ch7_system", "OpenURL": "ch7_system",
		"Quit": "ch7_system", "RandomSeed": "ch7_system",
		"EmitEvent": "ch2_custom_events", "StartTimer": "ch2_events", "StopTimer": "ch2_events",
		"If": "ch2_conditions", "Repeat": "ch2_conditions", "Wait": "ch2_actions",
		"Always": "ch2_conditions", "VariableEquals": "ch2_conditions",
		"VariableGreaterThan": "ch2_conditions", "PayloadEquals": "ch2_conditions",
		"PayloadGreaterThan": "ch2_conditions"
	}
	var section_id = mapping.get(block_type, "")
	if section_id != "":
		_switch_mode("guide")
		open_section(section_id)
