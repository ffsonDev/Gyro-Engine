class_name GyroCustomRegistry
extends RefCounted

const PACK_MAGIC := "GYROPCK1"
const MAX_RAW_SIZE := 33554432
const ALLOWED_PICKS := ["", "color", "obj", "var", "sprite", "sound", "event"]

static func find_block(project: GyroProject, block_id: String) -> GyroCustomBlock:
	if project == null:
		return null
	for pkv in project.custom_packs:
		var pk := pkv as GyroCustomPack
		if pk == null:
			continue
		for bv in pk.blocks:
			var b := bv as GyroCustomBlock
			if b != null and b.block_id == block_id:
				return b
	for bv in project.custom_blocks:
		var b := bv as GyroCustomBlock
		if b != null and b.block_id == block_id:
			return b
	return null

static func find_pack_of(project: GyroProject, block_id: String) -> GyroCustomPack:
	if project == null:
		return null
	for pkv in project.custom_packs:
		var pk := pkv as GyroCustomPack
		if pk == null:
			continue
		for bv in pk.blocks:
			var b := bv as GyroCustomBlock
			if b != null and b.block_id == block_id:
				return pk
	return null

static func is_packless(project: GyroProject, b: GyroCustomBlock) -> bool:
	return project != null and project.custom_blocks.has(b)

static func find_pack_by_name(project: GyroProject, pack_name: String) -> GyroCustomPack:
	if project == null:
		return null
	for pkv in project.custom_packs:
		var pk := pkv as GyroCustomPack
		if pk != null and pk.pack_name == pack_name:
			return pk
	return null

static func make_unique_id(project: GyroProject, desired: String) -> String:
	var base := GyroUI.sanitize_name(desired).to_lower().replace(" ", "_")
	if base == "":
		base = "block"
	var candidate := base
	var i := 2
	while find_block(project, candidate) != null:
		candidate = base + "_" + str(i)
		i += 1
	return candidate

static func make_unique_pack_name(project: GyroProject, desired: String) -> String:
	var base := GyroUI.sanitize_name(desired)
	if base == "":
		base = "Pack"
	var candidate := base
	var i := 2
	while find_pack_by_name(project, candidate) != null:
		candidate = base + "_" + str(i)
		i += 1
	return candidate

static func block_to_dict(b: GyroCustomBlock) -> Dictionary:
	var acts: Array = []
	for av in b.body:
		var a := av as GyroAction
		if a == null:
			continue
		acts.append({"type": a.type, "data": a.data.duplicate(true), "disabled": a.disabled})
	return {
		"block_id": b.block_id,
		"block_name": b.block_name,
		"author": b.author,
		"color": b.color.to_html(),
		"fields": b.fields.duplicate(true),
		"body": acts,
	}

static func dict_to_block(d: Dictionary) -> GyroCustomBlock:
	var b := GyroCustomBlock.new()
	b.block_id = str(d.get("block_id", ""))
	b.block_name = str(d.get("block_name", ""))
	b.author = str(d.get("author", ""))
	b.color = Color("#" + str(d.get("color", "8c6699")))
	for fv in d.get("fields", []):
		if fv is Dictionary:
			b.fields.append((fv as Dictionary).duplicate(true))
	for av in d.get("body", []):
		if not (av is Dictionary):
			continue
		var ad: Dictionary = av
		var a := GyroAction.new()
		a.type = str(ad.get("type", ""))
		a.data = (ad.get("data", {}) as Dictionary).duplicate(true)
		a.disabled = bool(ad.get("disabled", false))
		GyroBlocks.normalize_action_data(a.type, a.data)
		b.body.append(a)
	return b

static func pack_to_dict(pk: GyroCustomPack) -> Dictionary:
	var blocks: Array = []
	for bv in pk.blocks:
		var b := bv as GyroCustomBlock
		if b != null:
			blocks.append(block_to_dict(b))
	return {
		"pack_name": pk.pack_name,
		"author": pk.author,
		"version": pk.version,
		"blocks": blocks,
	}

static func dict_to_pack(d: Dictionary) -> GyroCustomPack:
	var pk := GyroCustomPack.new()
	pk.pack_name = str(d.get("pack_name", ""))
	pk.author = str(d.get("author", ""))
	pk.version = str(d.get("version", "1.0"))
	for bv in d.get("blocks", []):
		if bv is Dictionary:
			pk.blocks.append(dict_to_block(bv as Dictionary))
	return pk

static func packs_to_dict(packs: Array) -> Array:
	var out: Array = []
	for pkv in packs:
		var pk := pkv as GyroCustomPack
		if pk != null:
			out.append(pack_to_dict(pk))
	return out

static func dict_to_packs(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for dv in (raw as Array):
			if dv is Dictionary:
				out.append(dict_to_pack(dv as Dictionary))
	return out

static func blocks_to_dict(blocks: Array) -> Array:
	var out: Array = []
	for bv in blocks:
		var b := bv as GyroCustomBlock
		if b != null:
			out.append(block_to_dict(b))
	return out

static func dict_to_blocks(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for dv in (raw as Array):
			if dv is Dictionary:
				out.append(dict_to_block(dv as Dictionary))
	return out

static func export_pack(pk: GyroCustomPack, dest_path: String) -> bool:
	if pk == null:
		return false
	var bytes := JSON.stringify(pack_to_dict(pk)).to_utf8_buffer()
	var stored := bytes
	var method := 0
	if bytes.size() >= 2048:
		var comp := bytes.compress(FileAccess.COMPRESSION_ZSTD)
		if not comp.is_empty() and comp.size() < bytes.size():
			stored = comp
			method = FileAccess.COMPRESSION_ZSTD
	var f := FileAccess.open(dest_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(PACK_MAGIC)
	f.store_64(bytes.size())
	f.store_64(stored.size())
	f.store_8(method)
	f.store_buffer(stored)
	f.close()
	return true

static func export_single_block(b: GyroCustomBlock, dest_path: String) -> bool:
	if b == null:
		return false
	var pk := GyroCustomPack.new()
	pk.pack_name = b.block_name
	pk.author = b.author
	pk.blocks.append(b)
	return export_pack(pk, dest_path)

static func import_pack(project: GyroProject, src_path: String) -> Dictionary:
	var f := FileAccess.open(src_path, FileAccess.READ)
	if f == null:
		return {"ok": false, "report": ["open failed"]}
	if f.get_buffer(8).get_string_from_ascii() != PACK_MAGIC:
		f.close()
		return {"ok": false, "report": ["bad magic"]}
	var raw_size := f.get_64()
	var stored_size := f.get_64()
	var method := f.get_8()
	if raw_size <= 0 or raw_size > MAX_RAW_SIZE:
		f.close()
		return {"ok": false, "report": ["corrupt"]}
	if stored_size <= 0 or stored_size > f.get_length() - f.get_position():
		f.close()
		return {"ok": false, "report": ["corrupt"]}
	if method != 0 and method != FileAccess.COMPRESSION_ZSTD:
		f.close()
		return {"ok": false, "report": ["corrupt"]}
	var data := f.get_buffer(stored_size)
	f.close()
	if method != 0:
		data = data.decompress(raw_size, method)
	if data.size() != raw_size:
		return {"ok": false, "report": ["corrupt"]}
	var parsed = JSON.parse_string(data.get_string_from_utf8())
	if not (parsed is Dictionary):
		return {"ok": false, "report": ["bad json"]}
	var report: Array = []
	var incoming: Dictionary = parsed
	var pack_name := GyroUI.sanitize_name(str(incoming.get("pack_name", "")))
	if pack_name == "":
		return {"ok": false, "report": ["bad pack name"]}
	var new_pack := GyroCustomPack.new()
	new_pack.pack_name = pack_name
	new_pack.author = str(incoming.get("author", ""))
	new_pack.version = str(incoming.get("version", "1.0"))
	var incoming_ids: Array = []
	for bv in incoming.get("blocks", []):
		if not (bv is Dictionary):
			continue
		var bd: Dictionary = bv
		var block := dict_to_block(bd)
		var id := GyroUI.sanitize_name(block.block_id).to_lower()
		if id == "":
			report.append("block without id skipped")
			continue
		block.block_id = id
		var existing := find_block(project, id)
		if existing != null:
			var ep := find_pack_of(project, id)
			var same_pack := ep != null and ep.pack_name == pack_name
			if not same_pack:
				var new_id := make_unique_id(project, id)
				report.append("%s -> %s" % [id, new_id])
				block.block_id = new_id
		if incoming_ids.has(block.block_id):
			block.block_id = make_unique_id(project, block.block_id)
		incoming_ids.append(block.block_id)
		block.block_name = GyroUI.sanitize_name(block.block_name)
		if block.block_name == "":
			block.block_name = block.block_id
		var clean_fields: Array = []
		var seen_keys: Array = []
		for fv in block.fields:
			var fd: Dictionary = fv
			var key := GyroUI.sanitize_name(str(fd.get("key", ""))).to_lower().replace(" ", "_")
			if key == "" or seen_keys.has(key):
				report.append("field skipped in " + block.block_id)
				continue
			var pick := str(fd.get("pick", ""))
			if not ALLOWED_PICKS.has(pick):
				pick = ""
			seen_keys.append(key)
			clean_fields.append({"key": key, "label": str(fd.get("label", key)), "pick": pick, "default": str(fd.get("default", ""))})
		block.fields = clean_fields
		var clean_body: Array = []
		for av in block.body:
			var a := av as GyroAction
			if a == null:
				continue
			if not _type_allowed(a.type, project, incoming_ids):
				report.append("unknown action dropped in " + block.block_id + ": " + a.type)
				continue
			clean_body.append(a)
		block.body = clean_body
		new_pack.blocks.append(block)
	var old := find_pack_by_name(project, pack_name)
	if old != null:
		project.custom_packs.erase(old)
	project.custom_packs.append(new_pack)
	return {"ok": true, "report": report, "pack_name": pack_name}

static func _type_allowed(t: String, project: GyroProject, incoming_ids: Array) -> bool:
	if t == "":
		return false
	if GyroBlocks.ACTION_SCHEMAS.has(t):
		return true
	if t.begins_with("custom:"):
		var cid := t.substr(7)
		if incoming_ids.has(cid):
			return true
		return find_block(project, cid) != null
	return false

static func count_usages(project: GyroProject, id: String) -> int:
	var count := 0
	if project == null:
		return 0
	for sv in project.scripts:
		var s := sv as GyroScript
		if s == null or s.blueprint == null:
			continue
		for rv in s.blueprint.rules:
			var r := rv as GyroEventRule
			if r == null:
				continue
			if _list_uses(r.actions, id):
				count += 1
	return count

static func _list_uses(arr: Array, id: String) -> bool:
	for ev in arr:
		var t := ""
		var data: Dictionary = {}
		if ev is GyroAction:
			t = (ev as GyroAction).type
			data = (ev as GyroAction).data
		elif ev is Dictionary:
			t = str((ev as Dictionary).get("type", ""))
			data = ev as Dictionary
		else:
			continue
		if t == "custom:" + id:
			return true
		if data.has("blocks") and data.get("blocks") is Array and _list_uses(data.get("blocks"), id):
			return true
	return false

static func remove_block_everywhere(project: GyroProject, id: String) -> void:
	if project == null:
		return
	var block := find_block(project, id)
	if block != null:
		var pk := find_pack_of(project, id)
		if pk != null:
			pk.blocks.erase(block)
		else:
			project.custom_blocks.erase(block)
	for sv in project.scripts:
		var s := sv as GyroScript
		if s == null or s.blueprint == null:
			continue
		for rv in s.blueprint.rules:
			var r := rv as GyroEventRule
			if r != null:
				_purge_actions_in_place(r.actions, id)
	for pkv in project.custom_packs:
		var pk := pkv as GyroCustomPack
		if pk == null:
			continue
		for bv in pk.blocks:
			var b := bv as GyroCustomBlock
			if b != null:
				_purge_actions_in_place(b.body, id)
	for bv in project.custom_blocks:
		var b := bv as GyroCustomBlock
		if b != null:
			_purge_actions_in_place(b.body, id)

static func _purge_actions_in_place(arr: Array, id: String) -> void:
	var to_erase: Array = []
	for ev in arr:
		var t := ""
		var data: Dictionary = {}
		if ev is GyroAction:
			t = (ev as GyroAction).type
			data = (ev as GyroAction).data
		elif ev is Dictionary:
			t = str((ev as Dictionary).get("type", ""))
			data = ev as Dictionary
		else:
			continue
		if t == "custom:" + id:
			to_erase.append(ev)
			continue
		if data.has("blocks") and data.get("blocks") is Array:
			_purge_actions_in_place(data.get("blocks"), id)
	for ev in to_erase:
		arr.erase(ev)

static func duplicate_block(project: GyroProject, b: GyroCustomBlock) -> GyroCustomBlock:
	var nb := GyroCustomBlock.new()
	nb.block_id = make_unique_id(project, b.block_id)
	nb.block_name = b.block_name + "_copy"
	nb.author = b.author
	nb.color = b.color
	nb.fields = b.fields.duplicate(true)
	nb.body = b.body.duplicate(true)
	var pk := find_pack_of(project, b.block_id)
	if pk != null:
		pk.blocks.append(nb)
	else:
		project.custom_blocks.append(nb)
	return nb	
