"""Prepare user-supplied Sketchfab GLBs for the existing weapon/optic factories.
Run Blender --background --python this_file -- /directory/with/downloads.
Source-space grip, bore and sight measurements refer to the assembled meshes.
Only the assembled TEC-9 is exported; its exploded duplicate is a display aid.
"""
import bpy
import json
import math
import numpy as np
import sys
from pathlib import Path
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(sys.argv[sys.argv.index('--') + 1])
OUT = ROOT / 'assets/detailed_weapons'
OPTICS = ROOT / 'assets/replacement_optics'
OPTICS.mkdir(exist_ok=True)
# World axes after glTF import in Blender; all exports use +Y up / -Z bore.
ROTATIONS = {
    'negative_y': Matrix.Rotation(math.pi, 4, 'Z'),
    'positive_x': Matrix.Rotation(math.pi / 2, 4, 'Z'),
    'negative_x': Matrix.Rotation(-math.pi / 2, 4, 'Z'),
}
GUNS = {
    # file, bore axis, physical length, source grip, support, muzzle, rear/front sight
    'tec9': ('tec-9', 'negative_y', .317, (0,330,-125), (0,315,-120), (0,-134,21), ((0,375,68),(0,-85,68))),
    'mac10': ('mac 10', 'negative_y', .30, (0,4,-7), (0,4,-7), (0,-27,7), ((0,19,19),(0,-20,19))),
    'mp5': ('mp-5', 'negative_y', .68, (0,30,48), (0,-100,110), (0,-172,120), ((0,44,142),(0,-151,142))),
    'bullpup': ('bullpup', 'negative_x', .72, (.2,1.965,2.7), (-4.15,1.965,3.0), (-8.03,1.965,4.91), ((1,1.965,6.3),(-5,1.965,6.3))),
    'carbine': ('carbine', 'positive_x', .86, (-1.15,0,.24), (.85,0,.34), (2.50,0,.07), ((-.8,0,.85),(1.8,0,.85))),
    'compact': ('smg compact', 'negative_x', .64, (-.12,0,-.57), (-1.02,0,-.62), (-1.487,0,.18), ((-.12,0,.43),(-1.25,0,.43))),
}


def flatten(objects, conversion):
    transforms = {o: conversion @ o.matrix_world for o in objects}
    for obj in objects:
        obj.parent = None
        obj.matrix_world = transforms[obj]
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for obj in list(bpy.data.objects):
        if obj not in objects:
            bpy.data.objects.remove(obj, do_unlink=True)


def marker(name, point):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = point
    return obj


def bounds(objects):
    points = [o.matrix_world @ Vector(c) for o in objects for c in o.bound_box]
    return Vector([min(p[a] for p in points) for a in range(3)]), Vector([max(p[a] for p in points) for a in range(3)])


def join(objects, name):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    return obj


def split(obj, name, predicate):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.context.tool_settings.mesh_select_mode = (False, False, True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.object.mode_set(mode='OBJECT')
    for face in obj.data.polygons:
        face.select = predicate(face.center)
    count = sum(f.select for f in obj.data.polygons)
    if not 0 < count < len(obj.data.polygons):
        raise RuntimeError(f'{name}: invalid selection {count}')
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.separate(type='SELECTED')
    bpy.ops.object.mode_set(mode='OBJECT')
    part = next(o for o in bpy.context.selected_objects if o != obj)
    part.name = name
    obj.select_set(False)
    bpy.context.view_layer.objects.active = part
    bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    return part


def export(path):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB',
        use_selection=True, export_apply=True, export_yup=True, export_animations=False)


def preview(name, objects):
    lo, hi = bounds(objects)
    center = (lo + hi) * .5
    size = hi - lo
    bpy.ops.object.camera_add(location=center + Vector((-2,0,0)))
    camera = bpy.context.object
    camera.rotation_euler = (center-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = max(size) * 1.2
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'TEXTURE'
    scene.display.shading.show_cavity = True
    scene.world = bpy.data.worlds.new('World')
    scene.world.color = (.12,.12,.12)
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.filepath = '/tmp/prepared-' + name + '.png'
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(camera, do_unlink=True)
    print('PREPARED', name, 'bounds', list(lo), list(hi), flush=True)


def main():
    for name, (file, axis, length, grip, support, muzzle, sights) in GUNS.items():
        if '--only' in sys.argv and name not in sys.argv[sys.argv.index('--only')+1].split(','): continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(SOURCE / (file+'.glb')))
        objects = [o for o in bpy.data.objects if o.type == 'MESH']
        if name == 'tec9':
            objects = [o for o in objects if '.001_' not in o.name and '.002_' not in o.name]
        if name == 'bullpup':
            objects = [o for o in objects if 'ReflexSights' not in o.name and 'BulletsAndCases' not in o.name]
        magazine_objects = []
        if name == 'carbine':
            # The OBJ contains an unseated magazine and two redundant optic meshes.
            # Identify complete disconnected parts before flattening to retain UVs.
            obj = next(o for o in objects if o.name == 'Object_4')
            bpy.ops.object.select_all(action='DESELECT')
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.mesh.separate(type='LOOSE')
            bpy.ops.object.mode_set(mode='OBJECT')
            for piece in bpy.data.objects:
                if piece.type != 'MESH' or not piece.name.startswith('Object_4'): continue
                low, high = bounds([piece])
                if low.x > .14 and high.x < .66 and high.y < .065 and high.z < 1.01:
                    magazine_objects.append(piece)
            objects = [o for o in bpy.data.objects if o.type == 'MESH' and o.name != 'Object_6']
            # Source optic housing is Object_6; Object_5 is its separate glass.
            objects = [o for o in objects if o.name != 'Object_5']
        rotation = ROTATIONS[axis]
        # The AR-15 source is pitched relative to its OBJ axes.
        if name == 'carbine':
            rotation = rotation @ Matrix.Rotation(-.224, 4, 'Y')
        lo, hi = bounds(objects)
        bore_axis = 0 if axis.endswith('_x') else 1
        scale = length / (hi[bore_axis] - lo[bore_axis])
        conversion = Matrix.Scale(scale,4) @ rotation
        offset = Vector((0,0,-.055)) - conversion @ Vector(grip)
        conversion = Matrix.Translation(offset) @ conversion
        flatten(objects, conversion)
        def p(point): return conversion @ Vector(point)
        if name == 'carbine':
            magazine = join(magazine_objects, 'Magazine')
            points = np.array([v.co[:] for v in magazine.data.vertices])
            center = (points.min(0) + points.max(0)) * .5
            _, axes = np.linalg.eigh(np.cov(points.T))
            # PCA: thickness -> X, width -> Y, length -> Z. Keep right-handed UVs.
            if np.linalg.det(axes) < 0: axes[:,0] *= -1
            aligned = (points-center) @ axes
            for vertex, point in zip(magazine.data.vertices, aligned): vertex.co = point
            magazine.location = (0,.085,-.060)
            objects = [o for o in bpy.data.objects if o.type == 'MESH' and o != magazine]
        body = join(objects, 'Body')
        if name == 'tec9':
            # Magazine is a distinct source object (13/16/17/18); split its solid
            # lower portion while leaving the magwell in the receiver.
            split(body, 'Magazine', lambda v: v.z < p((0,0,-60)).z and abs(v.y-p((0,130,0)).y)<.025)
        elif name == 'mac10':
            split(body, 'Magazine', lambda v: v.z < p((0,0,-10)).z and abs(v.y-p((0,0,0)).y)<.023)
        elif name == 'mp5':
            split(body, 'Magazine', lambda v: v.z < p((0,0,70)).z and p((0,5,0)).y < v.y < p((0,-88,0)).y)
        elif name == 'bullpup':
            split(body, 'Magazine', lambda v: v.z < p((0,0,3.7)).z and p((2.4,0,0)).y > v.y > p((5.0,0,0)).y)
        elif name == 'compact':
            split(body, 'Magazine', lambda v: v.z < p((0,0,-.57)).z and p((-.7,0,0)).y > v.y > p((-.15,0,0)).y)
        marker('Grip', (.025,0,-.055))
        support_point = p(support); support_point.x = -.027
        marker('Support', support_point)
        marker('Muzzle', p(muzzle))
        marker('RearSight', p(sights[0]))
        marker('FrontSight', p(sights[1]))
        marker('LoadingPort', p(grip)+Vector((-.025,.025,.04)))
        if name in ['carbine','bullpup']:
            # Receiver rail seats, measured on the flattened mesh.
            marker('OpticMount', p((-.55,0,.875) if name=='carbine' else (-1.5,1.965,6.08)))
        export(OUT / (name+'.glb'))
        preview(name, [o for o in bpy.data.objects if o.type=='MESH'])

    # Optical axes are retained at y=50mm to reuse the collimated-dot contract.
    # Source front faces and source-axis heights are measured from their apertures.
    SIGHTS = {
     'reflex': ('red_dot','negative_y',.115, (0,0,.40)),
     'holographic': ('red_dot2','positive_x',.105, (0,0,.22)),
     'aimpoint': ('red dot 3','negative_x',.115, (0,0,53.26)),
     'nightforce': ('sniper scope','negative_y',.36, (-3861,0,-1843)),
     'accushot': ('sniper_scope','negative_y',.34, (.799,0,.71)),
    }
    for name,(file,axis,length,axis_point) in SIGHTS.items():
        if '--only' in sys.argv and name not in sys.argv[sys.argv.index('--only')+1].split(','): continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(SOURCE/(file+'.glb')))
        objects=[o for o in bpy.data.objects if o.type=='MESH']
        lo,hi=bounds(objects)
        a=0 if axis.endswith('_x') else 1
        scale=length/(hi[a]-lo[a])
        conversion=Matrix.Scale(scale,4) @ ROTATIONS[axis]
        # Centre the length, centre the aperture laterally, and retain the source
        # mount height. The runtime seats the actual lowest mount face on the rail.
        center=(lo+hi)*.5
        center.z=axis_point[2]
        if a==1:center.x=axis_point[0]
        else:center.y=(lo.y+hi.y)*.5
        offset=Vector((0,0,.05))-conversion@center
        flatten(objects,Matrix.Translation(offset)@conversion)
        if name == 'aimpoint':
            import bmesh
            for obj in objects:
                bm = bmesh.new(); bm.from_mesh(obj.data)
                faces = [f for f in bm.faces if all(-.001 < v.co.x < .004 and
                    .0485 < v.co.y < .0495 and .048 < v.co.z < .052 for v in f.verts)]
                bmesh.ops.delete(bm, geom=faces, context='FACES')
                bm.to_mesh(obj.data); bm.free()
                obj.location.x -= .00124
        if name == 'holographic':
            body = join(objects, 'Housing')
            lens = split(body, 'Lens', lambda v: .038 < v.z < .071 and
                (abs(v.y-.02904774) < .00002 or abs(v.y-.01145891) < .00002))
            # The side knob makes the overall bounding box asymmetric. Centre the
            # actual aperture, rather than aiming through the housing's centre.
            for obj in [body, lens]:
                obj.location += Vector((.007009,0,-.004278))
            objects = [body, lens]
        marker('OpticalAxis',(0,0,.05))
        export(OPTICS/(name+'.glb'))
        preview(name,objects)

    # M1's old scope is fused into the Steel surface. Remove only geometry above
    # the 73 mm receiver, then use the separate imported Accushot assembly at runtime.
    if '--only' not in sys.argv or 'm1' in sys.argv[sys.argv.index('--only')+1].split(','):
        import bmesh
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/arsenal/m1.glb'))
        for obj in list(bpy.data.objects):
            if obj.type != 'MESH': continue
            bm=bmesh.new();bm.from_mesh(obj.data)
            faces=[f for f in bm.faces if all((obj.matrix_world @ v.co).z > .079 for v in f.verts)]
            bmesh.ops.delete(bm,geom=faces,context='FACES')
            bm.to_mesh(obj.data);bm.free()
            if len(obj.data.polygons)==0: bpy.data.objects.remove(obj,do_unlink=True)
        export(OUT/'m1_scope_base.glb')


if __name__ == "__main__":
    main()
