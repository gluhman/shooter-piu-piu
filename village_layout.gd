extends RefCounted

const GROUND_SHADER := preload("res://village_ground.gdshader")
const ROAD_HALF_WIDTH := 4.0
const WALL_HEIGHT := 3.4
const WALL_THICKNESS := 0.25
const WINDOW_WIDTH := 2.2
const WINDOW_SILL := 1.05

var _map: Node3D
var _rng: RandomNumberGenerator
var _batches: Dictionary[Material, SurfaceTool] = {}
var _lots: Array[Rect2] = []
var _supplies: Array[Transform3D] = []
var _trim: Material
var _fence: Material
var _roof: Material


func _init(map: Node3D) -> void:
	_map = map


func build(width: float, rng: RandomNumberGenerator) -> Array[Transform3D]:
	_rng = rng
	var half := width * 0.5
	var ground := ShaderMaterial.new()
	ground.shader = GROUND_SHADER
	ground.set_shader_parameter("detail_color", _map._tex("concrete", "color"))
	ground.set_shader_parameter("detail_normal", _map._tex("concrete", "normal"))
	var landscape := MeshInstance3D.new()
	var horizon := PlaneMesh.new()
	horizon.size = Vector2.ONE * 480.0
	landscape.mesh = horizon
	landscape.material_override = ground
	landscape.position.y = -0.06
	landscape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_map.add_child(landscape)
	var road: Material = _map._world_mat("concrete", Color(0.66, 0.55, 0.43), 0.0, 0.55, 0.45, false)
	_trim = _map._world_mat("planks", Color(0.83, 0.78, 0.66), 0.0, 0.8, 0.65, true)
	_fence = _map._world_mat("planks", Color(0.57, 0.43, 0.33), 0.0, 0.9, 0.8, true)
	_roof = _map._world_mat("corrugated", Color(0.40, 0.48, 0.49), 0.27, 0.55, 0.8, true)
	_map._add_box(Vector3(0, -0.25, 0), Vector3(width + 2, 0.5, width + 2), ground)
	_paint(Vector3(0, 0.011, 0), Vector3(ROAD_HALF_WIDTH * 2, 0.02, width), road)
	for side in [-1.0, 1.0]:
		var edge: float = side * (half + 0.2)
		var road_length := half - ROAD_HALF_WIDTH
		_paint(Vector3(side * (ROAD_HALF_WIDTH + road_length * 0.5), 0.011, 0),
			Vector3(road_length, 0.02, ROAD_HALF_WIDTH * 2), road)
		_solid(Vector3(0, 1.4, edge), Vector3(width + 0.8, 2.8, 0.4), _fence)
		_solid(Vector3(edge, 1.4, 0), Vector3(0.4, 2.8, width), _fence)
		for along in range(-75, 80, 5):
			_paint(Vector3(along, 1.47, edge), Vector3(0.32, 2.94, 0.6), _trim)
			_paint(Vector3(edge, 1.47, along), Vector3(0.6, 2.94, 0.32), _trim)

	var siding: Array[Material] = [
		_map._world_mat("planks", Color(0.58, 0.66, 0.56), 0.0, 0.82, 0.8, true),
		_map._world_mat("planks", Color(0.74, 0.51, 0.37), 0.0, 0.82, 0.8, true),
		_map._world_mat("planks", Color(0.53, 0.63, 0.71), 0.0, 0.82, 0.8, true),
	]
	var houses := [
		Vector2(-25, -24), Vector2(25, -24), Vector2(-25, 24), Vector2(25, 24),
		Vector2(-39, -13), Vector2(38, -39), Vector2(-37, 39), Vector2(39, 12),
	]
	for index in houses.size():
		var width_x := 8.0 if index % 2 == 0 else 10.0
		var center: Vector2 = houses[index]
		_house(center, Vector2(width_x, 8.0), siding[index % siding.size()])
		_driveway(center, road)
		if index < 4:
			_yard(houses[index])
	_add_supply(Vector2(-12, -11))
	_add_supply(Vector2(13, 11))
	_add_supply(Vector2(-13, 12))
	_add_supply(Vector2(11, -13))
	_plant_forest(half)
	for material in _batches:
		var visual := MeshInstance3D.new()
		visual.mesh = _batches[material].commit()
		visual.material_override = material
		_map.add_child(visual)
	return _supplies


func _driveway(house: Vector2, material: Material) -> void:
	var side := signf(house.y)
	var lane_z := house.y - side * 7.0
	var lane_length := absf(house.x) - ROAD_HALF_WIDTH + 1.4
	_lane(Vector2(signf(house.x) * (ROAD_HALF_WIDTH + lane_length * 0.5), lane_z),
		Vector2(lane_length, 2.8), material)
	_lane(Vector2(house.x, house.y - side * 5.0), Vector2(2.8, 2.1), material)


func _lane(center: Vector2, size: Vector2, material: Material) -> void:
	_paint(Vector3(center.x, 0.009, center.y), Vector3(size.x, 0.014, size.y), material)
	_lots.append(Rect2(center - size * 0.5, size).grow(0.45))


func _house(center: Vector2, size: Vector2, siding: Material) -> void:
	var floor_area := Rect2(center - size * 0.5, size)
	_lots.append(floor_area.grow(1.8))
	_map._wood_floors.append(floor_area)
	var x := center.x
	var z := center.y
	var half_width := size.x * 0.5
	var half_depth := size.y * 0.5
	var door_width := 2.8
	var door_height := 2.45
	var panel_width := (size.x - door_width) * 0.5
	var gable_rise := 1.7
	_paint(Vector3(x, 0.022, z), Vector3(size.x, 0.04, size.y), _trim)
	for side in [-1.0, 1.0]:
		var front: float = z + side * half_depth
		_solid(Vector3(x - (door_width + panel_width) * 0.5, WALL_HEIGHT * 0.5, front),
			Vector3(panel_width, WALL_HEIGHT, WALL_THICKNESS), siding)
		_solid(Vector3(x + (door_width + panel_width) * 0.5, WALL_HEIGHT * 0.5, front),
			Vector3(panel_width, WALL_HEIGHT, WALL_THICKNESS), siding)
		_solid(Vector3(x, (WALL_HEIGHT + door_height) * 0.5, front),
			Vector3(door_width, WALL_HEIGHT - door_height, WALL_THICKNESS), _trim, false)
		_gable(x, front, half_width, gable_rise, siding, side)
		var flank: float = x + side * half_width
		var end_width := half_depth - WINDOW_WIDTH * 0.5
		var window_top := 2.45
		for end in [-1.0, 1.0]:
			_solid(Vector3(flank, WALL_HEIGHT * 0.5, z + end * (WINDOW_WIDTH + end_width) * 0.5),
				Vector3(WALL_THICKNESS, WALL_HEIGHT, end_width), siding)
		_solid(Vector3(flank, WINDOW_SILL * 0.5, z),
			Vector3(WALL_THICKNESS, WINDOW_SILL, WINDOW_WIDTH), siding)
		_solid(Vector3(flank, (WALL_HEIGHT + window_top) * 0.5, z),
			Vector3(WALL_THICKNESS, WALL_HEIGHT - window_top, WINDOW_WIDTH), siding, false)
		_paint(Vector3(flank, WINDOW_SILL, z), Vector3(0.42, 0.12, WINDOW_WIDTH + 0.24), _trim)

		var roof_run := half_width + 0.55
		var slope := atan2(gable_rise, half_width)
		var roof_center := Vector3(x + side * roof_run * 0.5,
			WALL_HEIGHT + gable_rise - tan(slope) * roof_run * 0.5 + 0.11, z)
		_paint(roof_center, Vector3(roof_run / cos(slope), 0.18, size.y + 1.2), _roof, -side * slope)
	_solid(Vector3(x, WALL_HEIGHT, z), Vector3(size.x, 0.18, size.y), siding, false)
	_add_supply(center + Vector2(-half_width + 1.1, -1.8))


func _gable(x: float, z: float, half_width: float, rise: float, material: Material, side: float) -> void:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var left := Vector3(x - half_width, WALL_HEIGHT, z)
	var right := Vector3(x + half_width, WALL_HEIGHT, z)
	var peak := Vector3(x, WALL_HEIGHT + rise, z)
	builder.set_normal(Vector3(0, 0, side))
	builder.set_uv(Vector2.ZERO)
	builder.add_vertex(left if side > 0.0 else right)
	builder.set_uv(Vector2(0.5, 1))
	builder.add_vertex(peak)
	builder.set_uv(Vector2.RIGHT)
	builder.add_vertex(right if side > 0.0 else left)
	builder.generate_tangents()
	builder.index()
	_batch(material).append_from(builder.commit(), 0, Transform3D.IDENTITY)


func _yard(center: Vector2) -> void:
	var side := signf(center.y)
	var outer_z := center.y + side * 10.5
	for end in [-1.0, 1.0]:
		_fence_panel(Vector2(center.x + end * 5.25, outer_z), 6.0, false)
		_fence_panel(Vector2(center.x + end * 8.25, center.y + side * 7.2), 6.6, true)
	_add_supply(center + Vector2(5.7, side * 8.6))


func _fence_panel(center: Vector2, length: float, vertical: bool) -> void:
	var size := Vector3(0.24, 1.65, length) if vertical else Vector3(length, 1.65, 0.24)
	_solid(Vector3(center.x, 0.825, center.y), size, _fence)
	for distance in [-length * 0.5, 0.0, length * 0.5]:
		var post: Vector2 = center + (Vector2.DOWN if vertical else Vector2.RIGHT) * distance
		_paint(Vector3(post.x, 0.92, post.y), Vector3(0.38, 1.84, 0.38), _trim)
	for height in [0.33, 1.39]:
		_paint(Vector3(center.x, height, center.y), size + Vector3(0.12, -1.53, 0.12), _trim)


func _add_supply(point: Vector2) -> void:
	_supplies.append(Transform3D(Basis(Vector3.UP, _rng.randf_range(0, TAU)), Vector3(point.x, 0, point.y)))
	_map._occupied.append(Rect2(point - Vector2.ONE * 0.8, Vector2.ONE * 1.6))


func _plant_forest(half: float) -> void:
	var canopy := _pine_mesh()
	var bark: Material = _map._world_mat("planks", Color(0.39, 0.31, 0.24), 0.0, 0.9, 0.8, true)
	var groups: Array[Array] = [[], [], [], []]
	var shrubs: Array[Transform3D] = []
	var grass: Array[Transform3D] = []
	for x in range(-14, 15):
		for z in range(-14, 15):
			var point := Vector2(x, z) * 5.25 + Vector2(_rng.randf_range(-1.6, 1.6), _rng.randf_range(-1.6, 1.6))
			var outer := maxf(absf(point.x), absf(point.y)) > 46.0
			if minf(absf(point.x), absf(point.y)) < ROAD_HALF_WIDTH + 2.0:
				continue
			var trunk_area := Rect2(point - Vector2.ONE * 1.0, Vector2.ONE * 2.0)
			if not _map._is_clear(trunk_area, half, 1.6) or _inside_lot(trunk_area):
				continue
			var roll := _rng.randf()
			if roll < (0.37 if outer else 0.10):
				var scale_factor := _rng.randf_range(0.77, 1.45)
				var placement: Transform3D = _map._plant_transform(point, _rng, scale_factor, scale_factor)
				var quadrant := int(point.x >= 0.0) + 2 * int(point.y >= 0.0)
				groups[quadrant].append(placement)
				var trunk_size := 0.47 * scale_factor
				_solid(Vector3(point.x, 1.2 * scale_factor, point.y),
					Vector3(trunk_size, 2.4 * scale_factor, trunk_size), bark)
			elif roll < 0.53:
				shrubs.append(_map._plant_transform(point, _rng, 0.8, 1.45))
			elif roll < 0.72:
				grass.append(_map._plant_transform(point, _rng, 0.8, 1.65))
	for group in groups:
		_tree_batch(canopy, group, true)
	var backdrop: Array[Transform3D] = []
	for x in range(-17, 18):
		for z in range(-17, 18):
			var point := Vector2(x, z) * 7.0 + Vector2(_rng.randf_range(-2, 2), _rng.randf_range(-2, 2))
			if maxf(absf(point.x), absf(point.y)) > half + 3.0 and _rng.randf() < 0.50:
				var placement: Transform3D = _map._plant_transform(point, _rng, 1.0, 2.3)
				backdrop.append(placement)
				_paint(placement * Vector3.UP * 1.2, Vector3(0.47, 2.4, 0.47) * placement.basis.get_scale(), bark)
	_tree_batch(canopy, backdrop, false)
	_map._add_plants(_map.GRASS, grass, _rng)
	_map._add_plants(_map.SHRUBS, shrubs, _rng)


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


func _solid(center: Vector3, size: Vector3, material: Material, obstacle: bool = true) -> void:
	_map._add_box(center, size, material, 0.0, "wood", _batch(material))
	if obstacle:
		var footprint := Vector2(size.x, size.z)
		_map._occupied.append(Rect2(Vector2(center.x, center.z) - footprint * 0.5, footprint))


func _paint(center: Vector3, size: Vector3, material: Material, tilt: float = 0.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_batch(material).append_from(mesh, 0, Transform3D(Basis(Vector3.BACK, tilt), center))


func _batch(material: Material) -> SurfaceTool:
	if not _batches.has(material):
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[material] = builder
	return _batches[material]
