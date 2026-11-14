extends RefCounted

const FIR_MESHES := preload("../forest_ridge/fir_meshes.gd")
const ART := "res://game/maps/farpost/art/"
const FOREST := "res://game/maps/forest_ridge/art/"
const CLIFF := ART + "cliff/mountainside_2k.gltf"
const STUMP := ART + "stump/tree_stump_01_2k.gltf"

var _root: Node3D
var _terrain: RefCounted
var _half: float
var _rng := RandomNumberGenerator.new()
var _models: Dictionary = {}
var _sheet: StandardMaterial3D
var _roof: StandardMaterial3D
var _wood: StandardMaterial3D
var _steel := _paint(Color("#343a37"), 0.54)
var _olive := _paint(Color("#77745d"), 0.42)
var _orange := _paint(Color("#c58f4a"), 0.25)
var _glass := _paint(Color("#253338"), 0.32)
var _lamp := _paint(Color("#ffd198"), 0.0)
var _mesh_cache: Dictionary = {}


func _init(root: Node3D, terrain: RefCounted, half_width: float) -> void:
	_root = root
	_terrain = terrain
	_half = half_width
	_rng.seed = 825361
	_sheet = _corrugated(Color("#9f8065"), 0.64)
	_roof = _corrugated(Color("#6d675c"), 0.76)
	_wood = _paint(Color("#757064"), 0.0)
	_wood.albedo_texture = load("res://assets/map_textures/planks_color.jpg")
	_wood.normal_enabled = true
	_wood.normal_texture = load("res://assets/map_textures/planks_normal.jpg")
	_wood.uv1_triplanar = true
	_wood.uv1_scale = Vector3(1.5, 0.31, 1.5)
	_lamp.emission_enabled = true
	_lamp.emission = Color("#ffc886")
	_lamp.emission_energy_multiplier = 2.1
	_glass.roughness = 0.17


func relay(size: Vector3) -> Node3D:
	var building := Node3D.new()
	var front := size.z * 0.5
	var height := size.y
	_box(building, Vector3(0, height * 0.5, 0), size, _sheet)
	_box(building, Vector3(0, 0.19, 0), Vector3(size.x + 0.14, 0.38, size.z + 0.14), _steel)
	_box(building, Vector3(0, height, 0), Vector3(size.x + 0.24, 0.16, size.z + 0.24), _steel)
	var parapet := _box(building, Vector3(0, height + 0.19, 0),
		Vector3(size.x + 0.32, 0.25, size.z + 0.34), _roof)
	parapet.rotation.z = -0.037
	for side in [-1.0, 1.0]:
		_box(building, Vector3(side * size.x * 0.47, 1.40, front + 0.035), Vector3(0.12, 2.56, 0.12), _steel)
		_box(building, Vector3(side * size.x * 0.31, 1.55, front + 0.06), Vector3(size.x * 0.24, 0.78, 0.15), _steel)
		_box(building, Vector3(side * size.x * 0.31, 1.55, front + 0.145), Vector3(size.x * 0.21, 0.64, 0.035), _glass)
		_box(building, Vector3(side * size.x * 0.31, 1.55, front + 0.17), Vector3(0.032, 0.64, 0.035), _steel)
		_box(building, Vector3(side * size.x * 0.39, 2.36, front + 0.12), Vector3(0.31, 0.18, 0.16), _steel)
		_box(building, Vector3(side * size.x * 0.39, 2.36, front + 0.205), Vector3(0.24, 0.093, 0.035), _lamp)
	_box(building, Vector3(0, 1.19, front + 0.045), Vector3(1.15, 2.20, 0.15), _steel)
	_box(building, Vector3(0, 1.18, front + 0.132), Vector3(1.02, 2.03, 0.04), _olive)
	_box(building, Vector3(0.38, 1.05, front + 0.17), Vector3(0.12, 0.038, 0.06), _steel)
	_box(building, Vector3(0, 2.48, front + 0.095), Vector3(1.52, 0.32, 0.14), _steel)
	_label(building, "FARPOST  /  09", Vector3(0, 2.48, front + 0.172), 0.132, Color("#e4d6b5"))
	_label(building, "RELAY", Vector3(0, 1.74, front + 0.155), 0.095, Color("#f1dfb7"))
	var canopy := _box(building, Vector3(0, 2.10, front + 0.24), Vector3(1.54, 0.08, 0.57), _roof)
	canopy.rotation.x = 0.11
	_box(building, Vector3(size.x * 0.22, height + 0.41, -size.z * 0.25), Vector3(0.72, 0.54, 0.62), _olive)
	for side in [-1.0, 1.0]:
		var wall: float = side * size.x * 0.5
		_box(building, Vector3(wall, 1.69, 0.27), Vector3(0.16, 0.65, 1.19), _steel)
		for slot in 6:
			_box(building, Vector3(wall + 0.095 * side, 1.44 + slot * 0.10, 0.27),
				Vector3(0.045, 0.042, 1.02), _olive)
		_beam(building, Vector3(wall, 0.46, front - 0.29), Vector3(wall, height, front - 0.29), 0.10, _steel)
		_box(building, Vector3(wall, 0.62, -front + 0.48), Vector3(0.32, 0.77, 0.54), _olive)
	_dish(building, Vector3(-size.x * 0.21, height + 0.16, -size.z * 0.14), 1.10)
	_mast(building, Vector3(size.x * 0.27, height + 0.12, 0.0), 3.35)
	return building


func dress_landscape(occupied: Array[Rect2]) -> void:
	_place_cliffs()
	_scatter_firs()
	_scatter_floor(occupied)
	_border()
	_dress_banks()
	for point: Vector2 in [Vector2(-0.78, -0.59), Vector2(0.82, 0.51), Vector2(-0.80, 0.18), Vector2(0.78, -0.5)]:
		var stump := fitted_model(STUMP, Vector3(0.65, 0.37, 0.61))
		stump.position = _terrain.position_at(point * _half, -0.055)
		stump.rotation.y = _rng.randf_range(0.0, TAU)
		_root.add_child(stump)
	for side in [-1.0, 1.0]:
		_waymarker(_terrain.position_at(Vector2(side * _half * 0.68, side * _half * 0.11)),
			"WEST DRAIN" if side < 0.0 else "EAST DRAIN", 0.18 * side)


func fitted_model(path: String, size: Vector3, mesh_name := StringName()) -> Node3D:
	if not _models.has(path):
		_models[path] = load(path)
	var model: Node3D = _models[path].instantiate()
	if not mesh_name.is_empty():
		var source := model.find_child(mesh_name, true, false) as MeshInstance3D
		var only_mesh := MeshInstance3D.new()
		only_mesh.mesh = source.mesh
		model.free()
		model = only_mesh
	var bounds := _model_bounds(model, Transform3D.IDENTITY)
	var root := Node3D.new()
	var pivot := Node3D.new()
	pivot.scale = size / bounds.size
	pivot.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * pivot.scale
	pivot.add_child(model)
	root.add_child(pivot)
	return root


func _model_bounds(node: Node3D, parent: Transform3D) -> AABB:
	var transform := parent * node.transform
	var bounds: AABB = transform * node.get_aabb() if node is MeshInstance3D else AABB()
	for child in node.get_children():
		if child is Node3D:
			var child_bounds := _model_bounds(child, transform)
			if child_bounds.has_volume():
				bounds = bounds.merge(child_bounds) if bounds.has_volume() else child_bounds
	return bounds


func _place_cliffs() -> void:
	for site: Array in [
		[Vector2(-19, -_half - 33), Vector3(30, 11.2, 10.2), -0.20],
		[Vector2(4, -_half - 37), Vector3(26, 8.4, 10.2), 0.31],
		[Vector2(-_half - 25, -7), Vector3(19, 6.6, 9.2), 1.30],
		[Vector2(_half + 23, 12), Vector3(21, 5.3, 8.7), -1.36],
	]:
		var cliff := fitted_model(CLIFF, site[1])
		cliff.position = _terrain.position_at(site[0], -site[1].y * 0.59)
		cliff.rotation.y = site[2]
		_root.add_child(cliff)


func _scatter_firs() -> void:
	var tree_rng := RandomNumberGenerator.new()
	tree_rng.seed = 71831
	var meshes: Array[Mesh] = FIR_MESHES.build(tree_rng)
	var groups: Array[Dictionary] = [{}, {}, {}]
	for z in range(-ceili((_half + 57.0) / 4.6), ceili((_half + 57.0) / 4.6) + 1):
		for x in range(-ceili((_half + 57.0) / 4.6), ceili((_half + 57.0) / 4.6) + 1):
			var point := Vector2(x, z) * 4.6 + Vector2(_rng.randf_range(-1.9, 1.9), _rng.randf_range(-1.9, 1.9))
			var edge := maxf(absf(point.x), absf(point.y)) - _half
			if edge < 2.5 or edge > 56.0 or _rng.randf() < 0.29:
				continue
			var base: Vector3 = _terrain.position_at(point, -0.13)
			if base.y > 27.0 or (point.y < -_half and absf(point.x) < 10.0 and edge < 11.5):
				continue
			var height := _rng.randf_range(5.8, 12.8) * lerpf(1.0, 0.67, smoothstep(7.0, 24.0, base.y))
			var width := height * _rng.randf_range(0.72, 1.07)
			var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(width, height, width))
			_record(groups[posmod(x + z * 2, meshes.size())], point, Transform3D(basis, base))
	for variant in meshes.size():
		_draw_groups("Firs%d" % variant, meshes[variant], groups[variant], true)


func _scatter_floor(occupied: Array[Rect2]) -> void:
	var grass := _model_meshes("res://assets/arena_props/grass.glb")
	var stones := _model_meshes(FOREST + "rock/rock_moss_set_01_1k.gltf")
	var ferns := _model_meshes(FOREST + "fern/fern_02_1k.gltf")
	var breakup := FastNoiseLite.new()
	breakup.seed = 56
	breakup.frequency = 0.25
	_scatter("Grass", grass, roundi(_half * _half * 8.0), Vector2(0.91, 2.1), breakup, occupied)
	_scatter("Ferns", ferns, roundi(_half * 13.0), Vector2(0.68, 1.12), breakup, occupied)
	_scatter("LooseRock", stones, roundi(_half * 12.0), Vector2(0.12, 0.43), breakup, occupied)


func _scatter(label: String, meshes: Array[Mesh], count: int, sizes: Vector2,
		noise: FastNoiseLite, occupied: Array[Rect2]) -> void:
	var reach := _half + 8.0
	var groups: Array[Dictionary] = []
	for mesh in meshes:
		groups.append({})
	for attempt in count:
		var point := Vector2(_rng.randf_range(-reach, reach), _rng.randf_range(-reach, reach))
		var road: float = _terrain.path_weight(point)
		if _terrain.ditch_weight(point) > 0.46 or (road > 0.37 and _rng.randf() < 0.92):
			continue
		if noise.get_noise_2dv(point) < -0.12 and _rng.randf() < 0.85:
			continue
		var clear := true
		for area in occupied:
			if area.has_point(point):
				clear = false
				break
		if not clear:
			continue
		var size := _rng.randf_range(sizes.x, sizes.y) * lerpf(1.0, 0.57, road)
		var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
		_record(groups[attempt % meshes.size()], point, Transform3D(basis, _terrain.position_at(point, -0.021)))
	for index in meshes.size():
		_draw_groups(label + str(index), meshes[index], groups[index], false)


func _record(groups: Dictionary, point: Vector2, placement: Transform3D) -> void:
	var tile := Vector2i((point / 17.0).floor())
	if not groups.has(tile):
		groups[tile] = []
	groups[tile].append(placement)


func _draw_groups(label: String, mesh: Mesh, groups: Dictionary, shadows: bool) -> void:
	for tile: Vector2i in groups:
		var placements: Array = groups[tile]
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = mesh
		batch.instance_count = placements.size()
		for index in placements.size():
			batch.set_instance_transform(index, placements[index])
		var node := MultiMeshInstance3D.new()
		node.name = "%s_%d_%d" % [label, tile.x, tile.y]
		node.multimesh = batch
		if not shadows:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(node)


func _model_meshes(path: String) -> Array[Mesh]:
	var scene: Node = (load(path) as PackedScene).instantiate()
	var meshes: Array[Mesh] = []
	for instance: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		meshes.append(instance.mesh)
	scene.free()
	return meshes


func _border() -> void:
	var pitch := 2.9
	var segments := ceili(_half * 2.0 / pitch)
	for side in [-1.0, 1.0]:
		for along_x in [true, false]:
			var last := Vector3.ZERO
			for index in segments + 1:
				var along := lerpf(-_half, _half, float(index) / segments)
				var point := Vector2(along, side * _half) if along_x else Vector2(side * _half, along)
				var base: Vector3 = _terrain.position_at(point, -0.08)
				_box(_root, base + Vector3.UP * 0.83, Vector3(0.095, 1.85, 0.095), _steel)
				if index > 0:
					for height in [0.43, 1.23, 1.65]:
						var thickness := 0.032 if height < 1.6 else 0.049
						_beam(_root, last + Vector3.UP * height, base + Vector3.UP * height, thickness, _steel)
				last = base
			var marker := Vector2(0, side * _half) if along_x else Vector2(side * _half, 0)
			var at: Vector3 = _terrain.position_at(marker, 0.08)
			_box(_root, at + Vector3.UP * 1.03, Vector3(0.19, 2.25, 0.19), _orange)
			_box(_root, at + Vector3.UP * 2.18, Vector3(0.28, 0.15, 0.23), _lamp)


func _dress_banks() -> void:
	var stones := _model_meshes(FOREST + "rock/rock_moss_set_01_1k.gltf")
	var placements := {}
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			var a := Vector2(side * _half * 0.69, end * _half * 0.49)
			var b := Vector2(side * _half * 0.69, end * _half * 0.69)
			for section in 3:
				var t0 := section / 3.0
				var t1 := (section + 1.0) / 3.0
				var start: Vector3 = _terrain.position_at(a.lerp(b, t0))
				var finish: Vector3 = _terrain.position_at(a.lerp(b, t1))
				for course in [0.10, 0.25, 0.40]:
					_beam(_root, start + Vector3.UP * course, finish + Vector3.UP * course, 0.136, _wood)
				_box(_root, start + Vector3.UP * 0.21, Vector3(0.15, 0.67, 0.14), _wood)
			for stone in roundi(_half * 0.85):
				var point := a.lerp(b, _rng.randf())
				point.x -= side * _rng.randf_range(0.30, 0.9)
				point.y += _rng.randf_range(-0.4, 0.4)
				var scale := _rng.randf_range(0.28, 0.64)
				var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale)
				_record(placements, point, Transform3D(basis, _terrain.position_at(point, -0.09)))
	_draw_groups("DitchRiprap", stones[0], placements, false)


func _waymarker(at: Vector3, caption: String, yaw: float) -> void:
	var marker := Node3D.new()
	marker.position = at
	marker.rotation.y = yaw
	_root.add_child(marker)
	_box(marker, Vector3.UP * 0.64, Vector3(0.075, 1.38, 0.087), _steel)
	_box(marker, Vector3.UP * 1.19, Vector3(0.88, 0.26, 0.072), _orange)
	_label(marker, caption, Vector3(0, 1.19, 0.038), 0.097, Color("#242721"))


func _mast(parent: Node3D, base: Vector3, height: float) -> void:
	var legs := [Vector3(-0.23, 0, -0.21), Vector3(0.23, 0, -0.21), Vector3(0, 0, 0.24)]
	for leg in 3:
		var from: Vector3 = legs[leg]
		var to: Vector3 = legs[(leg + 1) % legs.size()]
		_beam(parent, base + from, base + Vector3.UP * height + from * 0.35, 0.044, _steel)
		for tier in 4:
			var start := float(tier) / 4.0
			var finish := float(tier + 1) / 4.0
			_beam(parent, base + Vector3.UP * height * start + from * lerpf(1.0, 0.35, start),
				base + Vector3.UP * height * finish + to * lerpf(1.0, 0.35, finish), 0.026, _steel)
	_box(parent, base + Vector3.UP * height, Vector3(0.13, 0.17, 0.13), _lamp)
	_box(parent, base + Vector3.UP * (height - 0.57), Vector3(0.90, 0.05, 0.05), _steel)
	for side in [-1.0, 1.0]:
		_box(parent, base + Vector3(side * 0.42, height - 0.53, 0), Vector3(0.10, 0.58, 0.08), _olive)


func _dish(parent: Node3D, base: Vector3, radius: float) -> void:
	_box(parent, base + Vector3.UP * 0.59, Vector3(0.17, 1.19, 0.17), _steel)
	var dish := Node3D.new()
	dish.position = base + Vector3.UP * 1.26
	dish.rotation_degrees = Vector3(-27, -23, 0)
	parent.add_child(dish)
	var face := SurfaceTool.new()
	face.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in 5:
		for panel in 40:
			for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1),
					Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				var radial := (ring + corner.x) / 5.0
				var angle := (panel + corner.y) * TAU / 40.0
				var edge := Vector2.from_angle(angle) * radial * radius
				face.set_normal(Vector3(-edge.x * 0.42, -edge.y * 0.62, 1).normalized())
				face.add_vertex(Vector3(edge.x, edge.y * 0.79, radial * radial * 0.31))
	var reflector := MeshInstance3D.new()
	reflector.mesh = face.commit()
	var dish_material := _olive.duplicate() as StandardMaterial3D
	dish_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	reflector.material_override = dish_material
	dish.add_child(reflector)
	for angle in [0.55, 2.64, 4.73]:
		_beam(dish, Vector3(cos(angle) * radius, sin(angle) * radius * 0.79, 0.30),
			Vector3(0, 0, 0.73), 0.034, _steel)
	_box(dish, Vector3(0, 0, 0.73), Vector3(0.15, 0.14, 0.24), _steel)


func _corrugated(tint: Color, repeat: float) -> StandardMaterial3D:
	var material := _paint(tint, 0.59)
	var prefix := ART + "metal/rusty_corrugated_iron_"
	material.albedo_texture = load(prefix + "diff_2k.jpg")
	material.normal_enabled = true
	material.normal_texture = load(prefix + "nor_gl_2k.jpg")
	material.roughness_texture = load(prefix + "arm_2k.jpg")
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	material.uv1_triplanar = true
	material.uv1_scale = Vector3.ONE * repeat
	return material


func _paint(tint: Color, metal: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.78
	material.metallic = metal
	return material


func _label(parent: Node3D, caption: String, at: Vector3, character_height: float, tint: Color) -> void:
	var label := Label3D.new()
	label.text = caption
	label.font_size = 64
	label.pixel_size = character_height / float(label.font_size)
	label.outline_size = 0
	label.modulate = tint
	label.shaded = true
	label.position = at
	parent.add_child(label)


func _box(parent: Node3D, at: Vector3, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	if not _mesh_cache.has(size):
		var mesh := BoxMesh.new()
		mesh.size = size
		_mesh_cache[size] = mesh
	node.mesh = _mesh_cache[size]
	node.position = at
	node.material_override = material
	parent.add_child(node)
	return node


func _beam(parent: Node3D, start: Vector3, finish: Vector3, thickness: float, material: StandardMaterial3D) -> void:
	var direction := finish - start
	var beam := _box(parent, start.lerp(finish, 0.5), Vector3(thickness, thickness, direction.length()), material)
	var up := Vector3.RIGHT if absf(direction.normalized().dot(Vector3.UP)) > 0.95 else Vector3.UP
	beam.basis = Basis.looking_at(direction, up)
