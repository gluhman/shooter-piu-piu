// Run from the pinned Mesh2Motion checkout, with mesh2motion_ts_loader.mjs.
// Legacy bones only unpose the input geometry; their hierarchy is not exported.
// Anatomical weights are transferred to the new native joints.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {Vector3, Quaternion, Matrix4, Matrix3} from 'three';
import {MeshoptDecoder} from 'three/examples/jsm/libs/meshopt_decoder.module.js';
import {GLTFLoader} from 'three/examples/jsm/loaders/GLTFLoader.js';
import {Utility} from './src/lib/Utilities.ts';
import {AnimationUtility} from './src/lib/processes/animations-listing/AnimationUtility.ts';

globalThis.ProgressEvent=class {constructor(type,opts){Object.assign(this,opts);this.type=type}};
async function load(file) {
  const raw=fs.readFileSync(file), size=raw.readUInt32LE(12), g=JSON.parse(raw.toString('utf8',20,20+size));
  const offset=20+size, bin=raw.subarray(offset+8,offset+8+raw.readUInt32LE(offset));
  delete g.images; delete g.textures; delete g.samplers;
  g.materials=[{name:'preview'}];
  for(const mesh of g.meshes??[]) for(const p of mesh.primitives) p.material=0;
  for(const b of g.buffers) b.uri='data:application/octet-stream;base64,'+(b.uri?fs.readFileSync(new URL(b.uri,'file://'+file)):bin).toString('base64');
  return new GLTFLoader().setMeshoptDecoder(MeshoptDecoder).parseAsync(JSON.stringify(g),'');
}
const native=await load(path.resolve('static/assets/human/skeleton.glb'));
native.scene.updateMatrixWorld(true);
const bones=Utility.bone_list_from_hierarchy(native.scene), byName=new Map(bones.map(b=>[b.name,b]));
const pos=b=>b.getWorldPosition(new Vector3()), rot=b=>b.getWorldQuaternion(new Quaternion());
const mapping={Hips:'pelvis',Spine:'spine_01',Spine1:'spine_02',Spine2:'spine_03',Neck:'neck_01',Head:'head',HeadTop_End:'head_leaf',
  LeftShoulder:'clavicle_l',RightShoulder:'clavicle_r',LeftArm:'upperarm_l',LeftForeArm:'lowerarm_l',LeftHand:'hand_l',RightArm:'upperarm_r',RightForeArm:'lowerarm_r',RightHand:'hand_r',
  LeftUpLeg:'thigh_l',LeftLeg:'calf_l',LeftFoot:'foot_l',LeftToeBase:'ball_l',LeftToe_End:'ball_leaf_l',RightUpLeg:'thigh_r',RightLeg:'calf_r',RightFoot:'foot_r',RightToeBase:'ball_r',RightToe_End:'ball_leaf_r'};
function mapped(b) {
  const short=b.name.replace(/^mixamorig_/, '').replace(/_0\d+$/,'');
  if(mapping[short]) return byName.get(mapping[short]);
  const finger=short.match(/^(Left|Right)Hand(Thumb|Index|Middle|Ring|Pinky)([1-4])$/);
  if(finger) return byName.get(`${finger[2].toLowerCase()}_0${finger[3]}${finger[3]==='4'?'_leaf':''}_${finger[1]==='Left'?'l':'r'}`);
  if(b.parent?.isBone) return mapped(b.parent);
  return byName.get('root');
}
function handFrame(b, list, nativeHand) {
  const side=nativeHand?b.name.slice(-1):b.name.includes('Right')?'Right':'Left';
  const find=d=>list.find(x=>nativeHand?x.name===`${d}_01_${side}`:x.name.startsWith(`mixamorig_${side}Hand${d[0].toUpperCase()+d.slice(1)}1_`));
  const y=pos(find('middle')).sub(pos(b)).normalize();
  const x=pos(find('index')).sub(pos(find('pinky'))).normalize();
  const z=x.clone().cross(y).normalize(); x.copy(y).cross(z).normalize();
  return new Quaternion().setFromRotationMatrix(new Matrix4().makeBasis(x,y,z));
}
const output={source:'Mesh2Motion native human / all-fingers',commit:execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim(),
  bones:bones.map(b=>({name:b.name,parent:bones.indexOf(b.parent),position:b.position.toArray(),quaternion:b.quaternion.toArray(),scale:b.scale.toArray(),inverseBind:b.matrixWorld.clone().invert().toArray()})),variants:{},clips:[]};
for(const variant of ['blue','red']) {
  const src=await load(path.resolve(process.argv[2]??'/tmp/piupiu-operator-input',`operator_${variant}.glb`));
  src.scene.updateMatrixWorld(true);
  const meshes=[];src.scene.traverse(m=>{if(m.isSkinnedMesh) meshes.push(m)});
  const oldBones=meshes.reduce((a,m)=>m.skeleton.bones.length>a.length?m.skeleton.bones:a,[]);
  const warp=new Map();
  for(const b of oldBones) {
    const target=mapped(b);
    let reference=b;while(reference.parent?.isBone && mapped(reference.parent)===target) reference=reference.parent;
    let from=rot(reference), to=rot(target);
    if(/^(thigh|calf|foot)_/.test(target.name)) to.multiply(new Quaternion().setFromAxisAngle(new Vector3(0,1,0),Math.PI));
    if(/^hand_/.test(target.name)) {from=handFrame(reference,oldBones,false);to=handFrame(target,bones,true)}
    const turn=to.multiply(from.clone().invert());
    // Match segment lengths before unposing. In particular the native forearms
    // are longer; rotation-only transfer leaves a pinched gap at each wrist.
    const child=reference.children.find(c=>c.isBone && mapped(c)?.parent===target);
    let ratio=1;
    if(child && !/^(head|neck|clavicle|pelvis|root)/.test(target.name))
      ratio=Math.max(.65,Math.min(1.5,pos(mapped(child)).distanceTo(pos(target))/pos(child).distanceTo(pos(reference))));
    const axis=new Vector3(0,1,0).applyQuaternion(from);
    const targetPosition=pos(target);if(target.name==='head')targetPosition.y-=.025;
    const translation=targetPosition.sub(pos(reference).applyQuaternion(turn));
    const dual=new Quaternion(translation.x,translation.y,translation.z,0).multiply(turn);
    dual.set(dual.x*.5,dual.y*.5,dual.z*.5,dual.w*.5);
    warp.set(b,{turn,dual,axis,ratio,origin:pos(reference)});
  }
  const result=[];
  for(const mesh of meshes) {
    const geo=mesh.geometry.clone(), p=geo.attributes.position, n=geo.attributes.normal;
    const joints=geo.attributes.skinIndex, weights=geo.attributes.skinWeight;
    const rigidHead=['Object_97','Object_109','OperatorEyes'].includes(mesh.name);
    const positions=[],normals=[];
    for(let i=0;i<p.count;i++) {
      // Dual-quaternion unposing preserves sleeve/wrist volume through the
      // source's deeply bent elbows. This is a bind-mesh operation only.
      const qr=new Quaternion(0,0,0,0),qd=new Quaternion(0,0,0,0),stretch=new Vector3();
      let hemisphere=null;
      for(let j=0;j<(rigidHead?1:4);j++) {
        const weight=rigidHead?1:weights.getComponent(i,j);if(weight===0)continue;
        const b=rigidHead?oldBones.find(b=>/^mixamorig_Head_/.test(b.name)):mesh.skeleton.bones[joints.getComponent(i,j)];
        const w=warp.get(b), sign=hemisphere && hemisphere.dot(w.turn)<0?-1:1;hemisphere??=w.turn;
        for(const key of ['x','y','z','w']) {qr[key]+=w.turn[key]*weight*sign;qd[key]+=w.dual[key]*weight*sign}
        const delta=new Vector3().fromBufferAttribute(p,i).sub(w.origin);
        stretch.addScaledVector(w.axis.clone().multiplyScalar(delta.dot(w.axis)*(w.ratio-1)).applyQuaternion(w.turn),weight);
      }
      const length=qr.length();for(const key of ['x','y','z','w']) {qr[key]/=length;qd[key]/=length}
      const translation=qd.multiply(qr.clone().conjugate());
      const point=new Vector3().fromBufferAttribute(p,i).applyQuaternion(qr).add(new Vector3(translation.x,translation.y,translation.z).multiplyScalar(2)).add(stretch);
      const normal=new Vector3().fromBufferAttribute(n,i).applyQuaternion(qr);
      // Preserve a natural trouser taper around the native hip-knee-ankle line.
      // The source outfit was authored for wider-spaced legs; retaining that
      // radius on this rig creates overlapping thighs and bowed calf silhouettes.
      if(mesh.name==='Object_113') {
        const side=point.x<0?-1:1,y=point.y;
        const calf=.74+.26*Math.exp(-Math.pow((y-.53)/.09,2));
        const thigh=.72+.28*Math.min(1,Math.max(0,(y-.78)/.16));
        const taper=y<.55?calf:thigh;
        point.x=side*.089+(point.x-side*.089)*taper;
      }
      if(mesh.name==='Object_117') {
        const side=mesh.skeleton.bones[joints.getX(i)].name.startsWith('Right')?-1:1;
        point.x=side*.4702+(point.x-side*.4702)*.88;
        point.y=1.444+(point.y-1.444)*.76;
        point.z=-.073+(point.z+.073)*.76;
      }
      if(mesh.name==='Object_123') {const side=point.x<0?-1:1;point.x=side*.089+(point.x-side*.089)*.88;point.y+=.024}
      // Garment collar tips must sit below the neck, rather than following
      // the unusually forward native clavicle roots into tall shoulder spikes.
      if(mesh.name==='Object_105' && point.y>1.40) point.y=1.40+(point.y-1.40)*.45;
      if(mesh.name==='Object_107' && Math.abs(point.x)<.23 && point.y>1.445) point.y=1.445+(point.y-1.445)*.3;
      positions.push(...point.toArray());normals.push(...normal.normalize().toArray());
    }
    let indices=new Array(p.count*4).fill(0),skinWeights=new Array(p.count*4).fill(0);
    // Transfer the artist's anatomical vertex groups. Nearest-bone weighting
    // alone leaks sleeve vertices into the
    // clavicle and palm vertices into adjacent fingers on this layered outfit.
    // The destinations are the NEW 66 native joints, with new inverse binds.
    if(!/^(HeadKit|ChestKit|BodyKit)/.test(mesh.name)) {
      for(let i=0;i<p.count;i++) {
        const sums=new Map();
        for(let j=0;j<4;j++) {
          const w=weights.getComponent(i,j);if(w===0)continue;
          const id=bones.indexOf(mapped(mesh.skeleton.bones[joints.getComponent(i,j)]));
          sums.set(id,(sums.get(id)??0)+w);
        }
        const entries=[...sums.entries()].sort((a,b)=>b[1]-a[1]);
        for(let j=0;j<4;j++){indices[i*4+j]=entries[j]?.[0]??0;skinWeights[i*4+j]=entries[j]?.[1]??0}
      }
    }
    // Rigid equipment is explicitly bound to anatomical joints, never old helper bones.
    const rigid=/^(HeadKit|ChestKit|BodyKit)/.test(mesh.name)?mapped(mesh.skeleton.bones[joints.getX(0)]).name:
      ['Object_97','Object_109','OperatorEyes'].includes(mesh.name)?'head':null;
    if(rigid) {indices=Array.from({length:p.count},()=>[bones.indexOf(byName.get(rigid)),0,0,0]).flat();skinWeights=Array.from({length:p.count},()=>[1,0,0,0]).flat()}
    if(['Object_101','Object_117'].includes(mesh.name)) {
      for(let i=0;i<p.count;i++) {const side=mesh.skeleton.bones[joints.getX(i)].name.startsWith('Right')?'r':'l';const joint=bones.indexOf(byName.get((mesh.name==='Object_101'?'calf_':'lowerarm_')+side));indices.splice(i*4,4,joint,0,0,0);skinWeights.splice(i*4,4,1,0,0,0)}
    }
    const association=src.parser.associations.get(mesh);
    result.push({name:mesh.name,mesh:association.meshes,primitive:association.primitives??0,positions,normals,indices,weights:skinWeights});
    console.log(variant,mesh.name,p.count);
  }
  output.variants[variant]=result;
}
for(const name of ['rifle-idle','rifle-walk','rifle-run','sprint','crouch-idle','crouch-walk','jump-start','jump-air','jump-land','rifle-reload','rifle-fire','walk-backwards','strafe-left','strafe-right']) {
  const gl=await load(path.resolve('static/assets/human/animations',name+'.glb'));
  const clip=gl.animations[0];
  // Exactly the same track cleaning as Mesh2Motion's default animation browser.
  AnimationUtility.clean_track_data([clip],'pelvis');
  output.clips.push({name,duration:clip.duration,tracks:clip.tracks.map(t=>({name:t.name,type:t.ValueTypeName,times:Array.from(t.times),values:Array.from(t.values)}))});
}
fs.writeFileSync('/tmp/piupiu-m2m-native.json',JSON.stringify(output));
console.log('NATIVE RIG',bones.length,'bones;',output.clips.length,'unretargeted clips');
