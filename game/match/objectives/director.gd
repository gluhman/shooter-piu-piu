extends Node3D

const LAYOUT := preload("res://game/maps/objective_layout.gd")
const HILL := preload("res://game/match/objectives/hill.gd")
const FLAG := preload("res://game/match/objectives/flag.gd")
const DEFUSE := preload("res://game/match/objectives/defuse.gd")
const DISPLAY := preload("res://game/match/objectives/display.gd")

var game: Node3D
var mode := 0
var preset := 0
var target := 0
var tick := 0
var left := 0
var scores := Vector2i.ZERO
var overtime := false
var centers := PackedVector3Array()
var spawns: Array[PackedVector3Array] = []
var radius := 3.0
var rules: RefCounted
var display: Node3D
var state := {}
var wave := 0
var next_wave := 0
var wave_queue := {}
var pending_slots := {}
var inputs := {}
var sequences := {}
var revision := 0
var grace := 0
var empty_team := -1
var statistics := {}
var _sent_tick := -1
var _snapshot_time := 0
var _role_tick := -1
var _role_cache := {}
var _notice: Array[String] = []
var _notice_until := 0
var _notice_serial := 0
var _notice_cue := ""
var match_ticks := 0
var _signature := []


func configure(match_node: Node3D, layout: Dictionary, roster_size: int, seed_value: int) -> void:
	game = match_node
	mode = game.play_mode
	preset = clampi(roster_size - 1, 0, 3)
	centers = layout.centers
	spawns.assign(layout.spawns)
	radius = layout.radius
	left = [300, 360, 420, 480][preset] * 60
	match mode:
		LAYOUT.HILL:
			target = [90, 110, 140, 160][preset]
			wave = [3, 4, 5, 6][preset] * 60
			rules = HILL.new()
			rules.setup(seed_value, preset, game.objective_hill_first)
		LAYOUT.FLAG:
			target = [2, 3, 3, 3][preset]
			wave = [4, 4, 5, 6][preset] * 60
			rules = FLAG.new()
			rules.setup(centers)
		LAYOUT.DEFUSE:
			target = 5
			rules = DEFUSE.new()
	next_wave = wave
	if not Net.dedicated:
		display = DISPLAY.new()
		add_child(display)
		display.setup(self)


func start() -> void:
	if mode == LAYOUT.DEFUSE:
		rules.setup(self, game.objective_attack_side)
	broadcast(true)


func spawn_pool(team: int) -> PackedVector3Array:
	var physical := 1 - team if mode == LAYOUT.DEFUSE and rules.attack == 1 else team
	return spawns[physical]


func in_zone(actor: Node3D, index: int, clearance := 0.0) -> bool:
	return LAYOUT.contains(actor.gameplay_feet_position(), centers[index], radius + clearance)


func build_blocked(at: Vector3) -> bool:
	for center in centers:
		if LAYOUT.contains(at, center, radius + 2.0):
			return true
	return false


func eligible(actor: Node3D, require_unprotected := true) -> bool:
	return is_instance_valid(actor) and actor.is_inside_tree() and actor.control_enabled and actor.health > 0.0 \
		and (not require_unprotected or actor._hurt_lock <= 0.0)


func actors() -> Array:
	var roster := get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("bot")
	var active := roster.filter(func(actor): return actor.get_parent() == game and eligible(actor, mode != LAYOUT.DEFUSE))
	active.sort_custom(func(a, b): return a.slot < b.slot)
	return active


func nearest(roster: Array, at: Vector3, team: int, range_m: float) -> Node3D:
	var best := range_m * range_m
	var found: Node3D
	for actor in roster:
		var distance: float = actor.gameplay_feet_position().distance_squared_to(at)
		if actor.team_id() == team and distance < best and line_clear(actor.gameplay_feet_position() + Vector3.UP * 0.45, at + Vector3.UP * 0.18):
			best = distance
			found = actor
	return found


func grounded(actor: Node3D) -> bool:
	if not actor.combat_grounded():
		return false
	var feet: Vector3 = actor.gameplay_feet_position()
	var ray := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.08, feet - Vector3.UP * 0.22, game.Balance.WORLD_MASK)
	var floor := get_world_3d().direct_space_state.intersect_ray(ray)
	return not floor.is_empty() and floor.normal.y > 0.50


func line_clear(from: Vector3, to: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(from, to, game.Balance.WORLD_MASK)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func can_see(observer: Node3D, carrier: Node3D) -> bool:
	var from: Vector3 = observer.aim_center()
	var to: Vector3 = carrier.aim_center()
	return from.distance_to(to) < 45.0 and -observer.global_basis.z.dot(from.direction_to(to)) > 0.25 \
		and not game.get_node("Grenades").obscures(from, to) and line_clear(from, to)


func drop_floor(at: Vector3) -> Vector3:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at - Vector3.UP * 2.5, game.Balance.WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < 0.65:
		return Vector3.INF
	var nav := get_world_3d().navigation_map
	var point: Vector3 = hit.position
	if NavigationServer3D.map_get_iteration_id(nav) > 0 and NavigationServer3D.map_get_closest_point(nav, point).distance_to(point) > 1.7:
		return Vector3.INF
	return point


func departed(actor: Node3D, disconnect: bool) -> void:
	if mode != LAYOUT.HILL:
		rules.drop(self, actor)
	clear_interact(actor)
	sequences.erase(actor.score_id())
	if disconnect:
		wave_queue.erase(actor.score_id())
	elif wave > 0:
		wave_queue[actor.score_id()] = tick + 60


func frozen() -> bool:
	return mode == LAYOUT.DEFUSE and int(state.get("phase", DEFUSE.PREP)) in [DEFUSE.PREP, DEFUSE.RESULT] \
		or grace > 0 or int(state.get("grace", 0)) > 0


func step() -> void:
	match_ticks += 1
	var seats := Vector2i.ZERO
	for slot in game.player_slots.size():
		var id: int = game.player_slots[slot]
		var present: bool = id > 0 and (not pending_slots.has(slot) or game.match_peers().has(id))
		if present or game._bot_slots.has(slot):
			seats[slot % 2] += 1
	if game.blue_bot_count >= 0 and (seats.x == 0 or seats.y == 0):
		empty_team = 0 if seats.x == 0 else 1
		grace += 1
		if grace >= 900:
			finish("Соперники покинули матч", 1 - empty_team)
		elif _remaining_match_ticks() == 0:
			finish("Время матча вышло")
		else:
			broadcast()
		return
	if grace > 0:
		grace = 0
		empty_team = -1
		if mode == LAYOUT.DEFUSE:
			rules.begin(self)
	tick += 1
	if wave > 0 and tick == next_wave:
		next_wave += wave
		game.objective_fill_slots()
		for id in wave_queue.keys():
			var actor: Node = game.combatant(id)
			if actor == null:
				wave_queue.erase(id)
			elif wave_queue[id] <= tick:
				actor._request_respawn()
				if actor.health > 0:
					wave_queue.erase(id)
	left = maxi(0, left - 1)
	rules.step(self, actors())
	if not game.round_finished() and _remaining_match_ticks() == 0:
		finish("Время матча вышло")
	else:
		broadcast()


func leader() -> int:
	return -1 if scores.x == scores.y else (0 if scores.x > scores.y else 1)


func finish(reason: String, winner := -1) -> void:
	broadcast(true)
	if winner >= 0:
		game._finish_round(reason, winner)
	else:
		game._finish_round(reason)


func reset_defuse_round() -> void:
	inputs.clear()
	game.objective_reset_defuse_round()


func effect(at: Vector3) -> void:
	game.net_objective_effect(game._map_revision, at)
	for peer in game.match_peers():
		game.net_objective_effect.rpc_id(peer, game._map_revision, at)


func clear_interact(actor: Node3D) -> void:
	inputs.erase(actor.score_id())
	if mode == LAYOUT.DEFUSE:
		rules.cancel(actor)


func wants_interact(actor: Node3D) -> bool:
	if actor.is_in_group("bot"):
		return bot_action(actor)
	return inputs.has(actor.score_id()) and rules.action(self, actor) == inputs[actor.score_id()]


func request_interact(actor: Node3D, pressed: bool, sequence: int, round_number: int, target_id: int) -> void:
	if mode != LAYOUT.DEFUSE or not is_instance_valid(actor) or round_number != rules.generation:
		return
	var id: int = actor.score_id()
	if sequence <= int(sequences.get(id, -1)):
		return
	sequences[id] = sequence
	if pressed and grace == 0 and rules.action(self, actor) == target_id and target_id >= 0:
		inputs[id] = target_id
	else:
		clear_interact(actor)


func local_action(actor: Node3D) -> int:
	if mode != LAYOUT.DEFUSE or frozen() or not eligible(actor, false) or not grounded(actor):
		return -1
	if not Net.active or multiplayer.is_server():
		return rules.action(self, actor)
	if state.get("phase") == DEFUSE.LIVE and state.get("carrying") == true and state.get("carrier") == actor.score_id():
		for index in int(state.sites):
			if in_zone(actor, index):
				return index
	if state.get("phase") == DEFUSE.PLANTED and state.get("attack") != actor.team_id():
		var at: Vector3 = state.planted
		if actor.global_position.distance_to(at) <= 1.5 and line_clear(actor.aim_center(), at + Vector3.UP * 0.1):
			return 2
	return -1


func bot_action(actor: Node3D) -> bool:
	if mode != LAYOUT.DEFUSE:
		return false
	var action: int = rules.action(self, actor)
	if action != 2:
		return action >= 0
	if rules.holder != null:
		return rules.holder == actor
	if left < 300:
		return false
	var chosen: Node3D = nearest(actors(), rules.planted, actor.team_id(), 1.5)
	return chosen == actor or (chosen != null and not chosen.is_in_group("bot") and not wants_interact(chosen))


func bot_order(actor: Node3D) -> Dictionary:
	var team: int = actor.team_id()
	var rank := 0
	var team_size := 0
	for ally in actors():
		if ally.team_id() == team:
			team_size += 1
			if ally.slot < actor.slot and ally.is_in_group("bot"):
				rank += 1
	var approach := spawns[1 - team][0]
	match mode:
		LAYOUT.HILL:
			var index: int = rules.active
			var contest: bool = rules.team not in [-1, team]
			if rules.next >= 0 and rank == 2 and actor.difficulty >= 2 and not contest:
				index = rules.next
			var center := centers[index]
			var assault: bool = contest and index == rules.active
			if index != rules.active or (rank >= (2 if assault else 1) and not in_zone(actor, index)):
				return _order("screen", _lane_position(center, spawns[team][0], radius + 2.6, rank), approach, rank)
			if assault and not in_zone(actor, index):
				return _order("assault", center, center, rank, radius)
			return _order("hold", center, approach, rank, radius)
		LAYOUT.FLAG:
			# Keep the running lanes assigned through respawn waves.
			rank = 0
			for ally in get_tree().get_nodes_in_group("bot"):
				if ally.get_parent() == game and ally.team_id() == team and ally.slot < actor.slot:
					rank += 1
			var own: Dictionary = rules.flags[team]
			var enemy: Dictionary = rules.flags[1 - team]
			if enemy.carrier == actor:
				if own.state == FLAG.HOME:
					return _order("deliver", centers[team], centers[1 - team], rank)
				return _order("wait_home", _lane_position(centers[team], spawns[team][0], radius + 1.0, rank),
					centers[1 - team], rank)
			if own.state == FLAG.DROPPED and route_role(team, own.at, float(own.left) / 60.0) == actor:
				return _order("return", own.at, approach, rank)
			if own.state == FLAG.CARRIED:
				var retriever: Node3D
				for ally in actors():
					if ally.team_id() == team and ally.is_in_group("bot") and ally != enemy.carrier:
						retriever = ally
						break
				if actor == retriever and (enemy.state == FLAG.CARRIED or own.revealed.is_finite()):
					var intercept: Vector3 = own.revealed if own.revealed.is_finite() else centers[1 - team]
					return _order("intercept", intercept, intercept, rank)
			if enemy.state == FLAG.CARRIED:
				var carrier: Node3D = enemy.carrier
				var protect := carrier.global_position.lerp(centers[team], 0.24)
				var lateral := _flat_approach(centers[team], carrier.global_position).cross(Vector3.UP)
				protect += lateral * float(rank + 1) * (1.8 if rank % 2 == 0 else -1.8)
				return _order("escort", protect, centers[1 - team], rank)
			if rank == 1 and team_size > 1 and actor.difficulty > 0 and own.state == FLAG.HOME:
				return _order("screen", _lane_position(centers[team], spawns[team][0], radius + 1.5, rank),
					centers[1 - team], rank)
			var at: Vector3 = enemy.at if enemy.state == FLAG.DROPPED and _sees_drop(actor, enemy.at) else centers[1 - team]
			var role := "flank_steal" if rank >= 2 and actor.difficulty > 0 else "steal"
			return _order(role, at, approach, rank)
		LAYOUT.DEFUSE:
			approach = spawn_pool(1 - team)[0]
			if rules.phase == DEFUSE.PLANTED:
				if team != rules.attack and route_role(team, rules.planted, maxf(0.0, left / 60.0 - 5.0)) == actor:
					return _order("defuse", rules.planted, approach, rank)
				var center := centers[rules.site]
				var kind := "assault" if team != rules.attack else "screen"
				return _order(kind, _lane_position(center, spawn_pool(team)[0], radius + 1.1, rank), approach, rank)
			if team == rules.attack:
				if rules.dropped.is_finite() and route_role(team, rules.dropped, float(left) / 60.0) == actor:
					return _order("recover", rules.dropped, approach, rank)
				var center := centers[rules.round_index % rules.sites]
				if rules.carrier == actor:
					return _order("plant", center, approach, rank)
				return _order("screen", _lane_position(center, spawn_pool(team)[0], radius + 1.5, rank), approach, rank)
			return _order("screen", _lane_position(centers[rank % rules.sites], spawn_pool(team)[0], radius + 0.8, rank),
				approach, rank)
	return _order("steal", Vector3.INF, approach, rank)


func _order(kind: String, goal: Vector3, threat: Vector3, rank: int, zone_radius := 0.0) -> Dictionary:
	return {"kind": kind, "goal": goal, "threat": threat, "rank": rank, "radius": zone_radius}


func _flat_approach(from: Vector3, to: Vector3) -> Vector3:
	return Vector3(to.x - from.x, 0.0, to.z - from.z).normalized()


func _lane_position(center: Vector3, from: Vector3, reach: float, rank: int) -> Vector3:
	var offset := 0.42 + (rank / 2) * 0.38
	return center + _flat_approach(center, from).rotated(Vector3.UP, offset * (1.0 if rank % 2 == 0 else -1.0)) * reach


func _sees_drop(actor: Node3D, at: Vector3) -> bool:
	var eye: Vector3 = actor.aim_center()
	return eye.distance_squared_to(at) < 22.0 * 22.0 and line_clear(eye, at + Vector3.UP * 0.35) \
		and not game.get_node("Grenades").obscures(eye, at)


func route_role(team: int, target_position: Vector3, seconds: float) -> Node3D:
	if seconds <= 0.0:
		return null
	var role_tick := tick / 12
	if role_tick != _role_tick:
		_role_tick = role_tick
		_role_cache.clear()
	var key := Vector4(target_position.x, target_position.y, target_position.z, float(team))
	if _role_cache.has(key) and is_instance_valid(_role_cache[key]):
		return _role_cache[key]
	var nav := get_world_3d().navigation_map
	var best: Node3D
	var best_time := seconds
	for actor in actors():
		if not actor.is_in_group("bot") or actor.team_id() != team:
			continue
		var path := NavigationServer3D.map_get_path(nav, actor.global_position, target_position, true)
		if path.is_empty() or path[-1].distance_to(target_position) > 1.5:
			continue
		var length := 0.0
		for index in range(1, path.size()):
			length += path[index - 1].distance_to(path[index])
		var speed: float = actor.BOT_SPEED * actor._difficulty_modifiers().speed * actor.armor_movement_scale()
		var time := length / speed + 0.35
		if time < best_time:
			best = actor
			best_time = time
	_role_cache[key] = best
	return best


func _remaining_match_ticks() -> int:
	return maxi(0, int(game.MAX_MATCH_SECONDS) * 60 - match_ticks)


func notify(message: String, team := -1, own := "", other := "", cue := "") -> void:
	# Keep the scored event when a silent phase change follows on the same tick.
	if _notice_until == tick + 180 and not _notice_cue.is_empty() and cue.is_empty():
		return
	_notice = [message, message, message]
	if team in [0, 1]:
		_notice[team] = own
		_notice[1 - team] = other
	_notice_until = tick + 180
	_notice_serial += 1
	_notice_cue = cue


func _team_notice(team: int) -> String:
	return _notice[team if team >= 0 else 2] if tick < _notice_until else ""


func broadcast(force := false) -> void:
	var public: Dictionary
	match mode:
		LAYOUT.HILL: public = rules.view()
		LAYOUT.FLAG: public = rules.view(-1)
		_: public = rules.view(-1, 1)
	if mode == LAYOUT.FLAG:
		for flag in public.flags:
			flag.left = ceili(flag.left / 60.0)
	elif mode == LAYOUT.HILL:
		public.absence = ceili(public.absence / 60.0)
	var signature := [public, ceili(left / 60.0), scores, overtime, ceili(grace / 60.0), _team_notice(-1), _notice_serial]
	if not force and signature == _signature and (tick == _sent_tick or tick % 12 != 0):
		return
	_signature = signature
	_sent_tick = tick
	revision += 1
	receive(snapshot(Net.local_id()))
	for peer in game.match_peers():
		game.net_objectives.rpc_id(peer, game._map_revision, snapshot(peer))


func snapshot(peer: int) -> Dictionary:
	var slot: int = game.player_slots.find(peer)
	var team := slot % 2 if slot >= 0 and not pending_slots.has(slot) else -1
	var view: Dictionary
	match mode:
		LAYOUT.HILL: view = rules.view()
		LAYOUT.FLAG: view = rules.view(team, peer, game.combatant(peer), self)
		_: view = rules.view(team, peer)
	var displayed_left := mini(left, _remaining_match_ticks())
	var notice := _team_notice(team)
	view.merge({"revision": revision, "left": displayed_left, "scores": scores, "target": target, "stats": statistics.duplicate(true),
		"mode": mode, "tick": tick, "deadline": tick + displayed_left, "notice": notice,
		"notice_serial": _notice_serial, "notice_cue": _notice_cue if not notice.is_empty() else "",
		"overtime": overtime, "grace": 0 if grace == 0 else 15 - floori(grace / 60.0)})
	return view


func receive(value: Dictionary) -> void:
	if int(value.revision) <= int(state.get("revision", -1)):
		return
	state = value
	_snapshot_time = Time.get_ticks_msec()
	game._team_score = value.scores
	if display:
		display.update_state(value)


func _physics_process(_delta: float) -> void:
	if not game or not game.has_started() or game.is_loading() or game.round_finished():
		return
	if not Net.active or multiplayer.is_server():
		step()



func add_stat(actor: Node3D, column: int) -> void:
	var id: int = actor.score_id()
	var pair: Vector2i = statistics.get(id, Vector2i.ZERO)
	pair[column] += 1
	statistics[id] = pair


func clock_seconds() -> int:
	var elapsed := 0.0 if int(state.get("grace", 0)) > 0 else (Time.get_ticks_msec() - _snapshot_time) * 0.001
	return maxi(0, ceili(float(state.get("left", 0)) / 60.0 - elapsed))
