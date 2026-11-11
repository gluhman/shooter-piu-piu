extends Node3D

const PLAYER_SCENE := preload("res://player.tscn")
const BOT_SCRIPT := preload("res://bot.gd")
const MAP_NAMES := preload("res://map_builder.gd").MAP_NAMES
const WEAPON_SET_NAMES := ["Любое", "Только дробовики", "Только пистолеты и автоматы"]
const DIFFICULTY_NAMES := ["Легко", "Обычно", "Сложно"]
const WEAPON_SETS := [
	["deagle", "shotgun", "ak47"],
	["shotgun"],
	["deagle", "ak47"],
]

var map_id := 0
var weapon_set := 0
var guest_id := 0

var _reloading := false
var _started := false


func _ready() -> void:
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


func has_started() -> bool:
	return _started


func input_blocked() -> bool:
	return $HUD/MatchMenu.visible


func allows_weapon(id: String) -> bool:
	return id in WEAPON_SETS[weapon_set]


func can_restart() -> bool:
	return _started and (Net.solo or (Net.active and multiplayer.is_server()))


func restart_round() -> void:
	if not can_restart():
		return
	if Net.active:
		net_restart.rpc()
	else:
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


@rpc("authority", "call_local", "reliable")
func net_restart() -> void:
	$Ballistics.reset_round()
	$HUD.reset_round()
	for player in get_tree().get_nodes_in_group("player"):
		player.restart_round()
	for bot in get_tree().get_nodes_in_group("bot"):
		bot.restart_round()


@rpc("authority", "reliable")
func net_score_snapshot(scores: Dictionary) -> void:
	$HUD.apply_score_snapshot(scores)


func start_solo(bot_count: int, difficulty: int, weapons: int, arena: int) -> void:
	if _started or Net.active:
		return
	Net.play_solo()
	weapon_set = weapons
	map_id = arena
	$Map.build(map_id)
	_spawn_bots(clampi(bot_count, 1, 10), difficulty)
	_spawn_player(1)


func update_host_rules(weapons: int, arena: int) -> void:
	if _started or not Net.active or not multiplayer.is_server():
		return
	weapon_set = weapons
	map_id = arena
	if guest_id != 0:
		net_room_rules.rpc_id(guest_id, weapon_set, map_id)


func start_host_match() -> void:
	if _started or not Net.active or not multiplayer.is_server():
		return
	_begin_network_match(weapon_set, map_id, guest_id)
	if guest_id != 0:
		net_begin.rpc_id(guest_id, weapon_set, map_id, guest_id)
	else:
		$HUD.show_host_ip(Net.lan_addresses())


@rpc("authority", "reliable")
func net_room_rules(weapons: int, arena: int) -> void:
	if _started:
		return
	weapon_set = weapons
	map_id = arena
	$HUD/Lobby.refresh_room()


@rpc("authority", "reliable")
func net_begin(weapons: int, arena: int, guest: int) -> void:
	if not _started:
		_begin_network_match(weapons, arena, guest)


func _begin_network_match(weapons: int, arena: int, guest: int) -> void:
	weapon_set = weapons
	map_id = arena
	$Map.build(map_id)
	_spawn_bots(1, 1)
	_spawn_player(1)
	if guest != 0:
		_spawn_player(guest)
	if not multiplayer.is_server():
		net_ready.rpc_id(1)


func _spawn_bots(count: int, difficulty: int) -> void:
	var weapon := "deagle" if allows_weapon("deagle") else "shotgun"
	for index in count:
		var bot := BOT_SCRIPT.new()
		bot.name = "Bot%d" % index
		bot.combatant_id = -index
		bot.weapon_id = weapon
		bot.position = $Map.BOT_SPAWNS[index]
		bot.spawn_position = bot.position
		bot.patrol_route = $Map.PATROL_ROUTES[map_id]
		bot.difficulty = difficulty
		bot.floor_snap_length = 0.2
		add_child(bot)
		bot.begin(not Net.active or multiplayer.is_server())


func announce(killer_id: int, victim_id: int) -> void:
	if Net.active:
		net_frag.rpc(killer_id, victim_id)
	else:
		$HUD.on_frag(killer_id, victim_id)


@rpc("authority", "call_local", "reliable")
func net_frag(killer_id: int, victim_id: int) -> void:
	$HUD.on_frag(killer_id, victim_id)


func _spawn_player(peer_id: int) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id, true)
	player.position = Vector3(-14.6, 0.2, 14.2) if peer_id == 1 else Vector3(14.2, 0.2, -14.2)
	add_child(player)
	if Net.active:
		_add_player_sync(player, peer_id)
	if not Net.active or player.is_multiplayer_authority():
		_started = true
		$HUD/MatchMenu.close()
		$HUD.attach_local(player)
		$HUD/Lobby.hide_lobby()
		$HUD/WeaponSelect.show_select()
	$HUD.refresh_score()


func _add_player_sync(player: Node, peer_id: int) -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.root_path = NodePath("..")
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	config.add_property(NodePath("Camera3D:rotation"))
	config.add_property(NodePath(".:crouched"))
	config.add_property(NodePath(".:aiming"))
	sync.replication_config = config
	sync.replication_interval = 0.0
	sync.public_visibility = false
	player.add_child(sync)
	sync.set_multiplayer_authority(peer_id)
	if not multiplayer.is_server() and player.is_multiplayer_authority():
		sync.set_visibility_for(1, true)


func _on_joined() -> void:
	$HUD/Lobby.show_guest_room()


func _on_connection_failed() -> void:
	$HUD/Lobby.join_failed()


func _on_peer_connected(id: int) -> void:
	if Net.active and multiplayer.is_server():
		call_deferred("_welcome", id)


func _welcome(id: int) -> void:
	if not Net.active or not multiplayer.is_server() or not multiplayer.get_peers().has(id):
		return
	guest_id = id
	if _started:
		_spawn_player(id)
		net_begin.rpc_id(id, weapon_set, map_id, id)
	else:
		$HUD/Lobby.refresh_room()
		net_room_rules.rpc_id(id, weapon_set, map_id)


@rpc("any_peer", "reliable")
func net_ready() -> void:
	var id := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or not _started or id != guest_id or not has_node(str(id)):
		return
	$"1/Sync".set_visibility_for(id, true)
	$Bot0/Sync.set_visibility_for(id, true)
	get_node("1").send_weapon_to(id)
	net_score_snapshot.rpc_id(id, $HUD.score_snapshot())
	$HUD.hide_host_ip()


func _on_peer_disconnected(id: int) -> void:
	if not Net.active or not multiplayer.is_server() or id != guest_id:
		return
	guest_id = 0
	if not _started:
		$HUD/Lobby.refresh_room()
		return
	var player := get_node_or_null(str(id))
	if player:
		remove_child(player)
		player.queue_free()
	$HUD.show_host_ip(Net.lan_addresses(), "Соперник отключился.")
	$HUD.refresh_score()
