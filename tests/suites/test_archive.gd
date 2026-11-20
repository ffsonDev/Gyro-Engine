extends "res://tests/framework/test_case.gd"

const Env := preload("res://tests/framework/test_env.gd")

func suite_name() -> String:
	return "archive"

func _source_project() -> String:
	var path := Env.path("src/game.json")
	var p := Env.project("Archived")
	var s := GyroScript.new()
	s.script_name = "Main"
	s.blueprint = GyroEventBlueprint.new()
	s.blueprint.rules.append(Env.rule("ready", [Env.action("Print", {"message": "hi"})]))
	p.scripts.append(s)
	var a := GyroAsset.new()
	a.id = "a1"
	a.kind = "sprite"
	a.asset_name = "hero"
	a.path = "sprite/hero.png"
	p.assets.append(a)
	GyroProjectJSON.save_to_file(p, path)
	Env.write_png(Env.path("src/game.files/sprite/hero.png"), 8, 8)
	Env.write_text(Env.path("src/game.files/other/notes.txt"), "payload")
	return path

func test_export_import_round_trip() -> void:
	var src := _source_project()
	var archive := Env.path("out/game.gyroproj")
	check(GyroProjectArchive.export_project(src, archive), "export ok")
	var imported := GyroProjectArchive.import_project(archive, Env.path("dst/"), "game")
	check(imported != "", "import returned path")
	var loaded := GyroProjectJSON.load_from_file(imported)
	not_null(loaded, "imported project loads")
	eq(loaded.scripts.size(), 1, "scripts survived")
	eq(loaded.assets.size(), 1, "assets survived")
	check(FileAccess.file_exists(imported.get_basename() + ".files/sprite/hero.png"), "binary asset restored")
	check(FileAccess.file_exists(imported.get_basename() + ".files/other/notes.txt"), "text asset restored")

func test_export_strips_secrets() -> void:
	var src := _source_project()
	var p := GyroProjectJSON.load_from_file(src)
	p.settings.keystore_password = "secret"
	p.settings.keystore_path = "user://keystore/release.p12"
	GyroProjectJSON.save_to_file(p, src)
	var archive := Env.path("out/secrets.gyroproj")
	GyroProjectArchive.export_project(src, archive)
	var imported := GyroProjectArchive.import_project(archive, Env.path("dst2/"), "secrets")
	var loaded := GyroProjectJSON.load_from_file(imported)
	eq(loaded.settings.keystore_password, "", "password not exported")
	eq(loaded.settings.keystore_path, "", "keystore path not exported")

func test_read_project_name() -> void:
	var src := _source_project()
	var archive := Env.path("out/name.gyroproj")
	GyroProjectArchive.export_project(src, archive)
	eq(GyroProjectArchive.read_project_name(archive), "Archived", "name read from archive")

func test_bad_magic_rejected() -> void:
	var path := Env.path("bad/magic.gyroproj")
	Env.write_archive(path, [{"path": "project.json", "data": "{}".to_utf8_buffer()}], "NOTGYRO1")
	eq(GyroProjectArchive.import_project(path, Env.path("dst3/"), "x"), "", "bad magic")
	eq(GyroProjectArchive.read_project_name(path), "", "name reader rejects bad magic")

func test_truncated_archive_rejected() -> void:
	var path := Env.path("bad/truncated.gyroproj")
	Env.write_archive(path, [{"path": "project.json", "data": "{\"format_version\":2}".to_utf8_buffer(), "stored_size": 999999}])
	eq(GyroProjectArchive.import_project(path, Env.path("dst4/"), "x"), "", "truncated payload")

func test_invalid_entry_count_rejected() -> void:
	var zero := Env.path("bad/zero.gyroproj")
	Env.write_archive(zero, [], "GYROPRJ2", 0)
	eq(GyroProjectArchive.import_project(zero, Env.path("dst5/"), "x"), "", "zero entries")
	var huge := Env.path("bad/huge.gyroproj")
	Env.write_archive(huge, [{"path": "project.json", "data": "{}".to_utf8_buffer()}], "GYROPRJ2", 70000)
	eq(GyroProjectArchive.import_project(huge, Env.path("dst6/"), "x"), "", "too many entries")

func test_path_traversal_blocked() -> void:
	var path := Env.path("bad/traversal.gyroproj")
	Env.write_archive(path, [
		{"path": "project.json", "data": "{\"format_version\":2}".to_utf8_buffer()},
		{"path": "files/../../escaped.txt", "data": "x".to_utf8_buffer()},
		{"path": "files//absolute.txt", "data": "x".to_utf8_buffer()},
	])
	var imported := GyroProjectArchive.import_project(path, Env.path("dst7/"), "safe")
	check(imported != "", "valid part imported")
	check(not FileAccess.file_exists(Env.path("escaped.txt")), "no traversal write")
	check(not FileAccess.file_exists(Env.path("dst7/escaped.txt")), "no traversal write in dest")

func test_unknown_compression_method_rejected() -> void:
	var path := Env.path("bad/method.gyroproj")
	Env.write_archive(path, [{"path": "project.json", "data": "{\"format_version\":2}".to_utf8_buffer(), "method": 99}])
	eq(GyroProjectArchive.import_project(path, Env.path("dst8/"), "x"), "", "invalid method")

func test_raw_size_mismatch_rejected() -> void:
	var path := Env.path("bad/size.gyroproj")
	Env.write_archive(path, [{"path": "project.json", "data": "{}".to_utf8_buffer(), "raw_size": 1073741824}])
	eq(GyroProjectArchive.import_project(path, Env.path("dst9/"), "x"), "", "size mismatch")

func test_compressed_entries_round_trip() -> void:
	var big := "x".repeat(8192)
	var path := Env.path("out/compressed.gyroproj")
	Env.write_archive(path, [
		{"path": "project.json", "data": "{\"format_version\":2,\"settings\":{\"app_name\":\"Big\"}}".to_utf8_buffer(), "compress": true},
		{"path": "files/other/big.txt", "data": big.to_utf8_buffer(), "compress": true},
	])
	var imported := GyroProjectArchive.import_project(path, Env.path("dst10/"), "big")
	check(imported != "", "compressed import")
	eq(FileAccess.get_file_as_string(imported.get_basename() + ".files/other/big.txt").length(), big.length(), "compressed payload intact")

func test_pack_export_import() -> void:
	var pack := GyroCustomPack.new()
	pack.pack_name = "Weapons"
	pack.author = "tester"
	var b := GyroCustomBlock.new()
	b.block_id = "shoot"
	b.block_name = "Shoot"
	b.fields = [{"key": "power", "label": "Power", "pick": "", "default": "1"}]
	b.body.append(Env.action("Print", {"message": "bang"}))
	pack.blocks.append(b)
	var path := Env.path("out/weapons.gyropack")
	check(GyroCustomRegistry.export_pack(pack, path), "pack exported")
	var project := Env.project()
	var result := GyroCustomRegistry.import_pack(project, path)
	check(bool(result.get("ok", false)), "pack imported")
	eq(project.custom_packs.size(), 1, "pack added")
	eq(project.custom_packs[0].blocks.size(), 1, "block added")
	eq(project.custom_packs[0].blocks[0].block_id, "shoot", "block id kept")

func test_pack_duplicate_id_remapped() -> void:
	var project := Env.project()
	var existing := GyroCustomBlock.new()
	existing.block_id = "shoot"
	existing.block_name = "Existing"
	project.custom_blocks.append(existing)
	var pack := GyroCustomPack.new()
	pack.pack_name = "Other"
	var incoming := GyroCustomBlock.new()
	incoming.block_id = "shoot"
	incoming.block_name = "Incoming"
	pack.blocks.append(incoming)
	var path := Env.path("out/dup.gyropack")
	GyroCustomRegistry.export_pack(pack, path)
	var result := GyroCustomRegistry.import_pack(project, path)
	check(bool(result.get("ok", false)), "import ok")
	eq(project.custom_packs[0].blocks[0].block_id, "shoot_2", "id remapped")
	check(not (result.get("report", []) as Array).is_empty(), "rename reported")

func test_pack_unknown_action_dropped() -> void:
	var pack := GyroCustomPack.new()
	pack.pack_name = "Broken"
	var b := GyroCustomBlock.new()
	b.block_id = "b1"
	b.block_name = "B"
	b.body.append(Env.action("TotallyUnknown", {}))
	b.body.append(Env.action("Print", {"message": "ok"}))
	pack.blocks.append(b)
	var path := Env.path("out/broken.gyropack")
	GyroCustomRegistry.export_pack(pack, path)
	var project := Env.project()
	GyroCustomRegistry.import_pack(project, path)
	eq(project.custom_packs[0].blocks[0].body.size(), 1, "unknown action dropped")
	eq(project.custom_packs[0].blocks[0].body[0].type, "Print", "known action kept")

func test_pack_bad_magic_rejected() -> void:
	var path := Env.path("bad/pack.gyropack")
	Env.write_text(path, "NOPE")
	var result := GyroCustomRegistry.import_pack(Env.project(), path)
	check(not bool(result.get("ok", false)), "bad pack rejected")
