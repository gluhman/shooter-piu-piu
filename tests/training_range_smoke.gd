extends SceneTree

const MapBuilder := preload("res://game/maps/map_builder.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await arena.start_solo(0, 1, 0, MapBuilder.TEST_RANGE_ID, Vector2i(1, 0), 0)
	var map := arena.get_node("Map") as MapBuilder
	var loot := arena.get_node("Loot")
	if arena.is_loading() or not arena.combatant(1) or not get_nodes_in_group("bot").is_empty() \
			or arena.map_size != MapBuilder.DEFAULT_SIZE or loot._crates.size() != 3 \
			or map.respawn_points.size() < 11 or map.initial_spawn(0).z <= 0.0:
		push_error("Training range did not start with its layout and a solo player")
		quit(1)
		return
	arena.net_clock(45)
	if not is_equal_approx(arena.get_node("WorldEnvironment").current_time, 13.01):
		push_error("Training range sky did not advance with the round clock")
		quit(1)
		return
	var player: Node = arena.combatant(1)
	var crate_at: Vector3 = loot._crates[0].position + Vector3.UP * 0.63
	loot._open_crate(player, 0, crate_at)
	var crate_drop: int = loot._crate_drop_ids[0]
	loot._clock += 29.0
	loot._physics_process(0.0)
	if loot._open[0] or loot._drops.has(crate_drop):
		push_error("Training range crate restored without clearing its item")
		quit(1)
		return
	print("PASS training range starts a solo match without bots")
	arena.queue_free()
	await create_timer(0.25).timeout
	quit()
