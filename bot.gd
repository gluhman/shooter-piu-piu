extends "res://player.gd"

const BOT_SPEED := 3.3
const DIFFICULTY := [
	{"speed": 0.85, "shot_delay": 1.35, "spread": 2.4},
	{"speed": 1.0, "shot_delay": 1.0, "spread": 1.15},
	{"speed": 1.15, "shot_delay": 0.72, "spread": 0.50},
]
const FIRE := {
	"launcher": {"range": 28.0, "preferred": 13.0, "delay": 2.4, "damage": 65, "minimum": 7.0},
	"m249": {"range": 38.0, "preferred": 13.0, "delay": 0.37, "damage": 8},
	"m14": {"range": 41.0, "preferred": 15.0, "delay": 0.73, "damage": 16},
	"m1": {"range": 45.0, "preferred": 17.0, "delay": 1.04, "damage": 24},
	"deagle": {"range": 28.0, "preferred": 10.0, "delay": 0.95, "damage": 14},
	"shotgun": {"range": 17.0, "preferred": 6.0, "delay": 1.0, "damage": 5},
	"ak47": {"range": 34.0, "preferred": 12.0, "delay": 0.47, "damage": 10},
}

var combatant_id := 0
var difficulty := 1
var patrol_route: Array
var _spawn_waypoint := 0
var _waypoint := 0
var _shoot_wait := 0.0
var _loot_scan := 0.0
var _loot_target := Vector3.INF
var _blocked_time := 0.0
var _detour := Vector3.ZERO

@onready var _loot := get_parent().get_node("Loot")


func _ready() -> void:
	super._ready()
	remove_from_group("player")
	add_to_group("bot")
	_grenades.clear()
	for index in patrol_route.size():
		if spawn_position.distance_squared_to(patrol_route[index]) < spawn_position.distance_squared_to(patrol_route[_spawn_waypoint]):
			_spawn_waypoint = index
	_reset_behavior()


func _is_local() -> bool:
	return false


func score_id() -> int:
	return combatant_id


func shot_motion() -> Vector3:
	return velocity if _server_rules() else super.shot_motion()


func _respawn_delay() -> float:
	return 3.5


func _next_respawn_weapon() -> String:
	return get_parent().random_weapon(weapon_id)


func _apply_respawn(id: String) -> void:
	super._apply_respawn(id)
	_reset_behavior()


func _reset_behavior() -> void:
	_waypoint = _spawn_waypoint
	_shoot_wait = randf_range(0.55, 0.95) * float(DIFFICULTY[difficulty].shot_delay)
	_loot_scan = 0.0
	_loot_target = Vector3.INF
	_blocked_time = 0.0
	_detour = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if not _server_rules():
		super._physics_process(delta)
		return
	if _dead or not control_enabled:
		return

	_loot_scan -= delta
	if _loot_scan <= 0.0:
		_loot_scan = randf_range(0.25, 0.45)
		_loot_target = _loot.seek_bot_loot(self)
	var profile: Dictionary = FIRE[weapon_id]
	var modifiers: Dictionary = DIFFICULTY[difficulty]
	var ammo: Vector2i = gun.ammo_counts()
	var target := _visible_target(float(profile.range)) if ammo.x + ammo.y > 0 and flash_left < 0.2 else null
	aiming = target != null
	_shoot_wait = maxf(0.0, _shoot_wait - delta)
	var wish := Vector3.ZERO
	if target:
		var to_target: Vector3 = target.aim_center() - _camera.global_position
		_face(to_target, delta)
		_camera.rotation.x = clampf(asin(to_target.normalized().y), -0.78, 0.78)
		var distance: float = global_position.distance_to(target.global_position)
		if distance > float(profile.preferred) + 1.0:
			wish = _flat_direction(to_target)
		elif distance < float(profile.preferred) - 1.6:
			wish = -_flat_direction(to_target)
		if _shoot_wait <= 0.0 and distance >= float(profile.get("minimum", 0.0)) and (-global_basis.z).dot(_flat_direction(to_target)) > 0.985:
			var aim_at: Vector3 = target.aim_center()
			if weapon_id == "launcher":
				aim_at.y += 4.9 * pow(distance / 29.0, 2.0)
			if gun.fire_bot(aim_at, float(modifiers.spread), int(profile.damage)):
				_shoot_wait = float(profile.delay) * float(modifiers.shot_delay) * randf_range(0.88, 1.14)
	else:
		_camera.rotation.x = move_toward(_camera.rotation.x, 0.0, delta * 2.5)
		wish = _wander()
		_face(wish, delta)

	if _blocked_time > 0.0:
		_blocked_time -= delta
		if wish != Vector3.ZERO:
			wish = _detour
	velocity.x = wish.x * BOT_SPEED * float(modifiers.speed)
	velocity.z = wish.z * BOT_SPEED * float(modifiers.speed)
	velocity.y = 0.0 if is_on_floor() else velocity.y + get_gravity().y * delta
	var before := global_position
	move_and_slide()
	if wish != Vector3.ZERO and global_position.distance_squared_to(before) < 0.00009 and _blocked_time <= 0.0:
		_detour = wish.rotated(Vector3.UP, (PI / 2.0) * (-1.0 if randf() < 0.5 else 1.0))
		_blocked_time = 0.65
	_pose.grounded = is_on_floor()


func _visible_target(reach: float) -> Node:
	var best: Node
	var best_distance := reach * reach
	for player in get_tree().get_nodes_in_group("player"):
		if not player.control_enabled or player.health <= 0:
			continue
		var distance: float = global_position.distance_squared_to(player.global_position)
		if distance >= best_distance or get_parent().get_node("Grenades").obscures(_camera.global_position, player.aim_center()):
			continue
		var query := PhysicsRayQueryParameters3D.create(_camera.global_position, player.aim_center())
		query.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.collider == player:
			best = player
			best_distance = distance
	return best


func _wander() -> Vector3:
	if _loot_target.is_finite():
		return _flat_direction(_loot_target - global_position)
	var target: Vector3 = patrol_route[_waypoint]
	if Vector2(target.x - position.x, target.z - position.z).length_squared() < 1.5:
		_waypoint = (_waypoint + 1) % patrol_route.size()
		target = patrol_route[_waypoint]
	return _flat_direction(target - global_position)


func _flat_direction(offset: Vector3) -> Vector3:
	return Vector3(offset.x, 0, offset.z).normalized()


func _face(direction: Vector3, delta: float) -> void:
	if direction.x * direction.x + direction.z * direction.z > 0.001:
		rotation.y = rotate_toward(rotation.y, atan2(-direction.x, -direction.z), 9.0 * delta)
