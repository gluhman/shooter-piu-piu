extends RefCounted

const EarthSurface := preload("res://game/maps/procedural/earth_surface.gd")
const Terrain := preload("res://game/maps/procedural/village_terrain.gd")
const Fixtures := preload("res://game/maps/procedural/village_fixtures.gd")
const GROUND_SHADER := preload("res://game/maps/procedural/village_ground.gdshader")
const AWNING_SHADER := preload("res://game/maps/procedural/village_awning.gdshader")
const VILLAGE_TREE := preload("res://assets/arena_props/village/village_tree.res")
const PROP_ROOT := "res://assets/arena_props/village/"
const TIMBER_HEIGHT := 3.05
const INN_FLOOR := 2.9
const WALL := 0.24

var _map: Node3D
var _terrain: Terrain
var _fixtures: Fixtures
var _rng: RandomNumberGenerator
var _batches: Dictionary[Material, SurfaceTool] = {}
var _lots: Array[Rect2] = []
var _terrain_pads: Array[Rect2] = []
var _supplies: Array[Transform3D] = []
var market_supply_count := 0
var _trim: Material
var _fence: Material
var _gable: StandardMaterial3D
var _roof: Material
var _stone: StandardMaterial3D
var _road: Material
var _iron: Material
var _dark: Material
var _amber: StandardMaterial3D
var _barrel_model: PackedScene
var _crate_model: PackedScene
var _bucket_model: PackedScene
var _basket_model: PackedScene


func _init(map: Node3D) -> void:
	_map = map


func build(width: float, rng: RandomNumberGenerator) -> Array[Transform3D]:
	_rng = rng
	var half := width * 0.5
	_barrel_model = load(PROP_ROOT + "wine_barrel_01.glb")
	_crate_model = load(PROP_ROOT + "wooden_crate_01.glb")
	_bucket_model = load(PROP_ROOT + "wooden_bucket_02.glb")
	_basket_model = load(PROP_ROOT + "wicker_basket_01.glb")
	_trim = _map._world_mat("planks", Color(0.68, 0.53, 0.38), 0.0, 0.8, 0.85, true)
	_fence = _map._world_mat("planks", Color(0.46, 0.35, 0.26), 0.0, 0.9, 1.0, true)
	_gable = _fence.duplicate()
	_gable.cull_mode = BaseMaterial3D.CULL_DISABLED
	_roof = _map._world_mat("village/roof", Color(0.92, 0.78, 0.64), 0.0, 0.42, 1.15, true)
	_stone = _map._world_mat("village/plaster", Color(0.72, 0.69, 0.60), 0.0, 0.48, 1.18, true)
	_road = _map._world_mat("village/cobble", Color(0.83, 0.77, 0.68), 0.0, 0.5, 1.25, true)
	_iron = _map._container_mat(Color(0.22, 0.22, 0.20))
	_dark = _flat(Color(0.115, 0.082, 0.056), 0.87)
	_amber = _flat(Color(0.84, 0.45, 0.16), 0.58)
	_amber.emission_enabled = true
	_amber.emission = Color(0.66, 0.32, 0.085)
	_fixtures = Fixtures.new()
	_fixtures.name = "VillageFixtures"
	_map.add_child(_fixtures)
	_build_boundary(half)

	var barn := Vector2(-3.1, -half + 3.6)
	var gate := Vector2(3.1, half - 3.6)
	var street := PackedVector2Array([
		Vector2(barn.x, barn.y - 2.4), Vector2(-3.1, -10.5), Vector2(-2.2, -4.0),
		Vector2(0, 0), Vector2(2.2, 4.0), Vector2(3.1, 10.5), Vector2(gate.x, gate.y + 2.4),
	])
	_paved_path(street, 4.5, _road)
	_paved_path(PackedVector2Array([Vector2(-4.9, 0), Vector2(-12.5, 0.4), Vector2(-16.8, 0.4)]), 2.1, _road)
	_market()
	_inn()
	_shop()
	_yards(half)
	_start_area(barn, false)
	_start_area(gate, true)
	_build_spawns(barn, gate)
	_build_ground(half)
	_plant_forest(half)
	for material in _batches:
		var visual := MeshInstance3D.new()
		visual.mesh = _batches[material].commit()
		visual.material_override = material
		_map.add_child(visual)
	return _supplies


func ground_height(point: Vector2) -> float:
	return _terrain.height_at(point)


func _build_ground(half: float) -> void:
	var pads: Array[Rect2] = _terrain_pads.duplicate()
	pads.append_array(_map._occupied)
	_terrain = Terrain.new(half, pads)
	var ground := ShaderMaterial.new()
	ground.shader = GROUND_SHADER
	ground.set_shader_parameter("detail_color", _map._tex("village/dirt", "color"))
	ground.set_shader_parameter("detail_normal", _map._tex("village/dirt", "normal"))
	ground.set_shader_parameter("detail_roughness", _map._tex("village/dirt", "roughness"))
	var landscape := MeshInstance3D.new()
	var horizon := PlaneMesh.new()
	horizon.size = Vector2.ONE * 480.0
	landscape.mesh = horizon
	landscape.material_override = ground
	landscape.position.y = Terrain.HORIZON_Y - 0.02
	landscape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_map.add_child(landscape)
	var extent := half + 4.0
	var body := EarthSurface.new()
	body.name = "VillageTerrain"
	body.paving = _terrain_pads.duplicate()
	var dirt: Material = _map._world_mat("village/dirt", Color(0.74, 0.60, 0.45), 0.0, 0.9, 1.15, false)
	# Capture the terrain so it outlives this layout builder.
	var terrain := _terrain
	var sample := func(point: Vector2) -> float: return terrain.height_at(point)
	body.configure(Rect2(-Vector2.ONE * extent, Vector2.ONE * extent * 2.0),
		sample, ground, dirt, terrain.make_mesh())
	_map.add_child(body)


func _build_boundary(half: float) -> void:
	var width := half * 2.0
	for side in [-1.0, 1.0]:
		var edge: float = side * (half + 0.2)
		_solid(Vector3(0, 1.4, edge), Vector3(width + 0.8, 2.8, 0.4), _fence)
		_solid(Vector3(edge, 1.4, 0), Vector3(0.4, 2.8, width), _fence)
		for along in range(-floori(half) + 5, ceili(half), 5):
			_paint(Vector3(along, 1.48, edge), Vector3(0.32, 2.96, 0.6), _trim)
			_paint(Vector3(edge, 1.48, along), Vector3(0.6, 2.96, 0.32), _trim)


func _paved_path(points: PackedVector2Array, width: float, material: Material) -> void:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for index in points.size():
		var before := points[maxi(0, index - 1)]
		var after := points[mini(points.size() - 1, index + 1)]
		var tangent := (after - before).normalized()
		var edge := Vector2(tangent.y, -tangent.x) * width * 0.5
		left.append(points[index] + edge)
		right.append(points[index] - edge)
	for index in points.size() - 1:
		var span := Rect2(left[index], Vector2.ZERO)
		for point in [left[index + 1], right[index], right[index + 1]]:
			span = span.expand(point)
		_lots.append(span.grow(0.3))
		var sections := maxi(1, ceili(left[index].distance_to(left[index + 1]) / 1.25))
		for section in sections:
			var from := float(section) / sections
			var to := float(section + 1) / sections
			var pad := Rect2(left[index].lerp(left[index + 1], from), Vector2.ZERO)
			pad = pad.expand(left[index].lerp(left[index + 1], to))
			pad = pad.expand(right[index].lerp(right[index + 1], from))
			pad = pad.expand(right[index].lerp(right[index + 1], to))
			_terrain_pads.append(pad)
		for point: Vector2 in [left[index], left[index + 1], right[index + 1], left[index], right[index + 1], right[index]]:
			mesh.set_normal(Vector3.UP)
			mesh.set_uv(point * 0.5)
			mesh.add_vertex(Vector3(point.x, 0.013, point.y))
	mesh.generate_tangents()
	mesh.index()
	_batch(material).append_from(mesh.commit(), 0, Transform3D.IDENTITY)


func _market() -> void:
	_paint(Vector3(0, 0.018, 0), Vector3(10.8, 0.02, 9.2), _road)
	var paving := Rect2(-5.5, -4.7, 11, 9.4)
	_lots.append(paving)
	_terrain_pads.append(paving)
	_well(Vector3(0.15, 0.0, 0.15))
	_stall(Vector2(-3.6, 2.9), Color(0.59, 0.19, 0.13), 0.0)
	_stall(Vector2(3.5, -2.8), Color(0.22, 0.35, 0.29), PI)
	_fence_panel(Vector2(5.42, 0.29), 8.6, true, 2.3)
	_barrel(Vector3(-4.6, 0, -2.8), 0.4)
	_barrel(Vector3(4.1, 0, 3.5), 1.2)
	# Low cover on the north approach leaves space on both sides to reach the well.
	_crate(Vector3(-1.9, 0.024, -3.3), 0.22)
	_bench(_frame(Vector2(2.0, 3.9), -0.25), Vector3.UP * 0.024)
	_sign(_frame(Vector2(0.15, 0.15), 0.0), Vector3(0, 2.62, 0.24), "MARKET")
	for point in [Vector2(-4.0, -1.45), Vector2(4.2, 1.4), Vector2(4.2, -0.85), Vector2(-4.0, 0.85)]:
		_add_supply(point)
	market_supply_count = _supplies.size()


func _well(at: Vector3) -> void:
	var masonry: StandardMaterial3D = _map._world_mat("village/cobble", Color(0.77, 0.76, 0.70), 0.0, 0.66, 1.1, true)
	var cap: StandardMaterial3D = _map._world_mat("village/plaster", Color(0.90, 0.88, 0.79), 0.0, 0.7, 1.0, true)
	for course in 6:
		for index in 18:
			var angle := (float(index) + float(course % 2) * 0.5) * TAU / 18.0
			var radius := 0.88 + _rng.randf_range(-0.025, 0.025)
			var block := Vector3(sin(angle) * radius, 0.16 + 0.26 * course, cos(angle) * radius)
			_paint(at + block, Vector3(0.32, 0.247, 0.32), masonry, 0.0, angle)
	for index in 20:
		var angle := float(index) * TAU / 20.0
		_paint(at + Vector3(sin(angle), 1.65, cos(angle)) * Vector3(0.89, 1, 0.89),
			Vector3(0.30, 0.20, 0.46), cap, 0.0, angle)
	_hidden_box(at + Vector3.UP * 0.875, Vector3(1.92, 1.75, 1.92), "concrete")
	_cylinder(at + Vector3.UP * 1.16, 0.77, 0.015, _flat(Color(0.06, 0.14, 0.13), 0.18))
	for side in [-1.0, 1.0]:
		_solid(at + Vector3(side * 0.99, 1.61, 0), Vector3(0.16, 3.20, 0.17), _trim, false)
	_paint(at + Vector3.UP * 2.63, Vector3(2.17, 0.10, 0.13), _trim)
	_paint(at + Vector3.UP * 2.22, Vector3(1.70, 0.18, 0.18), _trim)
	_paint(at + Vector3(0.26, 1.85, 0.04), Vector3(0.026, 0.74, 0.026), _trim)
	_prop(_bucket_model, at + Vector3(0.26, 1.27, 0.04), 0.6, 0.62)
	_gable_roof(Transform3D(Basis.IDENTITY, at), Vector2(2.45, 1.8), 3.03, 0.48)


func _stall(at: Vector2, tint: Color, yaw: float) -> void:
	var frame := _frame(at, yaw)
	for x in [-1.28, 1.28]:
		for z in [-0.58, 0.58]:
			_piece(frame, Vector3(x, 1.14, z), Vector3(0.12, 2.28, 0.12), _trim)
	_piece(frame, Vector3(0, 0.44, 0.44), Vector3(2.58, 0.88, 0.28), _fence)
	_piece(frame, Vector3(0, 0.94, 0.22), Vector3(2.86, 0.14, 0.82), _trim)
	_paint(frame * Vector3(0, 2.22, -0.60), Vector3(2.85, 0.09, 0.10), _trim, 0, yaw)
	_paint(frame * Vector3(0, 2.22, 0.60), Vector3(2.85, 0.09, 0.10), _trim, 0, yaw)
	var awning := PlaneMesh.new()
	awning.size = Vector2(3.0, 1.65)
	awning.subdivide_width = 32
	awning.subdivide_depth = 12
	var cloth := ShaderMaterial.new()
	cloth.shader = AWNING_SHADER
	cloth.set_shader_parameter("stripe_color", tint)
	_mesh(awning, cloth, frame.translated_local(Vector3(0, 2.26, 0)))
	_prop(_basket_model, frame * Vector3(-0.68, 1.01, 0.23), yaw + 0.3, 0.85)
	_prop(_bucket_model, frame * Vector3(0.65, 1.01, 0.27), yaw - 0.45, 0.62)
	_crate(frame * Vector3(-0.56, 0.0, -0.66), yaw + 0.14)


func _inn() -> void:
	var frame := _frame(Vector2(-9.8, -5.2), PI * 0.5)
	var size := Vector2(8.0, 6.6)
	var wall: StandardMaterial3D = _map._world_mat("village/plaster", Color(0.98, 0.91, 0.78), 0, 0.48, 1.12, true)
	_lot(frame, size + Vector2(3.0, 3.8))
	_floor(frame, size)
	for side in [-1.0, 1.0]:
		# The rear lintel sits below the wooden threshold at the upstairs door.
		var lintel_clearance := 0.03 if side < 0.0 else 0.0
		_open_wall(frame, side * 3.3, size.x, 0.0, INN_FLOOR, 0.0, 1.75, 0.0, 2.25, wall, lintel_clearance)
		_house_door(frame, Vector3(0, 0, side * 3.3), 1.75, 2.25, side)
		if side > 0.0:
			_open_wall(frame, side * 3.3, size.x, INN_FLOOR, 2.67, 0.0, 2.25, 0.70, 2.54, wall)
			_window(frame, Vector3(0, 3.60, 3.3), 2.25, 1.84)
			_sign(frame, Vector3(0, 2.59, 3.53), "ПОСТОЯЛЫЙ ДВОР")
		else:
			_open_wall(frame, side * 3.3, size.x, INN_FLOOR, 2.67, 0.0, 1.72, 0.0, 2.21, wall)
			_house_door(frame, Vector3(0, INN_FLOOR, side * 3.3), 1.72, 2.21, side)
		_piece(frame, Vector3(side * 4.0, 2.785, 0), Vector3(WALL, 5.57, 6.6), wall)
		_paint(frame * Vector3(side * 3.83, 2.91, 3.45), Vector3(0.25, 5.83, 0.23), _trim, 0, PI * 0.5)
	# Carry the upstairs floor through the doorway to the outside face of the wall.
	_piece(frame, Vector3(0.96, INN_FLOOR - 0.13, -0.06), Vector3(6.08, 0.26, 6.72), _trim, false)
	_piece(frame, Vector3(-3.04, INN_FLOOR - 0.13, 2.27), Vector3(1.92, 0.26, 2.06), _trim, false)
	_stairs(frame, Vector3(-2.98, 0, -2.19), Vector3(-2.98, INN_FLOOR, 1.24), 1.65)
	_paint(frame * Vector3(-1.94, INN_FLOOR + 0.82, -0.91), Vector3(0.12, 0.12, 4.24), _trim, 0, PI * 0.5)
	_piece(frame, Vector3(0, INN_FLOOR - 0.13, -4.405), Vector3(2.3, 0.26, 1.97), _trim, false)
	_stairs(frame, Vector3(-6.55, 0, -4.43), Vector3(-1.15, INN_FLOOR, -4.43), 1.64)
	# The ramp is continuous, but voxel clearance splits off the first part from the yard.
	var stair_approach := NavigationLink3D.new()
	stair_approach.start_position = frame * Vector3(-7.15, 0.2, -4.43)
	stair_approach.end_position = frame * Vector3(-5.43, 0.8, -4.43)
	_map.add_child(stair_approach)
	_piece(frame, Vector3(0, INN_FLOOR + 0.39, -5.39), Vector3(2.25, 0.78, 0.12), _fence, false)
	_piece(frame, Vector3(1.12, INN_FLOOR + 0.39, -4.34), Vector3(0.12, 0.78, 2.04), _fence, false)
	_gable_roof(frame, size + Vector2(1.0, 1.0), 5.57, 1.14, size)
	_piece(frame, Vector3(2.56, 5.9, -1.4), Vector3(0.62, 2.0, 0.68), _stone, false)
	_bench(frame, Vector3(2.75, 0, 2.33))
	_barrel(frame * Vector3(2.63, 0, -2.35), 0.5)
	_crate(frame * Vector3(2.42, INN_FLOOR, 1.90), 0.6)
	_piece(frame, Vector3(2.73, 0.51, -0.91), Vector3(1.75, 1.02, 0.64), _fence)
	_paint(frame * Vector3(2.73, 1.05, -0.91), Vector3(1.89, 0.11, 0.78), _trim, 0, PI * 0.5)
	_prop(_basket_model, frame * Vector3(2.60, 1.105, -0.91), 1.1)
	_interior_light(frame, Vector3(2.65, 2.22, -1.0))
	_interior_light(frame, Vector3(2.83, INN_FLOOR + 1.97, -2.61))
	_lantern(frame, Vector3(-1.37, 1.95, 3.57))
	_lantern(frame, Vector3(1.37, 1.95, 3.57))
	_add_supply(_ground_point(frame * Vector3(2.20, 0, 0.45)))


func _shop() -> void:
	var frame := _frame(Vector2(-8.9, 5.9), PI * 0.5)
	var size := Vector2(5.8, 5.4)
	var wall: StandardMaterial3D = _map._world_mat("village/plaster", Color(0.83, 0.75, 0.55), 0, 0.48, 1.05, true)
	_lot(frame, size + Vector2.ONE * 1.6)
	_floor(frame, size)
	for side in [-1.0, 1.0]:
		_open_wall(frame, side * 2.7, size.x, 0.0, TIMBER_HEIGHT, 0.0, 1.65, 0.0, 2.21, wall)
		_house_door(frame, Vector3(0, 0, side * 2.7), 1.65, 2.21, side)
		var flank := frame * Transform3D(Basis(Vector3.UP, side * PI * 0.5), Vector3(side * 2.9, 0, 0))
		_open_wall(flank, 0.0, size.y, 0.0, TIMBER_HEIGHT, 0.0, 1.58, 0.72, 2.62, wall)
		_window(flank, Vector3(0, 0.72, 0), 1.58, 1.90)
	_gable_roof(frame, size + Vector2.ONE * 0.7, TIMBER_HEIGHT, 0.92, size)
	_sign(frame, Vector3(0, 2.48, 2.89), "ЛАВКА")
	_bench(frame, Vector3(1.86, 0, 1.72))
	_crate(frame * Vector3(-1.95, 0, 1.41), 0.6)
	_lantern(frame, Vector3(-1.19, 1.91, 2.97))
	_interior_light(frame, Vector3(2.15, 2.17, -1.5))


func _yards(half: float) -> void:
	var west := -16.1
	var east := 14.5
	_paved_path(PackedVector2Array([Vector2(-6.6, -half + 3.0), Vector2(west, -11.6),
		Vector2(west, 0.5), Vector2(west, 10.1), Vector2(0.2, half - 5.4)]), 1.55, _road)
	_paved_path(PackedVector2Array([Vector2(6.8, half - 3.6), Vector2(east, 10.4),
		Vector2(east, -3.9), Vector2(east, -10.8), Vector2(0.5, -half + 4.2)]), 1.55, _road)
	var cream: StandardMaterial3D = _map._world_mat("village/plaster", Color(0.78, 0.69, 0.56), 0, 0.48, 1.0, true)
	var green: StandardMaterial3D = _map._world_mat("planks", Color(0.44, 0.55, 0.46), 0, 0.72, 1.0, true)
	var red: StandardMaterial3D = _map._world_mat("planks", Color(0.64, 0.37, 0.28), 0, 0.72, 1.0, true)
	_landmark(_frame(Vector2(7.3, -7.1), -PI * 0.5), Vector2(5.9, 5.6), cream, 3.55)
	_landmark(_frame(Vector2(8.5, 5.1), -PI * 0.5), Vector2(5.8, 5.6), green, 3.2)
	_landmark(_frame(Vector2(8.0, 12.3), -PI * 0.5), Vector2(4.8, 4.7), red, 3.15)
	_landmark(_frame(Vector2(-10.6, -13.0), PI * 0.5), Vector2(4.8, 4.4), green, 2.95)
	_landmark(_frame(Vector2(-10.6, 13.15), PI * 0.5), Vector2(5.0, 4.3), cream, 2.95)
	_shed(_frame(Vector2(-17.2, 5.5), PI * 0.5))
	_shed(_frame(Vector2(17.2, -5.9), -PI * 0.5))
	for panel: Vector3 in [Vector3(-12.95, 3.9, 2.35), Vector3(-14.0, 8.3, 3.4),
			Vector3(12.0, -8.0, 4.4), Vector3(12.0, 4.8, 4.5), Vector3(12.0, 11.0, 3.0)]:
		_fence_panel(Vector2(panel.x, panel.y), panel.z, true, 1.65)
	_fence_panel(Vector2(-12.1, 9.5), 3.8, false, 1.65)
	_fence_panel(Vector2(15.6, -11.3), 3.6, false, 1.65)
	_planters(Vector2(-17.4, -1.3))
	_planters(Vector2(17.0, 2.1))
	_barrel(Vector3(-14.4, 0, 7.8), 0.6)
	_barrel(Vector3(11.7, 0, -3.8), 0.2)
	_crate(Vector3(17.4, 0, 8.7), 0.5)
	_crate(Vector3(-17.5, 0, -10.1), -0.4)
	var garden_trees: Array[Transform3D] = []
	for point: Vector2 in [Vector2(-17.7, -6.5), Vector2(17.1, 5.1), Vector2(16.9, -14.6)]:
		garden_trees.append(_map._plant_transform(point, _rng, 0.72, 0.86))
		_hidden_box(Vector3(point.x, 1.0, point.y), Vector3(0.4, 2.0, 0.4), "wood")
	_tree_batch(VILLAGE_TREE, garden_trees, true)
	if half >= 30.0:
		_landmark(_frame(Vector2(-9.1, -23.4), PI * 0.5), Vector2(5.6, 5.4), red, 3.2)
		_landmark(_frame(Vector2(9.1, 23.4), -PI * 0.5), Vector2(5.6, 5.4), cream, 3.2)
		_shed(_frame(Vector2(6.1, -20.2), -PI * 0.5))
		_shed(_frame(Vector2(-6.1, 20.2), PI * 0.5))
		_fence_panel(Vector2(-13.6, -21.7), 4.3, true, 1.65)
		_fence_panel(Vector2(13.6, 21.7), 4.3, true, 1.65)
	_add_supply(Vector2(-14.0, 10.4))
	_add_supply(Vector2(16.8, -12.5))


func _start_area(center: Vector2, is_gate: bool) -> void:
	var frame := _frame(center, PI if is_gate else 0.0)
	var size := Vector2(6.35, 5.8)
	var siding := _stone if is_gate else _fence
	_lot(frame, size + Vector2.ONE * 2.0)
	_lot(frame.translated_local(Vector3(0, 0, 5.45)), Vector2(9.3, 6.4))
	_floor(frame, size)
	_open_wall(frame, 2.9, size.x, 0.0, 3.5, 0.0, 4.24, 0.0, 2.85, siding)
	_piece(frame, Vector3(0, 1.75, -2.9), Vector3(size.x, 3.5, WALL), siding)
	_piece(frame, Vector3(3.175, 1.75, 0), Vector3(WALL, 3.5, size.y), siding)
	var side_wall := frame * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-3.175, 0, 0))
	_open_wall(side_wall, 0.0, size.y, 0.0, 3.5, -0.42, 2.18, 0.0, 2.43, siding)
	_door_frame(side_wall, Vector3(-0.42, 0, 0), 2.18, 2.43)
	_door_frame(frame, Vector3(0, 0, 2.9), 4.24, 2.85)
	_gable_roof(frame, size + Vector2.ONE * 0.86, 3.5, 1.16, size)
	_sign(frame, Vector3(0, 3.13, 3.06), "ВОРОТА" if is_gate else "АМБАР")
	var inside := frame * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 2.76))
	_sign(inside, Vector3(0, 3.12, 0), "РЫНОК")
	var toward_room := side_wall * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -0.15))
	_sign(toward_room, Vector3(0.42, 2.70, 0), "САДЫ")
	if is_gate:
		for index in 11:
			var angle := float(index) * PI / 10.0
			_paint(frame * Vector3(cos(angle) * 2.18, 2.37 + sin(angle) * 0.66, 3.05),
				Vector3(0.39, 0.28, 0.32), _stone, (angle - PI * 0.5) * 0.45, PI)
	_lantern(frame, Vector3(-2.54, 1.96, 2.98))
	_lantern(frame, Vector3(2.54, 1.96, 2.98))
	_crate(frame * Vector3(2.48, 0, 3.84), 0.3)
	_barrel(frame * Vector3(-2.55, 0, 5.65 if is_gate else 4.08), 1.1)
	# Screen the starts from the market while leaving routes around both ends.
	_piece(frame, Vector3(0.65, 1.20, 6.0), Vector3(5.10, 2.40, 0.32), siding)


func _build_spawns(barn: Vector2, gate: Vector2) -> void:
	for row in [0.65, -0.92]:
		for column in [-2.36, -1.18, 0.0, 1.18, 2.36]:
			_map._initial_spawns.append(Vector3(barn.x + column, 0.25, barn.y + row))
			_map._initial_spawns.append(Vector3(gate.x - column, 0.25, gate.y - row))


func _landmark(frame: Transform3D, size: Vector2, material: Material, height: float) -> void:
	_lot(frame, size + Vector2.ONE * 1.5)
	_floor(frame, size)
	var front := size.y * 0.5
	_open_wall(frame, front, size.x, 0.0, height, 0.0, 1.28, 0.0, 2.16, material)
	_house_door(frame, Vector3(0, 0, front), 1.28, 2.16, 1.0)
	_piece(frame, Vector3(0, height * 0.5, -front), Vector3(size.x, height, WALL), material)
	for side in [-1.0, 1.0]:
		var flank := frame * Transform3D(Basis(Vector3.UP, side * PI * 0.5),
			Vector3(side * size.x * 0.5, 0, 0))
		_open_wall(flank, 0.0, size.y, 0.0, height, 0.28, 1.42, 0.71, 2.57, material)
		_window(flank, Vector3(0.28, 0.71, 0), 1.42, 1.86)
	_gable_roof(frame, size + Vector2.ONE * 0.75, height, 0.93, size)
	_furnish_house(frame, size)
	_lantern(frame, Vector3(size.x * 0.21, 2.12, front + 0.22))


func _furnish_house(frame: Transform3D, size: Vector2) -> void:
	var back := -size.y * 0.5
	var table := Vector3(-size.x * 0.23, 0, back + 0.88)
	var yaw := frame.basis.get_euler().y
	_piece(frame, table + Vector3.UP * 0.77, Vector3(1.38, 0.13, 0.76), _trim)
	for x in [-0.57, 0.57]:
		for z in [-0.26, 0.26]:
			_paint(frame * (table + Vector3(x, 0.35, z)), Vector3(0.12, 0.70, 0.12), _fence, 0, yaw)
	_prop(_basket_model, frame * (table + Vector3(-0.30, 0.835, 0.01)), yaw + 0.31)
	_prop(_bucket_model, frame * (table + Vector3(0.34, 0.835, -0.04)), yaw, 0.55)
	_bench(frame, Vector3(size.x * 0.24, 0, back + 0.54))
	_crate(frame * Vector3(size.x * 0.31, 0, size.y * 0.26), yaw)
	_interior_light(frame, Vector3(size.x * 0.20, 2.0, back + 0.35))


func _shed(frame: Transform3D) -> void:
	var size := Vector2(3.5, 2.8)
	_lot(frame, size + Vector2.ONE)
	_piece(frame, Vector3(0, 1.08, -1.4), Vector3(3.5, 2.16, WALL), _fence)
	for side in [-1.0, 1.0]:
		_piece(frame, Vector3(side * 1.75, 1.08, 0), Vector3(WALL, 2.16, 2.8), _fence)
	_gable_roof(frame, size + Vector2.ONE * 0.5, 2.2, 0.49, size)
	_crate(frame * Vector3(-0.75, 0, -0.57), frame.basis.get_euler().y)
	_prop(_bucket_model, frame * Vector3(0.89, 0, -0.7), 0.3)


func _planters(center: Vector2) -> void:
	var dirt := _flat(Color(0.19, 0.13, 0.072), 0.97)
	var plants: Array[Transform3D] = []
	for z in [-1.2, 0.45, 2.1]:
		var at := Vector3(center.x, 0.16, center.y + z)
		_solid(at, Vector3(1.85, 0.32, 0.86), _trim)
		_paint(at + Vector3.UP * 0.166, Vector3(1.64, 0.028, 0.66), dirt)
		for x in [-0.57, 0.0, 0.57]:
			var point := Vector2(at.x + x, at.z)
			var plant: Transform3D = _map._plant_transform(point, _rng, 0.25, 0.40)
			plant.origin.y = 0.32
			plants.append(plant)
	_map._add_plants(_map.SHRUBS, plants, _rng)


func _open_wall(frame: Transform3D, z: float, width: float, base: float, height: float,
		open_x: float, opening: float, sill: float, head: float, material: Material, lintel_clearance := 0.0) -> void:
	var left := width * 0.5 + open_x - opening * 0.5
	var right := width - opening - left
	_piece(frame, Vector3((left - width) * 0.5, base + height * 0.5, z), Vector3(left, height, WALL), material)
	_piece(frame, Vector3((width - right) * 0.5, base + height * 0.5, z), Vector3(right, height, WALL), material)
	if sill > 0:
		_piece(frame, Vector3(open_x, base + sill * 0.5, z), Vector3(opening, sill, WALL), material, base < 0.1)
	var lintel_height := height - head - lintel_clearance
	_piece(frame, Vector3(open_x, base + head + lintel_height * 0.5, z),
		Vector3(opening, lintel_height, WALL), material, false)


func _floor(frame: Transform3D, size: Vector2) -> void:
	_paint(frame * Vector3(0, 0.018, 0), Vector3(size.x, 0.028, size.y), _trim, 0, frame.basis.get_euler().y)
	_map._wood_floors.append(_bounds(frame, size))


func _door_frame(frame: Transform3D, at: Vector3, width: float, height: float) -> void:
	var yaw := frame.basis.get_euler().y
	for side in [-1.0, 1.0]:
		_paint(frame * (at + Vector3(side * (width * 0.5 + 0.05), height * 0.5, 0)), Vector3(0.16, height, 0.38), _trim, 0, yaw)
	_paint(frame * (at + Vector3.UP * (height + 0.05)), Vector3(width + 0.34, 0.16, 0.40), _trim, 0, yaw)


func _house_door(frame: Transform3D, at: Vector3, width: float, height: float, outside: float) -> void:
	_door_frame(frame, at, width, height)
	var portal := frame.translated_local(at)
	if outside < 0.0:
		portal.basis *= Basis(Vector3.UP, PI)
	_fixtures.add_door(portal, width, height, _fence, _iron)


func _window(frame: Transform3D, at: Vector3, width: float, height: float) -> void:
	var yaw := frame.basis.get_euler().y
	_door_frame(frame, at, width, height)
	_paint(frame * at, Vector3(width + 0.32, 0.15, 0.43), _trim, 0, yaw)
	_fixtures.add_window(frame.translated_local(at), width, height)
	for side in [-1.0, 1.0]:
		var shutter := at + Vector3(side * (width * 0.5 + 0.29), height * 0.5, 0.10)
		_paint(frame * shutter, Vector3(0.44, height + 0.04, 0.11), _fence, 0, yaw)


func _gable_roof(frame: Transform3D, size: Vector2, eave: float, rise: float, walls: Vector2 = Vector2.ZERO) -> void:
	var run := size.x * 0.5
	var slope := atan2(rise, run)
	var yaw := frame.basis.get_euler().y
	for side in [-1.0, 1.0]:
		var center := Vector3(side * run * 0.5, eave + rise * 0.5, 0)
		var dimensions := Vector3(sqrt(run * run + rise * rise), 0.16, size.y)
		var roof_basis := frame.basis * Basis(Vector3.BACK, -side * slope)
		var roof: StaticBody3D = _map._add_box(frame * center, dimensions, _roof, rad_to_deg(yaw), "concrete", null, Node3D.new())
		roof.basis = roof_basis
		_paint(frame * center, dimensions, _roof, -side * slope, yaw)
		_paint(frame * Vector3(side * run, eave - 0.02, 0), Vector3(0.14, 0.18, size.y + 0.04), _trim, 0, yaw)
	_paint(frame * Vector3(0, eave + rise + 0.09, 0), Vector3(0.23, 0.18, size.y + 0.1), _roof, 0, yaw)
	if walls == Vector2.ZERO:
		return
	var span := walls.x * 0.5 + WALL * 0.5
	var shoulder := eave + rise * (1.0 - span / run)
	for side in [-1.0, 1.0]:
		var z: float = side * walls.y * 0.5
		var points := [
			Vector3(-span, eave - 0.18, z), Vector3(-span, shoulder, z),
			Vector3(0, eave + rise, z), Vector3(span, shoulder, z),
			Vector3(span, eave - 0.18, z),
		]
		if side < 0.0:
			points.reverse()
		var mesh := SurfaceTool.new()
		mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in range(1, points.size() - 1):
			for point: Vector3 in [points[0], points[index], points[index + 1]]:
				mesh.set_normal(frame.basis.z * side)
				mesh.set_uv(Vector2(point.x, point.y))
				mesh.add_vertex(frame * point)
		mesh.generate_tangents()
		mesh.index()
		_batch(_gable).append_from(mesh.commit(), 0, Transform3D.IDENTITY)
		var gable := StaticBody3D.new()
		gable.set_meta(&"impact_surface", "wood")
		var collider := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		var hull := PackedVector3Array()
		for point: Vector3 in points:
			hull.append(frame * (point + Vector3.BACK * 0.10))
			hull.append(frame * (point - Vector3.BACK * 0.10))
		shape.points = hull
		collider.shape = shape
		gable.add_child(collider)
		_map.add_child(gable)
	for side in [-1.0, 1.0]:
		var x: float = side * walls.x * 0.5
		var height := rise * (1.0 - absf(x) / run)
		_piece(frame, Vector3(x, eave + height * 0.5 - 0.07, 0),
			Vector3(WALL + 0.045, height + 0.16, walls.y), _gable, false)


func _stairs(frame: Transform3D, foot: Vector3, top: Vector3, width: float) -> void:
	var slope := top - foot
	var direction := Vector3(slope.x, 0, slope.z).normalized()
	var side := direction.cross(Vector3.UP)
	var yaw := atan2(direction.x, direction.z) + frame.basis.get_euler().y
	var length := Vector2(slope.x, slope.z).length()
	var steps := 16
	for index in steps:
		var point := foot + direction * ((float(index) + 0.5) * length / steps)
		point.y = (float(index) + 1.0) * slope.y / steps - 0.09
		_paint(frame * point, Vector3(width, 0.18, length / steps + 0.026), _trim, 0, yaw)
	for offset in [-1.0, 1.0]:
		for fraction in [0.03, 0.38, 0.70, 0.96]:
			var point: Vector3 = foot.lerp(top, fraction) + side * (offset * width * 0.5)
			_paint(frame * (point + Vector3.UP * 0.38), Vector3(0.10, 0.84, 0.10), _trim)
		var rail: Vector3 = foot.lerp(top, 0.5) + side * (offset * width * 0.5) + Vector3.UP * 0.78
		var transform := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -atan2(slope.y, length)), frame * rail)
		_box_batch(transform, Vector3(0.10, 0.11, slope.length()), _trim)
	var incline := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -atan2(slope.y, length))
	var center := frame * foot.lerp(top, 0.5) - incline.y * 0.09
	var ramp := _hidden_box(center, Vector3(width, 0.18, slope.length() + 0.42), "wood", yaw, false)
	ramp.basis = incline


func _fence_panel(center: Vector2, length: float, vertical: bool, height: float) -> void:
	var size := Vector3(0.23, height, length) if vertical else Vector3(length, height, 0.23)
	_map._add_wood_cover(Vector3(center.x, height * 0.5, center.y), size, _fence, 0.68)
	_map._occupied.append(Rect2(center - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)))
	var posts := maxi(1, ceili(length / 2.3))
	for index in posts + 1:
		var along := lerpf(-length * 0.5, length * 0.5, float(index) / posts)
		var point := center + (Vector2.DOWN if vertical else Vector2.RIGHT) * along
		_paint(Vector3(point.x, height * 0.53, point.y), Vector3(0.35, height * 1.06, 0.35), _trim)
	for fraction in [0.22, 0.8]:
		_paint(Vector3(center.x, height * fraction, center.y), size + Vector3(0.13, 0.12 - height, 0.13), _trim)


func _bench(frame: Transform3D, at: Vector3) -> void:
	_piece(frame, at + Vector3.UP * 0.43, Vector3(1.45, 0.12, 0.46), _trim)
	var yaw := frame.basis.get_euler().y
	for side in [-1.0, 1.0]:
		_paint(frame * (at + Vector3(side * 0.57, 0.22, 0)), Vector3(0.11, 0.44, 0.38), _trim, 0, yaw)
	_paint(frame * (at + Vector3(0, 0.69, -0.19)), Vector3(1.45, 0.22, 0.10), _fence, 0, yaw)


func _sign(frame: Transform3D, at: Vector3, wording: String) -> void:
	var yaw := frame.basis.get_euler().y
	var width := 2.74 if wording.length() > 7 else 1.46
	_paint(frame * at, Vector3(width, 0.42, 0.12), _trim, 0, yaw)
	_paint(frame * (at + Vector3.BACK * 0.063), Vector3(width - 0.14, 0.31, 0.025), _dark, 0, yaw)
	var label := Label3D.new()
	label.text = wording
	label.font_size = 44
	label.pixel_size = 0.0036
	label.modulate = Color(0.93, 0.81, 0.58)
	label.outline_size = 0
	label.transform = frame.translated_local(at + Vector3.BACK * 0.083)
	_map.add_child(label)


func _lantern(frame: Transform3D, at: Vector3) -> void:
	var yaw := frame.basis.get_euler().y
	_paint(frame * at, Vector3(0.16, 0.27, 0.16), _amber, 0, yaw)
	for height in [-0.15, 0.15]:
		_paint(frame * (at + Vector3.UP * height), Vector3(0.23, 0.052, 0.23), _iron, 0, yaw)
	for x in [-0.081, 0.081]:
		for z in [-0.081, 0.081]:
			_paint(frame * (at + Vector3(x, 0, z)), Vector3(0.024, 0.29, 0.024), _iron, 0, yaw)
	_paint(frame * (at + Vector3(0, 0.20, -0.13)), Vector3(0.08, 0.05, 0.29), _iron, 0, yaw)


func _interior_light(frame: Transform3D, at: Vector3) -> void:
	_lantern(frame, at)
	var light := OmniLight3D.new()
	light.position = frame * at
	light.light_color = Color(1.0, 0.69, 0.39)
	light.light_energy = 1.25
	light.omni_range = 3.5
	_map.add_child(light)


func _barrel(at: Vector3, yaw: float) -> void:
	_prop(_barrel_model, at, yaw, 1.22)
	_hidden_box(at + Vector3.UP * 0.53, Vector3(0.90, 1.06, 0.90), "wood", yaw)


func _crate(at: Vector3, yaw: float) -> void:
	_prop(_crate_model, at, yaw, 1.25)
	_hidden_box(at + Vector3.UP * 0.21, Vector3(1.03, 0.42, 0.51), "wood", yaw)


func _prop(scene: PackedScene, at: Vector3, yaw: float, scale_factor: float = 1.0) -> void:
	var model := scene.instantiate() as Node3D
	model.position = at
	model.rotation.y = yaw
	model.scale = Vector3.ONE * scale_factor
	_map.add_child(model)


func _hidden_box(at: Vector3, size: Vector3, surface: String, yaw: float = 0.0, obstacle: bool = true) -> StaticBody3D:
	var body: StaticBody3D = _map._add_box(at, size, null, rad_to_deg(yaw), surface, null, Node3D.new())
	if obstacle:
		_map._occupied.append(_bounds(body.transform, Vector2(size.x, size.z)))
	return body


func _piece(frame: Transform3D, at: Vector3, size: Vector3, material: Material, obstacle: bool = true) -> void:
	_solid(frame * at, size, material, obstacle, frame.basis.get_euler().y)


func _frame(center: Vector2, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, 0, center.y))


func _ground_point(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)


func _bounds(frame: Transform3D, size: Vector2) -> Rect2:
	var half := size * 0.5
	var area := Rect2(_ground_point(frame * Vector3(-half.x, 0, -half.y)), Vector2.ZERO)
	for corner in [Vector3(half.x, 0, -half.y), Vector3(-half.x, 0, half.y), Vector3(half.x, 0, half.y)]:
		area = area.expand(_ground_point(frame * corner))
	return area


func _lot(frame: Transform3D, size: Vector2) -> void:
	var bounds := _bounds(frame, size)
	_lots.append(bounds)
	_terrain_pads.append(bounds)


func _flat(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _cylinder(at: Vector3, radius: float, height: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	_mesh(mesh, material, Transform3D(Basis.IDENTITY, at))


func _mesh(mesh: Mesh, material: Material, transform: Transform3D) -> void:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.transform = transform
	_map.add_child(visual)


func _add_supply(point: Vector2) -> void:
	_supplies.append(Transform3D(Basis(Vector3.UP, _rng.randf_range(0, TAU)), Vector3(point.x, 0, point.y)))
	_map._occupied.append(Rect2(point - Vector2.ONE * 0.8, Vector2.ONE * 1.6))


func _plant_forest(half: float) -> void:
	var canopy := _pine_mesh()
	var bark: Material = _map._world_mat("planks", Color(0.39, 0.31, 0.24), 0.0, 0.9, 0.8, true)
	var groups: Array[Array] = [[], [], [], []]
	var shrubs: Array[Transform3D] = []
	var grass: Array[Transform3D] = []
	for x in range(-8, 9):
		for z in range(-8, 9):
			var point := Vector2(x, z) * 2.22 + Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6))
			var patch := Rect2(point - Vector2.ONE * 0.28, Vector2.ONE * 0.56)
			if not _inside_lot(patch) and _map._is_clear(patch, half, 0.85) and _rng.randf() < 0.62:
				grass.append(_terrain_plant(point, 0.57, 1.15))
	var forest_steps := floori(half / 5.25)
	for x in range(-forest_steps, forest_steps + 1):
		for z in range(-forest_steps, forest_steps + 1):
			var point := Vector2(x, z) * 5.25 + Vector2(_rng.randf_range(-1.6, 1.6), _rng.randf_range(-1.6, 1.6))
			var outer := maxf(absf(point.x), absf(point.y)) > half * 0.65
			if maxf(absf(point.x), absf(point.y)) < 19.0 or absf(point.x) < 7.0:
				continue
			var trunk_area := Rect2(point - Vector2.ONE * 1.0, Vector2.ONE * 2.0)
			if not _map._is_clear(trunk_area, half, 1.6) or _inside_lot(trunk_area):
				continue
			var roll := _rng.randf()
			if roll < (0.37 if outer else 0.10):
				var scale_factor := _rng.randf_range(0.77, 1.45)
				var placement: Transform3D = _terrain_plant(point, scale_factor, scale_factor)
				var quadrant := int(point.x >= 0.0) + 2 * int(point.y >= 0.0)
				groups[quadrant].append(placement)
				var trunk_size := 0.47 * scale_factor
				_map._add_box(Vector3(point.x, ground_height(point) + 1.2 * scale_factor, point.y),
					Vector3(trunk_size, 2.4 * scale_factor, trunk_size), bark, 0.0, "wood", null, Node3D.new())
				_map._occupied.append(Rect2(point - Vector2.ONE * trunk_size * 0.5, Vector2.ONE * trunk_size))
			elif roll < 0.53:
				shrubs.append(_terrain_plant(point, 0.8, 1.45))
			elif roll < 0.72:
				grass.append(_terrain_plant(point, 0.8, 1.65))
	for group in groups:
		_tree_batch(VILLAGE_TREE, group, true)
	var backdrop: Array[Transform3D] = []
	var woodland: Array[Transform3D] = []
	for x in range(-17, 18):
		for z in range(-17, 18):
			var point := Vector2(x, z) * 7.0 + Vector2(_rng.randf_range(-2, 2), _rng.randf_range(-2, 2))
			if maxf(absf(point.x), absf(point.y)) > half + 3.0 and _rng.randf() < 0.50:
				var placement: Transform3D = _terrain_plant(point, 1.0, 2.3)
				if maxf(absf(point.x), absf(point.y)) < half + 27.0:
					woodland.append(placement)
				else:
					backdrop.append(placement)
					_paint(placement * Vector3.UP * 1.2, Vector3(0.47, 2.4, 0.47) * placement.basis.get_scale(), bark)
	_tree_batch(VILLAGE_TREE, woodland, false)
	_tree_batch(canopy, backdrop, false)
	_map._add_plants(_map.GRASS, grass, _rng)
	_map._add_plants(_map.SHRUBS, shrubs, _rng)


func _terrain_plant(point: Vector2, min_scale: float, max_scale: float) -> Transform3D:
	var placement: Transform3D = _map._plant_transform(point, _rng, min_scale, max_scale)
	placement.origin.y = ground_height(point)
	return placement


func _tree_batch(mesh: ArrayMesh, placements: Array, cast_shadow: bool) -> void:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = mesh
	batch.instance_count = placements.size()
	for index in placements.size():
		batch.set_instance_transform(index, placements[index])
		var tone := _rng.randf_range(0.76, 1.0)
		batch.set_instance_color(index, Color(tone, lerpf(tone, 1.0, 0.4), tone * 0.94))
	var trees := MultiMeshInstance3D.new()
	trees.multimesh = batch
	if not cast_shadow:
		trees.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_map.add_child(trees)


func _inside_lot(area: Rect2) -> bool:
	for lot in _lots:
		if lot.intersects(area):
			return true
	return false


func _pine_mesh() -> ArrayMesh:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var branch_rng := RandomNumberGenerator.new()
	branch_rng.seed = 812
	for layer in 7:
		var height := 2.45 + layer * 0.79
		var radius := 2.12 - layer * 0.29
		var tips := PackedVector3Array()
		for point in 14:
			var angle := point * TAU / 14.0 + layer * 0.61
			var reach := radius * branch_rng.randf_range(0.82, 1.16)
			if point % 2:
				reach *= 0.72
			tips.append(Vector3(cos(angle) * reach, height + branch_rng.randf_range(-0.34, 0.32), sin(angle) * reach))
		var peak := Vector3(0.1, height + 1.45 - layer * 0.075, 0)
		var underside := Vector3(0, height - 0.32, 0)
		for point in tips.size():
			builder.set_smooth_group(-1)
			var tint := branch_rng.randf_range(0.80, 1.0)
			builder.set_color(Color(0.16, 0.31, 0.22) * Color(tint, tint, tint))
			builder.add_vertex(tips[(point + 1) % tips.size()])
			builder.add_vertex(peak)
			builder.add_vertex(tips[point])
			builder.set_color(Color(0.085, 0.18, 0.125))
			builder.add_vertex(tips[point])
			builder.add_vertex(underside)
			builder.add_vertex(tips[(point + 1) % tips.size()])
	builder.generate_normals()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	builder.set_material(material)
	return builder.commit()


func _solid(center: Vector3, size: Vector3, material: Material, obstacle: bool = true, yaw: float = 0.0) -> void:
	var masonry: bool = material is StandardMaterial3D and material.albedo_texture == _stone.albedo_texture
	var surface := "concrete" if masonry else "wood"
	var body: StaticBody3D = _map._add_box(center, size, material, rad_to_deg(yaw), surface, _batch(material))
	if surface == "wood":
		body.set_meta(&"ballistic_size", size)
		body.set_meta(&"ballistic_resistance", 0.30)
	if obstacle:
		_map._occupied.append(_bounds(body.transform, Vector2(size.x, size.z)))


func _paint(center: Vector3, size: Vector3, material: Material, tilt: float = 0.0, yaw: float = 0.0) -> void:
	_box_batch(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, tilt), center), size, material)


func _box_batch(transform: Transform3D, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_batch(material).append_from(mesh, 0, transform)


func _batch(material: Material) -> SurfaceTool:
	if not _batches.has(material):
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[material] = builder
	return _batches[material]
