extends Node3D

const ARENA_SCENE := "res://game/match/arena.tscn"
const ROUND_OVERVIEW := preload("res://game/ui/round_overview.gd")

const MAX_BOTS := 10
const PLAYER_SCENE := preload("res://game/actors/player.tscn")
const CLASSIC_WEAPONS := preload("res://game/combat/classic_weapons.gd")
const WEAPON_SCRIPT := preload("res://game/combat/weapon.gd")
const BOT_SCRIPT := preload("res://game/actors/bot.gd")
const MAP := preload("res://game/maps/map_builder.gd")
const MAP_NAMES := MAP.MAP_NAMES
const BREAKWATER_SCENE := preload("res://game/maps/breakwater/breakwater_arena.tscn")
const BREAKWATER := preload("res://game/maps/breakwater/scripts/arena_controller.gd")
const PLAYER_CAPSULE := preload("res://game/actors/player_capsule.tres")
const BREAKWATER_SPAWN_RETRY := 0.25
const WEAPON_SET_NAMES := ["Любое", "Дробовик и пистолет", "Всё, кроме дробовика"]
const TIME_LIMITS := [0, 60, 180, 300, 600, 900, 1200, 1800, 3600]
const KILL_LIMITS := [0, 1, 5, 10, 15, 20, 30, 50, 100]
const Balance := preload("res://game/combat/combat_balance.gd")
const POSE_INTERVAL: float = 1.0 / Balance.NETWORK.snapshot_hz
const ARENA_WEATHER := {
	0: {"hour": 13.0, "wind": Vector2(25, 1.0)},
	1: {"hour": 11.5, "wind": Vector2(-65, 0.75)},
	2: {"hour": 14.0, "wind": Vector2(120, 1.2)},
	MAP.VILLAGE_ID: {"hour": 13.0, "wind": Vector2(-35, 0.9)},
	MAP.DUST2_ID: {"hour": 14.0, "wind": Vector2(-105, 2.0)},
	MAP.WORKSHOP_ID: {"hour": 13.5, "wind": Vector2(60, 0.8)},
	MAP.TEST_RANGE_ID: {"hour": 13.0, "wind": Vector2(0, 0.2)},
	MAP.OFFICE_ID: {"hour": 12.0, "wind": Vector2.ZERO},
	MAP.OUTPOST_ID: {"hour": 11.0, "wind": Vector2(35, 1.0)},
	MAP.STATION_ID: {"hour": 16.0, "wind": Vector2(-45, 0.6)},
}
const MIN_RESPAWN_DISTANCE := 12.0
const TRAINING_RESPAWN_DELAY := 0.75
const DIFFICULTY_NAMES := ["Легко", "Обычно", "Сложно", "Эксперт", "Элита"]
const WEAPON_SETS := [
	["deagle", "shotgun", "ak47", "m1911", "mac10", "mp5", "m700", "tec9", "lever", "m14", "launcher", "m249", "m1"],
	["shotgun"],
	["deagle", "ak47", "m1911", "mac10", "mp5", "m700", "tec9", "lever", "m14", "launcher", "m249", "m1"],
]

signal damage_resolved(event: Dictionary)

var combat_seed := 0
var _damage_sequence := 0
var _latest_damage_event := 0
var _server_clock_offset := 0.0
var _server_clock_synced := false
var team_deathmatch := false
var random_map_each_match := false
var blue_bot_count := -1
var _previous_match_map := -1
var _team_score := Vector2i.ZERO
var _bot_slots := PackedInt32Array()
var map_id := 0
var map_size := MAP.DEFAULT_SIZE
var lobby_map_size := MAP.DEFAULT_SIZE
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
var room_owner := 1
var _solo_bot_count := 1
var _map_revision := 0
var _load_token := 0

var _reloading := false
var _started := false
var _loading := false
var _waiting_for_host := false
var _navigation_pending := false
var _navigation_region: NavigationRegion3D
var _ready_peers: Array[int] = []
var _pose_time := 0.0
var _cloud_time := 0.0
var _status_time := 0.0
var _ping_time := 0.0
var _ping_by_peer: Dictionary[int, int] = {}
var _had_player := false
var _room_password := ""
var _owner_token := ""
var _breakwater: BREAKWATER
var _spawn_retry_left := 0.0

@onready var _base_environment: Environment = $WorldEnvironment.environment


var _round_overview: Node3D


func _ready() -> void:
	if not Balance.validate():
		push_error("Invalid combat balance preset")
		get_tree().quit(1)
		return
	combat_seed = randi()
	Engine.physics_ticks_per_second = int(Balance.NETWORK.tick_hz)
	if Net.directory:
		return
	player_slots.resize(Net.MAX_PLAYERS)
	if Net.match_server:
		room_owner = 0
		if not _load_match_room():
			get_tree().quit(1)
			return
	elif Net.dedicated:
		room_owner = 0
	else:
		player_slots[0] = 1
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Net.joined.connect(_on_joined)
	Net.connection_failed.connect(_on_connection_failed)
	Net.host_lost.connect(_on_host_lost)
	GameSettings.graphics_changed.connect(_apply_graphics)
	_apply_graphics()


func _apply_graphics() -> void:
	var environment: Environment = $WorldEnvironment.environment
	if is_instance_valid(_breakwater):
		environment = _breakwater.get_node("WorldEnvironment").environment
	if environment:
		environment.ssao_enabled = GameSettings.ambient_occlusion
		_apply_indirect_lighting(environment)
	if is_instance_valid(_breakwater):
		_breakwater.get_node("Sun").shadow_enabled = GameSettings.shadows
		for light in get_tree().get_nodes_in_group(&"breakwater_shadow_lights"):
			light.shadow_enabled = GameSettings.shadows
		return
	$WorldEnvironment/SunLight.shadow_enabled = GameSettings.shadows
	$WorldEnvironment/SunLight.directional_shadow_max_distance = GameSettings.shadow_distance
	$WorldEnvironment/SunLight.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS \
		if GameSettings.shadow_cascades == 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	$WorldEnvironment/MoonLight.shadow_enabled = false
	if map_id == MAP.OFFICE_ID:
		for light in get_tree().get_nodes_in_group(&"office_shadow_lights"):
			if $Map.is_ancestor_of(light):
				light.shadow_enabled = GameSettings.shadows


func _apply_indirect_lighting(environment: Environment) -> void:
	var enabled := GameSettings.indirect_lighting and GameSettings.supports_advanced_graphics() \
		and DisplayServer.get_name() != "headless" and not Net.dedicated
	var probe := $Map.get_node_or_null("OfficeBounce") as VoxelGI
	environment.sdfgi_enabled = enabled and map_id != MAP.OFFICE_ID
	if not enabled or map_id != MAP.OFFICE_ID:
		if probe:
			probe.hide()
		return
	if probe:
		probe.show()
	elif $Map.has_node("VillageFixtures"):
		_bake_office_bounce.call_deferred(_load_token)


func _bake_office_bounce(token: int) -> void:
	if token != _load_token or map_id != MAP.OFFICE_ID or not GameSettings.indirect_lighting \
			or $Map.has_node("OfficeBounce"):
		return
	var probe := VoxelGI.new()
	probe.name = "OfficeBounce"
	probe.position.y = 1.45
	probe.size = Vector3(21.0, 4.8, 17.0)
	probe.subdiv = VoxelGI.SUBDIV_64
	$Map.add_child(probe)
	probe.bake($Map)
	if probe.data:
		probe.data.energy = 0.44
		probe.data.interior = true
	else:
		probe.queue_free()


func prepare_startup_resources() -> void:
	await $Map.preload_textures(map_id)
	await CLASSIC_WEAPONS.prepare(get_tree(), ["ak47"])


func match_peers() -> Array[int]:
	return _ready_peers


func player_label(slot: int) -> String:
	var alias: String = _display_names.get(player_slots[slot], "")
	if not alias.is_empty():
		return alias
	if Net.internet or Net.dedicated:
		return "Игрок %d" % (slot + 1)
	return "Хост" if slot == 0 else "Игрок %d" % (slot + 1)


func _match_player_label(slot: int) -> String:
	var label := player_label(slot)
	return "%s · Команда %d" % [label, slot % 2 + 1] if team_deathmatch else label


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
			player.set_name_label(_match_player_label(player.slot))
		for guest in _ready_peers:
			net_display_names.rpc_id(guest, _display_names)
	else:
		_send_room_state()


@rpc("authority", "reliable")
func net_display_names(names: Dictionary[int, String]) -> void:
	_display_names = names
	for player in get_tree().get_nodes_in_group("player"):
		player.set_name_label(_match_player_label(player.slot))


func is_loading() -> bool:
	return _loading or _waiting_for_host


func has_started() -> bool:
	return _started


func input_blocked() -> bool:
	return _reloading or is_loading() or round_finished() or $HUD/MatchMenu.visible or $HUD/WeaponSelect.selection_open()


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
	if is_instance_valid(_breakwater):
		return _breakwater.get_arena_bounds().size.x
	return MAP.SIZE_WIDTHS[map_size]


func _selected_map_size(arena: int, size: int) -> int:
	if arena == MAP.OFFICE_ID:
		return 0
	if arena == MAP.TEST_RANGE_ID:
		return MAP.DEFAULT_SIZE
	var minimum := MAP.VILLAGE_MIN_SIZE if arena == MAP.VILLAGE_ID else 0
	return clampi(size, minimum, MAP.SIZE_WIDTHS.size() - 1)


func is_training_range() -> bool:
	return map_id == MAP.TEST_RANGE_ID


func training_respawn_delay() -> float:
	return TRAINING_RESPAWN_DELAY


func choose_respawn(actor: Node3D, previous: Vector3) -> Vector3:
	if is_training_range():
		return actor.spawn_position
	var candidates: PackedVector3Array = $Map.respawn_points
	if is_instance_valid(_breakwater):
		candidates = _breakwater_spawn_candidates(actor.slot)
	return _choose_safe_spawn(actor, actor.slot, previous, candidates)


func _breakwater_spawn_candidates(slot: int) -> PackedVector3Array:
	var candidates := PackedVector3Array()
	var team := ("a" if slot % 2 == 0 else "b") if team_deathmatch else "ffa"
	for marker in _breakwater.get_spawn_candidates(team):
		candidates.append(_breakwater.spawn_feet(marker))
	return candidates


func _choose_safe_spawn(actor: Node3D, slot: int, previous: Vector3,
		candidates: PackedVector3Array) -> Vector3:
	var enemies: Array[Node3D] = []
	var occupied: Array[Node3D] = []
	for group in [&"player", &"bot"]:
		for fighter in get_tree().get_nodes_in_group(group):
			if fighter == actor or fighter.health <= 0:
				continue
			occupied.append(fighter)
			var ally := actor != null and same_team(actor.score_id(), fighter.score_id())
			if actor == null and team_deathmatch:
				ally = fighter.team_id() == slot % 2
			if fighter.control_enabled and not ally:
				enemies.append(fighter)
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = Balance.WORLD_MASK
	var overlap := PhysicsShapeQueryParameters3D.new()
	overlap.shape = PLAYER_CAPSULE
	overlap.collision_mask = Balance.WORLD_AND_CAPSULES
	if actor != null:
		overlap.exclude = [actor.get_rid()]
	var best := previous
	var best_score := -INF
	var visibility_radius := maxf(64.0, arena_width() * 0.65)
	var distance_limit := visibility_radius + 8.0
	var village := map_id == MAP.VILLAGE_ID
	var prefer_cover := village or map_id in [MAP.WORKSHOP_ID, MAP.OFFICE_ID]
	for point: Vector3 in candidates:
		var nearest_occupied := INF
		for fighter in occupied:
			nearest_occupied = minf(nearest_occupied, fighter.global_position.distance_to(point))
		if nearest_occupied < 1.2:
			continue
		overlap.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.93)
		if not space.intersect_shape(overlap, 1).is_empty():
			continue
		var nearest := distance_limit
		for enemy in enemies:
			nearest = minf(nearest, enemy.global_position.distance_to(point))
		var score := nearest + minf(nearest_occupied, distance_limit) * 0.15
		if nearest < MIN_RESPAWN_DISTANCE:
			score -= 1000.0
		if point.distance_squared_to(previous) < 0.1:
			score -= 6.0
		if score <= best_score:
			continue
		if prefer_cover or nearest >= MIN_RESPAWN_DISTANCE:
			ray.to = point + Vector3.UP * 1.4
			for enemy in enemies:
				var distance := enemy.global_position.distance_to(point)
				if not prefer_cover and distance > visibility_radius:
					continue
				ray.from = enemy.aim_center()
				var hit: Dictionary = $Ballistics.ray_through_glass(space, ray) if village else space.intersect_ray(ray)
				if hit.is_empty():
					score -= 400.0 if prefer_cover else 25.0 * (1.0 - distance / distance_limit)
					if prefer_cover:
						break
				if score <= best_score:
					break
		if score > best_score:
			best_score = score
			best = point
	return best


func can_restart() -> bool:
	if not _started or Net.dedicated:
		return false
	if Net.solo:
		return true
	if not Net.active or multiplayer.multiplayer_peer == null:
		return false
	if multiplayer.is_server():
		return true
	return room_owner == multiplayer.get_unique_id()


func can_choose_next_map() -> bool:
	return round_finished() and (can_restart() or not Net.active)


func start_next_map(arena: int) -> void:
	if is_loading() or arena < 0 or arena >= MAP_NAMES.size():
		return
	if Net.active and not multiplayer.is_server():
		if not can_choose_next_map():
			return
		net_request_next_map.rpc_id(1, arena)
		return
	if not round_finished():
		return
	await _start_round_on_map(arena)


func _start_round_on_map(arena: int) -> void:
	if Net.active:
		_map_revision += 1
		for peer in _ready_peers:
			net_prepare_next_map.rpc_id(peer, _map_revision)
		_clear_match_map()
		map_id = arena
		await start_host_match()
	else:
		var bot_count := _solo_bot_count if Net.solo else lan_bot_count
		_clear_match_map()
		await start_solo(bot_count, bot_difficulty, weapon_set, arena, Vector2i(time_option, kill_option), lobby_map_size, team_deathmatch, random_map_each_match, blue_bot_count)


@rpc("authority", "reliable")
func net_prepare_next_map(revision: int) -> void:
	if revision <= _map_revision or _loading:
		return
	_map_revision = revision
	_clear_match_map()
	net_wait_for_arena()


func _clear_match_map() -> void:
	_stop_overview()
	_load_token += 1
	_navigation_pending = false
	_started = false
	$Ambience.stop()
	$Ambience.stream = null
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
	$Fieldworks.reset_round()
	$Map.clear_map()
	if is_instance_valid(_breakwater):
		_breakwater = null
	$WorldEnvironment.environment = _base_environment
	$WorldEnvironment/SunLight.show()
	$WorldEnvironment/MoonLight.show()
	if is_instance_valid(_navigation_region):
		remove_child(_navigation_region)
		_navigation_region.queue_free()
		_navigation_region = null
	_finish_reason = ""
	_final_rows = []
	_pose_time = 0.0
	_cloud_time = 0.0
	_spawn_retry_left = 0.0


func restart_round() -> void:
	if Net.active and not multiplayer.is_server():
		if not can_restart():
			return
		net_request_restart.rpc_id(1)
		return
	if not _started or not (Net.solo or (Net.active and multiplayer.is_server())):
		return
	if random_map_each_match or map_id == MAP.BREAKWATER_ID:
		if not is_loading():
			await _start_round_on_map(map_id)
		return
	for peer in _ready_peers:
		net_restart.rpc_id(peer)
	net_restart()


func exit_to_lobby() -> void:
	if not _started or is_loading():
		return
	if Net.active and not multiplayer.is_server():
		if room_owner == Net.local_id():
			net_request_lobby.rpc_id(1)
		else:
			leave_round()
		return
	_map_revision += 1
	for peer in player_slots:
		if peer > 1:
			net_return_to_lobby.rpc_id(peer, _map_revision)
	_return_to_lobby()
	if Net.active:
		_send_room_state()
		_write_room_status()


@rpc("any_peer", "reliable")
func net_request_lobby() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == room_owner:
		exit_to_lobby()


@rpc("authority", "call_remote", "reliable")
func net_return_to_lobby(revision: int) -> void:
	if revision > _map_revision:
		_map_revision = revision
		_return_to_lobby()


func _return_to_lobby() -> void:
	_clear_match_map()
	_waiting_for_host = false
	_loading = false
	get_tree().paused = false
	GameSettings.set_match_audio_enabled(false)
	if not Net.dedicated:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		$HUD/Lobby.return_from_match()


func leave_round() -> void:
	_reload_main_menu()


func _reload_main_menu() -> void:
	if _reloading:
		return
	_reloading = true
	_return_to_main_menu.call_deferred()


func _return_to_main_menu() -> void:
	var tree := get_tree()
	var scene := load(ARENA_SCENE) as PackedScene
	if scene == null:
		_reloading = false
		push_error("Не удалось загрузить главное меню.")
		return
	GameSettings.set_match_audio_enabled(false)
	_stop_round_effects()
	$Ambience.stop()
	Net.leave_game()
	tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var error := tree.change_scene_to_packed(scene)
	if error != OK:
		_reloading = false
		push_error("Не удалось открыть главное меню: %s" % error_string(error))


@rpc("authority", "reliable")
func net_restart() -> void:
	_stop_overview()
	$HUD/WeaponSelect.hide_for_results()
	$HUD/MatchMenu.close()
	_finish_reason = ""
	_final_rows.clear()
	$Ballistics.reset_round()
	$Grenades.reset_round()
	$Fieldworks.reset_round()
	$Map.clear_bullet_holes()
	var fixtures := get_node_or_null("Map/VillageFixtures")
	if fixtures:
		fixtures.reset_round()
	$HUD.reset_round()
	$Loot.reset_round()
	for player in get_tree().get_nodes_in_group("player"):
		player.restart_round()
	for bot in get_tree().get_nodes_in_group("bot"):
		bot.restart_round()
	_reset_clock()
	GameSettings.set_match_audio_enabled(true)
	_play_ambience()
	var local := combatant(Net.local_id())
	if local:
		if local.control_enabled:
			$HUD/Crosshair.show()
			GameSettings.capture_gameplay_mouse()
		else:
			$HUD/WeaponSelect.show_select()


@rpc("authority", "reliable")
func net_score_snapshot(scores: Dictionary, team_score := Vector2i.ZERO) -> void:
	_team_score = team_score
	$HUD.apply_score_snapshot(scores)


func _map_for_match(selected: int) -> int:
	if random_map_each_match:
		var choices: Array[int] = []
		for arena in MAP_NAMES.size():
			if arena != MAP.TEST_RANGE_ID and arena != _previous_match_map:
				choices.append(arena)
		selected = choices.pick_random()
	_previous_match_map = selected
	return selected


func move_lobby_player(peer: int, team: int, swap_peer := 0) -> void:
	if Net.active and not multiplayer.is_server():
		if room_owner == Net.local_id():
			net_move_lobby_player.rpc_id(1, peer, team, swap_peer)
		return
	if _started or _loading or team not in [0, 1] or peer <= 0:
		return
	if Net.active and not team_deathmatch:
		return
	var from := player_slots.find(peer)
	if from < 0 or from % 2 == team:
		return
	if swap_peer > 0:
		var to := player_slots.find(swap_peer)
		if to >= 0 and to % 2 == team:
			player_slots[from] = swap_peer
			player_slots[to] = peer
			_send_room_state()
		return
	for to in range(team, player_slots.size(), 2):
		if player_slots[to] == 0:
			player_slots[from] = 0
			player_slots[to] = peer
			_send_room_state()
			return


@rpc("any_peer", "reliable")
func net_move_lobby_player(peer: int, team: int, swap_peer: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == room_owner:
		move_lobby_player(peer, team, swap_peer)


func start_solo(bot_count: int, difficulty: int, weapons: int, arena: int, limits: Vector2i, size: int, teams: bool = false, random_map := false, blue_bots := -1) -> void:
	if _started or _loading or Net.active:
		return
	_show_loading()
	Net.play_solo()
	team_deathmatch = teams
	random_map_each_match = random_map
	blue_bot_count = clampi(blue_bots, -1, MAX_BOTS)
	_set_limits(limits)
	weapon_set = weapons
	map_id = _map_for_match(arena)
	lobby_map_size = clampi(size, 0, MAP.SIZE_WIDTHS.size() - 1)
	map_size = _selected_map_size(map_id, lobby_map_size)
	bot_difficulty = clampi(difficulty, 0, DIFFICULTY_NAMES.size() - 1)
	_solo_bot_count = clampi(bot_count, 0, MAX_BOTS)
	_reserve_bot_slots(_solo_bot_count)
	await _load_arena(randi(), _solo_bot_count, bot_difficulty)
	_started = true
	if map_id != MAP.BREAKWATER_ID:
		_spawn_player(1, player_slots.find(1))
	await _finish_loading()


func update_host_rules(weapons: int, arena: int, limits: Vector2i, difficulty: int, bot_count: int, size: int, teams: bool = false, random_map := false, blue_bots := -1) -> void:
	if Net.active and not multiplayer.is_server():
		if room_owner != multiplayer.get_unique_id():
			return
		net_request_rules.rpc_id(1, weapons, arena, limits, difficulty, bot_count, size, teams, random_map, blue_bots)
		return
	if _started or _loading or not Net.active or not multiplayer.is_server():
		return
	_apply_room_rules(weapons, arena, limits, difficulty, bot_count, size, teams, random_map, blue_bots)
	_send_room_state()


func create_internet_room(weapons: int, arena: int, limits: Vector2i, difficulty: int, bot_count: int, size: int, teams: bool = false, random_map := false, blue_bots := -1) -> void:
	if not Net.internet or multiplayer.is_server() or room_owner != 0 or _started or _loading:
		return
	net_create_room.rpc_id(1, weapons, arena, limits, difficulty, bot_count, size, teams, random_map, blue_bots)


func start_host_match() -> void:
	if Net.internet and not multiplayer.is_server():
		if room_owner != multiplayer.get_unique_id() or _started or is_loading():
			return
		# Не ставить _loading: net_begin от сервера иначе решит, что арена уже грузится, и хост зависнет.
		_waiting_for_host = true
		$HUD/MatchMenu.close()
		$HUD/Lobby.show_loading()
		$HUD/Lobby.set_loading_stage("Сервер готовит арену…")
		net_request_start.rpc_id(1)
		return
	if _started or _loading or not Net.active or not multiplayer.is_server():
		return
	var token := _load_token
	map_id = _map_for_match(map_id)
	map_size = _selected_map_size(map_id, lobby_map_size)
	_show_loading()
	for peer in player_slots:
		if peer > 1:
			net_wait_for_arena.rpc_id(peer)
	_layout_seed = randi()
	_reserve_bot_slots(lan_bot_count)
	await _begin_network_match(weapon_set, map_id, _layout_seed, Vector2i(time_option, kill_option), bot_difficulty, lan_bot_count, map_size)
	if token != _load_token or _reloading or not Net.active:
		return
	for peer in player_slots:
		if peer > 1:
			_send_begin(peer)
	if not Net.dedicated and player_slots.count(0) == Net.MAX_PLAYERS - 1:
		$HUD.show_host_ip(Net.lan_addresses())
	if Net.dedicated:
		print("Матч начат: %s, игроков %d." % [MAP_NAMES[map_id], _connected_players()])
		_write_room_status()


func _apply_room_rules(weapons: int, arena: int, limits: Vector2i, difficulty: int, bot_count: int, size: int, teams: bool = false, random_map := false, blue_bots := -1) -> void:
	team_deathmatch = teams
	random_map_each_match = random_map
	blue_bot_count = clampi(blue_bots, -1, MAX_BOTS)
	weapon_set = clampi(weapons, 0, WEAPON_SET_NAMES.size() - 1)
	map_id = clampi(arena, 0, MAP_NAMES.size() - 1)
	lobby_map_size = clampi(size, 0, MAP.SIZE_WIDTHS.size() - 1)
	map_size = _selected_map_size(map_id, lobby_map_size)
	_set_limits(limits)
	bot_difficulty = clampi(difficulty, 0, DIFFICULTY_NAMES.size() - 1)
	lan_bot_count = clampi(bot_count, 0, MAX_BOTS)


func _send_room_state() -> void:
	if not Net.dedicated:
		$HUD/Lobby.refresh_room()
	for peer in player_slots:
		if peer > 1:
			net_room_state.rpc_id(peer, weapon_set, map_id, player_slots, Vector2i(time_option, kill_option), bot_difficulty, lan_bot_count, _display_names, lobby_map_size, room_owner, team_deathmatch, random_map_each_match, blue_bot_count)


@rpc("any_peer", "reliable")
func net_create_room(weapons: int, arena: int, limits: Vector2i, difficulty: int, bot_count: int, size: int, teams: bool = false, random_map := false, blue_bots := -1) -> void:
	if not Net.dedicated or not multiplayer.is_server() or _started or _loading:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not player_slots.has(sender):
		return
	if room_owner != 0:
		_send_room_state()
		return
	room_owner = sender
	_apply_room_rules(weapons, arena, limits, difficulty, bot_count, size, teams, random_map, blue_bots)
	print("Комнату создал игрок %d: %s." % [sender, MAP_NAMES[map_id]])
	_send_room_state()


@rpc("any_peer", "reliable")
func net_request_rules(weapons: int, arena: int, limits: Vector2i, difficulty: int, bot_count: int, size: int, teams: bool = false, random_map := false, blue_bots := -1) -> void:
	if not Net.dedicated or not multiplayer.is_server() or multiplayer.get_remote_sender_id() != room_owner:
		return
	update_host_rules(weapons, arena, limits, difficulty, bot_count, size, teams, random_map, blue_bots)


@rpc("any_peer", "reliable")
func net_request_start() -> void:
	if not Net.dedicated or not multiplayer.is_server() or multiplayer.get_remote_sender_id() != room_owner:
		return
	start_host_match()


@rpc("any_peer", "reliable")
func net_request_restart() -> void:
	if not Net.dedicated or not multiplayer.is_server() or multiplayer.get_remote_sender_id() != room_owner:
		return
	restart_round()


@rpc("any_peer", "reliable")
func net_request_next_map(arena: int) -> void:
	if not Net.dedicated or not multiplayer.is_server() or multiplayer.get_remote_sender_id() != room_owner:
		return
	start_next_map(arena)


@rpc("authority", "call_remote", "reliable")
func net_refused(message: String) -> void:
	Net.notice = message
	_reload_main_menu()


@rpc("authority", "reliable")
func net_room_owner(owner: int) -> void:
	room_owner = owner


@rpc("authority", "reliable")
func net_room_state(weapons: int, arena: int, roster: PackedInt32Array, limits: Vector2i,
		difficulty: int, bot_count: int, names: Dictionary[int, String], size: int, owner: int, teams: bool, random_map: bool, blue_bots: int) -> void:
	if _started or _loading:
		return
	var editing: bool = Net.internet and owner == 0 and $HUD/Lobby.is_editing_setup()
	if editing:
		player_slots = roster
		_display_names = names
	else:
		team_deathmatch = teams
		random_map_each_match = random_map
		blue_bot_count = blue_bots
		weapon_set = weapons
		map_id = arena
		lobby_map_size = clampi(size, 0, MAP.SIZE_WIDTHS.size() - 1)
		map_size = _selected_map_size(arena, lobby_map_size)
		player_slots = roster
		_set_limits(limits)
		bot_difficulty = clampi(difficulty, 0, DIFFICULTY_NAMES.size() - 1)
		lan_bot_count = bot_count
		_display_names = names
	room_owner = owner
	if Net.internet:
		$HUD/Lobby.show_internet_room()
	else:
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
		difficulty: int, bot_count: int, revision: int, size: int, teams: bool, bot_slots: PackedInt32Array,
		random_map: bool, preferred_size: int, blue_bots: int) -> void:
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
	team_deathmatch = teams
	_bot_slots = bot_slots
	random_map_each_match = random_map
	lobby_map_size = preferred_size
	blue_bot_count = blue_bots
	_show_loading()
	await _begin_network_match(weapons, arena, layout_seed, limits, difficulty, bot_count, size)
	if not _reloading and Net.active:
		net_ready.rpc_id(1, revision)


func _send_begin(peer: int) -> void:
	net_begin.rpc_id(peer, weapon_set, map_id, player_slots, _layout_seed, Vector2i(time_option, kill_option),
		bot_difficulty, lan_bot_count, _map_revision, map_size, team_deathmatch, _bot_slots,
		random_map_each_match, lobby_map_size, blue_bot_count)


func _load_current(token: int) -> bool:
	return token == _load_token and not _reloading and Net.active


func _begin_network_match(weapons: int, arena: int, layout_seed: int, limits: Vector2i, difficulty: int, bot_count: int, size: int) -> void:
	var token := _load_token
	weapon_set = weapons
	map_id = arena
	map_size = _selected_map_size(arena, size)
	_set_limits(limits)
	bot_difficulty = clampi(difficulty, 0, DIFFICULTY_NAMES.size() - 1)
	lan_bot_count = bot_count
	await _load_arena(layout_seed, bot_count, bot_difficulty, token)
	if not _load_current(token):
		return
	_started = true
	if map_id != MAP.BREAKWATER_ID:
		for slot in player_slots.size():
			if player_slots[slot] != 0:
				_spawn_player(player_slots[slot], slot)
	await _finish_loading()


func _show_loading() -> void:
	_waiting_for_host = false
	_loading = true
	if Net.dedicated:
		return
	$HUD/MatchMenu.close()
	$HUD/Lobby.show_loading()


func _loading_stage(message: String) -> void:
	if Net.dedicated:
		print(message)
	else:
		$HUD/Lobby.set_loading_stage(message)
	await get_tree().process_frame
	if not Net.dedicated and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	await get_tree().process_frame


func _load_arena(layout_seed: int, bot_count: int, difficulty: int, token: int = -1) -> void:
	await _loading_stage("Подгружаем текстуры…")
	if token >= 0 and not _load_current(token):
		return
	await $Map.preload_textures(map_id)
	if token >= 0 and not _load_current(token):
		return
	await _loading_stage("Собираем карту…")
	_build_arena(layout_seed)
	await _loading_stage("Подгружаем оружие и звуки…")
	if token >= 0 and not _load_current(token):
		return
	$Ballistics.prepare_acoustics()
	await CLASSIC_WEAPONS.prepare(get_tree(), WEAPON_SETS[weapon_set])
	if token >= 0 and not _load_current(token):
		return
	await _loading_stage("Готовим бойцов…")
	if map_id != MAP.BREAKWATER_ID:
		await _spawn_bots(bot_count, difficulty, token)
	while _navigation_pending and not _reloading and (token < 0 or _load_current(token)):
		await get_tree().process_frame
	if not _reloading and (token < 0 or _load_current(token)):
		var fixtures := get_node_or_null("Map/VillageFixtures")
		if fixtures:
			fixtures.reset_round()


func _finish_loading() -> void:
	if Net.dedicated:
		_loading = false
		if not _reloading:
			_reset_clock()
		return
	var warmup := WEAPON_SCRIPT.render_warmup(WEAPON_SETS[weapon_set])
	add_child(warmup)
	var props: Node3D = $Loot.warm_rendering()
	await _loading_stage("Готовим первый кадр…")
	if DisplayServer.get_name() != "headless":
		await $Ballistics.warm_effects()
		await $Grenades.warm_smoke()
	warmup.queue_free()
	props.queue_free()
	if _reloading:
		return
	_loading = false
	GameSettings.set_match_audio_enabled(true)
	_reset_clock()
	if map_id == MAP.BREAKWATER_ID and not combatant(Net.local_id()):
		$HUD/Lobby.set_loading_stage("Ожидаем безопасную точку появления…")
	else:
		$HUD/Lobby.hide_lobby()
		_play_ambience()
		$HUD/WeaponSelect.show_select()


func _play_ambience() -> void:
	if Net.dedicated or map_id != MAP.DUST2_ID or $Ambience.playing:
		return
	if $Ambience.stream == null:
		$Ambience.stream = load("res://assets/match_audio/dust2_wind.ogg")
	$Ambience.play()


func _grade_arena(environment: Environment) -> void:
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0
	environment.ssao_radius = 1.25
	environment.ssao_intensity = 1.2
	environment.ambient_light_energy = 0.78
	if map_id == MAP.OFFICE_ID:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color("#cbd6df")
		environment.ambient_light_energy = 0.34
	elif map_id == MAP.BREAKWATER_ID:
		environment.ambient_light_energy = 0.58
	else:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_sky_contribution = 0.8


func _build_arena(layout_seed: int) -> void:
	if map_id == MAP.BREAKWATER_ID:
		$WorldEnvironment.environment = null
		$WorldEnvironment/SunLight.hide()
		$WorldEnvironment/MoonLight.hide()
		_breakwater = BREAKWATER_SCENE.instantiate()
		$Map.add_child(_breakwater)
		_breakwater.apply_layout(map_size)
		_grade_arena(_breakwater.get_node("WorldEnvironment").environment)
		$Loot.build_crates(_breakwater.get_supply_placements())
	else:
		var weather: Dictionary = ARENA_WEATHER[map_id]
		$WorldEnvironment.current_time = weather.hour
		var wind: Vector2 = weather.wind
		$WorldEnvironment.wind_direction = deg_to_rad(wind.x)
		$WorldEnvironment.wind_speed = wind.y
		_grade_arena($WorldEnvironment.environment)
		if map_id == MAP.OFFICE_ID:
			$WorldEnvironment/SunLight.hide()
			$WorldEnvironment/MoonLight.hide()
		var supplies: Array[Transform3D] = $Map.build(map_id, layout_seed, arena_width())
		$Loot.build_crates(supplies, $Map.market_supply_count)
	_apply_graphics()
	if not Net.dedicated:
		var bounds := _breakwater.get_arena_bounds() if is_instance_valid(_breakwater) else Rect2()
		$HUD.set_minimap_layout($Map, maxf(arena_width(), bounds.size.y), bounds)
	if not Net.active or multiplayer.is_server():
		var mesh := NavigationMesh.new()
		mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		mesh.geometry_collision_mask = Balance.WORLD_MASK
		var village := map_id == MAP.VILLAGE_ID
		mesh.cell_size = 0.25 if village else 0.20
		mesh.cell_height = 0.1
		mesh.agent_radius = 0.50 if village else 0.40
		mesh.agent_height = 1.8
		mesh.agent_max_climb = 0.3 if village else 0.1
		mesh.filter_walkable_low_height_spans = true
		var width := arena_width()
		if is_instance_valid(_breakwater):
			var bounds := _breakwater.get_arena_bounds()
			mesh.filter_baking_aabb = AABB(Vector3(bounds.position.x, -0.5, bounds.position.y),
				Vector3(bounds.size.x, 4.5, bounds.size.y))
		elif map_id == MAP.DUST2_ID:
			mesh.filter_baking_aabb = AABB(Vector3(-width * 0.5, -3.0, -width * 0.5), Vector3(width, 7.5, width))
		else:
			var bake_bottom := -1.3 if village else -0.5
			var bake_height := 7.1 if village else 2.8
			mesh.filter_baking_aabb = AABB(Vector3(-width * 0.5, bake_bottom, -width * 0.5), Vector3(width, bake_height, width))
		var geometry := NavigationMeshSourceGeometryData3D.new()
		var fixtures := $Map.get_node_or_null("VillageFixtures")
		# Bots can open doors on their path. Bake the openings as traversable.
		if fixtures:
			fixtures.set_door_collision(false)
		NavigationServer3D.parse_source_geometry_data(mesh, geometry, self)
		if fixtures:
			fixtures.set_door_collision(true)
		_navigation_pending = true
		NavigationServer3D.bake_from_source_geometry_data_async(mesh, geometry, _on_navigation_baked.bind(mesh, _load_token))


func _on_navigation_baked(mesh: NavigationMesh, token: int) -> void:
	_install_navigation.call_deferred(mesh, token)


func _install_navigation(mesh: NavigationMesh, token: int) -> void:
	if not is_inside_tree() or _reloading or token != _load_token:
		return
	_navigation_region = NavigationRegion3D.new()
	_navigation_region.navigation_mesh = mesh
	add_child(_navigation_region)
	_navigation_pending = false


func _set_limits(limits: Vector2i) -> void:
	time_option = clampi(limits.x, 0, TIME_LIMITS.size() - 1)
	kill_option = clampi(limits.y, 0, KILL_LIMITS.size() - 1)


func _reset_clock() -> void:
	_team_score = Vector2i.ZERO
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
	if limit > 0 and map_id != MAP.BREAKWATER_ID:
		var elapsed := clampi(limit - seconds, 0, limit)
		var sky_hour := float(ARENA_WEATHER[map_id].hour) + float(elapsed - elapsed % 15) / 1500.0
		if not is_equal_approx($WorldEnvironment.current_time, sky_hour):
			$WorldEnvironment.current_time = sky_hour
			_apply_graphics()


func _finish_round(reason: String) -> void:
	if round_finished():
		return
	if team_deathmatch:
		var winner := "Ничья" if _team_score.x == _team_score.y else ("Команда 1 победила" if _team_score.x > _team_score.y else "Команда 2 победила")
		reason = "%s (%d–%d) · %s" % [winner, _team_score.x, _team_score.y, reason]
	var rows: Array = $HUD.score_rows(false)
	net_finish(reason, rows)
	for peer in _ready_peers:
		net_finish.rpc_id(peer, reason, rows)


@rpc("authority", "reliable")
func net_finish(reason: String, rows: Array) -> void:
	_finish_reason = reason
	_final_rows = rows
	GameSettings.set_match_audio_enabled(false)
	$Ambience.stop()
	_stop_round_effects.call_deferred()
	$HUD/Lobby.hide_lobby()
	$HUD/WeaponSelect.hide_for_results()
	$HUD/MatchMenu.show_results(reason, rows)
	if not Net.dedicated and DisplayServer.get_name() != "headless" and not is_instance_valid(_round_overview):
		_round_overview = ROUND_OVERVIEW.new()
		add_child(_round_overview)
		_round_overview.start(arena_width())


func _stop_overview() -> void:
	if is_instance_valid(_round_overview):
		_round_overview.stop()
		_round_overview = null


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


func _reserve_bot_slots(count: int) -> void:
	_bot_slots.clear()
	if not team_deathmatch and map_id != MAP.BREAKWATER_ID:
		return
	var open_slots: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
	var team_sizes := Vector2i.ZERO
	for slot in player_slots.size():
		var team := slot % 2
		if player_slots[slot] == 0:
			open_slots[team].append(slot)
		else:
			team_sizes[team] += 1
	for _index in mini(count, open_slots[0].size() + open_slots[1].size()):
		var team := 0 if team_sizes.x <= team_sizes.y else 1
		if team_deathmatch and blue_bot_count >= 0:
			team = 0 if _index < blue_bot_count else 1
		if open_slots[team].is_empty():
			team = 1 - team
		_bot_slots.append(open_slots[team][0])
		open_slots[team].remove_at(0)
		team_sizes[team] += 1


func _spawn_bots(count: int, difficulty: int, token: int = -1) -> void:
	if team_deathmatch:
		count = _bot_slots.size()
	for index in count:
		if token >= 0 and not _load_current(token):
			return
		if team_deathmatch and player_slots[_bot_slots[index]] != 0:
			continue
		var slot := _bot_slots[index] if team_deathmatch else 0
		var team_start := team_deathmatch and map_id in [MAP.VILLAGE_ID, MAP.WORKSHOP_ID, MAP.OFFICE_ID]
		var spawn_index := slot if team_start else Net.MAX_PLAYERS + index
		var bot := _add_bot(index, slot, difficulty, $Map.initial_spawn(spawn_index))
		if not Net.active or multiplayer.is_server():
			bot.equip(random_weapon())
		if index % 2 == 1 and index + 1 < count:
			await get_tree().process_frame


func _add_bot(index: int, slot: int, difficulty: int, at: Vector3) -> Node:
	var bot := PLAYER_SCENE.instantiate()
	bot.set_script(BOT_SCRIPT)
	bot.name = "Bot%d" % index
	bot.combatant_id = -index
	bot.slot = slot
	bot.position = at
	bot.spawn_position = at
	if is_instance_valid(_breakwater):
		var route: Array[Vector3] = []
		for marker in _breakwater.get_spawn_candidates():
			route.append(_breakwater.spawn_feet(marker))
		bot.patrol_route = route
	else:
		bot.patrol_route = $Map.patrol_route()
	bot.difficulty = difficulty
	bot.floor_snap_length = 0.2
	add_child(bot)
	return bot


func same_team(first: int, second: int) -> bool:
	if not team_deathmatch or first == second:
		return false
	var first_actor := combatant(first)
	var second_actor := combatant(second)
	return first_actor != null and second_actor != null and first_actor.team_id() == second_actor.team_id()


func is_local_teammate(team: int) -> bool:
	if not team_deathmatch or Net.dedicated:
		return false
	var local_slot := player_slots.find(Net.local_id())
	return local_slot >= 0 and local_slot % 2 == team


func allows_damage(attacker: int, victim: int) -> bool:
	return Balance.MATCH.friendly_fire_enabled or not same_team(attacker, victim)


func announce(killer_id: int, victim_id: int) -> void:
	var killer := combatant(killer_id)
	var team: int = killer.team_id() if team_deathmatch and killer and killer_id != victim_id else -1
	for peer in _ready_peers:
		net_frag.rpc_id(peer, killer_id, victim_id, team)
	net_frag(killer_id, victim_id, team)
	var limit: int = KILL_LIMITS[kill_option]
	var score: int = _team_score[team] if team >= 0 else $HUD.kills_for(killer_id)
	if killer_id != victim_id and limit > 0 and score >= limit:
		_finish_round.call_deferred("Достигнут лимит убийств")


func publish_damage(attacker: int, victim: int, source: String, zone: String,
		hp_damage: float, armor_damage: float, killed: bool, reaction: Dictionary = {}) -> void:
	_damage_sequence += 1
	var event := {
		"event_id": _damage_sequence, "server_tick": Engine.get_physics_frames(),
		"attacker_peer_id": attacker, "victim_peer_id": victim,
		"source_id": source, "zone_id": zone, "hp_damage": hp_damage,
		"armor_damage": armor_damage, "is_kill": killed,
	}
	if not reaction.is_empty():
		event["reaction"] = reaction
	net_damage_event(event)
	for peer in _ready_peers:
		net_damage_event.rpc_id(peer, event)


@rpc("authority", "reliable")
func net_damage_event(event: Dictionary) -> void:
	if int(event.event_id) <= _latest_damage_event:
		return
	_latest_damage_event = int(event.event_id)
	if event.has("reaction"):
		var victim := combatant(int(event.victim_peer_id))
		if victim:
			victim.show_hit_reaction(event.reaction)
	damage_resolved.emit(event)


@rpc("authority", "reliable")
func net_frag(killer_id: int, victim_id: int, team := -1) -> void:
	if team in [0, 1]:
		_team_score[team] += 1
	$HUD.on_frag(killer_id, victim_id)


func _spawn_player(peer_id: int, slot: int, at: Vector3 = Vector3.INF) -> void:
	if team_deathmatch:
		var index := _bot_slots.find(slot)
		var bot := get_node_or_null("Bot%d" % index) if index >= 0 else null
		if bot:
			$HUD.remove_score(bot.combatant_id)
			remove_child(bot)
			bot.queue_free()
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.slot = slot
	player.set_multiplayer_authority(peer_id, true)
	player.spawn_position = at if at.is_finite() else $Map.initial_spawn(slot)
	player.position = player.spawn_position
	add_child(player)
	if not Net.active or player.is_multiplayer_authority():
		$HUD/MatchMenu.close()
		$HUD.attach_local(player)
		if not _loading:
			$HUD/Lobby.hide_lobby()
			$HUD/WeaponSelect.show_select()
	else:
		player.set_name_label(_match_player_label(slot))
	$HUD.refresh_score()


func _spawn_breakwater_fighters() -> void:
	# Process players before bots. Unarmed players reserve a capsule but cannot threaten a spawn.
	for slot in player_slots.size():
		var id := player_slots[slot]
		if id == 0 or combatant(id) or (id != 1 and not _ready_peers.has(id)):
			continue
		var at := _choose_safe_spawn(null, slot, Vector3.INF, _breakwater_spawn_candidates(slot))
		if at.is_finite():
			_spawn_player(id, slot, at)
			_send_breakwater_spawn(id, slot, at)
	var new_bots: Array[Node] = []
	for index in _bot_slots.size():
		var slot := _bot_slots[index]
		if slot < 0 or player_slots[slot] != 0 or combatant(-index):
			continue
		var at := _choose_safe_spawn(null, slot, Vector3.INF, _breakwater_spawn_candidates(slot))
		if at.is_finite():
			new_bots.append(_add_bot(index, slot, bot_difficulty, at))
			_send_breakwater_spawn(-index, slot, at)
	for bot in new_bots:
		bot.equip(random_weapon())


func _send_breakwater_spawn(id: int, slot: int, at: Vector3) -> void:
	for peer in _ready_peers:
		net_breakwater_spawn.rpc_id(peer, _map_revision, id, slot, at)


func ping_for(id: int) -> int:
	return _ping_by_peer.get(id, -1)


func _sync_ping_snapshot(delta: float) -> void:
	if not Net.active or not multiplayer.is_server():
		return
	_ping_time += delta
	if _ping_time < 1.0:
		return
	_ping_time = fmod(_ping_time, 1.0)
	var snapshot: Dictionary[int, int] = {}
	for peer in player_slots:
		if peer > 1:
			snapshot[peer] = Net.peer_ping_ms(peer)
	_ping_by_peer = snapshot
	net_ping_snapshot(_ping_by_peer)
	for peer in _ready_peers:
		net_ping_snapshot.rpc_id(peer, _ping_by_peer)


@rpc("authority", "unreliable")
func net_ping_snapshot(snapshot: Dictionary) -> void:
	_ping_by_peer.clear()
	for peer: Variant in snapshot:
		_ping_by_peer[int(peer)] = int(snapshot[peer])


@rpc("authority", "reliable")
func net_breakwater_spawn(revision: int, id: int, slot: int, at: Vector3) -> void:
	if revision != _map_revision or not is_instance_valid(_breakwater) or combatant(id):
		return
	if id > 0:
		_spawn_player(id, slot, at)
	else:
		_add_bot(-id, slot, bot_difficulty, at)


func _physics_process(delta: float) -> void:
	if Net.match_server:
		_status_time += delta
		if _status_time >= 1.0:
			_status_time = 0.0
			_write_room_status()
	if not _started or _loading or round_finished():
		return
	_sync_ping_snapshot(delta)
	if is_instance_valid(_breakwater) and (not Net.active or multiplayer.is_server()):
		_spawn_retry_left -= delta
		if _spawn_retry_left <= 0.0:
			_spawn_retry_left = BREAKWATER_SPAWN_RETRY
			_spawn_breakwater_fighters()
	if not Net.dedicated and map_id != MAP.BREAKWATER_ID:
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
			net_poses.rpc_id(peer, poses, combat_time())
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
	if absf(pose[4]) > deg_to_rad(80.1) or pose[12] < 1.0 or pose[12] != floorf(pose[12]):
		return false
	for index in [5, 6, 7, 8, 10]:
		if pose[index] != 0.0 and pose[index] != 1.0:
			return false
	var previous: PackedFloat32Array = player._latest_pose
	var destination := Vector3(pose[0], pose[1], pose[2])
	var origin: Vector3 = player.global_position
	var elapsed := 0.12
	var travel_budget := 0.4
	if not previous.is_empty():
		if pose[12] <= previous[12]:
			return pose[12] >= previous[12] - 8.0
		origin = Vector3(previous[0], previous[1], previous[2])
		elapsed = clampf(combat_time() - float(player._pose_received_at), 0.0,
			float(Balance.NETWORK.pose_recovery_window_s))
		travel_budget = player._pose_travel_budget
	var travel := destination - origin
	var horizontal := Vector2(travel.x, travel.z).length()
	# A packet gap may span more travel than the normal burst allowance.
	var elapsed_travel := float(player.SPRINT_SPEED) * elapsed
	travel_budget = minf(maxf(1.4, elapsed_travel), travel_budget + elapsed_travel)
	if horizontal > travel_budget:
		return false
	if absf(travel.y) > 22.0 * minf(elapsed, 0.25) + 0.55:
		return false
	if travel.length_squared() > 0.0001:
		var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.65, destination + Vector3.UP * 0.65, Balance.WORLD_MASK)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return false
	player._pose_travel_budget = travel_budget - horizontal
	player.apply_network_pose(pose)
	return true


func combat_time() -> float:
	return Time.get_ticks_usec() * 0.000001


func estimated_server_time() -> float:
	return combat_time() + _server_clock_offset if _server_clock_synced else 0.0


func rewind_time(sent_time: float) -> float:
	var now := combat_time()
	if sent_time == 0.0:
		return now - float(Balance.NETWORK.remote_interpolation_delay_s)
	if not is_finite(sent_time) or sent_time > now + float(Balance.NETWORK.max_future_shot_skew_s) or sent_time < now - float(Balance.NETWORK.hitbox_history_s):
		return -1.0
	var viewed_time := sent_time - float(Balance.NETWORK.remote_interpolation_delay_s)
	return clampf(viewed_time, now - float(Balance.NETWORK.max_lag_compensation_s), now)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func net_poses(poses: Dictionary[int, PackedFloat32Array], server_time: float) -> void:
	if round_finished():
		return
	var transport := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var server := transport.get_peer(1) if transport else null
	if server:
		# ENet starts with a high RTT estimate before the first acknowledgements.
		var travel_time := minf(float(Balance.NETWORK.max_future_shot_skew_s) * 0.75,
			server.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) * 0.0005)
		var sample := server_time + travel_time - combat_time()
		_server_clock_offset = lerpf(_server_clock_offset, sample, 0.10) if _server_clock_synced else sample
		_server_clock_synced = true
	for peer in poses:
		if peer == Net.local_id():
			continue
		var actor := combatant(peer)
		if actor:
			actor.apply_network_pose(poses[peer])


func _on_joined() -> void:
	if Net.browsing:
		$HUD/Lobby.show_room_browser()
		return
	if Net.match_client:
		$HUD/Lobby.show_internet_wait("Входим в комнату…")
		submit_room_auth()
		return
	if Net.internet:
		$HUD/Lobby.show_internet_wait()
	else:
		$HUD/Lobby.show_guest_room()
	set_local_display_name(Net.display_name)


func submit_room_auth() -> void:
	if not Net.match_client:
		return
	net_auth.rpc_id(1, Net.pending_password, Net.pending_token)


func _on_connection_failed() -> void:
	if $HUD/Lobby.is_on_main():
		$HUD/Lobby.join_failed()
		return
	if Net.notice.is_empty():
		Net.notice = "Не удалось войти в комнату."
	_reload_main_menu()


func _on_peer_connected(id: int) -> void:
	if Net.match_server:
		return
	if Net.active and multiplayer.is_server():
		call_deferred("_welcome", id)


@rpc("any_peer", "reliable")
func net_auth(password: String, token: String) -> void:
	if not Net.match_server or not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender) or player_slots.has(sender):
		return
	if password != _room_password:
		net_refused.rpc_id(sender, "Неверный пароль")
		multiplayer.multiplayer_peer.disconnect_peer(sender)
		return
	if player_slots.find(0) < 0:
		net_refused.rpc_id(sender, "Комната заполнена")
		multiplayer.multiplayer_peer.disconnect_peer(sender)
		return
	if token != "" and token == _owner_token and room_owner == 0:
		room_owner = sender
		_owner_token = ""
	_had_player = true
	_welcome(sender)
	_write_room_status()


func _welcome(id: int) -> void:
	if not Net.active or not multiplayer.is_server() or not multiplayer.get_peers().has(id):
		return
	if player_slots.has(id):
		return
	var slot := player_slots.find(0)
	if slot < 0:
		net_refused.rpc_id(id, "Комната заполнена")
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	_set_slot(slot, id)
	if Net.dedicated:
		print("Подключился игрок %d. В комнате %d." % [id, _connected_players()])
	if _started:
		_send_slot(slot, id, id)
		_send_begin(id)
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
	if is_instance_valid(_breakwater):
		for actor in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("bot"):
			net_breakwater_spawn.rpc_id(id, _map_revision, actor.score_id(), actor.slot, actor.global_position)
	for bot in get_tree().get_nodes_in_group("bot"):
		bot.send_status_to(id)
	$Map.send_bullet_holes(id)
	var fixtures := get_node_or_null("Map/VillageFixtures")
	if fixtures:
		fixtures.send_state(id)
	$Loot.send_state(id)
	$Grenades.send_state(id)
	$Fieldworks.send_state(id)
	for player in get_tree().get_nodes_in_group("player"):
		player.send_status_to(id)
	net_score_snapshot.rpc_id(id, $HUD.score_snapshot(), _team_score)
	net_clock.rpc_id(id, _display_seconds)
	if round_finished():
		net_finish.rpc_id(id, _finish_reason, _final_rows)
	$HUD.hide_host_ip()


func _on_peer_disconnected(id: int) -> void:
	if not Net.active or not multiplayer.is_server():
		return
	var slot := player_slots.find(id)
	if slot < 0 or (id == 1 and not Net.dedicated):
		return
	_ready_peers.erase(id)
	_display_names.erase(id)
	var was_owner := id == room_owner
	_set_slot(slot, 0)
	if was_owner:
		room_owner = _next_room_owner()
	if Net.match_server and _had_player and _connected_players() == 0:
		_write_room_status()
		print("Комната закрыта.")
		get_tree().quit(0)
		return
	if Net.dedicated and not Net.match_server and _connected_players() == 0:
		_reset_dedicated_room()
		print("Комната пуста, сервер снова ждёт игроков.")
		return
	if _started:
		_send_slot(slot, 0)
		if was_owner:
			_broadcast_owner()
		if not Net.dedicated and _ready_peers.is_empty():
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


func _connected_players() -> int:
	var count := 0
	for peer in player_slots:
		if peer > 1:
			count += 1
	return count


func _next_room_owner() -> int:
	for peer in player_slots:
		if peer > 1:
			return peer
	return 0 if Net.dedicated else 1


func _broadcast_owner() -> void:
	for peer in player_slots:
		if peer > 1:
			net_room_owner.rpc_id(peer, room_owner)


func _load_match_room() -> bool:
	var cfg := ConfigFile.new()
	if Net.room_file.is_empty() or cfg.load(Net.room_file) != OK:
		print("Нет файла комнаты.")
		return false
	_room_password = str(cfg.get_value("room", "password", ""))
	_owner_token = str(cfg.get_value("room", "token", ""))
	_apply_room_rules(
		int(cfg.get_value("room", "weapons", 0)),
		int(cfg.get_value("room", "arena", 0)),
		Vector2i(int(cfg.get_value("room", "time", 4)), int(cfg.get_value("room", "kills", 5))),
		int(cfg.get_value("room", "difficulty", 1)),
		int(cfg.get_value("room", "bots", 1)),
		int(cfg.get_value("room", "size", 2)),
		bool(cfg.get_value("room", "teams", false)),
		bool(cfg.get_value("room", "random_map", false)),
		int(cfg.get_value("room", "blue_bots", -1))
	)
	DirAccess.remove_absolute(Net.room_file)
	_write_room_status()
	return _room_password != ""


func _write_room_status() -> void:
	if not Net.match_server or Net.room_status_path.is_empty():
		return
	var status := ConfigFile.new()
	status.set_value("room", "ready", true)
	status.set_value("room", "players", _connected_players())
	status.set_value("room", "playing", _started)
	status.set_value("room", "arena", map_id)
	status.save(Net.room_status_path)


func _reset_dedicated_room() -> void:
	room_owner = 0
	_ready_peers.clear()
	_display_names.clear()
	_finish_reason = ""
	_final_rows.clear()
	if _started or _loading:
		_clear_match_map()
	else:
		_load_token += 1
	_loading = false
	_waiting_for_host = false
	_started = false
	player_slots.fill(0)


func _set_slot(slot: int, id: int) -> void:
	var previous := player_slots[slot]
	player_slots[slot] = id
	if not _started:
		return
	if previous != 0:
		var player := get_node_or_null(str(previous))
		if player:
			remove_child(player)
			player.queue_free()
			$HUD.remove_score(previous)
	if id == 0:
		return
	if is_instance_valid(_breakwater):
		var index := _bot_slots.find(slot)
		if index >= 0:
			_bot_slots[index] = -1
			var bot := combatant(-index)
			if bot:
				remove_child(bot)
				bot.queue_free()
				$HUD.remove_score(-index)
	else:
		_spawn_player(id, slot)
