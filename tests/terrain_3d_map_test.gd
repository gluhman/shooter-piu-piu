extends SceneTree
## Rendered regression: godot --path . --script res://tests/terrain_3d_map_test.gd
## Add -- --screenshots to save overview and shoreline captures in /tmp.

const MAP := preload("res://game/maps/map_builder.gd")
const FOREST := preload("res://game/maps/forest_ridge/forest_ridge_layout.gd")
var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run with a rendering display to verify Terrain3D")
		quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	root.size = Vector2i(1280, 800)
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	for selection: Vector2i in [Vector2i(MAP.FOREST_RIDGE_ID, 2), Vector2i(MAP.VILLAGE_ID, 0),
			Vector2i(MAP.VILLAGE_ID, 1), Vector2i(MAP.VILLAGE_ID, 2), Vector2i(MAP.REFINERY_ID, 2)]:
		await arena.start_solo(0, 1, 0, selection.x, Vector2i.ZERO, selection.y)
		var map := arena.get_node("Map")
		var surfaces := map.find_children("Terrain3DSurface", "Terrain3D", true, false)
		_check(surfaces.size() == 1, "%s/%d uses Terrain3D" % [MAP.MAP_NAMES[selection.x], selection.y])
		if surfaces.is_empty():
			continue
		var terrain: Terrain3D = surfaces[0]
		_check(terrain.collision_mode == Terrain3DCollision.DISABLED, "Terrain3D does not duplicate gameplay collision")
		_check(is_equal_approx(terrain.vertex_spacing, 0.5), "Half-meter terrain grid retained")
		_check(terrain.data.get_region_count() > 0, "Height and paint regions generated")
		var camera := Camera3D.new()
		arena.add_child(camera)
		camera.make_current()
		arena.get_node("HUD").hide()
		if selection.x == MAP.FOREST_RIDGE_ID:
			var water := map.find_child("DitchPools", true, false) as MeshInstance3D
			_check(water != null and water.mesh.get_faces().size() > 100, "Forest pools have a shoreline mesh")
			if water:
				var wet := 0
				var outside := 0
				var vertices := water.mesh.get_faces()
				for index in range(0, vertices.size(), 3):
					var center: Vector3 = (vertices[index] + vertices[index + 1] + vertices[index + 2]) / 3.0
					var bed := terrain.data.get_surface_height(center)
					wet += int(bed < FOREST.WATER_LEVEL + 0.025)
					outside += int(bed > FOREST.WATER_LEVEL + 0.025)
				_check(wet > 100 and outside == 0, "Water follows the sampled ditch bed (%d submerged triangles)" % outside)
				for side: float in [-1.0, 1.0]:
					var z := 2.1 if side > 0 else -2.4
					var x := side * (18.0 + 1.8 * sin(z * 0.19) + 0.8 * sin(z * 0.41))
					_check(terrain.data.get_height(Vector3(x, 0, z)) > FOREST.WATER_LEVEL, "Forest crossing stays dry")
			await _capture(camera, Vector3(42, 46, 55), Vector3.ZERO, "forest-overview")
			await _capture(camera, Vector3(20, 10, 19), Vector3(18.5, -2, 13), "forest-water")
		elif selection.x == MAP.VILLAGE_ID:
			var earth := map.get_node("VillageTerrain")
			_check(terrain.visible and not earth._visual.visible, "Village has a single visible ground surface")
			var tile := Vector2i(5, 5)
			var tiles: Array[Vector2i] = [tile]
			earth.set_cuts(tiles)
			_check(not terrain.visible and earth._visual.visible and earth._dirt.mesh != null,
				"Village excavation retains its refined surface and collision")
			tiles.clear()
			earth.set_cuts(tiles)
			_check(terrain.visible and not earth._visual.visible, "Reset restores Terrain3D")
			await _capture(camera, Vector3(22, 22, 27), Vector3.ZERO, "village-%d" % selection.y)
		else:
			_check(terrain.data.get_height(Vector3(24, 0, 0)) > 3.3, "Refinery terrace joins the deck")
			_check(absf(terrain.data.get_height(Vector3(0, 0, 28))) < 0.01, "Refinery yard stays level")
			await _capture(camera, Vector3(52, 44, 60), Vector3.ZERO, "refinery-overview")
		camera.queue_free()
		arena._clear_match_map()
		await process_frame
	arena.queue_free()
	await process_frame
	print("FAIL Terrain3D maps" if _failed else "PASS Terrain3D maps and Forest water")
	quit(int(_failed))


func _capture(camera: Camera3D, eye: Vector3, target: Vector3, label: String) -> void:
	camera.position = eye
	camera.look_at(target)
	await create_timer(0.7).timeout
	if "--screenshots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/terrain3d-%s.png" % label)


func _check(value: bool, label: String) -> void:
	if not value:
		_failed = true
		printerr("FAIL ", label)
	else:
		print("PASS ", label)
