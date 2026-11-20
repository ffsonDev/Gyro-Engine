class_name GyroExprEditor
extends Control
signal accepted(text: String)
signal functions_requested
var _var_names: Array = []
var _param_names: Array = []
var _current_chip := ""

func _ready() -> void:
	%Title.add_theme_font_size_override("font_size", GyroUI.fs(26))
	%Title.add_theme_color_override("font_color", Color.WHITE)
	%ExprEdit.add_theme_font_size_override("font_size", GyroUI.fs(24))
	%CloseButton.pressed.connect(func(): visible = false)
	%OkButton.pressed.connect(func():
		visible = false
		accepted.emit(%ExprEdit.text)
	)
	%ChipFuncs.pressed.connect(func(): _toggle("funcs"))
	%ChipVars.pressed.connect(func(): _toggle("vars"))
	%ChipCompare.pressed.connect(func(): _toggle("compare"))
	%ChipLogic.pressed.connect(func(): _toggle("logic"))
	var chips := %ChipLogic.get_parent() as VBoxContainer
	var mine := Button.new()
	mine.name = "ChipMine"
	mine.custom_minimum_size = Vector2(0, GyroUI.sz(56))
	mine.pressed.connect(func(): _toggle("mine"))
	chips.add_child(mine)
	var manage := Button.new()
	manage.name = "ChipManage"
	manage.custom_minimum_size = Vector2(0, GyroUI.sz(48))
	manage.pressed.connect(func(): functions_requested.emit())
	chips.add_child(manage)
	
	var ts := GyroTouchScroll.new()
	add_child(ts)
	ts.setup(%ExtraScroll)
	
	apply_lang()

func apply_lang() -> void:
	%Title.text = GyroLang.t("expr_title")
	%ChipFuncs.text = GyroLang.t("expr_funcs")
	%ChipVars.text = GyroLang.t("expr_vars")
	%ChipCompare.text = GyroLang.t("expr_compare")
	%ChipLogic.text = GyroLang.t("expr_logic")
	var chips := %ChipLogic.get_parent()
	if chips.has_node("ChipMine"):
		(chips.get_node("ChipMine") as Button).text = GyroLang.t("expr_functions_mine")
	if chips.has_node("ChipManage"):
		(chips.get_node("ChipManage") as Button).text = GyroLang.t("expr_manage_functions")

func open(initial: String, var_names: Array, param_names: Array = []) -> void:
	_var_names = var_names
	_param_names = param_names
	%ExprEdit.text = initial
	_current_chip = ""
	GyroUI.clear_children(%ExtraList)
	visible = true

func _toggle(which: String) -> void:
	if _current_chip == which:
		_current_chip = ""
		GyroUI.clear_children(%ExtraList)
		return
	_current_chip = which
	GyroUI.clear_children(%ExtraList)
	match which:
		"funcs":
			for f in ["min(", "max(", "abs(", "round(", "floor(", "ceil(", "rand(", "randi(", "clamp(", "len(", "text(", "sqrt(", "pow(", "sin(", "cos(", "lerp(", "map(", "screen_w(", "screen_h(", "center_x(", "center_y(", "offset_x(", "offset_y(", "obj_x(", "obj_y(", "obj_w(", "obj_h(", "dist(", "time("]:
				_add_extra(f)
		"compare":
			for c in ["==", "!=", "<", "<=", ">", ">="]:
				_add_extra(c)
		"logic":
			for l in ["and", "or", "not", "&&", "||", "!"]:
				_add_extra(l)
		"mine":
			for v in GyroFunctions.items():
				var f := v as GyroCustomFunction
				if f != null:
					_add_extra(f.func_name + "(")
		"vars":
			for name in _var_names:
				_add_extra("$var." + str(name))
			for name in _param_names:
				_add_extra("$param." + str(name))
			for p in ["x", "y", "dx", "dy", "value", "name", "old", "new", "a", "b", "status", "body", "keycode", "type"]:
				_add_extra("$payload." + p)

func _add_extra(token: String) -> void:
	var b := Button.new()
	b.text = token
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, GyroUI.sz(48))
	b.pressed.connect(func(): _insert(token))
	%ExtraList.add_child(b)

func _insert(token: String) -> void:
	var col = %ExprEdit.caret_column
	var left = %ExprEdit.text.substr(0, col)
	var right = %ExprEdit.text.substr(col)
	%ExprEdit.text = left + token + right
	%ExprEdit.caret_column = col + token.length()
