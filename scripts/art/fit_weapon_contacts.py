"""Fit the real articulated glove skin against firearm contact surfaces.
Run with Blender after bake_weapon_contacts.gd and weapon_contact_gallery.tscn.
Inputs are temporary measurements in /tmp; output is assets/weapon_contacts.json.
"""
import sys,json,math,numpy as np,bpy,bmesh
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/art'))
from build_operator_variants import GLB
np.seterr(divide='ignore', over='ignore', invalid='ignore')
source=json.load(open('/tmp/weapon-fit-input.json'));arm_geometry=json.load(open('/tmp/weapon-arm-geometry.json'))
DIGITS=['thumb','index','middle','ring','pinky']
def rx(x):
 c,s=np.cos(x),np.sin(x);return np.array([[1,0,0],[0,c,-s],[0,s,c]])
def ry(x):
 c,s=np.cos(x),np.sin(x);return np.array([[c,0,s],[0,1,0],[-s,0,c]])
def rz(x):
 c,s=np.cos(x),np.sin(x);return np.array([[c,-s,0],[s,c,0],[0,0,1]])
def mat(a):return np.array(a,dtype=float).T
def hull(points):
 bm=bmesh.new()
 for p in points:bm.verts.new(p.tolist())
 bmesh.ops.convex_hull(bm,input=list(bm.verts),use_existing_faces=False)
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
 planes=[];seen=set()
 for f in bm.faces:
  n=np.array(f.normal);d=-n@np.array(f.verts[0].co);key=tuple(np.round(np.r_[n,d],4))
  if key not in seen:planes.append(np.r_[n,d]);seen.add(key)
 bm.free();return np.array(planes)
glb=GLB(ROOT/'assets/operator/variants/operator_blue.glb');g=glb.g
skin_data={}
for node in g['nodes']:
 if node.get('name')!='Soldier_ArticulatedGloves':continue
 skin=g['skins'][node['skin']];names=[g['nodes'][n]['name'] for n in skin['joints']];bind=np.array(glb.read_accessor(skin['inverseBindMatrices'])).reshape(-1,4,4).transpose(0,2,1)
 for primitive in g['meshes'][node['mesh']]['primitives']:
  a=primitive['attributes'];P=np.c_[np.array(glb.read_accessor(a['POSITION'])),np.ones(g['accessors'][a['POSITION']]['count'])];I=np.array(glb.read_accessor(a['JOINTS_0']),int);W=np.array(glb.read_accessor(a['WEIGHTS_0']))
  for side,tag in [('right','r'),('left','l')]:
   allowed=[i for i,n in enumerate(names) if n=='hand_'+tag or any(n.startswith(d+'_') and n.endswith('_'+tag) for d in DIGITS)]
   selected=np.isin(I,allowed);keep=(W*selected).sum(1)>.999
   pp=P[keep];ii=I[keep];ww=W[keep]
   # Keep all vertices in final validation, voxel-sample the objective for speed.
   local=np.einsum('nvij,nj->nvi',bind[ii],pp)
   keys=np.round(pp[:,:3]/.004).astype(int);_,sample=np.unique(keys,axis=0,return_index=True)
   remap={'hand_'+tag:0}
   for d,digit in enumerate(DIGITS):
    for j in range(4):remap[f'{digit}_0{j+1}'+('_leaf' if j==3 else '')+f'_{tag}']=1+d*4+j
   mapped=np.array([[remap.get(names[k],0) for k in row] for row in ii])
   skin_data[side]=(local, mapped, ww,sample)
   print('SKIN',side,len(pp),'sample',len(sample),flush=True)
result={};reports={}
for name,weapon in source['weapons'].items():
 result[name]={};reports[name]={}
 model_b=mat(weapon['model']['basis']);model_p=np.array(weapon['model']['origin']);inv=np.linalg.inv(model_b);mb=model_b/np.linalg.norm(model_b[:,0]);verts=np.array(weapon['vertices'])
 for side in ['right','left']:
  data=weapon[side];rig=source['rig'][side];tag='r' if side=='right' else 'l'
  precision_grip=name in ['deagle','gpmg']
  centred_support=name=='gpmg' and side=='left'
  frame=mat(rig['frame']);offset=np.array(rig['offset']);scale=np.array(rig['scale']);basis=mat(data['basis'])
  surface=np.array(data['palm']);normal=np.array(data['normal'])
  if centred_support:
   shift_z=-.28-surface[2];surface=np.array([-.0285,.057,-.28]);normal=np.array([0.,-1.,0.])
   for target in data['targets']:target['point'][2]+=shift_z
  cup=side=='left' and name in ['deagle','m1911','tec9','mac10']
  if cup:
   grip=np.array(weapon['right']['palm'])
   patch=right_glove[(np.abs(right_glove[:,2]-grip[2])<.075)&(np.abs(right_glove[:,1]-grip[1])<.08)]
   surface=np.array([patch[:,0].min(),grip[1],grip[2]])
   normal=np.array([-1.,0.,0.])
   if name=='deagle':
    y=np.array([0.,0.,-1.]);z=np.array([1.,0.,0.]);basis=np.column_stack([np.cross(y,z),y,z])
  # Conservative authored grasp envelopes include the handguard/grip cross-section,
  # so a fingertip on the far side cannot pull its phalanges through the barrel.
  if side=='left' and not cup:
   select=(np.abs(verts[:,2]-surface[2])<.025)&(verts[:,1]>surface[1]-.03)&(verts[:,1]<surface[1]+.075)&(np.abs(verts[:,0]-surface[0])<.11)
  elif side=='right' and precision_grip:
   # Keep the large pistol's trigger-guard opening out of the solid grip hull.
   select=(np.abs(verts[:,2]-surface[2])<.035)&(verts[:,1]>surface[1]-.08)&(verts[:,1]<surface[1]+.025)&(np.abs(verts[:,0]-surface[0])<.08)
  else:
   select=(np.abs(verts[:,2]-surface[2])<.075)&(verts[:,1]>surface[1]-.10)&(verts[:,1]<surface[1]+.035)&(np.abs(verts[:,0])<.085)
  points=verts[select]
  if cup:
   if name=='deagle':points=verts[(np.abs(verts[:,2]-grip[2])<.035)&(verts[:,1]>grip[1]-.08)&(verts[:,1]<grip[1]+.025)&(np.abs(verts[:,0]-grip[0])<.08)]
   else:points=np.r_[points,patch]
  if len(points)<8:points=verts[np.linalg.norm(verts-surface,axis=1)<.15]
  if side=='left' and not cup:
   section=points.copy();front=section.copy();back=section.copy();front[:,2]=surface[2]-.12;back[:,2]=surface[2]+.12;volume_points=np.r_[front,back]
  else:volume_points=points
  planes=hull(volume_points)
  local,mapped,weights,sample=skin_data[side]
  # Full glove geometry: palm and intermediate finger tissue, not just bone tips.
  # This grip has opposing thumb/pinky contacts; resolve their full skin during
  # fitting instead of correcting a few missed vertices with a large hand shift.
  if precision_grip:sample=np.arange(len(local))
  L=local[sample];M=mapped[sample];W=weights[sample]
  chains=[[(np.array(j['origin']),mat(j['basis'])) for j in chain] for chain in rig['chains']]
  targets=np.array([np.array(t['point'])+np.array(t['normal'])*.008 for t in data['targets']])
  if cup:
   targets=np.array([np.array(t['point'])+np.array(t['normal'])*.008 for t in weapon['right']['targets']])
   if name=='deagle':targets=np.array([right_glove[np.argmin(np.linalg.norm(right_glove-target,axis=1))] for target in targets])
  initial=np.array([0.,0.,0.]+[v for d in [[.25,.6,.45],[.35,.55,.25],[.85,1.2,.9],[.9,1.25,.95],[.95,1.25,.95]] for v in d]+[0.]*5+[0.,0.,0.])
  if cup and name=='deagle':initial[3:18]=np.array([[.1,.15,.1],[.12,.15,.12],[.15,.2,.15],[.16,.2,.16],[.18,.22,.18]]).ravel()
  elif side=='left':
   initial[3:18]=np.array([[.14,.207,.162],[.52,.75,.585],[.56,.805,.63],[.584,.84,.657],[.60,.863,.675]]).ravel()
  # Translate the palm's skeletal centre outside the metal by glove thickness.
  anchor=surface+normal*.025
  if side=='left' and not cup:
   surface=np.array([(points[:,0].min()+points[:,0].max())*.5,points[:,1].min(),surface[2]])
   normal=np.array([0.,-1.,0.])
   anchor=surface+normal*.025
   y=np.array([1.,.1,-.25]) if centred_support else np.array([-1.,.1,-.25]);y/=np.linalg.norm(y);z=np.array([0.,1.,0.]);xaxis=np.cross(y,z);xaxis/=np.linalg.norm(xaxis);z=np.cross(xaxis,y);basis=np.column_stack([xaxis,y,z])
  limit=.3 if cup and name=="deagle" else 1.4 if side=="left" or name=="deagle" else .6
  if name=="gpmg" and side=="right":limit=.2
  if centred_support:limit=.45
  lo=np.array([-limit]*3+[-.25]*15+[-1.1,-.45,-.4,-.4,-.4]+[-.07,-.085,-.095]);hi=np.array([limit]*3+[1.7]*15+[1.1,.45,.4,.4,.4]+[.07,.085,.095])
  lo[3:18]=np.full(15,-.05) if side=="right" and precision_grip else np.maximum(initial[3:18]-(.45 if centred_support else .25),-.05)
  hi[3:18]=np.full(15,1.55) if side=="right" and precision_grip else np.minimum(initial[3:18]+(.45 if centred_support else .25),1.55)
  lo[18:23]=[-.35,-.15,-.15,-.15,-.15]
  hi[18:23]=[.35,.15,.15,.15,.15]
  forearm=np.array([0.,0.,-1.])
  contact_indices=[]
  for digit in range(5):
   selected=((M==3+digit*4)|(M==4+digit*4))&(W>.35)
   ids=np.where(selected.any(1))[0]
   contact_indices.append(ids)
  # Cache the anatomical inner-palm patch in bind space, rather than
  # letting a nearest-point objective touch with the back of the hand or cuff.
  hand_slots=np.argmax(W*(M==0),axis=1)
  hand_points=L[np.arange(len(L)),hand_slots,:3]
  palm_rest=offset+frame[:,2]*.015
  hand_candidates=np.where(((M==0)&(W>.8)).any(1))[0]
  palm_patch=hand_candidates[np.argsort(np.linalg.norm(hand_points[hand_candidates]-palm_rest,axis=1))[:24]]
  def fk(x,full=False):
   socket=basis@rx(x[0])@ry(x[1])@rz(x[2]);H=socket@np.linalg.inv(frame);pos=anchor+x[23:]-H@(offset*scale)
   T=np.eye(4);T[:3,:3]=H;T[:3,3]=pos;matrices=[T];tips=[]
   for digit,chain in enumerate(chains):
    P=pos.copy();B=H.copy()
    for joint,(o,b) in enumerate(chain):
     P=P+B@(o*scale);B=B@b
     if joint<3:
      B=B@rx(x[3+digit*3+joint])
      if joint==0:B=B@rz(x[18+digit])
     T=np.eye(4);T[:3,:3]=B;T[:3,3]=P
     matrices.append(T)
    tips.append(P)
   matrices=np.array(matrices)
   l,m,w=(local,mapped,weights) if full else (L,M,W)
   deformed=(np.einsum('nvij,nvj->nvi',matrices[m],l)*w[:,:,None]).sum(axis=1)[:,:3]
   return np.array(tips),deformed,socket
  def residual(x):
   tips,v,socket=fk(x)
   sdf=(v@planes[:,:3].T+planes[:,3]).max(axis=1)
   collision=np.sort(np.maximum(.003-sdf,0))[-80:]*40.0 if precision_grip else np.sort(np.maximum(.003-sdf,0))[-40:]*4.0
   # Palm longitudinal axis stays within 30 degrees of the forearm.
   contacts=[]
   for digit,ids in enumerate(contact_indices):
    patch=v[ids]
    distances=(patch@planes[:,:3].T+planes[:,3]).max(axis=1)
    closest=int(np.argmin(np.abs(distances-.002)))
    if precision_grip and not centred_support:
     closest=int(np.argmin(np.linalg.norm(patch-targets[digit],axis=1)));contacts.extend((patch[closest]-targets[digit])*3.)
    else:contacts.extend([(distances[closest]-.002)*3.0,(patch[closest,2]-targets[digit,2])*.5])
   patch=v[palm_patch]
   palm_distances=(patch@planes[:,:3].T+planes[:,3]).max(axis=1)
   nearest=int(np.argmin(np.abs(palm_distances-.002)))
   palm_contact=np.array([(palm_distances[nearest]-.002)*3.,(patch[nearest,2]-surface[2])*.6])
   if centred_support or (cup and name=='deagle'):
    palm_goal=surface+normal*.002;nearest=int(np.argmin(np.linalg.norm(patch-palm_goal,axis=1)));palm_contact=(patch[nearest]-palm_goal)*3.
   palm_orientation=max(0.,math.cos(math.radians(35))-socket[:,2]@(-normal))*.1
   geometry=arm_geometry[name][side]
   shoulder=np.array(geometry['shoulder']);palm_position=anchor+x[23:];hand_position=palm_position-socket@np.linalg.inv(frame)@(offset*scale)
   reach=hand_position-shoulder;distance=np.linalg.norm(reach);upper=geometry['upper'];lower=geometry['lower']
   cone=math.acos(np.clip((distance*distance+lower*lower-upper*upper)/(2*max(distance,.001)*lower),-1,1))
   axis_angle=math.acos(np.clip(socket[:,1]@(reach/max(distance,.001)),-1,1))
   wrist_penalty=max(0.,abs(axis_angle-cone)-math.radians(15))*5.0
   orientation=np.maximum(.8-np.array([socket[1,0],-socket[2,1],-socket[0,2]]),0)*.5 if side=='right' else np.zeros(3)
   return np.r_[orientation,np.array(contacts)*2.0,palm_contact*4.0,palm_orientation,collision,wrist_penalty,(x[3:18]-initial[3:18])*.020,x[:3]*.0005,x[18:23]*.020,x[23:]*.018]

  # Stable damped least squares, with bounded line-search steps.
  x=initial.copy();lam=.0001
  for iteration in range(260 if name=="gpmg" else 180):
   r=residual(x);J=np.empty((len(r),len(x)));eps=.00015
   for i in range(len(x)):
    xp=x.copy();xp[i]+=eps;J[:,i]=(residual(xp)-r)/eps
   dx=np.linalg.solve(J.T@J+np.eye(len(x))*lam,-J.T@r)
   if not np.all(np.isfinite(dx)):lam*=10;continue
   trial=np.clip(x+np.clip(dx,-.18,.18),lo,hi)
   if np.linalg.norm(residual(trial))<np.linalg.norm(r):x=trial;lam=max(1e-8,lam*.72)
   else:lam=min(.1,lam*3)
   if np.linalg.norm(dx)<1e-5:break
  tips,v,socket=fk(x,True)
  dist=v@planes[:,:3].T+planes[:,3]
  patch_ids=[np.where((((mapped==3+digit*4)|(mapped==4+digit*4))&(weights>.35)).any(1))[0] for digit in range(5)]
  geometry=arm_geometry[name][side]
  def wrist_angle(shift):
   H=socket@np.linalg.inv(frame);hand_position=anchor+x[23:]+shift-H@(offset*scale)
   reach=hand_position-np.array(geometry['shoulder']);length=np.linalg.norm(reach);u,l=geometry['upper'],geometry['lower']
   cone=math.acos(np.clip((length*length+l*l-u*u)/(2*max(length,.001)*l),-1,1));axis=math.acos(np.clip(socket[:,1]@(reach/max(length,.001)),-1,1))
   return math.degrees(abs(axis-cone))
  directions=[np.zeros(3),normal]
  for dx in [-1,0,1]:
   for dy in [-1,0,1]:
    for dz in [-1,0,1]:
     direction=np.array([dx,dy,dz],float)
     if np.linalg.norm(direction):directions.append(direction/np.linalg.norm(direction))
  best=None
  for direction in directions:
   distance=0.
   if dist.max(1).min()<.002:
    if not np.linalg.norm(direction):continue
    slope=planes[:,:3]@direction;positive=slope>1e-8;negative=slope< -1e-8;stationary=~(positive|negative)
    low=((.002-dist[:,negative])/slope[negative]).max(1) if negative.any() else np.full(len(v),-np.inf)
    high=((.002-dist[:,positive])/slope[positive]).min(1) if positive.any() else np.full(len(v),np.inf);valid=low<high
    if stationary.any():valid&=(dist[:,stationary]<.002).all(1)
    for lo,hi in sorted(zip(low[valid],high[valid])):
     if lo<=distance<=hi:distance=hi+.0001
   shift=direction*distance
   gaps=[np.linalg.norm(v[ids]+shift-targets[digit],axis=1).min() for digit,ids in enumerate(patch_ids)]
   angle=wrist_angle(shift);score=np.mean(gaps)+max(0,angle-30)*.0015+np.linalg.norm(shift)*.08
   if best is None or score<best[0]:best=(score,shift,gaps,angle)
  _,shift,gaps,angle=best
  if side=='right':right_glove=v+shift
  x[23:]+=shift
  sdf=(dist+planes[:,:3]@shift).max(1)
  # Keep actual model surface keypoints and record the separate skeletal offset.
  palm=anchor+x[23:]
  out={'model_frame':weapon['model'],'palm':list(inv@(surface-model_p)),'palm_offset':list(np.linalg.inv(mb)@(palm-surface)),'basis':(np.linalg.inv(mb)@socket).T.tolist(),'curl':x[3:18].reshape(5,3).tolist(),'splay':x[18:23].tolist(),'volume_planes':planes.tolist(),'fit_wrist_degrees':angle,'fit_min_clearance_m':float(sdf.min()),'skin_contact_error_m':gaps,'clearance_correction_m':shift.tolist()}
  for i,digit in enumerate(DIGITS):
   out[digit]=list(inv@(targets[i]-model_p));contact_source=weapon['right'] if cup else data;out[digit+'_normal']=list(np.linalg.inv(mb)@np.array(contact_source['targets'][i]['normal']))
  result[name][side]=out
  reports[name][side]={'wrist_degrees':angle,'min_glove_clearance_mm':float(sdf.min()*1000),'penetrating_vertices':int((sdf<0).sum()),'tip_error_mm':(np.linalg.norm(tips-targets,axis=1)*1000).tolist()}
  print(name,side,'wrist',round(angle,1),'clearance mm',round(sdf.min()*1000,2),'inside',int((sdf<0).sum()),flush=True)
(ROOT/'assets/weapon_contacts.json').write_text(json.dumps(result,indent=2)+'\n');Path('/tmp/weapon-volume-report.json').write_text(json.dumps(reports,indent=2))
