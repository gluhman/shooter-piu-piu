extends RefCounted

const ROUTE_MARKING := preload("res://game/maps/procedural/route_marking.gd")

const Ladders := preload("res://game/maps/procedural/workshop_ladders.gd")
const FLOOR := preload("res://game/maps/procedural/workshop_floor.gdshader")
const ART := "res://game/maps/breakwater/art/"
const ROOF_TOP := 5.72
const HALL_X := 15.0
const HALL_HALF_WIDTH := 6.5
const HALL_HALF_DEPTH := 13.0
const WALL := 0.46

var _map: Node3D
var _scale: float
var _compact: bool
var _brick: StandardMaterial3D
var _slab: ORMMaterial3D
var _foundation: ORMMaterial3D
var _steel: ORMMaterial3D
var _oxide: ORMMaterial3D
var _blue: ORMMaterial3D
var _safety: ORMMaterial3D
var _deck: StandardMaterial3D
var _cardboard: ORMMaterial3D
var _tape: StandardMaterial3D
var _glass: StandardMaterial3D
var _ladders: Ladders
var _scenes: Dictionary[String, PackedScene] = {}
var _model_bounds: Dictionary[String, AABB] = {}
var _batches: Dictionary[Material, SurfaceTool] = {}


func _init(map: Node3D) -> void:
	_map = map


func build(width: float) -> Array[Transform3D]:
	_scale = width / 70.0
	_compact = width < 40.0
	_materials()
	_ladders = Ladders.new()
	_ladders.name = "WorkshopLadders"
	_map.add_child(_ladders)
	var ground := ShaderMaterial.new()
	ground.shader = FLOOR
	ground.set_shader_parameter("layout_scale", _scale)
	for kind in ["color", "normal", "orm"]:
		ground.set_shader_parameter("asphalt_" + kind, _texture("asphalt_01", kind))
		ground.set_shader_parameter("slab_" + kind, _texture("concrete_floor_worn_001", kind))
	_block(Vector3(0, -0.25, 0), Vector3(71.5, 0.5, 71.5), ground)
	for side in [-1.0, 1.0]:
		_block(Vector3(side * 35.4, 1.6, 0), Vector3(0.8, 3.2, 71.6), _foundation)
		_block(Vector3(0, 1.6, side * 35.4), Vector3(70, 3.2, 0.8), _foundation)
		_block(Vector3(side * 35.4, 5.25, 0), Vector3(0.55, 4.1, 71.6), _deck, "metal")
		_block(Vector3(0, 5.25, side * 35.4), Vector3(70, 4.1, 0.55), _deck, "metal")
		_hall(side)
		_yard(side)
	_skyline()
	_flush_batches()
	_build_spawns(width)
	var supplies: Array[Transform3D] = []
	for point: Vector3 in [Vector3(-12.0, 0, 0), Vector3(12.0, 0, 0),
			Vector3(-4.7, 0, -8.4), Vector3(4.7, 0, 8.4),
			Vector3(-29.6, 0, 12), Vector3(29.6, 0, -12)]:
		supplies.append(Transform3D(Basis.IDENTITY, _point(point)))
	return supplies


func _materials() -> void:
	_brick = _map._world_mat("bricks", Color("#c49b81"), 0.0, 0.64, 1.1, true)
	_foundation = load("res://game/maps/lighting/weathered_concrete.tres")
	_slab = _packed_material("concrete_floor_worn_001", Color("#c6c2b3"), 0.48)
	_steel = _packed_material("rusty_metal_sheet", Color("#707c80"), 0.8)
	_oxide = _packed_material("painted_metal_008", Color("#ca8768"), 0.72)
	_blue = _packed_material("painted_metal_006", Color("#8eaeb7"), 0.72)
	_safety = _packed_material("rusty_metal_03", Color("#ffbe41"), 1.05)
	_deck = _map._world_mat("corrugated", Color("#829091"), 0.55, 0.65, 1.0, true)
	_cardboard = _packed_material("concrete_floor_worn_001", Color("#d5a66f"), 1.7)
	_cardboard.normal_scale = 0.22
	_tape = StandardMaterial3D.new()
	_tape.albedo_color = Color("#c2a372")
	_tape.roughness = 0.7
	_glass = StandardMaterial3D.new()
	_glass.albedo_color = Color(0.48, 0.65, 0.69, 0.32)
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass.roughness = 0.25


func _texture(asset: String, kind: String) -> Texture2D:
	return load(ART + "materials/" + asset + "_" + kind + ".jpg") as Texture2D


func _packed_material(asset: String, tint: Color, frequency: float) -> ORMMaterial3D:
	var material := ORMMaterial3D.new()
	material.albedo_color = tint
	material.albedo_texture = _texture(asset, "color")
	material.normal_enabled = true
	material.normal_texture = _texture(asset, "normal")
	material.orm_texture = _texture(asset, "orm")
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * frequency
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material


func _hall(side: float) -> void:
	var x := HALL_X * side
	var accent := _blue if side < 0.0 else _oxide
	var name := "СКЛАД 03" if side < 0.0 else "МЕХАНИЧЕСКИЙ ЦЕХ"
	for end in [-1.0, 1.0]:
		var shift: float = 0.0 if _compact else end * 1.2
		_portal(Vector3(x, 0, end * HALL_HALF_DEPTH), 13.0, 7.3, shift, false)
		for jamb in [-1.0, 1.0]:
			_trim(Vector3(x + shift + jamb * 3.74, 1.52, end * 13.32), Vector3(0.18, 3.04, 0.25), accent)
		_trim(Vector3(x + shift, 3.13, end * 13.33), Vector3(7.68, 0.22, 0.25), accent)
		_sign(name, Vector3(x, 4.27, end * 13.32), 0.0 if end > 0.0 else PI)
	_portal(Vector3(side * 8.5, 0, 0), 26.0, 8.0, 0.0, true)
	_sign("ПРОХОД", Vector3(side * 8.19, 3.54, 0), -side * PI * 0.5)
	var outer_x := side * 21.5
	for bay in [-9.75, -3.25, 3.25, 9.75]:
		_window_bay(outer_x, bay)
	_block(Vector3(x, ROOF_TOP - 0.18, 0), Vector3(14.1, 0.36, 27.3), _deck, "metal")
	for end in [-1.0, 1.0]:
		_block(Vector3(x, ROOF_TOP + 0.38, end * 13.3), Vector3(14.0, 0.76, 0.26), _brick, "brick")
		_ladder(side, end * 6.5)
	_block(Vector3(side * 8.3, ROOF_TOP + 0.38, 0), Vector3(0.27, 0.76, 26.45), _brick, "brick")
	var gap := maxf(1.24 / _scale, 1.65)
	var stops := PackedFloat32Array([-13.3, -6.5 - gap * 0.5, -6.5 + gap * 0.5,
		6.5 - gap * 0.5, 6.5 + gap * 0.5, 13.3])
	for index in [0, 2, 4]:
		var start := stops[index]
		var finish := stops[index + 1]
		_block(Vector3(side * 21.93, ROOF_TOP + 0.38, (start + finish) * 0.5),
			Vector3(0.27, 0.76, finish - start), _brick, "brick")
	for z in [-9.5, 9.5]:
		_model("equipment_oxide" if side > 0.0 else "equipment_blue",
			Vector3(x + side * 1.4, ROOF_TOP, z), Vector3(2.35, 0.93, 2.1), 0.0, "metal")
	_roof_monitor(x, accent)
	_hall_ceiling(x, side)
	_fit_hall(x, side, accent)


func _portal(center: Vector3, span: float, opening: float, shift: float, across_z: bool) -> void:
	var left := (span - opening) * 0.5 + shift
	var right := span - opening - left
	_wall_strip(center, -span * 0.5 + left * 0.5, left, 0.0, 5.36, across_z, _brick)
	_wall_strip(center, span * 0.5 - right * 0.5, right, 0.0, 5.36, across_z, _brick)
	_wall_strip(center, shift, opening, 3.0, 2.36, across_z, _brick)


func _wall_strip(center: Vector3, offset: float, width: float, bottom: float, height: float,
		across_z: bool, material: Material) -> void:
	var axis := Vector3.BACK if across_z else Vector3.RIGHT
	var size := Vector3(WALL, height, width) if across_z else Vector3(width, height, WALL)
	_block(center + axis * offset + Vector3.UP * (bottom + height * 0.5), size, material, "brick")


func _window_bay(x: float, z: float) -> void:
	var center := Vector3(x, 0, z)
	_wall_strip(center, 0, 6.5, 0, 3.35, true, _brick)
	_wall_strip(center, 0, 6.5, 4.82, 0.54, true, _brick)
	for side in [-1.0, 1.0]:
		_wall_strip(center, side * 2.54, 1.42, 3.35, 1.47, true, _brick)
	_trim(Vector3(x, 3.34, z), Vector3(0.61, 0.13, 3.7), _slab)
	_model("factory_window", Vector3(x, 3.36, z), Vector3(3.68, 1.46, 0.13), 90.0, "", false)
	var pane := _block(Vector3(x, 4.085, z), Vector3(0.07 / _scale, 1.43, 3.58), _glass, "metal")
	pane.name = "Clerestory"


func _ladder(side: float, z: float) -> void:
	var outward := Vector3.RIGHT * side
	var rail_x := side * (22.05 + 0.10 / _scale)
	var clear_bottom := Vector3(side * (22.05 * _scale + 0.61), 0.06, z * _scale)
	var landing := Vector3(side * (22.05 * _scale - 1.03), ROOF_TOP + 0.05, z * _scale)
	_ladders.add_ladder(clear_bottom, landing, outward)
	for rail in [-1.0, 1.0]:
		var rail_z: float = z + rail * 0.37 / _scale
		_trim(Vector3(rail_x, (ROOF_TOP + 0.67) * 0.5, rail_z),
			Vector3(0.085 / _scale, ROOF_TOP + 0.67, 0.085 / _scale), _safety)
		for y in [0.48, 2.5, 4.58]:
			_trim(Vector3((rail_x + side * 21.65) * 0.5, y, rail_z),
				Vector3(absf(rail_x - side * 21.65), 0.09, 0.12 / _scale), _steel)
	for step in 19:
		_trim(Vector3(rail_x, 0.28 + step * 0.29, z),
			Vector3(0.08 / _scale, 0.04, 0.76 / _scale), _steel)
	_trim(Vector3(side * 21.43, ROOF_TOP + 0.015, z), Vector3(1.25 / _scale, 0.025, 1.05 / _scale), _safety)


func _roof_monitor(x: float, accent: Material) -> void:
	_block(Vector3(x, ROOF_TOP + 0.53, 0), Vector3(3.2, 1.06, 7.7), accent, "metal")
	_block(Vector3(x, ROOF_TOP + 1.11, 0), Vector3(3.6, 0.16, 8.1), _deck, "metal")
	for side in [-1.0, 1.0]:
		for z in [-2.48, 0.0, 2.48]:
			_model("factory_window", Vector3(x + side * 1.69, ROOF_TOP + 0.28, z),
				Vector3(2.14, 0.63, 0.07), 90.0, "", false)


func _hall_ceiling(x: float, side: float) -> void:
	for z in [-9.0, -3.0, 3.0, 9.0]:
		_trim(Vector3(x, 5.18, z), Vector3(12.7, 0.25, 0.24), _steel)
		for offset in [-5.8, 5.8]:
			_trim(Vector3(x + offset, 2.68, z), Vector3(0.18, 5.34, 0.19), _steel)
		_model("hall_pendant", Vector3(x, 3.93, z), Vector3(0.8, 1.30, 0.8), 0, "", false)
		var lamp := OmniLight3D.new()
		lamp.position = _point(Vector3(x, 3.8, z))
		lamp.light_intensity_lumens = 48000.0
		lamp.light_temperature = 4200.0 if side < 0.0 else 5000.0
		lamp.omni_range = maxf(5.1, 9.5 * _scale)
		_map.add_child(lamp)
	_wall_pipes(side)


func _wall_pipes(side: float) -> void:
	var wall := side * 21.27
	var x := wall - side * 0.26 / _scale
	var support_x := (x + wall) * 0.5
	var support_span := 0.39 / _scale
	var height := 4.93
	var end := 6.5
	_pipe(Vector3(x, height, -end), Vector3(x, height, end), 0.11, _oxide)
	for z in [-4.8, -1.65, 1.65, 4.8]:
		_trim(Vector3(support_x, height - 0.12, z),
			Vector3(support_span, 0.10, 0.21 / _scale), _steel)
		_pipe(Vector3(x, height, z - 0.065 / _scale),
			Vector3(x, height, z + 0.065 / _scale), 0.15, _steel)
	for z in [-end, end]:
		_pipe(Vector3(x, 0.12, z), Vector3(x, height, z), 0.11, _oxide)
		_pipe(Vector3(x, height - 0.16, z), Vector3(x, height + 0.045, z), 0.155, _steel)
		_trim(Vector3(x, 0.063, z), Vector3(0.36 / _scale, 0.126, 0.36 / _scale), _steel)
		for y in [0.72, 2.62]:
			_trim(Vector3(support_x, y, z), Vector3(support_span, 0.13, 0.18 / _scale), _steel)
		_pipe(Vector3(x, 1.27, z), Vector3(x, 1.66, z), 0.19, _steel)
		var wheel_x := x - side * 0.28 / _scale
		_pipe(Vector3(x, 1.46, z), Vector3(wheel_x, 1.46, z), 0.062, _steel)
		var wheel := TorusMesh.new()
		wheel.inner_radius = 0.122
		wheel.outer_radius = 0.16
		wheel.rings = 18
		wheel.ring_segments = 8
		_batch(_safety).append_from(wheel, 0,
			Transform3D(Basis(Vector3.BACK, PI * 0.5), _point(Vector3(wheel_x, 1.46, z))))
		_pipe(Vector3(wheel_x, 1.315, z), Vector3(wheel_x, 1.605, z), 0.019, _safety)
		_pipe(Vector3(wheel_x, 1.46, z - 0.145 / _scale),
			Vector3(wheel_x, 1.46, z + 0.145 / _scale), 0.019, _safety)


func _pipe(from: Vector3, to: Vector3, radius: float, material: Material) -> void:
	var start := _point(from)
	var finish := _point(to)
	var run := finish - start
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = run.length()
	mesh.radial_segments = 14
	_batch(material).append_from(mesh, 0,
		Transform3D(Basis(Quaternion(Vector3.UP, run.normalized())), (start + finish) * 0.5))


func _fit_hall(x: float, side: float, accent: Material) -> void:
	if side < 0.0:
		for z in [-8.25, 8.25]:
			_rack(Vector3(x - 2.75, 0, z), accent)
			if not _compact:
				_rack(Vector3(x + 2.65, 0, z + 1.25), accent)
		if not _compact:
			_rack(Vector3(x - 2.75, 0, 0), accent)
			_model("pallet_jack", Vector3(x + 4.65, 0, -10.95), Vector3(1.53, 1.22, 0.62), 90, "metal")
	else:
		_model("turbine_assembly", Vector3(x + 2.3, 0, -6.75), Vector3(4.5, 2.56, 4.5), 0, "metal")
		_model("hall_switchgear", Vector3(x + 4.7, 0, 4.8), Vector3(1.3, 1.87, 0.65), 90, "metal")
		_rack(Vector3(x - 2.65, 0, 7.7), accent)
		if not _compact:
			_model("equipment_blue", Vector3(x + 3.0, 0, -0.8), Vector3(2.25, 1.2, 1.65), 0, "metal")
			_workbench(Vector3(x + 4.8, 0, 1.8))


func _workbench(at: Vector3) -> void:
	_block(at + Vector3.UP * 0.98, Vector3(1.15, 0.13, 3.15), _steel, "metal")
	for z in [-1.19, 1.19]:
		_block(at + Vector3(0, 0.455, z), Vector3(0.88, 0.91, 0.46), _oxide, "metal")
	_model("plastic_crate_02", at + Vector3(0, 1.045, -0.83), Vector3(0.65, 0.30, 0.56), 90, "metal")
	_carton(at + Vector3(0, 1.045, 0.9), Vector3(0.53, 0.33, 0.58))


func _rack(at: Vector3, accent: Material) -> void:
	for x in [-0.89, 0.89]:
		for z in [-2.38, 2.38]:
			_trim(at + Vector3(x, 1.72, z), Vector3(0.13, 3.44, 0.13), _steel)
	for level in 4:
		var shelf := 0.12 + level * 0.88
		_block(at + Vector3(0, shelf, 0), Vector3(1.84, 0.11, 4.9), accent, "metal")
		for slot in 4:
			if (level * 3 + slot * 2) % 7 == 3:
				continue
			var position := at + Vector3(0, shelf + 0.055, -1.74 + slot * 1.16)
			if (level + slot) % 4 == 0:
				_model("wooden_crate_01", position, Vector3(1.24, 0.63, 0.94), 0, "wood")
			elif (level + slot) % 4 == 1:
				_model("plastic_crate_02", position, Vector3(1.23, 0.45, 0.94), 0, "metal")
			else:
				_carton(position, Vector3(1.32, 0.62 - 0.10 * (slot % 2), 0.91))


func _carton(at: Vector3, size: Vector3) -> void:
	var body := _block(at + Vector3.UP * size.y * 0.5, size, _cardboard, "wood")
	body.set_meta(&"ballistic_size", _point(size))
	body.set_meta(&"ballistic_resistance", 0.30)
	_trim(at + Vector3.UP * (size.y + 0.006), Vector3(size.x * 0.16, 0.012, size.z), _tape)
	for side in [-1.0, 1.0]:
		_trim(at + Vector3(0, size.y * 0.75, side * (size.z * 0.5 + 0.009)),
			Vector3(size.x * 0.16, size.y * 0.5, 0.016), _tape)


func _yard(side: float) -> void:
	for screen: Vector2 in [Vector2(8.5, 10.4), Vector2(24.1, 9.0)]:
		_block(Vector3(side * screen.x, 1.15, side * 21.4), Vector3(screen.y, 2.3, 0.82), _brick, "brick")
		_trim(Vector3(side * screen.x, 2.34, side * 21.4), Vector3(screen.y + 0.2, 0.12, 0.92), _slab)
	_model("container_oxide" if side > 0.0 else "container_blue",
		Vector3(side * 28.4, 0, side * 4.4), Vector3(3.5, 2.64, 10.0), 0, "metal")
	_model("concrete_road_barrier", Vector3(side * 25.9, 0, -side * 12.6),
		Vector3(3.6, 0.95, 1.3), 0, "concrete")
	for z in [-15.8, -15.8 - maxf(1.8, 0.92 / _scale)]:
		_model("barrel_03", Vector3(side * 26.9, 0, side * z),
			Vector3(0.78 / _scale, 0.96, 0.77 / _scale), 0, "metal")
	_model("wooden_crate_01", Vector3(side * 26.2, 0, side * 15.8),
		Vector3(2.2, 1.04, 2.2), 0, "wood")
	_model("plastic_crate_02", Vector3(side * 26.2, 1.04, side * 15.8),
		Vector3(1.44, 0.46, 1.34), 0, "metal")
	var shelter := Vector3(side * 27.5, 0, side * 19.0)
	_block(shelter + Vector3(0, 2.35, 0), Vector3(5.35, 0.20, 4.0), _deck, "metal")
	_block(shelter + Vector3(side * 2.52, 1.13, 0), Vector3(0.30, 2.26, 4.0), _brick, "brick")
	_block(shelter + Vector3(-side * 2.48, 1.13, side * 1.8), Vector3(0.27, 2.26, 0.31), _steel, "metal")
	# Offset cover in the central lane so both hall crossings remain open.
	_model("equipment_oxide" if side > 0.0 else "equipment_blue",
		Vector3(side * 2.9, 0, side * 5.1), Vector3(3.1, 1.36, 3.1), 12.0, "metal")
	ROUTE_MARKING.paint(_map, "FABRICATION" if side > 0.0 else "DISPATCH",
		_point(Vector3(side * 5.55, 0.008, side * 3.8)),
		Color("#e5b978") if side > 0.0 else Color("#a6cfdd"), PI if side > 0.0 else 0.0,
		2.5 * maxf(0.64, _scale))
	if not _compact:
		var freight := Vector3(side * 8.75, 0, side * 17.6)
		_model("wooden_crate_01", freight, Vector3(1.85, 0.98, 1.62), 0, "wood")
		_carton(freight + Vector3(0.21, 0.98, 0.09), Vector3(0.85, 0.54, 0.85))
		_carton(freight + Vector3(side * 1.55, 0, 0.7), Vector3(0.75, 0.59, 0.9))
		_model("pallet_jack", freight + Vector3(side * 2.55, 0, -side * 0.5),
			Vector3(1.53, 1.22, 0.62), 90, "metal")


func _skyline() -> void:
	for side in [-1.0, 1.0]:
		for index in 3:
			var x := -24.0 + index * 23.0
			var height := 8.4 + float(index % 2) * 1.8
			var z: float = side * (44.0 + float(index % 2) * 5.5)
			_trim(Vector3(x, height * 0.5, z), Vector3(18.0, height, 10.0), _brick)
			_trim(Vector3(x, height + 0.14, z), Vector3(19.1, 0.28, 10.8), _deck)
			_trim(Vector3(x + 3.5, height + 0.7, z + side * 2.0), Vector3(4.5, 1.2, 2.5), _steel)
		_trim(Vector3(side * 47.0, 5.4, -side * 17), Vector3(13, 10.8, 18), _slab)
		_trim(Vector3(side * 46.5, 8.4, -side * 18.0), Vector3(2.35, 16.8, 2.35), _oxide)


func _build_spawns(width: float) -> void:
	for z in [-30.4, -26.0]:
		for x in [-29.0, -23.1, -17.2, -11.3, -5.4]:
			var spawn := _point(Vector3(x, 0.18, z))
			_map._initial_spawns.append(spawn)
			_map._initial_spawns.append(Vector3(-spawn.x, spawn.y, -spawn.z))
	_map._build_respawn_grid(4, width * 0.1, width * 0.5)
	for point: Vector3 in [Vector3(-16, 0.15, -19), Vector3(0, 0.15, -16.2),
			Vector3(16, 0.15, 19), Vector3(0, 0.15, 16.2), Vector3(-15, 0.15, 0),
			Vector3(15, 0.15, 0), Vector3(0, 0.15, 0)]:
		_map._patrol.append(_point(point))


func _model(name: String, at: Vector3, size: Vector3, yaw: float, surface: String,
		solid := true) -> void:
	if not _scenes.has(name):
		var extension := ".tscn" if name.begins_with("container_") or name.begins_with("equipment_") or name == "turbine_assembly" else ".glb"
		var directory := "res://assets/arena_props/workshop/" if name == "pallet_jack" else ART + "models/"
		_scenes[name] = load(directory + name + extension) as PackedScene
	var visual := _scenes[name].instantiate() as Node3D
	if not _model_bounds.has(name):
		_model_bounds[name] = _bounds_of(visual)
	var bounds := _model_bounds[name]
	var world_size := _point(size)
	visual.scale = world_size / bounds.size
	var center := _point(at) + Vector3.UP * world_size.y * 0.5
	visual.position = -bounds.get_center() * visual.scale
	if not solid:
		visual.position = center + visual.position.rotated(Vector3.UP, deg_to_rad(yaw))
		visual.rotation.y = deg_to_rad(yaw)
		_map.add_child(visual)
		return
	var body: StaticBody3D = _map._add_box(center, world_size, null, yaw, surface, null, visual)
	body.set_meta(&"workshop_prop", name)
	if surface == "wood":
		body.set_meta(&"ballistic_size", world_size)
		body.set_meta(&"ballistic_resistance", 0.30)
	if at.y < 0.72:
		var angle := deg_to_rad(yaw)
		var footprint := Vector2(world_size.x * absf(cos(angle)) + world_size.z * absf(sin(angle)),
			world_size.x * absf(sin(angle)) + world_size.z * absf(cos(angle)))
		_map._occupied.append(_map._footprint(Vector2(center.x, center.z), footprint))


func _bounds_of(model: Node3D) -> AABB:
	var bounds := AABB()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var transform := mesh.transform
		var node := mesh.get_parent() as Node3D
		while node != model:
			transform = node.transform * transform
			node = node.get_parent() as Node3D
		var box := transform * mesh.get_aabb()
		bounds = bounds.merge(box) if bounds.has_volume() else box
	return bounds


func _point(value: Vector3) -> Vector3:
	return value * Vector3(_scale, 1, _scale)


func _block(at: Vector3, size: Vector3, material: Material, surface := "concrete") -> StaticBody3D:
	var center := _point(at)
	var world_size := _point(size)
	if at.y > 0.0 and at.y - size.y * 0.5 < 0.72:
		_map._occupied.append(_map._footprint(Vector2(center.x, center.z), Vector2(world_size.x, world_size.z)))
	return _map._add_box(center, world_size, material, 0, surface, _batch(material))


func _trim(at: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = _point(size)
	_batch(material).append_from(mesh, 0, Transform3D(Basis.IDENTITY, _point(at)))


func _batch(material: Material) -> SurfaceTool:
	if not _batches.has(material):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(material)
		_batches[material] = surface
	return _batches[material]


func _flush_batches() -> void:
	for material in _batches:
		var visual := MeshInstance3D.new()
		visual.mesh = _batches[material].commit()
		visual.material_override = material
		_map.add_child(visual)


func _sign(title: String, at: Vector3, yaw: float) -> void:
	var label := Label3D.new()
	label.text = title
	label.font_size = 64
	label.pixel_size = 0.01 * maxf(0.48, _scale)
	label.modulate = Color("#eadbb8")
	label.outline_modulate = Color("#261e18")
	label.outline_size = 8
	label.position = _point(at)
	label.rotation.y = yaw
	_map.add_child(label)
