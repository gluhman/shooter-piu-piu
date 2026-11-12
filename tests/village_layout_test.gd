extends SceneTree
## Run with: godot --headless --path . --script res://tests/village_layout_test.gd

const MAP := preload("res://game/maps/map_builder.gd")
const BALANCE := preload("res://game/combat/combat_balance.gd")
const CAPSULE := preload("res://game/actors/player_capsule.tres")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	for selected_size in [0, 2]:
		await arena.start_solo(0, 1, 0, MAP.VILLAGE_ID, Vector2i.ZERO, selected_size)
		var map := arena.get_node("Map") as Node3D
		var width: float = arena.arena_width()
		_check("Village started at %s m" % width,
			width == (40.0 if selected_size == 0 else 70.0) and not arena.is_loading() and arena.combatant(1) != null)
		var nav: RID = arena.get_world_3d().navigation_map
		var region: NavigationRegion3D = arena._navigation_region
		for frame in 120:
			await physics_frame
			if NavigationServer3D.map_get_closest_point_owner(nav, Vector3.ZERO) == region.get_rid():
				break
		_check_layout(map, nav, width)
		await _check_respawn(arena)
		if selected_size == 0:
			await _check_stairs(arena)
			await _check_fixtures(arena)
			await _check_blast_damage(arena)
			_check_market_loot(arena)
		arena._clear_match_map()
		await process_frame
	arena.queue_free()
	await create_timer(0.25).timeout
	quit(1 if _failures else 0)


func _check_layout(map: Node3D, nav: RID, width: float) -> void:
	var space := map.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = CAPSULE
	query.collision_mask = BALANCE.WORLD_MASK
	var clear: bool = map._initial_spawns.size() == 20
	for index in map._initial_spawns.size():
		query.transform.origin = map.initial_spawn(index) + Vector3.UP * 0.86
		clear = clear and space.intersect_shape(query, 1).is_empty()
	_check("All 20 starting slots have player capsule clearance", clear)
	if not clear:
		return

	var ground := PhysicsRayQueryParameters3D.new()
	ground.collision_mask = BALANCE.WORLD_MASK
	var low := 0.0
	var high := 0.0
	var steepest := 1.0
	for x in range(-int(width * 0.5), int(width * 0.5)):
		for z in range(-int(width * 0.5), int(width * 0.5)):
			ground.from = Vector3(x + 0.2, 8.0, z + 0.3)
			ground.to = ground.from - Vector3.UP * 10.0
			var hit := space.intersect_ray(ground)
			if not hit.is_empty() and hit.collider.name == &"VillageTerrain":
				low = minf(low, hit.position.y)
				high = maxf(high, hit.position.y)
				steepest = minf(steepest, hit.normal.y)
	_check("Terrain has hills and depressions with walkable grades (%.2f to %.2f m)" % [low, high],
		low < -0.24 and high > 0.30 and steepest > cos(deg_to_rad(42.0)))
	var fixtures := map.get_node("VillageFixtures")
	_check("Every village door starts closed", fixtures._doors.all(func(door): return not door.opened))
	_check("Respawn candidates stay out of the market", Array(map.respawn_points).all(
		func(point: Vector3): return absf(point.x) >= 6.0 or absf(point.z) >= 6.0))
	var homes := 7 if width > 40.0 else 5
	var thresholds_clear := true
	for door in fixtures._doors:
		for side in [-1.0, 1.0]:
			query.transform.origin = door.portal * Vector3(0, 0.91, side * 0.72)
			if not space.intersect_shape(query, 1).is_empty():
				print("Blocked door threshold at ", query.transform.origin)
				thresholds_clear = false
	_check("Standing capsules fit on both sides of every house door", thresholds_clear)
	_check("Every house has a working door and two glazed window openings",
		fixtures._doors.size() == 5 + homes and fixtures._windows.size() == 3 + 2 * homes)

	var barn: Vector3 = map.initial_spawn(0)
	var gate: Vector3 = map.initial_spawn(1)
	var square := Vector3(2.4, 0.2, 0)
	var from_barn := _route(nav, barn, square)
	var from_gate := _route(nav, gate, square)
	_check("Barn and gate reach the square within 4 m of each other (%.2f, %.2f)" % [from_barn, from_gate],
		is_finite(from_barn) and is_finite(from_gate) and absf(from_barn - from_gate) <= 4.0)
	var spawn_ray := PhysicsRayQueryParameters3D.new()
	spawn_ray.collision_mask = BALANCE.WORLD_MASK
	var exposed := 0
	for point in map._initial_spawns:
		spawn_ray.to = point + Vector3.UP * 1.4
		for approach in [Vector3(0, 1.6, 0), Vector3(-2.2, 1.6, -4), Vector3(2.2, 1.6, 4)]:
			spawn_ray.from = approach
			if space.intersect_ray(spawn_ray).is_empty():
				exposed += 1
	_check("Barn and gate starts are screened from the market approaches (%d exposed rays)" % exposed, exposed == 0)
	_check("Both side exits have a direct route to the yards",
		_route(nav, barn, Vector3(-7.2, 0.2, barn.z + 0.05)) < 7.0
		and _route(nav, gate, Vector3(7.2, 0.2, width * 0.5 - 3.2)) < 7.0)
	_check("Yards reconnect to the square and the far street",
		is_finite(_route(nav, Vector3(-16.1, 0.2, 0.4), Vector3(-3.6, 0.2, 0.4)))
		and is_finite(_route(nav, Vector3(14.5, 0.2, -4.0), Vector3(-3.1, 0.2, -12.7))))
	_check("Shop and inn have usable ground-floor shortcuts",
		_route(nav, Vector3(-5.6, 0.2, 5.9), Vector3(-12.2, 0.2, 5.9)) < 8.0
		and _route(nav, Vector3(-5.5, 0.2, -5.2), Vector3(-14.2, 0.2, -5.2)) < 10.0)
	var upper_room := Vector3(-8.3, 3.0, -5.1)
	_check("Both staircases offer separate paths to the inn's upper floor",
		_route(nav, Vector3(-11.6, 0.2, -3.9), upper_room) < 11.0
		and _route(nav, Vector3(-14.23, 0.2, 1.85), upper_room) < 16.0)
	var ray := PhysicsRayQueryParameters3D.create(Vector3(-2.2, 1.58, -4.3), Vector3(2.2, 1.58, 4.3), BALANCE.WORLD_MASK)
	var hit := space.intersect_ray(ray)
	_check("Well blocks the eye-height view across the square",
		not hit.is_empty() and Vector2(hit.position.x, hit.position.z).length() < 1.7)


func _route(nav: RID, from: Vector3, to: Vector3) -> float:
	var path := NavigationServer3D.map_get_path(nav, from, to, true)
	if path.size() < 2 or path[0].distance_to(from) >= 1.0 or path[-1].distance_to(to) >= 1.0:
		return INF
	var distance := 0.0
	for index in range(1, path.size()):
		distance += path[index - 1].distance_to(path[index])
	return distance


func _check_respawn(arena: Node3D) -> void:
	var map := arena.get_node("Map")
	var enemy: CharacterBody3D = arena.combatant(1)
	var initial := enemy.global_position
	enemy._apply_equip("ak47")
	enemy.global_position = Vector3(2.35, 0.15, 0.5)
	enemy.velocity = Vector3.ZERO
	await physics_frame
	var at: Vector3 = arena._choose_safe_spawn(null, 0, Vector3.INF, map.respawn_points)
	var covered := false
	if at.is_finite():
		var query := PhysicsRayQueryParameters3D.create(enemy.aim_center(),
			at + Vector3.UP * 1.4, BALANCE.WORLD_MASK)
		var space := arena.get_world_3d().direct_space_state
		covered = not arena.get_node("Ballistics").ray_through_glass(space, query).is_empty()
	_check("Respawn selects a clear site behind cover and at least 12 m from a market enemy",
		at.is_finite() and covered and at.distance_to(enemy.global_position) >= 12.0)
	enemy.global_position = initial
	enemy.velocity = Vector3.ZERO
	await physics_frame


func _check_stairs(arena: Node3D) -> void:
	var fixtures := arena.get_node("Map/VillageFixtures")
	for door in fixtures._doors:
		fixtures._apply_door(door, true)
	await physics_frame
	var walker := CharacterBody3D.new()
	walker.collision_layer = 0
	walker.collision_mask = BALANCE.WORLD_MASK
	walker.floor_snap_length = 0.2
	var collider := CollisionShape3D.new()
	collider.shape = CAPSULE
	collider.position.y = 0.85
	walker.add_child(collider)
	arena.add_child(walker)
	walker.position = Vector3(-12.59, 0.07, -2.16)
	var inside := await _walk(walker, Vector2(-7.83, -2.16))
	var landing := await _walk(walker, Vector2(-7.83, -4.42))
	_check("Player capsule turns off the internal landing into the upper room",
		inside and landing and walker.position.y > 2.8)
	walker.position = Vector3(-14.23, 0.07, 3.2)
	var outside := await _walk(walker, Vector2(-14.23, -5.17))
	var doorway := await _walk(walker, Vector2(-12.25, -5.17))
	_check("Player capsule climbs the exterior stairs and enters the inn",
		outside and doorway and walker.position.y > 2.8)
	var threshold_is_wood := true
	for x in [-13.21, -13.1, -12.99]:
		var threshold := PhysicsRayQueryParameters3D.create(
			Vector3(x, 3.2, -5.2), Vector3(x, 2.8, -5.2), BALANCE.WORLD_MASK)
		var hit := arena.get_world_3d().direct_space_state.intersect_ray(threshold)
		threshold_is_wood = threshold_is_wood and not hit.is_empty() \
			and hit.collider.get_meta(&"impact_surface") == "wood" and is_equal_approx(hit.position.y, 2.9)
	_check("Upstairs door has a flush wooden threshold", threshold_is_wood)
	var ground_ray := PhysicsRayQueryParameters3D.create(Vector3(-18.7, 2.0, 15.8),
		Vector3(-18.7, -1.2, 15.8), BALANCE.WORLD_MASK)
	var ground := arena.get_world_3d().direct_space_state.intersect_ray(ground_ray)
	if not ground.is_empty():
		walker.position = ground.position + Vector3.UP * 0.03
		var uphill := await _walk(walker, Vector2(-16.2, 15.8))
		var crest := walker.position.y
		var downhill := await _walk(walker, Vector2(-14.0, 15.8))
		_check("Player capsule walks up and down the yard hill",
			uphill and downhill and crest > 0.7 and crest - walker.position.y > 0.2)
	else:
		_check("Player capsule can reach the yard hill", false)
	walker.queue_free()
	fixtures.reset_round()
	await physics_frame


func _check_fixtures(arena: Node3D) -> void:
	var fixtures := arena.get_node("Map/VillageFixtures")
	var actor: CharacterBody3D = arena.combatant(1)
	arena.get_node("HUD/WeaponSelect")._set_open(false)
	actor._apply_equip("ak47")

	var door = fixtures._doors[0]
	actor.position = door.portal * Vector3(0, 0.08, 1.42)
	_face(actor, -door.portal.basis.z)
	for frame in 9:
		await physics_frame
	_interact()
	for frame in 9:
		await physics_frame
	var opened: bool = door.opened
	var ray := PhysicsRayQueryParameters3D.create(door.portal * Vector3(0, 1.1, 0.8),
		door.portal * Vector3(0, 1.1, -0.7), BALANCE.WORLD_MASK)
	var space := arena.get_world_3d().direct_space_state
	var clear: bool = space.intersect_ray(ray).is_empty()
	_interact()
	for frame in 9:
		await physics_frame
	_check("Interact opens and closes the door and updates its collision",
		opened and clear and not door.opened and space.intersect_ray(ray).get("collider") == door.leaf)

	var window = fixtures._windows[2]
	var sill: Transform3D = window.sill
	var pane: StaticBody3D = window.pane
	var from := sill * Vector3(0, 0.87, 1.15)
	var through := -sill.basis.z
	ray.from = from
	ray.to = from + through * 1.7
	var intact: bool = pane.visible and space.intersect_ray(ray).get("collider") == pane
	var ballistics := arena.get_node("Ballistics")
	ballistics.queue_shot("ak47", actor.gun.WEAPONS.ak47, actor,
		Transform3D(Basis.looking_at(through), from), 0.2, from, PackedVector3Array([through]))
	for frame in 4:
		await physics_frame
	_check("A simulated projectile removes the visible pane and its collision",
		intact and window.broken and not pane.visible and space.intersect_ray(ray).is_empty())

	actor.position = sill * Vector3(0, -0.66, 0.76)
	actor.velocity = Vector3.ZERO
	_face(actor, through)
	for frame in 8:
		await physics_frame
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")
	for frame in 40:
		await physics_frame
	Input.action_release(&"jump")
	Input.action_release(&"move_forward")
	_check("The player can jump through a broken ground-floor window",
		(sill.affine_inverse() * actor.position).z < -0.40)
	fixtures.reset_round()
	await physics_frame
	_check("Round restart restores the pane and shuts every door",
		not window.broken and pane.visible and fixtures._doors.all(func(entry): return not entry.opened))

	actor.position = sill * Vector3(0, -0.66, 0.76)
	actor.velocity = Vector3.ZERO
	_face(actor, through)
	actor._apply_equip("knife")
	await physics_frame
	actor.gun._try_fire()
	await create_timer(float(BALANCE.MELEE.windup_s) + 0.15).timeout
	_check("A knife swing shatters an intact window", window.broken)
	fixtures.reset_round()
	await physics_frame

	var grenades := arena.get_node("Grenades")
	var flight_id: int = grenades._next_id
	grenades._launch("frag", actor, from, through * float(BALANCE.GRENADES.shared.throw_speed_m_s), 1.0, 0)
	for frame in 9:
		await physics_frame
	_check("A thrown grenade shatters and passes through the window",
		window.broken and grenades._flights.has(flight_id)
		and (sill.affine_inverse() * grenades._flights[flight_id].at).z < -0.1)
	grenades.reset_round()
	fixtures.reset_round()
	await physics_frame

	var protected_window = fixtures._windows[3]
	grenades._launch("frag", actor, from, Vector3.ZERO, 0.0, 0)
	for frame in 3:
		await physics_frame
	_check("A nearby grenade blast shatters exposed glass and leaves a farther window intact",
		window.broken and not protected_window.broken)
	grenades.reset_round()
	fixtures.reset_round()
	await physics_frame

	var oblique_blast := pane.to_global(Vector3(1.8, 0.0, 0.6))
	grenades._launch("frag", actor, oblique_blast, Vector3.ZERO, 0.0, 0)
	for frame in 3:
		await physics_frame
	_check("A blast at an oblique angle breaks glass visible past the jamb", window.broken)
	grenades.reset_round()
	fixtures.reset_round()


func _check_blast_damage(arena: Node3D) -> void:
	var fixtures := arena.get_node("Map/VillageFixtures")
	var actor: CharacterBody3D = arena.combatant(1)
	var grenades := arena.get_node("Grenades")
	var door = fixtures._doors[4]
	var portal: Transform3D = door.portal
	actor._apply_respawn("ak47", portal * Vector3(0, 0.04, -1.5), actor._spawn_revision + 1)
	var outside := portal * Vector3(0, 1.24, 2.1)
	await physics_frame
	grenades._launch("frag", actor, outside, Vector3.ZERO, 0.0, 0)
	for frame in 3:
		await physics_frame
	_check("A closed door shields the player from a grenade", is_equal_approx(actor.health, 100.0))
	fixtures._apply_door(door, true)
	await physics_frame
	grenades._launch("frag", actor, outside, Vector3.ZERO, 0.0, 0)
	for frame in 3:
		await physics_frame
	_check("An open doorway lets the same grenade damage the player", actor.health < 100.0)
	fixtures.reset_round()
	var window = fixtures._windows[2]
	var sill: Transform3D = window.sill
	actor._apply_respawn("ak47", sill * Vector3(0, -0.66, -1.45), actor._spawn_revision + 1)
	outside = sill * Vector3(0, 0.87, 2.15)
	await physics_frame
	grenades._launch("frag", actor, outside, Vector3.ZERO, 0.0, 0)
	for frame in 3:
		await physics_frame
	var glazed_damage: float = 100.0 - actor.health
	_check("A grenade damages the player through intact glass and shatters the pane", glazed_damage > 0.0 and window.broken)
	actor.health = 100.0
	grenades._launch("frag", actor, outside, Vector3.ZERO, 0.0, 0)
	for frame in 3:
		await physics_frame
	_check("An already broken window passes the same blast damage", glazed_damage > 0.0
		and is_equal_approx(100.0 - actor.health, glazed_damage))
	fixtures.reset_round()


func _check_market_loot(arena: Node3D) -> void:
	var loot := arena.get_node("Loot")
	var actor: Node = arena.combatant(1)
	var rewards := []
	for index in loot._market_crate_count:
		var at: Vector3 = loot._crates[index].position + Vector3.UP * 0.63
		var id: int = loot._next_id
		loot._open_crate(actor, index, at)
		var drop: Dictionary = loot._drops[id]
		rewards.append([drop.kind, drop.weapon, drop.amount])
	_check("Market crates provide a launcher, machine gun, vest and two medkits",
		rewards == [[loot.Kind.WEAPON, "launcher", 1], [loot.Kind.WEAPON, "m249", 75],
			[loot.Kind.ARMOR, "", 1], [loot.Kind.MEDKIT, "", 2]])
	loot.reset_round()


func _face(actor: CharacterBody3D, direction: Vector3) -> void:
	actor.rotation.y = atan2(-direction.x, -direction.z)
	actor.get_node("Camera3D").rotation.x = 0.0


func _interact() -> void:
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)


func _walk(walker: CharacterBody3D, target: Vector2) -> bool:
	for frame in 300:
		await physics_frame
		var delta := target - Vector2(walker.position.x, walker.position.z)
		if delta.length() < 0.12:
			return true
		var direction := delta.normalized()
		walker.velocity = Vector3(direction.x * 3.5, -1.0, direction.y * 3.5)
		walker.move_and_slide()
	print("Walker stopped at ", walker.position, " going to ", target)
	return false


func _check(label: String, success: bool) -> void:
	print("PASS " if success else "FAIL ", label)
	_failures += int(not success)
