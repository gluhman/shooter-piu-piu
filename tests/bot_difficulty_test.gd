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
	bot.global_position = Vector3(0, 20, 0)
	player.global_position = Vector3(0, 20, -8)
	bot.health = 50
	bot._engage_left = 1.0
	bot._strafe_left = 1.0
	var toward := (player.global_position - bot.global_position).normalized()
	var profile := {"preferred": 8.0, "delay": 1.0}
	bot.difficulty = 0
	var easy: Vector3 = bot._fight(player, profile, bot._difficulty_modifiers(), Vector2i(10, 20), 0.016)
	bot.difficulty = ELITE
	var elite: Vector3 = bot._fight(player, profile, bot._difficulty_modifiers(), Vector2i(10, 20), 0.016)
	if absf(easy.dot(toward)) > 0.05 or elite.dot(toward) >= -0.4:
		_fail("elite must retreat when wounded while easy keeps strafing")
		return
	print("BOT_DIFFICULTY_OK")
	arena.queue_free()
	await create_timer(0.25).timeout
	quit()


func _fail(message: String) -> void:
	push_error("Bot difficulty test failed: " + message)
	quit(1)
