extends Node3D

const Balance := preload("res://game/combat/combat_balance.gd")
const Classic := preload("res://game/combat/classic_weapons.gd")
const Weapon := preload("res://game/combat/weapon.gd")
const SpatialAudio := preload("res://addons/spatial_audio_3d/spatial_audio_3d.gd")
const GRENADE_EXPLOSION := preload("res://game/combat/grenade_explosion.tscn")
const SHOT_HEARING_DISTANCE := 125.0
const SHOT_DISTANCE_LOSS_DB := 16.0

const SURFACES := {
	"metal": [Color(1.0, 0.61, 0.22), Color(0.38, 0.42, 0.44), 11, 0.0],
	"brick": [Color(0.66, 0.34, 0.24), Color(0.48, 0.29, 0.23), 7, 0.22],
	"wood": [Color(0.72, 0.52, 0.28), Color(0.54, 0.40, 0.27), 7, 0.34],
	"concrete": [Color(0.71, 0.68, 0.60), Color(0.55, 0.52, 0.46), 7, 0.16],
	"operator": [Color(0.48, 0.12, 0.09), Color(0.37, 0.10, 0.08), 5, 0.05],
}
const FLASH_SIZE := {"deagle": 0.21, "shotgun": 0.32, "ak47": 0.26, "m249": 0.27, "m14": 0.29, "m1": 0.32, "launcher": 0.38}
const MARK_SIZE := {"deagle": 0.12, "shotgun": 0.07, "ak47": 0.105, "m249": 0.095, "m14": 0.11, "m1": 0.115, "m700": 0.125}
const SHOT_SOUNDS := {
	"ak47": preload("res://assets/ak47/fire.wav"),
	"m249": preload("res://assets/arsenal/m249_fire.wav"),
	"m14": preload("res://assets/arsenal/m14_fire.wav"),
	"m1": preload("res://assets/arsenal/m1_fire.wav"),
	"launcher": preload("res://assets/arsenal/launcher_fire.wav"),
	"deagle": preload("res://assets/weapon_audio/deagle_fire.wav"),
	"shotgun": preload("res://assets/weapon_audio/shotgun_fire.wav"),
}
const IMPACT_SOUNDS := {
	"concrete": preload("res://assets/match_audio/hit_concrete.wav"),
	"metal": preload("res://assets/match_audio/hit_metal.wav"),
	"wood": preload("res://assets/match_audio/hit_wood.wav"),
	"operator": preload("res://assets/match_audio/hit_operator.wav"),
}
const IMPACT_HEARING_DISTANCE := 42.0
const IMPACT_VOICE_LIMIT := 16
const MAX_BURSTS := 32
const MUZZLE_VISUAL_DISTANCE := 58.0
const MUZZLE_LIGHT_DISTANCE := 27.0
const MAX_IMPACT_VISUAL_DISTANCE := 46.0
const MARK_DISTANCE := 85.0
const MAX_MARKS := 160


class Tracer extends MeshInstance3D:
	var trail_length: float
	var trail_width: float

	func _init(length: float, width: float) -> void:
		trail_length = length
		trail_width = width


var _soft: Texture2D
var _flare: Texture2D
var _pit: Texture2D
var _particle_meshes: Dictionary = {}
var _trace_meshes: Dictionary = {}
var _marks: Array[MeshInstance3D] = []
var _mark_meshes: Dictionary[bool, QuadMesh] = {}
var _flash_mesh: QuadMesh
var _burst_pool: Array[CPUParticles3D] = []
var _active_bursts := 0
var _burst_gradients: Dictionary[Color, Gradient] = {}
var _burst_curves: Dictionary[bool, Curve] = {}
var _combat_voices: Dictionary[StringName, Array] = {}
var _voice_cursor: Dictionary[StringName, int] = {}
var _impact_voices: Array[AudioStreamPlayer3D] = []


func _ready() -> void:
	_soft = _mask("smoke")
	_flare = _mask("flash")
	_pit = _mask("pit")
	_flash_mesh = QuadMesh.new()
	var material := _sprite(_flare, Color.WHITE)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.57, 0.19)
	material.emission_energy_multiplier = 2.2
	material.emission_texture = _flare
	_flash_mesh.material = material


func prepare_acoustics() -> void:
	if not _combat_voices.is_empty() or DisplayServer.get_name() == "headless":
		return
	for index in IMPACT_VOICE_LIMIT:
		var voice := AudioStreamPlayer3D.new()
		voice.bus = &"Gunfire"
		voice.unit_size = 7.0
		voice.max_distance = IMPACT_HEARING_DISTANCE
		voice.attenuation_filter_db = -8.0
		add_child(voice)
		_impact_voices.append(voice)
	for bus: StringName in [&"Gunfire", &"Explosions"]:
		var voices: Array[SpatialAudio] = []
		for index in (24 if bus == &"Gunfire" else 6):
			var voice := SpatialAudio.new()
			voice.bus = bus
			voice.panning_strength = 3.0
			voice.attenuation_filter_db = 0.0
			voice.collision_mask = Balance.WORLD_MASK
			voice.occlusion_lp_cutoff = 4700 if bus == &"Gunfire" else 5500
			if bus == &"Gunfire":
				voice.occlusion_min_lp_cutoff = 1800
			voice.occlusion_fadetime = 0.0
			voice.reverb_enabled = bus == &"Explosions" and index < 2
			voice.reflection_count = 2
			voice.reverb_volume_db = -12
			voice.max_raycast_distance = 28
			add_child(voice)
			voice.set_physics_process(false)
			voices.append(voice)
		_combat_voices[bus] = voices
		_voice_cursor[bus] = 0


func clear() -> void:
	_burst_pool.clear()
	for child in get_children():
		if child is SpatialAudio and child in _combat_voices.get(child.bus, []):
			child.do_stop()
			child.remove_meta(&"busy_until")
		elif child is AudioStreamPlayer3D and child in _impact_voices:
			child.stop()
			child.remove_meta(&"impact_started")
		elif child is CPUParticles3D:
			child.emitting = false
			child.hide()
			_burst_pool.append(child)
		else:
			child.queue_free()
	_active_bursts = 0
	_marks.clear()


func warm_rendering(ammo: Dictionary) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var barrel := camera.global_transform.translated_local(Vector3(0, 0, -2.0))
	var at := barrel.origin
	muzzle("ak47", barrel, Vector3.ZERO, false)
	for data in SURFACES.values():
		_burst(at, Vector3.UP, data[0], 2, 0.24, 1.5, 35.0, 0.03, Vector3.DOWN,
			"spark" if data == SURFACES["metal"] else "chip", float(data[3]))
	_mark(at, Vector3.UP, "concrete", 0.05)
	_mark(at, Vector3.UP, "metal", 0.05)
	for profile in ammo.values():
		if profile.trail > 0:
			var sample := tracer(profile)
			move_tracer(sample, at, -barrel.basis.z, 0.4)
	grenade_burst(at, false, 5.0, false)
	grenade_burst(at, true, 5.0, false)
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	clear()


func muzzle(profile: String, barrel: Transform3D, motion: Vector3, spatial_audio: bool) -> void:
	var forward := -barrel.basis.z.normalized()
	var position := barrel.origin
	if spatial_audio:
		_play_spatial_shot(profile, position)
	var camera := get_viewport().get_camera_3d()
	if not camera or DisplayServer.get_name() == "headless":
		return
	var distance_sq := camera.global_position.distance_squared_to(position)
	if distance_sq > MUZZLE_VISUAL_DISTANCE * MUZZLE_VISUAL_DISTANCE:
		return
	var size: float = FLASH_SIZE.get(profile, 0.23 * sqrt(float(Weapon.WEAPONS[profile].kick) / 0.045))
	var flash := MeshInstance3D.new()
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.mesh = _flash_mesh
	flash.scale = Vector3.ONE * size * randf_range(0.83, 1.15)
	add_child(flash)
	flash.global_position = position + forward * size * 0.25
	var fade := flash.create_tween()
	fade.tween_property(flash, "transparency", 1.0, 0.045)
	if distance_sq <= MUZZLE_LIGHT_DISTANCE * MUZZLE_LIGHT_DISTANCE:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.71, 0.38)
		light.light_energy = size * 16.0
		light.omni_range = 3.0
		flash.add_child(light)
		fade.parallel().tween_property(light, "light_energy", 0.0, 0.045)
		var drift := (forward * 1.6 + motion * 0.22 + Vector3.UP * 0.4).normalized()
		_burst(position + forward * size * 0.33, drift, Color(0.60, 0.60, 0.56, 0.12), 4,
			0.34, 1.7 + motion.length() * 0.15, 24.0, size * 0.29, Vector3.UP * 0.9, "smoke")
	fade.tween_callback(flash.queue_free)


static func shot_sound(profile: String) -> AudioStream:
	if profile != "ak47" and Classic.SHOT_COUNTS.has(profile):
		return Classic.shot_sound(profile)
	return SHOT_SOUNDS[profile]


func _play_spatial_shot(profile: String, at: Vector3) -> void:
	var level := -4.0 if profile in ["ak47", "m249"] else -2.0
	play_combat_sound(shot_sound(profile), at, level, SHOT_HEARING_DISTANCE, &"Gunfire")


func play_combat_sound(clip: AudioStream, at: Vector3, gain: float, reach: float, bus: StringName) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera or not _combat_voices.has(bus):
		return
	var distance := camera.global_position.distance_to(at)
	if reach <= 0.0 or distance > reach:
		return
	var is_gunfire := bus == &"Gunfire"
	# Apply gunfire falloff at emission so crossing the hearing limit cannot cut off a shot.
	var level := gain - SHOT_DISTANCE_LOSS_DB * distance / reach if is_gunfire else gain
	var voices: Array = _combat_voices[bus]
	var start := _voice_cursor[bus]
	var now := Time.get_ticks_msec()
	for offset in voices.size():
		var index := (start + offset) % voices.size()
		var voice: SpatialAudio = voices[index]
		if now < int(voice.get_meta(&"busy_until", 0)):
			continue
		_voice_cursor[bus] = (index + 1) % voices.size()
		voice.do_stop()
		voice.global_position = at + Vector3.UP * 0.10
		for player in [voice.soundsource.soundplayer_active, voice.soundsource.soundplayer_standby]:
			player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
			player.max_db = level
			player.max_distance = 0.0 if is_gunfire else reach
		var travel_time := distance / float(voice.speed_of_sound)
		var pitch := randf_range(0.97, 1.03)
		var tail := 0.35 if bus == &"Explosions" else 0.08
		voice.set_meta(&"busy_until", now + ceili((clip.get_length() / pitch + travel_time + tail) * 1000.0))
		voice.play_one_shot(clip, level, pitch)
		return


func _play_impact_sound(at: Vector3, surface: String, strength: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera or camera.global_position.distance_squared_to(at) > IMPACT_HEARING_DISTANCE * IMPACT_HEARING_DISTANCE:
		return
	var clip: AudioStream = IMPACT_SOUNDS.get(surface, IMPACT_SOUNDS["concrete"])
	var now := Time.get_ticks_msec()
	var available: AudioStreamPlayer3D
	for voice in _impact_voices:
		if voice.playing:
			# Group nearby pellets while preserving impacts at other positions or on other materials.
			if voice.stream == clip and now - int(voice.get_meta(&"impact_started", 0)) < 32 and voice.global_position.distance_squared_to(at) < 4.0:
				return
		elif available == null:
			available = voice
	if available == null:
		return
	available.stream = clip
	available.volume_db = -7.0 + linear_to_db(strength)
	available.max_db = available.volume_db + 2.0
	available.pitch_scale = randf_range(0.96, 1.04)
	available.global_position = at
	available.set_meta(&"impact_started", now)
	available.play()


func impact(at: Vector3, normal: Vector3, surface: String, profile: String, remaining_force: float = 1.0, leave_mark: bool = true) -> void:
	var power := 0.68 if profile == "shotgun" else sqrt(float(Weapon.WEAPONS[profile].damage) / 45.0)
	var strength := clampf(power * remaining_force, 0.32, 1.45)
	_play_impact_sound(at, surface, strength)
	var camera := get_viewport().get_camera_3d()
	if not camera or DisplayServer.get_name() == "headless":
		return
	var distance_sq := camera.global_position.distance_squared_to(at)
	if leave_mark and surface != "operator" and distance_sq <= MARK_DISTANCE * MARK_DISTANCE:
		_mark(at, normal, surface, float(MARK_SIZE.get(profile, 0.105)) * sqrt(strength))
	if distance_sq > MAX_IMPACT_VISUAL_DISTANCE * MAX_IMPACT_VISUAL_DISTANCE:
		return
	var data: Array = SURFACES.get(surface, SURFACES["concrete"])
	var position := at + normal * 0.012
	var amount: int = data[2]
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
	else:
		_burst(position, normal, data[0], amount, 0.24, 3.6, 46.0, 0.015,
			Vector3.DOWN * 9.8, "chip")


func grenade_burst(at: Vector3, flash: bool, radius: float, launcher: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var camera := get_viewport().get_camera_3d()
	if not camera or camera.global_position.distance_squared_to(at) > 95.0 * 95.0:
		return
	var scale := radius / 5.0 * (0.82 if launcher else 1.0)
	var center := at + Vector3.UP * 0.38 * scale
	var light := OmniLight3D.new()
	light.position = center
	light.light_color = Color(0.85, 0.91, 1.0) if flash else Color(1.0, 0.66, 0.30)
	light.light_energy = 6.4 if flash else 10.0 * scale
	light.omni_range = 12.0 if flash else radius * 2.4 * scale
	light.shadow_enabled = not flash and camera.global_position.distance_squared_to(at) < 28.0 * 28.0
	add_child(light)
	var light_fade := light.create_tween()
	var light_decay := light_fade.tween_property(light, "light_energy", 0.0, 0.16 if flash else 0.27)
	if not flash:
		light_decay.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	light_fade.tween_callback(light.queue_free)
	_burst(center, Vector3.UP, Color(1.0, 0.74, 0.29), 10 if flash else (32 if launcher else 44),
		0.52, 13.0 * scale, 125.0, 0.062 * scale, Vector3.DOWN * 9.8, "spark", 1.2)
	if flash:
		var core := MeshInstance3D.new()
		core.mesh = _flash_mesh
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		core.position = center
		core.scale = Vector3.ONE * 1.35
		add_child(core)
		var fade := core.create_tween().set_parallel(true)
		fade.tween_property(core, "transparency", 1.0, 0.14)
		fade.tween_property(core, "scale", core.scale * 1.55, 0.14)
		fade.chain().tween_callback(core.queue_free)
		return
	var explosion := GRENADE_EXPLOSION.instantiate() as GPUParticles3D
	explosion.position = center
	explosion.scale = Vector3.ONE * scale
	explosion.finished.connect(explosion.queue_free)
	add_child(explosion)
	explosion.emitting = true
	_burst(at + Vector3.UP * 0.18, Vector3.UP, Color(0.53, 0.45, 0.34, 0.35),
		12, 0.94, 6.3 * scale, 115.0, 0.85 * scale, Vector3.UP * 0.40, "smoke")


func tracer(ammo: Dictionary) -> Tracer:
	var streak := Tracer.new(float(ammo.trail), float(ammo.width))
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
	streak.hide()
	add_child(streak)
	return streak


func move_tracer(streak: Tracer, at: Vector3, direction: Vector3, distance: float) -> void:
	var length := minf(distance, streak.trail_length)
	if length <= 0.04:
		streak.hide()
		return
	var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.96 else Vector3.UP
	var width := streak.trail_width
	var orientation := Basis.looking_at(direction, up).scaled_local(Vector3(width, width, length))
	streak.global_transform = Transform3D(orientation, at - direction * length * 0.5)
	streak.show()


func _burst(at: Vector3, axis: Vector3, tint: Color, amount: int, duration: float,
		speed: float, spread: float, size: float, gravity: Vector3, kind: String, stretch: float = 0.0) -> void:
	if DisplayServer.get_name() == "headless" or _active_bursts >= MAX_BURSTS:
		return
	var particles: CPUParticles3D
	if _burst_pool.is_empty():
		particles = CPUParticles3D.new()
		particles.emitting = false
		particles.one_shot = true
		particles.local_coords = false
		particles.explosiveness = 0.92
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		particles.finished.connect(_recycle_burst.bind(particles))
		add_child(particles)
	else:
		particles = _burst_pool.pop_back()
	_active_bursts += 1
	particles.show()
	particles.amount = amount
	particles.lifetime = duration
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
	if not _burst_gradients.has(tint):
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([tint, Color(tint.r, tint.g, tint.b, 0.0)])
		_burst_gradients[tint] = gradient
	var smoke := kind == "smoke"
	if not _burst_curves.has(smoke):
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.36 if smoke else 1.0))
		curve.add_point(Vector2(1.0, 1.0 if smoke else 0.30))
		_burst_curves[smoke] = curve
	particles.color_ramp = _burst_gradients[tint]
	particles.scale_amount_curve = _burst_curves[smoke]
	particles.global_position = at
	particles.restart()


func _recycle_burst(particles: CPUParticles3D) -> void:
	if particles.is_queued_for_deletion() or particles in _burst_pool:
		return
	particles.hide()
	_active_bursts -= 1
	_burst_pool.append(particles)


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
	var mark: MeshInstance3D
	if _marks.size() < MAX_MARKS:
		mark = MeshInstance3D.new()
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mark.visibility_range_end = MARK_DISTANCE
		add_child(mark)
	else:
		mark = _marks.pop_front()
	var metal := surface == "metal"
	if not _mark_meshes.has(metal):
		var mesh := QuadMesh.new()
		var material := _sprite(_pit, Color(0.88, 0.93, 0.96) if metal else Color(0.95, 0.85, 0.70))
		material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		mesh.material = material
		_mark_meshes[metal] = mesh
	mark.mesh = _mark_meshes[metal]
	var up := Vector3.RIGHT if absf(normal.dot(Vector3.UP)) > 0.96 else Vector3.UP
	mark.global_transform = Transform3D(Basis.looking_at(-normal, up), at + normal * 0.006)
	mark.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	mark.scale = Vector3.ONE * size * randf_range(0.85, 1.16)
	_marks.append(mark)


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
					var edge := radius + noise.get_noise_2d(x, y) * 0.26
					var rim := smoothstep(0.36, 0.51, edge) * (1.0 - smoothstep(0.60, 0.80, edge))
					color = Color(0.045, 0.035, 0.026).lerp(Color(0.66, 0.57, 0.46), rim)
					alpha = 1.0 - smoothstep(0.62, 0.96, edge)
				_:
					alpha = pow(1.0 - smoothstep(0.0, 0.99, radius), 1.65) * (0.62 + noise.get_noise_2d(x, y) * 0.57)
			color.a = clampf(alpha, 0.0, 1.0)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
