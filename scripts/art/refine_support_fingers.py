"""Refine fitted support fingers against exact gun triangles without moving the palm.
Blender --background --python this_file [-- --weapons id,id]
Requires bake_weapon_contacts.gd -- --contact-surfaces and the fitted profiles.
--thumb-height-offset <metres> sets a per-profile offset below/above finger height.
"""
import json,sys,math
from pathlib import Path
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'scripts/art'))
from build_operator_variants import GLB
np.seterr(all='ignore')
DIGITS=['thumb','index','middle','ring','pinky']
def rx(a):
 c,s=np.cos(a),np.sin(a);return np.array([[1,0,0],[0,c,-s],[0,s,c]])
def rz(a):
 c,s=np.cos(a),np.sin(a);return np.array([[c,-s,0],[s,c,0],[0,0,1]])
def ry(a):
 c,s=np.cos(a),np.sin(a);return np.array([[c,0,s],[0,1,0],[-s,0,c]])
def mat(a):return np.array(a,float).T
source=json.load(open('/tmp/weapon-fit-input.json'));rig=source['rig']['left'];frame=mat(rig['frame']);offset=np.array(rig['offset']);scale=np.array(rig['scale'])
glb=GLB(ROOT/'assets/operator/variants/operator_blue.glb');g=glb.g
node=next(n for n in g['nodes'] if n.get('name')=='Soldier_ArticulatedGloves');skin=g['skins'][node['skin']];names=[g['nodes'][n]['name'] for n in skin['joints']]
bind=np.array(glb.read_accessor(skin['inverseBindMatrices'])).reshape(-1,4,4).transpose(0,2,1)
a=g['meshes'][node['mesh']]['primitives'][0]['attributes'];P=np.array(glb.read_accessor(a['POSITION']));P=np.c_[P,np.ones(len(P))];I=np.array(glb.read_accessor(a['JOINTS_0']),int);W=np.array(glb.read_accessor(a['WEIGHTS_0']))
allowed=[i for i,n in enumerate(names) if n=='hand_l' or any(n.startswith(d+'_') and n.endswith('_l') for d in DIGITS)];keep=(W*np.isin(I,allowed)).sum(1)>.999
L=np.einsum('nvij,nj->nvi',bind[I[keep]],P[keep]);W=W[keep];I=I[keep]
remap={'hand_l':0}
for d,digit in enumerate(DIGITS):
 for j in range(4):remap[f'{digit}_0{j+1}'+('_leaf' if j==3 else '')+'_l']=1+d*4+j
M=np.array([[remap.get(names[k],0) for k in row] for row in I])
profiles=json.loads((ROOT/'assets/weapon_contacts.json').read_text())
for name,profile in profiles.items():
 data=profile['left']
 if not data.get('support_kind'):continue
 height_reference='--thumb-height-reference' in sys.argv
 if height_reference and data.get('support_kind')!='handguard':continue
 if '--weapons' in sys.argv and name not in sys.argv[sys.argv.index('--weapons')+1].split(','):continue
 mb=mat(data['model_frame']['basis']);origin=np.array(data['model_frame']['origin']);rotation=mb/np.linalg.norm(mb[:,0]);socket=rotation@mat(data['basis']);H=socket@np.linalg.inv(frame)
 palm=mb@np.array(data['palm'])+origin+rotation@np.array(data['palm_offset']);wrist=palm-H@(offset*scale);planes=np.array(data['volume_planes'])
 faces=np.fromfile('/tmp/weapon-surface-'+name+'.bin',dtype=np.float32).reshape(-1,3);tree=BVHTree.FromPolygons([Vector(p) for p in faces],[(i,i+1,i+2) for i in range(0,len(faces),3)],all_triangles=True)
 curls=np.array(data['curl']);splay=np.array(data['splay']);matrices=np.repeat(np.eye(4)[None],21,axis=0);matrices[0,:3,:3]=H;matrices[0,:3,3]=wrist
 thumb_roll=float(data.get('thumb_roll',0.0))
 for d in range(5):
  pos=wrist.copy();B=H.copy()
  for j,joint in enumerate(rig['chains'][d]):
   pos=pos+B@(np.array(joint['origin'])*scale);B=B@mat(joint['basis'])
   if j<3:
    B=B@rx(curls[d,j])
    if j==0:
     B=B@rz(splay[d])
     if d==0:B=B@ry(thumb_roll)
   matrices[1+d*4+j,:3,:3]=B;matrices[1+d*4+j,:3,3]=pos
 all_vertices=(np.einsum('nvij,nvj->nvi',matrices[M],L)*W[:,:,None]).sum(1)[:,:3]
 other_fingers=((M>=5)&(W>.35)).any(1)
 thumb_height_offset=float(data.get('thumb_height_offset_m',0.0))
 if '--thumb-height-offset' in sys.argv:
  thumb_height_offset=float(sys.argv[sys.argv.index('--thumb-height-offset')+1])
 target_top=float(np.percentile(all_vertices[other_fingers,1],98))+thumb_height_offset
 gaps=list(data.get('skin_contact_error_m',[0.]*5)) if height_reference else []
 for digit in range(5):
  if height_reference and digit!=0:continue
  if not height_reference and digit==0 and data.get("thumb_reference"):continue
  affected=((M>=1+digit*4)&(M<=4+digit*4)&(W>.001)).any(1);l,m,w=L[affected],M[affected],W[affected]
  distal=(((m==3+digit*4)|(m==4+digit*4))&(w>.35)).any(1)
  chain=[(np.array(j['origin']),mat(j['basis'])) for j in rig['chains'][digit]]
  def skin_finger(x):
   pos=wrist.copy();B=H.copy()
   for j,(p,b) in enumerate(chain):
    pos=pos+B@(p*scale);B=B@b
    if j<3:
     B=B@rx(x[j])
     if j==0:
      B=B@rz(x[3])
      if digit==0:B=B@ry(x[4] if height_reference else thumb_roll)
    T=matrices[1+digit*4+j];T[:3,:3]=B;T[:3,3]=pos
   return (np.einsum('nvij,nvj->nvi',matrices[m],l)*w[:,:,None]).sum(1)[:,:3]
  def contact(v):
   best=math.inf
   for point in v[distal]:
    hit,_,_,gap=tree.find_nearest(Vector(point))
    if hit is not None and abs(hit.z-palm[2])<.13:best=min(best,gap)
   return best
  old=np.r_[curls[digit],splay[digit]];lo=np.array([-.05,-.05,-.05,-.9 if digit==0 else -.25]);hi=np.array([1.55,1.55,1.55,.9 if digit==0 else .25])
  if height_reference:
   old=np.r_[old,thumb_roll];lo=np.array([-3.1,-.05,-.05,-3.1,-3.1]);hi=np.array([3.1,1.3,1.3,3.1,3.1])
  thumb_mask=(((m>=1)&(m<=4))*w).sum(1)>.35
  def residual(x):
   v=skin_finger(x);sdf=(v@planes[:,:3].T+planes[:,3]).max(1)
   reference=np.empty(0)
   if height_reference:
    axis=matrices[4,:3,3]-matrices[1,:3,3];axis/=max(np.linalg.norm(axis),1e-8)
    desired=np.array([0.,.20,-.98]);desired/=np.linalg.norm(desired)
    top=float(np.percentile(v[thumb_mask,1],98))
    reference=np.r_[(top-target_top)*120.,(axis-desired)*.65,max(0.,matrices[4,0,3]-origin[0]+.008)*25.]
   return np.r_[(contact(v)-.0025)*(15 if height_reference else 70),np.maximum(.003-sdf,0)*30,reference,(x-old)*.003]
  old_vertices=skin_finger(old);old_clearance=(old_vertices@planes[:,:3].T+planes[:,3]).max(1).min()
  best=(np.linalg.norm(residual(old)) if old_clearance>=.002 else math.inf,old.copy())
  starts=[old]
  if not height_reference and (contact(skin_finger(old))>.012 or old_clearance<.002):
   starts.extend(np.array([a,b,c,s]) for a,b,c in [(0.,0.,0.),(.1,.2,.2),(.5,.5,.5),(1.,.3,.2),(.2,1.2,1.2)] for s in [old[3],-.2,.2])
   for q in starts:
    v=skin_finger(q);clearance=(v@planes[:,:3].T+planes[:,3]).max(1).min();cost=np.linalg.norm(residual(q))
    if clearance>=.002 and cost<best[0]:best=(cost,q.copy())
  if height_reference:
   def thumb_axis(q):
    pos=wrist.copy();B=H.copy();base=None
    for j,(p,b) in enumerate(chain):
     pos=pos+B@(p*scale);B=B@b
     if j==0:base=pos.copy()
     if j<3:
      B=B@rx(q[j])
      if j==0:B=B@rz(q[3])@ry(q[4])
    axis=pos-base;return axis/max(np.linalg.norm(axis),1e-8)
   desired=np.array([0.,.20,-.98]);desired/=np.linalg.norm(desired)
   candidates=[]
   for direction in [[0.,.2,-.98],[0.,.6,-.8],[0.,.85,-.53],[-.4,.7,-.59]]:
    desired=np.array(direction);desired/=np.linalg.norm(desired)
    for roll in np.linspace(-3.1,3.1,25):
     q=np.array([.15,.20,.20,1.0,roll])
     for step in range(30):
      axis=thumb_axis(q);error=axis-desired;J=np.empty((3,2))
      for k,index in enumerate([0,3]):
       trial=q.copy();trial[index]+=.0002;J[:,k]=(thumb_axis(trial)-axis)/.0002
      delta=np.linalg.solve(J.T@J+np.eye(2)*.0001,-J.T@error)
      q[[0,3]]=np.clip(q[[0,3]]+np.clip(delta,-.2,.2),lo[[0,3]],hi[[0,3]])
     v=skin_finger(q);clearance=(v@planes[:,:3].T+planes[:,3]).max(1).min()
     if clearance>=.002:candidates.append((np.linalg.norm(residual(q)),q.copy()))
   rng=np.random.default_rng(19)
   random_candidates=[]
   for trial in range(6000):
    q=rng.uniform(lo,hi);v=skin_finger(q)
    clearance=(v@planes[:,:3].T+planes[:,3]).max(1).min()
    if clearance<.002:continue
    axis=matrices[4,:3,3]-matrices[1,:3,3];axis/=max(np.linalg.norm(axis),1e-8)
    if axis[2]>.2 or matrices[4,0,3]>origin[0]+.005:continue
    height=abs(float(np.percentile(v[thumb_mask,1],98))-target_top)
    random_candidates.append((height,q.copy()))
   candidates.extend((np.linalg.norm(residual(q)),q) for _,q in sorted(random_candidates,key=lambda item:item[0])[:12])
   starts.extend(q for _,q in sorted(candidates,key=lambda item:item[0])[:4])
   for q in starts:
    v=skin_finger(q);clearance=(v@planes[:,:3].T+planes[:,3]).max(1).min();cost=np.linalg.norm(residual(q))
    if clearance>=.002 and cost<best[0]:best=(cost,q.copy())
  for start in starts:
   x=np.clip(start,lo,hi);lam=.0001
   for iteration in range(75):
    r=residual(x);J=np.empty((len(r),len(x)))
    for i in range(len(x)):
     xp=x.copy();xp[i]+=.0002;J[:,i]=(residual(xp)-r)/.0002
    dx=np.linalg.solve(J.T@J+np.eye(len(x))*lam,-J.T@r);trial=np.clip(x+np.clip(dx,-.18,.18),lo,hi)
    if np.linalg.norm(residual(trial))<np.linalg.norm(r):x=trial;lam=max(1e-8,lam*.7)
    else:lam=min(.1,lam*3)
    v=skin_finger(x);clearance=(v@planes[:,:3].T+planes[:,3]).max(1).min();cost=np.linalg.norm(residual(x))
    if clearance>=.002 and cost<best[0]:best=(cost,x.copy())
    if np.linalg.norm(dx)<1e-5:break
  if not math.isfinite(best[0]):raise RuntimeError(name+': no collision-free '+DIGITS[digit]+' pose')
  x=best[1];curls[digit]=x[:3];splay[digit]=x[3]
  vertices=skin_finger(x);gap=contact(vertices)
  if height_reference:
   gaps[digit]=gap;thumb_roll=float(x[4])
   contacts=[]
   for point in vertices[distal]:
    hit,_,_,distance=tree.find_nearest(Vector(point))
    if hit is not None and abs(hit.z-palm[2])<.13:
     surface=np.array(hit);normal=(point-surface)/max(distance,1e-8)
     contacts.append((distance,surface,normal))
   _,surface,normal=min(contacts,key=lambda item:item[0])
   data['thumb']=(np.linalg.inv(mb)@(surface-origin)).tolist()
   data['thumb_normal']=(np.linalg.inv(rotation)@normal).tolist()
  else:gaps.append(gap)
 data['curl']=curls.tolist();data['splay']=splay.tolist();data['skin_contact_error_m']=gaps
 if height_reference:
  data['thumb_roll']=thumb_roll;data['thumb_reference']=True;data['thumb_pose']='relaxed_forward'
  if thumb_height_offset:data['thumb_height_offset_m']=thumb_height_offset
  else:data.pop('thumb_height_offset_m',None)
 print('FINGERS',name,[round(g*1000,1) for g in gaps],flush=True)
(ROOT/'assets/weapon_contacts.json').write_text(json.dumps(profiles,indent=2)+'\n')
