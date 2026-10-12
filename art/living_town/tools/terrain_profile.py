"""Authored fictional coastal-bourg terrain. Pure Python; no bpy or numpy.

Import this module from Blender and use design_height everywhere that needs the
finished terrain, and building_pad_level(record) for a shell's ground/plinth
base. Finished floor remains the model's separate +0.38m construction offset.
Running the module writes its plan/evidence and topographic SVG/PNG only.
"""
from __future__ import annotations
import hashlib
import json
import math
import base64
import io
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MASTERPLAN = json.loads((ROOT / "masterplan.json").read_text(encoding="utf-8"))
LANDSCAPE_PATH = ROOT / 'landscape_plan.json'
LANDSCAPE = json.loads(LANDSCAPE_PATH.read_text(encoding='utf-8')) if LANDSCAPE_PATH.exists() else {}
WATER_Z = -.88
QUAY_Z = 1.615
QUAY_RECT = (31., 37., 66., 55.)
PLAZA_RECT = (-13., -8., 7., 8.)
ROAD_MAX_GRADE = .08
GRID = 8.
PAD_BLEND = .60
ROAD_BLEND = .55
ROAD_CROWN = .01
ROAD_APRON = .16
MAX_ROAD_RADIUS = max(r['width']/2 for r in MASTERPLAN['streets'])+ROAD_BLEND+ROAD_APRON


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def smoothstep(t):
    t = clamp(t, 0., 1.)
    return t*t*(3-2*t)


def rounded_rise(t, width=8., cap_start=70., cap_end=110.):
    """Smoothed hinge, then finite gently rounding plateau outside the town."""
    if t <= -width/2:
        return 0.
    if t < width/2:
        return (t+width/2)**2/(2*width)
    if t <= cap_start:
        return t
    if t >= cap_end:
        return cap_start+(cap_end-cap_start)/2
    u=(t-cap_start)/(cap_end-cap_start)
    return cap_start+(cap_end-cap_start)*(u/2+math.sin(math.pi*u)/(2*math.pi))


def coast_x(y):
    return 49+2*math.sin(y*.055)-7*math.exp(-((y-43)/10)**2)


def beach_width(y):
    return 7-6*smoothstep((y-24)/11)


def natural_height(x, y):
    """Unengineered land, with modest granite swells and a low coastal terrace.

    West rise tends to 5.5%, north rise to 3.5%. Both round to a finite broad
    plateau beyond the presentation site, rather than making endless cliffs.
    Water and engineered quay are distinct surfaces, not natural land here.
    """
    western = .055*rounded_rise(-x-10)
    northern = .035*rounded_rise(y-12)
    east_fall = .004*clamp(12-x, -30., 40.)
    church_knoll = .18*math.exp(-((x+28)/25)**2-((y-29)/23)**2)
    mill_knoll = .12*math.exp(-((x+57)/23)**2-((y-35)/28)**2)
    return .35+western+northern+east_fall+church_knoll+mill_knoll


def rect_distance(x, y, rect):
    x0,y0,x1,y1=rect
    return math.hypot(max(x0-x,0,x-x1),max(y0-y,0,y-y1))


def plaza_level(x, y):
    # A single 0.91% plane sheds east and gently south. It is never a bowl.
    return .48-.009*x+.0015*y


def engineered_height(x, y):
    """Square and quay grading before streets and level building pads."""
    z=natural_height(x,y)
    d=rect_distance(x,y,PLAZA_RECT)
    # A bounded grade cone avoids the 9-10% shoulder that a generic smooth
    # interpolation between a hill and a flat square would introduce.
    plane=plaza_level(x,y)
    z=clamp(z,plane-.060*d,plane+.060*d)
    # Grade up/down to a 6.5% cone around the engineered deck. Clamping to
    # this cone gives a continuous apron/ramp; no quay-height jump on land.
    d=rect_distance(x,y,QUAY_RECT)
    return clamp(z,QUAY_Z-.065*d,QUAY_Z+.065*d)


def building_pad_level(record):
    """Level ground/plinth base, not the finished interior floor."""
    return engineered_height(*record['center'])


PADS=[]
PAD_INDEX=defaultdict(list)
ROAD_SEGMENTS=[]
ROAD_INDEX=defaultdict(list)


def index_bounds(index, ident, bounds):
    x0,y0,x1,y1=bounds
    for i in range(math.floor(x0/GRID),math.floor(x1/GRID)+1):
        for j in range(math.floor(y0/GRID),math.floor(y1/GRID)+1):
            index[i,j].append(ident)


for b in MASTERPLAN['buildings']:
    a=math.radians(b['yaw_degrees'])
    item=(b,math.cos(a),math.sin(a),building_pad_level(b))
    PADS.append(item)
    poly=b['footprint_polygon']
    index_bounds(PAD_INDEX,len(PADS)-1,(min(p[0] for p in poly)-PAD_BLEND,
        min(p[1] for p in poly)-PAD_BLEND,max(p[0] for p in poly)+PAD_BLEND,max(p[1] for p in poly)+PAD_BLEND))

for road in MASTERPLAN['streets']:
    for a,b in zip(road['points'],road['points'][1:]):
        length=math.dist(a,b)
        if length<1e-9:continue
        # Short linear chords approximate one common engineering surface.
        # Every junction therefore inherits the same underlying elevation.
        n=max(1,math.ceil(length/.65))
        for j in range(n):
            p=[a[k]+(b[k]-a[k])*j/n for k in (0,1)]
            q=[a[k]+(b[k]-a[k])*(j+1)/n for k in (0,1)]
            half=road['width']/2
            ROAD_SEGMENTS.append((p,q,engineered_height(*p),engineered_height(*q),half,road['id'],road['kind']))
            r=MAX_ROAD_RADIUS
            index_bounds(ROAD_INDEX,len(ROAD_SEGMENTS)-1,(min(p[0],q[0])-r,min(p[1],q[1])-r,max(p[0],q[0])+r,max(p[1],q[1])+r))


def project(x,y,a,b):
    dx,dy=b[0]-a[0],b[1]-a[1]
    t=clamp(((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy),0,1)
    return t,math.hypot(x-a[0]-t*dx,y-a[1]-t*dy)


def design_height(x, y):
    """Finished ground: engineering, 1% road crown, nearest level parcel.

    Spatial indices restrict road/pad work to the local 8m construction cell.
    Inside a parcel the pad is exactly level. Its 0.6m skirt blends to land;
    at a shared stepped edge the closest pad owns that side of the surface.
    Public street clearance keeps those skirts out of carriageway centers.
    """
    z=engineered_height(x,y)
    key=(math.floor(x/GRID),math.floor(y/GRID))
    distance=math.inf;coverage=0.;inside_carriageway=False
    for i in ROAD_INDEX.get(key,()):
        a,b,za,zb,half,ident,kind=ROAD_SEGMENTS[i]
        t,d=project(x,y,a,b)
        distance=min(distance,d)
        apron=ROAD_APRON if kind=='public_street' else 0
        coverage=max(coverage,1-smoothstep((d-half-apron)/ROAD_BLEND))
        if kind=='public_street' and d<=half+apron+1e-6:inside_carriageway=True
    if coverage>0:
        # A shared continuous distance-to-network crown survives crossings.
        # Projecting heights onto whichever centerline is nearest would jump
        # when two differently oriented road planes exchange ownership.
        z-=ROAD_CROWN*distance*coverage
    nearest=None
    for i in PAD_INDEX.get(key,()):
        b,co,si,level=PADS[i];dx,dy=x-b['center'][0],y-b['center'][1]
        lx,ly=dx*co+dy*si,-dx*si+dy*co
        d=math.hypot(max(abs(lx)-b['width']/2,0),max(abs(ly)-b['depth']/2,0))
        if d>PAD_BLEND:continue
        if inside_carriageway and d>1e-7:continue
        # Exact adjoining edges tie by stable ID; a zero-width seam is a
        # modeled retaining/foundation joint rather than a blended slope.
        score=(d,(dx*dx+dy*dy),b['id'])
        if nearest is None or score<nearest[0]:nearest=(score,level,d)
    if nearest:
        _,level,d=nearest;w=1-smoothstep(d/PAD_BLEND)
        z=z*(1-w)+level*w
    return pond_ground_height(x,y,z)


def pond_spec():
    """Metric, lined park feature; independent of the coastal sea datum."""
    record=LANDSCAPE.get('pond',{})
    return {'center':record.get('center',[26.,-42.]),
        'water_radii_m':record.get('water_radii_m',[5.,3.]),
        'outer_bank_radii_m':record.get('outer_bank_radii_m',[7.,5.]),
        'water_z_m':record.get('water_z_m',-.12),'bed_z_m':record.get('bed_z_m',-.92)}


def pond_radius(x,y,outer=False):
    p=pond_spec();cx,cy=p['center'];rx,ry=p['outer_bank_radii_m' if outer else 'water_radii_m']
    return math.hypot((x-cx)/rx,(y-cy)/ry)


def pond_ground_height(x,y,unmodified_z):
    if not LANDSCAPE.get('pond'):return unmodified_z
    p=pond_spec();rho=pond_radius(x,y)
    if rho<=1:
        # Rounded linear bowl: a 15% transition at centre and shoreline keeps
        # even submerged banks <= 1:3 for the specified 0.8m / 3m section.
        t=pond_bank_ease(rho)
        return p['bed_z_m']+(p['water_z_m']-p['bed_z_m'])*t
    outer=pond_radius(x,y,True)
    if outer>=1:return unmodified_z
    # Along this ray, rho is the water edge parameter and rho/outer is the
    # outer ellipse. A smooth shoulder meets both water and undisturbed land.
    t=(rho-1)/(rho/outer-1)
    return p['water_z_m']+(unmodified_z-p['water_z_m'])*pond_bank_ease(t)


def pond_bank_ease(t):
    t=clamp(t,0,1);e=.15
    return t*t/(2*e*(1-e)) if t<e else (1-(1-t)**2/(2*e*(1-e)) if t>1-e else (t-e/2)/(1-e))


def beach_height(x,y):
    """Sand section with modest upper-beach dune shoulders and access gaps."""
    water=coast_x(y);width=beach_width(y);edge=water-width
    t=clamp((x-edge)/width,0,1)
    z=design_height(edge,y)*(1-t)+WATER_Z*t
    if width<3 or t>.50:return z
    gap=min(abs(y-v) for v in (-30.,-3.,17.))
    access=smoothstep((gap-1.25)/2.)
    bump=.18*math.sin(math.pi*clamp(t/.50,0,1))**2
    return z+bump*access*(.75+.25*math.sin(y*.23)**2)


def surface_height(x,y):
    """Complete topographic map surface including sand and visible water.

    Blender may construct beach/water meshes separately. Use design_height
    for dry terrain, streets, pads, props and foundation connection checks.
    """
    if 31<=x<=66 and 37<=y<=55:return QUAY_Z
    water=coast_x(y);edge=water-beach_width(y)
    if x>=water:return WATER_Z
    if x<=edge:
        if LANDSCAPE.get('pond') and pond_radius(x,y)<=1:return pond_spec()['water_z_m']
        return design_height(x,y)
    return beach_height(x,y)


def samples(a,b,spacing=.25):
    n=max(1,math.ceil(math.dist(a,b)/spacing))
    return [[a[0]+(b[0]-a[0])*i/n,a[1]+(b[1]-a[1])*i/n] for i in range(n+1)]


def contour_segments(extent=(-65.,-57.,70.,59.), grid=1., interval=.5):
    """Joined contour polylines, each {'level_m': z, 'points': [[x,y,z],...] }.

    Standard-library marching squares of the same full surface; useful for a
    hidden native review collection. Water is a separate constant datum and
    produces no redundant ocean contours. Pad/quay contour edges are sampled
    approximations, not surveyed breaklines or construction drawings.
    """
    x0,y0,x1,y1=extent
    nx,ny=round((x1-x0)/grid),round((y1-y0)/grid)
    gx=[x0+i*grid for i in range(nx+1)];gy=[y0+i*grid for i in range(ny+1)]
    heights={(x,y):surface_height(x,y) for y in gy for x in gx}
    low=math.ceil(min(heights.values())/interval)*interval
    high=math.floor(max(heights.values())/interval)*interval
    paths=[]
    for step in range(round((high-low)/interval)+1):
        level=low+step*interval;segments=[]
        for y in gy[:-1]:
            for x in gx[:-1]:
                corners=[(x,y),(x+grid,y),(x+grid,y+grid),(x,y+grid)];crossings=[]
                for a,b in zip(corners,corners[1:]+corners[:1]):
                    za,zb=heights[a],heights[b]
                    if (za<level<=zb) or (zb<level<=za):
                        t=(level-za)/(zb-za)
                        crossings.append((round(a[0]+(b[0]-a[0])*t,6),round(a[1]+(b[1]-a[1])*t,6)))
                for j in range(0,len(crossings)-1,2):segments.append((crossings[j],crossings[j+1]))
        nodes=defaultdict(list)
        for i,(a,b) in enumerate(segments):nodes[a].append(i);nodes[b].append(i)
        unused=set(range(len(segments)))
        starts=[p for p,indices in nodes.items() if len(indices)!=2]
        while unused:
            start=next((p for p in starts if any(i in unused for i in nodes[p])),None)
            if start is None:start=segments[min(unused)][0]
            point=start;chain=[point]
            while True:
                choices=[i for i in nodes[point] if i in unused]
                if not choices:break
                ident=min(choices);unused.remove(ident);a,b=segments[ident]
                point=b if point==a else a;chain.append(point)
                if point==start or len(nodes[point])!=2:break
            if len(chain)>1:paths.append({'level_m':level,'points':[[x,y,level] for x,y in chain]})
    return paths


def road_edge_grade(road, apron=0.):
    """Sample both physical ribbon edges, including averaged corner normals."""
    stations=[]
    for a,b in zip(road['points'],road['points'][1:]):stations.extend(samples(a,b,.65)[:-1])
    stations.append(road['points'][-1]);edges=[[],[]]
    for i,p in enumerate(stations):
        a,b=stations[max(0,i-1)],stations[min(len(stations)-1,i+1)]
        dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy);half=road['width']/2+apron
        normal=(-dy/length*half,dx/length*half)
        for j,side in enumerate((-1,1)):edges[j].append([p[0]+normal[0]*side,p[1]+normal[1]*side])
    worst=0.
    for edge in edges:
        for a,b in zip(edge,edge[1:]):
            if math.dist(a,b)<1e-8:continue
            pts=samples(a,b,.25)
            for p,q in zip(pts,pts[1:]):worst=max(worst,abs(design_height(*p)-design_height(*q))/math.dist(p,q))
    return worst*100


def make_plan():
    roads=[]
    for r in MASTERPLAN['streets']:
        pts=[]
        for a,b in zip(r['points'],r['points'][1:]):pts.extend(samples(a,b)[:-1])
        pts.append(r['points'][-1]);levels=[design_height(*p) for p in pts]
        grades=[abs(z2-z1)/math.dist(a,b) for a,b,z1,z2 in zip(pts,pts[1:],levels,levels[1:])]
        worst=max(grades,default=0);j=grades.index(worst) if grades else 0
        roadrecord={'id':r['id'],'kind':r['kind'],'width_m':r['width'],
            'max_grade_percent':round(worst*100,4),'start_level_m':levels[0],'end_level_m':levels[-1],
            'steepest_segment':[pts[j],pts[j+1]],'threshold_owner':r.get('threshold_owner'),
            'treatment':'entry_steps_required' if worst>.08 and r['kind'] in ('threshold','entrance_approach') else ('grade_review_required' if worst>.08 else 'continuous_graded_paving')}
        if r['kind']=='public_street':
            roadrecord['max_ribbon_edge_grade_percent']=round(road_edge_grade(r),4)
            roadrecord['max_paving_apron_edge_grade_percent']=round(road_edge_grade(r,.15),4)
        roads.append(roadrecord)
    pads=[]
    for b in MASTERPLAN['buildings']:
        level=building_pad_level(b);ring=[]
        p=b['footprint_polygon']
        for a,q in zip(p,p[1:]+p[:1]):ring.extend(samples(a,q,.5))
        natural=[natural_height(*p) for p in ring]
        threshold=b['front_threshold'];normal=b['front_outward']
        outside=[threshold[0]+normal[0]*.7,threshold[1]+normal[1]*.7]
        pads.append({'id':b['id'],'pad_base_z_m':level,'finished_floor_z_m':level+.38,
            'threshold_xy':threshold,'threshold_ground_z_m':design_height(*threshold),
            'outside_landing_xy':outside,'outside_landing_z_m':design_height(*outside),
            'max_cut_m':max(0,max(natural)-level),'max_fill_m':max(0,level-min(natural)),
            'foundation_toe_recommendation_z_m':min(min(natural),level)-.15,
            'entry_rise_from_outside_m':level+.38-design_height(*outside)})
    public=[r for r in roads if r['kind']=='public_street']
    drainage=[]
    for ident,x,y,kind in [('plaza_east',6.25,-6.8,'street_grate'),('plaza_south',-2,-8.65,'street_grate'),
            ('south_route',17.3,-10.1,'street_grate'),('sea_south',39.7,-27,'street_grate'),
            ('sea_mid',39.7,-13,'street_grate'),('sea_opening',39.7,-2.55,'street_grate'),
            ('sea_north',39.7,15,'street_grate'),('harbor_west',33,37.8,'quay_channel_grate'),
            ('harbor_mid',47,37.8,'quay_channel_grate'),('harbor_east',61,37.8,'quay_channel_grate')]:
        drainage.append({'id':ident,'center':[x,y],'level_m':design_height(x,y)+.005,'kind':kind})
    for ident,y in [('south_coast_outfall',-12),('central_coast_outfall',-2.55)]:
        drainage.append({'id':ident,'center':[coast_x(y)-.8,y],'level_m':WATER_Z+.25,'kind':'conceptual_culvert_outfall'})
    drainage.append({'id':'harbor_storm_outfall','center':[66,39.5],'level_m':WATER_Z+.25,'kind':'conceptual_culvert_outfall'})
    flow_arrows=[{'id':'western_rise','points':[[-48,-18],[-38,-15]],'kind':'surface_fall'},
        {'id':'church_rise','points':[[-23,22],[-18,18]],'kind':'surface_fall'},
        {'id':'square_east','points':[[-9,1],[3,-1]],'kind':'square_sheet_fall'},
        {'id':'square_south','points':[[2,3],[4,-5]],'kind':'square_sheet_fall'},
        {'id':'coastal_south','points':[[35,-32],[41,-31]],'kind':'surface_fall'},
        {'id':'coastal_middle','points':[[35,5],[41,5]],'kind':'surface_fall'},
        {'id':'north_service','points':[[25,44],[29,39]],'kind':'surface_fall'},
        {'id':'quay_channels','points':[[54,44],[54,38]],'kind':'shallow_channel_fall'}]
    beach_sections=[]
    for y in (-30,0,25,33):
        edge=coast_x(y)-beach_width(y);z=design_height(edge,y);width=beach_width(y)
        beach_sections.append({'y':y,'land_edge_x':edge,'land_edge_z_m':z,'water_edge_x':coast_x(y),
            'width_m':width,'rise_m':z-WATER_Z,'average_crossfall_percent':100*(z-WATER_Z)/width,
            'treatment':'broad_sandy_foreshore' if y<=25 else 'stone_revetment_transition_not_sandy_walkway'})
    pond=None
    if LANDSCAPE.get('pond'):
        p=pond_spec();cx,cy=p['center'];rx,ry=p['outer_bank_radii_m']
        maximum=0.;worst=None;h=.025
        for i in range(math.ceil(2*rx/.1)+1):
            for j in range(math.ceil(2*ry/.1)+1):
                x=cx-rx+i*.1;y=cy-ry+j*.1
                if pond_radius(x,y,True)>1:continue
                gx=(design_height(x+h,y)-design_height(x-h,y))/(2*h)
                gy=(design_height(x,y+h)-design_height(x,y-h))/(2*h)
                slope=math.hypot(gx,gy)
                if slope>maximum:maximum=slope;worst=[x,y]
        pond={**p,'construction':'Authored lined ornamental pond; no inferred natural aquifer or tidal connection.',
            'maximum_water_depth_m':p['water_z_m']-p['bed_z_m'],
            'wet_surface_area_m2':math.pi*p['water_radii_m'][0]*p['water_radii_m'][1],
            'maximum_sampled_bank_grade_percent':round(maximum*100,4),'steepest_sample_xy':worst,
            'grade_sample_spacing_m':.1,'gradient_central_difference_m':h,
            'bank_grade_limit_percent':100/3,'bank_grade_pass':maximum<=1/3+.001,
            'water_is_level':True,'bed_height_at_center_m':design_height(cx,cy)}
    return {'schema':'living_town.terrain_plan.v2','masterplan_sha256':hashlib.sha256((ROOT/'masterplan.json').read_bytes()).hexdigest(),
        'landscape_plan_sha256':hashlib.sha256(LANDSCAPE_PATH.read_bytes()).hexdigest() if LANDSCAPE_PATH.exists() else None,
        'authority':'Authored fictional Breton coastal site; no surveyed or geotechnical accuracy claimed.',
        'coordinate_system':'Metres; local water datum Z=-0.88; no national/geographic datum.',
        'frozen_xy':{'buildings':len(MASTERPLAN['buildings']),'street_records':len(MASTERPLAN['streets']),'masterplan_modified':False},
        'levels':{'water_z_m':WATER_Z,'quay_deck_z_m':QUAY_Z,'quay_freeboard_m':QUAY_Z-WATER_Z,
            'quay_rect_xyxy':QUAY_RECT,'plaza_plane':'.48-.009*x+.0015*y','plaza_grade_percent':math.hypot(.009,.0015)*100,
            'western_baseline_grade_percent':5.5,'northern_baseline_grade_percent':3.5,'quay_transition_grade_percent':6.5},
        'roads':roads,'building_pads':pads,'beach_cross_sections':beach_sections,'park_pond':pond,
        'contour_segments':contour_segments(),
        'drainage':{'scope':'Conceptual visible stormwater furniture and flow intent; no hydraulic sizing, flood design or discharge consent is implied.',
            'grates_and_outfalls':drainage,'flow_arrows':flow_arrows,
            'quay_note':'Deck nominal 1.615m; shallow channel bottoms and iron grates sit below/flush with this datum. Quay sheet-fall arrow states intended local drainage, not a solved deck mesh gradient.'},
        'validation':{'public_street_max_grade_percent':max(r['max_grade_percent'] for r in public),
            'public_ribbon_edge_max_grade_percent':max(r['max_ribbon_edge_grade_percent'] for r in public),
            'public_paving_apron_edge_max_grade_percent':max(r['max_paving_apron_edge_grade_percent'] for r in public),
            'public_street_over_8_percent':[r['id'] for r in public if r['max_grade_percent']>8],
            'entry_step_routes':[r['id'] for r in roads if r['treatment']=='entry_steps_required'],
            'other_grade_reviews':[r['id'] for r in roads if r['treatment']=='grade_review_required'],
            'maximum_parcel_cut_m':max(p['max_cut_m'] for p in pads),'maximum_parcel_fill_m':max(p['max_fill_m'] for p in pads),
            'sample_spacing_m':.25,'scope':'Elevation geometry proposal; no storm capacity, accessibility, flood or engineering certification.'}}


def render_topography(plan):
    """Vector contours/annotations over a height raster; PNG for quick review."""
    from PIL import Image, ImageDraw, ImageFont
    extent=(-65.,-57.,70.,59.)
    x0,y0,x1,y1=extent;scale=7.;left,top=70,108
    pw,ph=round((x1-x0)*scale),round((y1-y0)*scale)
    W,H=pw+430,ph+212
    image=Image.new('RGB',(W,H),'#f5f2e9');draw=ImageDraw.Draw(image)
    def xy(p):return(left+(p[0]-x0)*scale,top+(y1-p[1])*scale)
    fontpath='C:/Windows/Fonts/segoeui.ttf'
    def font(size):
        try:return ImageFont.truetype(fontpath,size)
        except OSError:return ImageFont.load_default()
    def line(points,fill,width=1):draw.line([xy(p) for p in points],fill=fill,width=width)
    # 0.5m height raster, enlarged without inventing fine terrain detail.
    rw,rh=270,232;raster=Image.new('RGB',(rw,rh));pixels=raster.load()
    def color(x,y,z):
        if z==WATER_Z:return (153,190,205)
        if plan.get('park_pond') and pond_radius(x,y)<=1:return (120,172,166)
        coast=coast_x(y)
        if coast-beach_width(y)<x<coast and not (31<=x<=66 and 37<=y<=55):
            return (222,209,179) if y<29 else (156,159,147)
        t=clamp((z-.2)/4.5,0,1);a,b=(212,222,191),(165,143,107)
        return tuple(round(a[k]*(1-t)+b[k]*t) for k in range(3))
    for j in range(rh):
        y=y1-(j+.5)*(y1-y0)/rh
        for i in range(rw):
            x=x0+(i+.5)*(x1-x0)/rw;pixels[i,j]=color(x,y,surface_height(x,y))
    raster=raster.resize((pw,ph),Image.Resampling.BILINEAR);image.paste(raster,(left,top))
    stream=io.BytesIO();raster.save(stream,format='PNG');encoded=base64.b64encode(stream.getvalue()).decode()
    svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
        '<rect width="100%" height="100%" fill="#f5f2e9"/>',
        f'<image x="{left}" y="{top}" width="{pw}" height="{ph}" href="data:image/png;base64,{encoded}"/>']
    def text_label(x,y,text,size=14,fill='#26352e'):
        from html import escape
        draw.text((x,y),text,font=font(size),fill=fill)
        svg.append(f'<text x="{x:.1f}" y="{y+size:.1f}" font-family="Segoe UI, sans-serif" font-size="{size}" fill="{fill}">{escape(text)}</text>')
    def vector_line(points,fill,width=1,dash=None):
        line(points,fill,max(1,round(width)))
        pts=' '.join(f'{xy(p)[0]:.2f},{xy(p)[1]:.2f}' for p in points)
        extra=f' stroke-dasharray="{dash}"' if dash else ''
        svg.append(f'<polyline points="{pts}" fill="none" stroke="{fill}" stroke-width="{width}"{extra}/>')
    contour_counts=defaultdict(int)
    for path in plan['contour_segments']:
        level=path['level_m'];vector_line(path['points'],'#7d775d',1.1 if level%1==0 else .6)
        contour_counts[str(level)]+=len(path['points'])-1
    # Streets are drawn at real scale over contours; their fall is evaluated
    # independently at 0.25m spacing, not estimated from this raster.
    roadreports={r['id']:r for r in plan['roads']}
    for r in MASTERPLAN['streets']:
        color='#c1c1b9' if r['kind']=='public_street' else '#dfd8c8'
        vector_line(r['points'],color,r['width']*scale)
        if roadreports[r['id']]['treatment']=='entry_steps_required':vector_line(r['points'],'#a45a3b',1.7)
    for b in MASTERPLAN['buildings']:
        points=[xy(p) for p in b['footprint_polygon']]
        draw.polygon(points,fill='#ece7d9',outline='#4b5b58',width=1)
        pts=' '.join(f'{x:.2f},{y:.2f}' for x,y in points)
        svg.append(f'<polygon points="{pts}" fill="#ece7d9" stroke="#4b5b58" stroke-width="1"/>')
    for path in LANDSCAPE.get('paths',[]):
        vector_line(path['points'],'#d8cfb5',path.get('width_m',1.5)*scale)
    if plan.get('park_pond'):
        p=pond_spec();cx,cy=p['center']
        for key,stroke in [('water_radii_m','#477f80'),('outer_bank_radii_m','#6b8863')]:
            rx,ry=p[key]
            points=[[cx+rx*math.cos(i*math.tau/80),cy+ry*math.sin(i*math.tau/80)] for i in range(81)]
            vector_line(points,stroke,1.8)
    for feature in plan['drainage']['grates_and_outfalls']:
        p=xy(feature['center']);outfall='outfall' in feature['kind'];r=4 if outfall else 3
        draw.rectangle((p[0]-r,p[1]-r,p[0]+r,p[1]+r),fill='#256b85' if outfall else '#263f49')
        svg.append(f'<rect x="{p[0]-r:.2f}" y="{p[1]-r:.2f}" width="{r*2}" height="{r*2}" fill="'+('#256b85' if outfall else '#263f49')+'"/>')
    for arrow in plan['drainage']['flow_arrows']:
        a,b=arrow['points'];vector_line([a,b],'#21758a',2.4)
        angle=math.atan2(b[1]-a[1],b[0]-a[0])
        for turn in (-.45,.45):vector_line([b,[b[0]-1.3*math.cos(angle+turn),b[1]-1.3*math.sin(angle+turn)]],'#21758a',2.4)
    spots=[('Mill',-56,35),('Church',-23,29),('Library',-18,11),('Square',-3,0),('Cafe',11.5,0),
        ('Hotel',30,30),('Cannery',22,47),('Quay',51,50),('Sea',61,8),('West',-56,-30),('Park pond',26,-42)]
    for label,x,y in spots:
        z=surface_height(x,y);p=xy((x,y))
        draw.ellipse((p[0]-2,p[1]-2,p[0]+2,p[1]+2),fill='#1e3840')
        text_label(p[0]+5,p[1]-17,f'{label} {z:+.2f}',12)
    text_label(left,22,'LIVING TOWN / TOPOGRAPHY & DRAINAGE',26)
    text_label(left,61,f"Authored fictional Breton site · fixed {len(MASTERPLAN['buildings'])}-building / {len(MASTERPLAN['streets'])}-route plan · 0.50m contours",16)
    lx=left+pw+28;ly=top+12
    labels=[('LOCAL LEVELS',19),('Sea datum −0.880m',16),('Quay deck +1.615m',16),('Freeboard 2.495m',16),('',10),
        ('CIRCULATION',19),(f"Public roads ≤ {plan['validation']['public_street_max_grade_percent']:.2f}%",16),
        ('Square fall 0.91% east/south',16),('Road crossfall/crown 1.0%',16),('Rust paths: threshold steps',16),('',10),
        ('LAND & WATER',19),('West rise: 5.5% baseline',16),('North rise: 3.5% baseline',16),('Finite rounded inland plateau',16),
        ('Broad sand: low south coast',16),('Stone edge: narrowing north',16),('Lined pond / graded planted banks',16),('Pond water −0.120m / bed −0.920m',14),('',10),('EARTHWORKS',19),
        (f"Maximum parcel cut {plan['validation']['maximum_parcel_cut_m']:.2f}m",16),
        (f"Maximum parcel fill {plan['validation']['maximum_parcel_fill_m']:.2f}m",16),('Level pads / stepped row joints',16),('',10),
        ('DRAINAGE',19),('Blue arrows: intended runoff',16),('Dark squares: iron grates',16),('Blue squares: culvert outlets',16),
        ('Conceptual furniture/flow only',14),('No surveyed or flood datum',14)]
    for label,size in labels:text_label(lx,ly,label,size);ly+=size+9
    # North and metric bar.
    vector_line([[-61,46],[-61,53]],'#26352e',2.6);vector_line([[-62,51],[-61,53],[-60,51]],'#26352e',2.6)
    p=xy((-61,54));text_label(p[0]-5,p[1]-12,'N',15)
    bar=[[-60,-42],[-40,-42]];vector_line(bar,'#26352e',4)
    for x in (-60,-50,-40):vector_line([[x,-42.6],[x,-41.4]],'#26352e',2)
    p=xy((-60,-42));text_label(p[0],p[1]+9,'0                 10                20m',12)
    text_label(left,top+ph+47,'Contours include graded pads and quay. Short entrance steps are intentional; no vehicular route exceeds 8%.',14)
    text_label(left,top+ph+73,'Dry land: deterministic height field. Beach/water: explicit cross-sections. All model X/Y coordinates remain frozen.',13)
    svg.append('</svg>')
    (ROOT/'concept/05_topography_and_drainage.svg').write_text('\n'.join(svg),encoding='utf-8')
    image.save(ROOT/'concept/05_topography_and_drainage.png')
    plan['contour_map']={'interval_m':.5,'grid_m':1,'extent_xyxy':extent,'segments_per_level':contour_counts,
        'svg':'concept/05_topography_and_drainage.svg','png':'concept/05_topography_and_drainage.png'}


def main():
    plan=make_plan()
    render_topography(plan)
    (ROOT/'terrain_plan.json').write_text(json.dumps(plan,indent=2),encoding='utf-8')
    print(json.dumps(plan['validation'],indent=2))


if __name__=='__main__':main()
