"""Native glTF mesh-joint animation and export checks, without engine imports."""
from __future__ import annotations

import json
import math
from pathlib import Path
import struct

from .animation import pelvis_height,pose_values
from .manifest import ANIMATED_JOINTS, BASE_HEIGHT, CLIPS, REQUIRED_JOINTS


def read_glb(path):
    data=Path(path).read_bytes()
    magic,version,length=struct.unpack_from('<III',data)
    if magic!=0x46546c67 or version!=2 or length!=len(data):raise ValueError('Invalid glTF2 GLB header')
    offset=12;document=None;binary=bytearray()
    while offset<len(data):
        size,kind=struct.unpack_from('<II',data,offset);offset+=8
        payload=data[offset:offset+size];offset+=size
        if kind==0x4e4f534a:document=json.loads(payload)
        elif kind==0x004e4942:binary=bytearray(payload)
    if document is None:raise ValueError('No glTF JSON chunk')
    return document,binary


def write_glb(path,document,binary):
    payload=json.dumps(document,separators=(',',':'),ensure_ascii=False).encode('utf-8')
    payload+=b' '*((-len(payload))%4);binary+=b'\0'*((-len(binary))%4)
    length=12+8+len(payload)+8+len(binary)
    Path(path).write_bytes(struct.pack('<III',0x46546c67,2,length)+struct.pack('<II',len(payload),0x4e4f534a)+payload+struct.pack('<II',len(binary),0x004e4942)+binary)


def quaternion(angles):
    x,y,z=[a*.5 for a in angles]
    sx,cx=math.sin(x),math.cos(x);sy,cy=math.sin(y),math.cos(y);sz,cz=math.sin(z),math.cos(z)
    return [sx*cy*cz-cx*sy*sz,cx*sy*cz+sx*cy*sz,cx*cy*sz-sx*sy*cz,cx*cy*cz+sx*sy*sz]


def multiply(a,b):
    ax,ay,az,aw=a;bx,by,bz,bw=b
    return [aw*bx+ax*bw+ay*bz-az*by,aw*by-ax*bz+ay*bw+az*bx,aw*bz+ax*by-ay*bx+az*bw,aw*bw-ax*bx-ay*by-az*bz]


def inverse(q):return [-q[0],-q[1],-q[2],q[3]]


def attach_animations(path):
    doc,binary=read_glb(path)
    nodes={node.get('name',''):i for i,node in enumerate(doc.get('nodes',[]))}
    parents={child:i for i,node in enumerate(doc.get('nodes',[])) for child in node.get('children',[])}
    def global_rotation(index):
        local=doc['nodes'][index].get('rotation',[0,0,0,1])
        return multiply(global_rotation(parents[index]),local) if index in parents else local
    missing=set(REQUIRED_JOINTS)-set(nodes)
    if missing:raise ValueError(f'glTF missing animated joints: {missing}')
    views=doc.setdefault('bufferViews',[]);accessors=doc.setdefault('accessors',[])
    def append(rows,kind):
        values=[v for row in rows for v in (row if isinstance(row,(list,tuple)) else [row])]
        binary.extend(b'\0'*((-len(binary))%4));offset=len(binary)
        binary.extend(struct.pack('<'+'f'*len(values),*values))
        views.append({'buffer':0,'byteOffset':offset,'byteLength':len(values)*4})
        accessor={'bufferView':len(views)-1,'componentType':5126,'count':len(rows),'type':kind}
        if kind=='SCALAR':accessor.update(min=[min(values)],max=[max(values)])
        accessors.append(accessor);return len(accessors)-1
    times=[i/24 for i in range(25)];time_index=append(times,'SCALAR')
    animations=[]
    def length(node):return math.sqrt(sum(v*v for v in doc['nodes'][nodes[node]].get('translation',[0,0,0])))
    leg_length=length('Shin_L')+length('Foot_L')
    root_extras=doc['nodes'][nodes['CharacterRoot']].get('extras',{}) if 'CharacterRoot' in nodes else {}
    parameters={'seat_metrics':root_extras.get('seat_kinematics'),'stature_scale':float(root_extras.get('body_height_m',BASE_HEIGHT))/BASE_HEIGHT}
    for clip in CLIPS:
        samplers=[];channels=[]
        animated_names=[name for name in ANIMATED_JOINTS if name in nodes]+['Skin_'+name for name in ANIMATED_JOINTS if 'Skin_'+name in nodes]
        for name in animated_names:
            node_id=nodes[name];node=doc['nodes'][node_id]
            rest=node.get('rotation',[0,0,0,1])
            semantic_name=name.removeprefix('Skin_')
            parent_rotation=global_rotation(parents[node_id]) if node_id in parents else [0,0,0,1]
            rows=[multiply(multiply(multiply(inverse(parent_rotation),quaternion(pose_values(clip,t,**parameters)[semantic_name])),parent_rotation),rest) for t in times]
            output=append(rows,'VEC4');samplers.append({'input':time_index,'output':output,'interpolation':'LINEAR'})
            channels.append({'sampler':len(samplers)-1,'target':{'node':node_id,'path':'rotation'}})
        for pelvis_name in ['PelvisRoot']+(['Skin_PelvisRoot'] if 'Skin_PelvisRoot' in nodes else []):
            pelvis_id=nodes[pelvis_name];position=list(doc['nodes'][pelvis_id].get('translation',[0,.88,0]))
            translations=[]
            for t in times:
                row=position[:]
                row[1]=pelvis_height(clip,t,position[1],leg_length,**parameters)
                translations.append(row)
            output=append(translations,'VEC3');samplers.append({'input':time_index,'output':output,'interpolation':'LINEAR'})
            channels.append({'sampler':len(samplers)-1,'target':{'node':pelvis_id,'path':'translation'}})
        # Standard glTF mesh weights make the same localized seat compression
        # visible outside this repository's Blender and Godot adapters.
        for node_id,node in enumerate(doc['nodes']):
            if 'mesh' not in node:continue
            mesh=doc['meshes'][node['mesh']];names=mesh.get('extras',{}).get('targetNames',[])
            if 'SeatContact' not in names:continue
            base=node.get('weights',mesh.get('weights',[0.]*len(names)))
            rows=[(1. if clip in ('Sit','Soak') else 0.) if name=='SeatContact' else base[index] for t in times for index,name in enumerate(names)]
            output=append(rows,'SCALAR');samplers.append({'input':time_index,'output':output,'interpolation':'LINEAR'})
            channels.append({'sampler':len(samplers)-1,'target':{'node':node_id,'path':'weights'}})
        animations.append({'name':clip,'samplers':samplers,'channels':channels})
    doc['animations']=animations
    for material in doc.get('materials',[]):
        if material.get('name','').startswith('CC0_Hair_') or material.get('extras',{}).get('character_alpha_mode')=='MASK':
            material['alphaMode']='MASK';material['alphaCutoff']=.35
            if material.get('name','').startswith('CC0_Hair_'):material['doubleSided']=True
    doc.setdefault('extras',{})['character_animation_contract']='named_joint_continuous_skin_v2'
    doc['extras']['seat_corrective_contract']='standard glTF morph SeatContact: Sit/Soak1; other clips0'
    doc['buffers'][0]['byteLength']=len(binary)
    write_glb(path,doc,binary)


def validate_glb(path):
    doc,binary=read_glb(path);errors=[]
    names={x.get('name') for x in doc.get('nodes',[])}
    if set(REQUIRED_JOINTS)-names:errors.append('missing animation joints')
    if {x.get('name') for x in doc.get('animations',[])}!=set(CLIPS):errors.append('missing native glTF clips')
    for animation in doc.get('animations',[]):
        animated={doc['nodes'][c['target']['node']].get('name') for c in animation.get('channels',[])}
        if set(REQUIRED_JOINTS)-animated:errors.append(animation['name']+': incomplete joint animation')
    for mesh in doc.get('meshes',[]):
        for primitive in mesh.get('primitives',[]):
            attrs=primitive.get('attributes',{})
            if not {'POSITION','NORMAL','TEXCOORD_0'}<=set(attrs):errors.append('mesh lacks position/normal/UV')
    if not doc.get('images'):errors.append('no baked PBR texture images')
    return errors
