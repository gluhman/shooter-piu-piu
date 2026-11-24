extends SceneTree
const MAP := preload("res://game/maps/map_builder.gd")
const HILL := preload("res://game/maps/forest_hill/forest_hill_layout.gd")
const LAYOUT := preload("res://game/maps/objective_layout.gd")
var failed := false
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	failed = failed or not ok
	print(("PASS " if ok else "FAIL ") + label)
func _run() -> void:
	AudioServer.set_bus_mute(0,true)
	for mode in 5:
		for size in 3:
			check(LAYOUT.supports(mode,HILL.MAP_ID,size) == (mode==LAYOUT.HILL and size==2), "Mode/size contract %d/%d"%[mode,size])
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await arena.start_solo(0,1,0,HILL.MAP_ID,Vector2i.ZERO,2,true,false,-1,LAYOUT.HILL)
	arena.objectives.set_physics_process(false)
	for bot in get_nodes_in_group("bot"):bot.set_physics_process(false)
	var map := arena.get_node("Map")
	if "--preview" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		await capture(arena)
		arena.queue_free()
		await process_frame
		print("PASS forest hill rendered preview")
		quit(int(failed))
		return
	check(arena.map_id==HILL.MAP_ID and arena.arena_width()==100.0,"Dedicated 100 m hill arena loads")
	check(arena.objectives.centers.size()==1 and arena.objectives.rules.order==[0],"One permanent summit flag for every roster")
	check(arena.objectives.spawns[0][0].x < -35 and arena.objectives.spawns[1][0].x > 35,"Teams deploy in opposite corners")
	check(map.get_meta("hill_fence_height")==0.9 and get_nodes_in_group(&"hill_cover").size()==16,"Summit rock walls are half player height")
	check(map.get_tree().get_nodes_in_group("hill_tunnel").size()==4,"Four physical tunnel meshes")
	var space: PhysicsDirectSpaceState3D = map.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.75
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.margin = 0.001
	for path: Array in HILL.paths():
		check(path[-1].y<=8.01,"Tunnel exits below the summit")
		var buried: Vector3=path[int(path.size()*0.3)]
		check(HILL.height_at(Vector2(buried.x,buried.z))>buried.y+3.15,"Tunnel passes underground below the hill")
		var clear := true
		for i in range(path.size()-1):
			for step in 7:
				var point: Vector3 = path[i].lerp(path[i+1],float(step)/6.0)
				var floor_ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*0.6,point-Vector3.UP*0.6,1)
				var floor_hit := space.intersect_ray(floor_ray)
				if not floor_hit.is_empty():point.y = floor_hit.position.y
				query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*1.05)
				var collisions := space.intersect_shape(query)
				if not collisions.is_empty():print("BLOCKED ",point," ",collisions[0].collider.get_path())
				clear = clear and collisions.is_empty()
		check(clear,"Standing clearance throughout tunnel %s"%path[0])
	for path: Array in HILL.paths():
		check(await walk_route(arena,path,capsule),"Player walks through tunnel %s"%path[0])
	for climb: Dictionary in HILL.climbs():
		var path: Array=[]
		var count:=ceili((float(climb.start)-float(climb.end))/0.5)
		for i in count+1:
			var p: Vector2=Vector2(cos(climb.angle),sin(climb.angle))*lerpf(climb.start,climb.end,float(i)/count)
			path.append(Vector3(p.x,HILL.height_at(p),p.y))
		check(await walk_route(arena,path,capsule),"Walks up terrace %d at %.0f degrees without jumping"%[climb.tier+1,rad_to_deg(climb.angle)])
	var nav: RID = arena._navigation_region.get_navigation_map()
	await physics_frame
	await physics_frame
	for attempt in 40:
		if NavigationServer3D.map_get_closest_point_owner(nav,Vector3(0,12,0))==arena._navigation_region.get_rid():break
		await create_timer(0.025).timeout
	print("NAV_POLYGONS ",arena._navigation_region.navigation_mesh.get_polygon_count()," CLOSEST ",NavigationServer3D.map_get_closest_point(nav,Vector3(0,12,0)))
	for radius in [27.0,20.5]:
		var connected:=true
		for i in 48:
			var a: Vector2=Vector2(cos(i*TAU/48),sin(i*TAU/48))*radius
			var b: Vector2=Vector2(cos((i+1)*TAU/48),sin((i+1)*TAU/48))*radius
			# Sample clear ground beside cover, rather than projecting a point inside
			# a real boulder onto its potentially isolated upper surface.
			var probes: Array[Array]=[]
			for point: Vector2 in [a,b]:
				var candidates: Array[Vector3]=[]
				var radial:=point.normalized()
				var tangent:=Vector2(-radial.y,radial.x)
				for offset: Vector2 in [Vector2.ZERO,radial*1.5,-radial*1.5,tangent*1.5,-tangent*1.5,radial*3,-radial*3,tangent*3,-tangent*3]:
					var p:=point+offset
					var feet:=Vector3(p.x,HILL.height_at(p)+0.1,p.y)
					query.transform=Transform3D(Basis.IDENTITY,feet+Vector3.UP*0.95)
					if not space.intersect_shape(query,1).is_empty():continue
					var projected:=NavigationServer3D.map_get_closest_point(nav,feet)
					if projected.distance_to(feet)<0.8:candidates.append(projected)
				probes.append(candidates)
			var linked:=false
			for start: Vector3 in probes[0]:
				for end: Vector3 in probes[1]:
					var route:=NavigationServer3D.map_get_path(nav,start,end,true)
					var land:=not route.is_empty() and route[-1].distance_to(end)<0.6
					for point in route:
						if HILL.height_at(Vector2(point.x,point.z))-point.y>2.0:land=false
					if land:
						linked=true
						break
				if linked:break
			if not linked:print("No clear overland connection at ring ",radius," segment ",i)
			connected=connected and linked
		check(connected,"Terrace ring %.1f m connects overland without entering tunnels"%radius)
	for side in [-1.0,1.0]:
		var blocked:=false
		var before:=0.0
		for i in 100:
			var p: Vector2=Vector2(-42,-42)*side*(1.0-i/100.0)
			var h:=HILL.height_at(p)
			if i>0 and h-before>0.85:blocked=true
			before=h
		check(blocked,"Direct spawn-to-summit line requires a detour")
	var summit := Vector3(0,12.1,0)
	var destinations := PackedVector3Array([summit])
	for pool in arena.objectives.spawns:destinations.append_array(pool)
	var loot := arena.get_node("Loot")
	check(loot._crates.size()==12,"Supplies on all four levels")
	for crate in loot._crates:
		var reachable := false
		for offset in [Vector3(-1.6,0,0),Vector3(1.6,0,0),Vector3(0,0,-1.6),Vector3(0,0,1.6)]:
			var approach: Vector3 = crate.position+offset
			var route := NavigationServer3D.map_get_path(nav,summit,approach,true)
			reachable = reachable or (not route.is_empty() and route[-1].distance_to(approach)<0.75)
		check(reachable,"Loot has reachable pickup approach at %s"%crate.position)
	for path: Array in HILL.paths():
		destinations.append(path[0]+Vector3.UP*0.1)
		destinations.append(path[-1]+Vector3.UP*0.1)
		destinations.append(path[path.size()/2]+Vector3.UP*0.1)
	for at in destinations:
		var route := NavigationServer3D.map_get_path(nav,summit,at,true)
		check(not route.is_empty() and route[-1].distance_to(at)<1.2,"Summit connected to %s"%at)
	var player: Node3D = arena.combatant(1)
	for i in 3:
		loot._open_crate(player,i,loot._crates[i].position+Vector3.UP*0.7)
		var drop: Dictionary = loot._drops[loot._crate_drop_ids[i]]
		check(drop.kind == [loot.Kind.WEAPON,loot.Kind.MEDKIT,loot.Kind.ARMOR][i],"Summit guaranteed reward %d"%i)
		if i==0:check(drop.weapon=="rpg","Summit crate contains RPG")
	player.position = summit
	for tick in 60:arena.objectives.rules.step(arena.objectives,[player])
	check(arena.objectives.scores.x+arena.objectives.scores.y>0,"Standing at the flag scores hill control")
	if DisplayServer.get_name()!="headless":await capture(arena)
	arena.queue_free()
	await process_frame
	print("FAIL forest hill" if failed else "PASS forest hill")
	quit(int(failed))

func walk_route(arena: Node3D,path: Array,capsule: Shape3D) -> bool:
	var walker := CharacterBody3D.new()
	walker.collision_layer=0
	walker.collision_mask=1
	walker.floor_snap_length=0.35
	var shape := CollisionShape3D.new()
	shape.shape=capsule
	shape.position.y=0.9
	walker.add_child(shape)
	arena.add_child(walker)
	walker.position=path[0]+Vector3.UP*0.12
	var target := 1
	for tick in 900:
		await physics_frame
		var offset: Vector3=path[target]-walker.position
		offset.y=0
		if offset.length()<0.4:
			if target==path.size()-1:break
			target+=1
		var fall := 0.0 if walker.is_on_floor() else walker.velocity.y-20.0/60.0
		walker.velocity=offset.normalized()*4.5+Vector3.UP*fall
		walker.move_and_slide()
	var reached: bool=walker.position.distance_to(path[-1])<0.8
	if not reached:
		print("WALK BLOCKED ",walker.position," next ",path[target])
		for i in walker.get_slide_collision_count():print("CONTACT ",walker.get_slide_collision(i).get_collider().get_path()," normal ",walker.get_slide_collision(i).get_normal())
	walker.queue_free()
	return reached

func capture(arena: Node3D) -> void:
	var map:=arena.get_node("Map")
	var player: Node3D=arena.combatant(1)
	check(not map.find_children("Terrain3DSurface","Terrain3D",true,false).is_empty(),"Terrain3D renders the hill")
	root.size = Vector2i(1600,960)
	root.always_on_top = true
	root.grab_focus()
	arena.get_node("HUD").hide()
	player.hide()
	var camera := Camera3D.new()
	arena.add_child(camera)
	camera.make_current()
	for shot: Array in [["player",Vector3(-40,1.8,-40),Vector3(0,10,0)]]:
		camera.position=shot[1]
		camera.look_at(shot[2])
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/forest-hill-%s.png"%shot[0])
	var lower: Array=HILL.paths()[0]
	var upper: Array=HILL.paths()[2]
	var approach: Vector3=(lower[1]-lower[0]).normalized()
	var emergence: Vector3=(upper[-1]-upper[-2]).normalized()
	var shots: Array=[["overview",Vector3(57,60,65),Vector3(0,4,0)],["summit",Vector3(7,15,6),Vector3(0,12.6,0)],
		["tunnel",lower[2]+Vector3.UP*1.7,lower[8]+Vector3.UP*1.7],
		["entrance",lower[0]-approach*1.3+Vector3.UP*1.8,lower[5]+Vector3.UP*1.4],
		["exit",upper[-1]+emergence*2.4+Vector3.UP*1.8,upper[-5]+Vector3.UP],
		["interior",lower[lower.size()/2]+Vector3.UP*1.7,lower[mini(lower.size()-1,lower.size()/2+5)]+Vector3.UP*1.7]]
	for shot: Array in shots:
		camera.position=shot[1]
		camera.look_at(shot[2])
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/forest-hill-%s.png"%shot[0])
	# Review the actual minimap overlays at the player's base.
	player.position=Vector3(-42,0.18,-42)
	arena.get_node("HUD/WeaponSelect")._confirm_loadout()
	player.position=Vector3(-42,0.18,-42)
	arena.get_node("HUD").show()
	arena.get_node("HUD/Lobby").hide()
	camera.make_current()
	camera.position=Vector3(-40,1.8,-40)
	camera.look_at(Vector3(-30,1,-39))
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/forest-hill-minimap.png")

