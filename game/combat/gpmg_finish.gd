extends RefCounted
## 4K CC0 Poly Haven finishes, mapped in model space to avoid UV stretching.
const ROOT := "res://assets/detailed_weapons/gpmg_pbr/"
const STUDIO := preload("res://assets/operator/textures/hd/studio_small_09_4k.hdr")
const REFLECTION := preload("res://game/combat/weapon_reflections.gdshader")
static var _materials: Dictionary[String, StandardMaterial3D] = {}
static var _textures: Dictionary[String, Texture2D] = {}

static func texture(name: String) -> Texture2D:
	if not _textures.has(name):
		_textures[name] = load(ROOT + name + "_4k.jpg") as Texture2D
	return _textures[name]

static func apply(model: Node3D, studio_reflections: bool) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if not source: continue
			var key := source.resource_name + str(studio_reflections)
			if not _materials.has(key):
				var material := source.duplicate() as StandardMaterial3D
				var wood := source.resource_name.contains("wood")
				var asset := "dark_wood" if wood else "metal_plate_02"
				material.albedo_texture = texture(asset + "_diff")
				material.normal_enabled = true
				material.normal_texture = texture(asset + "_nor_gl")
				material.normal_scale = .35 if wood else .25
				material.roughness_texture = texture(asset + "_rough")
				material.roughness = .85 if wood else .70
				material.metallic = 0.0 if wood else 1.0
				if not wood: material.metallic_texture = texture(asset + "_metal")
				material.uv1_triplanar = true
				material.uv1_scale = Vector3(4,1,1) if wood else Vector3(3,3,3)
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				if wood: material.albedo_color = Color(.65,.48,.32)
				elif source.resource_name.contains("olive"): material.albedo_color = Color(.28,.36,.16)
				elif source.resource_name.contains("stell"): material.albedo_color = Color(.72,.78,.85)
				else: material.albedo_color = Color(.42,.47,.53)
				if studio_reflections and not wood:
					var reflection := ShaderMaterial.new()
					reflection.shader = REFLECTION
					reflection.set_shader_parameter(&"panorama", STUDIO)
					reflection.set_shader_parameter(&"reflection_strength", .09)
					reflection.set_shader_parameter(&"surface_roughness", .50)
					material.next_pass = reflection
				_materials[key] = material
			mesh.set_surface_override_material(surface, _materials[key])
