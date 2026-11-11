extends Node3D

const SURFACES := {
	"metal": [Color(1.0, 0.61, 0.22), Color(0.38, 0.42, 0.44), 11, 0.0],
	"brick": [Color(0.66, 0.34, 0.24), Color(0.48, 0.29, 0.23), 7, 0.22],
	"wood": [Color(0.72, 0.52, 0.28), Color(0.54, 0.40, 0.27), 7, 0.34],
	"concrete": [Color(0.71, 0.68, 0.60), Color(0.55, 0.52, 0.46), 7, 0.16],
	"operator": [Color(0.48, 0.12, 0.09), Color(0.37, 0.10, 0.08), 5, 0.05],
}
const FLASH_SIZE := {"deagle": 0.21, "shotgun": 0.32, "ak47": 0.26}
const MARK_SIZE := {"deagle": 0.065, "shotgun": 0.035, "ak47": 0.055}
const SHOT_SOUNDS := {
	"deagle": preload("res://assets/weapon_audio/deagle_fire.wav"),
	"shotgun": preload("res://assets/weapon_audio/shotgun_fire.wav"),
	"ak47": preload("res://assets/ak47/fire.wav"),
}

var _soft: Texture2D
var _flare: Texture2D
var _pit: Texture2D
var _particle_meshes: Dictionary = {}
var _trace_meshes: Dictionary = {}
var _marks: Array[MeshInstance3D] = []


func _ready() -> void:
	_soft = _mask("smoke")
	_flare = _mask("flash")
	_pit = _mask("pit")


func clear() -> void:
	for child in get_children():
		child.queue_free()
	_marks.clear()


func muzzle(profile: String, barrel: Transform3D, motion: Vector3, spatial_audio: bool) -> void:
	var forward := -barrel.basis.z.normalized()
	var position := barrel.origin
	if spatial_audio:
		_play_spatial_shot(profile, position)
	var size: float = FLASH_SIZE[profile]
	var flash := MeshInstance3D.new()
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size * randf_range(0.83, 1.15)
	var flash_material := _sprite(_flare, Color(1.0, 0.61, 0.19))
	flash_material.emission_enabled = true
	flash_material.emission = Color(1.0, 0.57, 0.19)
	flash_material.emission_energy_multiplier = 2.2
	flash_material.emission_texture = _flare
	quad.material = flash_material
	flash.mesh = quad
	add_child(flash)
	flash.global_position = position + forward * size * 0.25
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.71, 0.38)
	light.light_energy = size * 16.0
	light.omni_range = 3.0
	flash.add_child(light)
	var fade := flash.create_tween()
	fade.tween_property(flash_material, "albedo_color:a", 0.0, 0.045)
	fade.parallel().tween_property(light, "light_energy", 0.0, 0.045)
	fade.tween_callback(flash.queue_free)
	var drift := (forward * 1.6 + motion * 0.22 + Vector3.UP * 0.4).normalized()
	_burst(position + forward * size * 0.33, drift, Color(0.60, 0.60, 0.56, 0.12), 4,
		0.34, 1.7 + motion.length() * 0.15, 24.0, size * 0.29, Vector3.UP * 0.9, "smoke")


func _play_spatial_shot(profile: String, at: Vector3) -> void:
	# Keep each report at the point where it was fired, even if the shooter moves.
	var sound := AudioStreamPlayer3D.new()
	sound.stream = SHOT_SOUNDS[profile]
	sound.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	sound.unit_size = 4.0
	sound.max_distance = 56.0
	sound.volume_db = -5.0 if profile == "ak47" else 0.0
	sound.max_db = sound.volume_db - 5.0
	sound.attenuation_filter_db = -12.0
	sound.panning_strength = 1.5
	sound.pitch_scale = randf_range(0.97, 1.03)
	add_child(sound)
	sound.global_position = at
	sound.finished.connect(sound.queue_free)
	sound.play()


func impact(at: Vector3, normal: Vector3, surface: String, profile: String, leave_mark: bool = true) -> void:
	var data: Array = SURFACES.get(surface, SURFACES["concrete"])
	var position := at + normal * 0.012
	var amount: int = data[2]
	var strength := 0.68 if profile == "shotgun" else 1.0
	var dust: Color = data[1]
	dust.a = 0.19 if surface == "metal" else 0.31
	var lifetime := 0.33 if surface == "operator" else 0.49
	_burst(position, normal, dust, 4, lifetime, 2.6 * strength, 48.0,
		0.14 * strength, Vector3.UP * 0.35, "smoke")
	if surface != "operator":
		var metal := surface == "metal"
		_burst(position, normal, data[0], amount, 0.22 if metal else 0.42,
			9.0 if metal else 4.0, 55.0, 0.018 * strength, Vector3.DOWN * 12.0,
			"spark" if metal else "chip", float(data[3]))
		if leave_mark:
			_mark(at, normal, surface, float(MARK_SIZE[profile]))
	else:
		_burst(position, normal, data[0], amount, 0.24, 3.6, 46.0, 0.015,
			Vector3.DOWN * 9.8, "chip")


func tracer(ammo: Dictionary) -> MeshInstance3D:
	var streak := MeshInstance3D.new()
	var color: Color = ammo.color
	if not _trace_meshes.has(color):
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.8
		mesh.material = material
		_trace_meshes[color] = mesh
	streak.mesh = _trace_meshes[color]
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	streak.set_meta("width", float(ammo.width))
	streak.hide()
	add_child(streak)
	return streak


func move_tracer(streak: MeshInstance3D, at: Vector3, direction: Vector3, distance: float) -> void:
	var length := minf(distance, streak.get_meta("trail"))
	var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.96 else Vector3.UP
	var width: float = streak.get_meta("width")
	var basis := Basis.looking_at(direction, up).scaled_local(Vector3(width, width, length))
	streak.global_transform = Transform3D(basis, at - direction * length * 0.5)
	streak.visible = length > 0.04


func _burst(at: Vector3, axis: Vector3, tint: Color, amount: int, duration: float,
		speed: float, spread: float, size: float, gravity: Vector3, kind: String, stretch: float = 0.0) -> void:
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = amount
	particles.lifetime = duration
	particles.explosiveness = 0.92
	particles.local_coords = false
	particles.direction = axis
	particles.spread = spread
	particles.initial_velocity_min = speed * 0.34
	particles.initial_velocity_max = speed
	particles.gravity = gravity
	particles.damping_min = 1.0
	particles.damping_max = 2.4
	particles.scale_amount_min = size * 0.45
	particles.scale_amount_max = size
	particles.particle_flag_align_y = kind != "smoke"
	particles.mesh = _particle_mesh(kind, stretch)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([tint, Color(tint.r, tint.g, tint.b, 0.0)])
	particles.color_ramp = gradient
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.36 if kind == "smoke" else 1.0))
	curve.add_point(Vector2(1.0, 1.0 if kind == "smoke" else 0.30))
	particles.scale_amount_curve = curve
	add_child(particles)
	particles.global_position = at
	particles.emitting = true
	get_tree().create_timer(duration + 0.16, false).timeout.connect(particles.queue_free)


func _particle_mesh(kind: String, stretch: float) -> Mesh:
	var key := "%s:%s" % [kind, stretch]
	if _particle_meshes.has(key):
		return _particle_meshes[key]
	var mesh: PrimitiveMesh
	if kind == "smoke":
		var quad := QuadMesh.new()
		quad.material = _sprite(_soft, Color.WHITE, true)
		mesh = quad
	else:
		var chip := BoxMesh.new()
		chip.size = Vector3(0.43, 2.7 + stretch, 0.43) if kind == "spark" else Vector3(0.68, 1.0 + stretch, 0.37)
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if kind == "spark":
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		chip.material = material
		mesh = chip
	_particle_meshes[key] = mesh
	return mesh


func _mark(at: Vector3, normal: Vector3, surface: String, size: float) -> void:
	var mark := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size * randf_range(0.85, 1.16)
	var tint := Color(0.16, 0.17, 0.16, 0.84) if surface == "metal" else Color(0.12, 0.09, 0.07, 0.82)
	var material := _sprite(_pit, tint)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	quad.material = material
	mark.mesh = quad
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mark)
	var up := Vector3.RIGHT if absf(normal.dot(Vector3.UP)) > 0.96 else Vector3.UP
	mark.global_transform = Transform3D(Basis.looking_at(-normal, up), at + normal * 0.0025)
	mark.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	_marks.append(mark)
	if _marks.size() > 96:
		_marks.pop_front().queue_free()


func _sprite(texture: Texture2D, tint: Color, use_particle_color: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = tint
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = use_particle_color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _mask(kind: String) -> Texture2D:
	var image := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 313
	noise.frequency = 0.11
	for y in 64:
		for x in 64:
			var p := (Vector2(x, y) + Vector2.ONE * 0.5) / 32.0 - Vector2.ONE
			var radius := p.length()
			var alpha := 0.0
			var color := Color.WHITE
			match kind:
				"flash":
					var rays := pow(absf(cos(p.angle() * 3.0 + 0.4)), 11.0)
					alpha = exp(-radius * radius * 17.0) + rays * (1.0 - smoothstep(0.05, 0.97, radius)) * 0.7
					color = Color(1.0, lerpf(0.95, 0.35, minf(1.0, radius)), lerpf(0.66, 0.10, minf(1.0, radius)))
				"pit":
					alpha = 1.0 - smoothstep(0.19, 0.92, radius + noise.get_noise_2d(x, y) * 0.24)
				_:
					alpha = pow(1.0 - smoothstep(0.0, 0.99, radius), 1.65) * (0.62 + noise.get_noise_2d(x, y) * 0.57)
			color.a = clampf(alpha, 0.0, 1.0)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
