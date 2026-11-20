extends "res://tests/framework/test_case.gd"

const Env := preload("res://tests/framework/test_env.gd")

func suite_name() -> String:
	return "backups"

func _project_path() -> String:
	var path := Env.path("bk/game.json")
	GyroProjectJSON.save_to_file(Env.project("Backup"), path)
	Env.write_text(Env.path("bk/game.files/other/a.txt"), "asset")
	return path

func test_force_backup_copies_project_and_files() -> void:
	var path := _project_path()
	check(GyroBackups.make_backup_force(path), "backup created")
	var list := GyroBackups.list_backups(path)
	eq(list.size(), 1, "one backup listed")
	check(FileAccess.file_exists(str(list[0])), "backup json exists")
	check(DirAccess.dir_exists_absolute(str(list[0]).get_basename() + ".files"), "asset folder copied")

func test_prune_keeps_limit() -> void:
	var path := _project_path()
	for i in 6:
		GyroBackups.make_backup_force(path)
	check(GyroBackups.list_backups(path).size() <= GyroBackups.MAX_BACKUPS, "old backups pruned")

func test_interval_blocks_second_backup() -> void:
	var path := _project_path()
	GyroBackups.make_backup_force(path)
	check(not GyroBackups.make_backup(path), "non-forced backup respects interval")

func test_restore_brings_back_content() -> void:
	var path := _project_path()
	GyroBackups.make_backup_force(path)
	var backup := str(GyroBackups.list_backups(path)[0])
	Env.write_text(path, "{\"format_version\":2,\"settings\":{\"app_name\":\"Changed\"}}")
	Env.remove_dir(Env.path("bk/game.files"))
	check(GyroBackups.restore_backup(path, backup), "restore ok")
	var loaded := GyroProjectJSON.load_from_file(path)
	eq(loaded.settings.app_name, "Backup", "project content restored")
	check(FileAccess.file_exists(Env.path("bk/game.files/other/a.txt")), "assets restored")

func test_invalid_backup_rejected() -> void:
	var path := _project_path()
	var bad := Env.path("bk/game.backups/bad.json")
	Env.write_text(bad, "{ broken")
	check(not GyroBackups.restore_backup(path, bad), "corrupt backup rejected")
	check(not GyroBackups.restore_backup(path, Env.path("bk/absent.json")), "missing backup rejected")
	eq(GyroProjectJSON.load_from_file(path).settings.app_name, "Backup", "project untouched")

func test_backup_of_missing_project() -> void:
	check(not GyroBackups.make_backup_force(Env.path("bk/absent.json")), "no project no backup")
