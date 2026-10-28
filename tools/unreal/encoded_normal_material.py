"""Reusable UE editor helper for an owned encoded-RGB confidence normal material.

No file IO, personal paths, trial IDs, actors or runtime switches. Callers own
input provenance, namespace/source-file guards, save/reopen and visual review.
Only pass owned textures to configure_encoded_texture; it modifies that object.
"""
import unreal as u
M=u.MaterialEditingLibrary
NORMAL_CODE='float3 n=(lerp(OriginalRGB,BakedRGB,Confidence)*2.0-1.0)*float3(1.0,-1.0,1.0); return normalize(n);'
def _need(v,m):
    if not v:raise ValueError(m)
def _set(o,k,v):
    o.set_editor_property(k,v);_need(o.get_editor_property(k)==v,'Editor property refused: '+k)
def texture_policy(role):
    _need(role in('original','baked','confidence'),'Unknown encoded texture role');comp={'original':u.TextureCompressionSettings.TC_VECTOR_DISPLACEMENTMAP,'baked':u.TextureCompressionSettings.TC_HDR,'confidence':u.TextureCompressionSettings.TC_GRAYSCALE}[role];address=u.TextureAddress.TA_CLAMP if role=='confidence'else u.TextureAddress.TA_WRAP
    return {'compression_settings':comp,'srgb':False,'flip_green_channel':False,'filter':u.TextureFilter.TF_TRILINEAR,'mip_gen_settings':u.TextureMipGenSettings.TMGS_SIMPLE_AVERAGE,'address_x':address,'address_y':address}
def configure_encoded_texture(texture,role):
    """Configure one caller-owned data texture; never silently use BC5 normals."""
    _need(isinstance(texture,u.Texture2D),'Texture2D required')
    for k,v in texture_policy(role).items():_set(texture,k,v)
    return {k:str(texture.get_editor_property(k))for k in texture_policy(role)}
def connected_graph(material):
    roots={k:M.get_material_property_input_node(material,p)for k,p in [('BaseColor',u.MaterialProperty.MP_BASE_COLOR),('Roughness',u.MaterialProperty.MP_ROUGHNESS),('Metallic',u.MaterialProperty.MP_METALLIC),('Normal',u.MaterialProperty.MP_NORMAL)]};pending=[n for n in roots.values()if n];seen={}
    while pending:
        n=pending.pop();name=n.get_name()
        if name in seen:continue
        _need(len(seen)<128 and n.get_outer()==material,'Bounded owned connected graph');names=list(M.get_material_expression_input_names(n));nodes=list(M.get_inputs_for_material_expression(material,n));_need(len(names)==len(nodes),'Aligned expression inputs');row={'name':name,'class':n.get_class().get_path_name(),'inputs':{k:x.get_name()if x else None for k,x in zip(names,nodes)}}
        if isinstance(n,(u.MaterialExpressionTextureObject,u.MaterialExpressionTextureSample)):
            t=n.get_editor_property('texture');row.update(texture=t.get_path_name()if t else None,sampler_type=str(n.get_editor_property('sampler_type')))
        if isinstance(n,u.MaterialExpressionMaterialFunctionCall):
            f=n.get_editor_property('material_function');row['function']=f.get_path_name()if f else None
        if isinstance(n,u.MaterialExpressionConstant):row['r']=n.get_editor_property('r')
        if isinstance(n,u.MaterialExpressionTextureCoordinate):row['coordinate_index']=n.get_editor_property('coordinate_index')
        if isinstance(n,u.MaterialExpressionCustom):row.update(code=n.get_editor_property('code'),output_type=str(n.get_editor_property('output_type')))
        seen[name]=row;pending.extend(x for x in nodes if x)
    return {'path':material.get_path_name(),'tangent_space_normal':material.get_editor_property('tangent_space_normal'),'roots':{k:n.get_name()if n else None for k,n in roots.items()},'nodes':seen}
def create_confidence_material(source_material,destination_path,textures,*,baseline=False,skeletal_usage=True,log=None):
    """Duplicate a connected tangent-space source and append a Normal-only graph.

    Texture keys are original/baked/confidence. Source PBR connected nodes must
    remain reachable unchanged (the proven glTF shared-body source contract).
    Returns (new_material, readback). It never saves or assigns the material.
    """
    source=u.load_asset(source_material)if isinstance(source_material,str)else source_material;_need(isinstance(source,u.Material),'Material source required');_need(set(textures)=={'original','baked','confidence'},'Exactly three encoded texture roles');_need(destination_path.startswith('/Game/')and not u.EditorAssetLibrary.does_asset_exist(destination_path),'Fresh owned material destination');before_source=connected_graph(source);material=u.EditorAssetLibrary.duplicate_asset(source.get_path_name(),destination_path.split('.',1)[0]);_need(isinstance(material,u.Material)and material!=source,'Distinct derived material');_set(material,'used_with_skeletal_mesh',bool(skeletal_usage));before=connected_graph(material);_need(before['tangent_space_normal']is True and all(before['roots'].values()),'Connected tangent-space source contract')
    def node(cls,x,y):
        n=M.create_material_expression(material,cls,x,y);_need(n and n.get_outer()==material,'Owned expression');return n
    def wire(a,index,b,pin):
        outputs=list(M.get_material_expression_output_names(a));_need(index<len(outputs),'Actual native output index');_need(M.connect_material_expressions(a,outputs[index],b,pin),'Expression connection refused: '+pin)
    uv=node(u.MaterialExpressionTextureCoordinate,-1000,700);_set(uv,'coordinate_index',0);samples={}
    for i,(role,t)in enumerate(textures.items()):
        _need(isinstance(t,u.Texture2D),'Texture role '+role)
        for k,v in texture_policy(role).items():_need(t.get_editor_property(k)==v,'Texture policy differs: '+role+'.'+k)
        n=node(u.MaterialExpressionTextureSample,-700,500+i*200);_set(n,'texture',t);_set(n,'sampler_type',u.MaterialSamplerType.SAMPLERTYPE_LINEAR_GRAYSCALE if role=='confidence'else u.MaterialSamplerType.SAMPLERTYPE_LINEAR_COLOR);wire(uv,0,n,'UVs');samples[role]=n
    custom=node(u.MaterialExpressionCustom,-200,500);_set(custom,'description','ENCODED_RGB_CONFIDENCE_NORMAL');_set(custom,'code',NORMAL_CODE);_set(custom,'output_type',u.CustomMaterialOutputType.CMOT_FLOAT3);_set(custom,'additional_outputs',[]);inputs=[]
    for name in('OriginalRGB','BakedRGB','Confidence'):
        i=u.CustomInput();i.set_editor_property('input_name',name);inputs.append(i)
    _set(custom,'inputs',inputs);wire(samples['original'],0,custom,'OriginalRGB');wire(samples['baked'],0,custom,'BakedRGB')
    if baseline:
        zero=node(u.MaterialExpressionConstant,-400,1000);_set(zero,'r',0.);wire(zero,0,custom,'Confidence')
    else:wire(samples['confidence'],1,custom,'Confidence')
    _need(M.connect_material_property(custom,'',u.MaterialProperty.MP_NORMAL),'Normal root refused');after=connected_graph(material)
    for key in('BaseColor','Roughness','Metallic'):_need(after['roots'][key]==before['roots'][key],'Source PBR root changed: '+key)
    _need(all(after['nodes'].get(k)==v for k,v in before['nodes'].items()),'Source connected PBR nodes changed');errors=list(M.recompile_material(material));report={'source':source.get_path_name(),'destination':material.get_path_name(),'before':before,'after':after,'compiler_errors':errors,'baseline_zero_confidence':bool(baseline),'normal_only_derivative':True,'green_conversion_once':True}
    if log:log(report)
    _need(errors==[],'Material compiler errors');_need(connected_graph(material)==after and connected_graph(source)==before_source,'Graph/source changed during compile');return material,report
