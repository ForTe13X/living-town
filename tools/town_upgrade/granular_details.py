"""Source-bound mill sails and small planter flowers; no engine on import.

The owning Blender build calls apply(api, output, buildings, source_furniture).
Every deletion is an exact connected-component match to a parsed source
recipe. Pots, leaves, unrelated wood and all protected furniture stay intact.
"""
from __future__ import annotations

import ast
from collections import Counter, defaultdict
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import random

ROOT=Path(__file__).resolve().parents[2]
SCHEMA='living_town.source_bound_granular_details.v1'
PALETTE=('BloomBlue','BloomPink','BloomCream')
PUBLIC_POTS=('Garden_Vegetation','Sheltered_Gardens_and_Canopies',
             'Civic_Square_and_Summer_Life','Everyday_StreetFurniture','Study_Hydrangeas')
MAX_EXPANDED_TRIANGLES=500_000
_HELPER=None


def _helper():
    global _HELPER
    if _HELPER is None:
        path=Path(__file__).with_name('scale_figures.py')
        spec=importlib.util.spec_from_file_location('granular_source_component_helper',path)
        _HELPER=importlib.util.module_from_spec(spec);spec.loader.exec_module(_HELPER)
    return _HELPER


def _sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def _write(path,value):Path(path).write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
def _ast_sha(node):return hashlib.sha256(ast.dump(node,include_attributes=False).encode()).hexdigest()


def _recipes(baseline):
    core=Path(baseline)/'tools/build_living_town.py';reserve=Path(baseline)/'tools/reserve_amenities.py'
    ct=ast.parse(core.read_text(encoding='utf-8-sig'));rt=ast.parse(reserve.read_text(encoding='utf-8-sig'))
    functions={n.name:n for n in ct.body if isinstance(n,ast.FunctionDef)}
    windmill=[n for n in ast.walk(functions['building']) if isinstance(n,ast.If)
              and isinstance(n.test,ast.Compare) and ast.dump(n.test)==ast.dump(ast.parse("kind=='windmill'",mode='eval').body)]
    if len(windmill)!=1:raise ValueError('Expected one explicit source windmill branch')
    planters=[n for n in ast.walk(rt) if isinstance(n,ast.For) and isinstance(n.target,ast.Name) and n.target.id=='side'
              and any(isinstance(x,ast.Constant) and x.value=='BloomCream' for x in ast.walk(n))
              and any(isinstance(x,ast.Attribute) and x.attr=='ellipsoid' for x in ast.walk(n))]
    if len(planters)!=1:raise ValueError('Expected one exact reserve entry-planter loop')
    ns={'math':math}
    exec(compile(ast.fix_missing_locations(ast.Module(body=[functions['flower_head'],functions['pot']],type_ignores=[])),str(core),'exec'),ns)
    return {'pot':ns['pot'],'mill':windmill[0].body,'reserve_planters':[planters[0]],
            'bindings':{'core_builder':{'path':str(core),'sha256':_sha(core),'flower_head_ast_sha256':_ast_sha(functions['flower_head']),
                        'pot_ast_sha256':_ast_sha(functions['pot']),'mill_branch_ast_sha256':_ast_sha(windmill[0])},
                        'reserve_amenities':{'path':str(reserve),'sha256':_sha(reserve),'planter_loop_ast_sha256':_ast_sha(planters[0])},
                        'component_helper_sha256':_sha(Path(__file__).with_name('scale_figures.py'))}}


def _execute(statements,namespace):
    exec(compile(ast.fix_missing_locations(ast.Module(body=statements,type_ignores=[])),'<bound granular source recipe>','exec'),namespace)


class Geometry:
    """Pure recorder, using the same canonical metric primitive equations."""
    def __init__(self):self.parts=[]
    def poly(self,vertices,faces,material,uvs=None):
        self.parts.append({'vertices':[tuple(p) for p in vertices],'faces':[tuple(f) for f in faces],'material':material})
    def _primitive(self,name,*args,**kwargs):
        recorder=_helper()._Recorder();getattr(recorder,name)(*args,**kwargs);self.parts.extend(recorder.parts)
    def rod(self,*args,**kwargs):self._primitive('rod',*args,**kwargs)
    def box(self,*args,**kwargs):self._primitive('box',*args,**kwargs)
    def ellipsoid(self,*args,**kwargs):self._primitive('ellipsoid',*args,**kwargs)


def _world(row,p):
    a=math.radians(row['yaw_degrees']);co,si=math.cos(a),math.sin(a)
    return (row['center_m'][0]+p[0]*co-p[1]*si,row['center_m'][1]+p[0]*si+p[1]*co,row['pad_level_m']+p[2])


def _local(row,p):
    a=math.radians(row['yaw_degrees']);co,si=math.cos(a),math.sin(a)
    x,y=p[0]-row['center_m'][0],p[1]-row['center_m'][1]
    return (x*co+y*si,-x*si+y*co,p[2]-row['pad_level_m'])


def _bounds(points):return [[min(p[k] for p in points) for k in range(3)],[max(p[k] for p in points) for k in range(3)]]
def _triangles(parts):return sum(len(face)-2 for part in parts for face in part['faces'])


class SourceScope:
    def __init__(self,objects,protected):
        self.objects={ob.name:ob for ob in objects if ob.type=='MESH'}
        self.components={name:_helper()._components(ob) for name,ob in self.objects.items()}
        self.protected=set(protected);self.selected=defaultdict(set);self.receipts=[]
    def select(self,part,transform=lambda p:p,label=''):
        expected={'vertices':[transform(p) for p in part['vertices']],'faces':part['faces']}
        candidates=[]
        for name,ob in self.objects.items():
            for index,c in enumerate(self.components[name]):
                if _helper()._matches(c,expected):candidates.append((name,index,c))
        if len(candidates)!=1:raise ValueError(f'Exact source component {label} has {len(candidates)} matches')
        name,index,c=candidates[0]
        if name in self.protected:raise ValueError('Granular scope would alter protected source furniture: '+name)
        if index in self.selected[name]:raise ValueError('Source component selected twice: '+label)
        self.selected[name].add(index)
        self.receipts.append({'label':label,'source_object':name,'source_component':index,'vertices':len(c['indices']),
            'faces':len(c['faces']),'world_bounds_m':c['bounds'],'geometry_uv_sha256':_helper()._component_hash(self.objects[name],c)})
        return name,index,c
    def delete(self,bpy):
        import bmesh
        records=[]
        for name,selected in self.selected.items():
            ob=self.objects[name];components=self.components[name]
            before=Counter(_helper()._component_hash(ob,c) for i,c in enumerate(components) if i not in selected)
            transform=[list(r) for r in ob.matrix_world];indices={i for n in selected for i in components[n]['indices']}
            if ob.data.users>1:ob.data=ob.data.copy()
            bm=bmesh.new();bm.from_mesh(ob.data);bm.verts.ensure_lookup_table()
            bmesh.ops.delete(bm,geom=[bm.verts[i] for i in sorted(indices)],context='VERTS');bm.to_mesh(ob.data);bm.free();ob.data.update()
            after=Counter(_helper()._component_hash(ob,c) for c in _helper()._components(ob)) if ob.data.vertices else Counter()
            if before!=after or transform!=[list(r) for r in ob.matrix_world]:raise RuntimeError('Unrelated source geometry/UV changed: '+name)
            records.append({'source_object':name,'removed_components':len(selected),'removed_vertices':len(indices),
                'preserved_component_count':sum(before.values()),'preserved_component_geometry_uv':'PASS','transform_unchanged':True})
            if not ob.data.vertices:bpy.data.objects.remove(ob,do_unlink=True)
        return records


def _mill_geometry(batch,row):
    """Four balanced cloth-covered timber frames inside the old swept envelope."""
    w,d=row['footprint_m'];h=row['floor_count']*2.85;y=-d/2-.58
    for index in range(4):
        a=index*math.pi/2;ux,uz=math.cos(a),math.sin(a);vx,vz=-uz,ux
        def p(r,v=0,depth=0):return (ux*r+vx*v,y+depth,h+uz*r+vz*v)
        batch.rod(p(.12),p(2.70),.052,'Oak',n=8)
        batch.rod(p(.78,.81),p(2.64,.81),.030,'Oak',n=6)
        for j in range(9):
            r=.78+j*(2.64-.78)/8
            batch.rod(p(r,-.035),p(r,.85),.019,'Oak',n=6)
        for v in (.27,.54):batch.rod(p(.78,v),p(2.64,v),.014,'Oak',n=5)
        batch.rod(p(.80,.02,.012),p(2.60,.79,.012),.012,'Oak',n=5)
        batch.rod(p(.80,.79,.012),p(2.60,.02,.012),.012,'Oak',n=5)
        for j in range(4):
            r0=.86+j*.435;r1=min(2.59,r0+.405);vertices=[]
            for r in(r0,(r0+r1)/2,r1):
                for v in(.065,.765):
                    bow=-.030*math.sin((r-r0)/(r1-r0)*math.pi)
                    vertices.append(p(r,v,-.045+bow))
            # Both surfaces and closed hems are real portable cloth geometry.
            vertices+=[(x,yy+.003,z) for x,yy,z in vertices]
            faces=[(0,2,3,1),(2,4,5,3),(7,9,8,6),(9,11,10,8),
                   (0,1,7,6),(4,10,11,5),(0,6,8,2),(2,8,10,4),(1,3,9,7),(3,5,11,9)]
            batch.poly(vertices,faces,'Linen')
            for v in(.065,.765):batch.rod(p(r0,v,-.050),p(r1,v,-.050),.0045,'Linen',n=4)
        for r in(.82,1.72,2.60):
            for v in(.0,.81):batch.rod(p(r,v,-.034),p(r,v,.034),.014,'Iron',n=6)
    # Iron-banded timber windshaft, bearing block and restrained wall braces.
    batch.rod((0,-d/2-.03,h),(0,y-.085,h),.125,'Oak',n=16)
    for yy in(y-.074,y+.01,-d/2-.10):batch.rod((0,yy-.012,h),(0,yy+.012,h),.17,'Iron',n=16)
    for j in range(8):
        a=j*math.tau/8;x,z=math.cos(a)*.135,h+math.sin(a)*.135
        batch.rod((x,y-.097,z),(x,y-.082,z),.013,'Iron',n=6)
    batch.box((0,-d/2-.09,h-.13),(.45,.16,.36),'Oak')
    for sign in(-1,1):
        batch.rod((sign*.48,-d/2-.07,h-.78),(0,-d/2-.15,h-.09),.055,'Oak',n=8)
        batch.box((sign*.43,-d/2-.12,h-.67),(.16,.05,.10),'Iron')
    return {'sail_count':4,'radius_m':2.70,'lattice_rungs':36,'canvas_panels':16,'rotor_axis_local_m':[0,y,h]}


def _unit(v):
    length=math.sqrt(sum(x*x for x in v));return tuple(x/length for x in v)
def _cross(a,b):return(a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])


def _flower_geometry(batch,material,variant,small):
    rng=random.Random(20261020+variant*199+int(small)*917);count=7 if small else 21
    for index in range(count):
        angle=index*2.399963+variant*.43;rr=.70*math.sqrt((index+.4)/count)
        center=(rr*math.cos(angle),rr*math.sin(angle),.48-.48*(rr/.75)**2+rng.uniform(-.045,.045))
        normal=_unit((center[0]*.35,center[1]*.35,1.))
        u=_unit(_cross(normal,(0.,1.,0.)));v=_cross(normal,u)
        start=(center[0]*.14,center[1]*.14,-.92)
        batch.rod(start,center,.013,'Leaf',n=5,r2=.008)
        petals=5 if small else 4
        for petal in range(petals):
            a=petal*math.tau/petals+angle;axis=tuple(math.cos(a)*u[k]+math.sin(a)*v[k] for k in range(3))
            side=tuple(-math.sin(a)*u[k]+math.cos(a)*v[k] for k in range(3))
            length=.29 if small else .235;width=length*.44
            outline=((.02,0.),(.36,-width),(.82,-width*.76),(1.,0.),(.82,width*.76),(.36,width))
            front=[tuple(center[k]+axis[k]*s*length+side[k]*t+normal[k]*(.04*math.sin(s*math.pi)) for k in range(3)) for s,t in outline]
            ridge=tuple(center[k]+axis[k]*length*.53+normal[k]*.060 for k in range(3))
            vertices=front+[ridge]+[tuple(p[k]-normal[k]*.010 for k in range(3)) for p in front+[ridge]]
            faces=[(i,(i+1)%6,6) for i in range(6)]+[(7+i,13,7+(i+1)%6) for i in range(6)]
            faces +=[(i,7+i,7+(i+1)%6,(i+1)%6) for i in range(6)]
            batch.poly(vertices,faces,material)
        batch.rod(center,tuple(center[k]+normal[k]*.050 for k in range(3)),.029,'BloomCream',n=6,r2=.020)
        for j in range(3):
            a=j*math.tau/3;end=tuple(center[k]+u[k]*math.cos(a)*.028+v[k]*math.sin(a)*.028+normal[k]*.085 for k in range(3))
            batch.rod(center,end,.0055,'BloomCream',n=4,r2=.009)


def _flower_target(scope,parts,row,ident,anchor,small,material):
    selected=[]
    for i,part in enumerate(parts):selected.append(scope.select(part,(lambda p:_world(row,p)) if row else (lambda p:p),ident+f'/source_lobe_{i}'))
    local_points=[p for part in parts for p in part['vertices']];bounds=_bounds(local_points)
    ob=scope.objects[selected[0][0]]
    return {'id':ident,'scope':scope,'source_object':ob,'owner':ob.get('building_id'),
            'row':row,'bounds_local_m':bounds,'small':small,'material':material,'anchor':anchor,
            'source_components':len(parts),'source_properties':{key:value for key,value in ob.items()},
            'source_collections':list(ob.users_collection),'source_parent':ob.parent}


def _preflight(api,buildings,source_furniture,recipes):
    bpy=api['bpy'];rows=list(buildings);protected=set(source_furniture);mills=[];targets=[];scopes=[]
    windmills=[row for row in rows if row['kind']=='windmill']
    if len(windmills)!=1:raise ValueError('Expected exactly one scoped source windmill')
    for row in windmills:
        roof=bpy.data.collections.get(row['collections']['roof'])
        if roof is None:raise ValueError('Windmill roof collection missing')
        scope=SourceScope(roof.all_objects,protected);scopes.append(scope);old=Geometry()
        _execute(recipes['mill'],{'math':math,'d':row['footprint_m'][1],'h':row['floor_count']*2.85,'roof':old})
        if len(old.parts)!=16 or Counter(p['material'] for p in old.parts)!=Counter({'Trunk':4,'Oak':12}):raise ValueError('Bare-cross source recipe changed')
        for i,part in enumerate(old.parts):scope.select(part,lambda p:_world(row,p),row['id']+f'/legacy_cross_{i}')
        proposed=Geometry();detail=_mill_geometry(proposed,row);floor=row['interior']['levels'][0]['finished_floor_local_z_m']
        lowest=min(p[2] for part in proposed.parts for p in part['vertices']);clearance=lowest-floor
        if clearance<2.5:raise ValueError('Actual proposed mill geometry has less than2.5m entry clearance')
        mills.append({'row':row,'scope':scope,'detail':detail,'entry_clearance_m':clearance,'proposed_triangles':_triangles(proposed.parts)})
    # All four exact reserve flowers and their planter box must agree.
    for row in rows:
        if row.get('group')!='reserve':continue
        root=bpy.data.collections.get(row['collections']['root'])
        scope=SourceScope(root.all_objects,protected);scopes.append(scope);source=Geometry()
        w,d=row['footprint_m'];_execute(recipes['reserve_planters'],{'p':row['reserve_source'],'w':w,'d':d,'b':source})
        if len(source.parts)!=12:raise ValueError('Reserve planter recipe component count changed')
        for side in range(2):
            group=source.parts[side*6:(side+1)*6]
            # Container is a required identity guard, never a deletion target.
            expected={'vertices':[_world(row,p) for p in group[0]['vertices']],'faces':group[0]['faces']}
            hits=[c for ob in scope.objects.values() for c in scope.components[ob.name] if _helper()._matches(c,expected)]
            if len(hits)!=1:raise ValueError('Exact reserve planter box missing: '+row['id'])
            for j,part in enumerate(group[2:]):
                if part['material'] not in PALETTE or len(part['vertices'])!=24:raise ValueError('Reserve coarse head recipe changed')
                targets.append(_flower_target(scope,[part],row,row['id']+f'/planter_{side}/flower_{j}',None,True,part['material']))
    # Canonical hydrangea heads: exact rod pot/rim + all17 lobe components.
    for prefix in PUBLIC_POTS:
        objects=[ob for ob in bpy.context.scene.objects if ob.name.startswith(prefix+'_') and ob.type=='MESH'
                 and any(key in ob.name for key in ('Terracotta','Bloom'))]
        if not objects:continue
        scope=SourceScope(objects,protected);scopes.append(scope)
        for name,ob in scope.objects.items():
            if 'Terracotta' not in name:continue
            for c in scope.components[name]:
                if len(c['points'])!=24:continue
                low,high=c['bounds'];scale=(high[2]-low[2])/.44
                if not .4<=scale<=1.6:continue
                x,y,z=(low[0]+high[0])/2,(low[1]+high[1])/2,low[2];source=Geometry()
                recipes['pot'](source,x,y,z,True,scale)
                if not _helper()._matches(c,{'vertices':source.parts[0]['vertices'],'faces':source.parts[0]['faces']}):continue
                rim=source.parts[1]
                guards=[part for other in scope.objects.values() for part in scope.components[other.name]
                        if _helper()._matches(part,{'vertices':rim['vertices'],'faces':rim['faces']})]
                if len(guards)!=1:raise ValueError('Canonical flowerpot rim missing: '+prefix)
                flowers=[p for p in source.parts if p['material'] in PALETTE]
                if len(flowers)!=119:raise ValueError('Canonical seven17-lobe head recipe changed')
                for j in range(7):
                    group=flowers[j*17:(j+1)*17]
                    targets.append(_flower_target(scope,group,None,prefix+f'/pot_{x:.5f}_{y:.5f}/head_{j}',[x,y,z],False,group[0]['material']))
    if not targets:raise ValueError('No exact source planter flower heads matched')
    return mills,targets,scopes


def apply(api,output,buildings=None,source_furniture=None):
    bpy=api['bpy'];output=Path(output);baseline=Path(api.get('baseline_root',ROOT/'art/living_town'))
    buildings=buildings if buildings is not None else api['buildings'];source_furniture=source_furniture or {}
    recipes=_recipes(baseline);receipt={'schema':SCHEMA,'status':'PREFLIGHT','tool_sha256':_sha(__file__),
        'source_bindings':recipes['bindings'],'source_furniture_count':len(source_furniture),
        'exact_component_position_tolerance_m':_helper().TOLERANCE_M,'input_engine_opened_by_factory':False}
    helper=api['module']('granular_furniture_guard',Path(__file__).with_name('building_native_audit.py'))
    before={name:helper.mesh_fingerprint(bpy.data.objects[name]) for name in source_furniture}
    if any(before[name]['geometry_sha256']!=row['geometry_sha256'] for name,row in source_furniture.items()):raise ValueError('Protected source furniture already differs before granular stage')
    mills,targets,scopes=_preflight(api,buildings,source_furniture,recipes)
    botanical_path=output/'botanical_report.json'
    if botanical_path.exists():
        botanical=json.loads(botanical_path.read_text(encoding='utf-8'))
        expected_pots=botanical['understory']['source_flowerpot_leaf_replacement']['source_pot_count']
        if sum(not target['small'] for target in targets)!=7*expected_pots:
            raise ValueError('Canonical flower target count differs from independently bound botanical source-pot inventory')
        receipt['botanical_source_pot_inventory']={'path':botanical_path.name,'sha256':_sha(botanical_path),'pot_count':expected_pots}
    unique={};expanded=sum(m['proposed_triangles'] for m in mills)
    for target in targets:
        variant=int(hashlib.sha256(target['id'].encode()).hexdigest()[:8],16)%3;key=(target['material'],variant,target['small']);target['prototype_key']=key
        if key not in unique:
            geometry=Geometry();_flower_geometry(geometry,*key);unique[key]=geometry
        expanded+=_triangles(unique[key].parts)
    if expanded>MAX_EXPANDED_TRIANGLES:raise ValueError('Granular factory exceeds explicit500k expanded triangle cap')
    # Complete source and budget preflight precedes any removal or new linkage.
    library=bpy.data.collections.new('Granular_Detail_PrototypeLibrary_NotInScene');prototypes={}
    for key,geometry in unique.items():
        batch=api['Batch']('Granular_Flower_'+str(len(prototypes)),library)
        for part in geometry.parts:batch.poly(part['vertices'],part['faces'],part['material'])
        objects=batch.flush();points=[tuple(v.co) for ob in objects for v in ob.data.vertices];bounds=_bounds(points)
        prototypes[key]=(objects,bounds)
    created=[];flower_records=[]
    from mathutils import Matrix
    for target in targets:
        objects,pb=prototypes[target['prototype_key']];low,high=target['bounds_local_m'];center=[(a+b)/2 for a,b in zip(low,high)]
        scale=[(high[k]-low[k])*.98/(pb[1][k]-pb[0][k]) for k in range(3)]
        pc=[(a+b)/2 for a,b in zip(*pb)];row=target['row'];angle=math.radians(row['yaw_degrees']) if row else 0.
        origin=_world(row,center) if row else center
        transform=Matrix.Translation(origin)@Matrix.Rotation(angle,4,'Z')@Matrix.Diagonal((*scale,1.))@Matrix.Translation([-v for v in pc])
        names=[]
        for prototype in objects:
            ob=bpy.data.objects.new('Granular_'+target['id'].replace('/','_')+'_'+prototype.name,prototype.data)
            for collection in target['source_collections']:collection.objects.link(ob)
            ob.parent=target['source_parent'];ob.matrix_world=transform
            for key,value in target['source_properties'].items():ob[key]=value
            ob['generator_owner']=SCHEMA;ob['semantic_role']='individual_petals_stamens_and_stems';ob['granular_planter_head_id']=target['id']
            ob['granular_source_object']=target['source_object'].name
            for vertex in ob.data.vertices:
                p=ob.matrix_world@vertex.co;p=_local(row,p) if row else p
                if any(p[k]<low[k]-.0001 or p[k]>high[k]+.0001 for k in range(3)):raise RuntimeError('Petals escape original measured planter-head bounds')
            created.append(ob);names.append(ob.name)
        flower_records.append({'id':target['id'],'source_object':target['source_object'].name,'building_id':target['owner'],
            'source_head_components':target['source_components'],'source_head_local_bounds_m':[low,high],
            'prototype_key':target['prototype_key'],'objects':names,'source_bounds_containment':'PASS'})
    mill_records=[]
    for mill in mills:
        row=mill['row'];batch=api['Batch'](row['id']+'_Granular_Windmill',bpy.data.collections[row['collections']['roof']],
            (*row['center_m'][:2],row['pad_level_m']),math.radians(row['yaw_degrees']))
        _mill_geometry(batch,row);objects=batch.flush()
        actual_low=min(_local(row,ob.matrix_world@vertex.co)[2] for ob in objects for vertex in ob.data.vertices)
        actual_clearance=actual_low-row['interior']['levels'][0]['finished_floor_local_z_m']
        if actual_clearance<2.5:raise RuntimeError('Flushed mill mesh violates the required2.5m entry clearance')
        for ob in objects:
            ob['building_id']=row['id'];ob['generator_owner']=SCHEMA;ob['semantic_role']='windmill_lattice_canvas_sails_and_windshaft';created.append(ob)
        mill_records.append({'building_id':row['id'],**mill['detail'],'proposed_entry_clearance_m':mill['entry_clearance_m'],
            'actual_flushed_mesh_entry_clearance_m':actual_clearance,
            'required_entry_clearance_m':2.5,'objects':[ob.name for ob in objects]})
    retention=[record for scope in scopes for record in scope.delete(bpy)]
    after={name:helper.mesh_fingerprint(bpy.data.objects[name]) for name in source_furniture}
    if before!=after:raise RuntimeError('Granular stage altered protected source furniture fingerprint')
    receipt.update(status='BUILT_REQUIRES_NATIVE_AND_VISUAL_REVIEW',windmills=mill_records,flower_head_count=len(targets),
        canonical17_lobe_heads=sum(not t['small'] for t in targets),reserve_small_heads=sum(t['small'] for t in targets),
        flower_heads=flower_records,source_component_proofs=[proof for scope in scopes for proof in scope.receipts],
        preserved_other_components=retention,protected_furniture_fingerprints='PASS',shared_flower_prototypes=len(prototypes),
        expanded_triangles_upper_bound=expanded,expanded_triangle_cap=MAX_EXPANDED_TRIANGLES,
        added_objects=[ob.name for ob in created],
        policy='Exact source components only. Existing pot bodies, rims, unrelated plants/wood, owner collections and all furniture geometry/poses remain unchanged. Flowers stay inside each original measured head box. No route or building footprint changes.',
        limitations=['Actual saved-native entry clearance and source furniture checks plus close visual review remain required.'])
    output.mkdir(parents=True,exist_ok=True);_write(output/'granular_details_receipt.json',receipt)
    return receipt


def self_test():
    recipes=_recipes(ROOT/'art/living_town');row={'footprint_m':[5.,6.],'floor_count':2,'yaw_degrees':0.,'center_m':[-56.,35.],
                                               'pad_level_m':4.,'interior':{'levels':[{'finished_floor_local_z_m':.38}]}}
    old=Geometry();_execute(recipes['mill'],{'math':math,'d':6.,'h':5.7,'roof':old})
    if len(old.parts)!=16:raise AssertionError('Windmill source recipe count')
    new=Geometry();_mill_geometry(new,row);low=min(p[2] for part in new.parts for p in part['vertices'])
    if low-.38<2.5:raise AssertionError('Windmill clearance')
    variants=[]
    for material in PALETTE:
        for variant in range(3):
            for small in (False,True):
                a=Geometry();b=Geometry();_flower_geometry(a,material,variant,small);_flower_geometry(b,material,variant,small)
                if a.parts!=b.parts:raise AssertionError('Nondeterministic flower geometry')
                if any(not math.isfinite(v) for part in a.parts for p in part['vertices'] for v in p):raise AssertionError('Nonfinite flower')
                variants.append({'material':material,'variant':variant,'small':small,'triangles':_triangles(a.parts)})
    # Exact component identity rejects changes to topology and arbitrary wood.
    part=old.parts[0];actual={'points':part['vertices'],'faces':part['faces']}
    if not _helper()._matches(actual,part):raise AssertionError('Positive component identity')
    broken=dict(actual,faces=actual['faces'][:-1])
    if _helper()._matches(broken,part):raise AssertionError('Topology mutation accepted')
    broken=dict(actual,points=[(p[0]+.01,p[1],p[2]) for p in actual['points']])
    if _helper()._matches(broken,part):raise AssertionError('Moved component accepted')
    return {'status':'PASS','source_component_checks':3,'flower_variants':len(variants),'windmill_entry_clearance_m':low-.38,
            'windmill_triangles':_triangles(new.parts),'variants':variants,'scope':'Pure source recipe/geometry checks; no Blender/native or visual acceptance.'}


if __name__=='__main__':print(json.dumps(self_test(),indent=2))
