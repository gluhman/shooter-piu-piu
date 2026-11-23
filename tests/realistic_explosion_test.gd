extends SceneTree
var effect_scene: PackedScene
var failed := false
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	effect_scene = load("res://game/combat/realistic_explosion.tscn")
	AudioServer.set_bus_mute(0, true)
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await arena.start_solo(0, 1, 0, 7, Vector2i.ZERO, 0)
	root.size = Vector2i(1600, 960)
	root.always_on_top = true
	root.grab_focus()
	arena.get_node("HUD").hide()
	var map := arena.get_node("Map")
	var at: Vector3 = map.initial_spawn(0) + Vector3(0, 0, -5)
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 5, at - Vector3.UP * 5, 1)
	var hit: Dictionary = map.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():at = hit.position + Vector3.UP * 0.025
	var camera := Camera3D.new()
	arena.add_child(camera)
	camera.attributes = arena.combatant(1).get_node("Camera3D").attributes if arena.combatant(1).has_node("Camera3D") else null
	arena.combatant(1).hide()
	camera.position = at + Vector3(3.5, 2.0, 7)
	camera.look_at(at + Vector3.UP * 1.2)
	camera.make_current()
	var ballistics := arena.get_node("Ballistics")
	var effects: Node3D = ballistics._effects
	ballistics.grenade_effect(at, false, 5.0, false)
	var fireball: Node3D = effects.get_children().filter(func(n: Node) -> bool: return n.scene_file_path == effect_scene.resource_path).back()
	fireball.set_process(false)
	_check(fireball.get_node("FireSmoke").material_override.get_shader_parameter("flow_texture") != null, "Explosion uses the paired CC0 motion-vector atlas")
	var ground_support: PyroluxExplosion3D
	for node in effects.get_children():
		if node is PyroluxExplosion3D:ground_support = node
	_check(ground_support != null and ground_support._dust_mat != null, "Ground blast retains its dust skirt")
	_check(float(ground_support._spark_mat.get_shader_parameter("width")) < 0.012 and float(ground_support._spark_mat.get_shader_parameter("stretch")) < 0.012, "Flying fragments have fine, short streaks")
	var first: Image
	for time: float in [0.14, 0.55, 1.7]:
		fireball.elapsed = time
		fireball._process(0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		if first == null:first = picture
		if "--screenshots" in OS.get_cmdline_user_args():picture.save_png("/tmp/realistic-explosion-%03d.png" % roundi(time * 100))
		if time == 1.7:
			var changes := 0
			for y in range(250, 650, 4):
				for x in range(500, 1100, 4):
					if Vector3(first.get_pixel(x, y).r, first.get_pixel(x, y).g, first.get_pixel(x, y).b).distance_to(Vector3(picture.get_pixel(x, y).r, picture.get_pixel(x, y).g, picture.get_pixel(x, y).b)) > 0.015:changes += 1
			_check(changes > 100, "Rendered blast changes from fire into smoke (%d samples)" % changes)
	var material: ShaderMaterial = fireball.get_node("FireSmoke").material_override
	var other := effect_scene.instantiate()
	other.autoplay = false
	effects.add_child(other)
	_check(other.get_node("FireSmoke").material_override != material, "Simultaneous blasts retain independent animation ages")
	other.queue_free()
	fireball.elapsed = 4.5
	fireball._process(0.0)
	var rising: MeshInstance3D = fireball.get_node("FireSmoke")
	_check(rising.position.y > 3.0 and is_equal_approx(float(material.get_shader_parameter("opacity")), 1.0), "Grenade smoke rises over three metres before fading")
	_check(is_zero_approx(float(material.get_shader_parameter("flame_fade"))), "Rising smoke has cooled beyond the initial fireball")
	camera.look_at(fireball.global_position + Vector3.UP * rising.position.y)
	await process_frame
	await RenderingServer.frame_post_draw
	if "--screenshots" in OS.get_cmdline_user_args():root.get_texture().get_image().save_png("/tmp/rising-grenade-smoke.png")
	fireball.elapsed = 6.4
	fireball._process(0.0)
	_check(rising.position.y > 5.0 and float(material.get_shader_parameter("opacity")) < 0.5, "Smoke fades only after rising higher into the sky")
	fireball._process(fireball.duration)
	await process_frame
	_check(not is_instance_valid(fireball), "Fireball cleans up after its one-shot animation")
	effects.clear()
	await process_frame
	ballistics.grenade_effect(at + Vector3.UP * 3.5, false, 5.0, true)
	var support: PyroluxExplosion3D
	for n in effects.get_children():
		if n is PyroluxExplosion3D:support = n
	_check(support != null and support.style == PyroluxExplosion3D.Style.AIR and support._dust_mat == null, "Airborne launcher blast has no ground dust skirt")
	_check(support.fireball == 0 and support.smoke == 0 and not support.shockwave, "Procedural support does not duplicate simulated fire and smoke")
	var aerial: Node3D = effects.get_children().filter(func(n: Node) -> bool: return n.scene_file_path == effect_scene.resource_path).back()
	aerial.set_process(false)
	aerial.elapsed = 0.50
	aerial._process(0.0)
	camera.look_at(at + Vector3.UP * 3.5)
	await process_frame
	await RenderingServer.frame_post_draw
	if "--screenshots" in OS.get_cmdline_user_args():root.get_texture().get_image().save_png("/tmp/realistic-explosion-air.png")
	aerial.elapsed = 4.5
	aerial._process(0.0)
	_check(aerial.get_node("FireSmoke").position.y > 3.0 and is_equal_approx(float(aerial.get_node("FireSmoke").material_override.get_shader_parameter("opacity")), 1.0), "RPG blast smoke also rises before fading")
	camera.look_at(aerial.global_position + Vector3.UP * aerial.get_node("FireSmoke").position.y)
	await process_frame
	await RenderingServer.frame_post_draw
	if "--screenshots" in OS.get_cmdline_user_args():root.get_texture().get_image().save_png("/tmp/rising-rpg-smoke.png")
	effects.clear()
	root.get_node("GameSettings").effects_detail = 0
	var low := effect_scene.instantiate()
	effects.add_child(low)
	_check(not low.get_node("Heat").visible, "Low effects detail skips heat refraction")
	low.queue_free()
	arena.queue_free()
	await process_frame
	print("FAIL realistic explosions" if failed else "PASS realistic explosions")
	quit(int(failed))
func _check(ok: bool, message: String) -> void:
	failed = failed or not ok
	print(("PASS " if ok else "FAIL ") + message)
