"""Build a closed wrist bridge with overlap inside both sleeve and glove.

A short, uncapped cuff leaves a hollow annulus around the glove's tapered wrist.
The closed bridge fills that join. Its skin transition stays under the sleeve
so the exposed wrist does not collapse when the support palm rolls upward.
"""
import math
from collections import Counter, defaultdict
from build_operator_variants import GLB, ROOT

REVISION = 3
SEGMENTS = 48
RINGS = 22


def smooth(value):
    t = max(0., min(1., value))
    return t*t*(3.-2.*t)


def close_glove_collar(glb, node, names, cap_material):
    """Trim the donor wrist recess and close its retained palm-back boundaries."""
    caps=[]
    for primitive in list(glb.g['meshes'][node['mesh']]['primitives']):
        attrs=primitive['attributes']
        values={key:[list(row) for row in glb.read_accessor(index)] for key,index in attrs.items()}
        source=[row[0] for row in glb.read_accessor(primitive['indices'])]
        points=values['POSITION'];faces=[]
        for i in range(0,len(source),3):
            triangle=source[i:i+3]
            cut = .755 if points[triangle[0]][0]>0 else .765
            if all(abs(points[j][0])>=cut for j in triangle):faces.extend(triangle)
        keys=[tuple(round(v,6) for v in point) for point in points]
        edges,oriented=Counter(),{}
        for i in range(0,len(faces),3):
            triangle=faces[i:i+3]
            for j in range(3):
                a,b=triangle[j],triangle[(j+1)%3]
                key=tuple(sorted([keys[a],keys[b]]))
                edges[key]+=1;oriented[key]=(a,b)
        adjacent=defaultdict(set)
        for (a,b),count in edges.items():
            if count==1:adjacent[a].add(b);adjacent[b].add(a)
        seen=set();components=[]
        for first in adjacent:
            if first in seen:continue
            todo=[first];component=set()
            while todo:
                point=todo.pop()
                if point in seen:continue
                seen.add(point);component.add(point);todo.extend(adjacent[point]-seen)
            components.append(component)
        assert len(components)==2, 'Expected one wrist closure per glove'
        cap_points=[];cap_normals=[];cap_uv=[];cap_joints=[];cap_weights=[];cap_faces=[]
        for component in components:
            center=[sum(p[k] for p in component)/len(component) for k in range(3)]
            side='l' if center[0]>0 else 'r';sign=1 if side=='l' else -1
            middle=len(cap_points)
            cap_points.append(center);cap_normals.append([-sign,0.,0.]);cap_uv.append([.5,.5])
            cap_joints.append([names.index('hand_'+side),0,0,0]);cap_weights.append([1.,0.,0.,0.])
            mapping={}
            for edge,count in edges.items():
                if count!=1 or edge[0] not in component:continue
                a,b=oriented[edge]
                for old in [a,b]:
                    if old in mapping:continue
                    mapping[old]=len(cap_points);point=points[old]
                    cap_points.append(point[:]);cap_normals.append([-sign,0.,0.])
                    cap_uv.append([point[1]*12.,point[2]*12.])
                    cap_joints.append(values['JOINTS_0'][old]);cap_weights.append(values['WEIGHTS_0'][old])
                cap_faces.extend([mapping[b],mapping[a],middle])
        used=sorted(set(faces));remap={old:new for new,old in enumerate(used)}
        for key,rows in values.items():
            old=glb.g['accessors'][attrs[key]]
            attrs[key]=glb.accessor([rows[i] for i in used],old['type'],old['componentType'],bounds=key=='POSITION')
        primitive['indices']=glb.accessor([remap[i] for i in faces],'SCALAR',5125)
        caps.append({'attributes':{
            'POSITION':glb.accessor(cap_points,'VEC3',bounds=True),
            'NORMAL':glb.accessor(cap_normals,'VEC3'),
            'TEXCOORD_0':glb.accessor(cap_uv,'VEC2'),
            'JOINTS_0':glb.accessor(cap_joints,'VEC4',5123),
            'WEIGHTS_0':glb.accessor(cap_weights,'VEC4')},
            'indices':glb.accessor(cap_faces,'SCALAR',5125),'material':cap_material})
    glb.g['meshes'][node['mesh']]['primitives'].extend(caps)


def correct_wrist(glb):
    g = glb.g
    if g['asset'].get('extras', {}).get('wrist_volume_revision') == REVISION:
        return
    node = next(n for n in g['nodes'] if n.get('name') == 'Soldier_WristCuffs')
    glove = next(n for n in g['nodes'] if n.get('name') == 'Soldier_ArticulatedGloves')
    names = [g['nodes'][i]['name'] for i in g['skins'][node['skin']]['joints']]
    cap_material = g['meshes'][node['mesh']]['primitives'][0]['material']
    close_glove_collar(glb,glove,names,cap_material)
    attrs = g['meshes'][glove['mesh']]['primitives'][0]['attributes']
    glove_points = glb.read_accessor(attrs['POSITION'])
    glove_joints = glb.read_accessor(attrs['JOINTS_0'])
    glove_weights = glb.read_accessor(attrs['WEIGHTS_0'])
    positions, normals, uvs, joints, weights, faces = [], [], [], [], [], []
    for side, sign in [('l',1),('r',-1)]:
        hand, forearm = names.index('hand_'+side), names.index('lowerarm_'+side)
        # Palm-only vertices exclude the folded-back glove rim and thumb.
        palm = [p for p,js,ws in zip(glove_points,glove_joints,glove_weights)
                if .780 < sign*p[0] < .805 and sum(w for j,w in zip(js,ws) if j==hand)>.8]
        center = [(min(p[a] for p in palm)+max(p[a] for p in palm))*.5 for a in [1,2]]
        palm_radius = [(max(p[a] for p in palm)-min(p[a] for p in palm))*.5 for a in [1,2]]
        start = len(positions)
        for ring in range(RINGS):
            t = ring/(RINGS-1)
            x = .700+.105*t
            # Broad sleeve-side overlap, a full wrist, then a smaller end buried
            # in the palm. Both end caps remain inside existing garment/glove.
            wrist = smooth((x-.714)/.044)
            buried = smooth((x-.750)/.035)
            wrist_radius = (.034,.035) if side=='l' else (.032,.041)
            radius = [(.041*(1-wrist)+wrist_radius[0]*wrist)*(1-buried)+palm_radius[0]*.72*buried,
                      (.038*(1-wrist)+wrist_radius[1]*wrist)*(1-buried)+palm_radius[1]*.72*buried]
            hand_weight = smooth((x-.700)/.032)
            for segment in range(SEGMENTS+1):
                angle = segment/SEGMENTS*math.tau
                co,si = math.cos(angle),math.sin(angle)
                # Keep the palm side clear of pistol grips; fill the dorsal cuff recess.
                dorsal_offset = .008*wrist*(1-buried) if side=='r' else 0.
                positions.append([sign*x,center[0]+dorsal_offset+radius[0]*co,center[1]+radius[1]*si])
                normal = [0.,co/radius[0],si/radius[1]]
                length = math.sqrt(sum(n*n for n in normal))
                normals.append([n/length for n in normal])
                uvs.append([segment/SEGMENTS,t])
                joints.append([forearm,hand,0,0])
                weights.append([1-hand_weight,hand_weight,0.,0.])
        stride = SEGMENTS+1
        for ring in range(RINGS-1):
            for segment in range(SEGMENTS):
                a = start+ring*stride+segment
                triangles = [(a,a+1,a+stride+1),(a,a+stride+1,a+stride)]
                for triangle in triangles:faces.extend(triangle if sign>0 else tuple(reversed(triangle)))
        # Real caps close the mesh rather than relying on a sleeve to mask a hole.
        for end in [0,RINGS-1]:
            base = start+end*stride
            cap = len(positions)
            positions.append([positions[base][0],*center])
            normals.append([sign*(-1 if end==0 else 1),0.,0.])
            uvs.append([.5,end/(RINGS-1)])
            joints.append(joints[base][:]);weights.append(weights[base][:])
            for segment in range(SEGMENTS):
                triangle = (cap,base+segment+1,base+segment)
                if end==RINGS-1:triangle=tuple(reversed(triangle))
                faces.extend(triangle if sign>0 else tuple(reversed(triangle)))
    keys=[tuple(round(v,6) for v in p) for p in positions]
    sums={key:[0.,0.,0.] for key in keys}
    for triangle in range(0,len(faces),3):
        ids=faces[triangle:triangle+3]
        a,b,c=[positions[i] for i in ids]
        u,v=[b[k]-a[k] for k in range(3)],[c[k]-a[k] for k in range(3)]
        normal=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
        for i in ids:
            for k in range(3):sums[keys[i]][k]+=normal[k]
    for i,key in enumerate(keys):
        normal=sums[key];length=math.sqrt(sum(n*n for n in normal))
        if length>1e-12:normals[i]=[n/length for n in normal]
    old = g['meshes'][node['mesh']]['primitives'][0]
    primitive = {'attributes':{
        'POSITION':glb.accessor(positions,'VEC3',bounds=True),
        'NORMAL':glb.accessor(normals,'VEC3'),
        'TEXCOORD_0':glb.accessor(uvs,'VEC2'),
        'JOINTS_0':glb.accessor(joints,'VEC4',5123),
        'WEIGHTS_0':glb.accessor(weights,'VEC4')},
        'indices':glb.accessor(faces,'SCALAR',5125),'material':old['material']}
    g['meshes'][node['mesh']]['primitives'] = [primitive]
    g['asset'].setdefault('extras',{})['wrist_volume_revision'] = REVISION


if __name__ == '__main__':
    for team in ['blue','red']:
        path = ROOT/f'assets/operator/variants/operator_{team}.glb'
        glb = GLB(path)
        correct_wrist(glb)
        glb.compact()
        glb.write(path)
        print('Updated closed wrist bridge:',team)
