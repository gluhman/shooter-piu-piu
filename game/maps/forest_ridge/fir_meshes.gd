extends RefCounted


static func build(random: RandomNumberGenerator) -> Array[Mesh]:
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = load("res://game/maps/forest_ridge/art/trees/fir_tree_01_bark_diff_1k.jpg")
	bark.roughness = 0.95
	var needles := StandardMaterial3D.new()
	needles.albedo_texture = load("res://game/maps/forest_ridge/art/trees/fir_needles.png")
	needles.albedo_color = Color("#bbd292")
	needles.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	needles.alpha_scissor_threshold = 0.34
	needles.cull_mode = BaseMaterial3D.CULL_DISABLED
	needles.roughness = 0.91
	var variants: Array[Mesh] = []
	for variant in 3:
		var tree := ArrayMesh.new()
		var trunk := CylinderMesh.new()
		trunk.bottom_radius = 0.033
		trunk.top_radius = 0.004
		trunk.height = 0.98
		trunk.radial_segments = 9
		trunk.rings = 2
		var bole := SurfaceTool.new()
		bole.begin(Mesh.PRIMITIVE_TRIANGLES)
		bole.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3.UP * 0.48))
		bole.set_material(bark)
		bole.commit(tree)
		var crown := SurfaceTool.new()
		crown.begin(Mesh.PRIMITIVE_TRIANGLES)
		crown.set_material(needles)
		for tier in 10:
			var y := 0.19 + float(tier) * 0.076
			for limb in 9:
				var angle := float(limb) * TAU / 9.0 + tier * 1.97 + variant * 0.87 + random.randf_range(-0.28, 0.28)
				var length := lerpf(0.34, 0.075, float(tier) / 9.0) * random.randf_range(0.70, 1.17)
				var axis := Vector3(cos(angle), 0.0, sin(angle))
				var across := Vector3(-axis.z, 0.0, axis.x)
				var origin := Vector3.UP * (y + random.randf_range(-0.023, 0.023))
				_branch_card(crown, origin, axis, across, length, random.randf_range(-0.05, 0.03))
				_branch_card(crown, origin + axis * length * 0.12, axis,
					(across + Vector3.UP * 1.14).normalized(), length * 0.94, 0.055)
		for direction in 4:
			var angle := float(direction) * PI * 0.25
			_branch_card(crown, Vector3.UP * 0.88, Vector3.UP,
				Vector3(cos(angle), 0, sin(angle)), 0.13, 0.0)
		crown.commit(tree)
		variants.append(tree)
	return variants


static func _branch_card(surface: SurfaceTool, origin: Vector3, axis: Vector3, across: Vector3,
		length: float, lift: float) -> void:
	var tip := origin + axis * length + Vector3.UP * lift
	var spread := across * length * 0.51
	var normal := axis.cross(across).normalized()
	if normal.y < 0.0:
		normal = -normal
	for uv: Vector2 in [Vector2(0, 1), Vector2(1, 1), Vector2(0, 0),
			Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]:
		surface.set_normal(normal)
		# Use the broad twig island in the lower middle of the texture atlas.
		surface.set_uv(Vector2(0.296 + uv.x * 0.340, 0.391 + uv.y * 0.386))
		surface.add_vertex(tip.lerp(origin, uv.y) + spread * (uv.x * 2.0 - 1.0))
