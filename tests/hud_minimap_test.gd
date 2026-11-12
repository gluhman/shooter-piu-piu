extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and DisplayServer.get_name() != "headless":
		var dimensions := args[1].split("x")
		var requested := Vector2i(int(dimensions[0]), int(dimensions[1]))
		var settings := root.get_node("GameSettings")
		settings.fullscreen = false
		settings.window_size = requested
		settings.apply_display()
		for frame in 6:
			await process_frame
		if not _check(root.size == requested, "requested window size applied"):
			return
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	await arena.start_solo(1, 1, 0, 4, Vector2i(1, 1), 2)
	var hud := arena.get_node("HUD")
	var minimap: Control = hud._minimap
	var player: CharacterBody3D = arena.combatant(1)
	var bot: CharacterBody3D = arena.combatant(0)
	player.set_physics_process(false)
	bot.set_physics_process(false)
	hud.get_node("WeaponSelect").hide_for_results()
	player.grant_weapon("ak47")
	player._apply_equip("ak47")
	player.grant_medkits(2)
	player.grant_grenades("flash", 2)
	player.health = 24
	hud._on_health(24, player.MAX_HEALTH)
	hud.get_node("Crosshair").show()
	await process_frame
	await process_frame
	if not _check(minimap.visible and not minimap._outline.is_empty(), "map is visible and contains geometry"):
		return
	if not _check(minimap._shots.is_empty(), "an idle enemy is hidden"):
		return
	bot._apply_equip("ak47")
	var fired: bool = bot.gun.fire_bot(bot.global_position + Vector3(0, 1.4, -30), 0.0)
	if not _check(fired and minimap._shots.has(bot.score_id()), "a real enemy shot reveals a marker"):
		return
	var shot: Vector3 = minimap._shots[bot.score_id()]
	bot.position.x += 3.0
	await process_frame
	if not _check(minimap._shots.get(bot.score_id()) == shot, "a marker stays at the shot position"):
		return
	var bounds := root.get_visible_rect()
	var blocks: Array[Control] = [minimap, hud._health_panel, hud._inventory_hud, hud.get_node("Ammo"), hud._score_panel]
	for i in blocks.size():
		var rect := blocks[i].get_global_rect()
		if not _check(blocks[i].visible and bounds.encloses(rect), "HUD block fits the viewport"):
			return
		for j in range(i):
			if not _check(not rect.intersects(blocks[j].get_global_rect()), "HUD blocks do not overlap"):
				return
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[0])
	await create_timer(1.0).timeout
	if not _check(minimap._shots.is_empty(), "the marker expires"):
		return
	arena.team_deathmatch = true
	bot.slot = player.slot
	hud.record_minimap_shot(bot.score_id(), bot.global_position)
	hud.record_minimap_shot(player.score_id(), player.global_position)
	if not _check(minimap._shots.is_empty(), "friendly and local shots stay hidden"):
		return
	hud.detach_local()
	if not _check(not minimap.visible and minimap._shots.is_empty(), "map hides when the player leaves"):
		return
	arena.queue_free()
	await create_timer(0.25).timeout
	print("HUD_MINIMAP_OK")
	quit()


func _check(passed: bool, message: String) -> bool:
	if not passed:
		printerr("HUD_MINIMAP_FAIL ", message)
		quit(1)
	return passed
