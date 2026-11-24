extends RefCounted
## Objective footprints and covered deployment lanes, by arena variant.

const FOREST_HILL := preload("res://game/maps/forest_hill/forest_hill_layout.gd")
const PLACEMENTS := preload("res://game/maps/objective_placements.gd")
const REFINERY := preload("res://game/maps/refinery/refinery_layout.gd")
const STATION_SCENERY := preload("res://game/maps/station/station_scenery.gd")
const WOODEN_CRATE := preload("res://assets/arena_props/village/wooden_crate_01.glb")
const TOOL_CHEST := preload("res://game/maps/station/art/metal_tool_chest/metal_tool_chest_2k.gltf")
const HILL_AREA_SCALE := 1.5
const HILL := 2
const FLAG := 3
const DEFUSE := 4
const NAMES := ["Каждый за себя", "Командный бой 5 на 5", "Царь горы", "Захват флага", "Обезвреживание"]
const GOLD := Color("#f4bb4a")
const TEAMS := [Color("#409df3"), Color("#f46861")]


static func supports(mode: int, arena: int, size: int) -> bool:
	if arena == FOREST_HILL.MAP_ID:
		return mode == HILL and size == 2
	if mode < HILL:
		return true
	return mode <= DEFUSE and PLACEMENTS.MAPS.get("%d-%d" % [arena, size], {}).has(str(mode))


static func reason(mode: int, arena: int, size: int) -> String:
	if supports(mode, arena, size):
		return ""
	if arena == FOREST_HILL.MAP_ID:
		return "Лесной бастион доступен только в режиме «Царь горы», размер 100 × 100 м."
	if arena == REFINERY.MAP_ID:
		return "Для НПЗ доступен один размер арены."
	if arena in [7, 8] or size == 0:
		return "Недостаточно места для целей и командных маршрутов."
	return "Для этого варианта нет проверенной расстановки целей."


static func _placement(mode: int, arena: int, size: int) -> Dictionary:
	if arena == FOREST_HILL.MAP_ID:return FOREST_HILL.placement()
	return PLACEMENTS.MAPS["%d-%d" % [arena, size]][str(mode)]


static func reserved_areas(mode: int, arena: int, size: int) -> Array[Rect2]:
	var areas: Array[Rect2] = []
	var placement := _placement(mode, arena, size)
	for point in placement.c:
		areas.append(Rect2(Vector2(point[0], point[2]), Vector2.ZERO).grow(_radius(placement, mode) + 0.55))
	for pool in placement.s:
		for point in pool:
			areas.append(Rect2(Vector2(point[0], point[2]), Vector2.ZERO).grow(1.0))
	for item in placement.cover:
		areas.append(Rect2(Vector2(item[0][0], item[0][2]), Vector2.ZERO).grow(1.6))
	return areas


static func create(map: Node3D, mode: int, arena: int, size: int) -> Dictionary:
	var placement := _placement(mode, arena, size)
	var centers := PackedVector3Array()
	for point in placement.c:
		centers.append(_point(point))
	var spawns: Array[PackedVector3Array] = []
	for points in placement.s:
		var pool := PackedVector3Array()
		for point in points:
			pool.append(_point(point) + Vector3.UP * 0.18)
		spawns.append(pool)
	_add_cover(map, arena, placement.cover)
	if mode == HILL:
		_add_hill_cover(map, arena, placement.hill_cover)
	return {"centers": centers, "spawns": spawns, "radius": _radius(placement, mode)}


static func _radius(placement: Dictionary, mode: int) -> float:
	return float(placement.r) * (sqrt(HILL_AREA_SCALE) if mode == HILL else 1.0)


static func _add_hill_cover(map: Node3D, arena: int, placements: Array) -> void:
	# One crouch-height prop per hill. The center and the other approaches remain open.
	for entry in placements:
		var at := _point(entry[0]) - Vector3.UP * 0.08
		var yaw: float = entry[1]
		var body: StaticBody3D
		match arena:
			3, 4, 11:
				body = _model_cover(map, WOODEN_CRATE, at, yaw, Vector3(1.58, 1.33, 0.97), "wood")
			5, 10, REFINERY.MAP_ID:
				body = _model_cover(map, TOOL_CHEST, at, yaw, Vector3(1.60, 1.31, 0.85), "metal")
			_:
				body = map._road_barrier(at, yaw, 1.8, 1.32)
		body.add_to_group(&"hill_cover")


static func _point(coordinates: Array) -> Vector3:
	return Vector3(coordinates[0], coordinates[1], coordinates[2])


static func _add_cover(map: Node3D, arena: int, placements: Array) -> void:
	var art: RefCounted
	if arena == 10 and DisplayServer.get_name() != "headless":
		art = STATION_SCENERY.new(map, 1.0, 0.0, 0.0, 0.0)
	for entry in placements:
		var at := _point(entry[0])
		var yaw: float = entry[1]
		match arena:
			3, 11:
				_wooden_cover(map, at, yaw)
			4:
				var stone: Material = map._world_mat("dust2/sandstone", Color("#b5a082"), 0.0, 0.62, 0.76, false)
				var extent := Vector3(2.15, 1.42, 0.76)
				map._add_box(at + Vector3.UP * 0.63, extent, stone, yaw, "brick")
			10:
				var extent := Vector3(1.28, 1.50, 1.07)
				var center := at + Vector3.UP * extent.y * 0.5
				map._add_box(center, extent, null, 0.0, "metal", null, Node3D.new())
				if art:
					art.fixture(center, extent, "cargo")
			_:
				map._road_barrier(at, yaw, 2.1)
	if art:
		art._flush_boxes()


static func _wooden_cover(map: Node3D, at: Vector3, yaw: float) -> void:
	_model_cover(map, WOODEN_CRATE, at - Vector3.UP * 0.06, yaw, Vector3(1.62, 1.36, 1.10), "wood")


static func _model_cover(map: Node3D, scene: PackedScene, at: Vector3, yaw: float,
		extent: Vector3, surface: String) -> StaticBody3D:
	var model := scene.instantiate() as Node3D
	var bounds := AABB()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var local := mesh.transform
		var parent := mesh.get_parent() as Node3D
		while parent != model:
			local = parent.transform * local
			parent = parent.get_parent() as Node3D
		var transformed := local * mesh.get_aabb()
		bounds = bounds.merge(transformed) if bounds.has_volume() else transformed
	model.scale = extent / bounds.size
	model.position = -bounds.get_center() * model.scale
	var body: StaticBody3D = map._add_box(at + Vector3.UP * extent.y * 0.5, extent, null, yaw, surface, null, model)
	map.SHOT_COLLISION.use_model(body, model)
	return body


static func contains(feet: Vector3, center: Vector3, radius: float) -> bool:
	var offset := feet - center
	return offset.y >= -0.35 and offset.y <= 1.65 and Vector2(offset.x, offset.z).length_squared() <= radius * radius
