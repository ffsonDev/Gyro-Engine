class_name GyroFunctions
extends RefCounted

const PATH := "user://gyro_functions.json"
const VERSION := 1
const MAGIC := "GYROFN1"
const MAX_DEPTH := 8
const MAX_PARAMS := 8
const MAX_EXPR := 1024
const MAX_RAW_SIZE := 1048576

const RESERVED := [
	"min", "max", "abs", "round", "floor", "ceil", "clamp", "rand", "randi",
	"len", "num", "text", "sqrt", "pow", "sin", "cos", "tan", "atan2", "sign",
	"lerp", "map", "pi", "chance", "upper", "lower", "contains", "substr", "text_round",
	"screen_w", "screen_h", "screen_x", "screen_y", "design_w", "design_h",
	"offset_x", "offset_y", "center_x", "center_y", "pointer_x", "pointer_y",
	"time", "now", "obj_x", "obj_y", "obj_w", "obj_h", "obj_rot",
	"dist", "angle_to", "exists", "vel_x", "vel_y",
	"true", "false", "and", "or", "not"
]

static var _items: Array = []
static var _loaded := false
static var _depth := 0
static var _active := {}
static var _last_written := ""

static func install() -> void:
	GyroExpression.custom_fn = func(n: String, a: Array) -> Variant:
		return GyroFunctions.resolve(n, a)

static func load_library() -> void:
	_load()

static func items() -> Array:
	_load()
	return _items

static func find(fname: String) -> GyroCustomFunction:
	_load()
	for v in _items:
		var f := v as GyroCustomFunction
		if f != null and f.func_name == fname:
			return f
	return null

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_items = from_array((parsed as Dictionary).get("functions", []))

static func save() -> void:
	_load()
	var payload := JSON.stringify({"version": VERSION, "functions": to_array(_items)}, "  ")
	if payload == _last_written:
		return
	var tmp := PATH + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(payload)
	file.flush()
	var write_err := file.get_error()
	file.close()
	if write_err != OK:
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

static func to_dict(f: GyroCustomFunction) -> Dictionary:
	return {
		"func_name": f.func_name,
		"author": f.author,
		"params": f.params.duplicate(),
		"expression": f.expression,
		"description": f.description,
	}

static func from_dict(d: Dictionary) -> GyroCustomFunction:
	var f := GyroCustomFunction.new()
	f.func_name = str(d.get("func_name", ""))
	f.author = str(d.get("author", ""))
	f.expression = str(d.get("expression", ""))
	f.description = str(d.get("description", ""))
	var raw = d.get("params", [])
	if raw is Array:
		for pv in (raw as Array):
			f.params.append(str(pv))
	return f

static func to_array(list: Array) -> Array:
	var out: Array = []
	for v in list:
		var f := v as GyroCustomFunction
		if f != null:
			out.append(to_dict(f))
	return out

static func from_array(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for v in (raw as Array):
			if v is Dictionary:
				var f := from_dict(v as Dictionary)
				if f.func_name != "":
					out.append(f)
	return out

static func install_from_array(raw: Variant) -> void:
	_loaded = true
	_items = from_array(raw)
	_depth = 0
	_active.clear()

static func adopt(raw: Variant) -> Array:
	_load()
	var report: Array = []
	for v in from_array(raw):
		var f := v as GyroCustomFunction
		if f == null:
			continue
		var existing := find(f.func_name)
		if existing != null:
			var same := existing.expression == f.expression and JSON.stringify(existing.params) == JSON.stringify(f.params)
			if same:
				continue
			var old := f.func_name
			f.func_name = unique_name(old)
			report.append("%s -> %s" % [old, f.func_name])
		_items.append(f)
	if not report.is_empty():
		save()
	return report

static func is_valid_identifier(s: String) -> bool:
	if s == "" or s.length() > 32:
		return false
	var c0 := s[0]
	if not ((c0 >= "a" and c0 <= "z") or (c0 >= "A" and c0 <= "Z") or c0 == "_"):
		return false
	for i in s.length():
		var c := s[i]
		if not ((c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return true

static func validate(fname: String, params: Array, expr: String, ignore: GyroCustomFunction = null) -> String:
	if not is_valid_identifier(fname):
		return "function_bad_name"
	if RESERVED.has(fname):
		return "function_reserved"
	var existing := find(fname)
	if existing != null and existing != ignore:
		return "function_exists"
	if params.size() > MAX_PARAMS:
		return "function_bad_params"
	var seen := {}
	for pv in params:
		var p := str(pv)
		if not is_valid_identifier(p) or seen.has(p) or RESERVED.has(p):
			return "function_bad_params"
		seen[p] = true
	var body := expr.strip_edges()
	if body == "" or body.length() > MAX_EXPR:
		return "function_bad_expr"
	if not GyroExpression.is_valid_syntax(body):
		return "function_bad_expr"
	return ""

static func unique_name(desired: String) -> String:
	var base := desired if is_valid_identifier(desired) else "fn"
	var candidate := base
	var i := 2
	while find(candidate) != null:
		candidate = base + "_" + str(i)
		i += 1
	return candidate

static func add(f: GyroCustomFunction) -> void:
	_load()
	_items.append(f)
	save()

static func remove(f: GyroCustomFunction) -> void:
	_load()
	_items.erase(f)
	save()

static func resolve(fname: String, args: Array) -> Variant:
	if _depth >= MAX_DEPTH or _active.has(fname):
		return null
	var f := find(fname)
	if f == null or args.size() != f.params.size():
		return null
	var ctx := GyroExpression.current_context()
	var bound := {}
	for i in f.params.size():
		bound[str(f.params[i])] = args[i]
	_active[fname] = true
	_depth += 1
	var out: Array = []
	var ok := GyroExpression.try_eval(
		f.expression,
		ctx.get("vars", {}),
		ctx.get("payload", {}),
		ctx.get("extra", Callable()),
		out,
		bound
	)
	_depth -= 1
	_active.erase(fname)
	if not ok or out.is_empty():
		return null
	return out[0]

static func export_function(f: GyroCustomFunction, dest_path: String) -> bool:
	if f == null:
		return false
	var bytes := JSON.stringify(to_dict(f)).to_utf8_buffer()
	var stored := bytes
	var method := 0
	if bytes.size() >= 2048:
		var comp := bytes.compress(FileAccess.COMPRESSION_ZSTD)
		if not comp.is_empty() and comp.size() < bytes.size():
			stored = comp
			method = FileAccess.COMPRESSION_ZSTD
	var file := FileAccess.open(dest_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(MAGIC)
	file.store_64(bytes.size())
	file.store_64(stored.size())
	file.store_8(method)
	file.store_buffer(stored)
	file.close()
	return true

static func import_function(src_path: String) -> Dictionary:
	var file := FileAccess.open(src_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "open failed"}
	if file.get_buffer(7).get_string_from_ascii() != MAGIC:
		file.close()
		return {"ok": false, "error": "bad magic"}
	var raw_size := file.get_64()
	var stored_size := file.get_64()
	var method := file.get_8()
	if raw_size <= 0 or raw_size > MAX_RAW_SIZE or stored_size <= 0 or file.get_position() + stored_size > file.get_length():
		file.close()
		return {"ok": false, "error": "corrupt"}
	if method != 0 and method != FileAccess.COMPRESSION_ZSTD:
		file.close()
		return {"ok": false, "error": "corrupt"}
	var data := file.get_buffer(stored_size)
	file.close()
	if method != 0:
		data = data.decompress(raw_size, method)
	if data.size() != raw_size:
		return {"ok": false, "error": "corrupt"}
	var parsed = JSON.parse_string(data.get_string_from_utf8())
	if not (parsed is Dictionary):
		return {"ok": false, "error": "bad json"}
	var f := from_dict(parsed as Dictionary)
	var err := validate(f.func_name, f.params, f.expression)
	if err == "function_exists":
		f.func_name = unique_name(f.func_name)
		err = ""
	if err != "":
		return {"ok": false, "error": err}
	add(f)
	return {"ok": true, "name": f.func_name}
