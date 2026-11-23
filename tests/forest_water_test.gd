extends SceneTree
## Rendered check of the clipped Forest surface, animation and footstep wakes.
const FOREST := preload("res://game/maps/forest_ridge/forest_ridge_layout.gd")
var failed := false

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	if not value:failed = true
	print("PASS " if value else "FAIL ", label)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run the Forest water test with a rendering display")
		quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	await arena.start_solo(0, 1, 0, 11, Vector2i.ZERO, 2)
	root.size = Vector2i(1600, 960)
	root.always_on_top = true
	root.grab_focus()
	arena.get_node("HUD").hide()
	var water := arena.get_node("Map").find_child("DitchPools", true, false) as MeshInstance3D
	check(water != null and water.has_method("add_ripple"), "Forest has a dynamic water surface")
	if water == null:
		quit(1)
		return
	water.set_process(false)
	var vertices := water.mesh.get_faces()
	var wet := Vector3.ZERO
	var found := false
	for i in range(0, vertices.size(), 3):
		var point: Vector3 = (vertices[i] + vertices[i+1] + vertices[i+2]) / 3.0
		if absf(point.z) < 18.0 and absf(point.z) > 8.0 \
				and FOREST.WATER_LEVEL - float(water.heightfield.sample_world(point.x, point.z)) > 0.25:
			wet = point
			found = true
			break
	check(found, "A shallow stream interior exists for interaction")
	for side: float in [-1.0, 1.0]:
		var z := 2.1 if side > 0 else -2.4
		var x := side * (18.0 + 1.8 * sin(z * 0.19) + 0.8 * sin(z * 0.41))
		check(not water.add_ripple(Vector3(x, FOREST.WATER_LEVEL, z)), "Dry crossing rejects water ripples")
	var actor := Node3D.new()
	root.add_child(actor)
	actor.add_to_group("player")
	actor.position = wet - Vector3.UP * 0.10
	var before: int = water._next_ripple
	water._process(0.2)
	check(water._next_ripple != before, "Entering the stream produces a footstep wake")
	before = water._next_ripple
	water._process(0.2)
	check(water._next_ripple == before, "Standing still does not emit continuous footstep rings")
	actor.position.z += 0.55
	water._process(0.2)
	check(water._next_ripple != before, "Walking through shallow water produces another wake")
	check(water._ripples.size() == 8, "Water uses a bounded GPU ripple pool")
	var camera := Camera3D.new()
	arena.add_child(camera)
	camera.fov = 65.0
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = 1
	var space := water.get_world_3d().direct_space_state
	for offset: Vector3 in [Vector3(0.5, 1.0, 2.5), Vector3(-0.5, 1.0, 2.5), Vector3(0, 2.0, 3.0)]:
		query.from = wet + Vector3.UP * 0.10
		query.to = wet + offset
		if space.intersect_ray(query).is_empty():
			camera.position = query.to
			break
	camera.look_at(wet)
	camera.make_current()
	var material := water.material_override as ShaderMaterial
	material.set_shader_parameter(&"water_time", 0.65)
	await process_frame
	await RenderingServer.frame_post_draw
	var image_a := root.get_texture().get_image()
	material.set_shader_parameter(&"water_time", 1.45)
	await process_frame
	await RenderingServer.frame_post_draw
	var image_b := root.get_texture().get_image()
	var scale := Vector2(image_a.get_size()) / root.get_visible_rect().size
	var center := Vector2i(camera.unproject_position(wet) * scale)
	var changed := 0
	for y in range(center.y - 20, center.y + 20):
		for x in range(center.x - 20, center.x + 20):
			var a := image_a.get_pixel(x,y)
			var b := image_b.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > 0.003:changed += 1
	check(changed > 20, "Rendered water moves between simulation times (%d changed pixels)" % changed)
	if "--screenshots" in OS.get_cmdline_user_args():
		image_a.save_png("/tmp/forest-dynamic-water-a.png")
		image_b.save_png("/tmp/forest-dynamic-water-b.png")
	actor.queue_free()
	arena.queue_free()
	await process_frame
	print("FAIL Forest dynamic water" if failed else "PASS Forest dynamic water")
	quit(int(failed))
