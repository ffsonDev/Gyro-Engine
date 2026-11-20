class_name GyroTextureCodec
extends RefCounted

const MAGIC := "GYROTEX1"
const MAX_DIM := 2048
const WEBP_QUALITY := 0.85

static func process_sprite_file(abs_path: String) -> Dictionary:
	var ext := abs_path.get_extension().to_lower()
	if ext == "svg":
		return {"ok": true, "new_path": ""}
	var img := Image.new()
	if img.load(abs_path) != OK:
		return {"ok": false, "new_path": ""}
	var changed := false
	var max_dim := maxi(img.get_width(), img.get_height())
	if max_dim > MAX_DIM:
		var k := float(MAX_DIM) / float(max_dim)
		img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		changed = true
	if not (changed or ext in ["png", "jpg", "jpeg"]):
		return {"ok": true, "new_path": ""}
	var orig_len := -1
	var of := FileAccess.open(abs_path, FileAccess.READ)
	if of != null:
		orig_len = of.get_length()
		of.close()
	var dst := abs_path.get_basename() + ".webp"
	var use_lossy := changed or ext != "png"
	var err := img.save_webp(dst, true, WEBP_QUALITY) if use_lossy else img.save_webp(dst, false)
	if err != OK:
		return {"ok": false, "new_path": ""}
	var new_len := -1
	var nf := FileAccess.open(dst, FileAccess.READ)
	if nf != null:
		new_len = nf.get_length()
		nf.close()
	if not changed and orig_len >= 0 and new_len >= orig_len:
		DirAccess.remove_absolute(dst)
		return {"ok": true, "new_path": ""}
	DirAccess.remove_absolute(abs_path)
	return {"ok": true, "new_path": dst}

static func build_gtx_file(src_abs: String, dst_abs: String) -> bool:
	var img := Image.new()
	if img.load(src_abs) != OK:
		return false
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := int(ceil(img.get_width() / 4.0) * 4)
	var h := int(ceil(img.get_height() / 4.0) * 4)
	if w != img.get_width() or h != img.get_height():
		var padded := Image.create(w, h, false, Image.FORMAT_RGBA8)
		padded.fill(Color(0, 0, 0, 0))
		padded.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i.ZERO)
		img = padded
	var mode := _etc2_compress_mode()
	if mode < 0 or img.compress(mode) != OK:
		return false
	var f := FileAccess.open(dst_abs, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(MAGIC)
	f.store_32(img.get_width())
	f.store_32(img.get_height())
	f.store_32(int(img.get_format()))
	f.store_buffer(img.get_data())
	f.close()
	return true

static func _etc2_compress_mode() -> int:
	if ClassDB.class_has_integer_constant("Image", "COMPRESS_ETC2_ASTC"):
		return ClassDB.class_get_integer_constant("Image", "COMPRESS_ETC2_ASTC")
	if ClassDB.class_has_integer_constant("Image", "COMPRESS_ETC2"):
		return ClassDB.class_get_integer_constant("Image", "COMPRESS_ETC2")
	return -1

static func load_gtx_texture(path: String) -> Texture2D:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	if f.get_buffer(8).get_string_from_ascii() != MAGIC:
		return null
	var w := f.get_32()
	var h := f.get_32()
	var fmt := f.get_32()
	var data := f.get_buffer(f.get_length() - f.get_position())
	f.close()
	if data.is_empty() or w == 0 or h == 0:
		return null
	var img := Image.new()
	img.set_data(int(w), int(h), false, fmt as Image.Format, data)
	if img.get_width() == 0:
		return null
	return ImageTexture.create_from_image(img)
