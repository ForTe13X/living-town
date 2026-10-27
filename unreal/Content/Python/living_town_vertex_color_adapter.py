"""Owned derivative fixing untextured glTF vertex color; originals read only."""
import json
from collections import Counter

def need(value,message):
    if not value:raise ValueError(message)

def apply(unreal,write):
    ml=unreal.MaterialEditingLibrary;eal=unreal.EditorAssetLibrary;keep=[]
    target='/Game/LivingTownHeroCore/__HeroMesh_Hero_OakBookshelf_LOD0.__HeroMesh_Hero_OakBookshelf_LOD0'
    pigment='/Game/LivingTownHeroCore/HeroCore_Authored_Matte_Pigment.HeroCore_Authored_Matte_Pigment'
    parent='/InterchangeAssets/gltf/MaterialInstances/MI_Default_Opaque_DS.MI_Default_Opaque_DS'
    master='/InterchangeAssets/gltf/M_Default.M_Default'
    body='/InterchangeAssets/gltf/MaterialBodies/MF_Default_Body.MF_Default_Body'
    destination='/Game/LivingTownVertexAdapter/'
    source_mesh=unreal.load_asset(target);source_pigment=unreal.load_asset(pigment)
    need(isinstance(source_mesh,unreal.StaticMesh) and isinstance(source_pigment,unreal.MaterialInstanceConstant),'Exact owned source assets missing')
    need(source_mesh.get_num_sections(0)==2 and source_mesh.get_material(0)==source_pigment,'Source bookshelf material assignment differs')
    need(source_pigment.get_editor_property('parent').get_path_name()==parent,'Actual pigment parent changed')
    need(unreal.load_asset(parent).get_editor_property('parent').get_path_name()==master,'Actual opaque parent changed')
    def name(o):return o.get_name() if o else None
    def paths(o):return [m.get_path_name() for m in ml.get_material_used_textures(o)]
    def value(v):
        if isinstance(v,unreal.Object):return v.get_path_name()
        if hasattr(v,'r'):return [v.r,v.g,v.b,v.a]
        return v
    def parameters(o):
        rows={}
        for kind in ('scalar','vector','texture','static_switch'):
            names=getattr(ml,'get_'+kind+'_parameter_names')(o);fn=getattr(ml,'get_material_instance_'+kind+'_parameter_value')
            rows[kind]={str(n):value(fn(o,n)) for n in names}
        rows['typed_local_static_parameters']=json.loads(unreal.LivingTownMaterialInspection.read_static_switches(o))['parameters']
        return rows
    before_parameters=parameters(source_pigment)
    need(before_parameters['static_switch']['bHasBaseColorTexture'] is False,'Only proven untextured pigment path may be adapted')
    def graph(asset):
        is_material=isinstance(asset,unreal.Material)
        expressions=ml.get_material_expressions(asset) if is_material else ml.get_material_function_expressions(asset)
        rows={}
        for e in expressions:
            cls=e.get_class().get_name();ins=ml.get_inputs_for_material_expression(asset,e) if is_material else ml.get_inputs_for_material_function_expression(asset,e)
            names=list(ml.get_material_expression_input_names(e));need(len(ins)==len(names),'Graph input array mismatch')
            row={'class':cls,'inputs':[[str(n),name(i)] for n,i in zip(names,ins)],'outputs':list(ml.get_material_expression_output_names(e))}
            if cls=='MaterialExpressionMaterialFunctionCall':row['function']=value(e.get_editor_property('material_function'))
            if cls=='MaterialExpressionFunctionInput':row['function_input_name']=str(e.get_editor_property('InputName'))
            if cls=='MaterialExpressionFunctionOutput':row['function_output_name']=str(e.get_editor_property('OutputName'))
            if cls in ('MaterialExpressionStaticBoolParameter','MaterialExpressionStaticSwitchParameter'):
                row['parameter_name']=str(e.get_editor_property('ParameterName'));row['default_value']=bool(e.get_editor_property('DefaultValue'))
            if cls=='MaterialExpressionNamedRerouteUsage':row['declaration']=name(unreal.LivingTownMaterialInspection.read_reroute_declaration(e))
            if cls=='MaterialExpressionNamedRerouteDeclaration':row['declaration_name']=str(e.get_editor_property('Name'))
            rows[e.get_name()]=row
        return rows
    originals={p:graph(unreal.load_asset(p)) for p in (master,body)}
    def duplicate(source,label):
        dest=destination+label;need(not eal.does_asset_exist(dest),'Fresh owned adapter asset required')
        obj=eal.duplicate_asset(source,dest);need(obj is not None and obj.get_path_name()==dest+'.'+label,'Native duplication failed');keep.append(obj);return obj
    local_body=duplicate(body,'MF_Default_Body_VertexColor')
    before_body=graph(local_body);need(before_body==originals[body],'Function clone graph differs before edit')
    expressions={e.get_name():e for e in ml.get_material_function_expressions(local_body)}
    switch=expressions['MaterialExpressionStaticSwitch_0'];factor=expressions['MaterialExpressionNamedRerouteUsage_3']
    need(before_body[switch.get_name()]['inputs']==[['True','MaterialExpressionReroute_0'],['False',factor.get_name()],['Value','MaterialExpressionStaticBoolParameter_0']],'Exact proven switch inputs changed')
    declaration=unreal.LivingTownMaterialInspection.read_reroute_declaration(factor)
    need(str(declaration.get_editor_property('Name'))=='Input_BaseColorFactor_RGB','False branch is not the observed factor reroute')
    vertex=ml.create_material_expression_in_function(local_body,unreal.MaterialExpressionVertexColor,-200,-200)
    multiply=ml.create_material_expression_in_function(local_body,unreal.MaterialExpressionMultiply,0,-200)
    need(vertex is not None and multiply is not None,'Owned material nodes not created')
    need(ml.connect_material_expressions(factor,'',multiply,'A'),'Factor input not connected')
    need(ml.connect_material_expressions(vertex,'',multiply,'B'),'Vertex-color input not connected')
    need(ml.connect_material_expressions(multiply,'',switch,'False'),'Untextured branch not connected')
    after_body=graph(local_body);expected=dict(before_body);expected[switch.get_name()]=dict(expected[switch.get_name()]);expected[switch.get_name()]['inputs']=[['True','MaterialExpressionReroute_0'],['False',multiply.get_name()],['Value','MaterialExpressionStaticBoolParameter_0']]
    need({k:v for k,v in after_body.items() if k not in (vertex.get_name(),multiply.get_name())}==expected,'Function changed outside the one declared False input')
    need(len(after_body)==len(before_body)+2,'Unexpected added/deleted function expressions')
    local_master=duplicate(master,'M_Default_VertexColor')
    before_master=graph(local_master);need(before_master==originals[master],'Master clone graph differs before edit')
    calls=[e for e in ml.get_material_expressions(local_master) if e.get_class().get_name()=='MaterialExpressionMaterialFunctionCall' and value(e.get_editor_property('material_function'))==body]
    need(len(calls)==1,'Expected exactly one default-body function call')
    calls[0].set_editor_property('material_function',local_body)
    after_master=graph(local_master);expected_master=dict(before_master);expected_master[calls[0].get_name()]=dict(expected_master[calls[0].get_name()]);expected_master[calls[0].get_name()]['function']=local_body.get_path_name()
    need(after_master==expected_master,'Master graph changed outside the one local function binding')
    local_parent=duplicate(parent,'MI_Default_Opaque_DS_VertexColor');ml.set_material_instance_parent(local_parent,local_master)
    local_pigment=duplicate(pigment,'MI_AuthoredMattePigment_VertexColor');ml.set_material_instance_parent(local_pigment,local_parent)
    ml.update_material_function(local_body)
    errors=list(ml.recompile_material(local_master));need(not errors,'Owned corrected master compilation errors: '+repr(errors))
    ml.update_material_instance(local_parent);ml.update_material_instance(local_pigment)
    unreal.SystemLibrary.execute_console_command(None,'Editor.AsyncAssetCompilationFinishAll')
    after_parameters=parameters(local_pigment);need(after_parameters==before_parameters,'Material factors/overrides changed after parent adaptation')
    need(paths(local_pigment)==paths(source_pigment),'Unexpected material texture dependency change')
    mesh=duplicate(target,'SM_OakBookshelf_VertexColor');mesh.set_material(0,local_pigment)
    need(mesh.get_material(0)==local_pigment and mesh.get_material(1)==source_mesh.get_material(1),'Only the cloned pigment slot may change')
    # Source and cloned mesh GPU arrays must remain exactly equal. Material slot0
    # is the only declared difference; do not waive known legacy source UV issue.
    def xyz(v):return [float(v.x),float(v.y),float(v.z)]
    def buffers(mesh):
        smes=unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem);rows=[]
        for lod in range(smes.get_lod_count(mesh)):
            sections=[]
            for section in range(mesh.get_num_sections(lod)):
                v,ix,n,uv,t=unreal.ProceduralMeshLibrary.get_section_from_static_mesh(mesh,lod,section)
                sections.append({'positions_cm':[xyz(x)for x in v],'indices':list(ix),'normals':[xyz(x)for x in n],
                  'UV0':[[x.x,x.y]for x in uv],'tangents':[{'xyz':xyz(x.get_editor_property('tangent_x')),'flip':bool(x.get_editor_property('flip_tangent_y'))}for x in t],
                  'material_slot':smes.get_lod_material_slot(mesh,lod,section)})
            rows.append({'LOD':lod,'triangles':mesh.get_num_triangles(lod),'vertices':mesh.get_num_vertices(lod),'UV_channels':smes.get_num_uv_channels(mesh,lod),'sections':sections})
        return rows
    original_buffers=buffers(source_mesh);adapted_buffers=buffers(mesh);need(adapted_buffers==original_buffers,'Copied GPU geometry/normals/UV/tangent arrays differ')
    def pigment_buffer(mesh):
        opts=unreal.GeometryScriptCopyMeshFromAssetOptions()
        for n,v in [('apply_build_settings',False),('request_tangents',True),('ignore_remove_degenerates',True),('use_build_scale',False)]:opts.set_editor_property(n,v)
        lod=unreal.GeometryScriptMeshReadLOD();lod.set_editor_property('lod_type',unreal.GeometryScriptLODType.RENDER_DATA);lod.set_editor_property('lod_index',0)
        dm=unreal.DynamicMesh();result=unreal.GeometryScript_AssetUtils.copy_mesh_from_static_mesh_v2(mesh,dm,opts,lod);need(result==(dm,unreal.GeometryScriptOutcomePins.SUCCESS),'RenderData copy failed');keep.append(dm)
        query=unreal.GeometryScript_MeshQueries;count=query.get_num_triangle_i_ds(dm);need(count==1380,'Bookcase triangle count changed');rows=[]
        for i in range(count):
            p=query.get_triangle_positions(dm,i);c=query.get_triangle_vertex_colors(dm,i);m=unreal.GeometryScript_Materials.get_triangle_material_id(dm,i)
            need(p[0] is True and c[-1] is True and m[-1] is True,'Invalid actual GPU triangle/color/material readback')
            rows.append({'positions_cm':[xyz(v)for v in p[1:]],'RGBA':[[v.r,v.g,v.b,v.a]for v in c[1:4]],'material_id':m[0]})
        return rows
    original_colors=pigment_buffer(source_mesh);adapted_colors=pigment_buffer(mesh);need(adapted_colors==original_colors,'Actual RenderData colors/material IDs changed')
    from thumbnail_metadata import read_presets
    metadata,metadata_keep,metadata_api=read_presets(unreal,{'original':source_mesh.get_path_name(),'adapted':mesh.get_path_name()});keep.extend(metadata_keep)
    camera_keys=('default_thumbnail_info_used','native_class_path','orbit_pitch','orbit_yaw','orbit_zoom')
    need({k:metadata[0][k]for k in camera_keys}=={k:metadata[1][k]for k in camera_keys},'Cloned thumbnail camera metadata differs')
    stats=ml.get_statistics(local_pigment);stats_row={n:int(stats.get_editor_property(n))for n in ['num_vertex_shader_instructions','num_pixel_shader_instructions','num_samplers','num_vertex_texture_samples','num_pixel_texture_samples']}
    need(any(stats_row.values()),'Corrected target shader resource not ready')
    for obj in keep:
        if isinstance(obj,(unreal.Material,unreal.MaterialInstanceConstant,unreal.MaterialFunction,unreal.StaticMesh)) and obj.get_path_name().startswith(destination):need(eal.save_loaded_asset(obj,False),'Owned derivative save failed')
    need({p:graph(unreal.load_asset(p))for p in originals}==originals,'Original engine graph changed')
    write('ACTUAL_VERTEX_ADAPTER_FUNCTION_GRAPHS.json',{'original':before_body,'adapted':after_body,'changed_original_node':switch.get_name(),'new_nodes':[vertex.get_name(),multiply.get_name()]})
    write('ACTUAL_VERTEX_ADAPTER_MASTER_GRAPHS.json',{'original':before_master,'adapted':after_master,'changed_function_call':calls[0].get_name()})
    write('ACTUAL_VERTEX_ADAPTER_PARAMETERS.json',{'original':before_parameters,'adapted':after_parameters,'equal':True})
    write('ACTUAL_VERTEX_ADAPTER_RENDER_BUFFERS.json',{'original':original_buffers,'adapted':adapted_buffers,'exact_equal':True})
    write('ACTUAL_VERTEX_ADAPTER_RENDERDATA_COLORS.json',{'original':original_colors,'adapted':adapted_colors,'exact_equal':True})
    write('ACTUAL_VERTEX_ADAPTER_THUMBNAIL_METADATA.json',{'actual':metadata,'api':metadata_api,'matched':True})
    result={'status':'CORRECTED_OWNED_UNTEXTURED_VERTEX_COLOR_BRANCH_RENDER_REVIEW_PENDING','original_mesh':source_mesh.get_path_name(),'adapted_mesh':mesh.get_path_name(),
      'owned_assets':[o.get_path_name()for o in keep if isinstance(o,(unreal.Material,unreal.MaterialInstanceConstant,unreal.MaterialFunction,unreal.StaticMesh)) and o.get_path_name().startswith(destination)],
      'exact_GPU_arrays_preserved':True,'exact_RenderData_colors_preserved':True,'exact_material_factors_preserved':True,'target_shader_statistics':stats_row,'engine_or_original_assets_saved':False,
      'known_legacy_source_UV_difference_waived':False,'full_room_or_final_art_accepted':False}
    return result,keep
