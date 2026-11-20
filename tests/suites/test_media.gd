extends "res://tests/framework/test_case.gd"

const Env := preload("res://tests/framework/test_env.gd")

func suite_name() -> String:
	return "media"

func test_texture_cache_returns_same_instance() -> void:
	var path := Env.path("tex/a.png")
	check(Env.write_png(path, 16, 16), "fixture written")
	var first := GyroMedia.load_texture(path)
	var second := GyroMedia.load_texture(path)
	not_null(first, "texture loaded")
	check(first == second, "second load hits cache (P0-3)")

func test_texture_cache_invalidation() -> void:
	var path := Env.path("tex/b.png")
	Env.write_png(path, 16, 16)
	var first := GyroMedia.load_texture(path)
	if not GyroMedia.has_method("invalidate_texture"):
		skip("P0-3: texture cache not applied yet")
		return
	GyroMedia.invalidate_texture(path)
	var second := GyroMedia.load_texture(path)
	check(first != second, "invalidate forces reload")

func test_missing_texture_returns_null() -> void:
	is_null(GyroMedia.load_texture(Env.path("tex/absent.png")), "missing file")
	is_null(GyroMedia.load_texture(""), "empty path")

func test_wav_parser() -> void:
	var path := Env.path("audio/tone.wav")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(Env.wav_bytes(64, 22050, 1, 16))
	f.close()
	var stream := GyroMedia.load_audio(path) as AudioStreamWAV
	not_null(stream, "wav parsed")
	eq(stream.mix_rate, 22050, "sample rate")
	eq(stream.stereo, false, "mono")
	eq(stream.format, AudioStreamWAV.FORMAT_16_BITS, "bit depth")
	eq(stream.data.size(), 128, "pcm bytes")

func test_wav_stereo_8bit() -> void:
	var path := Env.path("audio/stereo.wav")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(Env.wav_bytes(32, 44100, 2, 8))
	f.close()
	var stream := GyroMedia.load_audio(path) as AudioStreamWAV
	not_null(stream, "stereo wav parsed")
	eq(stream.stereo, true, "stereo flag")
	eq(stream.format, AudioStreamWAV.FORMAT_8_BITS, "8 bit format")

func test_wav_rejects_garbage() -> void:
	var path := Env.path("audio/broken.wav")
	Env.write_text(path, "not a wav file at all")
	is_null(GyroMedia.load_audio(path), "garbage rejected")
	is_null(GyroMedia.load_audio(Env.path("audio/absent.wav")), "missing audio")

func test_sprite_downscale_and_conversion() -> void:
	var path := Env.path("tex/huge.png")
	Env.write_png(path, 3000, 100)
	var result := GyroTextureCodec.process_sprite_file(path)
	check(bool(result.get("ok", false)), "processing ok")
	var new_path := str(result.get("new_path", ""))
	check(new_path != "", "new path returned")
	check(not FileAccess.file_exists(path), "original removed")
	var img := Image.new()
	eq(img.load(new_path), OK, "result loads")
	check(maxi(img.get_width(), img.get_height()) <= GyroTextureCodec.MAX_DIM, "downscaled to limit")

func test_small_png_kept_when_not_smaller() -> void:
	var path := Env.path("tex/small.png")
	Env.write_png(path, 4, 4)
	var result := GyroTextureCodec.process_sprite_file(path)
	check(bool(result.get("ok", false)), "ok")
	eq(str(result.get("new_path", "")), "", "no pointless conversion")
	check(FileAccess.file_exists(path), "original kept")

func test_gtx_round_trip() -> void:
	var src := Env.path("tex/comp.png")
	Env.write_png(src, 32, 32)
	var dst := Env.path("tex/comp.gtx")
	if not GyroTextureCodec.build_gtx_file(src, dst):
		skip("ETC2 compression unavailable on this platform")
		return
	var tex := GyroTextureCodec.load_gtx_texture(dst)
	not_null(tex, "gtx loaded")
	eq(tex.get_width(), 32, "width preserved")
	eq(tex.get_height(), 32, "height preserved")
