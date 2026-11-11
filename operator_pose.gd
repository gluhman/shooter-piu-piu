extends SkeletonModifier3D

const MODEL := preload("res://assets/operator/operator.glb")
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
const RIGHT_LEG := [&"mixamorig_RightUpLeg_057", &"mixamorig_RightLeg_058", &"mixamorig_RightFoot_059"]
const LEFT_LEG := [&"mixamorig_LeftUpLeg_063", &"mixamorig_LeftLeg_064", &"mixamorig_LeftFoot_065"]

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
var _right_leg: PackedInt32Array
var _left_leg: PackedInt32Array
var _right_foot: Transform3D
var _left_foot: Transform3D
var _walk_phase := 0.0
var _walk_blend := 0.0
var _jump_blend := 0.0
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
	_right_leg = _chain(skeleton, RIGHT_LEG)
	_left_leg = _chain(skeleton, LEFT_LEG)
	_right_foot = skeleton.get_bone_global_rest(_right_leg[2])
	_left_foot = skeleton.get_bone_global_rest(_left_leg[2])
	_head = skeleton.find_bone(&"mixamorig_Head_06")
	_hips = skeleton.find_bone(&"mixamorig_Hips_01")
	_right_reach = _arm_reach(skeleton, _right_arm)
	_left_reach = _arm_reach(skeleton, _left_arm)


func weapon_reach_correction() -> Vector3:
	var skeleton := get_skeleton()
	var right_shoulder := skeleton.to_global(skeleton.get_bone_global_rest(_right_arm[0]).origin)
	var left_shoulder := skeleton.to_global(skeleton.get_bone_global_rest(_left_arm[0]).origin)
	right_shoulder += actor.global_basis * stance_offset
	left_shoulder += actor.global_basis * stance_offset
	var correction := Vector3.ZERO
	# Project both targets back within reach, preserving the spacing of the weapon's grips.
	for _pass_index in 3:
		correction += _reach_offset(right_wrist.global_position + correction, right_shoulder, _right_reach)
		correction += _reach_offset(left_wrist.global_position + correction, left_shoulder, _left_reach)
	return correction


func _arm_reach(skeleton: Skeleton3D, chain: PackedInt32Array) -> float:
	var shoulder := skeleton.to_global(skeleton.get_bone_global_rest(chain[0]).origin)
	var elbow := skeleton.to_global(skeleton.get_bone_global_rest(chain[1]).origin)
	var wrist := skeleton.to_global(skeleton.get_bone_global_rest(chain[2]).origin)
	return shoulder.distance_to(elbow) + elbow.distance_to(wrist) - 0.024


func _reach_offset(wrist: Vector3, shoulder: Vector3, reach: float) -> Vector3:
	var away := wrist - shoulder
	return away.limit_length(reach) - away


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if not stance_offset.is_zero_approx():
		var hips := skeleton.get_bone_global_pose(_hips)
		hips.origin += skeleton.global_basis.inverse() * (actor.global_basis * stance_offset)
		skeleton.set_bone_global_pose(_hips, hips)
	var speed := planar_velocity.length()
	var moving := grounded and speed > 0.15
	_walk_phase = fmod(_walk_phase + speed * delta * 3.2, TAU)
	_walk_blend = move_toward(_walk_blend, minf(speed / 4.0, 1.0) if moving else 0.0, delta * 6.0)
	_jump_blend = move_toward(_jump_blend, 0.0 if grounded else 1.0, delta * 6.0)
	var stride := planar_velocity.normalized() * minf(0.39, speed * 0.073) * _walk_blend
	_step_leg(skeleton, _right_leg, _right_foot, stride, _walk_phase)
	_step_leg(skeleton, _left_leg, _left_foot, stride, _walk_phase + PI)

	if _head >= 0:
		var head := skeleton.get_bone_global_pose(_head)
		var head_axis := skeleton.global_basis.inverse() * actor.global_basis.x
		head.basis = Basis(head_axis.normalized(), aim_pitch) * head.basis
		skeleton.set_bone_global_pose(_head, head)

	if is_instance_valid(right_wrist) and is_instance_valid(left_wrist):
		_pose_arm(skeleton, _right_arm, right_wrist, 1.0)
		_pose_arm(skeleton, _left_arm, left_wrist, -1.0)
		_pose_fingers(skeleton, _right_arm[2], _right_fingers, [0.13, -0.13, 0.28, 0.34, 0.35])
		_pose_fingers(skeleton, _left_arm[2], _left_fingers, [
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


func _pose_fingers(skeleton: Skeleton3D, wrist: int, chains: Array[PackedInt32Array], curls: Array) -> void:
	var wrist_basis := skeleton.get_bone_global_pose(wrist).basis
	var curl_axis := wrist_basis.x.normalized()
	for digit in chains.size():
		for joint in chains[digit]:
			var pose := skeleton.get_bone_global_pose(joint)
			pose.basis = Basis(curl_axis, float(curls[digit])) * pose.basis
			skeleton.set_bone_global_pose(joint, pose)


func _step_leg(skeleton: Skeleton3D, chain: PackedInt32Array, rest: Transform3D, stride: Vector3, phase: float) -> void:
	if _walk_blend <= 0.001 and _jump_blend <= 0.001 and stance_offset.is_zero_approx():
		return
	var forward := -actor.global_basis.z
	var lift := maxf(0.0, sin(phase)) * 0.15 * _walk_blend + 0.10 * _jump_blend
	var offset := stride * cos(phase) + Vector3.UP * lift + forward * (0.06 * _jump_blend)
	var goal := rest
	goal.origin += skeleton.global_basis.inverse() * offset
	var pole := skeleton.to_local(actor.to_global(Vector3(0.0, 0.49, -1.0)))
	_solve(skeleton, chain, goal, pole)


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


static func apply_textures(avatar: Node3D) -> void:
	var upgraded: Dictionary = {}
	for mesh: MeshInstance3D in avatar.find_children("*", "MeshInstance3D", true, false):
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
