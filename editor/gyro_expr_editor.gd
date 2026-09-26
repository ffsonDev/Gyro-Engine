class_name GyroExprEditor
extends Control

signal accepted(text: String)

var _var_names: Array = []
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

func open(initial: String, var_names: Array) -> void:
	_var_names = var_names
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
			for f in ["min(", "max(", "abs(", "round(", "floor(", "ceil(", "rand(", "clamp(", "len(", "text(", "time", "screen_w", "screen_h"]:
				_add_extra(f)
		"compare":
			for c in ["==", "!=", "<", "<=", ">", ">="]:
				_add_extra(c)
		"logic":
			for l in ["and", "or", "not", "&&", "||", "!"]:
				_add_extra(l)
		"vars":
			for name in _var_names:
				_add_extra("$var." + str(name))

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
