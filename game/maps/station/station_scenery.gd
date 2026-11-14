extends RefCounted

const ART := "res://game/maps/station/art/"
const DECK_SHADER := preload("station_deck.gdshader")
const HEIGHTFIELD := preload("../forest_ridge/art/gdt/terrain_heightfield.gd")
const TERRAIN_MESH := preload("../forest_ridge/art/gdt/terrain_mesh_builder.gd")
const HORIZON_SHADER := preload("station_horizon.gdshader")
const AMBER := Color("#ffd49a")
const ICE := Color("#a9e8ff")
const ROOM_NAMES := ["CARGO CONTROL", "POWER SYSTEMS", "OBSERVATION LAB"]
const ROOM_TINTS := [Color("#ffab58"), Color("#6cd7ff"), Color("#ff668f")]
const MODEL_PARTS := {
	"power": ["power_box_01", ""],
	"tool": ["metal_tool_chest", ""],
	"duct": ["modular_airduct_rectangular_01", "modular_airduct_rectangular_01_single_01"],
	"sconce": ["industrial_caged_sconce", "industrial_caged_sconce_a"],
}

var _root: Node3D
var _half: float
var _inner: float
var _rise: float
var _roof: float
var _module: float
var _deck := ShaderMaterial.new()
var _panel: StandardMaterial3D
var _room_lamps: Array[StandardMaterial3D] = []
var _dark := _paint(Color("#172734"), 0.50)
var _edge := _paint(Color("#536473"), 0.45)
var _cream := _paint(Color("#a2aeb3"), 0.35)
var _screen := _paint(Color("#152c37"), 0.26)
var _amber := _paint(Color("#c28139"), 0.34)
var _rubber := _paint(Color("#121b20"), 0.11)
var _white_light := _glowing(Color("#d5edff"), 0.46)
var _cyan_light := _glowing(Color("#55d9ff"), 0.60)
var _warm_light := _glowing(Color("#ffc275"), 0.46)
var _green_light := _glowing(Color("#69ffbf"), 0.58)
var _models: Dictionary = {}
var _batches: Dictionary = {}


func _init(root: Node3D, half_width: float, inner: float, rise: float, roof: float) -> void:
	_root = root
	_half = half_width
	_inner = inner
	_rise = rise
	_roof = roof
	_module = _half * 2.0 / float(ceili(_half * 2.0 / 4.0))
	for tint: Color in ROOM_TINTS:
		_room_lamps.append(_glowing(tint, 0.72))
	_deck.shader = DECK_SHADER
	_deck.set_shader_parameter("steel_diff", _texture("metal_plate", "diff"))
	_deck.set_shader_parameter("steel_normal", _texture("metal_plate", "nor_gl"))
	_deck.set_shader_parameter("steel_rough", _texture("metal_plate", "rough"))
	_panel = _paint(Color("#bed1da"), 0.29)
	_panel.albedo_texture = _texture("blue_metal_plate", "diff")
	_panel.normal_enabled = true
	_panel.normal_texture = _texture("blue_metal_plate", "nor_gl")
	_panel.normal_scale = 0.65
	_panel.roughness_texture = _texture("blue_metal_plate", "rough")
	_panel.uv1_triplanar = true
	_panel.uv1_scale = Vector3.ONE * 0.62


func fixture(center: Vector3, size: Vector3, kind: String) -> void:
	match kind:
		"deck":
			_box(center, size, _deck)
		"core":
			_core(center)
		"locker":
			_locker(center, size)
		"partition":
			_partition(center, size)
		"cargo":
			_cargo(center, size)
		"console":
			_console(center, size)
		_:
			var yaw := 0.0 if center.z > 0.0 else PI
			if kind == "power":
				yaw = -PI * 0.5 if center.x > 0.0 else PI * 0.5
			_fit_model(kind, center - Vector3.UP * size.y * 0.5, size, yaw)


func stairs(low: Vector3, high: Vector3, width: float, count: int) -> void:
	var run := absf(high.z - low.z) / count
	var rise := (high.y - low.y) / count
	var direction := signf(high.z - low.z)
	for index in count:
		var step := low.lerp(high, (index + 0.5) / count)
		step.y = low.y + (index + 1) * rise
		_box(step - Vector3.UP * (rise + 0.045) * 0.5, Vector3(width, rise + 0.045, run), _deck)
		_box(step + Vector3(0, 0.020, -direction * (run * 0.5 - 0.027)),
			Vector3(width - 0.13, 0.017, 0.051), _edge)
		if index % 4 == 0:
			_box(step + Vector3(0, -0.077, -direction * (run * 0.5 + 0.006)),
				Vector3(width * 0.64, 0.027, 0.023), _warm_light)
	var basis := Basis.looking_at(high - low)
	_box(low.lerp(high, 0.5) - basis.y * 0.15, Vector3(width - 0.17, 0.19, low.distance_to(high)), _dark, basis)


func railing(start: Vector3, finish: Vector3) -> void:
	for height in [0.11, 0.52, 0.93]:
		_beam(start + Vector3.UP * height, finish + Vector3.UP * height, 0.064 if height > 0.9 else 0.033,
			_amber if height > 0.9 else _edge)
	var posts := maxi(1, ceili(start.distance_to(finish) / 1.48))
	for index in posts + 1:
		var at := start.lerp(finish, float(index) / posts)
		_box(at + Vector3.UP * 0.46, Vector3(0.057, 0.92, 0.057), _edge)


func finish(ramp_x: float, ramp_width: float) -> void:
	_exterior()
	_pressure_walls()
	_roof_structure()
	_machinery_and_signs(ramp_x, ramp_width)
	_lighting()
	_flush_boxes()


func _pressure_walls() -> void:
	var bays := roundi(_half * 2.0 / _module)
	for wall in 4:
		var rotation := Basis(Vector3.UP, wall * PI * 0.5)
		for deck in 3:
			var base := deck * _rise
			var ceiling := _rise if deck < 2 else _roof - base
			for bay in bays:
				var x := -_half + (bay + 0.5) * _module
				var window := (wall % 2 == 1 and (deck > 0 or bay % 3 != 0)) or (deck == 2 and bay % 3 == 1)
				_wall_bay(rotation, x, base, ceiling, window, bay)
			if wall % 2 == 0:
				_wall_sign(rotation, base, deck)


func _wall_bay(rotation: Basis, x: float, base: float, height: float, window: bool, bay: int) -> void:
	var z := -_half
	var w := _module
	_box(rotation * Vector3(x - w * 0.5 + 0.11, base + height * 0.5, z + 0.18),
		Vector3(0.24, height, 0.40), _dark, rotation)
	_box(rotation * Vector3(x - w * 0.5 + 0.17, base + height * 0.62, z + 0.40),
		Vector3(0.064, 0.80, 0.018), _cyan_light if window else _warm_light, rotation)
	if window:
		var lower := 0.78
		var upper := 0.68
		_box(rotation * Vector3(x, base + lower * 0.5, z + 0.04), Vector3(w, lower, 0.23), _panel, rotation)
		_box(rotation * Vector3(x, base + height - upper * 0.5, z + 0.04), Vector3(w, upper, 0.23), _panel, rotation)
		for y in [lower, height - upper]:
			_box(rotation * Vector3(x, base + y, z + 0.20), Vector3(w - 0.22, 0.12, 0.34), _edge, rotation)
		_box(rotation * Vector3(x, base + lower + 0.095, z + 0.374), Vector3(w - 0.48, 0.022, 0.025), _cyan_light, rotation)
	else:
		_box(rotation * Vector3(x, base + height * 0.5, z), Vector3(w, height, 0.21), _panel, rotation)
		_box(rotation * Vector3(x, base + 1.24, z + 0.12), Vector3(w - 0.62, 1.72, 0.15), _dark, rotation)
		_box(rotation * Vector3(x, base + 1.24, z + 0.21), Vector3(w - 0.86, 1.53, 0.12), _panel, rotation)
		_box(rotation * Vector3(x, base + 0.36, z + 0.27), Vector3(w - 0.95, 0.036, 0.02), _amber, rotation)
		for line in 5:
			_box(rotation * Vector3(x + w * 0.21, base + 0.68 + line * 0.075, z + 0.28),
				Vector3(0.48, 0.026, 0.024), _rubber, rotation)
		if bay % 3 == 2:
			_fit_model("sconce", rotation * Vector3(x + w * 0.30, base + 2.26, z + 0.26),
				Vector3(0.25, 0.44, 0.20), rotation.get_euler().y)


func _wall_sign(rotation: Basis, base: float, deck: int) -> void:
	var names := ["TRANSIT HALL", "SERVICE GALLERY", "OBSERVATION"]
	var label_point := rotation * Vector3(0, base + 2.64, -_half + 0.31)
	_box(label_point - rotation.z * 0.045, Vector3(3.24, 0.43, 0.15), _rubber, rotation)
	_label("%02d  /  %s" % [deck, names[deck]], label_point + rotation.z * 0.04, rotation,
		0.176, Color("#dbebee") if deck == 2 else Color("#ffe0a6"))


func _roof_structure() -> void:
	_box(Vector3(0, _roof + 0.18, 0), Vector3(_half * 2.0, 0.34, _half * 2.0), _dark)
	var sections := ceili(_half * 2.0 / 6.3)
	for index in sections:
		var z := lerpf(-_half, _half, (index + 0.5) / sections)
		_box(Vector3(0, _roof - 0.25, z), Vector3(_half * 2.0, 0.54, 0.31), _edge)
		for side in [-1.0, 1.0]:
			_box(Vector3(side * _inner * 0.64, _roof - 0.61, z),
				Vector3(1.50, 0.14, 0.66), _dark)
			_box(Vector3(side * _inner * 0.64, _roof - 0.717, z),
				Vector3(1.33, 0.024, 0.48), _white_light)
			_beam(Vector3(side * _half, _roof - 1.75, z),
				Vector3(side * (_half - 1.62), _roof - 0.34, z), 0.24, _edge)
	_box(Vector3(0, _roof - 0.19, 0), Vector3(0.78, 0.31, _half * 2.0), _panel)
	for side in [-1.0, 1.0]:
		_fit_model("duct", Vector3(side * _inner * 0.89, _roof - 0.72, 0.0),
			Vector3(0.64, 0.43, _half * 1.43), PI * 0.5)
		for deck in [1, 2]:
			var rail_level: float = deck * _rise - 0.17
			_box(Vector3(0, rail_level, side * (_inner + 0.028)),
				Vector3(_half * 2.0, 0.31, 0.067), _edge)
			_box(Vector3(0, rail_level - 0.05, side * (_inner - 0.015)),
				Vector3(_inner * 2.0 - 0.30, 0.057, 0.027), _cyan_light)
			_box(Vector3(side * (_inner + 0.045), rail_level, 0),
				Vector3(0.035, 0.062, _inner * 2.0 - 0.2), _cyan_light)


func _machinery_and_signs(ramp_x: float, ramp_width: float) -> void:
	for side in [-1.0, 1.0]:
		for deck in 3:
			var y := deck * _rise
			var center_x: float = side * (_inner + _half) * 0.5
			for index in ceili(_inner / 2.35):
				var along := lerpf(-_inner, _inner, (index + 0.5) / ceili(_inner / 2.35))
				_box(Vector3(side * (_inner + 0.38), y + 0.009, along),
					Vector3(0.085, 0.012, 1.08), _amber)
			for end in [-1.0, 1.0]:
				var door_z: float = end * (_half - 0.28)
				var sign_basis := Basis(Vector3.UP, PI if end > 0.0 else 0.0)
				var at := Vector3(center_x, y + 2.02, door_z)
				_label("A  •  PORT" if side < 0.0 else "B  •  STARBOARD", at, sign_basis, 0.13, ICE)
				_box(Vector3(side * ramp_x, y + 0.013, end * (_inner + 0.48)),
					Vector3(ramp_width + 0.34, 0.018, 0.10), _amber)
		for z_side in [-1.0, 1.0]:
			var center := Vector3(side * (_inner + 1.50), 0.0, z_side * (_inner - 1.20))
			_box(center + Vector3.UP * 0.08, Vector3(0.70, 0.16, 1.72), _dark)
			_fit_model("duct", center + Vector3.UP * 0.16, Vector3(0.52, 0.48, 1.61), PI * 0.5)
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			var edge := Vector3(side * (_inner + 0.16), 0, end * (_inner + 0.16))
			for tier in [1, 2]:
				var top: Vector3 = edge + Vector3.UP * (tier * _rise - 0.18)
				_beam(top + Vector3(0, -1.05, end * 0.94), top, 0.20, _edge)
				_beam(top + Vector3(side * 0.94, -1.05, 0), top, 0.20, _edge)
		var edge_z: float = _inner * side * 0.65
		_box(Vector3(0.0, 0.013, edge_z), Vector3(_inner * 0.72, 0.018, 0.13), _amber)
		_label("KEEP CLEAR", Vector3(0, 0.018, edge_z * 0.9), Basis(Vector3.RIGHT, -PI * 0.5),
			0.23, Color("#acb8bb"))


func _lighting() -> void:
	var cells := maxi(2, ceili(_inner / 4.25))
	for side in [-1.0, 1.0]:
		for row in cells:
			var z := lerpf(-_inner, _inner, (row + 0.5) / cells)
			_light(Vector3(side * _inner * 0.60, _roof - 1.05, z), ICE, 7800.0, 14.3)
			_light(Vector3(side * _inner * 0.81, 4.1, z), Color("#c2e4ff"), 8100.0, 11.5)
		for deck in 3:
			var base := deck * _rise
			var x: float = side * (_half + _inner) * 0.5
			var count := maxi(3, ceili(_half / 4.7))
			for row in count:
				var z := lerpf(-_inner, _inner, (row + 0.5) / count)
				var fixture := Vector3(x, base + 3.45, z)
				_box(fixture, Vector3(0.58, 0.10, 1.40), _dark)
				_box(fixture - Vector3.UP * 0.071, Vector3(0.40, 0.024, 1.18), _white_light)
				_spot(fixture - Vector3.UP * 0.16, Vector3(-side * 0.22, -1, 0),
					AMBER if deck == 0 else ICE, 7400.0, 9.0, 62.0)
			for end in [-1.0, 1.0]:
				_light(Vector3(0, base + 3.04, end * (_half + _inner) * 0.5), AMBER, 5300.0, maxf(8.0, _half * 0.42))
	_light(Vector3(0, 1.92, 0), Color("#77dafa"), 1700.0, 5.4)
	for side in [-1.0, 1.0]:
		for deck in 3:
			var base := deck * _rise
			var span: float = _half - _inner
			var z: float = side * (_half - span * 0.53)
			var fixtures := ceili(_half * 2.0 / 7.5)
			for section in fixtures:
				var x := lerpf(-_half, _half, (section + 0.5) / fixtures)
				_box(Vector3(x, base + 3.49, z), Vector3(1.84, 0.076, 0.45), _edge)
				_box(Vector3(x, base + 3.421, z), Vector3(1.64, 0.026, 0.32), _warm_light)
				_light(Vector3(x, base + 3.18, z), AMBER, 4350.0, 9.0)


func _core(center: Vector3) -> void:
	_box(Vector3(0.0, 0.19, 0.0), Vector3(2.67, 0.38, 2.67), _dark)
	_box(center, Vector3(2.48, 0.94, 2.48), _panel)
	_box(Vector3(0, 1.15, 0), Vector3(2.58, 0.18, 2.58), _edge)
	_box(Vector3(0, 1.25, 0), Vector3(1.62, 0.049, 1.62), _cyan_light)
	_box(Vector3(0, 1.31, 0), Vector3(1.41, 0.074, 1.41), _dark)
	_box(Vector3(0, 1.36, 0), Vector3(1.06, 0.035, 1.06), _screen)
	for index in 5:
		var length := [0.21, 0.48, 0.34, 0.59, 0.44]
		_box(Vector3(-0.41 + length[index] * 0.5, 1.38, -0.34 + index * 0.14),
			Vector3(length[index], 0.008, 0.026), _green_light)
	for wall in 4:
		var basis := Basis(Vector3.UP, wall * PI * 0.5)
		_box(basis * Vector3(0, 0.95, 1.25), Vector3(1.14, 0.054, 0.035), _cyan_light, basis)
		_box(basis * Vector3(0, 0.62, 1.25), Vector3(1.77, 0.36, 0.04), _rubber, basis)
		for slot in 11:
			_box(basis * Vector3(-0.72 + slot * 0.144, 0.62, 1.28), Vector3(0.068, 0.29, 0.037), _cream, basis)
		_label("TRANSFER", basis * Vector3(0, 0.84, 1.283), basis, 0.105, ICE)


func room(deck: int, side: float, corridor: float, room_x: float, room_end: float, door: float, door_half: float) -> void:
	var height := deck * _rise
	var x := side * (corridor - 0.145)
	var tint: Color = ROOM_TINTS[deck]
	var emitter := _room_lamps[deck]
	var sign_basis := Basis(Vector3.UP, -side * PI * 0.5)
	var face := Vector3(x, height, 0)
	_box(face + Vector3.UP * 2.62, Vector3(0.09, 0.38, minf(2.70, room_end * 0.54)), _rubber)
	_label(ROOM_NAMES[deck], face + Vector3(-side * 0.057, 2.62, 0), sign_basis, 0.137, tint)
	_box(Vector3(room_x, height + 3.26, 0), Vector3(minf(absf(room_x - x) * 1.25, 3.2), 0.13, room_end * 1.60), _edge)
	_box(Vector3(room_x, height + 3.163, 0), Vector3(0.40, 0.035, room_end * 1.28), emitter)
	_spot(Vector3(room_x, height + 3.03, 0), Vector3(0, -1, 0.22), tint, 10100.0, 8.2, 63.0)
	var equipment_x := side * (_half - 0.25)
	for end in [-1.0, 1.0]:
		var panel_at := Vector3(equipment_x, height + 1.72, end * room_end * 0.58)
		_box(panel_at, Vector3(0.22, 0.57, 0.71), _edge)
		_box(panel_at + Vector3(-side * 0.13, 0.02, 0), Vector3(0.025, 0.39, 0.57), _screen)
		for line in 3:
			_box(panel_at + Vector3(-side * 0.147, 0.107 - line * 0.082, (line - 1) * 0.048),
				Vector3(0.017, 0.026, 0.19 + line * 0.08), emitter)
		_box(panel_at + Vector3.UP * 0.60, Vector3(0.055, 0.75, 0.055), _dark)
	for end in [-1.0, 1.0]:
		var z: float = end * door
		_box(Vector3(x, height + 2.40, z), Vector3(0.22, 0.18, door_half * 2.0 + 0.15), _edge)
		_box(Vector3(x - side * 0.12, height + 2.38, z), Vector3(0.035, 0.075, door_half * 1.68), emitter)
		for edge in [-1.0, 1.0]:
			_box(Vector3(x, height + 1.14, z + edge * door_half), Vector3(0.23, 2.28, 0.095), _edge)
			_box(Vector3(x - side * 0.13, height + 1.7, z + edge * door_half), Vector3(0.036, 0.29, 0.044), emitter)
		_spot(Vector3(x - side * 0.18, height + 2.33, z),
			Vector3(-side * 0.44, -1, 0), tint, 6300.0, 6.1, 53.0)
		_box(Vector3(x - side * 0.45, height + 0.008, z), Vector3(0.10, 0.014, door_half * 1.68), _amber)


func _partition(center: Vector3, size: Vector3) -> void:
	_box(center, size, _panel)
	var spans_z := size.x < size.z
	var trim := Vector3(size.x + 0.037, 0.13, size.z) if spans_z else Vector3(size.x, 0.13, size.z + 0.037)
	for height in [-0.43, 0.43]:
		_box(center + Vector3.UP * (size.y * height), trim, _dark)
	if size.y < 2.0:
		return
	var modules := maxi(1, ceili(maxf(size.x, size.z) / 2.15))
	for index in modules:
		var fraction := (index + 0.5) / modules - 0.5
		var offset := Vector3(0, 0, size.z * fraction) if spans_z else Vector3(size.x * fraction, 0, 0)
		var seam := Vector3(size.x + 0.034, size.y * 0.73, 0.047) if spans_z else Vector3(0.047, size.y * 0.73, size.z + 0.034)
		_box(center + offset, seam, _edge)


func _cargo(center: Vector3, size: Vector3) -> void:
	_box(center, size, _dark)
	_box(center, size * Vector3(0.89, 0.72, 1.01), _panel)
	for offset in [-0.43, 0.43]:
		_box(center + Vector3.UP * (offset * size.y),
			Vector3(size.x + 0.041, 0.095, size.z + 0.034), _edge)
		_box(center + Vector3.RIGHT * (offset * size.x),
			Vector3(0.083, size.y * 0.84, size.z + 0.035), _amber)
	_box(center + Vector3(0.0, 0.18, size.z * 0.512), Vector3(size.x * 0.38, 0.065, 0.022), _green_light)


func _console(center: Vector3, size: Vector3) -> void:
	_box(center, size, _dark)
	_box(center + Vector3.UP * (size.y * 0.40), Vector3(size.x + 0.04, size.y * 0.17, size.z + 0.04), _edge)
	var front := center.z + size.z * 0.5
	_box(Vector3(center.x, center.y + 0.19, front + 0.015), Vector3(size.x * 0.77, 0.32, 0.046), _screen)
	for index in 4:
		_box(Vector3(center.x - size.x * 0.27 + index * size.x * 0.18, center.y + 0.23, front + 0.046),
			Vector3(size.x * 0.11, 0.042, 0.036), _cyan_light if index % 2 == 0 else _green_light)


func _spot(at: Vector3, direction: Vector3, tint: Color, lumens: float, reach: float, cone: float) -> void:
	var light := SpotLight3D.new()
	light.light_color = tint
	light.light_intensity_lumens = lumens
	light.spot_range = reach
	light.spot_angle = cone
	light.spot_angle_attenuation = 0.60
	light.spot_attenuation = 1.0
	light.position = at
	light.basis = Basis.looking_at(direction)
	light.light_specular = 0.22
	_root.add_child(light)


func _locker(center: Vector3, size: Vector3) -> void:
	_box(center, size, _dark)
	var front := center.z + size.z * 0.5
	for column in 3:
		var x := center.x + (column - 1.0) * size.x * 0.29
		_box(Vector3(x, center.y, front + 0.018), Vector3(size.x * 0.26, size.y * 0.82, 0.05), _panel)
		_box(Vector3(x + 0.15, center.y + 0.27, front + 0.06), Vector3(0.035, 0.09, 0.025), _green_light)
		for line in 4:
			_box(Vector3(x, center.y - 0.30 + line * 0.07, front + 0.06),
				Vector3(size.x * 0.19, 0.017, 0.02), _rubber)


func _exterior() -> void:
	# The original GDT modules generate a distant lunar surface outside the pressure hull.
	var field := HEIGHTFIELD.new()
	var noise := FastNoiseLite.new()
	noise.seed = 516010
	noise.frequency = 0.037
	noise.fractal_octaves = 5
	const SIZE := 250.0
	const QUADS := 112
	field.create_from_noise(QUADS, SIZE, 4.2, noise)
	for z in QUADS + 1:
		for x in QUADS + 1:
			var point := Vector2(x, z) * (SIZE / QUADS) - Vector2.ONE * SIZE * 0.5
			var distance := point.length()
			var rim := 10.0 * exp(-pow((distance - 82.0) / 19.0, 2.0))
			var ridges := pow(absf(sin(point.angle() * 4.1 + 0.85)), 1.55) * rim
			field.set_grid(x, z, field.sample_grid(x, z) + rim + ridges - 14.0)
	var builder := TERRAIN_MESH.new()
	builder.configure({
		"heightfield": field,
		"active_total_resolution": QUADS,
		"active_chunk_resolution": QUADS,
		"active_step": SIZE / QUADS,
		"active_half_size": SIZE * 0.5,
	})
	var landscape := MeshInstance3D.new()
	landscape.name = "LunarHorizon"
	landscape.mesh = builder.build_chunk_mesh(0, 0, 1)
	var material := ShaderMaterial.new()
	material.shader = HORIZON_SHADER
	material.set_shader_parameter("rock_diff", load(
		"res://game/maps/farpost/art/ground/rocky_terrain_02_diff_2k.jpg"))
	landscape.material_override = material
	landscape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(landscape)


func _fit_model(kind: String, foot: Vector3, size: Vector3, yaw: float) -> void:
	var asset: Array = MODEL_PARTS[kind]
	var model_id: String = asset[0]
	if not _models.has(kind):
		_models[kind] = load("%s%s/%s_2k.gltf" % [ART, model_id, model_id])
	var model: Node3D = _models[kind].instantiate()
	if not asset[1].is_empty():
		var source := model.find_child(asset[1], true, false) as MeshInstance3D
		var mesh := MeshInstance3D.new()
		mesh.mesh = source.mesh
		model.free()
		model = mesh
	var orientation := Basis(Vector3.UP, yaw)
	var bounds := _bounds(model, Transform3D(orientation, Vector3.ZERO))
	var pivot := Node3D.new()
	pivot.scale = size / bounds.size
	pivot.position = foot - Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * pivot.scale
	var direction := Node3D.new()
	direction.basis = orientation
	direction.add_child(model)
	pivot.add_child(direction)
	_root.add_child(pivot)


func _bounds(node: Node3D, parent: Transform3D) -> AABB:
	var transform := parent * node.transform
	var bounds: AABB = transform * node.get_aabb() if node is MeshInstance3D else AABB()
	for child in node.get_children():
		if child is Node3D:
			var part := _bounds(child, transform)
			if part.has_volume():
				bounds = bounds.merge(part) if bounds.has_volume() else part
	return bounds


func _light(at: Vector3, tint: Color, lumens: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_intensity_lumens = lumens
	light.omni_range = reach
	light.light_specular = 0.24
	light.position = at
	_root.add_child(light)


func _texture(name: String, channel: String) -> Texture2D:
	return load("%s%s/%s_%s_2k.jpg" % [ART, name, name, channel])


func _paint(tint: Color, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.metallic = metallic
	material.roughness = 0.61
	return material


func _glowing(tint: Color, energy: float) -> StandardMaterial3D:
	var material := _paint(tint, 0.0)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = energy
	return material


func _label(caption: String, at: Vector3, basis: Basis, character_height: float, tint: Color) -> void:
	var label := Label3D.new()
	label.text = caption
	label.font_size = 64
	label.pixel_size = character_height / label.font_size
	label.outline_size = 0
	label.modulate = tint
	label.transform = Transform3D(basis, at)
	_root.add_child(label)


func _box(at: Vector3, size: Vector3, material: Material, basis := Basis.IDENTITY) -> void:
	if not _batches.has(material):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(material)
		_batches[material] = surface
	var box := BoxMesh.new()
	box.size = size
	_batches[material].append_from(box, 0, Transform3D(basis, at))


func _beam(start: Vector3, finish: Vector3, thickness: float, material: Material) -> void:
	var direction := finish - start
	_box(start.lerp(finish, 0.5), Vector3(thickness, thickness, direction.length()),
		material, Basis.looking_at(direction))


func _flush_boxes() -> void:
	for material: Material in _batches:
		var instance := MeshInstance3D.new()
		instance.mesh = _batches[material].commit()
		_root.add_child(instance)
	_batches.clear()
