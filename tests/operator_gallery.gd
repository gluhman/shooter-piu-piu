extends Node3D
## F6: actual match actors and weapon IK under a reproducible Poly Haven studio.
const HDRI := preload("res://assets/operator/textures/hd/studio_small_09_4k.hdr")
var actors: Array[Node] = []
var camera: Camera3D
var clock := 0.0
var stage := 0
var label: Label
var captured: Array[int] = []
var grip_errors: Dictionary = {}
func _ready() -> void:
	set_process(false)
	var arena = load("res://game/match/arena.tscn").instantiate()
	add_child(arena)
	await arena.start_solo(2, 1, 0, 0, Vector2i.ZERO, 0, true, false, 1)
	arena.set_process(false)
	arena.set_physics_process(false)
	arena.get_node("WorldEnvironment").process_mode=Node.PROCESS_MODE_DISABLED
	arena.get_node("Map").hide()
	arena.get_node("Loot").hide()
	arena.get_node("WorldEnvironment").environment = null
	arena.get_node("WorldEnvironment").camera_attributes = null
	for light in arena.find_children("*", "Light3D", true, false):light.hide()
	for layer in arena.find_children("*", "CanvasLayer", true, false):layer.hide()
	var local: Node = arena.combatant(1)
	local.hide();local.control_enabled=false;local.set_physics_process(false);local.set_process(false)
	for bot in get_tree().get_nodes_in_group("bot"):
		actors.append(bot)
		bot._pose.pose_finished.connect(_measure_grips.bind(bot))
		bot.control_enabled = false
		bot.set_physics_process(false)
		bot.set_process(false)
		if is_instance_valid(bot._overhead):bot._overhead.hide()
		bot.position = Vector3(-0.62 if bot.team_id() == 0 else 0.62, 0.0, 0.0)
		bot.rotation.y = PI
		bot.gun.equip("ak47")
	var plane := MeshInstance3D.new();plane.mesh = PlaneMesh.new();plane.mesh.size=Vector2(200,200)
	var ground := StandardMaterial3D.new();ground.albedo_color=Color(0.055,0.065,0.078);ground.roughness=.88
	plane.material_override=ground;plane.position.y=-.012;add_child(plane)
	var env := WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.028,.036,.05)
	var sky := Sky.new();sky.radiance_size=Sky.RADIANCE_SIZE_512
	var panorama := PanoramaSkyMaterial.new();panorama.panorama=HDRI;sky.sky_material=panorama
	env.environment.sky=sky;env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	env.environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	env.environment.background_intensity=1200.0;env.environment.ambient_light_energy=.7;env.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	env.environment.ssao_enabled=true;env.environment.ssao_radius=.25;env.environment.ssao_intensity=1.6
	add_child(env)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-30,0);sun.light_energy=.65;sun.light_intensity_lux=12000.0;sun.shadow_enabled=true;add_child(sun)
	camera=Camera3D.new();camera.fov=39;
	var exposure := CameraAttributesPhysical.new();exposure.exposure_aperture=8.0;exposure.frustum_focal_length=50.0;exposure.exposure_shutter_speed=60.0;exposure.exposure_multiplier=3.0;camera.attributes=exposure;
	camera.position=Vector3(2.4,1.5,4.8);add_child(camera);camera.look_at(Vector3(0,1,0));camera.make_current()
	var overlay := CanvasLayer.new();add_child(overlay);label=Label.new();label.position=Vector2(28,24);label.add_theme_font_size_override("font_size",24);overlay.add_child(label)
	get_viewport().scaling_3d_scale = 1.0
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	set_process(true)
func _process(delta: float) -> void:
	clock += delta
	var next := int(clock / 7.0) % 14
	if next != stage:
		stage=next
		camera.position = Vector3(-0.05, 1.5, 1.55) if stage == 5 else Vector3(2.4,1.5,4.8)
		camera.look_at(Vector3(-0.62,1.35,0.32) if stage == 5 else Vector3(0,1,0))
		for actor in actors:
			actor.gun.equip("knife" if stage == 4 else "deagle" if stage == 3 else "ak47")
			if stage == 9:
				actor.gun._mag = 0
				actor.gun.reload_bot()
	for actor in actors:
		actor.crouched=stage==2 or stage>=10
		actor.aiming=stage==13
		actor.control_enabled=actor.aiming
		actor._crouch_blend=move_toward(actor._crouch_blend,float(actor.crouched),delta*7.5)
		var local_motion := Vector3.FORWARD * 1.65 if stage == 10 else Vector3.BACK * 1.65 if stage == 11 else Vector3.LEFT * 1.65 if stage == 12 else Vector3.FORWARD * 2.0 if stage == 1 else Vector3.BACK * 2.0 if stage == 6 else Vector3.LEFT * 2.0 if stage == 7 else Vector3.RIGHT * 2.0 if stage == 8 else Vector3.ZERO
		actor._visual_velocity=actor.global_basis * local_motion
		actor._pose.planar_velocity=actor._visual_velocity
		actor._pose.grounded=true
		actor._pose.update_locomotion(delta, actor.crouched,0.0)
		actor._update_view_pose()
		actor.gun.update_pose(delta)
	label.text="БАЗОВЫЙ / СИНИЙ                 КРАСНЫЙ\n"+["Винтовка · стойка","Винтовка · шаг","Винтовка · присед","Пистолет · хват","Нож · хват","Пальцы · контакт с оружием","Шаг назад","Шаг влево","Шаг вправо","Перезарядка","Присед · шаг вперёд","Присед · шаг назад","Присед · шаг в сторону","Присед · прицеливание"][stage]

	if fmod(clock, 7.0) > 2.0 and not captured.has(stage):
		captured.append(stage)
		_capture.call_deferred(stage)

func _capture(index: int) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/piupiu-gallery-%d.png" % index)
	print("GRIP stage=", index, " palm_gap_m=", grip_errors)

func _measure_grips(actor: Node) -> void:
	var sk: Skeleton3D = actor._skeleton
	var gaps: Array[float] = []
	for right in [true, false]:
		var bone: int = actor._pose._right_arm[2] if right else actor._pose._left_arm[2]
		var palm: Marker3D = actor._pose.right_palm if right else actor._pose.left_palm
		var offset: Vector3 = actor._pose._right_palm_offset if right else actor._pose._left_palm_offset
		var target: Marker3D = palm if palm else actor._pose.right_wrist if right else actor._pose.left_wrist
		var contact: Vector3 = sk.global_transform * sk.get_bone_global_pose(bone) * (offset if palm else Vector3.ZERO)
		gaps.append(contact.distance_to(target.global_position))
	grip_errors[actor.team_id()] = gaps
