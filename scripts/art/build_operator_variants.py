"""Assemble intermediate outfit geometry for the native Mesh2Motion rigging step.
These temporary GLBs retain source weights only to unpose the input geometry.
"""
import copy, json, math, struct, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def indexed_surface(obj):
 """Share identical corners without changing UV seams, normals or skin weights."""
 fields=[k for k in ['positions','normals','uv','joints','weights','colors'] if k in obj]
 result={**obj,**{k:[] for k in fields},'indices':[]};seen={}
 for i in obj['indices']:
  key=tuple(v for k in fields for v in obj[k][i])
  if key not in seen:
   seen[key]=len(result['positions'])
   for k in fields:result[k].append(obj[k][i])
  result['indices'].append(seen[key])
 return result

class GLB:
 def __init__(self,path):
  raw=Path(path).read_bytes();size=struct.unpack_from('<I',raw,12)[0]
  self.g=json.loads(raw[20:20+size]);offset=20+size
  self.data=bytearray(raw[offset+8:offset+8+struct.unpack_from('<I',raw,offset)[0]])
 def accessor(self,values,kind,component=5126,bounds=False):
  width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[kind]
  flat=[x for v in values for x in v] if width>1 else values
  while len(self.data)%4:self.data.append(0)
  offset=len(self.data);fmt={5126:'f',5123:'H',5125:'I'}[component]
  self.data.extend(struct.pack('<'+fmt*len(flat),*flat))
  vi=len(self.g.setdefault('bufferViews',[]));self.g['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(self.data)-offset})
  a={'bufferView':vi,'componentType':component,'count':len(values),'type':kind}
  if bounds:
   a['min']=[min(v[i] for v in values) for i in range(width)] if width>1 else [min(values)]
   a['max']=[max(v[i] for v in values) for i in range(width)] if width>1 else [max(values)]
  ai=len(self.g['accessors']);self.g['accessors'].append(a);return ai
 def write(self,path):
  while len(self.data)%4:self.data.append(0)
  self.g['buffers']=[{'byteLength':len(self.data)}]
  raw=json.dumps(self.g,separators=(',',':')).encode();raw+=b' '*((-len(raw))%4)
  Path(path).write_bytes(struct.pack('<III',0x46546c67,2,28+len(raw)+len(self.data))+struct.pack('<II',len(raw),0x4e4f534a)+raw+struct.pack('<II',len(self.data),0x004e4942)+self.data)
 def compact(self):
  # Drop superseded bind geometry, not resolution. Asset rebuilding appends
  # new accessors; only data referenced by live meshes/skins/clips is retained.
  g=self.g;used_meshes=sorted({n['mesh'] for n in g['nodes'] if 'mesh' in n});mesh_map={old:i for i,old in enumerate(used_meshes)}
  g['meshes']=[g['meshes'][i] for i in used_meshes]
  for n in g['nodes']:
   if 'mesh' in n:n['mesh']=mesh_map[n['mesh']]
  refs=[]
  for m in g['meshes']:
   for p in m['primitives']:
    refs.extend((p['attributes'],k) for k in p['attributes'])
    if 'indices' in p:refs.append((p,'indices'))
    for target in p.get('targets',[]):refs.extend((target,k) for k in target)
  for skin in g.get('skins',[]):
   if 'inverseBindMatrices' in skin:refs.append((skin,'inverseBindMatrices'))
  for clip in g.get('animations',[]):
   for sampler in clip['samplers']:refs.extend([(sampler,'input'),(sampler,'output')])
  used=sorted({o[k] for o,k in refs});mapping={old:i for i,old in enumerate(used)}
  g['accessors']=[g['accessors'][i] for i in used]
  for o,k in refs:o[k]=mapping[o[k]]
  views=[]
  for a in g['accessors']:
   if 'bufferView' in a:views.append((a,'bufferView'))
   for part in a.get('sparse',{}).values():
    if isinstance(part,dict) and 'bufferView' in part:views.append((part,'bufferView'))
  for im in g.get('images',[]):
   if 'bufferView' in im:views.append((im,'bufferView'))
  used=sorted({o[k] for o,k in views});mapping={old:i for i,old in enumerate(used)};packed=bytearray();new_views=[]
  for i in used:
   v=copy.deepcopy(g['bufferViews'][i]);start=v.get('byteOffset',0)
   while len(packed)%4:packed.append(0)
   v['byteOffset']=len(packed);packed.extend(self.data[start:start+v['byteLength']]);new_views.append(v)
  for o,k in views:o[k]=mapping[o[k]]
  g['bufferViews']=new_views;self.data=packed
 def read_accessor(self,index):
  a=self.g['accessors'][index];v=self.g['bufferViews'][a['bufferView']]
  width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
  fmt={5126:'f',5123:'H',5125:'I',5121:'B'}[a['componentType']]
  stride=v.get('byteStride',struct.calcsize(fmt)*width)
  start=v.get('byteOffset',0)+a.get('byteOffset',0)
  return [struct.unpack_from('<'+fmt*width,self.data,start+i*stride) for i in range(a['count'])]
 def rigid_pads(self):
  # A hard shell must follow its dedicated helper bone, not stretch across a hinge.
  for node in self.g['nodes']:
   kind={'Object_101':'Knee','Object_117':'Elbow'}.get(node.get('name'))
   if not kind:continue
   joints=self.g['skins'][node['skin']]['joints']
   names={self.g['nodes'][j]['name']:i for i,j in enumerate(joints)}
   sides={side:next(i for name,i in names.items() if name.startswith(side+'_'+kind+'_Pads')) for side in ['Left','Right']}
   for primitive in self.g['meshes'][node['mesh']]['primitives']:
    attrs=primitive['attributes'];positions=self.read_accessor(attrs['POSITION'])
    attrs['JOINTS_0']=self.accessor([[sides['Right' if p[0]<.176 else 'Left'],0,0,0] for p in positions],'VEC4',5123)
    attrs['WEIGHTS_0']=self.accessor([[1,0,0,0]]*len(positions),'VEC4')
 def animations(self,clips):
  nodes={n['name']:i for i,n in enumerate(self.g['nodes'])}
  for clip in clips:
   a={'name':clip['name'],'samplers':[],'channels':[]}
   for track in clip['tracks']:
    bone,prop=track['name'].rsplit('.',1)
    if bone not in nodes:continue
    width=4 if prop=='quaternion' else 3
    values=[track['values'][i:i+width] for i in range(0,len(track['values']),width)]
    si=len(a['samplers']);a['samplers'].append({'input':self.accessor(track['times'],'SCALAR',bounds=True),'output':self.accessor(values,'VEC'+str(width)),'interpolation':'LINEAR'})
    a['channels'].append({'sampler':si,'target':{'node':nodes[bone],'path':{'quaternion':'rotation','position':'translation','scale':'scale'}[prop]}})
   self.g.setdefault('animations',[]).append(a)
 def kit(self,kit,variant):
  g=self.g;skin_index=max(range(len(g['skins'])),key=lambda i:len(g['skins'][i]['joints']))
  joints=g['skins'][skin_index]['joints'];bone_indices={g['nodes'][node]['name']:i for i,node in enumerate(joints)}
  mats={}
  hd={}
  for file in ['fabric_pattern_05_col_01_4k.jpg','fabric_pattern_05_nor_gl_4k.jpg','fabric_pattern_05_arm_4k.jpg','fabric_leather_02_nor_gl_4k.jpg','fabric_leather_02_arm_4k.jpg']:
   ii=len(g.setdefault('images',[]));g['images'].append({'uri':'../textures/hd/'+file})
   hd[file]=len(g.setdefault('textures',[]));g['textures'].append({'source':ii})
  for name,m in kit['materials'].items():
   m=copy.deepcopy(m)
   cloth=any(t in name for t in ['nylon','sand','scarf','stitch','id_'])
   if cloth or name in ['Kit_shell','Kit_rubber']:
    prefix='fabric_pattern_05' if cloth else 'fabric_leather_02'
    m['normalTexture']={'index':hd[prefix+'_nor_gl_4k.jpg'],'scale':.6 if cloth else .16}
    if cloth:m['pbrMetallicRoughness']['metallicRoughnessTexture']={'index':hd[prefix+'_arm_4k.jpg']}
    # Painted helmet/rubber need uniform matte roughness, not polished leather.
    m['occlusionTexture']={'index':hd[prefix+'_arm_4k.jpg'],'strength':.6}
   # Game shader remaps the original pink fabric albedo to neutral scarf yarn.
   # Standalone GLBs retain the modeled check pattern and 4K weave normals.

   if name.endswith('_red') or name.endswith('_blue'):
    if not name.endswith('_'+variant):continue
   mats[name]=len(g['materials']);g['materials'].append(m)
  for obj in kit['objects']:
   if obj['variant'] not in ['both',variant]:continue
   obj=indexed_surface(obj)
   bi=bone_indices[obj['bone']];count=len(obj['positions'])
   # Kit was authored against Blender's unscaled rest display. Restore the source root scale.
   obj=copy.deepcopy(obj)
   obj['positions']=[[axis*(1.0 if kit.get('native') else .914404273) for axis in point] for point in obj['positions']]
   attrs={k:self.accessor(obj[v],kind,bounds=k=='POSITION') for k,v,kind in [('POSITION','positions','VEC3'),('NORMAL','normals','VEC3'),('TEXCOORD_0','uv','VEC2')]}
   if 'colors' in obj:attrs['COLOR_0']=self.accessor(obj['colors'],'VEC4')
   attrs['JOINTS_0']=self.accessor(obj.get('joints',[[bi,0,0,0]]*count),'VEC4',5123)
   attrs['WEIGHTS_0']=self.accessor(obj.get('weights',[[1,0,0,0]]*count),'VEC4')
   mi=len(g['meshes']);g['meshes'].append({'name':obj['name'],'primitives':[{'attributes':attrs,'indices':self.accessor(obj['indices'],'SCALAR',5125),'material':mats[obj['material']]}]})
   ni=len(g['nodes']);g['nodes'].append({'name':obj['name'],'mesh':mi,'skin':skin_index})
   g['nodes'][0]['children'].append(ni)

def main():
 source=Path(sys.argv[1] if len(sys.argv)>1 else '/tmp/piupiu-operator-clean.glb')
 # Native fitted kit is added after the body is adapted to Mesh2Motion.
 output=Path('/tmp/piupiu-operator-input');output.mkdir(exist_ok=True)
 for variant in ['blue','red']:
  glb=GLB(source);g=glb.g
  for node in g['nodes']:
   if node.get('name')=='0':node['name']='OperatorEyes'
  # Omit the source's displaced headset. The blue helmet replaces the cap.
  omit={'Object_111','Object_109'}
  for node in g['nodes']:
   if 'children' in node:node['children']=[i for i in node['children'] if g['nodes'][i].get('name') not in omit]
  colors=({'Mil_Suit_R5':(.055,.085,.13),'Mil_Suit_R5__Plate':(.065,.082,.10),'Mil_Suit_R5_Puches':(.075,.095,.115),'Mil_Suit_Pads__R5':(.09,.11,.13),'Mil_Suit_R5_Head':(.07,.09,.11)} if variant=='blue' else {'Mil_Suit_R5':(.68,.62,.49),'Mil_Suit_R5__Plate':(.86,.73,.54),'Mil_Suit_R5_Puches':(.77,.64,.45),'Mil_Suit_Pads__R5':(.63,.55,.43),'Mil_Suit_R5_Head':(.62,.57,.44),'GreenCap':(.73,.61,.42)})
  for m in g['materials']:
   p=m.setdefault('pbrMetallicRoughness',{})
   if m['name'] in colors:p['baseColorFactor']=[*colors[m['name']],1]
   p['roughnessFactor']=.9
   p['metallicFactor']=0.0
  glb.rigid_pads()
  # Split clothing materials so gloves/boots and trousers have their own finish.
  for node in g['nodes']:
   suffix={'Object_113':'Trousers','Object_115':'Gloves','Object_123':'Boots'}.get(node.get('name'))
   if not suffix:continue
   for primitive in g['meshes'][node['mesh']]['primitives']:
    mat=copy.deepcopy(g['materials'][primitive['material']]);mat['name']='Mil_Suit_R5_'+suffix
    tint=({'Trousers':(.095,.12,.14),'Gloves':(.09,.10,.11),'Boots':(.065,.075,.085)} if variant=='blue' else {'Trousers':(.36,.39,.28),'Gloves':(.38,.33,.23),'Boots':(.30,.26,.18)})[suffix]
    mat['pbrMetallicRoughness']['baseColorFactor']=[*tint,1]
    primitive['material']=len(g['materials']);g['materials'].append(mat)
  g['animations']=[]
  glb.write(output/f'operator_{variant}.glb')
 print('Assembled intermediate outfit geometry in',output)
if __name__=='__main__':main()
