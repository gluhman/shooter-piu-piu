extends SceneTree
## Reproduce the localized white-orb regression at the reported viewport size.
## Force FSR2 and verify the scoped glow workaround and preference restoration.
var failed := false
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	failed = failed or not ok
	print(("PASS " if ok else "FAIL ") + label)
func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	var settings := root.get_node("GameSettings")
	var saved_upscaling: int = settings.upscaling
	var saved_aa: int = settings.antialiasing
	settings.upscaling = Viewport.SCALING_3D_MODE_FSR2
	settings.antialiasing = 4
	settings.apply_graphics()
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	for id: int in [11, 3, 12]:
		await arena.start_solo(0, 1, 0, id, Vector2i.ZERO, 2)
		root.size = Vector2i(2890, 1741)
		root.always_on_top = true
		root.grab_focus()
		arena.get_node("HUD").hide()
		arena.combatant(1).hide()
		var camera := Camera3D.new()
		arena.add_child(camera)
		camera.make_current()
		var map := arena.get_node("Map")
		var at: Vector3 = map.initial_spawn(0)
		camera.position = Vector3(-36, 2.95, 36) if id == 11 else at + Vector3.UP * 1.65
		camera.look_at(camera.position + Vector3(sin(deg_to_rad(60.0)), 0.01, -cos(deg_to_rad(60.0))))
		var env: Environment = arena.get_node("WorldEnvironment").environment
		var metal := RenderingServer.get_current_rendering_driver_name() == "metal"
		if metal:
			check(not env.glow_enabled, "Map %d bypasses the faulty Metal glow pass" % id)
		check(settings.upscaling == Viewport.SCALING_3D_MODE_FSR2, "Saved upscaling choice is retained")
		check(root.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2, "FSR2 preference remains effective")
		var previous: Image
		var spots := 0
		for frame in 180:
			if frame == 90:
				settings.apply_graphics()
				if metal:check(not env.glow_enabled, "Graphics refresh retains the glow workaround")
			await process_frame
			await RenderingServer.frame_post_draw
			var original := root.get_texture().get_image()
			var image: Image = original.duplicate()
			image.resize(640, 384)
			var bright_spikes := 0
			if previous != null and frame > 15:
				for y in range(150, 370, 2):
					for x in range(20, 620, 2):
						var c := image.get_pixel(x,y)
						var low := minf(c.r,minf(c.g,c.b))
						var old := previous.get_pixel(x,y)
						var old_low := minf(old.r,minf(old.g,old.b))
						if low > 0.80 and maxf(c.r,maxf(c.g,c.b)) - low < 0.04 and low - old_low > 0.20:
							bright_spikes += 1
			if bright_spikes >= 3:
				spots += 1
				original.save_png("/tmp/terrain-dot-regression-%d-%d.png" % [id, frame])
			previous = image
		check(spots == 0, "Map %d: no transient localized white orbs in 180 frames (%d detections)" % [id, spots])
		if id == 11:
			var groups: Array = map.get_meta(&"terrain_grass_positions")
			var plants: Array = groups[0].duplicate()
			plants.sort_custom(func(a: Transform3D, b: Transform3D) -> bool: return a.origin.length_squared() < b.origin.length_squared())
			var target: Vector3 = plants[0].origin + Vector3.UP * 0.15
			for frame in 60:
				camera.position = target + Vector3(0.3 + frame * 0.004, 0.20, 0.45)
				camera.look_at(target)
				await process_frame
				await RenderingServer.frame_post_draw
				if frame in [0, 30, 59]:
					var closeup := root.get_texture().get_image()
					closeup.resize(1600, 964)
					closeup.save_png("/tmp/grass-stable-closeup-%d.png" % frame)
		camera.queue_free()
		arena._clear_match_map()
		await process_frame
	await arena.start_solo(0, 1, 0, 7, Vector2i.ZERO, 0)
	check(arena.get_node("WorldEnvironment").environment.glow_enabled, "Leaving affected maps restores glow automatically")
	settings.upscaling = saved_upscaling
	settings.antialiasing = saved_aa
	settings.apply_graphics()
	arena.queue_free()
	await process_frame
	print("FAIL terrain stability" if failed else "PASS terrain stability")
	quit(int(failed))
