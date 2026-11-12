extends SceneTree

const SPEED := 3.8
const LEG := 2.0
const DURATION := 8.0
const MAGAZINE := 100

var role: String
var shared_dir: String
var arena: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0]
	shared_dir = args[1]
	Engine.max_fps = 60
	var transport := ENetMultiplayerPeer.new()
	transport.set_bind_ip("127.0.0.1")
	var port := int(args[2])
	var error := transport.create_server(port, 2, 4) if role == "host" else transport.create_client("127.0.0.1", port, 4)
	if error != OK:
		quit(1)
		return
	var net := root.get_node("Net")
	net.active = true
	get_multiplayer().multiplayer_peer = transport
	if role != "host":
		while transport.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			await process_frame
		_write(role + ".peer", str(get_multiplayer().get_unique_id()))
	var peers := PackedInt32Array([1, int(await _wait_file("shooter.peer")), int(await _wait_file("observer.peer"))])
	arena = load("res://game/match/arena.tscn").instantiate()
	arena.name = "JitterMatch"
	root.add_child(arena)
	net.host_lost.disconnect(arena._on_host_lost)
	arena._round_left = 90.0
	for index in peers.size():
		arena.player_slots[index] = peers[index]
		_spawn(peers[index], index)
	var shooter := arena.get_node(str(peers[1])) as CharacterBody3D
	if role == "host":
		while not get_multiplayer().get_peers().has(peers[1]) or not get_multiplayer().get_peers().has(peers[2]):
			await process_frame
		arena._ready_peers.assign([peers[1], peers[2]])
	var network_time := root.get_node_or_null("NetworkTime")
	if network_time and await network_time.start() != OK:
		quit(1)
		return
	var probe: Node
	if role == "observer" and network_time:
		probe = load("res://tests/network_jitter/probe.gd").new()
		root.add_child(probe)
		probe.setup(arena, peers[1])
	_write(role + ".ready", "1")
	var schedule := (await _wait_file("start")).split(",")
	var epoch := float(schedule[0])
	var fire_at := float(schedule[1])
	arena._started = true
	var start := float(Time.get_ticks_usec()) / 1000000.0 + epoch - Time.get_unix_time_from_system()

	var drive: Callable
	if role == "shooter":
		drive = func() -> void:
			var t := clampf(float(Time.get_ticks_usec()) / 1000000.0 - start, -4.0, DURATION)
			shooter.position.x = SPEED * (LEG - absf(fposmod(t, 2.0 * LEG) - LEG))
			if t >= fire_at and t < fire_at + 2.0 * LEG:
				shooter.gun._try_fire()
		physics_frame.connect(drive)
	var rows: Array[Array] = []
	while true:
		await process_frame
		var t := float(Time.get_ticks_usec()) / 1000000.0 - start
		if t >= DURATION + 0.7:
			break
		if role == "observer" and t >= 0.0 and t <= DURATION:
			var rtt := transport.get_peer(1).get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
			var latest: float = probe.latest.position.x if probe else 0.0
			var buffered: float = probe.buffered.position.x if probe else 0.0
			rows.append([t, shooter.position.x, latest, buffered, rtt])
		if role == "host" and t >= 0.0 and t <= DURATION:
			var pose: PackedFloat32Array = shooter._latest_pose
			rows.append([t, pose[0] if not pose.is_empty() else shooter.position.x])
	if role == "observer":
		_write("frames.json", JSON.stringify(rows))
	if role == "host":
		_write("authority.json", JSON.stringify(rows))
		_write("shots", str(MAGAZINE - shooter.gun.ammo_counts().x))
	if role == "shooter":
		physics_frame.disconnect(drive)
		_write("attempts", str(shooter.gun._recoil_index))
	arena._started = false
	_write(role + ".done", "1")
	await _wait_file("finish")
	if network_time:
		network_time.stop()
	if probe:
		probe.queue_free()
	arena.queue_free()
	await create_timer(0.25).timeout
	get_multiplayer().multiplayer_peer = null
	quit()


func _spawn(peer: int, index: int) -> void:
	var actor: CharacterBody3D = load("res://game/actors/player.tscn").instantiate()
	actor.name = str(peer)
	actor.slot = index
	actor.set_multiplayer_authority(peer, true)
	actor.position = [Vector3(-5, 0, 8), Vector3.ZERO, Vector3(9, 0, 8)][index]
	actor.spawn_position = actor.position
	arena.add_child(actor)
	actor.set_physics_process(false)
	actor.rotation.y = 0.0
	actor._apply_equip("ak47")
	actor.gun._mag = MAGAZINE
	actor.cancel_spawn_protection()
	actor._update_view_pose()


func _wait_file(name: String) -> String:
	var path := shared_dir.path_join(name)
	while true:
		if FileAccess.file_exists(path):
			var value := FileAccess.get_file_as_string(path)
			if not value.is_empty():
				return value
		await process_frame
	return ""


func _write(name: String, value: String) -> void:
	var out := FileAccess.open(shared_dir.path_join(name), FileAccess.WRITE)
	out.store_string(value)
