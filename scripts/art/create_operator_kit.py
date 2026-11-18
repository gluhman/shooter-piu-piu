"""Author fitted tactical kit in Blender. Outputs a mesh manifest for GLB assembly.
Blender --background --factory-startup --python scripts/art/create_operator_kit.py
Dimensions use the native Mesh2Motion bind frame; the skeleton is never changed.
"""
import bpy, math, json, sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from mathutils import Vector
from collections import defaultdict
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
HEAD='head'; CHEST='spine_02'; HIPS='pelvis'
materials={}
def material(name,color,rough=.7,metal=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1);bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
 materials[name]={'name':name,'pbrMetallicRoughness':{'baseColorFactor':[*color,1],'metallicFactor':metal,'roughnessFactor':rough}}
 return m
M={}
for key,c,r,metal in [('shell',(.006,.009,.012),.86,0),('rubber',(.004,.006,.008),.88,0),('steel',(.045,.052,.058),.62,.45),('lens',(.003,.008,.020),.18,.12),('optic',(.008,.035,.028),.22,.25),('nylon',(.014,.019,.025),.93,0),('sand',(.075,.06,.035),.95,0),('stitch',(.10,.09,.065),.96,0),('scarf',(.075,.070,.055),.96,0),('scarf_dark',(.09,.105,.098),.96,0),('scarf_light',(.43,.42,.35),.96,0),('id_blue',(.035,.21,.48),.83,0),('id_red',(.45,.045,.035),.85,0),('white',(.72,.77,.74),.75,0)]:M[key]=material('Kit_'+key,c,r,metal)
objects=[]
def finish(o,name,mat,bone=HEAD,variant='both'):
 o.name=name;o.data.materials.clear();o.data.materials.append(M[mat]);o['bone']=bone;o['variant']=variant;o['mat']=M[mat].name;objects.append(o)
 return o
def box(name,p,size,mat,bone=HEAD,variant='both',bevel=.003,rot=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.scale=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if rot:o.rotation_euler=rot
 if bevel:
  mod=o.modifiers.new('Rounded manufactured edges','BEVEL');mod.width=bevel;mod.segments=3
  mod=o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
 return finish(o,name,mat,bone,variant)
def sphere(name,p,scale,mat,bone=HEAD,variant='both',segments=24):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=12,radius=1,location=p);o=bpy.context.object;o.scale=scale
 for f in o.data.polygons:f.use_smooth=True
 return finish(o,name,mat,bone,variant)
def tube(name,points,r,mat,bone=HEAD,variant='both'):
 cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.resolution_u=3;cu.bevel_depth=r;cu.bevel_resolution=2
 sp=cu.splines.new('POLY');sp.points.add(len(points)-1)
 for p,v in zip(sp.points,points):p.co=(*v,1)
 ob=bpy.data.objects.new(name,cu);bpy.context.collection.objects.link(ob);bpy.context.view_layer.objects.active=ob;ob.select_set(True);bpy.ops.object.convert(target='MESH');ob.select_set(False)
 return finish(ob,name,mat,bone,variant)
def cylinder(name,p,r,depth,mat,bone=HEAD,variant='both',direction=(0,0,1)):
 bpy.ops.mesh.primitive_cylinder_add(vertices=24,radius=r,depth=depth,location=p);o=bpy.context.object;o.rotation_euler=Vector(direction).to_track_quat('Z','Y').to_euler()
 bevel=o.modifiers.new('Edge chamfer','BEVEL');bevel.width=.0012;bevel.segments=2
 for f in o.data.polygons:f.use_smooth=True
 return finish(o,name,mat,bone,variant)
def mesh(name,verts,faces,mat,bone=HEAD,variant='both'):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o)
 for f in me.polygons:f.use_smooth=True
 return finish(o,name,mat,bone,variant)
# Fit chest accessories to the actual repaired vest, including its skin weights.
from pathlib import Path
from mathutils.bvhtree import BVHTree
native=json.loads(Path('/tmp/piupiu-m2m-native.json').read_text())
vest=next(m for m in native['variants']['blue'] if m['name']=='Object_105')
verts=[Vector(vest['positions'][i:i+3]) for i in range(0,len(vest['positions']),3)]
faces=[vest['triangles'][i:i+3] for i in range(0,len(vest['triangles']),3)]
bvh=BVHTree.FromPolygons(verts,faces,all_triangles=True)
def vest_hit(x,h):
 p,n,index,d=bvh.ray_cast(Vector((x,h,1)),Vector((0,0,-1)))
 if p is None:p,n,index,d=bvh.find_nearest(Vector((x,h,.18)))
 return p,index

def chest_box(name,x,h,size,mat,var,offset=0):
 p,_=vest_hit(x,h)
 return box(name,(x,-p.z-size[1]/2-offset,h),size,mat,CHEST,var,bevel=min(.004,min(size)/3))

# Helmet: compact shell fitted over the balaclava, raised ear cut and rubber binding.
cx,cy,cz=0,-.018,1.704
verts_h=[];faces_h=[];rings=16;segs=64
for j in range(rings+1):
 t=j/rings*math.pi/2
 for i in range(segs):
  a=i/segs*math.tau
  cut=.021*abs(math.cos(a))**6
  verts_h.append((.114*math.sin(t)*math.cos(a),cy+.135*math.sin(t)*math.sin(a),cz+.102*math.cos(t)+cut*math.sin(t)))
for j in range(rings):
 for i in range(segs):faces_h.append((j*segs+i,j*segs+(i+1)%segs,(j+1)*segs+(i+1)%segs,(j+1)*segs+i))
o=mesh('Helmet_shell',verts_h,faces_h,'shell',variant='blue');o.modifiers.new('Shell thickness','SOLIDIFY').thickness=.006
rim=verts_h[rings*segs:]+[verts_h[rings*segs]];tube('Helmet_binding',rim,.0045,'rubber',variant='blue')
for side in [-1,1]:
 x=side*.111
 box('Helmet_rail',(x,cy+.008,1.733),(.012,.105,.022),'rubber',variant='blue',bevel=.005)
 for k in range(5):box('Rail_slot',(x+side*.007,cy-.030+k*.018,1.734),(.003,.009,.012),'steel',variant='blue',bevel=.001)
 for y in [cy-.035,cy+.048]:cylinder('Rail_screw',(x+side*.009,y,1.733),.003,.003,'steel',variant='blue',direction=(1,0,0))
 box('Helmet_patch',(side*.058,cy+.005,1.791),(.035,.065,.004),'nylon',variant='blue',bevel=.004,rot=(0,side*.25,0))
 # Helmet-retained straps connect to the earcup instead of floating beside it.
 tube('Ear_support',[(side*.11,.018,1.737),(side*.112,.025,1.685),(side*.105,-.006,1.66)],.003,'steel',variant='blue')
box('NVG_shroud',(0,-.151,1.738),(.050,.012,.052),'shell',variant='blue',bevel=.008)
box('NVG_plate',(0,-.159,1.738),(.028,.004,.032),'steel',variant='blue',bevel=.004)
for x in [-.018,.018]:cylinder('Shroud_bolt',(x,-.16,1.752),.0025,.004,'steel',variant='blue',direction=(0,1,0))
box('NVG_hinge_arm',(0,-.14,1.782),(.022,.027,.039),'shell',variant='blue')
cylinder('NVG_hinge',(0,-.14,1.8),.011,.043,'steel',variant='blue',direction=(1,0,0))
cylinder('Folded_monocular',(0,-.118,1.818),.021,.062,'rubber',variant='blue',direction=(0,1,.35))
cylinder('Optic_rim',(0,-.15,1.806),.022,.006,'steel',variant='blue',direction=(0,1,.35))
cylinder('Optic_glass',(0,-.154,1.804),.016,.002,'optic',variant='blue',direction=(0,1,.35))
# Blue: a continuous curved ballistic goggle with a broad gasket and head strap.
def goggle(name,width,height,depth,mat):
 v=[];f=[];cols=32;rows=8
 for j in range(rows+1):
  b=j/rows*2-1
  for i in range(cols+1):
   a=i/cols*2-1;x=a*width/2
   # The lower bridge rises over the nose; the outer lens wraps to the temples.
   h=1.656+b*height/2+(max(0,-b)*.010*math.exp(-(a/.24)**2))
   z=.165-.036*a*a+depth
   v.append((x,-z,h))
 for j in range(rows):
  for i in range(cols):
   k=j*(cols+1)+i;f.append((k,k+1,k+cols+2,k+cols+1))
 o=mesh(name,v,f,mat,variant='blue');o.modifiers.new('Lens thickness','SOLIDIFY').thickness=.003
 return o
goggle('Goggle_gasket',.205,.074,-.003,'rubber')
goggle('Goggle_shell',.192,.063,.001,'shell')
goggle('Goggle_lens',.175,.047,.005,'lens')
for side in [-1,1]:
 tube('Goggle_retainer',[(side*.095,-.127,1.657),(side*.099,-.035,1.66),(side*.09,.06,1.664),(side*.06,.099,1.665)],.010,'nylon',variant='blue')
 box('Goggle_adjuster',(side*.098,-.056,1.662),(.009,.025,.025),'rubber',variant='blue',bevel=.003)
# Red: a sewn six-panel baseball cap. The brim is ABOVE the separate eyewear.
v=[];f=[];rows=12;cols=60
for j in range(rows+1):
 t=j/rows*math.pi/2
 for i in range(cols):
  a=i/cols*math.tau;v.append((.098*math.sin(t)*math.cos(a),-.018+.119*math.sin(t)*math.sin(a),1.703+.077*math.cos(t)))
for j in range(rows):
 for i in range(cols):f.append((j*cols+i,j*cols+(i+1)%cols,(j+1)*cols+(i+1)%cols,(j+1)*cols+i))
o=mesh('Cap_crown',v,f,'sand',variant='red');o.modifiers.new('Cloth thickness','SOLIDIFY').thickness=.002
for panel in range(6):
 a=panel/6*math.tau
 tube('Cap_seam',[(.099*math.sin(t)*math.cos(a),-.018+.120*math.sin(t)*math.sin(a),1.704+.077*math.cos(t)) for t in [k/20*math.pi/2 for k in range(21)]],.0008,'stitch',variant='red')
sphere('Cap_button',(0,-.018,1.782),(.006,.006,.003),'sand',variant='red')
v=[];f=[]
for j in range(9):
 t=j/8
 for i in range(33):
  a=i/32*2-1;v.append((a*(.083+.022*t),-.105-t*(.116-.025*a*a),1.705-.013*a*a-.006*t))
for j in range(8):
 for i in range(32):
  k=j*33+i;f.append((k,k+1,k+34,k+33))
o=mesh('Cap_brim',v,f,'sand',variant='red');o.modifiers.new('Brim thickness','SOLIDIFY').thickness=.004
for t in [.68,.86,.98]:tube('Brim_stitch',[(a*(.083+.022*t),-.105-t*(.116-.025*a*a),1.707-.013*a*a-.006*t) for a in [k/40*2-1 for k in range(41)]],.00065,'stitch',variant='red')
for side in [-1,1]:
 x=side*.043
 box('Eyewear_frame',(x,-.154,1.649),(.082,.013,.038),'rubber',variant='red',bevel=.012,rot=(0,0,side*.16))
 box('Eyewear_lens',(x,-.162,1.65),(.069,.005,.026),'lens',variant='red',bevel=.010,rot=(0,0,side*.16))
 tube('Eyewear_arm',[(side*.08,-.151,1.659),(side*.094,-.066,1.66),(side*.09,-.013,1.647)],.003,'rubber',variant='red')
box('Eyewear_bridge',(0,-.163,1.657),(.020,.008,.008),'rubber',variant='red',bevel=.003)
# Headsets touch the sides of the head. A padded band connects the red earcups.
for side in [-1,1]:
 sphere('Ear_cushion',(side*.091,-.022,1.63),(.014,.042,.048),'rubber')
 sphere('Ear_cup',(side*.106,-.022,1.63),(.016,.036,.042),'shell')
 box('Ear_yoke',(side*.116,-.019,1.674),(.008,.013,.025),'steel',bevel=.003)
 for h in [1.607,1.652]:cylinder('Ear_screw',(side*.122,-.021,h),.002,.003,'steel',direction=(1,0,0))
tube('Headset_band',[(.110*math.cos(a),.012,1.65+.137*math.sin(a)) for a in [k/48*math.pi for k in range(49)]],.006,'rubber',variant='red')
tube('Mic_boom',[(.115,-.02,1.612),(.11,-.09,1.591),(.068,-.152,1.58),(.024,-.158,1.579)],.003,'steel')
sphere('Mic_foam',(.017,-.158,1.579),(.017,.009,.008),'rubber')
# A flexible neck gaiter/collar visually joins the mask to the shoulders.
for var,mat in [('blue','nylon'),('red','scarf')]:
 for layer in range(3 if var=='red' else 2):
  points=[]
  for k in range(65):
   a=k/64*math.tau
   points.append(((.097+layer*.008)*math.cos(a),.002+(.126+layer*.004)*math.sin(a),1.478-layer*.018+.006*math.sin(3*a)))
  tube('Neck_collar',points,.012,mat,'neck_01',var)
# One continuous scarf surface, with fine woven shading instead of checkerboard blocks.
v=[];f=[]
for j in range(25):
 t=j/24
 for i in range(33):
  a=i/32*2-1;h=1.464-t*.205+(.012*a*a)
  x=a*(.126-.063*t);p,_=vest_hit(x,h)
  front=max(p.z+.025,.15)+.004*math.cos(a*math.pi*5)+.012*math.sin(t*math.pi)
  v.append((x,-front,h))
for j in range(24):
 for i in range(32):
  k=j*33+i;f.append((k,k+1,k+34,k+33))
o=mesh('Scarf_drape',v,f,'scarf',CHEST,'red');o.modifiers.new('Woven thickness','SOLIDIFY').thickness=.002
for i in range(21):
 x=(i/20*2-1)*.064;p,_=vest_hit(x,1.267)
 tube('Scarf_fringe',[(x,-p.z-.019,1.266),(x+.002,-p.z-.020,1.251)],.0009,'scarf',CHEST,'red')
# Sewn chest webbing and pouches sit on the vest instead of near the throat.
for var,cloth in [('blue','nylon'),('red','sand')]:
 for row in range(4):
  for col in range(5):
   x=(col-2)*.043;h=1.205+row*.028
   chest_box('MOLLE_loop',x,h,(.038,.005,.014),cloth,var)
   p,_=vest_hit(x,h)
   for dx in [-.016,.016]:tube('Bar_tack',[(x+dx,-p.z-.006,h-.004),(x+dx,-p.z-.006,h+.004)],.0006,'stitch',CHEST,var)
 patch_x=-.072 if var=='red' else 0
 chest_box('Chest_ID_backing',patch_x,1.365,(.087,.005,.032),'rubber',var)
 chest_box('Chest_ID',patch_x,1.365,(.079,.002,.024),'id_'+var,var,.006)
 for k in range(3):chest_box('ID_bar',patch_x+(k-1)*.018,1.365,(.005,.002,.014),'white',var,.008)
 for side in [-1,1]:
  chest_box('Shoulder_buckle',side*.123,1.415,(.032,.017,.041),'rubber',var)
  chest_box('Buckle_crossbar',side*.123,1.415,(.021,.004,.006),'steel',var,.018)
 # Radio beside the plate, mounted in a nylon pocket with a retaining strap.
 x=.147;h=1.255
 chest_box('Radio_pouch',x,h,(.059,.043,.103),cloth,var)
 chest_box('Radio',x,h+.021,(.044,.027,.105),'rubber',var,.011)
 chest_box('Radio_screen',x,h+.044,(.027,.002,.017),'optic',var,.040)
 for row in range(3):
  for col in range(3):chest_box('Radio_button',x+(col-1)*.011,h+.022-row*.009,(.005,.003,.004),'steel',var,.040)
 p,_=vest_hit(x,h)
 cylinder('Antenna',(x+.015,-p.z-.025,h+.15),.0023,.20,'rubber',CHEST,var)
 cylinder('Volume_knob',(x-.012,-p.z-.025,h+.083),.0045,.012,'steel',CHEST,var)
 chest_box('Radio_retainer',x,h-.018,(.062,.005,.011),cloth,var,.045)
 chest_box('Tourniquet',-.15,1.29,(.027,.027,.075),'rubber',var)
 p,_=vest_hit(-.15,1.29)
 cylinder('Tourniquet_windlass',(-.15,-p.z-.031,1.303),.003,.05,'steel',CHEST,var,direction=(1,0,0))
 for h in [1.267,1.32]:chest_box('Tourniquet_band',-.15,h,(.032,.004,.008),cloth,var,.029)
 # Padded upper-arm team panels use the native upper-arm frame.
 for side in [-1,1]:
  bone='upperarm_l' if side>0 else 'upperarm_r'
  box('Arm_patch',(side*.26,.068,1.508),(.078,.071,.006),'rubber',bone,var,bevel=.008)
  box('Arm_ID',(side*.26,.068,1.513),(.064,.055,.003),'id_'+var,bone,var,bevel=.006)
# Soft cuff closes the sleeve/glove join without obscuring finger movement.
for side in [-1,1]:
 hand='hand_l' if side>0 else 'hand_r'
 tube('Glove_cuff',[(side*.746,.068+.028*math.sin(a),1.439+.032*math.cos(a)) for a in [k/48*math.tau for k in range(49)]],.004,'rubber',hand)
# Boot soles and lacing are fitted to the continuous leather upper. Sole toes
# share the foot/ball blend, so they flex without separating from the boot.
boot=next(m for m in native['variants']['blue'] if m['name']=='Object_123')
boot_points=[Vector(boot['positions'][i:i+3]) for i in range(0,len(boot['positions']),3)]
boot_faces=[boot['triangles'][i:i+3] for i in range(0,len(boot['triangles']),3)]
boot_tree=BVHTree.FromPolygons(boot_points,boot_faces,all_triangles=True)
def boot_top(x,z):
 hit=boot_tree.ray_cast(Vector((x,.4,z)),Vector((0,-1,0)))[0]
 return hit.y if hit else .08
for side in [-1,1]:
 foot='foot_l' if side>0 else 'foot_r'
 v=[];f=[];segments=64
 for h in [.001,.018]:
  for i in range(segments):
   a=i/segments*math.tau;z=.067+.171*math.sin(a);radius=.048+.006*max(0,math.sin(a))
   v.append((side*.089+radius*math.cos(a),-z,h))
 for i in range(segments):f.append((i,(i+1)%segments,(i+1)%segments+segments,i+segments))
 f.append(tuple(reversed(range(segments))));f.append(tuple(range(segments,segments*2)))
 o=mesh('Boot_sole',v,f,'rubber',foot);o['boot_side']=side
 bevel=o.modifiers.new('Sole edge','BEVEL');bevel.width=.003;bevel.segments=2
 for h in [.009,.020]:
  pts=[]
  for i in range(65):
   a=i/64*math.tau;z=.067+.17*math.sin(a);radius=.048+.006*max(0,math.sin(a))
   pts.append((side*.089+radius*math.cos(a),-z,h))
  o=tube('Sole_welt',pts,.0017,'shell',foot);o['boot_side']=side
 for row in range(6):
  z=.018+row*.022;pts=[]
  for u in range(9):
   x=side*.089+(u/8*2-1)*.026;zz=z+.012*(u/8)
   pts.append((x,-zz,boot_top(x,zz)+.003))
  o=tube('Boot_lace',pts,.0019,'rubber',foot);o['boot_side']=side
  for dx in [-.029,.029]:
   x=side*.089+dx;h=boot_top(x,z)
   o=sphere('Lace_eyelet',(x,-z,h+.002),(.0035,.0035,.0017),'steel',foot,segments=12);o['boot_side']=side
# Convert evaluated parts to glTF. Use split normals (bevels), planar UVs per face,
# and the vest's own barycentric weights for attachments on the moving torso.
bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();groups={}
def chest_weights(point):
 p,index=vest_hit(point.x,point.z);tri=faces[index];a,b,c=[verts[i] for i in tri]
 v0=b-a;v1=c-a;v2=p-a;d00=v0.dot(v0);d01=v0.dot(v1);d11=v1.dot(v1);den=d00*d11-d01*d01
 if abs(den)<1e-12:abc=[1,0,0]
 else:
  q=(d11*v2.dot(v0)-d01*v2.dot(v1))/den;r=(d00*v2.dot(v1)-d01*v2.dot(v0))/den;abc=[1-q-r,q,r]
 weights=defaultdict(float)
 for vi,factor in zip(tri,abc):
  for j in range(4):weights[vest['indices'][vi*4+j]]+=max(0,factor)*vest['weights'][vi*4+j]
 top=sorted(weights.items(),key=lambda w:-w[1])[:4];total=sum(w for _,w in top)
 return [i for i,w in top]+[0]*(4-len(top)),[w/total for i,w in top]+[0.]*(4-len(top))
for obj in objects:
 ev=obj.evaluated_get(deps);me=ev.to_mesh();me.calc_loop_triangles()
 prefix='HeadKit' if obj['bone'] in [HEAD,'neck_01'] else 'ChestKit' if obj['bone']==CHEST else 'BodyKit'
 key=(obj['mat'],obj['bone'],obj['variant']);group=groups.setdefault(key,{'name':prefix+'_'+obj['mat']+'_'+obj['bone']+'_'+obj['variant'],'material':obj['mat'],'bone':obj['bone'],'variant':obj['variant'],'positions':[],'normals':[],'uv':[],'indices':[],'joints':[],'weights':[]})
 normalmatrix=obj.matrix_world.to_3x3().inverted().transposed()
 center=sum((obj.matrix_world@v.co for v in me.vertices),Vector())/max(1,len(me.vertices))
 attachment=chest_weights(center) if obj['bone']==CHEST else ([next(i for i,b in enumerate(native['bones']) if b['name']==obj['bone']),0,0,0],[1.,0,0,0])
 for tri in me.loop_triangles:
  for li in tri.loops:
   v=me.vertices[me.loops[li].vertex_index];p=obj.matrix_world@v.co;n=(normalmatrix@me.corner_normals[li].vector).normalized()
   group['indices'].append(len(group['positions']));group['positions'].append([p.x,p.z,-p.y]);group['normals'].append([n.x,n.z,-n.y])
   axis=max(range(3),key=lambda a:abs(n[a]));uv=[p.y,p.z] if axis==0 else [p.x,p.z] if axis==1 else [p.x,p.y]
   group['uv'].append([x*5 for x in uv])
   binding=chest_weights(p) if obj.name.startswith('Scarf_drape') else attachment
   if 'boot_side' in obj:
    side='l' if obj['boot_side']>0 else 'r';blend=max(0,min(1,(-p.y-.07)/.11))
    binding=([next(i for i,b in enumerate(native['bones']) if b['name']=='foot_'+side),next(i for i,b in enumerate(native['bones']) if b['name']=='ball_'+side),0,0],[1-blend,blend,0,0])
   group['joints'].append(binding[0]);group['weights'].append(binding[1])
 ev.to_mesh_clear()
# Bake local contact occlusion into the equipment vertices. Its attenuation
# follows the skinned parts, unlike a fixed painted light direction.
from build_operator_variants import GLB
body_source=GLB('/tmp/piupiu-operator-input/operator_blue.glb')
for variant in ['blue','red']:
 all_points=[];all_faces=[]
 for part in native['variants'][variant]:
  base=len(all_points);points=[part['positions'][i:i+3] for i in range(0,len(part['positions']),3)]
  ids=part.get('triangles')
  if ids is None:
   primitive=body_source.g['meshes'][part['mesh']]['primitives'][part['primitive']]
   ids=[v[0] for v in body_source.read_accessor(primitive['indices'])]
  all_points.extend(points);all_faces.extend([[base+i for i in ids[j:j+3]] for j in range(0,len(ids),3)])
 active=[g for g in groups.values() if g['variant'] in ['both',variant]]
 for group in active:
  base=len(all_points);all_points.extend(group['positions']);all_faces.extend([[base+i for i in group['indices'][j:j+3]] for j in range(0,len(group['indices']),3)])
 tree=BVHTree.FromPolygons(all_points,all_faces,all_triangles=True);cache={}
 for group in active:
  if 'colors' in group:continue
  colors=[]
  for xyz,nxyz in zip(group['positions'],group['normals']):
   key=tuple(round(v,5) for v in xyz+nxyz)
   if key not in cache:
    point=Vector(xyz);normal=Vector(nxyz).normalized();up=Vector((0,1,0)) if abs(normal.y)<.9 else Vector((1,0,0));u=normal.cross(up).normalized();v=normal.cross(u)
    hits=0
    for sample in range(24):
     r=math.sqrt((sample+.5)/24);a=sample*2.3999632297
     direction=u*(r*math.cos(a))+v*(r*math.sin(a))+normal*math.sqrt(1-r*r)
     hit=tree.ray_cast(point+normal*.0015,direction,.12)[0]
     if hit is not None:hits+=1
    cache[key]=1-.72*hits/24
   ao=cache[key];colors.append([ao,ao,ao,1.])
  group['colors']=colors
 print('Baked equipment contact AO',variant,len(cache),'samples')
Path('/tmp/piupiu-operator-kit.json').write_text(json.dumps({'native':True,'materials':materials,'objects':list(groups.values())}))
print('Fitted kit:',len(objects),'parts;',len(groups),'surfaces;',sum(len(g['positions']) for g in groups.values())//3,'triangles')
