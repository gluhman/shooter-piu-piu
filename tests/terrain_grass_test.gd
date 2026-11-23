extends SceneTree
## Rendered grass brush regression across all maps. Add -- --screenshots for /tmp captures.
const MAP := preload("res://game/maps/map_builder.gd")
const GRASS := preload("res://game/maps/foliage/terrain_grass.gd")
var _failed := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run this visual test with a rendering display")
		quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	for variant in ["short", "tall"]:
		var asset := load(GRASS.ASSET_ROOT + "grass_%s.tres" % variant) as Terrain3DMeshAsset
		var mesh := asset.get_mesh()
		var bounds := mesh.get_aabb()
		_check(absf(bounds.position.y) < 0.001, "%s grass roots sit at the object origin" % variant)
		_check(is_equal_approx(bounds.size.y, 0.20 if variant == "short" else 0.70), "%s grass has its authored height" % variant)
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	var maps: Array = [11, 3, 12, 9, 0, 1, 2, 4, 5, 6, 7, 8, 10]
	var args := OS.get_cmdline_user_args()
	if "--maps" in args:
		maps = Array(args[args.find("--maps") + 1].split(",")).map(func(id: String) -> int: return int(id))
	for id: int in maps:
		await arena.start_solo(0, 1, 0, id, Vector2i.ZERO, 2)
		if "--screenshots" in args:
			root.size = Vector2i(1600, 960)
			root.always_on_top = true
			root.grab_focus()
		await RenderingServer.frame_post_draw
		await process_frame
		var map := arena.get_node("Map")
		if id not in GRASS.OUTDOOR_MAPS:
			_check(not map.has_meta(&"terrain_grass_counts"), "%s remains indoors without grass" % MAP.MAP_NAMES[id])
		else:
			var counts: Vector2i = map.get_meta(&"terrain_grass_counts", Vector2i.ZERO)
			_check(counts.x > 0 and counts.y > 0, "%s has short and tall grass (%s)" % [MAP.MAP_NAMES[id], counts])
			if id in GRASS.DENSE_MAPS:
				_check(map.get_meta(&"terrain_grass_style") == "dense_blades", "Requested map uses tutorial-style blade grass")
				_check(counts.x + counts.y > {11: 80000, 3: 20000, 12: 12000}[id], "Lawn covers plantable areas with closely spaced tufts")
				_check(counts.x > (counts.x + counts.y) * 0.90, "Short lawn dominates instead of scattered tall clumps")
			var terrains := map.find_children("*", "Terrain3D", true, false)
			_check(terrains.size() == 1, "One Terrain3D instancer per outdoor map")
			if not terrains.is_empty():
				var terrain: Terrain3D = terrains[0]
				_check(terrain.assets.get_mesh_asset(0).scene_file != null and terrain.assets.get_mesh_asset(0).get_mesh().get_aabb().size.y < 0.25, "Instancer uses the prepared object, not generated cards")
				_check(terrain.assets.get_mesh_count() == 2, "Both reusable mesh brushes are registered")
				if id in GRASS.DENSE_MAPS:
					var blade_mesh := terrain.assets.get_mesh_asset(0).get_mesh()
					_check(blade_mesh.resource_name.begins_with("Dense tapered"), "Dense grass uses shaped opaque blades")
					_check(blade_mesh.get_faces().size() >= 300, "Lawn tufts contain enough blades to overlap")
				_check(terrain.assets.get_mesh_asset(0).get_instance_count() == counts.x
					and terrain.assets.get_mesh_asset(1).get_instance_count() == counts.y, "Native instance counts match brush placements")
				_check(terrain.collision_mode == Terrain3DCollision.DISABLED, "Grass does not add collision")
			var clear := true
			for group: Array in map.get_meta(&"terrain_grass_positions", []):
				for placement: Transform3D in group:
					for start: Vector3 in map._initial_spawns:
						clear = clear and Vector2(start.x - placement.origin.x, start.z - placement.origin.z).length_squared() >= 5.76
			_check(clear, "Starting positions remain clear of grass")
			if "--screenshots" in OS.get_cmdline_user_args():
				var camera := Camera3D.new()
				arena.add_child(camera)
				camera.make_current()
				var groups: Array = map.get_meta(&"terrain_grass_positions")
				var plants: Array = groups[0].duplicate()
				plants.sort_custom(func(a: Transform3D, b: Transform3D) -> bool: return a.origin.length_squared() < b.origin.length_squared())
				if not plants.is_empty():
					var space: PhysicsDirectSpaceState3D = map.get_world_3d().direct_space_state
					var query := PhysicsRayQueryParameters3D.new()
					query.collision_mask = 1
					for plant: Transform3D in plants:
						var target := plant.origin + Vector3.UP * 0.27
						var eye := target + Vector3(1.8, 1.0, 2.1)
						query.from = target
						query.to = eye
						if not space.intersect_ray(query).is_empty():
							continue
						camera.position = eye
						camera.look_at(target)
						break
					arena.get_node("HUD").hide()
					await create_timer(0.5).timeout
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("/tmp/terrain-grass-%02d.png" % id)
				camera.queue_free()
		arena._clear_match_map()
		await process_frame
	arena.queue_free()
	await process_frame
	print("FAIL Terrain3D outdoor grass" if _failed else "PASS Terrain3D outdoor grass across all maps")
	quit(int(_failed))

func _check(value: bool, label: String) -> void:
	if not value:
		_failed = true
		printerr("FAIL ", label)
	else:
		print("PASS ", label)
