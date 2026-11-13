extends SceneTree

const Map := preload("res://game/maps/map_builder.gd")
const Balance := preload("res://game/combat/combat_balance.gd")
const Capsule := preload("res://game/actors/player_capsule.tres")
var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	root.grab_focus()
	await arena.start_solo(0, 1, 0, Map.OFFICE_ID, Vector2i.ZERO, 2)
	var map := arena.get_node("Map") as Node3D
	var fixtures := map.get_node("VillageFixtures")
	var actor: CharacterBody3D = arena.combatant(1)
	arena.get_node("HUD/WeaponSelect").hide_for_results()
	actor._apply_equip("ak47")
	await physics_frame
	await physics_frame
	_check("Office is small only", arena.map_size == 0 and arena.arena_width() == 20.0)
	_check("Minimap includes the office walls", map.minimap_outline().size() >= 18)
	_check("All eight doors start closed", fixtures._doors.size() == 8 and fixtures._doors.all(func(door): return not door.opened))
	var space := map.get_world_3d().direct_space_state
	var nav := map.get_world_3d().navigation_map
	var standing := PhysicsShapeQueryParameters3D.new()
	standing.shape = Capsule
	standing.collision_mask = Balance.WORLD_MASK
	var corners := {}
	for at: Vector3 in map._initial_spawns:
		var spawn := at
		standing.transform.origin = spawn + Vector3.UP * 0.85
		var clear := space.intersect_shape(standing, 1).is_empty()
		var path := NavigationServer3D.map_get_path(nav, spawn, Vector3(0, 0.10, -3.0), true)
		_check("Corner spawn has clearance and a route: %s" % spawn,
			clear and absf(spawn.x) > 4.5 and absf(spawn.z) > 4.5 and path.size() > 1
			and path[0].distance_to(spawn) < 0.40 and path[-1].distance_to(Vector3(0, 0.10, -3.0)) < 0.40)
		corners[Vector2(signf(spawn.x), signf(spawn.z))] = true
	_check("Spawns cover all four corner rooms", corners.size() == 4 and map.respawn_points.size() == 20)
	_check_table_legs()
	var door_damage := _check_door_penetration(arena, actor, fixtures._doors[4])
	for i in fixtures._doors.size():
		var door = fixtures._doors[i]
		_check("Door %d sweep clears office furniture" % i, _swing_clear(fixtures, door, space))
		var face: Vector3 = -door.portal.basis.z
		var opening: Vector3 = door.portal.origin
		actor.global_position = opening - face * 1.55 + Vector3.UP * 0.05
		actor.rotation.y = atan2(-face.x, -face.z)
		actor.get_node("Camera3D").rotation.x = -0.30
		actor.velocity = Vector3.ZERO
		await physics_frame
		await physics_frame
		arena.get_node("Loot")._update_prompt()
		_check("Door %d can be targeted" % i, fixtures.door_in_view(actor) == i)
		_press_interact()
		await physics_frame
		await physics_frame
		_check("Door %d opens with F" % i, door.opened)
	var damaged_leaf: StaticBody3D = fixtures._doors[4].leaf
	var damage_moved := true
	for index in door_damage.closed_hits.size():
		var hit: Vector4 = door_damage.cover.points[index]
		var moved_hit := damaged_leaf.to_global(Vector3(hit.x, hit.y, hit.z))
		damage_moved = damage_moved and moved_hit.distance_to(door_damage.closed_hits[index]) > 0.4
	_check("Holes and marks stay in the moving leaf's coordinates", damage_moved
		and door_damage.cover.moving_surface.material_override == door_damage.cover.materials[0])
	arena.net_restart()
	_check("Restart restores the unmarked pane", door_damage.cover.points.is_empty()
		and door_damage.cover.moving_surface.material_override == door_damage.cover.original_material)
	_check("Restart shuts all doors", fixtures._doors.all(func(door): return not door.opened))
	arena.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _check_door_penetration(arena: Node3D, actor: CharacterBody3D, door) -> Dictionary:
	var ballistics := arena.get_node("Ballistics")
	var face: Vector3 = -door.portal.basis.z
	var center: Vector3 = door.leaf.to_global(door.center)
	var space := arena.get_world_3d().direct_space_state
	var cover = arena.get_node("Map")._perforated[door.leaf.get_meta(&"bullet_cover_id")]
	var across: Vector3 = door.portal.basis.x
	for profile in ["ak47", "deagle", "shotgun"]:
		var offset := -0.19 if profile == "deagle" else (0.19 if profile == "shotgun" else 0.0)
		var aim := center + across * offset
		var eye := aim - face * 0.55
		var muzzle := aim - face * 0.22
		_check("%s trace hits the closed office door" % profile,
			space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, aim, Balance.WORLD_MASK)).get("collider") == door.leaf)
		ballistics.queue_shot(profile, actor.gun.WEAPONS[profile], actor,
			Transform3D(Basis.looking_at(face), muzzle), 0.15, eye, PackedVector3Array([face]))
		ballistics._physics_process(1.0 / 240.0)
		var crossed: bool = ballistics._shots.values().any(func(shot):
			return (shot.position - center).dot(face) > 0.06 and shot.damage_scale < 1.0)
		var strong: bool = profile == "ak47"
		var mark: Vector4 = cover.points[cover.points.size() - 1]
		_check("%s %s" % [profile, "perforates the closed door with reduced damage" if strong else "leaves a mark and stops"],
			crossed == strong and (mark.w > 0) == strong and not door.opened)
		ballistics.reset_round()
	var close_eye := center - face * 0.14
	var clipped_muzzle := center + face * 0.09
	ballistics.queue_shot("ak47", actor.gun.WEAPONS.ak47, actor,
		Transform3D(Basis.looking_at(face), clipped_muzzle), 0.15, close_eye, PackedVector3Array([face]))
	ballistics._physics_process(1.0 / 240.0)
	_check("A muzzle clipping the pane still resolves penetration through the closed door",
		ballistics._shots.values().any(func(shot): return (shot.position - center).dot(face) > 0.06 and shot.damage_scale < 1.0))
	ballistics.reset_round()
	var closed_hits := PackedVector3Array()
	for hit: Vector4 in cover.points:
		closed_hits.append(door.leaf.to_global(Vector3(hit.x, hit.y, hit.z)))
	return {"cover": cover, "closed_hits": closed_hits}


func _swing_clear(fixtures: Node3D, door, space: PhysicsDirectSpaceState3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var envelope := BoxShape3D.new()
	envelope.size = door.shape.size + Vector3(0.04, 0.0, 0.035)
	query.shape = envelope
	query.collision_mask = Balance.WORLD_MASK
	query.exclude = [door.leaf.get_rid()]
	for step in range(19):
		var hinge: Transform3D = fixtures._hinge_transform(door, step * PI / 36.0)
		query.transform = fixtures.global_transform * hinge.translated_local(door.center)
		for hit in space.intersect_shape(query, 16):
			if hit.collider.is_in_group(&"office_furniture"):
				print("Obstruction at ", hit.collider.position)
				return false
	return true


func _check_table_legs() -> void:
	var tops := get_nodes_in_group(&"office_tabletop")
	var legs := get_nodes_in_group(&"office_table_leg")
	var fitted := tops.size() == 3 and legs.size() == 12
	for leg: StaticBody3D in legs:
		var leg_shape := leg.find_children("*", "CollisionShape3D", false, false)[0] as CollisionShape3D
		var cap: float = leg.position.y + leg_shape.shape.size.y * 0.5
		var matches := false
		for top: StaticBody3D in tops:
			var top_shape := top.find_children("*", "CollisionShape3D", false, false)[0] as CollisionShape3D
			var half: Vector3 = top_shape.shape.size * 0.5
			var offset := leg.position - top.position
			if absf(offset.x) < half.x and absf(offset.z) < half.z:
				matches = absf(cap - (top.position.y - half.y)) < 0.001
				break
		fitted = fitted and matches
	_check("Table legs meet the underside without crossing the tabletop", fitted)


func _press_interact() -> void:
	var press := InputEventAction.new()
	press.action = &"interact"
	press.pressed = true
	root.push_input(press)
	var release := InputEventAction.new()
	release.action = &"interact"
	root.push_input(release)


func _check(label: String, passed: bool) -> void:
	if not passed:
		_failed = true
	print("PASS " if passed else "FAIL ", label)
