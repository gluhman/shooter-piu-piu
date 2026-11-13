extends Node3D

const ARSENAL := preload("res://game/combat/arsenal_assets.gd")
const Classic := preload("res://game/combat/classic_weapons.gd")
const WeaponHud := preload("res://game/ui/weapon_hud.gd")
const Balance := preload("res://game/combat/combat_balance.gd")
const MAP := preload("res://game/maps/map_builder.gd")
const DEAGLE_MODEL := preload("res://assets/weapon_models/desert_eagle.glb")
const KNIFE_MODEL := preload("res://assets/weapon_models/fish_knife/fish_knife_2k.gltf")
const SHOTGUN_MESH := preload("res://assets/shotgun/Shotgun.obj")
const SHOTGUN_DIFFUSE := preload("res://assets/shotgun/Sg_Diffuse.png")
const SHOTGUN_NORMAL := preload("res://assets/shotgun/Sg_normals.png")
const SHOTGUN_SPEC := preload("res://assets/shotgun/Sg_Spec.png")
const AK47_MODEL := preload("res://assets/ak47/ak47.tscn")
const DEAGLE_SLIDE := preload("res://assets/weapon_audio/deagle_slide.wav")
const SHOTGUN_PUMP := preload("res://assets/weapon_audio/shotgun_pump.wav")
const SHELL_START: float = Balance.DATA.weapons.shotgun.reload_start_s
const SHELL_INTERVAL: float = Balance.DATA.weapons.shotgun.reload_shell_s
const SHELL_FINISH: float = Balance.DATA.weapons.shotgun.reload_end_s
const SHELL_IN_HAND := Vector3(-0.024, 0.126, 0.052)
const HIP_FOV := 110.0
const KNIFE_SWING_TIME := 0.48
const KNIFE_GRIP_IN_WRIST := Vector3(-0.010, 0.094, 0.020)
const M249_RELOAD_ACTION_START := 0.34
const M249_TRIPOD_FROM_MUZZLE := Vector3(0.0, -0.105, 0.19)
const STOCKED_WEAPONS := ["ak47", "shotgun", "mp5", "m700", "lever", "m14", "launcher", "m249", "m1"]
const SIDEARMS := ["deagle", "m1911", "tec9"]
const SPECIALIZATIONS := {
	"assault": {
		"name": "Штурмовик", "weapons": ["ak47", "m14", "lever"],
		"hint": "Средняя дистанция. Точнее короткими очередями и одиночными.",
		"aim_seconds": 0.20,
	},
	"close": {
		"name": "Ближний бой", "weapons": ["shotgun", "mac10", "mp5"],
		"hint": "Быстрое прицеливание и стрельба на ходу. Урон быстрее падает с расстоянием.",
		"aim_seconds": 0.13,
	},
	"marksman": {
		"name": "Снайпер", "weapons": ["m700", "m1"],
		"hint": "Точные выстрелы на дальней дистанции. Медленное прицеливание и сильный разброс на ходу.",
		"aim_seconds": 0.34,
	},
	"support": {
		"name": "Поддержка", "weapons": ["m249", "launcher"],
		"hint": "Лопата для траншей и мешков. Станок для M249 уменьшает разброс вдвое.",
		"aim_seconds": 0.28,
	},
}

const FIRST_PERSON_SHOTS := {
	"deagle": preload("res://assets/weapon_audio/first_person/deagle.wav"),
	"shotgun": preload("res://assets/weapon_audio/first_person/shotgun.wav"),
	"ak47": preload("res://assets/weapon_audio/first_person/ak47.wav"),
	"m1911": preload("res://assets/weapon_audio/first_person/m1911.wav"),
	"mac10": preload("res://assets/weapon_audio/first_person/mac10.wav"),
	"mp5": preload("res://assets/weapon_audio/first_person/mp5.wav"),
	"m700": preload("res://assets/weapon_audio/first_person/m700.wav"),
	"tec9": preload("res://assets/weapon_audio/first_person/tec9.wav"),
	"lever": preload("res://assets/weapon_audio/first_person/lever.wav"),
	"m14": preload("res://assets/weapon_audio/first_person/m14.wav"),
	"m1": preload("res://assets/weapon_audio/first_person/m1.wav"),
	"m249": preload("res://assets/weapon_audio/first_person/m249.wav"),
	"launcher": preload("res://assets/weapon_audio/first_person/launcher.wav"),
}

static var WEAPONS := Balance.weapon_stats({
	"knife": {"name": "НОЖ", "mode": "ближний бой", "mag": 0, "reserve": 0},
	"deagle": {"name": "DESERT EAGLE", "mode": "одиночный", "aim_fov": 72.0, "kick": 0.045},
	"shotgun": {"name": "ДРОБОВИК", "mode": "помповый", "aim_fov": 76.0, "kick": 0.09},
	"ak47": {"name": "AK-47", "mode": "автоматический", "aim_fov": 68.0, "kick": 0.035},
	"m1911": {"name": "M1911", "mode": "одиночный", "aim_fov": 73.0, "kick": 0.037},
	"mac10": {"name": "MAC-10", "mode": "автоматический", "aim_fov": 81.0, "kick": 0.03},
	"mp5": {"name": "MP5", "mode": "автоматический", "aim_fov": 76.0, "kick": 0.031},
	"m700": {"name": "M700", "mode": "болтовой", "aim_fov": 47.0, "kick": 0.082},
	"tec9": {"name": "TEC-9", "mode": "одиночный", "aim_fov": 79.0, "kick": 0.034},
	"lever": {"name": "LEVER ACTION", "mode": "рычажный", "aim_fov": 69.0, "kick": 0.064},
	"m14": {"name": "M14", "mode": "одиночный", "aim_fov": 68.0, "kick": 0.056},
	"launcher": {"name": "M79", "mode": "гранатомёт", "mag": 1, "reserve": 5, "reload": 2.80, "cooldown": 1.0, "pellets": 1, "spread": 0.18, "aim_spread": 0.05, "aim_fov": 70.0, "range": 75.0, "recoil": 3.2, "recoil_yaw": 0.34, "kick": 0.085, "damage": 96, "damage_min": 24, "falloff_start": 0.0, "falloff_end": 5.0},
	"m249": {"name": "M249 SAW", "mode": "пулемёт", "aim_fov": 71.0, "kick": 0.04},
	"m1": {"name": "M1 GARAND", "mode": "оптика 5×", "aim_fov": 31.9, "kick": 0.075},
})

static var _shotgun_material: StandardMaterial3D
static var _shared_shell_sound: AudioStreamWAV
static var _shared_dry_sound: AudioStreamWAV
static var _shell_hull_mesh: CylinderMesh
static var _shell_cap_mesh: CylinderMesh


static func inventory_slot(id: String) -> String:
	if id == "knife":
		return "knife"
	return "secondary" if id in SIDEARMS else "primary"


static func specialization(id: String) -> String:
	for key: String in SPECIALIZATIONS:
		if id in SPECIALIZATIONS[key].weapons:
			return key
	return ""


var _weapon_id := ""
var _stats: Dictionary = {}
var _handling: Dictionary = {}
var _mag := 0
var _reserve := 0
var _cooldown := 0.0
var _knife_swing_left := 0.0
var _pending_knife := Vector3.ZERO
var _reload_left := 0.0
var _reload_time := 1.0
var _reloading := false
var _active := false
var _trigger_held := false
var _fire_requested := false
var _burst_heat := 0.0
var _last_fire_sequence := 0
var _shot_index := 0
var _recoil_index := 0
var _knife_windup := 0.0
var _knife_probe_left := 0.0
var _sprint_recovery := 0.0
var _sprint_fire_queued := false
var _sprint_last_frame := false
var _reload_held := false
var _reload_sound_delay := 0.0
var _reload_sound_world := false
var _kick_pos := Vector3.ZERO
var _kick_rot := 0.0
var _bob_t := 0.0
var _pump_wait := 0.0
var _rest_pos := Vector3.ZERO
var _aim_amount := 0.0
var _run_carry := 0.0
var _switch_left := 0.0
var _aim_pose: Transform3D
var _stock_contact := Vector3.ZERO
var _aim_depth_limit := 0.0
var _scope_view := false
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
var _tripod_legs: Array[MeshInstance3D] = []
var _model: Node3D
var _muzzle: Marker3D
var _rear_sight: Marker3D
var _barrel_length := 0.0
var _shot_player: AudioStreamPlayer
var _pump_player: AudioStreamPlayer
var _reload_player: AudioStreamPlayer
var _world_pump: AudioStreamPlayer3D
var _world_reload: AudioStreamPlayer3D
var _shell_insert: AudioStream
var _dry: AudioStream

@onready var _camera: Camera3D = get_parent()
@onready var _player = get_parent().get_parent()
@onready var _match := get_node("../../..")
@onready var _grenades := get_node("../../../Grenades")
@onready var _hud := get_node("../../../HUD")
@onready var _ballistics := get_node("../../../Ballistics")
@onready var _ammo: WeaponHud = get_node("../../../HUD/Ammo")
@onready var _cross: Control = get_node("../../../HUD/Crosshair")


func _ready() -> void:
	_shot_player = _make_player()
	var shots := AudioStreamPolyphonic.new()
	shots.polyphony = 20
	_shot_player.stream = shots
	_pump_player = _make_player()
	_reload_player = _make_player()
	_world_pump = _make_world_player()
	_world_pump.volume_db = -4.0
	_world_reload = _make_world_player()
	_world_reload.volume_db = -8.0
	if _shared_dry_sound == null:
		_shared_dry_sound = _make_dry()
		_shared_shell_sound = _make_insert_sound()
	_dry = _shared_dry_sound
	_shell_insert = _shared_shell_sound


func equip(weapon_id: String, magazine: int = -1, reserve: int = -1, switching: bool = false) -> void:
	_set_scope_view(false)
	_weapon_id = weapon_id
	_stats = WEAPONS[weapon_id]
	_handling = SPECIALIZATIONS.get(specialization(weapon_id), {})
	_burst_heat = 0.0
	_mag = int(_stats.mag) if magazine < 0 else mini(magazine, int(_stats.mag))
	_reserve = int(_stats.reserve) if reserve < 0 else mini(reserve, _player.ammo_capacity(weapon_id))
	_aim_amount = 0.0
	_knife_swing_left = 0.0
	_pending_knife = Vector3.ZERO
	_knife_windup = 0.0
	_sprint_fire_queued = false
	_cooldown = maxf(_cooldown, 0.22) if switching else 0.0
	_switch_left = 0.22 if switching else 0.0
	_reload_left = 0.0
	_reloading = false
	_kick_pos = Vector3.ZERO
	_kick_rot = 0.0
	_pump_player.stop()
	_reload_player.stop()
	_world_reload.stop()
	_pump_wait = 0.0
	_active = true
	_trigger_held = false
	_fire_requested = false
	_build_viewmodel(weapon_id)
	if _player._is_local():
		_update_hud()
		_ammo.visible = true


func ammo_counts() -> Vector2i:
	return Vector2i(_mag, _reserve)


func reserve_space() -> int:
	return _player.ammo_capacity(_weapon_id) - _reserve if _active else 0


func _has_infinite_reserve() -> bool:
	var match := _player.get_parent()
	return is_instance_valid(match) and match.map_id == MAP.TEST_RANGE_ID


func add_reserve(amount: int) -> int:
	var added := clampi(amount, 0, reserve_space())
	_reserve += added
	if _player._is_local():
		_update_hud()
	return added


func _input(event: InputEvent) -> void:
	if not _active or not _player._is_local():
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not _player.accepts_gameplay_input():
		return
	var mouse := event as InputEventMouseButton
	var fire_button := GameSettings.fire_mouse_button()
	if OS.has_feature("macos") and mouse and fire_button > 0 and mouse.button_index <= MOUSE_BUTTON_MIDDLE:
		var buttons := GameSettings.physical_mouse_buttons(mouse)
		var held := (buttons & (1 << (fire_button - 1))) != 0
		_fire_requested = _fire_requested or (held and not _trigger_held)
		_trigger_held = held
	elif event.is_action_pressed(&"fire"):
		_trigger_held = true
		_fire_requested = true
	elif event.is_action_released(&"fire"):
		_trigger_held = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_trigger_held = false
		_fire_requested = false


func _process(delta: float) -> void:
	if not _active or _match.round_finished():
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_switch_left = maxf(_switch_left - delta, 0.0)
	_update_sprint_recovery(delta)
	if _cooldown == 0.0 and (not _trigger_held or not _player._is_local()):
		var balance: Dictionary = _stats.get("balance", {})
		_burst_heat = move_toward(_burst_heat, 0.0, delta * float(balance.get("shot_bloom_recovery_deg_s", 0.0)))
	_knife_swing_left = maxf(_knife_swing_left - delta, 0.0)
	if _pump_wait > 0.0:
		_pump_wait = maxf(_pump_wait - delta, 0.0)
		if _pump_wait == 0.0:
			if _player._is_local():
				_play_pump()
			else:
				_play_world_pump(_weapon_id)
	if _reloading:
		_reload_left = maxf(0.0, _reload_left - delta)
		if _loads_one_round():
			_insert_loaded_shells()
		if _reload_left == 0.0:
			_finish_reload()
		elif _player._is_local():
			_ammo.set_reload_progress(1.0 - _reload_left / _reload_time)
	if _reload_sound_delay > 0.0:
		_reload_sound_delay = maxf(0.0, _reload_sound_delay - delta)
		if _reload_sound_delay == 0.0 and _reloading:
			_play_reload_sound()
	_kick_pos = _kick_pos.lerp(Vector3.ZERO, minf(1.0, delta * 9.0))
	_kick_rot = lerpf(_kick_rot, 0.0, minf(1.0, delta * 9.0))
	if not _player._is_local():
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not _player.accepts_gameplay_input():
		_trigger_held = false
		_fire_requested = false
		_sprint_fire_queued = false
		_reload_held = Input.is_action_pressed(&"reload_weapon")
		_cross.update_pose(0.0, true, false, 0.0, false)
		return

	_cross.update_pose(aim_blend(), _reloading, _weapon_id == "knife", _current_spread(), _weapon_id in ["m700", "m1"], _camera)
	var shooting := _trigger_held
	var repeat := bool(_stats.get("automatic", false)) and (_mag > 0 or _reserve > 0)
	if _fire_requested or (shooting and repeat) or _sprint_fire_queued:
		_try_fire()
	_fire_requested = false

	var reload_key := Input.is_action_pressed(&"reload_weapon")
	if reload_key and not _reload_held:
		_start_reload()
	_reload_held = reload_key


func _update_sprint_recovery(delta: float) -> void:
	if _player.sprinting:
		_sprint_last_frame = true
		_sprint_recovery = float(_stats.get("balance", {}).get("sprint_to_fire_s", 0.0))
		cancel_reload()
	elif _sprint_last_frame:
		_sprint_last_frame = false
	else:
		_sprint_recovery = maxf(0.0, _sprint_recovery - delta)


func _can_fire() -> bool:
	var works: Node = _player.fieldworks()
	if works and works.is_building(_player):
		return false
	if not _active or not _player.control_enabled or _player.sprinting or _sprint_recovery > 0.0:
		return false
	return _cooldown <= 0.0 and not _player.weapon_switch_pending() and (
		not _reloading or (_loads_one_round() and _shells_inserted > 0 and _mag > 0))


func _try_fire() -> void:
	if _player.sprinting:
		_sprint_fire_queued = false
		return
	if _sprint_recovery > 0.0:
		_sprint_fire_queued = true
		return
	_sprint_fire_queued = false
	if not _can_fire():
		return
	if _weapon_id == "knife":
		_cooldown = float(_stats.cooldown)
		_knife_swing_left = KNIFE_SWING_TIME
		if _player._server_rules():
			_player.cancel_spawn_protection()
			_pending_knife = -_camera.global_basis.z.normalized()
			_knife_windup = Balance.MELEE.windup_s
			_send_shot_visual(_weapon_id)
		else:
			net_fire.rpc_id(1, _weapon_id, _player.network_pose(), _match.estimated_server_time())
		return
	if _mag <= 0:
		if _reserve > 0:
			_start_reload()
		else:
			_play_shot(_dry, -9.0, 1.0)
		return
	cancel_reload()
	_mag -= 1
	_cooldown = float(_stats.cooldown)
	_shoot()
	_update_hud()


func _physics_process(delta: float) -> void:
	if _weapon_id == "knife" and _player._is_local():
		_knife_probe_left -= delta
		if _knife_probe_left <= 0.0:
			_knife_probe_left = 0.08
			var in_reach := false
			if _can_fire() and _player.accepts_gameplay_input():
				var origin := _camera.global_position
				var hit: Dictionary = _ballistics.combat_ray(_player, origin, origin - _camera.global_basis.z * float(_stats.range))
				in_reach = not hit.is_empty() and hit.collider.has_meta(&"hit_zone")
			_cross.set_knife_reach(in_reach)
	if _pending_knife.is_zero_approx():
		return
	_knife_windup -= delta
	if _knife_windup > 0.0:
		return
	var bore := _pending_knife
	_pending_knife = Vector3.ZERO
	if _weapon_id != "knife" or not _player.control_enabled or _match.round_finished():
		return
	var origin: Vector3 = _player.current_shot_transform(_camera.global_transform).origin
	var hit: Dictionary = _ballistics.combat_ray(_player, origin, origin + bore * float(_stats.range))
	if hit.is_empty() or _ballistics.shatter_glass(hit) or not hit.collider.has_meta(&"hit_zone"):
		return
	var victim: Node3D = hit.collider.get_parent().get_parent()
	var previous_health: float = victim.health
	var zone: String = hit.collider.get_meta(&"hit_zone")
	var to_attacker: Vector3 = (_player.global_position - victim.global_position).normalized()
	var backstab := (-victim.global_basis.z).dot(to_attacker) <= float(Balance.MELEE.backstab_if_defender_forward_dot_direction_to_attacker_lte)
	var damage := Balance.melee_damage(zone, backstab)
	victim.take_damage(damage, _player.score_id(), zone, 0.0,
		{"velocity": bore * 0.8, "point": hit.position, "zone": zone, "source": "knife"})
	if victim.health < previous_health:
		if _player._is_local():
			confirm_projectile_hit()
		else:
			net_knife_hit.rpc_id(get_multiplayer_authority())


@rpc("any_peer", "reliable")
func net_knife_hit() -> void:
	if multiplayer.get_remote_sender_id() == 1 and _player._is_local():
		confirm_projectile_hit()


func _shoot() -> void:
	_apply_view(0.0, false)
	var camera: Transform3D = _player.shot_camera_transform()
	var target := _sight_target(camera)
	var aligned := _converge_view(_view.global_transform, camera, target)
	var barrel := aligned * _muzzle.transform
	var works: Node = _player.fieldworks()
	_view.global_transform = aligned if works and works.is_mounted(_player) else aligned.interpolate_with(_view.global_transform, aim_blend())
	if _player._server_rules():
		_player.cancel_spawn_protection()
		_launch_sighted(barrel, camera, target)
		_send_shot_visual(_weapon_id, barrel)
	else:
		var pose: PackedFloat32Array = _player.network_pose()
		_last_fire_sequence = int(pose[12])
		net_fire.rpc_id(1, _weapon_id, pose, _match.estimated_server_time())
	if not _scope_view:
		_ballistics.muzzle_effect(_weapon_id, _muzzle.global_transform, _player.shot_motion(), false)
	_kick_pos = Vector3(randf_range(-0.008, 0.008), randf_range(0.0, 0.012), float(_stats.kick))
	var recoil := float(_stats.recoil)
	_kick_rot = -recoil * 1.4
	_recoil_index += 1
	var recoil_rng := RandomNumberGenerator.new()
	recoil_rng.seed = hash([_player.score_id(), _recoil_index])
	var yaw_limit := float(_stats.recoil_yaw)
	_player.add_recoil(recoil, recoil_rng.randf_range(-yaw_limit, yaw_limit))
	_add_bloom()
	var volume := -6.0 if _stats.get("automatic", false) else -2.5
	_play_shot(FIRST_PERSON_SHOTS[_weapon_id], volume, randf_range(0.97, 1.03))
	if _weapon_id == "shotgun" or _weapon_id in Classic.ACTIONS:
		_pump_wait = 0.38


func _sight_target(camera: Transform3D, rewind: float = -1.0) -> Vector3:
	var forward := -camera.basis.z.normalized()
	var end := camera.origin + forward * float(_stats.range)
	var hit: Dictionary = _ballistics.combat_ray(_player, camera.origin, end, rewind)
	var target: Vector3 = hit.get("position", end)
	if _player._is_local() and _ammo.visible and _weapon_id != "launcher":
		_ammo.show_accuracy(camera.origin.distance_to(target), _current_spread(), hit.is_empty())
	return target


func mounted_camera(angles: Vector2) -> Transform3D:
	var basis := Basis.from_euler(Vector3(angles.y, angles.x, 0.0))
	var pose := _mounted_view(basis)
	return Transform3D(basis, pose * (_rear_sight.position + Vector3(0.0, 0.075, 0.055)))


func _mounted_view(basis: Basis) -> Transform3D:
	var rest: Vector3 = _player.fieldworks().weapon_rest(_player)
	var hinge := _muzzle.position + M249_TRIPOD_FROM_MUZZLE
	return Transform3D(basis, rest - basis * hinge)


func _converge_view(view: Transform3D, camera: Transform3D, target: Vector3) -> Transform3D:
	if _weapon_id == "m249":
		var works: Node = _player.fieldworks()
		if works and works.is_mounted(_player):
			return _mounted_view(camera.basis)
	var forward := -camera.basis.z.normalized()
	# Turn around the grip at hip fire and around the rear sight in ADS.
	var pivot := view * (Vector3.ZERO.lerp(_rear_sight.position, aim_blend()))
	var barrel := view * _muzzle.transform
	var bore := -barrel.basis.z.normalized()
	var muzzle_offset := barrel.origin - pivot
	var along := muzzle_offset.dot(bore)
	var lateral := muzzle_offset - bore * along
	var target_offset := target - pivot

	# Back the muzzle away from close surfaces before aligning the bore.
	var clearance := minf(0.08, maxf(0.02, (target - camera.origin).dot(forward) * 0.35))
	var min_along := maxf(along, 0.0) + clearance
	var min_distance_sq := lateral.length_squared() + min_along * min_along
	var depth := target_offset.dot(forward)
	var side_sq := target_offset.slide(forward).length_squared()
	var min_depth := sqrt(maxf(side_sq * 0.64, min_distance_sq - side_sq))
	var pullback := maxf(0.0, min_depth - depth)
	var shift := -forward * pullback
	target_offset -= shift

	# A point on the original bore at the target's distance from the pivot.
	var bore_point := lateral + bore * sqrt(maxf(0.0, target_offset.length_squared() - lateral.length_squared()))
	var turn := Basis(Quaternion(bore_point.normalized(), target_offset.normalized()))
	return Transform3D(turn * view.basis, pivot + shift + turn * (view.origin - pivot))


func _current_spread() -> float:
	if _weapon_id == "knife":
		return 0.0
	var aim := _accuracy_aim_amount()
	var spread := lerpf(float(_stats.spread), float(_stats.aim_spread), aim)
	if _player.crouched:
		spread *= float(Balance.ACCURACY.crouched_spread_multiplier)
	if _player.combat_speed() > 0.5:
		spread += lerpf(float(Balance.ACCURACY.moving_hip_spread_add_deg),
			float(Balance.ACCURACY.moving_ads_spread_add_deg), aim)
	if not _player.combat_grounded():
		spread += float(Balance.MOVEMENT.airborne_spread_bonus_deg)
	var works: Node = _player.fieldworks()
	var steady: bool = _weapon_id == "m249" and works != null and works.is_mounted(_player)
	return (spread + _burst_heat) * (0.5 if steady else 1.0)


func _accuracy_aim_amount() -> float:
	return 0.0 if _player.sliding else _aim_amount


func recoil_recovery() -> float:
	return float(_stats.get("balance", {}).get("recoil_recovery_deg_s", 6.5))


func _add_bloom() -> void:
	var balance: Dictionary = _stats.get("balance", {})
	_burst_heat = minf(float(balance.get("shot_bloom_cap_deg", 0.0)),
		_burst_heat + float(balance.get("shot_bloom_deg", 0.0)))


func reload_bot() -> void:
	_start_reload()


func is_reloading() -> bool:
	return _reloading


func fire_bot(target: Vector3, aim_error: float) -> bool:
	if not _can_fire() or _muzzle == null:
		return false
	if _mag == 0:
		if _reserve > 0:
			_start_reload()
		return false
	cancel_reload()
	_mag -= 1
	_cooldown = float(_stats.cooldown)
	_player.cancel_spawn_protection()
	_apply_view(0.0)
	var barrel := _muzzle.global_transform
	var direction := (target - barrel.origin).normalized()
	if _weapon_id == "launcher":
		var arc: Vector3 = _grenades.round_aim_direction(barrel.origin, target, _player.shot_motion())
		if not arc.is_zero_approx():
			direction = arc

	var aim := Basis.looking_at(direction, _camera.global_basis.y)
	var cone := tan(deg_to_rad(aim_error))
	var offset := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * cone
	var bore := aim * Vector3(offset.x, offset.y, -1.0).normalized()
	_launch_projectiles(barrel, Basis.looking_at(bore, aim.y), _current_spread(), _camera.global_position)
	_add_bloom()
	_play_remote_shot(_weapon_id, barrel)
	_send_shot_visual(_weapon_id, barrel)
	return true


func _launch_sighted(barrel: Transform3D, camera: Transform3D, target: Vector3, rewind: float = -1.0) -> void:
	var aim := barrel.basis
	var works: Node = _player.fieldworks()
	if _weapon_id == "launcher":
		var direction: Vector3 = _grenades.round_aim_direction(barrel.origin, target, _player.shot_motion())
		if not direction.is_zero_approx():
			aim = Basis.looking_at(direction, camera.basis.y)
	elif not (works and works.is_mounted(_player)):
		var direction: Vector3 = _ballistics.aim_direction(_weapon_id, barrel.origin, target, _player.shot_motion())
		if not direction.is_zero_approx():
			aim = Basis.looking_at(direction, camera.basis.y)
	_launch_projectiles(barrel, aim, _current_spread(), camera.origin, rewind)


func _launch_projectiles(barrel: Transform3D, aim: Basis, spread: float, eye: Vector3, rewind: float = -1.0) -> void:
	var directions := PackedVector3Array()
	var cone_edge := cos(deg_to_rad(spread))
	var cone_radius := sqrt(maxf(0.0, 1.0 - cone_edge * cone_edge))
	var concentration := float(Balance.ACCURACY.radial_concentration)
	_shot_index += 1
	var rng := RandomNumberGenerator.new()
	for pellet in int(_stats.pellets):
		rng.seed = hash([_match.combat_seed, _player.score_id(), _shot_index, pellet])
		var radius := pow(rng.randf(), concentration) * cone_radius
		var depth := sqrt(maxf(0.0, 1.0 - radius * radius))
		var offset := Vector2.from_angle(rng.randf() * TAU) * radius
		directions.append((aim * Vector3(offset.x, offset.y, -depth)).normalized())
	if _weapon_id == "launcher":
		_grenades.launch_round(_player, barrel, directions[0], _barrel_length, int(_stats.damage))
		return
	_ballistics.queue_shot(_weapon_id, _stats, _player, barrel, _barrel_length, eye, directions, rewind)


@rpc("authority", "reliable")
func net_fire(weapon_name: String, pose: PackedFloat32Array, shot_time: float) -> void:
	if _match.round_finished() or not multiplayer.is_server() or not _match.match_peers().has(multiplayer.get_remote_sender_id()):
		return
	if weapon_name != _weapon_id or _muzzle == null or not _match.apply_client_pose(_player, pose):
		return
	var sequence := int(pose[12])
	var rewind: float = _match.rewind_time(shot_time)
	var accepted := _accept_fire_sequence(sequence, pose[7] > 0.0)
	if rewind < 0.0 or not accepted:
		_send_ammo(sequence)
		return
	_cooldown = float(_stats.cooldown)
	_player.cancel_spawn_protection()
	var shot_camera: Transform3D = _player.shot_camera_transform()
	var shot_barrel := Transform3D.IDENTITY
	if weapon_name == "knife":
		_pending_knife = -shot_camera.basis.z
		_knife_windup = Balance.MELEE.windup_s
	else:
		cancel_reload()
		_mag -= 1
		_apply_view(0.0, false)
		var view: Transform3D = _player.current_shot_transform(_view.global_transform)
		var target := _sight_target(shot_camera, rewind)
		shot_barrel = _converge_view(view, shot_camera, target) * _muzzle.transform
		_launch_sighted(shot_barrel, shot_camera, target, rewind)
		_add_bloom()
		_send_ammo(sequence)
	_play_remote_shot(weapon_name, shot_barrel)
	_send_shot_visual(weapon_name, shot_barrel)


func _accept_fire_sequence(sequence: int, sprinting: bool) -> bool:
	_update_sprint_recovery(0.0)
	if sequence <= _last_fire_sequence:
		return false
	_last_fire_sequence = sequence
	return _can_fire() and not sprinting and (_mag > 0 or _weapon_id == "knife")


func _send_ammo(sequence: int) -> void:
	var peer := get_multiplayer_authority()
	if Net.active and multiplayer.is_server() and peer != 1:
		net_ammo.rpc_id(peer, _weapon_id, _mag, _reserve, sequence)


@rpc("any_peer", "reliable")
func net_ammo(id: String, magazine: int, reserve: int, sequence: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not _player._is_local() or id != _weapon_id:
		return
	if sequence < _last_fire_sequence:
		return
	_mag = magazine
	_reserve = reserve
	_update_hud()


func _send_shot_visual(weapon_name: String, barrel: Transform3D = Transform3D.IDENTITY) -> void:
	for peer in _match.match_peers():
		if peer != get_multiplayer_authority():
			net_visual.rpc_id(peer, weapon_name, barrel)


@rpc("any_peer", "call_remote", "unreliable", 2)
func net_visual(weapon_name: String, barrel: Transform3D) -> void:
	if multiplayer.get_remote_sender_id() == 1 and weapon_name == _weapon_id and _muzzle:
		_play_remote_shot(weapon_name, barrel)


func _play_remote_shot(weapon_name: String, barrel: Transform3D) -> void:
	if _match.round_finished():
		return
	if weapon_name == "knife":
		_knife_swing_left = KNIFE_SWING_TIME
		return
	_match.get_node("HUD").record_minimap_shot(_player.score_id(), barrel.origin)
	_ballistics.muzzle_effect(weapon_name, barrel, _player.shot_motion(), true)
	if weapon_name == "shotgun" or weapon_name in Classic.ACTIONS:
		_pump_wait = 0.38
	_recoil_remote(weapon_name)


func _recoil_remote(weapon_name: String) -> void:
	var stats: Dictionary = WEAPONS[weapon_name]
	_kick_pos = Vector3(0, 0.008, float(stats["kick"]))
	_kick_rot = -float(stats["recoil"]) * 1.4


func _play_world_pump(id: String) -> void:
	if _weapon_id != id or _match.round_finished():
		return
	_world_pump.stream = SHOTGUN_PUMP if id == "shotgun" else Classic.action_sound(id)
	_world_pump.pitch_scale = randf_range(0.97, 1.03)
	_world_pump.play()


func _start_reload() -> void:
	if _weapon_id == "knife" or _player.sprinting or _reloading or _mag >= int(_stats.mag) or _reserve <= 0:
		return
	var units := mini(int(_stats["mag"]) - _mag, _reserve)
	_begin_reload(units)
	_queue_reload_sound(not _player._is_local())
	if _player._is_local():
		_update_hud()
	if Net.active:
		if multiplayer.is_server():
			_send_reload(_weapon_id, units)
		else:
			net_reload.rpc_id(1, _weapon_id, units)


func _send_reload(id: String, units: int) -> void:
	for peer in _match.match_peers():
		if peer != get_multiplayer_authority():
			net_reload.rpc_id(peer, id, units)


@rpc("any_peer", "reliable")
func net_reload(id: String, units: int) -> void:
	if _match.round_finished():
		return
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		if sender != get_multiplayer_authority() or not _match.match_peers().has(sender):
			return
	elif sender != 1:
		return
	if id != _weapon_id or not _player.control_enabled or _player.sprinting or units < 1 or units > int(_stats["mag"]):
		return
	if multiplayer.is_server():
		units = mini(int(_stats.mag) - _mag, _reserve)
		if _reloading or units <= 0:
			return
		_send_reload(id, units)
	_begin_reload(units)
	_queue_reload_sound(true)


func _play_world_reload() -> void:
	_world_reload.stream = _reload_stream()
	if _world_reload.stream:
		_world_reload.play()


func _queue_reload_sound(world: bool) -> void:
	_reload_sound_world = world
	_reload_sound_delay = _reload_time * M249_RELOAD_ACTION_START if _weapon_id == "m249" else 0.0
	if _reload_sound_delay == 0.0:
		_play_reload_sound()


func _play_reload_sound() -> void:
	if _reload_sound_world:
		_play_world_reload()
	else:
		_play_on(_reload_player, _reload_stream(), -3.0, false)


func _begin_reload(units: int) -> void:
	_reload_units = units
	_shells_inserted = 0
	_reloading = true
	_reload_time = float(_stats.get("reload_empty", _stats.reload) if _mag == 0 else _stats.reload)
	if _loads_one_round():
		_reload_time = SHELL_START + SHELL_INTERVAL * units + SHELL_FINISH
	_reload_left = _reload_time


func _loads_one_round() -> bool:
	return _weapon_id in ["shotgun", "lever"]


func _reload_stream() -> AudioStream:
	if Classic.SHOT_COUNTS.has(_weapon_id) and not _loads_one_round():
		return Classic.reload_sound(_weapon_id)
	if _weapon_id == "m249":
		return Classic.reload_sound("ak47")
	if _weapon_id in ["m1", "launcher"]:
		return DEAGLE_SLIDE
	return null


func _insert_loaded_shells() -> void:
	var elapsed := _reload_time - _reload_left
	var inserted := clampi(floori((elapsed - SHELL_START + 0.00001) / SHELL_INTERVAL), 0, _reload_units)
	if inserted <= _shells_inserted:
		return
	var count := inserted - _shells_inserted
	_shells_inserted = inserted
	if _player._is_local() or _player._server_rules():
		_mag += count
		if not _has_infinite_reserve():
			_reserve -= count
	var insert_sound: AudioStream = Classic.reload_sound("lever") if _weapon_id == "lever" else _shell_insert
	if _player._is_local():
		_play_on(_reload_player, insert_sound, -5.0, true)
		_update_hud()
	else:
		_world_reload.stream = insert_sound
		_world_reload.play()


func _finish_reload() -> void:
	if (_player._is_local() or _player._server_rules()) and not _loads_one_round():
		_mag += _reload_units
		if not _has_infinite_reserve():
			_reserve -= _reload_units
	_reloading = false
	_reload_sound_delay = 0.0
	_reset_reload_pose()
	if _player._server_rules():
		_send_ammo(_last_fire_sequence)
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
	_reload_sound_delay = 0.0
	_reset_reload_pose()
	_reload_player.stop()
	_world_reload.stop()
	if _player._is_local():
		_update_hud()


func stop_round() -> void:
	cancel_reload()
	_fire_requested = false
	_trigger_held = false
	_pending_knife = Vector3.ZERO
	_sprint_fire_queued = false
	_pump_wait = 0.0
	for sound in [_shot_player, _reload_player, _pump_player, _world_pump, _world_reload]:
		sound.stop()


func aim_blend() -> float:
	return smoothstep(0.0, 1.0, _aim_amount)


func update_pose(delta: float) -> void:
	if _active and not _match.round_finished():
		_apply_view(delta)


func _apply_view(delta: float, converge: bool = true) -> void:
	if _view == null:
		return
	var works: Node = _player.fieldworks()
	var digging: bool = works and works.is_building(_player)
	_view.visible = not digging
	if digging:
		works.pose_shovel(_player)
		return
	var mounted: bool = works and works.is_mounted(_player)
	_player.set_weapon_grips(_right_wrist, _left_wrist, _weapon_id == "knife", mounted)
	if not _tripod_legs.is_empty():
		_pose_tripod(mounted)
	if mounted:
		_view.global_transform = _mounted_view(_camera.global_basis)
		if _reloading:
			_pose_reload(1.0 - _reload_left / _reload_time)
		return
	var speed: float = _player.visual_speed()
	var firing := _trigger_held or not _kick_pos.is_zero_approx() or not is_zero_approx(_kick_rot)
	var carry_target := smoothstep(2.65, 3.9, speed) if not _player.crouched and not firing else 0.0
	_run_carry = move_toward(_run_carry, carry_target, delta * (16.0 if firing else 7.0))
	if _weapon_id == "knife":
		_apply_knife_view()
		return
	var wants_aim: bool = _player.aiming and _player.control_enabled and not _reloading and not _player.sprinting and not _player.sliding
	var ads_time := float(_stats.get("balance", {}).get("ads_s", _handling.get("aim_seconds", 0.16)))
	ads_time += _player.armor_ads_delay()
	_aim_amount = move_toward(_aim_amount, float(wants_aim), delta / ads_time)
	var blend := aim_blend()
	if _player._is_local():
		_camera.fov = lerpf(HIP_FOV, float(_stats["aim_fov"]), blend)
		if _weapon_id in ["m700", "m1"]:
			_set_scope_view(blend >= 0.96)
			_model.visible = not _scope_view
	_bob_t += delta * speed * 1.7
	var sway := minf(speed / 5.0, 1.0)
	var bob := Vector3(sin(_bob_t * 2.0) * 0.008, absf(cos(_bob_t * 2.0)) * 0.01, 0.0) * sway
	var progress := 1.0 - _reload_left / _reload_time if _reloading else 0.0
	var reload_pose := smoothstep(0.0, 0.17, progress) * (1.0 - smoothstep(0.82, 1.0, progress))
	# Limit the pitch of the reload pose while the support hand reaches for the pouch.
	var aim_offset := (clampf(_camera.rotation.x, -0.78, 0.78) - _camera.rotation.x) * reload_pose
	var pitch := Basis(Vector3.RIGHT, aim_offset)
	var reload_roll := -0.56 if _weapon_id == "shotgun" else -0.40
	var handling_offset := _kick_pos + Vector3(-0.02, 0.025, -0.052) * reload_pose
	var handling_rotation := Basis.from_euler(Vector3(deg_to_rad(_kick_rot) + 0.14 * reload_pose,
		0.0, reload_roll * reload_pose - deg_to_rad(_kick_rot) * 0.25))
	var hip_position := pitch * (_rest_pos + bob + handling_offset)
	var hip_basis := pitch * handling_rotation
	var run_carry := smoothstep(0.0, 1.0, _run_carry)
	if run_carry > 0.0:
		# Follow the lowered torso through the run cycle and limit how far the weapon follows head pitch.
		var carry_pitch := -0.31 + clampf(_camera.rotation.x, -0.22, 0.22) * 0.5
		var carry_rotation := Basis.from_euler(Vector3(carry_pitch, 0.14, -0.10))
		var carry_offset := Vector3(_rest_pos.x + 0.025, -0.10, _rest_pos.z - 0.09)
		if _loads_one_round():
			carry_offset.z -= 0.10 * reload_pose
		var body_basis: Basis = _player.global_basis
		var carry_origin: Vector3 = _player.weapon_carry_anchor() + body_basis * (carry_offset + bob * 0.55 + handling_offset)
		var carry_basis := _camera.global_basis.inverse() * body_basis * carry_rotation * handling_rotation
		hip_position = hip_position.lerp(_camera.to_local(carry_origin), run_carry)
		hip_basis = hip_basis.slerp(carry_basis.orthonormalized(), run_carry)
	var bot: bool = _player.is_in_group("bot")
	var aimed_position := _aim_pose.origin
	if bot:
		if _weapon_id in STOCKED_WEAPONS:
			# Center the stock on the bot's shoulder instead of aligning the sights with its camera.
			_player.set_shoulder_brace(lerpf(0.85, 1.0, blend))
			if blend > 0.0:
				aimed_position = _camera.to_local(_player.weapon_stock_anchor()) - _aim_pose.basis * _stock_contact
		elif blend > 0.0:
			var hands := Vector3(0.035, 0.06, -0.39)
			var chest: Vector3 = _player.weapon_carry_anchor()
			aimed_position = _camera.to_local(chest + _camera.global_basis * hands)
	_view.position = hip_position.lerp(aimed_position + Vector3.BACK * _kick_pos.z, blend)
	_view.basis = hip_basis.orthonormalized().slerp(_aim_pose.basis, blend)
	if _switch_left > 0.0:
		var switch_pose := _switch_left / 0.22
		_view.position += Vector3(0.06 * switch_pose, -0.28 * switch_pose, 0.12 * switch_pose)
		_view.basis = _view.basis * Basis.from_euler(Vector3(0.16 * switch_pose, 0.0, -0.24 * switch_pose))
	if bot or blend < 1.0:
		var reach_weight := 1.0 if bot else 1.0 - blend
		_view.global_position += _player.weapon_reach_correction(not _reloading) * reach_weight
	if not bot and blend > 0.0:
		var axis := _camera.global_basis.z
		var depth: float = _player.weapon_reach_along(axis)
		_view.global_position += axis * minf(depth, _aim_depth_limit) * blend
	if _reloading:
		_pose_reload(progress)
	elif converge and not bot and not _player.sprinting:
		var camera := _camera.global_transform
		var target := _sight_target(camera)
		# Near targets require a steeper bore angle than the visible sights.
		if blend < 1.0:
			var aligned := _converge_view(_view.global_transform, camera, target)
			_view.global_transform = aligned.interpolate_with(_view.global_transform, blend)


func _set_scope_view(active: bool) -> void:
	if _scope_view != active:
		_scope_view = active
		_player.set_scoped_view(active)


func _apply_knife_view() -> void:
	if _player._is_local():
		_camera.fov = HIP_FOV
	var progress := 1.0 - _knife_swing_left / KNIFE_SWING_TIME
	var contact := float(Balance.MELEE.windup_s) / KNIFE_SWING_TIME
	var draw := smoothstep(0.0, contact * 0.5, progress) * (1.0 - smoothstep(contact * 0.5, contact, progress))
	var thrust := smoothstep(contact * 0.5, contact, progress) * (1.0 - smoothstep(contact, 1.0, progress))
	_view.position = _rest_pos + Vector3(0.035, -0.025, 0.10) * draw + Vector3(-0.15, 0.09, -0.26) * thrust
	_view.rotation = Vector3(0.25, -0.58, -0.37) + Vector3(-0.22, -0.24, 0.15) * draw + Vector3(-0.20, 0.56, 0.25) * thrust
	_view.global_position += _player.weapon_reach_correction(false)
	var left_rest := _camera.to_global(Vector3(-0.22 - thrust * 0.05, -0.30 - thrust * 0.05, -0.31 + draw * 0.04))
	_left_wrist.position = _view.to_local(_player.clamp_support_hand(left_rest))
	_left_wrist.basis = _view.global_basis.inverse() * _camera.global_basis * _support_basis


func _build_viewmodel(weapon_id: String) -> void:
	if _view:
		_view.hide()
		_view.queue_free()
	_view = Node3D.new()
	_view.name = "HeldWeapon"
	add_child(_view)
	var model := _make_model(weapon_id)
	_model = model
	_view.add_child(model)
	for animation_player in model.find_children("*", "AnimationPlayer", true, false):
		animation_player.active = false

	var grip := Vector3.ZERO
	var support := Vector3.ZERO
	var right_fingers := Vector3(-0.06, 0.24, -1.0)
	var right_palm := Vector3(-1.0, 0.15, 0.0)
	var left_fingers := Vector3(0.20, 0.14, -1.0)
	var left_palm := Vector3(0.33, 0.94, 0.0)
	match weapon_id:
		"knife":
			_rest_pos = Vector3(0.23, -0.24, -0.34)
			right_fingers = Vector3(-0.14, 0.23, -1.0)
			right_palm = Vector3(-0.70, -0.65, -0.10)
			left_fingers = Vector3(0.06, 0.16, -1.0)
			left_palm = Vector3(0.55, -0.70, 0.0)
		"deagle":
			model.rotation.y = PI
			grip = Vector3(0.024, 0.125, 0.093)
			support = Vector3(-0.041, 0.115, 0.076)
			_rest_pos = Vector3(0.104, -0.237, -0.285)
			left_fingers = Vector3(0.23, 0.19, -1.0)
			left_palm = Vector3(0.94, 0.33, 0.0)
			_barrel_length = 0.15
		"shotgun":
			_apply_shotgun_material(model)
			model.rotation.y = -PI / 2.0
			_scale_longest_axis(model, _view, 0.92)
			var bounds := _view_bounds(model, _view)
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
		"launcher", "m249", "m1":
			grip = _model_marker(model, "Grip")
			support = _model_marker(model, "Support")
			_rest_pos = Vector3(0.128, -0.224, -0.12)
			_barrel_length = _model_marker(model, "Muzzle").distance_to(Vector3(0.0, 0.04, 0.055))
		_:
			var setup: Array = Classic.MODELS[weapon_id]
			# The pack faces +Z, so rotate depth while retaining the left/right grip offsets.
			grip = model.basis * (Vector3(-1.0, 1.0, 1.0) * setup[0])
			support = model.basis * (Vector3(-1.0, 1.0, 1.0) * setup[1])
			_rest_pos = Vector3(0.123, -0.222, -0.125)
			if weapon_id in ["m1911", "mac10", "tec9"]:
				_rest_pos.z = -0.255
			if weapon_id in ["mac10", "mp5", "tec9", "m700", "m14", "lever"]:
				support.y -= 0.060 if weapon_id == "tec9" else 0.024
				left_fingers = Vector3(0.25, 0.35, -1.0)
				left_palm = Vector3(0.65, 0.75, 0.0)
			_barrel_length = maxf(0.10, Classic.bone_point(model, &"FX_FIRE").z - (setup[0] as Vector3).z - 0.03)
	model.position = -grip
	if weapon_id != "knife":
		_set_aim_pose(model, weapon_id)
	_support_rest = support - grip
	_support_basis = _hand_basis(left_fingers, left_palm)

	_right_wrist = _marker(Vector3.ZERO)
	_right_wrist.name = "RightGrip"
	_right_wrist.basis = _hand_basis(right_fingers, right_palm)
	if weapon_id == "knife":
		model.position = _right_wrist.transform * KNIFE_GRIP_IN_WRIST
	_left_wrist = _marker(_support_rest)
	_left_wrist.name = "LeftGrip"
	_left_wrist.basis = _support_basis
	_player.set_weapon_grips(_right_wrist, _left_wrist, weapon_id == "knife")

	_muzzle = _marker(_muzzle_point(model, weapon_id))
	_muzzle.name = "Muzzle"
	var bore := Vector3.FORWARD
	if weapon_id == "deagle" or Classic.MODELS.has(weapon_id):
		bore = Vector3.BACK
	elif weapon_id == "shotgun":
		bore = Vector3.LEFT
	_muzzle.basis = Basis.looking_at((model.basis * bore).normalized())
	if _player.is_in_group("bot") and weapon_id in STOCKED_WEAPONS:
		var bounds := _view_bounds(model, _view)
		var rearward := _muzzle.basis.z
		var bore_at_stock := _muzzle.position + rearward * ((bounds.end.z - _muzzle.position.z) / rearward.z)
		_stock_contact = Vector3(bore_at_stock.x, lerpf(_right_wrist.position.y, bore_at_stock.y, 0.5), bounds.end.z)
	_tripod_legs.clear()
	if weapon_id == "m249":
		_add_tripod(model)
	_prepare_reload(model)
	_reset_reload_pose()
	_apply_view(0.0)


func _set_aim_pose(model: Node3D, weapon_id: String) -> void:
	var rear: Vector3
	var front: Vector3
	var eye_relief := 0.21
	var sight_clearance := 0.004
	match weapon_id:
		"ak47":
			rear = Vector3(0.0, 0.128, -0.104)
			front = Vector3(0.0, 0.127, -0.586)
			eye_relief = 0.23
			sight_clearance = 0.006
		"shotgun":
			# This model has a bead and a receiver rib, so the rear line clears the rib.
			rear = Vector3(2.201, 3.51, 0.0)
			front = Vector3(-8.725, 3.389, -0.005)
			eye_relief = 0.23
		"deagle":
			rear = Vector3(0.0, 0.235, -0.080)
			front = Vector3(0.0, 0.234, 0.100)
			eye_relief = 0.31
		"launcher", "m249", "m1":
			rear = _model_marker(model, "RearSight")
			front = _model_marker(model, "FrontSight")
		"m700":
			rear = Classic.SCOPE_REAR
			front = Classic.SCOPE_FRONT
			eye_relief = 0.125
		_:
			front = Classic.bone_point(model, &"IRONSIGHT")
			rear = Vector3(front.x, front.y, Classic.MODELS[weapon_id][2])
			match weapon_id:
				"m1911":
					eye_relief = 0.28
				"lever":
					eye_relief = 0.43
					sight_clearance = 0.020
				"tec9":
					sight_clearance = 0.010
				"mac10", "mp5", "m14":
					if weapon_id == "mac10":
						sight_clearance = 0.038
					rear.y += 0.008 if weapon_id == "mp5" else 0.006
					front.y += 0.002
	_rear_sight = _marker(model.transform * rear)
	_rear_sight.name = "RearSight"
	var front_sight := _marker(model.transform * front)
	front_sight.name = "FrontSight"
	var line := (front_sight.position - _rear_sight.position).normalized()
	var basis := Basis.looking_at(line).inverse()
	_aim_pose = Transform3D(basis, Vector3(0.0, -sight_clearance, -eye_relief) - basis * _rear_sight.position)
	_aim_depth_limit = eye_relief - 0.10
	match weapon_id:
		"lever":
			_aim_depth_limit = 0.11
		"mp5":
			_aim_depth_limit = 0.06


func _add_tripod(model: Node3D) -> void:
	var tripod := Node3D.new()
	tripod.name = "Tripod"
	model.add_child(tripod)
	tripod.position = _model_marker(model, "Muzzle") + M249_TRIPOD_FROM_MUZZLE
	var finish := StandardMaterial3D.new()
	finish.albedo_color = Color(0.22, 0.24, 0.22)
	finish.metallic = 0.73
	finish.roughness = 0.52
	var hinge := MeshInstance3D.new()
	var collar := BoxMesh.new()
	collar.size = Vector3(0.080, 0.061, 0.093)
	hinge.mesh = collar
	hinge.material_override = finish
	tripod.add_child(hinge)
	for index in 3:
		var leg := MeshInstance3D.new()
		var strut := CylinderMesh.new()
		strut.radial_segments = 8
		strut.top_radius = 0.014
		strut.bottom_radius = 0.009
		leg.mesh = strut
		leg.material_override = finish
		tripod.add_child(leg)
		_tripod_legs.append(leg)
	_pose_tripod(false)


func _pose_tripod(deployed: bool) -> void:
	var folded := [Vector3(-0.033, -0.030, 0.21), Vector3(0.033, -0.030, 0.21), Vector3(0.0, -0.051, 0.20)]
	var open := [Vector3(-0.17, -0.19, -0.11), Vector3(0.17, -0.19, -0.11), Vector3(0.0, -0.19, 0.12)]
	for index in _tripod_legs.size():
		var foot: Vector3 = open[index] if deployed else folded[index]
		var leg := _tripod_legs[index]
		var strut := leg.mesh as CylinderMesh
		var length := foot.length()
		if not is_equal_approx(strut.height, length):
			strut.height = length
		leg.position = foot * 0.5
		leg.quaternion = Quaternion(Vector3.UP, -foot.normalized())


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
		"shotgun", "lever":
			_loading_port = Vector3(-0.028, 0.014, -0.14) if _weapon_id == "shotgun" else model.transform * Classic.bone_point(model, &"LOADING_GATE")
			_shell = _make_shell()
			if _weapon_id == "lever":
				_shell.scale = Vector3(0.55, 0.80, 0.55)
			_view.add_child(_shell)
			_shell.hide()
		"m249":
			_magazine = model.find_child("Magazine", true, false) as Node3D
			_magazine_rest = _magazine.transform
			_magazine_seat = _view.to_local(_magazine.global_position)
		"launcher", "m1":
			_magazine_seat = _model_marker(model, "RearSight") + model.position + Vector3(0.0, -0.03, -0.07)
		_:
			if _weapon_id == "knife":
				return
			_magazine_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
			_magazine_bone = _magazine_skeleton.find_bone("MAGASINE" if _weapon_id == "mp5" else "MAGAZINE")
			_magazine_rest = _magazine_skeleton.get_bone_global_rest(_magazine_bone)
			_magazine_seat = _view.to_local(_magazine_skeleton.to_global(_magazine_rest.origin))


func _reset_reload_pose() -> void:
	_left_wrist.position = _support_rest
	_left_wrist.basis = _support_basis
	_player.set_support_grip(0.0)
	if _shell:
		_shell.hide()
	else:
		_place_magazine(_magazine_seat)


func _pose_reload(progress: float) -> void:
	var pouch := _view.to_local(_player.reload_pouch_position())
	# Arc forward from the pouch so the wrist clears the vest and receiver.
	var reach := pouch + Vector3(-0.04, 0.08, -0.13)
	var pose_progress := _reload_pose_progress(progress)
	_player.set_support_grip(smoothstep(0.0, 0.17, pose_progress) * (1.0 - smoothstep(0.82, 1.0, pose_progress)))
	if _loads_one_round():
		_pose_shell_reload(pouch, reach)
		return

	var hand_offset := Vector3(-0.047, -0.035, 0.039)
	var seated_hand := _magazine_seat + hand_offset
	var extracted := seated_hand + Vector3(-0.024, -0.09, 0.025)
	var carry_basis := _hand_basis(Vector3(0.52, 0.24, -0.82), Vector3(0.32, 0.92, 0.0))
	var stow := pouch + hand_offset
	var wrist := _path(pose_progress, [0.0, 0.17, 0.30, 0.49, 0.58, 0.85, 1.0],
		[_support_rest, seated_hand, extracted, stow, stow, seated_hand, _support_rest])
	if pose_progress > 0.58 and pose_progress < 0.85:
		var t := smoothstep(0.58, 0.85, pose_progress)
		var guide := reach + hand_offset
		wrist = stow.lerp(guide, t).lerp(guide.lerp(seated_hand, t), t)
	wrist = _view.to_local(_player.clamp_support_hand(_view.to_global(wrist)))
	_left_wrist.position = wrist
	_left_wrist.basis = _support_basis.slerp(carry_basis,
		smoothstep(0.0, 0.17, pose_progress) * (1.0 - smoothstep(0.85, 1.0, pose_progress)))
	if pose_progress < 0.17 or pose_progress >= 0.85:
		_place_magazine(_magazine_seat)
	else:
		var tilt := -0.32 * smoothstep(0.17, 0.34, pose_progress) * (1.0 - smoothstep(0.69, 0.85, pose_progress))
		_place_magazine(wrist - hand_offset, tilt)


func _reload_pose_progress(progress: float) -> float:
	if _weapon_id != "m249":
		return progress
	var stream := _reload_stream()
	if stream == null:
		return progress
	var action_end := M249_RELOAD_ACTION_START + stream.get_length() / maxf(_reload_time, 0.001)
	return clampf(inverse_lerp(M249_RELOAD_ACTION_START, action_end, progress), 0.0, 1.0)


func _pose_shell_reload(pouch: Vector3, reach: Vector3) -> void:
	var elapsed := _reload_time - _reload_left
	var duration := SHELL_INTERVAL * _reload_units
	var carry_basis := _hand_basis(Vector3(0.44, 0.22, -0.87), Vector3.UP)
	var pinch := carry_basis * SHELL_IN_HAND
	var pouch_hand := pouch - pinch
	var loading_hand := _loading_port - pinch
	if elapsed < SHELL_START:
		_shell.hide()
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
		_left_wrist.global_position = _player.clamp_support_hand(_left_wrist.global_position)
		_shell.visible = phase < 0.82
		_shell.position = _left_wrist.transform * SHELL_IN_HAND
		_shell.rotation.x = -PI / 2.0
	else:
		_shell.hide()
		var blend := smoothstep(SHELL_START + duration, _reload_time, elapsed)
		_left_wrist.position = pouch_hand.lerp(_support_rest, blend)
		_left_wrist.basis = carry_basis.slerp(_support_basis, blend)
	_left_wrist.global_position = _player.clamp_support_hand(_left_wrist.global_position)


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


static func _make_shell() -> Node3D:
	if _shell_hull_mesh == null:
		_shell_hull_mesh = _shell_mesh(0.012, 0.052, Color(0.44, 0.035, 0.025), 0.15)
		_shell_cap_mesh = _shell_mesh(0.013, 0.013, Color(0.61, 0.40, 0.13), 0.7)
	var shell := Node3D.new()
	var hull := MeshInstance3D.new()
	hull.mesh = _shell_hull_mesh
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.add_child(hull)
	var cap := MeshInstance3D.new()
	cap.mesh = _shell_cap_mesh
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cap.position.y = -0.026
	shell.add_child(cap)
	return shell


static func _shell_mesh(radius: float, height: float, color: Color, metallic: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	mesh.material = material
	return mesh


static func render_warmup(weapons: Array) -> Node3D:
	var warmup := Node3D.new()
	warmup.hide()
	for id in weapons:
		var model := _make_model(id)
		warmup.add_child(model)
		if id == "shotgun":
			_apply_shotgun_material(model)
		if id in ["shotgun", "lever"]:
			warmup.add_child(_make_shell())
	warmup.add_child(_make_knife_model())
	return warmup


static func _make_model(weapon_id: String) -> Node3D:
	if weapon_id == "knife":
		return _make_knife_model()
	if weapon_id == "ak47":
		return AK47_MODEL.instantiate() as Node3D
	if weapon_id == "deagle":
		return DEAGLE_MODEL.instantiate() as Node3D
	if Classic.MODELS.has(weapon_id):
		return Classic.make_model(weapon_id)
	if ARSENAL.MODELS.has(weapon_id):
		return ARSENAL.make_model(weapon_id)
	var holder := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = SHOTGUN_MESH
	holder.add_child(mesh_instance)
	return holder


static func _make_knife_model() -> Node3D:
	var holder := Node3D.new()
	var knife := KNIFE_MODEL.instantiate() as Node3D
	knife.rotation.x = -PI * 0.5
	knife.scale = Vector3.ONE * 1.42
	knife.position.z = -0.071
	holder.add_child(knife)
	return holder


static func _apply_shotgun_material(model: Node3D) -> void:
	if _shotgun_material == null:
		_shotgun_material = StandardMaterial3D.new()
		_shotgun_material.albedo_texture = SHOTGUN_DIFFUSE
		_shotgun_material.normal_enabled = true
		_shotgun_material.normal_texture = SHOTGUN_NORMAL
		_shotgun_material.normal_scale = 0.85
		_shotgun_material.metallic = 1.0
		_shotgun_material.metallic_texture = SHOTGUN_SPEC
		_shotgun_material.metallic_texture_channel = StandardMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
		_shotgun_material.roughness = 0.62
		_shotgun_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		mesh_instance.material_override = _shotgun_material


static func _scale_longest_axis(model: Node3D, root: Node3D, length: float) -> void:
	var bounds := _view_bounds(model, root)
	var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if longest > 0.001:
		model.scale *= length / longest


static func add_pickup_model(parent: Node3D, id: String) -> void:
	var model := _make_model(id)
	parent.add_child(model)
	if id == "shotgun":
		_apply_shotgun_material(model)
		_scale_longest_axis(model, parent, 0.85)
	model.rotation.z = PI * 0.5
	var bounds := _view_bounds(model, parent)
	model.position = -bounds.get_center()
	model.position.y += bounds.size.y * 0.5
	for animation in model.find_children("*", "AnimationPlayer", true, false):
		animation.active = false


static func _muzzle_point(model: Node3D, weapon_id: String) -> Vector3:
	if weapon_id in ["launcher", "m249", "m1"]:
		return model.transform * _model_marker(model, "Muzzle")
	if Classic.MODELS.has(weapon_id):
		return model.transform * Classic.bone_point(model, &"FX_FIRE")
	match weapon_id:
		"ak47":
			return model.transform * (model.get_node("Muzzle") as Marker3D).position
		"shotgun":
			# Center of the ring at the front of the OBJ barrel.
			return model.transform * Vector3(-8.94, 3.048, -0.001)
		"deagle":
			return model.transform * Vector3(0.0, 0.188, 0.110)
		_:
			return model.transform * Vector3(0.0, 0.0, -0.252)


static func _model_marker(model: Node3D, marker_name: String) -> Vector3:
	var marker := model.find_child(marker_name, true, false) as Node3D
	return model.to_local(marker.global_position)


static func _view_bounds(model: Node3D, root: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var to_view: Transform3D = root.global_transform.affine_inverse() * mesh_instance.global_transform
		var piece: AABB = to_view * mesh_instance.get_aabb()
		bounds = piece if not found else bounds.merge(piece)
		found = true
	return bounds


func _marker(at: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.position = at
	_view.add_child(marker)
	return marker


func confirm_projectile_hit(headshot: bool = false) -> void:
	_cross.show_hit(headshot)


func _update_hud() -> void:
	if _ammo == null:
		return
	var progress := 1.0 - _reload_left / _reload_time if _reloading else -1.0
	_ammo.show_weapon(_stats.name, _stats.mode, _mag, _reserve, _stats.mag, progress, _stats.range,
		int(_stats.damage) if _weapon_id == "knife" else 0)
	_player.inventory_changed.emit()


func _make_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = &"Gunfire"
	add_child(player)
	return player


func _make_world_player() -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.bus = &"Gunfire"
	player.unit_size = 7.0
	player.max_distance = 48.0
	add_child(player)
	return player


func _play_shot(stream: AudioStream, volume_db: float, pitch: float) -> void:
	if not _shot_player.playing:
		_shot_player.play()
	var playback := _shot_player.get_stream_playback() as AudioStreamPlaybackPolyphonic
	playback.play_stream(stream, 0.0, volume_db, pitch, AudioServer.PLAYBACK_TYPE_STREAM, &"Gunfire")


func _play_on(player: AudioStreamPlayer, stream: AudioStream, volume_db: float, vary_pitch: bool) -> void:
	if stream == null:
		return
	if player.stream != stream:
		player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(0.97, 1.03) if vary_pitch else 1.0
	player.play()


func _play_pump() -> void:
	_play_on(_pump_player, SHOTGUN_PUMP if _weapon_id == "shotgun" else Classic.action_sound(_weapon_id), -6.0, true)


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
