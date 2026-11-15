extends SceneTree
## Bakes every objective edition from its regular MapBuilder entry point.

const MAP := preload("res://game/maps/map_builder.gd")
const LAYOUT := preload("res://game/maps/objective_layout.gd")
const BREAKWATER := preload("res://game/maps/breakwater/breakwater_arena.tscn")
const BALANCE := preload("res://game/combat/combat_balance.gd")
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var checked := 0
	for mode in range(LAYOUT.HILL, LAYOUT.DEFUSE + 1):
		for arena in MAP.MAP_NAMES.size():
			for size in MAP.SIZE_WIDTHS.size():
				if not LAYOUT.supports(mode, arena, size):
					if size != 0 and arena not in [MAP.OFFICE_ID, MAP.TEST_RANGE_ID]:
						_check(false, "unexpected exclusion")
					continue
				await _test_layout(mode, arena, size)
				checked += 1
	print("Objective map editions checked: %d, failures: %d" % [checked, failures])
	quit(1 if failures > 0 else 0)


func _test_layout(mode: int, arena: int, size: int) -> void:
	var map := Node3D.new()
	map.set_script(MAP)
	root.add_child(map)
	var authored: Node3D
	var width: float = MAP.FOREST_RIDGE.WIDTH if arena == MAP.FOREST_RIDGE_ID else MAP.SIZE_WIDTHS[size]
	if arena == MAP.BREAKWATER_ID:
		authored = BREAKWATER.instantiate()
		map.add_child(authored)
		authored.apply_layout(size)
	else:
		map.build(arena, 31562, width, mode, size)
	var layout: Dictionary = map.objective_layout(mode, arena, size)
	var mesh := MAP.navigation_mesh(arena, width, authored)
	var geometry := NavigationMeshSourceGeometryData3D.new()
	var fixtures := map.get_node_or_null("VillageFixtures")
	if fixtures:
		fixtures.set_door_collision(false)
	NavigationServer3D.parse_source_geometry_data(mesh, geometry, map)
	NavigationServer3D.bake_from_source_geometry_data(mesh, geometry)
	if fixtures:
		fixtures.set_door_collision(true)
	var region := NavigationRegion3D.new()
	region.navigation_mesh = mesh
	map.add_child(region)
	var nav := region.get_navigation_map()
	for attempt in 40:
		var spawn: Vector3 = layout.spawns[0][0]
		if NavigationServer3D.map_get_closest_point_owner(nav, spawn) == region.get_rid():
			break
		await create_timer(0.025).timeout
	await physics_frame
	var space := map.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.8
	var collision := PhysicsShapeQueryParameters3D.new()
	collision.shape = capsule
	collision.collision_mask = BALANCE.WORLD_MASK
	var notes: Array[String] = []
	for team in 2:
		var spawns: PackedVector3Array = layout.spawns[team]
		if spawns.size() < 5:
			notes.append("fewer than five team %d spawn points" % team)
		for position in spawns:
			collision.transform.origin = position + Vector3.UP * 0.93
			if not space.intersect_shape(collision, 1).is_empty():
				notes.append("team %d intersects cover at %s" % [team, position])
			for center in layout.centers:
				var path := NavigationServer3D.map_get_path(nav, position, center, true)
				if path.is_empty() or path[0].distance_to(position) > 1.0 or path[-1].distance_to(center) > 1.0:
					notes.append("unreachable point %s → %s" % [position, center])
				if LAYOUT.contains(position, center, layout.radius):
					notes.append("spawn inside an objective at %s" % position)
	if mode == LAYOUT.HILL:
		for center: Vector3 in layout.centers:
			var covers := 0
			for body in get_nodes_in_group(&"hill_cover"):
				if map.is_ancestor_of(body) and LAYOUT.contains(body.global_position, center, layout.radius):
					covers += 1
			if covers != 1:
				notes.append("expected one cover prop inside hill %s, found %d" % [center, covers])
			var entries := 0
			var reach := minf(2.3, layout.radius - 0.30)
			for direction in 12:
				var offset := Vector3.FORWARD.rotated(Vector3.UP, direction * TAU / 12.0) * reach
				var point := NavigationServer3D.map_get_closest_point(nav, center + offset)
				if point.distance_to(center + offset) > 0.60:
					continue
				var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP, center + Vector3.UP, BALANCE.WORLD_MASK)
				if space.intersect_ray(ray).is_empty():
					entries += 1
			if entries < 3:
				notes.append("fewer than three clear approach samples at hill %s" % center)
	if mode in [LAYOUT.HILL, LAYOUT.DEFUSE]:
		for center in layout.centers:
			var first := [INF, INF]
			for team in 2:
				for spawn in layout.spawns[team]:
					first[team] = minf(first[team], _travel(nav, spawn, center))
			if mode == LAYOUT.HILL and absf(first[0] - first[1]) > 1.55:
				notes.append("hill arrival differs by %.2f s at %s" % [absf(first[0] - first[1]), center])
			elif mode == LAYOUT.DEFUSE and (first[0] - first[1] < -0.15 or first[0] - first[1] > 2.05):
				notes.append("defender route lead %.2f s at %s" % [first[0] - first[1], center])
	if mode == LAYOUT.FLAG:
		var eye := Vector3.UP * 1.54
		var ray := PhysicsRayQueryParameters3D.create(layout.centers[0] + eye, layout.centers[1] + eye, BALANCE.WORLD_MASK)
		if space.intersect_ray(ray).is_empty():
			notes.append("opposing flag stands have direct sightline")
	var timing := ""
	if mode != LAYOUT.HILL:
		var out := _travel(nav, layout.centers[0], layout.centers[1])
		var back := _travel(nav, layout.centers[1], layout.centers[0])
		timing = " · %.1f/%.1f s" % [out, back]
		if mode == LAYOUT.DEFUSE and maxf(out, back) > 12.0:
			notes.append("site rotation exceeds 12 s")
		if mode == LAYOUT.FLAG:
			if absf(out - back) > maxf(out, back) * 0.1:
				notes.append("stand route times differ by more than 10%")
			var tolerance := Vector2(5.85, 9.0) if size == 1 else Vector2(9.0, 15.0)
			if minf(out, back) < tolerance.x or maxf(out, back) > tolerance.y:
				notes.append("stand route times outside the range for this map size")
	_check(notes.is_empty(), "%s · %s · %s%s %s" % [LAYOUT.NAMES[mode], MAP.MAP_NAMES[arena], MAP.SIZE_NAMES[size], timing,
		"; ".join(notes)])
	map.free()
	await physics_frame


func _travel(nav: RID, from: Vector3, to: Vector3) -> float:
	var path := NavigationServer3D.map_get_path(nav, from, to, true)
	if path.size() < 2:
		return INF
	var meters := 0.0
	for index in range(1, path.size()):
		meters += path[index - 1].distance_to(path[index])
	return meters / float(BALANCE.MOVEMENT.walk_speed_m_s)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", message)
