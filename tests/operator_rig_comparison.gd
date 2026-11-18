extends Node3D
## Source mannequin and both operators, same native tracks, without gameplay IK.
const Pose := preload("res://game/actors/operator_pose.gd")
const HDRI := preload("res://assets/operator/textures/hd/studio_small_09_4k.hdr")
const REFERENCE := preload("res://assets/animations/mesh2motion/reference.glb")
var players: Array[AnimationPlayer] = []
var skeletons: Array[Skeleton3D] = []
var lines: Array[MeshInstance3D] = []
var clock := 0.0
var stage := -1
var captured: Array[int] = []
var label: Label
var paused := false
var show_rig := false
func _ready() -> void:
	for i in 3:
		var model: Node3D = [REFERENCE, Pose.MODEL, Pose.RED_MODEL][i].instantiate()
		model.position.x = (i - 1) * 1.25
		add_child(model)
		if i > 0: Pose.apply_textures(model, i - 1)
		var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
		skeletons.append(sk)
		for embedded in model.find_children("*", "AnimationPlayer", true, false): embedded.active = false
		var ap := AnimationPlayer.new()
		ap.root_node = NodePath("..")
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		ap.add_animation_library(&"", Pose.LOCOMOTION)
		sk.add_child(ap)
		players.append(ap)
		var wire := MeshInstance3D.new()
		wire.mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.3, 1.0, 0.5)
		mat.no_depth_test = true
		wire.material_override = mat
		wire.visible = show_rig
		add_child(wire)
		lines.append(wire)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(200, 200)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.08, 0.09, 0.11)
	floor_material.roughness = 0.9
	floor_mesh.material_override = floor_material
	floor_mesh.position.y = -0.03
	add_child(floor_mesh)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.025, 0.03, 0.04)
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_512
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = HDRI
	sky.sky_material = panorama
	env.environment.sky = sky
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.environment.ambient_light_energy = 0.7
	env.environment.ssao_enabled = true
	env.environment.ssao_radius = 0.22
	env.environment.ssao_intensity = 1.5
	env.environment.background_intensity = 1200.0
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	sun.light_intensity_lux = 12000.0
	add_child(sun)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.4, 6.2)
	camera.fov = 43
	var exposure := CameraAttributesPhysical.new()
	exposure.exposure_aperture = 8.0
	exposure.frustum_focal_length = 50.0
	exposure.exposure_shutter_speed = 60.0
	exposure.exposure_multiplier = 3.0
	camera.attributes = exposure
	add_child(camera)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.make_current()
	var overlay := CanvasLayer.new()
	add_child(overlay)
	label = Label.new()
	label.position = Vector2(25, 22)
	label.add_theme_font_size_override("font_size", 23)
	overlay.add_child(label)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
func _process(delta: float) -> void:
	if not paused: clock += delta
	var clips := Pose.LOCOMOTION.get_animation_list()
	stage = int(clock / 5.0) % (clips.size() + 1) - 1
	for i in players.size():
		var sk := skeletons[i]
		if stage < 0:
			players[i].stop()
			sk.reset_bone_poses()
		else:
			var clip := clips[stage]
			players[i].play(clip)
			players[i].seek(fmod(clock, 5.0) / 5.0 * Pose.LOCOMOTION.get_animation(clip).length, true)
		var wire := lines[i].mesh as ImmediateMesh
		wire.clear_surfaces()
		wire.surface_begin(Mesh.PRIMITIVE_LINES)
		for b in sk.get_bone_count():
			var parent := sk.get_bone_parent(b)
			if parent < 0: continue
			wire.surface_add_vertex(sk.to_global(sk.get_bone_global_pose(parent).origin))
			wire.surface_add_vertex(sk.to_global(sk.get_bone_global_pose(b).origin))
		wire.surface_end()
	label.text = "MESH2MOTION SOURCE       BLUE / BASE       RED\n66 bones · 40 finger bones · " + ("REST" if stage < 0 else String(clips[stage])) + "\nSpace: pause · ←/→: clip · B: skeleton"
	if fmod(clock, 5.0) > 2.5 and not captured.has(stage):
		captured.append(stage)
		_capture.call_deferred(stage)
func _capture(index: int) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/piupiu-rig-comparison-%d.png" % (index + 1))

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo(): return
	if event.keycode == KEY_SPACE: paused = not paused
	if event.keycode == KEY_RIGHT: clock = (floor(clock / 5.0) + 1) * 5.0 + 2.5
	if event.keycode == KEY_LEFT: clock = maxf(0.0, (floor(clock / 5.0) - 1) * 5.0 + 2.5)
	if event.keycode == KEY_B:
		show_rig = not show_rig
		for wire in lines: wire.visible = show_rig
