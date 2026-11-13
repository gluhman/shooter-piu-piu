extends SceneTree

const MAP := preload("res://game/maps/map_builder.gd")

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await arena.start_solo(0, 1, 0, MAP.OFFICE_ID, Vector2i.ZERO, 0)
	var grenades := arena.get_node("Grenades")
	var sky := arena.get_node("WorldEnvironment")
	sky.wind_speed = 2.0
	var fixtures := arena.get_node("Map/VillageFixtures")
	var door = fixtures._doors[4]
	var through: Vector3 = door.portal.basis.z
	var origin: Vector3 = door.portal.origin - through * 0.9
	grenades.net_smoke(origin, 18.0, 3.0)
	await create_timer(0.25).timeout
	var cloud = grenades._clouds[0]
	var near := origin + Vector3.UP * 1.45
	var beyond := near + through * 1.6
	_check(cloud.indoor and cloud.wind.is_zero_approx() and cloud.center.is_equal_approx(near),
		"Office roof blocks wind")
	_check(grenades._inside_smoke(cloud, near, 3.5) and not grenades._inside_smoke(cloud, beyond, 3.5),
		"Closed office door blocks smoke")
	var across := Vector3(through.z, 0.0, -through.x)
	_check(not grenades.obscures(beyond - across * 0.1, beyond + across * 0.1),
		"Visibility stays clear on the other side of the closed door")
	fixtures._apply_door(door, true)
	await create_timer(0.35).timeout
	_check(grenades._inside_smoke(cloud, beyond, 3.5) and grenades.obscures(beyond - across * 0.1, beyond + across * 0.1),
		"Opened door lets smoke and its visibility effect through")
	fixtures._apply_door(door, false)
	await create_timer(0.35).timeout
	_check(not grenades._inside_smoke(cloud, beyond, 3.5), "Closing the door clips smoke again")

	arena._clear_match_map()
	await process_frame
	await arena.start_solo(0, 1, 0, MAP.OUTPOST_ID, Vector2i.ZERO, 1)
	sky.wind_direction = 0.0
	sky.wind_speed = 2.0
	var outdoors := Vector3(12.0, 0.02, -14.0)
	grenades.net_smoke(outdoors, 18.0, 3.0)
	await create_timer(0.25).timeout
	cloud = grenades._clouds[0]
	_check(not cloud.indoor and cloud.center.z > outdoors.z + 1.0 and cloud.center.z <= outdoors.z + 4.0,
		"Outdoor smoke drifts downwind")
	var wall_center := outdoors + Vector3(0.0, 1.5, 1.0)
	arena.get_node("Map")._add_box(wall_center, Vector3(5.0, 3.0, 0.20), StandardMaterial3D.new())
	await create_timer(0.35).timeout
	_check(cloud.center.z < wall_center.z - 0.10
		and not grenades._inside_smoke(cloud, wall_center + Vector3.BACK * 0.3, 3.5),
		"Outdoor wall stops downwind drift and clips the cloud")
	arena.queue_free()
	await process_frame
	quit(int(_failed))


func _check(ok: bool, message: String) -> void:
	_failed = _failed or not ok
	print("PASS " if ok else "FAIL ", message)
