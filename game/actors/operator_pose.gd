extends SkeletonModifier3D

const Balance := preload("res://game/combat/combat_balance.gd")
const VEST_MESH := "Object_105"
const MODEL := preload("res://assets/operator/operator.glb")
const LOCOMOTION := preload("res://assets/animations/operator_locomotion.res")
const DIRECTIONAL_LOCOMOTION := "res://assets/animations/local/operator_directions.res"
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

const TEAM_ALBEDO := [
	{
		"Mil_Suit_R5": preload("res://assets/operator/textures/blue_uniform.jpg"),
		"Mil_Suit_R5__Plate": preload("res://assets/operator/textures/blue_vest.jpg"),
		"Mil_Suit_R5_Puches": preload("res://assets/operator/textures/blue_pouches.jpg"),
	}, {
		"Mil_Suit_R5": preload("res://assets/operator/textures/red_uniform.jpg"),
		"Mil_Suit_R5__Plate": preload("res://assets/operator/textures/red_vest.jpg"),
		"Mil_Suit_R5_Puches": preload("res://assets/operator/textures/red_pouches.jpg"),
	},
]

const RIGHT_ARM := [&"mixamorig_RightArm_09", &"mixamorig_RightForeArm_010", &"mixamorig_RightHand_011"]
const LEFT_ARM := [&"mixamorig_LeftArm_033", &"mixamorig_LeftForeArm_034", &"mixamorig_LeftHand_035"]
const RIGHT_LEG := [&"mixamorig_RightUpLeg_057", &"mixamorig_RightLeg_058", &"mixamorig_RightFoot_059", &"mixamorig_RightToeBase_060"]
const LEFT_LEG := [&"mixamorig_LeftUpLeg_063", &"mixamorig_LeftLeg_064", &"mixamorig_LeftFoot_065", &"mixamorig_LeftToeBase_066"]
const GAITS := [&"crouch_walk", &"walk", &"jog", &"sprint"]
const WALK_DIRECTIONS := ["forward", "forward_right", "right", "backward_right",
	"backward", "backward_left", "left", "forward_left"]
const DIRECTION_STEP := TAU / 8.0
const TOE_CLEARANCE := 0.04
const CROUCH_TOE_OUT := 0.26
const FIREARM_FINGER_CURL := [0.18, -0.13, 0.36, 0.42, 0.44]
const KNIFE_FINGER_CURL := [0.30, 0.72, 0.83, 0.88, 0.95]

var actor: Node3D
var right_wrist: Marker3D
var left_wrist: Marker3D
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
var _forward_boots: Array[Basis]
var _rest_toe_pitch: Array[float]
var _foot_contact: Array[bool] = [false, false]
var _foot_anchor: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _foot_height: Array[float] = [0.0, 0.0]
var _floor_ray := PhysicsRayQueryParameters3D.new()
var _right_fingers: Array[PackedInt32Array]
var _left_fingers: Array[PackedInt32Array]
var _locomotion: AnimationPlayer
var _directional_gaits := false
var _travel_sector := 0
var _was_grounded := true
var _fall_speed := 0.0
var _transition_left := 0.0
var _stride_yaw := 0.0
var _stride_weight := 0.0
var _crouch_weight := 0.0
var _torso_angles := Vector3.ZERO
var _head := -1
var _spine := -1
var _right_reach: Vector2
var _left_reach: Vector2
var aim_pitch := 0.0


func _ready() -> void:
	var skeleton := get_skeleton()
	_right_arm = _chain(skeleton, RIGHT_ARM)
	_left_arm = _chain(skeleton, LEFT_ARM)
	_legs = [_chain(skeleton, RIGHT_LEG), _chain(skeleton, LEFT_LEG)]
	var rig_to_actor := actor.global_transform.affine_inverse() * skeleton.global_transform
	for chain in _legs:
		var ankle := rig_to_actor * skeleton.get_bone_global_rest(chain[2])
		var toe := rig_to_actor * skeleton.get_bone_global_rest(chain[3])
		var toe_offset := toe.origin - ankle.origin
		var toe_yaw := atan2(-toe_offset.x, -toe_offset.z)
		_forward_boots.append(Basis(Vector3.UP, -toe_yaw) * ankle.basis.orthonormalized())
		_rest_toe_pitch.append(toe_offset.angle_to(Vector3.UP))
	_floor_ray.collision_mask = Balance.WORLD_MASK
	_right_fingers = _finger_chains(skeleton, "Right")
	_left_fingers = _finger_chains(skeleton, "Left")
	_head = skeleton.find_bone(&"mixamorig_Head_06")
	_spine = skeleton.find_bone(&"mixamorig_Spine_02")
	_right_reach = _arm_reach(skeleton, _right_arm)
	_left_reach = _arm_reach(skeleton, _left_arm)
	_locomotion = AnimationPlayer.new()
	_locomotion.root_node = NodePath("../..")
	_locomotion.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_locomotion.add_animation_library(&"", LOCOMOTION)
	if ResourceLoader.exists(DIRECTIONAL_LOCOMOTION, "AnimationLibrary"):
		var directions := load(DIRECTIONAL_LOCOMOTION) as AnimationLibrary
		if directions:
			_locomotion.add_animation_library(&"directions", directions)
			_directional_gaits = true
	add_child(_locomotion)
	reset_locomotion()


func reset_locomotion() -> void:
	_was_grounded = true
	_fall_speed = 0.0
	_transition_left = 0.0
	_stride_yaw = 0.0
	_stride_weight = 0.0
	_travel_sector = 0
	_crouch_weight = 0.0
	_torso_angles = Vector3.ZERO
	_foot_contact.fill(false)
	_foot_height.fill(0.0)
	_locomotion.stop()
	_locomotion.speed_scale = 1.0
	_locomotion.play(&"idle")
	_locomotion.advance(0.0)


func update_locomotion(delta: float, crouched: bool, vertical_speed: float) -> void:
	var speed := planar_velocity.length()
	var current := _locomotion.current_animation
	var was_moving := current in GAITS or current.begins_with("directions/")
	var clip: StringName = &"idle"
	var rate := 1.0
	var travel := actor.global_basis.inverse() * planar_velocity
	var moving_speed := 0.20 if was_moving else 0.38
	_transition_left = maxf(0.0, _transition_left - delta)
	if not grounded:
		_fall_speed = maxf(_fall_speed, -vertical_speed)
		if _was_grounded and vertical_speed > 1.0:
			_transition_left = 0.20
			clip = &"jump_start"
		else:
			clip = &"jump_start" if current == &"jump_start" and _transition_left > 0.0 else &"jump_air"
		rate = 4.0 if clip == &"jump_start" else 1.0
	elif (not _was_grounded and maxf(_fall_speed, -vertical_speed) > 1.1) or (current == &"jump_land" and _transition_left > 0.0):
		if current != &"jump_land":
			_transition_left = 0.30
		clip = &"jump_land"
		rate = 3.0
	elif crouched:
		clip = &"crouch_walk" if speed > moving_speed else &"crouch_idle"
		rate = clampf(speed / 1.65, 0.55, 1.65) if clip == &"crouch_walk" else 1.0
	elif speed > moving_speed:
		if speed > (5.9 if current == &"sprint" else 6.3) and travel.z < -speed * 0.55:
			clip = &"sprint"
			rate = clampf(speed / 6.4, 0.8, 1.35)
		elif speed > (3.25 if current == &"jog" or current.begins_with("directions/jog_") else 3.65):
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
		if _directional_gaits and clip in [&"walk", &"jog"]:
			var last_heading := _travel_sector * DIRECTION_STEP
			if not current.begins_with("directions/") or absf(angle_difference(last_heading, heading)) > DIRECTION_STEP * 0.5 + 0.10:
				_travel_sector = posmod(roundi(heading / DIRECTION_STEP), WALK_DIRECTIONS.size())
			var directional := StringName("directions/%s_%s" % [clip, WALK_DIRECTIONS[_travel_sector]])
			if _locomotion.has_animation(directional):
				rate = clampf(speed / (2.0 if clip == &"walk" else 4.0), 0.45, 1.65)
				clip = directional
				stride_yaw = -angle_difference(_travel_sector * DIRECTION_STEP, heading)
	_stride_yaw = rotate_toward(_stride_yaw, stride_yaw, delta * 13.0)
	_stride_weight = move_toward(_stride_weight, float(moving), delta * 8.0)
	_crouch_weight = move_toward(_crouch_weight, float(crouched and grounded), delta * 8.0)
	var lean := Vector3(
		clampf(travel.z * 0.023, -0.17, 0.06),
		clampf(-travel.x * 0.027, -0.15, 0.15),
		clampf(-travel.x * 0.030, -0.16, 0.16))
	lean.x -= 0.08 if crouched else 0.0
	_torso_angles = _torso_angles.lerp(lean, 1.0 - exp(-delta * 9.0))
	if grounded:
		_fall_speed = 0.0
	_was_grounded = grounded
	if current != clip:
		var phase := 0.0
		if moving and was_moving:
			phase = _locomotion.current_animation_position / _locomotion.current_animation_length
		var blend_time := 0.08 if clip in [&"jump_start", &"jump_land"] else 0.15
		_locomotion.play(clip, blend_time)
		if phase > 0.0:
			_locomotion.seek(phase * _locomotion.get_animation(clip).length)
	_locomotion.speed_scale = rate
	_locomotion.advance(delta)


func weapon_carry_anchor() -> Vector3:
	return _animated_shoulder(_right_arm).lerp(_animated_shoulder(_left_arm), 0.5)


func weapon_stock_anchor() -> Vector3:
	return _animated_shoulder(_right_arm) + actor.global_basis * Vector3(-0.045, 0.06, -0.095)


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
	var spine := skeleton.get_bone_global_pose(_spine).origin
	return skeleton.to_global(spine + _torso_rotation(skeleton) * (shoulder - spine))


func _torso_rotation(skeleton: Skeleton3D) -> Basis:
	var axes := (skeleton.global_basis.inverse() * actor.global_basis).orthonormalized()
	var angles := _torso_angles
	angles.x += aim_pitch * 0.25 - shovel_lean.x
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
	if not mounted_grip:
		for index in _legs.size():
			_pose_leg(skeleton, index, delta, rig_to_actor, actor_to_rig, world_to_rig)

	var head_basis := skeleton.get_bone_global_pose(_head).basis
	var spine := skeleton.get_bone_global_pose(_spine)
	spine.basis = _torso_rotation(skeleton) * spine.basis
	skeleton.set_bone_global_pose(_spine, spine)
	if _head >= 0:
		var head := skeleton.get_bone_global_pose(_head)
		var head_axis := actor_to_rig.basis.x
		var roll_axis := actor_to_rig.basis.z.normalized()
		head.basis = Basis(roll_axis, -lean * 0.16) * Basis(head_axis.normalized(), aim_pitch) * head_basis
		skeleton.set_bone_global_pose(_head, head)

	if mounted_grip and _head >= 0:
		# Swing the entire operator around the tripod with the eye at the sight.
		var eye := skeleton.to_global(skeleton.get_bone_global_pose(_head) * eye_in_head)
		actor.align_mounted_operator(eye)
		world_to_rig = skeleton.global_transform.affine_inverse()
		rig_to_actor = actor_transform.affine_inverse() * skeleton.global_transform
		actor_to_rig = world_to_rig * actor_transform
		for index in _legs.size():
			_pose_leg(skeleton, index, delta, rig_to_actor, actor_to_rig, world_to_rig)

	if is_instance_valid(right_wrist) and is_instance_valid(left_wrist):
		_pose_arm(skeleton, _right_arm, right_wrist, 1.0, actor_to_rig.basis, world_to_rig)
		_pose_arm(skeleton, _left_arm, left_wrist, -1.0, actor_to_rig.basis, world_to_rig)
		_pose_fingers(skeleton, _right_fingers, KNIFE_FINGER_CURL if knife_grip or shovel_grip else FIREARM_FINGER_CURL)
		_pose_fingers(skeleton, _left_fingers, KNIFE_FINGER_CURL if shovel_grip else [
			lerpf(0.18, 0.08, support_grip),
			lerpf(0.27, 0.02, support_grip),
			lerpf(0.31, 0.10, support_grip),
			lerpf(0.34, 0.20, support_grip),
			lerpf(0.34, 0.22, support_grip),
		])


func _pose_leg(skeleton: Skeleton3D, index: int, delta: float, rig_to_actor: Transform3D,
		actor_to_rig: Transform3D, world_to_rig: Transform3D) -> void:
	var chain := _legs[index]
	var ankle := skeleton.get_bone_global_pose(chain[2])
	var toe := skeleton.get_bone_global_pose(chain[3]).origin
	var foot := rig_to_actor * ankle.origin
	var toe_offset := rig_to_actor.basis * (toe - ankle.origin)
	var animated_sole := foot.y + minf(toe_offset.y, -0.08)
	var sole_height := animated_sole
	var stride := Vector3(0.0, 0.0, foot.z - 0.035)
	foot += (stride.rotated(Vector3.UP, _stride_yaw) - stride) * _stride_weight
	var side := 1.0 if index == 0 else -1.0
	var lateral_weight := absf(sin(_stride_yaw)) * _stride_weight
	foot.x = lerpf(foot.x, side * maxf(side * foot.x, 0.055), lateral_weight)
	foot.x = lerpf(foot.x, side * maxf(side * foot.x, 0.10), _crouch_weight)
	var target := actor.to_global(foot)

	var up := actor_to_rig.basis.y.normalized()
	var toe_turn := clampf(_stride_yaw, -0.65, 0.65) * lateral_weight
	var boot := Basis(up, toe_turn) * ankle.basis
	var crouch_toe_yaw := -side * CROUCH_TOE_OUT
	if _crouch_weight > 0.0:
		var pitch := clampf(_rest_toe_pitch[index] - toe_offset.angle_to(Vector3.UP), -0.24, 0.30)
		var crouch_boot := actor_to_rig.basis.orthonormalized() * Basis(Vector3.UP, crouch_toe_yaw)
		crouch_boot *= Basis(Vector3.RIGHT, pitch * _stride_weight) * _forward_boots[index]
		boot = boot.slerp(crouch_boot, _crouch_weight)
		var posed_toe := rig_to_actor.basis * (boot * (ankle.basis.inverse() * (toe - ankle.origin)))
		sole_height = foot.y + minf(posed_toe.y, -0.08)

	var floor_offset := 0.0
	var contacting := false
	if grounded:
		var probe := Vector3(target.x, actor.global_position.y, target.z)
		_floor_ray.from = probe + Vector3.UP * 0.30
		_floor_ray.to = probe - Vector3.UP * 0.32
		var hit := actor.get_world_3d().direct_space_state.intersect_ray(_floor_ray)
		if not hit.is_empty() and hit.normal.y >= 0.65:
			var correction := TOE_CLEARANCE - sole_height
			var crouch_idle := _crouch_weight * (1.0 - _stride_weight)
			correction = lerpf(maxf(0.0, correction), correction, crouch_idle)
			if mounted_grip:
				correction = TOE_CLEARANCE - sole_height
				floor_offset = clampf(hit.position.y - probe.y + correction, -0.32, 0.45)
			else:
				floor_offset = clampf(hit.position.y - probe.y + correction, -0.17, 0.20)
			contacting = _stride_weight > 0.75 and animated_sole < 0.095
	if contacting and not _foot_contact[index]:
		_foot_anchor[index] = target
	if contacting:
		var drift := (_foot_anchor[index] - target).slide(Vector3.UP)
		var plant := (1.0 - smoothstep(0.04, 0.095, animated_sole)) * (1.0 - smoothstep(0.07, 0.31, drift.length()))
		target += drift * plant
	_foot_contact[index] = contacting
	_foot_height[index] = lerpf(_foot_height[index], floor_offset, 1.0 - exp(-delta * 23.0)) if grounded else 0.0
	target.y += _foot_height[index]

	var goal := Transform3D(boot, world_to_rig * target)
	var hip := skeleton.get_bone_global_pose(chain[0]).origin
	var knee := skeleton.get_bone_global_pose(chain[1]).origin
	var bend := (knee - hip).rotated(up, toe_turn).normalized()
	if _crouch_weight > 0.0:
		var leg_axis := (rig_to_actor.basis * (goal.origin - hip)).normalized()
		var knee_forward := Vector3.FORWARD.rotated(Vector3.UP, crouch_toe_yaw)
		# Adjust only the pole height to keep its horizontal heading aligned with the boot.
		knee_forward.y = -knee_forward.dot(leg_axis) / minf(leg_axis.y, -0.22)
		var crouch_bend := (actor_to_rig.basis * knee_forward).normalized()
		bend = bend.lerp(crouch_bend, _crouch_weight)
	_solve(skeleton, chain, goal, hip + bend, false, _crouch_weight)


func _chain(skeleton: Skeleton3D, names: Array) -> PackedInt32Array:
	var chain := PackedInt32Array()
	for bone: StringName in names:
		chain.append(skeleton.find_bone(bone))
	return chain


func _finger_chains(skeleton: Skeleton3D, side: String) -> Array[PackedInt32Array]:
	var chains: Array[PackedInt32Array] = []
	for digit in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
		var chain := PackedInt32Array()
		for joint in range(1, 4):
			var prefix := "mixamorig_%sHand%s%d_" % [side, digit, joint]
			for index in skeleton.get_bone_count():
				if String(skeleton.get_bone_name(index)).begins_with(prefix):
					chain.append(index)
					break
		chains.append(chain)
	return chains


func _pose_fingers(skeleton: Skeleton3D, chains: Array[PackedInt32Array], curls: Array) -> void:
	for digit in chains.size():
		var axis := Vector3.RIGHT
		for joint in chains[digit]:
			var rotation := skeleton.get_bone_pose_rotation(joint)
			skeleton.set_bone_pose_rotation(joint, Quaternion(axis, float(curls[digit])) * rotation)
			# Rotating around the curl axis leaves it unchanged in the next joint's parent space.
			axis = (rotation.inverse() * axis).normalized()


func _pose_arm(skeleton: Skeleton3D, chain: PackedInt32Array, wrist: Marker3D, side: float,
		actor_to_rig: Basis, world_to_rig: Transform3D) -> void:
	var shoulder := skeleton.get_bone_global_pose(chain[0]).origin
	var pole := shoulder + actor_to_rig * Vector3(side * 0.13, -0.34, 0.16)
	var goal := world_to_rig * wrist.global_transform
	goal.basis = goal.basis.orthonormalized()
	_solve(skeleton, chain, goal, pole, true)


func _solve(skeleton: Skeleton3D, chain: PackedInt32Array, goal: Transform3D, pole: Vector3, follow_wrist: bool = false, hinge_weight: float = 0.0) -> void:
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
	var hinge := axis.cross(bend).normalized()
	var upper_turn := Basis(Quaternion(upper_link.normalized(), upper_axis))
	upper.basis = upper_turn * upper.basis
	if hinge_weight > 0.0:
		upper.basis = _align_hinge(upper.basis, upper_axis, hinge, hinge_weight)
	skeleton.set_bone_global_pose(chain[0], upper)

	var lower_turn := Basis(Quaternion((upper_turn * lower_link).normalized(), lower_axis))
	lower.basis = lower_turn * upper_turn * lower.basis
	if hinge_weight > 0.0:
		lower.basis = _align_hinge(lower.basis, lower_axis, hinge, hinge_weight)
	elif follow_wrist:
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


func _align_hinge(basis: Basis, segment: Vector3, hinge: Vector3, weight: float) -> Basis:
	# The operator's thigh and shin use local X as their knee hinge axis.
	var roll := basis.x.slide(segment).signed_angle_to(hinge, segment)
	return Basis(segment, roll * weight) * basis


static var _fabric_materials: Dictionary = {}


static func apply_textures(avatar: Node3D, team := -1) -> void:
	for mesh: MeshInstance3D in avatar.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if original == null or not FABRIC_TEXTURES.has(original.resource_name):
				continue
			var name := original.resource_name
			var key := "%d/%s" % [team, name]
			if not _fabric_materials.has(key):
				var material := original.duplicate() as BaseMaterial3D
				material.albedo_texture = TEAM_ALBEDO[team][name] if team in [0, 1] else FABRIC_TEXTURES[name][0]
				material.normal_texture = FABRIC_TEXTURES[name][1]
				material.normal_enabled = true
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				_fabric_materials[key] = material
			mesh.set_surface_override_material(surface, _fabric_materials[key])
