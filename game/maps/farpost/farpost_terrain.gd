extends RefCounted

const HEIGHTFIELD := preload("../forest_ridge/art/gdt/terrain_heightfield.gd")
const MESH_BUILDER := preload("../forest_ridge/art/gdt/terrain_mesh_builder.gd")
const GROUND_SHADER := preload("farpost_ground.gdshader")
const WATER_SHADER := preload("farpost_water.gdshader")
const CHUNK_QUADS := 24
const CHUNKS := 8
const QUADS := CHUNKS * CHUNK_QUADS
const INNER_START := 2
const INNER_END := 6
const BACKDROP_REACH := 65.0

var _half: float
var _step: float
var _relief: float
var _ditch_bottom: float
var _field := HEIGHTFIELD.new()
var _material: ShaderMaterial


func _init(half_width: float) -> void:
	_half = half_width
	_step = _half / (CHUNK_QUADS * 2)
	_relief = sqrt(_half / 20.0)
	_ditch_bottom = -1.12 * _relief


func build(parent: Node3D, visuals: bool) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 5160141
	noise.frequency = 0.072
	noise.fractal_octaves = 4
	_field.create_from_noise(QUADS, QUADS * _step, 1.0, noise)
	var first := 0 if visuals else INNER_START * CHUNK_QUADS
	var last := QUADS if visuals else INNER_END * CHUNK_QUADS
	for z in range(first, last + 1):
		for x in range(first, last + 1):
			var point := Vector2(_position(x), _position(z))
			_field.set_grid(x, z, _height(point, noise))
	if visuals:
		_material = _ground_material()
	var builder := MESH_BUILDER.new()
	builder.configure({
		"heightfield": _field,
		"active_total_resolution": QUADS,
		"active_chunk_resolution": CHUNK_QUADS,
		"active_step": _step,
		"active_half_size": QUADS * _step * 0.5,
	})
	for z in CHUNKS:
		for x in CHUNKS:
			var playable := x >= INNER_START and x < INNER_END and z >= INNER_START and z < INNER_END
			if playable or visuals:
				_build_chunk(parent, builder, x, z, playable, visuals)
	if visuals:
		_add_water(parent)


func position_at(point: Vector2, lift := 0.0) -> Vector3:
	var grid := Vector2(_grid(point.x), _grid(point.y))
	var cell := Vector2i(floori(grid.x), floori(grid.y))
	var t := grid - Vector2(cell)
	var a: float = _field.sample_grid(cell.x + 1, cell.y)
	var b: float = _field.sample_grid(cell.x, cell.y + 1)
	# Match the GDT triangle diagonal so props and spawn feet sit on the same surface as collision.
	var y: float
	if t.x + t.y <= 1.0:
		y = _field.sample_grid(cell.x, cell.y) * (1.0 - t.x - t.y) + a * t.x + b * t.y
	else:
		y = _field.sample_grid(cell.x + 1, cell.y + 1) * (t.x + t.y - 1.0) + a * (1.0 - t.y) + b * (1.0 - t.x)
	return Vector3(point.x, y + lift, point.y)


func path_weight(point: Vector2) -> float:
	var p := point / _half
	var road := absf(p.x - 0.18 * sin(p.y * 3.8) - 0.12)
	var service := absf(p.y - 0.16 * cos(p.x * 2.9) - 0.05)
	var trail := minf(road, service * 1.15)
	var yard := (p - Vector2(0, -0.27)).length()
	return maxf(1.0 - smoothstep(0.045, 0.16, trail), (1.0 - smoothstep(0.27, 0.39, yard)) * 0.85)


func ditch_weight(point: Vector2) -> float:
	var p := point / _half
	var side := -1.0 if p.x < 0.0 else 1.0
	var crossing := 0.06 if side < 0.0 else -0.07
	var distance := absf(point.x - _ditch_x(side, point.y))
	var banks := 1.0 - smoothstep(_half * 0.038, maxf(1.72, _half * 0.17), distance)
	var ends := 1.0 - smoothstep(0.65, 0.88, absf(p.y))
	return banks * ends * smoothstep(0.13, 0.34, absf(p.y - crossing))


func _ditch_x(side: float, z: float) -> float:
	return _half * side * (0.55 + 0.048 * sin(z * 5.1 / _half) + 0.021 * sin(z * 10.5 / _half))


func _height(point: Vector2, noise: FastNoiseLite) -> float:
	var p := point / _half
	var trail := path_weight(point)
	var height := noise.get_noise_2dv(point) * lerpf(0.95, 0.27, trail)
	height += _relief * (1.46 * _hill(p, Vector2(-0.67, -0.62), Vector2(0.33, 0.32))
		+ 1.82 * _hill(p, Vector2(0.69, 0.53), Vector2(0.38, 0.38))
		+ 0.92 * _hill(p, Vector2(-0.66, 0.39), Vector2(0.31, 0.46)))
	var pad := (p - Vector2(0, -0.29)).abs()
	height = lerpf(0.18, height, smoothstep(0.0, 0.22, maxf(pad.x - 0.29, pad.y - 0.21)))
	height = lerpf(height, _ditch_bottom, ditch_weight(point))
	var edge := maxf(absf(point.x), absf(point.y)) - _half
	# The perimeter service shoulder gives every spawn a gently graded route back into the yard.
	height = lerpf(height, noise.get_noise_2dv(point * 0.45) * 0.22, smoothstep(-minf(4.3, _half * 0.31), -1.2, edge))
	var exterior := maxf(0.0, edge)
	var ridge := 37.0 * _hill(point, Vector2(-16.0, -_half - 43.0), Vector2(34.0, 21.0))
	ridge += 22.0 * _hill(point, Vector2(28.0, -_half - 49.0), Vector2(30.0, 25.0))
	ridge += 22.0 * _hill(point, Vector2(-_half - 37.0, -4.0), Vector2(25.0, 35.0))
	ridge += 13.0 * _hill(point, Vector2(_half + 42.0, 22.0), Vector2(29.0, 36.0))
	return height + smoothstep(0.0, 24.0, exterior) * (ridge + noise.get_noise_2dv(point * 0.53) * 9.0)


func _hill(point: Vector2, center: Vector2, spread: Vector2) -> float:
	return exp(-((point - center) / spread).length_squared() * 1.5)


func _position(index: int) -> float:
	var offset := index - QUADS * 0.5
	var local := offset * _step
	return clampf(local, -_half, _half) + signf(local) * maxf(0.0, absf(local) - _half) * BACKDROP_REACH / _half


func _grid(value: float) -> float:
	var local := clampf(value, -_half, _half) + signf(value) * maxf(0.0, absf(value) - _half) * _half / BACKDROP_REACH
	return local / _step + QUADS * 0.5


func _build_chunk(parent: Node3D, builder: RefCounted, x: int, z: int, playable: bool, visuals: bool) -> void:
	var arrays: Array = builder.build_chunk_mesh_arrays(x, z, 1)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var row := CHUNK_QUADS + 1
	for index in vertices.size():
		var gx := x * CHUNK_QUADS + index % row
		var gz := z * CHUNK_QUADS + floori(float(index) / row)
		var point := Vector2(_position(gx), _position(gz))
		vertices[index].x = point.x
		vertices[index].z = point.y
		if visuals:
			var dx: float = (_field.sample_grid(gx - 1, gz) - _field.sample_grid(gx + 1, gz)) / (_position(gx + 1) - _position(gx - 1))
			var dz: float = (_field.sample_grid(gx, gz - 1) - _field.sample_grid(gx, gz + 1)) / (_position(gz + 1) - _position(gz - 1))
			normals[index] = Vector3(dx, 1.0, dz).normalized()
			var exterior := smoothstep(0.0, 10.0, maxf(absf(point.x), absf(point.y)) - _half)
			colors[index] = Color(path_weight(point) * (1.0 - exterior), ditch_weight(point), exterior, 1)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh: ArrayMesh = builder.create_mesh_from_arrays(arrays)
	var chunk: Node3D
	if playable:
		var body := StaticBody3D.new()
		body.set_meta(&"impact_surface", "dirt")
		var collision := CollisionShape3D.new()
		collision.shape = mesh.create_trimesh_shape()
		body.add_child(collision)
		chunk = body
	else:
		chunk = Node3D.new()
	chunk.name = "Terrain_%d_%d" % [x, z]
	if visuals:
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = _material
		chunk.add_child(visual)
	parent.add_child(chunk)


func _ground_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	var soil := "res://game/maps/forest_ridge/art/ground/forest_ground_04"
	var gravel := "res://game/maps/farpost/art/ground/rocky_terrain_02"
	for channel: String in ["diff", "nor_gl", "arm"]:
		material.set_shader_parameter("soil_" + channel, load(soil + "_" + channel + "_1k.jpg"))
		material.set_shader_parameter("gravel_" + channel, load(gravel + "_" + channel + "_2k.jpg"))
	return material


func _add_water(parent: Node3D) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		for stretch in [Vector2(-0.74, -0.29), Vector2(0.29, 0.74)]:
			for segment in 12:
				for corner: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1),
						Vector2(1, 0), Vector2(1, 1), Vector2(-1, 1)]:
					var t := (segment + corner.y) / 12.0
					var z := _half * lerpf(stretch.x, stretch.y, t)
					var bank := _half * (0.053 + 0.045 * sin(t * PI) + 0.005 * sin(t * 42.0))
					surface.set_normal(Vector3.UP)
					surface.add_vertex(Vector3(_ditch_x(side, z) + bank * corner.x, _ditch_bottom + 0.19, z))
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	var pools := MeshInstance3D.new()
	pools.name = "DitchPools"
	pools.mesh = surface.commit()
	pools.material_override = material
	pools.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(pools)
