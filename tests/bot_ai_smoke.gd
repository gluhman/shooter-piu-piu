extends SceneTree

const MapBuilder := preload("res://game/maps/map_builder.gd")
const OBSERVATION_SECONDS := 20.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(31842)
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await arena.start_solo(4, 1, 0, MapBuilder.DUST2_ID, Vector2i(0, 0), MapBuilder.DEFAULT_SIZE)
	var bots := get_nodes_in_group("bot")
	if bots.size() != 4:
		_fail("expected four bots on Dust II")
		return
	var starts: Dictionary = {}
	var ammunition: Dictionary = {}
	for bot in bots:
		starts[bot] = bot.global_position
		var ammo: Vector2i = bot.gun.ammo_counts()
		ammunition[bot] = ammo.x + ammo.y
	var damage_events := 0
	arena.damage_resolved.connect(func(_event: Dictionary) -> void: damage_events += 1)
	await create_timer(OBSERVATION_SECONDS).timeout
	var moved := 0
	var targets := 0
	var shots := 0
	for bot in get_nodes_in_group("bot"):
		if bot.global_position.distance_to(starts.get(bot, bot.global_position)) > 2.0:
			moved += 1
		if is_instance_valid(bot._target):
			targets += 1
		var ammo: Vector2i = bot.gun.ammo_counts()
		if ammo.x + ammo.y < ammunition.get(bot, ammo.x + ammo.y):
			shots += 1
	if moved < 3 or shots == 0:
		_fail("moved=%d damage_events=%d targets=%d fired=%d" % [moved, damage_events, targets, shots])
		return
	print("PASS bot AI normal-map smoke: moved=%d damage_events=%d targets=%d fired=%d" % [moved, damage_events, targets, shots])
	arena.queue_free()
	await create_timer(0.25).timeout
	quit()


func _fail(message: String) -> void:
	push_error("Bot AI smoke failed: " + message)
	quit(1)
