extends CharacterBody3D

const WALK_SPEED := 5.0
const SPRINT_SPEED := 7.4
const CROUCH_SPEED := 2.6
const AIM_SPEED := 3.2
const STANDING_HEIGHT := 1.7
const CROUCH_HEIGHT := 1.22
const CROUCH_DROP := STANDING_HEIGHT - CROUCH_HEIGHT
const JUMP_VELOCITY := 4.6
const MOUSE_SENS := 0.0022
const MAX_HEALTH := 100
const MAX_ARMOR := 65
const HIT_MULTIPLIERS := {"head": 2.35, "chest": 1.0, "stomach": 0.85, "arm": 0.65, "leg": 0.55}
const ARSENAL := preload("res://game/combat/arsenal_assets.gd")
const NETWORK_POSE_SIZE := 13
const REMOTE_BLEND_TIME := 0.045
const COVER_SPEED := 1.85
const COVER_PEEK_SPEED := 4.6
const COVER_PEEK_DISTANCE := 0.55
const COVER_EDGE_PROBE := 0.34
const COVER_WALL_REACH := 0.72
const COVER_LOOK_LIMIT := 1.45
const FIRST_PERSON_BODY_LAYER := 3
const OperatorPose := preload("res://game/actors/operator_pose.gd")
const Weapon := preload("res://game/combat/weapon.gd")
const MovementAudio := preload("res://game/audio/movement_audio.gd")
const MEDKIT_HEAL := 45
const MAX_MEDKITS := 2

signal health_changed(current: int, maximum: int)
signal respawned
signal inventory_changed
signal weapon_wheel_used

var control_enabled := false
var slot := 0
var health := MAX_HEALTH
var armor := 0
var flash_left := 0.0
var _grenades: Dictionary[String, int] = {}
var _throw_wait := 0.0
var _pose_sequence := 0
var _latest_pose := PackedFloat32Array()
var _pose_elapsed := 0.0
var _pose_origin := Vector3.ZERO
var _pose_yaw := 0.0
var _pose_pitch := 0.0
var _net_grounded := true
var _vest: Node3D
var _scoped := false
var weapon_id := ""
var spawn_position: Vector3
var _last_spawn_position: Vector3
var _spawn_revision := 0
var _spawn_loadout := ""
var _spawn_sidearm := ""
var _spawn_grenade := ""
var medkits := 0
var _stored: Dictionary[String, Vector2i] = {}
var _switch_pending := false

var crouched := false
var aiming := false

var _cover_normal := Vector3.ZERO
var _peek_anchor := Vector3.ZERO
var _peek_direction := 0.0
var _cover_peek := 0.0

var _crouch_blend := 0.0
var _capsule_height := STANDING_HEIGHT
var _standing_capsule: CapsuleShape3D
var _pouch_rest: Vector3

var _jump_held := false
var _recoil_pitch := 0.0
var _dead := false
var _respawn_timer: SceneTreeTimer
var _hurt_lock := 0.0
var _avatar: Node3D
var _skeleton: Skeleton3D
var _pose: OperatorPose
var _eye_rest: Vector3
var _head_pivot: Vector3
var _pouch: Marker3D
var _bar_root: Node3D
var _bar_fill: MeshInstance3D
var _bar_mat: StandardMaterial3D
var _name_label: Label3D
var _prev_pos := Vector3.ZERO
var _visual_velocity := Vector3.ZERO
var _visual_vertical := 0.0
var _operator_elapsed := 0.0
var _movement_audio: MovementAudio

@onready var _camera: Camera3D = $Camera3D
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var gun := $Camera3D/Weapon


func _ready() -> void:
	add_to_group("player")
	_standing_capsule = _collision.shape as CapsuleShape3D
	_collision.shape = _standing_capsule.duplicate()
	_prev_pos = global_position
	_last_spawn_position = spawn_position
	rotation.y = atan2(spawn_position.x, spawn_position.z)
	if _is_local():
		_camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_camera.current = false
		_build_bar()
	_build_operator()
	_movement_audio = MovementAudio.new()
	_movement_audio.name = "MovementAudio"
	_movement_audio.actor = self
	_movement_audio.use_acoustics = not _is_local()
	add_child(_movement_audio)
	_reset_support()


func _is_local() -> bool:
	if not Net.active:
		return true
	return is_multiplayer_authority()


func _server_rules() -> bool:
	return not Net.active or multiplayer.is_server()


func take_damage(amount: int, killer_id: int = 0, zone: String = "chest", vest_fraction: float = 0.0) -> void:
	if not _server_rules() or get_parent().round_finished():
		return
	if _dead or not control_enabled or amount <= 0 or _hurt_lock > 0.0:
		return
	amount = maxi(1, roundi(amount * float(HIT_MULTIPLIERS[zone])))
	if zone == "chest" and armor > 0:
		var absorbed := mini(armor, clampi(roundi(amount * vest_fraction), 0, amount - 1))
		armor -= absorbed
		amount -= absorbed
	_set_health(maxi(health - amount, 0), killer_id)


func projectile_zone(at: Vector3) -> String:
	var point := to_local(at)
	if point.y >= _capsule_height - 0.225:
		return "head"
	if point.y < _capsule_height * 0.46:
		return "leg"
	if absf(point.x) > 0.23:
		return "arm"
	return "chest" if point.y >= _capsule_height - 0.52 else "stomach"


func grant_armor() -> void:
	if _server_rules() and control_enabled and armor < MAX_ARMOR:
		armor = MAX_ARMOR
		_set_health(health, 0)


func grenade_stock(kind: String) -> int:
	return _grenades.get(kind, 0)


func carried_grenade() -> String:
	return "" if _grenades.is_empty() else _grenades.keys()[0]


func grenade_space(kind: String) -> int:
	var carried := carried_grenade()
	return ARSENAL.MAX_GRENADES - grenade_stock(kind) if carried == "" or carried == kind else 0


func drop_carried_grenades() -> void:
	_grenades.clear()


func grant_grenades(kind: String, amount: int) -> void:
	var accepted := mini(amount, grenade_space(kind))
	if _server_rules() and control_enabled and accepted > 0 and ARSENAL.GRENADE_IDS.has(kind):
		_grenades[kind] = grenade_stock(kind) + accepted
		_send_inventory()


func consume_grenade(kind: String) -> bool:
	if not _server_rules() or _throw_wait > 0.0 or grenade_stock(kind) <= 0:
		return false
	_grenades[kind] -= 1
	if _grenades[kind] == 0:
		_grenades.erase(kind)
	_throw_wait = 0.72
	_send_inventory()
	return true


func apply_flash(strength: float) -> void:
	if not _server_rules() or strength < 0.04:
		return
	flash_left = maxf(flash_left, _flash_duration(strength))
	if _is_local():
		net_flash(strength)
	elif score_id() > 1:
		net_flash.rpc_id(score_id(), strength)


@rpc("any_peer", "reliable")
func net_flash(strength: float) -> void:
	if multiplayer.get_remote_sender_id() not in [0, 1] or not _is_local():
		return
	get_parent().get_node("HUD").show_flashbang(strength, _flash_duration(strength))


func _flash_duration(strength: float) -> float:
	return 0.24 + 3.3 * pow(clampf(strength, 0.0, 1.0), 1.17)


func set_scoped_view(scoped: bool) -> void:
	if _is_local():
		_scoped = scoped
		set_first_person_body_visible(not scoped)


func restore_health(amount: int) -> void:
	if _server_rules() and control_enabled:
		_set_health(mini(MAX_HEALTH, health + amount), 0)


func _set_health(value: int, killer_id: int) -> void:
	health = value
	for peer in get_parent().match_peers():
		net_set_health.rpc_id(peer, health, armor, killer_id)
	_commit(killer_id)


func equip(id: String) -> void:
	if not get_parent().allows_weapon(id):
		return
	_spawn_loadout = id
	_apply_equip(id)
	_send_equipment(id)


func choose_loadout(primary: String, sidearm: String, grenade: String) -> void:
	if weapon_id != "" or _dead or get_parent().round_finished() or not _valid_loadout(primary, sidearm, grenade):
		return
	if _server_rules():
		_apply_loadout(primary, sidearm, grenade)
		_send_equipment(primary)
	else:
		net_choose_loadout.rpc_id(1, primary, sidearm, grenade)


func _valid_loadout(primary: String, sidearm: String, grenade: String) -> bool:
	return get_parent().allows_weapon(primary) and Weapon.inventory_slot(primary) == "primary" \
		and get_parent().allows_weapon(sidearm) and sidearm in Weapon.SIDEARMS and grenade in ARSENAL.GRENADE_IDS


func _apply_loadout(primary: String, sidearm: String, grenade: String) -> void:
	_spawn_loadout = primary
	_spawn_sidearm = sidearm
	_spawn_grenade = grenade
	_restore_starting_supplies()
	_apply_equip(primary)
	inventory_changed.emit()


func _restore_starting_supplies() -> void:
	if _spawn_sidearm != "":
		var stats: Dictionary = Weapon.WEAPONS[_spawn_sidearm]
		_stored[_spawn_sidearm] = Vector2i(stats.mag, stats.reserve)
	if _spawn_grenade != "":
		_grenades[_spawn_grenade] = ARSENAL.MAX_GRENADES


func grant_weapon(id: String, magazine: int = -1, reserve: int = -1) -> void:
	if not _server_rules() or not get_parent().allows_weapon(id):
		return
	if score_id() <= 0:
		if id == weapon_id and magazine >= 0:
			grant_ammo(id, magazine + maxi(reserve, 0))
		else:
			_set_active_weapon(id, magazine, reserve, false)
		return
	var stats: Dictionary = Weapon.WEAPONS[id]
	var loaded := int(stats.mag) if magazine < 0 else magazine
	var loose := int(stats.reserve) if reserve < 0 else reserve
	if owns_weapon(id):
		grant_ammo(id, loaded + loose)
		return
	var previous := weapon_in_slot(Weapon.inventory_slot(id))
	if previous != "" and previous == weapon_id:
		_set_active_weapon(id, loaded, loose, true)
	else:
		_stored.erase(previous)
		_stored[id] = Vector2i(loaded, mini(ammo_capacity(id), loose))
	_send_inventory()


func owns_weapon(id: String) -> bool:
	return id != "" and (weapon_id == id or stock_for(id).x >= 0)


func weapon_in_slot(slot: String) -> String:
	if slot == "":
		return ""
	if slot == "knife":
		return "" if is_in_group("bot") else "knife"
	if weapon_id != "" and Weapon.inventory_slot(weapon_id) == slot:
		return weapon_id
	for id: String in _stored:
		if Weapon.inventory_slot(id) == slot:
			return id
	return ""


func stock_for(id: String) -> Vector2i:
	if id == "knife" and not is_in_group("bot"):
		return Vector2i.ZERO
	return gun.ammo_counts() if id == weapon_id else _stored.get(id, Vector2i(-1, 0))


func ammo_reward_weapon() -> String:
	return weapon_in_slot("primary") if weapon_id == "knife" else weapon_id


func ammo_capacity(id: String) -> int:
	var base := int(Weapon.WEAPONS[id].reserve)
	return base * 3 if score_id() > 0 else base


func ammo_space(id: String) -> int:
	return maxi(0, ammo_capacity(id) - stock_for(id).y) if id != "knife" and owns_weapon(id) else 0


func grant_ammo(id: String, amount: int) -> void:
	if not _server_rules() or not owns_weapon(id) or not get_parent().allows_weapon(id):
		return
	if id == weapon_id:
		var added: int = gun.add_reserve(amount)
		var peer := get_multiplayer_authority()
		if added > 0 and get_parent().match_peers().has(peer):
			net_loot_ammo.rpc_id(peer, id, added)
	elif score_id() > 0:
		var stock := stock_for(id)
		stock.y += clampi(amount, 0, ammo_space(id))
		_stored[id] = stock
		_send_inventory()


func grant_medkits(amount: int) -> void:
	if not _server_rules():
		return
	if score_id() <= 0:
		restore_health(MEDKIT_HEAL)
		return
	medkits = mini(medkits + amount, MAX_MEDKITS)
	_send_inventory()


func medkit_space() -> int:
	if is_in_group("bot"):
		return int(health < MAX_HEALTH)
	return MAX_MEDKITS - medkits


func inventory_stock() -> Dictionary[String, Vector2i]:
	var stock := _stored.duplicate()
	if weapon_id != "" and weapon_id != "knife":
		stock[weapon_id] = gun.ammo_counts()
	return stock


func select_weapon(id: String) -> void:
	if not control_enabled or id == weapon_id or not owns_weapon(id) or _switch_pending:
		return
	if _server_rules():
		_switch_weapon(id)
	else:
		_switch_pending = true
		net_switch_weapon.rpc_id(1, id)


func available_weapon_ids() -> Array[String]:
	var ids: Array[String] = []
	for slot: String in GameSettings.WEAPON_SLOTS:
		var id := weapon_in_slot(slot)
		if id != "":
			ids.append(id)
	return ids


func _cycle_weapon(step: int) -> void:
	var ids := available_weapon_ids()
	var current := ids.find(weapon_id)
	if current >= 0:
		select_weapon(ids[posmod(current + step, ids.size())])
		weapon_wheel_used.emit()


func use_medkit() -> void:
	if not control_enabled or medkits <= 0 or health >= MAX_HEALTH:
		return
	if _server_rules():
		_consume_medkit()
	else:
		net_use_medkit.rpc_id(1)


func weapon_switch_pending() -> bool:
	return _switch_pending


func _consume_medkit() -> void:
	if control_enabled and medkits > 0 and health < MAX_HEALTH:
		medkits -= 1
		restore_health(MEDKIT_HEAL)
		_send_inventory()


func _switch_weapon(id: String) -> void:
	var stock := stock_for(id)
	if not control_enabled or id == weapon_id or stock.x < 0:
		_send_inventory()
		return
	_stored.erase(id)
	if weapon_id != "knife":
		_stored[weapon_id] = gun.ammo_counts()
	_set_active_weapon(id, stock.x, stock.y, true)
	_send_inventory()


func _set_active_weapon(id: String, magazine: int, reserve: int, switching: bool) -> void:
	_apply_equip(id, magazine, reserve, switching)
	for peer in get_parent().match_peers():
		net_active_weapon.rpc_id(peer, id, magazine, reserve, switching, _spawn_loadout)


func _send_inventory() -> void:
	if _is_local():
		inventory_changed.emit()
	else:
		var peer := get_multiplayer_authority()
		if score_id() > 0 and get_parent().match_peers().has(peer):
			net_inventory.rpc_id(peer, _stored, medkits, _grenades)


func _is_owner_request(sender: int) -> bool:
	return multiplayer.is_server() and sender == get_multiplayer_authority() and get_parent().match_peers().has(sender)


func score_id() -> int:
	return get_multiplayer_authority()


func aim_center() -> Vector3:
	return global_position + Vector3.UP * (_capsule_height * 0.62)


func _send_equipment(id: String) -> void:
	for peer in get_parent().match_peers():
		if peer != get_multiplayer_authority():
			net_equip.rpc_id(peer, id, _spawn_loadout)


func send_status_to(peer: int) -> void:
	net_spawn_revision.rpc_id(peer, _spawn_revision)
	if peer != get_multiplayer_authority():
		if weapon_id != "":
			net_equip.rpc_id(peer, weapon_id, _spawn_loadout)
		net_set_health.rpc_id(peer, health, armor, 0)


func network_pose() -> PackedFloat32Array:
	if not _latest_pose.is_empty() and not _is_local() and not is_in_group("bot"):
		return _latest_pose
	_pose_sequence += 1
	var grounded := is_on_floor() if _is_local() or (_server_rules() and is_in_group("bot")) else _net_grounded
	return PackedFloat32Array([
		position.x, position.y, position.z, rotation.y, _camera.rotation.x, float(crouched), float(aiming),
		_cover_normal.x, _cover_normal.z, _cover_peek, float(grounded), float(_spawn_revision), float(_pose_sequence),
	])


func apply_network_pose(pose: PackedFloat32Array) -> void:
	if pose.size() != NETWORK_POSE_SIZE or pose[11] != float(_spawn_revision):
		return
	if not _latest_pose.is_empty() and pose[12] <= _latest_pose[12]:
		return
	var target := Vector3(pose[0], pose[1], pose[2])
	var snap := _latest_pose.is_empty() or position.distance_squared_to(target) > 25.0
	_latest_pose = pose
	_pose_origin = position
	_pose_yaw = rotation.y
	_pose_pitch = _camera.rotation.x
	_pose_elapsed = REMOTE_BLEND_TIME if snap else 0.0
	if snap:
		_interpolate_network_pose(0.0)
	crouched = pose[5] > 0.0
	aiming = pose[6] > 0.0
	_cover_normal = Vector3(clampf(pose[7], -1.0, 1.0), 0.0, clampf(pose[8], -1.0, 1.0)).normalized()
	_cover_peek = clampf(pose[9], -1.0, 1.0) if in_cover() else 0.0
	_net_grounded = pose[10] > 0.0
	_update_capsule()
	_update_view_pose()


func _interpolate_network_pose(delta: float) -> void:
	if _latest_pose.is_empty() or _dead or (delta > 0.0 and _pose_elapsed >= REMOTE_BLEND_TIME):
		return
	_pose_elapsed = minf(REMOTE_BLEND_TIME, _pose_elapsed + delta)
	var blend := _pose_elapsed / REMOTE_BLEND_TIME
	position = _pose_origin.lerp(Vector3(_latest_pose[0], _latest_pose[1], _latest_pose[2]), blend)
	rotation.y = lerp_angle(_pose_yaw, _latest_pose[3], blend)
	_camera.rotation.x = lerpf(_pose_pitch, _latest_pose[4], blend)


func current_shot_transform(rendered: Transform3D) -> Transform3D:
	if _latest_pose.is_empty() or _is_local() or is_in_group("bot"):
		return rendered
	var yaw_adjustment := Basis(Vector3.UP, angle_difference(rotation.y, _latest_pose[3]))
	var pitch_adjustment := Basis(Vector3.RIGHT, _latest_pose[4] - _camera.rotation.x)
	var camera_at := _camera.global_position
	var offset := camera_at - global_position
	var target := Vector3(_latest_pose[0], _latest_pose[1], _latest_pose[2])
	var camera_basis := _camera.global_basis.orthonormalized()
	var aim_rotation := yaw_adjustment * camera_basis * pitch_adjustment * camera_basis.inverse()
	return Transform3D(aim_rotation * rendered.basis,
		target + yaw_adjustment * offset + aim_rotation * (rendered.origin - camera_at))


func in_cover() -> bool:
	return _cover_normal != Vector3.ZERO


func can_fire_from_cover() -> bool:
	return not in_cover() or absf(_cover_peek) >= 0.78


func cover_tuck() -> float:
	return 1.0 - smoothstep(0.08, 0.82, absf(_cover_peek)) if in_cover() else 0.0


func set_weapon_grips(right: Marker3D, left: Marker3D, knife: bool) -> void:
	_pose.right_wrist = right
	_pose.left_wrist = left
	_pose.knife_grip = knife


func set_support_grip(reload_blend: float) -> void:
	_pose.support_grip = reload_blend


func weapon_reach_correction(two_handed: bool) -> Vector3:
	return _pose.weapon_reach_correction(two_handed)


func weapon_reach_along(axis: Vector3) -> float:
	return _pose.weapon_reach_along(axis)


func clamp_support_hand(point: Vector3) -> Vector3:
	return _pose.clamp_support_hand(point)


func reload_pouch_position() -> Vector3:
	return _pouch.global_position


func shot_motion() -> Vector3:
	if _is_local():
		return velocity
	return (_visual_velocity + Vector3.UP * _visual_vertical).limit_length(SPRINT_SPEED + JUMP_VELOCITY)


func visual_speed() -> float:
	return _visual_velocity.length()


@rpc("any_peer", "reliable")
func net_set_health(value: int, vest: int, killer_id: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	health = value
	armor = vest
	_commit(killer_id)


@rpc("any_peer", "reliable")
func net_equip(id: String, loadout: String = "") -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_spawn_loadout = loadout
		_apply_equip(id)


@rpc("any_peer", "reliable")
func net_choose_loadout(primary: String, sidearm: String, grenade: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		if not _is_owner_request(sender) or weapon_id != "" or _dead or get_parent().round_finished() or not _valid_loadout(primary, sidearm, grenade):
			return
		_apply_loadout(primary, sidearm, grenade)
		_send_equipment(primary)
		net_choose_loadout.rpc_id(sender, primary, sidearm, grenade)
	elif sender == 1 and _is_local():
		_apply_loadout(primary, sidearm, grenade)


@rpc("any_peer", "reliable")
func net_respawn(id: String, at: Vector3, revision: int) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_apply_respawn(id, at, revision)


@rpc("any_peer", "reliable")
func net_spawn_revision(revision: int) -> void:
	if multiplayer.get_remote_sender_id() == 1 and revision != _spawn_revision:
		_spawn_revision = revision
		_latest_pose = PackedFloat32Array()


@rpc("any_peer", "reliable")
func net_active_weapon(id: String, magazine: int, reserve: int, switching: bool, loadout: String) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_spawn_loadout = loadout
		_apply_equip(id, magazine, reserve, switching)


@rpc("any_peer", "reliable")
func net_switch_weapon(id: String) -> void:
	if not get_parent().round_finished() and _is_owner_request(multiplayer.get_remote_sender_id()):
		_switch_weapon(id)


@rpc("any_peer", "reliable")
func net_use_medkit() -> void:
	if not get_parent().round_finished() and _is_owner_request(multiplayer.get_remote_sender_id()):
		_consume_medkit()


@rpc("any_peer", "reliable")
func net_inventory(stock: Dictionary[String, Vector2i], kits: int, grenades: Dictionary[String, int]) -> void:
	if multiplayer.get_remote_sender_id() == 1 and _is_local():
		_stored = stock
		medkits = kits
		_grenades = grenades
		_switch_pending = false
		inventory_changed.emit()


@rpc("any_peer", "reliable")
func net_loot_ammo(id: String, amount: int) -> void:
	if multiplayer.get_remote_sender_id() == 1 and weapon_id == id:
		gun.add_reserve(amount)


func _apply_equip(id: String, magazine: int = -1, reserve: int = -1, switching: bool = false) -> void:
	if id != "knife" and not get_parent().allows_weapon(id):
		return
	weapon_id = id
	control_enabled = true
	_switch_pending = false
	gun.equip(id, magazine, reserve, switching)
	if _is_local() and not get_parent().input_blocked():
		GameSettings.capture_gameplay_mouse()


func _commit(killer_id: int) -> void:
	_vest.visible = armor > 0
	health_changed.emit(health, MAX_HEALTH)
	_refresh_bar()
	if health > 0 or _dead:
		return
	_dead = true
	_movement_audio.reset()
	_leave_cover()
	aiming = false
	control_enabled = false
	gun.cancel_reload()
	gun.hide()
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	if _avatar:
		_avatar.visible = false
	if _bar_root:
		_bar_root.visible = false
	if _server_rules():
		get_parent().get_node("Loot").drop_combatant(self)
		get_parent().announce(killer_id, score_id())
		_respawn_timer = get_tree().create_timer(_respawn_delay(), false, true)
		_respawn_timer.timeout.connect(_request_respawn)
	_clear_inventory()
	inventory_changed.emit()


func _clear_inventory() -> void:
	_stored.clear()
	medkits = 0
	_grenades.clear()
	_switch_pending = false


func _reset_support() -> void:
	armor = 0
	_vest.hide()
	flash_left = 0.0
	_throw_wait = 0.0


func _request_respawn() -> void:
	_respawn_timer = null
	if get_parent().round_finished():
		return
	var id := _next_respawn_weapon()
	var at: Vector3 = get_parent().choose_respawn(self, _last_spawn_position)
	var revision := _spawn_revision + 1
	for peer in get_parent().match_peers():
		net_respawn.rpc_id(peer, id, at, revision)
	_apply_respawn(id, at, revision)


func _next_respawn_weapon() -> String:
	return _spawn_loadout


func _respawn_delay() -> float:
	return 2.2


func restart_round() -> void:
	_cancel_respawn()
	_apply_respawn(_spawn_loadout, spawn_position, _spawn_revision + 1)
	_recoil_pitch = 0.0
	_jump_held = Input.is_action_pressed(&"jump")


func stop_round() -> void:
	_cancel_respawn()
	_movement_audio.reset()
	gun.stop_round()
	aiming = false
	velocity = Vector3.ZERO


func _cancel_respawn() -> void:
	if _respawn_timer and _respawn_timer.timeout.is_connected(_request_respawn):
		_respawn_timer.timeout.disconnect(_request_respawn)
	_respawn_timer = null


func _apply_respawn(id: String, at: Vector3, revision: int) -> void:
	_clear_inventory()
	_reset_support()
	_restore_starting_supplies()
	_leave_cover()
	_spawn_revision = revision
	_latest_pose = PackedFloat32Array()
	_last_spawn_position = at
	global_position = at
	_movement_audio.reset()
	velocity = Vector3.ZERO
	rotation.y = atan2(at.x, at.z)
	_camera.rotation.x = 0.0
	health = MAX_HEALTH
	_dead = false
	collision_layer = 1
	collision_mask = 1
	crouched = false
	aiming = false
	_crouch_blend = 0.0
	_update_capsule()
	_hurt_lock = 1.0
	if id != "":
		_apply_equip(id)
	control_enabled = id != ""
	_prev_pos = global_position
	_visual_velocity = Vector3.ZERO
	_visual_vertical = 0.0
	_operator_elapsed = 0.0
	_pose.reset_locomotion()
	if _is_local():
		respawned.emit()
		inventory_changed.emit()
	if _avatar:
		_avatar.visible = true
	if _bar_root:
		_bar_root.visible = true
	health_changed.emit(health, MAX_HEALTH)
	_refresh_bar()
	gun.show()


func add_recoil(pitch_deg: float, yaw_deg: float) -> void:
	if not _is_local():
		return
	var pitch := deg_to_rad(pitch_deg)
	_turn_yaw(deg_to_rad(yaw_deg))
	_camera.rotation.x = clampf(_camera.rotation.x + pitch, deg_to_rad(-80.0), deg_to_rad(80.0))
	_recoil_pitch += pitch


func _process(delta: float) -> void:
	if _server_rules():
		_hurt_lock = maxf(_hurt_lock - delta, 0.0)
		_throw_wait = maxf(_throw_wait - delta, 0.0)
		flash_left = maxf(flash_left - delta, 0.0)
	if _is_local():
		_recover_recoil(delta)
	else:
		_interpolate_network_pose(delta)
	_operator_elapsed += delta
	if _operator_elapsed >= visual_update_interval():
		_update_operator(_operator_elapsed)
		_operator_elapsed = 0.0


func visual_update_interval() -> float:
	if _is_local():
		return 0.0
	var camera := get_viewport().get_camera_3d()
	return 1.0 / 60.0 if camera and camera.global_position.distance_squared_to(global_position) < 24.0 * 24.0 else 1.0 / 30.0


func _recover_recoil(delta: float) -> void:
	if absf(_recoil_pitch) < 0.0001:
		_recoil_pitch = 0.0
		return
	var step := _recoil_pitch * minf(1.0, delta * 10.0)
	_recoil_pitch -= step
	_camera.rotation.x = clampf(_camera.rotation.x - step, deg_to_rad(-80.0), deg_to_rad(80.0))


func _unhandled_input(event: InputEvent) -> void:
	if not _is_local() or not accepts_gameplay_input():
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		var left_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		if left_click or event.is_action_pressed(&"fire"):
			GameSettings.capture_gameplay_mouse(true)
			get_viewport().set_input_as_handled()
			return
	var selection := weapon_in_slot(GameSettings.selected_weapon_slot(event))
	if selection != "":
		select_weapon(selection)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_cycle_weapon(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			get_viewport().set_input_as_handled()
			return
	for kind: String in ARSENAL.GRENADE_IDS:
		if event.is_action_pressed(ARSENAL.GRENADE_ACTIONS[kind]):
			_throw_grenade(kind)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"use_medkit"):
		use_medkit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"throw_grenade"):
		_throw_grenade(carried_grenade())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"interact"):
		get_parent().get_node("Loot").interact(self)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := MOUSE_SENS * GameSettings.sensitivity * (0.2 if _scoped else lerpf(1.0, 0.55, gun.aim_blend()))
		var pitch_sign := 1.0 if GameSettings.invert_y else -1.0
		_turn_yaw(-event.relative.x * sensitivity)
		var pitch: float = _camera.rotation.x + event.relative.y * sensitivity * pitch_sign
		_camera.rotation.x = clampf(pitch, deg_to_rad(-80.0), deg_to_rad(80.0))


func _throw_grenade(kind: String) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and grenade_stock(kind) > 0:
		get_parent().get_node("Grenades").request_throw(self, kind)


func accepts_gameplay_input() -> bool:
	return control_enabled and GameSettings.game_window_focused() and not get_parent().input_blocked()


func _turn_yaw(amount: float) -> void:
	if not in_cover():
		rotate_y(amount)
		return
	var wall_yaw := atan2(_cover_normal.x, _cover_normal.z)
	var angle := angle_difference(wall_yaw, rotation.y)
	rotation.y = wall_yaw + clampf(angle + amount, -COVER_LOOK_LIMIT, COVER_LOOK_LIMIT)


func _physics_process(delta: float) -> void:
	if _dead or get_parent().round_finished():
		return
	if not _is_local():
		_update_capsule()
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
		_track_movement_audio(delta, false)
		return
	var accepts_input := accepts_gameplay_input()
	var jump_held := Input.is_action_pressed(&"jump")
	var jump_pressed := jump_held and not _jump_held
	_jump_held = jump_held
	var side := signf(Input.get_axis(&"cover_left", &"cover_right")) if accepts_input else 0.0
	var leaving_cover := accepts_input and (jump_pressed or Input.is_action_pressed(&"move_back"))
	if is_on_floor() and not in_cover() and side != 0.0 and not leaving_cover:
		_try_cover_ahead()
	if in_cover():
		if not is_on_floor() or leaving_cover:
			_leave_cover()
		else:
			_move_in_cover(side, delta)
			_track_movement_audio(delta, true)
			aiming = accepts_input and can_fire_from_cover() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and GameSettings.aim_pressed()
			return

	aiming = accepts_input and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and GameSettings.aim_pressed()
	if accepts_input:
		_update_crouch(Input.is_action_pressed(&"crouch"))
	if not accepts_input:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y += get_gravity().y * delta
		else:
			velocity.y = 0.0
		move_and_slide()
		_track_movement_audio(delta, true)
		return

	var vertical := velocity.y
	if not is_on_floor():
		vertical += get_gravity().y * delta
	if jump_pressed and is_on_floor() and not crouched:
		vertical = JUMP_VELOCITY

	var wish := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var sprinting := not crouched and not aiming and Input.is_action_pressed(&"sprint")
	var speed := WALK_SPEED
	if crouched:
		speed = CROUCH_SPEED
	elif aiming:
		speed = AIM_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	var direction := (global_transform.basis * Vector3(wish.x, 0.0, wish.y))
	if direction.length_squared() > 0.001:
		direction = direction.normalized()
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 8.0 * delta)
	velocity.y = vertical
	move_and_slide()
	_track_movement_audio(delta, true)
	if sprinting and wish.y < -0.7 and is_on_floor():
		_try_attach_cover(direction)


func _try_attach_cover(direction: Vector3) -> void:
	for index in get_slide_collision_count():
		var contact := get_slide_collision(index)
		var normal := contact.get_normal()
		if not contact.get_collider() is StaticBody3D or absf(normal.y) > 0.12:
			continue
		var wall_normal := Vector3(normal.x, 0.0, normal.z).normalized()
		if direction.dot(wall_normal) > -0.91 or not _has_cover_wall(global_position, wall_normal):
			continue
		_enter_cover(wall_normal)
		return


func _try_cover_ahead() -> void:
	var forward := -global_basis.z
	var normal := _wall_normal_at(global_position, forward)
	if normal.dot(forward) < -0.65 and _has_cover_wall(global_position, normal):
		_enter_cover(normal)


func _enter_cover(normal: Vector3) -> void:
	_cover_normal = normal
	velocity = Vector3.ZERO
	_update_crouch(true)
	_turn_yaw(0.0)


func _wall_normal_at(at: Vector3, direction: Vector3) -> Vector3:
	var origin := at + Vector3.UP * 1.26
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + direction * COVER_WALL_REACH, 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or not hit.collider is StaticBody3D or absf(hit.normal.y) > 0.12:
		return Vector3.ZERO
	return Vector3(hit.normal.x, 0.0, hit.normal.z).normalized()


func _has_cover_wall(at: Vector3, normal: Vector3) -> bool:
	return normal.dot(_wall_normal_at(at, -normal)) > 0.88


func _move_in_cover(side: float, delta: float) -> void:
	var tangent := Vector3.UP.cross(_cover_normal)
	if _peek_direction == 0.0 and side != 0.0:
		var travel := tangent * side
		if not _has_cover_wall(global_position + travel * COVER_EDGE_PROBE, _cover_normal):
			if not test_move(global_transform, travel * COVER_PEEK_DISTANCE):
				_peek_anchor = global_position
				_peek_direction = side
			else:
				side = 0.0

	if _peek_direction == 0.0:
		velocity = tangent * side * COVER_SPEED - _cover_normal * 0.65
		velocity.y = -1.0
		move_and_slide()
		if not _has_cover_wall(global_position, _cover_normal):
			_leave_cover()
		return

	# Keep the crouched body partially exposed at the edge and retrace the same path on release.
	var peek_axis := tangent * _peek_direction
	var target_distance := COVER_PEEK_DISTANCE if side == _peek_direction else 0.0
	var distance := (global_position - _peek_anchor).dot(peek_axis)
	velocity = peek_axis * clampf((target_distance - distance) / delta, -COVER_PEEK_SPEED, COVER_PEEK_SPEED)
	velocity.y = -1.0
	move_and_slide()
	distance = (global_position - _peek_anchor).dot(peek_axis)
	_cover_peek = _peek_direction * clampf(distance / COVER_PEEK_DISTANCE, 0.0, 1.0)
	if target_distance == 0.0 and absf(distance) < 0.015:
		_peek_direction = 0.0
		_cover_peek = 0.0


func _leave_cover() -> void:
	_cover_normal = Vector3.ZERO
	_peek_direction = 0.0
	_cover_peek = 0.0


func _track_movement_audio(delta: float, simulated: bool) -> void:
	if control_enabled:
		_movement_audio.track(delta, simulated, crouched)
	else:
		_movement_audio.reset()


func _update_crouch(wants_crouch: bool) -> void:
	if wants_crouch == crouched:
		return
	if not wants_crouch:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = _standing_capsule
		query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (STANDING_HEIGHT * 0.5 + 0.018))
		query.collision_mask = collision_mask
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return
	crouched = wants_crouch
	_update_capsule()


func _update_capsule() -> void:
	var height := CROUCH_HEIGHT if crouched else STANDING_HEIGHT
	if _capsule_height == height:
		return
	_capsule_height = height
	(_collision.shape as CapsuleShape3D).height = height
	_collision.position.y = height * 0.5


func _build_operator() -> void:
	_avatar = OperatorPose.MODEL.instantiate() as Node3D
	_avatar.name = "Operator"
	_avatar.rotation.y = PI
	_avatar.scale = Vector3.ONE * 0.96
	_avatar.position = Vector3(0.169, 0.0, -0.041)
	add_child(_avatar)
	OperatorPose.apply_textures(_avatar)
	_skeleton = _avatar.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton.reset_bone_poses()
	_pose = OperatorPose.new()
	_pose.actor = self
	_skeleton.add_child(_pose)

	var eyes := _avatar.find_child("Mil_R5_Eye", true, false).get_child(0) as MeshInstance3D
	var eye_center := eyes.global_transform * eyes.get_aabb().get_center()
	_eye_rest = to_local(eye_center) + Vector3(0.0, 0.0, -0.015)
	var head := _skeleton.find_bone(&"mixamorig_Head_06")
	_head_pivot = to_local(_skeleton.to_global(_skeleton.get_bone_global_rest(head).origin))
	_camera.position = _eye_rest
	_pouch = Marker3D.new()
	_pouch_rest = Vector3(-0.115, 1.31, -0.19)
	_pouch.position = _pouch_rest
	add_child(_pouch)

	_vest = _avatar.find_child(OperatorPose.VEST_MESH, true, false) as Node3D
	_avatar.find_child("Object_111", true, false).hide()
	if _is_local():
		for mesh: MeshInstance3D in _avatar.find_children("*", "MeshInstance3D", true, false):
			mesh.set_layer_mask_value(1, false)
			mesh.set_layer_mask_value(FIRST_PERSON_BODY_LAYER, true)
		for mesh_name in ["Object_97", "Object_99", "Object_109"]:
			var mesh := _avatar.find_child(mesh_name, true, false) as MeshInstance3D
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		eyes.hide()


func set_first_person_body_visible(visible_body: bool) -> void:
	_camera.set_cull_mask_value(FIRST_PERSON_BODY_LAYER, visible_body)


func _update_operator(delta: float) -> void:
	if _bar_root and not _dead:
		_face_bar()
	if _dead:
		_prev_pos = global_position
		return
	var step := global_position - _prev_pos
	_prev_pos = global_position
	var vertical_speed := step.y / maxf(delta, 0.001)
	_visual_vertical = lerpf(_visual_vertical, vertical_speed, minf(1.0, delta * 12.0))
	step.y = 0.0
	var instant := step / maxf(delta, 0.001)
	_visual_velocity = _visual_velocity.lerp(instant, minf(1.0, delta * 12.0))
	_pose.planar_velocity = _visual_velocity
	var simulates_motion := _is_local() or (is_in_group("bot") and _server_rules())
	_pose.grounded = is_on_floor() if simulates_motion else _movement_audio.grounded or not control_enabled
	var animation_vertical := velocity.y if simulates_motion and not _pose.grounded else _visual_vertical
	_pose.update_locomotion(delta, crouched, animation_vertical)
	_pose.aim_pitch = clampf(_camera.rotation.x, -0.78, 0.78)
	_crouch_blend = move_toward(_crouch_blend, float(crouched), delta * 7.5)
	_update_view_pose()


func _update_view_pose() -> void:
	_pose.aim_pitch = clampf(_camera.rotation.x, -0.78, 0.78)
	var stance := Vector3(0.0, -CROUCH_DROP, 0.05) * smoothstep(0.0, 1.0, _crouch_blend)
	var lean := Vector3.UP.cross(_cover_normal) * (_cover_peek * 0.12) - _cover_normal * 0.055
	var lean_local := global_basis.inverse() * lean
	_pose.stance_offset = stance + lean_local * 0.65
	_camera.position = _head_pivot + (_eye_rest - _head_pivot).rotated(Vector3.RIGHT, _pose.aim_pitch) + stance + lean_local
	_camera.rotation.y = -_cover_peek * 0.30
	_camera.rotation.z = -_cover_peek * 0.11
	_pouch.position = _pouch_rest + _pose.stance_offset
	if _bar_root:
		_bar_root.position.y = 1.98 + stance.y


func _build_bar() -> void:
	_bar_root = Node3D.new()
	_bar_root.position.y = 1.98
	add_child(_bar_root)
	var back := MeshInstance3D.new()
	var back_mesh := QuadMesh.new()
	back_mesh.size = Vector2(0.7, 0.09)
	var back_mat := StandardMaterial3D.new()
	back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back_mat.albedo_color = Color(0.05, 0.05, 0.05)
	back_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	back_mesh.material = back_mat
	back.mesh = back_mesh
	_bar_root.add_child(back)
	_bar_fill = MeshInstance3D.new()
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(0.64, 0.055)
	_bar_mat = StandardMaterial3D.new()
	_bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bar_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fill_mesh.material = _bar_mat
	_bar_fill.mesh = fill_mesh
	_bar_fill.position.z = 0.01
	_bar_root.add_child(_bar_fill)
	_refresh_bar()


func set_name_label(display_name: String) -> void:
	if not _bar_root:
		return
	if not _name_label:
		_name_label = Label3D.new()
		_name_label.position.y = 0.14
		_name_label.font_size = 32
		_name_label.pixel_size = 0.004
		_name_label.modulate = Color(1.0, 1.0, 1.0, 0.82)
		_name_label.outline_size = 4
		_name_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.55)
		_bar_root.add_child(_name_label)
	_name_label.text = display_name


func _refresh_bar() -> void:
	if _bar_fill == null:
		return
	var ratio := clampf(float(health) / float(MAX_HEALTH), 0.0, 1.0)
	_bar_fill.scale.x = maxf(ratio, 0.001)
	_bar_fill.position.x = -0.32 * (1.0 - ratio)
	_bar_mat.albedo_color = Color(lerpf(0.85, 0.2, ratio), lerpf(0.16, 0.75, ratio), 0.18)


func _face_bar() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_bar_root.look_at(camera.global_position, Vector3.UP)
	_bar_root.rotate_y(PI)
