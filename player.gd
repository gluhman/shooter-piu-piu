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
const OperatorPose := preload("res://operator_pose.gd")
const Weapon := preload("res://weapon.gd")
const MEDKIT_HEAL := 45

signal health_changed(current: int, maximum: int)
signal respawned
signal inventory_changed

var control_enabled := false
var health := MAX_HEALTH
var weapon_id := ""
var slot := 0
var spawn_position: Vector3
var _spawn_yaw := 0.0
var _spawn_loadout := ""
var medkits := 0
var _stored: Dictionary[String, Vector2i] = {}
var _switch_pending := false

var crouched := false
var aiming := false

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
var _prev_pos := Vector3.ZERO
var _visual_velocity := Vector3.ZERO
var _visual_vertical := 0.0

@onready var _camera: Camera3D = $Camera3D
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var gun := $Camera3D/Weapon


func _ready() -> void:
	add_to_group("player")
	_standing_capsule = _collision.shape as CapsuleShape3D
	_collision.shape = _standing_capsule.duplicate()
	_prev_pos = global_position
	match slot:
		0: _spawn_yaw = deg_to_rad(-40.0)
		1: _spawn_yaw = deg_to_rad(140.0)
		_: _spawn_yaw = atan2(spawn_position.x, spawn_position.z)
	rotation.y = _spawn_yaw
	if _is_local():
		_camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_camera.current = false
		_build_bar()
	_build_operator()


func _is_local() -> bool:
	if not Net.active:
		return true
	return is_multiplayer_authority()


func _server_rules() -> bool:
	return not Net.active or multiplayer.is_server()


func take_damage(amount: int, killer_id: int = 0) -> void:
	if not _server_rules():
		return
	if _dead or amount <= 0 or _hurt_lock > 0.0:
		return
	_set_health(maxi(health - amount, 0), killer_id)


func restore_health(amount: int) -> void:
	if _server_rules() and control_enabled:
		_set_health(mini(MAX_HEALTH, health + amount), 0)


func _set_health(value: int, killer_id: int) -> void:
	health = value
	for peer in get_parent().match_peers():
		net_set_health.rpc_id(peer, health, killer_id)
	_commit(killer_id)


func equip(id: String) -> void:
	if not get_parent().allows_weapon(id):
		return
	_spawn_loadout = id
	_apply_equip(id)
	if _server_rules():
		_send_equipment(id)
	else:
		net_equip.rpc_id(1, id, "")


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
	_stored[id] = Vector2i(loaded, mini(ammo_capacity(id), stock_for(id).y + loose))
	_send_inventory()


func owns_weapon(id: String) -> bool:
	return weapon_id == id or stock_for(id).x >= 0


func stock_for(id: String) -> Vector2i:
	return gun.ammo_counts() if id == weapon_id else _stored.get(id, Vector2i(-1, 0))


func ammo_capacity(id: String) -> int:
	var base := int(Weapon.WEAPONS[id].reserve)
	return base * 3 if score_id() > 0 else base


func ammo_space(id: String) -> int:
	return ammo_capacity(id) - stock_for(id).y


func grant_ammo(id: String, amount: int) -> void:
	if not _server_rules() or not get_parent().allows_weapon(id):
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
	medkits += amount
	_send_inventory()


func inventory_stock() -> Dictionary[String, Vector2i]:
	var stock := _stored.duplicate()
	if weapon_id != "":
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
	if not control_enabled or not _stored.has(id) or _stored[id].x < 0:
		_send_inventory()
		return
	var stock := _stored[id]
	_stored.erase(id)
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
			net_inventory.rpc_id(peer, _stored, medkits)


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
	if peer != get_multiplayer_authority():
		if weapon_id != "":
			net_equip.rpc_id(peer, weapon_id, _spawn_loadout)
		net_set_health.rpc_id(peer, health, 0)


func network_pose() -> PackedFloat32Array:
	return PackedFloat32Array([
		position.x, position.y, position.z, rotation.y, _camera.rotation.x, float(crouched), float(aiming),
	])


func apply_network_pose(pose: PackedFloat32Array) -> void:
	position = Vector3(pose[0], pose[1], pose[2])
	rotation.y = pose[3]
	_camera.rotation.x = pose[4]
	crouched = pose[5] > 0.0
	aiming = pose[6] > 0.0


func set_weapon_grips(right: Marker3D, left: Marker3D) -> void:
	_pose.right_wrist = right
	_pose.left_wrist = left


func set_support_grip(reload_blend: float) -> void:
	_pose.support_grip = reload_blend


func weapon_reach_correction() -> Vector3:
	return _pose.weapon_reach_correction()


func reload_pouch_position() -> Vector3:
	return _pouch.global_position


func shot_motion() -> Vector3:
	if _is_local():
		return velocity
	return (_visual_velocity + Vector3.UP * _visual_vertical).limit_length(SPRINT_SPEED + JUMP_VELOCITY)


func visual_speed() -> float:
	return _visual_velocity.length()


@rpc("any_peer", "reliable")
func net_set_health(value: int, killer_id: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	health = value
	_commit(killer_id)


@rpc("any_peer", "reliable")
func net_equip(id: String, loadout: String = "") -> void:
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		if not _is_owner_request(sender):
			return
		if weapon_id == "" and not _dead and get_parent().allows_weapon(id):
			_spawn_loadout = id
			_apply_equip(id)
			_send_equipment(id)
	elif sender == 1:
		_spawn_loadout = loadout
		_apply_equip(id)


@rpc("any_peer", "reliable")
func net_respawn(id: String) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_apply_respawn(id)


@rpc("any_peer", "reliable")
func net_active_weapon(id: String, magazine: int, reserve: int, switching: bool, loadout: String) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_spawn_loadout = loadout
		_apply_equip(id, magazine, reserve, switching)


@rpc("any_peer", "reliable")
func net_switch_weapon(id: String) -> void:
	if _is_owner_request(multiplayer.get_remote_sender_id()):
		_switch_weapon(id)


@rpc("any_peer", "reliable")
func net_use_medkit() -> void:
	if _is_owner_request(multiplayer.get_remote_sender_id()):
		_consume_medkit()


@rpc("any_peer", "reliable")
func net_inventory(stock: Dictionary[String, Vector2i], kits: int) -> void:
	if multiplayer.get_remote_sender_id() == 1 and _is_local():
		_stored = stock
		medkits = kits
		_switch_pending = false
		inventory_changed.emit()


@rpc("any_peer", "reliable")
func net_loot_ammo(id: String, amount: int) -> void:
	if multiplayer.get_remote_sender_id() == 1 and weapon_id == id:
		gun.add_reserve(amount)


func _apply_equip(id: String, magazine: int = -1, reserve: int = -1, switching: bool = false) -> void:
	if not get_parent().allows_weapon(id):
		return
	weapon_id = id
	control_enabled = true
	_switch_pending = false
	gun.equip(id, magazine, reserve, switching)
	if _is_local() and not get_parent().input_blocked():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _commit(killer_id: int) -> void:
	health_changed.emit(health, MAX_HEALTH)
	_refresh_bar()
	if health > 0 or _dead:
		return
	_dead = true
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
		_respawn_timer = get_tree().create_timer(_respawn_delay(), false)
		_respawn_timer.timeout.connect(_request_respawn)
	_clear_inventory()
	inventory_changed.emit()


func _clear_inventory() -> void:
	_stored.clear()
	medkits = 0
	_switch_pending = false


func _request_respawn() -> void:
	_respawn_timer = null
	var id := _next_respawn_weapon()
	for peer in get_parent().match_peers():
		net_respawn.rpc_id(peer, id)
	_apply_respawn(id)


func _next_respawn_weapon() -> String:
	return _spawn_loadout


func _respawn_delay() -> float:
	return 2.2


func restart_round() -> void:
	if _respawn_timer and _respawn_timer.timeout.is_connected(_request_respawn):
		_respawn_timer.timeout.disconnect(_request_respawn)
	_respawn_timer = null
	_apply_respawn(_spawn_loadout)
	_recoil_pitch = 0.0
	_jump_held = Input.is_action_pressed(&"jump")


func _apply_respawn(id: String) -> void:
	_clear_inventory()
	global_position = spawn_position
	velocity = Vector3.ZERO
	rotation.y = _spawn_yaw
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
	if _is_local():
		respawned.emit()
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
	rotate_y(deg_to_rad(yaw_deg))
	_camera.rotation.x = clampf(_camera.rotation.x + pitch, deg_to_rad(-80.0), deg_to_rad(80.0))
	_recoil_pitch += pitch


func _process(delta: float) -> void:
	if _server_rules():
		_hurt_lock = maxf(_hurt_lock - delta, 0.0)
	if _is_local():
		_recover_recoil(delta)
	_update_operator(delta)


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
	var selection := GameSettings.weapon_selection(event)
	if selection != "":
		select_weapon(selection)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"use_medkit"):
		use_medkit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"interact"):
		get_parent().get_node("Loot").interact(self)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"fire"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := MOUSE_SENS * GameSettings.sensitivity * lerpf(1.0, 0.55, $Camera3D/Weapon.aim_blend())
		var pitch_sign := 1.0 if GameSettings.invert_y else -1.0
		rotate_y(-event.relative.x * sensitivity)
		_camera.rotate_x(event.relative.y * sensitivity * pitch_sign)
		_camera.rotation.x = clampf(_camera.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))


func accepts_gameplay_input() -> bool:
	return control_enabled and not get_parent().input_blocked()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not _is_local():
		_update_capsule()
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
		return
	var accepts_input := accepts_gameplay_input()
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
		return

	var vertical := velocity.y
	if not is_on_floor():
		vertical += get_gravity().y * delta
	var jump_held := Input.is_action_pressed(&"jump")
	if jump_held and not _jump_held and is_on_floor() and not crouched:
		vertical = JUMP_VELOCITY
	_jump_held = jump_held

	var wish := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var speed := WALK_SPEED
	if crouched:
		speed = CROUCH_SPEED
	elif aiming:
		speed = AIM_SPEED
	elif Input.is_action_pressed(&"sprint"):
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

	_avatar.find_child("Object_111", true, false).hide()
	if _is_local():
		for mesh_name in ["Object_97", "Object_99", "Object_109"]:
			var mesh := _avatar.find_child(mesh_name, true, false) as MeshInstance3D
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		eyes.hide()


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
	_pose.grounded = is_on_floor() if _is_local() else absf(vertical_speed) < 0.8
	_pose.aim_pitch = clampf(_camera.rotation.x, -0.78, 0.78)
	_crouch_blend = move_toward(_crouch_blend, float(crouched), delta * 7.5)
	var stance := Vector3(0.0, -CROUCH_DROP, 0.05) * smoothstep(0.0, 1.0, _crouch_blend)
	_pose.stance_offset = stance
	_camera.position = _head_pivot + (_eye_rest - _head_pivot).rotated(Vector3.RIGHT, _pose.aim_pitch) + stance
	_pouch.position = _pouch_rest + stance
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
