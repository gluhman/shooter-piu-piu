extends Node3D

const Balance := preload("res://game/combat/combat_balance.gd")
const LAYER := Balance.HURTBOX_MASK
const HISTORY_SECONDS: float = Balance.NETWORK.hitbox_history_s
const PREFIX := "mixamorig_"
# Segments follow the rendered rig. Trimming the ends keeps adjacent zones from overlapping at joints.
const SEGMENTS := [
	["head", "Head_06", "HeadTop_End_07", 0.105, 0.36, 0.80],
	["neck", "Neck_05", "Head_06", 0.065, 0.08, 0.78],
	["chest", "Spine1_03", "Neck_05", 0.125, 0.09, 0.94],
	["abdomen", "Spine_02", "Spine1_03", 0.108, 0.0, 1.0],
	["pelvis", "Hips_01", "Spine_02", 0.112, 0.0, 0.90],
	["upper_arm", "RightArm_09", "RightForeArm_010", 0.069, 0.12, 0.92],
	["forearm_hand", "RightForeArm_010", "RightHand_011", 0.051, 0.08, 1.25],
	["upper_arm", "LeftArm_033", "LeftForeArm_034", 0.069, 0.12, 0.92],
	["forearm_hand", "LeftForeArm_034", "LeftHand_035", 0.051, 0.08, 1.25],
	["thigh", "RightUpLeg_057", "RightLeg_058", 0.091, 0.13, 0.92],
	["calf_foot", "RightLeg_058", "RightFoot_059", 0.070, 0.07, 1.10],
	["thigh", "LeftUpLeg_063", "LeftLeg_064", 0.091, 0.13, 0.92],
	["calf_foot", "LeftLeg_064", "LeftFoot_065", 0.070, 0.07, 1.10],
]

var _skeleton: Skeleton3D
var _operator_pose: SkeletonModifier3D
var _areas: Array[Area3D]
var _shapes: Array[Shape3D]
var _history: Array[Dictionary]
var _starts: PackedInt32Array
var _ends: PackedInt32Array
var _centers: Dictionary[String, Area3D]


func _enter_tree() -> void:
	if is_instance_valid(_operator_pose):
		_operator_pose.modification_processed.connect(update_pose)


func _exit_tree() -> void:
	if is_instance_valid(_operator_pose) and _operator_pose.modification_processed.is_connected(update_pose):
		_operator_pose.modification_processed.disconnect(update_pose)
	reset_history()


func setup(skeleton: Skeleton3D, operator_pose: SkeletonModifier3D) -> void:
	_skeleton = skeleton
	_operator_pose = operator_pose
	for segment in SEGMENTS:
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false
		area.set_meta(&"hit_zone", segment[0])
		var collision := CollisionShape3D.new()
		match segment[0]:
			"chest", "abdomen", "pelvis":
				var box := BoxShape3D.new()
				var width := 0.38 if segment[0] == "chest" else 0.32
				box.size = Vector3(width, 0.15, float(segment[3]) * 2.0)
				collision.shape = box
			_:
				var capsule := CapsuleShape3D.new()
				capsule.radius = segment[3]
				collision.shape = capsule
		area.add_child(collision)
		add_child(area)
		_starts.append(skeleton.find_bone(PREFIX + segment[1]))
		_ends.append(skeleton.find_bone(PREFIX + segment[2]))
		_areas.append(area)
		_shapes.append(collision.shape)
		_centers[segment[0]] = area
	if is_inside_tree():
		update_pose()
		operator_pose.modification_processed.connect(update_pose)


func set_active(active: bool) -> void:
	for area in _areas:
		area.set_deferred("collision_layer", LAYER if active else 0)


func center(zone: String) -> Vector3:
	return _centers[zone].global_position


func update_pose() -> void:
	if not is_inside_tree() or not is_instance_valid(_skeleton) or not _skeleton.is_inside_tree():
		return
	var actor := get_parent() as Node3D
	if not actor or not actor.is_inside_tree():
		return
	var actor_basis := actor.global_basis.orthonormalized()
	var skeleton_transform := _skeleton.global_transform
	for index in _areas.size():
		var area := _areas[index]
		if not area.is_inside_tree():
			continue
		var segment: Array = SEGMENTS[index]
		var start := skeleton_transform * _skeleton.get_bone_global_pose(_starts[index]).origin
		var end := skeleton_transform * _skeleton.get_bone_global_pose(_ends[index]).origin
		var from := start.lerp(end, segment[4])
		var to := start.lerp(end, segment[5])
		var axis := to - from
		var length := axis.length()
		var shape := _shapes[index]
		if shape is BoxShape3D:
			var size: Vector3 = shape.size
			if not is_equal_approx(size.y, length):
				size.y = length
				shape.size = size
		else:
			var height := maxf(length, shape.radius * 2.0)
			if not is_equal_approx(shape.height, height):
				shape.height = height
		var swing := Basis(Quaternion(Vector3.UP, axis / length)) if length > 0.0001 else Basis.IDENTITY
		area.global_transform = Transform3D(swing * actor_basis, (from + to) * 0.5)


func reset_history() -> void:
	_history.clear()


func record_pose(time: float, correction: Transform3D) -> void:
	var transforms: Array[Transform3D] = []
	var dimensions := PackedVector3Array()
	for index in _areas.size():
		transforms.append(correction * _areas[index].global_transform)
		var shape := _shapes[index]
		if shape is BoxShape3D:
			dimensions.append(shape.size)
		else:
			dimensions.append(Vector3(shape.radius, shape.height, 0.0))
	_history.append({"time": time, "transforms": transforms, "dimensions": dimensions})
	while _history.size() > 2 and _history[1].time < time - HISTORY_SECONDS:
		_history.pop_front()


func rewound_ray(from: Vector3, to: Vector3, time: float) -> Dictionary:
	if _history.is_empty():
		return {}
	var before := _history[0]
	var after := _history.back() as Dictionary
	for index in range(1, _history.size()):
		if _history[index].time >= time:
			before = _history[index - 1]
			after = _history[index]
			break
	var blend := 0.0
	if after.time > before.time:
		blend = clampf(inverse_lerp(before.time, after.time, time), 0.0, 1.0)
	var nearest := INF
	var result := {}
	for index in _areas.size():
		var frame: Transform3D = before.transforms[index].interpolate_with(after.transforms[index], blend)
		var size: Vector3 = before.dimensions[index].lerp(after.dimensions[index], blend)
		var inverse := frame.affine_inverse()
		var local_from := inverse * from
		var local_to := inverse * to
		var impact = _shape_ray(local_from, local_to, size)
		if impact == null:
			continue
		var distance := local_from.distance_squared_to(impact)
		# SEGMENTS is ordered by zone priority for equal-depth intersections.
		if distance < nearest - 0.000001:
			nearest = distance
			result = {"collider": _areas[index], "position": frame * impact, "normal": Vector3.ZERO}
	return result


func _shape_ray(from: Vector3, to: Vector3, size: Vector3) -> Variant:
	if size.z > 0.0:
		var bounds := AABB(-size * 0.5, size)
		return from if bounds.has_point(from) else bounds.intersects_segment(from, to)
	var radius := size.x
	var half_axis := maxf(0.0, size.y * 0.5 - radius)
	var nearest_axis := Vector3(0.0, clampf(from.y, -half_axis, half_axis), 0.0)
	if from.distance_squared_to(nearest_axis) <= radius * radius:
		return from
	var segment := to - from
	var planar := Vector2(segment.x, segment.z)
	var start := Vector2(from.x, from.z)
	var a := planar.length_squared()
	var b := start.dot(planar)
	var discriminant := b * b - a * (start.length_squared() - radius * radius)
	var closest = null
	if a > 0.000001 and discriminant >= 0.0:
		var fraction := (-b - sqrt(discriminant)) / a
		var height := from.y + segment.y * fraction
		if fraction >= 0.0 and fraction <= 1.0 and absf(height) <= half_axis:
			closest = from + segment * fraction
	for cap in [-half_axis, half_axis]:
		var contact := Geometry3D.segment_intersects_sphere(from, to, Vector3(0.0, cap, 0.0), radius)
		if not contact.is_empty() and (closest == null or from.distance_squared_to(contact[0]) < from.distance_squared_to(closest)):
			closest = contact[0]
	return closest
