"""Geometry regressions that animation-only rig tests cannot detect."""
import math
from build_operator_variants import GLB, ROOT

def check_model(team):
 glb=GLB(ROOT/f'assets/operator/variants/operator_{team}.glb');g=glb.g
 triangles=0;surfaces=0;skin_samples=[];finger_weights=set()
 for node in g['nodes']:
  if 'mesh' not in node:continue
  joints=g['skins'][node['skin']]['joints'];names=[g['nodes'][i]['name'] for i in joints]
  assert len(names)==66
  for primitive in g['meshes'][node['mesh']]['primitives']:
   a=primitive['attributes'];positions=glb.read_accessor(a['POSITION']);indices=glb.read_accessor(a['JOINTS_0']);weights=glb.read_accessor(a['WEIGHTS_0'])
   faces=[x[0] for x in glb.read_accessor(primitive['indices'])];triangles+=len(faces)//3;surfaces+=1
   for p,ii,ww in zip(positions,indices,weights):
    assert all(math.isfinite(v) for v in p),node['name']+' has nonfinite geometry'
    assert abs(sum(ww)-1)<.0001,node['name']+' has unnormalized weights'
    assert all(0<=j<66 for j,w in zip(ii,ww) if w>0)
   if node['name']=='Soldier_ArticulatedGloves':
    for ii,ww in zip(indices,weights):
     finger_weights.update(names[j] for j,w in zip(ii,ww) if w>.01 and any(f in names[j] for f in ['thumb','index','middle','ring','pinky']))
   if node['name']=='Soldier_WristCuffs':
    for side in ['l','r']:
     assert any({names[j] for j,w in zip(ii,ww) if w>.05}=={'lowerarm_'+side,'hand_'+side} for ii,ww in zip(indices,weights)), 'Wrist cuff must blend continuously between forearm and hand'
   if 'COLOR_0' in a:skin_samples.extend(c[3] for c in glb.read_accessor(a['COLOR_0']))
 assert skin_samples and min(skin_samples)<.01 and max(skin_samples)>.99,'Exposed-skin recolor mask missing'
 assert triangles>700000,'High-detail source geometry was unexpectedly reduced'
 assert len(finger_weights)>=30,'Articulated glove weights missing'
 print(f'PASS {team}: {triangles:,} triangles, {surfaces} surfaces; normalized native weights, articulated gloves, exposed-skin mask')
for team in ['blue','red']:check_model(team)
