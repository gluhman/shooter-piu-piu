extends SceneTree

const MAP := preload("res://game/maps/map_builder.gd")
const CAPSULE := preload("res://game/actors/player_capsule.tres")
const BALANCE := preload("res://game/combat/combat_balance.gd")

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	var map := arena.get_node("Map") as Node3D
	for id in MAP.MAP_NAMES.size():
		var sizes := [0, 1, 2]
		if id == MAP.VILLAGE_ID:
			sizes = [1, 2]
		elif id == MAP.OFFICE_ID or id == MAP.TEST_RANGE_ID:
			sizes = [2]
		for size: int in sizes:
			seed(43)
			await arena.start_solo(0, 1, 0, id, Vector2i.ZERO, size)
			await physics_frame
			await physics_frame
			var context := "%s (size %d)" % [MAP.MAP_NAMES[id], size]
			var bounds := Rect2()
			var spawns := PackedVector3Array(map._initial_spawns)
			if id == MAP.BREAKWATER_ID:
				bounds = arena._breakwater.get_arena_bounds()
				for team in ["ffa", "a", "b"]:
					var markers: Array = arena._breakwater.get_spawn_candidates(team)
					_check(not markers.is_empty(), "%s has %s spawns" % [context, team])
					for marker in markers:
						spawns.append(arena._breakwater.spawn_feet(marker))
			_check(not spawns.is_empty() and _spawns_clear(map, spawns), context + " has clear spawns")
			var navigation: NavigationRegion3D = arena._navigation_region
			_check(is_instance_valid(navigation) and navigation.navigation_mesh.get_polygon_count() > 0,
				context + " has navigation")
			_check(not map.minimap_outline(bounds).is_empty(), context + " has a minimap")
			if id < MAP.VILLAGE_ID:
				_check(get_nodes_in_group(&"arena_wayfinding").size() == 2, context + " has two marked cover positions")
			arena._clear_match_map()
			await process_frame
	arena.queue_free()
	await create_timer(0.25).timeout
	quit(int(_failed))


func _spawns_clear(map: Node3D, spawns: PackedVector3Array) -> bool:
	var space := map.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = CAPSULE
	query.collision_mask = BALANCE.WORLD_MASK
	var clear := true
	for spawn in spawns:
		query.transform.origin = spawn + Vector3.UP * (CAPSULE.height * 0.5 + 0.02)
		if not space.intersect_shape(query, 1).is_empty():
			print("Blocked spawn at ", spawn)
			clear = false
	return clear


func _check(passed: bool, message: String) -> void:
	_failed = _failed or not passed
	print("PASS " if passed else "FAIL ", message)
