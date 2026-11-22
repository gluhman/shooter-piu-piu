"""Convert downloaded weapons to metre-scale, -Z-bore GLBs with animated parts.

Run in Blender: --background --python this_file -- /path/to/downloads
The input directory contains m4.blend, m249-godot.glb and the extracted Polyy pack.
Source files and download URLs are documented in assets/detailed_weapons/CREDITS.md.
"""
import bpy
import math
import sys
from pathlib import Path
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(sys.argv[sys.argv.index('--') + 1])
OUT = ROOT / 'assets/detailed_weapons'

# Source-space contacts were measured on the actual downloaded meshes. Polyy
# models have two different bore axes; do not infer their orientation by name.
# id: source, length, grip (height, depth), support (height, depth), bore, sights.
PACK = {
    'bullpup': ('bullpup_rifle', .72, (-.12, -.01), (.025, -.30), (.00, -.50), (.225, -.06, -.19)),
    'compact': ('compact_submachine_gun', .69, (-.14, .34), (-.10, -.28), (.17, -.49), (.32, .21, -.39)),
    'shotgun': ('pump_action_shotgun', .98, (.015, .20), (.025, -.17), (.075, -.50), (.115, .10, -.47)),
    'breacher': ('pump_action_shotgun', .76, (.015, .20), (.025, -.17), (.075, -.50), (.115, .10, -.47)),
    'longshot': ('bolt_action_sniper_rifle', 1.12, (-.035, .18), (.005, -.12), (.045, -.50), (.145, .28, -.04)),
    'scout': ('bolt_action_sniper_rifle', .94, (-.035, .18), (.005, -.12), (.045, -.50), (.145, .28, -.04)),
    'rpk': ('wood_furniture_assault_rifle', 1.08, (-.025, .23), (.075, -.17), (.085, -.50), (.165, .13, -.43)),
    'launcher': ('revolving_grenade_launcher', .74, (-.15, .20), (.02, -.15), (.075, -.50), (.275, -.07, -.31)),
}
AXIS_SCALE = {'compact': (.60, .60), 'bullpup': (.65, .70),
              'launcher': (.65, .75), 'rpk': (1., .72)}


def empty(name, point):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = (point[0], -point[2], point[1])
    obj.empty_display_size = .012
    return obj


def split_region(obj, name, predicate):
    """Detach complete textured faces, preserving their UVs and materials."""
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.context.tool_settings.mesh_select_mode = (False, False, True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.object.mode_set(mode='OBJECT')
    for polygon in obj.data.polygons:
        centre = obj.matrix_world @ polygon.center
        polygon.select = predicate(Vector((centre.x, centre.z, -centre.y)))
    count = sum(p.select for p in obj.data.polygons)
    if not count:
        raise RuntimeError(f'{name}: empty moving-part selection')
    if count == len(obj.data.polygons):
        raise RuntimeError(f'{name}: moving part cannot contain the entire gun')
    print(name, 'selected faces', count, 'of', len(obj.data.polygons), flush=True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.separate(type='SELECTED')
    bpy.ops.object.mode_set(mode='OBJECT')
    part = next(o for o in bpy.context.selected_objects if o != obj)
    part.name = name
    bpy.context.view_layer.objects.active = part
    obj.select_set(False)
    bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    return part


def export(name):
    bpy.ops.object.select_all(action='SELECT')
    staging = SOURCE / 'piupiu-weapon-export'
    staging.mkdir(exist_ok=True)
    output = staging / (name + '.glb')
    bpy.ops.export_scene.gltf(filepath=str(output),
        export_format='GLB', use_selection=True, export_apply=True,
        export_yup=True, export_animations=False)
    output.replace(OUT / output.name)


for name, (source, length, grip, support, bore, sight) in PACK.items():
    if '--weapons' in sys.argv and name not in sys.argv[sys.argv.index('--weapons') + 1].split(','):
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE / 'piupiu-new-models' /
        '3D_low_poly_guns_pack/models' / (source + '.glb')))
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    rotation = math.pi if name == 'bullpup' else math.pi / 2
    width_scale, height_scale = AXIS_SCALE.get(name, (1., 1.))
    conversion = Matrix.Translation((0, grip[1] * length, -.055 - grip[0] * length * height_scale)) @ Matrix.Diagonal((length * width_scale, length, length * height_scale, 1)) @ Matrix.Rotation(rotation, 4, 'Z')
    transforms = {o: conversion @ o.matrix_world for o in meshes}
    # Flatten import wrappers so moving parts have an unambiguous local frame.
    for obj in meshes:
        obj.parent = None
        obj.matrix_world = transforms[obj]
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for obj in list(bpy.data.objects):
        if obj.type != 'MESH':
            bpy.data.objects.remove(obj, do_unlink=True)

    def point(y, z, x=0):
        return (x, (y - grip[0]) * length * height_scale - .055, (z - grip[1]) * length)

    empty('Grip', (.025, -.055, 0))
    empty('Support', point(*support, x=-.028))
    empty('Muzzle', point(*bore))
    empty('RearSight', point(sight[0], sight[1]))
    empty('FrontSight', point(sight[0], sight[2]))
    empty('LoadingPort', point(.005, .08, x=-.025))
    body = meshes[0]
    body.name = 'Body'
    if name in ('shotgun', 'breacher'):
        lo, hi = point(0, -.32)[2], point(0, -.04)[2]
        split_region(body, 'Pump', lambda p: lo < p.z < hi and p.y < point(.065, 0)[1])
    elif name not in ('longshot', 'scout', 'launcher'):
        # Keep the forward grips in the fixed body when detaching magazines.
        lo, hi = {'bullpup': (.21, .46), 'compact': (-.22, .08),
                  'rpk': (-.055, .175), 'launcher': (-.335, .04)}[name]
        y = {'bullpup': -.015, 'compact': .015, 'rpk': .04, 'launcher': .185}[name]
        split_region(body, 'Magazine', lambda p: point(0, lo)[2] < p.z < point(0, hi)[2] and p.y < point(y, 0)[1])
    if name in ('longshot', 'scout'):
        split_region(body, 'Magazine', lambda p: point(0, .07)[2] < p.z < point(0, .175)[2] and p.y < point(.025, 0)[1])
    # The launcher drum and its upper frame are fused in the source. Preserve
    # the complete assembly; gameplay reloads insert a separate 40 mm round.
    export(name)

if '--pack-only' in sys.argv:
    raise SystemExit(0)

# The M4 lies on its side in the source .blend. Preserve its individual parts
# and original 2K PBR maps, with a small bevel on machined silhouette edges.
bpy.ops.wm.open_mainfile(filepath=str(SOURCE / 'm4.blend'))
conversion = Matrix.Translation((-.030, .12, .045)) @ Matrix.Rotation(math.pi / 2, 4, 'Y')
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
transforms = {o: conversion @ o.matrix_world for o in meshes}
for obj in list(bpy.data.objects):
    if obj.type != 'MESH':
        bpy.data.objects.remove(obj, do_unlink=True)
for obj in meshes:
    obj.parent = None
    obj.matrix_world = transforms[obj]
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bevel = obj.modifiers.new('Machined edges', 'BEVEL'); bevel.width = .00045; bevel.segments = 3
    if obj.name == 'Charging_Handle': obj.name = 'Bolt'
    # Blender's Bump chain masks the authored normal map during glTF export.
    for mat in obj.data.materials:
        bs = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        normal = next(n for n in mat.node_tree.nodes if n.type == 'NORMAL_MAP')
        mat.node_tree.links.new(normal.outputs['Normal'], bs.inputs['Normal'])
for label, p in {'Grip': (.025,-.055,0), 'Support': (-.027,.005,-.31),
    'Muzzle': (0,.045,-.616), 'RearSight': (0,.13,-.015),
    'FrontSight': (0,.13,-.215), 'LoadingPort': (-.025,.005,-.08),
    'OpticMount': (0,.080,-.015)}.items(): empty(label,p)
export('carbine')

# Provider's Godot GLB already contains baked 2K maps. Keep the whole connected
# optic assembly; only detach the ammunition bag for the reload animation.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE / 'm249-godot.glb'))
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
conversion = Matrix.Translation((.0305,.20,-.165)) @ Matrix.Rotation(math.pi,4,'Z')
transforms = {o: conversion @ o.matrix_world for o in meshes}
for obj in meshes:
    obj.parent=None; obj.matrix_world=transforms[obj]
    bpy.context.view_layer.objects.active=obj
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True)
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
for obj in list(bpy.data.objects):
    if obj.type != 'MESH': bpy.data.objects.remove(obj,do_unlink=True)
bag=[]
for obj in meshes:
    centre=sum((obj.matrix_world @ Vector(c) for c in obj.bound_box), Vector()) / 8
    if centre.z < .005 and abs(centre.y-.155)<.08: bag.append(obj)
mag=empty('Magazine', (0,-.08,-.155))
for obj in bag:
    transform=obj.matrix_world.copy(); obj.parent=mag; obj.matrix_world=transform
for label,p in {'Grip': (.025,-.055,0), 'Support': (-.028,-.015,-.36),
    'Muzzle': (0,.055,-.768), 'RearSight': (0,.171,-.02),
    'FrontSight': (0,.171,-.11), 'LoadingPort': (-.025,.02,-.16)}.items():empty(label,p)
export('m249')
