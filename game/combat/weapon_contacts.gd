extends RefCounted
## Model-local, surface-authored palm and fingertip contacts. See docs/weapon-rigging.md.
const PATH := "res://assets/weapon_contacts.json"
const DIGITS := ["thumb", "index", "middle", "ring", "pinky"]
static var profiles: Dictionary = {}

static func install(id: String, model: Node3D, right: Marker3D, left: Marker3D) -> void:
	if profiles.is_empty() and FileAccess.file_exists(PATH):
		profiles = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not profiles.has(id):
		if id != "knife":
			push_warning("Missing firearm surface contacts: " + id + ". Follow docs/weapon-rigging.md.")
		return
	var profile: Dictionary = profiles[id]
	for side in ["right", "left"]:
		var wrist := right if side == "right" else left
		var data: Dictionary = profile[side]
		if side == "left": wrist.set_meta(&"support_kind", data.get("support_kind", "pistol_cup"))
		var frame: Array = data.get("basis", [])
		if frame.size() == 3:
			wrist.basis = model.basis.orthonormalized() * Basis(vector(frame[0]), vector(frame[1]), vector(frame[2]))
		var palm_point := model.to_global(vector(data.palm))
		if data.has("palm_offset"):
			palm_point += model.global_basis.orthonormalized() * vector(data.palm_offset)
		elif data.has("palm_normal"):
			palm_point += model.global_basis.orthonormalized() * vector(data.palm_normal) * 0.006
		wrist.position = wrist.get_parent().to_local(palm_point)
		wrist.set_meta(&"finger_curls", data.get("curl", []))
		wrist.set_meta(&"finger_splay", data.get("splay", []))
		wrist.set_meta(&"thumb_roll", float(data.get("thumb_roll", 0.0)))
		wrist.set_meta(&"thumb_reference", bool(data.get("thumb_reference", false)))
		wrist.set_meta(&"thumb_pose", String(data.get("thumb_pose", "")))
		for digit in DIGITS:
			var target := Marker3D.new()
			target.name = "Contact_" + digit
			wrist.add_child(target)
			target.global_position = model.to_global(vector(data[digit]))
			if data.has(digit + "_normal"):
				target.global_position += model.global_basis.orthonormalized() * vector(data[digit + "_normal"]) * 0.004

static func vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

static func array(value: Vector3) -> Array:
	return [snappedf(value.x, 0.00001), snappedf(value.y, 0.00001), snappedf(value.z, 0.00001)]

# Baking/validation helper. Vertices are transformed into physical metres in root space.
static func triangles(model: Node3D, root: Node3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var transform := root.global_transform.affine_inverse() * instance.global_transform
		var faces := instance.mesh.get_faces()
		for point in faces:
			result.append(transform * point)
	return result

static func nearest(point: Vector3, faces: PackedVector3Array) -> Vector3:
	var best := point
	var distance := INF
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var plane := Plane(a, b, c)
		var projected := plane.project(point)
		var candidate := projected
		if not _inside(projected, a, b, c):
			candidate = Geometry3D.get_closest_point_to_segment(point, a, b)
			for edge in [Geometry3D.get_closest_point_to_segment(point, b, c), Geometry3D.get_closest_point_to_segment(point, c, a)]:
				if point.distance_squared_to(edge) < point.distance_squared_to(candidate):
					candidate = edge
		var gap := point.distance_squared_to(candidate)
		if gap < distance:
			distance = gap
			best = candidate
	return best

static func _inside(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var normal := (b - a).cross(c - a)
	return normal.length_squared() > 0.0000000001 and (b - a).cross(p - a).dot(normal) >= 0.0 and (c - b).cross(p - b).dot(normal) >= 0.0 and (a - c).cross(p - c).dot(normal) >= 0.0
