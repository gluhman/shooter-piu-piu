extends SceneTree
## Exercises the production launch path and flight integrator against the range ladder.
const Balance := preload("res://game/combat/combat_balance.gd")
const Calibration := preload("res://game/combat/rpg_ballistics.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1

func _run() -> void:
	var arena = load("res://game/match/arena.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	var actor = load("res://game/actors/player.tscn").instantiate()
	actor.name = "2"
	actor.set_multiplayer_authority(2, true)
	actor._net_grounded = true
	actor.position = Vector3(0, 80, 0)
	arena.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.gun.set_process(false)
	actor.equip("rpg")
	root.get_node("Net").active = true  # Remote, grounded fixture removes airborne cone noise.
	var grenades = arena.get_node("Grenades")
	grenades.set_physics_process(false)
	var camera := Transform3D(Basis.IDENTITY, Vector3(0, 80, 0))
	var barrel := Transform3D(Basis.IDENTITY, camera.origin + Vector3(.1, -.2, -.6))
	actor.gun._aim_amount = 1.0
	actor.gun._stats = actor.gun._stats.duplicate(true)
	actor.gun._stats.aim_spread = 0.0
	actor.gun._launch_sighted(barrel, camera, camera.origin + Vector3.FORWARD * 50.0)
	var flight = grenades._flights.values()[0]
	var first_velocity: Vector3 = flight.velocity
	grenades.reset_round()
	actor.gun._launch_sighted(barrel, camera, camera.origin + Vector3.FORWARD * 200.0)
	flight = grenades._flights.values()[0]
	check(first_velocity.is_equal_approx(flight.velocity), "Player RPG bore is fixed regardless of the raycast target distance")
	check(flight.velocity.normalized().is_equal_approx(Calibration.aim_direction(Basis.IDENTITY, 1.0)), "Production ADS launch follows the upper scope cross")
	var origin_offset := barrel.origin - camera.origin
	var reference_drop := [128.0 / 946.0, 233.0 / 946.0, 362.0 / 946.0, 497.0 / 946.0]
	for index in 4:
		var distance := float((index + 1) * 50)
		var time: float = (distance + flight.at.z) / -flight.velocity.z
		while time > 0.000001:
			var delta := minf(time, 1.0 / 120.0)
			grenades._step(flight, delta, root.get_world_3d().direct_space_state, false)
			time -= delta
		var actual: float = -(flight.at.y - camera.origin.y) / distance / (2.0 * tan(deg_to_rad(Calibration.AIM_FOV * .5)))
		var mark := Calibration.sight_offset(distance, Calibration.AIM_FOV, origin_offset)
		check(absf(actual - mark) < .00001, "%d m range mark matches integrated flight" % distance)
		check(absf(mark + Calibration.CROSS_HEIGHT - reference_drop[index]) < .025, "%d m spacing follows the supplied reference" % distance)
	grenades.reset_round()
	actor.gun._aim_amount = 0.0
	actor.gun._stats.spread = 0.0
	actor.gun._launch_sighted(barrel, camera, camera.origin + Vector3.FORWARD * 200.0)
	flight = grenades._flights.values()[0]
	check(absf(flight.velocity.y) < .0001, "Hip fire keeps the centre cross without range compensation")
	grenades.reset_round()
	root.get_node("Net").active = false
	actor.gun._aim_amount = 1.0
	actor.gun._apply_view(0.0, false)
	check(actor.gun._scope_view and not actor.gun._model.visible, "RPG ADS opens scope and hides the physical launcher")
	check(is_equal_approx(actor.get_node("Camera3D").fov, Calibration.AIM_FOV), "RPG ADS uses the calibrated scope FOV")
	actor.gun._aim_amount = 0.0
	actor.gun._apply_view(0.0, false)
	check(not actor.gun._scope_view and actor.gun._model.visible, "Leaving ADS restores the launcher")
	if DisplayServer.get_name() != "headless":
		var eye: Camera3D = actor.get_node("Camera3D")
		eye.global_transform = camera
		eye.fov = Calibration.AIM_FOV
		actor.hide()
		for overlay in arena.find_children("*", "CanvasLayer", true, false): overlay.hide()
		var environment: WorldEnvironment = arena.get_node("WorldEnvironment")
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(.65, .66, .59)
		eye.make_current()
		var layer := CanvasLayer.new()
		root.add_child(layer)
		var reticle := Control.new()
		reticle.set_script(load("res://game/ui/reticle.gd"))
		layer.add_child(reticle)
		reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		reticle.update_pose(1.0, false, false, 0.0, true, eye, "rpg", false, origin_offset)
		await process_frame
		eye.make_current()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/rpg-scope-review.png")
		layer.queue_free()
	root.get_node("Net").active = false
	arena.queue_free()
	await process_frame
	print("RPG scope failures: ", failures)
	quit(1 if failures else 0)
