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
	print("BOT_DIFFICULTY_OK")
	arena.queue_free()
	await create_timer(0.25).timeout
	quit()


func _fail(message: String) -> void:
	push_error("Bot difficulty test failed: " + message)
	quit(1)
