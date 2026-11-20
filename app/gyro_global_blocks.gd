class_name GyroGlobalBlocks
extends RefCounted

const PATH := "user://gyro_global_blocks.json"
const VERSION := 1

static var _packs: Array = []
static var _blocks: Array = []
static var _loaded := false
static var _last_written := ""

static func packs() -> Array:
	_ensure_loaded()
	return _packs

static func blocks() -> Array:
	_ensure_loaded()
	return _blocks

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	var d: Dictionary = parsed
	_packs = GyroCustomRegistry.dict_to_packs(d.get("custom_packs", []))
	_blocks = GyroCustomRegistry.dict_to_blocks(d.get("custom_blocks", []))

static func attach(project: GyroProject) -> void:
	if project == null:
		return
	_ensure_loaded()
	project.custom_packs = _packs
	project.custom_blocks = _blocks
	project.set_meta("gyro_globals", true)

static func adopt(project: GyroProject) -> void:
	if project == null:
		return
	_ensure_loaded()
	if project.has_meta("gyro_globals"):
		return
	var renames := {}
	for pv in project.custom_packs.duplicate():
		var pk := pv as GyroCustomPack
		if pk == null:
			continue
		var target := _pack_by_name(pk.pack_name)
		if target == null:
			target = GyroCustomPack.new()
			target.pack_name = pk.pack_name
			target.author = pk.author
			target.version = pk.version
			_packs.append(target)
		for bv in pk.blocks.duplicate():
			var b := bv as GyroCustomBlock
			if b == null:
				continue
			var resolved := _resolve_block(b, renames)
			if resolved == b:
				target.blocks.append(resolved)
	for bv in project.custom_blocks.duplicate():
		var loose := bv as GyroCustomBlock
		if loose == null:
			continue
		var resolved_loose := _resolve_block(loose, renames)
		if resolved_loose == loose:
			_blocks.append(resolved_loose)
	if not renames.is_empty():
		_rename_refs(project, renames)
	attach(project)
	write()

static func sync_from(project: GyroProject) -> void:
	if project == null:
		return
	if not project.has_meta("gyro_globals"):
		adopt(project)
	write()

static func write() -> void:
	_ensure_loaded()
	var payload := JSON.stringify({
		"version": VERSION,
		"custom_packs": GyroCustomRegistry.packs_to_dict(_packs),
		"custom_blocks": GyroCustomRegistry.blocks_to_dict(_blocks),
	}, "  ")
	if payload == _last_written:
		return
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(payload)
	f.flush()
	var err := f.get_error()
	f.close()
	if err != OK:
		DirAccess.remove_absolute(tmp)
		return
	var rename_err := DirAccess.rename_absolute(tmp, PATH)
	if rename_err != OK and FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
		rename_err = DirAccess.rename_absolute(tmp, PATH)
	if rename_err != OK:
		DirAccess.remove_absolute(tmp)
		return
	_last_written = payload

static func _pack_by_name(pack_name: String) -> GyroCustomPack:
	for pv in _packs:
		var pk := pv as GyroCustomPack
		if pk != null and pk.pack_name == pack_name:
			return pk
	return null

static func _all_blocks() -> Array:
	var out: Array = []
	for pv in _packs:
		var pk := pv as GyroCustomPack
		if pk != null:
			for bv in pk.blocks:
				if bv != null:
					out.append(bv)
	for bv in _blocks:
		if bv != null:
			out.append(bv)
	return out

static func _block_by_id(id: String) -> GyroCustomBlock:
	for bv in _all_blocks():
		var b := bv as GyroCustomBlock
		if b != null and b.block_id == id:
			return b
	return null

static func _unique_id(desired: String) -> String:
	var base := desired if desired != "" else "block"
	var candidate := base
	var i := 2
	while _block_by_id(candidate) != null:
		candidate = base + "_" + str(i)
		i += 1
	return candidate

static func _signature(b: GyroCustomBlock) -> String:
	return JSON.stringify(GyroCustomRegistry.block_to_dict(b))

static func _resolve_block(b: GyroCustomBlock, renames: Dictionary) -> GyroCustomBlock:
	var existing := _block_by_id(b.block_id)
	if existing == null:
		return b
	if _signature(existing) == _signature(b):
		return existing
	var new_id := _unique_id(b.block_id)
	renames[b.block_id] = new_id
	b.block_id = new_id
	return b

static func _rename_refs(project: GyroProject, renames: Dictionary) -> void:
	for sv in project.scripts:
		var s := sv as GyroScript
		if s == null or s.blueprint == null:
			continue
		for rv in s.blueprint.rules:
			var r := rv as GyroEventRule
			if r != null:
				_rename_in_array(r.actions, renames)
	for bv in _all_blocks():
		var b := bv as GyroCustomBlock
		if b != null:
			_rename_in_array(b.body, renames)

static func _rename_in_array(arr: Array, renames: Dictionary) -> void:
	for ev in arr:
		var t := ""
		var data: Dictionary = {}
		if ev is GyroAction:
			t = (ev as GyroAction).type
			data = (ev as GyroAction).data
		elif ev is Dictionary:
			var ed: Dictionary = ev
			t = str(ed.get("type", ""))
			var inner = ed.get("data", {})
			if inner is Dictionary:
				data = inner
			if t.begins_with("custom:") and renames.has(t.substr(7)):
				ed["type"] = "custom:" + str(renames[t.substr(7)])
		else:
			continue
		if ev is GyroAction and t.begins_with("custom:") and renames.has(t.substr(7)):
			(ev as GyroAction).type = "custom:" + str(renames[t.substr(7)])
		var nested = data.get("blocks", [])
		if nested is Array:
			_rename_in_array(nested as Array, renames)
