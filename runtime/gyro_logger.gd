class_name GyroLogger
extends RefCounted

signal log_received(entry: Dictionary)

var _enabled := false
var _entries: Array[Dictionary] = []
var _max_entries := 500

static var _instance: GyroLogger = null

static func get_instance() -> GyroLogger:
	if _instance == null:
		_instance = GyroLogger.new()
	return _instance

func enable() -> void:
	_enabled = true
	_entries.clear()

func disable() -> void:
	_enabled = false

func log_message(message: String, level: String = "info") -> void:
	if not _enabled:
		return
	
	var entry := {
		"time": Time.get_time_string_from_system(),
		"level": level,
		"message": message,
	}
	_entries.append(entry)
	if _entries.size() > _max_entries:
		_entries.pop_front()
	
	log_received.emit(entry)

func log_info(message: String) -> void:
	log_message(message, "info")

func log_warn(message: String) -> void:
	log_message(message, "warning")

func log_error(message: String) -> void:
	log_message(message, "error")

func log_debug(message: String) -> void:
	log_message(message, "debug")

func get_all_entries() -> Array[Dictionary]:
	return _entries

func clear() -> void:
	_entries.clear()
