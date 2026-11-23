"""Geometry regressions that animation-only rig tests cannot detect."""
import math
from collections import Counter
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
    # The visible glove-side wrist must retain its cross-section under a
    # half-turn of palm roll, where linear skin blending can collapse a ring.
    rings={}
    for p,ii,ww in zip(positions,indices,weights):
     if not .745 <= abs(p[0]) <= .765:continue
     hand=sum(w for j,w in zip(ii,ww) if names[j].startswith('hand_'))
     rings.setdefault(round(p[0],5),[]).append([p[1]*(1-2*hand),p[2]*(1-2*hand)])
    for ring in rings.values():
     spans=[max(p[k] for p in ring)-min(p[k] for p in ring) for k in [0,1]]
     assert min(spans)>.045, 'Visible wrist collapses to a narrow neck during palm roll'
    # Weld UV seams before checking topology: an open ring can look acceptable
    # from above but exposes an empty sleeve-to-glove join from the side.
    keys=[tuple(round(v,6) for v in point) for point in positions]
    edges=Counter()
    for triangle in range(0,len(faces),3):
     ids=faces[triangle:triangle+3]
     for k in range(3):edges[tuple(sorted([keys[ids[k]],keys[ids[(k+1)%3]]]))]+=1
    assert edges and all(count==2 for count in edges.values()), 'Wrist bridge has an open edge'
    assert min(p[0] for p in positions)<-.79 and max(p[0] for p in positions)>.79, 'Bridge must overlap inside both palms'
   if 'COLOR_0' in a:skin_samples.extend(c[3] for c in glb.read_accessor(a['COLOR_0']))
  if node.get('name')=='Soldier_ArticulatedGloves':
   # The glove and its new fabric closures use separate materials but must
   # form one sealed surface, with matching boundary positions and weights.
   combined=[];combined_faces=[]
   for primitive in g['meshes'][node['mesh']]['primitives']:
    start=len(combined)
    combined.extend(glb.read_accessor(primitive['attributes']['POSITION']))
    combined_faces.extend(i[0]+start for i in glb.read_accessor(primitive['indices']))
   keys=[tuple(round(v,6) for v in point) for point in combined];edges=Counter()
   for triangle in range(0,len(combined_faces),3):
    ids=combined_faces[triangle:triangle+3]
    for k in range(3):edges[tuple(sorted([keys[ids[k]],keys[ids[(k+1)%3]]]))]+=1
   assert all(count==2 for count in edges.values()), 'Glove wrist closure has an open edge'
 assert skin_samples and min(skin_samples)<.01 and max(skin_samples)>.99,'Exposed-skin recolor mask missing'
 assert triangles>700000,'High-detail source geometry was unexpectedly reduced'
 assert len(finger_weights)>=30,'Articulated glove weights missing'
 print(f'PASS {team}: {triangles:,} triangles, {surfaces} surfaces; normalized native weights, articulated gloves, exposed-skin mask')
for team in ['blue','red']:check_model(team)
