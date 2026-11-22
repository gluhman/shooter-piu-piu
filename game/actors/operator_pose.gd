extends SkeletonModifier3D

signal pose_finished
@export var use_godotik_arms := true
var _arm_ik: SkeletonModifier3D
var _arm_effectors: Array[Node3D] = []
var _arm_poles: Array[Node] = []
const ArmPole := preload("res://addons/libik/script/pole_bone_constraint.gd")

const Balance := preload("res://game/combat/combat_balance.gd")
const WRISTWATCH := preload("res://assets/operator/watch/digital_wrist_watch_1k.gltf")
const VEST_MESH := "ArmorState"
const MODEL := preload("res://assets/operator/variants/operator_blue.glb")
const RED_MODEL := preload("res://assets/operator/variants/operator_red.glb")
const LOCOMOTION := preload("res://assets/animations/mesh2motion/operator_locomotion.res")
const FABRIC_TEXTURES := {
	"Mil_Suit_R5": [
		preload("res://assets/operator/textures/uniform_albedo.jpg"),
		preload("res://assets/operator/textures/uniform_normal.webp"),
		preload("res://assets/operator/textures/uniform_roughness.jpg"),
	],
	"Mil_Suit_R5__Plate": [
		preload("res://assets/operator/textures/vest_albedo.jpg"),
		preload("res://assets/operator/textures/vest_normal.webp"),
		preload("res://assets/operator/textures/vest_roughness.jpg"),
	],
	"Mil_Suit_R5_Puches": [
		preload("res://assets/operator/textures/pouches_albedo.jpg"),
		preload("res://assets/operator/textures/pouches_normal.webp"),
		preload("res://assets/operator/textures/pouches_roughness.jpg"),
	],
}

const HD_FABRIC_NORMAL := preload("res://assets/operator/textures/hd/fabric_pattern_05_nor_gl_4k.jpg")
const HD_FABRIC_ARM := preload("res://assets/operator/textures/hd/fabric_pattern_05_arm_4k.jpg")
const HD_FABRIC_COLOR := preload("res://assets/operator/textures/hd/fabric_pattern_05_col_01_4k.jpg")
const FABRIC_SHADER := preload("res://assets/operator/fabric.gdshader")
const SCARF_SHADER := preload("res://assets/operator/scarf.gdshader")
const SOLDIER_SHADER := preload("res://assets/operator/soldier.gdshader")
const HD_LEATHER_COLOR := preload("res://assets/operator/textures/hd/fabric_leather_02_diff_4k.jpg")
const HD_LEATHER_NORMAL := preload("res://assets/operator/textures/hd/fabric_leather_02_nor_gl_4k.jpg")
const HD_LEATHER_ARM := preload("res://assets/operator/textures/hd/fabric_leather_02_arm_4k.jpg")
const HD_LEATHER_HEIGHT := preload("res://assets/operator/textures/hd/fabric_leather_02_disp_4k.jpg")

const RIGHT_ARM := [&"upperarm_r", &"lowerarm_r", &"hand_r"]
const LEFT_ARM := [&"upperarm_l", &"lowerarm_l", &"hand_l"]
const RIGHT_LEG := [&"thigh_r", &"calf_r", &"foot_r", &"ball_r"]
const LEFT_LEG := [&"thigh_l", &"calf_l", &"foot_l", &"ball_l"]
const GAITS := [&"crouch_walk", &"walk", &"jog", &"sprint", &"walk_back", &"strafe_left", &"strafe_right"]
const ADS_SPINE_OFFSET := Vector3(0.0, -0.060, -0.015)
const ADS_TORSO_PITCH := -0.27
const ADS_NECK_PITCH := -0.16
const ADS_HEAD_PITCH := -0.08
const CROUCH_HIP_LIFT := 0.18
# Thumb, index, middle, ring, little; proximal / middle / distal joints.
# Values are offsets from the fitted bind pose, independent of locomotion fingers.
const FIREARM_FINGER_CURL := [[0.25, 0.60, 0.45], [0.35, 0.55, 0.25],
	[0.85, 1.20, 0.90], [0.90, 1.25, 0.95], [0.95, 1.25, 0.95]]
const KNIFE_FINGER_CURL := [[0.60, 0.90, 0.65], [0.95, 1.30, 0.95],
	[1.00, 1.35, 0.95], [1.05, 1.35, 1.00], [1.10, 1.30, 1.00]]
const KNIFE_SUPPORT_CURL := [[0.15, 0.20, 0.10], [0.18, 0.30, 0.20],
	[0.22, 0.32, 0.22], [0.28, 0.40, 0.25], [0.35, 0.45, 0.28]]
const SHOVEL_FINGER_CURL := [[0.24, 0.35, 0.30], [0.52, 0.79, 0.67],
	[0.64, 0.88, 0.76], [0.69, 0.93, 0.80], [0.73, 0.96, 0.83]]

var actor: Node3D
var right_wrist: Marker3D
var left_wrist: Marker3D
var right_palm: Marker3D
var left_palm: Marker3D
var knife_grip := false
var planar_velocity := Vector3.ZERO
var grounded := true
var lean := 0.0
var support_grip := 0.0
var shovel_grip := false
var shovel_lean := Vector2.ZERO
var mounted_grip := false
var shoulder_brace := 0.0
var eye_in_head := Vector3.ZERO
var stance_offset := Vector3.ZERO

var _right_arm: PackedInt32Array
var _left_arm: PackedInt32Array
var _legs: Array[PackedInt32Array]
var _foot_height: Array[float] = [0.0, 0.0]
var _floor_ray := PhysicsRayQueryParameters3D.new()
var _right_fingers: Array[PackedInt32Array]
var _left_fingers: Array[PackedInt32Array]
var _locomotion: AnimationPlayer
var _was_grounded := true
var _transition_left := 0.0
var _stride_yaw := 0.0
var _stride_weight := 0.0
var _neck := -1
var _head := -1
var _spine := -1
var _pelvis := -1
var _crouch_weight := 0.0
var _right_reach: Vector2
var _left_reach: Vector2
var _right_palm_frame: Basis
var _left_palm_frame: Basis
var _right_palm_offset: Vector3
var _left_palm_offset: Vector3
var aim_pitch := 0.0
var ads_weight := 0.0


func _ready() -> void:
	var skeleton := get_skeleton()
	modification_processed.connect(_on_local_pose_finished)
	_setup_arm_ik.call_deferred()
	_right_arm = _chain(skeleton, RIGHT_ARM)
	_left_arm = _chain(skeleton, LEFT_ARM)
	_legs = [_chain(skeleton, RIGHT_LEG), _chain(skeleton, LEFT_LEG)]
	_floor_ray.collision_mask = Balance.WORLD_MASK
	_right_fingers = _finger_chains(skeleton, "r")
	_left_fingers = _finger_chains(skeleton, "l")
	_right_palm_offset = skeleton.get_bone_rest(_right_fingers[2][0]).origin * 0.62
	_left_palm_offset = skeleton.get_bone_rest(_left_fingers[2][0]).origin * 0.62
	_right_palm_frame = _palm_frame(skeleton, true)
	_left_palm_frame = _palm_frame(skeleton, false)
	_neck = skeleton.find_bone(&"neck_01")
	_head = skeleton.find_bone(&"head")
	_spine = skeleton.find_bone(&"spine_01")
	_pelvis = skeleton.find_bone(&"pelvis")
	_right_reach = _arm_reach(skeleton, _right_arm)
	_left_reach = _arm_reach(skeleton, _left_arm)
	_locomotion = AnimationPlayer.new()
	_locomotion.root_node = NodePath("../..")
	_locomotion.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_locomotion.add_animation_library(&"", LOCOMOTION)
	add_child(_locomotion)
	reset_locomotion()


func reset_locomotion() -> void:
	_was_grounded = true
	_transition_left = 0.0
	_stride_yaw = 0.0
	_stride_weight = 0.0
	_foot_height.fill(0.0)
	_crouch_weight = 0.0
	_locomotion.stop()
	_locomotion.speed_scale = 1.0
	_locomotion.play(&"idle")
	_locomotion.advance(0.0)


func _setup_arm_ik() -> void:
	if not ClassDB.class_exists("GodotIK"):
		return
	_arm_ik = ClassDB.instantiate("GodotIK") as SkeletonModifier3D
	_arm_ik.name = "WeaponArmIK"
	_arm_ik.set("iteration_count", 16)
	_arm_ik.active = use_godotik_arms
	for side in ["r", "l"]:
		var effector := ClassDB.instantiate("GodotIKEffector") as Node3D
		effector.name = "WeaponHand_" + side
		effector.set("bone_name", "hand_" + side)
		effector.set("bone_idx", get_skeleton().find_bone("hand_" + side))
		effector.set("chain_length", 3)
		effector.set("transform_mode", 3) # FULL_TRANSFORM: retain the weapon's explicit hand basis.
		var constraint := ArmPole.new()
		constraint.bone_name = "lowerarm_" + side
		constraint.bone_idx = get_skeleton().find_bone("lowerarm_" + side)
		constraint.pole_direction = Vector3.DOWN
		effector.add_child(constraint)
		_arm_ik.add_child(effector)
		_arm_effectors.append(effector)
		_arm_poles.append(constraint)
	get_skeleton().add_child(_arm_ik)
	_arm_ik.modification_processed.connect(func() -> void: pose_finished.emit())


func _on_local_pose_finished() -> void:
	if not use_godotik_arms or not is_instance_valid(_arm_ik) or not _arm_ik.active:
		pose_finished.emit()


func update_locomotion(delta: float, crouched: bool, vertical_speed: float) -> void:
	_crouch_weight = move_toward(_crouch_weight, float(crouched and grounded), delta * 7.5)
	var speed := planar_velocity.length()
	var current := _locomotion.current_animation
	var was_moving := current in GAITS
	var clip: StringName = &"idle"
	var rate := 1.0
	var travel := actor.global_basis.inverse() * planar_velocity
	var moving_speed := 0.20 if was_moving else 0.38
	_transition_left = maxf(0.0, _transition_left - delta)
	if not grounded:
		if _was_grounded and vertical_speed > 1.0:
			_transition_left = 0.20
			clip = &"jump_start"
		else:
			clip = &"jump_start" if current == &"jump_start" and _transition_left > 0.0 else &"jump_air"
		rate = 4.0 if clip == &"jump_start" else 1.0
	elif crouched:
		clip = &"crouch_walk" if speed > moving_speed else &"crouch_idle"
		rate = clampf(speed / 1.65, 0.55, 1.65) if clip == &"crouch_walk" else 1.0
	elif speed > moving_speed:
		if speed > (5.9 if current == &"sprint" else 6.3) and travel.z < -speed * 0.55:
			clip = &"sprint"
			rate = clampf(speed / 6.4, 0.8, 1.35)
		elif speed > (3.25 if current == &"jog" else 3.65):
			clip = &"jog"
			rate = clampf(speed / 4.2, 0.8, 1.60)
		else:
			clip = &"walk"
			rate = clampf(speed / 2.35, 0.45, 1.5)
	var moving := clip in GAITS
	var stride_yaw := 0.0
	if moving:
		var heading := atan2(travel.x, -travel.z)
		stride_yaw = -heading
		if clip in [&"walk", &"jog"]:
			# Use real back/side steps; only rotate the residual diagonal stride.
			var source_heading := 0.0
			if absf(heading) > PI * 0.75:
				clip = &"walk_back"
				source_heading = PI
				rate = clampf(speed / 1.8, 0.5, 2.3)
			elif absf(heading) > PI * 0.25:
				clip = &"strafe_right" if heading > 0.0 else &"strafe_left"
				source_heading = signf(heading) * PI * 0.5
				rate = clampf(speed / 2.2, 0.5, 2.4)
			stride_yaw = -angle_difference(source_heading, heading)
	_stride_yaw = rotate_toward(_stride_yaw, stride_yaw, delta * 13.0)
	_stride_weight = move_toward(_stride_weight, float(moving), delta * 8.0)
	_was_grounded = grounded
	if current != clip:
		var phase := 0.0
		if moving and was_moving:
			phase = _locomotion.current_animation_position / _locomotion.current_animation_length
		var blend_time := 0.08 if clip == &"jump_start" else 0.15
		_locomotion.play(clip, blend_time)
		if phase > 0.0:
			_locomotion.seek(phase * _locomotion.get_animation(clip).length)
	_locomotion.speed_scale = rate
	_locomotion.advance(delta)


func weapon_carry_anchor() -> Vector3:
	return _animated_shoulder(_right_arm).lerp(_animated_shoulder(_left_arm), 0.5)


func weapon_palm_offset(right: bool) -> Vector3:
	var offset := _right_palm_offset if right else _left_palm_offset
	var skeleton := get_skeleton()
	var hand := _right_arm[2] if right else _left_arm[2]
	var frame := _right_palm_frame if right else _left_palm_frame
	return (frame.inverse() * offset) * (skeleton.global_basis * skeleton.get_bone_global_rest(hand).basis).get_scale().abs()


func weapon_reach_correction(two_handed: bool) -> Vector3:
	var right_shoulder := _animated_shoulder(_right_arm)
	if not two_handed:
		return _reach_offset(right_wrist.global_position, right_shoulder, _right_reach)
	var left_shoulder := _animated_shoulder(_left_arm)
	var correction := Vector3.ZERO
	for _pass_index in 6:
		correction += _reach_offset(left_wrist.global_position + correction, left_shoulder, _left_reach)
		correction += _reach_offset(right_wrist.global_position + correction, right_shoulder, _right_reach)
	return correction


func weapon_reach_along(axis: Vector3) -> float:
	var right := _reach_along(right_wrist.global_position, _animated_shoulder(_right_arm), _right_reach.y, axis)
	var left := _reach_along(left_wrist.global_position, _animated_shoulder(_left_arm), _left_reach.y, axis)
	return maxf(right, left)


func _reach_along(wrist: Vector3, shoulder: Vector3, reach: float, axis: Vector3) -> float:
	var offset := wrist - shoulder
	var depth := offset.dot(axis)
	var lateral_sq := maxf(0.0, offset.length_squared() - depth * depth)
	return maxf(0.0, -depth - sqrt(maxf(0.0, reach * reach - lateral_sq)))


func clamp_support_hand(point: Vector3) -> Vector3:
	return point + _reach_offset(point, _animated_shoulder(_left_arm), _left_reach)


func _animated_shoulder(chain: PackedInt32Array) -> Vector3:
	var skeleton := get_skeleton()
	var shoulder := skeleton.get_bone_global_pose(chain[0]).origin
	return skeleton.to_global(_spine_adjustment(skeleton) * shoulder + _crouch_lift(skeleton))


func _crouch_lift(skeleton: Skeleton3D) -> Vector3:
	if mounted_grip or _crouch_weight <= 0.0:
		return Vector3.ZERO
	var lift := CROUCH_HIP_LIFT * _crouch_weight
	# The crouch blend can still contain a nearly straight standing leg. Limit
	# the lift to its available reach so the foot stays on its animated contact.
	for chain in _legs:
		var hip := skeleton.to_global(skeleton.get_bone_global_pose(chain[0]).origin)
		var knee := skeleton.to_global(skeleton.get_bone_global_pose(chain[1]).origin)
		var foot := skeleton.to_global(skeleton.get_bone_global_pose(chain[2]).origin)
		var reach := hip.distance_to(knee) + knee.distance_to(foot) - 0.010
		var offset := hip - foot
		var vertical_reach := sqrt(maxf(0.0, reach * reach - offset.x * offset.x - offset.z * offset.z))
		lift = minf(lift, maxf(0.0, vertical_reach - offset.y))
	return skeleton.global_basis.inverse() * Vector3.UP * lift


func _neck_rotation(skeleton: Skeleton3D, spine_adjustment := Transform3D.IDENTITY) -> Basis:
	var axes := (skeleton.global_basis.inverse() * actor.global_basis).orthonormalized()
	var direction := axes.inverse() * spine_adjustment.basis * (skeleton.get_bone_global_pose(_head).origin - skeleton.get_bone_global_pose(_neck).origin)
	var tilt := atan2(-direction.z, direction.y)
	# Unfold the source's tucked neck as well as the spine, keeping the face over
	# the stock instead of turning an otherwise horizontal neck toward the gun.
	var correction := clampf(tilt - 0.30, 0.0, 1.0) * _crouch_weight
	return Basis(_aim_axis(skeleton), correction + ADS_NECK_PITCH * ads_weight)


func aim_eye_position() -> Vector3:
	var skeleton := get_skeleton()
	var spine_adjustment := _spine_adjustment(skeleton)
	var neck := spine_adjustment * skeleton.get_bone_global_pose(_neck)
	var head := skeleton.get_bone_global_pose(_head)
	var neck_turn := _neck_rotation(skeleton, spine_adjustment)
	head.origin = neck.origin + neck_turn * (spine_adjustment * head.origin - neck.origin)
	head.basis = _aim_head_basis(skeleton, head.basis)
	return skeleton.to_global(head * eye_in_head + _crouch_lift(skeleton))


func _spine_adjustment(skeleton: Skeleton3D) -> Transform3D:
	var spine := skeleton.get_bone_global_pose(_spine).origin
	var turn := _torso_rotation(skeleton)
	var offset := skeleton.global_basis.inverse() * (actor.global_basis * ADS_SPINE_OFFSET * ads_weight)
	return Transform3D(turn, spine - turn * spine + offset)


func _aim_axis(skeleton: Skeleton3D) -> Vector3:
	return (skeleton.global_basis.inverse() * actor.global_basis.x).normalized()


func _aim_head_basis(skeleton: Skeleton3D, basis: Basis) -> Basis:
	var roll_axis := (skeleton.global_basis.inverse() * actor.global_basis.z).normalized()
	if is_instance_valid(right_wrist) and not shovel_grip:
		# Look along the weapon, including when the source crouch looks at the floor.
		# Preserve the animated roll; only correct the direction of the face.
		var rig_forward := (skeleton.global_basis.inverse() * -actor.global_basis.z).normalized()
		var bind_forward := skeleton.get_bone_global_rest(_head).basis.inverse() * rig_forward
		var desired := Basis(_aim_axis(skeleton), aim_pitch + ADS_HEAD_PITCH * ads_weight) * rig_forward
		basis = Basis(Quaternion((basis * bind_forward).normalized(), desired.normalized())) * basis
	else:
		basis = Basis(_aim_axis(skeleton), aim_pitch + ADS_HEAD_PITCH * ads_weight) * basis
	return Basis(roll_axis, -lean * 0.16) * basis


func _torso_rotation(skeleton: Skeleton3D) -> Basis:
	var axes := (skeleton.global_basis.inverse() * actor.global_basis).orthonormalized()
	var angles := Vector3.ZERO
	if is_instance_valid(right_wrist) and not shovel_grip:
		# A bounded aiming correction, not a replacement of the animated spine.
		# The source's deep stealth crouch otherwise puts the gun above the head.
		var spine_to_neck := skeleton.get_bone_global_pose(_neck).origin - skeleton.get_bone_global_pose(_spine).origin
		var local_axis := axes.inverse() * spine_to_neck
		var forward_tilt := atan2(-local_axis.z, local_axis.y)
		angles.x += clampf(forward_tilt - lerpf(0.55, 0.48, _crouch_weight), 0.0, 0.95)
	angles.x += aim_pitch * 0.25 - shovel_lean.x + ADS_TORSO_PITCH * ads_weight
	if mounted_grip:
		angles.x += 0.24 + maxf(0.0, aim_pitch) * 0.40
	angles.y += shovel_lean.y - shoulder_brace * 0.55
	angles.z -= lean * 0.45
	return axes * Basis.from_euler(angles) * axes.transposed()


func _arm_reach(skeleton: Skeleton3D, chain: PackedInt32Array) -> Vector2:
	var shoulder := skeleton.to_global(skeleton.get_bone_global_rest(chain[0]).origin)
	var elbow := skeleton.to_global(skeleton.get_bone_global_rest(chain[1]).origin)
	var wrist := skeleton.to_global(skeleton.get_bone_global_rest(chain[2]).origin)
	var upper := shoulder.distance_to(elbow)
	var lower := elbow.distance_to(wrist)
	return Vector2(absf(upper - lower) + 0.015, upper + lower - 0.024)


func _reach_offset(wrist: Vector3, shoulder: Vector3, reach: Vector2) -> Vector3:
	var away := wrist - shoulder
	var distance := away.length()
	if distance < 0.0001:
		return -actor.global_basis.z * reach.x
	return away * (clampf(distance, reach.x, reach.y) / distance - 1.0)


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	var rig_transform := skeleton.global_transform
	var actor_transform := actor.global_transform
	var world_to_rig := rig_transform.affine_inverse()
	var rig_to_actor := actor_transform.affine_inverse() * rig_transform
	var actor_to_rig := world_to_rig * actor_transform
	var feet: Array[Transform3D] = []
	for chain in _legs:
		feet.append(skeleton.get_bone_global_pose(chain[2]))
	var pelvis := skeleton.get_bone_global_pose(_pelvis)
	pelvis.origin += _crouch_lift(skeleton)
	skeleton.set_bone_global_pose(_pelvis, pelvis)
	if not mounted_grip:
		for index in _legs.size():
			_pose_leg(skeleton, index, delta, rig_to_actor, actor_to_rig, world_to_rig, feet[index])
	var head_basis := skeleton.get_bone_global_pose(_head).basis
	skeleton.set_bone_global_pose(_spine, _spine_adjustment(skeleton) * skeleton.get_bone_global_pose(_spine))
	if ads_weight > 0.0 or _crouch_weight > 0.0:
		var neck := skeleton.get_bone_global_pose(_neck)
		neck.basis = _neck_rotation(skeleton) * neck.basis
		skeleton.set_bone_global_pose(_neck, neck)
	var head := skeleton.get_bone_global_pose(_head)
	head.basis = _aim_head_basis(skeleton, head_basis)
	skeleton.set_bone_global_pose(_head, head)

	if mounted_grip and _head >= 0:
		# Swing the entire operator around the tripod with the eye at the sight.
		var eye := skeleton.to_global(skeleton.get_bone_global_pose(_head) * eye_in_head)
		actor.align_mounted_operator(eye)
		world_to_rig = skeleton.global_transform.affine_inverse()
		rig_to_actor = actor_transform.affine_inverse() * skeleton.global_transform
		actor_to_rig = world_to_rig * actor_transform
		for index in _legs.size():
			_pose_leg(skeleton, index, delta, rig_to_actor, actor_to_rig, world_to_rig, skeleton.get_bone_global_pose(_legs[index][2]))

	if is_instance_valid(right_wrist) and is_instance_valid(left_wrist):
		_pose_arm(skeleton, _right_arm, right_wrist, right_palm, _right_palm_offset, 1.0, actor_to_rig.basis, world_to_rig)
		_pose_arm(skeleton, _left_arm, left_wrist, left_palm, _left_palm_offset, -1.0, actor_to_rig.basis, world_to_rig)
		var right_curls: Array = right_wrist.get_meta(&"finger_curls", [])
		_pose_fingers(skeleton, _right_fingers, SHOVEL_FINGER_CURL if shovel_grip else KNIFE_FINGER_CURL if knife_grip else right_curls if right_curls.size() == 5 else FIREARM_FINGER_CURL)
		var fingers := float(left_wrist.get_meta(&"grip_curl", 0.0))
		var thumb := float(left_wrist.get_meta(&"thumb_curl", 0.18))
		_pose_fingers(skeleton, _left_fingers, SHOVEL_FINGER_CURL if shovel_grip else KNIFE_SUPPORT_CURL if knife_grip else [
			lerpf(thumb + fingers * 0.25, 0.08, support_grip),
			lerpf(0.65 + fingers * 0.60, 0.02, support_grip),
			lerpf(0.70 + fingers * 0.60, 0.10, support_grip),
			lerpf(0.73 + fingers * 0.65, 0.20, support_grip),
			lerpf(0.75 + fingers * 0.65, 0.22, support_grip),
		])

		if not knife_grip and not shovel_grip:
			var left_curls: Array = left_wrist.get_meta(&"finger_curls", [])
			if left_curls.size() == 5:
				var blended: Array = []
				for digit in 5:
					var angles: Array = []
					for joint in 3:
						angles.append(lerpf(float(left_curls[digit][joint]), [0.08, 0.02, 0.10, 0.20, 0.22][digit], support_grip))
					blended.append(angles)
				_pose_fingers(skeleton, _left_fingers, blended)
			_apply_finger_splay(skeleton, _right_fingers, right_wrist, 1.0)
			_apply_finger_splay(skeleton, _left_fingers, left_wrist, 1.0 - support_grip)


func _apply_finger_splay(skeleton: Skeleton3D, chains: Array[PackedInt32Array], wrist: Marker3D, weight: float) -> void:
	var splay: Array = wrist.get_meta(&"finger_splay", [])
	if splay.size() != 5: return
	for digit in 5:
		var joint := chains[digit][0]
		var rotation := skeleton.get_bone_pose_rotation(joint)
		rotation *= Quaternion(Vector3.BACK, float(splay[digit]) * weight)
		if digit == 0:
			rotation *= Quaternion(Vector3.UP, float(wrist.get_meta(&"thumb_roll", 0.0)) * weight)
		skeleton.set_bone_pose_rotation(joint, rotation)


func _pose_leg(skeleton: Skeleton3D, index: int, delta: float, rig_to_actor: Transform3D,
		actor_to_rig: Transform3D, world_to_rig: Transform3D, ankle: Transform3D) -> void:
	# Keep source foot contacts while correcting the raised crouch's knee plane,
	# terrain height and residual heading between authored stride directions.
	var chain := _legs[index]
	var local_foot := rig_to_actor * ankle.origin
	var turn := Basis(Vector3.UP, _stride_yaw * _stride_weight)
	var directed_foot := turn * local_foot
	if _crouch_weight > 0.0:
		# Turn the stride around each foot's stance lane, not around the actor:
		# rotating a whole crouch 180 degrees swaps the left and right feet.
		var lane := Vector3(local_foot.x, 0.0, 0.15)
		var travel := turn * Vector3(0.0, 0.0, local_foot.z - lane.z)
		travel.x *= 0.55
		var crouch_foot := lane + travel + Vector3.UP * local_foot.y
		crouch_foot.x = signf(lane.x) * maxf(0.075, crouch_foot.x * signf(lane.x))
		directed_foot = directed_foot.lerp(crouch_foot, _crouch_weight)
	var target := actor.to_global(directed_foot)
	var correction := 0.0
	if grounded:
		_floor_ray.from = Vector3(target.x, actor.global_position.y + 0.30, target.z)
		_floor_ray.to = _floor_ray.from - Vector3.UP * 0.62
		var hit := actor.get_world_3d().direct_space_state.intersect_ray(_floor_ray)
		if not hit.is_empty() and hit.normal.y >= 0.65:
			correction = clampf(hit.position.y - actor.global_position.y, -0.20, 0.20)
	_foot_height[index] = lerpf(_foot_height[index], correction, 1.0 - exp(-delta * 23.0))
	if absf(_foot_height[index]) < 0.001 and absf(_stride_yaw * _stride_weight) < 0.001 and _crouch_weight < 0.001:
		return
	target.y += _foot_height[index]
	var foot_turn := turn.slerp(Basis(Vector3.UP, clampf(_stride_yaw, -0.30, 0.30) * _stride_weight), _crouch_weight)
	var goal := Transform3D(actor_to_rig.basis * foot_turn * rig_to_actor.basis * ankle.basis, world_to_rig * target)
	var knee := skeleton.get_bone_global_pose(chain[1]).origin
	if _crouch_weight > 0.0:
		var hip := rig_to_actor * skeleton.get_bone_global_pose(chain[0]).origin
		var foot := actor.to_local(target)
		var forward_knee := Vector3(lerpf(hip.x, foot.x, 0.5),
			lerpf(hip.y, foot.y, 0.55), minf(hip.z, foot.z) - 0.45)
		knee = knee.lerp(actor_to_rig * forward_knee, _crouch_weight)
	_solve(skeleton, chain, goal, knee)


func _chain(skeleton: Skeleton3D, names: Array) -> PackedInt32Array:
	var chain := PackedInt32Array()
	for bone: StringName in names:
		chain.append(skeleton.find_bone(bone))
	return chain


func _finger_chains(skeleton: Skeleton3D, side: String) -> Array[PackedInt32Array]:
	var chains: Array[PackedInt32Array] = []
	for digit in ["thumb", "index", "middle", "ring", "pinky"]:
		var chain := PackedInt32Array()
		for joint in range(1, 4):
			chain.append(skeleton.find_bone("%s_0%d_%s" % [digit, joint, side]))
		chains.append(chain)
	return chains


func _palm_frame(skeleton: Skeleton3D, right: bool) -> Basis:
	# Weapon sockets use Y along the fingers and Z into the palm. Native M2M
	# hand axes differ from these socket axes; derive the conversion from the rig.
	var chain := _right_fingers if right else _left_fingers
	var hand := _right_arm[2] if right else _left_arm[2]
	var rest := skeleton.get_bone_global_rest(hand)
	var y := (skeleton.get_bone_global_rest(chain[2][0]).origin - rest.origin).normalized()
	var across := skeleton.get_bone_global_rest(chain[1][0]).origin - skeleton.get_bone_global_rest(chain[4][0]).origin
	var x := across.normalized() * (1.0 if right else -1.0)
	var z := x.cross(y).normalized()
	x = y.cross(z).normalized()
	return rest.basis.inverse() * Basis(x, y, z)


func _pose_fingers(skeleton: Skeleton3D, chains: Array[PackedInt32Array], curls: Array) -> void:
	for digit in chains.size():
		for phalanx in chains[digit].size():
			var joint := chains[digit][phalanx]
			var rotation := skeleton.get_bone_rest(joint).basis.get_rotation_quaternion()
			var curl: float = curls[digit][phalanx] if curls[digit] is Array else float(curls[digit]) * [0.8, 1.15, 0.9][phalanx]
			# M2M finger phalanges curl around their own local X, after rest rotation.
			skeleton.set_bone_pose_rotation(joint, rotation * Quaternion(Vector3.RIGHT, curl))


func _pose_arm(skeleton: Skeleton3D, chain: PackedInt32Array, wrist: Marker3D, palm: Marker3D, palm_offset: Vector3, side: float,
		actor_to_rig: Basis, world_to_rig: Transform3D) -> void:
	var shoulder := skeleton.get_bone_global_pose(chain[0]).origin
	var pole := shoulder + actor_to_rig * Vector3(side * 0.13, -0.34, 0.16)
	var frame := _right_palm_frame if side > 0.0 else _left_palm_frame
	var goal := world_to_rig * wrist.global_transform
	goal.basis *= frame.inverse()
	if is_instance_valid(palm):
		goal = world_to_rig * palm.global_transform
		goal.basis *= frame.inverse()
		goal.origin -= goal.basis.orthonormalized() * palm_offset
	goal.basis = goal.basis.orthonormalized()
	if not knife_grip and not shovel_grip:
		# Place the elbow on its reachable circle toward a neutral wrist. The old
		# fixed downward pole forced the hand to hinge sharply at the cuff.
		var lower := skeleton.get_bone_global_pose(chain[1]).origin
		var hand := skeleton.get_bone_global_pose(chain[2]).origin
		var hand_axis := (goal.basis * palm_offset).normalized()
		var relaxed_pole := goal.origin - hand_axis * lower.distance_to(hand)
		var local_pole := actor_to_rig.inverse() * (relaxed_pole - shoulder)
		local_pole.y = minf(local_pole.y, -0.02)
		pole = shoulder + actor_to_rig * local_pole
	if is_instance_valid(_arm_ik):
		_arm_ik.active = use_godotik_arms
	if use_godotik_arms and is_instance_valid(_arm_ik) and _arm_effectors.size() == 2:
		var index := 0 if side > 0.0 else 1
		_arm_effectors[index].transform = goal
		_arm_poles[index].set("pole_direction", (pole - shoulder).normalized())
	else:
		_solve(skeleton, chain, goal, pole, true)


func _solve(skeleton: Skeleton3D, chain: PackedInt32Array, goal: Transform3D, pole: Vector3, follow_wrist: bool = false) -> void:
	var upper := skeleton.get_bone_global_pose(chain[0])
	var lower := skeleton.get_bone_global_pose(chain[1])
	var tip := skeleton.get_bone_global_pose(chain[2])
	var upper_link := lower.origin - upper.origin
	var lower_link := tip.origin - lower.origin
	var upper_length := upper_link.length()
	var lower_length := lower_link.length()
	var aim := goal.origin - upper.origin
	if aim.length_squared() < 0.000001:
		return
	var axis := aim.normalized()
	var distance := clampf(aim.length(), absf(upper_length - lower_length) + 0.001, upper_length + lower_length - 0.002)
	var bend := pole - upper.origin
	bend -= axis * bend.dot(axis)
	if bend.length_squared() < 0.000001:
		bend = upper_link - axis * upper_link.dot(axis)
	if bend.length_squared() < 0.000001:
		return
	var projection := (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, upper_length * upper_length - projection * projection))
	var elbow := upper.origin + axis * projection + bend.normalized() * height
	var end := upper.origin + axis * distance

	var upper_axis := (elbow - upper.origin).normalized()
	var lower_axis := (end - elbow).normalized()
	var upper_turn := Basis(Quaternion(upper_link.normalized(), upper_axis))
	upper.basis = upper_turn * upper.basis
	skeleton.set_bone_global_pose(chain[0], upper)

	var lower_turn := Basis(Quaternion((upper_turn * lower_link).normalized(), lower_axis))
	lower.basis = lower_turn * upper_turn * lower.basis
	if follow_wrist:
		var desired := goal.basis * skeleton.get_bone_rest(chain[2]).basis.inverse()
		var current_side := lower.basis.z.slide(lower_axis)
		var desired_side := desired.z.slide(lower_axis)
		if current_side.length_squared() > 0.0001 and desired_side.length_squared() > 0.0001:
			var roll := current_side.signed_angle_to(desired_side, lower_axis)
			lower.basis = Basis(lower_axis, clampf(roll * 0.65, -0.95, 0.95)) * lower.basis
	lower.origin = elbow
	skeleton.set_bone_global_pose(chain[1], lower)

	goal.origin = end
	skeleton.set_bone_global_pose(chain[2], goal)


static var _fabric_materials: Dictionary = {}


static func model_for_team(team: int) -> PackedScene:
	return RED_MODEL if team == 1 else MODEL


static func bind_vest_visibility(avatar: Node3D) -> Node3D:
	var vest := avatar.find_child(VEST_MESH, true, false) as Node3D
	var equipment: Array[Node3D] = []
	for mesh: MeshInstance3D in avatar.find_children("ChestKit*", "MeshInstance3D", true, false):
		if not String(mesh.name).contains("Kit_scarf"):
			equipment.append(mesh)
	var sync := func() -> void:
		for part in equipment:
			part.visible = vest.visible
	vest.visibility_changed.connect(sync)
	sync.call()
	return vest


static func apply_textures(avatar: Node3D, team := -1) -> void:
	for mesh: MeshInstance3D in avatar.find_children("*", "MeshInstance3D", true, false):
		if mesh.name == &"OperatorEyes":
			mesh.hide()
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if original == null:
				continue
			var name := original.resource_name
			if name.begins_with("Soldier_"):
				var soldier_key := "soldier/%d/%s" % [1 if team == 1 else 0, name]
				if not _fabric_materials.has(soldier_key):
					var soldier := ShaderMaterial.new()
					soldier.shader = SOLDIER_SHADER
					soldier.set_shader_parameter(&"base_color", original.albedo_texture)
					soldier.set_shader_parameter(&"normal_map", original.normal_texture)
					soldier.set_shader_parameter(&"metal_roughness", original.roughness_texture)
					soldier.set_shader_parameter(&"black_uniform", team == 1)
					soldier.set_shader_parameter(&"gloves", name in ["Soldier_Gloves", "Soldier_Cuff"])
					soldier.set_shader_parameter(&"cuffs", name == "Soldier_Cuff")
					_fabric_materials[soldier_key] = soldier
				mesh.set_surface_override_material(surface, _fabric_materials[soldier_key])
				continue
			if name.begins_with("Kit_scarf") or name in ["Kit_nylon", "Kit_sand", "Kit_stitch"]:
				if not _fabric_materials.has(name):
					var scarf := ShaderMaterial.new()
					scarf.shader = SCARF_SHADER
					scarf.set_shader_parameter(&"yarn_color", HD_FABRIC_COLOR)
					scarf.set_shader_parameter(&"yarn_normal", HD_FABRIC_NORMAL)
					scarf.set_shader_parameter(&"yarn_arm", HD_FABRIC_ARM)
					scarf.set_shader_parameter(&"yarn_tint", original.albedo_color)
					_fabric_materials[name] = scarf
				mesh.set_surface_override_material(surface, _fabric_materials[name])
				continue
			if name.begins_with("Kit_"):
				var kit_key := "kit/%d/%s" % [1 if team == 1 else 0, name]
				if not _fabric_materials.has(kit_key):
					var kit := original.duplicate() as BaseMaterial3D
					kit.vertex_color_use_as_albedo = true
					kit.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
					_fabric_materials[kit_key] = kit
				mesh.set_surface_override_material(surface, _fabric_materials[kit_key])
				continue
			var texture_name := "Mil_Suit_R5" if name in ["Mil_Suit_R5_Trousers", "Mil_Suit_R5_Gloves", "Mil_Suit_R5_Boots"] else name
			var pads := name == "Mil_Suit_Pads__R5"
			if not pads and not FABRIC_TEXTURES.has(texture_name):
				continue
			var key := "%d/%s" % [1 if team == 1 else 0, name]
			if not pads and name not in ["Mil_Suit_R5_Gloves", "Mil_Suit_R5_Boots"]:
				if not _fabric_materials.has(key):
					var cloth := ShaderMaterial.new()
					cloth.shader = FABRIC_SHADER
					cloth.set_shader_parameter(&"macro_color", FABRIC_TEXTURES[texture_name][0])
					cloth.set_shader_parameter(&"macro_normal", FABRIC_TEXTURES[texture_name][1])
					cloth.set_shader_parameter(&"macro_roughness", FABRIC_TEXTURES[texture_name][2])
					if original.ao_texture: cloth.set_shader_parameter(&"macro_ao", original.ao_texture)
					cloth.set_shader_parameter(&"weave_color", HD_FABRIC_COLOR)
					cloth.set_shader_parameter(&"weave_normal", HD_FABRIC_NORMAL)
					cloth.set_shader_parameter(&"weave_arm", HD_FABRIC_ARM)
					cloth.set_shader_parameter(&"fabric_tint", original.albedo_color)
					_fabric_materials[key] = cloth
				mesh.set_surface_override_material(surface, _fabric_materials[key])
				continue
			if not _fabric_materials.has(key):
				var material := original.duplicate() as BaseMaterial3D
				if pads:
					var packed := HD_LEATHER_ARM
					material.roughness_texture = packed
					material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
					material.roughness = 0.96
					material.detail_enabled = true
					material.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
					material.detail_normal = HD_LEATHER_NORMAL
					material.heightmap_enabled = true
					material.heightmap_texture = HD_LEATHER_HEIGHT
					material.heightmap_scale = 0.001
					material.detail_mask = packed
				else:
					material.albedo_texture = FABRIC_TEXTURES[texture_name][0]
					material.normal_texture = FABRIC_TEXTURES[texture_name][1]
					material.normal_enabled = true
					material.normal_scale = 0.65
					material.roughness_texture = FABRIC_TEXTURES[texture_name][2]
					material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
					material.roughness = 1.0
					material.detail_enabled = true
					material.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
					material.detail_normal = HD_FABRIC_NORMAL
					material.detail_mask = HD_FABRIC_ARM
					if name in ["Mil_Suit_R5_Gloves", "Mil_Suit_R5_Boots"]:
						material.detail_normal = HD_LEATHER_NORMAL
						material.roughness = 0.84
				if name == "Mil_Suit_R5_Boots":
					material.albedo_texture = HD_LEATHER_COLOR
					material.albedo_color = Color(0.38, 0.31, 0.21) if team == 1 else Color(0.22, 0.235, 0.25)
					material.normal_texture = HD_LEATHER_NORMAL
					material.normal_scale = 0.35
					material.roughness_texture = null
					material.roughness = 0.9
					material.uv1_triplanar = true
					material.uv1_scale = Vector3.ONE * 8.0
					material.ao_enabled = false
				material.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
				material.uv2_triplanar = true
				material.uv2_scale = Vector3.ONE * 6.0
				material.metallic = 0.0
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				_fabric_materials[key] = material
			mesh.set_surface_override_material(surface, _fabric_materials[key])


static func attach_wristwatch(skeleton: Skeleton3D) -> void:
	var cuff := BoneAttachment3D.new()
	cuff.name = "WatchCuff"
	cuff.bone_name = &"hand_l"
	skeleton.add_child(cuff)
	var watch := WRISTWATCH.instantiate() as Node3D
	watch.name = "Wristwatch"
	# The scan's bracelet is laid flat. Fit the case over the operator's sleeve.
	for part: Node3D in watch.get_children():
		if part.name != &"digital_wrist_watch":
			part.hide()
	watch.rotation.x = PI * 0.5
	watch.position = Vector3(0.0, -0.038, 0.029)
	cuff.add_child(watch)
