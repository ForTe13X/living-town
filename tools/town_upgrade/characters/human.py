"""Checksum-verified CC0 MakeHuman topology and weights, with no upstream code.

The loader and rest-pose adaptation below are original implementation. Only
graphical data is vendored; the application's AGPL Python code is not imported.
"""
from functools import lru_cache
import hashlib
import json
import math
from pathlib import Path

VENDOR=Path(__file__).parent/'vendor/makehuman'


def mapped_bone(name):
    side='_L' if name.endswith('.L') else '_R'
    if name.startswith('upperarm'):return 'UpperArm'+side
    if name.startswith('lowerarm'):return 'Forearm'+side
    if name.startswith(('finger','metacarpal','wrist')):return 'Hand'+side
    if name.startswith('upperleg'):return 'Thigh'+side
    if name.startswith('lowerleg'):return 'Shin'+side
    if name.startswith(('foot','toe')):return 'Foot'+side
    if name.startswith(('pelvis','root')):return 'PelvisRoot'
    if name.startswith(('spine','breast','clavicle','shoulder','neck')):return 'BodyPivot'
    return 'HeadPivot'


def rotate_y(p,angle):
    x,y,z=p;c=math.cos(angle);s=math.sin(angle)
    return (x*c+z*s,y,-x*s+z*c)


def rotate_x(p,angle):
    x,y,z=p;c=math.cos(angle);s=math.sin(angle)
    return (x,y*c-z*s,y*s+z*c)


def minus(a,b):return tuple(a[i]-b[i] for i in range(3))
def plus(a,b):return tuple(a[i]+b[i] for i in range(3))


@lru_cache(maxsize=1)
def load_source():
    provenance=json.loads((VENDOR/'provenance.json').read_text(encoding='utf-8'))
    for name,entry in provenance['files'].items():
        if hashlib.sha256((VENDOR/name).read_bytes()).hexdigest()!=entry['sha256']:
            raise ValueError('Vendored CC0 source checksum changed: '+name)
    vertices=[];uv=[];groups={};group='body';faces=[]
    for line in (VENDOR/'base.obj').read_text(encoding='utf-8').splitlines():
        if line.startswith('v '):vertices.append(tuple(map(float,line.split()[1:4])))
        elif line.startswith('vt '):uv.append(tuple(map(float,line.split()[1:3])))
        elif line.startswith('g '):group=line[2:];groups.setdefault(group,[])
        elif line.startswith('f '):
            face=[tuple(int(v)-1 for v in token.split('/')[:2]) for token in line.split()[1:]]
            groups.setdefault(group,[]).append(face)
            # Swapping Y-up/Z-front to Blender Z-up/Y-front is a reflection;
            # reverse winding so anatomy normals still point out of the body.
            if group=='body':faces.append(list(reversed(face)))
    # Source uses decimeters, Y-up, with the ground at -8.168.
    def convert(v):return (v[0]*.1,v[2]*.1,(v[1]+8.168)*.1)
    vertices=[convert(v) for v in vertices]
    centers={}
    for name,fs in groups.items():
        ids={v[0] for face in fs for v in face}
        if ids:centers[name]=tuple(sum(vertices[i][j] for i in ids)/len(ids) for j in range(3))
    centers['_vertex_indices']={name:sorted({v[0] for face in fs for v in face}) for name,fs in groups.items() if name.startswith('joint-')}
    raw=json.loads((VENDOR/'default_weights.mhw').read_text(encoding='utf-8'))['weights']
    weights=[{} for _ in vertices]
    for source_bone,rows in raw.items():
        bone=mapped_bone(source_bone)
        for index,weight in rows:
            weights[index][bone]=weights[index].get(bone,0)+weight
    for index,row in enumerate(weights):
        total=sum(row.values())
        if total:weights[index]={key:value/total for key,value in row.items() if value>.00001}
    return vertices,uv,faces,weights,centers,provenance


@lru_cache(maxsize=8)
def load_target(name):
    rows=[]
    for line in (VENDOR/name).read_text(encoding='utf-8').splitlines():
        if not line.strip() or line.startswith('#'):continue
        index,x,y,z=line.split();rows.append((int(index),(float(x)*.1,float(z)*.1,float(y)*.1)))
    return rows


def adapted_body(look):
    source,uv,faces,weights,centers,provenance=load_source()
    source=[list(p) for p in source]
    female=look['id'] in {'aria','coco','evy','fei','mei','qin','hua','mian','gui','liu'}
    sex='female' if female else 'male'
    old=max(0,min(1,(look['age']-42)/35));child=max(0,min(1,(18-look['age'])/10))
    applied_targets={}
    for age,blend in [('young',(1-old)*(1-child)),('old',old),('child',child)]:
        if blend<=0:continue
        applied_targets[f'asian-{sex}-{age}.target']=blend
        for index,delta in load_target(f'asian-{sex}-{age}.target'):
            for axis in range(3):source[index][axis]+=delta[axis]*blend
    body_ids={i for face in faces for i,t in face}
    bottom=min(source[i][2] for i in body_ids);top=max(source[i][2] for i in body_ids)
    normalize=1.665/(top-bottom)
    source=[(p[0]*normalize,p[1]*normalize,(p[2]-bottom)*normalize) for p in source]
    centers={name:tuple(sum(source[i][j] for i in ids)/len(ids) for j in range(3)) for name,ids in centers['_vertex_indices'].items()}
    transforms={}
    for side,sign in [('L',1),('R',-1)]:
        letter=side.lower()
        shoulder=centers[f'joint-{letter}-shoulder'];elbow=centers[f'joint-{letter}-elbow']
        angle=sign*.61
        def upper(p,origin=shoulder,a=angle):return plus(origin,rotate_y(minus(p,origin),a))
        elbow_new=upper(elbow)
        def fore(p,origin=elbow,target=elbow_new,a=angle):
            return plus(target,rotate_x(rotate_y(minus(p,origin),a),-.76))
        transforms['UpperArm_'+side]=upper;transforms['Forearm_'+side]=fore;transforms['Hand_'+side]=fore
        hip=centers[f'joint-{letter}-upper-leg']
        def leg(p,origin=hip,a=sign*.12):return plus(origin,rotate_y(minus(p,origin),a))
        for part in ('Thigh','Shin'):transforms[part+'_'+side]=leg
        ankle=centers[f'joint-{letter}-ankle'];ankle_new=leg(ankle)
        # Open the stance at the hips while keeping the shoe soles horizontal;
        # the ankle compensates the small leg splay as a real standing foot does.
        def foot(p,origin=ankle,target=ankle_new):return plus(target,minus(p,origin))
        transforms['Foot_'+side]=foot
    breadth={'slim':.99,'broad':1.11,'stocky':1.08,'child':.92}[look['build']]
    def body_scale(p):
        x,y,z=p
        # Proportions vary while the detailed face, fingers and joints survive.
        width=1+(breadth-1)*max(0,1-abs(z-1.0)/.65)
        x*=width
        return (x,y*(1.03 if look['build']=='stocky' else 1),z)
    def pose_point(p,row):
        if row:
            q=[0.,0.,0.]
            for bone,weight in row.items():
                target=transforms.get(bone,lambda point:point)(p)
                for j in range(3):q[j]+=target[j]*weight
            return body_scale(q)
        return body_scale(p)
    positions=[pose_point(p,weights[index]) for index,p in enumerate(source)]
    head_origin=centers['joint-neck'];head_origin=(head_origin[0],head_origin[1],head_origin[2]+.015)
    joints={'PelvisRoot':centers['joint-pelvis'],'BodyPivot':centers['joint-pelvis'],'HeadPivot':head_origin}
    for side in ('L','R'):
        letter=side.lower()
        for part,marker in [('UpperArm','shoulder'),('Forearm','elbow'),('Hand','hand'),('Thigh','upper-leg'),('Shin','knee'),('Foot','ankle')]:
            original=centers[f'joint-{letter}-{marker}'];bone=part+'_'+side
            transform=transforms.get(bone,lambda p:p)
            joints[bone]=body_scale(transform(original))
    return {'positions':positions,'source':source,'uv':uv,'faces':faces,'weights':weights,'joints':joints,'markers':centers,'body_ids':body_ids,'provenance':provenance,'look':look,'morph_targets':applied_targets,'pose_point':pose_point}


def vertex_normals(positions,faces):
    normals=[[0.,0.,0.] for _ in positions]
    for face in faces:
        ids=[v[0] if isinstance(v,tuple) else v for v in face]
        a,b,c=[positions[i] for i in ids[:3]];u=minus(b,a);v=minus(c,a)
        n=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
        for index in ids:
            for j in range(3):normals[index][j]+=n[j]
    return [tuple(c/(math.sqrt(sum(v*v for v in row)) or 1) for c in row) for row in normals]


def boundary_loops(faces):
    edges={}
    for face in faces:
        ids=[v[0] if isinstance(v,tuple) else v for v in face]
        for a,b in zip(ids,ids[1:]+ids[:1]):
            key=tuple(sorted((a,b)));edges[key]=edges.get(key,0)+1
    graph={}
    for (a,b),count in edges.items():
        if count==1:graph.setdefault(a,[]).append(b);graph.setdefault(b,[]).append(a)
    loops=[];unused={tuple(sorted(edge)) for edge,count in edges.items() if count==1}
    while unused:
        edge=next(iter(unused));loop=[edge[0]];previous=-1;current=edge[0]
        while True:
            choices=[n for n in graph[current] if tuple(sorted((current,n))) in unused]
            if not choices:break
            nxt=choices[0];unused.remove(tuple(sorted((current,nxt))))
            previous,current=current,nxt
            if current==loop[0]:break
            loop.append(current)
        if len(loop)>2:loops.append(loop)
    return loops
