extends SceneTree
## Render the actual flying RPG and its two-metre exhaust under the grip studio light.
var arena: Node3D
var grenades: Node3D
var camera: Camera3D
var flight: RefCounted
var age := 0.0
var capturing := false
var capture_count := 0

func _initialize() -> void:
	_setup.call_deferred()

func _setup() -> void:
	arena = load("res://game/match/arena.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	arena.get_node("WorldEnvironment").process_mode = Node.PROCESS_MODE_DISABLED
	arena.get_node("WorldEnvironment").environment = null
	arena.get_node("WorldEnvironment").camera_attributes = null
	for layer in arena.find_children("*", "CanvasLayer", true, false): layer.hide()
	for light in arena.find_children("*", "Light3D", true, false): light.hide()
	var studio := WorldEnvironment.new()
	studio.environment = Environment.new()
	studio.environment.background_mode = Environment.BG_COLOR
	studio.environment.background_color = Color(.025, .032, .045)
	var sky := Sky.new()
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = load("res://assets/operator/textures/hd/studio_small_09_4k.hdr")
	sky.sky_material = panorama
	studio.environment.sky = sky
	studio.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	studio.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	studio.environment.background_intensity = 1200.0
	studio.environment.ambient_light_energy = .7
	studio.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	studio.environment.glow_enabled = true
	arena.add_child(studio)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_intensity_lux = 12000.0
	arena.add_child(sun)
	camera = Camera3D.new()
	var exposure := CameraAttributesPhysical.new()
	exposure.exposure_aperture = 8.0
	exposure.frustum_focal_length = 40.0
	exposure.frustum_focus_distance = 4.0
	exposure.exposure_shutter_speed = 60.0
	exposure.exposure_multiplier = 3.0
	camera.attributes = exposure
	arena.add_child(camera)
	camera.make_current()
	grenades = arena.get_node("Grenades")
	grenades.set_physics_process(false)
	grenades.net_launch(47, "rocket", Vector3(0, 30, 0), Vector3.FORWARD * 85.0, 5.0, 1)
	flight = grenades._flights[47]

func _process(delta: float) -> bool:
	if capturing or not is_instance_valid(flight): return false
	var step := minf(delta, 1.0 / 60.0)
	age += step
	grenades._step(flight, step, root.get_world_3d().direct_space_state, false)
	camera.global_position = flight.at + Vector3(3.2, .6, 1.5)
	camera.look_at(flight.at + Vector3.BACK * .75)
	if age > .6 + float(capture_count) * .2 and not capturing:
		capturing = true
		_capture.call_deferred()
	return false

func _capture() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/rpg-flame-trail.png")
	root.get_texture().get_image().save_png("/tmp/rpg-flame-frame-%d.png" % capture_count)
	print("CAPTURE actual RPG curved flight and two-metre flame trail")
	capture_count += 1
	if "--sequence" in OS.get_cmdline_user_args() and capture_count < 4:
		capturing = false
		return
	flight = null
	arena.queue_free()
	await process_frame
	quit()
