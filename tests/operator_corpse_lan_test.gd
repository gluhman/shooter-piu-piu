extends SceneTree
## Two ENet processes: host/client SHARED_DIR PORT. Uses the production loot RPC.
const Pose := preload("res://game/actors/operator_pose.gd")
const Fallen := preload("res://game/actors/fallen_operator.gd")
var folder: String
var role: String
var arena: Node3D
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or args[0] not in ["host", "client"]:
		push_error("Expected host|client SHARED_DIR PORT")
		quit(1)
		return
	role = args[0]
	folder = args[1]
	var net := root.get_node("Net")
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip("127.0.0.1")
	var error := peer.create_server(int(args[2]), 1, 4) if role == "host" else peer.create_client("127.0.0.1", int(args[2]), 4)
	if error != OK:
		_finish(false, "ENet startup failed")
		return
	net.active = true
	get_multiplayer().multiplayer_peer = peer
	arena = load("res://game/match/arena.tscn").instantiate()
	arena.name = "OperatorLAN"
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	net.host_lost.disconnect(arena._on_host_lost)
	if not await _until(func(): return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED):
		_finish(false, "connection timeout")
		return
	var loot := arena.get_node("Loot")
	if role == "client":
		_write("client-ready", str(get_multiplayer().get_unique_id()))
		if not await _until(func(): return loot._drops.size() == 2):
			_finish(false, "body snapshots did not arrive")
			return
		var good := true
		for team in [0, 1]:
			var body: Node3D = loot._drops[team + 1].node
			var state: Dictionary = body.snapshot()
			good = good and state.team == team and state.pose.size() == 66 and state.settled.size() == 13
			good = good and body.get_child(0).scene_file_path == Pose.model_for_team(team).resource_path
			var expected := _pose(team)
			for b in 66: good = good and state.pose[b].is_equal_approx(expected[b])
		_write("verified", str(good))
		_finish(good, "both native 66-bone corpse poses and team outfits replicated")
	else:
		if not await _until(func(): return FileAccess.file_exists(folder.path_join("client-ready"))):
			_finish(false, "client did not become ready")
			return
		var id := int(FileAccess.get_file_as_string(folder.path_join("client-ready")))
		for team in [0, 1]:
			var body := Fallen.new()
			root.add_child(body)
			body.build(true, {"pose": _pose(team), "team": team}, false)
			loot.net_add_drop.rpc_id(id, team + 1, loot.Kind.BODY, "", 100, Vector3(team * 2, 0, 0), 0.0, false, body.snapshot())
			body.queue_free()
		var received := await _until(func(): return FileAccess.file_exists(folder.path_join("verified")))
		_finish(received and FileAccess.get_file_as_string(folder.path_join("verified")) == "true", "production corpse RPC confirmed")
func _pose(team: int) -> Array[Transform3D]:
	var model := Pose.model_for_team(team).instantiate()
	root.add_child(model)
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	ap.play("rifle-walk")
	ap.seek(0.45, true)
	var result: Array[Transform3D] = []
	for b in sk.get_bone_count(): result.append(sk.get_bone_pose(b))
	model.free()
	return result
func _until(predicate: Callable) -> bool:
	for frame in 400:
		if predicate.call(): return true
		await create_timer(0.025).timeout
	return false
func _write(name: String, value: String) -> void:
	FileAccess.open(folder.path_join(name), FileAccess.WRITE).store_string(value)
func _finish(good: bool, detail: String) -> void:
	print(("PASS " if good else "FAIL ") + role + ": " + detail)
	if is_instance_valid(arena): arena.queue_free()
	await process_frame
	get_multiplayer().multiplayer_peer = null
	quit(0 if good else 1)
