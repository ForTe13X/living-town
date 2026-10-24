"""Independently verify embedded character PBR pixels and native UV registration.

Uses the dedicated refinement pipeline's GLB span reader. This checks real
exported bytes; license review and aesthetic acceptance remain separate.
"""
import argparse
import hashlib
import io
import json
import math
import statistics
import struct
from pathlib import Path
import sys

from PIL import Image,ImageChops

HERE=Path(__file__).resolve().parent;REPO=HERE.parents[2]
if str(REPO) not in sys.path:sys.path.insert(0,str(REPO))
from tools.asset_refinement.verify_scanned_exports import _GLB
from tools.town_upgrade.characters.assets import fit_asset,geometry_for,visible_skin
from tools.town_upgrade.characters.human import adapted_body
from tools.town_upgrade.characters.manifest import BASE_HEIGHT,CLIPS,build_manifest


def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def need(value,reason):
    if not value:raise ValueError(reason)


def float_attribute(glb,index,kind):
    """Decode ordinary or standard sparse float accessors locally.

    A missing base bufferView means zero initialization. Sparse indices are
    tightly packed, strictly increasing and unique; patches never escape the
    declared view or accessor. The common scanned-asset reader stays unchanged.
    """
    a=glb.doc['accessors'][index];components={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[kind]
    count=a.get('count');need(type(count) is int and count>0,'Invalid float accessor count')
    need(a.get('componentType')==5126 and a.get('type')==kind and not a.get('normalized',False),'Invalid float accessor type')
    width=components*4;rows=[(0.,)*components for _ in range(count)]
    if 'bufferView' in a:
        view=glb.doc['bufferViews'][a['bufferView']];data=glb.view(a['bufferView']);offset=a.get('byteOffset',0);stride=view.get('byteStride',width)
        need(type(offset) is int and offset>=0 and offset%4==0 and type(stride) is int and stride>=width and stride%4==0,'Invalid float base offset/stride')
        need(offset+(count-1)*stride+width<=len(data),'Float base exceeds bufferView')
        rows=[struct.unpack_from('<'+'f'*components,data,offset+i*stride) for i in range(count)]
        need(all(math.isfinite(value) for row in rows for value in row),'Nonfinite float base value')
    else:need(a.get('byteOffset',0)==0,'Zero-base accessor has a byte offset')
    if 'sparse' in a:
        sparse=a['sparse'];n=sparse.get('count');need(type(n) is int and 0<n<=count,'Invalid sparse count')
        indices=sparse['indices'];code={5121:'B',5123:'H',5125:'I'}.get(indices.get('componentType'))
        need(code is not None,'Invalid sparse index component type');size=struct.calcsize(code)
        index_view=glb.doc['bufferViews'][indices['bufferView']];data=glb.view(indices['bufferView']);offset=indices.get('byteOffset',0)
        need('byteStride' not in index_view and type(offset) is int and offset>=0 and offset%size==0 and offset+n*size<=len(data),'Sparse index span exceeds packed bufferView')
        ids=struct.unpack_from('<'+code*n,data,offset)
        need(all(0<=i<count for i in ids) and all(x<y for x,y in zip(ids,ids[1:])),'Sparse indices must be sorted, unique and in range')
        values=sparse['values'];value_view=glb.doc['bufferViews'][values['bufferView']];data=glb.view(values['bufferView']);offset=values.get('byteOffset',0)
        need('byteStride' not in value_view and type(offset) is int and offset>=0 and offset%4==0 and offset+n*width<=len(data),'Sparse value span exceeds packed bufferView')
        patches=[struct.unpack_from('<'+'f'*components,data,offset+i*width) for i in range(n)]
        need(all(math.isfinite(value) for row in patches for value in row),'Nonfinite sparse value')
        for i,row in zip(ids,patches):rows[i]=row
    return rows


def pixel_check(glb,info,source,alpha=False,channel=None):
    payload,meta=glb.image(info)
    with Image.open(io.BytesIO(payload)) as actual,Image.open(source) as expected:
        mode='RGBA' if alpha else 'RGB';actual=actual.convert(mode);expected=expected.convert(mode)
        if channel:actual=actual.getchannel(channel);expected=expected.getchannel(channel)
        need(actual.size==expected.size,'Registered map dimensions changed')
        extrema=ImageChops.difference(actual,expected).getextrema()
        error=extrema[1] if channel else max(v[1] for v in extrema)
        need(error<=1,'Embedded pixels differ from prepared input by '+str(error))
        return {**meta,'maximum_channel_error_255':error,'dimensions':list(actual.size),'compared_channels':channel or mode,'source_sha256':sha(source)}


def expected_uvs(look,role,entry):
    data=adapted_body(look)
    if role in ('skin','shirt','pants'):
        garment=fit_asset(data,'clothes',entry['garment_asset'].split('/')[-1])
        geometry=visible_skin(data,garment,(fit_asset(data,'clothes',entry['shoe_asset'].split('/')[-1]),))[0] if role=='skin' else geometry_for(garment,role)[0]
    else:
        category,name=entry[{'eyes':'eye_asset','brows':'brow_asset','lashes':'lash_asset','shoes':'shoe_asset'}[role]].split('/')
        geometry=geometry_for(fit_asset(data,category,name))[0]
    return [(u,1-v) for u,v in geometry[2]]


def verify_uv(actual,expected):
    epsilon=.000002;grid={}
    for u,v in expected:grid.setdefault((math.floor(u/epsilon),math.floor(v/epsilon)),[]).append((u,v))
    maximum=0
    for u,v in actual:
        key=(math.floor(u/epsilon),math.floor(v/epsilon));matches=[p for a in [-1,0,1] for b in [-1,0,1] for p in grid.get((key[0]+a,key[1]+b),[])]
        need(matches,'Exported UV was moved or tiled away from native atlas')
        error=min(max(abs(u-x),abs(v-y)) for x,y in matches);need(error<=epsilon,'Exported UV changed');maximum=max(maximum,error)
    return {'vertices_checked':len(actual),'maximum_absolute_uv_error':maximum,'tolerance':epsilon,'registration':'original authored atlas with exporter V flip only'}


def metric_uv_edges(glb,primitive,repeat,scale):
    attrs=primitive['attributes'];count=glb.doc['accessors'][attrs['POSITION']]['count']
    points=glb.accessor(attrs['POSITION'],'VEC3',count);uv=glb.accessor(attrs['TEXCOORD_0'],'VEC2',count)
    if 'indices' in primitive:
        a=glb.doc['accessors'][primitive['indices']];code={5121:'B',5123:'H',5125:'I'}[a['componentType']]
        ids=struct.unpack_from('<'+code*a['count'],glb.view(a['bufferView']),a.get('byteOffset',0))
    else:ids=range(count)
    ratios=[]
    for start in range(0,len(ids),3):
        face=tuple(ids[start:start+3])
        for i,j in zip(face,face[1:]+face[:1]):
            physical=math.dist(points[i],points[j])*scale
            repeat_distance=math.hypot((uv[i][0]-uv[j][0])*repeat[0],(uv[i][1]-uv[j][1])*repeat[1])
            if physical>.003 and repeat_distance>.001:ratios.append(repeat_distance/physical)
    return ratios


def verify_corrective(glb):
    targets=[];maximum=0.
    for node_index,node in enumerate(glb.doc['nodes']):
        if 'mesh' not in node:continue
        mesh=glb.doc['meshes'][node['mesh']];names=mesh.get('extras',{}).get('targetNames',[])
        if 'SeatContact' not in names:continue
        index=names.index('SeatContact');targets.append((node_index,index,len(names)))
        for primitive in mesh['primitives']:
            need('POSITION' in primitive['targets'][index],'Seat corrective has no portable position deltas')
            accessor=primitive['targets'][index]['POSITION'];count=glb.doc['accessors'][accessor]['count']
            values=float_attribute(glb,accessor,'VEC3')
            maximum=max(maximum,max((math.sqrt(sum(v*v for v in row)) for row in values),default=0.))
    need(bool(targets),'Missing actual SeatContact morph mesh')
    need({a['name'] for a in glb.doc['animations']}==set(CLIPS),'Corrective export lost clip identities')
    for animation in glb.doc['animations']:
        expected=1. if animation['name'] in ('Sit','Soak') else 0.
        for node_index,index,count in targets:
            channels=[c for c in animation['channels'] if c['target']['node']==node_index and c['target']['path']=='weights']
            need(len(channels)==1,'Native clip lacks one standard morph weights channel')
            sampler=animation['samplers'][channels[0]['sampler']];accessor=glb.doc['accessors'][sampler['output']]
            need(accessor['type']=='SCALAR' and accessor['componentType']==5126 and accessor['count']%count==0,'Malformed standard morph weights accessor')
            values=[row[0] for row in float_attribute(glb,sampler['output'],'SCALAR')]
            need(all(abs(value-expected)<1e-6 for value in values[index::count]),'Wrong SeatContact weight in '+animation['name'])
    return {'name':'SeatContact','mesh_nodes':len(targets),'standard_weights_clips':list(CLIPS),'maximum_rest_source_delta_m':maximum,'active_clips':['Sit','Soak'],'other_clip_weight':0.}


def verify(build):
    build=Path(build).resolve();library_path=build/'registered_pbr/library_manifest.json';library=json.loads(library_path.read_text(encoding='utf-8'));looks=build_manifest(json.loads((REPO/'game/data/personas.json').read_text(encoding='utf-8')))['characters']
    records={};failures=[]
    for path in sorted((build/'models').glob('*.glb')):
        key=path.stem;entry=library['characters'][key];glb=_GLB(path);by_name={m.get('name'):i for i,m in enumerate(glb.doc['materials'])};roles={}
        try:
            for role,row in entry['roles'].items():
                need(row['material'] in by_name,key+': missing registered '+role)
                index=by_name[row['material']];material=glb.doc['materials'][index];pbr=material['pbrMetallicRoughness'];maps={}
                need(material.get('extras',{}).get('character_pbr_library_sha256')==sha(library_path),'Material lost source-library binding')
                need(abs(pbr.get('roughnessFactor',1)-row['roughness'])<.00001,'Roughness finish changed')
                need(pbr.get('metallicFactor',1)==0,'Nonmetal character surface became metallic')
                for map_role,source in row['maps'].items():
                    info=pbr['baseColorTexture'] if map_role=='basecolor' else material['normalTexture'] if map_role=='normal' else pbr['metallicRoughnessTexture'] if map_role=='roughness' else material['occlusionTexture']
                    need(not info.get('extensions',{}).get('KHR_texture_transform'),'Unexpected atlas transform')
                    need(info.get('texCoord',0)==0,'Registered atlas uses wrong UV channel')
                    maps[map_role]=pixel_check(glb,info,library_path.parent/source['path'],row.get('alpha_mode')=='MASK' and map_role=='basecolor',channel='R' if map_role=='ao' else 'G' if map_role=='roughness' else None)
                if 'normal' in row['maps']:need(abs(material['normalTexture'].get('scale',1)-row['normal_strength'])<.00001,'Normal scale changed')
                if row.get('alpha_mode')=='MASK':need(material.get('alphaMode')=='MASK' and material.get('doubleSided',False)==row.get('double_sided',False),'Authored facial/strand alpha contract lost')
                uv=[];metric_ratios=[]
                for mesh in glb.doc['meshes']:
                    for primitive in mesh['primitives']:
                        if primitive.get('material')!=index:continue
                        attrs=primitive['attributes'];positions=glb.doc['accessors'][attrs['POSITION']]['count']
                        need({'NORMAL','TEXCOORD_0'}<=set(attrs),'Missing registered surface attributes')
                        if 'normal' in row['maps']:need('TANGENT' in attrs,'Authored tangent normal lacks tangent basis')
                        uv.extend(glb.accessor(attrs['TEXCOORD_0'],'VEC2',positions))
                        if row.get('mapping')=='metric_cloth':metric_ratios.extend(metric_uv_edges(glb,primitive,row['repeat_m'],looks[key]['body_height_m']/BASE_HEIGHT))
                need(bool(uv),'Registered material unused by geometry')
                if row.get('mapping')=='metric_cloth':
                    need(bool(metric_ratios),'Missing metric cloth UV edges');median=statistics.median(metric_ratios)
                    need(.90<median<1.10,'Cloth repeat no longer matches physical source dimensions')
                    uv_report={'vertices_checked':len(uv),'metric_edges_checked':len(metric_ratios),'median_uv_to_physical_ratio':median,'repeat_m':row['repeat_m'],'mapping':'source photographed physical repeat; gently folded panel projection and length-based strap UV'}
                else:uv_report=verify_uv(uv,expected_uvs(looks[key],role,entry))
                roles[role]={'maps':maps,'uv':uv_report}
            records[key]={'glb_sha256':sha(path),'roles':roles,'seat_corrective':verify_corrective(glb)}
        except (ValueError,KeyError) as error:failures.append(key+': '+str(error))
    need(bool(records) or bool(failures),'No exported character models')
    built=json.loads((build/'build_report.json').read_text(encoding='utf-8')) if (build/'build_report.json').exists() else {}
    report={'success':not failures,'scope':'Actual embedded PBR pixels, atlas registration, tangent attributes, alpha mode, source bindings and standard native morph channels; no artistic approval or measured skin roughness claim','library_sha256':sha(library_path),'verifier_sha256':sha(__file__),'build_source_digest':built.get('source_digest'),'entries':records,'failures':failures}
    return report


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--build',type=Path,required=True);parser.add_argument('--report',type=Path,required=True);args=parser.parse_args()
    result=verify(args.build);args.report.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps({'success':result['success'],'checked':list(result['entries']),'failures':result['failures']}));raise SystemExit(0 if result['success'] else 1)
