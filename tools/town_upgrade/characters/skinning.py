"""Dependency-free source-pose FK/LBS and sampled cloth clearance checks.

Coordinates are the *adapted rest mesh* in Blender XYZ meters, not the original
unposed MakeHuman mesh. Joint rest bases in this pipeline share world axes.
Animation Euler increments use the source baker's exact conversion X,-Z,Y and
Blender's XYZ convention. This checks source geometry before any engine import;
it is not a substitute for checking imported Godot bone/rest semantics.
"""
import math

from .animation import pelvis_height, pose_values


IDENTITY=((1.,0.,0.),(0.,1.,0.),(0.,0.,1.))


def _add(a,b):return tuple(x+y for x,y in zip(a,b))
def _sub(a,b):return tuple(x-y for x,y in zip(a,b))
def _mul(a,b):return tuple(tuple(sum(a[i][k]*b[k][j] for k in range(3)) for j in range(3)) for i in range(3))
def _apply(matrix,point):return tuple(sum(row[k]*point[k] for k in range(3)) for row in matrix)
def _distance(a,b):return math.sqrt(sum((x-y)**2 for x,y in zip(a,b)))


def source_rotation(engine_angles):
    """Return Blender XYZ Euler(x,-z,y) as a row-major 3x3 matrix."""
    if len(engine_angles)!=3 or not all(math.isfinite(v) for v in engine_angles):raise ValueError('Invalid joint Euler increment')
    x,y,z=engine_angles[0],-engine_angles[2],engine_angles[1]
    sx,cx=math.sin(x),math.cos(x);sy,cy=math.sin(y),math.cos(y);sz,cz=math.sin(z),math.cos(z)
    rx=((1.,0.,0.),(0.,cx,-sx),(0.,sx,cx))
    ry=((cy,0.,sy),(0.,1.,0.),(-sy,0.,cy))
    rz=((cz,-sz,0.),(sz,cz,0.),(0.,0.,1.))
    return _mul(_mul(rz,ry),rx)


def default_parents(joints):
    parents={'PelvisRoot':None,'BodyPivot':'PelvisRoot','HeadPivot':'BodyPivot',
             'ApronDrape':'PelvisRoot','ApronHem':'ApronDrape'}
    for side in ('L','R'):
        parents.update({'UpperArm_'+side:'BodyPivot','Forearm_'+side:'UpperArm_'+side,
                        'Hand_'+side:'Forearm_'+side,'Thigh_'+side:'PelvisRoot',
                        'Shin_'+side:'Thigh_'+side,'Foot_'+side:'Shin_'+side})
    return {name:parents[name] for name in joints}


def pose_transforms(joints,parents=None,clip=None,phase=0.,*,poses=None,pelvis_z=None):
    """Return absolute posed joint transforms, preserving all rest offsets.

    ``clip=None`` gives the exact rest pose. ``poses`` overrides named engine
    Euler increments from the selected clip. ``pelvis_z`` optionally supplies
    the already-normalized source-unit furniture height. Supplied optional
    joints without a curve inherit their parent's motion with zero local turn.
    """
    parents=default_parents(joints) if parents is None else parents
    if not math.isfinite(phase):raise ValueError('Invalid animation phase')
    angles=dict(pose_values(clip,phase)) if clip else {}
    if poses:angles.update(poses)
    transforms={};visiting=set()
    for name,p in joints.items():
        if len(p)!=3 or not all(math.isfinite(float(v)) for v in p):raise ValueError('Invalid rest joint: '+name)
    if 'PelvisRoot' in joints and pelvis_z is None and clip:
        leg_length=sum(_distance(joints[a],joints[b]) for a,b in [('Shin_L','Thigh_L'),('Foot_L','Shin_L')] if a in joints and b in joints)
        pelvis_z=pelvis_height(clip,phase,joints['PelvisRoot'][2],leg_length)
    if pelvis_z is not None and not math.isfinite(pelvis_z):raise ValueError('Invalid pelvis height')
    def visit(name):
        if name in transforms:return transforms[name]
        if name in visiting:raise ValueError('Cyclic joint hierarchy: '+name)
        if name not in parents:raise ValueError('Missing parent mapping: '+name)
        visiting.add(name);parent=parents[name];local_rotation=source_rotation(angles.get(name,(0.,0.,0.)))
        if parent is not None:
            if parent not in joints:raise ValueError('Missing rest parent: '+parent)
            ancestor=visit(parent)
            position=_add(ancestor['position'],_apply(ancestor['rotation'],_sub(joints[name],joints[parent])))
            rotation=_mul(ancestor['rotation'],local_rotation)
        else:position=tuple(joints[name]);rotation=local_rotation
        if name=='PelvisRoot' and pelvis_z is not None:position=(position[0],position[1],float(pelvis_z))
        transforms[name]={'position':position,'rotation':rotation,'rest_position':tuple(joints[name])}
        visiting.remove(name);return transforms[name]
    for name in joints:visit(name)
    return transforms


def deform_points(positions,weights,joints,parents=None,clip=None,phase=0.,*,poses=None,pelvis_z=None,scale=1.,strict=True):
    """Linear-blend-skin adapted rest vertices through the named joint rig.

    Weights must be positive and sum to one (1e-5 tolerance). Invalid influence
    names raise by default; ``strict=False`` ignores missing names and
    normalizes remaining influences, useful only for explicitly partial audits.
    Empty rows stay at rest only in non-strict mode. ``scale`` applies uniform
    persona stature after source-space posing, matching CharacterRoot.
    """
    if len(positions)!=len(weights):raise ValueError('Vertex/influence count differs')
    if not math.isfinite(scale) or scale<=0:raise ValueError('Invalid character scale')
    transforms=pose_transforms(joints,parents,clip,phase,poses=poses,pelvis_z=pelvis_z);result=[]
    for index,(point,row) in enumerate(zip(positions,weights)):
        if len(point)!=3 or not all(math.isfinite(v) for v in point):raise ValueError('Invalid vertex: '+str(index))
        if strict and any(name not in transforms for name in row):raise ValueError('Unknown skin joint at vertex '+str(index))
        active={name:float(weight) for name,weight in row.items() if name in transforms}
        if any(not math.isfinite(v) or v<0 for v in active.values()):raise ValueError('Invalid skin weight at vertex '+str(index))
        total=sum(active.values())
        if strict and abs(total-1)>1e-5:raise ValueError('Skin weights do not sum to one at vertex '+str(index))
        if not total:result.append(tuple(v*scale for v in point));continue
        output=[0.,0.,0.]
        for name,weight in active.items():
            transform=transforms[name]
            target=_add(transform['position'],_apply(transform['rotation'],_sub(point,transform['rest_position'])))
            for axis in range(3):output[axis]+=target[axis]*(weight/total)*scale
        result.append(tuple(output))
    return result


def _triangles(faces):
    for face_index,face in enumerate(faces):
        # Accept both mesh indices and OBJ (vertex,uv) pairs.
        ids=[index[0] if isinstance(index,(tuple,list)) else index for index in face]
        for i in range(1,len(ids)-1):yield face_index,(ids[0],ids[i],ids[i+1])


class ProjectedSurface:
    """Reusable spatial grid for directional, barycentric surface depth queries."""
    def __init__(self,positions,faces,axis=1,front_sign=1.,cell_size=.035):
        if axis not in (0,1,2) or front_sign not in (-1,1) or cell_size<=0:raise ValueError('Invalid projection')
        self.axis=axis;self.front_sign=front_sign;self.cell_size=cell_size
        self.axes=[i for i in range(3) if i!=axis];self.grid={};self.triangles=[];self.omitted=0
        for face_index,ids in _triangles(faces):
            a,b,c=[positions[i] for i in ids];x,y=self.axes
            denominator=(b[y]-c[y])*(a[x]-c[x])+(c[x]-b[x])*(a[y]-c[y])
            if abs(denominator)<1e-12:self.omitted+=1;continue
            index=len(self.triangles);self.triangles.append((a,b,c,denominator,face_index))
            xs=[p[x] for p in (a,b,c)];ys=[p[y] for p in (a,b,c)]
            for i in range(math.floor(min(xs)/cell_size),math.floor(max(xs)/cell_size)+1):
                for j in range(math.floor(min(ys)/cell_size),math.floor(max(ys)/cell_size)+1):self.grid.setdefault((i,j),[]).append(index)

    def depth_at(self,point):
        """Return (signed front depth, face index), or (None,None) off surface."""
        x,y=point[self.axes[0]],point[self.axes[1]];depth=None;hit_face=None
        for index in self.grid.get((math.floor(x/self.cell_size),math.floor(y/self.cell_size)),[]):
            a,b,c,denominator,face_index=self.triangles[index];k,l=self.axes
            u=((b[l]-c[l])*(x-c[k])+(c[k]-b[k])*(y-c[l]))/denominator
            v=((c[l]-a[l])*(x-c[k])+(a[k]-c[k])*(y-c[l]))/denominator;w=1-u-v
            if min(u,v,w)<-1e-8:continue
            candidate=(u*a[self.axis]+v*b[self.axis]+w*c[self.axis])*self.front_sign
            if depth is None or candidate>depth:depth=candidate;hit_face=face_index
        return depth,hit_face


def surface_contact_report(outer_positions,inner_positions,inner_faces,*,outer_faces=None,axis=1,front_sign=1.,minimum_clearance=0.,cell_size=.035,interior_samples=1,max_examples=8):
    """Measure sampled outer-minus-inner depth where surface projections overlap.

    For standing apron fronts choose Blender +Y (``axis=1``); for a seated lap
    choose +Z (``axis=2``), restricting meshes to the relevant lower cloth.
    Each outer vertex and optional triangle centroid/interior lattice point is
    compared against the frontmost barycentrically interpolated inner triangle
    at that projected location. A negative clearance is projected penetration.

    This is a directional sampled surface test, not a closed-volume or complete
    triangle/triangle intersection proof. Unrelated foreground layers (hands,
    torso above a lap, rear cloth) must be excluded by the caller. Tiny edge-on
    triangles are omitted; ``unmatched_samples`` makes coverage explicit.
    """
    if axis not in (0,1,2):raise ValueError('Projection axis must be 0, 1 or 2')
    if front_sign not in (-1,1):raise ValueError('Front sign must be -1 or +1')
    if not math.isfinite(cell_size) or cell_size<=0 or interior_samples<0:raise ValueError('Invalid sampling resolution')
    if not math.isfinite(minimum_clearance):raise ValueError('Invalid required clearance')
    surface=ProjectedSurface(inner_positions,inner_faces,axis,front_sign,cell_size)
    samples=[(tuple(p),'vertex',index) for index,p in enumerate(outer_positions)]
    if outer_faces and interior_samples:
        for face_index,ids in _triangles(outer_faces):
            a,b,c=[outer_positions[i] for i in ids]
            # One centroid is the bounded default. Higher orders add a strict
            # interior barycentric lattice without duplicate edge samples.
            samples.append((tuple((a[k]+b[k]+c[k])/3 for k in range(3)),'face',face_index))
            for i in range(1,interior_samples):
                for j in range(1,interior_samples+1-i):
                    u=i/(interior_samples+1);v=j/(interior_samples+1);w=1-u-v
                    if w>0:samples.append((tuple(a[k]*u+b[k]*v+c[k]*w for k in range(3)),'face',face_index))
    clearances=[];examples=[];violations=0;unmatched=0
    for point,kind,source_index in samples:
        depth,hit_face=surface.depth_at(point)
        if depth is None:unmatched+=1;continue
        clearance=point[axis]*front_sign-depth;clearances.append(clearance)
        if clearance<minimum_clearance-1e-9:
            violations+=1
            examples.append({'clearance_m':clearance,'point':point,'outer_kind':kind,'outer_index':source_index,'inner_face':hit_face})
    clearances.sort();examples.sort(key=lambda entry:entry['clearance_m'])
    count=len(clearances)
    return {'projection_axis':axis,'front_sign':front_sign,'minimum_required_m':minimum_clearance,
            'inner_triangles':len(surface.triangles),'edge_on_triangles_omitted':surface.omitted,
            'sample_count':len(samples),'matched_samples':count,'unmatched_samples':unmatched,
            'violation_samples':violations,'minimum_clearance_m':clearances[0] if count else None,
            'p05_clearance_m':clearances[math.floor((count-1)*.05)] if count else None,
            'median_clearance_m':clearances[count//2] if count else None,
            'maximum_penetration_m':max(0.,-clearances[0]) if count else None,
            'worst_samples':examples[:max_examples],
            'method':'directional projected triangle depth; sampled vertices and optional face interiors'}


def surface_envelope_report(outer_positions,inner_positions,inner_faces,*,outer_faces=None,axes=(1,2),minimum_clearance=0.,cell_size=.035,max_examples=8):
    """Sample clearance outside the union of positive-axis front envelopes.

    At a waist-to-lap fold a point may be safely in front of the trousers (+Y)
    while below their top (+Z). Taking the larger available directional gap
    avoids incorrectly inflating that point above the lap. A negative result
    means the sample lies behind *all* tested front envelopes. This bounded
    front-quadrant test is not a general closed-volume collision predicate.
    """
    surfaces={axis:ProjectedSurface(inner_positions,inner_faces,axis,1,cell_size) for axis in axes}
    samples=[(tuple(p),'vertex',index) for index,p in enumerate(outer_positions)]
    if outer_faces:
        for face_index,ids in _triangles(outer_faces):
            points=[outer_positions[i] for i in ids]
            samples.append((tuple(sum(p[k] for p in points)/3 for k in range(3)),'face',face_index))
    values=[];examples=[];violations=0;axis_counts={str(axis):0 for axis in axes}
    for point,kind,index in samples:
        gaps=[]
        for axis,surface in surfaces.items():
            depth,face=surface.depth_at(point)
            if depth is not None:gaps.append((point[axis]-depth,axis,face))
        if not gaps:continue
        gap,axis,face=max(gaps);values.append(gap);axis_counts[str(axis)]+=1
        if gap<minimum_clearance-1e-9:
            violations+=1;examples.append({'clearance_m':gap,'point':point,'outer_kind':kind,'outer_index':index,'inner_face':face,'best_exit_axis':axis})
    values.sort();examples.sort(key=lambda value:value['clearance_m']);count=len(values)
    return {'projection_axes':list(axes),'minimum_required_m':minimum_clearance,'sample_count':len(samples),
            'matched_samples':count,'unmatched_samples':len(samples)-count,'violation_samples':violations,
            'minimum_clearance_m':values[0] if count else None,'maximum_clearance_m':values[-1] if count else None,
            'p05_clearance_m':values[math.floor((count-1)*.05)] if count else None,'median_clearance_m':values[count//2] if count else None,
            'maximum_penetration_m':max(0.,-values[0]) if count else None,'best_exit_axis_counts':axis_counts,
            'worst_samples':examples[:max_examples],'method':'sampled positive-axis front-envelope clearance; not full-volume collision proof'}
