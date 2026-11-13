extends RefCounted

const EarthSurface := preload("res://game/maps/procedural/earth_surface.gd")
const WIDTH := 120.0
const WALL_THICKNESS := 0.65
const FLOOR_BASE := -3.0
const MESH_CELL_SIZE := 12.0
const SCRAP_SKIP_MESH_SIZE := Vector3(1.805, 0.8825, 1.265)

class Sector:
	var bounds: Rect2
	var near_height: float
	var far_height: float
	var slope_axis: int

	func _init(x1: float, z1: float, x2: float, z2: float, start_height: float,
			end_height: float, axis: int = Vector2.AXIS_Y) -> void:
		bounds = Rect2(x1, z1, x2 - x1, z2 - z1)
		near_height = start_height
		far_height = end_height
		slope_axis = axis

	func height_at(point: Vector2) -> float:
		var progress := (point[slope_axis] - bounds.position[slope_axis]) / bounds.size[slope_axis]
		return lerpf(near_height, far_height, progress)


const PATROL := [
	Vector2(-32, 49), Vector2(-4, 28), Vector2(-3, -13), Vector2(16, -9),
	Vector2(17, -29), Vector2(39, -47), Vector2(49, -19), Vector2(49, 11),
	Vector2(27, 11), Vector2(14, 26), Vector2(-3, -25), Vector2(-19, -37),
	Vector2(-44, -48), Vector2(-43, -14), Vector2(-41, 33),
]
const SPAWNS := [
	Vector2(-28, 51), Vector2(34, -48), Vector2(-46, -48), Vector2(50, 2),
	Vector2(-4, -39), Vector2(-43, 35), Vector2(14, 27), Vector2(-44, -15),
	Vector2(44, -45), Vector2(-17, 51), Vector2(-46, 47), Vector2(49, -11),
	Vector2(-6, 38), Vector2(-17, -35), Vector2(-39, -40), Vector2(-18.9, 8.7),
	Vector2(15, -29), Vector2(36, 13.7), Vector2(4, -41), Vector2(-40, 22),
	Vector2(-34, 47), Vector2(49, 10), Vector2(50, -48), Vector2(-2, 14),
]
const RESPAWNS := [
	Vector2(-44, 3), Vector2(-41, -26), Vector2(-5.6, -14), Vector2(-20, -4),
	Vector2(17, -17), Vector2(49, -25), Vector2(7, -9), Vector2(12, 20),
	Vector2(61, -0.5), Vector2(-6, -29), Vector2(-1, 25), Vector2(-47, -34),
]

var _map: Node3D
var _sectors: Array[Sector] = []
var _stone: StandardMaterial3D
var _ground: StandardMaterial3D
var _trim: StandardMaterial3D
var _wood: StandardMaterial3D
var _shade: StandardMaterial3D
var _patrol: Array[Vector3] = []
var _shell: Array[StaticBody3D] = []
var _occluder_walls: Array[StaticBody3D] = []


func _init(map: Node3D) -> void:
	_map = map


func build(width: float) -> Array[Transform3D]:
	_stone = _map._world_mat("dust2/sandstone", Color(1.0, 0.96, 0.89), 0.0, 0.34, 0.76, false)
	_ground = _map._world_mat("dust2/sand", Color(0.95, 1.0, 1.0), 0.0, 0.38, 0.52, false)
	_trim = _map._world_mat("concrete", Color(0.93, 0.81, 0.62), 0.0, 0.75, 0.6, false)
	_shade = _map._world_mat("concrete", Color(0.65, 0.55, 0.41), 0.0, 0.7, 0.8, false)
	_wood = _map._world_mat("planks", Color(0.64, 0.49, 0.32), 0.0, 0.86, 0.85, true)
	if width < 70.0:
		var compact_supplies := _build_compact(width)
		_batch_shell()
		return compact_supplies
	_add_sectors()
	for sector in _sectors:
		_boundary_walls(sector)
	_landmarks()
	for point in SPAWNS:
		_map._initial_spawns.append(_position(point, 0.2))
	_map.respawn_points = _map._initial_spawns.duplicate()
	for point in RESPAWNS:
		_map.respawn_points.append(_position(point, 0.2))
	var supplies: Array[Transform3D] = []
	for point: Vector2 in [Vector2(-42.5, -47.6), Vector2(36.3, -46.2), Vector2(-46.4, 12.8),
			Vector2(62.5, 6.6), Vector2(8.3, -35.7), Vector2(-22, 3.4), Vector2(14.1, -30.7),
			Vector2(-42.5, 52.0), Vector2(40.7, 7.6)]:
		supplies.append(Transform3D(Basis.IDENTITY, _position(point)))
	for point in PATROL:
		_patrol.append(_position(point, 0.2))
	_fit_full_layout(width, supplies)
	for sector in _sectors:
		_floor(sector, width / WIDTH, Vector2(5.5, 0.0))
	_add_wall_occluder()
	_batch_shell()
	return supplies


func _build_compact(width: float) -> Array[Transform3D]:
	var half := width * 0.5
	var sector := Sector.new(-half, -half, half, half, 0.0, 0.0)
	_sectors.append(sector)
	_floor(sector)
	_boundary_walls(sector)
	_map._build_spawn_ring(half - 1.35)
	var supplies: Array[Transform3D] = []
	# Two blocks divide the middle into three routes, with crossovers at either end.
	for side in [-1.0, 1.0]:
		var x: float = side * width * 0.24
		for end in [-1.0, 1.0]:
			var z: float = end * width * 0.12
			var block := Vector3(width * 0.15, 3.6, width * 0.17)
			_map._add_box(Vector3(x, block.y * 0.5, z), block, _stone, 0.0, "brick")
			_map._occupied.append(Rect2(Vector2(x, z) - Vector2(block.x, block.z) * 0.5,
				Vector2(block.x, block.z)))
		var site := Vector2(x, -width * 0.33)
		_sign(site, "A" if side > 0.0 else "B")
		var cover := site + Vector2(side * 2.0, 1.5)
		var cover_size := Vector3(1.6, 1.45, 1.1)
		_crate(cover, cover_size)
		_map._occupied.append(Rect2(cover - Vector2(0.8, 0.55), Vector2(1.6, 1.1)))
		for point in [site + Vector2(-side * 1.8, 0), Vector2(x, width * 0.32)]:
			supplies.append(Transform3D(Basis.IDENTITY, _position(point)))
			_map._occupied.append(Rect2(point - Vector2.ONE * 0.8, Vector2.ONE * 1.6))
	# The offsets leave a continuous middle route with a place to break sightlines.
	for side in [-1.0, 1.0]:
		var point := Vector2(side * width * 0.085, side * width * 0.14)
		_crate(point, Vector3(1.35, 1.23, 0.95))
		_map._occupied.append(Rect2(point - Vector2(0.675, 0.475), Vector2(1.35, 0.95)))
	_sign(Vector2(0, width * 0.29), "MID")
	var spacing := width * 0.14
	_map._build_respawn_grid(3, spacing, half)
	_patrol.assign(_map.respawn_points)
	return supplies


func _fit_full_layout(width: float, supplies: Array[Transform3D]) -> void:
	# Fit the original routes horizontally while preserving headroom and step heights.
	var ratio := width / WIDTH
	var scale := Vector3(ratio, 1.0, ratio)
	var center := Vector3(5.5, 0.0, 0.0)
	for child: Node3D in _map.get_children():
		child.position = (child.position - center) * scale
		if child is StaticBody3D:
			for piece: Node3D in child.get_children():
				if piece is CollisionShape3D:
					var shape: Shape3D = piece.shape
					if shape is BoxShape3D:
						shape.size *= scale
					elif shape is ConvexPolygonShape3D:
						var points: PackedVector3Array = shape.points
						for index in points.size():
							points[index] *= scale
						shape.points = points
				else:
					piece.position *= scale
					piece.basis = piece.basis.scaled(scale)
			if child.has_meta(&"ballistic_size"):
				child.set_meta(&"ballistic_size", child.get_meta(&"ballistic_size") * scale)
		elif child is Label3D:
			child.pixel_size *= ratio
	for index in _map._initial_spawns.size():
		_map._initial_spawns[index] = (_map._initial_spawns[index] - center) * scale
	for index in _map.respawn_points.size():
		_map.respawn_points[index] = (_map.respawn_points[index] - center) * scale
	for index in _patrol.size():
		_patrol[index] = (_patrol[index] - center) * scale
	for index in supplies.size():
		supplies[index].origin = (supplies[index].origin - center) * scale


func _add_sectors() -> void:
	_sectors = [
		# T spawn and the approaches to the three routes.
		Sector.new(-49, 44, 3, 56, 0, 0),
		Sector.new(-8, 32, 3, 44, 0, 0),
		Sector.new(-8, 23, 20, 32, 0, 0),
		Sector.new(10, 9, 20, 23, 0, 0),
		# Long doors, A Long, pit and A site.
		Sector.new(20, 6, 44, 16, 0, 0),
		Sector.new(44, -14, 57, 16, 0, 0),
		Sector.new(57, -6, 60, 10, 0, -1.1, Vector2.AXIS_X),
		Sector.new(60, -6, 64, 10, -1.1, -1.1),
		Sector.new(44, -34, 52, -14, 2.4, 0),
		Sector.new(29, -54, 52, -34, 2.4, 2.4),
		# Mid and the raised approach to A Short.
		Sector.new(-8, 10, 1, 23, 0, 0),
		Sector.new(-8, 0, 1, 10, -2, 0),
		Sector.new(-8, -22, 1, 0, -2, -2),
		Sector.new(1, -12, 20, -5, -2, -2),
		Sector.new(12, -26, 20, -12, 2.4, -2),
		Sector.new(12, -34, 39, -26, 2.4, 2.4),
		# CT spawn and both site connectors.
		Sector.new(-8, -47, 11, -22, -2, -2),
		Sector.new(11, -47, 17, -38, -2, -2),
		Sector.new(17, -47, 29, -38, -2, 2.4, Vector2.AXIS_X),
		Sector.new(-26, -42, -8, -32, 1.8, -2, Vector2.AXIS_X),
		Sector.new(-30, -42, -26, -32, 1.8, 1.8),
		# B site, upper tunnels and lower tunnels to Mid.
		Sector.new(-53, -56, -30, -32, 1.8, 1.8),
		Sector.new(-49, -32, -36, -22, 1.8, 0),
		Sector.new(-49, -22, -36, 3, 0, 0),
		Sector.new(-49, 3, -33, 14, 0, 0),
		Sector.new(-49, 14, -35, 44, 0, 0),
		Sector.new(-33, 3, -24, 14, 0, -2, Vector2.AXIS_X),
		Sector.new(-24, -8, -14, 14, -2, -2),
		Sector.new(-14, -8, -8, -2, -2, -2),
	]


func patrol_route() -> Array[Vector3]:
	return _patrol


func _position(point: Vector2, offset: float = 0.0) -> Vector3:
	for sector in _sectors:
		if sector.bounds.has_point(point):
			return Vector3(point.x, sector.height_at(point) + offset, point.y)
	push_error("Dust II point lies outside the playable area: %s" % point)
	return Vector3(point.x, offset, point.y)


func _floor(sector: Sector, ratio := 1.0, origin := Vector2.ZERO) -> void:
	var body := EarthSurface.new()
	body.name = "DustTerrain%d" % _sectors.find(sector)
	var dirt: Material = _map._world_mat("dust2/sand", Color(0.79, 0.70, 0.56), 0.0, 0.68, 1.1, false)
	var area := Rect2((sector.bounds.position - origin) * ratio, sector.bounds.size * ratio)
	var sample := func(point: Vector2) -> float: return sector.height_at(point / ratio + origin)
	body.configure(area, sample, _ground, dirt)
	_map.add_child(body)


func _boundary_walls(sector: Sector) -> void:
	for axis in 2:
		var along := 1 - axis
		for side in [-1, 1]:
			var edge := sector.bounds.position[axis] if side < 0 else sector.bounds.end[axis]
			var start := sector.bounds.position[along]
			var end := sector.bounds.end[along]
			var openings: Array[Vector2] = []
			for other in _sectors:
				var facing := other.bounds.end[axis] if side < 0 else other.bounds.position[axis]
				if other == sector or not is_equal_approx(edge, facing):
					continue
				var low := maxf(start, other.bounds.position[along])
				var high := minf(end, other.bounds.end[along])
				if low < high:
					openings.append(Vector2(low, high))
			openings.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
			for opening in openings:
				_wall(sector, axis, side, edge, start, opening.x)
				start = maxf(start, opening.y)
			_wall(sector, axis, side, edge, start, end)


func _wall(sector: Sector, axis: int, side: int, edge: float, start: float, end: float) -> void:
	if end - start < 0.01:
		return
	var center := Vector2.ZERO
	center[axis] = edge + side * WALL_THICKNESS * 0.5
	center[1 - axis] = (start + end) * 0.5
	var size := Vector2.ZERO
	size[axis] = WALL_THICKNESS
	size[1 - axis] = end - start + WALL_THICKNESS
	var top := maxf(sector.near_height, sector.far_height) + 4.8
	var height := top - FLOOR_BASE
	var wall := _shell_box(Vector3(center.x, FLOOR_BASE + height * 0.5, center.y),
		Vector3(size.x, height, size.y), _stone, "brick")
	if end - start >= 4.0:
		_occluder_walls.append(wall)
	if end - start >= 5.0:
		size[axis] += 0.18
		_shell_box(Vector3(center.x, top, center.y), Vector3(size.x, 0.18, size.y), _trim)
		var band := size
		band[axis] = WALL_THICKNESS + 0.1
		_shell_box(Vector3(center.x, top - 0.75, center.y), Vector3(band.x, 0.09, band.y), _trim)


func _shell_box(center: Vector3, size: Vector3, material: Material, surface := "concrete") -> StaticBody3D:
	var body: StaticBody3D = _map._add_box(center, size, material, 0.0, surface)
	_shell.append(body)
	return body


func _add_wall_occluder() -> void:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for body in _occluder_walls:
		var visual := body.get_child(0) as MeshInstance3D
		var transform := body.transform * visual.transform
		for vertex in visual.mesh.get_faces():
			indices.append(vertices.size())
			vertices.append(transform * (vertex * 0.98))
	if indices.is_empty():
		return
	var occluder := ArrayOccluder3D.new()
	occluder.set_arrays(vertices, indices)
	var instance := OccluderInstance3D.new()
	instance.occluder = occluder
	_map.add_child(instance)
	_map.get_viewport().use_occlusion_culling = true


func _batch_shell() -> void:
	var cells: Dictionary[Vector2i, Dictionary] = {}
	for body in _shell:
		var visual := body.get_child(0) as MeshInstance3D
		var material := visual.mesh.surface_get_material(0)
		var cell := Vector2i(floori(body.position.x / MESH_CELL_SIZE), floori(body.position.z / MESH_CELL_SIZE))
		var surfaces: Dictionary = cells.get_or_add(cell, {})
		if not surfaces.has(material):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surface.set_material(material)
			surfaces[material] = surface
		var batch: SurfaceTool = surfaces[material]
		batch.append_from(visual.mesh, 0, body.transform * visual.transform)
		body.remove_child(visual)
		visual.queue_free()
	for surfaces in cells.values():
		for surface: SurfaceTool in surfaces.values():
			var mesh := MeshInstance3D.new()
			mesh.mesh = surface.commit()
			_map.add_child(mesh)


func _landmarks() -> void:
	_gate(Vector2(32, 11), 10.0, 90.0, true)
	_gate(Vector2(-3.5, -19.0), 9.0, 0.0, true)
	_gate(Vector2(-28, -37), 10.0, 90.0, true)
	_gate(Vector2(-42.5, -20), 13.0, 0.0, false)
	_gate(Vector2(-42, 17), 14.0, 0.0, false)
	_gate(Vector2(-19, -4), 7.0, 90.0, false)
	_ceiling(Vector2(-42.5, -14), Vector2(13, 6), 3.25)
	_ceiling(Vector2(-42.5, -2.5), Vector2(13, 11), 3.25)
	_ceiling(Vector2(-19, 5), Vector2(10, 14), 1.0)
	_ceiling(Vector2(1.5, -37), Vector2(19, 11), 1.5)

	_site_a()
	_site_b()
	_long_approach()
	_middle()
	_crate(Vector2(-42.5, 49.5), Vector3(3.5, 1.95, 2.1))
	_wall_sign(Vector2(-23, 44.035), 2.15, "← B")
	_wall_sign(Vector2(-13.5, 44.035), 2.15, "МИД / A →")


func _site_a() -> void:
	# Full cover separates the Short entry from the site's rear; the low crate leaves Long readable.
	_crate(Vector2(36.3, -43.0), Vector3(3.2, 2.1, 2.4))
	_crate(Vector2(38.8, -43.5), Vector3(1.8, 1.14, 1.8))
	_crate(Vector2(32.0, -37.4), Vector3(2.5, 1.13, 1.55))
	_crate(Vector2(44.4, -49.7), Vector3(2.45, 1.6, 1.8))
	_parked_car(Vector2(50.4, -40.2), Color("#827960"))
	_crate(Vector2(14.0, -32.5), Vector3(2.4, 1.85, 1.55))
	_sign(Vector2(41, -43), "A")
	_wall_sign(Vector2(41, -53.965), 5.0, "A", 1.7)
	_wall_sign(Vector2(21, -33.965), 4.6, "A →")


func _site_b() -> void:
	# Tunnel and door arrivals retain separate paths around the central stack.
	_crate(Vector2(-42.5, -44), Vector3(3.4, 2.05, 2.5))
	_crate(Vector2(-39.8, -44.4), Vector3(1.85, 1.14, 1.7))
	_crate(Vector2(-35.4, -50.7), Vector3(2.45, 1.75, 2.3))
	_parked_car(Vector2(-50.5, -42.1), Color("#74604c"))
	_crate(Vector2(-46.4, 10.3), Vector3(2.5, 1.9, 1.65))
	_crate(Vector2(-37.4, -9), Vector3(1.6, 1.1, 2.0))
	_sign(Vector2(-39.5, -48), "B")
	_wall_sign(Vector2(-42, -55.965), 5.35, "B", 1.7)


func _long_approach() -> void:
	var dumpster_size := Vector3(3.7, 1.855, 2.5)
	var scene := load("res://assets/arena_props/junkyard_scrap_skip_01.glb") as PackedScene
	var dumpster := scene.instantiate() as Node3D
	dumpster.scale = dumpster_size / SCRAP_SKIP_MESH_SIZE
	dumpster.position.y = -dumpster_size.y * 0.5
	var center := _position(Vector2(37.9, 7.8), dumpster_size.y * 0.5)
	_map._add_box(center, dumpster_size, null, 0.0, "metal", null, dumpster)
	_crate(Vector2(62.5, 4.2), Vector3(2.2, 1.47, 1.6))
	_crate(Vector2(52.9, -7.1), Vector3(2.65, 1.32, 1.15))
	_sign(Vector2(47.5, 1.9), "LONG A")
	_wall_sign(Vector2(42, 6.035), 3.0, "A →")


func _middle() -> void:
	_crate(Vector2(-6.35, -9.4), Vector3(2.25, 1.6, 2.2))
	_crate(Vector2(-21.25, 6.15), Vector3(2.4, 1.28, 1.6))
	_sign(Vector2(-3.5, 19.0), "MID")
	_crate(Vector2(8.3, -33.5), Vector3(2.4, 1.8, 1.65))
	_wall_sign(Vector2(-3.5, -46.965), 0.3, "← B")
	_wall_sign(Vector2(6, -46.965), 0.3, "A →")


func _parked_car(point: Vector2, paint: Color) -> void:
	var base := _position(point)
	var chassis := _map._add_box(base + Vector3.UP * 0.63, Vector3(2.2, 0.94, 4.2),
		_flat_material(paint, 0.35), 0.0, "metal") as StaticBody3D
	_map._add_box(base + Vector3(0, 1.38, 0.35), Vector3(1.95, 0.59, 2.08),
		_flat_material(Color("#4b514e"), 0.25), 0.0, "metal")
	var rubber := _flat_material(Color("#302e2a"), 0.0)
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.37
	wheel.bottom_radius = 0.37
	wheel.height = 0.24
	wheel.radial_segments = 12
	wheel.material = rubber
	for side in [-1.0, 1.0]:
		for axle in [-1.24, 1.24]:
			var visual := MeshInstance3D.new()
			visual.mesh = wheel
			visual.position = Vector3(1.07 * side, -0.25, axle)
			visual.rotation.z = PI * 0.5
			chassis.add_child(visual)
	var bumper := BoxMesh.new()
	bumper.size = Vector3(2.23, 0.15, 0.14)
	bumper.material = rubber
	for end in [-1.0, 1.0]:
		var visual := MeshInstance3D.new()
		visual.mesh = bumper
		visual.position = Vector3(0.0, -0.22, end * 2.09)
		chassis.add_child(visual)
	var headlamp := BoxMesh.new()
	headlamp.size = Vector3(0.46, 0.19, 0.05)
	headlamp.material = _flat_material(Color("#ded3a3"), 0.12)
	var tail_lamp := headlamp.duplicate() as BoxMesh
	tail_lamp.material = _flat_material(Color("#963e32"), 0.08)
	for end in [-1.0, 1.0]:
		for side in [-1.0, 1.0]:
			var light := MeshInstance3D.new()
			light.mesh = headlamp if end < 0 else tail_lamp
			light.position = Vector3(side * 0.74, 0.16, end * 2.11)
			chassis.add_child(light)


func _flat_material(color: Color, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.76
	material.metallic = metallic
	return material


func _ceiling(point: Vector2, span: Vector2, height: float) -> void:
	_map._add_box(Vector3(point.x, height, point.y), Vector3(span.x, 0.45, span.y), _shade)


func _crate(point: Vector2, size: Vector3) -> void:
	_map._add_wood_cover(_position(point, size.y * 0.5), size, _wood, 0.32)


func _gate(point: Vector2, width: float, yaw: float, doors: bool) -> void:
	var base := _position(point)
	var axis := Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(yaw))
	var pillar_width := (width - 4.8) * 0.5
	for side in [-1.0, 1.0]:
		_map._add_box(base + side * axis * (2.4 + pillar_width * 0.5) + Vector3.UP * 1.8,
			Vector3(pillar_width, 3.6, 0.92), _stone, yaw, "brick")
		_map._add_box(base + side * axis * 2.3 + Vector3.UP * 2.92,
			Vector3(0.72, 0.42, 1.0), _trim, yaw, "brick")
		if doors:
			var door_size := Vector3(1.0, 2.55, 0.17)
			var door := _map._add_box(base + side * axis * 1.95 + Vector3.UP * 1.28,
				door_size, _wood, yaw + side * 22.0, "wood") as StaticBody3D
			door.set_meta(&"ballistic_size", door_size)
			door.set_meta(&"ballistic_resistance", 0.32)
			_map._register_perforated_cover(door)
	_map._add_box(base + Vector3.UP * 3.45, Vector3(width, 0.7, 0.95), _trim, yaw, "brick")


func _sign(point: Vector2, text: String) -> void:
	var label := _painted_label(text, 0.022)
	label.position = _position(point, 0.025)
	label.rotation.x = -PI * 0.5


func _wall_sign(point: Vector2, height: float, text: String, scale: float = 1.0) -> void:
	var label := _painted_label(text, 0.012 * scale)
	label.position = Vector3(point.x, height, point.y)


func _painted_label(text: String, pixel_size: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 112
	label.pixel_size = pixel_size
	label.modulate = Color("#aa4129")
	label.outline_size = 0
	_map.add_child(label)
	return label
