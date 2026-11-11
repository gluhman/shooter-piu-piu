extends CharacterBody3D

const WALK_SPEED := 5.0
const SPRINT_SPEED := 7.4
const JUMP_VELOCITY := 4.6
const MOUSE_SENS := 0.0022
const MAX_HEALTH := 100
const AK47_MODEL := preload("res://assets/ak47/ak47.tscn")

signal health_changed(current: int, maximum: int)
signal respawned

var control_enabled := false
var health := MAX_HEALTH
var weapon_id := ""

var _jump_held := false
var _recoil_pitch := 0.0
var _dead := false
var _hurt_lock := 0.0
var _avatar: Node3D
var _skeleton: Skeleton3D
var _anim: AnimationPlayer
var _clip := ""
var _gun_attach: BoneAttachment3D
var _bar_root: Node3D
var _bar_fill: MeshInstance3D
var _bar_mat: StandardMaterial3D
var _prev_pos := Vector3.ZERO
var _slide := 0.0
var _forward_dot := 1.0

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
		$Camera3D/Weapon.set_process(false)
		_build_puppet()


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


func play_shot_anim() -> void:
	if _avatar == null or _dead:
		return
	_clip = ""
	_play_clip("Pistol_Shoot")


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
	if _is_local():
		$Camera3D/Weapon.equip(id)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_set_puppet_weapon(id)
		_play_clip("Pistol_Idle")


func _commit(killer_id: int) -> void:
	health_changed.emit(health, MAX_HEALTH)
	_refresh_bar()
	if health > 0 or _dead:
		return
	_dead = true
	control_enabled = false
	velocity = Vector3.ZERO
	if _avatar:
		_avatar.visible = false
	if _bar_root:
		_bar_root.visible = false
	if _server_rules():
		get_parent().announce(killer_id, get_multiplayer_authority())
		get_tree().create_timer(2.2).timeout.connect(_request_respawn)


func _request_respawn() -> void:
	if Net.active:
		if multiplayer.is_server():
			net_respawn.rpc()
	else:
		_apply_respawn()


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
	_play_clip("Pistol_Idle" if weapon_id != "" else "Idle")


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
	else:
		_animate_puppet(delta)


func _recover_recoil(delta: float) -> void:
	if absf(_recoil_pitch) < 0.0001:
		_recoil_pitch = 0.0
		return
	var step := _recoil_pitch * minf(1.0, delta * 10.0)
	_recoil_pitch -= step
	_camera.rotation.x = clampf(_camera.rotation.x - step, deg_to_rad(-80.0), deg_to_rad(80.0))


func _unhandled_input(event: InputEvent) -> void:
	if not _is_local() or not control_enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		_camera.rotate_x(-event.relative.y * MOUSE_SENS)
		_camera.rotation.x = clampf(_camera.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))


func _physics_process(delta: float) -> void:
	if not _is_local():
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
		return
	if not control_enabled:
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
	var jump_held := Input.is_physical_key_pressed(KEY_SPACE)
	if jump_held and not _jump_held and is_on_floor():
		vertical = JUMP_VELOCITY
	_jump_held = jump_held

	var wish := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	var speed := SPRINT_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
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


func _build_puppet() -> void:
	_avatar = Node3D.new()
	_avatar.rotation.y = PI
	add_child(_avatar)
	_add_puppet_model("res://characters/male/Superhero_Male_FullBody.gltf", false)
	_add_puppet_model("res://characters/male/Hair_SimpleParted.gltf", true)
	_add_puppet_model("res://characters/male/Eyebrows_Regular.gltf", true)
	_add_puppet_model("res://characters/male/Hair_Beard.gltf", true)
	_skeleton = _avatar.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton:
		_skeleton.reset_bone_poses()
		_pin_hair()
		_prepare_hand()
		_setup_anims()
		_play_clip("Idle")
	_build_bar()


func _add_puppet_model(path: String, follows_head: bool) -> void:
	var packed: PackedScene = load(path)
	var model := packed.instantiate() as Node3D
	_avatar.add_child(model)
	if follows_head:
		model.set_meta("follows_head", true)


func _pin_hair() -> void:
	var bone := _skeleton.find_bone("Head")
	if bone < 0:
		return
	var head_global: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_rest(bone)
	var attach := BoneAttachment3D.new()
	attach.bone_name = "Head"
	_skeleton.add_child(attach)
	for node in _avatar.get_children():
		if not node.has_meta("follows_head"):
			continue
		var keep: Transform3D = node.global_transform
		node.reparent(attach)
		node.transform = head_global.affine_inverse() * keep


func _prepare_hand() -> void:
	_gun_attach = BoneAttachment3D.new()
	_gun_attach.name = "GunAttach"
	_gun_attach.bone_name = "hand_r"
	_skeleton.add_child(_gun_attach)


func _set_puppet_weapon(id: String) -> void:
	if _gun_attach == null:
		return
	for child in _gun_attach.get_children():
		child.queue_free()
	if id == "shotgun":
		var holder := Node3D.new()
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = load("res://drob/Shotgun.obj")
		var material := StandardMaterial3D.new()
		material.albedo_texture = load("res://drob/Sg_Diffuse.png")
		material.roughness = 0.45
		material.metallic = 0.6
		mesh_instance.material_override = material
		holder.add_child(mesh_instance)
		_gun_attach.add_child(holder)
		holder.rotation = Vector3(0.15, -PI / 2.0, 0.5)
		holder.position = Vector3(0.02, 0.06, 0.04)
		holder.scale = Vector3(0.5, 0.5, 0.5)
	elif id == "ak47":
		var gun := AK47_MODEL.instantiate() as Node3D
		_gun_attach.add_child(gun)
		# Align the rifle's grip and forward axis with the avatar's pistol pose.
		gun.rotation = Vector3(1.05, -2.65, 3.09)
	else:
		var packed: PackedScene = load("res://models/pistol.glb")
		var gun := packed.instantiate() as Node3D
		_gun_attach.add_child(gun)
		gun.rotation = Vector3(-0.35, PI, -PI / 2.0)
		gun.position = Vector3(0.0, 0.1, 0.02)
		gun.scale = Vector3(0.9, 0.9, 0.9)


func _setup_anims() -> void:
	var packed: PackedScene = load("res://characters/anim/UAL1_Standard.glb")
	var library_root := packed.instantiate()
	var source := library_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source == null:
		library_root.queue_free()
		return
	var holder := _skeleton.get_parent()
	_anim = AnimationPlayer.new()
	holder.add_child(_anim)
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	var library := AnimationLibrary.new()
	var skeleton_path := str(holder.get_path_to(_skeleton))
	for clip in ["Idle", "Jog_Fwd", "Pistol_Idle", "Pistol_Shoot"]:
		if not source.has_animation(clip):
			continue
		var animation := source.get_animation(clip).duplicate() as Animation
		_remap_tracks(animation, skeleton_path)
		if clip != "Pistol_Shoot":
			animation.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(clip, animation)
	_anim.add_animation_library("", library)
	_anim.animation_finished.connect(_on_anim_finished)
	library_root.queue_free()


func _remap_tracks(animation: Animation, skeleton_path: String) -> void:
	var index := 0
	while index < animation.get_track_count():
		var path := str(animation.track_get_path(index))
		var bone := path.get_slice(":", path.get_slice_count(":") - 1)
		var track_type := animation.track_get_type(index)
		if bone == "root" and track_type == Animation.TYPE_POSITION_3D:
			animation.remove_track(index)
			continue
		if track_type == Animation.TYPE_SCALE_3D:
			animation.remove_track(index)
			continue
		animation.track_set_path(index, NodePath("%s:%s" % [skeleton_path, bone]))
		index += 1


func _play_clip(clip: String) -> void:
	if _anim == null or _clip == clip or not _anim.has_animation(clip):
		return
	_clip = clip
	_anim.play(clip)


func _on_anim_finished(anim_name: StringName) -> void:
	if anim_name == "Pistol_Shoot" and not _dead:
		_clip = ""
		_play_clip("Pistol_Idle" if weapon_id != "" else "Idle")


func _animate_puppet(delta: float) -> void:
	if _avatar:
		_avatar.visible = not _dead
	if _bar_root:
		_bar_root.visible = not _dead
		_face_bar()
	if _dead or _anim == null:
		_prev_pos = global_position
		return
	var step := global_position - _prev_pos
	_prev_pos = global_position
	var instant := Vector2(step.x, step.z).length() / maxf(delta, 0.001)
	_slide = lerpf(_slide, instant, minf(1.0, delta * 8.0))
	if Vector2(step.x, step.z).length() > 0.001:
		var facing := Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z)
		_forward_dot = Vector3(step.x, 0.0, step.z).normalized().dot(facing)
	if _clip == "Pistol_Shoot":
		return
	var moving := _slide > 0.8
	_play_clip("Jog_Fwd" if moving else ("Pistol_Idle" if weapon_id != "" else "Idle"))
	if _clip == "Jog_Fwd":
		_anim.speed_scale = -1.0 if _forward_dot < -0.25 else 1.0
	else:
		_anim.speed_scale = 1.0


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
