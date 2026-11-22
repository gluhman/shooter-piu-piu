"""Author final support anchors from the fitted palm/finger skin and exact gun triangles.
Run bake_weapon_contacts.gd -- --contact-surfaces, then the independent skin test
with --dump-contact-skin, then Blender --background --python this_file.
Changing an anchor preserves the skeletal palm target and all joint poses.
"""
import json,sys
from pathlib import Path
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2]
path=ROOT/'assets/weapon_contacts.json'
profiles=json.loads(path.read_text())
digits=['thumb','index','middle','ring','pinky']
for name,profile in profiles.items():
 data=profile['left'];kind=data.get('support_kind')
 if kind not in ['handguard','vertical_grip']:continue
 faces=np.fromfile('/tmp/weapon-surface-'+name+'.bin',dtype=np.float32).reshape(-1,3)
 tree=BVHTree.FromPolygons([Vector(p) for p in faces],[(i,i+1,i+2) for i in range(0,len(faces),3)],all_triangles=True)
 skin=np.load('/tmp/weapon-contact-skin-'+name+'.npz');vertices=skin['vertices']
 M=np.array(data['model_frame']['basis']).T;o=np.array(data['model_frame']['origin']);rotation=M/np.linalg.norm(M[:,0])
 inv=np.linalg.inv(M);old=M@np.array(data['palm'])+o
 target=old+rotation@np.array(data['palm_offset'])
 candidates=[]
 for point in vertices[skin['hand_mask']]:
  hit,normal,_,distance=tree.find_nearest(Vector(point))
  if hit is None:continue
  hit=np.array(hit);normal=(point-hit)/max(distance,1e-8)
  if abs(hit[2]-old[2])>.07 or abs(hit[1]-old[1])>.07:continue
  if kind=='handguard' and normal[1]>-.15:continue
  if kind=='vertical_grip' and normal[0]>-.3:continue
  candidates.append((distance,hit,normal))
 if not candidates:raise RuntimeError(name+': no contact on intended support surface')
 distance,point,normal=min(candidates,key=lambda c:c[0])
 data['palm']=list(inv@(point-o));data['palm_offset']=list(np.linalg.inv(rotation)@(target-point))
 data['palm_normal']=list(np.linalg.inv(rotation)@normal)
 data['palm_skin_gap_m']=float(distance)
 gaps=[]
 for i,digit in enumerate(digits):
  candidates=[]
  for point in vertices[skin['digit_masks'][i]]:
   hit,normal,_,gap=tree.find_nearest(Vector(point))
   if hit is not None:
    hit=np.array(hit);normal=(point-hit)/max(gap,1e-8);candidates.append((gap,hit,normal))
  if not candidates:raise RuntimeError(name+': no '+digit+' surface contact')
  gap,point,normal=min(candidates,key=lambda c:c[0])
  data[digit]=list(inv@(point-o));data[digit+'_normal']=list(np.linalg.inv(rotation)@normal);gaps.append(float(gap))
 data['skin_contact_error_m']=gaps
 print('SURFACE',name,'palm mm',round(distance*1000,2),'digits mm',[round(g*1000,2) for g in gaps],flush=True)
path.write_text(json.dumps(profiles,indent=2)+'\n')
