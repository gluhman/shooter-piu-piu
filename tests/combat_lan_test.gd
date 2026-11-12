extends SceneTree
## Start host and two clients with -- host|shooter|observer SHARED_DIR UDP_PORT.

var mode: String
var shared_dir: String
var arena: Node3D
var net: Node
var actors: Array[CharacterBody3D]
var event_count := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		_finish(false, "expected role, shared directory and port")
		return
	mode = args[0]
	shared_dir = args[1]
	var transport := ENetMultiplayerPeer.new()
	var port := int(args[2])
	transport.set_bind_ip("127.0.0.1")
	var error := transport.create_server(port, 2, 4) if mode == "host" else transport.create_client("127.0.0.1", port, 4)
	if error != OK:
		_finish(false, "could not start loopback ENet: %s" % error)
		return
	net = root.get_node("Net")
	net.active = true
	get_multiplayer().multiplayer_peer = transport
	var local := 1
	if mode != "host":
		for frame in 180:
			if transport.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
				break
			await create_timer(0.02).timeout
		if transport.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			_finish(false, "client could not connect")
			return
		local = get_multiplayer().get_unique_id()
		_write(mode + ".peer", str(local))
	else:
		if not await _wait_file("shooter.peer") or not await _wait_file("observer.peer"):
			_finish(false, "host did not see both clients")
			return
		_write("roster", "%s,%s" % [_read("shooter.peer"), _read("observer.peer")])
	if not await _wait_file("roster"):
		_finish(false, "missing host roster")
		return
	var roster := _read("roster").split(",")
	var peers := PackedInt32Array([1, int(roster[0]), int(roster[1])])
	arena = load("res://game/match/arena.tscn").instantiate()
	arena.name = "CombatLAN"
	root.add_child(arena)
	net.host_lost.disconnect(arena._on_host_lost)
	arena.damage_resolved.connect(func(_event: Dictionary) -> void: event_count += 1)
	arena.set_process(false)
	arena.set_physics_process(false)
	for index in peers.size():
		arena.player_slots[index] = peers[index]
		actors.append(_spawn(peers[index], index))
	if mode == "host":
		arena._ready_peers.assign([peers[1], peers[2]])
	var victim := actors[0]
	var shooter := actors[1]
	shooter.gun._aim_amount = 1.0
	_write(mode + ".ready", "yes")
	if not await _wait_file("host.ready") or not await _wait_file("shooter.ready") or not await _wait_file("observer.ready"):
		_finish(false, "fixture did not become ready")
		return
	await create_timer(0.32).timeout

	if mode == "host":
		var snapshots: Dictionary[int, PackedFloat32Array] = {}
		for peer in arena._ready_peers:
			arena.net_poses.rpc_id(peer, snapshots, arena.combat_time())
		if not await _wait_file("shooter.fired"):
			_finish(false, "shooter did not send fire RPC")
			return
		await create_timer(0.35).timeout
		var good: bool = event_count == 1 and shooter.gun.ammo_counts().x == 29 and victim.health < 100.0 and victim.health > 65.0
		_write("server.result", "%f,%d" % [victim.health, shooter.gun.ammo_counts().x])
		if not await _wait_file("observer.checked") or not await _wait_file("shooter.checked"):
			_finish(false, "clients did not confirm authoritative state")
			return
		_finish(good and _read("observer.checked") == "true" and _read("shooter.checked") == "true",
			"three ENet peers agree on one accepted shot, one ammo spent and one damage event")
		return

	if mode == "shooter":
		await create_timer(0.20).timeout
		var pose: PackedFloat32Array = shooter.network_pose()
		pose[4] = -0.038
		pose[6] = 1.0
		pose[10] = 1.0
		var time: float = arena.estimated_server_time()
		shooter.gun.net_fire.rpc_id(1, "ak47", pose, time)
		# Replay after the rate limit, so sequence validation alone must stop the second shot.
		await create_timer(0.15).timeout
		shooter.gun.net_fire.rpc_id(1, "ak47", pose, arena.estimated_server_time())
		_write("shooter.fired", "yes")
	if not await _wait_file("server.result"):
		_finish(false, "missing server result")
		return
	var server := _read("server.result").split(",")
	var good: bool = event_count == 1 and is_equal_approx(float(victim.health), float(server[0])) and victim.health < 100.0
	if mode == "shooter":
		good = good and local == shooter.score_id() and shooter.gun.ammo_counts().x == int(server[1])
	_write(mode + ".checked", str(good))
	# Leave transport open until both clients have completed their assertions.
	await create_timer(0.4).timeout
	_finish(good, "authoritative health%s replicated" % (" and ammo" if mode == "shooter" else ""))


func _spawn(peer: int, index: int) -> CharacterBody3D:
	var actor: CharacterBody3D = load("res://game/actors/player.tscn").instantiate()
	actor.name = str(peer)
	actor.slot = index
	actor.set_multiplayer_authority(peer, true)
	actor.position = [Vector3(0, 0, -10), Vector3.ZERO, Vector3(4, 0, 0)][index]
	actor.spawn_position = actor.position
	arena.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.gun.set_process(false)
	actor.rotation.y = 0.0
	actor._apply_equip("ak47")
	actor.cancel_spawn_protection()
	actor._update_view_pose()
	return actor


func _wait_file(file: String) -> bool:
	for attempt in 220:
		if not _read(file).is_empty():
			return true
		await create_timer(0.02).timeout
	return false


func _read(file: String) -> String:
	var file_path := shared_dir.path_join(file)
	return FileAccess.get_file_as_string(file_path) if FileAccess.file_exists(file_path) else ""


func _write(file: String, data: String) -> void:
	var out := FileAccess.open(shared_dir.path_join(file), FileAccess.WRITE)
	out.store_string(data)


func _finish(good: bool, result: String) -> void:
	print("PASS " if good else "FAIL ", mode, " ", result)
	if arena:
		arena.queue_free()
		await process_frame
	quit(0 if good else 1)
