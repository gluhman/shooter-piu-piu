extends "res://game/actors/player.gd"

const BOT_SPEED := 3.3
const BOT_ACCELERATION := 22.0
const SEARCH_TIME := 10.0
const COVER_REACH := 9.0
const COVER_TRAVEL_TIME := 3.5
const COVER_ARRIVAL := 0.4
const COVER_DIRECTIONS := 8
const DIFFICULTY := [
	{"speed": 0.85, "shot_delay": 1.35, "spread": 2.4},
	{"speed": 1.0, "shot_delay": 1.0, "spread": 1.15},
	{"speed": 1.15, "shot_delay": 0.72, "spread": 0.50},
]
const FIRE := {
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
var _vision_wait := 0.0
var _target: Node3D
var _strafe_side := 1.0
var _strafe_left := 0.0
var _flank_point := Vector3.INF
var _shoot_wait := 0.0
var _loot_scan := 0.0
var _loot_target := Vector3.INF
var _blocked_time := 0.0
var _detour := Vector3.ZERO
var _navigation: NavigationAgent3D
var _path_target := Vector3.INF
var _last_seen := Vector3.INF
var _search_left := 0.0
var _incoming_fire := Vector3.INF
var _cover_goal := Vector3.INF
var _cover_threat := Vector3.INF
var _cover_travel_left := 0.0
var _cover_hold_left := 0.0
var _holding_cover := false
var _cover_cooldown := 0.0
var _sight_ray := PhysicsRayQueryParameters3D.new()

@onready var _loot := get_parent().get_node("Loot")


func _ready() -> void:
	super._ready()
	remove_from_group("player")
	add_to_group("bot")
	_grenades.clear()
	if _server_rules():
		_sight_ray.collision_mask = Balance.WORLD_AND_CAPSULES
		_sight_ray.exclude = [get_rid()]
		_navigation = NavigationAgent3D.new()
		_navigation.path_desired_distance = 0.25
		_navigation.target_desired_distance = 0.25
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
		if _holding_cover:
			_cover_goal = Vector3.INF
			_holding_cover = false
		_cover_cooldown = minf(_cover_cooldown, 0.3)


func _respawn_delay() -> float:
	return super._respawn_delay()


func _next_respawn_weapon() -> String:
	return get_parent().random_weapon(weapon_id)


func _apply_respawn(id: String, at: Vector3, revision: int) -> void:
	super._apply_respawn(id, at, revision)
	_reset_behavior()


func _reset_behavior() -> void:
	_waypoint = 0
	for index in patrol_route.size():
		if global_position.distance_squared_to(patrol_route[index]) < global_position.distance_squared_to(patrol_route[_waypoint]):
			_waypoint = index
	_shoot_wait = randf_range(0.55, 0.95) * float(DIFFICULTY[difficulty].shot_delay)
	_target = null
	_vision_wait = randf_range(0.0, 0.14)
	_strafe_side = -1.0 if randf() < 0.5 else 1.0
	_strafe_left = randf_range(0.5, 1.4)
	_flank_point = Vector3.INF
	_loot_scan = 0.0
	_loot_target = Vector3.INF
	_blocked_time = 0.0
	_detour = Vector3.ZERO
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


func _physics_process(delta: float) -> void:
	if not _server_rules():
		super._physics_process(delta)
		return
	if _dead or not control_enabled or get_parent().is_loading() or get_parent().round_finished():
		return

	_loot_scan -= delta
	if _loot_scan <= 0.0:
		_loot_scan = randf_range(0.25, 0.45)
		_loot_target = _loot.seek_bot_loot(self)
	var profile: Dictionary = FIRE[weapon_id]
	var modifiers: Dictionary = DIFFICULTY[difficulty]
	var ammo: Vector2i = gun.ammo_counts()
	_vision_wait -= delta
	if _vision_wait <= 0.0 and flash_left < 0.2:
		_vision_wait = randf_range(0.12, 0.19)
		_target = _visible_target(float(profile.range))
	var target := _target if flash_left < 0.2 and is_instance_valid(_target) and _target.control_enabled and _target.health > 0 else null
	_shoot_wait = maxf(0.0, _shoot_wait - delta)
	_cover_cooldown = maxf(0.0, _cover_cooldown - delta)
	if target:
		_last_seen = target.global_position
		_search_left = SEARCH_TIME
		_flank_point = Vector3.INF
	else:
		_search_left = maxf(0.0, _search_left - delta)
	_try_take_cover(target, profile, ammo)

	var wish := Vector3.ZERO
	var speed := BOT_SPEED * float(modifiers.speed)
	if _cover_goal.is_finite():
		wish = _use_cover(delta, ammo)
		speed *= 1.15
	else:
		_update_crouch(false)
		if ammo.x == 0 and ammo.y > 0:
			gun.reload_bot()
		if target:
			wish = _fight(target, profile, modifiers, ammo, delta)
		else:
			aiming = false
			_camera.rotation.x = move_toward(_camera.rotation.x, 0.0, delta * 2.5)
			wish = _wander() if ammo == Vector2i.ZERO else _search(float(profile.preferred))
			_face(wish, delta)
	if crouched:
		speed *= 0.65

	if _blocked_time > 0.0:
		_blocked_time -= delta
		if wish != Vector3.ZERO and not target:
			wish = _detour
	speed *= armor_movement_scale()
	if concussion_left > 0.0:
		speed *= float(Balance.GRENADES.concussion.movement_speed_multiplier_during_effect)
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(Vector2(wish.x, wish.z) * speed, BOT_ACCELERATION * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	velocity.y = 0.0 if is_on_floor() else velocity.y + -float(Balance.MOVEMENT.gravity_m_s2) * delta
	var before := global_position
	move_and_slide()
	_track_movement_audio(delta, true)
	var blocked_distance_sq := minf(0.00009, horizontal.length_squared() * delta * delta * 0.25)
	if wish != Vector3.ZERO and global_position.distance_squared_to(before) < blocked_distance_sq and _blocked_time <= 0.0:
		_detour = wish.rotated(Vector3.UP, (PI / 2.0) * (-1.0 if randf() < 0.5 else 1.0))
		_blocked_time = 0.4
		_strafe_side *= -1.0
		_path_target = Vector3.INF


func _fight(target: Node3D, profile: Dictionary, modifiers: Dictionary, ammo: Vector2i, delta: float) -> Vector3:
	aiming = true
	var to_target: Vector3 = target.aim_center() - _camera.global_position
	_face(to_target, delta)
	_camera.rotation.x = clampf(asin(to_target.normalized().y), -0.78, 0.78)
	var direction := _flat_direction(to_target)
	if ammo.x > 0 and _shoot_wait <= 0.0 and (-global_basis.z).dot(direction) > 0.985 and _has_sight(target):
		if gun.fire_bot(target.aim_center(), float(modifiers.spread)):
			var cadence := float(profile.delay) * float(modifiers.shot_delay) * randf_range(0.88, 1.14)
			_shoot_wait = maxf(float(Weapon.WEAPONS[weapon_id].cooldown), cadence)
	var distance: float = global_position.distance_to(target.global_position)
	_strafe_left -= delta
	if _strafe_left <= 0.0:
		_strafe_left = randf_range(0.65, 1.35)
		_strafe_side *= -1.0
	var side := direction.cross(Vector3.UP) * _strafe_side
	var retreat := ammo.x == 0 or distance < float(profile.preferred) * 0.78
	var back := -direction * (0.9 if retreat else 0.0)
	var wish := (side + back).normalized()
	if test_move(global_transform, wish * 0.55):
		wish = (back - side).normalized()
		if test_move(global_transform, wish * 0.55):
			return Vector3.ZERO
	return wish * (1.0 if retreat else 0.62)


func _search(preferred: float) -> Vector3:
	if _search_left <= 0.0:
		return _wander()
	if not _flank_point.is_finite():
		var toward := _flat_direction(_last_seen - global_position)
		var side := toward.cross(Vector3.UP) * _strafe_side
		var sample := _last_seen - toward * clampf(preferred * 0.75, 5.0, 10.0) + side * 5.0
		_flank_point = NavigationServer3D.map_get_closest_point(_navigation.get_navigation_map(), sample)
	var wish := _follow_path(_flank_point)
	if _navigation.is_navigation_finished():
		_search_left = 0.0
	return wish


func _try_take_cover(target: Node3D, profile: Dictionary, ammo: Vector2i) -> void:
	if _cover_goal.is_finite() or _cover_cooldown > 0.0:
		return
	var low_ammo: bool = ammo.x == 0 or (ammo.y > 0 and ammo.x <= 1 and not gun.is_reloading())
	var threat := _incoming_fire
	var approach := target != null and not threat.is_finite() and not low_ammo and float(profile.range) <= 24.0 and global_position.distance_to(target.global_position) > float(profile.preferred) + 4.0
	if not threat.is_finite() and target and (low_ammo or approach):
		threat = target.aim_center() + Vector3.UP * 0.4
	if not threat.is_finite():
		return
	_cover_cooldown = randf_range(2.5, 3.5) + (2 - difficulty)
	_incoming_fire = Vector3.INF
	_cover_goal = _find_cover(threat, approach)
	if _cover_goal.is_finite():
		_cover_threat = threat
		_cover_travel_left = COVER_TRAVEL_TIME
		_cover_hold_left = randf_range(0.65, 1.05)
		_holding_cover = false
		_blocked_time = 0.0


func _use_cover(delta: float, ammo: Vector2i) -> Vector3:
	aiming = false
	_camera.rotation.x = move_toward(_camera.rotation.x, 0.0, delta * 2.5)
	if not _holding_cover:
		var offset := _cover_goal - global_position
		if Vector2(offset.x, offset.z).length_squared() <= COVER_ARRIVAL * COVER_ARRIVAL:
			var query := _cover_query(_cover_threat)
			_holding_cover = _cover_blocks_shot(get_world_3d().direct_space_state, query, global_position)
		if not _holding_cover:
			return _move_to_cover(delta)

	_update_crouch(true)
	_face(_cover_threat - global_position, delta)
	if ammo.y > 0 and ammo.x <= 1:
		gun.reload_bot()
	_cover_hold_left -= delta
	if _cover_hold_left <= 0.0 and not gun.is_reloading():
		_cover_goal = Vector3.INF
		_holding_cover = false
		_cover_cooldown = maxf(_cover_cooldown, 1.2)
	return Vector3.ZERO


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
	var navigation_map := _navigation.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		return Vector3.INF
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
			if point.distance_squared_to(sample) > 0.5 or point.distance_squared_to(global_position) >= best_length * best_length:
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


func _visible_target(reach: float) -> Node3D:
	var best: Node3D
	var best_distance := reach * reach
	for enemy in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("bot"):
		if enemy == self or not enemy.control_enabled or enemy.health <= 0 or get_parent().same_team(score_id(), enemy.score_id()):
			continue
		var distance: float = global_position.distance_squared_to(enemy.global_position)
		if distance >= best_distance or get_parent().get_node("Grenades").obscures(_camera.global_position, enemy.aim_center()):
			continue
		var direction := _flat_direction(enemy.global_position - global_position)
		if distance > 25.0 and direction.dot(-global_basis.z) < -0.20 and enemy != _target:
			continue
		if _has_sight(enemy):
			best = enemy
			best_distance = distance
	return best


func _has_sight(enemy: Node3D) -> bool:
	_sight_ray.from = _camera.global_position
	_sight_ray.to = enemy.aim_center()
	var hit := get_world_3d().direct_space_state.intersect_ray(_sight_ray)
	return hit.is_empty() or hit.collider == enemy


func _wander() -> Vector3:
	if _loot_target.is_finite():
		return _follow_path(_loot_target)
	var target: Vector3 = patrol_route[_waypoint]
	if Vector2(target.x - position.x, target.z - position.z).length_squared() < 1.5:
		_waypoint = (_waypoint + 1) % patrol_route.size()
		target = patrol_route[_waypoint]
	return _follow_path(target)


func _follow_path(target: Vector3) -> Vector3:
	if NavigationServer3D.map_get_iteration_id(_navigation.get_navigation_map()) == 0:
		return Vector3.ZERO
	if not _path_target.is_finite() or _path_target.distance_squared_to(target) > 0.36:
		_path_target = target
		_navigation.target_position = target
	var next := _navigation.get_next_path_position()
	if _navigation.is_navigation_finished():
		return Vector3.ZERO
	return _flat_direction(next - global_position)


func _flat_direction(offset: Vector3) -> Vector3:
	return Vector3(offset.x, 0, offset.z).normalized()


func _face(direction: Vector3, delta: float) -> void:
	if direction.x * direction.x + direction.z * direction.z > 0.001:
		rotation.y = rotate_toward(rotation.y, atan2(-direction.x, -direction.z), 9.0 * delta)
