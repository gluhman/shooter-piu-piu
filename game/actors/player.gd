extends CharacterBody3D

const Balance := preload("res://game/combat/combat_balance.gd")
const WALK_SPEED: float = Balance.MOVEMENT.walk_speed_m_s
const SPRINT_SPEED: float = WALK_SPEED * Balance.MOVEMENT.sprint_multiplier
const LADDER_SPEED := 2.4
const CROUCH_SPEED: float = WALK_SPEED * Balance.MOVEMENT.crouch_speed_multiplier
const AIM_SPEED: float = WALK_SPEED * Balance.MOVEMENT.ads_speed_multiplier
const GROUND_ACCELERATION := 42.0
const GROUND_BRAKING := 46.0
const AIR_ACCELERATION := 24.0
const STANDING_HEIGHT := 1.7
const CROUCH_HEIGHT := 1.22
const CROUCH_DROP := STANDING_HEIGHT - CROUCH_HEIGHT
const JUMP_VELOCITY: float = Balance.MOVEMENT.jump_vertical_speed_m_s
const MOUSE_SENS := 0.0022
const MAX_HEALTH: int = Balance.PLAYER.max_health
const MAX_ARMOR: int = Balance.VESTS.heavy.starting_durability
const ARSENAL := preload("res://game/combat/arsenal_assets.gd")
const NETWORK_POSE_SIZE := 13
const REMOTE_BLEND_TIME: float = Balance.NETWORK.remote_interpolation_delay_s
const LEAN_DISTANCE := 0.28
const LEAN_SPEED := 8.0
const LEAN_CLEARANCE := 0.07
const FIRST_PERSON_BODY_LAYER := 3
const Hurtboxes := preload("res://game/actors/operator_hurtboxes.gd")
const OperatorPose := preload("res://game/actors/operator_pose.gd")
const OPERATOR_MODEL_PATH := "res://assets/operator/operator.glb"
const HitReaction := preload("res://addons/hit_reactions_lite/hit_flinch_lite.gd")
const Weapon := preload("res://game/combat/weapon.gd")
const MovementAudio := preload("res://game/audio/movement_audio.gd")
const MEDKIT_HEAL := 45
const MAX_MEDKITS := 2

signal health_changed(current: int, maximum: int)
signal respawned
signal inventory_changed
signal weapon_wheel_used
signal grenade_selector_used

var control_enabled := false
var slot := 0
var health := float(MAX_HEALTH)
var armor := 0.0
var vest_tier := "none"
var sprinting := false
var sliding := false
var concussion_left := 0.0
var _slide_left := 0.0
var _slide_cooldown := 0.0
var _slide_direction := Vector3.ZERO
var _crouch_held := false
var _regen_left := 0.0
var _regen_sync_left := 0.0
var flash_left := 0.0
var _grenades: Dictionary[String, int] = {}
var _selected_grenade := ""
var _throw_wait := 0.0
var _frag_button: StringName
var _pose_sequence := 0
var _latest_pose := PackedFloat32Array()
var _pose_received_at := 0.0
var _pose_travel_budget := 0.40
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

var _lean_amount := 0.0
var _view_lean := 0.0

var _crouch_blend := 0.0
var _capsule_height := STANDING_HEIGHT
var _standing_capsule: CapsuleShape3D
var _pouch_rest: Vector3

var _jump_held := false
var _recoil_pitch := 0.0
var _recoil_yaw := 0.0
var _dead := false
var _respawn_selection := PackedStringArray()
var _respawn_ready := false
var _ladder_route := PackedVector3Array()
var _ladder_step := 0

var _respawn_timer: SceneTreeTimer
var _hurt_lock := 0.0
var _avatar: Node3D
var _skeleton: Skeleton3D
var _pose: OperatorPose
var _hit_reaction: HitReaction
var _hurtboxes: Hurtboxes
var _eye_rest: Vector3
var _head_pivot: Vector3
var _pouch: Marker3D
var _overhead: Node3D
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
	collision_layer = Balance.MOVEMENT_CAPSULE_MASK
	collision_mask = Balance.WORLD_AND_CAPSULES
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
		if get_parent().is_local_teammate(team_id()):
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


func take_damage(amount: float, killer_id: int = 0, zone: String = "chest", head_multiplier: float = 0.0, impact: Dictionary = {}) -> void:
	if not _server_rules() or get_parent().round_finished() or _dead or not control_enabled or amount <= 0.0:
		return
	if not get_parent().allows_damage(killer_id, score_id()):
		return
	if _hurt_lock > 0.0 and not (impact.get("zone") == "blast" and killer_id == score_id()):
		return
	var absorbed := 0.0
	if head_multiplier > 0.0:
		amount = Balance.zone_damage(amount, zone, head_multiplier)
		absorbed = Balance.vest_absorption(amount, zone, vest_tier, armor)
		armor -= absorbed
		amount -= absorbed
	_regen_left = Balance.PLAYER.health_regen_delay_s
	var next_health := maxf(health - amount, 0.0)
	var damage := health - next_health
	_set_health(next_health, killer_id, impact)
	var reaction := {}
	if next_health > 0.0 and (damage > 0.0 or absorbed > 0.0) and impact.has("point") and impact.has("velocity"):
		var point: Vector3 = impact.point
		var impulse: Vector3 = impact.velocity
		reaction = {"point": to_local(point), "impulse": global_basis.inverse() * impulse,
			"revision": _spawn_revision}
	get_parent().publish_damage(killer_id, score_id(), impact.get("source", ""), impact.get("zone", zone),
		damage, absorbed, next_health == 0.0, reaction)


func show_hit_reaction(reaction: Dictionary) -> void:
	if not _hit_reaction or _dead or not control_enabled or reaction.get("revision") != _spawn_revision:
		return
	var point: Variant = reaction.get("point")
	var impulse: Variant = reaction.get("impulse")
	if point is Vector3 and impulse is Vector3:
		_hit_reaction.hit(to_global(point), global_basis * impulse.limit_length(3.0))


func cancel_spawn_protection() -> void:
	_hurt_lock = 0.0


func _regenerate_health(delta: float) -> void:
	if _dead or not control_enabled or health >= MAX_HEALTH:
		return
	var recovery_time := maxf(0.0, delta - _regen_left)
	_regen_left = maxf(0.0, _regen_left - delta)
	if recovery_time <= 0.0:
		return
	health = minf(MAX_HEALTH, health + recovery_time * float(Balance.PLAYER.health_regen_hp_s))
	_regen_sync_left -= recovery_time
	if _regen_sync_left <= 0.0 or health == MAX_HEALTH:
		_regen_sync_left = 0.10
		_set_health(health, 0)


func grant_armor() -> void:
	if _server_rules() and control_enabled and armor < MAX_ARMOR:
		vest_tier = "heavy"
		armor = MAX_ARMOR
		_set_health(health, 0)


func armor_capacity() -> int:
	return int(Balance.VESTS[vest_tier].starting_durability)


func armor_movement_scale() -> float:
	return float(Balance.VESTS[vest_tier].movement_multiplier)


func armor_ads_delay() -> float:
	return float(Balance.VESTS[vest_tier].ads_add_s)


func combat_grounded() -> bool:
	return is_on_floor() and not is_climbing_ladder() if _is_local() or is_in_group("bot") else _net_grounded


func combat_speed() -> float:
	return Vector2(velocity.x, velocity.z).length() if _is_local() or is_in_group("bot") else visual_speed()


func capsule_distance(at: Vector3) -> float:
	var shape := _collision.shape as CapsuleShape3D
	var half_segment := maxf(0.0, shape.height * 0.5 - shape.radius)
	var local := _collision.to_local(at)
	var nearest := Vector3(0.0, clampf(local.y, -half_segment, half_segment), 0.0)
	return maxf(0.0, local.distance_to(nearest) - shape.radius)


func hurtbox_center(zone: String) -> Vector3:
	return _hurtboxes.center(zone)


func blast_samples() -> Array[Vector3]:
	return [hurtbox_center("head"), hurtbox_center("chest"), hurtbox_center("pelvis")]


func grenade_stock(kind: String) -> int:
	return _grenades.get(kind, 0)


func carried_grenade() -> String:
	_ensure_selected_grenade()
	return _selected_grenade


func available_grenade_ids() -> Array[String]:
	var available: Array[String] = []
	for kind: String in ARSENAL.GRENADE_IDS:
		if grenade_stock(kind) > 0:
			available.append(kind)
	return available


func select_grenade(kind: String) -> bool:
	if grenade_stock(kind) <= 0:
		return false
	_selected_grenade = kind
	inventory_changed.emit()
	return true


func cycle_grenade(direction: int = 1) -> void:
	var available := available_grenade_ids()
	if available.is_empty():
		return
	var current := available.find(carried_grenade())
	_selected_grenade = available[posmod(current + direction, available.size())]
	inventory_changed.emit()
	grenade_selector_used.emit()


func grenade_space(kind: String) -> int:
	return ARSENAL.MAX_GRENADES - grenade_stock(kind) if ARSENAL.GRENADE_IDS.has(kind) else 0


func drop_carried_grenades() -> void:
	_grenades.clear()
	_selected_grenade = ""


func grant_grenades(kind: String, amount: int) -> void:
	var accepted := mini(amount, grenade_space(kind))
	if _server_rules() and control_enabled and accepted > 0 and ARSENAL.GRENADE_IDS.has(kind):
		_grenades[kind] = grenade_stock(kind) + accepted
		_ensure_selected_grenade()
		_send_inventory()


func consume_grenade(kind: String) -> bool:
	if not _server_rules() or _throw_wait > 0.0 or grenade_stock(kind) <= 0:
		return false
	_grenades[kind] -= 1
	if _grenades[kind] == 0:
		_grenades.erase(kind)
		if _selected_grenade == kind:
			_selected_grenade = ""
			_ensure_selected_grenade()
	_throw_wait = 0.72
	_send_inventory()
	return true


func apply_flash(duration: float) -> void:
	if not _server_rules() or duration <= 0.0:
		return
	flash_left = maxf(flash_left, duration)
	if _is_local():
		net_flash(duration)
	elif score_id() > 1:
		net_flash.rpc_id(score_id(), duration)


@rpc("any_peer", "reliable")
func net_flash(duration: float) -> void:
	if multiplayer.get_remote_sender_id() not in [0, 1] or not _is_local():
		return
	get_parent().get_node("HUD").show_flashbang(1.0, duration)


func apply_concussion(duration: float) -> void:
	if not _server_rules() or duration <= 0.0:
		return
	concussion_left = maxf(concussion_left, duration)
	if not _is_local() and score_id() > 1:
		net_concussion.rpc_id(score_id(), duration)


@rpc("any_peer", "reliable")
func net_concussion(duration: float) -> void:
	if multiplayer.get_remote_sender_id() == 1 and _is_local():
		concussion_left = maxf(concussion_left, duration)


func set_scoped_view(scoped: bool) -> void:
	if _is_local():
		_scoped = scoped
		set_first_person_body_visible(not scoped)


func restore_health(amount: int) -> void:
	if _server_rules() and control_enabled:
		_set_health(minf(MAX_HEALTH, health + amount), 0)


func _set_health(value: float, killer_id: int, impact: Dictionary = {}) -> void:
	health = value
	for peer in get_parent().match_peers():
		net_set_health.rpc_id(peer, health, armor, vest_tier, killer_id)
	_commit(killer_id, impact)


func equip(id: String) -> void:
	if not get_parent().allows_weapon(id):
		return
	_spawn_loadout = id
	_apply_equip(id)
	_send_equipment(id)


func choose_loadout(primary: String, sidearm: String, grenade: String) -> void:
	if _dead or get_parent().round_finished() or not _valid_loadout(primary, sidearm, grenade):
		return
	if _server_rules():
		_apply_loadout(primary, sidearm, grenade)
		_send_equipment(primary)
	else:
		net_choose_loadout.rpc_id(1, primary, sidearm, grenade)


func choose_respawn_loadout(primary: String, sidearm: String, grenade: String) -> void:
	if not _dead or get_parent().round_finished() or not _valid_loadout(primary, sidearm, grenade):
		return
	if _server_rules():
		_accept_respawn_loadout(primary, sidearm, grenade, _spawn_revision)
	else:
		net_choose_respawn_loadout.rpc_id(1, primary, sidearm, grenade, _spawn_revision)


@rpc("any_peer", "reliable")
func net_choose_respawn_loadout(primary: String, sidearm: String, grenade: String, revision: int) -> void:
	if multiplayer.is_server() and _is_owner_request(multiplayer.get_remote_sender_id()):
		_accept_respawn_loadout(primary, sidearm, grenade, revision)


func _accept_respawn_loadout(primary: String, sidearm: String, grenade: String, revision: int) -> void:
	if not _dead or revision != _spawn_revision or get_parent().round_finished():
		return
	if not _valid_loadout(primary, sidearm, grenade) or not _respawn_selection.is_empty():
		return
	_respawn_selection = PackedStringArray([primary, sidearm, grenade])
	if _respawn_ready:
		_request_respawn.call_deferred()


func _requires_respawn_selection() -> bool:
	return score_id() > 0 and not get_parent().is_training_range()


func _valid_loadout(primary: String, sidearm: String, grenade: String) -> bool:
	return get_parent().allows_weapon(primary) and Weapon.inventory_slot(primary) == "primary" \
		and get_parent().allows_weapon(sidearm) and sidearm in Weapon.SIDEARMS and grenade in ARSENAL.GRENADE_IDS


func _apply_loadout(primary: String, sidearm: String, grenade: String) -> void:
	_spawn_loadout = primary
	_spawn_sidearm = sidearm
	_spawn_grenade = grenade
	_stored.clear()
	_grenades.clear()
	medkits = 0
	_restore_starting_supplies()
	_apply_equip(primary)
	inventory_changed.emit()


func _restore_starting_supplies() -> void:
	if _spawn_sidearm != "":
		var stats: Dictionary = Weapon.WEAPONS[_spawn_sidearm]
		_stored[_spawn_sidearm] = Vector2i(stats.mag, stats.reserve)
	if _spawn_grenade != "":
		_grenades[_spawn_grenade] = ARSENAL.MAX_GRENADES
		_selected_grenade = _spawn_grenade


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
	return base


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


func team_id() -> int:
	return slot % 2


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
		net_set_health.rpc_id(peer, health, armor, vest_tier, 0)


func network_pose() -> PackedFloat32Array:
	if not _latest_pose.is_empty() and not _is_local() and not is_in_group("bot"):
		return _latest_pose
	_pose_sequence += 1
	var grounded := combat_grounded() if _is_local() or (_server_rules() and is_in_group("bot")) else _net_grounded
	return PackedFloat32Array([
		position.x, position.y, position.z, rotation.y, _camera.rotation.x, float(crouched), float(aiming),
		float(sprinting), float(sliding), _view_lean, float(grounded), float(_spawn_revision), float(_pose_sequence),
	])


func apply_network_pose(pose: PackedFloat32Array) -> void:
	if pose.size() != NETWORK_POSE_SIZE or pose[11] != float(_spawn_revision):
		return
	if not _latest_pose.is_empty() and pose[12] <= _latest_pose[12]:
		return
	var target := Vector3(pose[0], pose[1], pose[2])
	var snap := _latest_pose.is_empty() or position.distance_squared_to(target) > 25.0
	_latest_pose = pose
	_pose_received_at = Time.get_ticks_usec() * 0.000001
	_pose_origin = position
	_pose_yaw = rotation.y
	_pose_pitch = _camera.rotation.x
	_pose_elapsed = REMOTE_BLEND_TIME if snap else 0.0
	if snap:
		_interpolate_network_pose(0.0)
		_prev_pos = global_position
		_visual_velocity = Vector3.ZERO
		_visual_vertical = 0.0
		_pose.reset_locomotion()
	crouched = pose[5] > 0.0
	sprinting = pose[7] > 0.0
	sliding = pose[8] > 0.0
	aiming = pose[6] > 0.0 and not sprinting and not sliding
	var basis := Basis(Vector3.UP, pose[3])
	var eye := target + basis * _neutral_eye(pose[4], float(crouched))
	_lean_amount = _limit_lean(clampf(pose[9], -1.0, 1.0), eye, basis.x)
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
	var pitch_adjustment := Basis(global_basis.x.normalized(), _latest_pose[4] - _camera.rotation.x)
	var camera_at := _camera.global_position
	var offset := camera_at - global_position
	var target := Vector3(_latest_pose[0], _latest_pose[1], _latest_pose[2])
	var aim_rotation := yaw_adjustment * pitch_adjustment
	return Transform3D(aim_rotation * rendered.basis,
		target + yaw_adjustment * offset + aim_rotation * (rendered.origin - camera_at))


func record_hurtboxes(time: float) -> void:
	var correction := Transform3D.IDENTITY
	if not _latest_pose.is_empty() and not _is_local() and not is_in_group("bot"):
		var turn := Basis(Vector3.UP, angle_difference(rotation.y, _latest_pose[3]))
		var destination := Vector3(_latest_pose[0], _latest_pose[1], _latest_pose[2])
		correction = Transform3D(turn, destination - turn * global_position)
	_hurtboxes.record_pose(time, correction)


func rewound_hit(from: Vector3, to: Vector3, time: float) -> Dictionary:
	return _hurtboxes.rewound_ray(from, to, time)


func set_weapon_grips(right: Marker3D, left: Marker3D, knife: bool) -> void:
	_pose.right_wrist = right
	_pose.left_wrist = left
	_pose.knife_grip = knife


func set_support_grip(reload_blend: float) -> void:
	_pose.support_grip = reload_blend


func weapon_carry_anchor() -> Vector3:
	return _pose.weapon_carry_anchor()


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
func net_set_health(value: float, vest: float, tier: String, killer_id: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	health = value
	armor = vest
	vest_tier = tier
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
		if not _is_owner_request(sender) or _dead or get_parent().round_finished() or not _valid_loadout(primary, sidearm, grenade):
			return
		_apply_loadout(primary, sidearm, grenade)
		_send_equipment(primary)
		net_choose_loadout.rpc_id(sender, primary, sidearm, grenade)
	elif sender == 1 and _is_local():
		_apply_loadout(primary, sidearm, grenade)


@rpc("any_peer", "reliable")
func net_respawn(id: String, at: Vector3, revision: int, loadout := PackedStringArray()) -> void:
	if multiplayer.get_remote_sender_id() == 1 and revision > _spawn_revision:
		if loadout.size() == 3:
			_spawn_loadout = loadout[0]
			_spawn_sidearm = loadout[1]
			_spawn_grenade = loadout[2]
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
		_ensure_selected_grenade()
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
	if not control_enabled:
		_hurt_lock = Balance.MATCH.spawn_protection_s
	control_enabled = true
	_hurtboxes.set_active(true)
	_switch_pending = false
	gun.equip(id, magazine, reserve, switching)
	if _is_local() and not get_parent().input_blocked():
		GameSettings.capture_gameplay_mouse()


func _commit(killer_id: int, impact: Dictionary = {}) -> void:
	_vest.visible = armor > 0
	health_changed.emit(ceili(health), MAX_HEALTH)
	_refresh_bar()
	if health > 0 or _dead:
		return
	_dead = true
	_ladder_route.clear()
	if _hit_reaction:
		_hit_reaction.reset()
	_hurtboxes.set_active(false)
	_movement_audio.reset()
	_lean_amount = 0.0
	_view_lean = 0.0
	aiming = false
	control_enabled = false
	gun.cancel_reload()
	gun.hide()
	collision_layer = 0
	collision_mask = 0
	var drift := shot_motion().limit_length(4.0)
	velocity = Vector3.ZERO
	if _avatar:
		_avatar.visible = false
	if _overhead:
		_overhead.visible = false
	if _server_rules():
		get_parent().get_node("Grenades").drop_cooked(self)
		var body_impact := impact.duplicate()
		body_impact["drift"] = drift
		get_parent().get_node("Loot").drop_combatant(self, body_impact)
		get_parent().announce(killer_id, score_id())
		_respawn_timer = get_tree().create_timer(_respawn_delay(), false, true)
		_respawn_timer.timeout.connect(_request_respawn)
	_clear_inventory()
	inventory_changed.emit()
	if _is_local() and _requires_respawn_selection():
		get_parent().get_node("HUD/WeaponSelect").show_respawn_selection.call_deferred()


func _clear_inventory() -> void:
	_stored.clear()
	medkits = 0
	_grenades.clear()
	_selected_grenade = ""
	_switch_pending = false


func _reset_support() -> void:
	_ladder_route.clear()
	vest_tier = Balance.PLAYER.spawn_vest
	armor = armor_capacity()
	_vest.show()
	flash_left = 0.0
	concussion_left = 0.0
	sprinting = false
	sliding = false
	_slide_left = 0.0
	_slide_cooldown = 0.0
	_regen_left = 0.0
	_regen_sync_left = 0.0
	_throw_wait = 0.0
	_frag_button = &""


func _request_respawn() -> void:
	_respawn_timer = null
	if not _dead or get_parent().round_finished():
		return
	_respawn_ready = true
	if _requires_respawn_selection() and _respawn_selection.is_empty():
		return
	var at: Vector3 = get_parent().choose_respawn(self, _last_spawn_position)
	if not at.is_finite():
		_respawn_timer = get_tree().create_timer(0.25, false, true)
		_respawn_timer.timeout.connect(_request_respawn)
		return
	var loadout := _respawn_selection.duplicate()
	if loadout.size() == 3:
		_spawn_loadout = loadout[0]
		_spawn_sidearm = loadout[1]
		_spawn_grenade = loadout[2]
	var id := _next_respawn_weapon()
	var revision := _spawn_revision + 1
	for peer in get_parent().match_peers():
		net_respawn.rpc_id(peer, id, at, revision, loadout)
	_apply_respawn(id, at, revision)


func _next_respawn_weapon() -> String:
	return _spawn_loadout


func _respawn_delay() -> float:
	if get_parent().is_training_range():
		return get_parent().training_respawn_delay()
	return float(Balance.MATCH.respawn_delay_s)


func restart_round() -> void:
	_cancel_respawn()
	_apply_respawn(_spawn_loadout, spawn_position, _spawn_revision + 1)
	_recoil_pitch = 0.0
	_jump_held = Input.is_action_pressed(&"jump")


func stop_round() -> void:
	_ladder_route.clear()
	_cancel_respawn()
	if _hit_reaction:
		_hit_reaction.reset()
	_movement_audio.reset()
	gun.stop_round()
	_lean_amount = 0.0
	_view_lean = 0.0
	aiming = false
	velocity = Vector3.ZERO


func _cancel_respawn() -> void:
	_respawn_ready = false
	_respawn_selection.clear()
	if _respawn_timer and _respawn_timer.timeout.is_connected(_request_respawn):
		_respawn_timer.timeout.disconnect(_request_respawn)
	_respawn_timer = null


func _apply_respawn(id: String, at: Vector3, revision: int) -> void:
	_cancel_respawn()
	_clear_inventory()
	_reset_support()
	_restore_starting_supplies()
	_lean_amount = 0.0
	_view_lean = 0.0
	_spawn_revision = revision
	_latest_pose = PackedFloat32Array()
	_hurtboxes.reset_history()
	if _hit_reaction:
		_hit_reaction.reset()
	_net_grounded = true
	_last_spawn_position = at
	global_position = at
	_movement_audio.reset()
	velocity = Vector3.ZERO
	rotation.y = atan2(at.x, at.z)
	_camera.rotation.x = 0.0
	_recoil_pitch = 0.0
	_recoil_yaw = 0.0
	health = float(MAX_HEALTH)
	_dead = false
	collision_layer = Balance.MOVEMENT_CAPSULE_MASK
	collision_mask = Balance.WORLD_AND_CAPSULES
	crouched = false
	aiming = false
	_crouch_blend = 0.0
	_update_view_pose()
	_update_capsule()
	_hurt_lock = Balance.MATCH.spawn_protection_s
	if id != "":
		_apply_equip(id)
	control_enabled = id != ""
	_hurtboxes.set_active(control_enabled)
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
	if _overhead:
		_overhead.visible = true
	health_changed.emit(ceili(health), MAX_HEALTH)
	_refresh_bar()
	gun.show()


func add_recoil(pitch_deg: float, yaw_deg: float) -> void:
	if not _is_local():
		return
	var pitch := deg_to_rad(pitch_deg)
	var yaw := deg_to_rad(yaw_deg)
	rotate_y(yaw)
	_recoil_yaw += yaw
	_camera.rotation.x = clampf(_camera.rotation.x + pitch, deg_to_rad(-80.0), deg_to_rad(80.0))
	_recoil_pitch += pitch


func _process(delta: float) -> void:
	if _server_rules():
		_hurt_lock = maxf(_hurt_lock - delta, 0.0)
		_throw_wait = maxf(_throw_wait - delta, 0.0)
		flash_left = maxf(flash_left - delta, 0.0)
		if not get_parent().round_finished():
			_regenerate_health(delta)
	concussion_left = maxf(concussion_left - delta, 0.0)
	if _is_local():
		_recover_recoil(delta)
	else:
		_interpolate_network_pose(delta)
	_operator_elapsed += delta
	if _operator_elapsed >= _visual_update_interval():
		_update_operator(_operator_elapsed)
		_operator_elapsed = 0.0


func _visual_update_interval() -> float:
	if _is_local():
		return 0.0
	var camera := get_viewport().get_camera_3d()
	return 1.0 / 60.0 if camera and camera.global_position.distance_squared_to(global_position) < 24.0 * 24.0 else 1.0 / 30.0


func _recover_recoil(delta: float) -> void:
	var recovery: float = delta * gun.recoil_recovery()
	var pitch_step := clampf(_recoil_pitch, -recovery, recovery)
	var yaw_step := clampf(_recoil_yaw, -recovery, recovery)
	_recoil_pitch -= pitch_step
	_recoil_yaw -= yaw_step
	if not is_zero_approx(yaw_step):
		rotate_y(-yaw_step)
	_camera.rotation.x = clampf(_camera.rotation.x - pitch_step, deg_to_rad(-80.0), deg_to_rad(80.0))


func _unhandled_input(event: InputEvent) -> void:
	if _is_local() and _frag_button != &"" and event.is_action_released(_frag_button):
		_frag_button = &""
		get_parent().get_node("Grenades").request_throw(self, "frag", true)
		get_viewport().set_input_as_handled()
		return
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
	if event.is_action_pressed(&"select_grenade"):
		cycle_grenade()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_cycle_weapon(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			get_viewport().set_input_as_handled()
			return
	for kind: String in ARSENAL.GRENADE_IDS:
		var action: StringName = ARSENAL.GRENADE_ACTIONS[kind]
		if action != &"throw_grenade" and event.is_action_pressed(action):
			_throw_grenade(kind, action)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"use_medkit"):
		use_medkit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"throw_grenade"):
		_throw_grenade(carried_grenade(), &"throw_grenade")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"interact"):
		get_parent().get_node("Loot").interact(self)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := MOUSE_SENS * GameSettings.sensitivity * (0.2 if _scoped else lerpf(1.0, 0.55, gun.aim_blend()))
		if concussion_left > 0.0:
			sensitivity *= float(Balance.GRENADES.concussion.mouse_look_sensitivity_multiplier_during_effect)
		var pitch_sign := 1.0 if GameSettings.invert_y else -1.0
		rotate_y(-event.relative.x * sensitivity)
		var pitch: float = _camera.rotation.x + event.relative.y * sensitivity * pitch_sign
		_camera.rotation.x = clampf(pitch, deg_to_rad(-80.0), deg_to_rad(80.0))


func _throw_grenade(kind: String, action: StringName) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not sprinting and grenade_stock(kind) > 0:
		select_grenade(kind)
		if kind == "frag":
			_frag_button = action
		get_parent().get_node("Grenades").request_throw(self, kind)


func _ensure_selected_grenade() -> void:
	if grenade_stock(_selected_grenade) > 0:
		return
	var available := available_grenade_ids()
	_selected_grenade = available[0] if not available.is_empty() else ""


func accepts_gameplay_input() -> bool:
	return control_enabled and GameSettings.game_window_focused() and not get_parent().input_blocked()


func has_support_tools() -> bool:
	return Weapon.specialization(_spawn_loadout) == "support"


func fieldworks() -> Node:
	return get_parent().get_node_or_null("Fieldworks")


func _physics_process(delta: float) -> void:
	if _dead or get_parent().round_finished():
		return
	if not _is_local():
		_update_capsule()
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
		_track_movement_audio(delta, false)
		return
	if not _ladder_route.is_empty():
		_climb_ladder(delta)
		return
	var accepts_input := accepts_gameplay_input()
	if accepts_input:
		var look := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
		if look.length() > 0.18:
			var stick_sensitivity := MOUSE_SENS * GameSettings.sensitivity * 95.0 * delta
			rotate_y(-look.x * stick_sensitivity)
			var stick_pitch_sign := 1.0 if GameSettings.invert_y else -1.0
			_camera.rotation.x = clampf(_camera.rotation.x + look.y * stick_sensitivity * stick_pitch_sign, deg_to_rad(-80.0), deg_to_rad(80.0))
	var works := fieldworks()
	if works and works.is_mounted(self):
		velocity = Vector3.ZERO
		sprinting = false
		sliding = false
		_slide_left = 0.0
		_lean_amount = move_toward(_lean_amount, 0.0, LEAN_SPEED * delta)
		_jump_held = Input.is_action_pressed(&"jump")
		aiming = accepts_input and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and GameSettings.aim_pressed()
		return
	var jump_held := Input.is_action_pressed(&"jump")
	var jump_pressed := jump_held and not _jump_held
	_jump_held = jump_held
	var lean_input := Input.get_axis(&"cover_left", &"cover_right") if accepts_input else 0.0
	_lean_amount = move_toward(_lean_amount, lean_input, LEAN_SPEED * delta)

	var wish := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var wants_crouch := accepts_input and Input.is_action_pressed(&"crouch")
	var direction := (global_basis * Vector3(wish.x, 0.0, wish.y)).limit_length()
	_slide_left = maxf(0.0, _slide_left - delta)
	_slide_cooldown = maxf(0.0, _slide_cooldown - delta)
	if wants_crouch and not _crouch_held and sprinting and is_on_floor() and _slide_cooldown == 0.0:
		_slide_direction = Vector3(velocity.x, 0.0, velocity.z).normalized()
		_slide_left = Balance.MOVEMENT.slide_duration_s
		_slide_cooldown = Balance.MOVEMENT.slide_cooldown_s
	_crouch_held = wants_crouch
	sliding = _slide_left > 0.0 and accepts_input
	if accepts_input:
		_update_crouch(wants_crouch or sliding)
	sprinting = accepts_input and not crouched and not sliding and not wish.is_zero_approx() and Input.is_action_pressed(&"sprint")
	aiming = accepts_input and not sprinting and not sliding and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and GameSettings.aim_pressed()
	if not accepts_input:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y += -float(Balance.MOVEMENT.gravity_m_s2) * delta
		else:
			velocity.y = 0.0
		move_and_slide()
		_track_movement_audio(delta, true)
		return

	var vertical := velocity.y
	if not is_on_floor():
		vertical += -float(Balance.MOVEMENT.gravity_m_s2) * delta
	if jump_pressed and is_on_floor() and not crouched:
		vertical = maxf(JUMP_VELOCITY, works.jump_speed(global_position) if works else 0.0)
		var fixtures := get_parent().get_node_or_null("Map/VillageFixtures")
		if fixtures and not direction.is_zero_approx():
			vertical = maxf(vertical, fixtures.window_jump_speed(global_position, direction, STANDING_HEIGHT))

	var speed := WALK_SPEED
	if crouched:
		speed = CROUCH_SPEED
	elif aiming:
		speed = AIM_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	if sliding:
		direction = _slide_direction
		speed = lerpf(CROUCH_SPEED, float(Balance.MOVEMENT.slide_initial_speed_m_s),
			_slide_left / float(Balance.MOVEMENT.slide_duration_s))
	speed *= armor_movement_scale()
	if concussion_left > 0.0:
		speed *= float(Balance.GRENADES.concussion.movement_speed_multiplier_during_effect)
	var acceleration := AIR_ACCELERATION
	if is_on_floor():
		acceleration = GROUND_BRAKING if wish.is_zero_approx() else GROUND_ACCELERATION
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(Vector2(direction.x, direction.z) * speed, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	velocity.y = vertical
	move_and_slide()
	_track_movement_audio(delta, true)


func start_ladder_climb(route: PackedVector3Array) -> bool:
	var can_climb := control_enabled and _server_rules() if is_in_group("bot") else accepts_gameplay_input()
	if route.is_empty() or not can_climb or is_climbing_ladder():
		return false
	var feet := global_transform
	for point in route:
		if test_move(feet, point - feet.origin):
			return false
		feet.origin = point
	_ladder_route = route
	_ladder_step = 0
	velocity = Vector3.ZERO
	sprinting = false
	sliding = false
	aiming = false
	_lean_amount = 0.0
	_slide_left = 0.0
	return true


func is_climbing_ladder() -> bool:
	return not _ladder_route.is_empty()


func _climb_ladder(delta: float) -> void:
	var offset := _ladder_route[_ladder_step] - global_position
	var movement := offset.limit_length(LADDER_SPEED * delta)
	if move_and_collide(movement):
		_ladder_route.clear()
		return
	if offset.length_squared() <= movement.length_squared() + 0.000001:
		_ladder_step += 1
		if _ladder_step == _ladder_route.size():
			_ladder_route.clear()
	_track_movement_audio(delta, true)


func _limit_lean(amount: float, eye: Vector3, right: Vector3) -> float:
	if is_zero_approx(amount):
		return 0.0
	var offset := right * (amount * LEAN_DISTANCE)
	var ray := PhysicsRayQueryParameters3D.create(eye, eye + offset + offset.normalized() * LEAN_CLEARANCE, Balance.WORLD_MASK)
	ray.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return amount
	return signf(amount) * minf(absf(amount), maxf(0.0, eye.distance_to(hit.position) - LEAN_CLEARANCE) / LEAN_DISTANCE)


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
	var operator_model := load(OPERATOR_MODEL_PATH) as PackedScene
	if operator_model == null:
		push_error("Unable to load operator model")
		return
	_avatar = operator_model.instantiate() as Node3D
	_avatar.name = "Operator"
	_avatar.rotation.y = PI
	_avatar.scale = Vector3.ONE * 0.96
	_avatar.position = Vector3(0.169, 0.0, -0.041)
	add_child(_avatar)
	OperatorPose.apply_textures(_avatar, team_id() if get_parent().team_deathmatch else -1)
	_skeleton = _avatar.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton.reset_bone_poses()
	_pose = OperatorPose.new()
	_pose.actor = self
	_skeleton.add_child(_pose)
	_hurtboxes = Hurtboxes.new()
	_hurtboxes.name = "OperatorHurtboxes"
	add_child(_hurtboxes)
	_hurtboxes.setup(_skeleton, _pose)
	if not Net.dedicated and not _is_local():
		_hit_reaction = HitReaction.new()
		_hit_reaction.name = "HitReaction"
		_hit_reaction.strength = 1.55
		_hit_reaction.max_angle_deg = 17.0
		_hit_reaction.hit_bones = PackedStringArray([
			"mixamorig_Hips_01", "mixamorig_Spine_02", "mixamorig_Spine1_03", "mixamorig_Spine2_04",
			"mixamorig_Neck_05", "mixamorig_Head_06",
			"mixamorig_RightArm_09", "mixamorig_RightForeArm_010", "mixamorig_RightHand_011",
			"mixamorig_LeftArm_033", "mixamorig_LeftForeArm_034", "mixamorig_LeftHand_035",
			"mixamorig_RightUpLeg_057", "mixamorig_RightLeg_058", "mixamorig_RightFoot_059",
			"mixamorig_LeftUpLeg_063", "mixamorig_LeftLeg_064", "mixamorig_LeftFoot_065",
		])
		_skeleton.add_child(_hit_reaction)

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
	if _overhead and not _dead:
		_face_overhead()
		var observer := get_viewport().get_camera_3d()
		if observer:
			_overhead.visible = not get_parent().get_node("Grenades").obscures(observer.global_position, hurtbox_center("head"))
	if _dead:
		_prev_pos = global_position
		return
	var step := global_position - _prev_pos
	_prev_pos = global_position
	var simulates_motion := _is_local() or (is_in_group("bot") and _server_rules())
	var motion := get_real_velocity() if simulates_motion else step / maxf(delta, 0.001)
	var blend := 1.0 - exp(-delta * 14.0)
	_visual_vertical = lerpf(_visual_vertical, motion.y, blend)
	motion.y = 0.0
	_visual_velocity = _visual_velocity.lerp(motion, blend)
	_pose.planar_velocity = _visual_velocity
	_pose.grounded = (is_on_floor() if simulates_motion else _net_grounded) or not control_enabled
	_pose.aim_pitch = clampf(_camera.rotation.x, -0.78, 0.78)
	var animation_vertical := velocity.y if simulates_motion and not _pose.grounded else _visual_vertical
	_pose.update_locomotion(delta, crouched, animation_vertical)
	_crouch_blend = move_toward(_crouch_blend, float(crouched), delta * 7.5)
	_update_view_pose()
	gun.update_pose(delta)


func _update_view_pose() -> void:
	_pose.aim_pitch = clampf(_camera.rotation.x, -0.78, 0.78)
	var crouch_weight := smoothstep(0.0, 1.0, _crouch_blend)
	var stance := Vector3(0.0, -CROUCH_DROP, 0.05) * crouch_weight
	var eye := _neutral_eye(_camera.rotation.x, crouch_weight)
	_view_lean = _limit_lean(_lean_amount, to_global(eye), global_basis.x) if _is_local() else _lean_amount
	var lean_offset := Vector3.RIGHT * (_view_lean * LEAN_DISTANCE)
	_pose.lean = _view_lean
	_pose.stance_offset = stance + lean_offset * 0.65
	_camera.position = eye + lean_offset
	_camera.rotation.z = -_view_lean * 0.16
	_pouch.position = _pouch_rest + _pose.stance_offset
	if _overhead:
		_overhead.position.y = 1.98 + stance.y


func _neutral_eye(pitch: float, crouch_weight: float) -> Vector3:
	var eye_offset := (_eye_rest - _head_pivot).rotated(Vector3.RIGHT, clampf(pitch, -0.78, 0.78))
	return _head_pivot + eye_offset + Vector3(0.0, -CROUCH_DROP, 0.05) * crouch_weight


func _ensure_overhead() -> void:
	if _overhead:
		return
	_overhead = Node3D.new()
	_overhead.position.y = 1.98
	_overhead.visible = not _dead
	add_child(_overhead)


func _build_bar() -> void:
	_ensure_overhead()
	var back := MeshInstance3D.new()
	var back_mesh := QuadMesh.new()
	back_mesh.size = Vector2(0.7, 0.09)
	var back_mat := StandardMaterial3D.new()
	back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back_mat.albedo_color = Color(0.05, 0.05, 0.05)
	back_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	back_mesh.material = back_mat
	back.mesh = back_mesh
	_overhead.add_child(back)
	_bar_fill = MeshInstance3D.new()
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(0.64, 0.055)
	_bar_mat = StandardMaterial3D.new()
	_bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bar_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fill_mesh.material = _bar_mat
	_bar_fill.mesh = fill_mesh
	_bar_fill.position.z = 0.01
	_overhead.add_child(_bar_fill)
	_refresh_bar()


func set_name_label(display_name: String) -> void:
	if _is_local() or Net.dedicated:
		return
	_ensure_overhead()
	if not _name_label:
		_name_label = Label3D.new()
		_name_label.position.y = 0.14
		_name_label.font_size = 32
		_name_label.pixel_size = 0.004
		_name_label.modulate = Color(1.0, 1.0, 1.0, 0.82)
		_name_label.outline_size = 4
		_name_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.55)
		_overhead.add_child(_name_label)
	_name_label.text = display_name


func _refresh_bar() -> void:
	if _bar_fill == null:
		return
	var ratio := clampf(float(health) / float(MAX_HEALTH), 0.0, 1.0)
	_bar_fill.scale.x = maxf(ratio, 0.001)
	_bar_fill.position.x = -0.32 * (1.0 - ratio)
	_bar_mat.albedo_color = Color(lerpf(0.85, 0.2, ratio), lerpf(0.16, 0.75, ratio), 0.18)


func _face_overhead() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_overhead.look_at(camera.global_position, Vector3.UP)
	_overhead.rotate_y(PI)
