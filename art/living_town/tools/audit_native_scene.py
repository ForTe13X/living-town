"""Read-only native Blender audit. Execute in Blender after loading the final town file."""
import bpy,json,hashlib,math
from pathlib import Path
from datetime import datetime,timezone
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
s=bpy.data.scenes['Living_Town_Summer']
bpy.context.window.scene=s
bpy.context.view_layer.update()
checks=[]
def check(name,passed,detail):checks.append({'id':name,'status':'PASS' if passed else 'FAIL','detail':detail})
manifest=json.loads((ROOT/'town_manifest.json').read_text(encoding='utf-8'))
file_images=[i for i in bpy.data.images if i.source=='FILE']
check('packed_image_dependencies',len(file_images)==manifest.get('packed_image_count',27) and all(i.packed_file for i in file_images),{'count':len(file_images),'expected':manifest.get('packed_image_count',27),'unpacked':[i.name for i in file_images if not i.packed_file]})
fonts=[f for f in bpy.data.fonts if f.filepath and f.name!='Bfont Regular']
check('packed_external_fonts',all(f.packed_file for f in fonts),[{'name':f.name,'packed':bool(f.packed_file)} for f in fonts])
check('no_linked_libraries',not bpy.data.libraries,[l.filepath for l in bpy.data.libraries])
check('metric_scene',s.unit_settings.system=='METRIC' and s.unit_settings.scale_length==1,{'system':s.unit_settings.system,'scale':s.unit_settings.scale_length})
cam=bpy.data.objects['06_Production_Orthogonal']
m=cam.matrix_world.to_3x3()
check('true_xy_orthographic_camera',cam.data.type=='ORTHO' and (m@Vector((1,0,0))-Vector((1,0,0))).length<1e-6 and (m@Vector((0,1,0))-Vector((0,1,0))).length<1e-6,{'type':cam.data.type,'matrix':[list(r) for r in cam.matrix_world]})
groups=[c for b in manifest['buildings'] for c in [b['collection'],b['roof_collection'],b['front_collection'],b['upper_cover_collection']]]
check('native_building_ownership',len(manifest['buildings'])==49 and len(set(groups))==len(groups) and all(c in bpy.data.collections for c in groups),{'buildings':len(manifest['buildings']),'collections':len(groups)})
interiors=[b['id']+'_Interior' for b in manifest['buildings']]
check('interior_collections',all(c in bpy.data.collections for c in interiors),{'count':len(interiors),'missing':[c for c in interiors if c not in bpy.data.collections]})
before={c:(bpy.data.collections[c].hide_render,bpy.data.collections[c].hide_viewport) for c in groups}
target=['Main_cafe_'+suffix for suffix in ('Roof','FrontWall','UpperFloorCover')]
try:
    for c in target:bpy.data.collections[c].hide_render=True;bpy.data.collections[c].hide_viewport=True
    others=[c for c in groups if c not in target]
    check('local_cutaway_only',all(before[c]==(bpy.data.collections[c].hide_render,bpy.data.collections[c].hide_viewport) for c in others),{'target':target,'other_collections_checked':len(others)})
finally:
    for c,flags in before.items():bpy.data.collections[c].hide_render=flags[0];bpy.data.collections[c].hide_viewport=flags[1]
check('cutaway_restored',all(before[c]==(bpy.data.collections[c].hide_render,bpy.data.collections[c].hide_viewport) for c in groups),True)
b=next(b for b in manifest['buildings'] if b['id']=='Main_cafe')
x,y,z=b['center_m'];w,d=b['footprint_m'];a=math.radians(b['yaw_degrees'])
def wp(lx,ly,lz):return Vector((x+lx*math.cos(a)-ly*math.sin(a),y+lx*math.sin(a)+ly*math.cos(a),z+lz))
floor=bpy.data.objects['Main_cafe_Floor2_Oak']
def ray(lx,ly):
    origin=wp(lx,ly,2.65);ok,loc,norm,index=floor.ray_cast(floor.matrix_world.inverted()@origin,Vector((0,0,1)),distance=.5)
    return {'hit':ok,'z':float(loc.z) if ok else None}
shaft=ray(w*.4,0);control=ray(0,0)
check('real_stair_floor_opening',not shaft['hit'] and control['hit'],{'shaft':shaft,'floor_control':control})
party_windows=[o.name for o in s.objects if o.name.startswith('Main_cafe_SideWindows')]
check('cafe_has_no_party_wall_windows',not party_windows,party_windows)
topo=json.loads((ROOT/'terrain_plan.json').read_text(encoding='utf-8'))
pads={p['id']:p for p in topo['building_pads']}
errors=[]
for b in manifest['buildings']:
    name=b['id']+('_OpenTimberArcade_Granite' if b['kind']=='halles' else '_Shell_Granite')
    ob=bpy.data.objects.get(name)
    lowest=min((ob.matrix_world@v.co).z for v in ob.data.vertices) if ob else None
    expected=pads[b['id']]['foundation_toe_recommendation_z_m']
    if lowest is None or abs(lowest-expected)>1e-5:errors.append({'id':b['id'],'actual_toe':lowest,'expected_toe':expected})
check('native_foundations_reach_design_toes',not errors,{'foundations':49,'errors':errors})
check('stepped_thresholds_modelled',s.get('stepped_approach_count')==len(topo['validation']['entry_step_routes']) and 'Graded_Threshold_Approach_Steps_Granite' in bpy.data.objects,{'native':s.get('stepped_approach_count'),'required':len(topo['validation']['entry_step_routes'])})
roof=bpy.data.objects['Main_cafe_RoofParts_Slate']
roof_pitch=max(v.co.z for v in roof.data.vertices)-min(v.co.z for v in roof.data.vertices)
check('gable_roof_rise_preserved',roof_pitch>1.5,{'native_cafe_roof_rise_m':roof_pitch})
sea=bpy.data.objects['Atlantic_Terrain_Sea'];water=max(v.co.z for v in sea.data.vertices)
check('native_water_datum',abs(water-topo['levels']['water_z_m'])<1e-6,{'native_z':water,'plan_z':topo['levels']['water_z_m']})
grass=bpy.data.objects['Atlantic_Terrain_Grass'];paving=bpy.data.objects['Connected_Streets_and_Pavements_Paving']
grasshit=grass.ray_cast(Vector((44,54,20)),Vector((0,0,-1)),distance=50)[0]
deckhit,deckloc,_,_=paving.ray_cast(Vector((60,52,20)),Vector((0,0,-1)),distance=50)
check('quay_has_one_ground_surface',not grasshit and deckhit and abs(deckloc.z-topo['levels']['quay_deck_z_m'])<1e-5,{'overlapping_grass':grasshit,'native_deck_z':float(deckloc.z) if deckhit else None})
review=bpy.data.collections['04_Topographic_Review']
expected_review_objects=len(topo['contour_segments'])+6
check('optional_native_contour_layer',review.hide_render and review.hide_viewport and len(review.objects)==expected_review_objects,{'objects':len(review.objects),'expected':expected_review_objects,'hidden_for_beauty':review.hide_render})

# Inspect the saved pond/terrain/path meshes; the height-field plan alone is
# insufficient evidence that the water and banks were actually modelled.
import importlib.util
terrain_spec=importlib.util.spec_from_file_location('audit_living_town_terrain',ROOT/'tools/terrain_profile.py')
terrain=importlib.util.module_from_spec(terrain_spec);terrain_spec.loader.exec_module(terrain)
landscape=json.loads((ROOT/'landscape_plan.json').read_text(encoding='utf-8'))
landscape_bindings={'landscape_plan_sha256':hashlib.sha256((ROOT/'landscape_plan.json').read_bytes()).hexdigest(),
    'landscape_details_sha256':hashlib.sha256((ROOT/'tools/landscape_details.py').read_bytes()).hexdigest(),
    'terrain_profile_sha256':hashlib.sha256((ROOT/'tools/terrain_profile.py').read_bytes()).hexdigest()}
check('reference_landscape_bound_to_saved_source',all(s.get(k)==v and manifest.get(k)==v for k,v in landscape_bindings.items()),landscape_bindings)
pond=topo['park_pond'];cx,cy=pond['center'];water=bpy.data.objects.get('Atlantic_Terrain_PondWater')
bed=bpy.data.objects.get('Atlantic_Terrain_Dirt');ground_objects=[grass,bed]
water_levels=[(water.matrix_world@v.co).z for v in water.data.vertices] if water else []
def ground_ray(x,y):
    hits=[]
    for ob in ground_objects:
        if not ob:continue
        hit,loc,normal,index=ob.ray_cast(Vector((x,y,10)),Vector((0,0,-1)),distance=20)
        if hit:hits.append(float(loc.z))
    return max(hits) if hits else None
native_bed=ground_ray(cx,cy)
check('native_pond_has_level_water_and_recessed_basin',bool(water_levels) and max(water_levels)-min(water_levels)<1e-6
    and abs(water_levels[0]-pond['water_z_m'])<1e-6 and native_bed is not None and abs(native_bed-pond['bed_z_m'])<.008,
    {'water_vertices':len(water_levels),'water_z_m':water_levels[0] if water_levels else None,'native_bed_z_m':native_bed,'planned_depth_m':pond['maximum_water_depth_m']})
bank_errors=[];max_mesh_slope=0.;bank_faces=0
for ob in ground_objects:
    if not ob:continue
    for poly in ob.data.polygons:
        p=poly.center
        if terrain.pond_radius(p.x,p.y,True)>1:continue
        bank_faces+=1
        if abs(poly.normal.z)>1e-6:max_mesh_slope=max(max_mesh_slope,math.hypot(poly.normal.x,poly.normal.y)/abs(poly.normal.z))
for i in range(48):
    angle=i*math.tau/48;rx,ry=pond['water_radii_m'];x=cx+rx*math.cos(angle);y=cy+ry*math.sin(angle)
    hit=ground_ray(x,y)
    if hit is None or abs(hit-pond['water_z_m'])>.02:bank_errors.append({'shore_xy':[x,y],'native_ground_z':hit})
check('native_pond_banks_meet_water_and_are_graded',bank_faces>100 and not bank_errors and max_mesh_slope<=1/3+.012,
    {'bank_faces':bank_faces,'shore_rays':48,'maximum_native_face_grade_percent':max_mesh_slope*100,'height_field_grade_percent':pond['maximum_sampled_bank_grade_percent'],'errors':bank_errors})
paths=[ob for ob in s.objects if ob.type=='MESH' and ob.name.startswith('Reference_Garden_Paths_')]
path_errors=[];path_vertices=0
for ob in paths:
    for vertex in ob.data.vertices:
        p=ob.matrix_world@vertex.co;path_vertices+=1
        if abs(p.z-terrain.design_height(p.x,p.y)-.026)>.0001:path_errors.append([p.x,p.y,p.z])
environment=json.loads(s.get('environment_refinement','{}')).get('reference_landscape',{})
counts=environment.get('counts',{})
planned_trees=len(landscape.get('street_trees',[]))+sum(isinstance(t,dict) for t in landscape.get('park',{}).get('willows',[]))
layer_vertices={role:sum(len(ob.data.vertices) for ob in s.objects if ob.type=='MESH' and ob.get('landscape_role')==role)
    for role in ('Street_Trees','Pond_Planting','Pocket_Gardens','Coastal_Dune_Grass')}
check('native_reference_landscape_paths_and_planting',counts.get('paths')==len(landscape['paths'])
    and counts.get('street_trees',0)+counts.get('willows',0)==planned_trees and all(n>100 for n in layer_vertices.values())
    and counts.get('garden_beds',0)>=3 and counts.get('benches',0)>=2 and counts.get('reed_clumps',0)>0 and counts.get('beach_grass_patches',0)>0
    and path_vertices>100 and not path_errors,{'counts':counts,'planned_trees':planned_trees,'native_layer_mesh_vertices':layer_vertices,'path_vertices_sampled':path_vertices,'path_errors':path_errors[:20],
    'added_triangles':environment.get('added_triangles'),'rejections':environment.get('rejected')})

# The interior expansion is audited through saved native meshes, rather than
# accepting a room/furniture count or a successful planning script as proof.
interior_plan=json.loads((ROOT/'interior_plan.json').read_text(encoding='utf-8'))
planning_privacy=json.loads((ROOT/'evidence/interior_planning_audit.json').read_text(encoding='utf-8'))
privacy_edges={r['room']:r['edges'] for r in planning_privacy.get('privacy_enclosure_checks',[])}
privacy_mesh_errors=[];privacy_mesh_rooms=set();privacy_mesh_rays=0
interior_records=manifest.get('interiors',[])
records={r['id']:r for r in interior_records};building_records={b['id']:b for b in manifest['buildings']}
bindings={'interior_plan_sha256':hashlib.sha256((ROOT/'interior_plan.json').read_bytes()).hexdigest(),
    'interior_module_sha256':hashlib.sha256((ROOT/'tools/interior_design.py').read_bytes()).hexdigest()}
check('native_interiors_bound_to_current_sources',all(s.get(k)==v and manifest.get(k)==v for k,v in bindings.items()),
    {'expected':bindings,'scene':{k:s.get(k) for k in bindings},'manifest':{k:manifest.get(k) for k in bindings}})

def local_world(building,p):
    ox,oy,oz=building['center_m'];a=math.radians(building['yaw_degrees']);xx,yy,zz=p
    return Vector((ox+xx*math.cos(a)-yy*math.sin(a),oy+xx*math.sin(a)+yy*math.cos(a),oz+zz))

def native_ray(ob,building,origin,direction,distance):
    if ob is None:return None
    a=math.radians(building['yaw_degrees']);dx,dy,dz=direction
    ray_direction=Vector((dx*math.cos(a)-dy*math.sin(a),dx*math.sin(a)+dy*math.cos(a),dz))
    inv=ob.matrix_world.inverted()
    hit,loc,normal,face=ob.ray_cast(inv@local_world(building,origin),inv.to_3x3()@ray_direction,distance=distance)
    return float((ob.matrix_world@loc).z) if hit else None

level_errors=[];cover_errors=[];room_errors=[];asset_errors=[];slab_errors=[];stair_errors=[];opening_errors=[];fixture_errors=[]
integrated_kitchens=dining_assemblies=mill_assemblies=0
level_count=room_count=asset_count=flight_count=aperture_count=slab_count=0
for planned in interior_plan['buildings']:
    ident=planned['id'];b=building_records.get(ident);record=records.get(ident)
    if not b or not record:
        level_errors.append({'id':ident,'reason':'missing native building/interior record'});continue
    levels=record.get('levels',record.get('floors',[]))
    if record.get('floor_count')!=planned['floors'] or len(levels)!=planned['floors']:
        level_errors.append({'id':ident,'reason':'declared/native level mismatch'})
    for f in planned['levels']:
        n=f['level'];ff=f['finished_floor_local_z_m'];level_count+=1
        col=bpy.data.collections.get(ident+f'_Interior_L{n:02d}')
        parent=bpy.data.collections.get(b['upper_cover_collection'] if n else ident+'_Interior')
        if not col or col.get('floor_index')!=n or not math.isclose(col.get('finished_floor_local_z_m',-999),ff,abs_tol=1e-6):
            level_errors.append({'id':ident,'level':n,'reason':'missing level or wrong elevation'})
        if not parent or not col or col.name not in parent.children:cover_errors.append({'id':ident,'level':n,'reason':'level outside required cover owner'})
        if n:
            slab_count+=1;slab=bpy.data.objects.get(ident+f'_Floor{n+1}_Oak');a0,y0,c0,e0=planned['core']['bounds']
            shaft=native_ray(slab,b,((a0+c0)/2,(y0+e0)/2,ff-.5),(0,0,1),1)
            bounds=f.get('partial_slab_bounds',planned['clear_bounds_m'])
            control=native_ray(slab,b,(bounds[0]+.35,bounds[1]+.35,ff-.5),(0,0,1),1)
            if shaft is not None or control is None or abs(control-(b['center_m'][2]+ff-.12))>.0002:
                slab_errors.append({'id':ident,'level':n,'shaft_hit_z':shaft,'control_hit_z':control})
        stairs=f.get('stair_to_next_level')
        if stairs:
            flight_count+=1;ob=bpy.data.objects.get(ident+f'_L{n:02d}_Stairs_Oak');sample_errors=[]
            for j in range(stairs['risers']):
                y=stairs['first_tread_y']+j*stairs['tread_m'];expected=b['center_m'][2]+ff+(j+1)*stairs['riser_m']
                hit=native_ray(ob,b,(stairs['center_x'],y,ff+3.35),(0,0,-1),3.5)
                if hit is None or abs(hit-expected)>.0002:sample_errors.append({'tread':j,'actual_z':hit,'expected_z':expected})
            last_end=stairs['first_tread_y']+13*stairs['tread_m']+stairs['tread_m']/2
            bridge_y=(last_end+stairs['bounds'][3])*.5
            bridge=native_ray(ob,b,(stairs['center_x'],bridge_y,ff+3.35),(0,0,-1),.7)
            if bridge is None or abs(bridge-(b['center_m'][2]+ff+2.85))>.0002:sample_errors.append({'reason':'upper landing bridge missing','actual_z':bridge})
            if sample_errors:stair_errors.append({'id':ident,'level':n,'errors':sample_errors})
        partitions=bpy.data.objects.get(ident+f'_L{n:02d}_Partitions_Plaster')
        for wall in f['partitions']:
            co=wall['coordinate_m'];axis=wall['axis']
            for opening in wall['openings']:
                aperture_count+=1;c=opening['center_m'];z=ff+opening['bottom_m']+opening['height_m']/2
                origin=(co-.4,c,z) if axis=='x' else(c,co-.4,z);direction=(1,0,0) if axis=='x' else(0,1,0)
                hit=native_ray(partitions,b,origin,direction,.8)
                solidz=ff+wall['height_m']-.06
                control=(origin[0],origin[1],solidz);solid=native_ray(partitions,b,control,direction,.8)
                if not partitions or hit is not None or solid is None:
                    opening_errors.append({'id':ident,'level':n,'axis':axis,'coordinate':co,'kind':opening['kind'],'center':c,'aperture_hit':hit,'solid_control':solid})
        for r in f['rooms']:
            room_count+=1;rc=bpy.data.collections.get(r['id'])
            if r['id'] in privacy_edges:
                privacy_mesh_rooms.add(r['id'])
                for edge in privacy_edges[r['id']]:
                    if edge['boundary']=='exterior shell':continue
                    lo,hi=edge['span_m'];co=edge['coordinate_m'];axis=edge['axis']
                    stations=max(1,math.ceil((hi-lo)/.25))
                    for i in range(stations):
                        along=lo+(hi-lo)*(i+.5)/stations
                        if any(abs(along-o['center_m'])<o['width_m']/2+.025 for o in edge.get('door_apertures',[])):continue
                        origin=(co-.20,along,ff+1.20) if axis=='x' else(along,co-.20,ff+1.20)
                        direction=(1,0,0) if axis=='x' else(0,1,0)
                        privacy_mesh_rays+=1
                        if native_ray(partitions,b,origin,direction,.40) is None:
                            privacy_mesh_errors.append({'room':r['id'],'axis':axis,'coordinate_m':co,'station_m':along})
            if not rc or not col or rc.name not in col.children or rc.get('purpose')!=r['purpose']:
                room_errors.append({'room':r['id'],'reason':'missing room, purpose or level ownership'})
            for asset in r['assets']:
                asset_count+=1
                objects=[ob for ob in (rc.all_objects if rc else []) if ob.get('interior_asset_id')==asset['id']]
                if not objects or any(ob.get('interior_room_id')!=r['id'] or ob.get('interior_building_id')!=ident or ob.get('asset_role')!=asset['kind'] or not ob.get('reusable_asset') for ob in objects):
                    asset_errors.append({'asset':asset['id'],'reason':'missing native asset or semantic ownership'});continue
                angle=math.radians(b['yaw_degrees']);ox,oy,oz=b['center_m'];x0,y0,x1,y1=asset['footprint_m']
                outside=False
                for ob in objects:
                    for vertex in ob.data.vertices:
                        p=ob.matrix_world@vertex.co;xx=(p.x-ox)*math.cos(angle)+(p.y-oy)*math.sin(angle);yy=-(p.x-ox)*math.sin(angle)+(p.y-oy)*math.cos(angle)
                        if xx<x0-.065 or xx>x1+.065 or yy<y0-.065 or yy>y1+.065:outside=True;break
                    if outside:break
                if outside:asset_errors.append({'asset':asset['id'],'reason':'native geometry exceeds planned collision footprint plus .065m hardware allowance'})
                def asset_ray(material,point,direction,distance):
                    rotation=math.radians(asset.get('rotation_degrees',0));xx,yy,zz=point;dx,dy,dz=direction
                    cx,cy=asset['center_m']
                    point=(cx+xx*math.cos(rotation)-yy*math.sin(rotation),cy+xx*math.sin(rotation)+yy*math.cos(rotation),ff+zz)
                    direction=(dx*math.cos(rotation)-dy*math.sin(rotation),dx*math.sin(rotation)+dy*math.cos(rotation),dz)
                    ob=next((o for o in objects if any(slot.material and slot.material.name.split('.')[0]=='LT_'+material for slot in o.material_slots)),None)
                    return native_ray(ob,b,point,direction,distance)
                if asset['kind']=='kitchen_run':
                    integrated_kitchens+=1;ww,dd,_=asset['dimensions_m'];sx=-ww*.30
                    stone_hole=asset_ray('Granite',(sx,.025,1.20),(0,0,-1),.7)
                    stone_control=asset_ray('Granite',(-ww*.49,0,1.20),(0,0,-1),.7)
                    basin=asset_ray('White',(sx,.025,.93),(0,0,-1),.3)
                    fridge=asset_ray('White',(ww*.31,-dd/2-.20,.455),(0,1,0),.5)
                    tap=asset_ray('Zinc',(sx,.055,1.22),(0,0,-1),.20)
                    hob=asset_ray('Iron',(0,-dd*.18,1.02),(0,0,-1),.15)
                    expected_base=b['center_m'][2]+ff
                    metadata=all(set(json.loads(o.get('integrated_fixtures','[]')))=={'recessed_sink','tap','hob','undercounter_fridge'} for o in objects)
                    if not metadata or stone_hole is not None or stone_control is None or basin is None or abs(basin-(expected_base+.779))>.001 or fridge is None or tap is None or hob is None:
                        fixture_errors.append({'asset':asset['id'],'reason':'actual sink cutout, recessed basin, tap, hob or fridge face missing','stone_hole_hit':stone_hole,'stone_control_hit':stone_control,'basin_z':basin,'fridge_z':fridge,'tap_z':tap,'hob_z':hob,'metadata':metadata})
                if asset['kind']=='dining_table':
                    dining_assemblies+=1;seats=[asset_ray('Oak',(0,yy,.65),(0,0,-1),.30) for yy in(-.36,.36)]
                    expected_seat=b['center_m'][2]+ff+.48
                    if any(hit is None or abs(hit-expected_seat)>.001 for hit in seats) or not all(o.get('integrated_seating')==2 for o in objects):
                        fixture_errors.append({'asset':asset['id'],'reason':'actual two contained dining seats missing','seat_z':seats})
                if asset['kind']=='mill_mechanism':
                    mill_assemblies+=1;ww=asset['dimensions_m'][0]
                    disk=[asset_ray('Oak',(math.cos(j*math.tau/8)*ww*.22,math.sin(j*math.tau/8)*ww*.22,1.0),(0,0,-1),.50) for j in range(8)]
                    expected_disk=b['center_m'][2]+ff+.72
                    if any(hit is None or abs(hit-expected_disk)>.001 for hit in disk):
                        fixture_errors.append({'asset':asset['id'],'reason':'continuous wooden gear disk joining shaft and teeth missing','disk_surface_z':disk})

check('all89_native_floor_levels_and_cover_ownership',level_count==89 and not level_errors and not cover_errors,
    {'levels':level_count,'level_errors':level_errors,'cover_errors':cover_errors})
check('all40_upper_slabs_have_real_shaft_voids',slab_count==40 and not slab_errors,{'slabs':slab_count,'errors':slab_errors})
check('all40_stair_flights_have14_equal_rises_and_bridge',flight_count==40 and not stair_errors,
    {'flights':flight_count,'tread_rays':flight_count*14,'errors':stair_errors})
check('native_partition_apertures_are_geometric',aperture_count>200 and not opening_errors,
    {'apertures':aperture_count,'method':'Ray through every door/service opening plus solid lintel control on the actual partition mesh.','errors':opening_errors})
check('native104_private_room_internal_boundaries_are_solid',len(privacy_mesh_rooms)==104 and privacy_mesh_rays>500 and not privacy_mesh_errors,
    {'private_rooms':len(privacy_mesh_rooms),'solid_partition_rays':privacy_mesh_rays,'errors':privacy_mesh_errors,
     'method':'Actual saved partition meshes sampled at <=.25m along private internal edges, at floor+1.20m, excluding recorded door apertures. Exterior shell checks remain separate.'})
check('native_room_and_reusable_furniture_ownership',room_count==interior_plan['room_count'] and asset_count==interior_plan['furnishing_count'] and not room_errors and not asset_errors,
    {'room_zones':room_count,'furniture_assemblies':asset_count,'room_errors':room_errors,'asset_errors':asset_errors})
planning=json.loads((ROOT/'evidence/interior_planning_audit.json').read_text(encoding='utf-8'))
essential=planning.get('essential_fixture_coverage',[])
essential_ok=planning.get('status')=='PASS' and len(essential)==223 and all(q['pass'] for q in essential) and all(planning.get(k)==v for k,v in bindings.items())
check('native_essential_program_fixtures_and_integrated_kitchens',essential_ok and integrated_kitchens==43 and dining_assemblies==40 and mill_assemblies==2 and not fixture_errors,
    {'activity_rooms':len(essential),'purpose_requirements':planning.get('essential_fixture_requirements_tested'),
    'integrated_kitchens':integrated_kitchens,'two_seat_dining_assemblies':dining_assemblies,'connected_mill_gear_disks':mill_assemblies,'errors':fixture_errors,
    'method':'Current-hash purpose specifications plus native asset-role correspondence, counter-hole/stone control, recessed basin, tap, fridge-front, both dining-seat and eight radial gear-disk rays per mill.'})

# Fresh evaluated triangle intersections are required on this loaded scene.
# A cached diagnosis or construction-profile metadata cannot establish contact.
contact_path=ROOT/'tools/diagnose_roof_contact.py'
try:
    contact_spec=importlib.util.spec_from_file_location('audit_saved_roof_contact',contact_path)
    contact_module=importlib.util.module_from_spec(contact_spec);contact_spec.loader.exec_module(contact_module)
    contact=contact_module.audit_roof_contact(s)
    contact['helper_sha256']=hashlib.sha256(contact_path.read_bytes()).hexdigest()
except Exception as error:
    contact={'status':'FAIL','chimney_count':0,'sample_count':0,
        'failures':[{'reason':'actual evaluated chimney contact audit could not run','error':str(error)}]}
check('all57_chimney_bases_intersect_actual_roof_surfaces',contact.get('status')=='PASS'
    and contact.get('chimney_count')==57 and contact.get('sample_count')==57*9
    and not contact.get('failures'),contact)

native={'objects':len(s.objects),'mesh_vertices':sum(len(o.data.vertices) for o in s.objects if o.type=='MESH'),'cameras':[o.name for o in s.objects if o.type=='CAMERA'],'vegetable_gardens':s.get('vegetable_garden_count',0)}
report={'schema':'living_town.native_audit.v3','generated_utc':datetime.now(timezone.utc).isoformat(),'blender_version':bpy.app.version_string,'source_blend_sha256':hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest(),'masterplan_sha256':s.get('masterplan_sha256'),'terrain_plan_sha256':s.get('terrain_plan_sha256'),**{k:s.get(k) for k in {**bindings,**landscape_bindings}},'native':native,'checks':checks,'status':'FAIL' if any(c['status']=='FAIL' for c in checks) else 'PASS','scope':'Native dependencies, ownership, cutaways, XY camera, pond water/basin/shore/banks, reference paths/planting, all upper floor shafts/stair treads/partition apertures, purpose fixtures and evaluated nine-point contact for all 57 chimney bases. Engine import and runtime interaction require separate evidence.'}
(ROOT/'evidence/native_scene_audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
result={'status':report['status'],'checks':len(checks),'failures':[c for c in checks if c['status']=='FAIL'],'native':native}
if globals().get('__name__')=='__main__':print(json.dumps(result),flush=True)
