extends SceneTree

const LAYOUT := preload("res://game/maps/objective_layout.gd")
const HILL := preload("res://game/match/objectives/hill.gd")
const FLAG := preload("res://game/match/objectives/flag.gd")
const DEFUSE := preload("res://game/match/objectives/defuse.gd")
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	var lobby := arena.get_node("HUD/Lobby")
	_check_rosters(arena)
	_check(arena.TIME_LIMITS[0] > 0 and arena.TIME_LIMITS.back() == 1200, "time options are finite and capped at 20 minutes")
	arena._set_limits(Vector2i(99, 0))
	_check(arena.TIME_LIMITS[arena.time_option] == 1200, "authority clamps a stale or invalid time option")
	arena._set_limits(Vector2i(arena.DEFAULT_TIME_OPTION, arena.kill_option))
	lobby._on_solo()
	var args := OS.get_cmdline_user_args()
	var visual_mode := int(args[0]) if not args.is_empty() else 0
	lobby._mode.select(visual_mode if visual_mode > 0 else LAYOUT.HILL)
	lobby._mode.item_selected.emit(lobby._mode.selected)
	_check(lobby._map.is_item_disabled(7) and lobby._map.is_item_disabled(8)
		and lobby._map_size.is_item_disabled(0), "objective lobby excludes small, office and training")
	if visual_mode > 0:
		await create_timer(0.32).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/piupiu-objective-lobby-%d.png" % visual_mode)
	for entry in [[2, 2, 1], [3, 2, 1], [4, 4, 1], [2, 1, 1], [3, 6, 1], [3, 6, 2], [2, 6, 1], [4, 6, 2], [3, 2, 2], [4, 4, 2]]:
		var mode: int = entry[0]
		if visual_mode > 0 and visual_mode != mode:
			continue
		var map: int = entry[1]
		await arena.start_solo(5 if entry[2] == 2 else 3, 1, 0, map, Vector2i.ZERO, entry[2], true, false, -1, mode)
		var obj: Node3D = arena.objectives
		_check(is_instance_valid(obj) and arena.has_started(), "objective arena finished loading")
		if not is_instance_valid(obj):
			quit(1)
			return
		obj.set_physics_process(false)
		var player: CharacterBody3D = arena.combatant(1)
		var enemy: CharacterBody3D
		var ally: CharacterBody3D
		for actor in get_nodes_in_group("bot"):
			actor.set_physics_process(false)
			if actor.team_id() != player.team_id():
				enemy = actor
			else:
				ally = actor
		player.set_physics_process(false)
		arena.get_node("HUD/WeaponSelect").hide_for_results()
		player._spawn_loadout = "ak47"
		player._apply_equip("ak47")
		for actor in [player, enemy, ally]:
			actor.cancel_spawn_protection()
		_check(obj.preset == entry[2] and arena.team_deathmatch, "selected roster preset")
		await create_timer(0.25).timeout
		_validate_navigation(arena, obj)
		if map in [1, 6] or entry[2] == 2:
			arena.exit_to_lobby()
			await process_frame
			continue
		if mode == LAYOUT.HILL:
			_hill(obj, player, enemy, ally)
		elif mode == LAYOUT.FLAG:
			_flag(obj, player, enemy)
			await _check_flag_while_hit(obj, player, enemy)
		else:
			await physics_frame
			_defuse(obj, player, enemy)
		if mode != LAYOUT.HILL:
			await _check_running_rig(obj, player, ally, visual_mode > 0)
			await _check_possession_prompt(obj, player, visual_mode > 0)
		obj.broadcast(true)
		await create_timer(0.14).timeout
		arena.get_node("HUD")._refresh_modern()
		_check(not arena.get_node("HUD")._modern.data.get("objective", {}).is_empty(), "objective status reached HUD")
		if visual_mode > 0:
			_place_camera_for_preview(obj, player)
			await create_timer(0.20).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/private/tmp/piupiu-objective-%d.png" % mode)
		obj.match_ticks = arena.MAX_MATCH_SECONDS * 60 - 1
		obj.left = maxi(2, obj.left)
		obj.step()
		_check(arena.round_finished(), "objective match stops at the 20 minute ceiling")
		arena.exit_to_lobby()
		await process_frame
		_check(not is_instance_valid(obj), "objective state and markers freed at lobby return")
	arena.queue_free()
	await process_frame
	print("Objective mode failures: ", failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
	print("PASS " if condition else "FAIL ", message)


func _validate_navigation(arena: Node3D, obj: Node3D) -> void:
	var nav := arena.get_world_3d().navigation_map
	if obj.centers.size() == 2:
		var distance := _path_length(NavigationServer3D.map_get_path(nav, obj.centers[0], obj.centers[1], true))
		var reverse := _path_length(NavigationServer3D.map_get_path(nav, obj.centers[1], obj.centers[0], true))
		print("Map %d, size %d, mode %d, objective routes %.1f / %.1f m" % [arena.map_id, arena.map_size, arena.play_mode, distance, reverse])
		if arena.play_mode == LAYOUT.FLAG:
			var ray := PhysicsRayQueryParameters3D.create(obj.centers[0] + Vector3.UP * 1.55, obj.centers[1] + Vector3.UP * 1.55, arena.Balance.WORLD_MASK)
			_check(not arena.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "flag stands have obstructed eye-height sightline")
	for index in obj.centers.size():
		var center: Vector3 = obj.centers[index]
		var first := [INF, INF]
		for team in 2:
			for spawn in obj.spawn_pool(team):
				first[team] = minf(first[team], _path_length(NavigationServer3D.map_get_path(nav, spawn, center, true)))
		print("Map %d, size %d, mode %d, objective %d, team paths %.1f / %.1f m" % [arena.map_id, arena.map_size, arena.play_mode, index, first[0], first[1]])
	for team in 2:
		for spawn in obj.spawn_pool(team):
			for index in obj.centers.size():
				var center: Vector3 = obj.centers[index]
				var path := NavigationServer3D.map_get_path(nav, spawn, center, true)
				_check(path.size() >= 2 and path[0].distance_to(spawn) < 1.0 and path[-1].distance_to(center) < 1.0,
					"Map %d, team %d spawn %s and objective %d have a route" % [arena.map_id, team, spawn, index])


func _hill(obj: Node3D, player: Node3D, enemy: Node3D, ally: Node3D) -> void:
	obj.rules.active = 0
	player.position = obj.centers[0]
	ally.position = player.position + Vector3.RIGHT
	for i in 59:
		obj.rules.step(obj, [player, ally])
	_check(obj.scores == Vector2i.ZERO, "two allies do not accelerate hill scoring")
	enemy.position = player.position + Vector3.BACK
	obj.rules.step(obj, [player, ally, enemy])
	_check(obj.scores == Vector2i.ZERO and obj.rules.team == -2, "contest cancels the last scoring tick")
	_check(obj._team_notice(0) == "Зона оспаривается", "contested hill sends a public notification")
	enemy.position.y += 4.0
	for i in 60:
		obj.rules.step(obj, [player, ally, enemy])
	_check(obj.scores == Vector2i(1, 0), "upper floor does not contest the hill")
	player._hurt_lock = 1.0
	_check(not obj.actors().has(player), "spawn protection excludes players from objectives")
	player.cancel_spawn_protection()


func _flag(obj: Node3D, player: Node3D, enemy: Node3D) -> void:
	player.position = obj.centers[1]
	enemy.position = obj.centers[0]
	obj.rules.step(obj, [player, enemy])
	_check(obj.rules.flags[0].carrier == enemy and obj.rules.flags[1].carrier == player, "simultaneous flag steals")
	player.position = obj.centers[0]
	obj.rules.step(obj, [player, enemy])
	_check(obj.scores == Vector2i.ZERO, "own flag away blocks a capture")
	obj.rules.flags[0].state = FLAG.DROPPED
	obj.rules.flags[0].carrier = null
	obj.rules.flags[0].at = player.position
	obj.rules.flags[0].left = 100
	obj.rules.step(obj, [enemy, player])
	_check(obj.scores == Vector2i.ZERO and obj.rules.flags[0].state == FLAG.HOME and obj.rules.capture_ticks.x == 1,
		"friendly return beats same-tick pickup and starts a waiting carrier's countdown")
	for tick in range(1, FLAG.CAPTURE_TICKS):
		obj.rules.step(obj, [player])
	_check(obj.scores == Vector2i(1, 0), "flag capture completes at the countdown deadline")
	_check(obj._team_notice(0) == "Ваша команда захватила флаг соперника" and obj._team_notice(1) == "Соперник захватил ваш флаг",
		"flag capture sends team-specific notifications")
	obj.broadcast(true)
	_check(obj.state.notice_cue == "capture" and obj.display._alert_player.stream != null, "flag capture plays its global alert cue")
	obj.rules.flags[0].state = FLAG.DROPPED
	obj.rules.flags[0].left = 1
	obj.rules.flags[0].at = obj.centers[0] + Vector3.FORWARD * 5
	obj.rules.step(obj, [])
	_check(obj.rules.flags[0].state == FLAG.HOME, "expired dropped flag auto-returns")


func _check_flag_while_hit(obj: Node3D, player: CharacterBody3D, enemy: CharacterBody3D) -> void:
	var center: Vector3 = obj.centers[0] + Vector3.UP * 0.055
	enemy.global_position = center
	var has_lane := false
	for index in 16:
		var outward := Vector3.BACK.rotated(Vector3.UP, index * TAU / 16.0)
		player.global_position = center + outward * 3.5
		player.rotation.y = atan2(outward.x, outward.z)
		if obj.can_see(player, enemy):
			has_lane = true
			break
	_check(has_lane, "defender starts with a clear sightline to the flag carrier")
	if not has_lane:
		return
	obj.rules.flags[0].state = FLAG.CARRIED
	obj.rules.flags[0].carrier = enemy
	obj.broadcast(true)
	var flag: Node3D = obj.display._props[0]
	obj.display._update_carried_props(obj.game)
	_check(flag.visible, "enemy flag model is visible before the hit")

	# A narrow obstacle blocks the spotting ray at torso height, leaving the flag above it exposed.
	var midpoint: Vector3 = player.aim_center().lerp(enemy.aim_center(), 0.5)
	var obstacle := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.42, 0.22, 0.42)
	collider.shape = shape
	obstacle.add_child(collider)
	obj.game.get_node("Map").add_child(obstacle)
	obstacle.global_position = midpoint
	await physics_frame
	await physics_frame
	_check(not obj.can_see(player, enemy), "low cover blocks the carrier spotting ray")

	var health_before: float = enemy.health
	var hit: Vector3 = enemy.hurtbox_center("chest")
	var impact := {"point": hit, "velocity": player.global_position.direction_to(enemy.global_position), "source": "ak47"}
	enemy.take_damage(18.0, player.score_id(), "chest", 1.0, impact)
	obj.broadcast(true)
	await process_frame
	_check(enemy.health > 0.0 and enemy.health < health_before and obj.rules.flags[0].carrier == enemy,
		"nonlethal hit leaves the enemy carrying the flag")
	_check(flag.visible and flag.global_position.distance_to(enemy.objective_socket.global_position) < 0.9,
		"enemy flag stays on the back after a hit even when the torso spotting ray is blocked")
	_check(not obj.rules.view(-1).flags[0].mounted, "unassigned observers receive no carrier attachment")
	_check(obj.state.flags[0].at == Vector3.INF and not obj.state.flags[0].allied_carrier,
		"blocked sightline does not publish the enemy carrier location for HUD markers")
	enemy.take_damage(1000.0, player.score_id())
	obj.broadcast(true)
	await process_frame
	_check(obj.rules.flags[0].state == FLAG.DROPPED and flag.visible and flag.global_position.is_equal_approx(obj.rules.flags[0].at),
		"lethal hit places the dropped flag on the ground")
	obstacle.queue_free()
	obj.rules._home(obj, 0)


func _defuse(obj: Node3D, player: CharacterBody3D, enemy: CharacterBody3D) -> void:
	var rules: RefCounted = obj.rules
	player._net_grounded = true
	obj.left = 0
	rules.step(obj, [player, enemy])
	_check(rules.phase == DEFUSE.LIVE and rules.sites == 1, "compact 2v2 starts a one-site live round")
	player.position = obj.centers[0] + Vector3.UP * 0.055
	player.velocity = Vector3.DOWN * 6.0
	player.move_and_slide()
	rules.carrier = player
	obj.request_interact(enemy, true, 1, 1, 0)
	_check(not obj.inputs.has(enemy.score_id()), "defender cannot plant through objective request")
	obj.request_interact(player, true, 1, 1, 0)
	rules.holder = player
	rules.hold_target = 0
	rules.hold_ticks = 179
	obj.left = 0
	rules.step(obj, [player, enemy])
	_check(rules.phase == DEFUSE.PLANTED and obj.left == 27 * 60, "plant completes at the live deadline")
	_check(obj._team_notice(0) == "Заряд установлен на точке A", "plant sends a public site notification")
	obj.broadcast(true)
	_check(obj.state.notice_cue == "plant" and obj.display._alert_player.stream != null, "plant plays its global alert cue")
	rules.step(obj, [enemy])
	_check(rules.phase == DEFUSE.PLANTED, "plant remains active with all attackers out")
	rules.planted = obj.centers[0]
	enemy.position = rules.planted + Vector3.RIGHT + Vector3.UP * 0.055
	enemy.velocity = Vector3.DOWN * 6.0
	enemy.move_and_slide()
	obj.request_interact(enemy, true, 2, 1, 2)
	rules.holder = enemy
	rules.hold_target = 2
	rules.hold_ticks = 299
	obj.left = 0
	rules.step(obj, [enemy])
	_check(rules.phase == DEFUSE.RESULT and obj.scores == Vector2i(0, 1), "defuse completes at the post-plant deadline")
	_check(obj._team_notice(1) == "Заряд обезврежен", "defuse sends a public notification")
	rules.round_index = 4
	rules.begin(obj)
	_check(rules.attack == 1 - rules.initial_attack, "halftime switches sides")
	rules.round_index = 8
	rules.begin(obj)
	_check(rules.attack == rules.initial_attack, "first overtime round restores initial sides")



func _path_length(path: PackedVector3Array) -> float:
	var length := 0.0
	for index in range(1, path.size()):
		length += path[index - 1].distance_to(path[index])
	return length if path.size() > 1 else INF



func _place_camera_for_preview(obj: Node3D, player: Node3D) -> void:
	var center: Vector3 = obj.centers[0]
	player.global_position = center + Vector3(0.3, 0.1, 5.3)
	player.rotation.y = 0.0
	player.get_node("Camera3D").rotation.x = -0.24
	if obj.mode == LAYOUT.DEFUSE:
		obj.rules.round_index = 0
		obj.rules.attack = 0
		obj.rules.phase = DEFUSE.PLANTED
		obj.rules.site = 0
		obj.rules.planted = center
		obj.rules.live_counts = Vector2i(2, 2)
		obj.left = 20 * 60
		obj.broadcast(true)



func _check_running_rig(obj: Node3D, player: Node3D, ally: CharacterBody3D, save_preview: bool) -> void:
	var socket: Node3D = ally.objective_socket
	_check(is_instance_valid(socket) and socket.get_parent() is BoneAttachment3D, "objective gear uses an animated back bone")
	if not is_instance_valid(socket):
		return
	var center: Vector3 = obj.centers[0]
	await physics_frame
	var nav := ally.get_world_3d().navigation_map
	var run := Vector3.FORWARD
	for index in 16:
		var direction := Vector3.FORWARD.rotated(Vector3.UP, index * TAU / 16.0)
		var start_at := center - direction * 5.3
		var rear := start_at - direction * 2.0
		if NavigationServer3D.map_get_closest_point(nav, start_at).distance_to(start_at) < 0.42 				and NavigationServer3D.map_get_closest_point(nav, rear).distance_to(rear) < 0.48 				and obj.line_clear(rear + Vector3.UP, center + Vector3.UP):
			run = direction
			break
	ally.global_position = center - run * 5.3 + Vector3.UP * 0.055
	ally.rotation.y = atan2(-run.x, -run.z)
	player.global_position = center - run * 8.0 + Vector3.UP * 0.055
	player.rotation.y = ally.rotation.y
	player.get_node("Camera3D").rotation.x = -0.1
	if obj.mode == LAYOUT.FLAG:
		obj.rules.flags[1].state = FLAG.CARRIED
		obj.rules.flags[1].carrier = ally
	else:
		obj.rules.phase = DEFUSE.LIVE
		obj.rules.attack = ally.team_id()
		obj.rules.carrier = ally
		obj.rules.carrier_assigned = true
	obj.broadcast(true)
	var start := socket.global_position
	ally.sprinting = true
	for tick in 25:
		await physics_frame
		ally.velocity = run * 5.8 + Vector3.DOWN * 4.0
		ally.move_and_slide()
	await process_frame
	obj.display._update_carried_props(obj.game)
	_check(start.distance_to(socket.global_position) > 1.0, "back mount moves with the running operator")
	if obj.mode == LAYOUT.FLAG:
		var flag: Node3D = obj.display._props[1]
		_check(flag.visible and flag.global_position.distance_to(socket.global_position) < 0.9, "carried flag stays mounted behind the runner")
	else:
		_check(socket.has_node("ChargeBackpack") and not obj.display._props[0].visible,
			"runner has a backpack and carried charge remains stowed")
	if save_preview:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/piupiu-objective-rig-%d.png" % obj.mode)
	ally.sprinting = false
	if obj.mode == LAYOUT.FLAG:
		obj.rules._home(obj, 1)
	else:
		obj.rules.carrier = null



func _check_rosters(arena: Node3D) -> void:
	var original: PackedInt32Array = arena.player_slots.duplicate()
	arena._set_play_mode(LAYOUT.HILL, true)
	for humans in [3, 9]:
		for slot in arena.player_slots.size():
			arena.player_slots[slot] = slot + 1 if slot < humans else 0
		arena._reserve_bot_slots(0)
		var seats: Vector2i = arena._objective_seats()
		_check(seats.x == seats.y and seats.x + seats.y == humans + 1,
			"autofill rounds %d humans up to equal teams" % humans)
	for slot in arena.player_slots.size():
		arena.player_slots[slot] = slot + 1 if slot < 5 else 0
	arena.blue_bot_count = 0
	arena._reserve_bot_slots(0)
	_check(arena._objective_seats() == Vector2i(3, 2), "host can keep an uneven roster with autofill off")
	arena.blue_bot_count = -1
	arena.player_slots = original
	arena._bot_slots.clear()
	arena._set_play_mode(0, false)



func _check_possession_prompt(obj: Node3D, player: CharacterBody3D, save_preview: bool) -> void:
	await physics_frame
	player.global_position = obj.centers[0] + Vector3.UP * 0.055 + Vector3.RIGHT * 0.35
	player.velocity = Vector3.DOWN * 6.0
	player.move_and_slide()
	var expected := ""
	if obj.mode == LAYOUT.FLAG:
		obj.rules.flags[1].state = FLAG.CARRIED
		obj.rules.flags[1].carrier = player
		obj.rules.capture_ticks.x = 48
		expected = "У ВАС ФЛАГ"
	else:
		obj.rules.phase = DEFUSE.LIVE
		obj.rules.attack = player.team_id()
		obj.rules.carrier = player
		expected = "ЗАРЯД У ВАС"
	obj.broadcast(true)
	var hud: CanvasLayer = obj.game.get_node("HUD")
	hud._refresh_modern()
	var prompt := str(hud._modern.data.get("objective", {}).get("detail", ""))
	_check(prompt.contains(expected), "HUD makes local objective possession explicit")
	if obj.mode == LAYOUT.FLAG:
		_check(prompt.contains("Захват через") and hud._modern.data.objective.progress > 0.0,
			"HUD shows a capture countdown and its progress bar")
	else:
		var binding: String = root.get_node("GameSettings").binding_label(&"interact")
		_check(prompt.contains("установить") and prompt.contains(binding), "HUD shows the configured plant key at the site")
	if save_preview:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/piupiu-objective-prompt-%d.png" % obj.mode)
	if obj.mode == LAYOUT.FLAG:
		obj.rules.capture_ticks.x = 0
		obj.rules._home(obj, 1)
	else:
		obj.rules.carrier = null
