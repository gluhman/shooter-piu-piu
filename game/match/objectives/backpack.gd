extends RefCounted

const FABRIC := preload("res://assets/objectives/hessian_380_nor_gl_1k.jpg")
const METAL := preload("res://assets/arsenal/metal_plate_02_diff.jpg")


static func attach(socket: Node3D, body_layer: int) -> void:
	var fabric := StandardMaterial3D.new()
	fabric.albedo_color = Color("#605d45")
	fabric.roughness = 0.95
	fabric.normal_enabled = true
	fabric.normal_texture = FABRIC
	fabric.uv1_scale = Vector3(2.5, 2.5, 1.0)
	var straps := fabric.duplicate() as StandardMaterial3D
	straps.albedo_color = Color("#393d30")
	var hardware := StandardMaterial3D.new()
	hardware.albedo_texture = METAL
	hardware.albedo_color = Color("#646351")
	hardware.roughness = 0.76
	var pack := Node3D.new()
	pack.name = "ChargeBackpack"
	socket.add_child(pack)
	_piece(pack, Vector3(0, 0.025, 0), Vector3(0.39, 0.47, 0.19), fabric, body_layer)
	_piece(pack, Vector3(0, -0.085, 0.11), Vector3(0.30, 0.24, 0.10), fabric, body_layer)
	_piece(pack, Vector3(0, 0.225, 0.068), Vector3(0.38, 0.095, 0.15), fabric, body_layer)
	for side: float in [-1.0, 1.0]:
		_piece(pack, Vector3(side * 0.119, 0.07, 0.17), Vector3(0.035, 0.32, 0.014), straps, body_layer)
		_piece(pack, Vector3(side * 0.119, 0.05, 0.182), Vector3(0.058, 0.045, 0.017), hardware, body_layer)
	_piece(pack, Vector3(0, 0.285, 0.025), Vector3(0.14, 0.032, 0.04), straps, body_layer)


static func _piece(parent: Node3D, at: Vector3, extent: Vector3, finish: Material, body_layer: int) -> void:
	var mesh := BoxMesh.new()
	mesh.size = extent
	var item := MeshInstance3D.new()
	item.material_override = finish
	item.mesh = mesh
	item.position = at
	item.layers = 1 << (body_layer - 1)
	parent.add_child(item)
