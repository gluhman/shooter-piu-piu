extends Node3D

const Balance := preload("res://game/combat/combat_balance.gd")
const OperatorPose := preload("res://game/actors/operator_pose.gd")
const SIMULATION_SECONDS := 4.0
const BONE_PREFIX := "mixamorig_"
# Bone, end of its capsule, radius, mass, joint swing and twist limits.
const SEGMENTS := [
	["Hips_01", "Spine1_03", 0.145, 12.0, 0.0, 0.0],
	["Spine2_04", "Neck_05", 0.165, 17.0, 22.0, 14.0],
	["Head_06", "HeadTop_End_07", 0.095, 4.2, 28.0, 22.0],
	["RightArm_09", "RightForeArm_010", 0.060, 2.3, 75.0, 35.0],
	["RightForeArm_010", "RightHand_011", 0.052, 1.7, 64.0, 10.0],
	["LeftArm_033", "LeftForeArm_034", 0.060, 2.3, 75.0, 35.0],
	["LeftForeArm_034", "LeftHand_035", 0.052, 1.7, 64.0, 10.0],
	["RightUpLeg_057", "RightLeg_058", 0.086, 7.0, 58.0, 19.0],
	["RightLeg_058", "RightFoot_059", 0.061, 4.0, 78.0, 8.0],
	["RightFoot_059", "RightToeBase_060", 0.063, 1.0, 27.0, 12.0],
	["LeftUpLeg_063", "LeftLeg_064", 0.086, 7.0, 58.0, 19.0],
	["LeftLeg_064", "LeftFoot_065", 0.061, 4.0, 78.0, 8.0],
	["LeftFoot_065", "LeftToeBase_066", 0.063, 1.0, 27.0, 12.0],
]
const HIT_SEGMENTS := {"head": [2], "neck": [2], "chest": [1], "abdomen": [0], "pelvis": [0],
	"upper_arm": [3, 5], "forearm_hand": [4, 6], "thigh": [7, 10], "calf_foot": [8, 11]}

var _skeleton: Skeleton3D
var _simulator: PhysicalBoneSimulator3D
var _bodies: Array[PhysicalBone3D] = []
var _indices: PackedInt32Array
var _simulating := false


func build(has_armor: bool, state: Dictionary, animate: bool) -> void:
	var avatar := OperatorPose.MODEL.instantiate() as Node3D
	avatar.rotation.y = PI
	avatar.scale = Vector3.ONE * 0.96
	avatar.position = Vector3(0.169, 0.0, -0.041)
	add_child(avatar)
	OperatorPose.apply_textures(avatar)
	avatar.find_child(OperatorPose.VEST_MESH, true, false).visible = has_armor
	avatar.find_child("Object_111", true, false).hide()
	_skeleton = avatar.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton.reset_bone_poses()
	for segment in SEGMENTS:
		_indices.append(_skeleton.find_bone(BONE_PREFIX + segment[0]))
	var pose: Array = state.get("pose", [])
	if pose.size() == _skeleton.get_bone_count():
		for index in pose.size():
			_skeleton.set_bone_pose(index, pose[index])
	if not animate:
		_apply_settled_pose(state.get("settled", []))
	if animate or state.has("motion"):
		_start_fall.call_deferred(state)


func _start_fall(state: Dictionary) -> void:
	if get_parent().is_queued_for_deletion():
		return
	_simulator = PhysicalBoneSimulator3D.new()
	_skeleton.add_child(_simulator)
	for index in SEGMENTS.size():
		var segment: Array = SEGMENTS[index]
		var rest := _skeleton.get_bone_global_rest(_indices[index])
		var end := _skeleton.get_bone_global_rest(_skeleton.find_bone(BONE_PREFIX + segment[1]))
		var span := rest.affine_inverse() * end.origin
		var radius: float = segment[2]
		var body := PhysicalBone3D.new()
		body.set("bone_name", _skeleton.get_bone_name(_indices[index]))
		body.collision_layer = 0
		body.collision_mask = Balance.WORLD_MASK
		body.mass = segment[3]
		body.linear_damp = 0.45
		body.angular_damp = 2.2
		body.friction = 0.75
		var axis := span.normalized()
		body.body_offset = Transform3D(Basis(Quaternion(Vector3.UP, axis)), span * 0.5)
		if index != 0:
			body.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			body.set("joint_constraints/swing_span", segment[4])
			body.set("joint_constraints/twist_span", segment[5])
		var capsule := CapsuleShape3D.new()
		capsule.radius = radius
		capsule.height = maxf(radius * 2.0, span.length() + radius * 0.7)
		var collision := CollisionShape3D.new()
		collision.shape = capsule
		body.add_child(collision)
		_simulator.add_child(body)
		_bodies.append(body)
	_simulator.physical_bones_start_simulation()
	_simulating = true
	get_tree().create_timer(SIMULATION_SECONDS, false, true).timeout.connect(_settle)

	var motion: PackedVector3Array = state.get("motion", PackedVector3Array())
	if motion.size() == _bodies.size() * 2:
		for index in _bodies.size():
			_bodies[index].linear_velocity = motion[index * 2]
			_bodies[index].angular_velocity = motion[index * 2 + 1]
		return
	var shove: Vector3 = state.get("velocity", -global_basis.z)
	var zone: String = state.get("zone", "chest")
	var point: Vector3 = state.get("point", global_position + Vector3.UP)
	var drift: Vector3 = state.get("drift", Vector3.ZERO)
	var blast := zone == "blast"
	var pivot := _bodies[0].global_position
	var spin := Vector3.UP.cross(shove.normalized()) * 4.2 if blast else Vector3.ZERO
	for body in _bodies:
		body.linear_velocity = drift + shove * (1.0 if blast else 0.30) + spin.cross(body.global_position - pivot)
		body.angular_velocity = spin
	var struck := _closest_segment(HIT_SEGMENTS.get(zone, [0, 1]), point)
	struck.apply_impulse(shove * struck.mass * (0.32 if blast else 1.1),
		(point - struck.global_position).limit_length(0.23))


func _closest_segment(indices: Array, point: Vector3) -> PhysicalBone3D:
	var closest := _bodies[indices[0]]
	for index in indices:
		var body := _bodies[index]
		if body.global_position.distance_squared_to(point) < closest.global_position.distance_squared_to(point):
			closest = body
	return closest


func snapshot() -> Dictionary:
	var pose: Array[Transform3D] = []
	for index in _skeleton.get_bone_count():
		pose.append(_skeleton.get_bone_pose(index))
	var state := {"pose": pose, "settled": _body_pose()}
	if _simulating:
		var motion := PackedVector3Array()
		for body in _bodies:
			motion.append(body.linear_velocity)
			motion.append(body.angular_velocity)
		state["motion"] = motion
	return state


func _body_pose() -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	for index in _indices.size():
		var transform := _skeleton.get_bone_global_pose(_indices[index])
		if _simulating:
			var body := _bodies[index]
			transform = _skeleton.global_transform.affine_inverse() * body.global_transform * body.body_offset.affine_inverse()
		transforms.append(transform)
	return transforms


func _settle() -> void:
	var settled := _body_pose()
	_simulating = false
	_simulator.physical_bones_stop_simulation()
	_simulator.queue_free()
	_bodies.clear()
	_apply_settled_pose(settled)


func _apply_settled_pose(transforms: Array) -> void:
	for index in mini(transforms.size(), _indices.size()):
		_skeleton.set_bone_global_pose(_indices[index], transforms[index])
