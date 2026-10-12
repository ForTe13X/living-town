"""Compile the optional delivered-town spatial profile without changing base data.

Normal Python only. Canonical model metres are rasterized independently on each
plane; the old tile map is used solely for stable gameplay IDs and advertisements.
Run: python tools/build_town_profile.py
"""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import math
from collections import Counter, deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art/living_town"
OUT = ROOT / "game/data/town3d"
REPORT = ROOT / "docs/town_bridge/profile_compile_report.json"
BASE_NAMES = ("map", "spaces", "interiors", "agents", "buildings", "jobs",
              "production", "logistics", "housing", "festivals", "elections")
OUTDOOR_ORIGIN = (-66.0, 58.0)
OUTDOOR_SIZE = (268, 216)  # x[-66,68], y[-50,58], cell centres, metres
OUTDOOR_CELL = .5
INTERIOR_CELL = .25
AGENT_RADIUS = .08  # planar conservative inset; visual body is a separate projection


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def inside(x, y, rect, margin=0):
    return rect[0]-margin <= x <= rect[2]+margin and rect[1]-margin <= y <= rect[3]+margin


def local_to_world(b, x, y):
    a = math.radians(b['yaw_degrees'])
    c, s = math.cos(a), math.sin(a)
    return b['center'][0]+x*c-y*s, b['center'][1]+x*s+y*c


def world_to_local(b, x, y):
    a = math.radians(b['yaw_degrees'])
    c, s = math.cos(a), math.sin(a)
    x, y = x-b['center'][0], y-b['center'][1]
    return x*c+y*s, -x*s+y*c


def cell_xy(plane, cell):
    s = plane['cell_size_m']
    origin = plane.get('origin_local_m', plane.get('origin_world_m'))
    return origin[0]+(cell[0]+.5)*s, origin[1]-(cell[1]+.5)*s


def xy_cell(plane, x, y):
    s = plane['cell_size_m']
    origin = plane.get('origin_local_m', plane.get('origin_world_m'))
    return int(math.floor((x-origin[0])/s)), int(math.floor((origin[1]-y)/s))


def rect_grid(plane, bounds):
    s = plane['cell_size_m']; ox, oy = plane.get('origin_local_m', plane.get('origin_world_m'))
    x0 = math.floor((bounds[0]-ox)/s); x1 = math.ceil((bounds[2]-ox)/s)
    y0 = math.floor((oy-bounds[3])/s); y1 = math.ceil((oy-bounds[1])/s)
    return [x0, y0, x1-x0, y1-y0]


def components(w, h, blocked):
    labels = {}; sizes = Counter(); comp = 0
    for y in range(h):
        for x in range(w):
            p = (x, y)
            if p in blocked or p in labels:
                continue
            q = deque([p]); labels[p] = comp
            while q:
                cx, cy = q.popleft(); sizes[comp] += 1
                for n in ((cx-1,cy),(cx+1,cy),(cx,cy-1),(cx,cy+1)):
                    if 0 <= n[0] < w and 0 <= n[1] < h and n not in blocked and n not in labels:
                        labels[n] = comp; q.append(n)
            comp += 1
    return labels, sizes


def nearest_open(plane, labels, xy, max_distance=None, component=None, allowed_bounds=None):
    candidates = []
    for p, c in labels.items():
        if component is not None and c != component:
            continue
        x,y = cell_xy(plane,p)
        if allowed_bounds is not None and not inside(x,y,allowed_bounds):
            continue
        dist = math.hypot(x-xy[0],y-xy[1])
        if max_distance is None or dist <= max_distance+1e-8:
            candidates.append((dist,p[1],p[0],p))
    if not candidates:
        raise ValueError(f"No genuine open cell near {plane['space']}/{plane['floor']} {xy}, max={max_distance}")
    return min(candidates)[3]


def partition_blocks(part, x, y):
    axis = part['axis']; coord = part['coordinate_m']; lo,hi = part['span_m']
    across, along = (x,y) if axis == 'x' else (y,x)
    if abs(across-coord) > part['thickness_m']/2+AGENT_RADIUS or not lo-AGENT_RADIUS <= along <= hi+AGENT_RADIUS:
        return False
    for opening in part['openings']:
        # A service hatch is not a pedestrian opening.
        if opening.get('bottom_m',0) > .05 or opening.get('height_m',0) < 1.8:
            continue
        half = opening['width_m']/2-AGENT_RADIUS
        if abs(along-opening['center_m']) < half:
            return False
    return True


def compile_profile():
    base = {name: read(ROOT/f'game/data/{name}.json') for name in BASE_NAMES}
    master = read(ART/'masterplan.json'); interiors_plan = read(ART/'interior_plan.json')
    manifest = read(ART/'town_manifest.json'); landscape = read(ART/'landscape_plan.json')
    spec = importlib.util.spec_from_file_location('town_bridge_terrain', ART/'tools/terrain_profile.py')
    terrain = importlib.util.module_from_spec(spec); spec.loader.exec_module(terrain)
    buildings = {b['id']:b for b in master['buildings']}
    modeled = {b['id']:b for b in interiors_plan['buildings']}
    native = {b['id']:b for b in manifest['buildings']}
    assert set(buildings) == set(modeled) == set(native) and len(buildings) == 49

    # Each physical building has exactly one canonical Space. Existing Space IDs
    # survive; the old test loft is a real two-storey residential model now.
    assigned = {'Main_cafe':'cafe','Main_home':'home',
                'Main_shop':'shop','Main_library':'library','Main_wash':'wash','Main_work':'work',
                'Port_Warehouse_Exterior':'port_warehouse','lot_00_chapel':'chapel',
                'lot_01_mairie':'mairie','lot_04_bakery':'bakery','lot_05_creperie':'creperie',
                'lot_06_halles':'halles','lot_07_hotel':'hotel'}
    loft = next(b for b in master['buildings'] if b['id'] not in assigned and b['floors'] == 2 and b['kind'] not in ('windmill','cannery','netshed'))
    assigned[loft['id']] = 'test_loft'
    # Current core home2 has two distinct functional beds upstairs. The named
    # Main_home2 model is one storey, so map that semantic dwelling explicitly
    # onto the existing three-storey house with two actual beds. No fake level
    # or additional stair geometry is introduced.
    home2_id = 'lot_12_halftimber'
    assert home2_id not in assigned and modeled[home2_id]['floors'] == 3
    assigned[home2_id] = 'home2'
    for bid in buildings:
        assigned.setdefault(bid, 'model_'+bid.lower())
    reverse = {v:k for k,v in assigned.items()}
    assert len(reverse) == 49

    projection = {'schema':'living_town.projection3d.v1','coordinate_system':{
        'source':'Blender right-handed metres, Z up; local front is -Y',
        'godot':'Vector3(world_x, elevation_z, -world_y)',
        'cell_center_formula':'origin + ((cx+.5)*cell_size, -(cy+.5)*cell_size)',
        'interior_world_formula':'rotate(local_xy,yaw_degrees) + center_world_m.xy'},
        'planes':{},'building_spaces':assigned,'portal_projections':{},'interaction_bindings':{}}
    planes = projection['planes']; grids = {}; asset_lookup = {}; room_records = {}
    spaces_out = {'_note':'Optional model-aligned profile. Base spaces.json remains unchanged.',
                  'spaces':{},'portals':[]}
    interiors_out = {'_note':'Current core advertisements and bank/civic UI markers are compiled; geometry is the delivered GLB.'}
    connectivity = []; room_checks = []
    for bid,b in buildings.items():
        plan = modeled[bid]; space = assigned[bid]; w,d = plan['footprint_m']
        gw,gh = math.ceil(w/INTERIOR_CELL),math.ceil(d/INTERIOR_CELL)
        old = copy.deepcopy(base['spaces']['spaces'].get(space,{}))
        old.update({'kind':'interior','label':old.get('label',bid),'bounds':[0,0,gw,gh],
                    'floors':[f'{l+1}f' for l in range(plan['floors'])],'default_floor':'1f',
                    'model_building_id':bid})
        # Extra spaces are visitable geometry, not additional autonomous adverts.
        old.setdefault('public_venue',False)
        spaces_out['spaces'][space] = old; interiors_out[space] = {}
        for level in plan['levels']:
            ln = level['level']; floor = f'{ln+1}f'; key = space+'/'+floor
            plane = {'space':space,'floor':floor,'building_id':bid,'level':ln,
                     'cell_size_m':INTERIOR_CELL,'origin_local_m':[-w/2,d/2],
                     'center_world_m':native[bid]['center_m'],'yaw_degrees':b['yaw_degrees'],
                     'finished_floor_z_m':native[bid]['center_m'][2]+level['finished_floor_local_z_m'],
                     'grid_size':[gw,gh]}
            planes[key] = plane
            assets = [a for room in level['rooms'] for a in room['assets']]
            for a in assets:
                asset_lookup[a['id']] = (key,a)
            blocked = set()
            for y in range(gh):
                for x in range(gw):
                    px,py = cell_xy(plane,(x,y))
                    if not inside(px,py,plan['clear_bounds_m'],-AGENT_RADIUS):
                        blocked.add((x,y)); continue
                    if any(partition_blocks(p,px,py) for p in level['partitions']):
                        blocked.add((x,y)); continue
                    # Stairs are an explicit between-plane traversal, never a
                    # walkable flat shortcut through a slab void or stair body.
                    if plan['core'] and inside(px,py,plan['core']['bounds'],.015):
                        blocked.add((x,y)); continue
                    if any(inside(px,py,a['footprint_m'],AGENT_RADIUS) for a in assets if a.get('collision_proxy',True)):
                        blocked.add((x,y))
            labels,sizes = components(gw,gh,blocked)
            if not sizes:
                raise ValueError('Entire interior blocked: '+key)
            main = max(sizes,key=sizes.get)
            entry_target = (0,-d/2+.48) if ln == 0 else (plan['core']['center_x'],plan['core']['bounds'][3]+.28)
            entry = nearest_open(plane,labels,entry_target,.65,main)
            if ln == 0:
                # Door centre must enter the physical entrance sequence, not a
                # nearest disconnected room on the other side of a partition.
                assert abs(cell_xy(plane,entry)[0]) <= .54, (key,'door axis',entry)
            # Reject an inaccessible actual activity room, rather than quietly
            # carving arbitrary portal cells through a wall to rescue the grid.
            for room in level['rooms']:
                rr = rect_grid(plane,room['bounds_m'])
                enclosed = bool(room['assets']) and b['kind'] != 'halles' and 'gallery' not in room['purpose']
                room_records[room['id']] = {'rect':rr,'space':space,'floor':floor,
                    'enclosed':enclosed,'type':room['purpose'],'building':bid,
                    'owner':'aria' if space=='cafe' and ln>0 else '',
                    'model_room_id':room['id'],'bounds_m':room['bounds_m']}
                candidates = [p for p,c in labels.items() if c==main and inside(*cell_xy(plane,p),room['bounds_m'])]
                active = bool(room['assets'])
                room_checks.append({'id':room['id'],'plane':key,'activity_room':active,
                                    'connected_open_cells':len(candidates)})
                if active and not candidates:
                    raise ValueError('Activity room unreachable in genuine raster: '+room['id'])
            # Tiny cells stranded behind inset trims/furniture are excluded from
            # nav. No blocked geometry is made walkable.
            blocked.update(p for p,c in labels.items() if c!=main)
            labels = {p:c for p,c in labels.items() if c==main}
            grids[key] = {'blocked':blocked,'labels':labels,'component':main,'entry':entry,'assets':assets,'level':level}
            content = {'furniture':[],'nav_blockers':[list(p) for p in sorted(blocked,key=lambda p:(p[1],p[0]))],
                       'model_building_id':bid,'model_level':ln,'cell_size_m':INTERIOR_CELL}
            interiors_out[space][floor] = content
            connectivity.append({'plane':key,'open_cells':len(labels),'excluded_island_cells':sum(v for c,v in sizes.items() if c!=main),
                                 'entry_cell':list(entry),'initial_components':len(sizes)})

    # Outdoor authority is land/pond/quay and the actual rotated parcel shells,
    # not any affine transformation of the old map's rectangles.
    town = {'space':'town','floor':'outdoor','building_id':None,'level':-1,
            'cell_size_m':OUTDOOR_CELL,'origin_world_m':list(OUTDOOR_ORIGIN),
            'grid_size':list(OUTDOOR_SIZE),'terrain_heights_m':[]}
    planes['town/outdoor'] = town
    ow,oh = OUTDOOR_SIZE; blocked = set(); heights = town['terrain_heights_m']
    trees = landscape.get('street_trees',[])
    for y in range(oh):
        for x in range(ow):
            wx,wy = cell_xy(town,(x,y))
            quay = inside(wx,wy,terrain.QUAY_RECT)
            coast = terrain.coast_x(wy)
            wet = (wx >= coast and not quay) or terrain.pond_radius(wx,wy) <= 1.04
            if wet:
                blocked.add((x,y))
            z = terrain.design_height(wx,wy)
            if not quay and wx > coast-terrain.beach_width(wy):
                z = terrain.beach_height(wx,wy)
            heights.append(round(z,5))
            if not wet:
                for b in buildings.values():
                    lx,ly = world_to_local(b,wx,wy)
                    if abs(lx) <= b['width']/2+.08 and abs(ly) <= b['depth']/2+.08:
                        blocked.add((x,y)); break
            if any(math.hypot(wx-t['xy'][0],wy-t['xy'][1]) < .23 for t in trees):
                blocked.add((x,y))
    labels,sizes = components(ow,oh,blocked); main = max(sizes,key=sizes.get)
    blocked.update(p for p,c in labels.items() if c!=main)
    labels = {p:c for p,c in labels.items() if c==main}
    grids['town/outdoor'] = {'blocked':blocked,'labels':labels,'component':main}
    spaces_out['spaces'] = {'town':{'kind':'outdoor','label':'Living Town','bounds':[0,0,ow,oh],
                                       'floors':['outdoor'],'default_floor':'outdoor'},**spaces_out['spaces']}

    old_portals = {p['id']:p for p in base['spaces']['portals']}
    exterior_ids = {p['to']['space']:p['id'] for p in old_portals.values() if p['from']['space']=='town'}
    stair_ids = {p['from']['space']:p['id'] for p in old_portals.values() if p['from']['space']==p['to']['space']}
    def endpoint(space,floor,pos):
        return {'space':space,'floor':floor,'pos':list(pos)}
    def add_portal(pid,fr,to,default):
        p = copy.deepcopy(old_portals.get(pid,default)); p.update({'id':pid,'from':fr,'to':to,'bidirectional':True})
        spaces_out['portals'].append(p)
        def world(e):
            plane=planes[e['space']+'/'+e['floor']]; xy=cell_xy(plane,e['pos'])
            if plane['building_id'] is None:
                return [*xy,heights[e['pos'][1]*ow+e['pos'][0]]]
            return [*local_to_world(buildings[plane['building_id']],*xy),plane['finished_floor_z_m']]
        projection['portal_projections'][pid]={'from_world_m':world(fr),'to_world_m':world(to),
            'kind':'entrance' if fr['space']=='town' else 'stairs','model_building_id':reverse[to['space']]}
    for bid,b in buildings.items():
        space=assigned[bid]; plan=modeled[bid]
        outward=b['front_outward']; ft=b['front_threshold']
        outside=(ft[0]+outward[0]*.52,ft[1]+outward[1]*.52)
        outdoor_cell=nearest_open(town,labels,outside,.8,main)
        pid=exterior_ids.get(space,'p_model_'+bid.lower()+'_door')
        add_portal(pid,endpoint('town','outdoor',outdoor_cell),endpoint(space,'1f',grids[space+'/1f']['entry']),
                   {'kind':'door','access':'public','traversal_cost':1})
        for ln in range(plan['floors']-1):
            lower=space+f'/{ln+1}f'; upper=space+f'/{ln+2}f'; core=plan['core']
            foot=nearest_open(planes[lower],grids[lower]['labels'],(core['center_x'],core['bounds'][1]-.27),.68,grids[lower]['component'])
            head=nearest_open(planes[upper],grids[upper]['labels'],(core['center_x'],core['bounds'][3]+.27),.68,grids[upper]['component'])
            pid=stair_ids.get(space) if ln==0 else None
            pid=pid or f'p_model_{bid.lower()}_stairs_{ln+1}_{ln+2}'
            add_portal(pid,endpoint(space,f'{ln+1}f',foot),endpoint(space,f'{ln+2}f',head),{'kind':'stairs','access':'public','traversal_cost':2})
    assert len(spaces_out['portals']) == 89
    assert set(old_portals) <= {p['id'] for p in spaces_out['portals']}

    used_positions = Counter(); bindings=projection['interaction_bindings']; all_defs={}
    def select_asset(space,kinds,ordinal=0,level=None):
        bid=reverse[space]; choices=[]
        for lv in modeled[bid]['levels']:
            if level is not None and lv['level'] != level:
                continue
            for room in lv['rooms']:
                for a in room['assets']:
                    if a['kind'] in kinds:
                        choices.append((kinds.index(a['kind']),lv['level'],a['id'],space+f"/{lv['level']+1}f",a))
        choices.sort()
        if not choices:
            raise ValueError(f'No actual fixture {space} {kinds} level={level}')
        bestkind=choices[0][0]; choices=[v for v in choices if v[0]==bestkind]
        selected=choices[ordinal%len(choices)]
        return selected[3],selected[4]
    def asset_position(key,asset):
        plane=planes[key]; grid=grids[key]; rect=asset['footprint_m']; cx,cy=asset['center_m']
        candidates=[]
        for p in grid['labels']:
            x,y=cell_xy(plane,p)
            dx=max(rect[0]-x,0,x-rect[2]); dy=max(rect[1]-y,0,y-rect[3])
            edge_dist=math.hypot(dx,dy)
            if .045 <= edge_dist <= .65:
                # Reuse is permitted for truly shared fixture actions; favour
                # another adjacent standing cell before crowding one marker.
                candidates.append((used_positions[(key,p)]*.4+edge_dist+.02*math.hypot(x-cx,y-cy),p[1],p[0],p))
        if not candidates:
            raise ValueError('No accessible fixture approach: '+asset['id'])
        pos=min(candidates)[3];used_positions[(key,pos)]+=1
        return pos
    def bind(obj,key,asset=None,world=None,note=None):
        obj=copy.deepcopy(obj); space,floor=key.split('/')
        pos=asset_position(key,asset) if asset else nearest_open(planes[key],grids[key]['labels'],world,1.5,grids[key]['component'])
        obj.update({'space':space,'floor':floor,'pos':list(pos),'area':space+':'+floor if space!='town' else '',
                    'navigation_marker':True})
        info={'plane':key,'cell':list(pos),'approach_local_m':list(cell_xy(planes[key],pos)),
              'model_asset_id':asset['id'] if asset else None,'model_asset_kind':asset['kind'] if asset else None,
              'note':note or 'Legacy action at a reachable standing cell adjacent to an actual compatible fixture.'}
        if asset:
            info['fixture_center_local_m']=asset['center_m'];info['fixture_footprint_m']=asset['footprint_m']
        bindings[obj['id']]=info; all_defs[obj['id']]=obj
        return obj
    def fixture_obj(obj,space,kinds,ordinal=0,level=None,note=None):
        key,asset=select_asset(space,kinds,ordinal,level)
        return bind(obj,key,asset,note=note)

    # Baseline interior compiler, faithfully retaining old object IDs and ads.
    old_interior=[]; used={}
    for space,fs in base['interiors'].items():
        if space.startswith('_') or not isinstance(fs,dict): continue
        for floor,content in fs.items():
            if not isinstance(content,dict):continue
            for fu in content.get('furniture',[]):
                if not fu.get('advertises'):continue
                stem=space+floor+'_'+fu.get('slot','obj');seq=used.get(stem,0);used[stem]=seq+1
                oid=stem+(f'_{seq}' if seq else '')
                old_interior.append((space,floor,oid,fu))
    slot_kinds={'bed':['bed'],'bed_double':['bed'],'toilet':['toilet'],
        'basin':['basin'],'bathtub':['bathtub','shower_screen'],'sofa':['sofa','banquette','lounge_chair'],
        'armchair':['lounge_chair','sofa'],'bookshelf':['bookshelf'],
        'barstool':['cafe_table_set','banquette'],'table':['cafe_table_set','dining_table'],
        'bistro':['cafe_table_set','dining_table','retail_counter'],
        'altar':['altar'],'pew':['pew'],'market_stall':['market_stall'],
        'piano':['service_console','writing_desk'],'painting_sea':['bookshelf','cupboard','service_console','altar','market_stall','writing_desk'],
        'painting_parasol':['bread_rack','bookshelf','retail_counter']}
    ordinals=Counter()
    for space,floor,oid,fu in old_interior:
        slot=fu['slot']; target_space=space; level=0; kinds=slot_kinds.get(slot,['writing_desk'])
        if space=='home' and slot=='bed':
            target_space='home' if oid=='home1f_bed' else 'test_loft';level=1
        elif space=='home' and slot=='sofa':target_space='test_loft'
        elif space=='home' and slot=='toilet':level=1
        elif space=='home2' and floor=='2f':
            level=2 if slot=='bed' and oid.endswith('_1') else 1
        elif space=='cafe' and floor=='2f':level=1
        elif slot=='counter':
            kinds=['cafe_counter','retail_counter','writing_desk']
            if space=='bakery' and oid.endswith('_counter'):kinds=['kitchen_run'];
            elif space=='bakery':kinds=['retail_counter']
        # Legacy piano and viewed paintings are existing gameplay, but are not
        # separate model furniture assemblies. Bind them to the venue's actual
        # public music/art surface without claiming a new modeled piano mesh.
        note=None
        if slot=='piano':note='Preserved legacy music action at hotel lounge console; the delivered model has no dedicated piano assembly.'
        elif slot.startswith('painting'):note='Preserved art-viewing action at a public room wall/decor surface; not a new decoration advertisement.'
        n=ordinals[(space,slot)];ordinals[(space,slot)]+=1
        obj=fixture_obj({'id':oid,'type':fu.get('label',slot),'advertises':fu['advertises'],'staff':fu.get('staff',False)},target_space,kinds,n,level,note)
        target=interiors_out[obj['space']][obj['floor']]
        target['furniture'].append({'slot':slot,'object_id':oid,'label':fu.get('label',slot),
            'pos':obj['pos'],'staff':obj.get('staff',False),'advertises':copy.deepcopy(fu['advertises']),
            'navigation_marker':True,'model_asset_id':bindings[oid]['model_asset_id']})

    # These are read-only/transactional UI anchors, not NPC advertisements or
    # world.objects entries. Keep the exact special marker flags that current
    # Sim.bank_counter_cell/civic_observatory_cell queries.
    ui_markers=[]
    for space,flag,oid,kinds,note in [
        ('halles','bank_counter','bank_counter',['market_stall'],
         'Current cooperative-bank UI at an existing market counter; no new NPC advertisement.'),
        ('mairie','civic_observatory','civic_observatory',['writing_desk','service_console'],
         'Read-only civic notice interface at the public reception surface; no new NPC advertisement.')]:
        original=next(fu for fu in base['interiors'][space]['1f']['furniture'] if fu.get(flag))
        key,asset=select_asset(space,kinds,0,0)
        pos=asset_position(key,asset)
        marker=copy.deepcopy(original)
        marker.update({'pos':list(pos),'navigation_marker':True,'model_asset_id':asset['id']})
        marker.pop('size',None)  # nav is authoritative raster, not old tile art dimensions
        interiors_out[space]['1f']['furniture'].append(marker)
        bindings[oid]={'plane':key,'cell':list(pos),'approach_local_m':list(cell_xy(planes[key],pos)),
            'model_asset_id':asset['id'],'model_asset_kind':asset['kind'],
            'fixture_center_local_m':asset['center_m'],'fixture_footprint_m':asset['footprint_m'],
            'anchor_only':True,'marker_flag':flag,'note':note}
        ui_markers.append((space,flag,oid,original))

    map_objects=[]
    for obj in base['map']['objects']:
        oid=obj['id']
        if oid=='bed_1':o=fixture_obj(obj,'hotel',['bed'],0,1)
        elif oid=='bed_2':o=fixture_obj(obj,'bakery',['bed'],0,1)
        elif oid=='stove_1':o=fixture_obj(obj,'cafe',['cafe_table_set'],0,0)
        elif oid=='counter_1':o=fixture_obj(obj,'cafe',['cafe_counter'],0,0)
        elif oid=='bath_1':o=fixture_obj(obj,'wash',['shower_screen','bathtub'],0,0)
        elif oid=='desk_1':o=fixture_obj(obj,'work',['workbench'],0,0)
        elif oid=='bench_1':o=bind(obj,'town/outdoor',world=(-8,3),note='Public square social/sun interaction; preserved core action anchor.')
        elif oid=='arcade_1':o=bind(obj,'town/outdoor',world=(0,-3),note='Preserved play action at open square activity space; no dedicated arcade cabinet in supplied model.')
        elif oid=='cliff_overlook_1':o=bind(obj,'town/outdoor',world=(40.5,12),note='Preserved sea-view action on the actual connected coastal promenade; no invented cliff mesh.')
        elif oid=='upper_lane_bench_1':o=bind(obj,'town/outdoor',world=(-45,12.5),note='Preserved street-view rest activity on the connected upper western lane.')
        else:raise ValueError('Unmapped map object '+oid)
        map_objects.append(o)

    production=copy.deepcopy(base['production'])
    work_out=[]
    for obj in production.get('worksites',[]):
        oid=obj['id']
        if oid=='desk_workbench':o=fixture_obj(obj,'work',['workbench'],0,0)
        elif oid=='stove_home':o=fixture_obj(obj,'home',['kitchen_run'],0,0)
        elif oid=='counter_grocery':o=fixture_obj(obj,'shop',['retail_counter'],0,0)
        elif oid=='counter_stall':o=fixture_obj(obj,'halles',['market_stall'],0,0)
        else:
            world={'bench_sweepcart':(-5,-6),'bench_pier':(58,37.5),'bench_brickpile':(-48,12.5),
                   'bench_bathing':(44,16),'bench_boat':(60,39)}[oid]
            o=bind(obj,'town/outdoor',world=world,note='Preserved outdoor work/activity at an actual open accessible site in the matching district.')
        work_out.append(o)
    production['worksites']=work_out

    # Outdoor district rectangles classify interactions, not building collision.
    areas={}
    def area_rect(name,bounds,kind='plaza',**extra):
        areas[name]={'rect':rect_grid(town,bounds),'kind':kind,'type':kind,'label':base['map']['areas'].get(name,{}).get('label',name),**extra}
    area_rect('plaza',[-13,-8,7,8]);area_rect('dock',[31,37,66,55],population_anchor=False,route='east_ocean',facing='east')
    area_rect('cliff_walk',[39,8,48,14],population_anchor=False)
    area_rect('upper_lane',[-58,9,-18,16],population_anchor=False)
    area_rect('north_pier',[42,14,62,41],population_anchor=True)
    for oldname in ('home','home2','cafe','shop','library','wash','work'):
        b=buildings[reverse[oldname]];points=b['footprint_polygon'];xs=[p[0] for p in points];ys=[p[1] for p in points]
        area_rect(oldname,[min(xs)-2,min(ys)-2,max(xs)+2,max(ys)+2],base['map']['areas'][oldname].get('kind',base['map']['areas'][oldname].get('type','public')))
    area_rect('commons',[-66,-50,68,58])
    def area_at(pos):
        for name,a in areas.items():
            x,y,w,h=a['rect']
            if x<=pos[0]<x+w and y<=pos[1]<y+h:return name
        return ''
    for obj in map_objects+work_out:
        if obj['space']=='town':obj['area']=area_at(obj['pos'])
    logistics=copy.deepcopy(base['logistics'])
    for index,obj in enumerate(logistics.get('nodes',[])):
        o=bind(obj,'town/outdoor',world=(63,43+index*5),note='Actual engineered quay cargo standing cell; stable manifest node ID.')
        o['area']=area_at(o['pos']);logistics['nodes'][index]=o
    for index,c in enumerate(logistics.get('carriers',[])):
        c['berth']=list(xy_cell(town,67,43+index*5));c['facing']='west'
    areas['dock']['berth']=logistics['carriers'][0]['berth']

    festivals=copy.deepcopy(base['festivals'])
    for event in festivals.get('festivals',{}).values():
        for obj in event.get('objects',[]):
            obj['pos']=list(nearest_open(town,labels,(-3,0),1.0,main))
    elections=copy.deepcopy(base['elections'])
    if isinstance(elections.get('on_pass',{}).get('object'),dict):
        elections['on_pass']['object']['pos']=list(nearest_open(town,labels,(2,2),1.,main))

    agents=copy.deepcopy(base['agents'])
    bed_for={'aria':'cafe2f_bed','ben':'home1f_bed','coco':'home22f_bed_1','dan':'home1f_bed_1',
             'evy':'home22f_bed','fei':'bed_2','lin':'bed_2','hai':'home1f_bed',
             'shu':'home22f_bed','mei':'home1f_bed_1','qin':'home1f_bed_1','tie':'home1f_bed'}
    for a in agents['agents']:
        b=bindings[bed_for[a['id']]];sp,fl=b['plane'].split('/');pos=b['cell']
        a.update({'home':pos,'spawn':pos,'spatial_address':{'space_id':sp,'floor_id':fl,'position':pos}})
    for index,a in enumerate(agents.get('affiliates',[])):
        pos=list(nearest_open(town,labels,(62,42+index*5),1.,main))
        a.update({'home':pos,'spawn':pos,'spatial_address':{'space_id':'town','floor_id':'outdoor','position':pos}})

    map_out={'width':ow,'height':oh,'areas':areas,
             'nav_blockers':[list(p) for p in sorted(blocked,key=lambda p:(p[1],p[0]))],
             'blockers':[],'walls':[],'water':[],'trees':[],'landmarks':[],'doors':[],
             'objects':map_objects,'solid_lots':[],'solid_props':[], 'rooms':room_records,
             '_profile':'town3d; metres sampled independently; geometry is delivered model, not legacy map.'}
    output={'map':map_out,'spaces':spaces_out,'interiors':interiors_out,'agents':agents,
            'buildings':{'_note':'Model rooms are plane-scoped in profile map.rooms; no duplicate legacy compiler rooms or advertisements.','buildings':[]},
            'jobs':copy.deepcopy(base['jobs']),'production':production,'logistics':logistics,
            'housing':copy.deepcopy(base['housing']),'festivals':festivals,'elections':elections}
    source_hashes={f'game/data/{name}.json':sha(ROOT/f'game/data/{name}.json') for name in BASE_NAMES}
    for rel in ('masterplan.json','interior_plan.json','town_manifest.json','terrain_plan.json','landscape_plan.json','tools/terrain_profile.py','tools/interior_design.py','game_assets/export_manifest.json'):
        source_hashes['art/living_town/'+rel]=sha(ART/rel)
    source_hashes['tools/build_town_profile.py']=sha(Path(__file__))
    export_manifest=read(ART/'game_assets/export_manifest.json')
    projection['source_hashes']=source_hashes
    projection['model_source_blend_sha256']=export_manifest.get('source_blend_sha256')
    projection['runtime_navigation']={'interior_agent_radius_m':AGENT_RADIUS,'stairs':'explicit portal between actual foot/head landings',
        'interaction_cells':'reachable standing positions adjacent to modeled fixture proxy; never inside furniture',
        'decorations':'no additional advertisements','door_geometry':'crossing uses original explicit portal authority; closed door leaves are visual covers'}
    # Stable, meaningful static checks for the consumer's authoritative core.
    checks=[]
    def check(name,condition,details=None):
        checks.append({'id':name,'pass':bool(condition),'details':details})
        if not condition:raise AssertionError(name+': '+str(details))
    check('49_unique_building_spaces',len(assigned)==49 and len(set(assigned.values()))==49)
    check('89_modeled_floor_planes',len(planes)-1==89)
    check('561_plane_scoped_zones',len(room_records)==561)
    check('223_activity_rooms_reachable',sum(x['activity_room'] for x in room_checks)==223 and all(x['connected_open_cells'] for x in room_checks if x['activity_room']))
    check('49_real_entrances_40_real_stairs',len(spaces_out['portals'])==89 and sum(p['from']['space']=='town' for p in spaces_out['portals'])==49)
    check('all_current_original_portal_ids_and_access_preserved',all(next(p for p in spaces_out['portals'] if p['id']==pid).get('access')==p0.get('access') for pid,p0 in old_portals.items()))
    check('all_current_original_portal_rules_preserved',all(
        {k:v for k,v in next(p for p in spaces_out['portals'] if p['id']==pid).items() if k not in ('from','to')} ==
        {k:v for k,v in p0.items() if k not in ('from','to')} for pid,p0 in old_portals.items()))
    check('portal_endpoints_are_physically_open',all(tuple(e['pos']) in grids[e['space']+'/'+e['floor']]['labels'] for p in spaces_out['portals'] for e in (p['from'],p['to'])))
    check('12_residents_2_affiliates_preserved',[a['id'] for a in agents['agents']]==[a['id'] for a in base['agents']['agents']] and [a['id'] for a in agents['affiliates']]==[a['id'] for a in base['agents']['affiliates']])
    changed_fields={'home','spawn','spatial_address'}
    check('character_personas_and_metadata_preserved',all(
        {k:v for k,v in a.items() if k not in changed_fields} == {k:v for k,v in old.items() if k not in changed_fields}
        for field in ('agents','affiliates') for a,old in zip(agents[field],base['agents'][field])))
    check('resident_homes_share_actual_bed_plane',all(agents['agents'][i]['spatial_address']['space_id']+'/'+agents['agents'][i]['spatial_address']['floor_id']==bindings[bed_for[a['id']]]['plane'] for i,a in enumerate(agents['agents'])))
    check('all_legacy_action_definitions_unchanged',all(all_defs[oid]['advertises']==fu['advertises'] for _,_,oid,fu in old_interior) and all(all_defs[o['id']]['advertises']==o['advertises'] for o in base['map']['objects']+base['production']['worksites']+base['logistics']['nodes']))
    check('all_functional_approaches_reachable',all(tuple(o['pos']) in grids[o['space']+'/'+o['floor']]['labels'] for o in all_defs.values()))
    check('bank_and_civic_markers_preserve_flags_without_advertisements',all(
        next(f for f in interiors_out[sp]['1f']['furniture'] if f.get(flag)).get('advertises',[])==original.get('advertises',[])==[]
        and tuple(bindings[oid]['cell']) in grids[sp+'/1f']['labels'] and oid not in all_defs
        for sp,flag,oid,original in ui_markers))
    check('home2_original_beds_bind_distinct_actual_beds',
        bindings['home22f_bed']['model_asset_id']!=bindings['home22f_bed_1']['model_asset_id']
        and all(bindings[k]['model_asset_kind']=='bed' for k in ('home22f_bed','home22f_bed_1')))
    check('jobs_and_housing_unchanged',output['jobs']==base['jobs'] and output['housing']==base['housing'])
    check('festival_and_civic_action_values_preserved',all(
        [o['advertises'] for o in festivals['festivals'][name]['objects']] == [o['advertises'] for o in event['objects']]
        for name,event in base['festivals']['festivals'].items()) and
        elections['on_pass']['object']['advertises']==base['elections']['on_pass']['object']['advertises'])
    check('base_source_data_unchanged',all(sha(ROOT/rel)==digest for rel,digest in source_hashes.items() if rel.startswith('game/data/')))
    profile={'schema':'living_town.world_profile.v1','id':'town3d','label':'Delivered Living Town 3D',
             'files':{name+'.json':f'res://data/town3d/{name}.json' for name in BASE_NAMES},
             'projection_path':'res://data/town3d/projection.json','cell_sizes_m':{'outdoor':OUTDOOR_CELL,'interior':INTERIOR_CELL},
             'source_hashes':source_hashes,'base_data_untouched':True,
             'save_namespace':'town3d','model_source_blend_sha256':projection['model_source_blend_sha256']}
    for name,data in output.items():write(OUT/(name+'.json'),data)
    write(OUT/'projection.json',projection)
    profile['file_hashes']={name+'.json':sha(OUT/(name+'.json')) for name in BASE_NAMES}
    profile['projection_sha256']=sha(OUT/'projection.json')
    write(OUT/'profile.json',profile)
    report={'schema':'living_town.profile_compile_report.v1','status':'PASS','checks':checks,
        'counts':{'buildings':49,'interior_planes':89,'zones':561,'activity_rooms':223,'portal_count':89,
                  'original_portal_ids':len(old_portals),'entrances':49,'stairs':40,'functional_objects':len(all_defs),'ui_markers':len(ui_markers),
                  'legacy_interior_functional_objects':len(old_interior),'resident_count':12,'affiliate_count':2,
                  'outdoor_open_cells':len(labels),'outdoor_blocked_cells':len(blocked)},
        'source_hashes':source_hashes,'output_hashes':{p.name:sha(p) for p in sorted(OUT.glob('*.json'))},
        'planes':connectivity,'activity_room_access':room_checks,'shared_residential_beds':bed_for,
        'semantic_building_reassignments':{'home2':{'model_building_id':home2_id,'reason':'Two distinct functional beds require the existing three-storey dwelling; Main_home2 remains a visitable model space.'}},
        'adaptations':[{ 'object_id':oid,**b} for oid,b in bindings.items() if any(s in b.get('note','') for s in ('no dedicated','has no dedicated','art-viewing'))],
        'limits':['Static compiler verifies geometry-aligned topology and legacy action data, not live Godot behavior or economic calibration.',
                  'Legacy play/music actions keep their identities at compatible activity surfaces; arcade and hotel piano have no dedicated supplied mesh.',
                  'Current functional sleep anchors remain shared between twelve residents; decorative beds do not gain advertisements.',
                  'Navigation samples interior shell, partitions, stairs and 753 furnishing proxies; decorative trim, roof objects and tree canopies are not pedestrian blockers.',
                  'Door leaf visual reveal/collision state is consumer presentation; explicit core portal remains sole plane transition authority.']}
    write(REPORT,report)
    print(json.dumps({'status':report['status'],'counts':report['counts'],'profile_sha256':sha(OUT/'profile.json'),
                      'projection_sha256':sha(OUT/'projection.json')},ensure_ascii=False))


if __name__ == '__main__':
    compile_profile()
