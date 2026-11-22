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
    if axis == 'y':
        return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
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
            if side == 'left' and weapon not in ['deagle', 'm1911', 'tec9', 'mac10']:
                vertical = data.get('support_kind') == 'vertical_grip'
                if vertical and socket[0, 2] < .95:
                    failures.append(f'{team}/{weapon}: support palm does not face the front grip')
                if not vertical and socket[1, 2] < .985:
                    failures.append(f'{team}/{weapon}: handguard must rest on an upward-facing palm')
                if (not vertical and socket[0, 1] < .3) or palm[0] > model_origin[0] + .025:
                    failures.append(f'{team}/{weapon}: support hand approaches from the right')
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
                        if digit == 0: basis = basis @ axis_rotation(data.get('thumb_roll', 0.0), 'y')
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
            if side == 'left' and data.get('thumb_pose') == 'relaxed_forward':
                thumb_base = matrices[names.index('thumb_01_l'), :3, 3]
                thumb_tip = matrices[names.index('thumb_04_leaf_l'), :3, 3]
                thumb_axis = thumb_tip - thumb_base
                thumb_axis /= np.linalg.norm(thumb_axis)
                thumb_slots = [i for i, name in enumerate(names) if name.startswith('thumb_') and name.endswith('_l')]
                finger_slots = [i for i, name in enumerate(names) if any(name.startswith(d + '_') for d in DIGITS[1:]) and name.endswith('_l')]
                thumb_mask = (vertex_weights * np.isin(joint_indices, thumb_slots)).sum(1) > .35
                finger_mask = (vertex_weights * np.isin(joint_indices, finger_slots)).sum(1) > .35
                difference = np.percentile(vertices[thumb_mask, 1], 98) - np.percentile(vertices[finger_mask, 1], 98)
                if thumb_axis[2] > .2 or thumb_tip[0] > model_origin[0] + .005 or not -.020 <= difference <= .010:
                    failures.append(f'{team}/{weapon}: support thumb must stay left and level with the curled fingers ({difference*1000:.1f} mm)')
            if side == 'left' and data.get('support_kind') in ['handguard', 'vertical_grip']:
                hand_skin = (vertex_weights * (joint_indices == names.index('hand_' + tag))).sum(1) > .8
                normal = np.array([-1., 0., 0.]) if data['support_kind'] == 'vertical_grip' else np.array([0., -1., 0.])
                surface = model_basis @ np.array(data['palm']) + model_origin
                gap = np.linalg.norm(vertices[hand_skin] - (surface + normal * .002), axis=1).min()
                if gap > .012:
                    failures.append(f'{team}/{weapon}: palm tissue floats {gap*1000:.1f} mm from its support surface')
                if '--dump-contact-skin' in sys.argv and team == 'blue':
                    digit_masks = []
                    for digit in DIGITS:
                        slots = [i for i, name in enumerate(names) if name in [f'{digit}_03_{tag}', f'{digit}_04_leaf_{tag}']]
                        digit_masks.append((vertex_weights * np.isin(joint_indices, slots)).sum(1) > .35)
                    np.savez('/tmp/weapon-contact-skin-' + weapon + '.npz', vertices=vertices, hand_mask=hand_skin, digit_masks=np.array(digit_masks))
            planes = np.array(data['volume_planes'])
            clearance = (vertices @ planes[:, :3].T + planes[:, 3]).max(axis=1)
            minimum_clearance = min(minimum_clearance, float(clearance.min()))
            if not np.isfinite(vertices).all() or clearance.min() < .001:
                failures.append(f'{team}/{weapon}/{side}: minimum clearance {clearance.min()*1000:.3f} mm')
for failure in failures:
    print('FAIL', failure)
print(f'{"FAIL" if failures else "PASS"} {len(profiles)} firearms, both hands and teams; minimum full-glove clearance {minimum_clearance*1000:.3f} mm')
raise SystemExit(bool(failures))
