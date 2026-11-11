extends Node3D

const GRASS := preload("res://assets/arena_props/grass.glb")
const SHRUBS := preload("res://assets/arena_props/shrubs.glb")

const CONTAINER_HEIGHT := 2.59
const CONTAINER_WIDTH := 2.44
const LENGTH_20 := 6.06
const LENGTH_40 := 12.19

const PANEL_THICKNESS := 0.12
const CRATE_SIGHT_RADIUS := 15.0
const MAX_SUPPLY_CRATES := 6

class Cover:
	var center: Vector2
	var half_size: Vector2
	var yaw: float

const COLOR_RED := Color(0.92, 0.24, 0.18)
const COLOR_BLUE := Color(0.28, 0.48, 0.82)
const COLOR_GREEN := Color(0.28, 0.52, 0.34)
const COLOR_ORANGE := Color(0.95, 0.48, 0.14)
const COLOR_GREY := Color(0.72, 0.74, 0.72)

const MAP_NAMES := ["Контейнерный двор", "Складские ряды", "Перекрёсток"]

# Clear perimeter positions shared by all three arena layouts.
const PLAYER_SPAWNS := [
	Vector3(-14.6, 0.2, 14.2), Vector3(14.2, 0.2, -14.2),
	Vector3(-14.5, 0.2, -14.5), Vector3(14.5, 0.2, 14.5),
	Vector3(-5, 0.2, 15), Vector3(5, 0.2, -15),
	Vector3(-15, 0.2, -5), Vector3(15, 0.2, 5),
	Vector3(5, 0.2, 15), Vector3(-5, 0.2, -15),
]

const BOT_SPAWNS := [
	Vector3(12, 0.2, -12), Vector3(0, 0.2, -14), Vector3(-7, 0.2, -14),
	Vector3(-14, 0.2, -12), Vector3(-15, 0.2, -3), Vector3(-15, 0.2, 5),
	Vector3(-8, 0.2, 14), Vector3(0, 0.2, 14), Vector3(8, 0.2, 14),
	Vector3(15, 0.2, 8),
]
const RESERVED_SPAWNS := PLAYER_SPAWNS + BOT_SPAWNS

const PATROL_ROUTES := [
	[
		Vector3(15, 0.2, -15), Vector3(-15, 0.2, -15),
		Vector3(-15, 0.2, 15), Vector3(15, 0.2, 15),
	],
	[
		Vector3(15, 0.2, -15), Vector3(-15, 0.2, -15), Vector3(-15, 0.2, 0),
		Vector3(15, 0.2, 0), Vector3(15, 0.2, 15), Vector3(-15, 0.2, 15),
		Vector3(-15, 0.2, -15),
	],
	[
		Vector3(15, 0.2, 15), Vector3(15, 0.2, -15), Vector3(0, 0.2, -15),
		Vector3(0, 0.2, 15), Vector3(-15, 0.2, 15), Vector3(-15, 0.2, -15),
		Vector3(15, 0.2, -15),
	],
]

var _occupied: Array[Rect2] = []
var _cover: Array[Cover] = []
var _passages: Array[Transform3D] = []
var _floor_mat: StandardMaterial3D
var _wall_mat: StandardMaterial3D
var _wood_mat: StandardMaterial3D
var _corr_color: Texture2D
var _corr_normal: Texture2D
var _corr_rough: Texture2D
var _corr_metal: Texture2D
var _corr_ao: Texture2D


func _load_textures() -> void:
	_floor_mat = _world_mat("concrete", Color(0.58, 0.56, 0.53), 0.0, 0.85, 1.15, false)
	_wall_mat = _world_mat("bricks", Color(0.92, 0.9, 0.88), 0.0, 0.42, 1.0, true)
	_wood_mat = _world_mat("planks", Color(0.9, 0.84, 0.74), 0.0, 0.7, 1.0, true)
	_corr_color = load("res://textures/corrugated_color.jpg")
	_corr_normal = load("res://textures/corrugated_normal.jpg")
	_corr_rough = load("res://textures/corrugated_roughness.jpg")
	_corr_metal = load("res://textures/corrugated_metalness.jpg")
	_corr_ao = load("res://textures/corrugated_ao.jpg")


func build(map_id: int, layout_seed: int = 0) -> Array[Transform3D]:
	_load_textures()
	_add_box(Vector3(0.0, -0.25, 0.0), Vector3(36.0, 0.5, 36.0), _floor_mat)
	_add_box(Vector3(0.0, 2.75, -17.25), Vector3(35.0, 5.5, 0.5), _wall_mat, 0.0, "brick")
	_add_box(Vector3(0.0, 2.75, 17.25), Vector3(35.0, 5.5, 0.5), _wall_mat, 0.0, "brick")
	_add_box(Vector3(17.25, 2.75, 0.0), Vector3(0.5, 5.5, 35.0), _wall_mat, 0.0, "brick")
	_add_box(Vector3(-17.25, 2.75, 0.0), Vector3(0.5, 5.5, 35.0), _wall_mat, 0.0, "brick")

	match map_id:
		1: _build_storage()
		2: _build_crossroads()
		_: _build_container_yard()
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	_scatter_passages(rng)
	var crates := _scatter_crates(rng)
	_scatter_foliage(rng)
	return crates


func _build_container_yard() -> void:
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


func _build_storage() -> void:
	for x in [-9.0, 0.0, 9.0]:
		_add_container(Vector3(x, 1.295, -7.0), CONTAINER_WIDTH, LENGTH_40, COLOR_BLUE)
		_add_container(Vector3(x, 1.295, 7.0), CONTAINER_WIDTH, LENGTH_40, COLOR_GREEN)
	_add_container(Vector3(0, 3.885, -8), CONTAINER_WIDTH, LENGTH_20, COLOR_ORANGE)
	_add_container(Vector3(9, 3.885, 8), CONTAINER_WIDTH, LENGTH_20, COLOR_GREY)
	_add_crate(Vector3(-4.5, 0.55, -4))
	_add_crate(Vector3(4.5, 0.55, 4))


func _build_crossroads() -> void:
	for x in [-8.0, 8.0]:
		for z in [-8.0, 8.0]:
			var color := COLOR_RED if x * z > 0 else COLOR_ORANGE
			_add_container(Vector3(x, 1.295, z), LENGTH_40, CONTAINER_WIDTH, color)
			_add_container(Vector3(x, 3.885, z), LENGTH_20, CONTAINER_WIDTH, COLOR_GREY)
			_add_crate(Vector3(x, 0.55, z * 0.5))
			_add_crate(Vector3(x * 0.75, 0.55, z * 0.5))


func _add_container(center: Vector3, size_x: float, size_z: float, color: Color, yaw_deg: float = 0.0) -> void:
	var size := Vector3(size_x, CONTAINER_HEIGHT, size_z)
	var yaw := deg_to_rad(yaw_deg)
	var width := absf(cos(yaw)) * size_x + absf(sin(yaw)) * size_z
	var depth := absf(sin(yaw)) * size_x + absf(cos(yaw)) * size_z
	_occupied.append(_footprint(Vector2(center.x, center.z), Vector2(width, depth)))
	var material := _container_mat(color)
	var t := PANEL_THICKNESS
	var half := size * 0.5
	for side in [-1.0, 1.0]:
		var x_wall := Vector3(side * (half.x - t * 0.5), 0, 0)
		_add_steel_panel(center + x_wall.rotated(Vector3.UP, yaw),
			Vector3(t, size.y, size.z), material, yaw_deg)
		var z_wall := Vector3(0, 0, side * (half.z - t * 0.5))
		_add_steel_panel(center + z_wall.rotated(Vector3.UP, yaw),
			Vector3(size.x - t * 2, size.y, t), material, yaw_deg)
		_add_steel_panel(center + Vector3.UP * side * (half.y - t * 0.5),
			Vector3(size.x - t * 2, t, size.z - t * 2), material, yaw_deg)
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
	door.position = center + door.position.rotated(Vector3.UP, yaw)
	door.rotation.y = yaw
	add_child(door)


func _add_crate(center: Vector3) -> void:
	_occupied.append(_footprint(Vector2(center.x, center.z), Vector2(1.15, 1.15)))
	var size := Vector3(1.15, 1.1, 1.15)
	var box := _add_box(center, size, _wood_mat, 0.0, "wood")
	box.set_meta(&"ballistic_size", size)


func _footprint(center: Vector2, size: Vector2) -> Rect2:
	return Rect2(center - size * 0.5, size)


func _is_clear(area: Rect2, limit: float, spawn_clearance: float) -> bool:
	if not Rect2(-limit, -limit, limit * 2.0, limit * 2.0).encloses(area):
		return false
	for obstacle in _occupied:
		if obstacle.intersects(area):
			return false
	var spawn_area := area.grow(spawn_clearance)
	for spawn in RESERVED_SPAWNS:
		if spawn_area.has_point(Vector2(spawn.x, spawn.z)):
			return false
	return true


func _scatter_passages(rng: RandomNumberGenerator) -> void:
	var count := 0
	for attempt in 550:
		var center := Vector2(rng.randf_range(-13.0, 13.0), rng.randf_range(-13.0, 13.0))
		var across := rng.randi_range(0, 1) == 1
		var size := Vector2(CONTAINER_WIDTH + 0.35, LENGTH_20 + 1.5)
		if across:
			size = Vector2(size.y, size.x)
		var area := _footprint(center, size)
		if not _is_clear(area, 14.85, 0.75):
			continue
		_occupied.append(area)
		_add_passage(count, Vector3(center.x, 0, center.y), 90.0 if across else 0.0,
			COLOR_GREEN.lerp(COLOR_ORANGE, rng.randf_range(0.0, 0.65)))
		count += 1
		if count == 2:
			break


func _add_passage(index: int, center: Vector3, yaw_deg: float, color: Color) -> void:
	var yaw := deg_to_rad(yaw_deg)
	_passages.append(Transform3D(Basis(Vector3.UP, yaw), center))
	var side_mat := _container_mat(color)
	var frame_mat := _container_mat(color.darkened(0.24))
	for side in [-1.0, 1.0]:
		var side_offset := Vector3(side * (CONTAINER_WIDTH * 0.5 - 0.07), 1.29, 0)
		_add_steel_panel(center + side_offset.rotated(Vector3.UP, yaw), Vector3(0.14, 2.58, LENGTH_20),
			side_mat, yaw_deg).name = "Passage%dWall%d" % [index, int(side > 0.0)]
		for end in [-1.0, 1.0]:
			var frame := Vector3(side * 1.13, 1.29, end * (LENGTH_20 * 0.5 - 0.08))
			_add_box(center + frame.rotated(Vector3.UP, yaw), Vector3(0.18, 2.58, 0.16),
				frame_mat, yaw_deg, "metal")
	_add_steel_panel(center + Vector3.UP * 2.51, Vector3(CONTAINER_WIDTH, 0.16, LENGTH_20),
		side_mat, yaw_deg)
	var deck := MeshInstance3D.new()
	var deck_mesh := PlaneMesh.new()
	deck_mesh.size = Vector2(CONTAINER_WIDTH - 0.14, LENGTH_20)
	deck_mesh.material = _wood_mat
	deck.mesh = deck_mesh
	deck.rotation.y = yaw
	deck.position = center + Vector3.UP * 0.012
	add_child(deck)


func _scatter_crates(rng: RandomNumberGenerator) -> Array[Transform3D]:
	var crates: Array[Transform3D] = []
	# Place along a passage wall so the center lane and both exits stay open.
	for passage in _passages:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var local := Vector3(side * 0.67, 0.012, rng.randf_range(-1.55, 1.55))
		var facing := 0.0 if side < 0.0 else PI
		var placement := passage * Transform3D(Basis(Vector3.UP, facing), local)
		if _separated(placement.origin, crates):
			crates.append(placement)

	var candidates: Array[Dictionary] = []
	for _sample in 700:
		var center := Vector2(rng.randf_range(-15.9, 15.9), rng.randf_range(-15.9, 15.9))
		var quarter_turn := rng.randi_range(0, 3)
		var size := Vector2(2.28, 2.88) if quarter_turn % 2 == 0 else Vector2(2.88, 2.28)
		var area := _footprint(center, size)
		if not _is_clear(area, 16.85, 0.65):
			continue
		var cover := 0
		for sample in 12:
			var ray := Vector2.from_angle(sample * TAU / 12.0)
			if _behind_cover(center, center + ray * 4.3):
				cover += 1
		if cover < 4:
			continue
		var placement := Transform3D(Basis(Vector3.UP, quarter_turn * PI * 0.5), Vector3(center.x, 0, center.y))
		candidates.append({"placement": placement, "area": area, "weight": float(cover) + rng.randf_range(0, 4)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.weight > b.weight)
	for candidate in candidates:
		var placement: Transform3D = candidate.placement
		if not _separated(placement.origin, crates):
			continue
		crates.append(placement)
		_occupied.append(candidate.area)
		if crates.size() == MAX_SUPPLY_CRATES:
			break
	return crates


func _separated(position: Vector3, crates: Array[Transform3D]) -> bool:
	var from := Vector2(position.x, position.z)
	for crate in crates:
		var to := Vector2(crate.origin.x, crate.origin.z)
		var distance := from.distance_to(to)
		if distance < 4.5:
			return false
		if distance > CRATE_SIGHT_RADIUS:
			continue
		var step := (to - from).normalized().orthogonal() * 0.72
		# Test from either side of each crate as well as down the center sight line.
		for offset in [-step, Vector2.ZERO, step]:
			if not _behind_cover(from + offset, to) or not _behind_cover(from, to + offset):
				return false
	return true


func _behind_cover(from: Vector2, to: Vector2) -> bool:
	for obstacle in _cover:
		var local_from := (from - obstacle.center).rotated(obstacle.yaw)
		var local_to := (to - obstacle.center).rotated(obstacle.yaw)
		if _crosses_box(local_from, local_to - local_from, obstacle.half_size):
			return true
	return false


func _crosses_box(from: Vector2, travel: Vector2, half_size: Vector2) -> bool:
	var near := 0.0
	var far := 1.0
	for axis in 2:
		if absf(travel[axis]) < 0.0001:
			if absf(from[axis]) > half_size[axis]:
				return false
			continue
		var a := (-half_size[axis] - from[axis]) / travel[axis]
		var b := (half_size[axis] - from[axis]) / travel[axis]
		near = maxf(near, minf(a, b))
		far = minf(far, maxf(a, b))
		if near > far:
			return false
	return true


func _scatter_foliage(rng: RandomNumberGenerator) -> void:
	var grass: Array[Transform3D] = []
	var shrubs: Array[Transform3D] = []
	var shrub_clusters := 0
	var obstacle_count := _occupied.size()
	for attempt in 180:
		var side := rng.randi_range(0, 3)
		var center := Vector2(rng.randf_range(-15.7, 15.7), rng.randf_range(15.0, 16.05)).rotated(side * PI * 0.5)
		if attempt % 3 == 0:
			var obstacle := _occupied[rng.randi_range(0, obstacle_count - 1)]
			var along := rng.randf_range(0.15, 0.85)
			match side:
				0: center = Vector2(obstacle.position.x - 0.59, lerpf(obstacle.position.y, obstacle.end.y, along))
				1: center = Vector2(obstacle.end.x + 0.59, lerpf(obstacle.position.y, obstacle.end.y, along))
				2: center = Vector2(lerpf(obstacle.position.x, obstacle.end.x, along), obstacle.position.y - 0.59)
				3: center = Vector2(lerpf(obstacle.position.x, obstacle.end.x, along), obstacle.end.y + 0.59)
		var area := _footprint(center, Vector2.ONE * 0.9)
		if not _is_clear(area, 16.85, 0.65):
			continue
		_occupied.append(area)
		if shrub_clusters < 8 and (grass.is_empty() or rng.randf() < 0.35):
			for branch in 3:
				var offset := Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(0.0, 0.20)
				shrubs.append(_plant_transform(center + offset, rng, 0.64, 0.95))
			shrub_clusters += 1
		else:
			for tuft in rng.randi_range(10, 17):
				var offset := Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(0.0, 0.39)
				grass.append(_plant_transform(center + offset, rng, 1.05, 1.95))
		if shrub_clusters >= 8 and grass.size() >= 160:
			break
	_add_plants(GRASS, grass, rng)
	_add_plants(SHRUBS, shrubs, rng)


func _plant_transform(point: Vector2, rng: RandomNumberGenerator, min_scale: float, max_scale: float) -> Transform3D:
	var plant_basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * rng.randf_range(min_scale, max_scale))
	return Transform3D(plant_basis, Vector3(point.x, 0.01, point.y))


func _add_plants(scene: PackedScene, transforms: Array[Transform3D], rng: RandomNumberGenerator) -> void:
	var source := scene.instantiate()
	var variants := source.find_children("*", "MeshInstance3D", true, false)
	var groups: Array[Array] = []
	for variant in variants:
		groups.append([])
	for placement in transforms:
		groups[rng.randi_range(0, groups.size() - 1)].append(placement)
	for index in groups.size():
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = variants[index].mesh
		batch.instance_count = groups[index].size()
		for instance in batch.instance_count:
			batch.set_instance_transform(instance, groups[index][instance])
		var plants := MultiMeshInstance3D.new()
		plants.multimesh = batch
		plants.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(plants)
	source.free()


func _add_steel_panel(center: Vector3, size: Vector3, material: Material, yaw: float) -> StaticBody3D:
	var panel := _add_box(center, size, material, yaw, "metal")
	panel.set_meta(&"ballistic_size", size)
	return panel


func _add_box(center: Vector3, size: Vector3, material: Material, yaw_deg: float = 0.0, surface: String = "concrete") -> StaticBody3D:
	if center.y - size.y * 0.5 < 0.72 and center.y + size.y * 0.5 > 1.4:
		var cover := Cover.new()
		cover.center = Vector2(center.x, center.z)
		cover.half_size = Vector2(size.x, size.z) * 0.5
		cover.yaw = deg_to_rad(yaw_deg)
		_cover.append(cover)
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
