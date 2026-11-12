extends RefCounted

const PROP_DIRECTORY := "res://assets/arena_props/psx/"
const TEXTURE_SIZE := 64
const PATROL := [
	Vector2(-30, -25), Vector2(-15, -20), Vector2(0, -24), Vector2(15, -20),
	Vector2(30, -25), Vector2(30, 3.5), Vector2(30, 25), Vector2(15, 20),
	Vector2(0, 25), Vector2(-15, 20), Vector2(-30, 25), Vector2(-30, -3.5),
	Vector2(0, 10), Vector2(0, -10), Vector2(-13, 3), Vector2(11.3, 1.6),
]
const STARTS := [
	Vector2(-15, -26), Vector2(-11.9, -27.7), Vector2(-18.2, -28.7),
	Vector2(15, -26), Vector2(11.9, -27.7), Vector2(18.2, -28.7),
	Vector2(-28, -14.4), Vector2(28, -14.4), Vector2(-30.5, -27), Vector2(30.5, -27),
]

var _map: Node3D
var _scale: float
var _asphalt: StandardMaterial3D
var _concrete: StandardMaterial3D
var _green: StandardMaterial3D
var _red: StandardMaterial3D
var _yellow: StandardMaterial3D
var _roof: StandardMaterial3D
var _scenes: Dictionary[String, PackedScene] = {}
var _batches: Dictionary = {}
var _zone := 0


func _init(map: Node3D) -> void:
	_map = map


func build(width: float) -> Array[Transform3D]:
	_scale = width / 70.0
	_asphalt = _material(Color("#575655"), 0.21, 0.52, 71)
	_concrete = _material(Color("#a49b83"), 0.26, 0.48, 19, true)
	_green = _material(Color("#57645a"), 0.23, 0.58, 43)
	_red = _material(Color("#78493d"), 0.21, 0.52, 47)
	_yellow = _material(Color("#bd963f"), 0.17, 0.7, 53)
	_roof = _material(Color("#444b4a"), 0.23, 0.56, 61)

	_block(Vector3(0, -0.25, 0), Vector3(72, 0.5, 72), _asphalt)
	for side in [-1.0, 1.0]:
		_block(Vector3(side * 35.45, 2.05, 0), Vector3(0.9, 4.1, 72), _concrete)
		_block(Vector3(0, 2.05, side * 35.45), Vector3(70, 4.1, 0.9), _concrete)
	for side in [-1.0, 1.0]:
		_zone += 1
		_hall(side)
		_zone += 1
		_yard(side)
	_zone += 1
	_block(Vector3(0, 0.62, 0), Vector3(6, 1.24, 2.2), _green, "metal")
	_block(Vector3(0, 1.29, 0), Vector3(6.2, 0.1, 2.4), _yellow, "metal")
	_ground_lines()
	_flush_batches()
	if width < 40.0:
		_map._build_spawn_ring(width * 0.5 - 1.35)
	else:
		for start: Vector2 in STARTS:
			var point := _point(Vector3(start.x, 0.2, start.y))
			_map._initial_spawns.append(point)
			_map._initial_spawns.append(Vector3(-point.x, point.y, -point.z))
	_map._build_respawn_grid(4, width * 0.1, width * 0.5)
	for point: Vector2 in PATROL:
		_map._patrol.append(_point(Vector3(point.x, 0.2, point.y)))
	var supplies: Array[Transform3D] = []
	var west_supply := Vector2(-12.25, 3.5) if width < 40.0 else Vector2(-12.3, 4.5)
	var east_supply := Vector2(11.3, -4.55) if width < 40.0 else Vector2(12.3, -4.5)
	for point: Vector2 in [west_supply, east_supply, Vector2(6.2, -10),
			Vector2(-6.2, 10), Vector2(-26, -8.8), Vector2(26, 8.8)]:
		supplies.append(Transform3D(Basis.IDENTITY, _point(Vector3(point.x, 0, point.y))))
	return supplies


func _hall(side: float) -> void:
	var x := side * 15.0
	var face := _green if side < 0.0 else _red
	var name := "ЦЕХ 03" if side < 0.0 else "КОТЕЛЬНАЯ"
	var compact := _scale < 0.5
	for end in [-1.0, 1.0]:
		var gate_x: float = x + (0.0 if compact else side * end * 2.9)
		var gate_width := 7.0 if compact else 5.2
		var left := gate_x - gate_width * 0.5
		var right := gate_x + gate_width * 0.5
		var z: float = end * 13.0
		_wall(Vector3((x - 6.5 + left) * 0.5, 0, z), Vector3(left - x + 6.5, 4.1, 0.85), face)
		_wall(Vector3((x + 6.5 + right) * 0.5, 0, z), Vector3(x + 6.5 - right, 4.1, 0.85), face)
		_block(Vector3(gate_x, 3.34, z), Vector3(gate_width, 1.52, 0.85), _concrete)
		_visual_box(Vector3(gate_x, 0.024, z + end * 0.82), Vector3(gate_width, 0.012, 0.46), face)
		_sign(name, Vector3(gate_x, 3.43, z + end * 0.48), end)
	if compact:
		_block(Vector3(x, 1.04, -2.6), Vector3(3.35, 2.08, 1.0), face)
	_wall(Vector3(side * 21.5, 0, 0), Vector3(0.85, 4.1, 26), face)
	var inner_x := side * 8.5
	_wall(Vector3(inner_x, 0, -8.3), Vector3(0.85, 4.1, 9.4), face)
	_wall(Vector3(inner_x, 0, 8.3), Vector3(0.85, 4.1, 9.4), face)
	_block(Vector3(inner_x, 3.34, 0), Vector3(0.85, 1.52, 7.2), _concrete)
	_visual_box(Vector3(inner_x - side * 0.81, 0.024, 0), Vector3(0.44, 0.012, 7.1), face)
	_sign(name, Vector3(inner_x - side * 0.48, 3.39, 0), 1.0, -side * PI * 0.5)
	_block(Vector3(x, 4.26, 0), Vector3(14.1, 0.34, 27.2), _roof, "metal")
	_hall_fittings(x, side)

	if side < 0.0:
		_prop("SM_Lathe_1K62", Vector3(-18.75, 0, -5.0), Vector3(2.9, 1.45, 0.6), _green, 90)
		_prop("SM_Tool_Cabinet", Vector3(-19.2, 0, 6.2), Vector3(0.94, 1.29, 0.54), face, 90)
		_prop("SM_Drill_Press", Vector3(-11.2, 0, 7.2), Vector3(0.45, 1.95, 0.65), _green)
		_prop("SM_Control_Console", Vector3(-11.45, 0, -7.4), Vector3(1.2, 1.4, 0.63), face)
	else:
		_boiler_room()
	_block(Vector3(x + side * 2.7, 0.55, -1.3), Vector3(2.8, 1.1, 1.2), face, "metal")


func _boiler_room() -> void:
	var brick := _sample_material("T_Ind_BoilerBrick", _red, 0.52, 0.92)
	var floor := _sample_material("T_Ind_FloorWet", _asphalt, 0.62, 0.78)
	_visual_box(Vector3(21.05, 1.57, 0), Vector3(0.016, 3.12, 25.2), brick)
	_visual_box(Vector3(15, 0.012, 0), Vector3(11.9, 0.012, 24.8), floor)
	_prop("Furnace_Incinerator_Lit", Vector3(18.5, 0, -5.4), Vector3(1.752, 3.063, 2.126),
		_red, -90, "metal", Vector3(0.026, -0.018, 0.113))
	_prop("Boiler_FireTube_Rusted", Vector3(19, 0, 6), Vector3(2.2, 3.037, 4.8),
		_green, 0, "metal", Vector3(0, -0.019, 0.2))
	_prop("ElectricalPanel_Switchboard_Burnt", Vector3(10.6, 0, 8.7), Vector3(1.2, 3.0, 1.006),
		_green, 90, "metal", Vector3(0, 0, 0.597))
	var pipe_scene := _prop_scene("Pipe_Large_Straight_2m")
	if pipe_scene:
		for z in [-2.5, -0.5, 1.5, 3.5]:
			var pipe := pipe_scene.instantiate() as Node3D
			pipe.position = _point(Vector3(20.55, 3.65, z))
			pipe.rotation.y = PI * 0.5
			pipe.scale.x = _scale
			_map.add_child(pipe)


func _sample_material(name: String, fallback: StandardMaterial3D, repeat: float,
		roughness: float) -> StandardMaterial3D:
	var path := PROP_DIRECTORY + name + ".png"
	if not ResourceLoader.exists(path, "Texture2D"):
		return fallback
	var material := fallback.duplicate() as StandardMaterial3D
	material.albedo_texture = load(path) as Texture2D
	material.uv1_scale = Vector3.ONE * repeat
	material.roughness = roughness
	return material


func _hall_fittings(x: float, side: float) -> void:
	var diffuser := StandardMaterial3D.new()
	diffuser.albedo_color = Color("#e9ddb4") if side < 0.0 else Color("#cadcc2")
	diffuser.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for z in [-7.5, 7.5]:
		_visual_box(Vector3(x, 3.98, z), Vector3(13.1, 0.24, 0.40), _roof)
		_visual_box(Vector3(x, 3.83, z), Vector3(2.7, 0.08, 0.32), diffuser)
		var lamp := OmniLight3D.new()
		lamp.position = _point(Vector3(x, 3.69, z))
		lamp.light_color = diffuser.albedo_color
		lamp.light_energy = 1.05
		lamp.omni_range = maxf(6.0, 10.5 * _scale)
		_map.add_child(lamp)
	for z in [-9.0, -3.0, 3.0, 9.0]:
		_visual_box(Vector3(side * 21.95, 2.85, z), Vector3(0.13, 1.12, 3.25), _roof)
		for mullion in [-0.95, 0.0, 0.95]:
			_visual_box(Vector3(side * 22.03, 2.85, z + mullion), Vector3(0.15, 1.02, 0.13), _concrete)


func _yard(side: float) -> void:
	var z := side * 21.6
	if _scale < 0.5:
		_screen(Vector2(side * 29.8, 0.0), 4.5)
	else:
		_screen(Vector2(side * 27.0, -11.0), 4.9)
		_screen(Vector2(side * 30.1, 11.7), 4.9)
		for end in [-1.0, 1.0]:
			_screen(Vector2(side * 15.0, end * 22.4), 7.4)
	_prop("SM_Kiosk_Soyuzpechat" if side < 0.0 else "SM_Transformer_TP",
		Vector3(side * 6.8, 0, z), Vector3(2.5, 2.63, 1.9) if side < 0.0 else Vector3(2.9, 2.96, 2.5),
		_green, 180.0 if side < 0.0 else 0.0)
	_prop("SM_Concrete_Block_FBS", Vector3(side * 24.5, 0, side * 14.0),
		Vector3(2.4, 0.71, 0.6), _concrete, 90, "concrete")
	_prop("SM_Safety_Railing", Vector3(side * 25.5, 0, -side * 14.5),
		Vector3(2.14, 1.12, 0.14), _yellow)
	for offset in [-1.7, 1.7]:
		_prop("SM_Drum_Solvent", Vector3(side * 22.9, 0, z + offset),
			Vector3(0.6, 0.89, 0.6), _red)
	_block(Vector3(side * 26.8, 0.8, side * 4.6), Vector3(3.6, 1.6, 2.1), _green, "metal")
	_block(Vector3(side * 3.7, 0.75, -side * 16.3), Vector3(3.2, 1.5, 1.7), _concrete)


func _screen(point: Vector2, width: float) -> void:
	_block(Vector3(point.x, 1.06, point.y), Vector3(width, 2.12, 0.76), _concrete)
	_visual_box(Vector3(point.x, 2.1, point.y), Vector3(width + 0.14, 0.14, 0.82), _yellow)


func _wall(base: Vector3, size: Vector3, band: StandardMaterial3D) -> void:
	_block(base + Vector3.UP * size.y * 0.5, size, _concrete)
	var padding := 0.008 / _scale
	_visual_box(base + Vector3.UP * 0.525, Vector3(size.x + padding, 1.05, size.z + padding), band)


func _ground_lines() -> void:
	var markings := SurfaceTool.new()
	markings.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		for offset in [-21.0, -13.0, -5.0, 5.0, 13.0, 21.0]:
			var strip := BoxMesh.new()
			strip.size = _point(Vector3(0.2, 0.025, 3.4))
			markings.append_from(strip, 0, Transform3D(Basis.IDENTITY, _point(Vector3(side * 6.5, 0.015, offset))))
	var lines := MeshInstance3D.new()
	lines.mesh = markings.commit()
	lines.material_override = _yellow
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_map.add_child(lines)


func _prop(name: String, base: Vector3, source_size: Vector3, fallback: StandardMaterial3D,
		yaw: float = 0.0, surface: String = "metal", source_bottom: Vector3 = Vector3.ZERO) -> void:
	var point := _point(base)
	var scale := maxf(_scale, 0.58)
	var size := source_size * Vector3(scale, maxf(_scale, 0.83), scale)
	var center := point + Vector3.UP * size.y * 0.5
	var scene := _prop_scene(name)
	var visual: Node3D
	if scene:
		visual = scene.instantiate() as Node3D
		visual.scale = size / source_size
		visual.position = Vector3.DOWN * size.y * 0.5 - source_bottom * visual.scale
	var body: StaticBody3D = _map._add_box(center, size, fallback, yaw, surface, null, visual)
	var footprint := Vector2(size.z, size.x) if is_equal_approx(absf(yaw), 90.0) else Vector2(size.x, size.z)
	_map._occupied.append(_map._footprint(Vector2(center.x, center.z), footprint))
	if visual:
		body.set_meta(&"workshop_prop", name)


func _prop_scene(name: String) -> PackedScene:
	if not _scenes.has(name):
		var path := PROP_DIRECTORY + name + ".glb"
		var scene := load(path) as PackedScene if ResourceLoader.exists(path, "PackedScene") else null
		if scene:
			var preview := scene.instantiate()
			for child in preview.find_children("*", "MeshInstance3D", true, false):
				var mesh := child as MeshInstance3D
				for index in mesh.mesh.get_surface_count():
					var material := mesh.get_active_material(index) as StandardMaterial3D
					if material:
						material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			preview.free()
		_scenes[name] = scene
	return _scenes[name]


func _block(center: Vector3, size: Vector3, material: StandardMaterial3D, surface: String = "concrete") -> StaticBody3D:
	var world_center := _point(center)
	var world_size := _point(size)
	if center.y > 0.0 and center.y - size.y * 0.5 < 0.7:
		_map._occupied.append(_map._footprint(Vector2(world_center.x, world_center.z), Vector2(world_size.x, world_size.z)))
	return _map._add_box(world_center, world_size, material, 0.0, surface, _batch(material, true))


func _point(value: Vector3) -> Vector3:
	return value * Vector3(_scale, 1.0, _scale)


func _visual_box(center: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = _point(size)
	_batch(material, false).append_from(mesh, 0, Transform3D(Basis.IDENTITY, _point(center)))


func _batch(material: Material, shadows: bool) -> SurfaceTool:
	var key := [_zone, material, shadows]
	if not _batches.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(material)
		_batches[key] = surface
	return _batches[key]


func _flush_batches() -> void:
	for key: Array in _batches:
		var surface: SurfaceTool = _batches[key]
		var visual := MeshInstance3D.new()
		visual.mesh = surface.commit()
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if key[2] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_map.add_child(visual)
	_batches.clear()


func _sign(title: String, at: Vector3, side: float, yaw := 0.0) -> void:
	var label := Label3D.new()
	label.text = title
	label.font_size = 64
	label.pixel_size = 0.013 * maxf(0.44, _scale)
	label.modulate = Color("#d8c997")
	label.outline_modulate = Color("#302c24")
	label.outline_size = 7
	label.position = _point(at)
	label.rotation.y = PI if side < 0.0 else yaw
	_map.add_child(label)


func _material(tint: Color, contrast: float, repeat: float, seed: int,
		panel_lines: bool = false) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.14
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var image := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGB8)
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var shade := snappedf(noise.get_noise_2d(x, y) + rng.randf_range(-0.32, 0.32), 0.18)
			if panel_lines and (x == 0 or y == 0):
				shade -= 0.48
			image.set_pixel(x, y, tint.lightened(shade * contrast) if shade > 0.0 else tint.darkened(-shade * contrast))
	image.generate_mipmaps()
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * repeat
	material.roughness = 0.93
	return material
