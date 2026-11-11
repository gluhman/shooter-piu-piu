extends Node3D

const CONTAINER_HEIGHT := 2.59
const CONTAINER_WIDTH := 2.44
const LENGTH_20 := 6.06
const LENGTH_40 := 12.19

const COLOR_RED := Color(0.92, 0.24, 0.18)
const COLOR_BLUE := Color(0.28, 0.48, 0.82)
const COLOR_GREEN := Color(0.28, 0.52, 0.34)
const COLOR_ORANGE := Color(0.95, 0.48, 0.14)
const COLOR_GREY := Color(0.72, 0.74, 0.72)

var _floor_mat: StandardMaterial3D
var _wall_mat: StandardMaterial3D
var _wood_mat: StandardMaterial3D
var _corr_color: Texture2D
var _corr_normal: Texture2D
var _corr_rough: Texture2D
var _corr_metal: Texture2D
var _corr_ao: Texture2D


func _ready() -> void:
	_load_textures()
	_build()


func _load_textures() -> void:
	_floor_mat = _world_mat("concrete", Color(0.58, 0.56, 0.53), 0.0, 0.85, 1.15, false)
	_wall_mat = _world_mat("bricks", Color(0.92, 0.9, 0.88), 0.0, 0.42, 1.0, true)
	_wood_mat = _world_mat("planks", Color(0.9, 0.84, 0.74), 0.0, 0.7, 1.0, true)
	_corr_color = load("res://textures/corrugated_color.jpg")
	_corr_normal = load("res://textures/corrugated_normal.jpg")
	_corr_rough = load("res://textures/corrugated_roughness.jpg")
	_corr_metal = load("res://textures/corrugated_metalness.jpg")
	_corr_ao = load("res://textures/corrugated_ao.jpg")


func _build() -> void:
	_add_box(Vector3(0.0, -0.25, 0.0), Vector3(36.0, 0.5, 36.0), _floor_mat)
	_add_box(Vector3(0.0, 2.75, -17.25), Vector3(35.0, 5.5, 0.5), _wall_mat, 0.0, "brick")
	_add_box(Vector3(0.0, 2.75, 17.25), Vector3(35.0, 5.5, 0.5), _wall_mat, 0.0, "brick")
	_add_box(Vector3(17.25, 2.75, 0.0), Vector3(0.5, 5.5, 35.0), _wall_mat, 0.0, "brick")
	_add_box(Vector3(-17.25, 2.75, 0.0), Vector3(0.5, 5.5, 35.0), _wall_mat, 0.0, "brick")

	_add_container(Vector3(-12.2, 1.295, -1.0), CONTAINER_WIDTH, LENGTH_40, COLOR_BLUE)
	_add_container(Vector3(-12.2, 3.885, -4.0), CONTAINER_WIDTH, LENGTH_20, COLOR_RED)
	_add_container(Vector3(1.0, 1.295, -10.5), LENGTH_40, CONTAINER_WIDTH, COLOR_GREEN)
	_add_container(Vector3(3.5, 3.885, -10.5), LENGTH_20, CONTAINER_WIDTH, COLOR_GREY)
	_add_container(Vector3(-1.2, 1.295, -1.6), LENGTH_20, CONTAINER_WIDTH, COLOR_ORANGE, 18.0)
	_add_container(Vector3(-3.2, 1.295, 7.2), LENGTH_40, CONTAINER_WIDTH, COLOR_RED)
	_add_container(Vector3(9.6, 1.295, 0.6), LENGTH_20, CONTAINER_WIDTH, COLOR_BLUE)
	_add_container(Vector3(9.6, 3.885, 0.6), LENGTH_20, CONTAINER_WIDTH, COLOR_ORANGE)
	_add_container(Vector3(11.9, 1.295, 5.0), CONTAINER_WIDTH, LENGTH_20, COLOR_GREEN)
	_add_container(Vector3(5.4, 1.295, 11.2), LENGTH_20, CONTAINER_WIDTH, COLOR_GREY)
	_add_container(Vector3(-11.2, 1.295, 10.2), CONTAINER_WIDTH, LENGTH_20, COLOR_BLUE)

	_add_crate(Vector3(-1.0, 0.55, 3.4))
	_add_crate(Vector3(0.3, 0.55, 4.2))
	_add_crate(Vector3(1.5, 0.55, 3.2))
	_add_crate(Vector3(-0.2, 1.65, 3.7))
	_add_crate(Vector3(6.2, 0.55, -4.2))
	_add_crate(Vector3(7.4, 0.55, -3.5))


func _add_container(center: Vector3, size_x: float, size_z: float, color: Color, yaw_deg: float = 0.0) -> void:
	var size := Vector3(size_x, CONTAINER_HEIGHT, size_z)
	var body := _add_box(center, size, _container_mat(color), yaw_deg, "metal")
	var door := MeshInstance3D.new()
	var door_mesh := BoxMesh.new()
	var along_x := size_x >= size_z
	if along_x:
		door_mesh.size = Vector3(0.08, size.y * 0.78, size.z * 0.8)
		door.position = Vector3(size.x * 0.5 + 0.01, 0.0, 0.0)
	else:
		door_mesh.size = Vector3(size.x * 0.8, size.y * 0.78, 0.08)
		door.position = Vector3(0.0, 0.0, size.z * 0.5 + 0.01)
	door_mesh.material = _container_mat(color.darkened(0.28))
	door.mesh = door_mesh
	body.add_child(door)


func _add_crate(center: Vector3) -> void:
	_add_box(center, Vector3(1.15, 1.1, 1.15), _wood_mat, 0.0, "wood")


func _add_box(center: Vector3, size: Vector3, material: Material, yaw_deg: float = 0.0, surface: String = "concrete") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta(&"impact_surface", surface)
	body.position = center
	body.rotation.y = deg_to_rad(yaw_deg)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(mesh_instance)
	body.add_child(collision)
	add_child(body)
	return body


func _container_mat(tint: Color) -> StandardMaterial3D:
	var mat := _textured("corrugated", tint, 0.85, 0.48, 1.0, true)
	mat.metallic_texture = _corr_metal
	mat.metallic_texture_channel = StandardMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	return mat


func _world_mat(name: String, tint: Color, metallic: float, scale: float, normal_scale: float, ao: bool) -> StandardMaterial3D:
	return _textured(name, tint, metallic, scale, normal_scale, ao)


func _textured(name: String, tint: Color, metallic: float, scale: float, normal_scale: float, ao: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _tex(name, "color")
	mat.albedo_color = tint
	mat.normal_enabled = true
	mat.normal_texture = _tex(name, "normal")
	mat.normal_scale = normal_scale
	mat.roughness_texture = _tex(name, "roughness")
	mat.roughness_texture_channel = StandardMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	mat.metallic = metallic
	if ao:
		mat.ao_enabled = true
		mat.ao_texture = _tex(name, "ao")
		mat.ao_texture_channel = StandardMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
		mat.ao_light_affect = 0.35
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(scale, scale, scale)
	mat.uv1_triplanar_sharpness = 1.4
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


func _tex(name: String, kind: String) -> Texture2D:
	if name == "corrugated":
		match kind:
			"color":
				return _corr_color
			"normal":
				return _corr_normal
			"roughness":
				return _corr_rough
			"ao":
				return _corr_ao
	return load("res://textures/%s_%s.jpg" % [name, kind])
