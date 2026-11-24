extends RefCounted
## Presentation-only refinery detail and bounded baked VoxelGI volumes.
const PATCH:=preload("grime_patch.gdshader")
const LIGHTING:= "res://game/maps/refinery/art/lighting/"
const PROBES := [
	{"name":"NorthBayBounce","file":"north_bay.res","position":Vector3(-23.5,2.5,-10.4),"size":Vector3(12,6,12),"interior":false},
	{"name":"SouthBayBounce","file":"south_bay.res","position":Vector3(-23.5,2.5,10.4),"size":Vector3(12,6,12),"interior":false}]
static func install(root: Node3D) -> void:
	if "--bake-refinery" not in OS.get_cmdline_user_args():
		for spec: Dictionary in PROBES:
			if not ResourceLoader.exists(LIGHTING+spec.file):continue
			var probe:=make_probe(spec)
			probe.data=load(LIGHTING+spec.file)
			root.add_child(probe)
			probe.add_to_group(&"refinery_bounce")
	for side in [-1.0,1.0]:
		var reflection:=ReflectionProbe.new()
		reflection.name="BayReflection"
		reflection.position=Vector3(-23.5,2.4,side*10.4)
		reflection.size=Vector3(12,6,11)
		reflection.origin_offset=Vector3(2,0,0)
		reflection.box_projection=true
		reflection.intensity=0.65
		reflection.max_distance=24
		root.add_child(reflection)
		for x in [-25.0,-21.5]:
			var fixture:=MeshInstance3D.new()
			var mesh:=BoxMesh.new()
			mesh.size=Vector3(1.1,0.06,0.14)
			var material:=StandardMaterial3D.new()
			material.albedo_color=Color(0.55,0.52,0.40)
			material.emission_enabled=true
			material.emission=Color(1.0,0.78,0.42)
			material.emission_intensity=32000.0
			mesh.material=material
			fixture.mesh=mesh
			fixture.position=Vector3(x,4.22,side*10.4)
			root.add_child(fixture)
			var light:=OmniLight3D.new()
			light.position=fixture.position-Vector3.UP*0.16
			light.light_color=Color(1,0.85,0.64)
			light.light_intensity_lumens=90000
			light.omni_range=6
			light.omni_attenuation=1.7
			light.light_bake_mode=Light3D.BAKE_DYNAMIC
			root.add_child(light)
	var patch_material:=ShaderMaterial.new()
	patch_material.shader=PATCH
	for at: Vector3 in [Vector3(-24,0.027,26.4),Vector3(-24,0.027,-26.4),Vector3(-25,0.027,10.4),Vector3(-25,0.027,-10.4),Vector3(-13.5,0.027,1.9),Vector3(-22.5,0.027,-2),Vector3(0,3.417,0)]:
		var patch:=MeshInstance3D.new()
		var plane:=PlaneMesh.new()
		plane.size=Vector2(3.2,2.4)
		patch.mesh=plane
		patch.material_override=patch_material
		patch.position=at
		patch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		patch.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(patch)
static func make_probe(spec: Dictionary) -> VoxelGI:
	var probe:=VoxelGI.new()
	probe.name=spec.name
	probe.position=spec.position
	probe.size=spec.size
	probe.subdiv=VoxelGI.SUBDIV_128
	return probe
static func beveled_box(size: Vector3) -> ArrayMesh:
	return preload("../materials/beveled_box.gd").build(size)
