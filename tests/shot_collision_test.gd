extends SceneTree

const MAP := preload("res://game/maps/map_builder.gd")
const BALANCE := preload("res://game/combat/combat_balance.gd")
const LAYOUT := preload("res://game/maps/objective_layout.gd")
var _failures := 0
var _ballistics: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	_ballistics = arena.get_node("Ballistics")
	var map: Node3D = arena.get_node("Map")
	map.build(MAP.STATION_ID, 31562, MAP.SIZE_WIDTHS[1], LAYOUT.HILL, 1)
	map.objective_layout(LAYOUT.HILL, MAP.STATION_ID, 1)
	var loot: Node3D = arena.get_node("Loot")
	var placements: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(-8, 0, -8))]
	loot.build_crates(placements)
	await _sync_physics()
	var space := map.get_world_3d().direct_space_state
	var stairs: StaticBody3D
	for body in map.get_node("Station").get_children():
		if String(body.name).begins_with("Guardrail") and absf(body.global_basis.y.z) > 0.1:
			stairs = body
			break
	if not stairs:
		_check(false, "station stair rail exists")
	else:
		var detail: StaticBody3D = stairs.get_node("ShotGeometry")
		var post_a: Vector3 = detail.get_child(3).global_position
		var post_b: Vector3 = detail.get_child(4).global_position
		var gap := post_a.lerp(post_b, 0.5) - Vector3.UP * 0.15
		var across := stairs.global_basis.x * 0.24
		_check(_ray(space, gap - across, gap + across, BALANCE.WORLD_MASK).get("collider") == stairs,
			"stair guard still blocks movement")
		_check(_shot(space, gap - across, gap + across).is_empty(), "shot passes through railing gap")
		var bar: Vector3 = detail.get_child(1).global_position
		_check(_shot(space, bar - across, bar + across).get("collider") == detail, "shot hits the visible rail")
		_check(_shot(space, post_a - across, post_a + across).get("collider") == detail, "shot hits the visible post")
	var chest: StaticBody3D = get_first_node_in_group(&"hill_cover")
	var from := chest.to_global(Vector3(-0.9, 0.42, 0.12))
	var to := chest.to_global(Vector3(0.9, 0.42, 0.12))
	_check(_ray(space, from, to, BALANCE.WORLD_MASK).get("collider") == chest, "open chest keeps its movement blocker")
	_check(_shot(space, from, to).is_empty(), "shot clears empty space above the open chest")
	from = chest.to_global(Vector3(-0.9, -0.33, 0.0))
	to = chest.to_global(Vector3(0.9, -0.33, 0.0))
	_check(_shot(space, from, to).get("collider") == chest.get_node("ShotGeometry"), "shot hits the open chest wall")
	var crate: StaticBody3D = loot._crates[0]
	var lid: Node3D = loot._lids[0]
	var closed: Dictionary = _shot(space, crate.global_position + Vector3.UP * 1.15, crate.global_position + Vector3.UP * 0.025)
	_check(lid.is_ancestor_of(closed.get("collider")), "shot hits the closed supply crate lid")
	loot._set_open(0, true, true)
	await create_timer(0.36).timeout
	await _sync_physics()
	var open: Dictionary = _shot(space, crate.global_position + Vector3.UP * 1.15, crate.global_position + Vector3.UP * 0.025)
	var open_lid: Vector3 = lid.to_global(Vector3(-0.14, 0.01, 0.27))
	_check(open.is_empty() or not lid.is_ancestor_of(open.collider), "opening the crate clears the shot through its mouth")
	_check(lid.is_ancestor_of(_shot(space, open_lid + Vector3.RIGHT * 0.17, open_lid - Vector3.RIGHT * 0.17).get("collider")),
		"shot hits the supply crate lid in its new position")
	loot._set_open(0, false, false)
	await _sync_physics()
	_check(lid.is_ancestor_of(_shot(space, crate.global_position + Vector3.UP * 1.15,
		crate.global_position + Vector3.UP * 0.025).get("collider")), "reset restores the closed lid collision")
	arena.queue_free()
	await process_frame
	quit(1 if _failures else 0)


func _sync_physics() -> void:
	await physics_frame
	await physics_frame


func _shot(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = _ballistics.world_query()
	query.from = from
	query.to = to
	return space.intersect_ray(query)


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask))


func _check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		_failures += 1
