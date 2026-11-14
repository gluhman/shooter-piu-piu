extends "res://game/actors/player.gd"

const BOT_SPEED := 3.3
const BOT_ACCELERATION := 22.0
const SEARCH_TIME := 6.0
const COVER_REACH := 9.0
const COVER_TRAVEL_TIME := 3.5
const COVER_ARRIVAL := 0.4
const COVER_DIRECTIONS := 8
const HEARING_RANGE := 34.0
const HEARING_MEMORY := 2.4
const HEARING_INTERVAL := 0.12
const REACTION_TIME := 0.5
const STABILIZATION_TIME := 0.3
const AIM_TIME_MULTIPLIER := 0.8
const AIM_SWAY_RADIUS := deg_to_rad(3.0)
const CROWD_RADIUS := 3.5
const CROWD_TIME := 15.0
const DISPERSAL_TIME := 5.0
const PROGRESS_INTERVAL := 0.65
const RECOVERY_TIME := 2.5
const REPOSITION_SHOTS := [10, 8, 6, 5, 4]
const RETREAT_HEALTH := [0.0, 28.0, 40.0, 52.0, 62.0]
const COVER_RESERVE := [1, 2, 3, 4, 5]
const PEEK_EXPOSURE := [0.0, 0.0, 1.25, 1.0, 0.8]
const DIFFICULTY := [
	{"speed": 0.85, "shot_delay": 1.35, "spread": 2.4, "vision": Vector2(0.20, 0.30), "hearing": 26.0, "search_time": 4.0, "flank": 3.0, "cover_cooldown": Vector2(4.0, 5.0)},
	{"speed": 1.0, "shot_delay": 1.0, "spread": 1.15, "vision": Vector2(0.12, 0.19), "hearing": HEARING_RANGE, "search_time": SEARCH_TIME, "flank": 5.0, "cover_cooldown": Vector2(3.5, 4.5)},
	{"speed": 1.15, "shot_delay": 0.72, "spread": 0.50, "vision": Vector2(0.08, 0.14), "hearing": 38.0, "search_time": 7.0, "flank": 6.0, "cover_cooldown": Vector2(2.5, 3.5)},
	{"speed": 1.20, "shot_delay": 0.62, "spread": 0.32, "vision": Vector2(0.05, 0.09), "hearing": 42.0, "search_time": 8.0, "flank": 7.0, "cover_cooldown": Vector2(2.0, 2.8)},
	{"speed": 1.25, "shot_delay": 0.56, "spread": 0.20, "vision": Vector2(0.03, 0.06), "hearing": 46.0, "search_time": 9.0, "flank": 8.0, "cover_cooldown": Vector2(1.6, 2.3)},
]
const FIRE := {
	"carbine": {"range": 43.0, "preferred": 13.0, "delay": 0.43},
	"bullpup": {"range": 50.0, "preferred": 17.0, "delay": 0.52},
	"compact": {"range": 20.0, "preferred": 7.0, "delay": 0.37},
	"breacher": {"range": 12.0, "preferred": 5.0, "delay": 0.83},
	"longshot": {"range": 68.0, "preferred": 30.0, "delay": 1.55},
	"scout": {"range": 52.0, "preferred": 21.0, "delay": 0.87},
	"rpk": {"range": 39.0, "preferred": 14.0, "delay": 0.42},
	"gpmg": {"range": 47.0, "preferred": 17.0, "delay": 0.50},
	"launcher": {"range": 28.0, "preferred": 13.0, "delay": 2.4, "minimum": 7.0},
	"m249": {"range": 38.0, "preferred": 13.0, "delay": 0.37},
	"m1": {"range": 45.0, "preferred": 17.0, "delay": 1.04},
	"deagle": {"range": 28.0, "preferred": 10.0, "delay": 0.95},
	"shotgun": {"range": 17.0, "preferred": 6.0, "delay": 1.0},
	"ak47": {"range": 48.0, "preferred": 15.0, "delay": 0.47},
	"m1911": {"range": 26.0, "preferred": 9.0, "delay": 0.82},
	"mac10": {"range": 18.0, "preferred": 6.0, "delay": 0.38},
	"mp5": {"range": 24.0, "preferred": 9.0, "delay": 0.42},
	"m700": {"range": 64.0, "preferred": 26.0, "delay": 1.35},
	"tec9": {"range": 22.0, "preferred": 8.0, "delay": 0.59},
	"lever": {"range": 42.0, "preferred": 16.0, "delay": 1.0},
	"m14": {"range": 56.0, "preferred": 22.0, "delay": 0.79},
}

var combatant_id := 0
var difficulty := 1
var patrol_route: Array
var _waypoint := 0
var _patrol_direction := 1
var _vision_wait := 0.0
var _hearing_wait := 0.0
var _aim_elapsed := 0.0
var _aim_start := Vector2.ZERO
var _aim_sway := Vector2.ZERO
var _aim_phase := Vector2.ZERO
var _weapon_switch_left := 0.0
var _target: Node3D
var _strafe_side := 1.0
var _strafe_left := 0.0
var _flank_point := Vector3.INF
var _shoot_wait := 0.0
var _shots_since_reposition := 0
var _loot_scan := 0.0
var _loot_target := Vector3.INF
var _crowd_left := CROWD_TIME
var _dispersal_left := 0.0
var _dispersal_goal := Vector3.INF
var _progress_left := PROGRESS_INTERVAL
var _progress_start := Vector3.INF
var _recovery_left := 0.0
var _recovery_goal := Vector3.INF
var _recovery_direction := Vector3.ZERO
var _navigation: NavigationAgent3D
var _navigation_synced := false
var _path_target := Vector3.INF
var _last_seen := Vector3.INF
var _search_left := 0.0
var _incoming_fire := Vector3.INF
var _cover_goal := Vector3.INF
var _cover_threat := Vector3.INF
var _cover_travel_left := 0.0
var _cover_hold_left := 0.0
var _holding_cover := false
var _return_to_cover := Vector3.INF
var _peek_goal := Vector3.INF
var _peek_left := 0.0
var _peek_travel_left := 0.0
var _peeked_from_cover := false
var _cover_cooldown := 0.0
var _training_pose_left := 0.0
var _sight_ray := PhysicsRayQueryParameters3D.new()

var _ground_ray := PhysicsRayQueryParameters3D.new()

@onready var _loot := get_parent().get_node("Loot")


func _ready() -> void:
	super._ready()
	remove_from_group("player")
	add_to_group("bot")
	_grenades.clear()
	if _server_rules():
		_sight_ray.collision_mask = Balance.WORLD_AND_CAPSULES
		_sight_ray.exclude = [get_rid()]
		_ground_ray.collision_mask = Balance.WORLD_MASK
		_navigation = NavigationAgent3D.new()
		_navigation.path_desired_distance = 0.45
		_navigation.target_desired_distance = 0.5
		_navigation.path_max_distance = 1.25
		floor_snap_length = 0.35
		add_child(_navigation)
	_reset_behavior()


func _is_local() -> bool:
	return false


func score_id() -> int:
	return combatant_id


func shot_motion() -> Vector3:
	return velocity if _server_rules() else super.shot_motion()


func take_damage(amount: float, killer_id: int = 0, zone: String = "chest", head_multiplier: float = 0.0, impact: Dictionary = {}) -> void:
	var previous_health := health
	super.take_damage(amount, killer_id, zone, head_multiplier, impact)
	if health <= 0 or health == previous_health:
		return
	var attacker: Node = get_parent().combatant(killer_id)
	if is_instance_valid(attacker) and attacker != self:
		_incoming_fire = attacker.aim_center() + Vector3.UP * 0.4
		if attacker is Node3D and attacker.control_enabled and attacker.health > 0 and not get_parent().same_team(score_id(), attacker.score_id()):
			_last_seen = attacker.global_position
			_search_left = SEARCH_TIME
			_flank_point = Vector3.INF
		if _holding_cover:
			_cover_goal = Vector3.INF
			_holding_cover = false
		_cover_cooldown = minf(_cover_cooldown, 0.3)


func _respawn_delay() -> float:
	return super._respawn_delay()


func equip(id: String) -> void:
	var sidearms: Array[String] = []
	for sidearm: String in Weapon.SIDEARMS:
		if get_parent().allows_weapon(sidearm):
			sidearms.append(sidearm)
	if not sidearms.is_empty() and not get_parent().is_training_range():
		_spawn_sidearm = sidearms.pick_random()
		_restore_starting_supplies()
	super.equip(id)


func _next_respawn_weapon() -> String:
	return get_parent().random_bot_primary(_spawn_loadout)


func _apply_respawn(id: String, at: Vector3, revision: int) -> void:
	_spawn_loadout = id
	super._apply_respawn(id, at, revision)
	_reset_behavior()


func _reset_behavior() -> void:
	_waypoint = 0
	for index in patrol_route.size():
		if global_position.distance_squared_to(patrol_route[index]) < global_position.distance_squared_to(patrol_route[_waypoint]):
			_waypoint = index
	if not patrol_route.is_empty():
		_waypoint = posmod(_waypoint + abs(combatant_id), patrol_route.size())
		_patrol_direction = -1 if abs(combatant_id) % 2 == 1 else 1
	var modifiers := _difficulty_modifiers()
	_shoot_wait = randf_range(0.55, 0.95) * float(modifiers.shot_delay)
	_shots_since_reposition = 0
	_target = null
	var vision: Vector2 = modifiers.vision
	_vision_wait = randf_range(0.0, vision.y)
	_hearing_wait = float(absi(combatant_id) % 7) * HEARING_INTERVAL / 7.0
	_aim_elapsed = 0.0
	_aim_sway = Vector2.ZERO
	_weapon_switch_left = 0.0
	_strafe_side = -1.0 if randf() < 0.5 else 1.0
	_strafe_left = randf_range(0.5, 1.4)
	_flank_point = Vector3.INF
	_loot_scan = 0.0
	_loot_target = Vector3.INF
	_crowd_left = CROWD_TIME
	_dispersal_left = 0.0
	_dispersal_goal = Vector3.INF
	_progress_left = PROGRESS_INTERVAL
	_progress_start = Vector3.INF
	_recovery_left = 0.0
	_recovery_goal = Vector3.INF
	_recovery_direction = Vector3.ZERO
	_path_target = Vector3.INF
	_last_seen = Vector3.INF
	_search_left = 0.0
	_incoming_fire = Vector3.INF
	_cover_goal = Vector3.INF
	_cover_threat = Vector3.INF
	_cover_travel_left = 0.0
	_cover_hold_left = 0.0
	_holding_cover = false
	_cover_cooldown = 0.0
	_return_to_cover = Vector3.INF
	_peek_goal = Vector3.INF
	_peek_left = 0.0
	_peek_travel_left = 0.0
	_peeked_from_cover = false
	_training_pose_left = 0.0


func _physics_process(delta: float) -> void:
	if not _server_rules():
		super._physics_process(delta)
		return
	if _dead or not control_enabled or get_parent().is_loading() or get_parent().round_finished():
		return
	if get_parent().is_training_range():
		_training_pose_left -= delta
		if _training_pose_left <= 0.0:
			_training_pose_left = randf_range(1.2, 3.0)
			_update_crouch(randf() < 0.22)
			aiming = randf() < 0.45
			_camera.rotation.x = randf_range(-0.12, 0.12) if aiming else 0.0
		velocity = Vector3.ZERO
		return

	if is_climbing_ladder():
		_aim_elapsed = 0.0
		_progress_start = Vector3.INF
		_climb_ladder(delta)
		return
	var works := fieldworks()
	if is_on_floor() and works and start_ladder_climb(works.exit_route(self)):
		return

	_loot_scan -= delta
	if _loot_scan <= 0.0:
		_loot_scan = randf_range(0.25, 0.45)
		_loot_target = _loot.seek_bot_loot(self)
	var modifiers := _difficulty_modifiers()
	_vision_wait -= delta
	if _vision_wait <= 0.0 and flash_left < 0.2:
		var vision_range := float(FIRE[weapon_id].range)
		for id: String in available_weapon_ids():
			var stock := stock_for(id)
			if stock.x + stock.y > 0:
				vision_range = maxf(vision_range, float(FIRE[id].range))
		var vision: Vector2 = modifiers.vision
		_vision_wait = randf_range(vision.x, vision.y)
		var next_target := _visible_target(vision_range)
		if next_target != _target:
			_target = next_target
			_aim_elapsed = 0.0
			_shots_since_reposition = 0
	var target := _target if flash_left < 0.2 and is_instance_valid(_target) and _target.control_enabled and _target.health > 0 else null
	_weapon_switch_left = maxf(0.0, _weapon_switch_left - delta)
	_choose_weapon(target)
	var profile: Dictionary = FIRE[weapon_id]
	var ammo: Vector2i = gun.ammo_counts()
	_hearing_wait -= delta
	if target == null and _hearing_wait <= 0.0:
		_hearing_wait = HEARING_INTERVAL
		var heard := _audible_enemy(float(modifiers.hearing))
		if heard and (_last_seen.distance_squared_to(heard.global_position) > 2.25 or _search_left <= 0.0):
			_last_seen = heard.global_position
			_search_left = HEARING_MEMORY * (1.0 + float(modifiers.search_time) / SEARCH_TIME * 0.2)
			_flank_point = Vector3.INF
	_shoot_wait = maxf(0.0, _shoot_wait - delta)
	_cover_cooldown = maxf(0.0, _cover_cooldown - delta)
	if target:
		_last_seen = target.global_position
		_search_left = float(modifiers.search_time)
		_flank_point = Vector3.INF
	else:
		_search_left = maxf(0.0, _search_left - delta)
	_update_crowding(delta)
	_recovery_left = maxf(0.0, _recovery_left - delta)
	if _dispersal_left <= 0.0 and _recovery_left <= 0.0:
		_try_take_cover(target, profile, modifiers, ammo)

	aiming = false
	var wish := Vector3.ZERO
	var speed := BOT_SPEED * float(modifiers.speed)
	if _recovery_left > 0.0 or _dispersal_left > 0.0:
		_update_crouch(false)
		if ammo.x == 0 and ammo.y > 0:
			gun.reload_bot()
		wish = _recovery_motion() if _recovery_left > 0.0 else _follow_path(_dispersal_goal)
		if wish.is_zero_approx() and _recovery_left <= 0.0:
			_dispersal_left = 0.0
		_face(wish, delta)
	elif _return_to_cover.is_finite():
		wish = _peek(target, profile, modifiers, ammo, delta)
	elif _cover_goal.is_finite():
		wish = _use_cover(delta, ammo, target)
		speed *= 1.15
	else:
		_update_crouch(_should_crouch(target, profile, ammo))
		if ammo.x == 0 and ammo.y > 0:
			gun.reload_bot()
		if target:
			wish = _fight(target, profile, modifiers, ammo, delta)
		else:
			wish = _wander() if ammo == Vector2i.ZERO else _search(float(profile.preferred), float(modifiers.flank))
			_face(wish, delta)
	if crouched:
		speed *= 0.65

	if not aiming:
		_aim_elapsed = 0.0
		_aim_sway = Vector2.ZERO
		_camera.rotation.x = move_toward(_camera.rotation.x, 0.0, delta * 2.5)
	speed *= armor_movement_scale()
	if concussion_left > 0.0:
		speed *= float(Balance.GRENADES.concussion.movement_speed_multiplier_during_effect)
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(Vector2(wish.x, wish.z) * speed, BOT_ACCELERATION * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	if is_on_floor():
		velocity.y = JUMP_VELOCITY if _recovery_left > 0.0 and not crouched and _can_jump_obstacle(wish) else 0.0
	else:
		velocity.y -= float(Balance.MOVEMENT.gravity_m_s2) * delta
	move_and_slide()
	_track_movement_audio(delta, true)
	_check_movement_progress(wish, delta)


func _fight(target: Node3D, profile: Dictionary, modifiers: Dictionary, ammo: Vector2i, delta: float, strafe: bool = true) -> Vector3:
	var to_target: Vector3 = target.aim_center() - _camera.global_position
	var stabilized := false
	if _has_sight(target):
		stabilized = _track_aim(to_target, delta)
	var direction := _flat_direction(to_target)
	var distance: float = global_position.distance_to(target.global_position)
	var aligned := (-_camera.global_basis.z).dot(to_target.normalized()) > 0.998
	if stabilized and aligned and ammo.x > 0 and distance <= float(profile.range) and distance >= float(profile.get("minimum", 0.0)) and _shoot_wait <= 0.0:
		if gun.fire_bot(target.aim_center(), float(modifiers.spread)):
			var cadence := float(profile.delay) * float(modifiers.shot_delay) * randf_range(0.88, 1.14)
			_shoot_wait = maxf(float(Weapon.WEAPONS[weapon_id].cooldown), cadence)
			_shots_since_reposition += 1
			if _shots_since_reposition >= int(REPOSITION_SHOTS[_difficulty_index()]) and _cover_cooldown == 0.0:
				_incoming_fire = target.aim_center() + Vector3.UP * 0.4
				_shots_since_reposition = 0
	if not strafe:
		return Vector3.ZERO
	_strafe_left -= delta
	if _strafe_left <= 0.0:
		_strafe_left = randf_range(0.65, 1.35)
		_strafe_side *= -1.0
	var side := direction.cross(Vector3.UP) * _strafe_side
	var retreat: bool = ammo.x == 0 or distance < maxf(float(profile.get("minimum", 0.0)), float(profile.preferred) * 0.78) or health <= RETREAT_HEALTH[_difficulty_index()]
	var advance := not retreat and distance > float(profile.preferred) * 1.15
	var back := -direction * (0.9 if retreat else 0.0)
	var forward := _follow_path(target.global_position) if advance else Vector3.ZERO
	var wish := (side * (0.45 if advance else 1.0) + back + forward * 1.35).normalized()
	if is_on_floor() and not _has_ground_ahead(wish):
		wish = (back - side + forward).normalized()
		if not _has_ground_ahead(wish):
			wish = forward
			if wish.is_zero_approx():
				_start_recovery(-direction)
	return wish * (1.0 if retreat else 0.62)


func _should_crouch(target: Node3D, profile: Dictionary, ammo: Vector2i) -> bool:
	if not target or not is_on_floor() or ammo.x <= 0 or _aim_elapsed < _reaction_time() or health <= RETREAT_HEALTH[_difficulty_index()]:
		return false
	var ratio := global_position.distance_to(target.global_position) / float(profile.preferred)
	return absf(ratio - 1.0) < (0.18 if crouched else 0.12)


func _reaction_time() -> float:
	return REACTION_TIME * pow(AIM_TIME_MULTIPLIER, _difficulty_index())


func _stabilization_time() -> float:
	return STABILIZATION_TIME * pow(AIM_TIME_MULTIPLIER, _difficulty_index())


func _track_aim(offset: Vector3, delta: float) -> bool:
	aiming = true
	if _aim_elapsed == 0.0:
		_aim_start = Vector2(rotation.y, _camera.rotation.x)
		_aim_phase = Vector2(randf_range(0.0, TAU), randf_range(0.0, TAU))
	_aim_elapsed += delta
	var reaction := _reaction_time()
	var settling := clampf((_aim_elapsed - reaction) / _stabilization_time(), 0.0, 1.0)
	var sway := Vector2(sin(_aim_elapsed * 21.0 + _aim_phase.x), sin(_aim_elapsed * 27.0 + _aim_phase.y))
	_aim_sway = sway * (AIM_SWAY_RADIUS / sqrt(2.0)) * (1.0 - settling)
	var yaw := atan2(-offset.x, -offset.z) if not _flat_direction(offset).is_zero_approx() else rotation.y
	var pitch := clampf(asin(offset.normalized().y), -0.78, 0.78)
	var turn := smoothstep(0.0, 1.0, clampf(_aim_elapsed / reaction, 0.0, 1.0))
	rotation.y = lerp_angle(_aim_start.x, yaw + _aim_sway.x, turn)
	_camera.rotation.x = clampf(lerpf(_aim_start.y, pitch + _aim_sway.y, turn), -0.78, 0.78)
	return settling >= 1.0


func _choose_weapon(target: Node3D) -> void:
	if _weapon_switch_left > 0.0:
		return
	var distance := global_position.distance_to(target.global_position) if target else -1.0
	var best := weapon_id
	var best_score := _weapon_score(weapon_id, distance) + 0.25
	for id: String in available_weapon_ids():
		if id == weapon_id:
			continue
		var score := _weapon_score(id, distance)
		if score > best_score:
			best_score = score
			best = id
	if best != weapon_id:
		select_weapon(best)
		_weapon_switch_left = 1.25


func _weapon_score(id: String, distance: float) -> float:
	var stock := stock_for(id)
	if stock.x + stock.y <= 0:
		return -10.0
	var profile: Dictionary = FIRE[id]
	var score := 1.0 if stock.x > 0 else 0.0
	if distance >= 0.0:
		if distance < float(profile.get("minimum", 0.0)) or distance > float(profile.range):
			return score - 4.0
		score += 2.0 - absf(log(maxf(distance, 0.5) / float(profile.preferred)))
	elif Weapon.inventory_slot(id) == "primary":
		score += 0.5
	return score


func _update_crowding(delta: float) -> void:
	_dispersal_left = maxf(0.0, _dispersal_left - delta)
	if _dispersal_left > 0.0 or not _navigation_ready():
		return
	var neighbors: Array[Node3D] = []
	var has_neighbor := false
	for bot in get_tree().get_nodes_in_group("bot"):
		if bot == self or bot.get_parent() != get_parent() or not bot.control_enabled or bot.health <= 0.0 or bot._dispersal_left > 0.0 or bot.is_climbing_ladder():
			continue
		neighbors.append(bot)
		has_neighbor = has_neighbor or global_position.distance_squared_to(bot.global_position) <= CROWD_RADIUS * CROWD_RADIUS
	if not has_neighbor:
		_crowd_left = CROWD_TIME
		return
	_crowd_left -= delta
	if _crowd_left > 0.0:
		return
	# Follow nearby links so bots spread even when a crowd spans several bot lengths.
	var crowd: Array[Node3D] = [self]
	var index := 0
	while index < crowd.size():
		for bot in neighbors:
			if bot not in crowd and crowd[index].global_position.distance_squared_to(bot.global_position) <= CROWD_RADIUS * CROWD_RADIUS:
				crowd.append(bot)
		index += 1
	var center := Vector3.ZERO
	for bot in crowd:
		center += bot.global_position
	center /= crowd.size()
	crowd.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.score_id() < b.score_id())
	var player: Node3D
	for bot in crowd:
		player = bot._visible_target(45.0, true)
		if player:
			break
	var used: Array[Vector3] = []
	for slot in crowd.size():
		var bot := crowd[slot]
		var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * slot / crowd.size())
		var origin := center
		if player and not get_parent().same_team(bot.score_id(), player.score_id()):
			origin = player.global_position
			var approach := _flat_direction(center - origin)
			if not approach.is_zero_approx():
				var offset := lerpf(-1.35, 1.35, float(slot) / (crowd.size() - 1))
				direction = approach.rotated(Vector3.UP, offset)
		var radius := 8.0 if origin == center else clampf(center.distance_to(origin), 8.0, 16.0)
		var goal: Vector3 = bot._reachable_offset(origin, direction, radius, used)
		if not goal.is_finite():
			goal = bot._reachable_offset(center, direction, 8.0, used)
		if goal.is_finite():
			used.append(goal)
		bot._begin_dispersal(goal, direction)


func _begin_dispersal(goal: Vector3, direction: Vector3) -> void:
	_crowd_left = CROWD_TIME
	_dispersal_left = DISPERSAL_TIME
	_dispersal_goal = goal
	_recovery_left = 0.0
	_clear_movement_goals()
	if not goal.is_finite():
		_recovery_left = RECOVERY_TIME
		_recovery_goal = Vector3.INF
		_recovery_direction = direction


func _clear_movement_goals() -> void:
	_cover_goal = Vector3.INF
	_return_to_cover = Vector3.INF
	_holding_cover = false
	_cover_cooldown = maxf(_cover_cooldown, 1.5)
	_flank_point = Vector3.INF
	_search_left = 0.0
	_loot_target = Vector3.INF
	_loot_scan = 1.0
	_path_target = Vector3.INF
	_progress_start = Vector3.INF


func _reachable_offset(origin: Vector3, direction: Vector3, distance: float, used: Array[Vector3] = []) -> Vector3:
	var nav_map := _navigation.get_navigation_map()
	for angle in [0.0, 0.45, -0.45, 0.9, -0.9, 1.6, -1.6, PI]:
		var sample := origin + direction.rotated(Vector3.UP, angle) * distance
		var point := NavigationServer3D.map_get_closest_point(nav_map, sample)
		if point.distance_squared_to(global_position) < 4.0:
			continue
		var separated := true
		for goal in used:
			if point.distance_squared_to(goal) < CROWD_RADIUS * CROWD_RADIUS:
				separated = false
				break
		if not separated:
			continue
		var path := NavigationServer3D.map_get_path(nav_map, global_position, point, true)
		if path.size() > 1 and path[-1].distance_squared_to(point) <= 0.25:
			return point
	return Vector3.INF


func _check_movement_progress(wish: Vector3, delta: float) -> void:
	if wish.is_zero_approx():
		_progress_start = Vector3.INF
		return
	if not _progress_start.is_finite():
		_progress_start = global_position
		_progress_left = PROGRESS_INTERVAL
	_progress_left -= delta
	if _progress_left > 0.0:
		return
	var moved := global_position - _progress_start
	_progress_start = global_position
	_progress_left = PROGRESS_INTERVAL
	if Vector2(moved.x, moved.z).length_squared() >= 0.22 * 0.22:
		return
	_strafe_side *= -1.0
	var direction := _flat_direction(wish).rotated(Vector3.UP, _strafe_side * PI / 2.0)
	_start_recovery(-_flat_direction(wish) if _recovery_left > 0.0 else direction)


func _start_recovery(direction: Vector3) -> void:
	_recovery_direction = direction if not direction.is_zero_approx() else -global_basis.z
	_clear_movement_goals()
	if not patrol_route.is_empty():
		_waypoint = posmod(_waypoint + _patrol_direction, patrol_route.size())
	_recovery_left = RECOVERY_TIME
	_recovery_goal = _reachable_offset(global_position, _recovery_direction, 4.0) if _navigation_ready() else Vector3.INF


func _recovery_motion() -> Vector3:
	var direction := _follow_path(_recovery_goal)
	if not direction.is_zero_approx():
		return direction
	for angle in [0.0, 0.65, -0.65, 1.3, -1.3, PI]:
		var candidate := _recovery_direction.rotated(Vector3.UP, angle)
		if _has_ground_ahead(candidate) and not test_move(global_transform, candidate * 0.45):
			return candidate
	return _recovery_direction


func _has_ground_ahead(direction: Vector3) -> bool:
	var point := global_position + direction.normalized() * 0.75
	_ground_ray.from = point + Vector3.UP * 0.8
	_ground_ray.to = point - Vector3.UP * 0.7
	var hit := get_world_3d().direct_space_state.intersect_ray(_ground_ray)
	return not hit.is_empty() and hit.normal.y >= cos(floor_max_angle)


func _can_jump_obstacle(wish: Vector3) -> bool:
	if wish.is_zero_approx():
		return false
	var step := wish.normalized() * 0.65
	var rise := Vector3.UP * 0.55
	if not test_move(global_transform, step) or test_move(global_transform, rise):
		return false
	return not test_move(global_transform.translated(rise), step) and _has_ground_ahead(wish)


func _navigation_ready() -> bool:
	if not _navigation_synced:
		var nav_map := _navigation.get_navigation_map()
		_navigation_synced = NavigationServer3D.map_get_iteration_id(nav_map) != 0 and not NavigationServer3D.map_get_regions(nav_map).is_empty()
	return _navigation_synced


func _search(preferred: float, flank_offset: float) -> Vector3:
	if _search_left <= 0.0:
		return _wander()
	if not _flank_point.is_finite():
		var toward := _flat_direction(_last_seen - global_position)
		var side := toward.cross(Vector3.UP) * _strafe_side
		if not _navigation_ready():
			return Vector3.ZERO
		var navigation_map := _navigation.get_navigation_map()
		var center := _last_seen - toward * clampf(preferred * 0.75, 5.0, 10.0)
		_flank_point = NavigationServer3D.map_get_closest_point(navigation_map, center + side * flank_offset)
		if _difficulty_index() >= 2:
			var opposite := NavigationServer3D.map_get_closest_point(navigation_map, center - side * flank_offset)
			var chosen_path := NavigationServer3D.map_get_path(navigation_map, global_position, _flank_point, true)
			var other_path := NavigationServer3D.map_get_path(navigation_map, global_position, opposite, true)
			var threat := Vector2(_last_seen.x, _last_seen.z)
			var chosen_length := _cover_path_length(chosen_path, threat, 2.0)
			var other_length := _cover_path_length(other_path, threat, 2.0)
			if not other_path.is_empty() and other_path[-1].distance_squared_to(opposite) <= 0.25 and (
				chosen_path.is_empty() or chosen_path[-1].distance_squared_to(_flank_point) > 0.25 or other_length < chosen_length
			):
				_flank_point = opposite
	var wish := _follow_path(_flank_point)
	if _navigation.is_navigation_finished():
		_search_left = 0.0
	return wish


func _try_take_cover(target: Node3D, profile: Dictionary, modifiers: Dictionary, ammo: Vector2i) -> void:
	if _cover_goal.is_finite() or _return_to_cover.is_finite() or _cover_cooldown > 0.0:
		return
	var low_ammo: bool = ammo.x == 0 or (ammo.y > 0 and ammo.x <= COVER_RESERVE[_difficulty_index()] and not gun.is_reloading())
	var threat := _incoming_fire
	var wounded: bool = health <= RETREAT_HEALTH[_difficulty_index()]
	var approach := target != null and not threat.is_finite() and not low_ammo and not wounded and float(profile.range) <= 24.0 and global_position.distance_to(target.global_position) > float(profile.preferred) + 4.0
	if not threat.is_finite() and target and (low_ammo or approach or wounded):
		threat = target.aim_center() + Vector3.UP * 0.4
	if not threat.is_finite():
		return
	var cover_cooldown: Vector2 = modifiers.cover_cooldown
	_cover_cooldown = randf_range(cover_cooldown.x, cover_cooldown.y)
	_incoming_fire = Vector3.INF
	_cover_goal = _find_cover(threat, approach)
	if _cover_goal.is_finite():
		_peeked_from_cover = false
		_cover_threat = threat
		_cover_travel_left = COVER_TRAVEL_TIME
		_cover_hold_left = randf_range(0.65, 1.05)
		_holding_cover = false


func _use_cover(delta: float, ammo: Vector2i, target: Node3D) -> Vector3:
	if not _holding_cover:
		var offset := _cover_goal - global_position
		if Vector2(offset.x, offset.z).length_squared() <= COVER_ARRIVAL * COVER_ARRIVAL:
			var query := _cover_query(_cover_threat)
			_holding_cover = _cover_blocks_shot(get_world_3d().direct_space_state, query, global_position)
		if not _holding_cover:
			return _move_to_cover(delta)

	_update_crouch(true)
	_face(_cover_threat - global_position, delta)
	if ammo.y > 0 and ammo.x <= COVER_RESERVE[_difficulty_index()]:
		gun.reload_bot()
	_cover_hold_left -= delta
	if _cover_hold_left <= 0.0 and not gun.is_reloading():
		if _difficulty_index() >= 2 and ammo.x > 0 and not _peeked_from_cover:
			_plan_peek(target.aim_center() if target else _cover_threat)
		_cover_goal = Vector3.INF
		_holding_cover = false
		_cover_cooldown = maxf(_cover_cooldown, 1.2)
	return Vector3.ZERO


func _plan_peek(threat: Vector3) -> void:
	var side := _flat_direction(threat - global_position).cross(Vector3.UP) * _strafe_side
	var query := _cover_query(threat)
	var space := get_world_3d().direct_space_state
	for direction in [side, -side]:
		for distance in [0.8, 1.5, 2.2]:
			var offset: Vector3 = direction * distance
			if test_move(global_transform, offset):
				continue
			query.to = _camera.global_position + offset + Vector3.UP * CROUCH_DROP
			if space.intersect_ray(query).is_empty():
				_return_to_cover = global_position
				_peek_goal = global_position + offset
				_peek_travel_left = 1.5
				_peek_left = PEEK_EXPOSURE[_difficulty_index()]
				_shots_since_reposition = 0
				return


func _peek(target: Node3D, profile: Dictionary, modifiers: Dictionary, ammo: Vector2i, delta: float) -> Vector3:
	_update_crouch(false)
	if _peek_travel_left > 0.0:
		_peek_travel_left -= delta
		if global_position.distance_squared_to(_peek_goal) > 0.1:
			_face(_cover_threat - global_position, delta)
			return _follow_path(_peek_goal)
		_peek_travel_left = 0.0
	_peek_left -= delta
	if target and _peek_left > 0.0:
		_fight(target, profile, modifiers, ammo, delta, false)
		if _shots_since_reposition >= 2 or gun.ammo_counts().x == 0:
			_peek_left = 0.0
	if _peek_left > 0.0:
		return Vector3.ZERO

	_peeked_from_cover = true
	_cover_goal = _return_to_cover
	_cover_travel_left = COVER_TRAVEL_TIME
	_cover_hold_left = 0.65
	_return_to_cover = Vector3.INF
	# Reassess after a peek instead of repeating the same angle indefinitely.
	_cover_cooldown = maxf(_cover_cooldown, 1.5)
	return _move_to_cover(delta)


func _move_to_cover(delta: float) -> Vector3:
	_update_crouch(false)
	_cover_travel_left -= delta
	if _cover_travel_left <= 0.0:
		_cover_goal = Vector3.INF
		return Vector3.ZERO
	var wish := _follow_path(_cover_goal)
	if _navigation.is_navigation_finished():
		_cover_goal = Vector3.INF
		return Vector3.ZERO
	_face(wish, delta)
	return wish


func _find_cover(threat: Vector3, approach: bool) -> Vector3:
	if not _navigation_ready():
		return Vector3.INF
	var navigation_map := _navigation.get_navigation_map()
	var space := get_world_3d().direct_space_state
	var query := _cover_query(threat)
	if _cover_blocks_shot(space, query, global_position):
		return global_position
	var away := _flat_direction(global_position - threat)
	if away.is_zero_approx():
		away = global_basis.z
	var threat_floor := Vector2(threat.x, threat.z)
	var distance := Vector2(global_position.x, global_position.z).distance_to(threat_floor)
	var safe_distance := maxf(0.7, distance - (4.0 if approach else 1.5))
	var best := Vector3.INF
	var best_length := COVER_REACH
	for radius in [2.0, 4.0, 6.0]:
		for index in COVER_DIRECTIONS:
			var sample := global_position + away.rotated(Vector3.UP, TAU * index / COVER_DIRECTIONS) * float(radius)
			var point := NavigationServer3D.map_get_closest_point(navigation_map, sample)
			if Vector2(point.x - sample.x, point.z - sample.z).length_squared() > 0.5 or point.distance_squared_to(global_position) >= best_length * best_length:
				continue
			var floor_point := Vector3(point.x, global_position.y, point.z)
			if not _cover_blocks_shot(space, query, floor_point):
				continue
			var path := NavigationServer3D.map_get_path(navigation_map, global_position, point, true)
			if path.is_empty() or path[-1].distance_squared_to(point) > 0.25:
				continue
			var length := _cover_path_length(path, threat_floor, safe_distance)
			if length < best_length:
				best = point
				best_length = length
	return best


func _cover_path_length(path: PackedVector3Array, threat: Vector2, safe_distance: float) -> float:
	var length := 0.0
	for step in range(1, path.size()):
		var from := Vector2(path[step - 1].x, path[step - 1].z)
		var to := Vector2(path[step].x, path[step].z)
		var closest := Geometry2D.get_closest_point_to_segment(threat, from, to)
		if closest.distance_squared_to(threat) < safe_distance * safe_distance:
			return INF
		length += from.distance_to(to)
	return length


func _cover_query(threat: Vector3) -> PhysicsRayQueryParameters3D:
	var query := PhysicsRayQueryParameters3D.new()
	query.from = threat
	query.collision_mask = Balance.WORLD_MASK
	return query


func _cover_blocks_shot(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D, point: Vector3) -> bool:
	query.to = point + Vector3.UP * (CROUCH_HEIGHT * 0.8)
	return not space.intersect_ray(query).is_empty()


func _visible_target(reach: float, players_only: bool = false) -> Node3D:
	var best: Node3D
	var best_score := INF
	var candidates := get_tree().get_nodes_in_group("player")
	if not players_only:
		candidates.append_array(get_tree().get_nodes_in_group("bot"))
	for enemy in candidates:
		if enemy == self or not enemy.control_enabled or enemy.health <= 0 or get_parent().same_team(score_id(), enemy.score_id()):
			continue
		var distance: float = global_position.distance_squared_to(enemy.global_position)
		if distance >= reach * reach:
			continue
		var direction := _flat_direction(enemy.global_position - global_position)
		if distance > 25.0 and direction.dot(-global_basis.z) < -0.20 and enemy != _target:
			continue
		if _has_sight(enemy):
			var score := distance * (0.72 if enemy == _target else 1.0)
			if score >= best_score:
				continue
			best = enemy
			best_score = score
	return best


func _audible_enemy(hearing_range: float) -> Node3D:
	var closest: Node3D
	var best_distance := hearing_range * hearing_range
	for enemy in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("bot"):
		if enemy == self or not enemy.control_enabled or enemy.health <= 0 or get_parent().same_team(score_id(), enemy.score_id()):
			continue
		var distance := global_position.distance_squared_to(enemy.global_position)
		if distance >= best_distance:
			continue
		var motion: Vector3 = enemy.velocity
		if Vector2(motion.x, motion.z).length_squared() < 0.4:
			continue
		closest = enemy
		best_distance = distance
	return closest


func _has_sight(enemy: Node3D) -> bool:
	_sight_ray.from = _camera.global_position
	_sight_ray.to = enemy.aim_center()
	if get_parent().get_node("Grenades").obscures(_sight_ray.from, _sight_ray.to):
		return false
	var hit := get_world_3d().direct_space_state.intersect_ray(_sight_ray)
	return hit.is_empty() or hit.collider == enemy


func _wander() -> Vector3:
	if not _navigation_ready():
		return Vector3.ZERO
	if _loot_target.is_finite():
		var loot_direction := _follow_path(_loot_target)
		if not _navigation.is_navigation_finished():
			return loot_direction
		_loot_target = Vector3.INF
	if patrol_route.is_empty():
		return Vector3.ZERO
	for _index in patrol_route.size():
		var target: Vector3 = patrol_route[_waypoint]
		var direction := _follow_path(target)
		if not _navigation.is_navigation_finished() and global_position.distance_squared_to(target) > 1.5:
			return direction
		_waypoint = posmod(_waypoint + _patrol_direction, patrol_route.size())
	_start_recovery(-global_basis.z)
	return Vector3.ZERO


func _follow_path(target: Vector3) -> Vector3:
	if not target.is_finite() or not _navigation_ready():
		return Vector3.ZERO
	if not _path_target.is_finite() or _path_target.distance_squared_to(target) > 0.36:
		_path_target = target
		_navigation.target_position = target
	var next := _navigation.get_next_path_position()
	if _navigation.is_navigation_finished():
		return Vector3.ZERO
	# A projected path can start well above a bot at the bottom of a ditch.
	var direction := _flat_direction(next - global_position)
	if direction.is_zero_approx() and absf(next.y - global_position.y) > _navigation.path_desired_distance:
		var path := _navigation.get_current_navigation_path()
		var index := _navigation.get_current_navigation_path_index()
		if index + 1 < path.size():
			next = path[index + 1]
			direction = _flat_direction(next - global_position)
	var fixtures := get_parent().get_node_or_null("Map/VillageFixtures")
	if fixtures:
		fixtures.open_door_on_path(global_position, next)
	return direction


func _flat_direction(offset: Vector3) -> Vector3:
	return Vector3(offset.x, 0, offset.z).normalized()


func _face(direction: Vector3, delta: float) -> void:
	if direction.x * direction.x + direction.z * direction.z > 0.001:
		rotation.y = rotate_toward(rotation.y, atan2(-direction.x, -direction.z), 9.0 * delta)


func _difficulty_index() -> int:
	return clampi(difficulty, 0, DIFFICULTY.size() - 1)


func _difficulty_modifiers() -> Dictionary:
	return DIFFICULTY[_difficulty_index()]
