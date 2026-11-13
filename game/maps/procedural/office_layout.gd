extends RefCounted

const ROUTE_MARKING := preload("res://game/maps/procedural/route_marking.gd")

const SURFACE := preload("res://game/maps/procedural/office_surface.gdshader")
const DISPLAY := preload("res://game/maps/procedural/office_display.gdshader")
const Fixtures := preload("res://game/maps/procedural/village_fixtures.gd")
const CEILING := 2.95
const WALL := 0.22
const DOOR := 1.55
const DOOR_HEIGHT := 2.18
const HALF_X := 9.8
const HALF_Z := 7.6
const DOOR_PATH := "res://assets/arena_props/office/glass_office_door.glb"
const DETAIL_PATH := "res://assets/arena_props/office/details/"
const DESK_PATH := "res://assets/arena_props/office/metal_office_desk/metal_office_desk.gltf"
const LAPTOP_PATH := "res://assets/arena_props/office/classic_laptop/classic_laptop.gltf"

enum Finish { PAINT, ACOUSTIC, CERAMIC, CARPET }

var _map: Node3D
var _placing_furniture := false
var _fixtures: Fixtures
var _plaster: Material
var _wood: Material
var _trim: Material
var _metal: Material
var _plastic: Material
var _fabric: Material
var _paper: Material
var _ceiling: Material
var _screen: ShaderMaterial
var _status_light: StandardMaterial3D
var _painted_metal: StandardMaterial3D
var _light: StandardMaterial3D
var _door_model: PackedScene
var _frosted_glass: StandardMaterial3D
var _desk: PackedScene
var _laptop: PackedScene
var _detail_models: Dictionary[String, PackedScene] = {}


func _init(map: Node3D) -> void:
	_map = map


func build() -> Array[Transform3D]:
	_plaster = _surface(Finish.PAINT, "concrete", Color(0.90, 0.87, 0.79), 2.2, 0.48)
	_wood = _map._world_mat("planks", Color(0.76, 0.56, 0.37), 0.0, 0.78, 0.85, true)
	_trim = _map._world_mat("planks", Color(0.39, 0.31, 0.26), 0.0, 0.92, 0.72, false)
	_metal = _map._world_mat("brushed", Color(0.60, 0.63, 0.64), 0.78, 2.4, 0.50, false)
	_painted_metal = _map._world_mat("brushed", Color(0.47, 0.52, 0.47), 0.30, 1.8, 0.36, false)
	_plastic = _map._world_mat("rubber", Color(0.32, 0.36, 0.38), 0.0, 4.0, 0.42, false)
	_fabric = _map._world_mat("office/carpet", Color(0.47, 0.55, 0.47), 0.0, 3.2, 0.98, false)
	_paper = _mat(Color(0.86, 0.83, 0.72))
	_ceiling = _surface(Finish.ACOUSTIC, "concrete", Color(0.79, 0.78, 0.72), 3.0, 0.23)
	_light = _emissive(Color(1.0, 0.94, 0.80), 2.1)
	_status_light = _emissive(Color(0.19, 0.35, 0.43), 0.65)
	_screen = ShaderMaterial.new()
	_screen.shader = DISPLAY
	_door_model = load(DOOR_PATH)
	_frosted_glass = _mat(Color(0.46, 0.60, 0.64), 0.12)
	_frosted_glass.roughness = 0.47
	_frosted_glass.normal_enabled = true
	_frosted_glass.normal_texture = _map._tex("concrete", "normal")
	_frosted_glass.normal_scale = 0.17
	_frosted_glass.uv1_scale = Vector3(5.0, 7.0, 1.0)
	_desk = load(DESK_PATH)
	_laptop = load(LAPTOP_PATH)
	_fixtures = Fixtures.new()
	_fixtures.name = "VillageFixtures"
	_map.add_child(_fixtures)
	_shell()
	_placing_furniture = true
	_furnish()
	_placing_furniture = false
	_spawns()
	var supplies: Array[Transform3D] = []
	for at in [Vector3(-1.8, 0, -2.4), Vector3(1.8, 0, 2.6)]:
		supplies.append(Transform3D(Basis.IDENTITY, at))
	return supplies


func _shell() -> void:
	var carpet := _surface(Finish.CARPET, "office/carpet", Color(0.54, 0.64, 0.66), 2.1, 0.52)
	var tile := _surface(Finish.CERAMIC, "concrete", Color(0.80, 0.79, 0.72), 1.6, 0.36)
	_solid(Vector3(0, -0.16, 0), Vector3(20, 0.32, 15.5), carpet)
	_paint(Vector3(0, 0.007, 3.8), Vector3(7.2, 0.014, 7.4), tile)
	_solid(Vector3(0, CEILING + 0.12, 0), Vector3(20, 0.24, 15.5), _ceiling)
	for side in [-1.0, 1.0]:
		_wall(Vector2(-HALF_X, side * HALF_Z), Vector2(HALF_X, side * HALF_Z))
		_wall(Vector2(side * HALF_X, -HALF_Z), Vector2(side * HALF_X, HALF_Z))
	# West lounge and records, east offices and meeting room, lobby above the break room.
	_wall(Vector2(-4.0, -HALF_Z), Vector2(-4.0, HALF_Z), [2.1, 11.8])
	_wall(Vector2(4.0, -HALF_Z), Vector2(4.0, HALF_Z), [3.0, 12.0])
	_wall(Vector2(-HALF_X, 0.25), Vector2(-4.0, 0.25), [2.35])
	_wall(Vector2(4.0, -0.35), Vector2(HALF_X, -0.35), [3.5])
	_wall(Vector2(-4.0, 0.0), Vector2(4.0, 0.0), [1.8, 6.2])
	for x in range(-9, 10):
		_paint(Vector3(x, CEILING - 0.013, 0), Vector3(0.014, 0.02, 15.2), _metal)
	for z in range(-7, 8):
		_paint(Vector3(0, CEILING - 0.023, z), Vector3(19.6, 0.02, 0.014), _metal)
	for at: Vector2 in [Vector2(-7,-5), Vector2(-7,-2), Vector2(-7,2), Vector2(-7,5),
			Vector2(7,-5), Vector2(7,-2), Vector2(7,2), Vector2(7,5),
			Vector2(-2,-4), Vector2(2,-4), Vector2(0,-1), Vector2(-2,3), Vector2(2,3), Vector2(0,6)]:
		_ceiling_light(at)
	ROUTE_MARKING.paint(_map, "RECEPTION", Vector3(0, 0.008, -5.5), Color("#bcd0db"))
	ROUTE_MARKING.paint(_map, "BREAK ROOM", Vector3(0, 0.018, 2.1), Color("#515e51"))


func _wall(from: Vector2, to: Vector2, doors: Array = []) -> void:
	var direction := (to - from).normalized()
	var frame := Transform3D(Basis(Vector3.UP, atan2(-direction.y, direction.x)), Vector3(from.x, 0, from.y))
	var previous := 0.0
	for offset: float in doors:
		_wall_span(frame, previous, offset - DOOR * 0.5)
		_door(frame.translated_local(Vector3(offset, 0, 0)))
		previous = offset + DOOR * 0.5
	_wall_span(frame, previous, from.distance_to(to))


func _wall_span(frame: Transform3D, start: float, end: float) -> void:
	var middle := (start + end) * 0.5
	var yaw := rad_to_deg(frame.basis.get_euler().y)
	_solid(frame * Vector3(middle, CEILING * 0.5, 0), Vector3(end - start, CEILING, WALL), _plaster, yaw)
	for side in [-1.0, 1.0]:
		_paint(frame * Vector3(middle, 0.08, side * 0.12), Vector3(end - start, 0.16, 0.04), _trim, yaw)
		_paint(frame * Vector3(middle, 0.92, side * 0.119), Vector3(end - start, 0.09, 0.034), _wood, yaw)


func _door(portal: Transform3D) -> void:
	var yaw := rad_to_deg(portal.basis.get_euler().y)
	var headroom := CEILING - DOOR_HEIGHT
	_solid(portal * Vector3(0, DOOR_HEIGHT + headroom * 0.5, 0), Vector3(DOOR, headroom, WALL), _plaster, yaw)
	for side in [-1.0, 1.0]:
		_solid(portal * Vector3(side * (DOOR * 0.5 - 0.035), DOOR_HEIGHT * 0.5, -0.045),
			Vector3(0.072, DOOR_HEIGHT, 0.38), _metal, yaw, "metal")
	_paint(portal * Vector3(0, DOOR_HEIGHT + 0.027, -0.045), Vector3(DOOR + 0.16, 0.095, 0.39), _metal, yaw)
	var leaf := _door_model.instantiate() as Node3D
	leaf.name = "OfficeDoorModel"
	# The frame stays in the wall. Only the pane and its fittings follow the hinge.
	var pane: MeshInstance3D
	for part: MeshInstance3D in leaf.find_children("*", "MeshInstance3D", true, false):
		part.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
		if part.name.begins_with("Frame"):
			part.hide()
		elif "tempered glass leaf" in part.name:
			part.material_override = _frosted_glass
			pane = part
	# Fit the source pane to the shared fixture's collision box.
	leaf.scale = Vector3((DOOR - 0.11) / 0.914, (DOOR_HEIGHT - 0.065) / 2.136, 0.77)
	var body := _fixtures.add_door(portal, DOOR, DOOR_HEIGHT, _wood, _metal, leaf)
	body.set_meta(&"impact_surface", "concrete")
	body.set_meta(&"ballistic_material", "laminate")
	body.set_meta(&"ballistic_resistance", 0.30)
	if pane:
		_map._register_perforated_cover(body, pane)


func _ceiling_light(at: Vector2) -> void:
	_paint(Vector3(at.x, CEILING - 0.065, at.y), Vector3(1.16, 0.105, 0.56), _metal)
	_paint(Vector3(at.x, CEILING - 0.126, at.y), Vector3(1.03, 0.026, 0.46), _light)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(at.x, CEILING - 0.24, at.y)
	if at.x < -4.0 or (absf(at.x) < 4.0 and at.y > 0.0):
		lamp.light_temperature = 3500.0
		lamp.light_intensity_lumens = 4100.0
	elif at.x > 4.0:
		lamp.light_temperature = 5600.0
		lamp.light_intensity_lumens = 4700.0
	else:
		lamp.light_temperature = 4600.0
		lamp.light_intensity_lumens = 4500.0
	lamp.omni_range = 5.4
	lamp.omni_attenuation = 1.25
	if at == Vector2(-2, -4) or at == Vector2(2, 3):
		lamp.add_to_group(&"office_shadow_lights")
	_map.add_child(lamp)


func _furnish() -> void:
	# Northwest lounge and visitor check-in.
	_workstation(Vector3(-8.55, 0, -3.1), -90.0, true)
	_sofa(Vector3(-9.03, 0, -1.22), -90.0)
	_low_table(Vector3(-6.3, 0, -2.7), Vector3(1.2, 0.48, 0.63))
	_prop("binder_notebook", Vector3(-6.50, 0.483, -2.77), -18)
	_prop("potted_plant_04", Vector3(-5.97, 0.48, -2.53))
	_prop("wall_clock", Vector3(-7.1, 2.23, -7.45))
	_notice(Vector3(-7.1, 1.57, -7.45), 0.0)
	_sign("VISITOR LOUNGE", Vector3(-9.65, 2.0, -2.05), 90.0)

	# Northeast tech office with two distinct workstations and a patch cabinet.
	_workstation(Vector3(8.45, 0, -3.9), 90.0, false)
	_workstation(Vector3(6.32, 0, -2.6), 0.0, false)
	_cabinet(Vector3(9.3, 0, -1.25), -90.0)
	_prop("stationery_supplies", Vector3(6.93, 0.79, -2.71), -12)
	_prop("desk_lamp_arm_01", Vector3(8.11, 0.79, -4.65), -90)
	_equipment_board(Vector3(9.65, 1.53, -5.4), -90.0)
	_sign("TECH OFFICE", Vector3(7.2, 2.13, -7.45), 0.0)

	# Southwest records room with shelves, file bins and a sorting cabinet.
	_cabinet(Vector3(-9.28, 0, 3.0), 90.0)
	_records_shelf(Vector3(-9.22, 0, 5.55), 90.0)
	_cabinet(Vector3(-7.1, 0, 2.95), 0.0)
	_prop("binder_notebook", Vector3(-7.35, 1.581, 2.90), 21)
	_sign("RECORDS", Vector3(-9.65, 2.05, 3.9), 90.0)

	# Southeast meeting room with a planning board and a screen on its credenza.
	_low_table(Vector3(7.25, 0, 3.1), Vector3(2.05, 0.76, 0.91))
	_chair(Vector3(5.98, 0, 3.12), -90.0)
	_chair(Vector3(8.52, 0, 3.12), 90.0)
	_chair(Vector3(7.1, 0, 4.0), 0.0)
	_cabinet(Vector3(9.3, 0, 1.5), -90.0)
	_cabinet(Vector3(7.0, 0, 2.0), 0.0)
	_prop("television_02", Vector3(7.0, 1.58, 2.0), 0, 1.24)
	_prop("binder_notebook", Vector3(7.0, 0.763, 3.05), -16)
	_whiteboard(Vector3(9.64, 1.60, 3.6), -90.0)
	_sign("MEETING ROOM", Vector3(9.65, 2.28, 3.8), -90.0)

	# Reception and the break room use different clutter and wall details.
	_workstation(Vector3(-1.2, 0, -4.4), 0.0, true)
	_sofa(Vector3(1.75, 0, -6.96), 180.0)
	_cabinet(Vector3(1.65, 0, -4.9), 72.0)
	_prop("potted_plant_04", Vector3(1.58, 1.58, -5.09), 30, 1.45)
	_sign("RECEPTION", Vector3(0.0, 2.02, -7.46), 0.0)
	_notice(Vector3(3.85, 1.52, -3.25), -90.0)
	_break_counter()
	_low_table(Vector3(0.0, 0, 4.8), Vector3(1.70, 0.85, 0.76))
	_mug(Vector3(-0.42, 0.85, 4.86), Color(0.55, 0.24, 0.16))
	_mug(Vector3(0.48, 0.99, 6.83), Color(0.19, 0.38, 0.50))
	_paint(Vector3(2.32, 1.14, 7.10), Vector3(0.51, 0.31, 0.34), _plastic)
	_paint(Vector3(2.26, 1.15, 6.923), Vector3(0.32, 0.19, 0.02), _metal)
	_prop("wall_clock", Vector3(-2.1, 2.18, 7.46), 180)
	_notice(Vector3(-2.1, 1.53, 7.46), 180.0)
	for at: Vector3 in [Vector3(-6.2,0.018,3.1), Vector3(-5.8,0.02,3.4), Vector3(3.1,0.02,2.8), Vector3(6.5,0.02,-2.8)]:
		_paint(at, Vector3(0.24, 0.008, 0.31), _paper, 24.0)


func _prop(asset: String, at: Vector3, yaw := 0.0, scale_factor := 1.0) -> void:
	if not _detail_models.has(asset):
		_detail_models[asset] = load(DETAIL_PATH + "%s/%s.gltf" % [asset, asset])
	var prop := _detail_models[asset].instantiate() as Node3D
	prop.position = at
	prop.rotation_degrees.y = yaw
	prop.scale = Vector3.ONE * scale_factor
	_map.add_child(prop)


func _records_shelf(at: Vector3, yaw: float) -> void:
	var frame := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at)
	var depth := 0.49
	_solid(frame * Vector3(0, 0.94, -0.23), Vector3(1.44, 1.88, 0.05), _metal, yaw, "metal")
	for side in [-1.0, 1.0]:
		_solid(frame * Vector3(side * 0.69, 0.94, 0), Vector3(0.06, 1.88, depth), _metal, yaw, "metal")
	for row in 5:
		var y := 0.13 + row * 0.42
		_solid(frame * Vector3(0, y, 0), Vector3(1.38, 0.045, depth), _metal, yaw, "metal")
		if row < 4:
			for column in range(row % 2, 3):
				var x := -0.44 + column * 0.43
				_paint(frame * Vector3(x, y + 0.149, 0.015), Vector3(0.35, 0.25, 0.38), _paper, yaw)
				_paint(frame * Vector3(x, y + 0.166, 0.211), Vector3(0.16, 0.055, 0.013), _metal, yaw)


func _equipment_board(at: Vector3, yaw: float) -> void:
	var frame := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at)
	_paint(at, Vector3(0.90, 0.56, 0.075), _plastic, yaw)
	for row in 2:
		for column in 6:
			var x := -0.33 + column * 0.13
			_paint(frame * Vector3(x, 0.10 - row * 0.20, 0.045), Vector3(0.088, 0.082, 0.025), _metal, yaw)
			if (column + row) % 3 != 0:
				_paint(frame * Vector3(x, 0.115 - row * 0.20, 0.062), Vector3(0.021, 0.012, 0.008), _status_light, yaw)


func _whiteboard(at: Vector3, yaw: float) -> void:
	var frame := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at)
	_paint(at, Vector3(1.58, 0.93, 0.045), _metal, yaw)
	_paint(frame * Vector3(0, 0, 0.026), Vector3(1.51, 0.86, 0.014), _paper, yaw)
	_sign("WEEKLY PLAN", frame * Vector3(0, 0.24, 0.036), yaw)
	for column in 4:
		var x := -0.49 + column * 0.32
		_paint(frame * Vector3(x, -0.02, 0.036), Vector3(0.22, 0.008, 0.005), _metal, yaw)
		_paint(frame * Vector3(x, -0.13 - (column % 2) * 0.06, 0.036), Vector3(0.16, 0.009, 0.005), _plastic, yaw)


func _mug(at: Vector3, color: Color) -> void:
	var material := _mat(color)
	var cup := CSGCylinder3D.new()
	cup.radius = 0.046
	cup.height = 0.103
	cup.sides = 20
	cup.material = material
	var hollow := CSGCylinder3D.new()
	hollow.operation = CSGShape3D.OPERATION_SUBTRACTION
	hollow.radius = 0.038
	hollow.height = 0.099
	hollow.sides = 20
	hollow.position.y = 0.013
	cup.add_child(hollow)
	var handle := CSGTorus3D.new()
	handle.inner_radius = 0.017
	handle.outer_radius = 0.026
	handle.rotation.x = PI * 0.5
	handle.position.x = 0.049
	handle.material = material
	cup.add_child(handle)
	cup.position = at + Vector3.UP * 0.052
	_map.add_child(cup)


func _spawns() -> void:
	# Alternate teams between opposite diagonal rooms. Every slot stays behind a closed door.
	for index in 20:
		var corner := index % 4
		var seat := index / 4
		var side_x := -1.0 if corner in [0, 3] else 1.0
		var side_z := -1.0 if corner in [0, 1] else 1.0
		var x := 5.6 + float(seat % 3) * 1.42
		var z := 6.18 - float(seat / 3) * 1.10
		_map._initial_spawns.append(Vector3(x * side_x, 0.12, z * side_z))
	_map.respawn_points = _map._initial_spawns.duplicate()
	for point: Vector3 in [Vector3(-7, 0.15, -4.8), Vector3(7.3, 0.15, -5.2),
			Vector3(-7.2, 0.15, 4.0), Vector3(7.2, 0.15, 5.0),
			Vector3(0, 0.15, -3.4), Vector3(0, 0.15, 2.8), Vector3(2.65, 0.15, 0.0)]:
		_map._patrol.append(point)


func _workstation(at: Vector3, yaw: float, laptop_desk: bool) -> void:
	var frame := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at)
	var visual := _desk.instantiate() as Node3D
	_solid(at + Vector3.UP * 0.39, Vector3(2.0, 0.79, 0.95), _wood, yaw, "wood", visual)
	visual.position.y = -0.39
	if laptop_desk:
		var laptop := _laptop.instantiate() as Node3D
		_map.add_child(laptop)
		laptop.transform = frame.translated_local(Vector3(-0.10, 0.795, -0.13))
		_prop("binder_notebook", frame * Vector3(0.48, 0.795, -0.15), yaw - 14)
	else:
		_paint(frame * Vector3(0.08, 0.802, 0.08), Vector3(0.37, 0.023, 0.14), _plastic, yaw)
		_paint(frame * Vector3(-0.19, 0.814, -0.20), Vector3(0.24, 0.036, 0.18), _metal, yaw)
		_paint(frame * Vector3(-0.19, 0.943, -0.20), Vector3(0.057, 0.23, 0.048), _metal, yaw)
		_paint(frame * Vector3(-0.19, 1.123, -0.20), Vector3(0.53, 0.33, 0.092), _plastic, yaw)
		var display := MeshInstance3D.new()
		var panel := QuadMesh.new()
		panel.size = Vector2(0.478, 0.273)
		panel.material = _screen
		display.mesh = panel
		display.transform = frame.translated_local(Vector3(-0.19, 1.127, -0.151))
		_map.add_child(display)
		_paint(frame * Vector3(0.71, 0.991, -0.19), Vector3(0.18, 0.40, 0.33), _plastic, yaw)
		for vent in 4:
			_paint(frame * Vector3(0.71, 0.90 + 0.033 * vent, -0.020), Vector3(0.10, 0.009, 0.008), _metal, yaw)
	_chair(frame * Vector3(0.1, 0, 0.89), yaw)


func _chair(at: Vector3, yaw: float) -> void:
	var frame := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at)
	_solid(at + Vector3.UP * 0.48, Vector3(0.56, 0.17, 0.53), _fabric, yaw, "wood")
	_solid(frame * Vector3(0, 0.77, 0.21), Vector3(0.53, 0.43, 0.11), _fabric, yaw, "wood")
	_paint(at + Vector3.UP * 0.21, Vector3(0.075, 0.44, 0.075), _metal)
	for spoke in [0.0, 72.0, 144.0, 216.0, 288.0]:
		var angle: float = deg_to_rad(yaw + spoke)
		_paint(at + Vector3(0, 0.065, 0.15).rotated(Vector3.UP, angle), Vector3(0.05, 0.055, 0.32), _metal, yaw + spoke)


func _sofa(at: Vector3, yaw: float) -> void:
	var frame := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at)
	_solid(at + Vector3.UP * 0.32, Vector3(2.03, 0.60, 0.83), _fabric, yaw, "wood")
	_solid(frame * Vector3(0, 0.71, 0.33), Vector3(2.03, 0.43, 0.18), _fabric, yaw, "wood")
	for side in [-1.0, 1.0]:
		_solid(frame * Vector3(side * 0.9, 0.67, 0), Vector3(0.24, 0.22, 0.80), _fabric, yaw, "wood")
	for x in [-0.54, 0.0, 0.54]:
		_paint(frame * Vector3(x, 0.61, -0.02), Vector3(0.52, 0.08, 0.64), _fabric, yaw)


func _low_table(at: Vector3, size: Vector3) -> void:
	const TOP_THICKNESS := 0.11
	var top := _solid(at + Vector3.UP * (size.y - TOP_THICKNESS * 0.5),
		Vector3(size.x, TOP_THICKNESS, size.z), _wood, 0.0, "wood")
	top.add_to_group(&"office_tabletop")
	var leg_height := size.y - TOP_THICKNESS
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var leg := _solid(at + Vector3(x * (size.x * 0.5 - 0.09), leg_height * 0.5, z * (size.z * 0.5 - 0.08)),
				Vector3(0.09, leg_height, 0.09), _metal, 0.0, "metal")
			leg.add_to_group(&"office_table_leg")
	_paint(at + Vector3(0.25, size.y + 0.02, -0.08), Vector3(0.23, 0.04, 0.31), _paper, 17.0)


func _cabinet(at: Vector3, yaw: float) -> void:
	var frame := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at)
	_solid(at + Vector3.UP * 0.79, Vector3(1.45, 1.58, 0.49), _painted_metal, yaw, "metal")
	for drawer in 4:
		var y := 0.22 + drawer * 0.38
		_paint(frame * Vector3(0, y, 0.258), Vector3(1.37, 0.35, 0.036), _painted_metal, yaw)
		_paint(frame * Vector3(0, y + 0.04, 0.286), Vector3(0.17, 0.037, 0.039), _plastic, yaw)
		_paint(frame * Vector3(0.42, y, 0.28), Vector3(0.18, 0.08, 0.01), _paper, yaw)


func _break_counter() -> void:
	_solid(Vector3(1.4, 0.45, 7.08), Vector3(3.75, 0.90, 0.72), _wood, 0.0, "wood")
	_paint(Vector3(1.4, 0.94, 7.06), Vector3(3.82, 0.10, 0.80), _plastic)
	_paint(Vector3(0.55, 1.0, 7.02), Vector3(0.70, 0.06, 0.47), _metal)
	_paint(Vector3(0.55, 1.13, 7.25), Vector3(0.08, 0.28, 0.08), _metal)
	_paint(Vector3(0.55, 1.25, 7.16), Vector3(0.08, 0.06, 0.22), _metal)
	_solid(Vector3(-2.85, 0.89, 7.01), Vector3(0.88, 1.78, 0.78), _metal, 0.0, "metal")
	_paint(Vector3(-2.85, 1.23, 6.60), Vector3(0.72, 0.062, 0.052), _plastic)


func _notice(at: Vector3, yaw: float) -> void:
	var frame := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at)
	_paint(at, Vector3(1.27, 0.88, 0.065), _wood, yaw)
	for i in 6:
		var x := -0.40 + float(i % 3) * 0.37
		var y := -0.19 + float(i / 3) * 0.38
		_paint(frame * Vector3(x, y, 0.043), Vector3(0.21, 0.27, 0.013), _paper, yaw)


func _sign(title: String, at: Vector3, yaw: float) -> void:
	var label := Label3D.new()
	label.text = title
	label.font_size = 45
	label.pixel_size = 0.0054
	label.modulate = Color(0.26, 0.29, 0.26)
	label.outline_size = 0
	label.position = at
	label.rotation_degrees.y = yaw
	_map.add_child(label)


func _solid(at: Vector3, size: Vector3, material: Material, yaw := 0.0, surface := "concrete", visual: Node3D = null) -> StaticBody3D:
	var body: StaticBody3D = _map._add_box(at, size, material, yaw, surface, null, visual)
	if _placing_furniture:
		body.add_to_group(&"office_furniture")
	return body


func _paint(at: Vector3, size: Vector3, material: Material, yaw := 0.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.rotation_degrees.y = yaw
	_map.add_child(node)


func _surface(finish: Finish, texture: String, tint: Color, scale_factor: float, bump: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("finish", finish)
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("detail_scale", scale_factor)
	material.set_shader_parameter("bump_strength", bump)
	for kind in ["color", "normal", "roughness"]:
		material.set_shader_parameter("detail_" + kind, _map._tex(texture, kind))
	return material


func _mat(color: Color, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	material.metallic = metallic
	return material


func _emissive(color: Color, power: float) -> StandardMaterial3D:
	var material := _mat(color)
	material.emission_enabled = true
	material.emission = color
	material.emission_intensity = power * 900.0
	return material
