"""Normalize the second user-supplied weapon batch, preserving UV/PBR and parts.
Blender --background --python this_file -- /directory/of/GLBs [--only id,id]
"""
import bpy
import math
import sys
import numpy as np
from pathlib import Path
from mathutils import Matrix, Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_replacement_weapons import bounds, flatten, join, split, marker, export, preview

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(sys.argv[sys.argv.index('--') + 1])
OUT = ROOT / 'assets/detailed_weapons'
# file, forward vector, physical length, trigger grip, support, muzzle, sights.
GUNS = {
 'm1': ('m1', (0,1,0), 1.10, (0,-.40,-.09), (0,.15,-.025), (0,1,.025), ((0,-.36,.075),(0,.94,.075))),
 'rpg': ('rpg_7', (1,0,0), 1.35, (.08,-.015,.09), (-.025,-.015,.11), (.509,-.015,.185), ((-.018,-.015,.25),(.195,-.015,.25))),
 'launcher': ('grenade-launcher_m79', (1,0,0), .74, (-.04,0,-.025), (.25,0,-.025), (.455,0,.014), ((.045,0,.043),(.45,0,.054))),
 'gpmg': ('gpmg', (1,0,0), 1.22, (-3.15,0,-.86), (-.30,0,-.18), (5.76,0,0), ((-2.8,0,.44),(3.93,0,.73))),
 'm249': ('m249', (0,-1,0), 1.04, (0,.22,-.145), (0,-.19,.015), (0,-.607,.1), ((0,.365,.220),(0,-.465,.215))),
 'rpk': ('squad lmg', (0,-1,0), 1.04, (0,.015,-.025), (0,-.29,.025), (0,-.673,.075), ((0,.025,.15),(0,-.46,.15))),
 'breacher': ('breacher', (-1,0,0), .73, (.31,0,-.075), (-.12,0,-.005), (-.368,0,.034), ((.23,0,.052),(-.35,0,.052))),
 'shotgun': ('shotgun', (1,0,.15), 1.04, (-.67,.80,1.21), (.36,.835,1.35), (1.29,.86,1.61), ((-.40,.85,1.48),(1.24,.88,1.67))),
 'scout': ('scout', (-1,0,0), 1.03, (1.08,-.097,-.18), (.37,-.097,-.10), (-.715,-.097,-.059), ((.86,-.097,.06),(.39,-.097,.06))),
 'longshot': ('longshot', (0,1,0), 1.40, (0,-1.19,-.18), (0,-.45,-.04), (0,1.99,.12), ((0,-.80,.24),(0,-.15,.24))),
 'm700': ('m700', (0,1,0), 1.10, (0,-2.10,-.42), (0,.0,.18), (0,4.865,.62), ((0,-2.0,.78),(0,.60,.78))),
}


def bake_skin(objects):
    graph = bpy.context.evaluated_depsgraph_get()
    for obj in objects:
        if not obj.modifiers: continue
        mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(graph))
        obj.modifiers.clear()
        obj.data = mesh


def name_part(objects, predicate, label):
    # Joining an earlier part invalidates handles in the original object list.
    pieces = [o for o in list(bpy.data.objects) if o.type == "MESH" and predicate(o)]
    if not pieces: raise RuntimeError('Missing source part: '+label)
    piece = join(pieces, label)
    if label != 'LoadedRocket':
        bpy.context.view_layer.objects.active = piece
        bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    return piece


def remove_m249_attachments(objects):
    """Remove whole disconnected source parts, never slice the carry handle.

    glTF duplicates vertices at UV/normal seams. Join coincident positions only
    in the connectivity map; retain the original vertices, UVs and normals.
    """
    for obj in objects:
        mesh = obj.data
        points = [obj.matrix_world @ v.co for v in mesh.vertices]
        parent = list(range(len(points)))
        def root(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i
        def union(a,b):
            a,b=root(a),root(b)
            if a!=b: parent[b]=a
        coincident={}
        for i,p in enumerate(points):
            key=tuple(round(c,6) for c in p)
            if key in coincident: union(i,coincident[key])
            else: coincident[key]=i
        for face in mesh.polygons:
            for i in face.vertices[1:]: union(face.vertices[0],i)
        groups={}
        for i,p in enumerate(points):groups.setdefault(root(i),[]).append(p)
        removed=set()
        for key,part in groups.items():
            lo=Vector([min(p[i] for p in part) for i in range(3)])
            hi=Vector([max(p[i] for p in part) for i in range(3)])
            optic=lo.z>.19 and lo.y>0 and hi.y<.36 and max(abs(lo.x),abs(hi.x))<.04
            bipod=lo.z<-.20 and hi.y<-.30
            if optic or bipod:removed.add(key)
        indices={f.index for f in mesh.polygons if root(f.vertices[0]) in removed}
        import bmesh
        bm=bmesh.new();bm.from_mesh(mesh);bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm,geom=[bm.faces[i] for i in indices],context='FACES')
        bm.to_mesh(mesh);bm.free()
        print('M249 complete attachment faces removed',len(indices),flush=True)


def main():
    for name, (file, forward, length, grip, support, muzzle, sights) in GUNS.items():
        if '--only' in sys.argv and name not in sys.argv[sys.argv.index('--only')+1].split(','): continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(SOURCE/(file+'.glb')))
        objects = [o for o in bpy.data.objects if o.type=='MESH']
        bake_skin(objects)
        if name == 'm249': remove_m249_attachments(objects)
        if name == 'launcher': objects = [o for o in objects if o.name=='Object_7']
        if name == 'rpg': objects = [o for o in objects if o.name in [
            'RPG_7_Grenade_RPG_7_Grenade_0', 'RPG_7_WoodenHeatShield_RPG_7_WoodenHeatShield_0']]
        if name == 'gpmg': objects = [o for o in objects if o.name not in [
            'Object_4','Object_5','Object_7','Object_9','Object_11','Object_12','Object_13',
            'Object_32','Object_33','Object_34','Object_35']]
        clip = next((o for o in objects if o.name=='defaultMaterial.001'),None) if name=='m1' else None
        if clip:
            lo,hi=bounds([clip]);clip.matrix_world=Matrix.Translation(Vector((0,-.20,.04))-(lo+hi)*.5)@clip.matrix_world
            bpy.context.view_layer.update()
        u=Vector(forward).normalized()
        up_hint=Vector((0,0,1))
        if name=='shotgun':
            barrel=next(o for o in objects if o.name.startswith('Barrel_Lp'))
            pts=np.array([tuple(barrel.matrix_world@v.co) for v in barrel.data.vertices])
            _,vectors=np.linalg.eigh(np.cov(pts.T));u=Vector(vectors[:,-1]);u*=1 if u.x>0 else -1
            up_hint=Vector(vectors[:,1]);up_hint*=1 if up_hint.z>0 else -1
        right=u.cross(up_hint).normalized();up=right.cross(u).normalized()
        rotation=Matrix((right,u,up)).to_4x4()
        # Scale the visible assembly along the actual bore, excluding spare ammo.
        pts=[rotation@(o.matrix_world@Vector(c)) for o in objects for c in o.bound_box]
        scale=length/(max(p.y for p in pts)-min(p.y for p in pts))
        conversion=Matrix.Scale(scale,4)@rotation
        conversion=Matrix.Translation(Vector((0,0,-.055))-conversion@Vector(grip))@conversion
        flatten(objects,conversion)
        inverse=conversion.inverted()
        def p(v):return conversion@Vector(v)
        def source(v):return inverse@v
        moving=[]
        if name=='breacher':moving=[name_part(objects,lambda o:o.name.startswith('Fore-end'),'Pump')]
        elif name=='shotgun':moving=[name_part(objects,lambda o:o.name.startswith(('Grip_Lp','BarrelPump_Lp')),'Pump')]
        elif name=='rpk':moving=[name_part(objects,lambda o:o.name.startswith('mag_'),'Magazine'),name_part(objects,lambda o:o.name.startswith('bolt_'),'Bolt')]
        elif name=='gpmg':moving=[name_part(objects,lambda o:o.name=='Object_37','Magazine')]
        elif name=='rpg':moving=[name_part(objects,lambda o:o.name=='RPG_7_Grenade_RPG_7_Grenade_0','LoadedRocket')]
        elif name=='m1':moving=[name_part(objects,lambda o:o==clip,'Magazine')]
        elif name=='scout':
            moving=[name_part(objects,lambda o:o.name.startswith(('Rifle.033_','Rifle.034_')),'Magazine'),
                    name_part(objects,lambda o:o.name.startswith(('Rifle.025_','Rifle.026_','Rifle.027_')),'Bolt')]
        # Joining removed source objects from bpy.data; only collect live objects.
        fixed=[o for o in bpy.data.objects if o.type=='MESH' and o not in moving]
        body=join(fixed,'Body')
        if name=='m249':
            # Detach only the ammunition box, leaving the grip and handguard fixed.
            split(body,'Magazine',lambda v: source(v).z<-.005 and -.12<source(v).y<.055 and source(v).x<-.012)
        elif name=='m700':
            split(body,'Bolt',lambda v:-2.5<source(v).y<-.60 and .49<source(v).z<.65 and source(v).x>.02)
        elif name=='launcher':
            barrel=split(body,'Barrel',lambda v:source(v).x>.085)
            hinge=marker('BreakAction',p((.085,0,-.005)))
            bpy.context.view_layer.update()
            world=barrel.matrix_world.copy();barrel.parent=hinge;barrel.matrix_world=world
        # AR-50 is single-shot; retain its receiver and animate the bolt region.
        elif name=='longshot':
            split(body,'Bolt',lambda v:-1.20<source(v).y<-.66 and source(v).z>.06 and source(v).x>.022)
        marker('Grip',(.025,0,-.055))
        point=p(support);point.x=-.027;marker('Support',point)
        marker('Muzzle',p(muzzle));marker('RearSight',p(sights[0]));marker('FrontSight',p(sights[1]))
        port=marker('LoadingPort',p(grip)+Vector((-.025,.035,.035)))
        if name in ['longshot','m700']:
            port.location=p((0,-.80,.12) if name=='longshot' else (0,-1.4,.53))
        if name=='launcher':
            port.location=p((.10,0,.014))
            bpy.context.view_layer.update()
            world=port.matrix_world.copy();port.parent=hinge;port.matrix_world=world
        if name=='shotgun':
            # Twin tubes are rolled in the source. Measure the firing tube at
            # its mouth after conversion instead of guessing a source-space Y.
            points=[v.co.copy() for v in body.data.vertices]
            end=max(v.y for v in points)
            tip=[v for v in points if v.y>end-.008]
            top=max(v.z for v in tip)
            upper=[v for v in tip if v.z>top-.014]
            center=sum(upper,Vector())/len(upper)
            bpy.data.objects['Muzzle'].location=Vector((center.x,end,center.z))
            for label in ['RearSight','FrontSight']:
                bpy.data.objects[label].location.x=center.x
                bpy.data.objects[label].location.z=center.z+.012

        if name in ['m1','longshot']:
            seat=p((0,-.20,.06) if name=='m1' else (0,-.65,.20))
            marker('OpticMount',seat)
        if name=='rpg':
            # Export exactly the same projectile shown in the loaded launcher.
            rocket=moving[0]
            bpy.ops.object.select_all(action='DESELECT');rocket.select_set(True)
            transform=rocket.matrix_world.copy()
            tip=p(muzzle);rocket.data.transform(Matrix.Translation(-tip))
            bpy.ops.export_scene.gltf(filepath=str(OUT/'rpg_projectile.glb'),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_animations=False)
            rocket.data.transform(Matrix.Translation(tip));rocket.matrix_world=transform
        export(OUT/(name+'.glb'))
        preview(name,[o for o in bpy.data.objects if o.type=='MESH'])

if __name__=='__main__':main()
