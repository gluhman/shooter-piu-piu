extends SceneTree

const MAP := preload("res://game/maps/map_builder.gd")
const BALANCE := preload("res://game/combat/combat_balance.gd")
const CAPSULE := preload("res://game/actors/player_capsule.tres")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	root.grab_focus()
	for size in MAP.SIZE_WIDTHS.size():
		await arena.start_solo(0, 1, 0, MAP.WORKSHOP_ID, Vector2i.ZERO, size)
		var width: float = arena.arena_width()
		var map := arena.get_node("Map") as Node3D
		var actor: CharacterBody3D = arena.combatant(1)
		arena.get_node("HUD/WeaponSelect").hide_for_results()
		actor._apply_equip("ak47")
		for frame in 4:
			await physics_frame
		_check_layout(map, width)
		var ladders := map.get_node("WorkshopLadders")
		_check("Each hall has two exterior ladders", ladders.ladders.size() == 4)
		for ladder in ladders.ladders:
			actor.global_position = ladder.bottom + ladder.face * 0.48
			actor.velocity = Vector3.ZERO
			_face(actor, -ladder.face, 0.0)
			for frame in 4:
				await physics_frame
			_check("Ground approach detects the ladder", not ladders.route_in_view(actor).is_empty())
			_press_interact()
			await physics_frame
			_check("Interact starts climbing", actor.is_climbing_ladder())
			await _wait_for_climb(actor)
			_check("Climb ends on a clear roof landing", actor.global_position.distance_to(ladder.landing) < 0.14)
			_face(actor, ladder.face, -0.60)
			await physics_frame
			_press_interact()
			await physics_frame
			_check("Interact starts descent", actor.is_climbing_ladder())
			await _wait_for_climb(actor)
			_check("Descent ends at the foot of the ladder", actor.global_position.distance_to(ladder.bottom) < 0.14)
		arena._clear_match_map()
		await process_frame
	arena.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _check_layout(map: Node3D, width: float) -> void:
	var space := map.get_world_3d().direct_space_state
	var nav := map.get_world_3d().navigation_map
	var scale_factor := width / 70.0
	var overlap := PhysicsShapeQueryParameters3D.new()
	overlap.shape = CAPSULE
	overlap.collision_mask = BALANCE.WORLD_MASK
	var floor_ray := PhysicsRayQueryParameters3D.new()
	floor_ray.collision_mask = BALANCE.WORLD_MASK
	var clear: bool = map._initial_spawns.size() == 20
	var reachable := true
	var screened := true
	for point: Vector3 in map._initial_spawns:
		overlap.transform.origin = point + Vector3.UP * 0.86
		floor_ray.from = point
		floor_ray.to = point - Vector3.UP
		clear = clear and space.intersect_shape(overlap, 1).is_empty() and not space.intersect_ray(floor_ray).is_empty()
		floor_ray.from = Vector3(0, 1.55, 0)
		floor_ray.to = point + Vector3.UP * 1.37
		if space.intersect_ray(floor_ray).is_empty():
			screened = false
			print("Exposed spawn at ", point)
		var path := NavigationServer3D.map_get_path(nav, point, Vector3(0, 0.1, 0), true)
		reachable = reachable and path.size() > 1 and path[0].distance_to(point) < 0.6 and path[-1].length() < 0.65
	_check("All 20 spawn points have clearance and ground at %d m" % width, clear)
	_check("All spawn points have a path to the central lane at %d m" % width, reachable)
	_check("All spawn points have cover from the center at %d m" % width, screened)
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			var from := Vector3(side * 15.0 * scale_factor, 0.12, end * 16.0 * scale_factor)
			var target := Vector3(side * 15.0 * scale_factor, 0.12, 0)
			var path := NavigationServer3D.map_get_path(nav, from, target, true)
			_check("Both loading entrances connect to each hall", path.size() > 1
				and path[0].distance_to(from) < 0.5 and path[-1].distance_to(target) < 0.6)


func _face(actor: CharacterBody3D, direction: Vector3, pitch: float) -> void:
	actor.rotation.y = atan2(-direction.x, -direction.z)
	actor.get_node("Camera3D").rotation.x = pitch


func _press_interact() -> void:
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)


func _wait_for_climb(actor: CharacterBody3D) -> void:
	for frame in 280:
		if not actor.is_climbing_ladder():
			return
		await physics_frame


func _check(label: String, passed: bool) -> void:
	print("PASS " if passed else "FAIL ", label)
	if not passed:
		_failures += 1
