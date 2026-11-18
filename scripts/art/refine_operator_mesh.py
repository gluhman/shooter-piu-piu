"""Smooth the adapted garment surfaces while retaining UVs and native skin groups.
Run in Blender, after rig_operator_mesh2motion.mjs and before kit authoring.
"""
import bpy, bmesh, json, sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_operator_variants import GLB

def refine(data):
 if data.get('surface_refined'):return
 # Both teams share geometry: refine once, then reuse the result with their materials.
 source=GLB('/tmp/piupiu-operator-input/operator_blue.glb')
 for part in data['variants']['blue']:
  if part['name'] in ['OperatorEyes','Object_101','Object_117']:continue
  primitive=source.g['meshes'][part['mesh']]['primitives'][part['primitive']]
  attrs=primitive['attributes'];uv=source.read_accessor(attrs['TEXCOORD_0'])
  ids=[x[0] for x in source.read_accessor(primitive['indices'])]
  pts=[part['positions'][i:i+3] for i in range(0,len(part['positions']),3)]
  me=bpy.data.meshes.new(part['name']);me.from_pydata(pts,[],[ids[i:i+3] for i in range(0,len(ids),3)]);me.update()
  obj=bpy.data.objects.new(part['name'],me);bpy.context.collection.objects.link(obj)
  for b in data['bones']:obj.vertex_groups.new(name=b['name'])
  for i in range(len(pts)):
   for j in range(4):
    w=part['weights'][i*4+j]
    if w>0:obj.vertex_groups[part['indices'][i*4+j]].add([i],w,'REPLACE')
  layer=me.uv_layers.new(name='UVMap')
  for loop in me.loops:layer.data[loop.index].uv=uv[loop.vertex_index]
  bm=bmesh.new();bm.from_mesh(me);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
  for f in bm.faces:f.smooth=True
  bm.to_mesh(me);bm.free();me.update()
  sub=obj.modifiers.new('Garment curvature','SUBSURF');sub.levels=1;sub.render_levels=1
  sub.uv_smooth='PRESERVE_BOUNDARIES';sub.boundary_smooth='PRESERVE_CORNERS'
  bpy.context.view_layer.update();ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());out=ev.to_mesh();out.calc_loop_triangles()
  new={k:[] for k in ['positions','normals','indices','weights','uv','triangles']}
  for tri in out.loop_triangles:
   for li in tri.loops:
    vi=out.loops[li].vertex_index;v=out.vertices[vi]
    new['triangles'].append(len(new['uv']));new['positions'].extend(v.co);new['normals'].extend(out.corner_normals[li].vector)
    new['uv'].append(list(out.uv_layers.active.data[li].uv))
    weights=sorted([(g.group,g.weight) for g in v.groups if g.weight>.00001],key=lambda a:-a[1])[:4]
    total=sum(w for _,w in weights)
    new['indices'].extend([g for g,w in weights]+[0]*(4-len(weights)))
    new['weights'].extend([w/total for g,w in weights]+[0.]*(4-len(weights)))
  for variant in ['blue','red']:
   target=next(m for m in data['variants'][variant] if m['name']==part['name']);target.update(new)
  ev.to_mesh_clear();bpy.data.objects.remove(obj,do_unlink=True)
  print('Refined',part['name'],len(new['uv'])//3,'triangles')
 data['surface_refined']=True

if __name__=='__main__':
 p=Path('/tmp/piupiu-m2m-native.json');data=json.loads(p.read_text());refine(data);p.write_text(json.dumps(data))
