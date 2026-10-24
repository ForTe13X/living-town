"""Bounded, same-topology seat-contact morphs using inverse source LBS.

The garment keeps its vertices, faces, UV indexing and skin weights. Only
source positions change. Contact is measured on triangles clipped to the
metric seat footprint; no actor/fixture anchor movement is introduced.
"""
import math

from .seating import solve
from .skinning import deform_points,pose_transforms


TARGET_NAME='SeatContact'


def _face_ids(face):return [value[0] if isinstance(value,(tuple,list)) else value for value in face]
def _dot(a,b):return sum(x*y for x,y in zip(a,b))
def _length(a):return math.sqrt(_dot(a,a))
def _apply(matrix,point):return tuple(_dot(row,point) for row in matrix)
def _smooth(value):
    value=max(0.,min(1.,value));return value*value*(3-2*value)


def _inverse(matrix):
    a,b,c=matrix[0];d,e,f=matrix[1];g,h,i=matrix[2]
    determinant=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g)
    if abs(determinant)<1e-9:raise ValueError('Singular weighted skin matrix')
    return (( (e*i-f*h)/determinant,(c*h-b*i)/determinant,(b*f-c*e)/determinant),
            ((f*g-d*i)/determinant,(a*i-c*g)/determinant,(c*d-a*f)/determinant),
            ((d*h-e*g)/determinant,(b*g-a*h)/determinant,(a*e-b*d)/determinant))


def _clip(poly,axis,bound,sign):
    result=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        inside_a=(a[0][axis]-bound)*sign>=-1e-12;inside_b=(b[0][axis]-bound)*sign>=-1e-12
        if inside_a:result.append(a)
        if inside_a!=inside_b:
            fraction=(bound-a[0][axis])/(b[0][axis]-a[0][axis])
            result.append((tuple(a[0][k]+fraction*(b[0][k]-a[0][k]) for k in range(3)),
                           tuple(a[1][k]+fraction*(b[1][k]-a[1][k]) for k in range(3))))
    return result


def clipped_seat_report(positions,faces,*,seat_height_m=.462,seat_half_extent_m=.22,minimum_clearance_m=.001,seat_thickness_m=.045,include_constraints=False):
    """Exact piecewise-linear minimum Z after clipping triangles in seat XY."""
    minimum=None;clipped_count=0;violations=0;penetrations=0;worst=None;constraints=[]
    for face_index,face in enumerate(faces):
        ids=_face_ids(face)
        for fan in range(1,len(ids)-1):
            triangle=(ids[0],ids[fan],ids[fan+1])
            poly=[(positions[index],tuple(1. if k==j else 0. for k in range(3))) for j,index in enumerate(triangle)]
            for axis,bound,sign in [(0,-seat_half_extent_m,1),(0,seat_half_extent_m,-1),(1,-seat_half_extent_m,1),(1,seat_half_extent_m,-1)]:
                if poly:poly=_clip(poly,axis,bound,sign)
            if not poly:continue
            clipped_count+=1;point,bary=min(poly,key=lambda value:value[0][2]);gap=point[2]-seat_height_m
            if minimum is None or gap<minimum:
                minimum=gap;worst={'face_index':face_index,'triangle':triangle,'point':point,'barycentric':bary,'clearance_m':gap}
            if gap<minimum_clearance_m-1e-8:
                violations+=1
                if include_constraints:constraints.append((triangle,bary,minimum_clearance_m-gap))
            if gap<0 and max(value[0][2] for value in poly)>seat_height_m-seat_thickness_m:penetrations+=1
    report={'minimum_clipped_triangle_clearance_m':minimum,'minimum_required_m':minimum_clearance_m,
            'clipped_triangle_count':clipped_count,'triangles_below_required_clearance':violations,
            'triangles_intersecting_seat_volume':penetrations,'maximum_plane_penetration_m':max(0.,-minimum) if minimum is not None else 0.,
            'worst_triangle':worst,'success':minimum is None or minimum>=minimum_clearance_m-1e-8,
            'method':'triangle fans clipped exactly to fixed seat XY footprint; minimum interpolated Z'}
    return (report,constraints) if include_constraints else report


def _weighted_matrix(row,transforms):
    total=sum(row.values())
    if abs(total-1)>1e-5:raise ValueError('Skin weights must sum to one')
    return tuple(tuple(sum(weight*transforms[name]['rotation'][r][c] for name,weight in row.items())/total for c in range(3)) for r in range(3))


def generate_target(positions,faces,weights,joints,metrics,*,scale=1.,seat_height_m=.462,seat_half_extent_m=.22,minimum_clearance_m=.001,max_posed_displacement_m=.040,root_floor_offsets_m=(0.,.025),include_soak=True,blend_band_m=.060,maximum_iterations=8):
    """Return full source positions and a serializable SeatContact report.

    ``faces`` may select only pants while referencing full-garment indices;
    OBJ ``(vertex,uv)`` corners are also accepted. Native/runtime cases share
    the seating solver's world-height convention. Knees/lower legs are fixed.
    The 40 mm cap applies to actual posed-world motion in every tested case;
    inverse-LBS source deltas are separately reported and may be longer.
    """
    if len(positions)!=len(weights) or not all(math.isfinite(value) for p in positions for value in p):raise ValueError('Invalid source geometry')
    if scale<=0 or max_posed_displacement_m<=0 or blend_band_m<=0:raise ValueError('Invalid corrective dimensions')
    positions=[tuple(p) for p in positions];selected={index for face in faces for index in _face_ids(face)}
    if any(index<0 or index>=len(positions) for index in selected):raise ValueError('Face index out of bounds')
    cases=[]
    for offset in root_floor_offsets_m:
        solution=solve(metrics,seat_height_m,scale,offset)
        cases.append({'name':'native' if offset==0 else ('runtime' if offset==.025 else 'offset_'+str(offset)),
                      'clip':'Sit','offset':offset,'pelvis':solution['source_pelvis_height_m'],'poses':solution['poses'],'contact':True,'solution':solution})
    if include_soak:
        poses={}
        for side in ('L','R'):
            poses['Thigh_'+side]=(math.pi/2,0.,0.);poses['Shin_'+side]=(-math.pi/2,0.,0.);poses['Foot_'+side]=(0.,0.,0.)
        poses['ApronDrape']=(math.pi/2,0.,0.);poses['ApronHem']=(-math.pi/2,0.,0.)
        cases.append({'name':'soak_90','clip':'Soak','offset':0.,'pelvis':(.36+.025)/scale,'poses':poses,'contact':False})
    for case in cases:
        transforms=pose_transforms(joints,clip=case['clip'],phase=.25,poses=case['poses'],pelvis_z=case['pelvis'])
        case['matrix']=[_weighted_matrix(row,transforms) for row in weights]
        case['base']=[(x,y,z+case['offset']) for x,y,z in deform_points(positions,weights,joints,clip=case['clip'],phase=.25,poses=case['poses'],pelvis_z=case['pelvis'],scale=scale)]
        if case['contact']:case['pre']=clipped_seat_report(case['base'],faces,seat_height_m=seat_height_m,seat_half_extent_m=seat_half_extent_m,minimum_clearance_m=minimum_clearance_m)
    reference=next(case for case in cases if case['contact']);count=len(positions);directions=[];caps=[];active=[]
    knee_z=max(joints['Shin_L'][2],joints['Shin_R'][2]);protected=[]
    for index,p in enumerate(positions):
        knee_mask=_smooth((p[2]-knee_z-.045)/.085) if index in selected else 0.
        if not knee_mask:
            directions.append((0.,0.,0.));caps.append(0.);protected.append(index);continue
        direction=_apply(_inverse(reference['matrix'][index]),(0.,0.,1./scale));directions.append(direction);active.append(index)
        gains=[tuple(value*scale for value in _apply(case['matrix'][index],direction)) for case in cases]
        max_gain=max(_length(value) for value in gains)
        silhouette_cap=.006 if all(case['base'][index][2]>seat_height_m+.065 for case in cases if case['contact']) else max_posed_displacement_m
        caps.append(min(max_posed_displacement_m,silhouette_cap)*knee_mask/max_gain)
    for case in cases:case['gain']=[tuple(value*scale for value in _apply(matrix,directions[index])) for index,matrix in enumerate(case['matrix'])]
    amplitude=[0.]*count
    for case in cases:
        if not case['contact']:continue
        for index in active:
            x,y,z=case['base'][index];outside=max(abs(x)-seat_half_extent_m,abs(y)-seat_half_extent_m,0.)
            if outside>=blend_band_m:continue
            gain=case['gain'][index][2]
            if gain>.15:
                need=max(0.,seat_height_m+minimum_clearance_m+.00002-z)*(1-_smooth(outside/blend_band_m))
                amplitude[index]=min(caps[index],max(amplitude[index],need/gain))
    # Broad local smoothing affects the transition band, while the conservative
    # maximum retains required contact lifts. Lower legs remain exactly fixed.
    grid={};cell=blend_band_m
    for index in active:
        key=tuple(math.floor(v/cell) for v in positions[index]);grid.setdefault(key,[]).append(index)
    def envelope(values):
        output=values[:]
        for index in active:
            key=tuple(math.floor(v/cell) for v in positions[index]);total=0.;weighted=0.
            for dx in (-1,0,1):
                for dy in (-1,0,1):
                    for dz in (-1,0,1):
                        for other in grid.get((key[0]+dx,key[1]+dy,key[2]+dz),[]):
                            distance=sum((positions[index][k]-positions[other][k])**2 for k in range(3));weight=math.exp(-distance/(2*(blend_band_m*.5)**2))
                            total+=weight;weighted+=values[other]*weight
            smooth=weighted/total if total else 0.
            output[index]=min(caps[index],max(values[index],smooth*.7))
        return output
    amplitude=envelope(amplitude);iterations=0
    def posed(case):return [tuple(case['base'][i][k]+case['gain'][i][k]*amplitude[i] for k in range(3)) for i in range(count)]
    for iteration in range(maximum_iterations):
        extra=[0.]*count;violations=0
        for case in cases:
            if not case['contact']:continue
            current=posed(case);audit,constraints=clipped_seat_report(current,faces,seat_height_m=seat_height_m,seat_half_extent_m=seat_half_extent_m,minimum_clearance_m=minimum_clearance_m,include_constraints=True)
            violations+=len(constraints)
            for triangle,bary,need in constraints:
                available=[(index,factor) for index,factor in zip(triangle,bary) if caps[index]-amplitude[index]>1e-9]
                gain=sum(factor*case['gain'][index][2] for index,factor in available)
                if gain<=1e-9:continue
                increment=(need+.00002)/gain
                for index,factor in available:extra[index]=max(extra[index],increment)
        if not violations:break
        if max(extra,default=0)<1e-10:break
        smoothed=envelope(extra)
        for index in active:amplitude[index]=min(caps[index],amplitude[index]+smoothed[index])
        iterations=iteration+1
    target=[tuple(p[k]+directions[i][k]*amplitude[i] for k in range(3)) for i,p in enumerate(positions)]
    reports={};max_posed=0.;max_source=0.;protected_motion=0.
    for i in range(count):max_source=max(max_source,_length(tuple(target[i][k]-positions[i][k] for k in range(3))))
    for case in cases:
        current=posed(case);delta=[_length(tuple(current[i][k]-case['base'][i][k] for k in range(3))) for i in range(count)];motion=max(delta,default=0.);max_posed=max(max_posed,motion)
        protected_motion=max(protected_motion,max((delta[i] for i in protected),default=0.))
        entry={'root_floor_offset_m':case['offset'],'source_pelvis_height_m':case['pelvis'],'chair_contact_required':case['contact'],'maximum_posed_displacement_m':motion,'finite':all(math.isfinite(v) for p in current for v in p)}
        if case['contact']:
            entry.update(pre=case['pre'],post=clipped_seat_report(current,faces,seat_height_m=seat_height_m,seat_half_extent_m=seat_half_extent_m,minimum_clearance_m=minimum_clearance_m),solution=case['solution'])
        reports[case['name']]=entry
    success=all(entry['finite'] and (not entry['chair_contact_required'] or entry['post']['success']) for entry in reports.values()) and max_posed<=max_posed_displacement_m+1e-8
    report={'target_name':TARGET_NAME,'success':success,'same_topology':True,'source_vertex_count':count,'selected_face_count':len(faces),'changed_vertices':sum(amplitude[i]>1e-10 for i in range(count)),
            'maximum_posed_displacement_m':max_posed,'maximum_source_displacement_m':max_source,'maximum_world_scaled_source_delta_m':max_source*scale,
            'maximum_protected_knee_lower_leg_motion_m':protected_motion,'maximum_allowed_posed_displacement_m':max_posed_displacement_m,'blend_band_m':blend_band_m,'iterations':iterations,'fixed_actor_and_seat_anchor':True,'cases':reports,
            'limitations':'Rigid flat seat footprint only; no chair back/arms, cloth self-collision or artistic acceptance. Caller preserves original UV/index/skin arrays and applies this target only in seated/soak states.'}
    if not success:report['failure_reason']='Bounded same-topology correction did not satisfy every clipped seat triangle; cap was retained.'
    return target,report
