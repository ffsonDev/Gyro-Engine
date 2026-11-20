class_name BlockEditorState
extends RefCounted

var blueprint: GyroEventBlueprint
var project: GyroProject
var current_script: GyroScript
var save_path: String

var rule_collapsed: Dictionary = {}
var block_collapsed: Dictionary = {}
var last_object_name: String = ""
var object_counter: int = 0
var custom_param_names: Array = []

var _merged_cache: GyroEventBlueprint
var _merged_dirty: bool = true
var _rule_sigs: Dictionary = {}

func _init() -> void:
	blueprint = GyroEventBlueprint.new()

func clear() -> void:
	rule_collapsed.clear()
	block_collapsed.clear()
	custom_param_names.clear()
	last_object_name = ""
	object_counter = 0
	_merged_cache = null
	_merged_dirty = true
	_rule_sigs.clear()

func mark_dirty() -> void:
	_merged_dirty = true
	if project != null:
		project.mark_merged_dirty()

func merged_blueprint() -> GyroEventBlueprint:
	if project == null:
		return blueprint
	if _merged_dirty or _merged_cache == null:
		_merged_cache = project.merge_blueprints()
		_merged_dirty = false
	return _merged_cache
