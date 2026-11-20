extends "res://tests/framework/test_case.gd"

const Env := preload("res://tests/framework/test_env.gd")

var sink: Array = []

func suite_name() -> String:
	return "objects"

func teardown() -> void:
	sink.clear()

func _host(actions: Array) -> GyroEventHost:
	var bp := Env.blueprint([Env.rule("ready", actions)])
	return Env.make_host(parent, bp, Env.project(), Env.path("proj/objects.json"), sink)

func _create(name: String, extra: Dictionary = {}) -> GyroAction:
	var data := {"name": name, "type": "rect", "x": 10, "y": 20, "w": 40, "h": 30, "color": "#ffffff"}
	for k in extra:
		data[k] = extra[k]
	return Env.action("CreateObject", data)

func test_create_rect_and_aabb() -> void:
	var host := _host([_create("box")])
	var node := host.get_stage().get_node_or_null("box")
	not_null(node, "object created")
	eq((node as Node2D).position, Vector2(10, 20), "position applied")
	var rect := host.runtime.object_system.get_aabb(node)
	eq(rect.size, Vector2(40, 30), "aabb size")

func test_recreate_clears_tags() -> void:
	var host := _host([
		_create("box"),
		Env.action("AddTag", {"node": "box", "tag": "enemy"}),
		_create("box"),
	])
	var tags: Array = host.runtime.tag_system.tags.get("enemy", [])
	check(not tags.has("box"), "stale tag removed on recreate (P0-2)")

func test_recreate_kills_tweens() -> void:
	var host := _host([
		_create("box"),
		Env.action("TweenOpacity", {"node": "box", "value": 0, "time": 30.0}),
		_create("box"),
	])
	check(not host.runtime.tween_system.tweens.has("box"), "stale tween killed on recreate (P0-2)")

func test_delete_purges_node_variable() -> void:
	var host := _host([
		_create("temp", {"variable": "ref"}),
		Env.action("DeleteObject", {"node": "temp"}),
		_create("other"),
	])
	is_null(host.runtime.variables.get("ref"), "variable no longer points to recycled node (P0-7)")

func test_freed_node_reference_resolves_to_null() -> void:
	var host := _host([])
	var orphan := Node2D.new()
	host.add_child(orphan)
	host.remove_child(orphan)
	orphan.free()
	is_null(host.runtime._node_from_value(orphan), "freed node rejected (P0-7)")

func test_pool_reuse_resets_state() -> void:
	var host := _host([
		_create("first"),
		Env.action("SetObjectMeta", {"node": "first", "key": "hp", "value": 5}),
		Env.action("DeleteObject", {"node": "first"}),
		_create("second"),
	])
	var stage := host.get_stage()
	is_null(stage.get_node_or_null("first"), "old node gone")
	var second := stage.get_node_or_null("second") as Node2D
	not_null(second, "new node present")
	check(not second.has_meta("hp"), "meta cleared by pool")
	eq(second.rotation, 0.0, "rotation reset")
	eq(second.scale, Vector2.ONE, "scale reset")
	eq(second.get_child_count(), 1, "only fresh visual child")

func test_set_size_updates_aabb() -> void:
	var host := _host([
		_create("box"),
		Env.action("SetSize", {"node": "box", "w": 80, "h": 60}),
	])
	var node := host.get_stage().get_node_or_null("box")
	eq(host.runtime.object_system.get_aabb(node).size, Vector2(80, 60), "aabb follows resize")

func test_delete_by_tag() -> void:
	var host := _host([
		_create("e1"),
		_create("e2"),
		Env.action("AddTag", {"node": "e1", "tag": "enemy"}),
		Env.action("AddTag", {"node": "e2", "tag": "enemy"}),
		Env.action("DeleteByTag", {"tag": "enemy"}),
	])
	var stage := host.get_stage()
	is_null(stage.get_node_or_null("e1"), "e1 deleted")
	is_null(stage.get_node_or_null("e2"), "e2 deleted")
	eq((host.runtime.tag_system.tags.get("enemy", []) as Array).size(), 0, "tag list emptied")

func test_group_reparents_and_keeps_global_position() -> void:
	var host := _host([
		Env.action("CreateGroup", {"name": "grp", "x": 100, "y": 50}),
		_create("box"),
		Env.action("AddToGroup", {"node": "box", "group": "grp"}),
	])
	var box := host.get_stage().get_node("grp").get_node_or_null("box") as Node2D
	not_null(box, "box moved into group")
	eq(box.global_position, Vector2(10, 20), "global position preserved")

func test_anchor_registered() -> void:
	var host := _host([_create("hud", {"anchor": "tr"})])
	var node := host.get_stage().get_node_or_null("hud") as Node2D
	not_null(node, "hud created")
	eq(str(node.get_meta("gyro_anchor", "")), "tr", "anchor meta stored")

func test_border_is_not_treated_as_visual() -> void:
	skip("P1: ObjectUtils.get_visual still returns border Line2D")
