class_name GyroProject
extends Resource

const FORMAT_VERSION := 1

@export var format_version := 1
@export var scripts: Array[GyroScript] = []
@export var folders: Array[String] = []
@export var assets: Array[GyroAsset] = []
@export var settings: GyroProjectSettings
@export var blueprint: GyroEventBlueprint
@export var asset_folders: Array[String] = []

var _merged_cache: GyroEventBlueprint
var _merged_dirty := true

func mark_merged_dirty() -> void:
	_merged_dirty = true

func merge_blueprints() -> GyroEventBlueprint:
	if not _merged_dirty and _merged_cache != null:
		return _merged_cache

	var merged := GyroEventBlueprint.new()
	for s_value in scripts:
		var s := s_value as GyroScript
		if s == null or s.blueprint == null:
			continue
		for key in s.blueprint.variables.keys():
			merged.variables[key] = s.blueprint.variables[key]
		for rule in s.blueprint.rules:
			merged.rules.append(rule)
		for t_value in s.blueprint.timers:
			var t := t_value as GyroTimerConfig
			if t == null:
				continue
			var exists := false
			for mt_value in merged.timers:
				if (mt_value as GyroTimerConfig).timer_name == t.timer_name:
					exists = true
					break
			if not exists:
				merged.timers.append(t)

	_merged_cache = merged
	_merged_dirty = false
	return merged
	
func migrate_event_names() -> bool:
	var changed := false
	for s in scripts:
		if s != null and s.blueprint != null and s.blueprint.migrate_event_names():
			changed = true
	return changed
