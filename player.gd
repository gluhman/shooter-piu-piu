extends CharacterBody3D

const WALK_SPEED := 5.0
const SPRINT_SPEED := 7.4
const JUMP_VELOCITY := 4.6
const MOUSE_SENS := 0.0022
const MAX_HEALTH := 100
const OperatorPose := preload("res://operator_pose.gd")

const FABRIC_TEXTURES := {
	"Mil_Suit_R5": [
		preload("res://assets/operator/textures/uniform_albedo.jpg"),
		preload("res://assets/operator/textures/uniform_normal.webp"),
	],
	"Mil_Suit_R5__Plate": [
		preload("res://assets/operator/textures/vest_albedo.jpg"),
		preload("res://assets/operator/textures/vest_normal.webp"),
	],
	"Mil_Suit_R5_Puches": [
		preload("res://assets/operator/textures/pouches_albedo.jpg"),
		preload("res://assets/operator/textures/pouches_normal.webp"),
	],
}

signal health_changed(current: int, maximum: int)
signal respawned

var control_enabled := false
var health := MAX_HEALTH
var weapon_id := ""

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

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	add_to_group("player")
	_prev_pos = global_position
	if get_multiplayer_authority() == 1:
		rotation.y = deg_to_rad(-40.0)
	else:
		rotation.y = deg_to_rad(140.0)
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
	health = maxi(health - amount, 0)
	if Net.active:
		net_set_health.rpc(health, killer_id)
	else:
		_commit(killer_id)


func equip(id: String) -> void:
	if Net.active:
		net_equip.rpc(id)
	else:
		_apply_equip(id)


func send_weapon_to(peer: int) -> void:
	if weapon_id == "":
		return
	net_equip.rpc_id(peer, weapon_id)


func set_weapon_grips(right: Marker3D, left: Marker3D) -> void:
	_pose.right_wrist = right
	_pose.left_wrist = left


func set_support_grip(reload_blend: float) -> void:
	_pose.support_grip = reload_blend


func weapon_reach_correction() -> Vector3:
	return _pose.weapon_reach_correction()


func reload_pouch_position() -> Vector3:
	return _pouch.global_position


func visual_speed() -> float:
	return _visual_velocity.length()


@rpc("any_peer", "call_local", "reliable")
func net_set_health(value: int, killer_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	health = value
	_commit(killer_id)


@rpc("authority", "call_local", "reliable")
func net_equip(id: String) -> void:
	_apply_equip(id)


@rpc("any_peer", "call_local", "reliable")
func net_respawn() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	_apply_respawn()


func _apply_equip(id: String) -> void:
	weapon_id = id
	control_enabled = true
	$Camera3D/Weapon.equip(id)
	if _is_local():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _commit(killer_id: int) -> void:
	health_changed.emit(health, MAX_HEALTH)
	_refresh_bar()
	if health > 0 or _dead:
		return
	_dead = true
	control_enabled = false
	$Camera3D/Weapon.cancel_reload()
	$Camera3D/Weapon.visible = false
	velocity = Vector3.ZERO
	if _avatar:
		_avatar.visible = false
	if _bar_root:
		_bar_root.visible = false
	if _server_rules():
		get_parent().announce(killer_id, get_multiplayer_authority())
		_respawn_timer = get_tree().create_timer(2.2, false)
		_respawn_timer.timeout.connect(_request_respawn)


func _request_respawn() -> void:
	_respawn_timer = null
	if Net.active:
		if multiplayer.is_server():
			net_respawn.rpc()
	else:
		_apply_respawn()


func restart_round() -> void:
	if _respawn_timer and _respawn_timer.timeout.is_connected(_request_respawn):
		_respawn_timer.timeout.disconnect(_request_respawn)
	_respawn_timer = null
	_apply_respawn()
	_recoil_pitch = 0.0
	_jump_held = Input.is_action_pressed(&"jump")
	$Camera3D/Weapon.restart_round()


func _apply_respawn() -> void:
	var peer := get_multiplayer_authority()
	global_position = Vector3(-14.6, 0.2, 14.2) if peer == 1 else Vector3(14.2, 0.2, -14.2)
	velocity = Vector3.ZERO
	rotation.y = deg_to_rad(-40.0) if peer == 1 else deg_to_rad(140.0)
	health = MAX_HEALTH
	_dead = false
	_hurt_lock = 1.0
	control_enabled = weapon_id != ""
	_prev_pos = global_position
	if _is_local():
		_camera.rotation.x = 0.0
		respawned.emit()
	if _avatar:
		_avatar.visible = true
	if _bar_root:
		_bar_root.visible = true
	health_changed.emit(health, MAX_HEALTH)
	_refresh_bar()
	$Camera3D/Weapon.visible = true


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
	if event.is_action_pressed(&"fire"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := MOUSE_SENS * GameSettings.sensitivity
		var pitch_sign := 1.0 if GameSettings.invert_y else -1.0
		rotate_y(-event.relative.x * sensitivity)
		_camera.rotate_x(event.relative.y * sensitivity * pitch_sign)
		_camera.rotation.x = clampf(_camera.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))


func accepts_gameplay_input() -> bool:
	return control_enabled and not get_parent().input_blocked()


func _physics_process(delta: float) -> void:
	if not _is_local():
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
		return
	if not accepts_gameplay_input():
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
	if jump_held and not _jump_held and is_on_floor():
		vertical = JUMP_VELOCITY
	_jump_held = jump_held

	var wish := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var speed := SPRINT_SPEED if Input.is_action_pressed(&"sprint") else WALK_SPEED
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


func _build_operator() -> void:
	_avatar = OperatorPose.MODEL.instantiate() as Node3D
	_avatar.name = "Operator"
	_avatar.rotation.y = PI
	_avatar.scale = Vector3.ONE * 0.96
	_avatar.position = Vector3(0.169, 0.0, -0.041)
	add_child(_avatar)
	_apply_operator_textures()
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
	_pouch.position = Vector3(-0.115, 1.31, -0.19)
	add_child(_pouch)

	_avatar.find_child("Object_111", true, false).hide()
	if _is_local():
		for mesh_name in ["Object_97", "Object_99", "Object_109"]:
			var mesh := _avatar.find_child(mesh_name, true, false) as MeshInstance3D
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		eyes.hide()


func _apply_operator_textures() -> void:
	var upgraded: Dictionary = {}
	for mesh: MeshInstance3D in _avatar.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.get_active_material(surface) as BaseMaterial3D
			if original == null or not FABRIC_TEXTURES.has(original.resource_name):
				continue
			var name := original.resource_name
			if not upgraded.has(name):
				var material := original.duplicate() as BaseMaterial3D
				material.albedo_texture = FABRIC_TEXTURES[name][0]
				material.normal_texture = FABRIC_TEXTURES[name][1]
				material.normal_enabled = true
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				upgraded[name] = material
			mesh.set_surface_override_material(surface, upgraded[name])


func _update_operator(delta: float) -> void:
	if _bar_root and not _dead:
		_face_bar()
	if _dead:
		_prev_pos = global_position
		return
	var step := global_position - _prev_pos
	_prev_pos = global_position
	var vertical_speed := step.y / maxf(delta, 0.001)
	step.y = 0.0
	var instant := step / maxf(delta, 0.001)
	_visual_velocity = _visual_velocity.lerp(instant, minf(1.0, delta * 12.0))
	_pose.planar_velocity = _visual_velocity
	_pose.grounded = is_on_floor() if _is_local() else absf(vertical_speed) < 0.8
	_pose.aim_pitch = clampf(_camera.rotation.x, -0.78, 0.78)
	_camera.position = _head_pivot + (_eye_rest - _head_pivot).rotated(Vector3.RIGHT, _pose.aim_pitch)


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
