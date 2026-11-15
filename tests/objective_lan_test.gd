extends SceneTree
## Three real ENet peers. Start host, defender, observer with the same shared directory and UDP port.

const DEFUSE := preload("res://game/match/objectives/defuse.gd")
var role := ""
var folder := ""
var match_node: Node3D
var net: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or args[0] not in ["host", "defender", "observer"]:
		_end(false, "expected role, shared directory and port")
		return
	role = args[0]
	folder = args[1]
	net = root.get_node("Net")
	if role == "observer" and not await _until(func(): return _exists("planted")):
		_end(false, "host never planted")
		return
	match_node = load("res://game/match/arena.tscn").instantiate()
	match_node.name = "ObjectiveLAN"
	root.add_child(match_node)
	net.host_lost.disconnect(match_node._on_host_lost)
	var transport := ENetMultiplayerPeer.new()
	transport.set_bind_ip("127.0.0.1")
	var port := int(args[2])
	var error := transport.create_server(port, 2, 4) if role == "host" else transport.create_client("127.0.0.1", port, 4)
	if error != OK:
		_end(false, "ENet startup failed")
		return
	net.active = true
	get_multiplayer().multiplayer_peer = transport
	match role:
		"host": await _host()
		"defender": await _defender()
		"observer": await _observer()


func _host() -> void:
	if not await _until(func(): return match_node.player_slots.count(0) == 8):
		_end(false, "defender did not join the lobby")
		return
	match_node.update_host_rules(0, 4, Vector2i.ZERO, 1, 2, 1, true, false, -1, 4)
	await match_node.start_host_match()
	var obj: Node3D = match_node.objectives
	obj.set_physics_process(false)
	var local: CharacterBody3D = match_node.combatant(1)
	local.choose_loadout("ak47", "m1911", "frag")
	if not await _until(func(): return match_node.match_peers().size() == 1 and match_node.combatant(match_node.player_slots[1]).control_enabled):
		_end(false, "remote loadout and ready handshakes did not converge")
		return
	obj.rules.carrier = local
	obj.rules.carrier_assigned = true
	obj.left = 1
	obj.step()
	obj.broadcast(true)
	if not await _until(func(): return _exists("invalid-sent")):
		_end(false, "defender did not send invalid objective request")
		return
	await create_timer(0.20).timeout
	var defender_id: int = match_node.player_slots[1]
	if obj.inputs.has(defender_id) or obj.rules.hold_ticks > 0:
		_end(false, "defender gained plant progress")
		return
	await physics_frame
	local.position = obj.centers[0] + Vector3.UP * 0.055
	local.velocity = Vector3.DOWN * 6.0
	local.move_and_slide()
	var generation: int = obj.rules.generation
	obj.request_interact(local, true, 21, generation, 0)
	for tick in 300:
		obj.step()
	if obj.rules.phase != DEFUSE.PLANTED or obj.statistics.get(1, Vector2i.ZERO).x != 1:
		_end(false, "authority failed to plant once")
		return
	obj.request_interact(local, true, 21, generation, 0)
	obj.step()
	if obj.statistics[1].x != 1:
		_end(false, "duplicate sequence changed plant count")
		return
	_write("planted")
	if not await _until(func(): return _exists("observer-ready") and _exists("defender-ready")):
		_end(false, "clients did not converge on the planted state")
		return
	_write("verified")
	_end(true, "forged wrong-side interaction rejected, one plant, late observer converged")


func _defender() -> void:
	if not await _until(func(): return match_node.has_started() and not match_node.is_loading() and not match_node.objectives.state.is_empty()):
		_end(false, "defender failed to load objective match")
		return
	var local: Node = match_node.combatant(get_multiplayer().get_unique_id())
	local.choose_loadout("ak47", "m1911", "frag")
	var obj: Node3D = match_node.objectives
	if not await _until(func(): return obj.state.phase == DEFUSE.LIVE):
		_end(false, "defender did not receive live state")
		return
	if obj.state.carrying or obj.state.carrier != 0 or obj.state.drop.is_finite():
		_end(false, "defender received hidden charge data")
		return
	var round_generation: int = obj.state.generation
	for attempt in 2:
		match_node.net_objective_interact.rpc_id(1, match_node._map_revision, round_generation, 5, true, 0)
	_write("invalid-sent")
	if await _until(func(): return obj.state.phase == DEFUSE.PLANTED and obj.state.site == 0):
		_write("defender-ready")
		_end(await _until(func(): return _exists("verified")), "defender received public planted site")
	else:
		_end(false, "defender missed public plant")


func _observer() -> void:
	if not await _until(func(): return match_node.has_started() and not match_node.is_loading() and not match_node.objectives.state.is_empty()):
		_end(false, "late observer failed to load objective match")
		return
	var obj: Node3D = match_node.objectives
	var good: bool = obj.state.phase == DEFUSE.PLANTED and obj.state.site == 0 and obj.state.planted.is_finite() \
		and match_node.combatant(get_multiplayer().get_unique_id()) == null
	if good:
		_write("observer-ready")
		good = await _until(func(): return _exists("verified"))
	_end(good, "late observer has current objective snapshot and no live body")


func _exists(name: String) -> bool:
	return FileAccess.file_exists(folder.path_join(name))


func _write(name: String) -> void:
	var file := FileAccess.open(folder.path_join(name), FileAccess.WRITE)
	file.store_line("ok")


func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 25000
	while not condition.call():
		if Time.get_ticks_msec() >= deadline:
			return false
		await create_timer(0.075).timeout
	return true


func _end(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", role, " ", message)
	quit(0 if ok else 1)
