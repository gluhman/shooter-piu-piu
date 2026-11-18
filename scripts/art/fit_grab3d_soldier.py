"""Fit the CC0 high-detail Grab3D soldier to the game's native combat rig.

Run with Blender 4.5: --background --disable-autoexec --python this_file
The high-poly master and a backup of the previous operator are in art/player/.
Preserves the source UVs and 4K PBR maps; retains the existing articulated gloves.
"""
from pathlib import Path
import bpy
import bmesh
import json
import math
import numpy as np
from mathutils import Matrix, Vector

GAME = Path(__file__).resolve().parents[2]
ART = GAME.parent / 'art/player'
OUT = ART / 'game_export'
OUT.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ART / 'soldier_highpoly.blend'), load_ui=False, use_scripts=False)
body = bpy.data.objects['Soldier_HighPoly_800k']
source_rig = bpy.data.objects['Soldier_Rig']
source_heads = {b.name: b.head_local.copy() for b in source_rig.data.bones}
source_groups = [g.name for g in body.vertex_groups]
source_weights = [[(source_groups[g.group], g.weight) for g in v.groups] for v in body.data.vertices]
original = np.array([v.co[:] for v in body.data.vertices], dtype=np.float64)

# Use the existing export as a glove donor; its finger surface already matches IK.
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(ART / 'game_backup/operator_blue.glb'))
imported = set(bpy.data.objects) - before
rig = next(o for o in imported if o.type == 'ARMATURE')
rig.animation_data_clear()
rig.data.pose_position = 'REST'
gloves = next(o for o in imported if o.name == 'Object_115')
gloves.name = 'Soldier_ArticulatedGloves'
gloves.data.materials[0].name = 'Soldier_Gloves'
# Restore external donor image paths after loading the preserved backup.
for im in bpy.data.images:
    if im.source == 'FILE' and not im.packed_file and im.filepath:
        name = Path(im.filepath).name
        candidates = list((GAME / 'assets/operator/textures').rglob(name))
        if candidates:
            im.filepath = str(candidates[0]); im.reload(); im.pack()
for obj in imported:
    if obj not in {rig, gloves}:
        bpy.data.objects.remove(obj, do_unlink=True)
heads = {b.name: b.head_local.copy() for b in rig.data.bones}

mapping = {'Hips':'pelvis', 'Spine02':'spine_01', 'Spine01':'spine_02',
           'Spine':'spine_03', 'neck':'neck_01', 'Head':'head',
           'head_end':'head', 'headfront':'head'}
transforms = {name: Matrix.Identity(4) for name in source_groups}
def segment(source, child, target, target_child):
    a, b = source_heads[source], source_heads[child]
    c, d = heads[target], heads[target_child]
    axis = (b-a).normalized()
    rotation = axis.rotation_difference((d-c).normalized()).to_matrix()
    # Stretch only along the limb. Preserve cloth and equipment thickness.
    scale = Matrix.Identity(3)
    ratio = (d-c).length / (b-a).length
    for row in range(3):
        for col in range(3): scale[row][col] += (ratio-1)*axis[row]*axis[col]
    result = (rotation @ scale).to_4x4()
    result.translation = c - result.to_3x3() @ a
    transforms[source] = result
    return result
for side, suffix in [('Left','l'),('Right','r')]:
    for src, dst in [('Shoulder','clavicle'),('Arm','upperarm'),('ForeArm','lowerarm'),
                     ('Hand','hand'),('UpLeg','thigh'),('Leg','calf'),('Foot','foot'),('ToeBase','ball')]:
        mapping[side+src] = dst+'_'+suffix
    segment(side+'Arm', side+'ForeArm', 'upperarm_'+suffix, 'lowerarm_'+suffix)
    lower = segment(side+'ForeArm', side+'Hand', 'lowerarm_'+suffix, 'hand_'+suffix)
    transforms[side+'Hand'] = lower
    # Shoulder weights blend the rest chest into the raised arm smoothly.
    shoulder = Matrix.Identity(4)
    shoulder.translation = heads['upperarm_'+suffix]-source_heads[side+'Arm']
    transforms[side+'Shoulder'] = shoulder
    segment(side+'UpLeg', side+'Leg', 'thigh_'+suffix, 'calf_'+suffix)
    segment(side+'Leg', side+'Foot', 'calf_'+suffix, 'foot_'+suffix)
    foot = Matrix.Identity(4)
    foot.translation = heads['foot_'+suffix]-source_heads[side+'Foot']
    # Keep the original sole on the floor instead of translating it below zero.
    foot.translation.z = 0.0
    transforms[side+'Foot'] = foot
    transforms[side+'ToeBase'] = foot

fitted = np.zeros_like(original)
for name in source_groups:
    weights = np.array([sum(w for n,w in groups if n == name) for groups in source_weights])
    matrix = np.array(transforms[name], dtype=np.float64)
    fitted += (original @ matrix[:3,:3].T + matrix[:3,3]) * weights[:,None]
body.data.vertices.foreach_set('co', fitted.astype(np.float32).ravel())
body.vertex_groups.clear()
for name in heads: body.vertex_groups.new(name=name)
for index, groups in enumerate(source_weights):
    combined = {}
    for name, weight in groups:
        target = mapping[name]
        combined[target] = combined.get(target, 0.0) + weight
    for name, weight in combined.items(): body.vertex_groups[name].add([index], weight, 'REPLACE')
body.parent = rig
body.matrix_parent_inverse = Matrix.Identity(4)
for modifier in body.modifiers:
    if modifier.type == 'ARMATURE': modifier.object = rig

# Vertex mask separates exposed skin from clothing for the black team material.
# The texture's skin hue refines this broad spatial mask in the game shader.
mask = body.data.color_attributes.new(name='SkinRegion', type='FLOAT_COLOR', domain='POINT')
for i, p in enumerate(original):
    skin_region = float(1.485 < p[2] < 1.70 and abs(p[0]) < .115)
    mask.data[i].color = (1, 1, 1, skin_region)
body.data.color_attributes.active_color = mask

# Replace only the source's unarticulated hands, overlapping the sleeve cuff.
bm = bmesh.new(); bm.from_mesh(body.data)
remove = [v for v in bm.verts if abs(v.co.x) > .748 and v.co.z > 1.22]
bmesh.ops.delete(bm, geom=remove, context='VERTS')
bm.to_mesh(body.data); bm.free()
body.data.update()

# Close the wrist opening with an undersleeve that actually deforms between
# forearm and hand. The source sleeve and donor glove have different cuff
# cross-sections; overlap alone opened a visible gap when the wrist rotated.
cuff_vertices, cuff_faces, cuff_weights, cuff_uvs = [], [], [], []
glove_points = np.array([v.co[:] for v in gloves.data.vertices])
for side, sign in [('l',1),('r',-1)]:
    sleeve_points = fitted[np.abs(fitted[:,0] - sign*.72) < .004]
    hand_points = glove_points[np.abs(glove_points[:,0] - sign*.775) < .004]
    sleeve_center = (sleeve_points[:,1:].min(axis=0) + sleeve_points[:,1:].max(axis=0)) * .5
    hand_center = (hand_points[:,1:].min(axis=0) + hand_points[:,1:].max(axis=0)) * .5
    sleeve_radius = np.ptp(sleeve_points[:,1:], axis=0) * .48
    hand_radius = np.ptp(hand_points[:,1:], axis=0) * .32
    start = len(cuff_vertices)
    segments, rings = 48, 9
    for ring in range(rings):
        t = ring/(rings-1)
        center = sleeve_center*(1-t) + hand_center*t
        radius = sleeve_radius*(1-t) + hand_radius*t
        # A rib at the cuff opening makes the join read as fitted clothing.
        radius *= 1 + .035*math.sin(t*math.pi*8)
        hand_weight = t*t*(3-2*t)
        for segment_index in range(segments):
            angle = segment_index/segments*2*math.pi
            cuff_vertices.append((sign*(.715+.060*t), center[0]+radius[0]*math.cos(angle), center[1]+radius[1]*math.sin(angle)))
            cuff_weights.append((side, hand_weight))
            cuff_uvs.append((segment_index/segments, t))
    for ring in range(rings-1):
        for segment_index in range(segments):
            a=start+ring*segments+segment_index; b=start+ring*segments+(segment_index+1)%segments
            face=(a,b,b+segments,a+segments)
            cuff_faces.append(face if sign>0 else tuple(reversed(face)))
cuff_mesh = bpy.data.meshes.new('WristCuff_ContinuousSkin')
cuff_mesh.from_pydata(cuff_vertices, [], cuff_faces); cuff_mesh.update()
cuffs = bpy.data.objects.new('Soldier_WristCuffs', cuff_mesh)
bpy.context.scene.collection.objects.link(cuffs)
cuffs.parent=rig; cuffs.modifiers.new('Forearm to hand skin','ARMATURE').object=rig
for side in ['l','r']:
    cuffs.vertex_groups.new(name='lowerarm_'+side)
    cuffs.vertex_groups.new(name='hand_'+side)
for index,(side,weight) in enumerate(cuff_weights):
    if weight<1: cuffs.vertex_groups['lowerarm_'+side].add([index],1-weight,'REPLACE')
    if weight>0: cuffs.vertex_groups['hand_'+side].add([index],weight,'REPLACE')
uv = cuff_mesh.uv_layers.new(name='UVMap')
for face in cuff_mesh.polygons:
    for loop_index in face.loop_indices:
        uv.data[loop_index].uv=cuff_uvs[cuff_mesh.loops[loop_index].vertex_index]
cuff_material = bpy.data.materials.new('Soldier_Cuff')
cuff_material.use_nodes = True
cuff_material.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value = (.065,.075,.052,1)
cuff_material.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value = .94
cuff_mesh.materials.append(cuff_material)

# A separate head retains full shadow casting while hidden from the FP camera.
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True); bpy.context.view_layer.objects.active = body
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='DESELECT')
bm = bmesh.from_edit_mesh(body.data)
for face in bm.faces:
    center = face.calc_center_median()
    face.select_set(center.z > 1.495 and abs(center.x) < .16)
bmesh.update_edit_mesh(body.data)
bpy.ops.mesh.separate(type='SELECTED'); bpy.ops.object.mode_set(mode='OBJECT')
head = next(o for o in bpy.context.selected_objects if o != body)
head.name = 'HeadKit_Soldier'
body.name = 'Soldier_Uniform'
body.data.materials[0].name = 'Soldier_4K_PBR'

# The original carrier is integrated into the scan; armor is represented by
# plates inside it, so the outside carrier remains present when armor is spent.
armor = bpy.data.objects.new('ArmorState', None)
bpy.context.scene.collection.objects.link(armor)
armor.parent = rig

# Invisible, skinned eye anchor; its center supplies the first-person camera.
mesh = bpy.data.meshes.new('EyeAnchor')
mesh.from_pydata([(-.001,-.112,1.65),(.001,-.112,1.65),(0,-.112,1.651)], [], [(0,1,2)])
eyes = bpy.data.objects.new('OperatorEyes', mesh)
bpy.context.scene.collection.objects.link(eyes); eyes.parent = rig
eyes.vertex_groups.new(name='head').add([0,1,2],1.0,'REPLACE')
eyes.modifiers.new('Skin','ARMATURE').object = rig

for obj in [body,head,gloves,eyes,cuffs]:
    for face in obj.data.polygons: face.use_smooth = True
bpy.data.objects.remove(source_rig, do_unlink=True)
rig.name = 'Operator'
rig.data.name = 'Mesh2Motion_AllFingers'
bpy.ops.object.select_all(action='DESELECT')
for obj in [rig,body,head,gloves,eyes,armor,cuffs]: obj.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(OUT / 'soldier_fitted.glb'), export_format='GLB',
    use_selection=True, export_animations=False, export_skins=True,
    export_all_influences=False, export_yup=True, export_texcoords=True,
    export_normals=True, export_materials='EXPORT', export_cameras=False,
    export_lights=False, export_image_format='AUTO',
    export_vertex_color='ACTIVE', export_all_vertex_colors=False)
bpy.ops.wm.save_as_mainfile(filepath=str(ART / 'soldier_game_rig.blend'))
print('FITTED', [(o.name,len(o.data.polygons)) for o in [body,head,gloves,cuffs]], flush=True)
