"""Deterministic metric chair/sole contact for the shared presentation rig.

Rest data uses adapted Blender XYZ meters (+Z up). A seated shin counterturns
the thigh, leaving the shin and shoe in their rest orientation. This makes sole
height an analytic sinusoid of thigh pitch, rather than an engine-specific IK.
The caller retains authority over fixture anchors and simulation state.
"""
import math


def metrics_from_joints(joints,minimum_rest_shoe_sole_z=0.):
    """Return JSON-safe source metrics; sole Z may be scalar or per-side map."""
    pelvis=[float(v) for v in joints['PelvisRoot']]
    if len(pelvis)!=3 or not all(math.isfinite(v) for v in pelvis):raise ValueError('Invalid pelvis rest position')
    legs={}
    for side in ('L','R'):
        hip=[float(v) for v in joints['Thigh_'+side]];knee=[float(v) for v in joints['Shin_'+side]];ankle=[float(v) for v in joints['Foot_'+side]]
        sole=float(minimum_rest_shoe_sole_z.get(side,0.)) if isinstance(minimum_rest_shoe_sole_z,dict) else float(minimum_rest_shoe_sole_z)
        if any(len(p)!=3 or not all(math.isfinite(v) for v in p) for p in [hip,knee,ankle]) or not math.isfinite(sole):raise ValueError('Invalid leg rest metrics: '+side)
        legs[side]={'hip':hip,'knee':knee,'ankle':ankle,'minimum_rest_sole_z_m':sole,
                    'hip_from_pelvis_z_m':hip[2]-pelvis[2],
                    'knee_from_hip_y_m':knee[1]-hip[1],'knee_from_hip_z_m':knee[2]-hip[2],
                    'ankle_from_knee_z_m':ankle[2]-knee[2],'sole_from_ankle_z_m':sole-ankle[2]}
    return {'schema':'living_town.seat_kinematics.v1','source_coordinates':'Blender XYZ meters; +Z up; +Y front',
            'rest_pelvis':pelvis,'legs':legs,'constraints':'shin=-thigh; foot0; no root/fixture movement'}


def sole_height(metrics,side,thigh_radians,source_pelvis_height_m,*,scale=1.,root_floor_offset_m=0.):
    """Predict world sole Z for a thigh turn and exactly counterturned shin."""
    leg=metrics['legs'][side]
    local=(source_pelvis_height_m+leg['hip_from_pelvis_z_m']
           +leg['knee_from_hip_y_m']*math.sin(thigh_radians)+leg['knee_from_hip_z_m']*math.cos(thigh_radians)
           +leg['ankle_from_knee_z_m']+leg['sole_from_ankle_z_m'])
    return root_floor_offset_m+scale*local


def solve(metrics,seat_height_m=.462,scale=1.,root_floor_offset_m=0.,*,floor_height_m=0.,pelvis_clearance_source_m=.06,presentation_floor_reference_m=.025,minimum_pitch_radians=0.,maximum_pitch_radians=math.pi/2):
    """Solve each thigh pitch while preserving the caller's metric pelvis rule.

    Pelvis source height is ``seat_height_m/scale + .06 +
    (.025-root_floor_offset_m)/scale`` by default. The presentation reference
    keeps the same world hip/sole pose when a native export uses root0 and the
    game uses root25mm. It is coordinate compensation, not fixture movement.
    Returned gaps expose any unreachable/clamped result.
    """
    contact_allowance=float(metrics.get('pelvis_contact_allowance_m',0.))
    values=[seat_height_m,scale,root_floor_offset_m,floor_height_m,pelvis_clearance_source_m,presentation_floor_reference_m,minimum_pitch_radians,maximum_pitch_radians,contact_allowance]
    if not all(math.isfinite(v) for v in values) or scale<=0 or maximum_pitch_radians<minimum_pitch_radians:raise ValueError('Invalid seating dimensions/bounds')
    if contact_allowance<0:raise ValueError('Pelvis contact allowance must be nonnegative world meters')
    pelvis=seat_height_m/scale+pelvis_clearance_source_m+(presentation_floor_reference_m-root_floor_offset_m+contact_allowance)/scale;legs={};poses={};angles=[]
    policy=metrics.get('seating_policy','adult_grounded');dangling=policy=='child_natural_dangling'
    if policy not in ('adult_grounded','child_natural_dangling'):raise ValueError('Unknown seating policy: '+str(policy))
    for side in ('L','R'):
        leg=metrics['legs'][side];a=leg['knee_from_hip_y_m'];b=leg['knee_from_hip_z_m']
        constant=pelvis+leg['hip_from_pelvis_z_m']+leg['ankle_from_knee_z_m']+leg['sole_from_ankle_z_m']
        target=(floor_height_m-root_floor_offset_m)/scale-constant;radius=math.hypot(a,b);candidates=[]
        if radius>1e-12 and abs(target)<=radius+1e-12:
            alpha=math.acos(max(-1.,min(1.,target/radius)));phase=math.atan2(a,b)
            for sign in (-1,1):
                for turn in (-1,0,1):
                    angle=phase+sign*alpha+turn*math.tau
                    if minimum_pitch_radians-1e-10<=angle<=maximum_pitch_radians+1e-10:candidates.append(max(minimum_pitch_radians,min(maximum_pitch_radians,angle)))
        if dangling:
            # A shorter resident on an adult chair keeps the thigh anatomically
            # level; the positive sole gap is intentional, never forced closed.
            natural=math.atan2(-b,a)
            angle=max(minimum_pitch_radians,min(maximum_pitch_radians,natural))
            reachable=abs(angle-natural)<1e-9
        elif candidates:
            # The near-horizontal solution is the natural chair branch when
            # unusual rest knee offsets make the sinusoid yield two roots.
            angle=max(candidates);reachable=True
        else:
            bounds=[minimum_pitch_radians,maximum_pitch_radians]
            angle=min(bounds,key=lambda value:abs(sole_height(metrics,side,value,pelvis,scale=scale,root_floor_offset_m=root_floor_offset_m)-floor_height_m));reachable=False
        gap=sole_height(metrics,side,angle,pelvis,scale=scale,root_floor_offset_m=root_floor_offset_m)-floor_height_m
        legs[side]={'thigh_radians':angle,'shin_radians':-angle,'foot_radians':0.,'sole_gap_m':gap,'reachable':reachable,
                    'ground_contact_required':not dangling,'ground_contact_reachable':abs(gap)<1e-7,
                    'contact_status':'intentional_dangling' if dangling else 'grounded' if abs(gap)<1e-7 else 'unreachable_floor'}
        poses['Thigh_'+side]=(angle,0.,0.);poses['Shin_'+side]=(-angle,0.,0.);poses['Foot_'+side]=(0.,0.,0.);angles.append(angle)
    drape=sum(angles)/len(angles);poses['ApronDrape']=(drape,0.,0.);poses['ApronHem']=(-drape,0.,0.)
    return {'schema':'living_town.seated_contact_solution.v1','seat_height_m':seat_height_m,'floor_height_m':floor_height_m,
            'scale':scale,'root_floor_offset_m':root_floor_offset_m,'presentation_floor_reference_m':presentation_floor_reference_m,'source_pelvis_height_m':pelvis,'seating_policy':policy,'pelvis_contact_allowance_m':contact_allowance,
            'pelvis_world_height_m':root_floor_offset_m+scale*pelvis,'legs':legs,'apron_drape_radians':drape,
            'apron_hem_radians':-drape,'poses':poses,'reachable':all(leg['reachable'] for leg in legs.values()),
            'maximum_absolute_sole_gap_m':max(abs(leg['sole_gap_m']) for leg in legs.values())}


def poses_for(metrics,seat_height_m=.462,scale=1.,root_floor_offset_m=0.,**options):
    """Return named engine Euler overrides for pose_values/deform_points."""
    return solve(metrics,seat_height_m,scale,root_floor_offset_m,**options)['poses']
