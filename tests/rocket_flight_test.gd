extends SceneTree
const Balance := preload("res://game/combat/combat_balance.gd")
const Trail := preload("res://game/combat/rocket_trail.gd")
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
	var grenades = arena.get_node("Grenades")
	grenades.set_physics_process(false)
	grenades.net_launch(47, "rocket", Vector3(0, 30, 0), Vector3.FORWARD * float(Balance.RPG.speed_m_s), float(Balance.RPG.fuse_s), 1)
	var flight = grenades._flights[47]
	var initial_basis: Basis = flight.model.basis
	var maximum_pitch := 0.0
	var maximum_roll := 0.0
	for frame in 120:
		grenades._step(flight, 1.0 / 60.0, root.get_world_3d().direct_space_state, false)
		var rotation: Vector3 = (Basis.looking_at(flight.velocity.normalized()).inverse() * flight.model.basis).get_euler()
		maximum_pitch = maxf(maximum_pitch, absf(rotation.x))
		maximum_roll = maxf(maximum_roll, absf(rotation.z))
	check(absf(flight.at.y - 24.0) < .01, "Rocket drops 6 m over 170 m of travel: shallow long-range ballistic arc")
	check(absf(flight.at.x) > .001 and absf(flight.at.x) < .1, "Flight has bounded, deterministic lateral instability")
	check(not flight.model.basis.is_equal_approx(initial_basis), "Projectile pitch and roll change during flight")
	check(maximum_pitch > deg_to_rad(.5) and maximum_pitch < deg_to_rad(1.6) and maximum_roll > deg_to_rad(45.0), "Pitch varies within 1.5 degrees while the rocket rolls about its flight axis")
	check((-flight.model.basis.z).dot(flight.velocity.normalized()) > .998, "Wobble remains close to the actual velocity direction")
	check(flight.trail.length_m() <= 2.0001 and flight.trail.points.size() < 64, "Fast rocket retains at most 2 m of sampled exhaust path")
	var trail := Trail.new()
	arena.add_child(trail)
	trail.advance(Vector3.ZERO)
	trail.advance(Vector3(1.5, 0, 0))
	trail.advance(Vector3(1.5, 1.5, 0))
	check(absf(trail.length_m() - 2.0) < .0001 and trail.points.front().distance_to(Vector3(1, 0, 0)) < .0001, "Tail is clipped along a curved path, not along its chord")
	var camera := Camera3D.new()
	arena.add_child(camera)
	camera.position = Vector3(2, 2, 4)
	camera.make_current()
	trail._process(0.0)
	var colors: PackedColorArray = trail.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check(colors[0].a > .99 and colors[colors.size() - 1].a < .0001, "Flame opacity fades to zero at the 2 m tail")
	var exhaust: Node = flight.trail
	grenades.net_detonate(47, "rocket", flight.at)
	await process_frame
	check(not is_instance_valid(exhaust), "Impact removes the flame trail with the projectile")
	arena.queue_free()
	await process_frame
	print("Rocket flight failures: ", failures)
	quit(1 if failures else 0)
