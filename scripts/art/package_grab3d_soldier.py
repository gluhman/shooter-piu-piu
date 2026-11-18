"""Package fitted soldier geometry with the unmodified 66-bone rig and 14 clips."""
import copy
import json
from pathlib import Path
from build_operator_variants import GLB, ROOT

ART = ROOT.parent / 'art/player'
rig = json.loads((ROOT / 'assets/animations/mesh2motion/rig.json').read_text())
reference = GLB(ROOT / 'assets/animations/mesh2motion/reference.glb')
glb = GLB(ART / 'game_export/soldier_fitted.glb')
g = glb.g
native_indices = {b['name']:i for i,b in enumerate(rig['bones'])}
meshes = []
for node in g['nodes']:
    if 'mesh' not in node: continue
    joint_map = [native_indices[g['nodes'][j]['name']] for j in g['skins'][node['skin']]['joints']]
    for primitive in g['meshes'][node['mesh']]['primitives']:
        attrs = primitive['attributes']
        joints = glb.read_accessor(attrs['JOINTS_0'])
        attrs['JOINTS_0'] = glb.accessor([[joint_map[i] for i in row] for row in joints], 'VEC4', 5123)
        assert all(abs(sum(w)-1) < .001 for w in glb.read_accessor(attrs['WEIGHTS_0']))
        assert all(all(abs(v) < 10 for v in row) for row in glb.read_accessor(attrs['POSITION']))
    meshes.append({'name':node['name'], 'mesh':node['mesh'], 'skin':0})
g['nodes'] = [{'name':'Operator', 'children':[]}]
for bone in rig['bones']:
    g['nodes'].append({'name':bone['name'], 'translation':bone['position'],
                       'rotation':bone['quaternion'], 'scale':bone['scale']})
for i,bone in enumerate(rig['bones']):
    g['nodes'][bone['parent']+1].setdefault('children', []).append(i+1)
g['skins'] = [{'name':'Mesh2Motion_AllFingers', 'skeleton':1, 'joints':list(range(1,67)),
               'inverseBindMatrices':glb.accessor([b['inverseBind'] for b in rig['bones']], 'MAT4')}]
for mesh in meshes:
    g['nodes'][0]['children'].append(len(g['nodes'])); g['nodes'].append(mesh)
g['nodes'][0]['children'].append(len(g['nodes'])); g['nodes'].append({'name':'ArmorState'})
g['scenes'] = [{'name':'Operator', 'nodes':[0]}]; g['scene'] = 0
g['animations'] = []
for source in reference.g['animations']:
    clip = copy.deepcopy(source)
    for sampler in clip['samplers']:
        for key in ['input','output']:
            old = reference.g['accessors'][sampler[key]]
            values = reference.read_accessor(sampler[key])
            if old['type'] == 'SCALAR': values = [v[0] for v in values]
            sampler[key] = glb.accessor(values, old['type'], old['componentType'], bounds=key=='input')
    for channel in clip['channels']:
        name = reference.g['nodes'][channel['target']['node']]['name']
        channel['target']['node'] = native_indices[name]+1
    g['animations'].append(clip)
g['asset']['extras'] = {'source':'Grab3D Soldier', 'license':'CC0-1.0',
    'source_url':'https://grab3d.com/models/characters/soldier/',
    'rig':'Mesh2Motion native 66 bones; 14 original clips',
    'hands':'Existing articulated military gloves, fitted at cuffs',
    'surface':'Original 4K PBR textures; vertex alpha is exposed-skin region mask',
    'armor':'Integrated cosmetic carrier remains visible without ballistic plates'}
glb.compact()
for team in ['blue','red']:
    g['asset']['extras']['team'] = team
    glb.write(ROOT / f'assets/operator/variants/operator_{team}.glb')
print('Packaged soldier for both teams:',len(g['animations']),'clips,',len(rig['bones']),'bones')
