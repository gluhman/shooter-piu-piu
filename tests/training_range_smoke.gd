extends SceneTree

const MapBuilder := preload("res://game/maps/map_builder.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await arena.start_solo(0, 1, 0, MapBuilder.TEST_RANGE_ID, Vector2i(1, 0), MapBuilder.DEFAULT_SIZE)
	var map := arena.get_node("Map") as MapBuilder
	if arena.is_loading() or not arena.combatant(1) or not get_nodes_in_group("bot").is_empty() \
			or map.respawn_points.size() < 10 or map.initial_spawn(0).z <= 0.0:
		push_error("Training range did not start with its layout and a solo player")
		quit(1)
		return
	arena.net_clock(45)
	if not is_equal_approx(arena.get_node("WorldEnvironment").current_time, 12.01):
		push_error("Training range sky did not advance with the round clock")
		quit(1)
		return
	print("PASS training range starts a solo match without bots")
	arena.queue_free()
	await create_timer(0.25).timeout
	quit()
