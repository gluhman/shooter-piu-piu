extends SceneTree

const LAYOUT := preload("res://game/maps/objective_layout.gd")
const TACTICS := preload("res://game/actors/objective_tactics.gd")
var _failures := 0
var _arena: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(93378)
	AudioServer.set_bus_mute(0, true)
	_arena = (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(_arena)
	await _ctf_against_visible_player(1)
	await _ctf_against_visible_player(4)
	await _hold_hill()
	await _attack_occupied_hill()
	await _plant_charge()
	await _flank_after_death()
	await _leave_village_house(false)
	await _leave_village_house(true)
	await _advance_between_cover()
	_check(TACTICS.REPLAN_SECONDS[4] < TACTICS.REPLAN_SECONDS[1] and TACTICS.FLANK_SAMPLES[4] > TACTICS.FLANK_SAMPLES[1],
		"higher difficulty considers more routes and replans sooner")
	_arena.queue_free()
	await process_frame
	print("Objective bot failures: ", _failures)
	quit(1 if _failures else 0)


func _start(mode: int, difficulty: int, arena: int) -> Node3D:
	await _arena.start_solo(1, difficulty, 0, arena, Vector2i.ZERO, 1, true, false, -1, mode)
	var player: CharacterBody3D = _arena.combatant(1)
	player.choose_loadout("ak47", "m1911", "frag")
	player.set_physics_process(false)
	player._hurt_lock = 1000.0
	_arena.get_node("HUD/WeaponSelect").hide_for_results()
	await create_timer(0.35).timeout
	return _arena.combatant(0)


func _ctf_against_visible_player(difficulty: int) -> void:
	var bot := await _start(LAYOUT.FLAG, difficulty, 2)
	var obj: Node3D = _arena.objectives
	var player: CharacterBody3D = _arena.combatant(1)
	var nav := bot.get_world_3d().navigation_map
	var route := NavigationServer3D.map_get_path(nav, bot.global_position, obj.centers[0], true)
	_check(route.size() > 1, "steal route exists")
	if route.size() < 2:
		await _exit_match()
		return
	var seen := false
	var carried := false
	for frame in 60 * 42:
		if frame % 8 == 0:
			var side := -bot.global_basis.z
			# Keep a visible target near the route and outside the bot's physical path.
			player.global_position = bot.global_position + side * 3.7 + side.cross(Vector3.UP) * 1.55
		await physics_frame
		seen = seen or bot._target == player
		carried = carried or obj.rules.flags[0].carrier == bot
		if obj.scores.y > 0:
			break
	_check(seen and carried and obj.scores.y > 0, "difficulty %d steals and scores while tracking a player" % difficulty)
	await _exit_match()


func _hold_hill() -> void:
	var bot := await _start(LAYOUT.HILL, 4, 2)
	var obj: Node3D = _arena.objectives
	var covered := false
	for frame in 60 * 22:
		await physics_frame
		if obj.in_zone(bot, 0) and bot.crouched and bot._objective_tactics.cover:
			covered = true
			break
	if not covered:
		print("Hill diagnostics ", {"at": bot.global_position, "goal": bot._objective_tactics.destination,
			"cover": bot._objective_tactics.cover, "crouched": bot.crouched, "center": obj.centers[0],
			"order": obj.bot_order(bot), "team": obj.rules.team})
	_check(covered and bot._objective_tactics.kind == "hold", "bot crouches in cover while standing inside the hill")
	await _exit_match()


func _attack_occupied_hill() -> void:
	var bot := await _start(LAYOUT.HILL, 4, 2)
	var obj: Node3D = _arena.objectives
	var holder: CharacterBody3D = _arena.combatant(1)
	holder.global_position = obj.centers[0] + Vector3.UP * 0.05
	holder._hurt_lock = 0.0
	holder.health = 1000.0
	var assaulted := false
	var flanked := false
	for frame in 60 * 20:
		await physics_frame
		assaulted = assaulted or bot._objective_tactics.kind == "assault"
		flanked = flanked or bot._objective_tactics.flank.is_finite()
		if assaulted and obj.in_zone(bot, 0):
			break
	_check(assaulted and obj.in_zone(bot, 0), "elite bot switches to assault and reaches an occupied hill")
	_check(flanked, "elite bot picks a flank when the approach offers one")
	await _exit_match()


func _plant_charge() -> void:
	var bot := await _start(LAYOUT.DEFUSE, 3, 4)
	var obj: Node3D = _arena.objectives
	obj.rules.attack = bot.team_id()
	obj.rules.carrier = bot
	obj.rules.carrier_assigned = true
	var planted := false
	var defender: Node = _arena.combatant(1)
	for frame in 60 * 28:
		defender._hurt_lock = 1000.0
		await physics_frame
		if obj.state.get("phase", 0) == 2:
			planted = true
			break
	if not planted:
		print("Defuse diagnostics ", {"at": bot.global_position, "goal": bot._objective_tactics.destination,
			"order": obj.bot_order(bot), "phase": obj.rules.phase, "carrier": obj.rules.carrier,
			"site": obj.centers[0], "grounded": obj.grounded(bot), "hold": obj.rules.hold_ticks,
			"alive": bot.health, "time": obj.left})
	_check(planted, "attacking bot travels to a site and holds Interact to plant")
	await _exit_match()


func _flank_after_death() -> void:
	var bot := await _start(LAYOUT.HILL, 4, 2)
	bot.set_physics_process(false)
	var nav: RID = bot._navigation.get_navigation_map()
	var goal: Vector3 = _arena.objectives.centers[0]
	var route := NavigationServer3D.map_get_path(nav, bot.global_position, goal, true)
	if route.size() < 2:
		_check(false, "bot has a route to the hill before being killed")
		await _exit_match()
		return
	var from := route[-2]
	var direction := from.direction_to(route[-1])
	var death := from.lerp(route[-1], 0.48)
	bot.global_position = death
	bot._last_approach = direction
	bot._hurt_lock = 0.0
	bot.take_damage(1000.0, 1)
	var revision: int = bot._spawn_revision
	for frame in 60 * 10:
		if bot._spawn_revision > revision:
			break
		await physics_frame
	var tactics: RefCounted = bot._objective_tactics
	_check(bot.health > 0 and tactics._death.is_equal_approx(death), "bot remembers the kill location through the respawn wave")
	bot.global_position = route[0]
	var eye := goal + Vector3.UP * 1.45
	var side: Vector3 = tactics.route_after_death(bot, goal, eye, 0.016)
	var first := NavigationServer3D.map_get_path(nav, route[0], side, true)
	var second := NavigationServer3D.map_get_path(nav, side, goal, true)
	_check(side != goal and tactics._death_risk(first) + tactics._death_risk(second) < tactics._death_risk(route),
		"respawned bot takes a reachable flank with less exposure to the kill location")
	bot.global_position = side
	_check(tactics.route_after_death(bot, goal, eye, 0.016) == goal, "bot resumes the objective after the detour")
	bot.restart_round()
	_check(not tactics._death.is_finite(), "round restart clears the remembered kill location")
	await _exit_match()


func _leave_village_house(jammed: bool) -> void:
	var bot := await _start(LAYOUT.FLAG, 4, 3)
	var obj: Node3D = _arena.objectives
	obj.set_physics_process(false)
	var fixtures := _arena.get_node("Map/VillageFixtures")
	var door = fixtures._doors[5]
	var portal: Transform3D = door.portal
	var player: Node3D = _arena.combatant(1)
	player.global_position = portal.origin + Vector3.UP * 15.0
	var start := portal * Vector3(0, 0.065, -0.91 if jammed else -1.85)
	var goal := portal * Vector3(0, 0.08, 2.15)
	obj.centers[0] = goal
	obj.rules.flags[0].at = goal
	bot.global_position = start
	bot.velocity = Vector3.ZERO
	bot._reset_behavior()
	if jammed:
		for side in [-1.0, 1.0]:
			var blocker := StaticBody3D.new()
			blocker.collision_layer = _arena.Balance.MOVEMENT_CAPSULE_MASK
			var shape := SphereShape3D.new()
			shape.radius = 0.21
			var collision := CollisionShape3D.new()
			collision.shape = shape
			blocker.add_child(collision)
			fixtures.add_child(blocker)
			blocker.global_position = portal * Vector3(-0.14, 0.95, -0.17 + side * 0.71)
	var took_window := false
	for frame in 60 * 16:
		await physics_frame
		took_window = took_window or bot._window_jumping
		if bot.global_position.distance_to(goal) < 0.9:
			break
	if jammed:
		_check(took_window and fixtures._windows.any(func(window): return window.broken)
			and bot.global_position.distance_to(goal) < 0.9,
			"bot breaks a window and jumps out when both door swings are blocked")
	else:
		_check(door.opened and bot.global_position.distance_to(goal) < 0.9,
			"bot opens the house door and walks out along its objective route")
	if bot.global_position.distance_to(goal) >= 0.9:
		print("House exit diagnostics ", {"jammed": jammed, "at": bot.global_position,
			"goal": goal, "route": bot._window_route, "failed_window": bot._failed_window,
			"failed_route": bot._failed_route, "door": door.swing, "jumped": took_window})
		if jammed:
			var nav: RID = bot._navigation.get_navigation_map()
			print("Window plan from original position ", fixtures.bot_window_route(bot, nav, goal, bot._failed_route, -1))
			for window in fixtures._windows:
				var sill: Transform3D = window.sill
				if sill.origin.distance_to(start) < 6.0:
					var entry: Vector3 = fixtures._window_feet(sill, signf((sill.affine_inverse() * start).z))
					var exit: Vector3 = fixtures._window_feet(sill, -signf((sill.affine_inverse() * start).z))
					var route := NavigationServer3D.map_get_path(nav, start, entry, true) if entry.is_finite() else PackedVector3Array()
					print("Window near house ", {"sill": sill.origin, "entry": entry, "exit": exit, "path": route})
	await _exit_match()


func _advance_between_cover() -> void:
	var bot := await _start(LAYOUT.FLAG, 4, 2)
	bot.set_physics_process(false)
	var obj: Node3D = _arena.objectives
	obj.set_physics_process(false)
	var player: CharacterBody3D = _arena.combatant(1)
	var goal: Vector3 = obj.centers[0]
	var nav: RID = bot._navigation.get_navigation_map()
	var path := NavigationServer3D.map_get_path(nav, bot.global_position, goal, true)
	if path.size() < 2:
		_check(false, "bot has a flag route before taking fire")
		await _exit_match()
		return
	var spot := Vector3.INF
	var direct := TACTICS.new()
	for index in range(1, path.size()):
		var start := path[index - 1].lerp(path[index], 0.25)
		var forward := start.direction_to(path[index])
		bot.global_position = start
		for wing in [-1.0, 1.0]:
			player.global_position = NavigationServer3D.map_get_closest_point(nav, start + forward.cross(Vector3.UP) * wing * 8.0)
			spot = direct._choose_advance_cover(bot, goal, player.aim_center(), 4, true, false)
			if spot.is_finite():
				break
		if spot.is_finite():
			break
	if not spot.is_finite():
		_check(false, "flag approach has a nearby forward cover position")
		await _exit_match()
		return
	var original: Vector3 = bot.global_position
	bot.cancel_spawn_protection()
	bot.take_damage(16.0, 1)
	var mods: Dictionary = bot._difficulty_modifiers()
	bot._play_objective(obj, player, bot.FIRE[bot.weapon_id], mods, bot.gun.ammo_counts(), 1.0 / 60.0)
	var chosen: Vector3 = bot._objective_tactics._advance_cover
	var eye: Vector3 = player.aim_center()
	_check(bot._under_fire_left > 0.0 and chosen.is_finite() and not chosen.is_equal_approx(goal)
		and direct._near_cover(bot.get_world_3d().direct_space_state, chosen, eye),
		"enemy damage redirects the flag runner to cover")
	if chosen.is_finite():
		bot.global_position = chosen
		bot._objective_tactics.advance_under_fire(bot, goal, eye, true, true, 1.0)
		var next: Vector3 = bot._objective_tactics.advance_under_fire(bot, goal, eye, true, true, 1.0)
		var before: float = direct._path_length(NavigationServer3D.map_get_path(nav, chosen, goal, true), goal)
		var after: float = direct._path_length(NavigationServer3D.map_get_path(nav, next, goal, true), goal)
		_check(after < before and not next.is_equal_approx(original), "runner leaves cover for a better position nearer the flag")
		var blocked := original.lerp(goal, 0.25)
		var route := NavigationServer3D.map_get_path(nav, original, goal, true)
		if route.size() > 1:
			blocked = route[0].lerp(route[1], 0.55)
		bot.global_position = original
		var detour: Vector3 = direct.route_around_obstruction(bot, goal, blocked)
		var first := NavigationServer3D.map_get_path(nav, original, detour, true) if detour.is_finite() else PackedVector3Array()
		var second := NavigationServer3D.map_get_path(nav, detour, goal, true) if detour.is_finite() else PackedVector3Array()
		_check(detour.is_finite() and direct._point_risk(first, blocked) + direct._point_risk(second, blocked) < direct._point_risk(route, blocked),
			"blocked route is replaced by a viable detour with less overlap")
	await _exit_match()


func _exit_match() -> void:
	_arena.exit_to_lobby()
	await process_frame


func _check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	if not condition:
		_failures += 1
