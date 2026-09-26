class_name GyroEventRule
extends Resource

@export var event_type := "ready"
@export var note := ""
@export var event_name := ""
@export var conditions: Array[GyroCondition] = []
@export var actions: Array[GyroAction] = []
@export var disabled := false
@export var event_filter := ""

func is_named() -> bool:
	return event_type == "custom" or event_type == "func"

func fire_name() -> String:
	if is_named():
		return event_name
	return event_type
