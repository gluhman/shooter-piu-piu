extends SceneTree

const MAP := preload("res://game/maps/map_builder.gd")
const TEMPLATE := preload("res://game/maps/lighting/forest_ridge_visuals.tres")
const BACKGROUND_PROPERTIES := ["sky", "sky_rotation", "background_mode", "background_color",
	"background_energy_multiplier", "background_intensity", "background_canvas_max_layer"]
var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	# Independently verify that applying the template cannot replace a map's background.
	var probe := Environment.new()
	probe.sky = Sky.new()
	probe.sky.sky_material = ProceduralSkyMaterial.new()
	probe.sky_rotation = Vector3(0.1, 0.7, 0.2)
	probe.background_mode = Environment.BG_SKY
	probe.background_intensity = 12345.0
	var background := {}
	for key in BACKGROUND_PROPERTIES:
		background[key] = probe.get(key)
	TEMPLATE.apply_environment(probe)
	for key in background:
		_check(probe.get(key) == background[key], "Template preserves %s" % key)
	for key: String in TEMPLATE.environment_settings:
		_check(not key.begins_with("background_") and key != "sky" and not key.begins_with("sky_"),
			"Background excluded from template: %s" % key)
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	var maps := [MAP.FOREST_RIDGE_ID, MAP.BREAKWATER_ID]
	for map_id in MAP.MAP_NAMES.size():
		if map_id not in maps:
			maps.append(map_id)
	for map_id in maps:
		await arena.start_solo(0, 1, 0, map_id, Vector2i.ZERO, MAP.DEFAULT_SIZE)
		var world := arena.get_node("WorldEnvironment") as WorldEnvironment
		var sun := world.get_node("SunLight") as DirectionalLight3D
		if map_id == MAP.BREAKWATER_ID:
			world = arena._breakwater.get_node("WorldEnvironment") as WorldEnvironment
			sun = arena._breakwater.get_node("Sun") as DirectionalLight3D
		for key: String in TEMPLATE.environment_settings:
			if key in ["ssao_enabled", "ssil_enabled", "sdfgi_enabled", "ambient_light_color", "adjustment_color_correction"]:
				continue
			if key == "ambient_light_source" and world.environment.sky == null:
				continue
			var actual: Variant = world.environment.get(key)
			var expected: Variant = TEMPLATE.environment_settings[key]
			if key == "glow_enabled" and RenderingServer.get_current_rendering_driver_name() == "metal" \
					and map_id in [MAP.FOREST_RIDGE_ID, MAP.VILLAGE_ID, MAP.REFINERY_ID]:
				expected = false
			var matches: bool = is_equal_approx(actual, expected) if expected is float else actual == expected
			_check(matches, "%s: %s (actual %s, expected %s)" % [map_id, key, actual, expected])
		_check(world.camera_attributes != null, "Camera profile restored")
		_check(is_equal_approx(sun.light_intensity_lux, 95000.0), "Forest Ridge sun intensity")
		_check_background(map_id, world.environment)
		var original_sky := world.environment.sky
		var settings := root.get_node("GameSettings")
		var ao_before: bool = settings.ambient_occlusion
		var shadows_before: bool = settings.shadows
		settings.ambient_occlusion = false
		settings.shadows = false
		arena._apply_graphics()
		_check(not world.environment.ssao_enabled and not sun.shadow_enabled, "Graphics controls apply")
		settings.ambient_occlusion = ao_before
		settings.shadows = shadows_before
		arena._apply_graphics()
		arena.net_clock(45)
		await create_timer(0.5).timeout
		_check(world.environment.sky == original_sky, "Clock preserves map background")
		_check_background(map_id, world.environment)
		if DisplayServer.get_name() != "headless" and "--screenshots" in OS.get_cmdline_user_args():
			arena.get_node("HUD").hide()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/piupiu-forest-template-%02d.png" % map_id)
		print("Checked Forest Ridge template and original background: ", MAP.MAP_NAMES[map_id])
		arena._clear_match_map()
		await process_frame
	arena.queue_free()
	await process_frame
	print("FAIL map visual template" if _failed else "PASS Forest Ridge template and original backgrounds across all 13 maps")
	quit(int(_failed))


func _check_background(map_id: int, environment: Environment) -> void:
	if map_id == MAP.OFFICE_ID:
		_check(environment.background_mode == Environment.BG_COLOR and environment.sky == null,
			"Office keeps its color background")
		return
	_check(environment.sky != null, "Map retains its sky")
	if environment.sky == null:
		return
	var material := environment.sky.sky_material
	if map_id == MAP.BREAKWATER_ID:
		_check(material is PanoramaSkyMaterial and material.panorama.resource_path.ends_with("freight_station.hdr"),
			"Breakwater keeps freight station HDRI")
	elif DisplayServer.get_name() != "headless" and map_id == MAP.OUTPOST_ID:
		_check(material is PanoramaSkyMaterial and material.panorama.resource_path.ends_with("kloofendal_overcast_puresky_2k.hdr"),
			"Farpost keeps its HDRI")
	elif DisplayServer.get_name() != "headless" and map_id == MAP.STATION_ID:
		_check(material is ShaderMaterial and material.shader.resource_path.ends_with("station_sky.gdshader"),
			"Station keeps its night background")
	elif DisplayServer.get_name() != "headless" and map_id == MAP.REFINERY_ID:
		_check(material is ShaderMaterial and material.shader.resource_path.ends_with("refinery_sky.gdshader"),
			"Refinery keeps its hilltop background")
	else:
		_check(material is ShaderMaterial and material.shader.resource_path.ends_with("SkyMaterial.gdshader"),
			"Map keeps original dynamic sky")


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		printerr("FAIL ", message)
