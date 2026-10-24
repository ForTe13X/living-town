"""Deterministic clip curves shared by source baking and glTF export.

Angles are engine X/Y/Z Euler increments, model forward -Z and up +Y.
Walking has no root displacement: canonical navigation remains authoritative.
"""
import math
from .manifest import ANIMATED_JOINTS


def pose_values(clip,phase,*,seat_metrics=None,stature_scale=1.,root_floor_offset_m=0.):
    swing=math.sin(phase*math.tau)
    v={name:(0.,0.,0.) for name in ANIMATED_JOINTS}
    if clip=='Walk':
        for side,sign in [('L',1),('R',-1)]:
            step=swing*sign;v['Thigh_'+side]=(step*.47,0,0)
            v['Shin_'+side]=(-max(0,-step)*.66,0,0)
            v['Foot_'+side]=(-v['Thigh_'+side][0]-v['Shin_'+side][0],0,0)
            v['UpperArm_'+side]=(-step*.33,0,0);v['Forearm_'+side]=(.13+max(0,step)*.12,0,0)
        v['ApronDrape']=(abs(swing)*.50,0,0)
    elif clip in ('Sit','Soak'):
        for side in ('L','R'):
            v['Thigh_'+side]=(math.pi/2,0,0);v['Shin_'+side]=(-math.pi/2,0,0);v['Forearm_'+side]=(.63,0,0)
        v['ApronDrape']=(math.pi/2,0,0)
        v['ApronHem']=(-math.pi/2,0,0)
        if clip=='Sit' and seat_metrics:
            from .seating import poses_for
            v.update(poses_for(seat_metrics,.462,stature_scale,root_floor_offset_m))
    elif clip=='Lie':v['PelvisRoot']=(math.pi/2,0,0)
    elif clip=='Work':
        for side,sign in [('L',1),('R',-1)]:
            v['UpperArm_'+side]=(.32+sign*swing*.06,0,0);v['Forearm_'+side]=(.75+sign*swing*.12,0,0)
    elif clip=='Talk':v['UpperArm_R']=(.2+swing*.10,0,-.12);v['Forearm_R']=(.75+swing*.12,0,0)
    v['HeadPivot']=(.008*swing,0,.008*math.cos(phase*math.tau))
    if clip=='Idle':v['BodyPivot']=(.004*swing,0,0)
    return v


def pelvis_height(clip,phase,rest_height,leg_length,*,seat_metrics=None,stature_scale=1.,root_floor_offset_m=0.):
    if clip=='Walk':return rest_height-leg_length*(1-math.cos(math.sin(phase*math.tau)*.47))
    if clip=='Sit':return .462/stature_scale+.06+(.025-root_floor_offset_m+float(seat_metrics.get('pelvis_contact_allowance_m',0.)))/stature_scale if seat_metrics else .52
    if clip=='Soak':return (.36+.025-root_floor_offset_m)/stature_scale if seat_metrics else .36
    if clip=='Lie':return .65
    return rest_height
