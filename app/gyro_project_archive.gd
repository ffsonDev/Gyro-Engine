class_name GyroProjectArchive
extends RefCounted

const MAGIC := "GYROPRJ1"

static func export_project(project_path: String, dest_path: String, strip_secrets: bool = true) -> bool:
	var tres_bytes: PackedByteArray
	if strip_secrets:
		var proj := ResourceLoader.load(project_path) as GyroProject
		if proj == null:
			return false
		proj = proj.duplicate(true) as GyroProject
		if proj.settings != null:
			proj.settings.keystore_password = ""
			proj.settings.keystore_path = ""
		var tmp := "user://_tmp_export.tres"
		var err := ResourceSaver.save(proj, tmp)
		if err != OK:
			return false
		tres_bytes = FileAccess.get_file_as_bytes(tmp)
		DirAccess.remove_absolute(tmp)
	else:
		tres_bytes = FileAccess.get_file_as_bytes(project_path)
	if tres_bytes.is_empty():
		return false
	var f := FileAccess.open(dest_path, FileAccess.WRITE)
	if f == null:
		return false
	var entries: Array = []
	var blobs: Array = []
	entries.append({"p": "project.tres", "s": tres_bytes.size()})
	blobs.append(tres_bytes)
	var files_dir := project_path.get_basename() + ".files"
	var dir := DirAccess.open(files_dir)
	if dir != null:
		_collect(dir, files_dir, "files", entries, blobs)
	f.store_string(MAGIC)
	f.store_32(entries.size())
	for e in entries:
		var pb := (e.p as String).to_utf8_buffer()
		f.store_32(pb.size())
		f.store_buffer(pb)
		f.store_64(e.s)
	for b in blobs:
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
	if f.get_buffer(8).get_string_from_ascii() != MAGIC:
		return ""
	var count := f.get_32()
	var metas: Array = []
	for i in count:
		var plen := f.get_32()
		var p := f.get_buffer(plen).get_string_from_utf8()
		var s := f.get_64()
		metas.append([p, s])
	var base := base_name
	var target := dest_dir + base + ".tres"
	var i := 1
	while FileAccess.file_exists(target):
		base = base_name + "_" + str(i)
		i += 1
		target = dest_dir + base + ".tres"
	for m in metas:
		var p: String = m[0]
		var s: int = m[1]
		var data := f.get_buffer(s)
		if p == "project.tres":
			var out := FileAccess.open(target, FileAccess.WRITE)
			if out == null:
				return ""
			out.store_buffer(data)
			out.close()
		elif p.begins_with("files/"):
			var dst := dest_dir + base + ".files/" + p.substr(6)
			DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
			var out := FileAccess.open(dst, FileAccess.WRITE)
			if out != null:
				out.store_buffer(data)
				out.close()
	f.close()
	return target

static func read_project_name(src_path: String) -> String:
	var f := FileAccess.open(src_path, FileAccess.READ)
	if f == null:
		return ""
	if f.get_length() < 12:
		f.close()
		return ""
	if f.get_buffer(8).get_string_from_ascii() != MAGIC:
		f.close()
		return ""
	
	var count := f.get_32()
	for i in count:
		if f.get_position() + 12 > f.get_length():
			break
		var plen := f.get_32()
		if f.get_position() + plen > f.get_length():
			break
		var p := f.get_buffer(plen).get_string_from_utf8()
		var s := f.get_64()
		
		if p == "project.tres":
			if f.get_position() + s > f.get_length():
				break
			var data := f.get_buffer(s)
			f.close()
			
			var tmp := "user://_tmp_import_name.tres"
			var out := FileAccess.open(tmp, FileAccess.WRITE)
			if out == null:
				return ""
			out.store_buffer(data)
			out.close()
			
			var proj := ResourceLoader.load(tmp) as GyroProject
			DirAccess.remove_absolute(tmp)
			
			if proj != null and proj.settings != null and proj.settings.app_name != "":
				return proj.settings.app_name
			return ""
		else:
			if f.get_position() + s > f.get_length():
				break
			f.seek(f.get_position() + s)
	
	f.close()
	return ""
