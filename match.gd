extends Node3D

const PLAYER_SCENE := preload("res://player.tscn")

var _reloading := false
var _started := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Net.joined.connect(_on_joined)
	Net.connection_failed.connect(_on_connection_failed)
	Net.host_lost.connect(_on_host_lost)
	GameSettings.graphics_changed.connect(_apply_graphics)
	_apply_graphics()


func _apply_graphics() -> void:
	$Sun.shadow_enabled = GameSettings.shadows
	$WorldEnvironment.environment.ssao_enabled = GameSettings.ambient_occlusion


func has_started() -> bool:
	return _started


func input_blocked() -> bool:
	return $HUD/MatchMenu.visible


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
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


@rpc("authority", "call_local", "reliable")
func net_restart() -> void:
	$HUD.reset_round()
	for player in get_tree().get_nodes_in_group("player"):
		player.restart_round()
	$Bot.restart_round()


@rpc("authority", "reliable")
func net_score_snapshot(scores: Dictionary) -> void:
	$HUD.apply_score_snapshot(scores)


func start_solo() -> void:
	Net.play_solo()
	_spawn_player(1)
	$Bot.begin(true)


func start_host() -> Error:
	var err := Net.host_game()
	if err != OK:
		return err
	_spawn_player(1)
	$Bot.begin(true)
	$HUD.show_host_ip(Net.lan_addresses())
	return OK


func announce(killer_id: int, victim_id: int) -> void:
	if Net.active:
		net_frag.rpc(killer_id, victim_id)
	else:
		$HUD.on_frag(killer_id, victim_id)


@rpc("authority", "call_local", "reliable")
func net_spawn(peer_id: int) -> void:
	_spawn_player(peer_id)


@rpc("authority", "call_local", "reliable")
func net_frag(killer_id: int, victim_id: int) -> void:
	$HUD.on_frag(killer_id, victim_id)


func _spawn_player(peer_id: int) -> Node:
	var existing := get_node_or_null(str(peer_id))
	if existing:
		return existing
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id, true)
	player.position = Vector3(-14.6, 0.2, 14.2) if peer_id == 1 else Vector3(14.2, 0.2, -14.2)
	add_child(player)
	_add_player_sync(player, peer_id)
	if not Net.active or player.is_multiplayer_authority():
		_started = true
		$HUD.attach_local(player)
		if str(player.weapon_id) == "":
			$HUD/WeaponSelect.show_select()
			$HUD/Lobby.hide_lobby()
	$HUD.refresh_score()
	return player


func _add_player_sync(player: Node, peer_id: int) -> void:
	if not Net.active:
		return
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.root_path = NodePath("..")
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	config.add_property(NodePath("Camera3D:rotation"))
	sync.replication_config = config
	sync.replication_interval = 0.0
	sync.public_visibility = false
	player.add_child(sync)
	sync.set_multiplayer_authority(peer_id)
	if Net.active and not multiplayer.is_server() and peer_id == multiplayer.get_unique_id():
		$Bot.begin(false)
		sync.set_visibility_for(1, true)
		net_ready.rpc_id(1)


func _on_joined() -> void:
	$Bot.begin(false)
	$HUD/Lobby.set_status("Подключено...")


func _on_connection_failed() -> void:
	var lobby: Node = $HUD/Lobby
	lobby.set_status("Не удалось подключиться. Проверь IP: хост уже должен создать игру.")
	lobby._busy = false


func _on_host_lost() -> void:
	if _reloading:
		return
	_reloading = true
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func _on_peer_connected(id: int) -> void:
	if not Net.active or not multiplayer.is_server() or id == 1:
		return
	var humans := 0
	for node in get_tree().get_nodes_in_group("player"):
		humans += 1
	if humans >= 2:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	call_deferred("_welcome", id)


func _welcome(id: int) -> void:
	if not has_node("1"):
		return
	net_spawn.rpc_id(id, 1)
	net_spawn.rpc(id)
	$HUD.hide_host_ip()


@rpc("any_peer", "reliable")
func net_ready() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	_show_sync(id)
	# Player RPCs can reach this peer once its synchronizer makes the player visible.
	get_node("1").send_weapon_to(id)
	net_score_snapshot.rpc_id(id, $HUD.score_snapshot())


func _show_sync(id: int) -> void:
	for node in get_tree().get_nodes_in_group("player"):
		var sync := node.get_node_or_null("Sync") as MultiplayerSynchronizer
		if sync:
			sync.set_visibility_for(id, true)
	var bot_sync := $Bot.get_node_or_null("Sync") as MultiplayerSynchronizer
	if bot_sync:
		bot_sync.set_visibility_for(id, true)


func _on_peer_disconnected(id: int) -> void:
	if id == 1 or not Net.active:
		return
	var node := get_node_or_null(str(id))
	if node:
		node.queue_free()
	if multiplayer.is_server():
		$HUD.show_host_ip(Net.lan_addresses(), "Соперник отключился.")
		$HUD.refresh_score()
