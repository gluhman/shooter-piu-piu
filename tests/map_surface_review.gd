extends SceneTree
## Graphical all-map material/grass review; -- --maps 11,3 --performance is supported.
const MAP := preload("res://game/maps/map_builder.gd")
var failed := false
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:failed = true
	print("PASS " if ok else "FAIL ",label)
func _run() -> void:
	if DisplayServer.get_name()=="headless":
		quit(1)
		return
	AudioServer.set_bus_mute(0,true)
	var settings := root.get_node("GameSettings")
	settings.fullscreen = false
	settings.vsync = false
	settings.fps_limit = 0
	settings.render_scale = 1.0
	settings.upscaling = Viewport.SCALING_3D_MODE_FSR2
	settings.apply_display()
	settings.apply_graphics()
	await process_frame
	await RenderingServer.frame_post_draw
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	await process_frame
	await RenderingServer.frame_post_draw
	var dpi := root.get_texture().get_size()/Vector2(root.size)
	root.size = Vector2i(Vector2(2560,1440)/dpi)
	root.position = Vector2i.ZERO
	root.always_on_top = true
	root.grab_focus()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_size()==Vector2(2560,1440),"Review uses actual 2560×1440 framebuffer")
	var arena: Node3D = load("res://game/match/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	var ids: Array = range(MAP.MAP_NAMES.size())
	var args := OS.get_cmdline_user_args()
	if "--maps" in args:ids=Array(args[args.find("--maps")+1].split(",")).map(func(id: String)->int:return int(id))
	for id: int in ids:
		await arena.start_solo(0,1,0,id,Vector2i.ZERO,2,true,false,-1,2 if id==13 else 0)
		arena.get_node("HUD").hide()
		for player in get_nodes_in_group("player"):player.hide()
		var map: Node3D = arena.get_node("Map")
		if id!=12:check(map.get_meta(&"surface_finish_count",0)>0,"%s receives weathered surfaces"%MAP.MAP_NAMES[id])
		var count := 0
		for mesh: MeshInstance3D in map.find_children("*","MeshInstance3D",true,false):
			if not mesh.mesh:continue
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface)
				if not material is ShaderMaterial or not material.get_meta(&"surface_finish",false):continue
				count+=1
				var source: StandardMaterial3D = material.get_meta(&"source_material")
				check(material.get_shader_parameter("use_mesh_uv")==not source.uv1_triplanar,"Authored UV projection retained")
				check(material.get_shader_parameter("roughness_channel")==source.roughness_texture_channel,"PBR roughness channel retained")
				break
			if count>0:break
		var moving_tested := false
		var solid_tested := false
		for cover in map._perforated:
			var meshes: Array = [cover.moving_surface] if cover.moving_surface else cover.body.find_children("*","MeshInstance3D",false,false)
			for visual: MeshInstance3D in meshes:
				var material := visual.get_active_material(0)
				if not material is ShaderMaterial or not material.get_meta(&"surface_finish",false):continue
				if (cover.moving_surface and moving_tested) or (not cover.moving_surface and solid_tested):continue
				cover.points.append(Vector4(visual.global_position.x,visual.global_position.y,visual.global_position.z,0.04))
				cover.axes.append(Vector3.RIGHT)
				map._apply_bullet_holes(cover)
				check(visual.material_override.get_shader_parameter("hole_count")==1,"Weathered cover retains rendered bullet holes")
				map.clear_bullet_holes()
				check(visual.get_active_material(0)==material,"Clearing holes restores the weathered finish")
				if cover.moving_surface:moving_tested=true
				else:solid_tested=true
				break
			if moving_tested and solid_tested:break
		var camera := Camera3D.new()
		camera.fov=74
		arena.add_child(camera)
		camera.make_current()
		var width: float = arena.arena_width()
		var bounds: Rect2 = arena._breakwater.get_arena_bounds() if id==6 else Rect2(-Vector2.ONE*width/2,Vector2.ONE*width)
		var center := Vector3(bounds.get_center().x,0,bounds.get_center().y)
		camera.position=center+Vector3(width*0.42,width*0.34,width*0.47)
		camera.look_at(center+Vector3.UP*(5.0 if id==13 else 1.0))
		if id in [8,10]:
			camera.position=Vector3(-3.2,1.7,-5.5) if id==8 else Vector3(-5,1.7,-5)
			camera.look_at(Vector3(0,1.5,0))
		await create_timer(0.7).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/map-finish-%02d-overview.png"%id)
		if map.has_meta(&"terrain_grass_positions"):
			var plants: Array=map.get_meta(&"terrain_grass_positions")[0]
			var space := map.get_world_3d().direct_space_state
			var closest := INF
			var target := Vector3(width*0.24,0,-width*0.16)
			for plant: Transform3D in plants:
				var delta := Vector2(plant.origin.x-target.x,plant.origin.z-target.z).length_squared()
				if delta>=closest:continue
				var eye := plant.origin+Vector3(1.6,1.6,2.2)
				var ray := PhysicsRayQueryParameters3D.create(eye,plant.origin+Vector3.UP*0.25,1)
				if not space.intersect_ray(ray).is_empty():continue
				closest=delta
				camera.position=eye
				camera.look_at(plant.origin+Vector3.UP*0.15)
			await create_timer(0.6).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/map-finish-%02d-grass.png"%id)
		if "--performance" in args:
			var times: Array[float]=[]
			var previous:=Time.get_ticks_usec()
			for frame in 120:
				await process_frame
				var now:=Time.get_ticks_usec()
				times.append((now-previous)/1000.0)
				previous=now
			times.sort()
			print("BENCH ",JSON.stringify({"map":id,"frames":120,"median_ms":times[60],"p95_ms":times[114],"scale":root.scaling_3d_scale,"texture_mib":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)/1048576.0}))
		print("REVIEW ",id," ",MAP.MAP_NAMES[id]," ",map.get_meta(&"surface_finish_count",0)," surfaces")
		camera.queue_free()
		arena._clear_match_map()
		await process_frame
	arena.queue_free()
	for i in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	print("FAIL map surface review" if failed else "PASS all requested map surface reviews")
	quit(int(failed))
