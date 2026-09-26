class_name GyroMedia
extends RefCounted


static func load_texture(path: String) -> Texture2D:
	var p := path.replace("\\", "/")
	if p == "":
		return null

	if ResourceLoader.exists(p):
		var loaded := load(p)
		if loaded is Texture2D:
			return loaded

	if FileAccess.file_exists(p):
		var img := Image.new()
		var err := img.load(p)
		if err == OK:
			return ImageTexture.create_from_image(img)

	return null


static func load_audio(path: String) -> AudioStream:
	var p := path.replace("\\", "/")
	if p == "":
		return null

	if ResourceLoader.exists(p):
		var loaded := load(p)
		if loaded is AudioStream:
			return loaded

	if not FileAccess.file_exists(p):
		return null

	var ext := p.get_extension().to_lower()
	var bytes := FileAccess.get_file_as_bytes(p)
	if bytes.is_empty():
		return null
	match ext:
		"mp3":
			var stream := AudioStreamMP3.new()
			stream.data = bytes
			return stream
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav":
			return _parse_wav(bytes)
	return null

static func _parse_wav(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var i := 12
	var format := 0
	var channels := 1
	var rate := 44100
	var bits := 16
	var data := PackedByteArray()
	while i + 8 <= bytes.size():
		var chunk := bytes.slice(i, i + 4).get_string_from_ascii()
		var size := bytes.decode_u32(i + 4)
		var body := i + 8
		if chunk == "fmt ":
			format = bytes.decode_u16(body)
			channels = bytes.decode_u16(body + 2)
			rate = int(bytes.decode_u32(body + 4))
			bits = bytes.decode_u16(body + 14)
		elif chunk == "data":
			data = bytes.slice(body, body + size)
		i = body + size
		if i % 2 == 1:
			i += 1
	if data.is_empty() or format != 1:
		return null
	var stream := AudioStreamWAV.new()
	stream.mix_rate = rate
	stream.stereo = channels > 1
	match bits:
		8:
			stream.format = AudioStreamWAV.FORMAT_8_BITS
		16:
			stream.format = AudioStreamWAV.FORMAT_16_BITS
		_:
			return null
	stream.data = data
	return stream
