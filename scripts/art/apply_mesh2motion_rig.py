"""Package the native Mesh2Motion rig/weights/clips without recompressing textures."""
import copy, json, sys
from pathlib import Path
from build_operator_variants import GLB, ROOT, indexed_surface

def groups(values, width):
 return [values[i:i+width] for i in range(0,len(values),width)]

def main():
 data=json.loads(Path('/tmp/piupiu-m2m-native.json').read_text())
 source=Path(sys.argv[1] if len(sys.argv)>1 else '/tmp/piupiu-operator-input')
 for variant in ['blue','red']:
  glb=GLB(source/f'operator_{variant}.glb');g=glb.g
  g['nodes']=[{'name':'Operator','children':[]}]
  g['scenes']=[{'name':'Operator','nodes':[0]}];g['scene']=0
  for i,b in enumerate(data['bones']):
   g['nodes'].append({'name':b['name'],'translation':b['position'],'rotation':b['quaternion'],'scale':b['scale']})
  for i,b in enumerate(data['bones']):
   g['nodes'][b['parent']+1].setdefault('children',[]).append(i+1)
  g['skins']=[{'name':'Mesh2Motion_AllFingers','skeleton':1,'joints':list(range(1,67)),
    'inverseBindMatrices':glb.accessor([b['inverseBind'] for b in data['bones']],'MAT4')}]
  for m in data['variants'][variant]:
   if 'uv' in m:
    surface=indexed_surface({'positions':groups(m['positions'],3),'normals':groups(m['normals'],3),'uv':m['uv'],'joints':groups(m['indices'],4),'weights':groups(m['weights'],4),'indices':m['triangles']})
    m={**m,'positions':[v for p in surface['positions'] for v in p],'normals':[v for p in surface['normals'] for v in p],'uv':surface['uv'],'indices':[v for p in surface['joints'] for v in p],'weights':[v for p in surface['weights'] for v in p],'triangles':surface['indices']}
   a=g['meshes'][m['mesh']]['primitives'][m['primitive']]['attributes']
   a['POSITION']=glb.accessor(groups(m['positions'],3),'VEC3',bounds=True)
   a['NORMAL']=glb.accessor(groups(m['normals'],3),'VEC3')
   a['JOINTS_0']=glb.accessor(groups(m['indices'],4),'VEC4',5123)
   a['WEIGHTS_0']=glb.accessor(groups(m['weights'],4),'VEC4')
   if 'uv' in m:
    a['TEXCOORD_0']=glb.accessor(m['uv'],'VEC2')
    g['meshes'][m['mesh']]['primitives'][m['primitive']]['indices']=glb.accessor(m['triangles'],'SCALAR',5125)
   a.pop('TANGENT',None)
   g['nodes'][0]['children'].append(len(g['nodes']))
   g['nodes'].append({'name':m['name'],'mesh':m['mesh'],'skin':0})
  glb.kit(json.loads(Path('/tmp/piupiu-operator-kit.json').read_text()),variant)
  g['animations']=[];glb.animations(data['clips'])
  g['asset']['extras']={'variant':variant,'rig':'Mesh2Motion human / all-fingers','mesh2motion_commit':data['commit'],
   'bone_count':66,'finger_chains':10,'finger_joints_per_chain':4,'weight_binding':'Anatomical vertex groups transferred to native Mesh2Motion joints; rigid equipment corrections',
   'animation_processing':'AnimationUtility.clean_track_data; no retargeting, resampling or rotation replacement'}
  glb.compact()
  glb.write(ROOT/f'assets/operator/variants/operator_{variant}.glb')
 metadata={k:data[k] for k in ['source','commit','bones']}
 metadata['clips']=[{'name':c['name'],'duration':c['duration'],'tracks':len(c['tracks'])} for c in data['clips']]
 (ROOT/'assets/animations/mesh2motion/rig.json').write_text(json.dumps(metadata,indent=2)+'\n')
 reference=GLB('/tmp/piupiu-mesh2motion/static/assets/human/model.glb')
 reference.g['animations']=[];reference.animations(data['clips'])
 reference.write(ROOT/'assets/animations/mesh2motion/reference.glb')
 print('Packaged 2 operators with the native 66-bone Mesh2Motion skeleton and 14 unchanged source sequences.')
if __name__=='__main__':main()
