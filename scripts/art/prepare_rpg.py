import bpy, math
from mathutils import Matrix,Vector
from pathlib import Path
import sys
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
if not args: raise SystemExit('Usage: blender --background --python scripts/art/prepare_rpg.py -- /path/to/Rpg.blend')
bpy.ops.wm.open_mainfile(filepath=args[0])
root=Path(__file__).resolve().parents[2]/'assets/rpg'
# Native source uses X along tube and Z up; rotate into the project's -Z bore convention.
conv=Matrix.Rotation(-math.pi/2,4,'Z') @ Matrix.Scale(0.04,4)
meshes=[o for o in bpy.data.objects if o.type=='MESH']
for o in list(bpy.data.objects):
 if o.type!='MESH':bpy.data.objects.remove(o,do_unlink=True)
for o in meshes:
 o.matrix_world=conv@o.matrix_world
 bpy.context.view_layer.objects.active=o;o.select_set(True)
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 # Keep the authored bevels and subdivision, adding rounded edges on remaining machined parts.
 if not o.modifiers:
  m=o.modifiers.new('Machined edge bevel','BEVEL');m.width=0.001;m.segments=3
 for m in o.modifiers:
  if m.type=='SUBSURF':m.levels=3;m.render_levels=3
 for p in o.data.polygons:p.use_smooth=True
 # Poly Haven mapping in physical metres, with original 4K images.
 wood=o.name in ['Cylinder.003','Cylinder.004','Cube.003','Cube.004']
 finish='Wood' if wood else 'Steel'
 mat=bpy.data.materials.get(finish)
 if not mat:
  mat=bpy.data.materials.new(finish);mat.use_nodes=True
  bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.28,.24,.18,1) if wood else (.16,.18,.12,1)
  bs.inputs['Metallic'].default_value=0 if wood else .65
  bs.inputs['Roughness'].default_value=.48
 o.data.materials.clear();o.data.materials.append(mat)
 o.select_set(False)
# The launcher source has no loaded rocket. A separate projectile mesh is authored here.
# Its profile is visual content only; gameplay dimensions are in combat_balance.gd.
def rocket(name):
 verts=[];faces=[];profile=[(-.11,.0),(-.10,.018),(-.02,.018),(.0,.035),(.13,.045),(.23,.024),(.28,.0)]
 for z,r in profile:
  for i in range(64):
   a=i*math.tau/64;verts.append((r*math.cos(a),r*math.sin(a),z))
 for j in range(len(profile)-1):
  for i in range(64):faces.append((j*64+i,j*64+(i+1)%64,(j+1)*64+(i+1)%64,(j+1)*64+i))
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
 ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob)
 # Blender +Y is glTF -Z. Rocket nose faces down the bore.
 ob.rotation_euler.x=-math.pi/2;ob.location=(0,.48,.18)
 ob.data.materials.append(bpy.data.materials['Steel'])
 for p in me.polygons:p.use_smooth=True
 return ob
r=rocket('LoadedRocket')
# Blender coordinates of glTF metre-space markers.
def marker(name,v):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=(v[0],-v[2],v[1]);o.empty_display_size=.015
for name,v in {'Grip':(.025,.065,-.13),'Support':(-.026,.145,-.35),'Muzzle':(0,.18,-.46),'RearSight':(-.025,.27,-.19),'FrontSight':(-.025,.27,-.40),'LoadingPort':(0,.18,-.45)}.items():marker(name,v)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=str(root/'rpg.glb'),export_format='GLB',use_selection=True,export_apply=True,export_yup=True)
# Separate in-flight rocket with its origin at the motor, forward -Z in Godot.
bpy.ops.object.select_all(action='DESELECT');r.select_set(True);r.location=(0,0,0)
bpy.ops.export_scene.gltf(filepath=str(root/'rocket.glb'),export_format='GLB',use_selection=True,export_apply=True,export_yup=True)
print('Exported RPG with source detail and added loaded rocket')
