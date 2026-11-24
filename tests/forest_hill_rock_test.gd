extends "res://tests/forest_hill_test.gd"
## Compare actual physics hits to the source rock triangles, including empty AABB corners.
const ROCK_SCENE := preload("res://game/maps/forest_ridge/art/rock/rock_moss_set_01_1k.gltf")
const ISOLATED_LAYER := 1 << 27
func _run() -> void:
	AudioServer.set_bus_mute(0,true)
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await arena.start_solo(0,1,0,HILL.MAP_ID,Vector2i.ZERO,2,true,false,-1,LAYOUT.HILL)
	arena.objectives.set_physics_process(false)
	for bot in get_nodes_in_group("bot"):bot.set_physics_process(false)
	await physics_frame
	await physics_frame
	var source := ROCK_SCENE.instantiate()
	var meshes: Array[Mesh]=[]
	if source is MeshInstance3D:meshes.append(source.mesh)
	for node: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):meshes.append(node.mesh)
	source.free()
	var samples: Dictionary[int,Array]={}
	for i in meshes.size():samples[i]=reference_rays(meshes[i])
	var rocks:=get_nodes_in_group("hill_rock")
	var space: PhysicsDirectSpaceState3D=arena.get_world_3d().direct_space_state
	var empty_corners:=0
	var solid_hits:=0
	var summit_count:=0
	var shape_digest: Array=[]
	for rock: StaticBody3D in rocks:
		var index: int=rock.get_meta("rock_variant")
		var size: Vector3=rock.get_meta("rock_size")
		var bounds:=meshes[index].get_aabb()
		var scale:=size/bounds.size
		var fit:=rock.global_transform*Transform3D(Basis.from_scale(scale),-bounds.get_center()*scale)
		var colliders:=rock.find_children("*","CollisionShape3D",true,false)
		check(colliders.size()==1 and colliders[0].shape is ConcavePolygonShape3D and rock.collision_layer==1,"Rock uses mesh collision for movement and hits: %s"%rock.name)
		if rock.is_in_group("hill_cover"):summit_count+=1
		shape_digest.append([rock.position,hash(var_to_bytes(colliders[0].shape.get_faces()))])
		rock.collision_layer=ISOLATED_LAYER
		await physics_frame
		var matched:=true
		for sample: Dictionary in samples[index]:
			var ray:=PhysicsRayQueryParameters3D.create(fit*sample.from,fit*sample.to,ISOLATED_LAYER)
			var actual:=space.intersect_ray(ray)
			if sample.hit==null:
				empty_corners+=1
				if not actual.is_empty():matched=false
			else:
				solid_hits+=1
				if actual.is_empty() or actual.position.distance_to(fit*sample.hit)>0.005:matched=false
		rock.collision_layer=1
		check(matched,"Rays fit the visible stone and pass empty box corners: %s"%rock.name)
	check(rocks.size()>16 and summit_count==16,"Checked every rock, including all sixteen summit wall stones")
	check(empty_corners>0 and solid_hits>0,"Both empty bounding-box space and solid rock tested")
	print("ROCK_COLLISION_DIGEST ",hash(var_to_bytes(shape_digest))," rocks ",rocks.size()," clear rays ",empty_corners," stone hits ",solid_hits)
	if DisplayServer.get_name()!="headless":await capture(arena)
	arena.queue_free()
	await process_frame
	print("FAIL forest hill rocks" if failed else "PASS forest hill rocks")
	quit(int(failed))
func reference_rays(mesh: Mesh) -> Array:
	var rays: Array=[]
	var bounds:=mesh.get_aabb()
	var faces:=mesh.get_faces()
	for axis in 3:
		for side in [-1.0,1.0]:
			for row in 5:
				for column in 5:
					var from:=bounds.position
					from[(axis+1)%3]+=bounds.size[(axis+1)%3]*(0.02+row*0.24)
					from[(axis+2)%3]+=bounds.size[(axis+2)%3]*(0.02+column*0.24)
					from[axis]+=(-0.1 if side>0 else 1.1)*bounds.size[axis]
					var to:=from
					to[axis]+=side*bounds.size[axis]*1.2
					var hit: Variant=null
					var distance:=INF
					for face in range(0,faces.size(),3):
						var candidate: Variant=Geometry3D.segment_intersects_triangle(from,to,faces[face],faces[face+1],faces[face+2])
						if candidate!=null and from.distance_squared_to(candidate)<distance:
							distance=from.distance_squared_to(candidate)
							hit=candidate
					rays.append({"from":from,"to":to,"hit":hit})
	return rays
