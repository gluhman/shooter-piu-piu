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
		elif id in [MAP.OFFICE_ID, MAP.TEST_RANGE_ID, MAP.FOREST_RIDGE_ID]:
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
			if id in [MAP.OUTPOST_ID, MAP.STATION_ID, MAP.FOREST_RIDGE_ID]:
				var crates: Array = arena.get_node("Loot")._crates
				var destinations := PackedVector3Array(map.respawn_points)
				for crate: StaticBody3D in crates:
					destinations.append(crate.position)
				_check(crates.size() == 4 and _spawns_clear(map, map.respawn_points),
					context + " has four crates and clear respawns")
				if id == MAP.FOREST_RIDGE_ID:
					destinations.append_array(spawns)
				await _wait_for_navigation(navigation, spawns[0])
				_check(_connected(navigation.get_navigation_map(), spawns[0], destinations),
					context + " connects all spawns and supply crates")
			if id == MAP.FOREST_RIDGE_ID:
				var forest: Node3D = map.get_node("ForestRidge")
				_check(arena.arena_width() == 100.0 and forest.find_children("Spawn*", "Marker3D", false, false).size() == 4,
					context + " has a fixed 100 m footprint and four spawn markers")
				var terrain := _ground_height(map, Vector2(4, -45))
				var ditch := _ground_height(map, Vector2(18, 16))
				_check(terrain > 15.0 and ditch < -1.8, context + " has collision on the peak and in the ditch")
			if id < MAP.VILLAGE_ID:
				_check(get_nodes_in_group(&"arena_wayfinding").size() == 2, context + " has two marked cover positions")
			arena._clear_match_map()
			await process_frame
	arena.queue_free()
	await create_timer(0.25).timeout
	quit(int(_failed))


func _wait_for_navigation(region: NavigationRegion3D, spawn: Vector3) -> void:
	var nav_map := region.get_navigation_map()
	for attempt in 40:
		if NavigationServer3D.map_get_closest_point_owner(nav_map, spawn) == region.get_rid():
			return
		await create_timer(0.025).timeout


func _connected(nav_map: RID, from: Vector3, destinations: PackedVector3Array) -> bool:
	for point in destinations:
		var path := NavigationServer3D.map_get_path(nav_map, from, point, true)
		if path.is_empty() and from.is_equal_approx(point):
			var nearest := NavigationServer3D.map_get_closest_point(nav_map, point)
			if nearest.distance_to(point) <= 1.5:
				continue
		if path.is_empty() or path[-1].distance_to(point) > 1.5:
			print("Unreachable destination ", point)
			return false
	return true


func _ground_height(map: Node3D, point: Vector2) -> float:
	var high := Vector3(point.x, 27.0, point.y)
	var ray := PhysicsRayQueryParameters3D.create(high, high - Vector3.UP * 32.0, BALANCE.WORLD_MASK)
	var hit := map.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.position.y if not hit.is_empty() else INF


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
