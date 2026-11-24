extends SceneTree
## Godot --path . --script res://scripts/bake_refinery_lighting.gd -- --bake-refinery
const VISUALS:=preload("res://game/maps/refinery/refinery_visuals.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Use graphical Forward+ to bake VoxelGI")
		quit(1)
		return
	var arena: Node3D=load("res://game/match/arena.tscn").instantiate()
	root.add_child(arena)
	await arena.start_solo(0,1,0,12,Vector2i.ZERO,2)
	arena.get_node("HUD").hide()
	var geometry: Node3D=arena.get_node("Map")
	var bake_root:=Node3D.new()
	root.add_child(bake_root)
	for mesh: MeshInstance3D in geometry.find_children("*","MeshInstance3D",true,false):
		if mesh.gi_mode==GeometryInstance3D.GI_MODE_DISABLED:continue
		var clone:=MeshInstance3D.new()
		clone.mesh=surrogate(mesh.mesh,mesh.material_override)
		clone.transform=mesh.global_transform
		bake_root.add_child(clone)
		mesh.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	for node: MultiMeshInstance3D in geometry.find_children("*","MultiMeshInstance3D",true,false):
		if node.gi_mode==GeometryInstance3D.GI_MODE_DISABLED:continue
		var mesh:=surrogate(node.multimesh.mesh,node.material_override)
		for i in node.multimesh.instance_count:
			var clone:=MeshInstance3D.new()
			clone.mesh=mesh
			clone.transform=node.global_transform*node.multimesh.get_instance_transform(i)
			bake_root.add_child(clone)
		node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VISUALS.LIGHTING))
	var failed:=false
	for spec: Dictionary in VISUALS.PROBES:
		var probe:=VISUALS.make_probe(spec)
		bake_root.add_child(probe)
		probe.bake(bake_root)
		if probe.data==null:
			failed=true
			continue
		probe.data.energy=0.75
		probe.data.interior=spec.interior
		probe.data.propagation=0.48
		probe.data.use_two_bounces=true
		probe.data.normal_bias=1.2
		var error:=ResourceSaver.save(probe.data,VISUALS.LIGHTING+spec.file,ResourceSaver.FLAG_COMPRESS)
		print("BAKED ",spec.file," ",probe.data.get_octree_size()," result ",error)
		failed=failed or error!=OK
		probe.queue_free()
		await process_frame
	arena.queue_free()
	bake_root.queue_free()
	await process_frame
	await process_frame
	quit(int(failed))
func surrogate(source: Mesh,override: Material) -> Mesh:
	var mesh: Mesh=source.duplicate()
	for surface in mesh.get_surface_count():
		var material: Material=override if override!=null else mesh.surface_get_material(surface)
		if material is ShaderMaterial and material.has_meta(&"voxel_bake_material"):
			material=material.get_meta(&"voxel_bake_material")
		mesh.surface_set_material(surface,material)
	return mesh
