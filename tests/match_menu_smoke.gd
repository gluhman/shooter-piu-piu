extends SceneTree

const ARENA := "res://game/match/arena.tscn"

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	change_scene_to_file(ARENA)
	await scene_changed
	var arena := current_scene
	var lobby := arena.get_node("HUD/Lobby")
	var menu := arena.get_node("HUD/MatchMenu")
	var weapons := arena.get_node("HUD/WeaponSelect")
	await _click(lobby, "Настройки")
	for tab in ["Экран", "Графика", "Звук", "Управление"]:
		await _click(menu, tab)
		var tabs := menu.find_children("*", "TabContainer", true, false)
		_check(not tabs.is_empty() and str(tabs[0].get_current_tab_control().name) == tab, "settings tab " + tab)
	await _click(menu, "Назад")
	_check(lobby._frame.visible and not menu.visible, "settings return to main menu")
	lobby._ip.clear()
	await _click(lobby, "Подключиться")
	_check(lobby._status.text == "Введи IP хоста", "empty LAN address validation")
	await _click(lobby, "Играть одному")
	await _click(lobby, "Назад")
	_check(lobby.is_on_main(), "solo setup back")
	await _click(lobby, "Играть одному")
	lobby._solo_bots.value = 0
	await _click(lobby, "Начать матч")
	await _wait_for_match(arena)
	_check(weapons.visible, "initial loadout")
	await _escape()
	await _click(menu, "Начать раунд заново")
	_check(weapons.visible and not menu.visible and not paused, "restart before choosing loadout")
	await _click(weapons, "Снайпер")
	_check(weapons._specialization == "marksman", "class selection")
	await _click(weapons, "В бой")
	var player: Node = arena.combatant(1)
	_check(player.control_enabled and not weapons.visible, "enter match")
	var armory := InputEventAction.new()
	armory.action = &"open_armory"
	armory.pressed = true
	root.push_input(armory)
	await process_frame
	_check(weapons.visible and weapons._loadout_reconfigure, "open loadout during match")
	await _click(weapons, "Ближний бой")
	await _click(weapons, "В бой")
	_check(player.control_enabled and not weapons.visible and player.weapon_id == "shotgun", "apply new loadout during match")
	await _escape()
	await _click(menu, "Продолжить")
	_check(not menu.visible and not paused, "resume")

	player._hurt_lock = 0.0
	player.take_damage(999.0)
	await _settle()
	_check(player._dead and weapons.visible and weapons._for_respawn, "respawn loadout")
	await _escape()
	await _click(menu, "Выйти в главное меню")
	_check(weapons._panel.get_mouse_filter_with_override() == Control.MOUSE_FILTER_IGNORE,
		"exit dialog blocks clicks on the respawn loadout")
	await _click(menu, "Остаться")
	await _click(menu, "Продолжить")
	_check(weapons.visible and weapons._panel.get_mouse_filter_with_override() != Control.MOUSE_FILTER_IGNORE,
		"cancel exit restores respawn loadout")
	await _click(weapons, "В бой")
	for frame in 180:
		if not player._dead:
			break
		await create_timer(0.02).timeout
	_check(not player._dead and not weapons.visible, "respawn after cancelling exit")

	arena.net_finish("Проверка", [])
	await _click(menu, "Реванш")
	_check(not arena.round_finished() and not menu.visible and player.control_enabled, "rematch")
	arena.net_finish("Проверка", [])
	var next_map: OptionButton = menu.find_children("*", "OptionButton", true, false)[0]
	next_map.select(1)
	await _click(menu, "Начать на выбранной карте")
	await _wait_for_match(arena)
	_check(arena.map_id == 1 and not arena.round_finished() and weapons.visible, "next map")
	await _click(weapons, "В бой")
	await _escape()
	await _click(menu, "Выйти в лобби")
	_check(lobby.visible and not lobby.is_on_main() and not arena.has_started() and not paused, "return to solo lobby")

	await _click(lobby, "Начать матч")
	await _wait_for_match(arena)
	await _click(weapons, "В бой")
	player = arena.combatant(1)
	player._hurt_lock = 0.0
	player.take_damage(999.0)
	await _settle()
	await _escape()
	await _click(menu, "Выйти в главное меню")
	await _click(menu, "Выйти в главное меню")
	await _settle()
	var main := current_scene.get_node("HUD/Lobby")
	_check(not is_instance_valid(arena) and main.is_on_main() and main._music.playing and not paused,
		"confirmed exit opens a fresh main menu")
	_check(get_nodes_in_group("player").is_empty() and get_nodes_in_group("bot").is_empty(), "old match removed")
	await _click(main, "Играть одному")
	_check(not main.is_on_main(), "main menu buttons work after exit")
	var new_arena := current_scene
	main._solo_bots.value = 0
	await _click(main, "Начать матч")
	await _wait_for_match(new_arena)
	new_arena.net_finish("Проверка", [])
	var new_menu := new_arena.get_node("HUD/MatchMenu")
	await _escape()
	await _escape()
	_check(new_arena.round_finished() and not new_menu._confirming_exit, "escape cancels exit from results")
	await _click(new_menu, "Выйти в главное меню")
	await _click(new_menu, "Выйти в главное меню")
	await _settle()
	_check(not is_instance_valid(new_arena) and current_scene.get_node("HUD/Lobby").is_on_main() and not paused,
		"confirmed exit from results")
	quit(int(_failed))


func _wait_for_match(arena: Node) -> void:
	for frame in 600:
		if arena.has_started() and not arena.is_loading():
			return
		await process_frame
	_check(false, "match load timeout")


func _settle() -> void:
	await create_timer(0.30).timeout


func _click(where: Node, title: String) -> void:
	await _settle()
	for node: Button in where.find_children("*", "Button", true, false):
		if node.text != title or not node.is_visible_in_tree():
			continue
		var point := node.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = point
		root.push_input(motion, true)
		_check(root.gui_get_hovered_control() == node and not node.disabled, "click target " + title)
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			event.position = point
			root.push_input(event, true)
			await process_frame
		return
	_check(false, "missing button " + title)


func _escape() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	await process_frame


func _check(passed: bool, description: String) -> void:
	_failed = _failed or not passed
	print("PASS " if passed else "FAIL ", description)
