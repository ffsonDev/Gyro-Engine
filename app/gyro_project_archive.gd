class_name GyroProjectArchive
extends RefCounted

const MAGIC := "GYROPRJ1"
const MAGIC_V2 := "GYROPRJ2"
const METHOD_RAW := 0
const MIN_COMPRESS_SIZE := 2048
const MAX_ENTRY_RAW := 268435456
const MAX_TOTAL_RAW := 536870912

static func export_project(project_path: String, dest_path: String, strip_secrets: bool = true) -> bool:
	var json_bytes: PackedByteArray
	if strip_secrets:
		var proj := GyroProjectJSON.load_from_file(project_path)
		if proj == null:
			return false
		if proj.settings != null:
			proj.settings.keystore_password = ""
			proj.settings.keystore_path = ""
			proj.settings.keystore_alias = ""
		GyroGlobalBlocks.attach(proj)
		var tmp := "user://_tmp_export.json"
		if not GyroProjectJSON.save_to_file(proj, tmp, true):
			return false
		json_bytes = FileAccess.get_file_as_bytes(tmp)
		DirAccess.remove_absolute(tmp)
	else:
		json_bytes = FileAccess.get_file_as_bytes(project_path)
	if json_bytes.is_empty():
		return false
	var f := FileAccess.open(dest_path, FileAccess.WRITE)
	if f == null:
		return false
	var entries: Array = []
	var blobs: Array = []
	entries.append({"p": "project.json", "s": json_bytes.size()})
	blobs.append(json_bytes)
	var files_dir := project_path.get_basename() + ".files"
	var dir := DirAccess.open(files_dir)
	if dir != null:
		_collect(dir, files_dir, "files", entries, blobs)
	f.store_string(MAGIC_V2)
	f.store_32(entries.size())
	var stored_blobs: Array = []
	for i in entries.size():
		var e: Dictionary = entries[i]
		var raw: PackedByteArray = blobs[i]
		var method := METHOD_RAW
		var stored: PackedByteArray = raw
		if raw.size() >= MIN_COMPRESS_SIZE:
			var comp := raw.compress(FileAccess.COMPRESSION_ZSTD)
			if not comp.is_empty() and comp.size() < raw.size():
				stored = comp
				method = FileAccess.COMPRESSION_ZSTD
		var pb := (e.p as String).to_utf8_buffer()
		f.store_32(pb.size())
		f.store_buffer(pb)
		f.store_64(raw.size())
		f.store_64(stored.size())
		f.store_8(method)
		stored_blobs.append(stored)
	for b in stored_blobs:
		f.store_buffer(b)
	f.close()
	return true

static func _collect(dir: DirAccess, root_abs: String, rel: String, entries: Array, blobs: Array) -> void:
	for fn in dir.get_files():
		var bytes := FileAccess.get_file_as_bytes(root_abs + "/" + str(fn))
		entries.append({"p": rel + "/" + str(fn), "s": bytes.size()})
		blobs.append(bytes)
	for dn in dir.get_directories():
		var sub := DirAccess.open(root_abs + "/" + str(dn))
		if sub != null:
			_collect(sub, root_abs + "/" + str(dn), rel + "/" + str(dn), entries, blobs)

static func import_project(src_path: String, dest_dir: String, base_name: String) -> String:
	var f := FileAccess.open(src_path, FileAccess.READ)
	if f == null:
		return ""
	var magic := f.get_buffer(8).get_string_from_ascii()
	if magic != MAGIC and magic != MAGIC_V2:
		return ""
	var is_v2 := magic == MAGIC_V2
	var count := f.get_32()
	if count <= 0 or count > 65536:
		f.close()
		return ""
	var metas: Array = []
	for i in count:
		var plen := f.get_32()
		if plen <= 0 or plen > 4096 or f.get_position() + plen > f.get_length():
			f.close()
			return ""
		var p := f.get_buffer(plen).get_string_from_utf8()
		var s := f.get_64()
		if is_v2:
			var stored := f.get_64()
			var method := f.get_8()
			metas.append([p, s, stored, method])
		else:
			metas.append([p, s, s, METHOD_RAW])
	var base := base_name
	var target := dest_dir + base + ".json"
	var i := 1
	while FileAccess.file_exists(target):
		base = base_name + "_" + str(i)
		i += 1
		target = dest_dir + base + ".json"
	var wrote_project := false
	var total_raw := 0
	for m in metas:
		var p: String = m[0]
		var s: int = m[1]
		var stored_size: int = m[2]
		var method: int = m[3]
		if s < 0 or s > MAX_ENTRY_RAW or total_raw + s > MAX_TOTAL_RAW:
			f.close()
			_abort_import(target, dest_dir + base + ".files")
			return ""
		if stored_size < 0 or f.get_position() + stored_size > f.get_length():
			f.close()
			_abort_import(target, dest_dir + base + ".files")
			return ""
		if method != METHOD_RAW and method != FileAccess.COMPRESSION_ZSTD:
			f.close()
			_abort_import(target, dest_dir + base + ".files")
			return ""
		var data := f.get_buffer(stored_size)
		if method != METHOD_RAW:
			data = data.decompress(s, method)
		total_raw += s
		if data.size() != s:
			f.close()
			_abort_import(target, dest_dir + base + ".files")
			return ""
		if p == "project.json":
			var out := FileAccess.open(target, FileAccess.WRITE)
			if out == null:
				f.close()
				_abort_import(target, dest_dir + base + ".files")
				return ""
			out.store_buffer(data)
			out.close()
			wrote_project = true
		elif p.begins_with("files/"):
			var rel := p.substr(6).replace("\\", "/")
			if rel == "" or rel.contains("..") or rel.begins_with("/") or rel.contains(":"):
				continue
			var dst := dest_dir + base + ".files/" + rel
			DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
			var out := FileAccess.open(dst, FileAccess.WRITE)
			if out != null:
				out.store_buffer(data)
				out.close()
	f.close()
	if not wrote_project:
		_abort_import(target, dest_dir + base + ".files")
		return ""
	return target

static func _abort_import(target: String, files_dir: String) -> void:
	DirAccess.remove_absolute(target)
	_remove_dir(files_dir)

static func _remove_dir(abs_path: String) -> void:
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	for fn in dir.get_files():
		DirAccess.remove_absolute(abs_path + "/" + str(fn))
	for dn in dir.get_directories():
		_remove_dir(abs_path + "/" + str(dn))
	DirAccess.remove_absolute(abs_path)

static func read_project_name(src_path: String) -> String:
	var f := FileAccess.open(src_path, FileAccess.READ)
	if f == null:
		return ""
	if f.get_length() < 12:
		f.close()
		return ""
	var magic := f.get_buffer(8).get_string_from_ascii()
	if magic != MAGIC and magic != MAGIC_V2:
		f.close()
		return ""
	var is_v2 := magic == MAGIC_V2
	var count := f.get_32()
	for i in count:
		if f.get_position() + 12 > f.get_length():
			break
		var plen := f.get_32()
		if f.get_position() + plen > f.get_length():
			break
		var p := f.get_buffer(plen).get_string_from_utf8()
		var s := f.get_64()
		var stored_size := s
		var method := METHOD_RAW
		if is_v2:
			if f.get_position() + 9 > f.get_length():
				break
			stored_size = f.get_64()
			method = f.get_8()
		if p == "project.json":
			if s < 0 or s > MAX_ENTRY_RAW or stored_size < 0:
				break
			if method != METHOD_RAW and method != FileAccess.COMPRESSION_ZSTD:
				break
			if f.get_position() + stored_size > f.get_length():
				break
			var data := f.get_buffer(stored_size)
			if method != METHOD_RAW:
				data = data.decompress(s, method)
			f.close()
			var json_string := data.get_string_from_utf8()
			var json := JSON.new()
			var err := json.parse(json_string)
			if err == OK and json.data is Dictionary:
				var settings_dict: Dictionary = json.data.get("settings", {})
				var app_name: String = settings_dict.get("app_name", "")
				if app_name != "":
					return app_name
			return ""
		else:
			if f.get_position() + stored_size > f.get_length():
				break
			f.seek(f.get_position() + stored_size)
	f.close()
	return ""
