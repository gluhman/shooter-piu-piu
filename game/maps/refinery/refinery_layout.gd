extends RefCounted

const HEIGHTFIELD := preload("../forest_ridge/art/gdt/terrain_heightfield.gd")
const TERRAIN_MESH := preload("../forest_ridge/art/gdt/terrain_mesh_builder.gd")
const GROUND := preload("refinery_ground.gdshader")
const TERRAIN_3D := preload("../terrain_3d_surface.gd")
const LADDERS := preload("../procedural/workshop_ladders.gd")
const SHOT_COLLISION := preload("../../combat/shot_collision.gd")
const ART := "res://game/maps/refinery/art/"
const MARKING := preload("../procedural/route_marking.gd")
const MAP_ID := 12
const SIZE := 2
const WIDTH := 80.0
const HALF := WIDTH * 0.5
const DECK := 3.4
const DECK_EDGE_X := 8.5
const BRIDGE_JOIN_X := 19.0
const TERRACE_CENTER_X := 24.0
const RACK_Z := 18.6
const RACK_PIPE_Y := 5.48
const RACK_PIPE_RADIUS := 0.23
const RACK_PIPE_OFFSETS := [-0.52, 0.15, 0.66]
const RACK_EAST_X := 12.05
const BAKE_BOUNDS := AABB(Vector3(-HALF, -2, -HALF), Vector3(WIDTH, 13, WIDTH))
const QUADS := 160
const CHUNK := 40
const FOREST_GROUND := "res://game/maps/forest_ridge/art/ground/"
const STATION_ART := "res://game/maps/station/art/"
const VILLAGE_ART := "res://assets/arena_props/village/"
const PROP_SCENES := {
	"cabinet": STATION_ART + "power_box_01/power_box_01_2k.gltf",
	"tools": STATION_ART + "metal_tool_chest/metal_tool_chest_2k.gltf",
	"crate": VILLAGE_ART + "wooden_crate_01.glb",
	"jack": "res://assets/arena_props/workshop/pallet_jack.glb",
}
const SPAWN_LANES := [-15.0, -12.0, -9.0, -6.0, -3.0, 0.0, 3.0, 6.0, 9.0, 12.0]

var _map: Node3D
var _root := Node3D.new()
var _ladders := LADDERS.new()
var _heightfield := HEIGHTFIELD.new()
var _visuals := DisplayServer.get_name() != "headless"
var _rng := RandomNumberGenerator.new()
var _batches: Dictionary = {}
var _prop_scenes: Dictionary[String, PackedScene] = {}
var _outline: Array[PackedVector2Array] = []
var _rock: Material
var _concrete: Material
var _teal: Material
var _rust: Material
var _white: Material
var _frame: Material
var _deck: Material
var _amber: Material
var _glass: Material


func _init(map: Node3D) -> void:
	_map = map


func build() -> Array[Transform3D]:
	_root.name = "Refinery"
	_map.add_child(_root)
	_ladders.name = "ArenaLadders"
	_map.add_child(_ladders)
	_rng.seed = 59217
	if _visuals:
		_rock = _material("rock_boulder_dry", Color("#d0c2ab"), 0.0, 0.54)
		_concrete = _material("concrete_floor_worn_001", Color("#d3cbb4"), 0.0, 0.33)
		_teal = _material("blue_metal_plate", Color("#4ea9a6"), 0.38, 0.48)
		_rust = _material("blue_metal_plate", Color("#b2764e"), 0.33, 0.43, false)
		_white = _material("blue_metal_plate", Color("#b9c3c3"), 0.42, 0.31, false)
		_frame = _material("blue_metal_plate", Color("#405560"), 0.50, 0.54)
		_deck = _material("metal_plate", Color("#98a4a5"), 0.45, 0.64)
		_amber = _material("metal_plate", Color("#ffd265"), 0.27, 0.68, false)
		_glass = _paint(Color("#4a8195"), 0.50)
	_terrain()
	if _visuals:
		_backdrop()
	_boundary()
	_process_deck()
	_yard()
	_containers()
	_equipment()
	_hills()
	_pipe_racks()
	if _visuals:
		_detail()
		_flush_boxes()
	_root.set_meta(&"minimap_outline", _outline)
	for x: float in SPAWN_LANES:
		for side in [1.0, -1.0]:
			_map._initial_spawns.append(Vector3(x, 0.18, side * 31.5))
			_map.respawn_points.append(Vector3(x, 0.18, side * 31.5))
	for point: Vector3 in [Vector3(-22, 0.15, 20), Vector3(-17, 0.15, 0),
			Vector3(-23, 0.15, -16), Vector3(0, 0.15, -25),
			Vector3(0, DECK + 0.12, 0), Vector3(24, DECK + 0.12, 0), Vector3(0, 0.15, 25)]:
		_map._patrol.append(point)
	var supplies: Array[Transform3D] = []
	for point: Vector3 in [Vector3(-23, 0, 15), Vector3(-22, 0, -14),
			Vector3(6, DECK, -2.3), Vector3(26, DECK, 12)]:
		supplies.append(Transform3D(Basis.IDENTITY, point))
	return supplies


func _terrain() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 18477
	noise.frequency = 0.105
	noise.fractal_octaves = 4
	_heightfield.create_from_noise(QUADS, WIDTH, 2.3, noise)
	for z in QUADS + 1:
		for x in QUADS + 1:
			var point := Vector2(x, z) * 0.5 - Vector2.ONE * HALF
			var rise := smoothstep(11.0, 23.0, point.x) * DECK
			var eastern_hill := smoothstep(28.0, 37.5, point.x) * 7.6
			var west_bluff := (1.0 - smoothstep(-39.0, -29.0, point.x)) * 7.9
			var natural := maxf(smoothstep(15.0, 32.0, point.x), west_bluff / 7.9)
			var terrace_radius := TERRACE_CENTER_X - BRIDGE_JOIN_X
			var terrace := (1.0 - smoothstep(terrace_radius, terrace_radius + 2.5, absf(point.x - TERRACE_CENTER_X))) 				* (1.0 - smoothstep(13.0, 19.0, absf(point.y)))
			var height := rise + (eastern_hill + west_bluff) * (0.82 + 0.18 * cos(point.y * 0.29))
			height += _heightfield.sample_grid(x, z) * natural
			height = lerpf(height, DECK, terrace)
			var tower_pad := point.distance_to(Vector2(-33.6, signf(point.y) * 5.62))
			height = lerpf(2.83, height, smoothstep(1.2, 2.75, tower_pad))
			_heightfield.set_grid(x, z, height)
	var builder := TERRAIN_MESH.new()
	builder.configure({"heightfield": _heightfield, "active_total_resolution": QUADS,
		"active_chunk_resolution": CHUNK, "active_step": 0.5, "active_half_size": HALF})
	for z in QUADS / CHUNK:
		for x in QUADS / CHUNK:
			var mesh: ArrayMesh = builder.build_chunk_mesh(x, z, 1)
			_body(mesh.create_trimesh_shape(), Transform3D.IDENTITY, "concrete")
	if _visuals:
		var layers: Array[Dictionary] = []
		for entry: Array in [[FOREST_GROUND + "forest_ground_04", "1k", Color(0.68, 0.90, 0.52)],
				[FOREST_GROUND + "rocky_trail", "1k", Color(1.10, 1.02, 0.79)],
				[ART + "concrete_floor_worn_001", "4k", Color(0.91, 0.90, 0.80)]]:
			var prefix: String = entry[0]
			var suffix: String = "_" + entry[1] + ".jpg"
			layers.append({"name": prefix.get_file(), "color": prefix + "_diff" + suffix,
				"normal": prefix + "_nor_gl" + suffix, "roughness": prefix + "_arm" + suffix, "tint": entry[2]})
		var height := func(point: Vector2) -> float: return _heightfield.sample_world(point.x, point.y)
		TERRAIN_3D.build(_root, Rect2(-Vector2.ONE * HALF, Vector2.ONE * WIDTH), height, _terrain_paint, layers)


func _terrain_paint(point: Vector2) -> Vector4:
	var apron := smoothstep(-31.0, -26.0, point.x) * (1.0 - smoothstep(8.0, 15.0, point.x))
	if apron > 0.01:
		return Vector4(0, 2, apron, 1)
	var path := 1.0 - smoothstep(1.25, 3.6, absf(point.x - 24.0 - 2.0 * sin(point.y * 0.15)))
	var slope := Vector2(_y(point.x + 0.5, point.y) - _y(point.x - 0.5, point.y),
		_y(point.x, point.y + 0.5) - _y(point.x, point.y - 0.5)).length()
	return Vector4(0, 1, maxf(path * 0.65, smoothstep(0.5, 1.5, slope) * 0.88), 1)


func _backdrop() -> void:
	const RESOLUTION := 100
	const SPAN := 240.0
	const STEP := SPAN / RESOLUTION
	var noise := FastNoiseLite.new()
	noise.seed = 73038
	noise.frequency = 0.037
	noise.fractal_octaves = 4
	var backdrop := HEIGHTFIELD.new()
	backdrop.create_from_noise(RESOLUTION, SPAN, 15.0, noise)
	for z in RESOLUTION + 1:
		for x in RESOLUTION + 1:
			var point := Vector2(x, z) * STEP - Vector2.ONE * SPAN * 0.5
			var edge := maxf(absf(point.x), absf(point.y))
			var outside := maxf(edge - HALF, 0.0)
			var shoulder := _y(clampf(point.x, -HALF, HALF), clampf(point.y, -HALF, HALF))
			var upland := 11.0 + 9.0 * pow(absf(point.x) / (SPAN * 0.5), 1.4)
			upland += backdrop.sample_grid(x, z)
			var height := lerpf(shoulder - 0.18, upland, smoothstep(0.0, 25.0, outside))
			if edge < HALF:
				height = lerpf(-2.8, height, smoothstep(HALF - STEP, HALF, edge))
			backdrop.set_grid(x, z, height)
	var builder := TERRAIN_MESH.new()
	builder.configure({"heightfield": backdrop, "active_total_resolution": RESOLUTION,
		"active_chunk_resolution": RESOLUTION, "active_step": STEP, "active_half_size": SPAN * 0.5})
	var material := _ground_material()
	_mesh(_root, builder.build_chunk_mesh(0, 0, 1), Transform3D.IDENTITY, material)


func _ground_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GROUND
	for key: String in ["soil", "gravel", "concrete", "concrete_normal", "concrete_arm", "gravel_normal"]:
		var path: String = {
			"soil": FOREST_GROUND + "forest_ground_04_diff_1k.jpg",
			"gravel": FOREST_GROUND + "rocky_trail_diff_1k.jpg",
			"concrete": ART + "concrete_floor_worn_001_diff_4k.jpg",
			"concrete_normal": ART + "concrete_floor_worn_001_nor_gl_4k.jpg",
			"concrete_arm": ART + "concrete_floor_worn_001_arm_4k.jpg",
			"gravel_normal": FOREST_GROUND + "rocky_trail_nor_gl_1k.jpg",
		}[key]
		material.set_shader_parameter(key, load(path))
	return material


func _boundary() -> void:
	for side in [-1.0, 1.0]:
		_block(Vector3(0, 12, side * (HALF + 0.25)), Vector3(WIDTH + 1, 32, 0.5), null, 0, false)
		_block(Vector3(side * (HALF + 0.25), 12, 0), Vector3(0.5, 32, WIDTH), null, 0, false)


func _process_deck() -> void:
	_block(Vector3(0, DECK - 0.21, 0), Vector3(DECK_EDGE_X * 2, 0.42, 14.0), _deck, 0.0, false, "metal")
	# The flat terrain starts on the same grid line where the bridge ends.
	var bridge_center := (DECK_EDGE_X + BRIDGE_JOIN_X) * 0.5
	_block(Vector3(bridge_center, DECK - 0.18, 0), Vector3(BRIDGE_JOIN_X - DECK_EDGE_X, 0.36, 4.6),
		_deck, 0.0, false, "metal")
	for side in [-1.0, 1.0]:
		var foot := Vector3(0, 0.05, side * 17.8)
		var top := Vector3(0, DECK, side * 6.92)
		_ramp(foot, top)
		for z in [3.9, -3.9]:
			_block(Vector3(side * 7.8, 1.45, z), Vector3(0.62, 2.91, 0.62), _frame, 0.0, true, "metal")
		_rail(Vector3(-8.45, DECK, side * 6.9), Vector3(-2.48, DECK, side * 6.9))
		_rail(Vector3(2.48, DECK, side * 6.9), Vector3(8.35, DECK, side * 6.9))
		_rail(Vector3(8.45, DECK, side * 2.25), Vector3(BRIDGE_JOIN_X, DECK, side * 2.25))
		_rail(Vector3(8.45, DECK, side * 6.9), Vector3(8.45, DECK, side * 2.25))
	_rail(Vector3(-8.45, DECK, -6.9), Vector3(-8.45, DECK, 6.9))
	_block(Vector3(-4.8, 1.12, 0), Vector3(3.0, 2.24, 2.8), _teal, 0.0, true, "metal")
	_block(Vector3(5.5, DECK + 0.69, 3.7), Vector3(2.9, 1.38, 1.25), _teal, 0.0, true, "metal")
	_block(Vector3(-5.65, DECK + 0.65, -3.7), Vector3(2.6, 1.30, 1.25), _rust, 0.0, true, "metal")
	_tank(Vector3(-6.8, DECK, 0.5), 1.03, 4.7, _teal)
	_pipe(Vector3(-6.8, DECK + 3.55, 0.5), Vector3(-9.5, DECK + 3.55, 0.5), 0.22, _white, true, true)
	_pipe(Vector3(-9.5, DECK + 3.55, 0.5), Vector3(-9.5, 0.9, 0.5), 0.22, _rust, true, true)
	if _visuals:
		for z in [-6.45, 6.45]:
			_box(Vector3(0, DECK + 0.014, z), Vector3(4.5, 0.026, 0.15), _amber)


func _ramp(foot: Vector3, top: Vector3) -> void:
	var basis := Basis.looking_at((top - foot).normalized())
	var width := 4.9
	var length := foot.distance_to(top)
	var center := foot.lerp(top, 0.5) - basis.y * 0.15
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.30, length + 0.12)
	_metal_box(center, shape.size, _deck, basis)
	for side in [-1.0, 1.0]:
		var offset: Vector3 = Vector3.RIGHT * (width * 0.5 - 0.10) * side
		_rail(foot + offset, top + offset)
		if not _visuals:
			continue
		for stripe in 13:
			var at := foot.lerp(top, (stripe + 0.5) / 13.0)
			_box(at + offset * 0.87 + basis.y * 0.021, Vector3(0.18, 0.025, 0.30), _amber, basis)


func _yard() -> void:
	for side in [-1.0, 1.0]:
		_hall(Vector3(-23.5, 0, side * 10.4), 10.0, 9.2, side)
		_tank(Vector3(-23.8, 0, side * 26.4), 3.25, 7.6, _white)
		_tank(Vector3(-29.8, _y(-29.8, side * 23.0), side * 23.0), 2.15, 10.2, _rust)
		_block(Vector3(-10.5, 0.57, side * 12.6), Vector3(3.0, 1.14, 1.36), _concrete)
		_block(Vector3(6.1, 0.65, side * 12.0), Vector3(2.8, 1.30, 1.22), _teal, 0.0, true, "metal")
	for z in [-18.6, 18.6]:
		for x in [-28.0, -13.6, 11.4]:
			_block(Vector3(x, 2.60, z), Vector3(0.36, 5.2, 0.38), _frame, 0.0, true, "metal")
			_block(Vector3(x, 0.22, z), Vector3(1.02, 0.44, 0.86), _concrete, 0.0, false)
	_hall(Vector3(-29.3, 0, 0), 6.6, 6.8, 1.0)
	_tank(Vector3(-33.6, _y(-33.6, -3.3), -3.3), 1.40, 15.1, _white, Vector3.FORWARD)
	_tank(Vector3(-33.6, _y(-33.6, 3.3), 3.3), 1.20, 12.8, _white, Vector3.BACK)
	_block(Vector3(-13.5, 1.31, 1.9), Vector3(2.9, 2.62, 2.35), _rust, 0.0, true, "metal")
	_block(Vector3(-22.8, 0.62, -2.0), Vector3(2.7, 1.24, 1.20), _concrete)
	_block(Vector3(12.5, _y(12.5, 10) + 0.69, 10), Vector3(2.8, 1.38, 1.60), _concrete)
	_block(Vector3(12.5, _y(12.5, -10) + 0.69, -10), Vector3(2.8, 1.38, 1.60), _concrete)


func _containers() -> void:
	var teal := Color("#4ea9a6")
	var rust := Color("#d28053")
	_map._begin_container_fittings()
	for side in [-1.0, 1.0]:
		_map._add_container(Vector3(-11.8, _map.CONTAINER_HEIGHT * 0.5, side * 23.2),
			_map.LENGTH_20, _map.CONTAINER_WIDTH, teal if side > 0 else rust)
		_map._add_container(Vector3(8.8, _map.CONTAINER_HEIGHT * 0.5, side * 23.1),
			_map.LENGTH_20, _map.CONTAINER_WIDTH, rust if side > 0 else teal)
	_map._finish_container_fittings()


func _hall(at: Vector3, width: float, depth: float, side: float) -> void:
	var height := 4.5
	var siding := _teal if side > 0 else _white
	if width > 8.0:
		_block(at + Vector3(-width * 0.5, height * 0.5, 0), Vector3(0.22, height, depth), siding, 0.0, true, "metal")
		for end in [-1.0, 1.0]:
			_block(at + Vector3(0, height * 0.5, end * depth * 0.5), Vector3(width, height, 0.22), siding, 0.0, true, "metal")
			_block(at + Vector3(width * 0.48, 1.53, end * (depth * 0.5 - 0.76)),
				Vector3(0.38, 3.06, 1.58), _frame)
		_block(at + Vector3(width * 0.48, 3.8, 0), Vector3(0.22, 1.42, depth), siding, 0.0, false, "metal")
	else:
		_block(at + Vector3(0, height * 0.5, 0), Vector3(width, height, depth), siding)
	_block(at + Vector3(0, height + 0.15, 0), Vector3(width + 0.50, 0.30, depth + 0.50), _frame, 0.0, false)
	if not _visuals:
		return
	if width < 8.0:
		_box(at + Vector3(0, 0.42, 0), Vector3(width + 0.16, 0.84, depth + 0.16), _concrete)
	for z in [-1.0, 1.0]:
		var face := at + Vector3(0, 0, z * (depth * 0.5 + 0.055))
		_box(face + Vector3(-1.72, 1.55, 0), Vector3(3.15, 2.65, 0.12), _frame)
		for row in 9:
			_box(face + Vector3(-1.72, 0.46 + row * 0.268, z * 0.1), Vector3(2.89, 0.18, 0.075), _white)
		for column in 3:
			_box(face + Vector3(0.55 + column * 1.22, 3.31, 0), Vector3(1.06, 0.78, 0.13), _frame)
			_box(face + Vector3(0.55 + column * 1.22, 3.31, z * 0.085), Vector3(0.88, 0.60, 0.10), _glass)
	for index in 4:
		_box(at + Vector3(width * 0.503, 3.62, (index - 1.5) * depth * 0.22),
			Vector3(0.16, 0.80, depth * 0.198), _glass)
	_box(at + Vector3(-1.25, height + 0.49, 0), Vector3(2.8, 0.55, 1.45), _white)
	_box(at + Vector3(2, height + 0.35, 2), Vector3(1.3, 0.32, 1.6), _frame)


func _tank(at: Vector3, radius: float, height: float, material: Material, face := Vector3.RIGHT) -> void:
	var cap_height := height + 0.25
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = cap_height
	var tank := _body(shape, Transform3D(Basis.IDENTITY, at + Vector3.UP * cap_height * 0.5), "metal")
	tank.collision_layer = _map.BALANCE.MOVEMENT_PROXY_MASK
	_pipe(at, at + Vector3.UP * height, radius, material, true)
	_pipe(at + Vector3.UP * height, at + Vector3.UP * cap_height, radius + 0.055, _frame, true)
	_pipe(at + Vector3.UP * cap_height, at + Vector3.UP * (cap_height + 0.48), radius * 0.22, _white, true)
	if _visuals:
		for y in [0.25, height * 0.37, height * 0.67, height - 0.27]:
			_pipe(at + Vector3.UP * y, at + Vector3.UP * (y + 0.12), radius + 0.065, _frame)
	_climb_access(at, radius, cap_height, face)


func _climb_access(at: Vector3, radius: float, rise: float, face: Vector3) -> void:
	var bottom := at + face * (radius + 0.68)
	var ladder_basis := Basis(Vector3.UP, atan2(-face.z, face.x))
	var floor_height := at.y if is_equal_approx(at.y, DECK) else _y(bottom.x, bottom.z)
	bottom.y = floor_height + 0.06
	var deck_y := at.y + rise
	var landing := at + face * (radius - 0.53)
	landing.y = deck_y + 0.06
	_ladders.add_ladder(bottom, landing, face)
	for rung in floori((deck_y - floor_height) / 0.29):
		var center := Vector3(at.x, floor_height + 0.30 + rung * 0.29, at.z) + face * (radius + 0.13)
		_metal_box(center, Vector3(0.12, 0.045, 0.49), _amber, ladder_basis, true)
	for z in [-0.25, 0.25]:
		var rail_height := deck_y + 0.56 - floor_height
		var center := Vector3(at.x, floor_height + rail_height * 0.5, at.z)
		center += ladder_basis * Vector3(radius + 0.12, 0.0, z)
		_metal_box(center, Vector3(0.075, rail_height, 0.055), _amber, ladder_basis, true)


func _hills() -> void:
	var rocks := _meshes(load("res://game/maps/forest_ridge/art/rock/rock_moss_set_01_1k.gltf"))
	for point: Vector2 in [Vector2(30, 7), Vector2(29, -7), Vector2(19, 12),
			Vector2(19, -12), Vector2(25, 20), Vector2(25, -20), Vector2(32, 24), Vector2(32, -24),
			Vector2(33, -0.5), Vector2(36, 10), Vector2(36, -13), Vector2(-34, 13), Vector2(-35, -15)]:
		var size := Vector3(_rng.randf_range(2.5, 4.1), _rng.randf_range(1.9, 3.1), _rng.randf_range(2.5, 3.8))
		var center := Vector3(point.x, _y(point.x, point.y) + size.y * 0.22, point.y)
		var yaw := _rng.randf_range(0, TAU)
		var body := _block(center, size * Vector3(0.64, 0.66, 0.68), null, yaw)
		var variant := posmod(roundi(point.x * 11 + point.y), rocks.size())
		_fit_rock(body, rocks[variant], size)
	if not _visuals:
		return
	var shrubs := _meshes(load("res://assets/arena_props/shrubs.glb"))
	var trees: Mesh = load("res://assets/arena_props/village/village_tree.res")
	_lawn_grass()
	_scatter(shrubs, 420, Vector2(0.8, 1.65))
	var ferns := _meshes(load("res://game/maps/forest_ridge/art/fern/fern_02_1k.gltf"))
	_scatter(ferns, 630, Vector2(1.2, 2.2))
	_scatter(rocks, 250, Vector2(0.12, 0.34), _rock)
	if trees:
		var transforms: Array[Transform3D] = []
		for z in range(-37, 38, 5):
			var x := 34.3 + _rng.randf_range(-0.7, 3.2)
			var scale := _rng.randf_range(0.55, 1.13)
			for at in [Vector2(x, z), Vector2(-37.2, z + 1.0)]:
				transforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * scale),
					Vector3(at.x, _y(at.x, at.y) - 0.10, at.y)))
		for z in range(-32, 33, 8):
			var x := 29.5 + _rng.randf_range(0.0, 3.2)
			var scale := _rng.randf_range(0.62, 1.08)
			transforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * scale),
				Vector3(x, _y(x, z) - 0.10, z)))
		_multimesh(trees, transforms, null, true)


func _lawn_grass() -> void:
	var placements: Array[Transform3D] = []
	var lawn_rng := RandomNumberGenerator.new()
	lawn_rng.seed = 37619
	for ix in range(-156, 157):
		for iz in range(-158, 159):
			var x := ix * 0.25 + lawn_rng.randf_range(-0.035, 0.035)
			var z := iz * 0.25 + lawn_rng.randf_range(-0.035, 0.035)
			if (x > -31.0 and x < 15.0) or absf(x - 24.0) < 3.1 or (x < 21.0 and absf(z) < 3.3):continue
			placements.append(Transform3D(Basis.IDENTITY, Vector3(x, _y(x, z) - 0.015, z)))
	_map.TERRAIN_GRASS.queue(_root, placements)


func _scatter(meshes: Array[Mesh], count: int, size: Vector2, material: Material = null, grass := false) -> void:
	var patches: Dictionary = {}
	for index in count:
		var x := _rng.randf_range(15.0, 39.4) if index % 5 else _rng.randf_range(-39.0, -31.0)
		var z := _rng.randf_range(-39.5, 39.5)
		if absf(x - 24.0) < 3.1 or (x < 21.0 and absf(z) < 3.3):
			continue
		var id := Vector3i(floori(x / 20.0), floori(z / 20.0), index % meshes.size())
		if not patches.has(id):
			patches[id] = []
		var scale := _rng.randf_range(size.x, size.y)
		patches[id].append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * scale),
			Vector3(x, _y(x, z) - 0.035, z)))
	for id: Vector3i in patches:
		if grass:
			_map.TERRAIN_GRASS.queue(_root, patches[id])
			continue
		_multimesh(meshes[id.z], patches[id], material, false)


func _equipment() -> void:
	for side in [-1.0, 1.0]:
		_pump_skid(Vector3(8.2, 0, side * 17.5), side)
		_pump_skid(Vector3(28.3, _y(28.3, side * 22.4), side * 22.4), side)
		_cargo_stack(Vector3(-16.6, 0, side * 26.7), side)
		_prop("cabinet", Vector3(-7.9, 0, side * 17.6), Vector3(1.30, 1.58, 0.72), side * 0.25)
		_prop("cabinet", Vector3(6.6, DECK, side * 5.5), Vector3(1.12, 1.47, 0.63), side * PI * 0.5)
		_prop("tools", Vector3(-21.7, 0, side * 11.3), Vector3(1.24, 1.05, 0.54), -PI * 0.5)
		_prop("tools", Vector3(-21.4, 0, side * 17.6), Vector3(1.22, 0.98, 0.60), side * 0.32)
		_prop("jack", Vector3(-20.2, 0, side * 8.4), Vector3(0.75, 0.97, 1.48), side * 0.65)
		_prop("crate", Vector3(-25.8, 0, side * 8.0), Vector3(1.38, 1.05, 1.29), side * 0.13)
		_prop("crate", Vector3(14.8, _y(14.8, side * 31.8), side * 31.8), Vector3(1.14, 0.91, 1.17), side * 0.36)
		_block(Vector3(5.1, 0.71, side * 38.6), Vector3(16.0, 1.42, 0.48), _concrete)
		_block(Vector3(-17.0, 0.71, side * 38.6), Vector3(16.0, 1.42, 0.48), _concrete)
		if _visuals:
			_fence(Vector3(-25, 1.42, side * 38.6), Vector3(-9, 1.42, side * 38.6))
			_fence(Vector3(-2.9, 1.42, side * 38.6), Vector3(13.1, 1.42, side * 38.6))
			_sign(Vector3(-18.35, 3.57, side * 10.4), "0%d   ЦЕХ" % (1 if side > 0 else 2), PI * 0.5)
			_sign(Vector3(9.0, 2.1, side * 38.3), "ТЕХНИЧЕСКАЯ ЗОНА", PI if side > 0 else 0.0)
	_tank(Vector3(-26.0, 0, 3.9), 1.23, 4.5, _teal)
	_tank(Vector3(-25.4, 0, -3.7), 1.05, 3.7, _rust)
	_prop("crate", Vector3(-12.2, 0, 3.5), Vector3(1.03, 0.81, 0.88), -0.15)
	_prop("cabinet", Vector3(4.5, 0, -3.5), Vector3(1.48, 1.78, 0.85), PI * 0.5)
	_loading_gantry()


func _loading_gantry() -> void:
	for z in [-4.7, 4.7]:
		_block(Vector3(-26.7, 3.45, z), Vector3(0.40, 6.9, 0.40), _frame, 0.0, true, "metal")
		_block(Vector3(-26.7, 0.24, z), Vector3(1.27, 0.48, 1.27), _concrete, 0.0, false)
	if not _visuals:
		return
	for height in [6.25, 7.45]:
		_beam(Vector3(-26.7, height, -4.7), Vector3(-26.7, height, 4.7), 0.22, _amber)
	for panel in 6:
		var start := -4.7 + float(panel) * 9.4 / 6.0
		var end := start + 9.4 / 6.0
		_beam(Vector3(-26.7, 6.25, start), Vector3(-26.7, 7.45, end), 0.095, _amber)
		_beam(Vector3(-26.7, 6.25, end), Vector3(-26.7, 7.45, end), 0.075, _frame)
	_box(Vector3(-26.7, 6.08, -0.77), Vector3(0.86, 0.42, 0.72), _frame)
	_beam(Vector3(-26.7, 5.96, -0.77), Vector3(-26.7, 3.47, -0.77), 0.038, _frame)
	_beam(Vector3(-26.7, 3.47, -0.77), Vector3(-26.7, 3.29, -0.48), 0.079, _rust)
	_beam(Vector3(-26.7, 3.29, -0.48), Vector3(-26.7, 3.52, -0.39), 0.079, _rust)


func _pump_skid(at: Vector3, side: float) -> void:
	_block(at + Vector3.UP * 0.28, Vector3(3.05, 0.62, 2.05), _concrete)
	_block(at + Vector3.UP * 0.91, Vector3(2.38, 0.92, 1.44), _teal, 0.0, true, "metal")
	for z in [-0.46, 0.46]:
		_pipe(at + Vector3(-1.42, 1.14, z), at + Vector3(1.37, 1.14, z), 0.27, _rust, true, true)
		_pipe(at + Vector3(1.37, 1.13, z), at + Vector3(1.37, 1.74, z), 0.27, _white, true, true)
		_pipe(at + Vector3(1.37, 1.68, z), at + Vector3(1.37, 1.80, z), 0.36, _frame, true, true)
	_box(at + Vector3(-0.2, 1.47, side * 0.38), Vector3(0.69, 0.28, 0.58), _amber)


func _cargo_stack(at: Vector3, side: float) -> void:
	_prop("crate", at + Vector3(-0.7, 0, 0), Vector3(1.24, 1.02, 1.16), side * 0.14)
	_prop("crate", at + Vector3(-0.7, 1.02, 0), Vector3(0.90, 0.73, 0.93), -side * 0.18)
	_prop("crate", at + Vector3(0.72, 0, side * 0.28), Vector3(1.04, 0.90, 0.91), -side * 0.12)
	if _visuals:
		for offset in [-0.45, 0.0, 0.45]:
			_box(at + Vector3(offset - 0.34, 0.055, -0.76), Vector3(0.29, 0.11, 1.09), _rust)
	var barrel := at + Vector3(1.68, 0, 0.45)
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.31
	cylinder.height = 0.85
	var proxy := _body(cylinder, Transform3D(Basis.IDENTITY, barrel + Vector3.UP * 0.425), "metal")
	proxy.collision_layer = _map.BALANCE.MOVEMENT_PROXY_MASK
	_pipe(barrel, barrel + Vector3.UP * 0.85, 0.31, _rust, true)
	_pipe(barrel + Vector3.UP * 0.51, barrel + Vector3.UP * 0.58, 0.32, _white)


func _prop(kind: String, feet: Vector3, size: Vector3, yaw: float) -> void:
	var center := feet + Vector3.UP * size.y * 0.5
	var surface := "wood" if kind == "crate" else "metal"
	var body := _block(center, size, null, yaw, true, surface, false)
	if not _prop_scenes.has(kind):
		_prop_scenes[kind] = load(PROP_SCENES[kind]) as PackedScene
	var model := _prop_scenes[kind].instantiate() as Node3D
	var bounds := AABB()
	for item: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var pose := item.transform
		var parent := item.get_parent() as Node3D
		while parent != model:
			pose = parent.transform * pose
			parent = parent.get_parent()
		var box := pose * item.get_aabb()
		bounds = bounds.merge(box) if bounds.has_volume() else box
	if model is MeshInstance3D:
		bounds = model.get_aabb()
	var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(size / bounds.size)
	model.transform = body.transform.affine_inverse() * Transform3D(basis, center - basis * bounds.get_center())
	body.add_child(model)
	var shot := SHOT_COLLISION.use_model(body, model)
	if kind == "crate" or kind == "cabinet" or kind == "tools":
		var resistance := 0.32 if kind == "crate" else 0.46
		_set_perforation(body, size + Vector3.ONE * 0.024, resistance)
		shot.set_meta(&"ballistic_size", body.get_meta(&"ballistic_size"))
		shot.set_meta(&"ballistic_resistance", resistance)
		shot.set_meta(&"ballistic_mesh_exit", true)
		shot.set_meta(&"bullet_cover_id", body.get_meta(&"bullet_cover_id"))
	if not _visuals:
		model.free()


func _fence(a: Vector3, b: Vector3) -> void:
	var rail := Vector3.UP * 1.48
	_beam(a, b, 0.055, _frame)
	_beam(a + rail, b + rail, 0.055, _frame)
	for index in 9:
		var post := a.lerp(b, index / 8.0)
		_beam(post, post + rail, 0.075, _frame)
	for index in 33:
		var bottom := a.lerp(b, index / 33.0)
		var top := a.lerp(b, (index + 1) / 33.0) + rail
		_beam(bottom, top, 0.018, _frame)


func _sign(at: Vector3, title: String, yaw: float) -> void:
	_box(at, Vector3(3.15, 0.56, 0.09), _frame, Basis(Vector3.UP, yaw))
	var label := Label3D.new()
	label.position = at + Vector3(0, 0, 0.055).rotated(Vector3.UP, yaw)
	label.rotation.y = yaw
	label.text = title
	label.modulate = Color("#ffe2a2")
	label.font_size = 38
	label.pixel_size = 0.006
	label.outline_size = 0
	_root.add_child(label)


func _pipe_racks() -> void:
	# Pipe racks frame the yard, leaving the service lanes open below.
	for z: float in [-RACK_Z, RACK_Z]:
		for offset: float in RACK_PIPE_OFFSETS:
			_pipe(Vector3(-29.0, RACK_PIPE_Y, z + offset), Vector3(RACK_EAST_X, RACK_PIPE_Y, z + offset),
				RACK_PIPE_RADIUS, _rust if offset < 0 else _white, true, true)
			_pipe(Vector3(RACK_EAST_X, RACK_PIPE_Y, z + offset), Vector3(RACK_EAST_X, 1.4, z + offset),
				RACK_PIPE_RADIUS, _teal, true, true)
		_climb_access(Vector3(RACK_EAST_X, 0, z + RACK_PIPE_OFFSETS[1]), RACK_PIPE_RADIUS,
			RACK_PIPE_Y + RACK_PIPE_RADIUS, Vector3.RIGHT)
		_beam(Vector3(-29.5, 5.08, z), Vector3(12.0, 5.08, z), 0.27, _frame)
		for x in [-25.0, -18.0, -10.0, -2.0, 6.0]:
			_beam(Vector3(x, 5.12, z - 0.85), Vector3(x + 2.4, 5.12, z + 0.85), 0.09, _frame)
			_pipe(Vector3(x, 5.48, z - 0.52), Vector3(x + 0.15, 5.48, z - 0.52), 0.30, _frame, true, true)
		for x in range(-27, 12, 3):
			_box(Vector3(x, 5.17, z), Vector3(0.21, 0.23, 2.1), _frame)
	for z in [-3.3, 3.3]:
		_pipe(Vector3(-33.6, 5.95, z), Vector3(-26.7, 5.95, z), 0.49, _rust, true, true)
		_pipe(Vector3(-26.7, 5.95, z), Vector3(-26.7, 3.8, z), 0.49, _rust, true, true)


func _detail() -> void:
	for z in [-28, -25, -21, -15, -10, -5, 5, 10, 15, 21, 25, 28]:
		_box(Vector3(-15.4, 0.025, z), Vector3(0.12, 0.03, 1.5), _amber)
	for side in [-1.0, 1.0]:
		for bay in 4:
			var x := -14.0 + bay * 2.4
			_box(Vector3(x, 0.014, side * 35.45), Vector3(0.070, 0.024, 3.5), _amber)
		_box(Vector3(-10.4, 0.014, side * 33.7), Vector3(7.28, 0.024, 0.075), _amber)
		for stripe in 7:
			var x := -14.7 + stripe * 0.42
			_box(Vector3(x, 0.019, side * 18.55), Vector3(0.17, 0.029, 1.13),
				_amber, Basis(Vector3.UP, PI * 0.25))
	for z in [-32.0, 32.0]:
		for x in [-19.6, 15.0]:
			_box(Vector3(x, 3.35, z), Vector3(0.17, 6.7, 0.17), _frame)
			_box(Vector3(x, 6.57, z), Vector3(1.30, 0.10, 0.22), _frame)
			_box(Vector3(x, 6.46, z - signf(z) * 0.16), Vector3(0.84, 0.20, 0.24), _white)
	MARKING.paint(_root, "01 / ПОГРУЗКА", Vector3(-18, 0.015, 18), Color("#f2c75f"), 0.0, 3.9)
	MARKING.paint(_root, "02 / ЭСТАКАДА", Vector3(0, DECK + 0.012, 5.7), Color("#eec66d"), 0.0, 3.9)
	MARKING.paint(_root, "03 / СКЛОН", Vector3(24, DECK + 0.018, 4.6), Color("#eddda2"), 0.0, 3.9)


func _rail(a: Vector3, b: Vector3) -> void:
	var direction := b - a
	var basis := Basis.looking_at(direction)
	for height in [0.10, 0.33, 0.59]:
		_metal_box(a.lerp(b, 0.5) + Vector3.UP * height, Vector3(0.063, 0.063, direction.length()),
			_amber if height > 0.5 else _frame, basis)
	var bays := ceili(direction.length() / 1.45)
	for index in bays + 1:
		_metal_box(a.lerp(b, float(index) / bays) + Vector3.UP * 0.29, Vector3(0.07, 0.58, 0.07), _frame)


func _metal_box(at: Vector3, size: Vector3, material: Material, basis := Basis.IDENTITY,
		shot_only := false) -> StaticBody3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var body := _body(shape, Transform3D(basis, at), "metal")
	if shot_only:
		body.collision_layer = _map.BALANCE.SHOT_GEOMETRY_MASK
		body.collision_mask = 0
	_set_perforation(body, size)
	if _visuals:
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = material
		_mesh(body, mesh, Transform3D.IDENTITY)
	return body


func _set_perforation(body: StaticBody3D, size: Vector3, resistance := 1.0) -> void:
	body.set_meta(&"ballistic_size", size)
	body.set_meta(&"ballistic_resistance", resistance)
	_map._register_perforated_cover(body)


func _block(at: Vector3, size: Vector3, material: Material, yaw := 0.0, minimap := true, surface := "concrete",
		perforates := true) -> StaticBody3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var basis := Basis(Vector3.UP, yaw)
	var body: StaticBody3D
	if surface == "metal" and perforates:
		body = _metal_box(at, size, material, basis)
	else:
		body = _body(shape, Transform3D(basis, at), surface)
		if _visuals and material:
			_box(at, size, material, basis)
	if minimap:
		var polygon := PackedVector2Array()
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			polygon.append(Vector2(at.x, at.z) + (corner * Vector2(size.x, size.z) * 0.5).rotated(-yaw))
		_outline.append(polygon)
	return body


func _body(shape: Shape3D, transform: Transform3D, surface: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.transform = transform
	body.set_meta(&"impact_surface", surface)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	_root.add_child(body)
	return body


func _box(at: Vector3, size: Vector3, material: Material, basis := Basis.IDENTITY) -> void:
	if not _visuals:
		return
	if not _batches.has(material):
		_batches[material] = []
	_batches[material].append(Transform3D(basis * Basis.from_scale(size), at))


func _beam(a: Vector3, b: Vector3, width: float, material: Material) -> void:
	var direction := (b - a).normalized()
	var up := Vector3.FORWARD if absf(direction.y) > 0.98 else Vector3.UP
	_box(a.lerp(b, 0.5), Vector3(width, width, a.distance_to(b)), material, Basis.looking_at(direction, up))


func _pipe(a: Vector3, b: Vector3, radius: float, material: Material, shootable := false, solid := false) -> void:
	if not shootable and not _visuals:
		return
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 48
	mesh.rings = 2
	var up := (b - a).normalized()
	var rotation := Basis(Quaternion(Vector3.UP, up))
	var placement := Transform3D(rotation, a.lerp(b, 0.5))
	if shootable:
		var body := _body(mesh.create_trimesh_shape(), placement, "metal")
		body.collision_layer = _map.BALANCE.SHOT_GEOMETRY_MASK
		if solid:
			body.collision_layer |= _map.BALANCE.MOVEMENT_PROXY_MASK
		body.collision_mask = 0
		body.set_meta(&"ballistic_mesh_exit", true)
		_set_perforation(body, Vector3(radius * 2, mesh.height, radius * 2), 0.84)
		if _visuals:
			mesh.material = material
			_mesh(body, mesh, Transform3D.IDENTITY)
	elif _visuals:
		_mesh(_root, mesh, placement, material)


func _mesh(parent: Node3D, mesh: Mesh, placement: Transform3D, material: Material = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.transform = placement
	node.material_override = material
	parent.add_child(node)
	return node


func _flush_boxes() -> void:
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	for material: Material in _batches:
		_multimesh(unit, _batches[material], material, true)


func _multimesh(mesh: Mesh, transforms: Array, material: Material, shadows: bool) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(node)


func _meshes(scene: PackedScene) -> Array[Mesh]:
	var root := scene.instantiate()
	var meshes: Array[Mesh] = []
	if root is MeshInstance3D:
		meshes.append(root.mesh)
	for child: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		meshes.append(child.mesh)
	root.free()
	return meshes


func _fit_rock(body: StaticBody3D, mesh: Mesh, size: Vector3) -> void:
	var bounds := mesh.get_aabb()
	var basis := Basis.from_scale(size / bounds.size)
	var visual := _mesh(body, mesh, Transform3D(basis, -(basis * bounds.get_center())), _rock)
	SHOT_COLLISION.use_model(body, visual)
	if not _visuals:
		visual.free()


func _material(asset: String, tint: Color, metallic: float, tiling: float,
		textured_color := true) -> StandardMaterial3D:
	var material := _paint(tint, metallic)
	if textured_color:
		material.albedo_texture = load(ART + asset + "_diff_4k.jpg")
	material.normal_enabled = true
	material.normal_texture = load(ART + asset + "_nor_gl_4k.jpg")
	material.normal_scale = 0.65
	material.roughness_texture = load(ART + asset + "_arm_4k.jpg")
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	material.ao_enabled = true
	material.ao_texture = material.roughness_texture
	material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * tiling
	return material


func _paint(tint: Color, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.metallic = metallic
	material.roughness = 0.75
	return material


func _y(x: float, z: float) -> float:
	return _heightfield.sample_world(x, z)
