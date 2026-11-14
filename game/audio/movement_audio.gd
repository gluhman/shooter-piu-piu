extends "res://addons/spatial_audio_3d/spatial_audio_3d.gd"

const Balance := preload("res://game/combat/combat_balance.gd")
const CONCRETE_VARIANTS := preload("res://game/audio/footsteps.gd").STEPS
const REMOTE_HEARING_DISTANCE := 50.0
const STEPS := {
	"concrete": preload("res://assets/match_audio/step_concrete.wav"),
	"metal": preload("res://assets/match_audio/step_metal.wav"),
	"wood": preload("res://assets/match_audio/step_wood.wav"),
}

const STATION_STEPS := {
	"station_steel": [
		preload("res://game/maps/station/audio/steel_01.wav"),
		preload("res://game/maps/station/audio/steel_02.wav"),
		preload("res://game/maps/station/audio/steel_03.wav"),
		preload("res://game/maps/station/audio/steel_04.wav"),
		preload("res://game/maps/station/audio/steel_05.wav"),
		preload("res://game/maps/station/audio/steel_06.wav"),
	],
	"station_stairs": [
		preload("res://game/maps/station/audio/stairs_01.wav"),
		preload("res://game/maps/station/audio/stairs_02.wav"),
		preload("res://game/maps/station/audio/stairs_03.wav"),
		preload("res://game/maps/station/audio/stairs_04.wav"),
		preload("res://game/maps/station/audio/stairs_05.wav"),
		preload("res://game/maps/station/audio/stairs_06.wav"),
	],
}

static var _concrete_steps: AudioStreamRandomizer
static var _station_steps: Dictionary[String, AudioStreamRandomizer] = {}

var actor: CharacterBody3D
var use_acoustics := false
var grounded := false
var _map: Node
var _floor_ray := PhysicsRayQueryParameters3D.new()
var _last_position: Vector3
var _has_floor_sample := false
var _distance := 0.0
var _fall_speed := 0.0
var _elapsed := 0.0


func _ready() -> void:
	if _concrete_steps == null:
		_concrete_steps = AudioStreamRandomizer.new()
		_concrete_steps.add_stream(0, STEPS["concrete"])
		for variant in CONCRETE_VARIANTS:
			_concrete_steps.add_stream(_concrete_steps.streams_count, variant)
		for surface: String in STATION_STEPS:
			var steps := AudioStreamRandomizer.new()
			steps.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
			for sample: AudioStream in STATION_STEPS[surface]:
				steps.add_stream(steps.streams_count, sample)
			_station_steps[surface] = steps
	bus = &"Footsteps"
	_map = actor.get_parent().get_node("Map")
	_floor_ray.collision_mask = actor.collision_mask
	_floor_ray.exclude = [actor.get_rid()]
	position.y = 0.14
	unit_size = 2.6
	max_distance = 18.0
	max_db = 0.0
	attenuation_filter_db = -16.0
	panning_strength = 1.25
	if use_acoustics:
		unit_size = 11.0
		max_distance = REMOTE_HEARING_DISTANCE
		max_db = -6.0
		attenuation_filter_db = -6.0
		panning_strength = 1.5
		reverb_enabled = false
		collision_mask = Balance.WORLD_MASK
		occlusion_lp_cutoff = 4200
		occlusion_min_lp_cutoff = 1600
		occlusion_fadetime = 0.0
		super._ready()
	reset()


func _physics_process(delta: float) -> void:
	if use_acoustics:
		super._physics_process(delta)


func reset() -> void:
	if playing:
		stop()
	if use_acoustics and (soundsource.soundplayer_active.playing or soundsource.soundplayer_standby.playing):
		do_stop()
	_last_position = actor.global_position
	grounded = false
	_has_floor_sample = false
	_distance = 0.0
	_fall_speed = 0.0
	_elapsed = 0.0


func track(delta: float, simulated: bool, crouched: bool) -> void:
	_elapsed += delta
	var motion := actor.global_position - _last_position
	_last_position = actor.global_position
	if not simulated and _has_floor_sample and motion.is_zero_approx():
		return
	if motion.length_squared() > 9.0:
		reset()
		return
	var vertical_speed := motion.y / _elapsed
	var horizontal := Vector2(motion.x, motion.z).length()
	var speed := horizontal / _elapsed
	_elapsed = 0.0

	var was_grounded := grounded
	if simulated:
		grounded = actor.is_on_floor()
	elif not grounded or absf(motion.y) > 0.005:
		grounded = not _floor_hit().is_empty()
	_has_floor_sample = true
	if not grounded:
		_distance = 0.0
		_fall_speed = maxf(_fall_speed, -vertical_speed)
		if was_grounded and vertical_speed > 1.6:
			_play_step(-12.0, 1.12, motion.y)
		return
	if not was_grounded and _fall_speed > 1.6:
		_play_step(clampf(_fall_speed - 10.0, -8.0, -4.0), 0.78)
		_fall_speed = 0.0
		return
	_fall_speed = 0.0
	if speed < 0.4:
		return
	var sprinting := speed > 5.8 and not crouched
	var stride := 1.1 if crouched else clampf(0.65 + speed * 0.18, 1.1, 2.0)
	_distance += horizontal
	if _distance >= stride:
		_distance = fmod(_distance, stride)
		_play_step(-15.0 if crouched else (-6.0 if sprinting else -9.0), 0.93 if crouched else 1.0)


func _floor_hit(rise: float = 0.0) -> Dictionary:
	var feet := actor.global_position - Vector3.UP * rise
	_floor_ray.from = feet + Vector3.UP * 0.10
	_floor_ray.to = feet - Vector3.UP * 0.13
	var hit := get_world_3d().direct_space_state.intersect_ray(_floor_ray)
	return hit if hit.get("collider") is StaticBody3D else {}


func _play_step(level: float, pitch: float, rise: float = 0.0) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera or camera.global_position.distance_squared_to(global_position) > max_distance * max_distance:
		return
	var hit := _floor_hit(rise)
	var collider: StaticBody3D = hit.get("collider")
	var surface := "concrete"
	if collider:
		surface = collider.get_meta(&"footstep_surface", collider.get_meta(&"impact_surface", "concrete"))
	if surface == "concrete" and collider and _map.has_wood_deck_at(hit.position):
		surface = "wood"
	var sample: AudioStream = STEPS.get(surface, _concrete_steps) if surface != "concrete" else _concrete_steps
	if _station_steps.has(surface):
		sample = _station_steps[surface]
		level -= 3.0
		pitch *= 0.96
	var varied_pitch := pitch * randf_range(0.91, 1.09)
	if use_acoustics:
		play_one_shot(sample, level, varied_pitch)
		return
	stream = sample
	volume_db = level
	pitch_scale = varied_pitch
	play()
