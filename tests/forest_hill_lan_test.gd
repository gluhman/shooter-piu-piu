extends SceneTree
## Three ENet processes: host, client, observer; shared folder and UDP port.
var role := ""
var folder := ""
var arena: Node3D
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=3:
		finish(false,"expected role, folder, port")
		return
	role=args[0]
	folder=args[1]
	if role=="observer" and not await until(func():return exists("scored")):
		finish(false,"host did not score")
		return
	arena=load("res://game/match/arena.tscn").instantiate()
	arena.name="ForestHillLAN"
	root.add_child(arena)
	var net := root.get_node("Net")
	net.host_lost.disconnect(arena._on_host_lost)
	var transport := ENetMultiplayerPeer.new()
	transport.set_bind_ip("127.0.0.1")
	var error := transport.create_server(int(args[2]),2,4) if role=="host" else transport.create_client("127.0.0.1",int(args[2]),4)
	if error!=OK:
		finish(false,"ENet startup failed")
		return
	net.active=true
	get_multiplayer().multiplayer_peer=transport
	if role=="host":
		if not await until(func():return arena.player_slots.count(0)==8):
			finish(false,"client did not join")
			return
		arena.update_host_rules(0,13,Vector2i.ZERO,1,2,2,true,false,1,2)
		await arena.start_host_match()
		if not await until(func():return exists("client-loaded")):
			finish(false,"client did not load")
			return
		arena.objectives.set_physics_process(false)
		for bot in get_nodes_in_group("bot"):bot.set_physics_process(false)
		var player: Node3D=arena.combatant(1)
		player.position=Vector3(0,12.1,0)
		for tick in 60:arena.objectives.rules.step(arena.objectives,[player])
		var loot := arena.get_node("Loot")
		for i in 3:loot._open_crate(player,i,loot._crates[i].position+Vector3.UP*0.7)
		arena.objectives.broadcast(true)
		write("signature",signature())
		write("scored")
		if not await until(func():return exists("client-verified") and exists("observer-verified")):
			finish(false,"clients did not converge")
			return
		write("verified")
		await create_timer(0.3).timeout
		finish(true,"hill capture and summit supplies replicated to client and late observer")
	else:
		if not await until(func():return arena.has_started() and not arena.is_loading() and arena.objectives!=null):
			finish(false,"map did not load")
			return
		if role=="client":
			var player: Node=arena.combatant(get_multiplayer().get_unique_id())
			player.choose_loadout("ak47","m1911","frag")
			write("client-loaded")
		if not await until(func():return exists("scored") and arena.get_node("Loot")._drops.size()>=3 and not arena.objectives.state.is_empty()):
			finish(false,"supplies or objective snapshot missing")
			return
		var good: bool = arena.map_id==13 and arena.play_mode==2 and arena.arena_width()==100.0 and arena.objectives.centers.size()==1
		good=good and arena.objectives.state.scores.x+arena.objectives.state.scores.y>0
		good=good and signature()==FileAccess.get_file_as_string(folder.path_join("signature")).strip_edges()
		var kinds: Array=[]
		for drop in arena.get_node("Loot")._drops.values():kinds.append(drop.kind)
		var loot := arena.get_node("Loot")
		good=good and loot.Kind.WEAPON in kinds and loot.Kind.MEDKIT in kinds and loot.Kind.ARMOR in kinds
		if not good:
			finish(false,"map geometry or summit rewards diverged")
			return
		write(role+"-verified")
		finish(await until(func():return exists("verified")),"same hill geometry and supplies, including late-join snapshot")
func signature() -> String:
	var map := arena.get_node("Map")
	var positions: Array=[]
	for crate in arena.get_node("Loot")._crates:positions.append(crate.position)
	var rocks: Array=[]
	for rock: StaticBody3D in get_nodes_in_group("hill_rock"):
		var shape: ConcavePolygonShape3D=rock.get_child(0).shape
		rocks.append([rock.position,hash(var_to_bytes(shape.get_faces()))])
	return str(hash(var_to_str([map.get_meta("hill_tunnels"),positions,map._initial_spawns,rocks])))
func exists(name: String) -> bool:
	return FileAccess.file_exists(folder.path_join(name))
func write(name: String,value: String="ok") -> void:
	var file := FileAccess.open(folder.path_join(name),FileAccess.WRITE)
	file.store_line(value)
func until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec()+45000
	while not condition.call():
		if Time.get_ticks_msec()>deadline:return false
		await create_timer(0.075).timeout
	return true
func finish(ok: bool,message: String) -> void:
	print("PASS " if ok else "FAIL ",role," ",message)
	quit(0 if ok else 1)
