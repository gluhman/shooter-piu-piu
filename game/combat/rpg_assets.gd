extends RefCounted
## Downloaded launcher geometry with original 4K Poly Haven finishes.
const ROOT := "res://assets/rpg/"
const EXHAUST_OFFSET := Vector3(0.0, 0.0, 0.10)
static var materials: Dictionary = {}
static func make_model(projectile: bool = false) -> Node3D:
	var scene := load(ROOT + ("rocket.glb" if projectile else "rpg.glb")) as PackedScene
	var model := scene.instantiate() as Node3D
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface)
			var wood := source != null and source.resource_name == "Wood"
			mesh.set_surface_override_material(surface, _material(wood))
	return model
static func _material(wood: bool) -> StandardMaterial3D:
	var key := "wood" if wood else "metal"
	if materials.has(key): return materials[key]
	var name := "american_walnut_veneer" if wood else "metal_plate_02"
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(ROOT + "textures/" + name + "_diff_4k.jpg")
	material.normal_enabled = true
	material.normal_texture = load(ROOT + "textures/" + name + "_nor_gl_4k.jpg")
	material.normal_scale = 0.45
	var packed := load(ROOT + "textures/" + name + "_arm_4k.jpg") as Texture2D
	material.ao_enabled = true
	material.ao_texture = packed
	material.roughness_texture = packed
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	material.metallic_texture = packed
	material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	material.metallic = 0.0 if wood else 0.72
	material.roughness = 0.7
	material.albedo_color = Color(0.58, 0.42, 0.27) if wood else Color(0.33, 0.39, 0.26)
	material.uv1_triplanar = true
	material.uv1_world_triplanar = false
	material.uv1_scale = Vector3.ONE * (7.0 if wood else 4.0)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	materials[key] = material
	return material
