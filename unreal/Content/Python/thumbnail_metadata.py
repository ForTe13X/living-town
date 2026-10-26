"""Read native thumbnail CDO through generic reflected APIs; never mutate it."""
import math
NATIVE_CLASS='/Script/UnrealEd.SceneThumbnailInfo'
DEFAULT_ORBIT=(-11.25,-157.5,0.0)
def need(v,m):
    if not v:raise ValueError(m)
def read_presets(unreal,paths):
    rows=[];keep=[]
    for identity,path in paths.items():
        mesh=unreal.load_asset(path);need(mesh is not None and mesh.get_path_name()==path,'Exact thumbnail mesh missing')
        info=mesh.get_editor_property('thumbnail_info');default_used=info is None
        if default_used:
            native_class=unreal.load_class(None,NATIVE_CLASS)
            need(native_class is not None,'Native thumbnail UClass could not be loaded')
            info=unreal.get_default_object(native_class)
            need(info is not None,'Native thumbnail CDO is missing')
            need(info.get_class().get_path_name()==NATIVE_CLASS,'Loaded thumbnail CDO has wrong native class')
            keep.extend([native_class,info])
        values=tuple(float(info.get_editor_property(k)) for k in ('OrbitPitch','OrbitYaw','OrbitZoom'))
        need(all(math.isfinite(x) for x in values),'Non-finite thumbnail orbit metadata')
        if default_used:need(values==DEFAULT_ORBIT,'Actual native thumbnail CDO differs from installed constructor defaults')
        keep.extend([mesh,info])
        rows.append({'fixture_id':identity,'asset':path,'default_thumbnail_info_used':default_used,
                     'thumbnail_info_class':info.get_class().get_name(),'native_class_path':info.get_class().get_path_name(),
                     'thumbnail_info_object_path':info.get_path_name(),'orbit_pitch':values[0],'orbit_yaw':values[1],
                     'orbit_zoom':values[2],'preset_mutated':False,
                     'default_resolution':'load_class native UClass then get_default_object; no named Python class assumption' if default_used else 'Actual saved mesh thumbnail_info retained'})
    api={'load_class':str(unreal.load_class.__doc__ or ''),'get_default_object':str(unreal.get_default_object.__doc__ or ''),
         'native_class_path':NATIVE_CLASS,'installed_native_constructor_defaults':list(DEFAULT_ORBIT),
         'defaults_read_from_actual_CDO_and_checked':True,'objects_constructed_or_properties_assigned':False}
    return rows,keep,api
