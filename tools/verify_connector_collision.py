#!/usr/bin/env python3
"""Verify the frozen connector source and recorded native collision fixture using stdlib.

This rechecks recorded data. It does not run Unreal, cook assets, or prove walking.
"""
from pathlib import Path
from collections import Counter
import argparse,gzip,hashlib,json,math,struct

SOURCE_SHA='b7cf9f1d56b7159e7a57ddc17dd95d3120b22ed8bd92f79f5099f5a18798eb2e'
NAMESPACE='/Game/LivingTown_UEPilot/TownSlice_v003/ReserveConnectorPhysics_v002/Colliders'
READY='READ_ONLY_EXACT_NATIVE_29_COLLIDER_ASSETS_AND_COOKED_CHAOS'
def need(value,message):
    if not value:raise ValueError(message)
def digest(data):return hashlib.sha256(data).hexdigest()
def source(data):
    need(len(data)==73798 and digest(data)==SOURCE_SHA,'Exact 73798-byte source SHA required')
    need(data[:16]==b'LTCOLL29V001\0\0\0\0'and struct.unpack_from('<II',data,16)==(29,1424),'Source header/count mismatch');at=24;rows=[];maximum_error=0.0
    for index in range(29):
        n,v,t=struct.unpack_from('<III',data,at);at+=12;need(1<=n<=96 and 3<=v<=10000 and 1<=t<=10000,'Bounded mesh header');name=data[at:at+n].decode('ascii');at+=n;need(name.startswith(f'SM_CA_{index:02}_')and name.endswith('_WALK_COLLIDER')and name.replace('_','').isalnum(),'Ordered source name')
        values=struct.unpack_from('<'+str(v*3)+'d',data,at);at+=24*v;need(all(math.isfinite(x)and abs(x)<=1e8 for x in values),'Finite bounded F64 position');points=[]
        for start in range(0,len(values),3):
            encoded=struct.pack('<fff',*values[start:start+3]);points.append(list(struct.unpack('<III',encoded)));rounded=struct.unpack('<fff',encoded);maximum_error=max(maximum_error,*(abs(a-b)for a,b in zip(values[start:start+3],rounded)))
        triangles=[list(x)for x in struct.iter_unpack('<III',data[at:at+12*t])];at+=12*t;need(all(len(set(q))==3 and max(q)<v for q in triangles),'Bounded distinct triangle indices');edges=Counter()
        for q in triangles:
            for a,b in((q[0],q[1]),(q[1],q[2]),(q[2],q[0])):edges[tuple(sorted((tuple(points[a]),tuple(points[b]))))]+=1
        need(edges and set(edges.values())=={2},'Closed F32 geometric edge multiplicity must be two');rows.append({'name':name,'vertices':v,'triangles':t,'points':points,'indices':triangles})
    need(at==len(data)and sum(x['triangles']for x in rows)==1424,'Closed binary with no trailing data');return rows,maximum_error
def oriented(points,triangles,flip=False):
    need(all(type(p)is list and len(p)==3 and all(type(x)is int and 0<=x<=0xffffffff for x in p)for p in points),'F32 position bit triples');out=Counter()
    for t in triangles:
        need(type(t)is list and len(t)==3 and all(type(x)is int and 0<=x<len(points)for x in t),'Bounded triangle index triples');q=[tuple(points[x])for x in t]
        if flip:q[0],q[1]=q[1],q[0]
        out[min(tuple(q),tuple(q[1:]+q[:1]),tuple(q[2:]+q[:2]))]+=1
    return out
def native(reply,rows):
    need(reply['schema']=='LivingTown.NativeConnectorCollisionReadback.v1'and reply['status']==READY and reply['source_sha256']==SOURCE_SHA and reply['source_triangles']==1424 and len(reply['meshes'])==29,'Exact native source/readback identity');need(all(reply[x]is False for x in('asset_save_or_actor_spawn','reader_explicit_build_cook_compile_flush_wait','full_walk_camera_rails_or_final_render_qualified')),'Reader scope flags')
    for source_mesh,actual in zip(rows,reply['meshes'],strict=True):
        need(actual['asset']==NAMESPACE+'/'+source_mesh['name']+'.'+source_mesh['name'],'Exact new asset namespace');need(actual['MeshDescription_positions_F32_bits']==source_mesh['points']and actual['MeshDescription_source_vertex_indices']==source_mesh['indices'],'Committed MeshDescription F32 bits/source indices differ');expected=oriented(source_mesh['points'],source_mesh['indices']);need(oriented(actual['provider_positions_F32_bits'],actual['provider_indices'])==expected and len(actual['provider_indices'])==source_mesh['triangles'],'Physics provider differs from full source');need(type(actual['provider_bFlipNormals'])is bool,'Actual provider winding flag required');cooked_expected=oriented(actual['provider_positions_F32_bits'],actual['provider_indices'],actual['provider_bFlipNormals']);need(oriented(actual['Chaos_cooked_positions_F32_bits'],actual['Chaos_cooked_indices'])==cooked_expected and len(actual['Chaos_cooked_indices'])==source_mesh['triangles'],'Actual cooked Chaos oriented triangles differ');need(len(actual['Chaos_cooked_external_face_indices'])==source_mesh['triangles'],'Actual cooked face census');need(actual['complex_as_simple_static_BlockAll_no_simple_shapes']is True and actual['Nanite_enabled']is False and actual['support_ray_tracing']is False,'Static complex-as-simple BlockAll policy');need(actual['package_dirty_before']==actual['package_dirty_after'],'Reader dirtied a package');need(all(actual[k]is True for k in('MeshDescription_source_F64_to_F32_and_indices_exact','provider_source_oriented_triangle_multiset_exact','cooked_oriented_triangle_multiset_exact_after_recorded_flip','all_source_and_cooked_checks_exact')),'Native and portable checks disagree');need(len(actual['BodySetup_guid'])==32 and int(actual['BodySetup_guid'],16)!=0,'Actual nonzero BodySetup identity')
def verify(root):
    root=Path(root);rows,error=source((root/'unreal/Content/ConnectorCollisionSource_v001/ConnectorWalk29.ltcoll').read_bytes());evidence=json.loads((root/'docs/asset_refinement/evidence/connector_collision_v001.json').read_text());need(evidence['schema']=='LivingTown.NativeConnectorCollisionEvidence.v1'and evidence['source']['sha256']==SOURCE_SHA,'Evidence identity');record=evidence['shared_native_readback'];path=(root/record['path']).resolve();need(path.is_relative_to(root.resolve()),'Contained portable native receipt');packed=path.read_bytes();need(len(packed)==record['compressed_bytes']and digest(packed)==record['compressed_sha256'],'Compressed actual receipt custody');raw=gzip.decompress(packed);need(len(raw)==record['raw_bytes']and len(raw)<=2**21 and digest(raw)==record['raw_sha256'],'Full actual receipt custody');native(json.loads(raw),rows);need(evidence['author']['native_readback_sha256']==record['raw_sha256']==evidence['cold']['native_readback_sha256'],'Author and new-process cold full readbacks byte-identical');need(evidence['cold']['same29_saved_package_bytes']is True and evidence['qualification']['full_world_walk_qualified']is False,'Honest frozen-case scope')
    return {'status':'PASS_PORTABLE_SOURCE29_AND_RECORDED_NATIVE_MD_PROVIDER_CHAOS1424','meshes':29,'source_vertices':sum(x['vertices']for x in rows),'source_triangles':1424,'closed_F32_edge_multiplicity':2,'maximum_F64_to_F32_error_cm':error,'source_sha256':SOURCE_SHA,'actual_Unreal_executed_by_this_verifier':False,'current_world_walk_render_or_FPS_qualified':False}
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);args=parser.parse_args();print(json.dumps(verify(args.root),indent=2))
