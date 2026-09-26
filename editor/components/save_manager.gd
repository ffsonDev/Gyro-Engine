class_name SaveManager
extends RefCounted

signal save_performed

var dirty := false
var _timer: Timer
var _save: Callable
var _host: Node

const DEBOUNCE_SEC := 1.5

func setup(host: Node, save_fn: Callable) -> void:
	_host = host
	_save = save_fn
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = DEBOUNCE_SEC
	_timer.timeout.connect(flush)
	_host.add_child(_timer)

func mark_dirty() -> void:
	dirty = true
	_timer.start()

func flush() -> void:
	if not dirty:
		return
	if _save.is_valid():
		_save.call()
	dirty = false
	save_performed.emit()

func force_save() -> void:
	_timer.stop()
	flush()
