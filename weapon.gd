extends Node3D

const AK47_MODEL := preload("res://assets/ak47/ak47.tscn")
const AK47_SHOT := preload("res://assets/ak47/fire.wav")
const AK47_RELOAD := preload("res://assets/ak47/reload.wav")
const DEAGLE_SHOT := preload("res://assets/weapon_audio/deagle_fire.wav")
const DEAGLE_SLIDE := preload("res://assets/weapon_audio/deagle_slide.wav")
const SHOTGUN_SHOT := preload("res://assets/weapon_audio/shotgun_fire.wav")
const SHOTGUN_PUMP := preload("res://assets/weapon_audio/shotgun_pump.wav")
const SHELL_START := 0.28
const SHELL_INTERVAL := 0.60
const SHELL_FINISH := 0.20
const SHELL_IN_HAND := Vector3(-0.024, 0.126, 0.052)

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
var _pump_wait := 0.0
var _rest_pos := Vector3.ZERO
var _reload_units := 0
var _shells_inserted := 0
var _right_wrist: Marker3D
var _left_wrist: Marker3D
var _support_rest: Vector3
var _support_basis: Basis
var _magazine: Node3D
var _magazine_skeleton: Skeleton3D
var _magazine_bone := -1
var _magazine_rest: Transform3D
var _magazine_seat: Vector3
var _shell: Node3D
var _loading_port: Vector3

var _view: Node3D
var _muzzle: Marker3D
var _barrel_length := 0.0
var _flash: OmniLight3D
var _shot_player: AudioStreamPlayer
var _pump_player: AudioStreamPlayer
var _reload_player: AudioStreamPlayer
var _world_shot: AudioStreamPlayer3D
var _world_pump: AudioStreamPlayer3D
var _world_reload: AudioStreamPlayer3D
var _last_net_msec := 0
var _shell_insert: AudioStream
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
	_pump_player = _make_player()
	_reload_player = _make_player()
	_world_shot = _make_world_player()
	_world_shot.max_polyphony = 5
	_world_pump = _make_world_player()
	_world_pump.volume_db = -4.0
	_world_reload = _make_world_player()
	_world_reload.volume_db = -8.0
	_dry = _make_dry()
	_shell_insert = _make_insert_sound()


func equip(weapon_id: String) -> void:
	_weapon_id = weapon_id
	_stats = WEAPONS[weapon_id]
	_mag = int(_stats["mag"])
	_reserve = int(_stats["reserve"])
	_cooldown = 0.0
	_reload_left = 0.0
	_reloading = false
	_kick_pos = Vector3.ZERO
	_kick_rot = 0.0
	_shot_player.stop()
	_pump_player.stop()
	_reload_player.stop()
	_world_reload.stop()
	_pump_wait = 0.0
	_active = true
	_trigger_held = false
	_build_viewmodel(weapon_id)
	if _player._is_local():
		_update_hud()
		_ammo.visible = true


func restart_round() -> void:
	_last_net_msec = 0
	_world_shot.stop()
	_world_pump.stop()
	_flash_left = 0.0
	for mark in _marks:
		if is_instance_valid(mark):
			mark.queue_free()
	_marks.clear()
	if _active:
		equip(_weapon_id)


func _process(delta: float) -> void:
	if not _active:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)
	if _pump_wait > 0.0:
		_pump_wait = maxf(_pump_wait - delta, 0.0)
		if _pump_wait == 0.0:
			_play_pump()
	if _flash:
		_flash.light_energy = 5.0 if _flash_left > 0.0 else 0.0
	if _reloading:
		_reload_left = maxf(0.0, _reload_left - delta)
		if _weapon_id == "shotgun":
			_insert_loaded_shells()
		if _reload_left == 0.0:
			_finish_reload()
	_kick_pos = _kick_pos.lerp(Vector3.ZERO, minf(1.0, delta * 9.0))
	_kick_rot = lerpf(_kick_rot, 0.0, minf(1.0, delta * 9.0))
	_apply_view(delta)

	if not _player._is_local():
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not _player.accepts_gameplay_input():
		_trigger_held = Input.is_action_pressed(&"fire")
		_reload_held = Input.is_action_pressed(&"reload_weapon")
		return

	var shooting := Input.is_action_pressed(&"fire")
	var repeat := bool(_stats.get("automatic", false)) and (_mag > 0 or _reserve > 0)
	if shooting and (not _trigger_held or repeat):
		_try_fire()
	_trigger_held = shooting

	var reload_key := Input.is_action_pressed(&"reload_weapon")
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
	_show_shot(result["muzzle"], result, true)
	_flash_left = 0.05
	_kick_pos = Vector3(randf_range(-0.008, 0.008), randf_range(0.0, 0.012), float(_stats["kick"]))
	_kick_rot = -float(_stats["recoil"]) * 1.4
	_player.add_recoil(float(_stats["recoil"]), randf_range(-float(_stats["recoil_yaw"]), float(_stats["recoil_yaw"])))
	var volume := -5.0 if _weapon_id == "ak47" else 0.0
	_play_on(_shot_player, _shot_stream(_weapon_id), volume, true)
	if _weapon_id == "shotgun":
		_pump_wait = 0.38
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


func _cast_all(weapon_name: String, eye: Vector3, dirs: PackedVector3Array, apply_damage: bool) -> Dictionary:
	var stats: Dictionary = WEAPONS[weapon_name]
	var space := _camera.get_world_3d().direct_space_state
	var muzzle := _muzzle.global_position
	var barrel_forward := -_muzzle.global_basis.z
	var breech := muzzle - barrel_forward * _barrel_length
	var obstruction := _ray_hit(space, breech, muzzle)
	var ends := PackedVector3Array()
	var kinds := PackedInt32Array()
	var normals := PackedVector3Array()
	var reach := float(stats["range"])
	for index in mini(dirs.size(), int(stats["pellets"])):
		var direction := dirs[index]
		if not direction.is_finite() or direction.length_squared() < 0.001:
			continue
		direction = direction.normalized()
		var end := muzzle + direction * reach
		var hit := obstruction
		if hit.is_empty():
			# Find the point under the crosshair, then test the path from the actual barrel.
			var sight_end := eye + direction * reach
			var sight_hit := _ray_hit(space, eye, sight_end)
			var aim: Vector3 = sight_hit.get("position", sight_end)
			var barrel_to_aim := aim - muzzle
			if barrel_to_aim.dot(direction) > 0.02:
				var distance := minf(reach, barrel_to_aim.length() + 0.015)
				end = muzzle + barrel_to_aim.normalized() * distance
			hit = _ray_hit(space, muzzle, end)
		var kind := 2
		var normal := Vector3.ZERO
		if not hit.is_empty():
			end = hit["position"]
			if _damage_body(hit["collider"], muzzle.distance_to(end), apply_damage, stats):
				kind = 1
			else:
				kind = 0
				normal = hit["normal"]
				if normal.is_zero_approx():
					normal = -barrel_forward
		ends.append(end)
		kinds.append(kind)
		normals.append(normal)
	return {"ends": ends, "kinds": kinds, "normals": normals, "muzzle": muzzle}


func _ray_hit(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	query.hit_from_inside = true
	return space.intersect_ray(query)


func _show_shot(muzzle: Vector3, result: Dictionary, local_view: bool) -> void:
	var ends: PackedVector3Array = result["ends"]
	var kinds: PackedInt32Array = result["kinds"]
	var normals: PackedVector3Array = result["normals"]
	var any_hit := false
	for index in ends.size():
		if _muzzle == null or (ends[index] - muzzle).dot(-_muzzle.global_basis.z) > 0.0:
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
	if not multiplayer.is_server() or weapon_name != _weapon_id or _muzzle == null:
		return
	var now := Time.get_ticks_msec()
	var wait := int(float(WEAPONS[weapon_name]["cooldown"]) * 750.0)
	if now - _last_net_msec < wait:
		return
	_last_net_msec = now
	var origin := _camera.global_position
	if not from.is_finite() or from.distance_to(origin) > 3.0:
		from = origin
	var result := _cast_all(weapon_name, from, dirs, true)
	_stats = WEAPONS[weapon_name]
	_show_shot(result["muzzle"], result, false)
	_play_world_shot(weapon_name)
	_recoil_remote(weapon_name)
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
	var visual_muzzle := _muzzle.global_position if weapon_name == _weapon_id and _muzzle else muzzle
	_show_shot(visual_muzzle, {"ends": ends, "kinds": kinds, "normals": normals}, false)
	_play_world_shot(weapon_name)
	_recoil_remote(weapon_name)


func _recoil_remote(weapon_name: String) -> void:
	var stats: Dictionary = WEAPONS[weapon_name]
	_kick_pos = Vector3(0, 0.008, float(stats["kick"]))
	_kick_rot = -float(stats["recoil"]) * 1.4


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
		get_tree().create_timer(0.38).timeout.connect(_play_world_pump)


func _shot_stream(weapon_name: String) -> AudioStream:
	match weapon_name:
		"ak47":
			return AK47_SHOT
		"shotgun":
			return SHOTGUN_SHOT
		_:
			return DEAGLE_SHOT


func _play_world_pump() -> void:
	_world_pump.stream = SHOTGUN_PUMP
	_world_pump.pitch_scale = randf_range(0.97, 1.03)
	_world_pump.play()


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
	var units := mini(int(_stats["mag"]) - _mag, _reserve)
	_begin_reload(units)
	_play_on(_reload_player, _reload_stream(), -3.0, false)
	if Net.active:
		net_reload.rpc(_weapon_id, units)
	_update_hud()


@rpc("authority", "reliable")
func net_reload(id: String, units: int) -> void:
	if id != _weapon_id or not _player.control_enabled or units < 1 or units > int(_stats["mag"]):
		return
	_begin_reload(units)
	_world_reload.stream = _reload_stream()
	if _world_reload.stream:
		_world_reload.play()


func _begin_reload(units: int) -> void:
	_reload_units = units
	_shells_inserted = 0
	_reloading = true
	_reload_time = float(_stats["reload"])
	if _weapon_id == "shotgun":
		_reload_time = SHELL_START + SHELL_INTERVAL * units + SHELL_FINISH
	_reload_left = _reload_time


func _reload_stream() -> AudioStream:
	match _weapon_id:
		"ak47":
			return AK47_RELOAD
		_:
			return null


func _insert_loaded_shells() -> void:
	var elapsed := _reload_time - _reload_left
	var inserted := clampi(1 + floori((elapsed - SHELL_START - 0.49) / SHELL_INTERVAL), 0, _reload_units)
	if inserted <= _shells_inserted:
		return
	var count := inserted - _shells_inserted
	_shells_inserted = inserted
	if _player._is_local():
		_mag += count
		_reserve -= count
		_play_on(_reload_player, _shell_insert, -5.0, true)
	else:
		_world_reload.stream = _shell_insert
		_world_reload.play()


func _finish_reload() -> void:
	if _player._is_local() and _weapon_id != "shotgun":
		_mag += _reload_units
		_reserve -= _reload_units
	_reloading = false
	if _weapon_id == "deagle":
		if _player._is_local():
			_play_on(_reload_player, DEAGLE_SLIDE, -6.0, false)
		else:
			_world_reload.stream = DEAGLE_SLIDE
			_world_reload.play()
	if _player._is_local():
		_update_hud()


func cancel_reload() -> void:
	if not _reloading:
		return
	_reloading = false
	_reload_player.stop()
	_world_reload.stop()
	if _player._is_local():
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
	var speed: float = _player.visual_speed()
	_bob_t += delta * speed * 1.7
	var sway := minf(speed / 5.0, 1.0)
	var bob := Vector3(sin(_bob_t * 2.0) * 0.008, absf(cos(_bob_t * 2.0)) * 0.01, 0.0) * sway
	var progress := 1.0 - _reload_left / _reload_time if _reloading else 0.0
	var reload_pose := smoothstep(0.0, 0.17, progress) * (1.0 - smoothstep(0.82, 1.0, progress))
	# The eye can look farther up and down than the character can shoulder the weapon.
	var aim_offset := clampf(_camera.rotation.x, -0.78, 0.78) - _camera.rotation.x
	var pitch := Basis(Vector3.RIGHT, aim_offset)
	var reload_roll := -0.56 if _weapon_id == "shotgun" else -0.40
	_view.position = pitch * (_rest_pos + bob + _kick_pos + Vector3(-0.02, 0.025, -0.052) * reload_pose)
	_view.basis = pitch * Basis.from_euler(Vector3(deg_to_rad(_kick_rot) + 0.14 * reload_pose, 0.0, reload_roll * reload_pose - deg_to_rad(_kick_rot) * 0.25))
	_pose_reload(progress)
	var correction: Vector3 = _player.weapon_reach_correction()
	if correction.length_squared() > 0.000001:
		_view.global_position += correction
		if _reloading:
			_pose_reload(progress)


func _build_viewmodel(weapon_id: String) -> void:
	if _view:
		_view.hide()
		_view.queue_free()
	_view = Node3D.new()
	_view.name = "HeldWeapon"
	add_child(_view)
	var model := _make_model(weapon_id)
	_view.add_child(model)
	for animation_player in model.find_children("*", "AnimationPlayer", true, false):
		animation_player.active = false

	var grip := Vector3.ZERO
	var support := Vector3.ZERO
	var right_fingers := Vector3(-0.06, 0.24, -1.0)
	var left_fingers := Vector3(0.20, 0.14, -1.0)
	var left_palm := Vector3(0.33, 0.94, 0.0)
	match weapon_id:
		"deagle":
			model.rotation.y = PI
			grip = Vector3(0.025, 0.067, 0.139)
			support = Vector3(-0.058, 0.052, 0.123)
			_rest_pos = Vector3(0.104, -0.237, -0.285)
			left_fingers = Vector3(0.23, 0.19, -1.0)
			left_palm = Vector3(0.94, 0.33, 0.0)
			_barrel_length = 0.15
		"shotgun":
			_apply_shotgun_material(model)
			model.rotation.y = -PI / 2.0
			_scale_longest_axis(model, 0.92)
			var bounds := _view_bounds(model)
			var rear := bounds.end.z
			grip = Vector3(0.029, bounds.position.y + 0.056, rear - 0.232)
			support = Vector3(-0.039, bounds.position.y + 0.053, rear - 0.461)
			_rest_pos = Vector3(0.138, -0.220, -0.122)
			_barrel_length = 0.48
		"ak47":
			model.rotation.y = 0.10
			grip = model.basis * Vector3(0.027, -0.030, 0.046)
			support = model.basis * Vector3(-0.032, -0.011, -0.19)
			_rest_pos = Vector3(0.125, -0.219, -0.109)
			_barrel_length = 0.48
	model.position = -grip
	_support_rest = support - grip
	_support_basis = _hand_basis(left_fingers, left_palm)

	_right_wrist = _marker(Vector3.ZERO)
	_right_wrist.name = "RightGrip"
	_right_wrist.basis = _hand_basis(right_fingers, Vector3(-1.0, 0.15, 0.0))
	_left_wrist = _marker(_support_rest)
	_left_wrist.name = "LeftGrip"
	_left_wrist.basis = _support_basis
	_player.set_weapon_grips(_right_wrist, _left_wrist)

	_muzzle = _marker(_muzzle_point(model, weapon_id))
	_muzzle.name = "Muzzle"
	if weapon_id == "ak47":
		_muzzle.rotation.y = model.rotation.y
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1, 0.78, 0.4)
	_flash.omni_range = 2.2
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	_muzzle.add_child(_flash)
	_prepare_reload(model)
	_apply_view(0.0)


func _hand_basis(fingers: Vector3, palm: Vector3) -> Basis:
	var along := fingers.normalized()
	var across := along.cross(palm).normalized()
	return Basis(across, along, across.cross(along))


func _prepare_reload(model: Node3D) -> void:
	_magazine = null
	_magazine_skeleton = null
	_magazine_bone = -1
	_shell = null
	match _weapon_id:
		"deagle":
			_magazine = model.find_child("magazine", true, false) as Node3D
			_magazine_rest = _magazine.transform
			_magazine_seat = _view.to_local(_magazine.global_position)
		"ak47":
			_magazine_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
			_magazine_bone = _magazine_skeleton.find_bone("MAGAZINE")
			_magazine_rest = _magazine_skeleton.get_bone_global_rest(_magazine_bone)
			_magazine_seat = _view.to_local(_magazine_skeleton.to_global(_magazine_rest.origin))
		"shotgun":
			_loading_port = Vector3(-0.028, 0.014, -0.14)
			_shell = _make_shell()
			_view.add_child(_shell)
			_shell.hide()


func _pose_reload(progress: float) -> void:
	_left_wrist.position = _support_rest
	_left_wrist.basis = _support_basis
	_player.set_support_grip(0.0)
	if _shell:
		_shell.hide()
	if not _reloading:
		_place_magazine(_magazine_seat)
		return

	var pouch := _view.to_local(_player.reload_pouch_position())
	# Arc forward from the pouch so the wrist clears the vest and receiver.
	var reach := pouch + Vector3(-0.04, 0.08, -0.13)
	_player.set_support_grip(smoothstep(0.0, 0.17, progress) * (1.0 - smoothstep(0.82, 1.0, progress)))
	if _weapon_id == "shotgun":
		_pose_shell_reload(pouch, reach)
		return

	var hand_offset := Vector3(-0.047, -0.035, 0.039)
	var seated_hand := _magazine_seat + hand_offset
	var extracted := seated_hand + Vector3(-0.024, -0.09, 0.025)
	var carry_basis := _hand_basis(Vector3(0.52, 0.24, -0.82), Vector3(0.32, 0.92, 0.0))
	var stow := pouch + hand_offset
	var wrist := _path(progress, [0.0, 0.17, 0.30, 0.49, 0.58, 0.85, 1.0],
		[_support_rest, seated_hand, extracted, stow, stow, seated_hand, _support_rest])
	if progress > 0.58 and progress < 0.85:
		var t := smoothstep(0.58, 0.85, progress)
		var guide := reach + hand_offset
		wrist = stow.lerp(guide, t).lerp(guide.lerp(seated_hand, t), t)
	_left_wrist.position = wrist
	_left_wrist.basis = _support_basis.slerp(carry_basis,
		smoothstep(0.0, 0.17, progress) * (1.0 - smoothstep(0.85, 1.0, progress)))
	if progress < 0.17 or progress >= 0.85:
		_place_magazine(_magazine_seat)
	else:
		var tilt := -0.32 * smoothstep(0.17, 0.34, progress) * (1.0 - smoothstep(0.69, 0.85, progress))
		_place_magazine(wrist - hand_offset, tilt)


func _pose_shell_reload(pouch: Vector3, reach: Vector3) -> void:
	var elapsed := _reload_time - _reload_left
	var duration := SHELL_INTERVAL * _reload_units
	var carry_basis := _hand_basis(Vector3(0.44, 0.22, -0.87), Vector3.UP)
	var pinch := carry_basis * SHELL_IN_HAND
	var pouch_hand := pouch - pinch
	var loading_hand := _loading_port - pinch
	if elapsed < SHELL_START:
		var blend := smoothstep(0.0, SHELL_START, elapsed)
		_left_wrist.position = _support_rest.lerp(pouch_hand, blend)
		_left_wrist.basis = _support_basis.slerp(carry_basis, blend)
	elif elapsed < SHELL_START + duration:
		var phase := fmod(elapsed - SHELL_START, SHELL_INTERVAL) / SHELL_INTERVAL
		_left_wrist.basis = carry_basis
		var approach := loading_hand + Vector3(0.0, -0.015, 0.031)
		if phase < 0.66:
			var t := smoothstep(0.0, 0.66, phase)
			var guide := reach - pinch
			_left_wrist.position = pouch_hand.lerp(guide, t).lerp(guide.lerp(approach, t), t)
		else:
			_left_wrist.position = _path(phase, [0.66, 0.82, 1.0], [approach, loading_hand, pouch_hand])
		_shell.visible = phase < 0.82
		_shell.position = _left_wrist.transform * SHELL_IN_HAND
		_shell.rotation.x = -PI / 2.0
	else:
		var blend := smoothstep(SHELL_START + duration, _reload_time, elapsed)
		_left_wrist.position = pouch_hand.lerp(_support_rest, blend)
		_left_wrist.basis = carry_basis.slerp(_support_basis, blend)


func _path(progress: float, times: Array, points: Array) -> Vector3:
	for i in range(1, times.size()):
		if progress <= float(times[i]):
			var from: Vector3 = points[i - 1]
			return from.lerp(points[i], smoothstep(times[i - 1], times[i], progress))
	return points.back()


func _place_magazine(point: Vector3, tilt: float = 0.0) -> void:
	var axis := _view.global_basis.z.normalized()
	if _magazine:
		_magazine.transform = _magazine_rest
		_magazine.global_position = _view.to_global(point)
		_magazine.global_rotate(axis, tilt)
	elif _magazine_skeleton:
		var pose := _magazine_rest
		pose.origin = _magazine_skeleton.to_local(_view.to_global(point))
		var local_axis := _magazine_skeleton.global_basis.inverse() * axis
		pose.basis = Basis(local_axis.normalized(), tilt) * pose.basis
		_magazine_skeleton.set_bone_global_pose(_magazine_bone, pose)


func _make_shell() -> Node3D:
	var shell := Node3D.new()
	var hull := _shell_part(0.012, 0.052, Color(0.44, 0.035, 0.025), 0.15)
	var cap := _shell_part(0.013, 0.013, Color(0.61, 0.40, 0.13), 0.7)
	shell.add_child(hull)
	shell.add_child(cap)
	cap.position.y = -0.026
	return shell


func _shell_part(radius: float, height: float, color: Color, metallic: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	mesh.material = material
	instance.mesh = mesh
	return instance


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


func _muzzle_point(model: Node3D, weapon_id: String) -> Vector3:
	match weapon_id:
		"ak47":
			return model.transform * (model.get_node("Muzzle") as Marker3D).position
		"shotgun":
			# Center of the ring at the front of the OBJ barrel.
			return model.transform * Vector3(-8.94, 3.048, -0.001)
		_:
			return model.transform * Vector3(0.0, 0.1575, 0.112)


func _view_bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var to_view: Transform3D = _view.global_transform.affine_inverse() * mesh_instance.global_transform
		var piece: AABB = to_view * mesh_instance.get_aabb()
		bounds = piece if not found else bounds.merge(piece)
		found = true
	return bounds


func _marker(at: Vector3) -> Marker3D:
	var marker := Marker3D.new()
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


func _play_pump() -> void:
	_play_on(_pump_player, SHOTGUN_PUMP, -6.0, true)


func _make_insert_sound() -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * 0.13)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for i in count:
		var t := float(i) / rate
		var latch := maxf(0.0, t - 0.036)
		var scrape := rng.randf_range(-1.0, 1.0) * exp(-t * 85.0) * 0.22
		var click := sin(TAU * 1140.0 * latch) * exp(-latch * 106.0) * 0.30
		data.encode_s16(i * 2, int((scrape + click) * 32767.0))
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
