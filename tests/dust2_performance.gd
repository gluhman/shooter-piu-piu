extends SceneTree

const TARGET := Vector2i(2560, 1440)
const DUST_II := 4
const SAMPLE_TIME := 12.0
const WARMUP := 4.0
const POINTS := [0, 7, 13]
const DIRECTIONS := [Vector3(0.7, -0.06, -1.0), Vector3(-0.7, -0.05, 1.0), Vector3(-1.0, -0.08, -0.3)]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FAIL performance measurement requires a graphical window")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var profile := args[0] if not args.is_empty() else "default"
	var settings := root.get_node("GameSettings")
	settings.fullscreen = false
	settings.vsync = false
	settings.fps_limit = 0
	settings.render_scale = 1.0
	if "upscaling" in settings:
		settings.upscaling = Viewport.SCALING_3D_MODE_FSR if profile == "fsr1-75" else Viewport.SCALING_3D_MODE_BILINEAR
		settings.shadow_distance = 52 if profile in ["same-shadows", "4-cascades"] else 36
		settings.shadow_cascades = int(profile == "4-cascades")
		settings.ssao_quality = 1
		settings.anisotropy = 2
		settings.effects_detail = 1
	else:
		settings.fsr2 = false
	settings.antialiasing = 0
	settings.shadows = profile != "no-shadows"
	settings.ambient_occlusion = profile != "no-ssao"
	settings.apply_graphics()
	AudioServer.set_bus_mute(0, true)
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	await process_frame
	await RenderingServer.frame_post_draw
	var dpi := root.get_texture().get_size() / Vector2(root.size)
	root.size = Vector2i(Vector2(TARGET) / dpi)
	root.position = Vector2i.ZERO
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.scaling_3d_scale = 0.75 if profile in ["75%", "fsr1-75"] else 1.0
	if root.get_texture().get_size() != Vector2(TARGET):
		printerr("FAIL framebuffer ", root.get_texture().get_size(), " window ", root.size, " dpi ", dpi)
		quit(1)
		return

	seed(45821)
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	var load_start := Time.get_ticks_usec()
	await arena.start_solo(10, 1, 0, DUST_II, Vector2i.ZERO, 2)
	var load_ms := (Time.get_ticks_usec() - load_start) / 1000.0
	if get_nodes_in_group("bot").size() != 10:
		printerr("FAIL expected 10 bots")
		quit(1)
		return
	arena.get_node("HUD/WeaponSelect").hide()
	var camera := Camera3D.new()
	arena.add_child(camera)
	camera.fov = 74.0
	camera.make_current()
	var map := arena.get_node("Map")
	_place_camera(camera, map, 0)

	var viewport := root.get_viewport_rid()
	var sun := arena.get_node("WorldEnvironment/SunLight") as DirectionalLight3D
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	await create_timer(WARMUP).timeout
	var frames := PackedFloat64Array()
	var gpu := PackedFloat64Array()
	var script_ms := PackedFloat64Array()
	var physics_ms := PackedFloat64Array()
	var draws := PackedFloat64Array()
	var combats := [0]
	arena.damage_resolved.connect(func(_event: Dictionary) -> void: combats[0] += 1)
	var previous := Time.get_ticks_usec()
	var start := previous
	var current_view := 0
	while (previous - start) / 1000000.0 < SAMPLE_TIME:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - previous) / 1000.0)
		previous = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
		script_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var view := mini(int((now - start) / (1000000.0 * SAMPLE_TIME / POINTS.size())), POINTS.size() - 1)
		if view != current_view:
			current_view = view
			_place_camera(camera, map, view)
	frames.sort()
	var worst_count := maxi(1, ceili(frames.size() * 0.01))
	var worst_sum := 0.0
	for index in range(frames.size() - worst_count, frames.size()):
		worst_sum += frames[index]
	print("BENCH ", JSON.stringify({
		"profile": profile, "framebuffer": str(root.get_texture().get_size()), "render_scale": root.scaling_3d_scale,
		"shadow_distance": sun.directional_shadow_max_distance, "shadow_mode": sun.directional_shadow_mode,
		"frames": frames.size(), "fps": frames.size() * 1000000.0 / (previous - start),
		"low_1pct_fps": 1000.0 * worst_count / worst_sum,
		"p95_ms": _percentile(frames, 0.95), "p99_ms": _percentile(frames, 0.99), "max_ms": frames[-1],
		"over_33ms": frames.size() - frames.bsearch(33.333),
		"gpu_p95_ms": _sorted_percentile(gpu, 0.95), "process_p95_ms": _sorted_percentile(script_ms, 0.95),
		"physics_p95_ms": _sorted_percentile(physics_ms, 0.95), "draws_p50": _sorted_percentile(draws, 0.5),
		"damage_events": combats[0], "match_load_ms": load_ms, "bots": get_nodes_in_group("bot").size(),
	}))
	arena.queue_free()
	await process_frame
	quit()

func _place_camera(camera: Camera3D, map: Node, view: int) -> void:
	camera.global_position = map.initial_spawn(POINTS[view]) + Vector3.UP * 1.62
	camera.look_at(camera.global_position + DIRECTIONS[view])

func _sorted_percentile(values: PackedFloat64Array, p: float) -> float:
	values.sort()
	return _percentile(values, p)

func _percentile(values: PackedFloat64Array, p: float) -> float:
	return values[clampi(ceili(values.size() * p) - 1, 0, values.size() - 1)]
