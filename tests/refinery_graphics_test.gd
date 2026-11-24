extends SceneTree
const MAP:=preload("res://game/maps/map_builder.gd")
var failed:=false
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool,label: String) -> void:
	failed=failed or not ok
	print("PASS " if ok else "FAIL ",label)
func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Run with a graphical renderer")
		quit(1)
		return
	AudioServer.set_bus_mute(0,true)
	var settings:=root.get_node("GameSettings")
	settings.fullscreen=false
	settings.vsync=false
	settings.fps_limit=0
	settings.render_scale=1.0
	settings.upscaling=Viewport.SCALING_3D_MODE_FSR2
	settings.apply_display()
	settings.apply_graphics()
	await process_frame
	await RenderingServer.frame_post_draw
	root.mode=Window.MODE_WINDOWED
	root.borderless=true
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	await process_frame
	await RenderingServer.frame_post_draw
	var dpi:=root.get_texture().get_size()/Vector2(root.size)
	root.size=Vector2i(Vector2(2560,1440)/dpi)
	root.position=Vector2i.ZERO
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_size()==Vector2(2560,1440),"Actual framebuffer is 2560×1440")
	root.scaling_3d_scale=1.0
	root.always_on_top=true
	root.grab_focus()
	var arena: Node3D=(load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await arena.start_solo(0,1,0,MAP.REFINERY_ID,Vector2i.ZERO,2)
	arena.get_node("HUD").hide()
	for player in get_nodes_in_group("player"):player.hide()
	var camera:=Camera3D.new()
	arena.add_child(camera)
	camera.make_current()
	var old_indirect: bool=settings.indirect_lighting
	settings.indirect_lighting=true
	arena._apply_graphics()
	if "--before" not in OS.get_cmdline_user_args():
		var probes:=get_nodes_in_group(&"refinery_bounce")
		check(probes.size()==2,"Two bounded VoxelGI volumes installed")
		for probe: VoxelGI in probes:check(probe.data!=null and probe.visible,"Baked local bounce is active")
		var terrain: Terrain3D=arena.get_node("Map").find_child("Terrain3DSurface",true,false)
		check(terrain.assets.get_texture_asset(2).albedo_texture.get_width()==2048,"Refinery ground retains 2K surface detail")
		settings.indirect_lighting=false
		arena._apply_graphics()
		for probe: VoxelGI in probes:check(not probe.visible,"Indirect-lighting setting disables local GI")
		settings.indirect_lighting=true
		arena._apply_graphics()
		var tested:=false
		var map:=arena.get_node("Map")
		for cover in map._perforated:
			for visual: MeshInstance3D in cover.body.find_children("*","MeshInstance3D",false,false):
				var material: Material=visual.get_active_material(0)
				if not material is ShaderMaterial or not material.get_meta(&"perforation_ready",false):continue
				cover.points.append(Vector4(visual.global_position.x,visual.global_position.y,visual.global_position.z,0.04))
				cover.axes.append(Vector3.RIGHT)
				map._apply_bullet_holes(cover)
				var perforated: ShaderMaterial=visual.material_override
				check(perforated.shader==material.shader and perforated.get_shader_parameter("hole_count")==1,"Bullet holes retain the weathered material")
				tested=true
				break
			if tested:break
		check(tested,"A refinery metal panel exercised the perforation path")
		map.clear_bullet_holes()
	var label: String="before" if "--before" in OS.get_cmdline_user_args() else "after"
	for shot: Array in [["overview",Vector3(48,37,51),Vector3(-4,1,0)],["yard",Vector3(-16,1.8,27),Vector3(-22,3,0)],["process",Vector3(15,5.2,9),Vector3(-4,4,0)],["bay",Vector3(-15,1.8,10.4),Vector3(-26,1.8,10.4)],["surface",Vector3(-17,1.4,14),Vector3(-20,0,9)]]:
		camera.position=shot[1]
		camera.look_at(shot[2])
		await create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/refinery-%s-%s.png"%[label,shot[0]])
	if label=="after":
		settings.indirect_lighting=false
		arena._apply_graphics()
		camera.position=Vector3(-18.9,1.8,10.4)
		camera.look_at(Vector3(-27,1.8,10.4))
		await create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/refinery-gi-off.png")
		settings.indirect_lighting=true
		arena._apply_graphics()
		await create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/refinery-gi-on.png")
	if "--performance" in OS.get_cmdline_user_args():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps=0
		for enabled in [false,true]:
			settings.indirect_lighting=enabled
			arena._apply_graphics()
			var times: Array[float]=[]
			var draws: float=0.0
			for shot: Array in [[Vector3(-16,1.8,27),Vector3(-22,3,0)],[Vector3(15,5.2,9),Vector3(-4,4,0)],[Vector3(-18.9,1.8,10.4),Vector3(-27,1.8,10.4)]]:
				camera.position=shot[0]
				camera.look_at(shot[1])
				await create_timer(1.0).timeout
				var previous:=Time.get_ticks_usec()
				for i in 90:
					await process_frame
					var now:=Time.get_ticks_usec()
					times.append((now-previous)/1000.0)
					previous=now
					draws+=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			times.sort()
			print("BENCH ",JSON.stringify({"indirect":enabled,"framebuffer":str(root.get_texture().get_size()),"scale":root.scaling_3d_scale,"upscaling":root.scaling_3d_mode,"frames":times.size(),"median_ms":times[times.size()/2],"p95_ms":times[int(times.size()*0.95)],"draws":draws/times.size(),"texture_mib":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)/1048576.0}))
	settings.indirect_lighting=old_indirect
	print("FAIL refinery rendered review" if failed else "PASS refinery rendered review ",label)
	arena.queue_free()
	for i in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	quit(int(failed))
