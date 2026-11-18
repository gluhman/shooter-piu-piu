extends SceneTree
func _initialize() -> void:
	call_deferred("normalize")
func normalize() -> void:
	var original = load("res://assets/operator/operator.glb").instantiate()
	root.add_child(original)
	var source: Skeleton3D = original.find_child("Skeleton3D",true,false)
	source.reset_bone_poses()
	var model=Node3D.new()
	model.name="Operator"
	root.add_child(model)
	var sk=Skeleton3D.new()
	sk.name="Skeleton3D"
	model.add_child(sk)
	sk.owner=model
	var world_rests: Array[Transform3D] = []
	for i in source.get_bone_count():
		sk.add_bone(source.get_bone_name(i))
		sk.set_bone_parent(i,source.get_bone_parent(i))
		var world_rest = source.global_transform * source.get_bone_global_rest(i)
		world_rest.basis = world_rest.basis.orthonormalized()
		if source.get_bone_parent(i) < 0:
			world_rest = Transform3D.IDENTITY
		var rest = world_rest
		if source.get_bone_parent(i) >= 0:
			rest = world_rests[source.get_bone_parent(i)].affine_inverse() * world_rest
		world_rests.append(world_rest)
		sk.set_bone_rest(i,rest)
	sk.reset_bone_poses()
	for old in original.find_children("*","MeshInstance3D",true,false):
		var mesh=MeshInstance3D.new()
		mesh.name=old.name
		sk.add_child(mesh)
		mesh.owner=model
		mesh.skeleton=NodePath("..")
		var skin=Skin.new()
		var matrices:Array[Transform3D]=[]
		if old.skin:
			for i in old.skin.get_bind_count():
				var bone=old.skin.get_bind_bone(i)
				if bone<0:bone=source.find_bone(old.skin.get_bind_name(i))
				var rest=source.global_transform*source.get_bone_global_rest(bone)
				matrices.append(rest*old.skin.get_bind_pose(i))
				skin.add_named_bind(sk.get_bone_name(bone),sk.get_bone_global_rest(bone).affine_inverse())
		else:
			var head=sk.find_bone("mixamorig_Head_06")
			skin.add_named_bind(sk.get_bone_name(head),sk.get_bone_global_rest(head).affine_inverse())
		mesh.skin=skin
		mesh.mesh=ArrayMesh.new()
		for surface in old.mesh.get_surface_count():
			var arrays=old.mesh.surface_get_arrays(surface)
			var positions:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES] if old.skin else PackedInt32Array()
			var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS] if old.skin else PackedFloat32Array()
			if not old.skin:
				bones.resize(positions.size()*4);weights.resize(positions.size()*4)
			for v in positions.size():
				var pos=Vector3.ZERO
				var norm=Vector3.ZERO
				if old.skin:
					for j in 4:
						var idx=v*4+j
						if weights[idx]>0.0:
							var t=matrices[bones[idx]]
							pos+=(t*positions[v])*weights[idx]
							norm+=(t.basis.inverse().transposed()*normals[v])*weights[idx]
				else:
					pos=old.global_transform*positions[v]
					norm=old.global_basis.inverse().transposed()*normals[v]
					weights[v*4]=1.0
				positions[v]=pos;normals[v]=norm.normalized()
			arrays[Mesh.ARRAY_VERTEX]=positions;arrays[Mesh.ARRAY_NORMAL]=normals
			arrays[Mesh.ARRAY_BONES]=bones;arrays[Mesh.ARRAY_WEIGHTS]=weights
			arrays[Mesh.ARRAY_TANGENT]=null
			mesh.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			mesh.mesh.surface_set_material(surface,old.mesh.surface_get_material(surface))
	var doc=GLTFDocument.new();var state=GLTFState.new()
	print("APPEND ",doc.append_from_scene(model,state))
	print("EXPORT ",doc.write_to_filesystem(state,"/tmp/piupiu-operator-clean.glb"))
	quit()
