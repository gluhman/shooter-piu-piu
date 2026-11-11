extends Node3D

const PLAYER_SCENE := preload("res://player.tscn")
const BOT_SCRIPT := preload("res://bot.gd")
const MAP_NAMES := preload("res://map_builder.gd").MAP_NAMES
const WEAPON_SET_NAMES := ["Любое", "Только дробовики", "Пистолеты, винтовки и пулемёты"]
const POSE_INTERVAL := 1.0 / 30.0
const DIFFICULTY_NAMES := ["Легко", "Обычно", "Сложно"]
const WEAPON_SETS := [
	["deagle", "shotgun", "ak47", "launcher", "m249", "m14", "m1"],
	["shotgun"],
	["deagle", "ak47", "m249", "m14", "m1"],
]

var map_id := 0
var weapon_set := 0
var round_limits := Vector2i.ZERO
var _layout_seed := 0
var player_slots := PackedInt32Array()
var _display_names: Dictionary[int, String] = {}

var _reloading := false
var _started := false
var _ready_peers: Array[int] = []
var _pose_time := 0.0
var _round_time := 0.0
var _clock_seconds := -1
var _round_finished := false
var _winner := ""
var _winning_score := 0


func _ready() -> void:
	player_slots.resize(Net.MAX_PLAYERS)
	player_slots[0] = 1
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Net.joined.connect(_on_joined)
	Net.connection_failed.connect(_on_connection_failed)
	Net.host_lost.connect(_reload_main_menu)
	GameSettings.graphics_changed.connect(_apply_graphics)
	_apply_graphics()


func _apply_graphics() -> void:
	$Sun.shadow_enabled = GameSettings.shadows
	$WorldEnvironment.environment.ssao_enabled = GameSettings.ambient_occlusion


func match_peers() -> Array[int]:
	return _ready_peers


func player_label(slot: int) -> String:
	var alias: String = _display_names.get(player_slots[slot], "")
	if not alias.is_empty():
		return alias
	return "Хост" if slot == 0 else "Игрок %d" % (slot + 1)


func set_local_display_name(value: String) -> void:
	Net.remember_display_name(value)
	if not Net.active:
		return
	if multiplayer.is_server():
		_set_display_name(1, Net.display_name)
	elif Net.client_session:
		net_set_display_name.rpc_id(1, Net.display_name)


@rpc("any_peer", "reliable")
func net_set_display_name(value: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if Net.active and multiplayer.is_server() and multiplayer.get_peers().has(sender):
		_set_display_name(sender, Net.clean_display_name(value))


func _set_display_name(peer: int, alias: String) -> void:
	if _display_names.get(peer, "") == alias:
		return
	if alias.is_empty():
		_display_names.erase(peer)
	else:
		_display_names[peer] = alias
	if _started:
		for guest in _ready_peers:
			net_display_names.rpc_id(guest, _display_names)
	else:
		_send_room_state()


@rpc("authority", "reliable")
func net_display_names(names: Dictionary[int, String]) -> void:
	_display_names = names


func has_started() -> bool:
	return _started


func round_finished() -> bool:
	return _round_finished


func input_blocked() -> bool:
	return _round_finished or $HUD/MatchMenu.visible


func allows_weapon(id: String) -> bool:
	return id in WEAPON_SETS[weapon_set]


func random_weapon(exclude: String = "") -> String:
	var choices: Array = WEAPON_SETS[weapon_set].duplicate()
	if choices.size() > 1:
		choices.erase(exclude)
	return choices.pick_random()


func combatant(id: int) -> Node:
	return get_node_or_null("Bot%d" % -id if id <= 0 else str(id))


func can_restart() -> bool:
	return _started and (Net.solo or (Net.active and multiplayer.is_server()))


func restart_round() -> void:
	if not can_restart():
		return
	for peer in _ready_peers:
		net_restart.rpc_id(peer)
	net_restart()


func leave_round() -> void:
	Net.leave_game()
	_reload_main_menu()


func _reload_main_menu() -> void:
	if _reloading:
		return
	_reloading = true
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


@rpc("authority", "reliable")
func net_restart() -> void:
	$HUD/MatchMenu.clear_round_result()
	_reset_round_clock()
	$Ballistics.reset_round()
	$Grenades.reset_round()
	$Map.clear_bullet_holes()
	$HUD.reset_round()
	$Loot.reset_round()
	for player in get_tree().get_nodes_in_group("player"):
		player.restart_round()
	for bot in get_tree().get_nodes_in_group("bot"):
		bot.restart_round()


@rpc("authority", "reliable")
func net_score_snapshot(scores: Dictionary) -> void:
	$HUD.apply_score_snapshot(scores)


func start_solo(bot_count: int, difficulty: int, weapons: int, arena: int, limits: Vector2i = Vector2i.ZERO) -> void:
	if _started or Net.active:
		return
	Net.play_solo()
	weapon_set = weapons
	map_id = arena
	round_limits = limits
	_reset_round_clock()
	$Loot.build_crates($Map.build(map_id, randi()))
	_spawn_bots(clampi(bot_count, 1, 10), difficulty)
	_started = true
	_spawn_player(1, 0)


func update_host_rules(weapons: int, arena: int, limits: Vector2i = Vector2i.ZERO) -> void:
	if _started or not Net.active or not multiplayer.is_server():
		return
	weapon_set = weapons
	map_id = arena
	round_limits = limits
	_send_room_state()


func start_host_match() -> void:
	if _started or not Net.active or not multiplayer.is_server():
		return
	_layout_seed = randi()
	_begin_network_match(weapon_set, map_id, player_slots, _layout_seed, round_limits)
	for peer in player_slots:
		if peer > 1:
			net_begin.rpc_id(peer, weapon_set, map_id, player_slots, _layout_seed, round_limits)
	if player_slots.count(0) == Net.MAX_PLAYERS - 1:
		$HUD.show_host_ip(Net.lan_addresses())


func _send_room_state() -> void:
	$HUD/Lobby.refresh_room()
	for peer in player_slots:
		if peer > 1:
			net_room_state.rpc_id(peer, weapon_set, map_id, player_slots, round_limits, _display_names)


@rpc("authority", "reliable")
func net_room_state(weapons: int, arena: int, roster: PackedInt32Array, limits: Vector2i,
		names: Dictionary[int, String]) -> void:
	if _started:
		return
	weapon_set = weapons
	map_id = arena
	round_limits = limits
	player_slots = roster
	_display_names = names
	$HUD/Lobby.refresh_room()


@rpc("authority", "reliable")
func net_begin(weapons: int, arena: int, roster: PackedInt32Array, layout_seed: int, limits: Vector2i) -> void:
	if not _started:
		_begin_network_match(weapons, arena, roster, layout_seed, limits)
		net_ready.rpc_id(1)


func _begin_network_match(weapons: int, arena: int, roster: PackedInt32Array, layout_seed: int, limits: Vector2i) -> void:
	weapon_set = weapons
	map_id = arena
	player_slots = roster
	round_limits = limits
	_reset_round_clock()
	$Loot.build_crates($Map.build(map_id, layout_seed))
	_spawn_bots(1, 1)
	_started = true
	for slot in player_slots.size():
		if player_slots[slot] != 0:
			_spawn_player(player_slots[slot], slot)


func _spawn_bots(count: int, difficulty: int) -> void:
	for index in count:
		var bot := PLAYER_SCENE.instantiate()
		bot.set_script(BOT_SCRIPT)
		bot.name = "Bot%d" % index
		bot.combatant_id = -index
		bot.position = $Map.BOT_SPAWNS[index]
		bot.spawn_position = bot.position
		bot.patrol_route = $Map.PATROL_ROUTES[map_id]
		bot.difficulty = difficulty
		bot.floor_snap_length = 0.2
		add_child(bot)
		if not Net.active or multiplayer.is_server():
			bot.equip(random_weapon())


func announce(killer_id: int, victim_id: int) -> void:
	if _round_finished:
		return
	for peer in _ready_peers:
		net_frag.rpc_id(peer, killer_id, victim_id)
	net_frag(killer_id, victim_id)
	if round_limits.y > 0 and killer_id != victim_id and $HUD.kills_for(killer_id) >= round_limits.y:
		var winner := combatant(killer_id)
		if winner:
			_finish_round(_combatant_label(winner), $HUD.kills_for(killer_id))


@rpc("authority", "reliable")
func net_frag(killer_id: int, victim_id: int) -> void:
	$HUD.on_frag(killer_id, victim_id)


func _reset_round_clock() -> void:
	_round_finished = false
	_winner = ""
	_winning_score = 0
	_round_time = float(round_limits.x * 60)
	net_round_clock(ceili(_round_time) if round_limits.x > 0 else -1)


func _tick_round_clock(delta: float) -> void:
	if round_limits.x == 0:
		return
	_round_time = maxf(0.0, _round_time - delta)
	var seconds := ceili(_round_time)
	if seconds != _clock_seconds:
		for peer in _ready_peers:
			net_round_clock.rpc_id(peer, seconds)
		net_round_clock(seconds)
	if _round_time == 0.0:
		_finish_timed_round()


@rpc("authority", "reliable")
func net_round_clock(seconds: int) -> void:
	_clock_seconds = seconds
	$HUD.show_round_limits(seconds, round_limits.y)


func _combatants() -> Array[Node]:
	var actors := get_tree().get_nodes_in_group("player")
	actors.append_array(get_tree().get_nodes_in_group("bot"))
	return actors


func _combatant_label(actor: Node) -> String:
	if actor.is_in_group("bot"):
		return "Бот" if get_tree().get_node_count_in_group("bot") == 1 else "Бот %d" % (1 - actor.combatant_id)
	return "Вы" if Net.solo else player_label(actor.slot)


func _finish_timed_round() -> void:
	var best := -1
	var winner := ""
	for actor in _combatants():
		var kills: int = $HUD.kills_for(actor.score_id())
		if kills > best:
			best = kills
			winner = _combatant_label(actor)
		elif kills == best:
			winner = ""
	_finish_round(winner, maxi(0, best))


func _finish_round(winner: String, score: int) -> void:
	for peer in _ready_peers:
		net_round_finished.rpc_id(peer, winner, score)
	net_round_finished(winner, score)


@rpc("authority", "reliable")
func net_round_finished(winner: String, score: int) -> void:
	_round_finished = true
	_winner = winner
	_winning_score = score
	for actor in _combatants():
		actor.control_enabled = false
		actor.aiming = false
		actor.velocity = Vector3.ZERO
	$HUD.show_loot_prompt("")
	$HUD/MatchMenu.show_round_result(winner, score)


func _spawn_player(peer_id: int, slot: int) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id, true)
	player.slot = slot
	player.spawn_position = $Map.PLAYER_SPAWNS[slot]
	player.position = player.spawn_position
	add_child(player)
	if not Net.active or player.is_multiplayer_authority():
		$HUD/MatchMenu.close()
		$HUD.attach_local(player)
		$HUD/Lobby.hide_lobby()
		$HUD/WeaponSelect.show_select()
	$HUD.refresh_score()


func _physics_process(delta: float) -> void:
	if not _started or _round_finished:
		return
	if not Net.active or multiplayer.is_server():
		_tick_round_clock(delta)
	if not Net.active or _round_finished:
		return
	_pose_time += delta
	if _pose_time < POSE_INTERVAL:
		return
	_pose_time = fmod(_pose_time, POSE_INTERVAL)
	if multiplayer.is_server():
		if _ready_peers.is_empty():
			return
		# Batch all actors into one movement update per guest.
		var poses: Dictionary[int, PackedFloat32Array] = {}
		for player in get_tree().get_nodes_in_group("player"):
			poses[player.get_multiplayer_authority()] = player.network_pose()
		poses[0] = $Bot0.network_pose()
		for peer in _ready_peers:
			net_poses.rpc_id(peer, poses)
	else:
		var player := get_node_or_null(str(Net.local_id()))
		if player and player.control_enabled:
			net_client_pose.rpc_id(1, player.network_pose())


@rpc("any_peer", "unreliable_ordered")
func net_client_pose(pose: PackedFloat32Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not _ready_peers.has(id):
		return
	var player := get_node_or_null(str(id))
	if player:
		apply_client_pose(player, pose)


func apply_client_pose(player: Node, pose: PackedFloat32Array) -> bool:
	if not player or not player.control_enabled or pose.size() != player.NETWORK_POSE_SIZE:
		return false
	for value in pose:
		if not is_finite(value):
			return false
	player.apply_network_pose(pose)
	return true


@rpc("authority", "unreliable_ordered")
func net_poses(poses: Dictionary[int, PackedFloat32Array]) -> void:
	if _round_finished:
		return
	for peer in poses:
		if peer == Net.local_id():
			continue
		var actor := combatant(peer)
		if actor:
			actor.apply_network_pose(poses[peer])


func _on_joined() -> void:
	$HUD/Lobby.show_guest_room()
	set_local_display_name(Net.display_name)


func _on_connection_failed() -> void:
	$HUD/Lobby.join_failed()


func _on_peer_connected(id: int) -> void:
	if Net.active and multiplayer.is_server():
		call_deferred("_welcome", id)


func _welcome(id: int) -> void:
	if not Net.active or not multiplayer.is_server() or not multiplayer.get_peers().has(id):
		return
	var slot := player_slots.find(0)
	if slot < 0 or player_slots.has(id):
		return
	_set_slot(slot, id)
	if _started:
		_send_slot(slot, id, id)
		net_begin.rpc_id(id, weapon_set, map_id, player_slots, _layout_seed, round_limits)
	else:
		_send_room_state()


@rpc("any_peer", "reliable")
func net_ready() -> void:
	var id := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or not _started or not player_slots.has(id) or _ready_peers.has(id):
		return
	# Gameplay RPCs can target this guest once it has built the match scene.
	_ready_peers.append(id)
	net_display_names.rpc_id(id, _display_names)
	$Bot0.send_status_to(id)
	$Loot.send_state(id)
	$Grenades.send_state(id)
	$Map.send_bullet_holes(id)
	for player in get_tree().get_nodes_in_group("player"):
		player.send_status_to(id)
	net_score_snapshot.rpc_id(id, $HUD.score_snapshot())
	net_round_clock.rpc_id(id, _clock_seconds)
	if _round_finished:
		net_round_finished.rpc_id(id, _winner, _winning_score)
	$HUD.hide_host_ip()


func _on_peer_disconnected(id: int) -> void:
	if not Net.active or not multiplayer.is_server():
		return
	_display_names.erase(id)
	var slot := player_slots.find(id)
	if slot <= 0:
		return
	_ready_peers.erase(id)
	_set_slot(slot, 0)
	if _started:
		_send_slot(slot, 0)
		if _ready_peers.is_empty():
			$HUD.show_host_ip(Net.lan_addresses())
	else:
		_send_room_state()


func _send_slot(slot: int, id: int, excluded_peer: int = 0) -> void:
	for peer in player_slots:
		if peer > 1 and peer != excluded_peer:
			net_slot.rpc_id(peer, slot, id)


@rpc("authority", "reliable")
func net_slot(slot: int, id: int) -> void:
	_set_slot(slot, id)


func _set_slot(slot: int, id: int) -> void:
	var previous := player_slots[slot]
	player_slots[slot] = id
	if not _started:
		return
	if previous != 0:
		_display_names.erase(previous)
		var player := get_node(str(previous))
		remove_child(player)
		player.queue_free()
		$HUD.remove_score(previous)
	if id != 0:
		_spawn_player(id, slot)
