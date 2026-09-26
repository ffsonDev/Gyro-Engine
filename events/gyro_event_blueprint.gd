class_name GyroEventBlueprint
extends Resource

@export var rules: Array[GyroEventRule] = []
@export var variables: Dictionary = {}
@export var variable_types: Dictionary = {}
@export var timers: Array[GyroTimerConfig] = []

func migrate_event_names() -> bool:
	var changed := false
	for r in rules:
		if r == null:
			continue
		if r.event_type == "ready" and r.event_name != "":
			var old := r.event_name
			if GyroBlocks.BUILTIN_EVENTS.has(old):
				r.event_type = old
				r.event_name = ""
			elif old.begins_with("func_"):
				r.event_type = "func"
				r.event_name = old
			else:
				r.event_type = "custom"
				r.event_name = old
			changed = true
		elif not r.is_named() and r.event_name != "":
			r.event_name = ""
			changed = true
	return changed
