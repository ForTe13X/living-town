"""Original reader/fitter for explicitly CC0 MakeHuman graphical system assets.

The .mhclo data expresses each garment vertex as a barycentric point on the
unposed base plus an anatomical-axis offset. Fit before relaxing the rest pose;
otherwise the sleeve offsets follow world axes rather than the wearer's arm.
No MakeHuman application code is imported or redistributed.
"""
from collections import deque
from functools import lru_cache
import hashlib
import json
from pathlib import Path
from .human import mapped_bone

VENDOR=Path(__file__).parent/'vendor/system_assets'


def _casual_face_roles(faces,uv):
    """Keep the verified outfit's complete authored UV islands together.

    The source atlas puts trousers in its middle column, the shirt body on
    the left and collar/sleeves on the right. Its connected 3D mesh includes
    the tailored waist join: a height cut instead crosses the shirt's hem
    differently on each adapted wearer. This lookup uses source UV topology
    only, before anatomical fitting; no fitted coordinate or skin weight is
    involved. The vendor checksum binds the layout these column gaps describe.
    """
    users={}
    for face_index,face in enumerate(faces):
        for _,index in face:users.setdefault(index,[]).append(face_index)
    roles=[None]*len(faces);pending=set(range(len(faces)))
    while pending:
        first=min(pending);pending.remove(first);queue=deque([first]);island=[]
        while queue:
            face_index=queue.popleft();island.append(face_index)
            for _,index in faces[face_index]:
                for neighbor in users[index]:
                    if neighbor in pending:pending.remove(neighbor);queue.append(neighbor)
        columns={('pants' if .35<u<.715 else 'shirt')
                 for face_index in island for _,index in faces[face_index]
                 for u,_ in (uv[index],)}
        if len(columns)!=1:raise ValueError('Verified casual outfit UV island crosses material columns')
        role=columns.pop()
        for face_index in island:roles[face_index]=role
    return tuple(roles)


@lru_cache(maxsize=1)
def verify_assets():
    provenance=json.loads((VENDOR/'provenance.json').read_text(encoding='utf-8'))
    for name,entry in provenance['files'].items():
        payload=(VENDOR/name).read_bytes()
        if len(payload)!=entry['bytes'] or hashlib.sha256(payload).hexdigest()!=entry['sha256']:
            raise ValueError('CC0 system asset checksum changed: '+name)
    return provenance


@lru_cache(maxsize=8)
def load_asset(category,name):
    verify_assets()
    stem=VENDOR/category/name/name
    vertices=[];uv=[];faces=[]
    for line in stem.with_suffix('.obj').read_text(encoding='utf-8').splitlines():
        if line.startswith('v '):vertices.append(tuple(map(float,line.split()[1:4])))
        elif line.startswith('vt '):uv.append(tuple(map(float,line.split()[1:3])))
        elif line.startswith('f '):
            faces.append(list(reversed([tuple(int(v)-1 for v in s.split('/')[:2]) for s in line.split()[1:]])))
    scales={};mapping=[];deleted=set();section=None
    for line in stem.with_suffix('.mhclo').read_text(encoding='utf-8').splitlines():
        items=line.split()
        if not items or items[0].startswith('#'):continue
        if items[0] in ('x_scale','y_scale','z_scale'):
            scales[items[0][0]]=(int(items[1]),int(items[2]),float(items[3]))
        elif items[0]=='verts':section='verts'
        elif items[0]=='delete_verts':section='delete'
        elif section=='verts' and len(items)==9:
            mapping.append((tuple(map(int,items[:3])),tuple(map(float,items[3:6])),tuple(map(float,items[6:]))))
        elif section=='verts' and len(items)==1 and items[0].isdigit():
            index=int(items[0]);mapping.append(((index,index,index),(1.,0.,0.),(0.,0.,0.)))
        elif section=='delete':
            n=0
            while n<len(items):
                first=int(items[n]);n+=1
                if n<len(items) and items[n]=='-':
                    last=int(items[n+1]);n+=2;deleted.update(range(first,last+1))
                else:deleted.add(first)
    if len(vertices)!=len(mapping):raise ValueError(f'{name}: incomplete vertex fit {len(vertices)} != {len(mapping)}')
    # Disconnected outfits use their authored surface components. The casual
    # outfit has a connected waist and instead uses its complete UV islands.
    graph={i:set() for i in range(len(vertices))}
    for face in faces:
        ids=[i for i,t in face]
        for a,b in zip(ids,ids[1:]+ids[:1]):graph[a].add(b);graph[b].add(a)
    components={};unused=set(graph);component=0
    while unused:
        queue=deque([unused.pop()]);current=[]
        while queue:
            i=queue.popleft();current.append(i)
            for j in graph[i]:
                if j in unused:unused.remove(j);queue.append(j)
        for i in current:components[i]=component
        component+=1
    own_weights=None
    if stem.with_suffix('.mhw').exists():
        weight_data=json.loads(stem.with_suffix('.mhw').read_text(encoding='utf-8'))
        if weight_data.get('license')!='CC0':raise ValueError('Asset weights do not explicitly declare CC0')
        own_weights=[{} for _ in vertices]
        for source_bone,rows in weight_data['weights'].items():
            bone=mapped_bone(source_bone)
            for index,value in rows:own_weights[index][bone]=own_weights[index].get(bone,0)+value
        own_weights=[{bone:value/sum(row.values()) for bone,value in row.items() if value>0} for row in own_weights]
    face_roles=_casual_face_roles(faces,uv) if name=='male_casualsuit01' else None
    return {'vertices':vertices,'uv':uv,'faces':faces,'mapping':mapping,'scales':scales,'deleted':deleted,'components':components,'stem':stem,'name':name,'authored_weights':own_weights,'face_roles':face_roles}


def fit_asset(data,category,name):
    asset=load_asset(category,name);source=data['source']
    # Axis permutation: MakeHuman uses X/Y-up/Z-front; Blender X/Y-front/Z-up.
    axis_map={'x':0,'y':2,'z':1};scale={}
    for axis,(a,b,length) in asset['scales'].items():
        k=axis_map[axis];scale[axis]=abs(source[a][k]-source[b][k])/(length*.1)
    unposed=[];positions=[];weights=[]
    for vertex_index,(ids,bary,offset) in enumerate(asset['mapping']):
        p=[sum(source[index][k]*factor for index,factor in zip(ids,bary)) for k in range(3)]
        p[0]+=offset[0]*.1*scale.get('x',1)
        p[1]+=offset[2]*.1*scale.get('z',1)
        p[2]+=offset[1]*.1*scale.get('y',1)
        row={}
        # Extrapolation is valid for geometry, but skin influences must remain
        # positive and normalized for portable glTF/Godot interpolation.
        for index,factor in zip(ids,bary):
            for bone,value in data['weights'][index].items():row[bone]=row.get(bone,0)+value*max(0,factor)
        row={bone:weight for bone,weight in row.items() if weight>.0001};total=sum(row.values())
        row={bone:weight/total for bone,weight in row.items()}
        if asset['authored_weights'] is not None:row=asset['authored_weights'][vertex_index]
        unposed.append(tuple(p));positions.append(data['pose_point'](p,row));weights.append(row)
    tags={}
    for component in set(asset['components'].values()):
        indices=[i for i,c in asset['components'].items() if c==component]
        heights=[unposed[i][2] for i in indices]
        # The main jeans component begins below the belt, whereas the shirt
        # includes collar and sleeves. Small details use their own mean height.
        tags[component]='shirt' if max(heights)>1.12 or sum(heights)/len(heights)>.97 else 'pants'
    if name=='male_worksuit01':tags={component:('shirt' if component in (0,1) else 'pants') for component in tags}
    ground_offset=0
    if name.startswith('shoes'):
        ground_offset=-min(p[2] for p in positions)
        positions=[(x,y,z+ground_offset) for x,y,z in positions]
    return {**asset,'positions':positions,'unposed':unposed,'weights':weights,'tags':tags,'axis_scale':scale,'ground_offset_m':ground_offset}


def geometry_for(asset,region=None):
    vertices=[];uv=[];weights=[];faces=[];cache={};source_ids=[]
    for face_index,face in enumerate(asset['faces']):
        tag=asset['face_roles'][face_index] if asset['face_roles'] is not None else asset['tags'][asset['components'][face[0][0]]]
        if region and tag!=region:continue
        polygon=[]
        for index,tindex in face:
            key=(index,tindex)
            if key not in cache:
                cache[key]=len(vertices);vertices.append(asset['positions'][index]);uv.append(asset['uv'][tindex]);weights.append(asset['weights'][index]);source_ids.append(index)
            polygon.append(cache[key])
        faces.append(tuple(polygon))
    return (vertices,faces,uv),weights,source_ids


def visible_skin(data,garment,occlusion_assets=()):
    """Use the asset author's precise under-clothing mask, retaining seams."""
    deleted=set(garment['deleted'])
    for asset in occlusion_assets:deleted.update(asset['deleted'])
    vertices=[];uv=[];weights=[];faces=[];cache={}
    for face in data['faces']:
        if all(index in deleted for index,t in face):continue
        # Shoe volume replaces the foot sole without exposing a naked ankle.
        if all(data['positions'][index][2]<.072 for index,t in face):continue
        polygon=[]
        for index,tindex in face:
            key=(index,tindex)
            if key not in cache:
                cache[key]=len(vertices);vertices.append(data['positions'][index]);uv.append(data['uv'][tindex]);weights.append(data['weights'][index])
            polygon.append(cache[key])
        faces.append(tuple(polygon))
    return (vertices,faces,uv),weights
