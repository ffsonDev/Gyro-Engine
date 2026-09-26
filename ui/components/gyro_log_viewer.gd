class_name GyroLogViewer
extends Control

var _log_label: RichTextLabel
var _auto_scroll := true

func _ready() -> void:
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_log_label)
	
	var logger := GyroLogger.get_instance()
	logger.log_received.connect(_on_log_entry)

func _on_log_entry(entry: Dictionary) -> void:
	var color := "white"
	match entry["level"]:
		"warning": color = "yellow"
		"error": color = "red"
		"debug": color = "gray"
	
	var line := "[color=%s][%s] %s[/color]\n" % [color, entry["time"], entry["message"]]
	_log_label.append_text(line)

func clear() -> void:
	_log_label.clear()
