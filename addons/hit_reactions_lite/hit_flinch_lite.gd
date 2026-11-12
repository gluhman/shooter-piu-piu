@tool
class_name HitFlinchLite
extends SkeletonModifier3D
## Physical Hit Reactions Lite: a simple procedural flinch on an animated humanoid.
##
## Call [method hit] with a world point and an impulse. The bone nearest the
## point (and, less, its parents up the spine) twists away from the hit and
## springs back to the animation. No physics bodies, no ragdoll.
##
## The full Physical Hit Reactions adds a real partial ragdoll on top of the
## animation, flinch / stagger / knockdown levels, recovery from a fall, hit
## boxes, blasts, thrown-object hits and a tuning panel:
## https://dangalg.itch.io/physical-hit-reactions-godot

## Emitted on every hit with the bone name that was hit.
signal flinched(bone_name: StringName)

## How strongly hits twist the body.
@export_range(0.0, 5.0, 0.01) var strength: float = 1.0
## Largest twist of a single bone, in degrees.
@export_range(5.0, 80.0, 1.0) var max_angle_deg: float = 45.0

## Bones that can be hit (others are mapped to the nearest of these). Empty = auto-detect.
@export var hit_bones: PackedStringArray = PackedStringArray()

const _AUTO: Array = [
	["DEF-hips", "DEF-spine.001", "DEF-spine.002", "DEF-spine.003", "DEF-neck", "DEF-head",
		"DEF-upper_arm.L", "DEF-forearm.L", "DEF-upper_arm.R", "DEF-forearm.R"],
	["mixamorig:Hips", "mixamorig:Spine", "mixamorig:Spine1", "mixamorig:Spine2", "mixamorig:Neck", "mixamorig:Head",
		"mixamorig:LeftArm", "mixamorig:LeftForeArm", "mixamorig:RightArm", "mixamorig:RightForeArm"],
	["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
		"LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm"],
]
const _STIFFNESS: float = 140.0
const _DAMPING: float = 15.0
const _PARENT_SHARE: float = 0.45

var _bones: PackedInt32Array = PackedInt32Array()
var _rot: Dictionary = {}  # bone -> Vector3 (axis * angle, skeleton space)
var _vel: Dictionary = {}  # bone -> Vector3


## Hit the character at [param point] (world) with [param impulse] (world, N*s-ish).
func hit(point: Vector3, impulse: Vector3) -> void:
	var skel: Skeleton3D = get_skeleton()
	if skel == null or not skel.is_inside_tree() or not point.is_finite() or not impulse.is_finite() \
			or impulse.is_zero_approx() or not _ensure(skel):
		return
	var inv: Transform3D = skel.global_transform.affine_inverse()
	var p: Vector3 = inv * point
	var imp: Vector3 = inv.basis * impulse
	var best: int = -1
	var best_d: float = INF
	for b: int in _bones:
		var d: float = _segment_distance(skel, b, p)
		if d < best_d:
			best_d = d
			best = b
	if best < 0:
		return
	var share: float = 1.0
	var b: int = best
	while b >= 0 and share > 0.05:
		if _bones.has(b):
			var pivot: Vector3 = skel.get_bone_global_pose(b).origin
			var spin: Vector3 = (p - pivot).cross(imp) * strength * 14.0 * share
			_vel[b] = ((_vel.get(b, Vector3.ZERO) as Vector3) + spin).limit_length(20.0)
			_rot[b] = _rot.get(b, Vector3.ZERO)
			share *= _PARENT_SHARE
		b = skel.get_bone_parent(b)
	flinched.emit(skel.get_bone_name(best))


## Current twist of a bone in degrees (0 when calm). For tests and gameplay.
func get_twist_deg(bone_name: String) -> float:
	var skel: Skeleton3D = get_skeleton()
	if skel == null:
		return 0.0
	return rad_to_deg((_rot.get(skel.find_bone(bone_name), Vector3.ZERO) as Vector3).length())


func reset() -> void:
	_rot.clear()
	_vel.clear()


func _ensure(skel: Skeleton3D) -> bool:
	if not _bones.is_empty():
		return true
	var lists: Array = [hit_bones] if not hit_bones.is_empty() else _AUTO
	for names: Variant in lists:
		var found := PackedInt32Array()
		for n: String in names:
			var i: int = skel.find_bone(n)
			if i >= 0:
				found.append(i)
		if found.size() >= 4:
			found.sort()
			_bones = found
			return true
	push_warning("HitFlinchLite: no hit bones found; set hit_bones by name.")
	return false


func _segment_distance(skel: Skeleton3D, b: int, p: Vector3) -> float:
	var a: Vector3 = skel.get_bone_global_pose(b).origin
	var e: Vector3 = a
	for c: int in skel.get_bone_children(b):
		e = skel.get_bone_global_pose(c).origin
		break
	var ab: Vector3 = e - a
	var t: float = 0.0 if ab.length_squared() < 1e-8 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _process_modification_with_delta(delta: float) -> void:
	var skel: Skeleton3D = get_skeleton()
	if skel == null or _rot.is_empty():
		return
	var elapsed := clampf(delta, 0.0, 0.1)
	var steps := maxi(1, ceili(elapsed * 120.0))
	var dt := elapsed / steps
	var max_a: float = deg_to_rad(max_angle_deg)
	var calm: Array = []
	for b: int in _bones:
		if not _rot.has(b):
			continue
		var r: Vector3 = _rot[b]
		var v: Vector3 = _vel[b]
		for _step in steps:
			v += (-_STIFFNESS * r - _DAMPING * v) * dt
			r += v * dt
		if r.length() > max_a:
			r = r.normalized() * max_a
			v *= 0.5
		_rot[b] = r
		_vel[b] = v
		if r.length() < 0.0005 and v.length() < 0.005:
			calm.append(b)
			continue
		if not r.is_zero_approx():
			var g: Transform3D = skel.get_bone_global_pose(b)
			skel.set_bone_global_pose(b, Transform3D(Basis(r.normalized(), r.length()) * g.basis, g.origin))
	for b: int in calm:
		_rot.erase(b)
		_vel.erase(b)
