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
var finger_errors: Dictionary = {}
var forearm_directions: Dictionary = {}
var wrist_angles: Dictionary = {}
var arm_geometry: Dictionary = {}
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
	preview_local = local
	local.position = Vector3(3, 0, 0)
	local.hide();local.control_enabled=false;local.set_physics_process(false);local.set_process(false)
	for bot in get_tree().get_nodes_in_group("bot"):
		actors.append(bot)
		bot._pose.use_godotik_arms = "--analytic" not in OS.get_cmdline_user_args()
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
var weapons: Array = []
var last_weapon := -1
var preview_local: Node
var preview_phase := 0
var poses := false
var preview_phases: Array[int] = [0]
var preview_step := 0
var phase_elapsed := 0.0
var phase_frames := 0
var capture_pending := false
var smoke_emitted: Array[int] = []
func _process(delta: float) -> void:
	if weapons.is_empty():
		weapons = actors[0].gun.WEAPONS.keys()
		weapons.erase("knife")
		var args := OS.get_cmdline_user_args()
		if "--poses" in args:
			preview_phases = [0, 1, 2, 3, 4, 5, 6]
		elif "--contacts" in args:
			preview_phases = [0, 1, 6]
		elif "--first-person" in args:
			preview_phases = [6]
		elif "--ads" in args:
			preview_phases = [2]
		poses = preview_phases != [0]
		if "--weapon" in args:
			weapons = [args[args.find("--weapon") + 1]]
	clock += delta
	phase_elapsed += delta
	phase_frames += 1
	var duration := 0.9 if poses else 1.5
	if phase_elapsed >= duration and phase_frames >= 6 and captured.has(preview_step):
		preview_step += 1
		phase_elapsed = 0.0
		phase_frames = 0
	var step := preview_step
	var index := int(step / preview_phases.size())
	preview_phase = preview_phases[step % preview_phases.size()]
	if index >= weapons.size():
		var file := FileAccess.open("/tmp/weapon-preview-forearms.json" if "--weapon" in OS.get_cmdline_user_args() else "/tmp/weapon-forearms.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(forearm_directions))
		file = FileAccess.open("/tmp/weapon-preview-arm-geometry.json" if "--weapon" in OS.get_cmdline_user_args() else "/tmp/weapon-arm-geometry.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(arm_geometry))
		get_tree().quit()
		return
	if step != last_weapon:
		last_weapon = step
		for actor in actors:
			actor.gun.equip(weapons[index])
			actor.crouched = preview_phase == 3
			if preview_phase == 5:
				actor.gun._mag = 0
				actor.gun.reload_bot()
		camera.make_current()
		preview_local.hide()
		if preview_phase == 6:
			preview_local.show()
			preview_local._avatar.show()
			preview_local.gun.equip(weapons[index])
			var first_person_exposure := CameraAttributesPractical.new()
			first_person_exposure.exposure_multiplier = 20.0
			preview_local.get_node("Camera3D").attributes = first_person_exposure
			preview_local.control_enabled = true
			preview_local.get_node("Camera3D").make_current()
		camera.position = Vector3(0.15, 1.55, 1.35)
		if preview_phase == 1:
			camera.position = Vector3(-1.4, 1.45, -0.5)
		camera.look_at(Vector3(-0.62, 1.35, 0.2))
	for actor in actors:
		actor._update_operator(delta)
		if preview_phase == 2:
			actor.gun._aim_amount = 1.0
			actor.set_aim_posture(1.0)
			actor.gun._apply_view(0.0)
		elif preview_phase == 4:
			actor.gun._kick_pos.z = 0.08
			actor.gun._kick_rot = 4.0
			actor.gun._apply_view(0.0)
		elif preview_phase == 5:
			actor.gun._reload_left = actor.gun._reload_time * 0.55
			actor.gun._apply_view(0.0)
	if preview_phase == 6:
		preview_local._update_operator(delta)
		# Hidden map colliders can sit centimetres from this studio camera. Review
		# the normal distant-target hold, rather than converging the gun into them.
		preview_local.gun._apply_view(0.0, false)
	if "--smoke" in OS.get_cmdline_user_args() and phase_elapsed > duration * 0.20 and not smoke_emitted.has(step):
		smoke_emitted.append(step)
		var actor: Node = actors[0]
		actor.get_parent().get_node("Ballistics").muzzle_effect(weapons[index], actor.gun._muzzle.global_transform, Vector3.ZERO, false)
	label.text = str(weapons[index])
	if phase_elapsed > duration * 0.40 and phase_frames >= 3 and not captured.has(step) and not capture_pending:
		capture_pending = true
		_capture_weapon.call_deferred(weapons[index] + ("-" + str(preview_phase) if poses else ""), step)

func _capture_weapon(id: String, step: int) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/weapon-contact-" + id + ".png")
	if preview_phase == 6:
		var eye: Camera3D = get_viewport().get_camera_3d()
		print("FIRST_PERSON ", eye.get_path(), " fov=", eye.fov, " near=", eye.near, " palm_camera=", eye.to_local(preview_local.gun._left_palm.global_position), " screen=", eye.unproject_position(preview_local.gun._left_palm.global_position), " viewport=", get_viewport().get_visible_rect().size)
	print("CONTACT ", id, " palms ", grip_errors, " wrist_degrees ", wrist_angles)
	captured.append(step)
	capture_pending = false

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
	var errors: Array = []
	var directions := {}
	var geometry := {}
	for side in ["right", "left"]:
		var wrist: Marker3D = actor.gun._right_wrist if side == "right" else actor.gun._left_wrist
		var hand: int = sk.find_bone("hand_" + ("r" if side == "right" else "l"))
		var forearm: int = sk.find_bone("lowerarm_" + ("r" if side == "right" else "l"))
		var upper: int = sk.find_bone("upperarm_" + ("r" if side == "right" else "l"))
		var shoulder_world := sk.to_global(sk.get_bone_global_pose(upper).origin)
		var elbow_world := sk.to_global(sk.get_bone_global_pose(forearm).origin)
		var wrist_world := sk.to_global(sk.get_bone_global_pose(hand).origin)
		geometry[side] = {"shoulder": actor.gun.Contacts.array(actor.gun._view.to_local(shoulder_world)), "upper": shoulder_world.distance_to(elbow_world), "lower": elbow_world.distance_to(wrist_world)}
		var direction: Vector3 = actor.gun._view.global_basis.inverse() * sk.global_basis * (sk.get_bone_global_pose(hand).origin - sk.get_bone_global_pose(forearm).origin)
		directions[side] = actor.gun.Contacts.array(direction.normalized())
		var hand_axis: Vector3 = actor.gun._view.global_basis.inverse() * wrist.global_basis.y
		wrist_angles[side] = snappedf(rad_to_deg(hand_axis.normalized().angle_to(direction.normalized())), 0.1)
		for digit in ["thumb", "index", "middle", "ring", "pinky"]:
			var goal := wrist.get_node_or_null("Contact_" + digit) as Marker3D
			if not goal: continue
			var leaf: int = sk.find_bone(digit + "_04_leaf_" + ("r" if side == "right" else "l"))
			var tip := sk.to_global(sk.get_bone_global_pose(leaf).origin)
			errors.append(snappedf(tip.distance_to(goal.global_position) * 1000.0, 0.1))
	finger_errors[actor.team_id()] = errors
	forearm_directions[actor.gun._weapon_id] = directions
	arm_geometry[actor.gun._weapon_id] = geometry
