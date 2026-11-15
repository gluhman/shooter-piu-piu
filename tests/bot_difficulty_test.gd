extends SceneTree

const MapBuilder := preload("res://game/maps/map_builder.gd")
const ELITE := 4


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await arena.start_solo(2, ELITE, 0, MapBuilder.DUST2_ID, Vector2i.ZERO, MapBuilder.DEFAULT_SIZE)
	var bots := get_nodes_in_group("bot")
	if arena.bot_difficulty != ELITE or bots.size() != 2:
		_fail("elite difficulty or bot count was not applied")
		return
	for bot in bots:
		if bot.difficulty != ELITE:
			_fail("elite difficulty was not passed to every bot")
			return
	var bot: CharacterBody3D = bots[0]
	var player: CharacterBody3D = arena.combatant(1)
	for actor in [bot, player, bots[1]]:
		actor.set_physics_process(false)
	for level in range(ELITE + 1):
		bot.difficulty = level
		var reaction := 0.5 * pow(0.8, level)
		var settling := 0.3 * pow(0.8, level)
		if not is_equal_approx(bot._reaction_time(), reaction) or not is_equal_approx(bot._stabilization_time(), settling):
			_fail("aim timings must decrease by 20 percent per level")
			return
		bot._aim_elapsed = -1.0
		bot.rotation.y = PI * 0.5
		if bot._track_aim(Vector3.FORWARD, 1.0 / 60.0) or not is_equal_approx(bot.rotation.y, PI * 0.5):
			_fail("the acquisition tick must start the turn at zero elapsed time")
			return
		if bot._track_aim(Vector3.FORWARD, reaction * 0.5) or absf(bot.rotation.y) < 0.1:
			_fail("aim snapped before the reaction time elapsed")
			return
		if bot._track_aim(Vector3.FORWARD, reaction * 0.5) or bot._aim_sway.length() > deg_to_rad(3.0):
			_fail("aim did not sway within its radius at the end of the turn")
			return
		var sway: Vector2 = bot._aim_sway
		if bot._track_aim(Vector3.FORWARD, settling * 0.5) or sway.is_equal_approx(bot._aim_sway) or bot._aim_sway.length() > deg_to_rad(1.5):
			_fail("aim must keep swaying with a shrinking radius while settling")
			return
		if not bot._track_aim(Vector3.FORWARD, settling * 0.5 + 0.001) or not bot._aim_sway.is_zero_approx() or absf(bot.rotation.y) > 0.001:
			_fail("aim did not settle onto the target")
			return
	bot._aim_elapsed = -1.0
	var primary: String = bot.weapon_id
	var sidearm: String = bot.weapon_in_slot("secondary")
	if sidearm.is_empty():
		_fail("bot spawned without a sidearm")
		return
	bot.gun.equip(primary, 0, 0)
	bot._choose_weapon(null)
	if bot.weapon_id != sidearm or bot.stock_for(primary) != Vector2i.ZERO:
		_fail("bot did not switch from an empty primary to its sidearm")
		return

	bot.global_position = Vector3(0, 20, 0)
	player.global_position = Vector3(0, 20, -8)
	bot.health = 50
	bot._strafe_left = 1.0
	var toward := (player.global_position - bot.global_position).normalized()
	var profile := {"preferred": 8.0, "delay": 1.0, "range": 30.0}
	bot.difficulty = 0
	var easy: Vector3 = bot._fight(player, profile, bot._difficulty_modifiers(), Vector2i(10, 20), 0.016)
	bot.difficulty = ELITE
	var elite: Vector3 = bot._fight(player, profile, bot._difficulty_modifiers(), Vector2i(10, 20), 0.016)
	if absf(easy.dot(toward)) > 0.05 or elite.dot(toward) >= -0.4:
		_fail("elite must retreat when wounded while easy keeps strafing")
		return
	# A respawn reuses the same player node. The previous aim must not carry over.
	bot.equip("ak47")
	bot.difficulty = 2
	bot._shoot_wait = 0.0
	bot._aim_elapsed = 1.0
	bot._aim_target_revision = player._spawn_revision
	player._apply_respawn("ak47", player.global_position, player._spawn_revision + 1)
	await physics_frame
	await physics_frame
	var ammo: Vector2i = bot.gun.ammo_counts()
	var step := 1.0 / Engine.physics_ticks_per_second
	var earliest_shot := ceili(0.512 / step)
	for tick in range(earliest_shot + 1):
		bot._fight(player, profile, bot._difficulty_modifiers(), ammo, step, false)
		var expected := ammo.x if tick < earliest_shot else ammo.x - 1
		if bot.gun.ammo_counts().x != expected:
			_fail("Hard bot fired before stabilization or failed to fire when settled (tick %d)" % tick)
			return
	print("BOT_DIFFICULTY_OK")
	arena.queue_free()
	await create_timer(0.25).timeout
	quit()


func _fail(message: String) -> void:
	push_error("Bot difficulty test failed: " + message)
	quit(1)
