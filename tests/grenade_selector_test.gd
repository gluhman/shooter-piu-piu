extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
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
	print("GRENADE_SELECTOR_OK")
	arena.queue_free()
	quit()


func _check(passed: bool, message: String) -> bool:
	if not passed:
		printerr("GRENADE_SELECTOR_FAIL ", message)
		quit(1)
	return passed
