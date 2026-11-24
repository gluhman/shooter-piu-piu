extends SceneTree
## Thin, root-aligned blade meshes; native LODs retain the same plant density.
const DEST := "res://game/maps/foliage/"

func _initialize() -> void:
	var material := ShaderMaterial.new()
	material.shader = load(DEST + "dense_grass.gdshader")
	ResourceSaver.save(material, DEST + "dense_grass_material.tres")
	material = load(DEST + "dense_grass_material.tres")
	for spec: Array in [["short", 0.20, 32], ["tall", 0.70, 13]]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 91231 + int(spec[2])
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var distant := SurfaceTool.new()
		distant.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sections := 2 if spec[0]=="short" else 3
		for blade in int(spec[2]):
			var angle := rng.randf_range(0, TAU)
			var across := Vector3(cos(angle), 0, sin(angle))
			var forward := Vector3(-across.z, 0, across.x)
			var radius := sqrt(rng.randf()) * 0.25
			var root := Vector3(cos(angle * 2.7), 0, sin(angle * 2.7)) * radius
			var height: float = spec[1] * (1.0 if blade == 0 else rng.randf_range(0.78, 0.98))
			var width := rng.randf_range(0.007, 0.014)
			var rows: Array[Vector3] = []
			for level in sections+1:
				var t := float(level) / sections
				var center := root + Vector3.UP * height * t + forward * height * t * t * 0.34
				var half_width := width * 0.5 * pow(1.0 - t, 0.65)
				rows.append(center - across * half_width)
				rows.append(center + across * half_width)
			for section in sections:
				var a := section * 2
				var triangles: Array = [[a, a + 2, a + 1]] if section == sections-1 else [[a, a + 2, a + 1], [a + 1, a + 2, a + 3]]
				for triangle: Array in triangles:
					for index: int in triangle:
						var normal := (-forward + Vector3.UP * 0.25).normalized()
						var uv := Vector2(index % 2, float(index / 2) / sections)
						var tint := Color.WHITE
						tool.set_normal(normal)
						tool.set_uv(uv)
						tool.set_color(tint)
						tool.add_vertex(rows[index])
			# Distant blades keep the same roots and tips, with a single triangle.
			for index in [0,sections*2,1]:
				distant.set_normal((-forward+Vector3.UP*0.25).normalized())
				distant.set_uv(Vector2(index%2,float(index/2)/sections))
				distant.set_color(Color.WHITE)
				distant.add_vertex(rows[index])
		tool.set_material(material)
		tool.index()
		var mesh := tool.commit()
		mesh.resource_name = "Dense tapered grass " + str(spec[0])
		var stem := DEST + "dense_grass_" + str(spec[0])
		ResourceSaver.save(mesh, stem + ".res")
		var object := MeshInstance3D.new()
		object.name = "DenseGrass" + str(spec[0]).capitalize()+"_LOD0"
		object.mesh = load(stem + ".res")
		object.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if spec[0]=="short":
			distant.set_material(material)
			distant.index()
			var distant_mesh := distant.commit()
			distant_mesh.resource_name = "Dense tapered grass short LOD1"
			ResourceSaver.save(distant_mesh,stem+"_lod1.res")
			var low := MeshInstance3D.new()
			low.name = "DenseGrassShort_LOD1"
			low.mesh = load(stem+"_lod1.res")
			low.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			object.add_child(low)
			low.owner = object
			object.visibility_range_end = 32.0
			low.visibility_range_begin = 32.0
			low.visibility_range_end = 95.0
		var scene_root := Node3D.new()
		scene_root.name = "DenseGrass"+str(spec[0]).capitalize()
		scene_root.add_child(object)
		object.owner = scene_root
		if spec[0]=="short":
			var low := object.get_child(0)
			low.owner = null
			object.remove_child(low)
			scene_root.add_child(low)
			low.owner = scene_root
		var scene := PackedScene.new()
		scene.pack(scene_root)
		ResourceSaver.save(scene, stem + ".tscn")
		scene_root.free()
		var brush := Terrain3DMeshAsset.new()
		brush.name = "Dense grass " + str(spec[0])
		brush.id = 0 if spec[0] == "short" else 1
		brush.scene_file = load(stem + ".tscn")
		brush.density = 12.0
		brush.cast_shadows = RenderingServer.SHADOW_CASTING_SETTING_OFF
		brush.last_lod = 1 if spec[0]=="short" else 0
		brush.last_shadow_lod = 0
		brush.lod0_range = 32.0 if spec[0]=="short" else 95.0
		if spec[0]=="short":brush.set_lod_range(1,95.0)
		ResourceSaver.save(brush, stem + ".tres")
		print("Prepared ", stem, " ", mesh.get_aabb())
	quit()
