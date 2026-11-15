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


func _exit_match() -> void:
	_arena.exit_to_lobby()
	await process_frame


func _check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	if not condition:
		_failures += 1
