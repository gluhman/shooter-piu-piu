extends RefCounted
## Refinery-only PBR finish; keeps the existing perforation shader contract.
const SHADER:=preload("weathered_surface.gdshader")
static func finish(base: StandardMaterial3D, weathering: float, rust: float) -> ShaderMaterial:
	var material:=ShaderMaterial.new()
	material.shader=SHADER
	material.set_meta(&"perforation_ready",true)
	# VoxelGI cannot bake custom shaders; use a matte mean-color surrogate only
	# while baking occupancy/albedo, then restore the runtime finish.
	var bake:=StandardMaterial3D.new()
	bake.albedo_color=base.albedo_color*Color(0.85,0.85,0.85)
	bake.roughness=0.9
	material.set_meta(&"voxel_bake_material",bake)
	for entry: Array in [["color_texture",base.albedo_texture],["normal_texture",base.normal_texture],["roughness_texture",base.roughness_texture],["tint",base.albedo_color],["texture_scale",base.uv1_scale],["normal_strength",0.48],["roughness_factor",1.0],["metalness",base.metallic],["weathering",weathering],["rust_amount",rust],["painted",base.metallic>0.0]]:
		if entry[1]!=null:material.set_shader_parameter(entry[0],entry[1])
	return material
