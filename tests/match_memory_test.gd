extends SceneTree

const DUST_II := 4
const WORKSHOP := 5


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var cycles := int(args[0]) if not args.is_empty() else 12
	Engine.max_fps = 60
	AudioServer.set_bus_mute(0, true)
	var initial_audio_buses := AudioServer.bus_count
	_sample("initial", -1)
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	for cycle in cycles:
		seed(45821)
		var map := DUST_II if cycle % 2 == 0 else WORKSHOP
		await arena.start_solo(10, 1, 0, map, Vector2i.ZERO, 2)
		var player: CharacterBody3D = arena.combatant(1)
		if not player or get_nodes_in_group("bot").size() != 10:
			printerr("FAIL arena did not load")
			quit(1)
			return
		player._apply_equip("ak47")
		var grenades := arena.get_node("Grenades")
		for index in 8:
			player.gun._try_fire()
			var kind: String = ["frag", "flash", "smoke"][index % 3]
			grenades._launch(kind, player, Vector3(0, 2, 0), Vector3.ZERO, 0.01, 0)
			await create_timer(0.12).timeout
		_sample("active", cycle)
		arena._clear_match_map()
		await create_timer(0.25).timeout
		if not get_nodes_in_group("bot").is_empty() or not get_nodes_in_group("player").is_empty() \
				or arena.get_node("Map").get_child_count() != 0 or grenades.get_child_count() != 0 \
				or AudioServer.bus_count != initial_audio_buses or Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) != 0:
			printerr("FAIL match nodes survived cleanup")
			quit(1)
			return
		_sample("cleared", cycle)
	arena._loading = true
	arena.map_id = DUST_II
	arena._build_arena(45821)
	arena._reset_dedicated_room()
	await create_timer(1.0).timeout
	if arena.get_children().any(func(node: Node) -> bool: return node is NavigationRegion3D):
		printerr("FAIL cancelled navigation bake installed a region")
		quit(1)
		return
	print("PASS cancelled navigation bake")
	arena.queue_free()
	root.get_node("Net").leave_game()
	await create_timer(0.4).timeout
	_sample("freed", cycles)
	quit()


func _sample(phase: String, cycle: int) -> void:
	var result: Array = []
	OS.execute("/bin/ps", PackedStringArray(["-o", "rss=", "-p", str(OS.get_process_id())]), result)
	print("MEM ", JSON.stringify({
		"phase": phase,
		"cycle": cycle,
		"rss_kib": str(result[0]).strip_edges().to_int() if not result.is_empty() else 0,
		"static_bytes": OS.get_static_memory_usage(),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"audio_buses": AudioServer.bus_count,
	}))
