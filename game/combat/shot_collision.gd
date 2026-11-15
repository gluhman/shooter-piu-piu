extends RefCounted

const BALANCE := preload("res://game/combat/combat_balance.gd")


static func detail_for(proxy: StaticBody3D) -> StaticBody3D:
	proxy.collision_layer = BALANCE.MOVEMENT_PROXY_MASK
	var detail := StaticBody3D.new()
	detail.name = "ShotGeometry"
	detail.collision_layer = BALANCE.SHOT_GEOMETRY_MASK
	detail.collision_mask = 0
	detail.set_meta(&"impact_surface", proxy.get_meta(&"impact_surface"))
	proxy.add_child(detail)
	return detail


static func use_model(proxy: StaticBody3D, model: Node3D, exclude: Node3D = null) -> StaticBody3D:
	var detail := detail_for(proxy)
	add_meshes(detail, model, exclude)
	return detail


static func add_meshes(body: PhysicsBody3D, node: Node3D, exclude: Node3D = null) -> void:
	if node == exclude:
		return
	if node is MeshInstance3D and node.mesh:
		var faces: PackedVector3Array = node.mesh.get_faces()
		if not faces.is_empty():
			var relative := body.global_transform.affine_inverse() * node.global_transform
			for index in faces.size():
				faces[index] = relative * faces[index]
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			shape.backface_collision = true
			_add_shape(body, shape, Transform3D.IDENTITY)
	for child in node.get_children():
		if child is Node3D and child != body:
			add_meshes(body, child, exclude)


static func add_box(body: StaticBody3D, size: Vector3, world: Transform3D) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	_add_shape(body, shape, body.global_transform.affine_inverse() * world)


static func _add_shape(body: PhysicsBody3D, shape: Shape3D, local: Transform3D) -> void:
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = local
	body.add_child(collider)
