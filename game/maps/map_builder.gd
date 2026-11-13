extends Node3D

const BULLET_HOLE_SHADER := preload("res://game/combat/bullet_holes.gdshader")
const STACK_CONTAINER_SCENE := "res://assets/arena_props/oxygen/stacked_containers.glb"
const HOLES_PER_PANEL := 32

class PerforatedCover:
	var body: StaticBody3D
	var points := PackedVector4Array()
	var axes := PackedVector3Array()
	var materials: Array[ShaderMaterial] = []
	var moving_surface: MeshInstance3D
	var original_material: Material

const GRASS := preload("res://assets/arena_props/grass.glb")
const SHRUBS := preload("res://assets/arena_props/shrubs.glb")
const VILLAGE := preload("res://game/maps/procedural/village_layout.gd")
const DUST2 := preload("res://game/maps/procedural/dust2_layout.gd")
const ROUTE_MARKING := preload("res://game/maps/procedural/route_marking.gd")
const YARD_GROUND := preload("res://game/maps/procedural/yard_ground.gdshader")
const ROAD_BARRIER := "res://game/maps/breakwater/art/models/concrete_road_barrier.glb"
const OFFICE := preload("res://game/maps/procedural/office_layout.gd")
const WORKSHOP := preload("res://game/maps/procedural/workshop_layout.gd")
const KENNEY_OUTPOST := preload("res://game/maps/procedural/kenney_outpost_layout.gd")

const CONTAINER_HEIGHT := 2.59
const CONTAINER_WIDTH := 2.44
const LENGTH_20 := 6.06
const LENGTH_40 := 12.19

const PANEL_THICKNESS := 0.12
const CRATE_SIGHT_RADIUS := 15.0
const MAX_SUPPLY_CRATES := 12
const ARENA_WIDTH := 70.0
const SIZE_WIDTHS := [20.0, 40.0, ARENA_WIDTH]
const SIZE_NAMES := ["Маленькая", "Средняя", "Большая"]
const DEFAULT_SIZE := 2
const VILLAGE_ID := 3
const VILLAGE_MIN_SIZE := 1
const DUST2_ID := 4
const WORKSHOP_ID := 5
const BREAKWATER_ID := 6
const TEST_RANGE_ID := 7
const OFFICE_ID := 8
const OUTPOST_ID := 9
const STATION_ID := 10
const OFFICE_BOUNDS := Rect2(-OFFICE.HALF_X, -OFFICE.HALF_Z, OFFICE.HALF_X * 2.0, OFFICE.HALF_Z * 2.0)

class Cover:
	var center: Vector2
	var half_size: Vector2
	var yaw: float

const COLOR_RED := Color(0.92, 0.24, 0.18)
const COLOR_BLUE := Color(0.28, 0.48, 0.82)
const COLOR_GREEN := Color(0.28, 0.52, 0.34)
const COLOR_ORANGE := Color(0.95, 0.48, 0.14)
const COLOR_GREY := Color(0.72, 0.74, 0.72)

const MAP_NAMES := ["Контейнерный двор", "Складские ряды", "Перекрёсток", "Лесной посёлок", "Dust II", "Цех № 3", "BREAKWATER 9", "Тренировочный полигон", "Малый офис", "Форпост", "Станция"]

const PATROL_ROUTES := [
	[
		Vector3(30, 0.2, 0), Vector3(0, 0.2, 0), Vector3(0, 0.2, 30),
		Vector3(-32, 0.2, 32), Vector3(-32, 0.2, -32), Vector3(32, 0.2, -32),
	],
	[
		Vector3(32, 0.2, -32), Vector3(-32, 0.2, -32), Vector3(-32, 0.2, 0),
		Vector3(32, 0.2, 0), Vector3(32, 0.2, 32), Vector3(-32, 0.2, 32),
		Vector3(-32, 0.2, 0), Vector3(0, 0.2, 0), Vector3(0, 0.2, -32),
	],
	[
		Vector3(32, 0.2, 32), Vector3(32, 0.2, -32), Vector3(0, 0.2, -32),
		Vector3(0, 0.2, 32), Vector3(-32, 0.2, 32), Vector3(-32, 0.2, -32),
		Vector3(0, 0.2, -32), Vector3(0, 0.2, 0),
	],
]

var _perforated: Array[PerforatedCover] = []
var _stack_meshes: Dictionary[String, Mesh] = {}
var _container_fittings: SurfaceTool
var _occupied: Array[Rect2] = []
var _cover: Array[Cover] = []
var _passages: Array[Transform3D] = []
var _wood_floors: Array[Rect2] = []
var _initial_spawns := PackedVector3Array()
var respawn_points := PackedVector3Array()
var market_supply_count := 0
var _patrol: Array[Vector3] = []
var _half_extent := 35.0
var _district_origin := Vector3.ZERO
var _district_yaw := 0.0
var _wall_mat: StandardMaterial3D
var _wood_mat: StandardMaterial3D
const BASE_TEXTURE_KINDS := ["color", "normal", "roughness"]
const TEXTURE_EXTRA_KINDS := {
	"bricks": ["ao"],
	"planks": ["ao"],
	"corrugated": ["ao", "metalness"],
	"village/cobble": ["ao"],
	"village/plaster": ["ao"],
	"village/roof": ["ao"],
}
const YARD_MATERIALS := ["bricks", "planks", "corrugated"]
const MAP_MATERIALS := {
	DUST2_ID: ["dust2/sandstone", "dust2/sand", "concrete", "planks"],
	VILLAGE_ID: ["planks", "village/cobble", "village/dirt", "village/plaster", "village/roof"],
	OFFICE_ID: ["concrete", "planks", "office/carpet", "brushed", "rubber"],
	WORKSHOP_ID: ["bricks", "corrugated"],
	BREAKWATER_ID: [],
	OUTPOST_ID: [],
	STATION_ID: [],
}

var _textures: Dictionary[String, Texture2D] = {}


func patrol_route() -> Array[Vector3]:
	return _patrol


func preload_textures(map_id: int) -> void:
	var paths := PackedStringArray()
	for material: String in MAP_MATERIALS.get(map_id, YARD_MATERIALS):
		for kind: String in BASE_TEXTURE_KINDS + TEXTURE_EXTRA_KINDS.get(material, []):
			paths.append(_texture_path(material, kind))
	for path in _textures.keys():
		if not paths.has(path):
			_textures.erase(path)
	var pending: Array[String] = []
	for path in paths:
		if not _textures.has(path) and ResourceLoader.load_threaded_request(path, "Texture2D") == OK:
			pending.append(path)
	while not pending.is_empty():
		for index in range(pending.size() - 1, -1, -1):
			var path := pending[index]
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				continue
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				_textures[path] = ResourceLoader.load_threaded_get(path) as Texture2D
			pending.remove_at(index)
		if not pending.is_empty():
			await get_tree().process_frame


func _load_textures() -> void:
	_wall_mat = _world_mat("bricks", Color(0.92, 0.9, 0.88), 0.0, 0.42, 1.0, true)
	_wood_mat = _world_mat("planks", Color(0.9, 0.84, 0.74), 0.0, 0.7, 1.0, true)


func build(map_id: int, layout_seed: int, width: float) -> Array[Transform3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	_half_extent = width * 0.5
	if map_id == OUTPOST_ID or map_id == STATION_ID:
		return KENNEY_OUTPOST.new(self).build(width, map_id == STATION_ID)
	if map_id == OFFICE_ID:
		return OFFICE.new(self).build()
	if map_id == WORKSHOP_ID:
		return WORKSHOP.new(self).build(width)
	if map_id == DUST2_ID:
		var dust2 := DUST2.new(self)
		var supplies := dust2.build(width)
		_patrol = dust2.patrol_route()
		return supplies
	if map_id == TEST_RANGE_ID:
		return _build_test_range(width)
	if map_id == VILLAGE_ID:
		var village_width := maxf(width, SIZE_WIDTHS[VILLAGE_MIN_SIZE])
		_half_extent = village_width * 0.5
		var layout := VILLAGE.new(self)
		var supplies := layout.build(village_width, rng)
		market_supply_count = layout.market_supply_count
		_build_respawn_grid(floori((_half_extent - 1.0) / 5.6), 5.6, _half_extent, layout.ground_height)
		_patrol.assign(respawn_points)
		# Keep respawn candidates out of the contested market.
		var outer_candidates := PackedVector3Array()
		for point in respawn_points:
			if absf(point.x) >= 6.0 or absf(point.z) >= 6.0:
				outer_candidates.append(point)
		respawn_points = outer_candidates
		return supplies

	_build_spawn_ring(_half_extent - (2.25 if width == 70.0 else 1.35))
	var spacing := 2.8 if width == 20.0 else 5.6
	var steps := floori((_half_extent - 1.0) / spacing)

	_load_textures()
	_add_box(Vector3(0.0, -0.25, 0.0), Vector3(width + 2.0, 0.5, width + 2.0), _yard_ground(map_id))
	for side in [-1.0, 1.0]:
		var edge: float = side * (_half_extent + 0.25)
		_add_box(Vector3(0.0, 2.75, edge), Vector3(width + 1.0, 5.5, 0.5), _wall_mat, 0.0, "brick")
		_add_box(Vector3(edge, 2.75, 0.0), Vector3(0.5, 5.5, width), _wall_mat, 0.0, "brick")

	_container_fittings = SurfaceTool.new()
	_container_fittings.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fittings := _world_mat("corrugated", Color("#5f6059"), 0.52, 1.0, 0.55, true)
	_container_fittings.set_material(fittings)
	if width == 20.0:
		_build_small_yard(map_id)
	else:
		for district in (4 if width == 70.0 else 1):
			_district_origin = Vector3(17.25, 0, 17.25).rotated(Vector3.UP, district * PI * 0.5) if width == 70.0 else Vector3.ZERO
			_district_yaw = float(district * 90)
			match map_id:
				1: _build_storage()
				2: _build_crossroads()
				_: _build_container_yard()
	_build_yard_routes(map_id, width)
	if width > 20.0:
		_scatter_passages(rng)
	var details := MeshInstance3D.new()
	details.name = "ContainerHardware"
	details.mesh = _container_fittings.commit()
	add_child(details)
	_container_fittings = null
	var crates := _scatter_crates(rng)
	_build_respawn_grid(steps, spacing, _half_extent)
	_scatter_foliage(rng)
	if width == 70.0:
		_patrol.assign(PATROL_ROUTES[map_id])
	else:
		_patrol.assign(respawn_points)
	return crates


func _yard_ground(map_id: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = YARD_GROUND
	var asphalt := map_id == 2 or map_id == TEST_RANGE_ID
	var asset := "asphalt_01" if asphalt else "concrete_floor_worn_001"
	for kind in ["color", "normal", "orm"]:
		var path := "res://game/maps/breakwater/art/materials/%s_%s.jpg" % [asset, kind]
		material.set_shader_parameter("surface_" + kind, load(path))
	material.set_shader_parameter("joint_strength", 0.0 if asphalt else 0.85)
	material.set_shader_parameter("tint", Color("#dce6eb") if map_id == 1 else Color("#e3d9cc"))
	return material


func _build_yard_routes(map_id: int, width: float) -> void:
	var candidates: Array
	var title: String
	var color: Color
	var yaw: float
	match map_id:
		1:
			# Offset barriers give the long aisles a midpoint crossover.
			candidates = [Vector2(-2.25, -4.7), Vector2(2.25, 3.65)] if width == 20.0 else [
				Vector2(-4.35, -1.3), Vector2(4.35, 1.3), Vector2(-5.1, 1.0), Vector2(5.1, -1.0)]
			title = "AISLE TRANSFER"
			color = Color("#9ac8db")
			yaw = 75.0
		2:
			# Keep the center of the junction open and screen its diagonal approaches.
			candidates = [Vector2(-3.4, 1.55), Vector2(3.4, -1.55)] if width == 20.0 else [
				Vector2(-3.1, 3.0), Vector2(3.1, -3.0), Vector2(-3.5, -2.0), Vector2(3.5, 2.0)]
			title = "CROSSING"
			color = Color("#d8c789")
			yaw = 45.0
		_:
			candidates = [Vector2(0.0, -1.9), Vector2(3.05, 6.0)] if width == 20.0 else [
				Vector2(4.4, 1.6), Vector2(-4.25, -5.2), Vector2(8.0, -6.2), Vector2(-9.0, 1.6)]
			title = "RECEIVING"
			color = Color("#e4a970")
			yaw = 0.0
	var placed := 0
	var length := 1.65 if width == 20.0 else 2.3
	var angle := deg_to_rad(yaw)
	var footprint := Vector2(length * absf(cos(angle)) + 0.78 * absf(sin(angle)),
		length * absf(sin(angle)) + 0.78 * absf(cos(angle)))
	for candidate: Vector2 in candidates:
		var point := candidate * (1.9 if width == 70.0 else 1.0)
		var area := _footprint(point, footprint)
		if not _is_clear(area.grow(0.30), _half_extent, 1.20):
			continue
		_road_barrier(Vector3(point.x, 0, point.y), yaw, length)
		_occupied.append(area.grow(0.20))
		var direction := -1.0 if point.y < 0.0 else 1.0
		var route := Vector3(point.x, 0.008, point.y + direction * (footprint.y * 0.5 + 0.5))
		ROUTE_MARKING.paint(self, title, route, color, PI if direction < 0.0 else 0.0, length + 0.1)
		placed += 1
		if placed == 2:
			break


func _road_barrier(at: Vector3, yaw: float, width: float) -> void:
	var scene := load(ROAD_BARRIER) as PackedScene
	var model := scene.instantiate() as Node3D
	# The imported barrier is centered at the origin, including its root translation.
	var size := Vector3(width, 0.96, 0.78)
	var bounds := AABB(Vector3(-0.7722, -0.4168, -0.3179), Vector3(1.5445, 0.8336, 0.6358))
	model.scale = size / bounds.size
	model.position = -bounds.get_center() * model.scale
	_add_box(at + Vector3.UP * size.y * 0.5, size, null, yaw, "concrete", null, model)


func _build_test_range(width: float) -> Array[Transform3D]:
	_load_textures()
	_add_box(Vector3(0.0, -0.25, 0.0), Vector3(width + 2.0, 0.5, width + 2.0), _yard_ground(TEST_RANGE_ID))
	for side in [-1.0, 1.0]:
		_add_box(Vector3(side * (_half_extent + 0.25), 2.75, 0.0), Vector3(0.5, 5.5, width), _wall_mat, 0.0, "brick")
	_add_box(Vector3(0.0, 2.75, -_half_extent - 0.25), Vector3(width + 1.0, 5.5, 0.5), _wall_mat, 0.0, "brick")
	_add_box(Vector3(0.0, 2.75, _half_extent + 0.25), Vector3(width + 1.0, 5.5, 0.5), _wall_mat, 0.0, "brick")
	var target_mat := _world_mat("planks", Color(0.95, 0.48, 0.14), 0.0, 0.7, 1.0, true)
	var steel_mat := _container_mat(Color(0.22, 0.32, 0.46))
	var spawn_positions := [
		Vector3(0.0, 0.2, 29.0), Vector3(-25.0, 0.2, 25.0), Vector3(25.0, 0.2, 25.0),
		Vector3(-25.0, 0.2, -25.0), Vector3(25.0, 0.2, -25.0), Vector3(-16.0, 0.2, 29.0),
		Vector3(16.0, 0.2, 29.0), Vector3(-29.0, 0.2, 8.0), Vector3(29.0, 0.2, 8.0),
		Vector3(-29.0, 0.2, -10.0), Vector3(29.0, 0.2, -10.0),
	]
	for spawn: Vector3 in spawn_positions:
		_initial_spawns.append(spawn)
		respawn_points.append(spawn)

	# Three lanes expose short, medium and long-range accuracy without placing targets in one line.
	for lane_x: float in [-12.0, 0.0, 12.0]:
		for target_z: float in [18.0, 3.0, -17.0]:
			var target := Vector3(lane_x, 1.35, target_z)
			_add_wood_cover(target, Vector3(1.5, 2.4, 0.14), target_mat, 0.32)
			_add_box(Vector3(lane_x, 1.35, target_z - 1.1), Vector3(2.4, 2.8, 0.32), steel_mat, 0.0, "metal")

	# Dividers mark the firing bays and stop before the shared entry apron.
	for x in [-18.0, 18.0]:
		_road_barrier(Vector3(x, 0, 22.5), 90.0, 3.2)
	ROUTE_MARKING.paint(self, "WOOD / STEEL", Vector3(-25, 0.008, 21.5), Color("#e0b073"))
	ROUTE_MARKING.paint(self, "ACCURACY", Vector3(0, 0.008, 24), Color("#e6dabb"))
	ROUTE_MARKING.paint(self, "MOVEMENT", Vector3(25, 0.008, 21.5), Color("#a0c6d8"))

	# Left side: wood and steel panels for projectile penetration and ricochet checks.
	for target_z: float in [12.0, 2.0, -8.0]:
		_add_wood_cover(Vector3(-25.0, 1.35, target_z), Vector3(3.2, 2.5, 0.18), _wood_mat, 0.32)
		_add_steel_panel(Vector3(-25.0, 1.35, target_z - 1.0), Vector3(3.2, 2.5, 0.18), steel_mat, 0.0)

	# Right side: a traversal and cover course for sprint, crouch, jump, smoke and grenade practice.
	for course in [Vector3(24.0, 0.45, 17.0), Vector3(19.0, 0.75, 10.0), Vector3(24.0, 1.05, 3.0)]:
		_add_box(course, Vector3(4.6, course.y * 2.0, 2.8), _wood_mat, 0.0, "wood")
	_add_wood_cover(Vector3(20.0, 1.1, -6.0), Vector3(7.0, 2.2, 1.0), _wood_mat, 0.32)
	_add_wood_cover(Vector3(27.0, 1.1, -14.0), Vector3(1.0, 2.2, 7.0), _wood_mat, 0.32)
	_add_box(Vector3(20.0, 1.75, -16.0), Vector3(7.0, 0.25, 4.0), steel_mat, 0.0, "metal")
	_add_box(Vector3(16.7, 0.9, -16.0), Vector3(0.25, 1.8, 4.0), steel_mat, 0.0, "metal")
	_add_box(Vector3(23.3, 0.9, -16.0), Vector3(0.25, 1.8, 4.0), steel_mat, 0.0, "metal")

	# North side remains open for grenade trajectories and optional bot fights.
	_add_steel_panel(Vector3(0.0, 1.5, -27.0), Vector3(20.0, 3.0, 0.3), steel_mat, 0.0)
	_add_wood_cover(Vector3(-8.0, 1.0, -22.0), Vector3(3.0, 2.0, 1.0), _wood_mat, 0.32)
	_add_wood_cover(Vector3(8.0, 1.0, -22.0), Vector3(3.0, 2.0, 1.0), _wood_mat, 0.32)

	var supplies: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3(-5.0, 0.0, 25.0)),
		Transform3D(Basis.IDENTITY, Vector3(5.0, 0.0, 25.0)),
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -22.0)),
	]
	_patrol.assign(respawn_points)
	return supplies


func _build_small_yard(map_id: int) -> void:
	match map_id:
		1:
			for x in [-4.5, 0.0, 4.5]:
				_add_container(Vector3(x, 1.295, 0.0), CONTAINER_WIDTH, LENGTH_20, COLOR_BLUE)
				_add_crate(Vector3(x + 1.3, 0.55, 5.5))
		2:
			for x in [-4.7, 4.7]:
				for z in [-4.7, 4.7]:
					_add_container(Vector3(x, 1.295, z), LENGTH_20, CONTAINER_WIDTH,
						COLOR_RED if x * z > 0 else COLOR_ORANGE)
		_:
			_add_container(Vector3(-5.4, 1.295, -2.5), CONTAINER_WIDTH, LENGTH_20, COLOR_BLUE)
			_add_container(Vector3(1.3, 1.295, -4.5), LENGTH_20, CONTAINER_WIDTH, COLOR_GREEN)
			_add_container(Vector3(4.6, 1.295, 2.0), CONTAINER_WIDTH, LENGTH_20, COLOR_ORANGE)
			_add_crate(Vector3(-2.0, 0.55, 4.2))
			_add_crate(Vector3(-3.2, 0.55, 5.1))


func minimap_outline(bounds: Rect2 = Rect2()) -> Array[PackedVector2Array]:
	var outline: Array[PackedVector2Array] = []
	var limited := bounds.has_area()
	var bodies := find_children("*", "StaticBody3D", limited, false)
	var to_map := global_transform.affine_inverse()
	var clip := PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y),
		bounds.end, Vector2(bounds.position.x, bounds.end.y)])
	for body: StaticBody3D in bodies:
		if body.collision_layer == 0:
			continue
		for collider in body.get_children():
			if not collider is CollisionShape3D or collider.disabled:
				continue
			var transform: Transform3D = to_map * collider.global_transform
			var polygon := PackedVector2Array()
			if collider.shape is BoxShape3D:
				var half: Vector3 = collider.shape.size * 0.5
				if transform.origin.y + half.y <= 0.65 or transform.origin.y - half.y >= 1.4:
					continue
				for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					var point := transform * Vector3(corner.x * half.x, 0.0, corner.y * half.z)
					polygon.append(Vector2(point.x, point.z))
			elif limited and collider.shape is CylinderShape3D:
				var half_height: float = collider.shape.height * 0.5
				if transform.origin.y + half_height <= 0.65 or transform.origin.y - half_height >= 1.4:
					continue
				for index in 16:
					var edge := Vector2.from_angle(index * TAU / 16.0) * float(collider.shape.radius)
					var point := transform * Vector3(edge.x, 0.0, edge.y)
					polygon.append(Vector2(point.x, point.z))
			if polygon.is_empty():
				continue
			if limited:
				outline.append_array(Geometry2D.intersect_polygons(polygon, clip))
			else:
				outline.append(polygon)
	return outline


func clear_map() -> void:
	get_viewport().use_occlusion_culling = false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_perforated.clear()
	_occupied.clear()
	_cover.clear()
	_wall_mat = null
	_wood_mat = null
	_passages.clear()
	_wood_floors.clear()
	_initial_spawns.clear()
	respawn_points.clear()
	market_supply_count = 0
	_patrol.clear()
	_district_origin = Vector3.ZERO
	_district_yaw = 0.0


func _build_spawn_ring(radius: float) -> void:
	for index in 20:
		var side := floori(index / 5.0)
		var along := lerpf(-radius, radius, float(index % 5) / 5.0)
		_initial_spawns.append(Vector3(along, 0.2, radius).rotated(Vector3.UP, side * PI * 0.5))


func _build_respawn_grid(steps: int, spacing: float, limit: float, ground_height := Callable()) -> void:
	respawn_points = _initial_spawns.duplicate()
	for x in range(-steps, steps + 1):
		for z in range(-steps, steps + 1):
			var center := Vector2(x, z) * spacing
			if _is_clear(_footprint(center, Vector2.ONE * 1.8), limit, 0.0):
				var height: float = ground_height.call(center) if ground_height.is_valid() else 0.0
				respawn_points.append(Vector3(center.x, height + 0.2, center.y))


func initial_spawn(index: int) -> Vector3:
	return _initial_spawns[(index * 7) % _initial_spawns.size()]


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
	center = _district_origin + center.rotated(Vector3.UP, deg_to_rad(_district_yaw))
	yaw_deg += _district_yaw
	var size := Vector3(size_x, CONTAINER_HEIGHT, size_z)
	var yaw := deg_to_rad(yaw_deg)
	var width := absf(cos(yaw)) * size_x + absf(sin(yaw)) * size_z
	var depth := absf(sin(yaw)) * size_x + absf(cos(yaw)) * size_z
	_occupied.append(_footprint(Vector2(center.x, center.z), Vector2(width, depth)))
	var material := _container_mat(color)
	var t := PANEL_THICKNESS
	var half := size * 0.5
	var along_x := size_x >= size_z
	var door_panel: StaticBody3D
	var panels: Array[StaticBody3D] = []
	for side in [-1.0, 1.0]:
		var x_wall := Vector3(side * (half.x - t * 0.5), 0, 0)
		var side_panel := _add_steel_panel(center + x_wall.rotated(Vector3.UP, yaw),
			Vector3(t, size.y, size.z), material, yaw_deg)
		if along_x and side > 0.0:
			door_panel = side_panel
		var z_wall := Vector3(0, 0, side * (half.z - t * 0.5))
		var end_panel := _add_steel_panel(center + z_wall.rotated(Vector3.UP, yaw),
			Vector3(size.x - t * 2, size.y, t), material, yaw_deg)
		if not along_x and side > 0.0:
			door_panel = end_panel
		var horizontal_panel := _add_steel_panel(center + Vector3.UP * side * (half.y - t * 0.5),
			Vector3(size.x - t * 2, t, size.z - t * 2), material, yaw_deg)
		panels.append_array([side_panel, end_panel, horizontal_panel])

	if center.y > CONTAINER_HEIGHT and _replace_stack_visuals(panels, center, size, color, along_x):
		return
	var door := MeshInstance3D.new()
	var door_mesh := BoxMesh.new()
	if along_x:
		door_mesh.size = Vector3(0.08, size.y * 0.78, size.z * 0.8)
		door.position = Vector3(size.x * 0.5 + 0.01, 0.0, 0.0)
	else:
		door_mesh.size = Vector3(size.x * 0.8, size.y * 0.78, 0.08)
		door.position = Vector3(0.0, 0.0, size.z * 0.5 + 0.01)
	door_mesh.material = _container_mat(color.darkened(0.28))
	door.mesh = door_mesh
	door.position = door_panel.to_local(center + door.position.rotated(Vector3.UP, yaw))
	door_panel.add_child(door)
	if _container_fittings:
		var end_width := size.z if along_x else size.x
		var facing := yaw + PI * 0.5 if along_x else yaw
		var face := Transform3D(Basis(Vector3.UP, facing),
			center + Vector3(0, 0, (size.x if along_x else size.z) * 0.5).rotated(Vector3.UP, facing))
		_add_container_fittings(face, end_width, size.y)


func _add_container_fittings(face: Transform3D, width: float, height: float) -> void:
	var stile := BoxMesh.new()
	stile.size = Vector3(0.065, height * 0.87, 0.05)
	var latch := BoxMesh.new()
	latch.size = Vector3(0.18, 0.048, 0.055)
	for side in [-1.0, 1.0]:
		_container_fittings.append_from(stile, 0, face.translated_local(Vector3(side * width * 0.22, 0, 0.070)))
		_container_fittings.append_from(latch, 0, face.translated_local(Vector3(side * width * 0.18, -0.30, 0.105)))


func _replace_stack_visuals(panels: Array[StaticBody3D], center: Vector3, size: Vector3,
		color: Color, along_x: bool) -> bool:
	if _stack_meshes.is_empty() and ResourceLoader.exists(STACK_CONTAINER_SCENE, "PackedScene"):
		var scene := load(STACK_CONTAINER_SCENE) as PackedScene
		var asset := scene.instantiate()
		for mesh: MeshInstance3D in asset.find_children("*", "MeshInstance3D", true, false):
			_stack_meshes[String(mesh.name)] = mesh.mesh
		asset.free()
	var variant := "red" if color == COLOR_RED else ("orange" if color == COLOR_ORANGE else "black")
	var faces := ["x_neg", "z_neg", "y_neg", "x_pos", "z_pos", "y_pos"] if along_x else [
		"z_neg", "x_pos", "y_neg", "z_pos", "x_neg", "y_pos"]
	for face: String in faces:
		if not _stack_meshes.has(variant + "_" + face):
			return false
	var model_size := Vector3(maxf(size.x, size.z) / 10.0, size.y / 4.2, minf(size.x, size.z) / 4.0)
	for index in panels.size():
		var panel := panels[index]
		var visual := panel.get_child(0) as MeshInstance3D
		visual.mesh = _stack_meshes[variant + "_" + faces[index]]
		visual.position = panel.to_local(center - Vector3.UP * size.y * 0.5)
		visual.rotation.y = 0.0 if along_x else PI * 0.5
		visual.scale = model_size
	return true


func _add_crate(center: Vector3) -> void:
	center = _district_origin + center.rotated(Vector3.UP, deg_to_rad(_district_yaw))
	_occupied.append(_footprint(Vector2(center.x, center.z), Vector2(1.15, 1.15)))
	var size := Vector3(1.15, 1.1, 1.15)
	_add_wood_cover(center, size, _wood_mat, 0.32)


func _add_wood_cover(center: Vector3, size: Vector3, material: Material, resistance: float) -> void:
	var box := _add_box(center, size, material, 0.0, "wood")
	box.set_meta(&"ballistic_size", size)
	box.set_meta(&"ballistic_resistance", resistance)
	_register_perforated_cover(box)


func _footprint(center: Vector2, size: Vector2) -> Rect2:
	return Rect2(center - size * 0.5, size)


func _is_clear(area: Rect2, limit: float, spawn_clearance: float) -> bool:
	if not Rect2(-limit, -limit, limit * 2.0, limit * 2.0).encloses(area):
		return false
	for obstacle in _occupied:
		if obstacle.intersects(area):
			return false
	var spawn_area := area.grow(spawn_clearance)
	if spawn_clearance > 0.0:
		for spawn in _initial_spawns:
			if spawn_area.has_point(Vector2(spawn.x, spawn.z)):
				return false
	return true


func _scatter_passages(rng: RandomNumberGenerator) -> void:
	var count := 0
	var target := 6 if _half_extent == 35.0 else 3
	var scatter_extent := _half_extent - 5.0
	for attempt in 900:
		var center := Vector2(rng.randf_range(-scatter_extent, scatter_extent), rng.randf_range(-scatter_extent, scatter_extent))
		var across := rng.randi_range(0, 1) == 1
		var size := Vector2(CONTAINER_WIDTH + 0.35, LENGTH_20 + 1.5)
		if across:
			size = Vector2(size.y, size.x)
		var area := _footprint(center, size)
		if not _is_clear(area, _half_extent - 3.0, 0.9):
			continue
		_occupied.append(area)
		_add_passage(count, Vector3(center.x, 0, center.y), 90.0 if across else 0.0,
			COLOR_GREEN.lerp(COLOR_ORANGE, rng.randf_range(0.0, 0.65)))
		count += 1
		if count == target:
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


func has_wood_deck_at(point: Vector3) -> bool:
	for floor_area in _wood_floors:
		if floor_area.has_point(Vector2(point.x, point.z)):
			return true
	for passage in _passages:
		var offset := passage.basis.transposed() * (point - passage.origin)
		if absf(offset.y) < 0.15 and absf(offset.x) < (CONTAINER_WIDTH - 0.14) * 0.5 and absf(offset.z) < LENGTH_20 * 0.5:
			return true
	return false


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
	var scatter_extent := _half_extent - 1.5
	var target := clampi(roundi(_half_extent / 3.0), 3, MAX_SUPPLY_CRATES)
	for _sample in 950:
		var center := Vector2(rng.randf_range(-scatter_extent, scatter_extent), rng.randf_range(-scatter_extent, scatter_extent))
		var quarter_turn := rng.randi_range(0, 3)
		var size := Vector2(2.28, 2.88) if quarter_turn % 2 == 0 else Vector2(2.88, 2.28)
		var area := _footprint(center, size)
		if not _is_clear(area, _half_extent - 0.15, 0.85):
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
		if crates.size() >= target:
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
	var half := _half_extent
	for attempt in 240:
		var side := rng.randi_range(0, 3)
		var center := Vector2(rng.randf_range(-half + 1.0, half - 1.0), rng.randf_range(half - 2.0, half - 0.7)).rotated(side * PI * 0.5)
		if attempt % 3 == 0:
			var obstacle := _occupied[rng.randi_range(0, obstacle_count - 1)]
			var along := rng.randf_range(0.15, 0.85)
			match side:
				0: center = Vector2(obstacle.position.x - 0.59, lerpf(obstacle.position.y, obstacle.end.y, along))
				1: center = Vector2(obstacle.end.x + 0.59, lerpf(obstacle.position.y, obstacle.end.y, along))
				2: center = Vector2(lerpf(obstacle.position.x, obstacle.end.x, along), obstacle.position.y - 0.59)
				3: center = Vector2(lerpf(obstacle.position.x, obstacle.end.x, along), obstacle.end.y + 0.59)
		var area := _footprint(center, Vector2.ONE * 0.9)
		if not _is_clear(area, half - 0.15, 0.65):
			continue
		_occupied.append(area)
		if shrub_clusters < 12 and (grass.is_empty() or rng.randf() < 0.35):
			for branch in 3:
				var offset := Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(0.0, 0.20)
				shrubs.append(_plant_transform(center + offset, rng, 0.64, 0.95))
			shrub_clusters += 1
		else:
			for tuft in rng.randi_range(10, 17):
				var offset := Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(0.0, 0.39)
				grass.append(_plant_transform(center + offset, rng, 1.05, 1.95))
		if shrub_clusters >= 12 and grass.size() >= 280:
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
	_register_perforated_cover(panel)
	return panel


func _register_perforated_cover(body: StaticBody3D, moving_surface: MeshInstance3D = null) -> void:
	var cover := PerforatedCover.new()
	cover.body = body
	cover.moving_surface = moving_surface
	if moving_surface:
		cover.original_material = moving_surface.material_override
	body.set_meta(&"bullet_cover_id", _perforated.size())
	_perforated.append(cover)


func add_bullet_hole(id: int, entry: Vector3, axis: Vector3, profile: String, force: float = 1.0, perforated := true) -> void:
	if id < 0 or id >= _perforated.size():
		return
	var cover := _perforated[id]
	var wood: bool = cover.moving_surface != null or cover.body.get_meta(&"impact_surface") == "wood"
	var radius := (0.049 if wood else 0.035) * sqrt(clampf(force, 0.32, 1.45))
	if profile == "deagle":
		radius *= 0.85
	if not perforated:
		radius *= -0.68
	if cover.points.size() == HOLES_PER_PANEL:
		cover.points.remove_at(0)
		cover.axes.remove_at(0)
	cover.points.append(Vector4(entry.x, entry.y, entry.z, radius))
	cover.axes.append(axis)
	_apply_bullet_holes(cover)


func clear_bullet_holes() -> void:
	for cover in _perforated:
		if cover.points.is_empty():
			continue
		if cover.moving_surface:
			cover.moving_surface.material_override = cover.original_material
		else:
			for mesh: MeshInstance3D in cover.body.find_children("*", "MeshInstance3D", false, false):
				mesh.material_override = null
		cover.points.clear()
		cover.axes.clear()
		cover.materials.clear()


func send_bullet_holes(peer: int) -> void:
	for id in _perforated.size():
		var cover := _perforated[id]
		if not cover.points.is_empty():
			net_bullet_holes.rpc_id(peer, id, cover.points, cover.axes)


@rpc("authority", "call_remote", "reliable", 3)
func net_bullet_holes(id: int, points: PackedVector4Array, axes: PackedVector3Array) -> void:
	if id < 0 or id >= _perforated.size():
		return
	var cover := _perforated[id]
	cover.points = points
	cover.axes = axes
	_apply_bullet_holes(cover)


func _apply_bullet_holes(cover: PerforatedCover) -> void:
	if cover.materials.is_empty():
		var meshes := cover.body.find_children("*", "MeshInstance3D", false, false)
		if cover.moving_surface:
			meshes.assign([cover.moving_surface])
		for mesh: MeshInstance3D in meshes:
			var source := mesh.get_active_material(0) as StandardMaterial3D
			if not source:
				continue
			var material := ShaderMaterial.new()
			material.shader = BULLET_HOLE_SHADER
			if cover.moving_surface:
				material.set_shader_parameter("moving_cover", true)
				material.set_shader_parameter("mesh_to_cover", cover.body.global_transform.affine_inverse() * mesh.global_transform)
			material.set_shader_parameter("color_texture", source.albedo_texture)
			material.set_shader_parameter("normal_texture", source.normal_texture)
			material.set_shader_parameter("roughness_texture", source.roughness_texture)
			material.set_shader_parameter("metallic_texture", source.metallic_texture)
			material.set_shader_parameter("ao_texture", source.ao_texture)
			material.set_shader_parameter("tint", source.albedo_color)
			material.set_shader_parameter("texture_scale", source.uv1_scale)
			material.set_shader_parameter("blend_sharpness", source.uv1_triplanar_sharpness)
			material.set_shader_parameter("metalness", source.metallic)
			material.set_shader_parameter("normal_strength", source.normal_scale if source.normal_enabled else 0.0)
			material.set_shader_parameter("use_mesh_uv", not source.uv1_triplanar)
			material.set_shader_parameter("roughness_factor", source.roughness if not source.uv1_triplanar else 1.0)
			mesh.material_override = material
			cover.materials.append(material)
	var points := cover.points.duplicate()
	var axes := cover.axes.duplicate()
	points.resize(HOLES_PER_PANEL)
	axes.resize(HOLES_PER_PANEL)
	for material in cover.materials:
		material.set_shader_parameter("hole_count", cover.points.size())
		material.set_shader_parameter("hole_points", points)
		material.set_shader_parameter("hole_axes", axes)


func _add_box(center: Vector3, size: Vector3, material: Material, yaw_deg: float = 0.0,
		surface: String = "concrete", mesh_batch: SurfaceTool = null,
		visual: Node3D = null) -> StaticBody3D:
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
	if visual:
		body.add_child(visual)
	else:
		var mesh := BoxMesh.new()
		mesh.size = size
		if mesh_batch:
			mesh_batch.append_from(mesh, 0, body.transform)
		else:
			var mesh_instance := MeshInstance3D.new()
			mesh.material = material
			mesh_instance.mesh = mesh
			body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body


func _container_mat(tint: Color) -> StandardMaterial3D:
	var mat := _textured("corrugated", tint, 0.85, 0.48, 1.0, true)
	mat.metallic_texture = _tex("corrugated", "metalness")
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


func _texture_path(material: String, kind: String) -> String:
	return "res://assets/map_textures/%s_%s.jpg" % [material, kind]


func _tex(material: String, kind: String) -> Texture2D:
	var path := _texture_path(material, kind)
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D
	return _textures[path]
