"""Independently skin both production gloves and reject grasp-volume intersections.
Run with a Python interpreter providing NumPy after importing gun assets.
"""
import json
import math
import sys
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/art'))
from build_operator_variants import GLB

DIGITS = ['thumb', 'index', 'middle', 'ring', 'pinky']
profiles = json.loads((ROOT / 'assets/weapon_contacts.json').read_text())
bones = json.loads((ROOT / 'assets/animations/mesh2motion/rig.json').read_text())['bones']
by_name = {bone['name']: bone for bone in bones}


def rotation(quaternion):
    x, y, z, w = quaternion
    return np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                     [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                     [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])


def axis_rotation(angle, axis):
    c, s = math.cos(angle), math.sin(angle)
    if axis == 'x':
        return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


failures = []
minimum_clearance = math.inf
for team in ['blue', 'red']:
    glb = GLB(ROOT / f'assets/operator/variants/operator_{team}.glb')
    nodes = glb.g['nodes']
    glove = next(node for node in nodes if node.get('name') == 'Soldier_ArticulatedGloves')
    skin = glb.g['skins'][glove['skin']]
    names = [nodes[index]['name'] for index in skin['joints']]
    binds = np.array(glb.read_accessor(skin['inverseBindMatrices'])).reshape(-1, 4, 4).transpose(0, 2, 1)
    primitive = glb.g['meshes'][glove['mesh']]['primitives'][0]
    attributes = primitive['attributes']
    positions = np.array(glb.read_accessor(attributes['POSITION']))
    positions = np.c_[positions, np.ones(len(positions))]
    indices = np.array(glb.read_accessor(attributes['JOINTS_0']), dtype=int)
    weights = np.array(glb.read_accessor(attributes['WEIGHTS_0']))
    for side, tag in [('right', 'r'), ('left', 'l')]:
        allowed = [i for i, name in enumerate(names) if name == 'hand_' + tag or
                   any(name.startswith(digit + '_') and name.endswith('_' + tag) for digit in DIGITS)]
        selected = (weights * np.isin(indices, allowed)).sum(axis=1) > .999
        local = np.einsum('nvij,nj->nvi', binds[indices[selected]], positions[selected])
        joint_indices, vertex_weights = indices[selected], weights[selected]
        rest = {name: np.linalg.inv(np.array(by_name[name]['inverseBind']).reshape(4, 4).T)
                for name in names if name in by_name}
        hand = rest['hand_' + tag]
        y = rest['middle_01_' + tag][:3, 3] - hand[:3, 3]
        y /= np.linalg.norm(y)
        x = rest['index_01_' + tag][:3, 3] - rest['pinky_01_' + tag][:3, 3]
        x = x / np.linalg.norm(x) * (1 if side == 'right' else -1)
        z = np.cross(x, y)
        z /= np.linalg.norm(z)
        x = np.cross(y, z)
        frame = np.linalg.inv(hand[:3, :3]) @ np.column_stack([x, y, z])
        palm_offset = np.array(by_name['middle_01_' + tag]['position']) * .62
        for weapon, profile in profiles.items():
            data = profile[side]
            model_basis = np.array(data['model_frame']['basis']).T
            model_origin = np.array(data['model_frame']['origin'])
            model_rotation = model_basis / np.linalg.norm(model_basis[:, 0])
            socket = model_rotation @ np.array(data['basis']).T
            if side == 'right' and min(socket[1, 0], -socket[2, 1], -socket[0, 2]) < .8:
                failures.append(f'{team}/{weapon}: trigger palm rolls away from thumb-up, fingers-forward grip')
            if abs(np.linalg.det(socket) - 1.0) > .002:
                failures.append(f'{team}/{weapon}/{side}: reflected or non-orthonormal palm basis')
            hand_basis = socket @ np.linalg.inv(frame)
            palm = model_basis @ np.array(data['palm']) + model_origin + model_rotation @ np.array(data['palm_offset'])
            if weapon == 'gpmg' and side == 'left' and abs(palm[0] - model_origin[0]) > .025:
                failures.append(f'{team}/gpmg: support palm is laterally detached from handguard')
            hand_position = palm - hand_basis @ palm_offset
            matrices = np.repeat(np.eye(4)[None], len(names), axis=0)
            transform = np.eye(4)
            transform[:3, :3], transform[:3, 3] = hand_basis, hand_position
            matrices[names.index('hand_' + tag)] = transform
            for digit, name in enumerate(DIGITS):
                point, basis = hand_position.copy(), hand_basis.copy()
                for joint in range(3):
                    bone_name = f'{name}_0{joint+1}_{tag}'
                    bone = by_name[bone_name]
                    point += basis @ np.array(bone['position'])
                    basis = basis @ rotation(bone['quaternion']) @ axis_rotation(data['curl'][digit][joint], 'x')
                    if joint == 0:
                        basis = basis @ axis_rotation(data['splay'][digit], 'z')
                    transform = np.eye(4)
                    transform[:3, :3], transform[:3, 3] = basis, point
                    matrices[names.index(bone_name)] = transform
                leaf_name = f'{name}_04_leaf_{tag}'
                leaf = by_name[leaf_name]
                point += basis @ np.array(leaf['position'])
                basis = basis @ rotation(leaf['quaternion'])
                transform = np.eye(4)
                transform[:3, :3], transform[:3, 3] = basis, point
                matrices[names.index(leaf_name)] = transform
            vertices = (np.einsum('nvij,nvj->nvi', matrices[joint_indices], local) * vertex_weights[:, :, None]).sum(axis=1)[:, :3]
            planes = np.array(data['volume_planes'])
            clearance = (vertices @ planes[:, :3].T + planes[:, 3]).max(axis=1)
            minimum_clearance = min(minimum_clearance, float(clearance.min()))
            if not np.isfinite(vertices).all() or clearance.min() < .001:
                failures.append(f'{team}/{weapon}/{side}: minimum clearance {clearance.min()*1000:.3f} mm')
for failure in failures:
    print('FAIL', failure)
print(f'{"FAIL" if failures else "PASS"} {len(profiles)} firearms, both hands and teams; minimum full-glove clearance {minimum_clearance*1000:.3f} mm')
raise SystemExit(bool(failures))
