"""Blender consumer for prepared, source-bound registered character PBR maps."""
import hashlib
import json
from pathlib import Path


def load_library(path):
    path=Path(path).resolve();data=json.loads(path.read_text(encoding='utf-8'))
    if data.get('schema')!='living_town.character_pbr.v1' or data.get('license')!='CC0-1.0':raise ValueError('Invalid character PBR library')
    from .assets import verify_assets,VENDOR
    provenance=verify_assets()
    from .linen import verify_linen,VENDOR as LINEN_VENDOR
    linen=verify_linen()
    if data.get('linen_receipt_sha256') is not None and data['linen_receipt_sha256']!=hashlib.sha256((LINEN_VENDOR/'source_receipts.json').read_bytes()).hexdigest():raise ValueError('Prepared linen uses different source receipt')
    if data.get('source_module_sha256')!=hashlib.sha256((Path(__file__).parent/'prepare_textures.py').read_bytes()).hexdigest():raise ValueError('Prepared textures use a different palette recipe source')
    if data.get('source_look_manifest_sha256')!=hashlib.sha256((Path(__file__).parent/'manifest.py').read_bytes()).hexdigest():raise ValueError('Prepared textures use different persona/wardrobe recipes')
    if data.get('source_provenance_sha256')!=hashlib.sha256((VENDOR/'provenance.json').read_bytes()).hexdigest():raise ValueError('Prepared textures use a different source provenance')
    checked=set()
    for entry in data['characters'].values():
        eyes=entry['roles'].get('eyes',{})
        if eyes.get('alpha_mode')!='MASK' or not eyes.get('alpha_semantics'):raise ValueError('Eye atlas lost its transparent cornea coverage semantics')
        for role in entry['roles'].values():
            for row in role['maps'].values():
                origin=linen if row.get('source_provider')=='Poly Haven' else provenance
                if row['source_sha256']!=origin['files'][row['source']]['sha256']:raise ValueError('Prepared map lost its original source binding')
                source=path.parent/row['path']
                if source in checked:continue
                if hashlib.sha256(source.read_bytes()).hexdigest()!=row['sha256']:raise ValueError('Prepared character texture changed: '+str(source))
                checked.add(source)
    data['_path']=path;return data


def material(builder,key,role):
    library=builder.texture_library;entry=library['characters'][key]['roles'][role];name=entry['material']
    if name in builder.materials:return builder.materials[name]
    bpy=builder.bpy;mat=bpy.data.materials.new(name);mat.use_nodes=True;mat.use_backface_culling=not entry.get('double_sided',False)
    nodes=mat.node_tree.nodes;links=mat.node_tree.links;bsdf=nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value=(1,1,1,1)
    bsdf.inputs['Roughness'].default_value=entry['roughness'];bsdf.inputs['Metallic'].default_value=0
    if 'Subsurface Weight' in bsdf.inputs:bsdf.inputs['Subsurface Weight'].default_value=entry.get('subsurface',0)
    for map_role,row in entry['maps'].items():
        path=library['_path'].parent/row['path'];image=bpy.data.images.load(str(path),check_existing=True)
        image.colorspace_settings.name=row['color_space'];image.pack()
        tex=nodes.new('ShaderNodeTexImage');tex.name='Registered_'+map_role;tex.image=image
        if map_role=='basecolor':
            links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
            if entry.get('alpha_mode')=='MASK':
                links.new(tex.outputs['Alpha'],bsdf.inputs['Alpha'])
                if hasattr(mat,'surface_render_method'):mat.surface_render_method='DITHERED'
                if hasattr(mat,'blend_method'):mat.blend_method='CLIP';mat.alpha_threshold=entry.get('alpha_cutoff',.35)
        elif map_role=='normal':
            normal=nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=entry.get('normal_strength',1)
            links.new(tex.outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],bsdf.inputs['Normal'])
        elif map_role=='roughness':
            links.new(tex.outputs['Color'],bsdf.inputs['Roughness'])
        elif map_role=='ao':
            group=bpy.data.node_groups.get('glTF Material Output')
            if group is None:
                group=bpy.data.node_groups.new('glTF Material Output','ShaderNodeTree')
                group.interface.new_socket(name='Occlusion',in_out='INPUT',socket_type='NodeSocketFloat')
            node=nodes.new('ShaderNodeGroup');node.node_tree=group;links.new(tex.outputs['Color'],node.inputs['Occlusion'])
    mat['character_pbr_role']=role;mat['character_pbr_library_sha256']=hashlib.sha256(library['_path'].read_bytes()).hexdigest()
    if entry.get('alpha_mode'):mat['character_alpha_mode']=entry['alpha_mode']
    if entry.get('mapping'):mat['character_mapping']=entry['mapping'];mat['character_repeat_m']=entry['repeat_m']
    builder.materials[name]=mat
    return mat
