extends CharacterBody3D

const MAX_HEALTH := 100
const MOVE_SPEED := 3.3
const SHOOT_DAMAGE := 14
const SHOOT_RANGE := 26.0
const SHOT_STATS := {"range": SHOOT_RANGE, "damage": SHOOT_DAMAGE, "damage_min": SHOOT_DAMAGE,
	"falloff_start": 0.0, "falloff_end": SHOOT_RANGE}
const PREFER_DISTANCE := 7.0
const SPAWN_POSITION := Vector3(12.0, 0.2, -12.0)

const WAYPOINTS := [
	Vector3(12.0, 0.2, -10.0),
	Vector3(8.0, 0.2, 8.0),
	Vector3(-2.0, 0.2, 12.0),
	Vector3(-8.0, 0.2, -6.0),
	Vector3(2.0, 0.2, -4.0),
]

var health := MAX_HEALTH
var defeated := false

var _dead := false
var _respawn_timer: SceneTreeTimer
var _sim := false
var _hurt_lock := 0.0
var _shoot_wait := 0.8
var _lost_sight := 0.0
var _waypoint := 0
var _avatar: Node3D
var _skeleton: Skeleton3D
var _anim: AnimationPlayer
var _clip := ""
var _meshes: Array[MeshInstance3D] = []
var _follow_head: Array[Node3D] = []
var _bar_fill: MeshInstance3D
var _bar_mat: StandardMaterial3D
var _bar_root: Node3D
var _flash_mat: StandardMaterial3D
var _flash_left := 0.0
var _flash_on := false
var _muzzle: Marker3D

@onready var _ballistics := get_node("../Ballistics")
var _remote_prev := Vector3.ZERO
var _remote_slide := 0.0


func _ready() -> void:
	add_to_group("bot")
	_build_body()
	_build_health_bar()
	_remote_prev = global_position
	set_physics_process(false)


func begin(simulate: bool) -> void:
	_sim = simulate
	set_physics_process(simulate)
	if Net.active:
		_ensure_sync()


func take_damage(amount: int, killer_id: int = 0) -> void:
	if not _sim or _dead or amount <= 0 or _hurt_lock > 0.0:
		return
	health = maxi(health - amount, 0)
	_flash_left = 0.08
	_refresh_bar()
	if health == 0:
		_die(killer_id)


func _physics_process(delta: float) -> void:
	_hurt_lock = maxf(_hurt_lock - delta, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)
	_update_flash()
	_face_bar()
	if _dead:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y += get_gravity().y * delta
		move_and_slide()
		return

	var player: Node = _nearest_player()
	var engaged := _can_fight(player) and _has_line_of_sight(player)
	if engaged:
		_lost_sight = 0.0
	else:
		_lost_sight += delta
	var chasing: bool = engaged or (_lost_sight < 1.6 and player != null and player.health > 0 and player.control_enabled)

	var wish := Vector3.ZERO
	if chasing:
		var to_player: Vector3 = player.global_position - global_position
		to_player.y = 0.0
		var distance: float = to_player.length()
		if distance > PREFER_DISTANCE + 1.2:
			wish = to_player.normalized()
		elif distance < PREFER_DISTANCE - 1.5:
			wish = -to_player.normalized()
		_face(to_player)
		_shoot_wait -= delta
		if engaged and _shoot_wait <= 0.0:
			_shoot_at(player)
			_shoot_wait = randf_range(0.85, 1.35)
	else:
		wish = _wander_direction()
		_face(wish)

	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	else:
		velocity.y = 0.0
	velocity.x = wish.x * MOVE_SPEED
	velocity.z = wish.z * MOVE_SPEED
	move_and_slide()
	var facing := Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z)
	_update_anim(wish.length_squared() > 0.04, wish.dot(facing))


func _can_fight(player: Node) -> bool:
	if player == null or not player.control_enabled or player.health <= 0:
		return false
	return global_position.distance_to(player.global_position) <= SHOOT_RANGE


func _has_line_of_sight(player: Node) -> bool:
	var from := global_position + Vector3(0.0, 1.45, 0.0)
	var to: Vector3 = player.global_position + Vector3(0.0, 1.2, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit["collider"] == player


func _shoot_at(player: Node) -> void:
	if not _muzzle:
		return
	var muzzle := _muzzle.global_transform
	var aim: Vector3 = (player.global_position + Vector3(0.0, 1.15, 0.0) - muzzle.origin).normalized()
	var spread := deg_to_rad(randf_range(3.5, 8.0))
	if randf() < 0.22:
		spread = deg_to_rad(randf_range(11.0, 18.0))
	var basis := Basis.looking_at(aim)
	var cone := tan(spread)
	var direction := (basis * Vector3(randf_range(-cone, cone), randf_range(-cone, cone), -1.0).normalized()).normalized()
	_ballistics.queue_shot("deagle", SHOT_STATS, self, 0, muzzle, 0.15,
		PackedVector3Array([direction]), velocity)
	_play_shot_fx()
	if Net.active and multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		net_shot_fx.rpc()


func _play_shot_fx() -> void:
	if _muzzle:
		_ballistics.muzzle_effect("deagle", _muzzle.global_transform, velocity, true)
	if _clip != "Jog_Fwd":
		_clip = ""
		_play_clip("Pistol_Shoot")


func _wander_direction() -> Vector3:
	var target: Vector3 = WAYPOINTS[_waypoint]
	var offset: Vector3 = target - global_position
	offset.y = 0.0
	if offset.length() < 1.3:
		_waypoint = (_waypoint + 1) % WAYPOINTS.size()
		target = WAYPOINTS[_waypoint]
		offset = target - global_position
		offset.y = 0.0
	if offset.length_squared() < 0.01:
		return Vector3.ZERO
	return offset.normalized()


func _face(direction: Vector3) -> void:
	if direction.length_squared() < 0.001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 0.18)


func _die(killer_id: int) -> void:
	_dead = true
	defeated = true
	collision_layer = 0
	collision_mask = 0
	_avatar.visible = false
	_bar_root.visible = false
	get_parent().announce(killer_id, 0)
	_respawn_timer = get_tree().create_timer(3.5, false)
	_respawn_timer.timeout.connect(_respawn)


func restart_round() -> void:
	if _respawn_timer and _respawn_timer.timeout.is_connected(_respawn):
		_respawn_timer.timeout.disconnect(_respawn)
	_respawn()
	_shoot_wait = 0.8
	_waypoint = 0
	_flash_left = 0.0
	_update_flash()
	_remote_prev = global_position
	_remote_slide = 0.0


func _respawn() -> void:
	_respawn_timer = null
	global_position = SPAWN_POSITION
	velocity = Vector3.ZERO
	health = MAX_HEALTH
	_dead = false
	defeated = false
	_hurt_lock = 1.2
	_lost_sight = 99.0
	collision_layer = 1
	collision_mask = 1
	_avatar.visible = true
	_bar_root.visible = true
	_clip = ""
	_play_clip("Pistol_Idle")
	_refresh_bar()


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.75
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)

	_avatar = Node3D.new()
	_avatar.rotation.y = PI
	add_child(_avatar)
	_add_model("res://characters/male/Superhero_Male_FullBody.gltf", false)
	_add_model("res://characters/male/Hair_SimpleParted.gltf", true)
	_add_model("res://characters/male/Eyebrows_Regular.gltf", true)
	_add_model("res://characters/male/Hair_Beard.gltf", true)
	_skeleton = _avatar.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton:
		_skeleton.reset_bone_poses()
		_pin_to_head()
		_attach_pistol()
		_setup_anims()
		_play_clip("Pistol_Idle")
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_color = Color(1, 1, 1, 0.45)


func _add_model(path: String, follows_head: bool) -> void:
	var packed: PackedScene = load(path)
	var model := packed.instantiate() as Node3D
	_avatar.add_child(model)
	if follows_head:
		_follow_head.append(model)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mesh)


func _pin_to_head() -> void:
	var bone := _skeleton.find_bone("Head")
	if bone < 0 or _follow_head.is_empty():
		return
	var head_global: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_rest(bone)
	var attach := BoneAttachment3D.new()
	attach.bone_name = "Head"
	_skeleton.add_child(attach)
	for node in _follow_head:
		var keep: Transform3D = node.global_transform
		node.reparent(attach)
		node.transform = head_global.affine_inverse() * keep


func _attach_pistol() -> void:
	var attach := BoneAttachment3D.new()
	attach.name = "GunAttach"
	attach.bone_name = "hand_r"
	_skeleton.add_child(attach)
	var packed: PackedScene = load("res://models/pistol.glb")
	var gun := packed.instantiate() as Node3D
	gun.name = "Gun"
	attach.add_child(gun)
	gun.rotation = Vector3(-0.35, PI, -PI / 2.0)
	gun.position = Vector3(0.0, 0.1, 0.02)
	gun.scale = Vector3(0.9, 0.9, 0.9)
	_muzzle = Marker3D.new()
	_muzzle.position = Vector3(0.0, 0.1575, 0.112)
	_muzzle.rotation.y = PI
	gun.add_child(_muzzle)


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
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	var library := AnimationLibrary.new()
	var skeleton_path := str(holder.get_path_to(_skeleton))
	for clip in ["Jog_Fwd", "Pistol_Idle", "Pistol_Shoot"]:
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


func _update_anim(moving: bool, forward_dot: float) -> void:
	if _anim == null or _dead or _clip == "Pistol_Shoot":
		return
	_play_clip("Jog_Fwd" if moving else "Pistol_Idle")
	if _clip == "Jog_Fwd":
		_anim.speed_scale = -1.0 if forward_dot < -0.25 else 1.0
	else:
		_anim.speed_scale = 1.0


func _on_anim_finished(anim_name: StringName) -> void:
	if anim_name == "Pistol_Shoot" and not _dead:
		_clip = ""
		_play_clip("Pistol_Idle")


func _update_flash() -> void:
	var on := _flash_left > 0.0
	if on == _flash_on:
		return
	_flash_on = on
	for mesh in _meshes:
		mesh.material_overlay = _flash_mat if on else null


func _build_health_bar() -> void:
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
	_bar_mat.albedo_color = Color(0.2, 0.75, 0.25)
	fill_mesh.material = _bar_mat
	_bar_fill.mesh = fill_mesh
	_bar_fill.position.z = 0.01
	_bar_root.add_child(_bar_fill)
	_refresh_bar()


func _refresh_bar() -> void:
	var ratio := clampf(float(health) / float(MAX_HEALTH), 0.0, 1.0)
	_bar_fill.scale.x = maxf(ratio, 0.001)
	_bar_fill.position.x = -0.32 * (1.0 - ratio)
	_bar_mat.albedo_color = Color(lerpf(0.85, 0.2, ratio), lerpf(0.16, 0.75, ratio), 0.18)


func _process(delta: float) -> void:
	if _sim:
		return
	_flash_left = maxf(_flash_left - delta, 0.0)
	_update_flash()
	_face_bar()
	_refresh_bar()
	if _avatar:
		_avatar.visible = not defeated
	if _bar_root:
		_bar_root.visible = not defeated
	collision_layer = 0 if defeated else 1
	collision_mask = 0 if defeated else 1
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
	_follow_remote(delta)


func _nearest_player() -> Node:
	var best: Node = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("player"):
		if node.health <= 0 or not node.control_enabled:
			continue
		var distance: float = global_position.distance_to(node.global_position)
		if distance < best_distance:
			best = node
			best_distance = distance
	return best


func _ensure_sync() -> void:
	if has_node("Sync"):
		return
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.root_path = NodePath("..")
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	config.add_property(NodePath(".:health"))
	config.add_property(NodePath(".:defeated"))
	sync.replication_config = config
	sync.replication_interval = 0.0
	sync.public_visibility = false
	add_child(sync)
	sync.set_multiplayer_authority(1)


@rpc("authority", "call_remote", "unreliable")
func net_shot_fx() -> void:
	_play_shot_fx()


func _follow_remote(delta: float) -> void:
	var step := global_position - _remote_prev
	_remote_prev = global_position
	var instant := Vector2(step.x, step.z).length() / maxf(delta, 0.001)
	_remote_slide = lerpf(_remote_slide, instant, minf(1.0, delta * 8.0))
	var facing := Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z)
	var dot := 1.0
	if Vector2(step.x, step.z).length() > 0.001:
		dot = Vector3(step.x, 0.0, step.z).normalized().dot(facing)
	_update_anim(_remote_slide > 0.8, dot)


func _face_bar() -> void:
	if _bar_root == null or not _bar_root.visible:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_bar_root.look_at(camera.global_position, Vector3.UP)
	_bar_root.rotate_y(PI)
