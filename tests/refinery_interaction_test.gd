extends SceneTree

const MAP := preload("res://game/maps/map_builder.gd")
const BALANCE := preload("res://game/combat/combat_balance.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var arena: Node3D = load("res://game/match/arena.tscn").instantiate()
	root.add_child(arena)
	root.grab_focus()
	await arena.start_solo(0, 1, 0, MAP.REFINERY_ID, Vector2i(5, 0), 2)
	var actor: CharacterBody3D = arena.combatant(1)
	arena.get_node("HUD/WeaponSelect").hide_for_results()
	actor._apply_equip("ak47")
	for frame in 4:
		await physics_frame
	var space := actor.get_world_3d().direct_space_state
	var gap := PhysicsRayQueryParameters3D.create(Vector3(13.1, 3.84, 1.6), Vector3(13.1, 3.84, 3), BALANCE.SHOT_WORLD_MASK)
	var bar := PhysicsRayQueryParameters3D.create(Vector3(13.1, 3.99, 1.6), Vector3(13.1, 3.99, 3), BALANCE.SHOT_WORLD_MASK)
	check(space.intersect_ray(gap).is_empty(), "shot ray passes through open rail bay")
	var hit := space.intersect_ray(bar)
	check(not hit.is_empty() and hit.collider.has_meta(&"ballistic_size"), "rail bar blocks ray and uses penetration metadata")
	if not hit.is_empty():
		var simulation := arena.get_node("Ballistics")
		var ballistics = simulation.get_script()
		var projectile = ballistics.Projectile.new()
		projectile.profile = "ak47"
		projectile.velocity = Vector3.BACK * ballistics.AMMO.ak47.speed
		projectile.remaining = 30.0
		var weak: Dictionary = simulation._redirect(projectile, hit, Vector3.BACK, ballistics.AMMO.shotgun.power, 0, space)
		var strong: Dictionary = simulation._redirect(projectile, hit, Vector3.BACK, ballistics.AMMO.ak47.power, 0, space)
		check(weak.is_empty() and strong.has("exit"), "rail penetration follows shell energy")
	var join_x := MAP.REFINERY.BRIDGE_JOIN_X
	var bridge := _floor(space, Vector3(join_x - 0.35, MAP.REFINERY.DECK, 0))
	var hillside := _floor(space, Vector3(join_x + 0.35, MAP.REFINERY.DECK, 0))
	check(bridge.get("collider") and hillside.get("collider")
		and bridge.collider.get_meta(&"impact_surface") == "metal"
		and hillside.collider.get_meta(&"impact_surface") == "concrete"
		and is_equal_approx(bridge.position.y, hillside.position.y),
		"bridge meets the hillside flush with separate surfaces")
	actor.global_position = Vector3(14.2, 3.46, 1.10)
	actor.rotation.y = PI
	actor.velocity = Vector3.ZERO
	for frame in 8:
		await physics_frame
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")
	for frame in 36:
		await physics_frame
	Input.action_release(&"jump")
	Input.action_release(&"move_forward")
	check(actor.global_position.z > 2.61, "standing jump clears bridge railing")
	var ladders := arena.get_node("Map/ArenaLadders")
	check(ladders.ladders.size() == 11, "tank and pipe rack ladders are registered")
	for ladder in ladders.ladders:
		actor.global_position = ladder.bottom + ladder.face * 0.42
		actor.velocity = Vector3.ZERO
		actor.rotation.y = atan2(ladder.face.x, ladder.face.z)
		actor.get_node("Camera3D").rotation.x = 0.0
		for frame in 4:
			await physics_frame
		var ascent: PackedVector3Array = ladders.route_in_view(actor)
		var label := "ladder at %s" % ladder.bottom
		check(actor.start_ladder_climb(ascent), label + " starts ascent")
		await wait_climb(actor)
		check(actor.global_position.distance_to(ladder.landing) < 0.14, label + " reaches landing")
		actor.rotation.y = atan2(-ladder.face.x, -ladder.face.z)
		actor.get_node("Camera3D").rotation.x = -0.60
		var descent: PackedVector3Array = ladders.route_in_view(actor)
		check(actor.start_ladder_climb(descent), label + " starts descent")
		await wait_climb(actor)
		check(actor.global_position.distance_to(ladder.bottom) < 0.14, label + " reaches foot")
	await check_pipe_walk(actor, space)
	arena.queue_free()
	await process_frame
	quit(int(failures != 0))


func check_pipe_walk(actor: CharacterBody3D, space: PhysicsDirectSpaceState3D) -> void:
	var rack_y := MAP.REFINERY.RACK_PIPE_Y + MAP.REFINERY.RACK_PIPE_RADIUS
	for side in [-1.0, 1.0]:
		var start := Vector3(7.0, rack_y + 0.08, side * MAP.REFINERY.RACK_Z + MAP.REFINERY.RACK_PIPE_OFFSETS[1])
		var support := _floor(space, start)
		check(not support.is_empty() and is_equal_approx(support.position.y, rack_y)
			and support.collider.get_meta(&"impact_surface") == "metal", "pipe crown supports movement")
		actor.global_position = start
		actor.rotation.y = PI * 0.5
		actor.velocity = Vector3.ZERO
		for frame in 6:
			await physics_frame
		Input.action_press(&"move_forward")
		for frame in 36:
			await physics_frame
		Input.action_release(&"move_forward")
		check(actor.is_on_floor() and actor.global_position.x < start.x - 2.0
			and absf(actor.global_position.y - rack_y) < 0.07, "can walk along either pipe rack")


func _floor(space: PhysicsDirectSpaceState3D, at: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at - Vector3.UP, BALANCE.WORLD_MASK)
	return space.intersect_ray(query)


func wait_climb(actor: CharacterBody3D) -> void:
	for frame in 960:
		if not actor.is_climbing_ladder():
			return
		await physics_frame


func check(ok: bool, label: String) -> void:
	failures += int(not ok)
	print("PASS " if ok else "FAIL ", label)
