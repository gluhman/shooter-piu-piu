extends StaticBody3D
## Regular half-meter terrain grid with locally refined excavation tiles.

const CELL := 0.5
const TILE := 1.5
const DEPTH := 1.7 * 0.75
const SUBDIVISIONS := 8
const SIDES := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var bounds: Rect2
var paving: Array[Rect2] = []
var cuts: Dictionary[Vector2i, bool] = {}
var _height_at: Callable
var _columns: int
var _rows: int
var _base: ArrayMesh
var _base_shape: Shape3D
var _visual := MeshInstance3D.new()
var _shape := CollisionShape3D.new()
var _soil_material: Material
var _dirt := MeshInstance3D.new()
var _dirt_shape := CollisionShape3D.new()


func configure(area: Rect2, sampler: Callable, material: Material, exposed_dirt: Material, original: ArrayMesh = null) -> void:
	bounds = area
	_height_at = sampler
	_columns = ceili(area.size.x / CELL)
	_rows = ceili(area.size.y / CELL)
	_base = original if original else _grid_mesh()
	_base_shape = _base.create_trimesh_shape()
	_visual.mesh = _base
	_visual.material_override = material
	_shape.shape = _base_shape
	_soil_material = exposed_dirt
	if exposed_dirt is StandardMaterial3D:
		exposed_dirt.vertex_color_use_as_albedo = true
	set_meta(&"impact_surface", "concrete")
	add_child(_visual)
	add_child(_shape)
	add_child(_dirt)
	add_child(_dirt_shape)


func tile_at(point: Vector2) -> Vector2i:
	return Vector2i(((point - bounds.position) / TILE).floor())


func area_of(tile: Vector2i) -> Rect2:
	return Rect2(bounds.position + Vector2(tile) * TILE, Vector2.ONE * TILE)


func height_at(point: Vector2) -> float:
	return _height_at.call(point)


func is_paved(point: Vector2) -> bool:
	for pad in paving:
		if pad.has_point(point):
			return true
	return false


func can_cut(tile: Vector2i) -> bool:
	var area := area_of(tile).grow(0.38)
	if cuts.has(tile) or not bounds.encloses(area):
		return false
	for pad in paving:
		if pad.intersects(area):
			return false
	# Corner-to-corner relief limit keeps a connected floor and usable exits.
	var center := height_at(area.get_center())
	for offset in [Vector2.ZERO, Vector2(area.size.x, 0), Vector2(0, area.size.y), area.size]:
		if absf(height_at(area.position + offset) - center) > 0.42:
			return false
	return true


func set_cuts(tiles: Array[Vector2i]) -> void:
	cuts.clear()
	for tile in tiles:
		cuts[tile] = true
	if cuts.is_empty():
		_visual.mesh = _base
		_shape.shape = _base_shape
		_dirt.mesh = null
		_dirt_shape.shape = null
		return
	var arrays := _base.surface_get_arrays(0)
	var indices := PackedInt32Array()
	for row in _rows:
		for col in _columns:
			if cuts.has(Vector2i(col / 3, row / 3)):
				continue
			var i := row * (_columns + 1) + col
			indices.append_array([i, i + 1, i + _columns + 2, i, i + _columns + 2, i + _columns + 1])
	arrays[Mesh.ARRAY_INDEX] = indices
	var remaining := ArrayMesh.new()
	remaining.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_visual.mesh = remaining
	_shape.shape = remaining.create_trimesh_shape()
	var patch := SurfaceTool.new()
	patch.begin(Mesh.PRIMITIVE_TRIANGLES)
	var collar := SurfaceTool.new()
	collar.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tile in cuts:
		_add_patch(patch, collar, tile)
	for surface in [patch, collar]:
		surface.index()
		surface.generate_normals()
		surface.generate_tangents()
	var excavation := patch.commit()
	collar.commit(excavation)
	excavation.surface_set_material(0, _soil_material)
	excavation.surface_set_material(1, _visual.material_override)
	_dirt.mesh = excavation
	_dirt_shape.shape = excavation.create_trimesh_shape()


func _grid_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in _rows + 1:
		for col in _columns + 1:
			var point := (bounds.position + Vector2(col, row) * CELL).min(bounds.end)
			vertices.append(Vector3(point.x, height_at(point), point.y))
			normals.append(Vector3.UP)
			if col < _columns and row < _rows:
				var i := row * (_columns + 1) + col
				indices.append_array([i, i + 1, i + _columns + 2, i, i + _columns + 2, i + _columns + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _exposed_edges(tile: Vector2i) -> Array[Rect2]:
	var edges: Array[Rect2] = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var neighbor := tile + Vector2i(dx, dz)
			if not cuts.has(neighbor):
				continue
			var center := area_of(neighbor).get_center()
			for side: Vector2i in SIDES:
				if cuts.has(neighbor + side):
					continue
				var normal := Vector2(side)
				var along := Vector2(absf(normal.y), absf(normal.x))
				var corner := center + (normal - along) * TILE * 0.5
				edges.append(Rect2(corner, along * TILE))
	return edges


func _excavation_depth(at: Vector2, edges: Array[Rect2]) -> float:
	var nearest := TILE
	var second := TILE
	for edge in edges:
		var distance := at.distance_to(at.clamp(edge.position, edge.end))
		if distance < nearest:
			second = nearest
			nearest = distance
		else:
			second = minf(second, distance)
	# Keep a collar of original ground at the tile boundary. The collar widens
	# around corners, so the visible opening curves inward before it drops.
	var corner := 1.0 - smoothstep(0.0, 0.25, second - nearest)
	var wobble := sin(at.x * 6.9 + at.y * 5.1) * cos(at.y * 6.2 - at.x * 3.4)
	var collar := 0.045 + 0.17 * corner + 0.038 * wobble
	nearest = maxf(0.0, nearest - collar)
	var strata := sin(at.x * 12.7 + at.y * 6.3) * cos(at.y * 9.3 - at.x * 4.6)
	var contour := sin(at.x * 4.1 + at.y * 5.2) + 0.42 * sin(at.x * 15.1 - at.y * 11.7)
	var bevel := 0.23 + contour * 0.041
	var lip := 0.095 * smoothstep(0.0, 0.11 + contour * 0.022, nearest)
	var wall := (DEPTH - 0.095) * smoothstep(0.055 + contour * 0.016, bevel, nearest)
	var depth := lip + wall
	depth += 0.060 * strata * sin(PI * clampf(depth / DEPTH, 0.0, 1.0))
	var lumps := pow(0.5 + 0.5 * sin(at.x * 8.3 + at.y * 4.9) * cos(at.y * 7.7), 4.0)
	return clampf(depth - 0.055 * lumps * smoothstep(0.72, DEPTH, depth), 0.0, DEPTH)


func _add_patch(mesh: SurfaceTool, collar: SurfaceTool, tile: Vector2i) -> void:
	var start := area_of(tile).position
	var count := 3 * SUBDIVISIONS
	var step := CELL / SUBDIVISIONS
	var edges := _exposed_edges(tile)
	var points := PackedVector3Array()
	var distances := PackedFloat32Array()
	for row in count + 1:
		for col in count + 1:
			var at := start + Vector2(col, row) * step
			var depth := _excavation_depth(at, edges)
			points.append(Vector3(at.x, height_at(at) - depth, at.y))
			distances.append(depth)
	for row in count:
		for col in count:
			var i := row * (count + 1) + col
			_add_triangle(mesh, collar, points, distances, i, i + 1, i + count + 2)
			_add_triangle(mesh, collar, points, distances, i, i + count + 2, i + count + 1)


func _add_triangle(soil: SurfaceTool, collar: SurfaceTool, points: PackedVector3Array,
		depths: PackedFloat32Array, a: int, b: int, c: int) -> void:
	var mesh := soil if maxf(depths[a], maxf(depths[b], depths[c])) > 0.005 else collar
	for index in [a, b, c]:
		var at := points[index]
		var depth := depths[index]
		var tint := lerpf(1.0, 0.70, smoothstep(0.05, DEPTH, depth))
		tint += 0.04 * sin(at.y * 27.0 + at.x * 4.0 + at.z * 2.0)
		mesh.set_color(Color(tint, tint, tint))
		mesh.set_uv(Vector2(at.x + depth * 0.68, at.z - depth * 0.42) * 0.9)
		mesh.add_vertex(at)
