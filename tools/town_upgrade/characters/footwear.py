"""Fit CC0 shoe ankle linings inside the actual tailored trouser surface.

The two large shoe components contain every sole, toe, lace and leather upper.
The separate 144-vertex ankle linings extend much farther up the leg and can
cross trousers after independent body fitting. Only those linings are fitted;
authored topology, atlas coordinates, Z positions and skin weights are retained.
"""
import math

from .assets import geometry_for
from .skinning import ProjectedSurface,deform_points,pose_transforms


def _smooth(t):
    t=max(0.,min(1.,t));return t*t*(3.-2.*t)


def _cross(a,b):return a[0]*b[1]-a[1]*b[0]


def _ids(face):return [value[0] if isinstance(value,(tuple,list)) else value for value in face]


def _apply(matrix,point):return tuple(sum(row[k]*point[k] for k in range(3)) for row in matrix)


def _inverse(matrix):
    a,b,c=matrix[0];d,e,f=matrix[1];g,h,i=matrix[2];det=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g)
    if abs(det)<1e-10:raise ValueError('Singular ankle skin transform')
    return (((e*i-f*h)/det,(c*h-b*i)/det,(b*f-c*e)/det),((f*g-d*i)/det,(a*i-c*g)/det,(c*d-a*f)/det),((d*h-e*g)/det,(b*g-a*h)/det,(a*e-b*d)/det))


def _source_frame(positions,indices,row,transforms):
    """Put posed trousers into one cuff vertex's exact affine skin frame."""
    matrix=tuple(tuple(sum(weight*transforms[name]['rotation'][r][c] for name,weight in row.items()) for c in range(3)) for r in range(3))
    inverse=_inverse(matrix)
    offset=[0.,0.,0.]
    for name,weight in row.items():
        transform=transforms[name];rotated=_apply(transform['rotation'],transform['rest_position'])
        for k in range(3):offset[k]+=weight*(transform['position'][k]-rotated[k])
    return {i:_apply(inverse,tuple(positions[i][k]-offset[k] for k in range(3))) for i in indices}


def _section(positions,triangles,z):
    """Intersect the actual piecewise-linear trouser mesh with source Z."""
    segments=[]
    for triangle in triangles:
        points=[positions[i] for i in triangle]
        if z<min(p[2] for p in points)-1e-10 or z>max(p[2] for p in points)+1e-10:continue
        hits=[]
        for a,b in zip(points,points[1:]+points[:1]):
            if abs(a[2]-z)<1e-10:hits.append(a[:2])
            if (a[2]-z)*(b[2]-z)<-1e-18:
                t=(z-a[2])/(b[2]-a[2]);hits.append(tuple(a[k]+t*(b[k]-a[k]) for k in range(2)))
        unique=[]
        for hit in hits:
            if not any(math.dist(hit,other)<1e-9 for other in unique):unique.append(hit)
        if len(unique)>=2:segments.append(max(((a,b) for a in unique for b in unique),key=lambda pair:math.dist(*pair)))
    return segments


def _radius(center,direction,segments):
    distances=[]
    for a,b in segments:
        edge=(b[0]-a[0],b[1]-a[1]);relative=(a[0]-center[0],a[1]-center[1]);denominator=_cross(direction,edge)
        if abs(denominator)<1e-12:continue
        distance=_cross(relative,edge)/denominator;along=_cross(relative,direction)/denominator
        if distance>1e-8 and -1e-8<=along<=1+1e-8:distances.append(distance)
    return min(distances) if distances else None


def _pose_report(positions,footwear,garment,joints,legs,upper_ids):
    """Finite sampled four-cardinal layering checks in the shared source rig."""
    cases=[(None,0.),('Walk',.125),('Walk',.25),('Walk',.375),('Walk',.625),('Walk',.75),('Walk',.875),('Sit',.25),('Lie',.25),('Soak',.25)]
    reports={}
    for clip,phase in cases:
        pants=deform_points(garment['positions'],garment['weights'],joints,clip=clip,phase=phase)
        shoe=deform_points(positions,footwear['weights'],joints,clip=clip,phase=phase)
        axes=(0,2) if clip=='Lie' else (0,1);gaps=[];misses=0
        for side,leg in legs.items():
            surfaces=[ProjectedSurface(pants,leg['faces'],axis,sign) for axis in axes for sign in (-1,1)]
            samples=[shoe[i] for i in upper_ids[side]]
            for face in footwear['faces']:
                ids=_ids(face)
                if not all(i in upper_ids[side] for i in ids):continue
                for fan in range(1,len(ids)-1):
                    tri=[shoe[i] for i in (ids[0],ids[fan],ids[fan+1])]
                    samples.append(tuple(sum(p[k] for p in tri)/3 for k in range(3)))
            for point in samples:
                for surface in surfaces:
                    depth,_=surface.depth_at(point)
                    if depth is None:misses+=1;continue
                    gaps.append(depth-point[surface.axis]*surface.front_sign)
        reports[(clip or 'Rest')+'_'+str(phase)]={'matched_cardinal_samples':len(gaps),'unmatched_cardinal_samples':misses,
            'minimum_trouser_over_cuff_clearance_source_m':min(gaps) if gaps else None,'outside_samples':sum(gap<-.00001 for gap in gaps),
            'finite':all(math.isfinite(v) for p in shoe for v in p)}
    return reports


def _motion_envelope_fit(adapted,footwear,garment,joints,legs,selected,upper_ids):
    """Retain the largest cuff radius hidden by all actual walk poses.

    Trousers and ankle linings have slightly different authored Foot/Shin
    blends. One smooth scalar contraction resolves their moving interface;
    its value is measured from the real posed surfaces, never an ellipse.
    """
    centers=list(adapted)
    for side,leg in legs.items():
        foot=joints['Foot_'+side];knee=joints['Shin_'+side]
        for i in selected[side]:
            x,y,z=adapted[i];blend=_smooth((z-leg['hem'])/.040)
            t=(z-foot[2])/(knee[2]-foot[2]);cx=foot[0]+t*(knee[0]-foot[0]);cy=foot[1]+t*(knee[1]-foot[1])
            centers[i]=(x+(cx-x)*blend,y+(cy-y)*blend,z)
    states=[]
    for clip,phase in [(None,0.),('Walk',.125),('Walk',.25),('Walk',.625),('Walk',.75),('Lie',.25)]:
        pants=deform_points(garment['positions'],garment['weights'],joints,clip=clip,phase=phase)
        outer=deform_points(adapted,footwear['weights'],joints,clip=clip,phase=phase)
        inner=deform_points(centers,footwear['weights'],joints,clip=clip,phase=phase)
        for side,leg in legs.items():
            samples=[(inner[i],outer[i]) for i in upper_ids[side]]
            for face in footwear['faces']:
                ids=_ids(face)
                if not all(i in upper_ids[side] for i in ids):continue
                for fan in range(1,len(ids)-1):
                    triangle=(ids[0],ids[fan],ids[fan+1])
                    samples.append((tuple(sum(inner[i][k] for i in triangle)/3 for k in range(3)),tuple(sum(outer[i][k] for i in triangle)/3 for k in range(3))))
            samples=[(a,tuple(b[k]-a[k] for k in range(3))) for a,b in samples]
            # Both horizontal cardinal axes remain valid projection checks
            # after Lie; include the rotated garment-front axis as well.
            axes=(0,1,2) if clip=='Lie' else (0,1)
            for axis in axes:
                for sign in (-1,1):states.append((ProjectedSurface(pants,leg['faces'],axis,sign),samples))
    target=.0005
    def clear(factor):
        for surface,samples in states:
            for center,vector in samples:
                point=tuple(center[k]+vector[k]*factor for k in range(3));depth,_=surface.depth_at(point)
                if depth is not None and depth-point[surface.axis]*surface.front_sign<target:return False
        return True
    if clear(1.):return adapted,1.,True
    low=0.;high=1.
    if not clear(0.):
        # Folded trousers do not provide a monotone radial visibility field:
        # a completely collapsed cuff can hit a seam/open projection even
        # when a small, nonzero cuff fits. Find a measured feasible bracket
        # rather than incorrectly declaring the source anatomy impossible.
        previous=1.;found=False
        for step in range(63,-1,-1):
            candidate=step/64
            if clear(candidate):low=candidate;high=previous;found=True;break
            previous=candidate
        if not found:return adapted,1.,False
    for iteration in range(12):
        middle=(low+high)/2
        if clear(middle):low=middle
        else:high=middle
    result=[tuple(centers[i][k]+(point[k]-centers[i][k])*low for k in range(3)) for i,point in enumerate(adapted)]
    return result,low,True


def fit_upper_cuff(footwear,garment,joints):
    """Return a new footwear dict; only ankle-lining XY positions may change.

    Complete main-shoe components are immutable even above the trouser hem.
    Below each actual trouser hem every lining vertex is immutable as well.
    A smooth 40 mm transition then fits the lining along rays intersecting the
    actual trouser cross-section, with a small internal layering allowance.
    """
    positions=footwear['positions'];groups={}
    for i,component in footwear['components'].items():groups.setdefault(component,[]).append(i)
    main=sorted(groups,key=lambda component:len(groups[component]),reverse=True)[:2]
    cuff=[component for component in groups if component not in main]
    if footwear['name'] not in ('shoes01','shoes05') or len(cuff)!=2 or any(len(groups[c])!=144 for c in cuff):
        raise ValueError('Upper-cuff fitting requires the checksum-verified shoes01/05 ankle topology')
    mesh,_,source_ids=geometry_for(garment,'pants');pant_faces=[tuple(source_ids[i] for i in face) for face in mesh[1]]
    legs={};selected={};upper_ids={}
    for side,sign in [('L',1),('R',-1)]:
        faces=[face for face in pant_faces if all(garment['positions'][i][0]*sign>0 for i in face)]
        local_faces=[face for face in faces if min(garment['positions'][i][2] for i in face)<.40]
        triangles=[(face[0],face[fan],face[fan+1]) for face in local_faces for fan in range(1,len(face)-1)]
        pant_ids={i for face in faces for i in face};hem=min(garment['positions'][i][2] for i in pant_ids)
        components=[c for c in cuff if sum(positions[i][0]*sign for i in groups[c])>0]
        ids={i for c in components for i in groups[c]};selected[side]=ids
        # The protected leather/sneaker upper extends above the lowest hem in
        # some outfits. It stays unchanged because it is a separate component.
        collar=max(positions[i][2] for c in main for i in groups[c] if positions[i][0]*sign>0)
        legs[side]={'faces':faces,'triangles':triangles,'hem':hem,'collar':collar}
        upper_ids[side]={i for i in ids if positions[i][2]>=max(hem+.040,.14)}
    before=_pose_report(positions,footwear,garment,joints,legs,upper_ids)
    adapted=list(positions);queries=0;missing=[];inset=.004
    # Positive/negative walking sine extrema in the current clip family are
    # the two distinct calf-to-foot relative transforms. Sit/Soak/Lie are
    # rigid-equivalent to rest for this local layering relationship.
    walking=[]
    for phase in (.25,.75):
        walking.append((deform_points(garment['positions'],garment['weights'],joints,clip='Walk',phase=phase),pose_transforms(joints,clip='Walk',phase=phase)))
    frame_cache={}
    for side,leg in legs.items():
        foot=joints['Foot_'+side];knee=joints['Shin_'+side]
        pant_ids={i for triangle in leg['triangles'] for i in triangle}
        for i in selected[side]:
            x,y,z=positions[i]
            if z<=leg['hem']:continue
            blend=_smooth((z-leg['hem'])/.040)
            t=(z-foot[2])/(knee[2]-foot[2]);center=(foot[0]+t*(knee[0]-foot[0]),foot[1]+t*(knee[1]-foot[1]))
            radial=(x-center[0],y-center[1]);length=math.hypot(*radial)
            if length<1e-9:continue
            direction=tuple(value/length for value in radial)
            radii=[]
            rest_radius=_radius(center,direction,_section(garment['positions'],leg['triangles'],z));queries+=1
            if rest_radius is not None:radii.append(rest_radius)
            row=tuple(sorted(footwear['weights'][i].items()))
            for case,(posed,transforms) in enumerate(walking):
                key=(side,row,case)
                if key not in frame_cache:frame_cache[key]=_source_frame(posed,pant_ids,dict(row),transforms)
                radius=_radius(center,direction,_section(frame_cache[key],leg['triangles'],z));queries+=1
                if radius is not None:radii.append(radius)
            if not radii:missing.append(i);continue
            radius=min(radii)
            limit=max(radius*.1,radius-inset);factor=min(1.,limit/length);factor=1.-blend*(1.-factor)
            adapted[i]=(center[0]+radial[0]*factor,center[1]+radial[1]*factor,z)
    adapted,motion_factor,motion_success=_motion_envelope_fit(adapted,footwear,garment,joints,legs,selected,upper_ids)
    after=_pose_report(adapted,footwear,garment,joints,legs,upper_ids)
    changed=[i for i,(a,b) in enumerate(zip(positions,adapted)) if math.dist(a,b)>1e-12]
    protected=[i for c in main for i in groups[c]]+[i for side,leg in legs.items() for i in selected[side] if positions[i][2]<=leg['hem']]
    report={'schema':'living_town.footwear_upper_cuff_fit.v1','method':'separate authored ankle-lining components fitted inside the intersection of exact rest/positive-walk/negative-walk trouser cross-sections in each cuff vertex skin frame; smooth hem transition',
        'source_units':'Blender XYZ metres normalized to1.665m stature; multiply by persona stature ratio for world lengths',
        'cuff_component_ids':cuff,'protected_main_shoe_component_ids':main,'protected_main_shoe_vertices':sum(len(groups[c]) for c in main),
        'protected_lower_z_m':min(leg['hem'] for leg in legs.values()),'panthem_bounds_m':{side:leg['hem'] for side,leg in legs.items()},
        'natural_main_shoe_collar_height_m':{side:leg['collar'] for side,leg in legs.items()},'transition_height_m':.040,'internal_inset_source_m':inset,
        'changed_vertices':len(changed),'changed_source_z_bounds_m':[min((positions[i][2] for i in changed),default=0.),max((positions[i][2] for i in changed),default=0.)],
        'maximum_displacement_source_m':max((math.dist(positions[i],adapted[i]) for i in changed),default=0.),
        'protected_vertex_maximum_displacement_m':max((math.dist(positions[i],adapted[i]) for i in protected),default=0.),
        'section_queries':queries,'unmatched_section_vertices':missing,'topology_uv_weights_z_preserved':True,'motion_envelope_radial_factor':motion_factor,'motion_envelope_target_source_m':.0005,'motion_envelope_success':motion_success,
        'before':before,'after':after,'success':all(row['finite'] and row['matched_cardinal_samples'] and not row['outside_samples'] for row in after.values()),
        'limitations':'Sampled four-cardinal trouser/cuff layering only; source topology and all main shoe components remain unchanged; native visual review required.'}
    return {**footwear,'positions':adapted,'upper_cuff_fit':report}
