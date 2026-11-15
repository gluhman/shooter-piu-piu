extends Node3D

const ALERT_SOUND := preload("res://game/match/objectives/alert_sound.gd")
const LAYOUT := preload("res://game/maps/objective_layout.gd")
const STEEL := preload("res://assets/arsenal/metal_plate_02_diff.jpg")
const STEEL_NORMAL := preload("res://assets/arsenal/metal_plate_02_nor_gl.jpg")
const FABRIC_NORMAL := preload("res://assets/objectives/hessian_380_nor_gl_1k.jpg")
const PAINT := preload("res://game/maps/breakwater/art/materials/rusty_metal_03_color.jpg")

var _zones: Array[Node3D] = []
var _props: Array[Node3D] = []
var _cloth: Array[ShaderMaterial] = []
var _markers: Array[Label3D] = []
var _last_notice_serial := 0
var _alert_player: AudioStreamPlayer
var _spectator: Camera3D
var _spectated: Node3D
var _spectator_index := 0
var _director: Node3D
var _carry_angle := Basis.from_euler(Vector3(0.13, 0.4, -0.32))


func _unhandled_input(event: InputEvent) -> void:
	if _spectator and _spectator.current and event.is_action_pressed(&"interact"):
		_spectator_index += 1
		get_viewport().set_input_as_handled()


func setup(director: Node3D) -> void:
	_director = director
	_alert_player = AudioStreamPlayer.new()
	_alert_player.bus = &"Interface"
	_alert_player.volume_db = -5.0
	add_child(_alert_player)
	for index in director.centers.size():
		var color: Color = LAYOUT.TEAMS[index] if director.mode == LAYOUT.FLAG else LAYOUT.GOLD
		var zone := Node3D.new()
		add_child(zone)
		zone.position = director.centers[index]
		_zones.append(zone)
		var title := "A" if index == 0 else "B"
		if director.mode == LAYOUT.HILL:
			title = str(index + 1)
		elif director.mode == LAYOUT.FLAG:
			title = "СИНИЕ" if index == 0 else "КРАСНЫЕ"
		_paint(zone, director.radius, color, title)
		_markers.append(_label(zone, title, color))
		if director.mode != LAYOUT.DEFUSE:
			_props.append(_flag(color))
	if director.mode == LAYOUT.DEFUSE:
		_props.append(_charge())
	_spectator = Camera3D.new()
	add_child(_spectator)


func _process(_delta: float) -> void:
	var game: Node3D = _director.game
	if game.is_loading() or game.round_finished():
		return
	var local: Node = game.combatant(Net.local_id())
	if local == null or (_director.mode == LAYOUT.DEFUSE and local.health <= 0):
		var allies: Array[Node] = []
		var slot: int = game.player_slots.find(Net.local_id())
		for group in ["player", "bot"]:
			for actor in get_tree().get_nodes_in_group(group):
				if actor != local and actor.control_enabled and actor.health > 0 and slot >= 0 and actor.team_id() == slot % 2:
					allies.append(actor)
		if not allies.is_empty():
			_spectated = allies[_spectator_index % allies.size()]
			_spectator.global_transform = _spectated.get_node("Camera3D").global_transform
			_spectator.make_current()
		else:
			_spectated = null
			if local and _spectator.current:
				local.get_node("Camera3D").make_current()
			elif local == null and slot >= 0:
				var pool: PackedVector3Array = _director.spawn_pool(slot % 2)
				if not pool.is_empty():
					_spectator.global_position = pool[0] + Vector3.UP * 1.55
					_spectator.look_at(Vector3(0, _spectator.global_position.y, 0))
					_spectator.make_current()
	elif local and _spectator.current:
		local.get_node("Camera3D").make_current()
	_update_carried_props(game)


func _update_carried_props(game: Node3D) -> void:
	if _director.mode == LAYOUT.FLAG:
		var flags: Array = _director.state.get("flags", [])
		for index in flags.size():
			if not flags[index].mounted:
				continue
			var actor: Node = game.combatant(flags[index].carrier)
			if not is_instance_valid(actor) or not is_instance_valid(actor.objective_socket) or actor.health <= 0:
				_props[index].hide()
				continue
			_props[index].visible = actor.score_id() != Net.local_id()
			var rig := Transform3D(_carry_angle.scaled(Vector3.ONE * 0.62), Vector3(-0.16, -0.62, 0.071))
			_props[index].global_transform = actor.objective_socket.global_transform * rig
			_cloth[index].set_shader_parameter("flutter", clampf(1.0 + actor._visual_velocity.length() * 0.075, 1.0, 1.6))
	elif _director.mode == LAYOUT.DEFUSE and _director.state.get("carrying", false):
		var actor: Node = game.combatant(_director.state.carrier)
		if is_instance_valid(actor) and is_instance_valid(actor.objective_socket):
			_props[0].global_transform = actor.objective_socket.global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3(0.69, 0.66, 0.55)), Vector3(0, -0.085, -0.04))
		_props[0].hide()


func update_state(state: Dictionary) -> void:
	var serial := int(state.get("notice_serial", 0))
	if serial > _last_notice_serial:
		_last_notice_serial = serial
		var cue := ALERT_SOUND.stream(state.get("notice_cue", ""))
		if cue:
			_alert_player.stream = cue
			_alert_player.play()
	match _director.mode:
		LAYOUT.HILL:
			for index in _zones.size():
				_zones[index].visible = index == state.active or index == state.next
				_props[index].visible = index == state.active
				_props[index].position = _zones[index].position
				_markers[index].text = "ГОРА %d" % (index + 1) if index == state.active else "СЛЕДУЮЩАЯ · %d" % (index + 1)
				_cloth[index].set_shader_parameter("tint", LAYOUT.TEAMS[state.occupancy] if state.occupancy >= 0 else LAYOUT.GOLD)
		LAYOUT.FLAG:
			for index in _props.size():
				var flag: Dictionary = state.flags[index]
				_zones[index].show()
				_props[index].visible = flag.at.is_finite() and not flag.mounted and flag.state != 1
				if flag.at.is_finite() and not flag.mounted:
					_props[index].transform = Transform3D(Basis.IDENTITY, flag.at)
					_cloth[index].set_shader_parameter("flutter", 1.0)
		LAYOUT.DEFUSE:
			for index in _zones.size():
				_zones[index].visible = index < state.sites
				_markers[index].text = ["ТОЧКА A", "ТОЧКА B"][index]
			var at: Vector3 = state.planted if state.planted.is_finite() else state.drop
			_props[0].visible = at.is_finite()
			if at.is_finite():
				_props[0].transform = Transform3D(Basis.IDENTITY, at)



func _paint(parent: Node3D, radius: float, color: Color, title: String) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, shadows_disabled, depth_draw_never;
uniform vec4 tint : source_color;
uniform sampler2D weathering : source_color;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float dashes = step(0.21, fract(a * 3.81972));
	float line = smoothstep(0.88, 0.895, r) * (1.0 - smoothstep(0.98, 1.0, r));
	float grain = texture(weathering, UV * 1.4).r;
	ALBEDO = tint.rgb * mix(0.64, 1.0, grain);
	ROUGHNESS = 0.98;
	ALPHA = (line * dashes * 0.89 + (1.0 - smoothstep(0.96, 1.0, r)) * 0.12) * mix(0.64, 1.0, grain);
}
"""
	material.shader = shader
	material.set_shader_parameter("tint", color)
	material.set_shader_parameter("weathering", PAINT)
	plane.material = material
	var paint := _mesh(parent, plane, Vector3.UP * 0.021, null)
	paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if DisplayServer.get_name() != "headless" and _director.game.map_id in [3, 4, 9, 11]:
		_fit_paint_to_ground(paint, radius, material)
	var label := _label(parent, title, color)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.rotation.x = -PI * 0.5
	label.position = Vector3(0.0, 0.026, 1.3)
	label.pixel_size = 0.017
	label.outline_size = 0


func _fit_paint_to_ground(paint: MeshInstance3D, radius: float, material: Material) -> void:
	await get_tree().physics_frame
	if not is_instance_valid(paint):
		return
	const STEPS := 12
	var center: Vector3 = paint.get_parent().global_position
	var space := get_world_3d().direct_space_state
	var vertices := PackedVector3Array()
	var varied := false
	var up := Vector3.UP
	for row in STEPS + 1:
		for column in STEPS + 1:
			var offset := Vector3(float(column) / STEPS * 2.0 - 1.0, 0.0, float(row) / STEPS * 2.0 - 1.0) * radius
			var at := center + offset
			var ray := PhysicsRayQueryParameters3D.create(at + up * 0.50, at - up * 0.58, _director.game.Balance.WORLD_MASK)
			var floor := space.intersect_ray(ray)
			if floor.is_empty() or floor.normal.y < 0.62:
				vertices.append(Vector3.INF)
			else:
				var height: float = floor.position.y - center.y
				varied = varied or absf(height) > 0.015
				vertices.append(offset + up * height)
	if not varied:
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	for row in STEPS:
		for column in STEPS:
			var a := row * (STEPS + 1) + column
			var b := a + 1
			var c := a + STEPS + 1
			var d := c + 1
			for triangle in [[a, b, c], [b, d, c]]:
				if not (vertices[triangle[0]].is_finite() and vertices[triangle[1]].is_finite() and vertices[triangle[2]].is_finite()):
					continue
				for index in triangle:
					var vertex := vertices[index]
					surface.set_normal(up)
					surface.set_uv(Vector2(vertex.x, vertex.z) / (2.0 * radius) + Vector2.ONE * 0.5)
					surface.add_vertex(vertex)
	var fitted := surface.commit()
	if fitted and fitted.get_surface_count() > 0:
		paint.mesh = fitted


func _label(parent: Node3D, text: String, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position.y = 2.95
	label.font_size = 46
	label.pixel_size = 0.009
	label.modulate = color.lightened(0.21)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	return label


func _metal(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = STEEL
	material.normal_enabled = true
	material.normal_texture = STEEL_NORMAL
	material.metallic = 0.52
	material.roughness = 0.7
	return material


func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, finish: Material) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = finish
	piece.position = at
	parent.add_child(piece)
	return piece


func _box(parent: Node3D, size: Vector3, at: Vector3, finish: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	_mesh(parent, box, at, finish)


func _flag(color: Color) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.hide()
	var steel := _metal(Color("#c1c2b8"))
	var pole := CylinderMesh.new()
	pole.top_radius = 0.025
	pole.bottom_radius = 0.034
	pole.height = 2.55
	_mesh(root, pole, Vector3.UP * 1.275, steel)
	var ball := SphereMesh.new()
	ball.radius = 0.045
	ball.height = 0.09
	_mesh(root, ball, Vector3.UP * 2.56, steel)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1.28, 0.72)
	mesh.orientation = PlaneMesh.FACE_Z
	mesh.subdivide_width = 24
	mesh.subdivide_depth = 12
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 tint : source_color;
uniform float flutter = 1.0;
uniform sampler2D fabric_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
void vertex() {
	VERTEX.z += (sin(UV.x * 8.0 - TIME * 3.1) * 0.11 + cos(UV.x * 14.0 + UV.y * 4.0 - TIME * 2.4) * 0.033) * UV.x * flutter;
	VERTEX.y -= UV.x * UV.x * 0.1;
}
void fragment() {
	float hem = step(0.034, UV.y) - step(0.955, UV.y);
	float stripe = smoothstep(0.56, 0.59, UV.y + UV.x * 0.49) - smoothstep(0.65, 0.68, UV.y + UV.x * 0.49);
	ALBEDO = mix(tint.rgb * (0.69 + hem * 0.31), vec3(0.89), stripe * 0.71);
	NORMAL_MAP = texture(fabric_normal, UV * vec2(4.2, 2.4)).rgb;
	NORMAL_MAP_DEPTH = 0.64;
	ROUGHNESS = 0.93;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tint", color)
	material.set_shader_parameter("fabric_normal", FABRIC_NORMAL)
	_cloth.append(material)
	_mesh(root, mesh, Vector3(0.658, 2.06, 0), material)
	return root


func _charge() -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.hide()
	var steel := _metal(Color("#4c5354"))
	var rubber := _metal(Color("#202724"))
	var screen := StandardMaterial3D.new()
	screen.albedo_color = Color("#ffc04d")
	screen.emission_enabled = true
	screen.emission = Color("#e58c23")
	_box(root, Vector3(0.43, 0.13, 0.32), Vector3.UP * 0.074, rubber)
	_box(root, Vector3(0.34, 0.045, 0.25), Vector3.UP * 0.15, steel)
	_box(root, Vector3(0.23, 0.009, 0.067), Vector3(0, 0.177, -0.065), screen)
	for row in 3:
		for column in 4:
			_box(root, Vector3(0.035, 0.014, 0.025), Vector3((column - 1.5) * 0.047, 0.178, row * 0.03), rubber)
	return root


func play_completion(at: Vector3) -> void:
	if not at.is_finite():
		return
	var sound := AudioStreamPlayer3D.new()
	sound.stream = preload("res://assets/arsenal/explosion.wav")
	sound.unit_size = 7.0
	add_child(sound)
	sound.global_position = at
	sound.finished.connect(sound.queue_free)
	sound.play()
	_completion_flash(at)



func _completion_flash(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color("#ffbd5c")
	light.light_energy = 7.0
	light.omni_range = 12.0
	add_child(light)
	light.global_position = at + Vector3.UP * 0.45
	var pulse := light.create_tween()
	pulse.tween_property(light, "light_energy", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pulse.tween_callback(light.queue_free)
