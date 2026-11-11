extends Node3D

const AK47_MODEL := preload("res://assets/ak47/ak47.tscn")
const AK47_SHOT := preload("res://assets/ak47/fire.wav")
const AK47_RELOAD := preload("res://assets/ak47/reload.wav")

const WEAPONS := {
	"deagle": {
		"name": "DESERT EAGLE",
		"mode": "одиночный",
		"mag": 7,
		"reserve": 35,
		"reload": 1.45,
		"cooldown": 0.28,
		"pellets": 1,
		"spread": 0.2,
		"range": 90.0,
		"recoil": 1.7,
		"recoil_yaw": 0.35,
		"kick": 0.045,
		"mark": 0.085,
		"tracer": Color(1.0, 0.84, 0.4),
		"tracer_size": 0.012,
		"damage": 52,
		"damage_min": 34,
		"falloff_start": 16.0,
		"falloff_end": 48.0,
	},
	"shotgun": {
		"name": "ДРОБОВИК",
		"mode": "помповый",
		"mag": 6,
		"reserve": 24,
		"reload": 2.15,
		"cooldown": 0.82,
		"pellets": 8,
		"spread": 5.4,
		"range": 34.0,
		"recoil": 3.3,
		"recoil_yaw": 0.85,
		"kick": 0.09,
		"mark": 0.032,
		"tracer": Color(1.0, 0.7, 0.32),
		"tracer_size": 0.007,
		"damage": 14,
		"damage_min": 3,
		"falloff_start": 5.0,
		"falloff_end": 18.0,
	},
	"ak47": {
		"name": "AK-47",
		"mode": "автоматический",
		"automatic": true,
		"mag": 30,
		"reserve": 90,
		"reload": 1.75,
		"cooldown": 0.11,
		"pellets": 1,
		"spread": 0.85,
		"range": 75.0,
		"recoil": 0.9,
		"recoil_yaw": 0.28,
		"kick": 0.035,
		"mark": 0.05,
		"tracer": Color(1.0, 0.8, 0.36),
		"tracer_size": 0.008,
		"damage": 24,
		"damage_min": 14,
		"falloff_start": 15.0,
		"falloff_end": 50.0,
	},
}

var _weapon_id := ""
var _stats: Dictionary = {}
var _mag := 0
var _reserve := 0
var _cooldown := 0.0
var _reload_left := 0.0
var _reload_time := 1.0
var _reloading := false
var _active := false
var _trigger_held := false
var _reload_held := false
var _kick_pos := Vector3.ZERO
var _kick_rot := 0.0
var _bob_t := 0.0
var _flash_left := 0.0
var _shell_wait := 0.0
var _rest_pos := Vector3.ZERO

var _view: Node3D
var _muzzle: Marker3D
var _flash: OmniLight3D
var _shot_player: AudioStreamPlayer
var _shell_player: AudioStreamPlayer
var _reload_player: AudioStreamPlayer
var _world_shot: AudioStreamPlayer3D
var _world_shell: AudioStreamPlayer3D
var _world_reload: AudioStreamPlayer3D
var _last_net_msec := 0
var _shot_deagle: AudioStream
var _shotgun_shot: AudioStream
var _shotgun_reload: AudioStream
var _shotgun_shell: AudioStream
var _dry: AudioStream
var _marks: Array[Node3D] = []

@onready var _camera: Camera3D = get_parent()
@onready var _player = get_parent().get_parent()
@onready var _ammo: Label = get_node("../../../HUD/Ammo")
@onready var _cross: ColorRect = get_node("../../../HUD/Crosshair")
@onready var _cross_v: ColorRect = get_node("../../../HUD/CrosshairV")


func _ready() -> void:
	_shot_player = _make_player()
	_shot_player.max_polyphony = 5
	_shell_player = _make_player()
	_reload_player = _make_player()
	_world_shot = _make_world_player()
	_world_shot.max_polyphony = 5
	_world_shell = _make_world_player()
	_world_shell.volume_db = -4.0
	_world_reload = _make_world_player()
	_world_reload.stream = AK47_RELOAD
	_world_reload.volume_db = -8.0
	_shot_deagle = _make_shot(true)
	_dry = _make_dry()
	_shotgun_shot = load("res://drob/выстрел.mp3") as AudioStream
	_shotgun_reload = load("res://drob/перезарядка.mp3") as AudioStream
	_shotgun_shell = load("res://drob/гильза.mp3") as AudioStream


func equip(weapon_id: String) -> void:
	_weapon_id = weapon_id
	_stats = WEAPONS[weapon_id]
	_mag = int(_stats["mag"])
	_reserve = int(_stats["reserve"])
	_cooldown = 0.0
	_reload_left = 0.0
	_reloading = false
	_shot_player.stop()
	_shell_player.stop()
	_reload_player.stop()
	_shell_wait = 0.0
	_active = true
	_trigger_held = false
	_build_viewmodel(weapon_id)
	_update_hud()
	_ammo.visible = true


func _process(delta: float) -> void:
	if not _active:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)
	if _shell_wait > 0.0:
		_shell_wait = maxf(_shell_wait - delta, 0.0)
		if _shell_wait == 0.0:
			_play_shell()
	if _flash:
		_flash.light_energy = 5.0 if _flash_left > 0.0 else 0.0
	if _reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
	_kick_pos = _kick_pos.lerp(Vector3.ZERO, minf(1.0, delta * 9.0))
	_kick_rot = lerpf(_kick_rot, 0.0, minf(1.0, delta * 9.0))
	_apply_view(delta)

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not _player.control_enabled:
		_trigger_held = false
		return

	var shooting := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var repeat := bool(_stats.get("automatic", false)) and (_mag > 0 or _reserve > 0)
	if shooting and (not _trigger_held or repeat):
		_try_fire()
	_trigger_held = shooting

	var reload_key := Input.is_physical_key_pressed(KEY_R)
	if reload_key and not _reload_held:
		_start_reload()
	_reload_held = reload_key


func _try_fire() -> void:
	if _reloading or _cooldown > 0.0:
		return
	if _mag <= 0:
		if _reserve > 0:
			_start_reload()
		else:
			_play_on(_shot_player, _dry, -2.0, false)
		return
	_mag -= 1
	_cooldown = float(_stats["cooldown"])
	_shoot()
	_update_hud()


func _shoot() -> void:
	var from := _camera.global_position
	var dirs := PackedVector3Array()
	for _pellet in int(_stats["pellets"]):
		dirs.append(_ray_direction(float(_stats["spread"])))
	var result := _cast_all(_weapon_id, from, dirs, _authoritative())
	var muzzle: Vector3 = _muzzle.global_position if _muzzle else from
	_show_shot(muzzle, result, true)
	_flash_left = 0.05
	_kick_pos = Vector3(randf_range(-0.008, 0.008), randf_range(0.0, 0.012), float(_stats["kick"]))
	_kick_rot = -float(_stats["recoil"]) * 1.4
	_player.add_recoil(float(_stats["recoil"]), randf_range(-float(_stats["recoil_yaw"]), float(_stats["recoil_yaw"])))
	var volume := -5.0 if _weapon_id == "ak47" else 0.0
	_play_on(_shot_player, _shot_stream(_weapon_id), volume, true)
	if _weapon_id == "shotgun":
		_shell_wait = 0.38
	if not Net.active:
		return
	var ends: PackedVector3Array = result["ends"]
	var kinds: PackedInt32Array = result["kinds"]
	var normals: PackedVector3Array = result["normals"]
	var net_muzzle: Vector3 = result["muzzle"]
	if multiplayer.is_server():
		net_visual.rpc(_weapon_id, net_muzzle, ends, kinds, normals)
	else:
		net_fire.rpc(_weapon_id, from, dirs)


func _authoritative() -> bool:
	return not Net.active or multiplayer.is_server()


func _cast_all(weapon_name: String, from: Vector3, dirs: PackedVector3Array, apply_damage: bool) -> Dictionary:
	var stats: Dictionary = WEAPONS[weapon_name]
	var space := _camera.get_world_3d().direct_space_state
	var ends := PackedVector3Array()
	var kinds := PackedInt32Array()
	var normals := PackedVector3Array()
	var reach := float(stats["range"])
	var cap := int(stats["pellets"])
	var count := mini(dirs.size(), cap)
	for index in count:
		var direction: Vector3 = dirs[index]
		if direction.length_squared() < 0.001:
			continue
		direction = direction.normalized()
		var end := from + direction * reach
		var kind := 2
		var normal := Vector3.ZERO
		var query := PhysicsRayQueryParameters3D.create(from, end)
		query.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			end = hit["position"]
			if _damage_body(hit["collider"], from.distance_to(end), apply_damage, stats):
				kind = 1
			else:
				kind = 0
				normal = hit["normal"]
		ends.append(end)
		kinds.append(kind)
		normals.append(normal)
	var forward := -_camera.global_transform.basis.z
	return {
		"ends": ends,
		"kinds": kinds,
		"normals": normals,
		"muzzle": from + forward * 0.45,
	}


func _show_shot(muzzle: Vector3, result: Dictionary, local_view: bool) -> void:
	var ends: PackedVector3Array = result["ends"]
	var kinds: PackedInt32Array = result["kinds"]
	var normals: PackedVector3Array = result["normals"]
	var any_hit := false
	for index in ends.size():
		_spawn_tracer(muzzle, ends[index])
		if kinds[index] == 2:
			continue
		any_hit = true
		if kinds[index] == 1:
			_spawn_blood(ends[index])
		else:
			_spawn_impact(ends[index], normals[index])
	if any_hit and local_view:
		_flash_crosshair()


@rpc("authority", "reliable")
func net_fire(weapon_name: String, from: Vector3, dirs: PackedVector3Array) -> void:
	if not multiplayer.is_server() or not WEAPONS.has(weapon_name):
		return
	var now := Time.get_ticks_msec()
	var wait := int(float(WEAPONS[weapon_name]["cooldown"]) * 750.0)
	if now - _last_net_msec < wait:
		return
	_last_net_msec = now
	var origin := _camera.global_position
	if from.distance_to(origin) > 3.0:
		from = origin
	var result := _cast_all(weapon_name, from, dirs, true)
	_stats = WEAPONS[weapon_name]
	_show_shot(result["muzzle"], result, false)
	_play_world_shot(weapon_name)
	if _player.has_method("play_shot_anim"):
		_player.play_shot_anim()
	var shooter := get_multiplayer_authority()
	var ends: PackedVector3Array = result["ends"]
	var kinds: PackedInt32Array = result["kinds"]
	var normals: PackedVector3Array = result["normals"]
	var muzzle: Vector3 = result["muzzle"]
	for peer_id in multiplayer.get_peers():
		if peer_id == shooter:
			continue
		net_visual.rpc_id(peer_id, weapon_name, muzzle, ends, kinds, normals)


@rpc("authority", "reliable")
func net_visual(weapon_name: String, muzzle: Vector3, ends: PackedVector3Array, kinds: PackedInt32Array, normals: PackedVector3Array) -> void:
	if not WEAPONS.has(weapon_name):
		return
	_stats = WEAPONS[weapon_name]
	_show_shot(muzzle, {"ends": ends, "kinds": kinds, "normals": normals}, false)
	_play_world_shot(weapon_name)
	if _player.has_method("play_shot_anim"):
		_player.play_shot_anim()


func _play_world_shot(weapon_name: String) -> void:
	var stream := _shot_stream(weapon_name)
	if _world_shot == null or stream == null:
		return
	if _world_shot.stream != stream:
		_world_shot.stream = stream
	_world_shot.volume_db = -5.0 if weapon_name == "ak47" else 0.0
	_world_shot.pitch_scale = randf_range(0.97, 1.03)
	_world_shot.play()
	if weapon_name == "shotgun":
		get_tree().create_timer(0.38).timeout.connect(_play_world_shell)


func _shot_stream(weapon_name: String) -> AudioStream:
	match weapon_name:
		"ak47":
			return AK47_SHOT
		"shotgun":
			return _shotgun_shot
		_:
			return _shot_deagle


func _play_world_shell() -> void:
	if _world_shell == null or _shotgun_shell == null:
		return
	_world_shell.stream = _shotgun_shell
	_world_shell.pitch_scale = randf_range(0.97, 1.03)
	_world_shell.play()


func _damage_body(collider: Object, distance: float, apply_damage: bool, stats: Dictionary) -> bool:
	var node: Node = collider as Node
	while node:
		if node.has_method("take_damage") and (node.is_in_group("player") or node.is_in_group("bot")):
			if apply_damage:
				node.take_damage(_damage_at(distance, stats), _player.get_multiplayer_authority())
			return true
		node = node.get_parent()
	return false


func _damage_at(distance: float, stats: Dictionary) -> int:
	var close := float(stats["damage"])
	var far := float(stats["damage_min"])
	var start := float(stats["falloff_start"])
	var finish := float(stats["falloff_end"])
	if distance <= start:
		return int(close)
	if distance >= finish:
		return int(far)
	var blend := (distance - start) / (finish - start)
	return int(round(lerpf(close, far, blend)))


func _spawn_blood(at: Vector3) -> void:
	var spark := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.75, 0.08, 0.06)
	sphere.material = material
	spark.mesh = sphere
	spark.top_level = true
	add_child(spark)
	spark.global_position = at
	get_tree().create_timer(0.12).timeout.connect(spark.queue_free)


func _start_reload() -> void:
	if _reloading or _mag == int(_stats["mag"]) or _reserve <= 0:
		return
	_reloading = true
	_reload_time = float(_stats["reload"])
	if _weapon_id == "shotgun" and _shotgun_reload != null:
		var length: float = _shotgun_reload.get_length()
		if length > 0.2:
			_reload_time = length
		_play_on(_reload_player, _shotgun_reload, -1.0, false)
	elif _weapon_id == "ak47":
		_play_on(_reload_player, AK47_RELOAD, -3.0, false)
		if Net.active:
			net_ak47_reload.rpc()
	_reload_left = _reload_time
	_update_hud()


@rpc("authority", "reliable")
func net_ak47_reload() -> void:
	if _player.weapon_id == "ak47" and _player.control_enabled:
		_world_reload.play()


func _finish_reload() -> void:
	var need := int(_stats["mag"]) - _mag
	var take := mini(need, _reserve)
	_mag += take
	_reserve -= take
	_reloading = false
	_update_hud()


func _ray_direction(spread_deg: float) -> Vector3:
	var forward := -_camera.global_transform.basis.z
	if spread_deg <= 0.01:
		return forward
	var basis := Basis.looking_at(forward)
	var cone := tan(deg_to_rad(spread_deg))
	return (basis * Vector3(randf_range(-cone, cone), randf_range(-cone, cone), -1.0).normalized()).normalized()


func _apply_view(delta: float) -> void:
	if _view == null:
		return
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	if speed > 0.4 and _player.is_on_floor():
		_bob_t += delta * speed * 1.7
	else:
		_bob_t += delta
	var bob := Vector3.ZERO
	if speed > 0.4 and _player.is_on_floor():
		bob = Vector3(sin(_bob_t * 2.0) * 0.008, absf(cos(_bob_t * 2.0)) * 0.01, 0.0)
	var dip := 0.0
	if _reloading:
		var t := 1.0 - clampf(_reload_left / _reload_time, 0.0, 1.0)
		dip = sin(t * PI) * 0.1
	_view.position = _rest_pos + bob + _kick_pos + Vector3(0.0, -dip, dip * 0.4)
	_view.rotation_degrees = Vector3(_kick_rot, 0.0, _kick_rot * -0.25)


func _build_viewmodel(weapon_id: String) -> void:
	if _view:
		_view.queue_free()
	_view = Node3D.new()
	_view.position = _rest_pos
	add_child(_view)
	var model := _make_model(weapon_id)
	_view.add_child(model)
	for animation_player in model.find_children("*", "AnimationPlayer", true, false):
		animation_player.active = false
	if weapon_id == "deagle":
		# Pistol model points the muzzle along +Z. The camera looks down -Z.
		model.rotation.y = PI
	elif weapon_id == "shotgun":
		# Shotgun OBJ lies along X, muzzle toward -X, up is +Y.
		_apply_shotgun_material(model)
		model.rotation.y = -PI / 2.0
		_scale_longest_axis(model, 0.92)
	elif weapon_id == "ak47":
		model.rotation.y = 0.07
	_seat_model(model, weapon_id)
	_muzzle = _marker(_muzzle_point(model, weapon_id))
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1, 0.78, 0.4)
	_flash.omni_range = 2.2
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	_muzzle.add_child(_flash)


func _make_model(weapon_id: String) -> Node3D:
	if weapon_id == "ak47":
		return AK47_MODEL.instantiate() as Node3D
	var path := "res://models/pistol.glb" if weapon_id == "deagle" else "res://drob/Shotgun.obj"
	var resource: Resource = load(path)
	if resource is PackedScene:
		return (resource as PackedScene).instantiate()
	var holder := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = resource as Mesh
	holder.add_child(mesh_instance)
	return holder


func _apply_shotgun_material(model: Node3D) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://drob/Sg_Diffuse.png")
	material.normal_enabled = true
	material.normal_texture = load("res://drob/Sg_normals.png")
	material.normal_scale = 0.85
	material.metallic = 1.0
	material.metallic_texture = load("res://drob/Sg_Spec.png")
	material.metallic_texture_channel = StandardMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	material.roughness = 0.5
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		mesh_instance.material_override = material


func _scale_longest_axis(model: Node3D, length: float) -> void:
	var bounds := _view_bounds(model)
	var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if longest > 0.001:
		model.scale *= length / longest


func _seat_model(model: Node3D, weapon_id: String) -> void:
	var bounds := _view_bounds(model)
	var back := bounds.position.z + bounds.size.z
	var target_back := -0.25 if weapon_id == "deagle" else -0.08
	var target_bottom := -0.22 if weapon_id == "deagle" else -0.2
	var target_x := 0.18 if weapon_id == "deagle" else 0.12
	if weapon_id == "ak47":
		target_back = -0.3
		target_bottom = -0.34
		target_x = 0.22
	model.position += Vector3(
		target_x - bounds.get_center().x,
		target_bottom - bounds.position.y,
		target_back - back
	)


func _muzzle_point(model: Node3D, weapon_id: String) -> Vector3:
	if weapon_id == "ak47":
		return model.transform * (model.get_node("Muzzle") as Marker3D).position
	if weapon_id != "shotgun":
		var bounds := _view_bounds(model)
		return Vector3(
			bounds.get_center().x,
			bounds.position.y + bounds.size.y * 0.58,
			bounds.position.z - 0.02
		)
	var points := PackedVector3Array()
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mesh_instance.mesh
		if mesh == null:
			continue
		var to_view: Transform3D = _view.global_transform.affine_inverse() * mesh_instance.global_transform
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				points.append(to_view * vertex)
	var front_z := points[0].z
	for point in points:
		front_z = minf(front_z, point.z)
	var xs: Array[float] = []
	var ys: Array[float] = []
	for point in points:
		if point.z <= front_z + 0.06:
			xs.append(point.x)
			ys.append(point.y)
	xs.sort()
	ys.sort()
	var mid := xs.size() / 2
	# The front sight sits above the bore, so the raw tip is a little high.
	return Vector3(xs[mid], ys[mid] - 0.012, front_z - 0.01)


func _view_bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var to_view: Transform3D = _view.global_transform.affine_inverse() * mesh_instance.global_transform
		var piece: AABB = to_view * mesh_instance.get_aabb()
		bounds = piece if not found else bounds.merge(piece)
		found = true
	return bounds


func _marker(at: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = "Muzzle"
	marker.position = at
	_view.add_child(marker)
	return marker


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var thickness := float(_stats["tracer_size"])
	mesh.size = Vector3(thickness, thickness, length)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = _stats["tracer"]
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.top_level = true
	add_child(mesh_instance)
	mesh_instance.global_position = (from + to) * 0.5
	mesh_instance.look_at(to, Vector3.UP)
	get_tree().create_timer(0.045).timeout.connect(mesh_instance.queue_free)


func _spawn_impact(at: Vector3, normal: Vector3) -> void:
	var mark := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	var mark_size := float(_stats["mark"])
	mesh.size = Vector2(mark_size, mark_size)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.05, 0.045, 0.04)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = material
	mark.mesh = mesh
	mark.top_level = true
	add_child(mark)
	mark.global_position = at + normal * 0.02
	var up := Vector3.RIGHT if absf(normal.dot(Vector3.UP)) > 0.85 else Vector3.UP
	mark.look_at(at - normal, up)
	_marks.append(mark)
	if _marks.size() > 36:
		var old: Node3D = _marks.pop_front()
		if is_instance_valid(old):
			old.queue_free()

	var spark := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = mark_size * 0.35
	sphere.height = mark_size * 0.7
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(1, 0.75, 0.35)
	sphere.material = spark_mat
	spark.mesh = sphere
	spark.top_level = true
	add_child(spark)
	spark.global_position = at + normal * 0.03
	get_tree().create_timer(0.06).timeout.connect(spark.queue_free)


func _flash_crosshair() -> void:
	var hit_color := Color(1, 0.45, 0.2, 0.95)
	_cross.color = hit_color
	_cross_v.color = hit_color
	get_tree().create_timer(0.06).timeout.connect(_reset_crosshair)


func _reset_crosshair() -> void:
	if not is_instance_valid(_cross):
		return
	var idle := Color(1, 1, 1, 0.92)
	_cross.color = idle
	_cross_v.color = idle


func _update_hud() -> void:
	if _ammo == null:
		return
	var status := "перезарядка" if _reloading else "%d | %d" % [_mag, _reserve]
	_ammo.text = "%s\n%s\n%s" % [str(_stats["name"]), str(_stats["mode"]), status]


func _make_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	add_child(player)
	return player


func _make_world_player() -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.unit_size = 7.0
	player.max_distance = 48.0
	add_child(player)
	return player


func _play_on(player: AudioStreamPlayer, stream: AudioStream, volume_db: float, vary_pitch: bool) -> void:
	if stream == null:
		return
	if player.stream != stream:
		player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(0.97, 1.03) if vary_pitch else 1.0
	player.play()


func _play_shell() -> void:
	_play_on(_shell_player, _shotgun_shell, -4.0, true)


func _make_shot(pistol: bool) -> AudioStreamWAV:
	var rate := 22050
	var duration := 0.16 if pistol else 0.3
	var count := int(rate * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 if pistol else 19
	var decay := 24.0 if pistol else 9.0
	var tone := 150.0 if pistol else 62.0
	for i in count:
		var t := float(i) / float(rate)
		var envelope := exp(-t * decay)
		var noise := rng.randf_range(-1.0, 1.0)
		var body := sin(TAU * tone * t)
		var sample := (noise * 0.72 + body * 0.28) * envelope
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32000.0))
	return _wav(rate, data)


func _make_dry() -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * 0.04)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in count:
		var t := float(i) / float(rate)
		var sample := rng.randf_range(-1.0, 1.0) * exp(-t * 80.0) * 0.35
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _wav(rate, data)


func _wav(rate: int, data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
