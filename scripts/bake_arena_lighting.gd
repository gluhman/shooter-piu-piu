extends SceneTree
## Run in the graphical Forward+ renderer from the project directory:
## godot --path . --script res://scripts/bake_arena_lighting.gd

const MAP := preload("res://game/maps/map_builder.gd")
const LIGHTING_DIR := "res://game/maps/lighting/"


func _initialize() -> void:
	_bake.call_deferred()


func _bake() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		printerr("Baking arena lighting requires a graphical Forward+ renderer.")
		quit(1)
		return

	var office := MAP.new()
	root.add_child(office)
	await office.preload_textures(MAP.OFFICE_ID)
	office.build(MAP.OFFICE_ID, 0, 20.0)
	var office_probe := VoxelGI.new()
	office_probe.position.y = 1.45
	office_probe.size = Vector3(21, 4.8, 17)
	office_probe.subdiv = VoxelGI.SUBDIV_64
	office_probe.camera_attributes = load(LIGHTING_DIR + "office_exposure.tres")
	office.add_child(office_probe)
	var office_saved := _save_probe(office_probe, office, "office_bounce.res", 0.82)
	office.queue_free()
	await process_frame

	var breakwater := (load("res://game/maps/breakwater/breakwater_arena.tscn") as PackedScene).instantiate()
	root.add_child(breakwater)
	breakwater.apply_layout(2)
	var hall_probe := breakwater.get_node("HallBounce") as VoxelGI
	var hall_saved := _save_probe(hall_probe, breakwater, "turbine_hall_bounce.res", 0.72)
	breakwater.queue_free()
	await process_frame
	quit(0 if office_saved and hall_saved else 1)


func _save_probe(probe: VoxelGI, geometry: Node3D, file: String, energy: float) -> bool:
	probe.bake(geometry)
	if not probe.data:
		printerr("No lighting data produced for ", file)
		return false
	probe.data.energy = energy
	var result := ResourceSaver.save(probe.data, LIGHTING_DIR + file, ResourceSaver.FLAG_COMPRESS)
	print("Baked ", file, " ", probe.data.get_octree_size(), " result=", result)
	return result == OK
