extends RefCounted

const SANDBOX := "user://gyro_tests/"
const GUARDED := [
	"user://gyro_global_blocks.json",
	"user://gyro_functions.json",
	"user://gyro_settings.tres",
	"user://gyro_favorites.json",
	"user://gyro_secret.salt",
]

static var _snapshot := {}
static var _hosts: Array = []

static func begin() -> void:
	_snapshot.clear()
	for path in GUARDED:
		_snapshot[path] = {
			"exists": FileAccess.file_exists(path),
			"bytes": FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray(),
		}
	reset_sandbox()
	reset_statics()

static func finish() -> void:
	free_hosts()
	reset_sandbox()
	for path in GUARDED:
		var entry: Dictionary = _snapshot.get(path, {})
		if not bool(entry.get("exists", false)):
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
			continue
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(entry.get("bytes", PackedByteArray()))
			f.close()
	reset_statics()
	_snapshot.clear()

static func reset_statics() -> void:
	GyroFunctions._loaded = false
	GyroFunctions._items = []
	GyroFunctions._last_written = ""
	GyroFunctions._depth = 0
	GyroFunctions._active.clear()
	GyroGlobalBlocks._loaded = false
	GyroGlobalBlocks._packs = []
	GyroGlobalBlocks._blocks = []
	GyroGlobalBlocks._last_written = ""
	GyroExpression._ast_cache.clear()
	GyroExpression._fail_cache.clear()
	GyroExpression.custom_fn = Callable()
	GyroAppSettings._cache = null

static func path(name: String) -> String:
	return SANDBOX + name

static func reset_sandbox() -> void:
	remove_dir(SANDBOX)
	DirAccess.make_dir_recursive_absolute(SANDBOX)

static func remove_dir(abs_path: String) -> void:
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(abs_path.path_join(str(f)))
	for d in dir.get_directories():
		remove_dir(abs_path.path_join(str(d)))
	DirAccess.remove_absolute(abs_path)

static func write_text(abs_path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true

static func write_png(abs_path: String, width: int, height: int, color := Color(0.2, 0.6, 0.9, 1.0)) -> bool:
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img.save_png(abs_path) == OK

static func make_host(parent: Node, blueprint: GyroEventBlueprint, project: GyroProject = null, project_path := "", sink: Array = []) -> GyroEventHost:
	var host := GyroEventHost.new()
	host.blueprint = blueprint
	host.project = project
	host.project_path = project_path
	host.runtime.print_handler = func(message): sink.append(str(message))
	parent.add_child(host)
	_hosts.append(host)
	return host

static func free_hosts() -> void:
	for h in _hosts:
		if is_instance_valid(h):
			h.queue_free()
	_hosts.clear()

static func action(type: String, data: Dictionary = {}) -> GyroAction:
	var a := GyroAction.new()
	a.type = type
	a.data = data
	return a

static func condition(type: String, data: Dictionary = {}) -> GyroCondition:
	var c := GyroCondition.new()
	c.type = type
	c.data = data
	return c

static func rule(event_type: String, actions: Array = [], event_name := "") -> GyroEventRule:
	var r := GyroEventRule.new()
	r.event_type = event_type
	r.event_name = event_name
	for a in actions:
		r.actions.append(a)
	return r

static func blueprint(rules: Array, variables: Dictionary = {}) -> GyroEventBlueprint:
	var bp := GyroEventBlueprint.new()
	bp.variables = variables.duplicate(true)
	for r in rules:
		bp.rules.append(r)
	return bp

static func project(app_name := "Test") -> GyroProject:
	var p := GyroProject.new()
	p.settings = GyroProjectSettings.new()
	p.settings.app_name = app_name
	p.settings.package_name = "com.test.app"
	return p

static func wav_bytes(sample_count := 32, rate := 22050, channels := 1, bits := 16) -> PackedByteArray:
	var block := channels * (bits / 8)
	var data_size := sample_count * block
	var bytes := PackedByteArray()
	bytes.resize(44 + data_size)
	_ascii(bytes, 0, "RIFF")
	bytes.encode_u32(4, 36 + data_size)
	_ascii(bytes, 8, "WAVE")
	_ascii(bytes, 12, "fmt ")
	bytes.encode_u32(16, 16)
	bytes.encode_u16(20, 1)
	bytes.encode_u16(22, channels)
	bytes.encode_u32(24, rate)
	bytes.encode_u32(28, rate * block)
	bytes.encode_u16(32, block)
	bytes.encode_u16(34, bits)
	_ascii(bytes, 36, "data")
	bytes.encode_u32(40, data_size)
	return bytes

static func write_archive(abs_path: String, entries: Array, magic := "GYROPRJ2", count_override := -1) -> void:
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(magic)
	f.store_32(count_override if count_override >= 0 else entries.size())
	var blobs: Array = []
	for e in entries:
		var raw: PackedByteArray = e.get("data", PackedByteArray())
		var stored := raw
		var method := 0
		if bool(e.get("compress", false)):
			stored = raw.compress(FileAccess.COMPRESSION_ZSTD)
			method = FileAccess.COMPRESSION_ZSTD
		method = int(e.get("method", method))
		var pb := str(e.get("path", "")).to_utf8_buffer()
		f.store_32(pb.size())
		f.store_buffer(pb)
		f.store_64(int(e.get("raw_size", raw.size())))
		f.store_64(int(e.get("stored_size", stored.size())))
		f.store_8(method)
		blobs.append(stored)
	for b in blobs:
		f.store_buffer(b)
	f.close()

static func _ascii(bytes: PackedByteArray, offset: int, text: String) -> void:
	var raw := text.to_ascii_buffer()
	for i in raw.size():
		bytes[offset + i] = raw[i]
