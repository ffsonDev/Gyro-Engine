class_name BlockRenderer
extends RefCounted

signal event_name_changed(rule: GyroEventRule, text: String)
signal note_changed(rule: GyroEventRule, text: String)
signal remove_rule_requested(rule: GyroEventRule)
signal copy_rule_requested(rule: GyroEventRule)
signal collapse_rule_requested(rule: GyroEventRule)
signal remove_action_requested(rule: GyroEventRule, action: GyroAction)
signal copy_action_requested(rule: GyroEventRule, action: GyroAction)
signal remove_condition_requested(rule: GyroEventRule, condition: GyroCondition)
signal copy_condition_requested(rule: GyroEventRule, condition: GyroCondition)
signal field_focus_entered()
signal block_collapse_requested(resource: Variant)
signal expr_pick_requested(set_callback: Callable, key: String, button: Button)
signal var_pick_requested(set_callback: Callable, key: String, button: Button, resource: Variant)
signal obj_pick_requested(set_callback: Callable, key: String, button: Button)
signal asset_pick_requested(set_callback: Callable, key: String, button: Button, kind: String)
signal event_pick_requested(set_callback: Callable, key: String, button: Button)
signal block_menu_requested(kind: String, resource: Variant, rule: GyroEventRule)

var _rule_titles := {}
var _name_edits := {}
var editor: GyroBlockEditor
var flow_handler: FlowHandler
var _style_cache := {}
var _style_v_cache := {}
var _field_nodes := {}
var _block_panels := {}

var _burger_icon: Texture2D
var _pick_style_normal: StyleBoxFlat
var _pick_style_focus: StyleBoxFlat
var _more_icon: Texture2D

const EVENT_FILTER := {
	"timer": {"kind": "timer", "label": "field.timer_name"},
	"var_changed": {"kind": "var", "label": "field.var_name"},
	"widget_changed": {"kind": "obj", "label": "field.widget"},
	"obj_touch_begin": {"kind": "obj", "label": "field.node"},
	"obj_touch_end": {"kind": "obj", "label": "field.node"},
	"collide": {"kind": "obj", "label": "field.node"},
	"collide_end": {"kind": "obj", "label": "field.node"},
}

func setup(ed: GyroBlockEditor, flow: FlowHandler) -> void:
	editor = ed
	flow_handler = flow
	_load_shared_resources()
	_warm_style_cache()

func _load_shared_resources() -> void:
	_burger_icon = load("res://ui/icons/burger.svg")
	_more_icon = load("res://ui/icons/more.svg")
	_pick_style_normal = StyleBoxFlat.new()
	_pick_style_normal.bg_color = Color(0, 0, 0, 0)
	_pick_style_normal.border_width_bottom = 2
	_pick_style_normal.border_color = Color(0.1, 0.1, 0.12)
	_pick_style_normal.content_margin_left = 4
	_pick_style_normal.content_margin_right = 4
	_pick_style_normal.content_margin_top = 2
	_pick_style_normal.content_margin_bottom = 2
	_pick_style_focus = _pick_style_normal.duplicate()

func _warm_style_cache() -> void:
	for type in GyroBlocks.ACTION_COLORS:
		_style(GyroBlocks.ACTION_COLORS[type], 8)
		_style_v(GyroBlocks.ACTION_COLORS[type].darkened(0.35), 0, 10)
	for type in GyroBlocks.CONDITION_COLORS:
		_style(GyroBlocks.CONDITION_COLORS[type], 8)
	_style_v(GyroBlocks.COLOR_EVENT, 10, 0)
	_style_v(GyroBlocks.COLOR_EVENT.darkened(0.35), 0, 10)

func clear_field_cache() -> void:
	_field_nodes.clear()
	_block_panels.clear()
	_rule_titles.clear()
	_name_edits.clear()

func update_field_value(resource: Variant, key: String, value: Variant) -> void:
	if _field_nodes.has(resource):
		var fields: Dictionary = _field_nodes[resource]
		if fields.has(key):
			var btn: Button = fields[key]
			if is_instance_valid(btn) and btn.get_child_count() > 0:
				var label: Label = btn.get_child(0) as Label
				if label != null:
					label.text = _short(editor._display_value(value))

func get_block_panel(resource: Variant) -> PanelContainer:
	if _block_panels.has(resource):
		var panel = _block_panels[resource]
		if is_instance_valid(panel):
			return panel
	return null

func block_alpha(resource: Variant) -> float:
	return 0.45 if bool(resource.get("disabled")) else 1.0

func refresh_block_alpha(resource: Variant) -> void:
	var panel := get_block_panel(resource)
	if panel != null:
		panel.modulate.a = block_alpha(resource)

func build_event_block(parent: Control, rule: GyroEventRule, collapsed: bool) -> VBoxContainer:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 0)
	parent.add_child(wrapper)

	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _style_v(GyroBlocks.COLOR_EVENT, 10, 0))
	wrapper.add_child(header)

	var header_row := HBoxContainer.new()
	header.add_child(header_row)

	var handle := _make_handle()
	handle.button_down.connect(func(): editor._start_drag_from_rule(rule, wrapper))
	header_row.add_child(handle)

	var title_label := Label.new()
	title_label.text = _rule_title(rule)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", GyroUI.fs(20))
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header_row.add_child(title_label)
	_rule_titles[rule] = title_label

	var options_btn := GyroUI.icon_button("res://ui/icons/more.svg", GyroUI.fs(26), 10)
	options_btn.pressed.connect(func(): block_menu_requested.emit("rule", rule, rule))
	header_row.add_child(options_btn)

	var body_panel := PanelContainer.new()
	body_panel.add_theme_stylebox_override("panel", _style_v(GyroBlocks.COLOR_EVENT.darkened(0.35), 0, 10))
	body_panel.visible = not collapsed
	wrapper.add_child(body_panel)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body_panel.add_child(body)

	if not collapsed:
		_build_rule_body(body, rule)

	wrapper.modulate.a = 0.45 if rule.disabled else 1.0
	return wrapper

func _build_rule_body(body: VBoxContainer, rule: GyroEventRule) -> void:
	# === Заметка ===
	var note_row := HBoxContainer.new()
	body.add_child(note_row)
	var note_label := Label.new()
	note_label.text = GyroLang.t("note")
	note_label.add_theme_color_override("font_color", Color.WHITE)
	note_row.add_child(note_label)
	var note_btn := _make_pick_button(rule.note)
	note_btn.set_meta("expr_raw", rule.note)
	var note_set := func(key: String, value: Variant):
		rule.note = str(value)
		editor._mark_dirty()
	note_btn.pressed.connect(func(): expr_pick_requested.emit(note_set, "note", note_btn))
	note_row.add_child(note_btn)

	if rule.is_named():
		var name_row := HBoxContainer.new()
		body.add_child(name_row)
		var name_label := Label.new()
		name_label.text = GyroLang.t("event_name_label")
		name_label.add_theme_color_override("font_color", Color.WHITE)
		name_row.add_child(name_label)
		var name_btn := _make_pick_button(rule.event_name)
		name_btn.set_meta("expr_raw", rule.event_name)
		var name_set := func(key: String, value: Variant):
			var clean := str(value).strip_edges()
			if clean == "" or GyroBlocks.BUILTIN_EVENTS.has(clean) or editor._is_event_name_taken(clean, rule):
				editor._set_pick_text(name_btn, rule.event_name)
				name_btn.set_meta("expr_raw", rule.event_name)
				return
			rule.event_name = clean
			refresh_rule_title(rule)
			editor._mark_dirty()
		name_btn.pressed.connect(func(): expr_pick_requested.emit(name_set, "event_name", name_btn))
		name_row.add_child(name_btn)
		_name_edits[rule] = name_btn

	var fmeta: Dictionary = EVENT_FILTER.get(rule.event_type, {})
	if not fmeta.is_empty():
		var frow := HBoxContainer.new()
		body.add_child(frow)
		var flabel := Label.new()
		flabel.text = GyroLang.t(str(fmeta.label))
		flabel.add_theme_color_override("font_color", Color.WHITE)
		frow.add_child(flabel)
		var fbtn := _make_pick_button(rule.event_filter)
		fbtn.set_meta("expr_raw", rule.event_filter)
		if rule.event_filter == "":
			var fl: Label = fbtn.get_child(0) as Label
			if fl != null:
				fl.text = GyroLang.t("filter_any")
		var set_filter := func(key: String, value: Variant):
			rule.event_filter = str(value)
			editor._mark_dirty()
		match str(fmeta.kind):
			"timer":
				fbtn.pressed.connect(func(): editor._open_timer_for(set_filter, "event_filter", fbtn))
			"var":
				fbtn.pressed.connect(func(): var_pick_requested.emit(set_filter, "event_filter", fbtn, rule))
			"obj":
				fbtn.pressed.connect(func(): obj_pick_requested.emit(set_filter, "event_filter", fbtn))
		frow.add_child(fbtn)

	for condition_value in rule.conditions:
		var condition: GyroCondition = condition_value as GyroCondition
		if condition == null:
			continue
		_build_condition_block(body, rule, condition)

	for action_value in rule.actions:
		var action: GyroAction = action_value as GyroAction
		if action == null:
			continue
		_build_action_block(body, rule, action)

func _build_condition_block(parent: Control, rule: GyroEventRule, condition: GyroCondition) -> void:
	var schema: Array = GyroBlocks.CONDITION_SCHEMAS.get(condition.type, [])
	var color: Color = GyroBlocks.CONDITION_COLORS.get(condition.type, Color(0.45, 0.5, 0.3))
	_build_data_block(
		parent, rule, "condition", condition, color,
		GyroBlocks.condition_name(condition.type), schema, condition.data,
		func(): remove_condition_requested.emit(rule, condition),
		func(): copy_condition_requested.emit(rule, condition),
		func(key: String, value: Variant): condition.data[key] = value
	)

func _build_action_block(parent: Control, rule: GyroEventRule, action: GyroAction) -> void:
	var schema: Array = GyroBlocks.ACTION_SCHEMAS.get(action.type, [])
	var color: Color = GyroBlocks.ACTION_COLORS.get(action.type, Color(0.72, 0.55, 0.25))
	_build_data_block(
		parent, rule, "action", action, color,
		GyroBlocks.action_name(action.type), schema, action.data,
		func(): remove_action_requested.emit(rule, action),
		func(): copy_action_requested.emit(rule, action),
		func(key: String, value: Variant): action.data[key] = value
	)

func _build_data_block(
	parent: Control, rule: GyroEventRule, kind: String, resource: Variant,
	color: Color, title_text: String, schema: Array, data: Dictionary,
	remove_cb: Callable, copy_cb: Callable, set_callback: Callable,
	owner_array: Array = []
) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(color, 8))
	parent.add_child(panel)
	_block_panels[resource] = panel

	var is_collapsed := bool(editor.block_collapsed.get(resource, false))
	panel.modulate.a = 0.45 if (bool(resource.get("disabled")) or is_collapsed) else 1.0
	editor._drag_register(kind, resource, rule, panel, owner_array)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	var handle := _make_handle()
	handle.button_down.connect(func(): editor._start_drag_from_panel(kind, resource, rule, panel))
	title_row.add_child(handle)

	var title := Label.new()
	title.text = title_text
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_font_size_override("font_size", GyroUI.fs(18))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	var more := GyroUI.icon_button("res://ui/icons/more.svg", GyroUI.fs(26), 10)
	more.pressed.connect(func(): block_menu_requested.emit(kind, resource, rule))
	title_row.add_child(more)

	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 4)
	fields.visible = not is_collapsed
	vbox.add_child(fields)
	
	if kind == "action":
		var flow_action: GyroAction = resource as GyroAction
		if flow_action != null and (flow_action.type == "If" or flow_action.type == "Repeat" or flow_action.type == "ForEachTable" or flow_action.type == "LoopRange"):
			_build_flow_pocket(vbox, rule, flow_action)

	var field_map: Dictionary = {}
	for field_value in schema:
		var key: String = str(field_value[0])
		var label_text: String = str(field_value[1])
		var row := HBoxContainer.new()
		fields.add_child(row)

		var label := Label.new()
		label.text = GyroLang.t(label_text)
		label.custom_minimum_size = Vector2(GyroUI.sz(110), 0)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_font_size_override("font_size", GyroUI.fs(16))
		row.add_child(label)

		var btn := _make_pick_button(editor._display_value(data.get(key, null)))
		if field_value.size() > 2 and str(field_value[2]) == "var":
			btn.set_meta("expr_raw", data.get(key, null))
			btn.pressed.connect(func(): var_pick_requested.emit(set_callback, key, btn, resource))
		elif field_value.size() > 2 and str(field_value[2]) == "obj":
			btn.pressed.connect(func(): obj_pick_requested.emit(set_callback, key, btn))
		elif field_value.size() > 2 and (str(field_value[2]) == "sprite" or str(field_value[2]) == "sound"):
			var pick_kind: String = str(field_value[2])
			btn.pressed.connect(func(): asset_pick_requested.emit(set_callback, key, btn, pick_kind))
		elif field_value.size() > 2 and str(field_value[2]) == "event":
			btn.pressed.connect(func(): event_pick_requested.emit(set_callback, key, btn))
		else:
			btn.set_meta("expr_raw", data.get(key, null))
			btn.pressed.connect(func(): expr_pick_requested.emit(set_callback, key, btn))
		row.add_child(btn)
		field_map[key] = btn
	_field_nodes[resource] = field_map

func _rule_title(rule: GyroEventRule) -> String:
	if rule.is_named():
		return rule.event_name if rule.event_name != "" else GyroLang.t("event_name_placeholder")
	return GyroBlocks.event_name(rule.event_type)

func refresh_rule_title(rule: GyroEventRule) -> void:
	var l = _rule_titles.get(rule, null)
	if is_instance_valid(l):
		l.text = _rule_title(rule)

func mark_rule_name_invalid(rule: GyroEventRule, on: bool) -> void:
	var e = _name_edits.get(rule, null)
	if is_instance_valid(e):
		e.modulate = Color(1.0, 0.6, 0.6) if on else Color.WHITE

func _build_flow_pocket(vbox: VBoxContainer, rule: GyroEventRule, flow_action: GyroAction) -> void:
	var pocket := PanelContainer.new()
	var pocket_style := StyleBoxFlat.new()
	pocket_style.bg_color = Color(0, 0, 0, 0.25)
	pocket_style.set_corner_radius_all(6)
	pocket_style.content_margin_bottom = 8
	pocket.add_theme_stylebox_override("panel", pocket_style)
	pocket.custom_minimum_size = Vector2(0, GyroUI.sz(48))
	pocket.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(pocket)

	var pocket_vbox := VBoxContainer.new()
	pocket_vbox.add_theme_constant_override("separation", 2)
	pocket_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pocket.add_child(pocket_vbox)

	var arr: Array = flow_handler.get_array(flow_action)
	for child_value in arr:
		var child: GyroAction = child_value as GyroAction
		if child == null:
			continue
		_build_flow_child_block(pocket_vbox, rule, flow_action, child)

	editor._drag_register_flow(flow_action, pocket)

func _build_flow_child_block(parent: Control, rule: GyroEventRule, flow_action: GyroAction, child: GyroAction) -> void:
	var schema: Array = GyroBlocks.ACTION_SCHEMAS.get(child.type, [])
	var color: Color = GyroBlocks.ACTION_COLORS.get(child.type, Color(0.72, 0.55, 0.25))
	var remove_callback := func():
		flow_handler.get_array(flow_action).erase(child)
		flow_handler.sync(flow_action)
		editor._on_flow_changed()
	var copy_callback := func():
		var arr: Array = flow_handler.get_array(flow_action)
		var index: int = arr.find(child)
		var copy: GyroAction = child.duplicate(true) as GyroAction
		arr.insert(index + 1, copy)
		flow_handler.sync(flow_action)
		editor._on_flow_changed()
	var set_callback := func(key: String, value: Variant):
		child.data[key] = value
		flow_handler.sync(flow_action)
	_build_data_block(
		parent, rule, "action", child, color,
		GyroBlocks.action_name(child.type), schema, child.data,
		remove_callback, copy_callback, set_callback,
		flow_handler.get_array(flow_action)
	)

func _make_handle() -> Button:
	var button := Button.new()
	button.icon = _burger_icon
	button.flat = true
	button.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	button.custom_minimum_size = Vector2(GyroUI.sz(25), GyroUI.sz(35))
	button.add_theme_constant_override("icon_max_width", 25)
	return button

func _make_pick_button(initial_text: String) -> Button:
	var button := Button.new()
	button.flat = false
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_stylebox_override("normal", _pick_style_normal)
	button.add_theme_stylebox_override("hover", _pick_style_normal)
	button.add_theme_stylebox_override("pressed", _pick_style_normal)
	button.add_theme_stylebox_override("focus", _pick_style_focus)
	var label := Label.new()
	label.text = _short(initial_text) if initial_text != "" else GyroLang.t("pick")
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", GyroUI.fs(16))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	return button

func _short(text: String, max_chars: int = 24) -> String:
	if text.length() > max_chars:
		return text.substr(0, max_chars - 1) + "…"
	return text

func _style(color: Color, radius: int) -> StyleBoxFlat:
	var key := str(color) + "_" + str(radius)
	if _style_cache.has(key):
		return _style_cache[key]
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_style_cache[key] = style
	return style

func _style_v(color: Color, r_top: int, r_bottom: int) -> StyleBoxFlat:
	var key := str(color) + "_" + str(r_top) + "_" + str(r_bottom)
	if _style_v_cache.has(key):
		return _style_v_cache[key]
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = r_top
	style.corner_radius_top_right = r_top
	style.corner_radius_bottom_right = r_bottom
	style.corner_radius_bottom_left = r_bottom
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_style_v_cache[key] = style
	return style

func _style_field(edit: LineEdit, underline: bool = true) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	if underline:
		style.border_width_bottom = 2
		style.border_color = Color(0.1, 0.1, 0.12)
	edit.add_theme_stylebox_override("normal", style)
	edit.add_theme_stylebox_override("focus", style)
	edit.add_theme_color_override("font_color", Color.WHITE)
	edit.add_theme_color_override("caret_color", Color.WHITE)
	edit.add_theme_font_size_override("font_size", GyroUI.fs(16))
