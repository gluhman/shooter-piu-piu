extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings := root.get_node("GameSettings")
	var legacy := ConfigFile.new()
	legacy.set_value("controls", "bindings_version", 1)
	legacy.set_value("bindings", "throw_grenade", KEY_C)
	legacy.set_value("bindings", "throw_frag", KEY_G)
	legacy.set_value("bindings", "select_grenade", KEY_3)
	settings._migrate_bindings(legacy)
	if not _check(not legacy.has_section_key("bindings", "throw_grenade")
			and not legacy.has_section_key("bindings", "throw_frag")
			and legacy.get_value("bindings", "select_grenade") == KEY_3,
			"legacy default throw moves to G and selection stays unchanged"):
		return
	legacy.set_value("bindings", "throw_grenade", KEY_P)
	settings._migrate_bindings(legacy)
	if not _check(legacy.get_value("bindings", "throw_grenade") == KEY_P, "custom shared binding is preserved"):
		return
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await arena.start_solo(0, 1, 0, 4, Vector2i(1, 1), 0)
	var player: Variant = arena.combatant(1)
	if not _check(InputMap.has_action(&"select_grenade"), "grenade selection action is registered"):
		return
	player._grenades.clear()
	player._grenades["flash"] = 2
	player._grenades["smoke"] = 1
	if not _check(player.select_grenade("smoke"), "available grenade can be selected"):
		return
	if not _check(player.carried_grenade() == "smoke", "selected grenade is used by the throw action"):
		return
	if not _check(player.available_grenade_ids() == ["flash", "smoke"], "multiple grenade types remain in inventory"):
		return
	player.cycle_grenade()
	if not _check(player.carried_grenade() == "flash", "selector cycles through available grenade types"):
		return
	if not _check(not player.select_grenade("frag"), "unavailable grenade cannot be selected"):
		return
	for action in [&"throw_frag", &"throw_flash", &"throw_smoke"]:
		if not _check(not InputMap.has_action(action), "direct throw action removed"):
			return
	if not _check(settings.ACTIONS[&"throw_grenade"][1] == KEY_G, "G is the default shared throw"):
		return
	if DisplayServer.get_name() != "headless":
		player.control_enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var grenades := arena.get_node("Grenades")
		for kind in ["flash", "smoke", "concussion", "frag"]:
			player._throw_wait = 0.0
			player._grenades[kind] = 1
			player.select_grenade(kind)
			_throw_event(player, true)
			if kind == "frag":
				await physics_frame
				await physics_frame
				if not _check(grenades._cooking.has(player.score_id()), "holding G keeps the frag in hand"):
					return
			_throw_event(player, false)
			await physics_frame
			await physics_frame
			var launched: bool = grenades._flights.values().any(func(flight) -> bool: return flight.kind == kind)
			if not _check(launched and player.grenade_stock(kind) == 0, "shared throw launches " + kind):
				return
	print("GRENADE_SELECTOR_OK")
	arena.queue_free()
	quit()


func _throw_event(player: Node, pressed: bool) -> void:
	var event: InputEvent = InputMap.action_get_events(&"throw_grenade")[0].duplicate()
	event.pressed = pressed
	player._unhandled_input(event)


func _check(passed: bool, message: String) -> bool:
	if not passed:
		printerr("GRENADE_SELECTOR_FAIL ", message)
		quit(1)
	return passed
