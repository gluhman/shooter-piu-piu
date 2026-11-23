extends SceneTree
## Own tapered blade geometry, following the linked tutorial's mesh/UV method.
const DEST := "res://game/maps/foliage/"

func _initialize() -> void:
	var material := ShaderMaterial.new()
	material.shader = load(DEST + "dense_grass.gdshader")
	ResourceSaver.save(material, DEST + "dense_grass_material.tres")
	material = load(DEST + "dense_grass_material.tres")
	for spec: Array in [["short", 0.20, 36], ["tall", 0.70, 13]]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 91231 + int(spec[2])
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for blade in int(spec[2]):
			var angle := rng.randf_range(0, TAU)
			var across := Vector3(cos(angle), 0, sin(angle))
			var forward := Vector3(-across.z, 0, across.x)
			var radius := sqrt(rng.randf()) * 0.25
			var root := Vector3(cos(angle * 2.7), 0, sin(angle * 2.7)) * radius
			var height: float = spec[1] * (1.0 if blade == 0 else rng.randf_range(0.78, 0.98))
			var width := rng.randf_range(0.007, 0.014)
			var rows: Array[Vector3] = []
			for level in 4:
				var t := float(level) / 3.0
				var center := root + Vector3.UP * height * t + forward * height * t * t * 0.34
				var half_width := width * 0.5 * pow(1.0 - t, 0.65)
				rows.append(center - across * half_width)
				rows.append(center + across * half_width)
			for section in 3:
				var a := section * 2
				var triangles: Array = [[a, a + 2, a + 1]] if section == 2 else [[a, a + 2, a + 1], [a + 1, a + 2, a + 3]]
				for triangle: Array in triangles:
					for index: int in triangle:
						tool.set_normal((-forward + Vector3.UP * 0.25).normalized())
						tool.set_uv(Vector2(index % 2, float(index / 2) / 3.0))
						tool.set_color(Color.WHITE)
						tool.add_vertex(rows[index])
		tool.set_material(material)
		tool.index()
		var mesh := tool.commit()
		mesh.resource_name = "Dense tapered grass " + str(spec[0])
		var stem := DEST + "dense_grass_" + str(spec[0])
		ResourceSaver.save(mesh, stem + ".res")
		var object := MeshInstance3D.new()
		object.name = "DenseGrass" + str(spec[0]).capitalize()
		object.mesh = load(stem + ".res")
		object.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var scene := PackedScene.new()
		scene.pack(object)
		ResourceSaver.save(scene, stem + ".tscn")
		object.free()
		var brush := Terrain3DMeshAsset.new()
		brush.name = "Dense grass " + str(spec[0])
		brush.id = 0 if spec[0] == "short" else 1
		brush.scene_file = load(stem + ".tscn")
		brush.density = 12.0
		brush.cast_shadows = RenderingServer.SHADOW_CASTING_SETTING_OFF
		brush.last_lod = 0
		brush.last_shadow_lod = 0
		brush.lod0_range = 95.0
		ResourceSaver.save(brush, stem + ".tres")
		print("Prepared ", stem, " ", mesh.get_aabb())
	quit()
