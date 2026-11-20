class_name GyroSecrets
extends RefCounted

const PREFIX := "gyro3:"
const SALT_PATH := "user://gyro_secret.salt"
const PEPPER := "GyroEngine/secrets/v3"
const ITERATIONS := 4096

static var _key := PackedByteArray()

static func is_encrypted(text: String) -> bool:
	return text.begins_with(PREFIX)

static func encrypt(text: String) -> String:
	if text == "":
		return ""
	var key := _derive()
	var crypto := Crypto.new()
	var iv := crypto.generate_random_bytes(16)
	var plain := text.to_utf8_buffer()
	var pad := 16 - (plain.size() % 16)
	var padded := plain.duplicate()
	for i in pad:
		padded.append(pad)
	var aes := AESContext.new()
	if aes.start(AESContext.MODE_CBC_ENCRYPT, key, iv) != OK:
		return ""
	var cipher := aes.update(padded)
	aes.finish()
	if cipher.is_empty():
		return ""
	var body := PackedByteArray()
	body.append_array(iv)
	body.append_array(cipher)
	var blob := PackedByteArray()
	blob.append_array(_hmac(key, body))
	blob.append_array(body)
	return PREFIX + Marshalls.raw_to_base64(blob)

static func decrypt(text: String) -> String:
	if not text.begins_with(PREFIX):
		return text
	var blob := Marshalls.base64_to_raw(text.substr(PREFIX.length()))
	if blob.size() < 64:
		return ""
	var key := _derive()
	var mac := blob.slice(0, 32)
	var body := blob.slice(32)
	if not _const_eq(mac, _hmac(key, body)):
		return ""
	var iv := body.slice(0, 16)
	var cipher := body.slice(16)
	if cipher.is_empty() or cipher.size() % 16 != 0:
		return ""
	var aes := AESContext.new()
	if aes.start(AESContext.MODE_CBC_DECRYPT, key, iv) != OK:
		return ""
	var padded := aes.update(cipher)
	aes.finish()
	if padded.is_empty():
		return ""
	var pad := int(padded[padded.size() - 1])
	if pad < 1 or pad > 16 or pad > padded.size():
		return ""
	return padded.slice(0, padded.size() - pad).get_string_from_utf8()

static func _hmac(key: PackedByteArray, data: PackedByteArray) -> PackedByteArray:
	var ctx := HMACContext.new()
	ctx.start(HashingContext.HASH_SHA256, key)
	ctx.update(data)
	return ctx.finish()

static func _const_eq(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff := 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0

static func _salt() -> PackedByteArray:
	var f := FileAccess.open(SALT_PATH, FileAccess.READ)
	if f != null:
		var raw := f.get_buffer(32)
		f.close()
		if raw.size() == 32:
			return raw
	var salt := Crypto.new().generate_random_bytes(32)
	var out := FileAccess.open(SALT_PATH, FileAccess.WRITE)
	if out != null:
		out.store_buffer(salt)
		out.close()
	return salt

static func _derive() -> PackedByteArray:
	if not _key.is_empty():
		return _key
	var salt := _salt()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((OS.get_unique_id() + PEPPER).to_utf8_buffer())
	ctx.update(salt)
	var acc := ctx.finish()
	for i in ITERATIONS:
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(acc)
		ctx.update(salt)
		acc = ctx.finish()
	_key = acc
	return _key
