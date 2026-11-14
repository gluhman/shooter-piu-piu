extends RefCounted

const HEIGHTFIELD := preload("art/gdt/terrain_heightfield.gd")
const TERRAIN_MESH := preload("art/gdt/terrain_mesh_builder.gd")
const GROUND_SHADER := preload("forest_ground.gdshader")
const FIR_MESHES := preload("fir_meshes.gd")
const WATER_SHADER := preload("forest_water.gdshader")
const CRATE_PATH := "res://assets/arena_props/village/wooden_crate_01.glb"
const BARREL_PATH := "res://assets/arena_props/village/wine_barrel_01.glb"

const WIDTH := 100.0
const HALF := WIDTH * 0.5
const QUADS := 200
const CHUNK_QUADS := 50
const DITCH_FLOOR := -2.35
const TERRAIN_BAKE_BOUNDS := AABB(Vector3(-HALF, -3.0, -HALF), Vector3(WIDTH, 25.0, WIDTH))

const CAMPS := [Vector2(-36, 36), Vector2(36, -36), Vector2(36, 36), Vector2(-36, -36)]
const CAMP_HEIGHTS := [1.3, 2.1, 0.7, 1.6]
# Four camp markers, with spaced starts for larger lobbies.
const CAMP_OFFSETS := [Vector2.ZERO, Vector2(-3.1, 0), Vector2(3.1, 0),
	Vector2(-2.6, 3.1), Vector2(2.6, 3.1)]
const CAMP_COLORS := [Color("#a86a36"), Color("#769080"), Color("#9e4840"), Color("#8f8655")]

const TRAILS := [
	[Vector2(-36, -36), Vector2(-20, -29), Vector2(-8, -28), Vector2(8, -32), Vector2(23, -30), Vector2(36, -36)],
	[Vector2(36, -36), Vector2(30, -22), Vector2(32, -6), Vector2(31, 11), Vector2(30, 24), Vector2(36, 36)],
	[Vector2(36, 36), Vector2(20, 29), Vector2(6, 29), Vector2(-9, 33), Vector2(-23, 30), Vector2(-36, 36)],
	[Vector2(-36, 36), Vector2(-30, 23), Vector2(-30, 9), Vector2(-32, -11), Vector2(-29, -24), Vector2(-36, -36)],
	[Vector2(-13, -29), Vector2(-8, -21), Vector2(-5, -14), Vector2(1, -8), Vector2(1, 0)],
	[Vector2(31.3, 6), Vector2(24, 3), Vector2(17, 2), Vector2(9, 1), Vector2(1, 0)],
	[Vector2(9, 29), Vector2(7, 21), Vector2(2, 14), Vector2(1, 8), Vector2(1, 0)],
	[Vector2(-31, -6), Vector2(-24, -4), Vector2(-18, -2.5), Vector2(-9, -1), Vector2(1, 0)],
]
const RIDGES := [
	Vector4(-6, -42, 14.0, 13), Vector4(8, -45, 16.5, 12),
	Vector4(20, -42, 7.0, 10), Vector4(-22, 14, 5.8, 8),
	Vector4(22, -15, 6.3, 10), Vector4(20, 16, 4.8, 8),
	Vector4(-13, -17, 4.2, 8), Vector4(-13, 39, 4.0, 9),
]
const ROUTE_SUPPLIES := [Vector2(-3, -18), Vector2(25, 5.6), Vector2(5.1, 19.1), Vector2(-25, -6.4)]

var _map: Node3D
var _world := Node3D.new()
var _heightfield := HEIGHTFIELD.new()
var _rng := RandomNumberGenerator.new()
var _detail_rng := RandomNumberGenerator.new()
var _trail_grid := PackedFloat32Array()
var _ditch_grid := PackedFloat32Array()
var _trees: Array[Mesh] = []
var _rocks: Array[Mesh] = []
var _wall_blocks: Array[Array] = [[], [], [], [], [], []]
var _stone: StandardMaterial3D
var _wood: StandardMaterial3D
var _crate_scene: PackedScene
var _barrel_scene: PackedScene
var _outline: Array[PackedVector2Array] = []
var _visuals := DisplayServer.get_name() != "headless"


func _init(map_builder: Node3D) -> void:
	_map = map_builder


func build() -> Array[Transform3D]:
	_rng.seed = 581319
	_detail_rng.seed = 71831
	_world.name = "ForestRidge"
	_map.add_child(_world)
	_build_ground()
	if _visuals:
		_stone = _material("res://assets/map_textures/village/cobble", Color("#aba38a"), 1.0)
		_wood = _material("res://assets/map_textures/planks", Color("#715b49"), 2.4)
		_rocks = _model_meshes(load("res://game/maps/forest_ridge/art/rock/rock_moss_set_01_1k.gltf"))
		_trees = FIR_MESHES.build(_detail_rng)
		_crate_scene = load(CRATE_PATH)
		_barrel_scene = load(BARREL_PATH)
	_build_boundary()
	_build_ruin()
	_build_camps()
	if _visuals:
		for index in _rocks.size():
			_batch("Masonry%d" % index, _rocks[index], _wall_blocks[index],
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON, _stone)
	for offset: Vector2 in CAMP_OFFSETS:
		for center: Vector2 in CAMPS:
			_map._initial_spawns.append(_at(center + offset.rotated(Vector2.DOWN.angle_to(center)), 0.16))
	_scatter_forest()
	_world.set_meta(&"minimap_outline", _outline)
	var supplies: Array[Transform3D] = []
	for point: Vector2 in ROUTE_SUPPLIES:
		supplies.append(Transform3D(Basis.IDENTITY, _at(point)))
	for point: Vector2 in [Vector2(-26, -25), Vector2(0, -26), Vector2(30, -17),
			Vector2(26, 3), Vector2(28, 24), Vector2(0, 31), Vector2(-28, 20), Vector2(-26, -4),
			Vector2(4, -13), Vector2(6, 10), Vector2(-6, 3)]:
		_map._patrol.append(_at(point, 0.12))
	return supplies


func _build_ground() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 14386
	noise.frequency = 0.086
	noise.fractal_octaves = 4
	_heightfield.create_from_noise(QUADS, WIDTH, 2.45, noise)
	var stride := QUADS + 1
	_trail_grid.resize(stride * stride)
	_ditch_grid.resize(stride * stride)
	for z in stride:
		for x in stride:
			var point := Vector2(x, z) * _heightfield.step - Vector2.ONE * HALF
			var d := _path_distance(point)
			var trail := 1.0 - smoothstep(0.85, 2.85, d)
			var height := _heightfield.sample_grid(x, z) * lerpf(1.0, 0.30, trail)
			for ridge: Vector4 in RIDGES:
				var relative := (point - Vector2(ridge.x, ridge.y)) / ridge.w
				height += ridge.z * exp(-relative.length_squared() * 1.4)
			for camp in CAMPS.size():
				var distance := point.distance_to(CAMPS[camp])
				height = lerpf(CAMP_HEIGHTS[camp], height, smoothstep(5.4, 11.0, distance))
				trail = maxf(trail, (1.0 - smoothstep(4.8, 6.8, distance)) * 0.78)
			var plaza := maxf(absf((point.x - 1.0) / 9.2), absf(point.y / 10.5))
			height = lerpf(0.65, height, smoothstep(0.88, 1.48, plaza))
			trail = maxf(trail, (1.0 - smoothstep(0.9, 1.06, plaza)) * 0.92)
			var ditch := _ditch_weight(point)
			height = lerpf(height, DITCH_FLOOR, ditch)
			_heightfield.set_grid(x, z, height)
			_trail_grid[z * stride + x] = trail
			_ditch_grid[z * stride + x] = ditch
	var builder := TERRAIN_MESH.new()
	builder.configure({
		"heightfield": _heightfield,
		"active_total_resolution": QUADS,
		"active_chunk_resolution": CHUNK_QUADS,
		"active_step": _heightfield.step,
		"active_half_size": HALF,
	})
	var ground := _ground_material() if _visuals else null
	for z in QUADS / CHUNK_QUADS:
		for x in QUADS / CHUNK_QUADS:
			_build_chunk(builder, x, z, ground)
	if _visuals:
		_add_ditch_water()


func _ground_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	var directory := "res://game/maps/forest_ridge/art/ground/"
	var texture_sets := {"floor": "forest_ground_04", "trail": "rocky_trail"}
	var textures := {"color": "diff", "normal": "nor_gl", "arm": "arm"}
	for layer: String in texture_sets:
		for channel: String in textures:
			material.set_shader_parameter(layer + "_" + channel,
				load("%s%s_%s_1k.jpg" % [directory, texture_sets[layer], textures[channel]]))
	return material


func _build_chunk(builder: RefCounted, x: int, z: int, material: ShaderMaterial) -> void:
	var arrays: Array = builder.build_chunk_mesh_arrays(x, z, 1)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var chunk_stride := CHUNK_QUADS + 1
	for local_z in chunk_stride:
		for local_x in chunk_stride:
			var index := (z * CHUNK_QUADS + local_z) * (QUADS + 1) + x * CHUNK_QUADS + local_x
			colors[local_z * chunk_stride + local_x] = Color(_trail_grid[index], _ditch_grid[index], 0, 1)
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh: ArrayMesh = builder.create_mesh_from_arrays(arrays)
	var body := StaticBody3D.new()
	body.name = "Terrain_%d_%d" % [x, z]
	body.set_meta(&"impact_surface", "dirt")
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	if _visuals:
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = material
		body.add_child(visual)
	_world.add_child(body)


func _path_distance(point: Vector2) -> float:
	var distance := INF
	for route: Array in TRAILS:
		for index in range(1, route.size()):
			var closest := Geometry2D.get_closest_point_to_segment(point, route[index - 1], route[index])
			distance = minf(distance, point.distance_squared_to(closest))
	return sqrt(distance)


func _ditch_x(side: float, z: float) -> float:
	return side * (18.0 + 1.8 * sin(z * 0.19) + 0.8 * sin(z * 0.41))


func _ditch_weight(point: Vector2) -> float:
	var side := 1.0 if point.x >= 0.0 else -1.0
	var crossing := 2.1 if side > 0.0 else -2.4
	var bank := 1.0 - smoothstep(0.85, 4.65, absf(point.x - _ditch_x(side, point.y)))
	var ends := 1.0 - smoothstep(18.5, 25.0, absf(point.y))
	var ford := smoothstep(2.3, 6.1, absf(point.y - crossing))
	return bank * ends * ford


func _add_ditch_water() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		for stretch: Vector2 in [Vector2(-18, -9), Vector2(9, 18)]:
			for meter in range(int(stretch.x), int(stretch.y)):
				var a := float(meter)
				var b := a + 1.0
				var start := _ditch_x(side, a)
				var finish := _ditch_x(side, b)
				for offset: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1),
						Vector2(1, 0), Vector2(1, 1), Vector2(-1, 1)]:
					surface.set_normal(Vector3.UP)
					var z := lerpf(a, b, offset.y)
					var bank := 0.78 + 0.25 * sin(z * 0.6) + 0.17 * cos(z * 1.8)
					var ends := smoothstep(0.0, 2.6, minf(z - stretch.x, stretch.y - z))
					var x := lerpf(start, finish, offset.y) + offset.x * bank * lerpf(0.2, 1.0, ends)
					surface.add_vertex(Vector3(x, DITCH_FLOOR + 0.16, z))
	var water := MeshInstance3D.new()
	water.name = "DitchPools"
	water.mesh = surface.commit()
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	water.material_override = material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(water)


func _at(point: Vector2, lift := 0.0) -> Vector3:
	return Vector3(point.x, _heightfield.sample_world(point.x, point.y) + lift, point.y)


func _build_boundary() -> void:
	var body := StaticBody3D.new()
	body.name = "MapBoundary"
	_world.add_child(body)
	for side in [-1.0, 1.0]:
		for along_x in [true, false]:
			var shape := BoxShape3D.new()
			shape.size = Vector3(WIDTH + 0.5, 42, 0.5) if along_x else Vector3(0.5, 42, WIDTH)
			var collider := CollisionShape3D.new()
			collider.shape = shape
			collider.position = Vector3(0, 12, side * (HALF + 0.25)) if along_x else Vector3(side * (HALF + 0.25), 12, 0)
			body.add_child(collider)


func _build_ruin() -> void:
	var walls := [
		[Vector2(-8.0, -6.5), 6.5, 1.8, 90.0], [Vector2(-8.0, 5.4), 8.8, 1.45, 90.0],
		[Vector2(9.0, -5.3), 8.7, 1.8, 90.0], [Vector2(9.0, 6.5), 6.5, 1.55, 90.0],
		[Vector2(-5.2, -10), 5.4, 1.7, 0.0], [Vector2(5.8, -10), 6.0, 1.43, 0.0],
		[Vector2(-4.6, 10), 6.8, 1.45, 0.0], [Vector2(6.8, 10), 4.4, 1.8, 0.0],
		[Vector2(-1.85, 1.8), 3.8, 0.93, -15.0], [Vector2(4.4, -3.1), 2.9, 1.02, 23.0],
	]
	for wall: Array in walls:
		_dry_stone_wall(wall[0], wall[1], wall[2], wall[3])
	if _visuals:
		for point: Vector2 in [Vector2(-6, -7), Vector2(6.2, 7), Vector2(-4.4, 6.1), Vector2(6.8, -7.3)]:
			_add_rock_detail(point, 0.42)


func _dry_stone_wall(point: Vector2, length: float, height: float, yaw: float) -> void:
	var at := _at(point, height * 0.5 - 0.1)
	var size := Vector3(length, height, 0.83)
	var body := _cover_box(at, size, yaw, "stone")
	if not _visuals:
		return
	var rows := maxi(2, ceili(height / 0.43))
	var course := height / rows
	for row in rows:
		var blocks := maxi(1, roundi(length / 1.05) + row % 2)
		var width := length / blocks
		for col in blocks:
			var upper := row == rows - 1
			var relief := _detail_rng.randf_range(0.76, 1.11) if upper else _detail_rng.randf_range(0.96, 1.07)
			var x := -length * 0.5 + (col + 0.5) * width
			var y := -height * 0.5 + row * course + course * relief * 0.5
			var index := (col + row) % _rocks.size()
			var bounds := _rocks[index].get_aabb()
			var block_size := Vector3(width * 1.13, course * relief * 1.52, _detail_rng.randf_range(0.91, 1.10))
			var basis := Basis(Vector3.UP, _detail_rng.randf_range(-0.13, 0.13)).scaled(block_size / bounds.size)
			var block := Vector3(x, y, _detail_rng.randf_range(-0.055, 0.055)) - basis * bounds.get_center()
			_wall_blocks[index].append(body.transform * Transform3D(basis, block))


func _build_camps() -> void:
	for index in CAMPS.size():
		var center: Vector2 = CAMPS[index]
		var inward := -center.normalized()
		var front := Vector2(-inward.y, inward.x)
		var back := -inward
		var facing := rad_to_deg(-front.angle())
		_dry_stone_wall(center + back * 5.8, 10.0, 1.45, facing)
		for side in [-1.0, 1.0]:
			_dry_stone_wall(center + front * side * 5.7 + back * 1.6, 5.8, 1.2, facing + 90.0)
			if _visuals:
				_add_camp_post(center + front * side * 4.8 - back * 2.7, CAMP_COLORS[index])
		if _visuals:
			_set_dressing(_crate_scene, center + back * 4.35 + front * 3.0, facing)
			_set_dressing(_barrel_scene, center + back * 4.25 - front * 3.9, facing + 45.0)
		var marker := Marker3D.new()
		marker.name = "Spawn%d" % (index + 1)
		marker.position = _at(center, 0.16)
		marker.rotation.y = atan2(center.x, center.y)
		_world.add_child(marker)
		_map.respawn_points.append(marker.position)
		_map.respawn_points.append(_at(center + inward * 7.6 + front * 2.6, 0.16))
		_map.respawn_points.append(_at(center + inward * 7.6 - front * 2.6, 0.16))


func _set_dressing(scene: PackedScene, point: Vector2, yaw: float) -> void:
	var prop := scene.instantiate() as Node3D
	prop.position = _at(point)
	prop.rotation.y = deg_to_rad(yaw)
	_world.add_child(prop)


func _add_camp_post(point: Vector2, cloth: Color) -> void:
	var trim := StandardMaterial3D.new()
	trim.albedo_color = cloth
	trim.roughness = 0.92
	var post := Node3D.new()
	post.position = _at(point)
	post.rotation.y = 0.78 if point.x * point.y > 0.0 else -0.78
	_world.add_child(post)
	_visual_box(post, Vector3(0, 1.4, 0), Vector3(0.15, 2.8, 0.15), _wood)
	_visual_box(post, Vector3(0.26, 2.67, 0), Vector3(0.64, 0.095, 0.09), _wood)
	_visual_box(post, Vector3(0.34, 2.32, 0), Vector3(0.55, 0.67, 0.03), trim)


func _scatter_forest() -> void:
	var tree_positions: Array[Vector2] = []
	var tree_transforms: Array[Array] = [[], [], []]
	for attempt in 1350:
		var point := _random_point()
		if _reserved(point, 3.35) or _ditch_weight(point) > 0.37:
			continue
		var spacing := 3.9 if maxf(absf(point.x), absf(point.y)) < 43.0 else 3.2
		var clear := true
		for other: Vector2 in tree_positions:
			if point.distance_squared_to(other) < spacing * spacing:
				clear = false
				break
		if not clear:
			continue
		tree_positions.append(point)
		var height := _rng.randf_range(6.5, 14.2)
		var radius := _rng.randf_range(0.17, 0.33) * height / 10.0
		var yaw := _rng.randf_range(0.0, TAU)
		var spread := height * _rng.randf_range(0.63, 0.95)
		var base := _at(point, -0.12)
		var variant := tree_positions.size() % tree_transforms.size()
		tree_transforms[variant].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(spread, height, spread)), base))
		_add_trunk_collision(base, radius)
		if tree_positions.size() >= 215:
			break
	for point: Vector2 in [Vector2(-24, 13), Vector2(-22, 17), Vector2(21, -15), Vector2(24, -18),
			Vector2(20, 16), Vector2(23, 18), Vector2(-12, -15), Vector2(-16, -19),
			Vector2(-7, -41), Vector2(4, -46), Vector2(12, -42), Vector2(14, -44),
			Vector2(22, 8), Vector2(-22, 4), Vector2(14, -12), Vector2(-14, 10),
			Vector2(41, -20), Vector2(40, 12), Vector2(-41, -8), Vector2(-39, 14)]:
		if not _reserved(point, 2.4):
			_add_boulder(point, _rng.randf_range(1.8, 3.5), _rng.randf_range(0.0, TAU))
	if not _visuals:
		return
	for index in _trees.size():
		_batch("Firs%d" % index, _trees[index], tree_transforms[index])
	_scatter_understory()


func _reserved(point: Vector2, trail_margin: float, ground_cover := false) -> bool:
	if _path_distance(point) < trail_margin or (not ground_cover and absf(point.x - 1.0) < 11.4 and absf(point.y) < 12.4):
		return true
	for center: Vector2 in CAMPS:
		if point.distance_squared_to(center) < (25.0 if ground_cover else 83.0):
			return true
	for supply: Vector2 in ROUTE_SUPPLIES:
		if point.distance_squared_to(supply) < 3.2:
			return true
	return false


func _scatter_understory() -> void:
	var grass := _model_meshes(load("res://assets/arena_props/grass.glb"))
	var shrubs := _model_meshes(load("res://assets/arena_props/shrubs.glb"))
	var ferns := _model_meshes(load("res://game/maps/forest_ridge/art/fern/fern_02_1k.gltf"))
	_scatter_plants("Grass", grass, 17500, 0.85, Vector2(1.25, 2.75))
	_scatter_plants("Ferns", ferns, 1600, 1.6, Vector2(0.85, 1.75))
	_scatter_plants("Shrubs", shrubs, 340, 2.3, Vector2(0.80, 1.7))
	_scatter_plants("LooseStone", _rocks, 450, 0.70, Vector2(0.07, 0.32))


func _scatter_plants(label: String, variants: Array[Mesh], amount: int, margin: float, scales: Vector2) -> void:
	var groups := {}
	var noise := FastNoiseLite.new()
	noise.seed = 519
	noise.frequency = 0.17
	for attempt in amount:
		var point := _random_point()
		if _reserved(point, margin, true) or _ditch_weight(point) > 0.68:
			continue
		if noise.get_noise_2dv(point) < -0.12 and _rng.randf() < 0.78:
			continue
		var index := attempt % variants.size()
		var patch := Vector2i(floori((point.x + HALF) / 25.0), floori((point.y + HALF) / 25.0))
		var key := Vector3i(patch.x, patch.y, index)
		if not groups.has(key):
			groups[key] = []
		var scale := _rng.randf_range(scales.x, scales.y)
		var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale)
		groups[key].append(Transform3D(basis, _at(point, -0.025)))
	for key: Vector3i in groups:
		_batch("%s_%d_%d_%d" % [label, key.x, key.y, key.z], variants[key.z], groups[key],
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func _random_point() -> Vector2:
	return Vector2(_rng.randf_range(-49.7, 49.7), _rng.randf_range(-49.7, 49.7))


func _batch(label: String, mesh: Mesh, transforms: Array,
		shadows := GeometryInstance3D.SHADOW_CASTING_SETTING_ON, material: Material = null) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = label
	instance.multimesh = multimesh
	instance.cast_shadow = shadows
	instance.material_override = material
	_world.add_child(instance)


func _add_boulder(point: Vector2, width: float, rotation: float) -> void:
	var height := width * 0.57
	var at := _at(point, height * 0.22)
	var size := Vector3(width, height, width * 0.79)
	var body := _cover_box(at, size * Vector3(0.67, 0.8, 0.70), rad_to_deg(rotation), "stone")
	if _visuals:
		_fit_mesh(body, _rocks[3], Vector3(0, -height * 0.08, 0), size, 0.0)
		_add_rock_detail(point + Vector2.from_angle(rotation) * width * 0.38, width * 0.28)


func _add_rock_detail(point: Vector2, scale: float) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _rocks[posmod(roundi(point.x * 7 + point.y), _rocks.size())]
	instance.position = _at(point)
	instance.rotation.y = point.x + point.y
	instance.scale = Vector3.ONE * scale
	_world.add_child(instance)


func _cover_box(at: Vector3, size: Vector3, yaw: float, surface: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta(&"impact_surface", surface)
	body.position = at
	body.rotation.y = deg_to_rad(yaw)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	body.add_child(collider)
	_world.add_child(body)
	var outline := PackedVector2Array()
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		outline.append(Vector2(at.x, at.z) + (corner * Vector2(size.x, size.z) * 0.5).rotated(-body.rotation.y))
	_outline.append(outline)
	return body


func _add_trunk_collision(base: Vector3, radius: float) -> void:
	var body := StaticBody3D.new()
	body.position = base + Vector3.UP * 2.45
	body.set_meta(&"impact_surface", "wood")
	var collider := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = 5.1
	collider.shape = cylinder
	body.add_child(collider)
	_world.add_child(body)


func _model_meshes(scene: PackedScene) -> Array[Mesh]:
	var root := scene.instantiate()
	var meshes: Array[Mesh] = []
	if root is MeshInstance3D:
		meshes.append(root.mesh)
	for node: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node.mesh)
	root.free()
	return meshes


func _material(prefix: String, tint: Color, scale: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.albedo_texture = load(prefix + "_color.jpg")
	material.normal_enabled = true
	material.normal_texture = load(prefix + "_normal.jpg")
	material.roughness_texture = load(prefix + "_roughness.jpg")
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * scale
	return material


func _visual_box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)


func _fit_mesh(parent: Node3D, mesh: Mesh, at: Vector3, size: Vector3, angle: float,
		material: Material = null) -> void:
	var bounds := mesh.get_aabb()
	var pivot := Node3D.new()
	pivot.position = at
	pivot.rotation.y = angle
	parent.add_child(pivot)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.scale = size / bounds.size
	instance.position = -bounds.get_center() * instance.scale
	pivot.add_child(instance)
