extends RefCounted
## King-of-the-Hill-only, 100 m forest bastion with real covered climbing tunnels.
const MAP_ID := 13
const WIDTH := 100.0
const HALF := 50.0
const SUMMIT := 12.0
const FENCE_HEIGHT := 0.9
const BAKE_BOUNDS := AABB(Vector3(-50, -2, -50), Vector3(100, 32, 100))
const TERRAIN := preload("../terrain_3d_surface.gd")
const FIRS := preload("../forest_ridge/fir_meshes.gd")
const TUNNELS := [
	[Vector3(-20,0,-34), Vector3(-15,0,-27), Vector3(-10,0,-20), Vector3(-9,2,-12), Vector3(-22,4,-13)],
	[Vector3(20,0,34), Vector3(15,0,27), Vector3(10,0,20), Vector3(9,2,12), Vector3(22,4,13)],
	[Vector3(-19,4,22), Vector3(-10,3,17), Vector3(-6,5.5,11), Vector3(-14,8,6)],
	[Vector3(19,4,-22), Vector3(10,3,-17), Vector3(6,5.5,-11), Vector3(14,8,-6)],
]
const RAMPS := [
	[Vector2(-0.8660254,-0.5),Vector2(0.5,-0.8660254),Vector2(0.8660254,0.5),Vector2(-0.5,0.8660254)],
	[Vector2(-0.258819,-0.965926),Vector2(0.965926,-0.258819),Vector2(0.258819,0.965926),Vector2(-0.965926,0.258819)],
	[Vector2(-0.8660254,-0.5),Vector2(0.5,-0.8660254),Vector2(0.8660254,0.5),Vector2(-0.5,0.8660254)]]
const APPROACHES := [[Vector2(-42,-42),Vector2(-42,-31),Vector2(-36.4,-21)],
	[Vector2(-42,-42),Vector2(-30,-39),Vector2(-20,-34)]]
const SUPPLIES := [Vector2(-4,1), Vector2(1,3), Vector2(4,-1),
	Vector2(-29,-4), Vector2(29,4), Vector2(4,29),
	Vector2(-18,3), Vector2(18,-3), Vector2(3,-18),
	Vector2(-39,-25), Vector2(39,25), Vector2(-26,39)]
var _map: Node3D
var _root := Node3D.new()
var _rng := RandomNumberGenerator.new()
var _visuals := DisplayServer.get_name() != "headless"
var _soil: StandardMaterial3D
var _stone: Material
var _rocks: Array[Mesh] = []
var _rock_collisions: Dictionary[String,ConcavePolygonShape3D] = {}
var _outlines: Array[PackedVector2Array] = []

func _init(map: Node3D) -> void:
	_map = map

static func placement() -> Dictionary:
	var pools: Array = []
	for side in [-1.0, 1.0]:
		var points: Array = []
		for offset: Vector2 in [Vector2.ZERO, Vector2(3,0), Vector2(0,3), Vector2(3,3), Vector2(6,0)]:
			points.append([side * (42.0 - offset.x), 0.0, side * (42.0 - offset.y)])
		pools.append(points)
	return {"c": [[0,SUMMIT,0]], "s": pools, "r": 4.5, "cover": [], "hill_cover": []}

static func climbs() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for tier in 3:
		for arm in 4:
			result.append({"tier":tier,"angle":deg_to_rad([-150.0,-105.0,-150.0][tier]+arm*90),"start":[42.0,30.0,22.0][tier],"end":[28.0,16.0,9.0][tier]})
	return result

static func surface_routes() -> Array[PackedVector2Array]:
	var routes: Array[PackedVector2Array]=[]
	for climb: Dictionary in climbs():
		var direction:=Vector2(cos(climb.angle),sin(climb.angle))
		routes.append(PackedVector2Array([direction*float(climb.start),direction*float(climb.end)]))
	for radius in [27.0,20.5]:
		var ring:=PackedVector2Array()
		for i in 65:ring.append(Vector2(cos(i*TAU/64),sin(i*TAU/64))*radius)
		routes.append(ring)
	for side in [-1.0,1.0]:
		for approach: Array in APPROACHES:
			var points:=PackedVector2Array()
			for p: Vector2 in approach:points.append(p*side)
			routes.append(points)
	return routes

static func height_at(p: Vector2) -> float:
	var radius:=p.length()
	var height:=0.0
	for tier in 3:
		var edge: float=[35.0,23.0,11.0][tier]
		var step:=1.0-smoothstep(edge-1.0,edge+1.0,radius)
		var start: float=[42.0,30.0,22.0][tier]
		var end: float=[28.0,16.0,9.0][tier]
		for arm in 4:
			var forward: Vector2=RAMPS[tier][arm]
			var across:=absf(p.cross(forward))
			var along:=p.dot(forward)
			var lane: float=(1.0-smoothstep(3.2,5.5,across))*smoothstep(end-2.0,end+1.0,along)
			step=lerpf(step,1.0-smoothstep(end,start,radius),lane)
		height+=step*4.0
	return height

static var _paths: Array = []
static var _tunnel_cells: Dictionary = {}

static func paths() -> Array:
	if not _paths.is_empty():return _paths
	for authored: Array in TUNNELS:
		var curve := Curve3D.new()
		curve.bake_interval = 0.4
		for i in authored.size():
			var before: Vector3 = authored[maxi(0,i-1)]
			var after: Vector3 = authored[mini(authored.size()-1,i+1)]
			var tangent := (after-before)*0.25
			curve.add_point(authored[i],-tangent,tangent)
		var samples: Array = []
		var count := ceili(curve.get_baked_length()/0.6)
		for i in count+1:samples.append(curve.sample_baked(curve.get_baked_length()*i/count,true))
		_paths.append(samples)
		for i in range(samples.size()-1):
			var a: Vector3 = samples[i]
			var b: Vector3 = samples[i+1]
			var lo := Vector2(minf(a.x,b.x)-5.0,minf(a.z,b.z)-5.0)/4.0
			var hi := Vector2(maxf(a.x,b.x)+5.0,maxf(a.z,b.z)+5.0)/4.0
			for x in range(floori(lo.x),floori(hi.x)+1):
				for z in range(floori(lo.y),floori(hi.y)+1):
					var key := Vector2i(x,z)
					if not _tunnel_cells.has(key):_tunnel_cells[key]=[]
					_tunnel_cells[key].append([a,b])
	return _paths

static func tunnel_floor(p: Vector2) -> float:
	if _paths.is_empty():paths()
	var result := -INF
	for segment: Array in _tunnel_cells.get(Vector2i(floori(p.x/4.0),floori(p.y/4.0)),[]):
		var a: Vector3 = segment[0]
		var b: Vector3 = segment[1]
		var av := Vector2(a.x,a.z)
		var bv := Vector2(b.x,b.z)
		var t := clampf((p-av).dot(bv-av) / av.distance_squared_to(bv),0,1)
		if p.distance_to(av.lerp(bv,t)) < 2.0:
			result = maxf(result,lerpf(a.y,b.y,t))
	return result

static func terrain_hole(p: Vector2) -> bool:
	var sample := _nearest_tunnel(p)
	return sample.distance<1.55 and height_at(p)<sample.floor+3.3

static func visual_hole(p: Vector2) -> bool:
	return _nearest_tunnel(p).distance<3.2

func build() -> Array[Transform3D]:
	_rng.seed = 932713
	_root.name = "ForestHill"
	_map.add_child(_root)
	var rock_material := StandardMaterial3D.new()
	if _visuals:
		rock_material.albedo_texture=load("res://game/maps/refinery/art/rock_boulder_dry_diff_4k.jpg")
		rock_material.normal_texture=load("res://game/maps/refinery/art/rock_boulder_dry_nor_gl_4k.jpg")
	rock_material.normal_enabled=true
	rock_material.normal_scale=0.6
	rock_material.albedo_color=Color(0.48,0.51,0.52)
	rock_material.roughness=0.95
	rock_material.uv1_triplanar=true
	rock_material.uv1_world_triplanar=true
	rock_material.uv1_scale=Vector3.ONE*0.6
	_stone=rock_material
	_stone.set("cull_mode",BaseMaterial3D.CULL_DISABLED)
	_soil = _map._world_mat("village/dirt",Color(0.74,0.60,0.45),0.0,0.9,1.15,false)
	_soil.vertex_color_use_as_albedo = true
	_soil.uv1_triplanar=true
	_soil.uv1_world_triplanar=true
	# Collision uses the same source geometry on rendered and headless peers.
	var rock_scene := (load("res://game/maps/forest_ridge/art/rock/rock_moss_set_01_1k.gltf") as PackedScene).instantiate()
	if rock_scene is MeshInstance3D:_rocks.append(rock_scene.mesh)
	for node: MeshInstance3D in rock_scene.find_children("*","MeshInstance3D",true,false):_rocks.append(node.mesh)
	rock_scene.free()
	_ground()
	for i in TUNNELS.size():
		_tunnel(i,paths()[i])
	_perimeter()
	_summit()
	for side in [-1.0,1.0]:_rock(Vector3(-31*side,0,-31*side),Vector3(6,3,5),1)
	_bases()
	var supplies: Array[Transform3D] = []
	for i in SUPPLIES.size():
		var p: Vector2 = SUPPLIES[i]
		var at := Vector3(p.x,height_at(p),p.y)
		supplies.append(Transform3D(Basis(Vector3.UP,float(i)*0.7),at))
		_rock(at + Vector3(2.0,0,0),Vector3(1.5,1.4,1.3),i)
	_root.set_meta(&"minimap_outline",_outlines)
	_map.set_meta(&"minimap_tunnels",paths())
	_map.set_meta(&"minimap_routes",surface_routes())
	_map.set_meta(&"crate_rewards",[{"kind":"weapon","weapon":"rpg"},{"kind":"medkit","amount":2},{"kind":"armor"}])
	_map.set_meta(&"hill_levels",[0.0,4.0,8.0,12.0])
	_map.set_meta(&"hill_tunnels",paths())
	_map.set_meta(&"hill_fence_height",FENCE_HEIGHT)
	_forest()
	return supplies

func _ground() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in 200:
		for x in 200:
			var p := Vector2(x*0.5-50,z*0.5-50)
			if _nearest_tunnel(p+Vector2.ONE*0.25).distance<3.7:
				continue
			var points := [p,p+Vector2(0.5,0),p+Vector2(0.5,0.5),p+Vector2(0,0.5)]
			for index in [0,1,2,0,2,3]:
				var q: Vector2 = points[index]
				tool.add_vertex(Vector3(q.x,height_at(q),q.y))
	tool.generate_normals()
	tool.set_material(_stone)
	var mesh := tool.commit()
	_mesh_body("HillGround",mesh)
	if _visuals:
		var directory := "res://game/maps/forest_ridge/art/ground/"
		var layers: Array[Dictionary] = []
		for name in ["forest_ground_04","rocky_terrain_02"]:
			var prefix: String = directory + name
			var resolution := "1k"
			if name=="rocky_terrain_02":
				prefix="res://game/maps/farpost/art/ground/rocky_terrain_02"
				resolution="2k"
			layers.append({"name":name,"color":prefix+"_diff_"+resolution+".jpg","normal":prefix+"_nor_gl_"+resolution+".jpg","roughness":prefix+"_arm_"+resolution+".jpg","tint":Color(0.72,0.75,0.68) if name=="forest_ground_04" else Color(0.84,0.88,0.91)})
		TERRAIN.build(_root,Rect2(-50,-50,100,100),height_at,_paint,layers,visual_hole,1024)
		_root.get_node("HillGround/Visual").hide()
	_excavated_edges()
	_outlines.append(PackedVector2Array([Vector2(-50,-50),Vector2(50,-50),Vector2(50,50),Vector2(-50,50)]))
	for radius in [35.0,23.0,11.0]:
		var line := PackedVector2Array()
		for i in 65:line.append(Vector2(cos(i*TAU/64),sin(i*TAU/64))*radius)
		_outlines.append(line)

func _excavated_edges() -> void:
	# Clip the refined soil triangles at the continuous cut contour. Dropping whole
	# grid cells leaves stair-step teeth and alternating thin faces at cave mouths.
	var dirt:=SurfaceTool.new()
	dirt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top:=SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var masks: Dictionary[Vector2i,float]={}
	for bin: Vector2i in _tunnel_cells:
		for z in 32:
			for x in 32:
				var key:=bin*32+Vector2i(x,z)
				var center:=Vector2(key)*0.125+Vector2.ONE*0.0625
				if absf(center.x)>50 or absf(center.y)>50 or _nearest_tunnel(center).distance>4.25:continue
				var corners: Array[Vector2i]=[key,key+Vector2i.RIGHT,key+Vector2i.ONE,key+Vector2i.DOWN]
				for corner in corners:
					if not masks.has(corner):masks[corner]=_cut_mask(Vector2(corner)*0.125)
				for triangle: Array in [[0,1,2],[0,2,3]]:
					var polygon: Array[Vector2]=[]
					var boundary: Array[Vector2]=[]
					for side in 3:
						var ak: Vector2i=corners[triangle[side]]
						var bk: Vector2i=corners[triangle[(side+1)%3]]
						var av:=Vector2(ak)*0.125
						var bv:=Vector2(bk)*0.125
						var am: float=masks[ak]
						var bm: float=masks[bk]
						if am<=0:polygon.append(av)
						if (am>0)!=(bm>0):
							var cut:=av.lerp(bv,clampf(am/(am-bm),0,1))
							polygon.append(cut)
							boundary.append(cut)
					for i in range(1,polygon.size()-1):
						_soil_triangle(top,dirt,[polygon[0],polygon[i],polygon[i+1]])
					if boundary.size()==2:_soil_lip(dirt,boundary[0],boundary[1])
	dirt.generate_normals()
	top.generate_normals()
	_soil.cull_mode=BaseMaterial3D.CULL_DISABLED
	dirt.set_material(_soil)
	var ground:=StandardMaterial3D.new()
	if _visuals:ground.albedo_texture=load("res://game/maps/forest_ridge/art/ground/forest_ground_04_diff_1k.jpg")
	ground.albedo_color=Color(0.72,0.75,0.68)
	ground.roughness=1.0
	ground.uv1_triplanar=true
	ground.uv1_world_triplanar=true
	ground.uv1_scale=Vector3.ONE*0.39
	top.set_material(ground)
	var mesh:=top.commit()
	dirt.commit(mesh)
	_mesh_body("ExcavationEdges",mesh)

static func _cut_mask(p: Vector2) -> float:
	var nearest:=_nearest_tunnel(p)
	return minf(1.55-nearest.distance,float(nearest.floor)+3.3-height_at(p))

func _soil_triangle(top: SurfaceTool,dirt: SurfaceTool,points: Array) -> void:
	var vertices: Array[Vector4]=[]
	var exposed:=false
	for p: Vector2 in points:
		var v:=_dug_vertex(p)
		vertices.append(v)
		if v.w>0.015:exposed=true
	var target:=dirt if exposed else top
	for v in vertices:
		var tint:=lerpf(0.98,0.68,smoothstep(0.05,1.275,v.w))+0.04*sin(v.y*27+v.x*4+v.z*2)
		target.set_color(Color(tint,tint,tint) if exposed else Color.WHITE)
		target.add_vertex(Vector3(v.x,v.y,v.z))

func _soil_lip(tool: SurfaceTool,ap: Vector2,bp: Vector2) -> void:
	var av:=_dug_vertex(ap)
	var bv:=_dug_vertex(bp)
	var a:=Vector3(av.x,av.y,av.z)
	var b:=Vector3(bv.x,bv.y,bv.z)
	var ab:=a
	var bb:=b
	var an:=_nearest_tunnel(ap)
	var bn:=_nearest_tunnel(bp)
	ab.y=minf(a.y-0.20,float(an.floor)+(-0.08 if an.distance>1.4 else 2.35))
	bb.y=minf(b.y-0.20,float(bn.floor)+(-0.08 if bn.distance>1.4 else 2.35))
	for point: Vector3 in [a,b,bb,a,bb,ab]:
		tool.set_color(Color(0.74,0.74,0.74))
		tool.add_vertex(point)

static func _dug_vertex(p: Vector2) -> Vector4:
	var nearest:=_nearest_tunnel(p)
	var ground:=height_at(p)
	var depth: float=ground-nearest.floor
	var cut:=0.0
	if depth<3.5 and nearest.distance<2.85:
		var wobble:=0.035*sin(p.x*6.9+p.y*5.1)*cos(p.y*6.2-p.x*3.4)
		var inward:=maxf(0,2.75+wobble-nearest.distance)
		var lip:=minf(0.095,maxf(0,depth)*0.2)*smoothstep(0,0.16,inward)
		var wall:=maxf(0,depth-lip)*smoothstep(0.20,1.16,inward)
		cut=(lip+wall)*(1.0-smoothstep(2.2,3.5,depth))
		cut+=0.035*sin(p.x*12.7+p.y*6.3)*cos(p.y*9.3-p.x*4.6)*sin(PI*clampf(cut/maxf(0.01,depth),0,1))
	return Vector4(p.x,ground-cut+0.008,p.y,cut)

static func _nearest_tunnel(p: Vector2) -> Dictionary:
	if _paths.is_empty():paths()
	var nearest := INF
	var result := {"floor":0.0,"direction":Vector2.RIGHT,"distance":INF}
	for segment: Array in _tunnel_cells.get(Vector2i(floori(p.x/4.0),floori(p.y/4.0)),[]):
		var a: Vector3=segment[0]
		var b: Vector3=segment[1]
		var av:=Vector2(a.x,a.z)
		var bv:=Vector2(b.x,b.z)
		var t:=clampf((p-av).dot(bv-av)/av.distance_squared_to(bv),0,1)
		var distance:=p.distance_squared_to(av.lerp(bv,t))
		if distance<nearest:
			nearest=distance
			result={"floor":lerpf(a.y,b.y,t),"direction":(bv-av).normalized(),"distance":sqrt(distance)}
	return result

static func _paint(p: Vector2) -> Vector4:
	var gradient:=Vector2(height_at(p+Vector2(0.25,0))-height_at(p-Vector2(0.25,0)),height_at(p+Vector2(0,0.25))-height_at(p-Vector2(0,0.25))).length()*2.0
	var distance:=minf(absf(p.length()-27.0),absf(p.length()-20.5))
	for tier in 3:
		for arm in 4:
			var forward: Vector2=RAMPS[tier][arm]
			var a: Vector2=forward*float([42.0,30.0,22.0][tier])
			var b: Vector2=forward*float([28.0,16.0,0.0][tier])
			distance=minf(distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,b)))
	# Winding approach forks lead to separate land and underground choices.
	for side in [-1.0,1.0]:
		for path: Array in APPROACHES:
			for i in range(path.size()-1):
				distance=minf(distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,path[i]*side,path[i+1]*side)))
	var trail:=1.0-smoothstep(1.6,3.3,distance)
	return Vector4(0,1,maxf(trail*0.85,smoothstep(0.7,1.6,gradient)),1)

func _mesh_body(title: String, mesh: ArrayMesh) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = title
	body.set_meta(&"impact_surface","brick")
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	collision.shape.backface_collision = true
	body.add_child(collision)
	if _visuals:
		var visual := MeshInstance3D.new()
		visual.name = "Visual"
		visual.mesh = mesh
		body.add_child(visual)
	_root.add_child(body)
	return body

func _tunnel(index: int, path: Array) -> void:
	# Aprons span the rounded terrain cut at both mouths so there is no floor gap.
	var authored := path
	path = path.duplicate()
	var first_dir: Vector3 = authored[0] - authored[1]
	first_dir.y = 0
	var last_dir: Vector3 = authored[-1] - authored[-2]
	last_dir.y = 0
	path.push_front(authored[0] + first_dir.normalized() * 2.2)
	path.append(authored[-1] + last_dir.normalized() * 2.2)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var section := [Vector2(-1.8,0),Vector2(-1.8,2.1),Vector2(-1.2,2.85),Vector2(0,3.15),Vector2(1.2,2.85),Vector2(1.8,2.1),Vector2(1.8,0)]
	var floor_tool := SurfaceTool.new()
	floor_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for i in path.size():
		var before: Vector3 = path[maxi(i-1,0)]
		var after: Vector3 = path[mini(i+1,path.size()-1)]
		var direction := (after-before).normalized()
		var right := Vector3(-direction.z,0,direction.x).normalized()
		var ring := PackedVector3Array()
		for v: Vector2 in section:ring.append(path[i]+right*v.x+Vector3.UP*v.y)
		rings.append(ring)
	for i in range(rings.size()-1):
		# Split the sloping floor at its centreline to avoid twisted wide quads.
		for half in 2:
			var left: Vector3 = rings[i][0] if half==0 else path[i]
			var right: Vector3 = path[i] if half==0 else rings[i][6]
			var next_left: Vector3 = rings[i+1][0] if half==0 else path[i+1]
			var next_right: Vector3 = path[i+1] if half==0 else rings[i+1][6]
			for triangle: Array in [[left,next_left,next_right],[left,next_right,right]]:
				# A complete slightly raised floor closes partial triangles at the soil lip.
				for point: Vector3 in triangle:floor_tool.add_vertex(point+Vector3.UP*0.02)
		for side in 6:
			var next := side+1
			var points: Array[Vector3] = [rings[i][side],rings[i+1][next],rings[i+1][side],rings[i][side],rings[i][next],rings[i+1][next]]
			if side in [0,5]:
				# Retaining walls end flush with terrain beside the open exit stairs.
				for j in points.size():points[j].y=minf(points[j].y,height_at(Vector2(points[j].x,points[j].z))+0.03)
			else:
				var buried := true
				for point in points:
					if point.y>height_at(Vector2(point.x,point.z))-0.08:buried=false
				if not buried:continue
			for triangle in 2:
				var a: Vector3=points[triangle*3]
				var b: Vector3=points[triangle*3+1]
				var c: Vector3=points[triangle*3+2]
				if (b-a).cross(c-a).length_squared()<0.000001:continue
				for point: Vector3 in [a,b,c]:tool.add_vertex(point)
	tool.generate_normals()
	tool.set_material(_stone)
	var body := _mesh_body("Tunnel%d"%index,tool.commit())
	body.add_to_group(&"hill_tunnel")
	# Exclude the arch from navigation: its exterior is buried in solid terrain.
	# The full-height passage floor is baked separately; physics retains the arch.
	body.add_to_group(&"buried_tunnel_arch")
	floor_tool.generate_normals()
	floor_tool.set_material(_stone)
	_mesh_body("TunnelFloor%d"%index,floor_tool.commit())
	for end in [0,path.size()-1]:
		var point: Vector3 = authored[0 if end==0 else -1]
		var other: Vector3 = authored[1 if end==0 else -2]
		var forward := (point-other).normalized()
		var right := Vector3(-forward.z,0,forward.x).normalized()
		for side in [-1.0,1.0]:
			_rock(point+right*side*2.8,Vector3(2.2,3.0 if end==0 else 1.4,3.0),index+end)
		if end==0:_rock(point+Vector3.UP*2.3,Vector3(5.6,2.3,4.0),index+end,false)
		# Offset cover protects the mouth without sealing the approach.
		var cover_at := point+forward*3.8+right*3.3
		if _nearest_tunnel(Vector2(cover_at.x,cover_at.z)).distance>3.4:
			_rock(cover_at,Vector3(2.0,1.5,1.8),index)
		if _visuals:
			var label := Label3D.new()
			label.text = "%s · %s" % ["AБВГ"[index],"ВХОД" if end==0 else "ВЫХОД"]
			label.font_size = 22
			label.pixel_size = 0.005
			label.position = point+right*2.0+Vector3.UP*1.3
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_root.add_child(label)

func _box(title: String, at: Vector3, size: Vector3, material: Material) -> StaticBody3D:
	var body: StaticBody3D = _map._add_box(at,size,material,0,"brick")
	body.name = title
	return body

func _rock(at: Vector3, size: Vector3, variant: int, grounded := true) -> StaticBody3D:
	if grounded:at.y=minf(at.y,height_at(Vector2(at.x,at.z)))
	var index:=variant%_rocks.size()
	var mesh:=_rocks[index]
	var bounds:=mesh.get_aabb()
	var scale:=size/bounds.size
	var fit:=Transform3D(Basis.from_scale(scale),-bounds.get_center()*scale)
	var body:=StaticBody3D.new()
	body.name="RockCover"
	body.position=at+Vector3.UP*size.y*0.5
	body.set_meta(&"impact_surface","brick")
	body.set_meta(&"rock_variant",index)
	body.set_meta(&"rock_size",size)
	body.add_to_group(&"hill_rock")
	# Bake the visible mesh fit into vertices, avoiding scaled physics shapes and
	# the empty corners/ledges introduced by the old bounding-box collider.
	var key: String="%d:%s"%[index,size]
	if not _rock_collisions.has(key):
		var faces:=mesh.get_faces()
		for i in faces.size():faces[i]=fit*faces[i]
		var collision:=ConcavePolygonShape3D.new()
		collision.set_faces(faces)
		collision.backface_collision=true
		_rock_collisions[key]=collision
	var collider:=CollisionShape3D.new()
	collider.shape=_rock_collisions[key]
	body.add_child(collider)
	if _visuals:
		var visual:=MeshInstance3D.new()
		visual.mesh=mesh
		visual.transform=fit
		body.add_child(visual)
	_map.add_child(body)
	return body

func _summit() -> void:
	# Waist-high stone breastworks with gaps facing each surface approach.
	for sx in [-1.0,1.0]:
		for sz in [-1.0,1.0]:
			if sx != sz:continue
			for axis in 2:
				for block in 4:
					var offset := (block-1.5)*0.75
					var center := Vector3(sx*5.2+offset,SUMMIT,sz*6.5) if axis==0 else Vector3(sx*6.5,SUMMIT,sz*5.2+offset)
					var rock := _rock(center,Vector3(1.3,FENCE_HEIGHT,1.0) if axis==0 else Vector3(1.0,FENCE_HEIGHT,1.3),block+axis)
					rock.add_to_group(&"hill_cover")

func _bases() -> void:
	for pool: Array in placement().s:
		for p: Array in pool:
			var at := Vector3(p[0],p[1]+0.18,p[2])
			_map._initial_spawns.append(at)
			_map.respawn_points.append(at)
			_map._patrol.append(at)
	for p in [Vector2(-30,-22),Vector2(30,22),Vector2(-18,18),Vector2(18,-18),Vector2.ZERO]:
		_map._patrol.append(Vector3(p.x,height_at(p),p.y))

func _perimeter() -> void:
	for side in [-1.0,1.0]:
		for body in [_box("Boundary",Vector3(side*50.25,8,0),Vector3(0.5,20,100.5),_stone),_box("Boundary",Vector3(0,8,side*50.25),Vector3(100.5,20,0.5),_stone)]:
			for child in body.get_children():
				if child is MeshInstance3D:child.hide()

func _forest() -> void:
	var trees: Array[Mesh] = []
	if _visuals:
		var tree_rng := RandomNumberGenerator.new()
		tree_rng.seed = 8941
		trees = FIRS.build(tree_rng)
	var batches: Array[Array] = [[],[],[]]
	# Mirror collision-bearing trees so both opening routes have equal cover.
	for attempt in 375:
		var p:=Vector2(_rng.randf_range(-48,0),_rng.randf_range(-48,48))
		if p.length()<3.5 or _nearest_tunnel(p).distance<3.8 or _paint(p).z>0.40:continue
		var clear:=true
		for q: Vector2 in [p,-p]:
			for point: Vector2 in SUPPLIES:
				if point.distance_to(q)<3.0:clear=false
			for pool: Array in placement().s:
				for point: Array in pool:
					if q.distance_to(Vector2(point[0],point[2]))<4.0:clear=false
		if not clear:continue
		var y:=height_at(p)
		if absf(y-roundf(y/4)*4)>0.05:continue
		var h:=_rng.randf_range(7.0,12.0)
		var yaw:=_rng.randf()*TAU
		for side in [-1.0,1.0]:
			var q: Vector2=p*side
			var trunk:=StaticBody3D.new()
			trunk.position=Vector3(q.x,y+2.5,q.y)
			trunk.set_meta(&"impact_surface","wood")
			var collider:=CollisionShape3D.new()
			var cylinder:=CylinderShape3D.new()
			cylinder.radius=0.22
			cylinder.height=5.0
			collider.shape=cylinder
			trunk.add_child(collider)
			_root.add_child(trunk)
			batches[attempt%3].append(Transform3D(Basis(Vector3.UP,yaw+(PI if side<0 else 0)).scaled(Vector3(h*0.7,h,h*0.7)),Vector3(q.x,y,q.y)))
	if not _visuals:return
	for i in 3:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = trees[i]
		multi.instance_count = batches[i].size()
		for j in batches[i].size():multi.set_instance_transform(j,batches[i][j])
		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		_root.add_child(node)
	_backdrop(trees)
	var grass: Array[Transform3D] = []
	var grass_rng := RandomNumberGenerator.new()
	grass_rng.seed = 33918
	var steps := floori(48.0/_map.TERRAIN_GRASS.LAWN_SPACING)
	for x in range(-steps,steps+1):
		for z in range(-steps,steps+1):
			var p: Vector2 = Vector2(x,z)*_map.TERRAIN_GRASS.LAWN_SPACING+Vector2(grass_rng.randf_range(-0.035,0.035),grass_rng.randf_range(-0.035,0.035))
			if _nearest_tunnel(p).distance<3.8 or _paint(p).z>0.55:continue
			grass.append(Transform3D(Basis.IDENTITY,Vector3(p.x,height_at(p),p.y)))
	_map.TERRAIN_GRASS.queue(_root,grass)

func _backdrop(trees: Array[Mesh]) -> void:
	var earth := StandardMaterial3D.new()
	earth.albedo_texture = load("res://game/maps/forest_ridge/art/ground/forest_ground_04_diff_1k.jpg")
	earth.albedo_color = Color(0.68,0.90,0.52)
	earth.uv1_scale = Vector3(120,120,1)
	earth.roughness = 1.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(500,500)
	var horizon := MeshInstance3D.new()
	horizon.mesh = plane
	horizon.material_override = earth
	horizon.position.y = -1.6
	_root.add_child(horizon)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = trees[0]
	multi.instance_count = 100
	for i in 100:
		var angle := i * TAU/100
		var radius := _rng.randf_range(53,72)
		var h := _rng.randf_range(11,18)
		multi.set_instance_transform(i,Transform3D(Basis(Vector3.UP,angle).scaled(Vector3(h*0.7,h,h*0.7)),Vector3(cos(angle)*radius,-1.6,sin(angle)*radius)))
	var tree_ring := MultiMeshInstance3D.new()
	tree_ring.multimesh = multi
	_root.add_child(tree_ring)
	# Continuous distant ridgeline instead of isolated oversized boulders.
	var ridges := SurfaceTool.new()
	ridges.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for band in 4:
		var ring := PackedVector3Array()
		for i in 65:
			var angle := (i%64)*TAU/64
			var radius: float = [70,108,166,235][band]
			var peak := 27.0+12.0*sin(angle*5.0)+7.0*cos(angle*9.0)
			var y: float = [-1.8,peak,peak*0.45,-2.0][band]
			ring.append(Vector3(cos(angle)*radius,y,sin(angle)*radius))
		rings.append(ring)
	for band in 3:
		for i in 64:
			for point: Vector3 in [rings[band][i],rings[band][i+1],rings[band+1][i+1],rings[band][i],rings[band+1][i+1],rings[band+1][i]]:
				ridges.set_uv(Vector2(point.x,point.z)*0.12)
				ridges.add_vertex(point)
	ridges.generate_normals()
	var rock := StandardMaterial3D.new()
	rock.albedo_texture=load("res://game/maps/forest_ridge/art/ground/rocky_trail_diff_1k.jpg")
	rock.albedo_color=Color(0.65,0.68,0.63)
	rock.roughness=1.0
	rock.cull_mode=BaseMaterial3D.CULL_DISABLED
	ridges.set_material(rock)
	var mountains := MeshInstance3D.new()
	mountains.mesh=ridges.commit()
	_root.add_child(mountains)
