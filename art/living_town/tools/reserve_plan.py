"""Deterministic metric reserve masterplan; pure Python, no Blender dependency.

The existing terrain module remains authoritative inside CORE_RECT.  Outside
that rectangle this module adds finite granite relief, engineered amenity pads
and graded trails.  Import ``design_height`` for the new reserve mesh/props;
do not make terrain_profile.py import this module (the dependency is one way).

Run this file to write only reserve_plan.json and reserve planning diagrams.
The optional Pillow dependency is used only to rasterize the planning plate.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import math
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE_RECT = (-75., -65., 70., 65.)
BOUNDS = (-600., -340., 66., 500.)
WATER_Z = -.88
INDEX_CELL = 24.
GRADE_EDGE_EXTENSION_M = 2.
PLAN = None
_PADS = []
_PAD_INDEX = defaultdict(list)
_ROADS = []
_ROAD_INDEX = defaultdict(list)
_STAIR_CUTS = []
_STAIR_CUT_INDEX = defaultdict(list)
_ROUTE_NODES = {}
_JUNCTION_APRONS = []

_spec = importlib.util.spec_from_file_location('reserve_existing_terrain', ROOT/'tools/terrain_profile.py')
CORE = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(CORE)
MASTER = json.loads((ROOT/'masterplan.json').read_text(encoding='utf-8'))

HILLS = [
    {'id':'western_granite_upland','center_m':[-405,150],'radii_m':[175,195],'amplitude_m':31},
    {'id':'north_forest_dome','center_m':[-255,340],'radii_m':[128,125],'amplitude_m':33},
    {'id':'south_heath_hill','center_m':[-340,-180],'radii_m':[145,110],'amplitude_m':22},
    {'id':'coastal_north_foothill','center_m':[-65,235],'radii_m':[88,155],'amplitude_m':13},
]
RIDGES = [
    {'id':'west_spine','points_xy':[[-475,-55],[-455,65],[-425,190],[-355,300]],'radius_m':65.,'amplitude_m':13.},
    {'id':'north_east_shoulder','points_xy':[[-275,365],[-185,340],[-110,275]],'radius_m':55.,'amplitude_m':8.},
]
RAVINES = [
    {'id':'fern_brook_ravine','points_xy':[[-235,-130],[-250,-50],[-265,45],[-285,140],[-250,230]],'half_width_m':15.,'depth_m':14.,'end_blend_m':42.,'water':'intermittent dry gravel/sedge bed; no unverified permanent stream'},
    {'id':'granite_cleft','points_xy':[[-372,55],[-347,120],[-320,200]],'half_width_m':5.5,'depth_m':8.,'end_blend_m':25.,'water':'dry exposed granite cleft'},
]


def clamp(x, a, b):
    return max(a, min(b, x))


def smooth(t):
    t=clamp(t,0.,1.)
    return t*t*(3-2*t)


def project(p, a, b):
    dx,dy=b[0]-a[0],b[1]-a[1]
    ll=dx*dx+dy*dy
    t=clamp(((p[0]-a[0])*dx+(p[1]-a[1])*dy)/ll,0.,1.) if ll else 0.
    return t, math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy)


def rect_distance(x,y,rect):
    x0,y0,x1,y1=rect
    return math.hypot(max(x0-x,0.,x-x1),max(y0-y,0.,y-y1))


def polyline_distance(x,y,points):
    return min(project((x,y),a,b)[1] for a,b in zip(points,points[1:]))


def core_mask(x,y):
    return smooth(rect_distance(x,y,CORE_RECT)/55.)


def natural_height(x,y):
    """Unengineered reserve relief, with exact original ground in core."""
    if rect_distance(x,y,CORE_RECT)==0:
        return CORE.design_height(x,y)
    relief=0.
    for h in HILLS:
        cx,cy=h['center_m'];rx,ry=h['radii_m']
        relief+=h['amplitude_m']*math.exp(-((x-cx)/rx)**2-((y-cy)/ry)**2)
    for r in RIDGES:
        dist=polyline_distance(x,y,r['points_xy'])
        relief+=r['amplitude_m']*math.exp(-(dist/r['radius_m'])**2)
    # Small coherent swells, not white-noise displacement.
    relief+=1.1*math.sin(x*.023+y*.006)*math.sin(y*.019)*math.exp(-((x+290)/340)**4-((y-75)/440)**4)
    for r in RAVINES:
        pts=r['points_xy'];d=polyline_distance(x,y,pts)
        end=min(math.dist((x,y),pts[0]),math.dist((x,y),pts[-1]))
        relief-=r['depth_m']*math.exp(-(d/r['half_width_m'])**2)*smooth(end/r['end_blend_m'])
    # A wide outer transition meets the existing coarse apron without a cliff.
    x0,y0,x1,y1=BOUNDS
    outer=min(x-x0,y-y0,y1-y)
    return CORE.engineered_height(x,y)+core_mask(x,y)*smooth(outer/65.)*relief


def index_rect(index, ident, bounds):
    x0,y0,x1,y1=bounds
    for i in range(math.floor(x0/INDEX_CELL),math.floor(x1/INDEX_CELL)+1):
        for j in range(math.floor(y0/INDEX_CELL),math.floor(y1/INDEX_CELL)+1):
            index[i,j].append(ident)


def pad_distance(x,y,p):
    a=math.radians(p.get('yaw_degrees',0));co,si=math.cos(a),math.sin(a)
    dx,dy=x-p['center'][0],y-p['center'][1]
    lx,ly=dx*co+dy*si,-dx*si+dy*co
    return math.hypot(max(abs(lx)-p['width']/2,0),max(abs(ly)-p['depth']/2,0))


def pad_height(x,y):
    z=natural_height(x,y)
    nearest=None;blends=[]
    key=(math.floor(x/INDEX_CELL),math.floor(y/INDEX_CELL))
    for i in _PAD_INDEX.get(key,()):
        p=_PADS[i];d=pad_distance(x,y,p)
        if d>p['blend_m']:continue
        score=(d,p.get('priority',1),p['id'])
        if nearest is None or score<nearest[0]:nearest=(score,p,d)
        blends.append((p,d))
    if nearest:
        _,p,d=nearest;t=1-smooth(d/p['blend_m'])
        if d<1e-9:return p['level_m']
        # Smooth the overlap of two terrace shoulders. A nearest-owner switch
        # between unlike terrace levels would create an accidental ground
        # discontinuity; inverse-distance blending converges to each true
        # flat pad at its own boundary.
        weights=[((1-smooth(dd/pp['blend_m']))/(dd+.02)**4,pp['level_m']) for pp,dd in blends]
        total=sum(w for w,_ in weights)
        target=sum(w*h for w,h in weights)/total if total else p['level_m']
        z=z*(1-t)+target*t
    return z


def design_height(x,y):
    """One finished-ground authority; exact core, graded reserve pads/trails.

    Bridge spans retain the ravine. Stone stair flights/landings have a
    cut-only supporting channel beneath their unchanged walking elevations.
    """
    if rect_distance(x,y,CORE_RECT)==0:
        return CORE.design_height(x,y)
    _ensure_plan()
    z=pad_height(x,y)
    key=(math.floor(x/INDEX_CELL),math.floor(y/INDEX_CELL))
    best=None
    for i in _ROAD_INDEX.get(key,()):
        a,b,half,shoulder,ident=_ROADS[i]
        t,d=project((x,y),a,b)
        if d>half+GRADE_EDGE_EXTENSION_M+shoulder:continue
        score=(d-half,ident)
        if best is None or score<best[0]:best=(score,a,b,t,d,half,shoulder)
    if best:
        _,a,b,t,d,half,shoulder=best
        # A two-metre fully graded verge beyond each visible path edge keeps
        # coarse reserve-mesh cell corners on the engineered road profile.
        # The displayed trail width and its declared centreline remain exact.
        weight=1-smooth((d-half-GRADE_EDGE_EXTENSION_M)/shoulder)
        target=a[2]+(b[2]-a[2])*t-.012*min(d,half)
        z=z*(1-weight)+target*weight
    # The short hub/camp retaining wall is an intentional engineered step.
    # Overlapping pad shoulders and trail shoulders must not lift its lower
    # face or leave either wall toe hanging. Ground inside the solid wall
    # thickness is interpolated; both exposed faces meet exact terrace levels.
    for edge in PLAN.get('site_earthworks',{}).get('retaining_edges',[]):
        a,b=edge['points_xy'];dx,dy=b[0]-a[0],b[1]-a[1]
        length=math.hypot(dx,dy);ux,uy=dx/length,dy/length
        along=(x-a[0])*ux+(y-a[1])*uy
        normal=-(x-a[0])*uy+(y-a[1])*ux
        beyond=max(-along,0.,along-length)
        half=edge['thickness_m']/2
        full=edge['ground_profile']['face_flat_distance_m']
        outer=edge['ground_profile']['normal_blend_extent_m']
        weight=(1-smooth((abs(normal)-full)/(outer-full)))*(1-smooth(beyond/edge['ground_profile']['end_blend_m']))
        if weight:
            side=clamp((normal+half)/(2*half),0.,1.)
            target=edge['upper_level_m']*(1-side)+edge['lower_level_m']*side
            z=z*(1-weight)+target*weight
    return stair_cut_height(x,y,z)


def stair_cut_height(x,y,z):
    """Excavate below the exact stair profile, never raise existing ground."""
    for index in _STAIR_CUT_INDEX.get((math.floor(x/INDEX_CELL),math.floor(y/INDEX_CELL)),()):
        cut=_STAIR_CUTS[index];a=cut['start_m'];ux,uy=cut['axis_xy'];length=cut['length_m']
        along=(x-a[0])*ux+(y-a[1])*uy;lateral=abs(-(x-a[0])*uy+(y-a[1])*ux)
        beyond=max(-along,0.,along-length)
        weight=(1-smooth((lateral-cut['full_half_width_m'])/cut['bank_blend_m']))*(1-smooth(beyond/cut['end_blend_m']))
        if weight<=0:continue
        # Preserve neighboring trail roadbeds while cutting the stair's bank.
        # Flat end caps matter: a circular cap behind a stair endpoint would
        # reinstate the high approach ground over its descending treads.
        road_protection=0.
        if not (0.<=along<=length and lateral<=cut['full_half_width_m']):
            for road in _ROAD_INDEX.get((math.floor(x/INDEX_CELL),math.floor(y/INDEX_CELL)),()):
                p,q,half,_,_= _ROADS[road];dx,dy=q[0]-p[0],q[1]-p[1];ll=dx*dx+dy*dy
                t=((x-p[0])*dx+(y-p[1])*dy)/ll
                if t<0. or t>1.:continue
                distance=abs((x-p[0])*dy-(y-p[1])*dx)/math.sqrt(ll)
                road_protection=max(road_protection,1-smooth((distance-half-.35)/1.5))
            if 0.<=along<=length:road_protection*=smooth((lateral-cut['full_half_width_m'])/.6)
        weight*=1-road_protection
        if weight<=0:continue
        station=clamp(along,0.,length);level=None
        for start,end,za,zb in cut['profile']:
            if station<=end+1e-7:
                t=clamp((station-start)/(end-start),0.,1.) if end>start else 0.
                level=za+(zb-za)*t;break
        if level is None:level=cut['profile'][-1][3]
        # Meet each existing approach at its exact datum. Inside the flight,
        # clearance leaves the land below every tread and landing edge.
        clearance=cut['clearance_m']*smooth(min(station,length-station)/cut['end_clearance_taper_m'])
        target=level-clearance
        if target<z:z+=(target-z)*weight
    return z


def _index_stair_cuts(stairs):
    _STAIR_CUTS.clear();_STAIR_CUT_INDEX.clear()
    for stair in stairs:
        a,b=stair['points_m'];length=math.dist(a[:2],b[:2]);ux,uy=(b[0]-a[0])/length,(b[1]-a[1])/length
        spec=stair['ground_cut'];profile=[]
        for part in stair['flights']+stair.get('landings',[]):
            p,q=part['points_m'];start=(p[0]-a[0])*ux+(p[1]-a[1])*uy;end=(q[0]-a[0])*ux+(q[1]-a[1])*uy
            profile.append((start,end,p[2],q[2]))
        profile.sort()
        cut=dict(spec,id=stair['id'],start_m=a,axis_xy=[ux,uy],length_m=length,profile=profile,
                 full_half_width_m=stair['width_m']/2+spec['clear_margin_m'])
        _STAIR_CUTS.append(cut)
        r=cut['full_half_width_m']+cut['bank_blend_m']+cut['end_blend_m']
        index_rect(_STAIR_CUT_INDEX,len(_STAIR_CUTS)-1,(min(a[0],b[0])-r,min(a[1],b[1])-r,max(a[0],b[0])+r,max(a[1],b[1])+r))


def resample(points,spacing=4.):
    out=[list(points[0][:2])]
    for a,b in zip(points,points[1:]):
        n=max(1,math.ceil(math.dist(a[:2],b[:2])/spacing))
        out.extend([[a[k]+(b[k]-a[k])*i/n for k in (0,1)] for i in range(1,n+1)])
    return out


def poly_length(points):
    return sum(math.dist(a[:2],b[:2]) for a,b in zip(points,points[1:]))


def organic_controls(points,closed=False):
    """Catmull-Rom outside the core; passes every original junction exactly."""
    unique=points[:-1] if closed and points[0]==points[-1] else points
    out=[list(unique[0])]
    count=len(unique)
    segments=count if closed else count-1
    for i in range(segments):
        p1=unique[i];p2=unique[(i+1)%count]
        if min(rect_distance(*p1,CORE_RECT),rect_distance(*p2,CORE_RECT))<15:
            out.append(list(p2));continue
        p0=unique[(i-1)%count] if closed or i>0 else p1
        p3=unique[(i+2)%count] if closed or i+2<count else p2
        n=max(2,math.ceil(math.dist(p1,p2)/7))
        for j in range(1,n+1):
            t=j/n
            out.append([.5*((2*p1[k])+(-p0[k]+p2[k])*t+(2*p0[k]-5*p1[k]+4*p2[k]-p3[k])*t*t+(-p0[k]+3*p1[k]-3*p2[k]+p3[k])*t*t*t) for k in (0,1)])
    return out


def graded_path(ident, controls, kind='walking_trail',width=2.,max_grade=.08,closed=False,core_reuse=False,start_landing_length=0.):
    pts=resample(controls,3.)
    # Exact quay-boundary stations prevent a midpoint classification from
    # skipping an unpaved half-segment immediately outside the harbor deck.
    split=[pts[0]]
    for a,b in zip(pts,pts[1:]):
        hits=[]
        for axis,level in ((0,31.),(0,66.),(1,37.),(1,55.)):
            delta=b[axis]-a[axis]
            if abs(delta)<1e-12:continue
            t=(level-a[axis])/delta
            if not 1e-9<t<1-1e-9:continue
            q=[a[k]+(b[k]-a[k])*t for k in (0,1)]
            if 30.9<=q[0]<=66.1 and 36.9<=q[1]<=55.1:hits.append((t,q))
        split.extend(q for _,q in sorted(hits));split.append(b)
    pts=split
    # Rectangular ribbons overlap briefly at a turn or a shared trail node.
    # Give both incident profiles the same short level apron, rather than
    # allowing a higher neighboring strip to create a ray-height jump.
    aprons=[]
    lengths=[0.]
    for a,b in zip(pts,pts[1:]):lengths.append(lengths[-1]+math.dist(a,b))
    for apron in _JUNCTION_APRONS:
        if ident not in apron['routes']:continue
        node=min(range(len(pts)),key=lambda i:math.dist(pts[i],apron['center_m']))
        if math.dist(pts[node],apron['center_m'])>1e-4:raise ValueError('level apron is not a real route node: '+ident+'/'+apron['id'])
        aprons.append((apron,lengths[node]))
    if aprons:
        cuts={s for apron,center in aprons for s in (max(0.,center-apron['radius_m']),min(lengths[-1],center+apron['radius_m']))}
        split=[pts[0]]
        for i,(a,b) in enumerate(zip(pts,pts[1:])):
            for station in sorted(s for s in cuts if lengths[i]+1e-7<s<lengths[i+1]-1e-7):
                t=(station-lengths[i])/(lengths[i+1]-lengths[i])
                split.append([a[k]+(b[k]-a[k])*t for k in (0,1)])
            split.append(b)
        pts=split
    heights=[pad_height(*p) for p in pts]
    # Fixed original core stations. Reserve profile is the closest feasible
    # neighbor-limited surface; repeated projection enforces both directions.
    fixed=[rect_distance(*p,CORE_RECT)==0 or any(pad_distance(*p,q)<1e-9 for q in _PADS) for p in pts]
    for i,p in enumerate(pts):
        key=tuple(round(v,5) for v in p)
        if key in _ROUTE_NODES:
            heights[i]=_ROUTE_NODES[key];fixed[i]=True
    if start_landing_length:
        distance=0.;level=heights[0]
        for i,p in enumerate(pts):
            if i:distance+=math.dist(pts[i-1],p)
            if distance<=start_landing_length+1e-6:heights[i]=level;fixed[i]=True
    raw=heights[:]
    def relax():
        for _ in range(160):
            before=heights[:]
            for indices in (range(1,len(pts)),range(len(pts)-2,-1,-1)):
                for i in indices:
                    j=i-1 if indices.step==1 else i+1
                    if fixed[i]:continue
                    delta=max_grade*math.dist(pts[i],pts[j])
                    heights[i]=clamp(heights[i],heights[j]-delta,heights[j]+delta)
            if closed:
                zz=(heights[0]+heights[-1])/2
                if not fixed[0]:heights[0]=zz
                if not fixed[-1]:heights[-1]=zz
            if max(abs(a-b) for a,b in zip(before,heights))<1e-8:break
    relax()
    lengths=[0.]
    for a,b in zip(pts,pts[1:]):lengths.append(lengths[-1]+math.dist(a,b))
    for apron,center in aprons:
        node=min(range(len(pts)),key=lambda i:abs(lengths[i]-center))
        if apron['level_m'] is None:apron['level_m']=round(heights[node],6)
        for i,station in enumerate(lengths):
            if abs(station-center)<=apron['radius_m']+1e-7:
                heights[i]=apron['level_m'];fixed[i]=True
    if aprons:relax()
    record={'id':ident,'kind':kind,'width_m':width,'points_m':[[round(p[0],5),round(p[1],5),round(z,6)] for p,z in zip(pts,heights)],'control_points_xy':controls,'closed':closed,'grade_limit':max_grade,'surface':'compacted warm granite fines' if kind!='service_access' else 'permeable reinforced gravel','core_reuse':core_reuse,'shoulder_m':4. if kind=='jogging_belt' else 2.5,'maximum_cut_fill_m':round(max(abs(a-b) for a,b in zip(raw,heights)),4)}
    if start_landing_length:record['stair_endpoint_landing_length_m']=start_landing_length
    record['length_m']=round(poly_length(pts),3)
    record['maximum_grade']=round(max((abs(b[2]-a[2])/math.dist(a[:2],b[:2]) for a,b in zip(record['points_m'],record['points_m'][1:]) if math.dist(a[:2],b[:2])>1e-8),default=0.),7)
    record['grading_edge_extension_m']=GRADE_EDGE_EXTENSION_M
    record['fully_graded_width_m']=width+2*GRADE_EDGE_EXTENSION_M
    record['level_aprons']=[{'id':a['id'],'center_m':a['center_m'],'radius_m':a['radius_m'],'level_m':a['level_m']} for a,_ in aprons]
    record['segments']=[{'kind':'ground','points_m':record['points_m'],'core_reuse':core_reuse}]
    # An overall belt includes both reserve land and unchanged town streets.
    # Split at the preservation boundary so consumers never duplicate paving
    # across the original town simply because one route also has forest legs.
    groups=[]
    for a,b in zip(record['points_m'],record['points_m'][1:]):
        reuse=False
        if rect_distance(*a[:2],CORE_RECT)==0 and rect_distance(*b[:2],CORE_RECT)==0:
            length=math.dist(a[:2],b[:2]);nx,ny=-(b[1]-a[1])/length,(b[0]-a[0])/length
            def actual_paved(x,y):
                if 31<=x<=66 and 37<=y<=55:return True
                for road in MASTER['streets']:
                    for s,t in zip(road['points'],road['points'][1:]):
                        dx,dy=t[0]-s[0],t[1]-s[1];ll=dx*dx+dy*dy
                        raw=((x-s[0])*dx+(y-s[1])*dy)/ll
                        if -1e-8<=raw<=1+1e-8 and abs((x-s[0])*dy-(y-s[1])*dx)/math.sqrt(ll)<=road['width']/2-.025:return True
                return False
            reuse=all(actual_paved(a[0]+(b[0]-a[0])*t+nx*side*width/2,a[1]+(b[1]-a[1])*t+ny*side*width/2)
                      for t in (0.,.25,.5,.75,1.) for side in(-1,0,1))
        if groups and groups[-1]['core_reuse']==reuse:groups[-1]['points_m'].append(b)
        else:groups.append({'kind':'ground','points_m':[a,b],'core_reuse':reuse})
    record['segments']=groups
    for p in record['points_m']:_ROUTE_NODES[tuple(p[:2])]=p[2]
    return record


def add_pad(ident,center,width,depth,level=None,yaw=0,blend=4,priority=1,use='graded facility pad'):
    p={'id':ident,'center':list(center),'center_m':list(center),'width':width,'depth':depth,'size_m':[width,depth],'yaw_degrees':yaw,'level_m':round(natural_height(*center) if level is None else level,6),'blend_m':blend,'priority':priority,'use':use}
    _PADS.append(p)
    r=math.hypot(width,depth)/2+blend
    index_rect(_PAD_INDEX,len(_PADS)-1,(center[0]-r,center[1]-r,center[0]+r,center[1]+r))
    return p


def building(ident,kind,center,w,d,yaw=0,program=None,level=None,**extra):
    p=add_pad(ident+'_pad',center,w+1.2,d+1.2,level,yaw,1.2,0,'level foundation/door apron')
    return {'id':ident,'kind':kind,'use':kind.replace('_',' '),'center':list(center),'center_m':list(center),'width':w,'depth':d,'size_m':[w,d],'floors':1,'yaw_degrees':yaw,'pad_id':p['id'],'pad_level_m':p['level_m'],'finished_floor_offset_m':.45 if kind=='trailer' else .18,'entry_local':[0,-d/2],'program':program or [],**extra}


def _index_paths(paths):
    _ROADS.clear();_ROAD_INDEX.clear()
    for p in paths:
        if p['kind'] in ('bridge','stairs'):continue
        for a,b in zip(p['points_m'],p['points_m'][1:]):
            if math.dist(a[:2],b[:2])<1e-8:continue
            if rect_distance(*a[:2],CORE_RECT)==0 and rect_distance(*b[:2],CORE_RECT)==0:continue
            half=p['width_m']/2;s=p['shoulder_m']
            _ROADS.append((a,b,half,s,p['id']))
            r=half+s+GRADE_EDGE_EXTENSION_M
            index_rect(_ROAD_INDEX,len(_ROADS)-1,(min(a[0],b[0])-r,min(a[1],b[1])-r,max(a[0],b[0])+r,max(a[1],b[1])+r))


def _ensure_plan():
    global PLAN
    if PLAN is None:PLAN=make_plan()


def make_plan():
    global PLAN
    _PADS.clear();_PAD_INDEX.clear()
    _ROUTE_NODES.clear()
    _JUNCTION_APRONS.clear()
    hub_z=natural_height(-116,-64)
    camp_z=natural_height(-178,-116)
    _JUNCTION_APRONS.extend([
        {'id':'Reserve_Loop_Ridge_Level_Junction','center_m':[-485,-150],'radius_m':2.75,'level_m':None,'routes':['Reserve_Jogging_Belt','Reserve_West_Ridge_Trail']},
        {'id':'Reserve_Gateway_Level_Corner','center_m':[-149,-68],'radius_m':2.75,'level_m':round(hub_z,6),'routes':['Reserve_Town_West_Gateway']},
        {'id':'Reserve_Camp_Level_Corner','center_m':[-143,-143],'radius_m':2.75,'level_m':round(camp_z,6),'routes':['Reserve_Camp_Access','Reserve_Camp_Perimeter']},
        {'id':'Reserve_Fern_East_Level_Landing','center_m':[-245,45],'radius_m':2.75,'level_m':None,'routes':['Reserve_Fern_Bridge_East','Reserve_Ravine_Stone_Stair_Lower_Link']},
    ])
    add_pad('visitor_hub_terrace',[-116,-64],57,46,hub_z,blend=12,priority=2,use='visitor forecourt and service building terrace')
    add_pad('campground_terrace',[-178,-116],72,58,camp_z,blend=25,priority=2,use='twelve-pitch serviced trailer court; permeable, no ungraded pitches')
    buildings=[
        building('Reserve_Visitor_Reception','visitor_reception',[-130,-50],9,7,program=['information/reception','first aid and ranger desk','map display','locked equipment store'],level=hub_z),
        building('Reserve_Convenience','convenience_store',[-116,-50],10,7,program=['grocery aisles','counter and cold drinks','stock room'],level=hub_z),
        building('Reserve_Souvenir','souvenir_store',[-102,-50],9,7,program=['local craft and reserve interpretation','checkout','stock room'],level=hub_z),
        building('Reserve_Bathhouse','public_bathhouse',[-137,-78],14,9,90,program=['dry changing and lockers','six private shower cubicles','wash basins','accessible shower/changing','plant and cleaning room'],level=hub_z),
        building('Reserve_Public_Toilets','public_toilets',[-111,-78],7,5,180,program=['private WC cubicles','larger accessible WC','handwashing vestibule','cleaning cupboard'],level=hub_z),
        building('Reserve_Food_Truck','food_truck',[-99,-68],7,2.6,90,program=['sandwich/hotdog preparation','separate handwash and food sink','cold storage','side serving hatch','fold-out awning and menu'],level=hub_z),
        building('Reserve_Laundry','laundry',[-137,-99],8,6,-90,program=['washer/dryer stations','folding counter','utility sink','cleaning store'],level=camp_z),
        building('Reserve_Maintenance','maintenance',[-137,-113],7,5,-90,program=['workbench','tool wall','reserve equipment store','locked electrical cabinet'],level=camp_z),
        building('Reserve_Refuse_Service','refuse_service',[-137,-127],6,4,-90,program=['screened sorting bins','sealed service cabinet'],level=camp_z),
    ]
    truck=next(b for b in buildings if b['kind']=='food_truck')
    truck['entry_local']=[2.85,-1.3]
    truck['service_hatch_local_center_x_m']=-.25
    truck['service_hatch_width_m']=3.4
    for row,y,yaw in [('N',-103,0),('S',-128,180)]:
        for i,x in enumerate([-203,-193,-183,-173,-163,-153]):
            n=i+(0 if row=='N' else 6)
            buildings.append(building(f'Reserve_Trailer_{row}{i+1:02d}','trailer',[x,y],3.3,8.4,yaw,program=['end living/dining','galley kitchen','private wet bathroom','rear sleeping compartment'],level=camp_z,layout_variant=['double','twin','family_bunk','lounge_sleeper'][n%4],mirrored=bool(n%2),pitch_id=f'Pitch_{row}{i+1:02d}'))
    paths=[]
    seaside=next(p['points'] for p in MASTER['streets'] if p['id']=='seaside')
    # Enter the quay from inland, with the entire2.4m ribbon on grass/quay.
    # Its north/south traverses also clear the warehouse and quay outer edge.
    jogging=[[-88,-58],[-115,-160],[-220,-235],[-355,-240],[-485,-150],[-545,-20],[-535,125],[-470,270],[-340,395],[-200,425],[-80,345],[-25,220],[8,125],[15,80],[38,63],[39,59],[39,53.5],[55,53.5],[55,39.5],[43,39.5],[43,35]]+list(reversed(seaside))[1:]+[[38,-56],[35,-65],[20,-77],[-20,-92],[-60,-105],[-88,-90],[-88,-58]]
    paths.append(graded_path('Reserve_Jogging_Belt',organic_controls(jogging,True),'jogging_belt',2.4,.075,True,True))
    paths.append(graded_path('Reserve_Town_West_Gateway',[[-58,-25],[-78,-18],[-100,-25],[-140,-33],[-149,-48],[-149,-68],[-129,-68]],width=2.5))
    paths.append(graded_path('Reserve_Hub_Spine',[[-88,-58],[-102,-62],[-116,-64],[-129,-68]],'service_access',3.5,.06))
    paths.append(graded_path('Reserve_Hub_Forecourt',[[-134,-62],[-116,-62],[-102,-62],[-94,-62]],width=2.0,max_grade=.06))
    paths.append(graded_path('Reserve_Hub_Forecourt_Link',[[-116,-62],[-116,-64]],width=2.0,max_grade=.06))
    paths.append(graded_path('Reserve_Camp_Access',[[-129,-68],[-123,-88],[-123,-136],[-143,-143],[-143,-116],[-211,-116]],'service_access',3.5,.06))
    paths.append(graded_path('Reserve_Camp_Perimeter',[[-143,-116],[-143,-143],[-212,-143],[-212,-89],[-143,-89],[-143,-116]],width=1.8,closed=True))
    # Precise threshold links; no core geometry remapping or arbitrary rescue.
    for b in buildings:
        a=math.radians(b['yaw_degrees']);lx,ly=b['entry_local'];cx,cy=b['center']
        entry=[cx+lx*math.cos(a)-ly*math.sin(a),cy+lx*math.sin(a)+ly*math.cos(a)]
        b['entry_threshold_m']=[*entry,round(b['pad_level_m']+b['finished_floor_offset_m'],6)]
        if b['kind']=='trailer':end=[cx,-116]
        elif b['id'] in ('Reserve_Laundry','Reserve_Maintenance','Reserve_Refuse_Service'):end=[-143,cy]
        elif b['kind']=='public_bathhouse':end=[-129,-68]
        elif b['kind']=='public_toilets':end=[cx,-62]
        elif b['kind']=='food_truck':end=[-94,-62]
        else:end=[cx,-62]
        paths.append(graded_path(b['id']+'_Approach',[entry,end],width=1.5,max_grade=.08))
    # Two actual crevice crossings, with separate supported walking decks.
    bridges=[]
    for ident,a,b,width in [
        ('Reserve_Fern_Ravine_Bridge',[-285,45],[-245,45],2.2),
        ('Reserve_Granite_Cleft_Bridge',[-360,120],[-334,120],1.8),
    ]:
        deck=max(natural_height(*a),natural_height(*b))+.12
        for suffix,p in [('W',a),('E',b)]:add_pad(ident+'_'+suffix+'_landing',p,4.5,4.5,deck,blend=4,priority=0,use='bridge abutment landing')
        bridges.append({'id':ident,'points_m':[[*a,round(deck,6)],[*b,round(deck,6)]],'width_m':width,'deck_thickness_m':.24,'railing_height_m':1.15,'structure':'timber deck on granite abutments; discreet intermediate trestles for long span' if math.dist(a,b)>30 else 'short timber/steel footbridge on granite abutments','ravine_id':'fern_brook_ravine' if 'Fern' in ident else 'granite_cleft','minimum_ground_clearance_m':None})
        for p in (a,b):_ROUTE_NODES[tuple(float(v) for v in p)]=round(deck,6)
    scenic=[
        ('Reserve_West_Ridge_Trail',[[-485,-150],[-470,-60],[-455,45],[-425,145],[-390,240],[-340,320],[-340,395]]),
        ('Reserve_Fern_Bridge_West',[[-455,45],[-400,15],[-345,20],[-310,15],[-285,45]]),
        ('Reserve_Fern_Bridge_East',[[-245,45],[-200,38],[-145,43],[-95,50],[-65,55],[15,80]]),
        ('Reserve_Cleft_Bridge_West',[[-425,145],[-410,165],[-380,160],[-390,140],[-360,120]]),
        ('Reserve_Cleft_Bridge_East',[[-334,120],[-310,155],[-300,200],[-270,255],[-200,310],[-200,425]]),
        ('Reserve_South_Meadow_Trail',[[-115,-160],[-170,-170],[-230,-165],[-300,-145],[-355,-240]]),
        ('Reserve_North_Meadow_Link',[[-200,310],[-174,310],[-145,350],[-120,315],[-85,285],[-95,245],[-60,235],[-25,220]]),
    ]
    paths.extend(graded_path(i,p,'scenic_trail',1.6,.12) for i,p in scenic)
    # Upper and lower end elevations are sampled from the same terrain;
    # calculated flights use >=.28m going and <=.17m rise, with landings.
    stairs=[]
    for ident,a,b in [('Reserve_Ridge_Stone_Stair',[-342,140],[-380,150]),('Reserve_Ravine_Stone_Stair',[-255,60],[-245,70])]:
        za=_ROUTE_NODES.get(tuple(float(v) for v in a),pad_height(*a))
        zb=_ROUTE_NODES.get(tuple(float(v) for v in b),pad_height(*b))
        if za>zb:a,b=b,a;za,zb=zb,za
        rise=zb-za;steps=max(2,math.ceil(rise/.165));flights_n=math.ceil(steps/12)
        length=math.dist(a,b);going=(length-(flights_n-1)*1.5)/steps
        flights=[];landings=[];distance=0.;done=0
        def stair_point(dist,z):return [round(a[0]+(b[0]-a[0])*dist/length,6),round(a[1]+(b[1]-a[1])*dist/length,6),round(z,6)]
        for j in range(flights_n):
            n=min(12,steps-done);start=stair_point(distance,za+rise*done/steps)
            distance+=n*going;done+=n;end=stair_point(distance,za+rise*done/steps)
            flights.append({'id':ident+f'_Flight{j+1}','points_m':[start,end],'step_count':n,'rise_m':round(rise/steps,6),'tread_m':round(going,6)})
            if j<flights_n-1:
                start=end;distance+=1.5;end=stair_point(distance,za+rise*done/steps)
                landings.append({'points_m':[start,end],'length_m':1.5})
        stairs.append({'id':ident,'points_m':[[*a,round(za,6)],[*b,round(zb,6)]],'width_m':1.6,'step_count':steps,'rise_m':round(rise/steps,6),'tread_m':round(going,6),'landing_every':12,'landing_length_m':1.5,'flights':flights,'landings':landings,'material':'local granite with rough non-slip tread','handrail_height_m':1.1,'purpose':'optional steep scenic shortcut; the jogging belt remains stair-free',
            'ground_cut':{'clearance_m':.06,'clear_margin_m':.35,'bank_blend_m':8.,'end_blend_m':1.5,'end_clearance_taper_m':.6,
                          'policy':'Cut only beneath exact flight ramp and flat landing profiles; preserve tread geometry and approach datum; smoothly blend exposed banks into existing ground.'}})
        for p,z in ((a,za),(b,zb)):_ROUTE_NODES[tuple(float(v) for v in p)]=round(z,6)
        # Connect each end to an existing scenic trail node, not an island.
        ux,uy=(b[0]-a[0])/length,(b[1]-a[1])/length
        lower_departure=[round(a[0]-ux*3.,6),round(a[1]-uy*3.,6)]
        upper_departure=[round(b[0]+ux*3.,6),round(b[1]+uy*3.,6)]
        lower=[a,[-235,70],[-230,52],[-245,45]] if 'Ravine' in ident else [a,lower_departure,[-342,155],[-310,155]]
        paths.append(graded_path(ident+'_Lower_Link',lower,'scenic_trail',1.6,.12,start_landing_length=0. if 'Ravine' in ident else 6.5))
        upper=[b,upper_departure,[-215,80],[-200,38]] if 'Ravine' in ident else [b,upper_departure,[-372,155],[-380,160]]
        paths.append(graded_path(ident+'_Upper_Link',upper,'scenic_trail',1.6,.12,start_landing_length=6.5))
    # Structural routes are first-class network edges, but are explicitly
    # excluded from the grading index. Consumers must skip ground ribbons for
    # these segments and build the separately specified deck/treads instead.
    for b in bridges:
        paths.append({'id':b['id']+'_Route','kind':'bridge','width_m':b['width_m'],'points_m':b['points_m'],'segments':[{'kind':'bridge','crossing_id':b['id'],'points_m':b['points_m']}],'closed':False,'grade_limit':.08,'maximum_grade':0.,'length_m':round(poly_length(b['points_m']),3),'shoulder_m':0,'core_reuse':False,'maximum_cut_fill_m':0})
    for s in stairs:
        paths.append({'id':s['id']+'_Route','kind':'stairs','width_m':s['width_m'],'points_m':s['points_m'],'segments':[{'kind':'stairs','crossing_id':s['id'],'points_m':s['points_m']}],'closed':False,'grade_limit':1.,'maximum_grade':round((s['points_m'][-1][2]-s['points_m'][0][2])/poly_length(s['points_m']),6),'length_m':round(poly_length(s['points_m']),3),'shoulder_m':0,'core_reuse':False,'maximum_cut_fill_m':0})
    for i,x in enumerate([-203,-190,-177,-164]):
        add_pad('Reserve_Tent_Pitch_'+str(i+1),[x,-149],6,6,camp_z,blend=2,priority=0,use='level tent pitch')
        paths.append(graded_path('Reserve_Tent_Pitch_'+str(i+1)+'_Approach',[[x,-146],[x,-143]],width=1.2,max_grade=.08))
    _index_paths(paths)
    forest=[
        {'id':'Reserve_West_Mixed_Wood','polygon_xy':[[-575,-80],[-520,-200],[-395,-260],[-340,-170],[-315,-20],[-330,120],[-425,200],[-530,155]],'target_tree_count':1150,'species':{'sessile_oak':.40,'scots_pine':.25,'silver_birch':.20,'rowan':.15},'crown_radius_m':[2.5,5.2],'height_m':[7,17],'understory':['bracken','fern','holly','gorse'],'density_pattern':'clustered woodland; feathered edges and two view clearings'},
        {'id':'Reserve_North_Canopy','polygon_xy':[[-525,160],[-425,335],[-300,455],[-150,455],[-70,330],[-125,250],[-250,235],[-330,120]],'target_tree_count':1050,'species':{'beech':.30,'sessile_oak':.30,'silver_birch':.20,'holly':.10,'rowan':.10},'crown_radius_m':[2.6,5.4],'height_m':[8,19],'understory':['fern','wood_anemone','bluebell','hazel'],'density_pattern':'dense sheltered pockets separated by ridge and meadow openings'},
        {'id':'Reserve_South_Wood_Heath','polygon_xy':[[-550,-190],[-420,-300],[-250,-295],[-185,-205],[-240,-130],[-350,-90],[-450,-95]],'target_tree_count':650,'species':{'maritime_pine':.40,'sessile_oak':.25,'silver_birch':.20,'rowan':.15},'crown_radius_m':[2.5,4.8],'height_m':[7,16],'understory':['heather','gorse','grasses'],'density_pattern':'open pine/oak groups interleaved with heath'},
        {'id':'Reserve_Ravine_Wet_Wood','polygon_xy':[[-292,-90],[-275,-135],[-218,-120],[-225,-20],[-240,75],[-260,155],[-225,240],[-275,260],[-310,145]],'target_tree_count':350,'species':{'alder':.40,'willow':.20,'silver_birch':.25,'rowan':.15},'crown_radius_m':[2.0,4.0],'height_m':[6,13],'understory':['sedge','fern','moss'],'density_pattern':'narrow shaded ravine bands; keep bridge sightlines clear'},
        {'id':'Reserve_East_Ecotone','polygon_xy':[[-180,-190],[-85,-170],[-55,-95],[-90,-55],[-120,25],[-80,100],[-10,160],[-20,290],[-75,340],[-145,270],[-170,160],[-160,55],[-195,-45]],'target_tree_count':300,'species':{'sessile_oak':.35,'silver_birch':.30,'rowan':.20,'maritime_pine':.15},'crown_radius_m':[2.3,4.8],'height_m':[6,15],'understory':['wildflower_meadow','gorse','bracken'],'density_pattern':'grouped woodland margin with broad town and coast view windows'},
    ]
    clearings=[
        {'id':'Reserve_Hub_Clearing','center_m':[-116,-64],'radii_m':[38,36],'use':'visitor services, picnic and vehicle turning; no canopy over roofs'},
        {'id':'Reserve_Camp_Clearing','center_m':[-174,-117],'radii_m':[56,47],'use':'serviced pitches, laundry, picnic, play lawn and fire-safe separation'},
        {'id':'Reserve_South_Meadow','polygon_xy':[[-265,-210],[-185,-210],[-130,-170],[-190,-145],[-260,-155]],'use':'long grass, mown route strips, seasonal flowers'},
        {'id':'Reserve_North_Meadow','polygon_xy':[[-210,280],[-130,250],[-70,275],[-110,325],[-180,335]],'use':'upland meadow; keep sea-view opening'},
        {'id':'Reserve_Ridge_View','center_m':[-425,145],'radii_m':[16,12],'use':'granite outcrop, orientation panel and bench'},
        {'id':'Reserve_North_View','center_m':[-200,425],'radii_m':[19,13],'use':'ridge panorama and rest bench'},
    ]
    plan={'schema':'living_town.reserve_plan.v1','authority':'Authored fictional coastal nature reserve; proposed offline environment, not surveyed terrain or certified civil engineering. Existing core geometry and elevations are preserved.','coordinate_system':'Metres; X east, Y north, Z up; local building frontage south; yaw about +Z.','source_bindings':{n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in ['masterplan.json','landscape_plan.json','terrain_plan.json','tools/terrain_profile.py']},'terrain':{'bounds_xyxy_m':list(BOUNDS),'core_preserve_rect_xyxy_m':list(CORE_RECT),'core_blend_m':55,'outer_blend_m':65,'sea_level_m':WATER_Z,'hills':HILLS,'ridges':RIDGES,'ravines':RAVINES,'height_authority':'tools/reserve_plan.py:design_height(x,y); returns unchanged core design_height inside preservation rectangle','mesh_spacing_m':{'core':.6,'reserve':4.,'ravine_and_structures':1.},'coast_policy':'Retain existing coast_x/beach/quay/sea meshes and clip extended dry land to original coast except engineered quay; no eastward infill.'},'pads':_PADS,'buildings':buildings,'paths':paths,'bridges':bridges,'stairs':stairs,'forest_zones':forest,'clearings':clearings,'vegetation_budget':{'linked_trees':3500,'prototype_species':8,'prototype_variants_per_species':3,'understory_linked_groups':900,'rock_clusters':140,'principle':'3500 is an instance budget; actual canopy coverage is sampled separately and is not claimed from tree count. Preserve deliberate meadow and viewpoint gaps.','exclusions':{'core_rect':list(CORE_RECT),'path_edge_buffer_m':1.2,'building_edge_buffer_m':3.,'bridge_abutment_buffer_m':5.}},'utilities':{'authority':'Conceptual visible service assets, with no engineering capacity/compliance claim.','lines':[{'id':'Reserve_Buried_Water_Power','kind':'buried water and electric sleeves','points_xy':[[-58,-25],[-76,-39],[-88,-58],[-116,-64],[-129,-68],[-143,-91],[-143,-116],[-211,-116]]}],'points':[{'id':'Reserve_Water_Point','kind':'drinking_water_and_bottle_fill','center_m':[-120,-67]},{'id':'Reserve_Electrical_Service','kind':'locked_electric_distribution','center_m':[-132,-113]},{'id':'Reserve_Sealed_Wastewater','kind':'sealed_service_tank_access_not_open_pond','center_m':[-133,-137]},{'id':'Reserve_Emergency_Point','kind':'first_aid_and_emergency_phone','center_m':[-126,-56]}],'pitch_hookups':[{'id':b['pitch_id']+'_hookup','center_m':[b['center'][0]+2.4,b['center'][1]],'kind':'water/electric bollard; capped drain connection'} for b in buildings if b['kind']=='trailer']},'visitor_furniture':{'picnic_tables':[[-119,-74],[-121,-82],[-99,-77],[-163,-138],[-193,-138]],'benches':[[-425,145],[-200,425],[-115,-160],[-25,220]],'trailhead_boards':[[-88,-58],[-143,-91],[15,80]],'bike_racks':[[-126,-58],[-94,-58]],'tent_pitches':[[-203,-149],[-190,-149],[-177,-149],[-164,-149]],'campfire':'one controlled stone-ring/social pad at[-192,-139], outside roof/canopy exclusions; no claim of real fire permission'},'validation':{},'planning_plate':{'svg':'concept/reserve_masterplan.svg','png':'concept/reserve_masterplan.png'}}
    PLAN=plan
    _index_stair_cuts(stairs)
    plan['junction_aprons']=[dict(a,policy='Shared short level walking profile; neighboring grades relax within their unchanged declared limits. Existing core terrain and structure landing levels remain authoritative.') for a in _JUNCTION_APRONS]
    plan['site_earthworks']={'terrace_policy':'Broad planted/cut granite shoulders around graded pads; no unsupported floating platforms. Hub and camp levels intentionally step at their short common corner.','retaining_edges':[{'id':'Reserve_Hub_Camp_Step','points_xy':[[-144.5,-87],[-142,-87]],'lower_level_m':round(hub_z,6),'upper_level_m':round(camp_z,6),'thickness_m':.5,'material':'local granite retaining wall with capped top and planted upper edge'}],'camp_outer_bank_blend_m':25,'hub_outer_bank_blend_m':12,'inspection':'Actual mesh cut/fill bank slopes and retaining edge contacts must be inspected after implementation; these are authored site works, not a civil engineering design.'}
    for r in plan['site_earthworks']['retaining_edges']:
        r['ground_profile']={'lower_side':'left of directed points_xy; north for this edge','face_flat_distance_m':.45,'normal_blend_extent_m':1.8,'end_blend_m':1.25,'side_sampling_offset_m':r['thickness_m']/2+.05,'policy':'Terrain meets both wall faces at declared terrace levels; interpolate only inside solid wall thickness; locally blend exposed ground into existing pad/route shoulders.'}
        r['lower_points_m']=[[*p,r['lower_level_m']] for p in r['points_xy']]
        r['upper_points_m']=[[*p,r['upper_level_m']] for p in r['points_xy']]
        r['points_m']=r['upper_points_m']
    return plan


def validate(plan):
    errors=[]
    # Exact core comparison includes town streets, pond and quay, not merely
    # the analytic unengineered terrain surface.
    core_max=0.;core_samples=0
    for x in range(-75,71,5):
        for y in range(-65,66,5):
            core_max=max(core_max,abs(design_height(x,y)-CORE.design_height(x,y)));core_samples+=1
    if core_max!=0:errors.append('core terrain changed')
    bad_paths=[]
    for p in plan['paths']:
        if p['maximum_grade']>p['grade_limit']+.00002:bad_paths.append(p['id'])
    if bad_paths:errors.append('path grade limit: '+','.join(bad_paths))
    # Validate finished ground, not just a declared polyline elevation. This
    # catches competing grading surfaces at a route junction or pitch apron.
    surface_grades=[]
    for p in plan['paths']:
        if p['kind'] in ('bridge','stairs'):continue
        points=resample(p['points_m'],1.)
        levels=[design_height(*v) for v in points]
        grades=[abs(b-a)/math.dist(q,r) for a,b,q,r in zip(levels,levels[1:],points,points[1:]) if math.dist(q,r)>1e-8]
        actual=max(grades,default=0.)
        surface_grades.append({'id':p['id'],'maximum_finished_ground_grade':round(actual,7),'declared_grade_limit':p['grade_limit']})
        if actual>p['grade_limit']+.001:errors.append('actual route surface grade: '+p['id'])
    # A route record connects when an end touches another route's centerline.
    # All geometric crossings are intended at-grade; suspended edges only
    # connect at their actual abutment/end stations.
    paths=plan['paths'];graph={p['id']:set() for p in paths}
    for i,p in enumerate(paths):
        for q in paths[i+1:]:
            touches=False
            for a,b in ((p,q),(q,p)):
                for v in (a['points_m'][0],a['points_m'][-1]):
                    if any(project(v,s,t)[1]<.025 for s,t in zip(b['points_m'],b['points_m'][1:])):
                        touches=True;break
                if touches:break
            if touches:graph[p['id']].add(q['id']);graph[q['id']].add(p['id'])
    reached=set();todo=[paths[0]['id']]
    while todo:
        ident=todo.pop()
        if ident in reached:continue
        reached.add(ident);todo.extend(graph[ident]-reached)
    disconnected=sorted(set(graph)-reached)
    if disconnected:errors.append('disconnected routes: '+','.join(disconnected))
    # Check route ribbon envelopes against actual rotated building shells.
    # A building's own approach may meet its exact front threshold, and an
    # existing core street may preserve its already validated shell margin.
    collisions=[]
    shells=MASTER['buildings']+plan['buildings']
    for p in paths:
        if p['kind'] in ('bridge','stairs'):continue
        for v in resample(p['points_m'],.8):
            for b in shells:
                if p['id']==b['id']+'_Approach':continue
                if pad_distance(*v,b)<p['width_m']/2+.015:
                    collisions.append({'route':p['id'],'building':b['id'],'point_xy':v});break
            if collisions and collisions[-1]['route']==p['id']:break
    if collisions:errors.append('route/building overlap: '+','.join(x['route']+'/'+x['building'] for x in collisions))
    # A route centre on land is insufficient: its complete visible ribbon,
    # including rounded joins, must lie on dry land or the preserved quay.
    # Add10cm construction margin and sample segment edges every20cm; the
    # analytic coastline is smooth at this resolution. Suspended structures
    # have their own abutment/deck checks and are excluded here.
    coastal_checks=[]
    for path in paths:
        if path['kind'] in ('bridge','stairs'):continue
        count=0;quay_count=0;minimum=None;failures=[]
        def coastal_station(x,y):
            nonlocal count,quay_count,minimum
            count+=1
            if 31<=x<=66 and 37<=y<=55:
                quay_count+=1;return
            gap=CORE.coast_x(y)-CORE.beach_width(y)-x
            if minimum is None or gap<minimum['dry_land_clearance_m']:
                minimum={'point_xy':[round(x,6),round(y,6)],'dry_land_clearance_m':gap}
            if gap<0 and len(failures)<12:failures.append({'point_xy':[x,y],'dry_land_clearance_m':gap})
        radius=path['width_m']/2+.1
        for a,b in zip(path['points_m'],path['points_m'][1:]):
            length=math.dist(a[:2],b[:2]);nx,ny=-(b[1]-a[1])/length,(b[0]-a[0])/length
            stations=max(1,math.ceil(length/.2))
            for j in range(stations+1):
                t=j/stations;x,y=a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t
                for side in(-1,0,1):coastal_station(x+nx*radius*side,y+ny*radius*side)
        for point in path['points_m']:
            for angle in range(32):
                a=math.tau*angle/32;coastal_station(point[0]+radius*math.cos(a),point[1]+radius*math.sin(a))
        if failures:errors.append('full-width coastal route leaves land/quay: '+path['id'])
        if minimum:minimum['dry_land_clearance_m']=round(minimum['dry_land_clearance_m'],7)
        coastal_checks.append({'id':path['id'],'status':'FAIL' if failures else 'PASS','edge_padding_m':.1,'sample_spacing_m':.2,'stations':count,'preserved_quay_stations':quay_count,'minimum_nonquay_dry_land_clearance':minimum,'failures':failures})
    bridge_samples=[]
    for b in plan['bridges']:
        a,q=b['points_m'];vals=[]
        for i in range(1,20):
            t=i/20;x=a[0]+(q[0]-a[0])*t;y=a[1]+(q[1]-a[1])*t
            z=a[2]+(q[2]-a[2])*t
            if min(math.dist((x,y),a[:2]),math.dist((x,y),q[:2]))>=5:
                vals.append(z-design_height(x,y))
        b['minimum_ground_clearance_m']=round(min(vals),4)
        # Independently recompute the central station (sample list excludes
        # the graded 5m abutment margins and is therefore not always length19).
        mx,my=(a[0]+q[0])/2,(a[1]+q[1])/2
        b['center_ground_clearance_m']=round((a[2]+q[2])/2-design_height(mx,my),4)
        landing=max(abs(v[2]-design_height(*v[:2])) for v in (a,q))
        bridge_samples.append({'id':b['id'],'minimum_inner_span_ground_clearance_m':b['minimum_ground_clearance_m'],'inner_span_excludes_abutment_margin_m':5.,'center_ground_clearance_m':b['center_ground_clearance_m'],'landing_maximum_height_difference_m':round(landing,7)})
        if landing>.01:errors.append('bridge landing mismatch: '+b['id'])
        if min(vals)<-.02:errors.append('bridge deck buried: '+b['id'])
    stair_ground_checks=[]
    for s in plan['stairs']:
        if s['rise_m']>.17 or s['tread_m']<.28:errors.append('stair proportions: '+s['id'])
        clearances=[]
        for part in s['flights']+s.get('landings',[]):
            a,b=part['points_m'];length=math.dist(a[:2],b[:2]);nx,ny=-(b[1]-a[1])/length,(b[0]-a[0])/length
            n=part.get('step_count',max(1,math.ceil(length/.12)))
            for i in range(n):
                top=a[2]+(b[2]-a[2])*(i+1)/n if 'step_count' in part else a[2]
                for fraction in (.1,.5,.9):
                    t=(i+fraction)/n
                    for lateral in (-s['width_m']/2+.05,-s['width_m']/4,0.,s['width_m']/4,s['width_m']/2-.05):
                        x=a[0]+(b[0]-a[0])*t+nx*lateral;y=a[1]+(b[1]-a[1])*t+ny*lateral
                        clearances.append(top-design_height(x,y))
        minimum=min(clearances)
        stair_ground_checks.append({'id':s['id'],'samples':len(clearances),'minimum_walking_surface_above_analytic_land_m':minimum,'status':'PASS' if minimum>=-.02 else 'FAIL'})
        if minimum<-.02:errors.append('stair walking surface buried by analytic land: '+s['id'])
    # Every new shell lies outside the protected core; rectangular hulls have
    # generous separation at the hub and campsite. Exact narrow meshes remain
    # the amenities consumer's separate room/fixture QA responsibility.
    pad_levels=[]
    for p in plan['pads']:
        a=math.radians(p['yaw_degrees']);co,si=math.cos(a),math.sin(a)
        vals=[]
        for dx in (-p['width']/2,p['width']/2):
            for dy in (-p['depth']/2,p['depth']/2):
                x=p['center'][0]+dx*co-dy*si;y=p['center'][1]+dx*si+dy*co
                vals.append(p['level_m']-natural_height(x,y))
        pad_levels.append({'id':p['id'],'maximum_cut_m':round(max(0,-min(vals)),4),'maximum_fill_m':round(max(0,max(vals)),4)})
    retaining_checks=[]
    for edge in plan['site_earthworks']['retaining_edges']:
        a,b=edge['points_xy'];length=math.dist(a,b)
        nx,ny=-(b[1]-a[1])/length,(b[0]-a[0])/length
        offset=edge['ground_profile']['side_sampling_offset_m'];samples=[]
        for t in (0.,.25,.5,.75,1.):
            for sign,side,level in ((-1,'upper',edge['upper_level_m']),(1,'lower',edge['lower_level_m'])):
                x=a[0]+(b[0]-a[0])*t+nx*offset*sign;y=a[1]+(b[1]-a[1])*t+ny*offset*sign
                actual=design_height(x,y);delta=actual-level
                samples.append({'side':side,'point_m':[x,y,actual],'required_level_m':level,'difference_m':delta})
                if abs(delta)>1e-7:errors.append('retaining face ground contact: '+edge['id']+' '+side)
        retaining_checks.append({'id':edge['id'],'status':'PASS' if all(abs(s['difference_m'])<=1e-7 for s in samples) else 'FAIL','samples':samples,'maximum_contact_difference_m':max(abs(s['difference_m']) for s in samples)})
    plan['terrain']['elevation_samples_m']=[[x,y,round(design_height(x,y),4)] for x,y in [(-58,-25),(-116,-64),(-178,-116),(-340,-180),(-425,145),(-255,340),(-200,425),(-245,45),(-334,120),(31,54),(26,-42)]]
    plan['validation']={'status':'PASS' if not errors else 'FAIL','errors':errors,'exact_core_samples':core_samples,'exact_core_maximum_difference_m':core_max,'jogging_belt_closed':plan['paths'][0]['points_m'][0]==plan['paths'][0]['points_m'][-1],'jogging_belt_length_m':plan['paths'][0]['length_m'],'jogging_maximum_grade':plan['paths'][0]['maximum_grade'],'new_building_count':len(plan['buildings']),'trailer_count':sum(b['kind']=='trailer' for b in plan['buildings']),'forest_tree_budget':sum(z['target_tree_count'] for z in plan['forest_zones']),'connected_route_records':len(reached),'route_record_count':len(paths),'disconnected_routes':disconnected,'route_building_collisions':collisions,'actual_surface_grades':surface_grades,'bridges':bridge_samples,'pad_cut_fill':pad_levels,'scope':'Metric planning/profile checks only; actual native terrain contact, bridge supports, stair treads, forest exclusions and interior fixture reachability must be verified after geometry implementation.'}
    plan['validation']['retaining_face_ground_contacts']=retaining_checks
    plan['validation']['stair_ground_cut_controls']=stair_ground_checks
    plan['validation']['full_width_coastal_clearance']={'scope':'Entire ordinary-route width plus10cm, segment edge stations every20cm and32-angle vertex joins; analytic coast_x minus beach_width, or actual preserved quay rectangle[31,37,66,55]. No actual mesh-contact claim.','routes':coastal_checks}
    earthworks=[]
    for path in plan['paths']:
        if path['kind'] in ('bridge','stairs'):continue
        values=[]
        for i,(a,b) in enumerate(zip(path['points_m'],path['points_m'][1:])):
            if i%3:continue
            length=math.dist(a[:2],b[:2]);nx,ny=-(b[1]-a[1])/length,(b[0]-a[0])/length
            for sign in(-1,0,1):
                offset=sign*(path['width_m']/2+GRADE_EDGE_EXTENSION_M)
                x,y=(a[0]+b[0])/2+nx*offset,(a[1]+b[1])/2+ny*offset
                if rect_distance(x,y,CORE_RECT):values.append(design_height(x,y)-natural_height(x,y))
        if values:earthworks.append({'id':path['id'],'samples':len(values),'maximum_cut_m':round(max(0,-min(values)),4),'maximum_fill_m':round(max(0,max(values)),4),'mean_absolute_cut_fill_m':round(sum(abs(v) for v in values)/len(values),4)})
    plan['validation']['graded_corridor_earthworks']={'scope':'Analytic ground vs unengineered natural_height at centre and fully graded outer edges, every third source segment; not earthwork volumes or actual mesh proof. Bridges/stairs and protected core excluded.','edge_extension_m':GRADE_EDGE_EXTENSION_M,'maximum_cut_m':max(e['maximum_cut_m'] for e in earthworks),'maximum_fill_m':max(e['maximum_fill_m'] for e in earthworks),'routes':earthworks}
    return errors


def draw_plate(plan):
    """Legible plan with actual-authority 10m contours, roads and amenities."""
    out=ROOT/'concept';out.mkdir(exist_ok=True)
    W,H=1300,1580;scale=1.49;ox,oy=950,850
    def xy(p):return ox+p[0]*scale,oy-p[1]*scale
    def points(poly):return ' '.join(f'{xy(p)[0]:.1f},{xy(p)[1]:.1f}' for p in poly)
    svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">','<rect width="1300" height="1580" fill="#f0ede2"/>','<style>text{font-family:Arial,sans-serif;fill:#203835}.small{font-size:14px}.label{font-size:16px;font-weight:600}</style>','<text x="55" y="47" font-size="28" font-weight="700">LIVING TOWN / COASTAL NATURE RESERVE</text>','<text x="55" y="76" font-size="16">Authored terrain + connected visitor, camping and trail plan · metres · north ↑</text>']
    for zone in plan['forest_zones']:
        svg.append(f'<polygon points="{points(zone["polygon_xy"])}" fill="#b4c8ac" stroke="#7d997a" stroke-width="1" opacity=".75"/>')
    for c in plan['clearings']:
        if 'polygon_xy' in c:svg.append(f'<polygon points="{points(c["polygon_xy"])}" fill="#e2dcb2" stroke="#a5aa7c"/>')
        else:
            cx,cy=xy(c['center_m']);rx,ry=c['radii_m'];svg.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx*scale}" ry="{ry*scale}" fill="#e2dcb2" stroke="#a5aa7c"/>')
    # Marching square segments from exactly the same natural height profile.
    for x in range(-590,51,10):
        for y in range(-330,491,10):
            corners=[(x,y),(x+10,y),(x+10,y+10),(x,y+10)]
            zs=[natural_height(*p) for p in corners]
            for level in range(10,81,10):
                hits=[]
                for i,j in ((0,1),(1,2),(2,3),(3,0)):
                    if (zs[i]<level)!=(zs[j]<level):
                        t=(level-zs[i])/(zs[j]-zs[i]);hits.append([corners[i][k]+t*(corners[j][k]-corners[i][k]) for k in (0,1)])
                if len(hits)==2:svg.append(f'<polyline points="{points(hits)}" fill="none" stroke="#a8a98f" stroke-width=".65"/>')
    coast=[[CORE.coast_x(y),y] for y in range(-340,501,10)]
    svg.append(f'<polygon points="{points(coast+[[180,500],[180,-340]])}" fill="#c0dce0"/>')
    for r in RAVINES:svg.append(f'<polyline points="{points(r["points_xy"])}" fill="none" stroke="#6c8b7e" stroke-width="{r["half_width_m"]*scale}" opacity=".38"/>')
    x0,y0=xy([CORE_RECT[0],CORE_RECT[3]]);svg.append(f'<rect x="{x0}" y="{y0}" width="{(CORE_RECT[2]-CORE_RECT[0])*scale}" height="{(CORE_RECT[3]-CORE_RECT[1])*scale}" fill="#f5e8ce" stroke="#b88449" stroke-dasharray="7 5"/>')
    for b in MASTER['buildings']:svg.append(f'<polygon points="{points(b["footprint_polygon"])}" fill="#a78870"/>')
    for p in plan['paths']:
        color='#a65a30' if p['kind']=='jogging_belt' else '#766d54' if p['kind']=='service_access' else '#948973'
        svg.append(f'<polyline points="{points(p["points_m"])}" fill="none" stroke="{color}" stroke-width="{4 if p["kind"]=="jogging_belt" else 2}" stroke-linejoin="round"/>')
    for b in plan['buildings']:
        cx,cy=xy(b['center']);w,d=b['width']*scale,b['depth']*scale
        svg.append(f'<rect x="{cx-w/2}" y="{cy-d/2}" width="{w}" height="{d}" fill="#725b49" transform="rotate({-b["yaw_degrees"]} {cx} {cy})"/>')
    for b in plan['bridges']:
        svg.append(f'<polyline points="{points(b["points_m"])}" fill="none" stroke="#f6f4e9" stroke-width="8"/>')
        svg.append(f'<polyline points="{points(b["points_m"])}" fill="none" stroke="#314d59" stroke-width="4"/>')
    for s in plan['stairs']:svg.append(f'<polyline points="{points(s["points_m"])}" fill="none" stroke="#9b3f51" stroke-width="5" stroke-dasharray="2 2"/>')
    labels=[([-116,-42],'VISITOR HUB / 9 SERVICE UNITS'),([-178,-155],'12 TRAILERS + 4 TENT PITCHES'),([-400,180],'WESTERN GRANITE WOODLAND'),([-260,350],'NORTHERN CANOPY / MEADOWS'),([-300,-210],'SOUTH HEATH + OAK/PINE'),([-220,80],'FERN RAVINE'),([-355,130],'CLEFT BRIDGE'),([-30,15],'EXISTING TOWN'),([-175,440],'RIDGE VIEW'),([-80,-115],'STAI R-FREE JOGGING BELT'.replace('STAI R','STAIR'))]
    for p,label in labels:
        x,y=xy(p);svg.append(f'<text x="{x}" y="{y}" class="small">{label}</text>')
    svg+=['<rect x="55" y="1390" width="1190" height="145" rx="8" fill="#fffdf5" stroke="#aab3a3"/>',f'<text x="75" y="1418" class="label">{plan["paths"][0]["length_m"]/1000:.2f} km continuous jogging belt · maximum designed grade {plan["paths"][0]["maximum_grade"]*100:.1f}% · 3,500 linked-tree budget</text>','<text x="75" y="1444" class="small">Brown: stair-free running belt   Grey: scenic trails/service access   Blue: actual ravine bridges   Magenta: optional stone stairs</text>','<text x="75" y="1469" class="small">10 m authored contours · graded hub/camp pads · dense woods, open heath, fern ravines and deliberate view clearings</text>','<text x="75" y="1494" class="small">Dashed amber rectangle: unchanged town/coast/pond elevation authority. Core sea/beach/quay remain in place.</text>','<text x="75" y="1519" class="small">Planning proposal; geometry, supports, canopy placement and amenity interiors require implementation QA.</text>','</svg>']
    (out/'reserve_masterplan.svg').write_text('\n'.join(svg),encoding='utf-8')
    try:
        import cairosvg
        cairosvg.svg2png(bytestring='\n'.join(svg).encode('utf-8'),write_to=str(out/'reserve_masterplan.png'))
    except (ImportError,OSError):
        # The bundled runtime includes Pillow; this fallback uses the same
        # plan geometry without requiring Cairo on a portable Windows host.
        from PIL import Image,ImageDraw,ImageFont
        im=Image.new('RGB',(W,H),'#f0ede2');dr=ImageDraw.Draw(im)
        font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',16);title=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',28)
        dr.text((55,25),'LIVING TOWN / COASTAL NATURE RESERVE',font=title,fill='#203835')
        dr.text((55,66),'Authored topography + connected visitor, camping and trail plan / north up',font=font,fill='#203835')
        for z in plan['forest_zones']:dr.polygon([xy(p) for p in z['polygon_xy']],fill='#b4c8ac',outline='#7d997a')
        for c in plan['clearings']:
            if 'polygon_xy' in c:dr.polygon([xy(p) for p in c['polygon_xy']],fill='#e2dcb2')
            else:
                cx,cy=xy(c['center_m']);rx,ry=c['radii_m'];dr.ellipse((cx-rx*scale,cy-ry*scale,cx+rx*scale,cy+ry*scale),fill='#e2dcb2')
        for x in range(-590,51,10):
            for y in range(-330,491,10):
                cs=[(x,y),(x+10,y),(x+10,y+10),(x,y+10)];zs=[natural_height(*p) for p in cs]
                for lev in range(10,81,10):
                    hits=[]
                    for i,j in ((0,1),(1,2),(2,3),(3,0)):
                        if (zs[i]<lev)!=(zs[j]<lev):
                            t=(lev-zs[i])/(zs[j]-zs[i]);hits.append([cs[i][k]+t*(cs[j][k]-cs[i][k]) for k in (0,1)])
                    if len(hits)==2:dr.line([xy(p) for p in hits],fill='#a8a98f',width=1)
        dr.polygon([xy(p) for p in coast+[[180,500],[180,-340]]],fill='#c0dce0')
        for b in MASTER['buildings']:dr.polygon([xy(p) for p in b['footprint_polygon']],fill='#a78870')
        for p in plan['paths']:dr.line([xy(q) for q in p['points_m']],fill='#a65a30' if p['kind']=='jogging_belt' else '#948973',width=4 if p['kind']=='jogging_belt' else 2)
        for b in plan['buildings']:
            cx,cy=xy(b['center']);dr.rectangle((cx-3,cy-4,cx+3,cy+4),fill='#725b49')
        for b in plan['bridges']:dr.line([xy(p) for p in b['points_m']],fill='#314d59',width=5)
        for s in plan['stairs']:dr.line([xy(p) for p in s['points_m']],fill='#9b3f51',width=5)
        for p,label in labels:dr.text(xy(p),label,font=font,fill='#203835',stroke_width=1,stroke_fill='#f0ede2')
        dr.rectangle((55,1390,1245,1538),fill='#fffdf5',outline='#aab3a3')
        lines=[f'{plan["paths"][0]["length_m"]/1000:.2f} km continuous jogging belt / max {plan["paths"][0]["maximum_grade"]*100:.1f}% grade / 3,500 linked trees', 'Brown: running belt  Grey: scenic/service  Blue: bridges  Magenta: optional stone stairs','10 m authored contours / graded hub + camp / woods, heath, fern ravines and view clearings','Existing town/coast/pond elevation preserved; no sea/beach/quay infill.','Planning proposal: actual mesh/support/planting/interior QA follows implementation.']
        for i,line in enumerate(lines):dr.text((75,1407+i*25),line,font=font,fill='#203835')
        im.save(out/'reserve_masterplan.png')


def main():
    plan=make_plan();errors=validate(plan)
    (ROOT/'reserve_plan.json').write_text(json.dumps(plan,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    draw_plate(plan)
    print(json.dumps({'status':plan['validation']['status'],'buildings':len(plan['buildings']),'paths':len(plan['paths']),'connected':plan['validation']['connected_route_records'],'jogging_length_m':plan['paths'][0]['length_m'],'jogging_maximum_grade':plan['paths'][0]['maximum_grade'],'bridges':plan['validation']['bridges'],'stairs':[{'id':s['id'],'steps':s['step_count'],'rise':s['rise_m'],'tread':s['tread_m'],'flights':len(s['flights'])} for s in plan['stairs']],'errors':errors},indent=2))
    if errors:raise SystemExit(1)


if __name__=='__main__':main()
