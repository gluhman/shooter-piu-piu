extends SkeletonModifier3D

const VEST_MESH := "Object_105"
const MODEL := preload("res://assets/operator/operator.glb")
const LOCOMOTION := preload("res://assets/animations/operator_locomotion.res")
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

const RIGHT_ARM := [&"mixamorig_RightArm_09", &"mixamorig_RightForeArm_010", &"mixamorig_RightHand_011"]
const LEFT_ARM := [&"mixamorig_LeftArm_033", &"mixamorig_LeftForeArm_034", &"mixamorig_LeftHand_035"]

var actor: Node3D
var right_wrist: Marker3D
var left_wrist: Marker3D
var planar_velocity := Vector3.ZERO
var grounded := true
var support_grip := 0.0
var stance_offset := Vector3.ZERO

var _right_arm: PackedInt32Array
var _left_arm: PackedInt32Array
var _right_fingers: Array[PackedInt32Array]
var _left_fingers: Array[PackedInt32Array]
var _locomotion: AnimationPlayer
var _was_grounded := true
var _transition_left := 0.0
var _stride_yaw := 0.0
var _head := -1
var _hips := -1
var _right_reach: float
var _left_reach: float
var aim_pitch := 0.0


func _ready() -> void:
	var skeleton := get_skeleton()
	_right_arm = _chain(skeleton, RIGHT_ARM)
	_left_arm = _chain(skeleton, LEFT_ARM)
	_right_fingers = _finger_chains(skeleton, "Right")
	_left_fingers = _finger_chains(skeleton, "Left")
	_head = skeleton.find_bone(&"mixamorig_Head_06")
	_hips = skeleton.find_bone(&"mixamorig_Hips_01")
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
	_locomotion.speed_scale = 1.0
	_locomotion.play(&"idle")
	_locomotion.advance(0.0)


func update_locomotion(delta: float, crouched: bool, vertical_speed: float) -> void:
	var speed := planar_velocity.length()
	var current := _locomotion.current_animation
	var clip: StringName = &"idle"
	var rate := 1.0
	var travel := actor.global_basis.inverse() * planar_velocity
	var backwards := travel.z > absf(travel.x) * 0.8
	_transition_left = maxf(0.0, _transition_left - delta)
	if not grounded:
		if _was_grounded and vertical_speed > 1.0:
			_transition_left = 0.20
			clip = &"jump_start"
		else:
			clip = &"jump_start" if current == &"jump_start" and _transition_left > 0.0 else &"jump_air"
		rate = 4.0 if clip == &"jump_start" else 1.0
	elif (not _was_grounded and vertical_speed < -1.1) or (current == &"jump_land" and _transition_left > 0.0):
		if current != &"jump_land":
			_transition_left = 0.30
		clip = &"jump_land"
		rate = 3.0
	elif crouched:
		clip = &"crouch_walk" if speed > 0.24 else &"crouch_idle"
		rate = clampf(speed / 1.8, 0.75, 1.5) if clip == &"crouch_walk" else 1.0
	elif speed > 0.24:
		if speed > 6.2:
			clip = &"sprint"
			rate = clampf(speed / 6.8, 0.8, 1.35)
		elif speed > 3.8:
			clip = &"jog"
			rate = clampf(speed / 4.5, 0.8, 1.35)
		else:
			clip = &"walk"
			rate = clampf(speed / 2.5, 0.7, 1.5)
	var moving := clip in [&"crouch_walk", &"walk", &"jog", &"sprint"]
	var turn := clampf(atan2(-travel.x, maxf(absf(travel.z), 0.3)), -0.55, 0.55) if moving else 0.0
	_stride_yaw = move_toward(_stride_yaw, turn, delta * 5.0)
	_was_grounded = grounded
	_locomotion.speed_scale = -rate if moving and backwards else rate
	if current != clip:
		_locomotion.play(clip, 0.12, 1.0, moving and backwards)
	_locomotion.advance(delta)


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
	var right := _reach_along(right_wrist.global_position, _animated_shoulder(_right_arm), _right_reach, axis)
	var left := _reach_along(left_wrist.global_position, _animated_shoulder(_left_arm), _left_reach, axis)
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
	var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(chain[0]).origin)
	var hips := skeleton.to_global(skeleton.get_bone_global_pose(_hips).origin)
	return hips + (shoulder - hips).rotated(actor.global_basis.y.normalized(), _stride_yaw)


func _arm_reach(skeleton: Skeleton3D, chain: PackedInt32Array) -> float:
	var shoulder := skeleton.to_global(skeleton.get_bone_global_rest(chain[0]).origin)
	var elbow := skeleton.to_global(skeleton.get_bone_global_rest(chain[1]).origin)
	var wrist := skeleton.to_global(skeleton.get_bone_global_rest(chain[2]).origin)
	return shoulder.distance_to(elbow) + elbow.distance_to(wrist) - 0.024


func _reach_offset(wrist: Vector3, shoulder: Vector3, reach: float) -> Vector3:
	var away := wrist - shoulder
	return away.limit_length(reach) - away


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if not is_zero_approx(_stride_yaw):
		var hips := skeleton.get_bone_global_pose(_hips)
		var up := skeleton.global_basis.inverse() * actor.global_basis.y
		hips.basis = Basis(up.normalized(), _stride_yaw) * hips.basis
		skeleton.set_bone_global_pose(_hips, hips)

	if _head >= 0:
		var head := skeleton.get_bone_global_pose(_head)
		var head_axis := skeleton.global_basis.inverse() * actor.global_basis.x
		head.basis = Basis(head_axis.normalized(), aim_pitch) * head.basis
		skeleton.set_bone_global_pose(_head, head)

	if is_instance_valid(right_wrist) and is_instance_valid(left_wrist):
		_pose_arm(skeleton, _right_arm, right_wrist, 1.0)
		_pose_arm(skeleton, _left_arm, left_wrist, -1.0)
		_pose_fingers(skeleton, _right_fingers, [0.18, -0.13, 0.36, 0.42, 0.44])
		_pose_fingers(skeleton, _left_fingers, [
			lerpf(0.18, 0.08, support_grip),
			lerpf(0.27, 0.02, support_grip),
			lerpf(0.31, 0.10, support_grip),
			lerpf(0.34, 0.20, support_grip),
			lerpf(0.34, 0.22, support_grip),
		])


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


func _pose_arm(skeleton: Skeleton3D, chain: PackedInt32Array, wrist: Marker3D, side: float) -> void:
	var pole := skeleton.to_local(actor.to_global(Vector3(side * 0.35, 1.15, 0.15) + stance_offset))
	var goal := skeleton.global_transform.affine_inverse() * wrist.global_transform
	goal.basis = goal.basis.orthonormalized()
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

	var upper_turn := Basis(Quaternion(upper_link.normalized(), (elbow - upper.origin).normalized()))
	upper.basis = upper_turn * upper.basis
	skeleton.set_bone_global_pose(chain[0], upper)

	var lower_turn := Basis(Quaternion((upper_turn * lower_link).normalized(), (end - elbow).normalized()))
	lower.basis = lower_turn * upper_turn * lower.basis
	if follow_wrist:
		var forearm_axis := (end - elbow).normalized()
		var desired := goal.basis * skeleton.get_bone_rest(chain[2]).basis.inverse()
		var current_side := lower.basis.z.slide(forearm_axis)
		var desired_side := desired.z.slide(forearm_axis)
		if current_side.length_squared() > 0.0001 and desired_side.length_squared() > 0.0001:
			var roll := current_side.signed_angle_to(desired_side, forearm_axis)
			lower.basis = Basis(forearm_axis, clampf(roll * 0.65, -0.95, 0.95)) * lower.basis
	lower.origin = elbow
	skeleton.set_bone_global_pose(chain[1], lower)

	goal.origin = end
	skeleton.set_bone_global_pose(chain[2], goal)


static var _fabric_materials: Dictionary = {}


static func apply_textures(avatar: Node3D) -> void:
	for mesh: MeshInstance3D in avatar.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.get_active_material(surface) as BaseMaterial3D
			if original == null or not FABRIC_TEXTURES.has(original.resource_name):
				continue
			var name := original.resource_name
			if not _fabric_materials.has(name):
				var material := original.duplicate() as BaseMaterial3D
				material.albedo_texture = FABRIC_TEXTURES[name][0]
				material.normal_texture = FABRIC_TEXTURES[name][1]
				material.normal_enabled = true
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				_fabric_materials[name] = material
			mesh.set_surface_override_material(surface, _fabric_materials[name])
