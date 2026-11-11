extends Node3D

const MAX_BOTS := 10
const PLAYER_SCENE := preload("res://game/actors/player.tscn")
const CLASSIC_WEAPONS := preload("res://game/combat/classic_weapons.gd")
const WEAPON_SCRIPT := preload("res://game/combat/weapon.gd")
const BOT_SCRIPT := preload("res://game/actors/bot.gd")
const MAP := preload("res://game/maps/map_builder.gd")
const MAP_NAMES := MAP.MAP_NAMES
const WEAPON_SET_NAMES := ["Любое", "Дробовик и пистолет", "Всё, кроме дробовика"]
const TIME_LIMITS := [0, 60, 180, 300, 600, 900, 1200, 1800, 3600]
const KILL_LIMITS := [0, 1, 5, 10, 15, 20, 30, 50, 100]
const POSE_INTERVAL := 1.0 / 30.0
const ARENA_HOURS := [13.0, 9.5, 16.0, 15.5, 14.0]
const MIN_RESPAWN_DISTANCE := 12.0
const DIFFICULTY_NAMES := ["Легко", "Обычно", "Сложно"]
const WEAPON_SETS := [
	["deagle", "shotgun", "ak47", "m1911", "mac10", "mp5", "m700", "tec9", "lever", "m14", "launcher", "m249", "m1"],
	["shotgun"],
	["deagle", "ak47", "m1911", "mac10", "mp5", "m700", "tec9", "lever", "m14", "launcher", "m249", "m1"],
]

var map_id := 0
var map_size := MAP.DEFAULT_SIZE
var weapon_set := 0
var bot_difficulty := 1
var time_option := 4
var kill_option := 5
var _round_left := 0.0
var _display_seconds := -1
var _finish_reason := ""
var _final_rows: Array = []
var _layout_seed := 0
var player_slots := PackedInt32Array()
var _display_names: Dictionary[int, String] = {}
var lan_bot_count := 1
var _solo_bot_count := 1
var _map_revision := 0

var _reloading := false
var _started := false
var _loading := false
var _waiting_for_host := false
var _navigation_pending := false
var _navigation_region: NavigationRegion3D
var _ready_peers: Array[int] = []
var _pose_time := 0.0
var _cloud_time := 0.0


func _ready() -> void:
	player_slots.resize(Net.MAX_PLAYERS)
	player_slots[0] = 1
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Net.joined.connect(_on_joined)
	Net.connection_failed.connect(_on_connection_failed)
	Net.host_lost.connect(_on_host_lost)
	GameSettings.graphics_changed.connect(_apply_graphics)
	_apply_graphics()


func _apply_graphics() -> void:
	$WorldEnvironment/SunLight.shadow_enabled = GameSettings.shadows
	$WorldEnvironment/MoonLight.shadow_enabled = false
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
		var player := combatant(peer)
		if player:
			player.set_name_label(player_label(player.slot))
		for guest in _ready_peers:
			net_display_names.rpc_id(guest, _display_names)
	else:
		_send_room_state()


@rpc("authority", "reliable")
func net_display_names(names: Dictionary[int, String]) -> void:
	_display_names = names
	for player in get_tree().get_nodes_in_group("player"):
		player.set_name_label(player_label(player.slot))


func is_loading() -> bool:
	return _loading or _waiting_for_host


func has_started() -> bool:
	return _started


func input_blocked() -> bool:
	return _reloading or is_loading() or round_finished() or $HUD/MatchMenu.visible or $HUD/WeaponSelect.armory_open()


func round_finished() -> bool:
	return not _finish_reason.is_empty()


func allows_weapon(id: String) -> bool:
	return id in WEAPON_SETS[weapon_set] or (weapon_set == 1 and id == "deagle")


func random_weapon(exclude: String = "") -> String:
	var choices: Array = WEAPON_SETS[weapon_set].duplicate()
	if choices.size() > 1:
		choices.erase(exclude)
	return choices.pick_random()


func combatant(id: int) -> Node:
	return get_node_or_null("Bot%d" % -id if id <= 0 else str(id))


func arena_width() -> float:
	return MAP.SIZE_WIDTHS[map_size]


func choose_respawn(actor: Node3D, previous: Vector3) -> Vector3:
	var enemies: Array[Node3D] = []
	for group in [&"player", &"bot"]:
		for fighter in get_tree().get_nodes_in_group(group):
			if fighter != actor and fighter.health > 0:
				enemies.append(fighter)
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = 2
	var best := previous
	var best_score := -INF
	var visibility_radius := maxf(64.0, arena_width() * 0.65)
	var distance_limit := visibility_radius + 8.0
	for point: Vector3 in $Map.respawn_points:
		var nearest := distance_limit
		for enemy in enemies:
			nearest = minf(nearest, enemy.global_position.distance_to(point))
		var score := nearest
		if nearest < MIN_RESPAWN_DISTANCE:
			score -= 1000.0
		if point.distance_squared_to(previous) < 0.1:
			score -= 6.0
		if score <= best_score:
			continue
		if nearest >= MIN_RESPAWN_DISTANCE:
			ray.to = point + Vector3.UP * 1.4
			for enemy in enemies:
				var distance := enemy.global_position.distance_to(point)
				if distance > visibility_radius:
					continue
				ray.from = enemy.aim_center()
				if space.intersect_ray(ray).is_empty():
					score -= 25.0 * (1.0 - distance / distance_limit)
				if score <= best_score:
					break
		if score > best_score:
			best_score = score
			best = point
	return best


func can_restart() -> bool:
	return _started and (Net.solo or (Net.active and multiplayer.is_server()))


func can_choose_next_map() -> bool:
	return round_finished() and (can_restart() or not Net.active)


func start_next_map(arena: int) -> void:
	if not can_choose_next_map() or is_loading() or arena < 0 or arena >= MAP_NAMES.size():
		return
	if Net.active:
		_map_revision += 1
		for peer in _ready_peers:
			net_prepare_next_map.rpc_id(peer, _map_revision)
		_clear_match_map()
		map_id = arena
		await start_host_match()
	else:
		var bot_count := _solo_bot_count if Net.solo else maxi(1, lan_bot_count)
		_clear_match_map()
		await start_solo(bot_count, bot_difficulty, weapon_set, arena, Vector2i(time_option, kill_option), map_size)


@rpc("authority", "reliable")
func net_prepare_next_map(revision: int) -> void:
	if revision <= _map_revision or _loading:
		return
	_map_revision = revision
	_clear_match_map()
	net_wait_for_arena()


func _clear_match_map() -> void:
	_started = false
	_ready_peers.clear()
	$HUD/WeaponSelect.hide_for_results()
	$HUD/MatchMenu.close()
	$HUD.detach_local()
	$HUD.reset_round()
	for actor in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("bot"):
		if actor.get_parent() == self:
			remove_child(actor)
			actor.queue_free()
	$Ballistics.reset_round()
	$Grenades.reset_round()
	$Loot.clear_map()
	$Map.clear_map()
	if is_instance_valid(_navigation_region):
		remove_child(_navigation_region)
		_navigation_region.queue_free()
		_navigation_region = null
	_finish_reason = ""
	_final_rows = []
	_pose_time = 0.0
	_cloud_time = 0.0


func restart_round() -> void:
	if not can_restart():
		return
	for peer in _ready_peers:
		net_restart.rpc_id(peer)
	net_restart()


func leave_round() -> void:
	_reload_main_menu()


func _reload_main_menu() -> void:
	if _reloading:
		return
	_reloading = true
	GameSettings.set_match_audio_enabled(false)
	_stop_round_effects()
	Net.leave_game()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


@rpc("authority", "reliable")
func net_restart() -> void:
	$HUD/WeaponSelect.close_armory()
	var finished := round_finished()
	_finish_reason = ""
	_final_rows.clear()
	if finished:
		$HUD/MatchMenu.close()
	$Ballistics.reset_round()
	$Grenades.reset_round()
	$Map.clear_bullet_holes()
	$HUD.reset_round()
	$Loot.reset_round()
	for player in get_tree().get_nodes_in_group("player"):
		player.restart_round()
	for bot in get_tree().get_nodes_in_group("bot"):
		bot.restart_round()
	_reset_clock()
	GameSettings.set_match_audio_enabled(true)
	var local := combatant(Net.local_id())
	if finished and local:
		if local.control_enabled:
			$HUD/Crosshair.show()
			GameSettings.capture_gameplay_mouse()
		else:
			$HUD/WeaponSelect.show_select()


@rpc("authority", "reliable")
func net_score_snapshot(scores: Dictionary) -> void:
	$HUD.apply_score_snapshot(scores)


func start_solo(bot_count: int, difficulty: int, weapons: int, arena: int, limits: Vector2i, size: int) -> void:
	if _started or _loading or Net.active:
		return
	_show_loading()
	Net.play_solo()
	_set_limits(limits)
	weapon_set = weapons
	map_id = arena
	map_size = clampi(size, 0, MAP.SIZE_WIDTHS.size() - 1)
	bot_difficulty = clampi(difficulty, 0, DIFFICULTY_NAMES.size() - 1)
	_solo_bot_count = clampi(bot_count, 1, MAX_BOTS)
	await _load_arena(randi(), _solo_bot_count, bot_difficulty)
	_started = true
	_spawn_player(1, 0)
	await _finish_loading()


func update_host_rules(weapons: int, arena: int, limits: Vector2i, difficulty: int, bot_count: int, size: int) -> void:
	if _started or _loading or not Net.active or not multiplayer.is_server():
		return
	weapon_set = weapons
	map_id = arena
	map_size = clampi(size, 0, MAP.SIZE_WIDTHS.size() - 1)
	_set_limits(limits)
	bot_difficulty = clampi(difficulty, 0, DIFFICULTY_NAMES.size() - 1)
	lan_bot_count = clampi(bot_count, 0, MAX_BOTS)
	_send_room_state()


func start_host_match() -> void:
	if _started or _loading or not Net.active or not multiplayer.is_server():
		return
	_show_loading()
	for peer in player_slots:
		if peer > 1:
			net_wait_for_arena.rpc_id(peer)
	_layout_seed = randi()
	await _begin_network_match(weapon_set, map_id, _layout_seed, Vector2i(time_option, kill_option), bot_difficulty, lan_bot_count, map_size)
	if _reloading or not Net.active:
		return
	for peer in player_slots:
		if peer > 1:
			net_begin.rpc_id(peer, weapon_set, map_id, player_slots, _layout_seed, Vector2i(time_option, kill_option), bot_difficulty, lan_bot_count, _map_revision, map_size)
	if player_slots.count(0) == Net.MAX_PLAYERS - 1:
		$HUD.show_host_ip(Net.lan_addresses())


func _send_room_state() -> void:
	$HUD/Lobby.refresh_room()
	for peer in player_slots:
		if peer > 1:
			net_room_state.rpc_id(peer, weapon_set, map_id, player_slots, Vector2i(time_option, kill_option), bot_difficulty, lan_bot_count, _display_names, map_size)


@rpc("authority", "reliable")
func net_room_state(weapons: int, arena: int, roster: PackedInt32Array, limits: Vector2i,
		difficulty: int, bot_count: int, names: Dictionary[int, String], size: int) -> void:
	if _started or _loading:
		return
	weapon_set = weapons
	map_id = arena
	map_size = clampi(size, 0, MAP.SIZE_WIDTHS.size() - 1)
	player_slots = roster
	_set_limits(limits)
	bot_difficulty = clampi(difficulty, 0, DIFFICULTY_NAMES.size() - 1)
	lan_bot_count = bot_count
	_display_names = names
	$HUD/Lobby.refresh_room()


@rpc("authority", "reliable")
func net_wait_for_arena() -> void:
	if _started or _loading:
		return
	_waiting_for_host = true
	$HUD/MatchMenu.close()
	$HUD/Lobby.show_loading()
	$HUD/Lobby.set_loading_stage("Хост готовит арену…")


@rpc("authority", "reliable")
func net_begin(weapons: int, arena: int, roster: PackedInt32Array, layout_seed: int, limits: Vector2i,
		difficulty: int, bot_count: int, revision: int, size: int) -> void:
	if revision < _map_revision:
		return
	if revision > _map_revision:
		while _loading and not _reloading:
			await get_tree().process_frame
		if _reloading or revision <= _map_revision:
			return
		_map_revision = revision
		_clear_match_map()
	if _started or _loading:
		return
	player_slots = roster
	_show_loading()
	await _begin_network_match(weapons, arena, layout_seed, limits, difficulty, bot_count, size)
	if not _reloading and Net.active:
		net_ready.rpc_id(1, revision)


func _begin_network_match(weapons: int, arena: int, layout_seed: int, limits: Vector2i, difficulty: int, bot_count: int, size: int) -> void:
	weapon_set = weapons
	map_id = arena
	map_size = clampi(size, 0, MAP.SIZE_WIDTHS.size() - 1)
	_set_limits(limits)
	bot_difficulty = clampi(difficulty, 0, DIFFICULTY_NAMES.size() - 1)
	lan_bot_count = bot_count
	await _load_arena(layout_seed, bot_count, bot_difficulty)
	if _reloading or not Net.active:
		return
	_started = true
	for slot in player_slots.size():
		if player_slots[slot] != 0:
			_spawn_player(player_slots[slot], slot)
	await _finish_loading()


func _show_loading() -> void:
	_waiting_for_host = false
	_loading = true
	$HUD/MatchMenu.close()
	$HUD/Lobby.show_loading()


func _loading_stage(message: String) -> void:
	$HUD/Lobby.set_loading_stage(message)
	await get_tree().process_frame
	await get_tree().process_frame


func _load_arena(layout_seed: int, bot_count: int, difficulty: int) -> void:
	await _loading_stage("Подгружаем текстуры…")
	await $Map.preload_textures()
	await _loading_stage("Собираем карту…")
	_build_arena(layout_seed)
	await _loading_stage("Подгружаем оружие и звуки…")
	$Ballistics.prepare_acoustics()
	await CLASSIC_WEAPONS.prepare(get_tree(), WEAPON_SETS[weapon_set])
	await _loading_stage("Готовим бойцов…")
	await _spawn_bots(bot_count, difficulty)
	while _navigation_pending and not _reloading:
		await get_tree().process_frame


func _finish_loading() -> void:
	var warmup := WEAPON_SCRIPT.render_warmup(WEAPON_SETS[weapon_set])
	add_child(warmup)
	var props: Node3D = $Loot.warm_rendering()
	await _loading_stage("Готовим первый кадр…")
	if DisplayServer.get_name() != "headless":
		await $Ballistics.warm_effects()
	warmup.queue_free()
	props.queue_free()
	if _reloading:
		return
	_loading = false
	GameSettings.set_match_audio_enabled(true)
	_reset_clock()
	$HUD/Lobby.hide_lobby()
	$HUD/WeaponSelect.show_select()


func _build_arena(layout_seed: int) -> void:
	$WorldEnvironment.current_time = ARENA_HOURS[map_id]
	_apply_graphics()
	$Loot.build_crates($Map.build(map_id, layout_seed, arena_width()))
	if not Net.active or multiplayer.is_server():
		var mesh := NavigationMesh.new()
		mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		var village := map_id == MAP.VILLAGE_ID
		mesh.cell_size = 0.25 if village else 0.20
		mesh.cell_height = 0.1
		mesh.agent_radius = 0.50 if village else 0.40
		mesh.agent_height = 1.8
		mesh.agent_max_climb = 0.1
		mesh.filter_walkable_low_height_spans = true
		var width := arena_width()
		if map_id == MAP.DUST2_ID:
			mesh.filter_baking_aabb = AABB(Vector3(-width * 0.5, -3.0, -width * 0.5), Vector3(width, 7.5, width))
		else:
			mesh.filter_baking_aabb = AABB(Vector3(-width * 0.5, -0.5, -width * 0.5), Vector3(width, 2.8, width))
		var geometry := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(mesh, geometry, self)
		_navigation_pending = true
		NavigationServer3D.bake_from_source_geometry_data_async(mesh, geometry, _on_navigation_baked.bind(mesh))


func _on_navigation_baked(mesh: NavigationMesh) -> void:
	_install_navigation.call_deferred(mesh)


func _install_navigation(mesh: NavigationMesh) -> void:
	if not is_inside_tree() or _reloading:
		return
	_navigation_region = NavigationRegion3D.new()
	_navigation_region.navigation_mesh = mesh
	add_child(_navigation_region)
	_navigation_pending = false


func _set_limits(limits: Vector2i) -> void:
	time_option = clampi(limits.x, 0, TIME_LIMITS.size() - 1)
	kill_option = clampi(limits.y, 0, KILL_LIMITS.size() - 1)


func _reset_clock() -> void:
	_round_left = TIME_LIMITS[time_option]
	net_clock(ceili(_round_left))


func _tick_round(delta: float) -> void:
	if TIME_LIMITS[time_option] == 0:
		return
	_round_left = maxf(0.0, _round_left - delta)
	var seconds := ceili(_round_left)
	if seconds != _display_seconds:
		net_clock(seconds)
		for peer in _ready_peers:
			net_clock.rpc_id(peer, seconds)
	if _round_left == 0.0:
		_finish_round("Время вышло")


@rpc("authority", "reliable")
func net_clock(seconds: int) -> void:
	_display_seconds = seconds
	var limit: int = TIME_LIMITS[time_option]
	$HUD.show_round_status(seconds, limit > 0, KILL_LIMITS[kill_option])
	if limit > 0:
		var elapsed := clampi(limit - seconds, 0, limit)
		var sky_hour := float(ARENA_HOURS[map_id]) + float(elapsed - elapsed % 15) / 1500.0
		if not is_equal_approx($WorldEnvironment.current_time, sky_hour):
			$WorldEnvironment.current_time = sky_hour
			_apply_graphics()


func _finish_round(reason: String) -> void:
	if round_finished():
		return
	var rows: Array = $HUD.score_rows(false)
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1] or (a[1] == b[1] and a[2] < b[2]))
	net_finish(reason, rows)
	for peer in _ready_peers:
		net_finish.rpc_id(peer, reason, rows)


@rpc("authority", "reliable")
func net_finish(reason: String, rows: Array) -> void:
	_finish_reason = reason
	_final_rows = rows
	GameSettings.set_match_audio_enabled(false)
	_stop_round_effects.call_deferred()
	$HUD/Lobby.hide_lobby()
	$HUD/WeaponSelect.hide_for_results()
	$HUD/MatchMenu.show_results(reason, rows)


func _stop_round_effects() -> void:
	if not round_finished() and not _reloading:
		return
	$Ballistics.reset_round()
	$Grenades.reset_round()
	$HUD.show_loot_prompt("")
	for actor in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("bot"):
		if actor.get_parent() == self:
			actor.stop_round()


func _on_host_lost() -> void:
	if not _started or is_loading():
		_reload_main_menu()
		return
	Net.notice = ""
	if round_finished():
		$HUD/MatchMenu.show_results(_finish_reason, _final_rows)
	else:
		_finish_round("Хост отключился")


func _spawn_bots(count: int, difficulty: int) -> void:
	for index in count:
		var bot := PLAYER_SCENE.instantiate()
		bot.set_script(BOT_SCRIPT)
		bot.name = "Bot%d" % index
		bot.combatant_id = -index
		bot.position = $Map.initial_spawn(Net.MAX_PLAYERS + index)
		bot.spawn_position = bot.position
		bot.patrol_route = $Map.patrol_route()
		bot.difficulty = difficulty
		bot.floor_snap_length = 0.2
		add_child(bot)
		if not Net.active or multiplayer.is_server():
			bot.equip(random_weapon())
		if index % 2 == 1 and index + 1 < count:
			await get_tree().process_frame


func announce(killer_id: int, victim_id: int) -> void:
	for peer in _ready_peers:
		net_frag.rpc_id(peer, killer_id, victim_id)
	net_frag(killer_id, victim_id)
	var limit: int = KILL_LIMITS[kill_option]
	if killer_id != victim_id and limit > 0 and $HUD.kills_for(killer_id) >= limit:
		_finish_round("Достигнут лимит убийств")


@rpc("authority", "reliable")
func net_frag(killer_id: int, victim_id: int) -> void:
	$HUD.on_frag(killer_id, victim_id)


func _spawn_player(peer_id: int, slot: int) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.slot = slot
	player.set_multiplayer_authority(peer_id, true)
	player.spawn_position = $Map.initial_spawn(slot)
	player.position = player.spawn_position
	add_child(player)
	if not Net.active or player.is_multiplayer_authority():
		$HUD/MatchMenu.close()
		$HUD.attach_local(player)
		if not _loading:
			$HUD/Lobby.hide_lobby()
			$HUD/WeaponSelect.show_select()
	else:
		player.set_name_label(player_label(slot))
	$HUD.refresh_score()


func _physics_process(delta: float) -> void:
	if not _started or _loading or round_finished():
		return
	_cloud_time += delta
	if _cloud_time >= 0.2:
		$WorldEnvironment/SkyDome.process_tick(_cloud_time)
		_cloud_time = 0.0
	if not Net.active or multiplayer.is_server():
		_tick_round(delta)
	if not Net.active or round_finished():
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
		for bot in get_tree().get_nodes_in_group("bot"):
			poses[bot.combatant_id] = bot.network_pose()
		for peer in _ready_peers:
			net_poses.rpc_id(peer, poses)
	else:
		var player := get_node_or_null(str(Net.local_id()))
		if player and player.control_enabled:
			net_client_pose.rpc_id(1, player.network_pose())


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func net_client_pose(pose: PackedFloat32Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if round_finished() or not _ready_peers.has(id):
		return
	var player := get_node_or_null(str(id))
	apply_client_pose(player, pose)


func apply_client_pose(player: Node, pose: PackedFloat32Array) -> bool:
	if round_finished() or not player or not player.control_enabled or pose.size() != player.NETWORK_POSE_SIZE:
		return false
	if pose[11] != float(player._spawn_revision):
		return false
	for value in pose:
		if not is_finite(value):
			return false
	player.apply_network_pose(pose)
	return true


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func net_poses(poses: Dictionary[int, PackedFloat32Array]) -> void:
	if round_finished():
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
		net_begin.rpc_id(id, weapon_set, map_id, player_slots, _layout_seed, Vector2i(time_option, kill_option), bot_difficulty, lan_bot_count, _map_revision, map_size)
	else:
		_send_room_state()


@rpc("any_peer", "reliable")
func net_ready(revision: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or not _started or revision != _map_revision or not player_slots.has(id) or _ready_peers.has(id):
		return
	# Gameplay RPCs can target this guest once it has built the match scene.
	_ready_peers.append(id)
	net_display_names.rpc_id(id, _display_names)
	for bot in get_tree().get_nodes_in_group("bot"):
		bot.send_status_to(id)
	$Map.send_bullet_holes(id)
	$Loot.send_state(id)
	$Grenades.send_state(id)
	for player in get_tree().get_nodes_in_group("player"):
		player.send_status_to(id)
	net_score_snapshot.rpc_id(id, $HUD.score_snapshot())
	net_clock.rpc_id(id, _display_seconds)
	if round_finished():
		net_finish.rpc_id(id, _finish_reason, _final_rows)
	$HUD.hide_host_ip()


func _on_peer_disconnected(id: int) -> void:
	if not Net.active or not multiplayer.is_server():
		return
	var slot := player_slots.find(id)
	if slot <= 0:
		return
	_ready_peers.erase(id)
	_display_names.erase(id)
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
		var player := get_node(str(previous))
		remove_child(player)
		player.queue_free()
		$HUD.remove_score(previous)
	if id != 0:
		_spawn_player(id, slot)
