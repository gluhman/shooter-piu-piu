extends RefCounted
## Closed, inward-chamfered box; dimensions never exceed the source collision box.
static func build(size: Vector3) -> ArrayMesh:
	var half:=size*0.5
	var bevel:=minf(0.035,minf(size.x,minf(size.y,size.z))*0.12)
	var tool:=SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in 3:
		var u: int=(axis+1)%3
		var v: int=(axis+2)%3
		for sign_value in [-1.0,1.0]:
			var normal:=Vector3.ZERO
			normal[axis]=sign_value
			var points: Array[Vector3]=[]
			for corner: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
				var p:=Vector3.ZERO
				p[axis]=half[axis]*sign_value
				p[u]=(half[u]-bevel)*corner.x
				p[v]=(half[v]-bevel)*corner.y
				points.append(p)
			face(tool,points,normal,1.0)
	for a in 3:
		for b in range(a+1,3):
			var c:=3-a-b
			for sa in [-1.0,1.0]:
				for sb in [-1.0,1.0]:
					var points: Array[Vector3]=[]
					for edge: Vector2 in [Vector2(0,-1),Vector2(1,-1),Vector2(1,1),Vector2(0,1)]:
						var p:=Vector3.ZERO
						p[a]=(half[a]-(bevel if edge.x==0 else 0.0))*sa
						p[b]=(half[b]-(bevel if edge.x==1 else 0.0))*sb
						p[c]=(half[c]-bevel)*edge.y
						points.append(p)
					var normal:=Vector3.ZERO
					normal[a]=sa
					normal[b]=sb
					face(tool,points,normal.normalized(),0.35)
	for sx in [-1.0,1.0]:
		for sy in [-1.0,1.0]:
			for sz in [-1.0,1.0]:
				var signs:=Vector3(sx,sy,sz)
				var points: Array[Vector3]=[]
				for axis in 3:
					var p: Vector3=(half-Vector3.ONE*bevel)*signs
					p[axis]=half[axis]*signs[axis]
					points.append(p)
				face(tool,points,signs.normalized(),0.35)
	return tool.commit()
static func face(tool: SurfaceTool,points: Array[Vector3],normal: Vector3,wear: float) -> void:
	if (points[1]-points[0]).cross(points[2]-points[0]).dot(normal)>0:points.reverse()
	for i in range(1,points.size()-1):
		for index in [0,i,i+1]:
			tool.set_normal(normal)
			tool.set_color(Color(wear,1,1,1))
			tool.add_vertex(points[index])
