extends SceneTree
## Rebuild the Terrain3D brush objects from the existing CC0 source GLB.
const DEST := "res://game/maps/foliage/"

func _initialize() -> void:
	var source := (load("res://assets/arena_props/grass.glb") as PackedScene).instantiate()
	var material := ShaderMaterial.new()
	material.shader = load(DEST + "grass.gdshader")
	material.set_shader_parameter("grass_albedo", load(DEST + "grass_albedo.png"))
	material.set_shader_parameter("grass_normal", load(DEST + "grass_normal.jpg"))
	material.set_shader_parameter("grass_roughness", load(DEST + "grass_roughness.jpg"))
	material.set_shader_parameter("wind_strength", 0.055)
	ResourceSaver.save(material, DEST + "grass_material.tres", ResourceSaver.FLAG_CHANGE_PATH)
	material = load(DEST + "grass_material.tres")
	for spec: Array in [["short", "grass_medium_01_small_b_LOD0", 0.20], ["tall", "grass_medium_01_tall_a_LOD0", 0.70]]:
		var original := source.find_child(spec[1], true, false) as MeshInstance3D
		assert(original != null)
		var bounds := original.mesh.get_aabb()
		var factor: float = spec[2] / bounds.size.y
		var origin := Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z) * factor
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.append_from(original.mesh, 0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * factor), origin))
		tool.set_material(material)
		var mesh := tool.commit()
		mesh.resource_name = "Grass %s, %.2f m" % [spec[0], spec[2]]
		ResourceSaver.save(mesh, DEST + "grass_%s.res" % spec[0], ResourceSaver.FLAG_CHANGE_PATH)
		var object := MeshInstance3D.new()
		object.name = "GrassShort" if spec[0] == "short" else "GrassTall"
		object.mesh = load(DEST + "grass_%s.res" % spec[0])
		object.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var scene := PackedScene.new()
		scene.pack(object)
		ResourceSaver.save(scene, DEST + "grass_%s.tscn" % spec[0])
		object.free()
		print("Prepared %s grass: %s" % [spec[0], mesh.get_aabb()])
	source.free()
	quit()
