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
				if id == MAP.STATION_ID:
					var half: float = arena.arena_width() * 0.5
					var inner := lerpf(5.55, 12.8, inverse_lerp(10.0, 35.0, half))
					var wall_x := inner + clampf((half - inner) * 0.40, 2.05, 3.4)
					for deck in 3:
						for side in [-1.0, 1.0]:
							destinations.append(Vector3(side * (wall_x + 0.83),
								deck * MAP.STATION.DECK_HEIGHT + 0.2, inner * 0.34))
				await _wait_for_navigation(navigation, spawns[0])
				_check(_connected(navigation.get_navigation_map(), spawns[0], destinations),
					context + " connects all spawns and supply crates")
			if id == MAP.STATION_ID:
				_check_station(map, context, arena.arena_width())
			if id == MAP.OUTPOST_ID:
				var edge: float = arena.arena_width() * 0.5
				var hill := _ground_height(map, Vector2(0.77, 0.55) * edge)
				var west_drain := _ground_height(map, Vector2(-0.56, -0.60) * edge)
				var east_drain := _ground_height(map, Vector2(0.56, 0.60) * edge)
				_check(hill > 0.8 and hill < 5.0 and minf(west_drain, east_drain) > -3.0
					and maxf(west_drain, east_drain) < -0.65,
					context + " has collision on the hill and in both ditches (%.2f, %.2f, %.2f m)" % [hill, west_drain, east_drain])
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


func _check_station(map: Node3D, context: String, width: float) -> void:
	var world := map.get_world_3d().direct_space_state
	var side := width * 0.5 - 2.0
	for deck in [1, 2]:
		var height: float = deck * MAP.STATION.DECK_HEIGHT
		var query := PhysicsRayQueryParameters3D.create(Vector3(side, height + 1.0, 0),
			Vector3(side, height - 0.30, 0), BALANCE.WORLD_MASK)
		var hit := world.intersect_ray(query)
		_check(not hit.is_empty() and is_equal_approx(hit.position.y, height)
			and not map.minimap_outline(Rect2(), height).is_empty(),
			context + " has a colliding balcony and minimap on deck %d" % deck)
	var sightline := PhysicsRayQueryParameters3D.create(Vector3(0, 10.5, 2.0),
		Vector3(0, 0.3, 2.0), BALANCE.WORLD_MASK)
	_check(world.intersect_ray(sightline).is_empty(), context + " has an open three-deck atrium")
	var half := width * 0.5
	var inner := lerpf(5.55, 12.8, inverse_lerp(10.0, 35.0, half))
	var room_end := inner * 0.60
	var wall_x := inner + clampf((half - inner) * 0.40, 2.05, 3.4)
	for deck in 3:
		var y: float = deck * MAP.STATION.DECK_HEIGHT + 1.2
		var wall := PhysicsRayQueryParameters3D.create(Vector3(wall_x - 0.6, y, 0),
			Vector3(wall_x + 0.6, y, 0), BALANCE.WORLD_MASK)
		var doorway := PhysicsRayQueryParameters3D.create(Vector3(wall_x - 0.6, y, room_end * 0.56),
			Vector3(wall_x + 0.6, y, room_end * 0.56), BALANCE.WORLD_MASK)
		_check(not world.intersect_ray(wall).is_empty() and world.intersect_ray(doorway).is_empty(),
			context + " has a walled room and open doorway on deck %d" % deck)
	var floor := PhysicsRayQueryParameters3D.create(Vector3(0, 0.35, 2.0),
		Vector3(0, -0.3, 2.0), BALANCE.WORLD_MASK)
	var stairs := PhysicsRayQueryParameters3D.create(Vector3(inner * 0.65, 2.2, 0),
		Vector3(inner * 0.65, 1.5, 0), BALANCE.WORLD_MASK)
	var floor_hit := world.intersect_ray(floor)
	var stair_hit := world.intersect_ray(stairs)
	_check(not floor_hit.is_empty() and not stair_hit.is_empty()
		and floor_hit.collider.get_meta(&"footstep_surface", "") == "station_steel"
		and stair_hit.collider.get_meta(&"footstep_surface", "") == "station_stairs",
		context + " assigns distinct steel and stair footstep surfaces")


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
