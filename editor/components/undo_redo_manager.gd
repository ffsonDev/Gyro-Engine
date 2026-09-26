class_name UndoRedoManager
extends RefCounted

signal snapshot_requested(snapshot: Dictionary)
signal restore_requested(snapshot: Dictionary)

const MAX_STEPS := 50

var undo_stack: Array = []
var redo_stack: Array = []
var pending_snapshot: Dictionary = {}

var _capture: Callable
var _apply: Callable

func setup(capture: Callable, apply: Callable) -> void:
	_capture = capture
	_apply = apply

func clear() -> void:
	undo_stack.clear()
	redo_stack.clear()
	pending_snapshot = {}

func mark_field_focus() -> void:
	if pending_snapshot.is_empty() and _capture.is_valid():
		pending_snapshot = _capture.call()

func commit_pending() -> void:
	if pending_snapshot.is_empty():
		return
	undo_stack.append(pending_snapshot)
	_trim()
	redo_stack.clear()
	pending_snapshot = {}

func push_undo() -> void:
	if not pending_snapshot.is_empty():
		commit_pending()
		return
	if _capture.is_valid():
		undo_stack.append(_capture.call())
		_trim()
	redo_stack.clear()

func undo() -> void:
	if undo_stack.is_empty():
		return
	commit_pending()
	if _capture.is_valid():
		redo_stack.append(_capture.call())
	var snapshot: Dictionary = undo_stack.pop_back()
	if _apply.is_valid():
		_apply.call(snapshot)

func redo() -> void:
	commit_pending()
	if redo_stack.is_empty():
		return
	if _capture.is_valid():
		undo_stack.append(_capture.call())
		_trim()
	var snapshot: Dictionary = redo_stack.pop_back()
	if _apply.is_valid():
		_apply.call(snapshot)

func _trim() -> void:
	while undo_stack.size() > MAX_STEPS:
		undo_stack.pop_front()
