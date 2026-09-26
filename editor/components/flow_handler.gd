class_name FlowHandler
extends RefCounted

var _cache := {}

func get_array(action: GyroAction) -> Array:
	if _cache.has(action):
		return _cache[action]
	var arr: Array = []
	var blocks = action.data.get("blocks", [])
	if blocks is Array:
		for b in (blocks as Array):
			var bd := b as Dictionary
			if bd.is_empty():
				continue
			var child := GyroAction.new()
			child.type = str(bd.get("type", ""))
			child.data = (bd.get("data", {}) as Dictionary).duplicate(true)
			child.disabled = bool(bd.get("disabled", false))   # ← добавлено
			arr.append(child)
	_cache[action] = arr
	return arr

func sync(action: GyroAction) -> void:
	var arr: Array = _cache.get(action, [])
	var blocks: Array = []
	for c in arr:
		var child := c as GyroAction
		if child == null:
			continue
		blocks.append({"type": child.type, "data": child.data.duplicate(true), "disabled": child.disabled})   # ← добавлено
	action.data["blocks"] = blocks

func sync_all() -> void:
	for key in _cache.keys():
		sync(key)

func clear() -> void:
	_cache.clear()
