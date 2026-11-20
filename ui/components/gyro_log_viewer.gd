class_name GyroLogViewer
extends Control
const MAX_LOG_LINES := 100
var _log_label: RichTextLabel
var _auto_scroll := true
var _line_count := 0

func _ready() -> void:
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_log_label)
	var logger := GyroLogger.get_instance()
	logger.log_received.connect(_on_log_entry)
	tree_exiting.connect(func():
		if logger.log_received.is_connected(_on_log_entry):
			logger.log_received.disconnect(_on_log_entry)
	)
	
func _on_log_entry(entry: Dictionary) -> void:
	var color := "white"
	match entry["level"]:
		"warning": color = "yellow"
		"error": color = "red"
		"debug": color = "gray"
	var line := "[color=%s][%s] %s[/color]
" % [color, entry["time"], entry["message"]]
	_log_label.append_text(line)
	_line_count += 1
	if _line_count > MAX_LOG_LINES:
		_log_label.remove_paragraph(0)
		_line_count -= 1
		
func clear() -> void:
	_log_label.clear()
	_line_count = 0
