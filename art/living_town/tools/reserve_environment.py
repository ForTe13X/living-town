"""Editable reserve terrain, linked woodland, trails and crossings for Blender.

Called with the existing town builder's API. All elevations come from the pure
Python reserve_plan module; the coastal town keeps its original grading.
"""
import importlib.util
import json
import math
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_planner():
    spec = importlib.util.spec_from_file_location('lt_reserve_plan_geometry', ROOT / 'tools/reserve_plan.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def point_segment(x, y, a, b):
    dx, dy = b[0]-a[0], b[1]-a[1]
    t = max(0., min(1., ((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy))) if dx*dx+dy*dy else 0.
    return math.hypot(x-a[0]-t*dx, y-a[1]-t*dy)


def polygon_contains(x, y, polygon):
    result = False
    for a, b in zip(polygon, polygon[1:]+polygon[:1]):
        if (a[1] > y) != (b[1] > y) and x < (b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]:
            result = not result
    return result


def ribbon(batch, points, width, height, material,ground=None):
    # Compute joins on authored profile stations, before any subdivision.
    # Dense centre samples are too close to a miter: its tangent offset can
    # overtake the next sample and invert the inside edge of the walkway.
    if len(points)<2 or width<=0:raise ValueError('Ribbon needs two stations and a positive width')
    sections=[]
    for i,p in enumerate(points):
        a=points[max(0,i-1)];b=points[min(len(points)-1,i+1)]
        if points[0]==points[-1] and i in (0,len(points)-1):a,b=points[-2],points[1]
        directions=[]
        for q,r in ((a,p),(p,b)):
            dx,dy=r[0]-q[0],r[1]-q[1];ll=math.hypot(dx,dy)
            if ll>.000001:directions.append((-dy/ll,dx/ll))
        if not directions:raise ValueError('Ribbon contains an isolated duplicate station')
        nx,ny=directions[0];safe_miter=True
        if len(directions)==2:
            ax,ay=nx+directions[1][0],ny+directions[1][1]
            dot=ax*directions[1][0]+ay*directions[1][1]
            if dot>.25:
                nx,ny=ax/dot,ay/dot
            else:
                # A near-hairpin cannot fit its long miter between authored
                # stations. Its rectangular spans form a clipped planar union.
                safe_miter=False
        # A level bend is an explicit landing/apron and can use one joined
        # miter. Sloping source segments retain their own true profile plane.
        flat=abs(a[2]-p[2])<.00001 and abs(b[2]-p[2])<.00001
        # Rounded collinear stations can differ by microradians. Share their
        # cross-section so separate normal calculations cannot widen into an
        # overlapping wedge when stored as float32 mesh coordinates.
        nearly_straight=len(directions)==2 and sum(x*y for x,y in zip(directions[0],directions[1]))>1.-1e-10
        sections.append((nx,ny) if (flat or nearly_straight) and safe_miter else None)
    source_quads=0;faces=0;minimum_area=None;clipped_area=0.;clipped_spans=0
    def cross(a,b,c):
        return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    def area(poly):
        return abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(poly,poly[1:]+poly[:1])))/2
    def half_plane(poly,a,b,inside):
        result=[]
        for p,q in zip(poly,poly[1:]+poly[:1]):
            dp,dq=cross(a,b,p),cross(a,b,q)
            pi,qi=(dp>=0.,dq>=0.) if inside else (dp<=0.,dq<=0.)
            if pi:result.append(p)
            if pi!=qi:
                t=dp/(dp-dq);result.append(tuple(p[k]+t*(q[k]-p[k]) for k in range(3)))
        cleaned=[]
        for p in result:
            if not cleaned or math.dist(p,cleaned[-1])>1e-9:cleaned.append(p)
        if len(cleaned)>1 and math.dist(cleaned[0],cleaned[-1])<=1e-9:cleaned.pop()
        while len(cleaned)>3:
            collinear=next((i for i,p in enumerate(cleaned)
                            if abs(cross(cleaned[i-1],p,cleaned[(i+1)%len(cleaned)]))<=1e-10),None)
            if collinear is None:break
            cleaned.pop(collinear)
        # Sub-square-millimetre clipping remnants can collapse at world-scale
        # float32 coordinates; omit only these negligible fragments.
        return cleaned if len(cleaned)>=3 and area(cleaned)>1e-7 else []
    def subtract(poly,cutter):
        # Sequential half-planes partition a convex polygon's difference
        # into disjoint convex pieces, retaining its exact original Z plane.
        remainder=poly;outside=[]
        for a,b in zip(cutter,cutter[1:]+cutter[:1]):
            if not remainder:break
            piece=half_plane(remainder,a,b,False)
            if piece:outside.append(piece)
            remainder=half_plane(remainder,a,b,True)
        return outside
    surface_index={};surfaces=[]
    def box(poly):return min(p[0] for p in poly),min(p[1] for p in poly),max(p[0] for p in poly),max(p[1] for p in poly)
    def cells(bounds):
        for gx in range(math.floor(bounds[0]/4),math.floor(bounds[2]/4)+1):
            for gy in range(math.floor(bounds[1]/4),math.floor(bounds[3]/4)+1):yield gx,gy
    def coplanar(a,b):
        def plane(poly):
            p,q,r=poly[:3];det=cross(p,q,r)
            if abs(det)<=1e-12:return None
            return p,q,r,det
        first,second=plane(a),plane(b)
        if first is None or second is None:return False
        def z_at(coeff,v):
            p,q,r,det=coeff
            u=((v[0]-p[0])*(r[1]-p[1])-(v[1]-p[1])*(r[0]-p[0]))/det
            t=((q[0]-p[0])*(v[1]-p[1])-(q[1]-p[1])*(v[0]-p[0]))/det
            return p[2]+u*(q[2]-p[2])+t*(r[2]-p[2])
        # Same tolerance as the evaluated native overlap audit. Heights stay
        # on each retained original plane; no averaged/flattened grade is made.
        return all(abs(z_at(first,v)-z_at(second,v))<=1e-4 for v in a+b)
    def emit(poly):
        nonlocal faces,clipped_area,clipped_spans
        bounds=box(poly);pieces=[poly]
        candidates=sorted({i for cell in cells(bounds) for i in surface_index.get(cell,[])}) if ground is None else []
        original_area=area(poly)
        for index in candidates:
            cutter,bb=surfaces[index]
            if min(bounds[2],bb[2])-max(bounds[0],bb[0])<=1e-9 or min(bounds[3],bb[3])-max(bounds[1],bb[1])<=1e-9:continue
            if not coplanar(poly,cutter):continue
            remaining=[]
            for piece in pieces:
                intersection=piece
                for a,b in zip(cutter,cutter[1:]+cutter[:1]):
                    intersection=half_plane(intersection,a,b,True)
                    if not intersection:break
                # Rounded source stations can create micrometre-wide slivers.
                # They are below the native overlap gate and must not create
                # fragments that collapse in Blender's float32 mesh storage.
                remaining.extend(subtract(piece,cutter) if intersection and area(intersection)>1e-5 else [piece])
            pieces=remaining
            if not pieces:break
        retained_area=sum(area(piece) for piece in pieces)
        if original_area-retained_area>1e-8:
            clipped_spans+=1;clipped_area+=original_area-retained_area
        for piece in pieces:
            # Pieces are convex/CCW; the existing mesh exporter triangulates
            # them without introducing a new profile or height interpolation.
            batch.poly(piece,[tuple(range(len(piece)))],material);faces+=1
            index=len(surfaces);bb=box(piece);surfaces.append((piece,bb))
            for cell in cells(bb):surface_index.setdefault(cell,[]).append(index)
    for i,(a, b) in enumerate(zip(points, points[1:])):
        dx, dy = b[0]-a[0], b[1]-a[1]
        length = math.hypot(dx, dy)
        if length < .001:
            continue
        normal=(-dy/length,dx/length)
        corners=[]
        for p,offset,(nx,ny) in ((a,width/2,sections[i] or normal),(a,-width/2,sections[i] or normal),(b,-width/2,sections[i+1] or normal),(b,width/2,sections[i+1] or normal)):
            corners.append((p[0]+nx*offset,p[1]+ny*offset,p[2]))
        # A convex positively wound quad has neither crossed opposite edges
        # nor a reversed triangle under either possible triangulation.
        signs=[cross(corners[j],corners[(j+1)%4],corners[(j+2)%4]) for j in range(4)]
        if min(signs)<=1e-10:
            raise ValueError('Invalid projected ribbon span '+str(i)+': '+str(signs))
        source_quads+=1
        longitudinal=max(1,math.ceil(max(math.dist(corners[0][:2],corners[3][:2]),math.dist(corners[1][:2],corners[2][:2]))/.35))
        # Authored-Z spans are exact planes; extra transverse tessellation
        # adds cost without changing their surface. A sampled ground callback
        # needs transverse stations to follow its curved surface.
        lanes=max(1,math.ceil(max(math.dist(corners[0][:2],corners[1][:2]),math.dist(corners[3][:2],corners[2][:2]))/.35)) if ground else 1
        def station(t,u):
            left=[corners[0][k]*(1-t)+corners[3][k]*t for k in range(3)]
            right=[corners[1][k]*(1-t)+corners[2][k]*t for k in range(3)]
            x,y,z=[left[k]*(1-u)+right[k]*u for k in range(3)]
            return (x,y,(ground(x,y) if ground else z)+height)
        for along in range(longitudinal):
            t0,t1=along/longitudinal,(along+1)/longitudinal
            for lane in range(lanes):
                u0,u1=lane/lanes,(lane+1)/lanes
                verts=[station(t0,u0),station(t0,u1),station(t1,u1),station(t1,u0)]
                signs=[cross(verts[j],verts[(j+1)%4],verts[(j+2)%4]) for j in range(4)]
                if min(signs)<=1e-10:raise ValueError('Ribbon subdivision reversed a face at source span '+str(i))
                minimum_area=min(signs) if minimum_area is None else min(minimum_area,min(signs))
                emit(verts)
    return {'source_spans':source_quads,'subdivided_quads':faces,'minimum_projected_cross_product_m2':minimum_area,
            'same_run_coplanar_overlap_removed_m2':clipped_area,'clipped_subdivisions':clipped_spans,
            'method':'Authored-station sections, bilinear subdivision, and exact coplanar same-run polygon difference at overlaps'}


def dense_points(points, spacing, height=None):
    result = []
    for a, b in zip(points, points[1:]):
        n = max(1, math.ceil(math.dist(a[:2], b[:2])/spacing))
        for i in range(n):
            t = i/n
            x, y = a[0]*(1-t)+b[0]*t, a[1]*(1-t)+b[1]*t
            z = height(x,y) if height else a[2]*(1-t)+b[2]*t
            result.append((x,y,z))
    result.append(tuple(points[-1]))
    return result


def ground_runs(path):
    """Join adjacent new ground spans, including a closed path's head/tail.

    Reused paving and crossings remain gaps. Joining the closed head and tail
    before constructing sections gives their shared station one real miter,
    rather than two overlapping rectangular end caps.
    """
    if path.get('kind') in ('bridge','stairs'):
        return []
    def same(a,b):
        return len(a)==len(b) and all(abs(x-y)<=1e-8 for x,y in zip(a,b))
    points=path['points_m'];runs=[];current=[]
    for segment in path.get('segments',[{'kind':'ground','points_m':points}]):
        if segment.get('kind') in ('bridge','stairs') or segment.get('core_reuse'):
            if current:runs.append(current);current=[]
            continue
        part=[tuple(p) for p in segment['points_m']]
        if len(part)<2:raise ValueError('Ground segment needs two profile stations')
        if current and same(current[-1],part[0]):
            current.extend(part[1:])
        else:
            if current:runs.append(current)
            current=part
    if current:runs.append(current)
    if len(runs)>1 and same(points[0],points[-1]) and same(runs[-1][-1],runs[0][0]):
        runs=[runs[-1]+runs[0][1:]]+runs[1:-1]
    return runs


def convex_xy_triangles(ids, vertices):
    """Triangulate a convex XY cell while preserving every boundary station.

    Blender's 3D tessellator may form vertical triangles along a nonplanar
    inserted edge. Clip positive XY ears instead; no vertices are added and
    neighboring cells retain identical boundary edges and heights.
    """
    if len(ids)<=4:return [tuple(ids)]
    ring=list(ids);result=[]
    def cross(a,b,c):
        ax,ay,_=vertices[a];bx,by,_=vertices[b];cx,cy,_=vertices[c]
        return (bx-ax)*(cy-ay)-(by-ay)*(cx-ax)
    def area_of(r):return sum(cross(r[0],a,b) for a,b in zip(r[1:-1],r[2:]))
    total=area_of(ring)
    # Clipping beyond the curved coast can collapse a cell to a line.
    if abs(total)<=1e-10:return []
    def occupied(a,b,c):
        return any(min(cross(a,b,p),cross(b,c,p),cross(c,a,p))>=-1e-12
                   for p in ring if p not in (a,b,c))
    while len(ring)>3:
        ears=[(cross(ring[i-1],b,ring[(i+1)%len(ring)]),i)
              for i,b in enumerate(ring)]
        valid=[(area,i) for area,i in ears if area>1e-12 and total-area>1e-12
               and not occupied(ring[i-1],ring[i],ring[(i+1)%len(ring)])]
        if not valid:raise RuntimeError('Terrain cell has no positive XY ear: '+str([vertices[v] for v in ring]))
        area,i=max(valid)
        result.append((ring[i-1],ring[i],ring[(i+1)%len(ring)]))
        del ring[i];total=area_of(ring)
    if cross(*ring)<=1e-12:raise RuntimeError('Terrain cell ends in a degenerate XY triangle')
    result.append(tuple(ring));return result


def build(api, plan):
    import bpy
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    planner = load_planner()
    elevation = planner.design_height
    scene = api['SCENE']
    parent = api['coll']('06_Natural_Reserve')
    terrain_col = api['coll']('Reserve_Terrain', parent)
    trails_col = api['coll']('Reserve_Trails_and_Crossings', parent)
    woods_col = api['coll']('Reserve_Woodland', parent)
    detail_col = api['coll']('Reserve_Understorey_and_Geology', parent)
    B = api['Batch']
    api['mat']('NaturalRock','ffffff','natural_rock')
    for node in api['MATS']['NaturalRock'].node_tree.nodes:
        if node.type=='NORMAL_MAP':node.inputs['Strength'].default_value=.85
    rng = random.Random(121026)
    report = {'schema':'living_town.reserve_geometry.v1', 'terrain_authority':'tools/reserve_plan.py',
              'tree_instances':0, 'tree_species':{}, 'crossings':[], 'paths':[], 'stairs':[]}
    bounds = plan['terrain']['bounds_xyxy_m']
    # Keep the original beach, pond water, quay and sea. Replace only land.
    original = bpy.data.objects.get('Atlantic_Terrain_Grass')
    if original is None:
        raise RuntimeError('Expected native land mesh missing')
    old_surface=BVHTree.FromPolygons([v.co.copy() for v in original.data.vertices],
        [list(p.vertices) for p in original.data.polygons])
    def vertex_elevation(x,y):
        if -75<=x<=70 and -65<=y<=65:
            hit=old_surface.ray_cast(Vector((x,y,1000)),Vector((0,0,-1)))[0]
            if hit is not None:return hit.z
        return elevation(x,y)
    original.hide_render = True
    original.hide_set(True)
    original['superseded_by'] = 'Reserve_Continuous_Land'
    original.name = 'Archive_PreReserve_Land_NotExported'
    archive = bpy.data.collections.new('Reserve_Previous_Land_Archive_NotExported')
    for owner in list(original.users_collection):
        owner.objects.unlink(original)
    archive.objects.link(original)
    # A single varying-resolution grid avoids cracks at a core/outer seam.
    xs = sorted(set([bounds[0]+i*2 for i in range(math.ceil((bounds[2]-bounds[0])/2)+1)]
                    + [-85+i*.6 for i in range(258)] + [18+i*.2 for i in range(81)]))
    xs = [x for x in xs if bounds[0] <= x <= bounds[2]]
    ys = sorted(set([bounds[1]+i*2 for i in range(math.ceil((bounds[3]-bounds[1])/2)+1)]
                    + [-75+i*.6 for i in range(268)] + [-48+i*.2 for i in range(61)] + [37,55]))
    ys = [y for y in ys if bounds[1] <= y <= bounds[3]]
    for edge in plan.get('site_earthworks',{}).get('retaining_edges',[]):
        half=edge['thickness_m']/2
        for x,y,_ in edge['points_m']:
            xs.extend([x-half-.05,x,x+half+.05])
            ys.extend([y-half-.05,y-half,y,y+half,y+half+.05])
    xs=sorted(set(xs));ys=sorted(set(ys))
    # Refine only real roadbeds, rather than increasing every forest cell.
    # Neighboring cells share all boundary stations, including fine/coarse
    # joins: this prevents T-junction cracks in the continuous land surface.
    road_cells={}
    for path in plan['paths']:
        # Stone stair corridors need the same local land resolution as paths:
        # their cut profile must not be bridged by coarse hillside triangles.
        # Suspended bridge spans intentionally retain the ravine below.
        if path['kind']=='bridge':continue
        for a,b in zip(path['points_m'],path['points_m'][1:]):
            radius=path['width_m']/2+2.4
            for ix in range(math.floor((min(a[0],b[0])-radius)/8),math.floor((max(a[0],b[0])+radius)/8)+1):
                for iy in range(math.floor((min(a[1],b[1])-radius)/8),math.floor((max(a[1],b[1])+radius)/8)+1):
                    road_cells.setdefault((ix,iy),[]).append((a,b,path['width_m']/2))
    vertices=[];faces=[];vertex_ids={};cells=[];edges={};refined=0
    base_terrain = api['TERRAIN']
    def vertex(x,y):
        px=min(x,base_terrain.coast_x(y)-base_terrain.beach_width(y))
        key=(round(px,8),round(y,8))
        if key not in vertex_ids:
            vertex_ids[key]=len(vertices)
            vertices.append((px,y,vertex_elevation(px,y)))
        return vertex_ids[key]
    def edge_key(horizontal,fixed,lower,upper):
        return (horizontal,round(fixed,8),round(lower,8),round(upper,8))
    def register(horizontal,fixed,lower,upper,stations):
        edges.setdefault(edge_key(horizontal,fixed,lower,upper),set()).update(stations)
    for j in range(len(ys)-1):
        for i in range(len(xs)-1):
            x0,x1,y0,y1=xs[i],xs[i+1],ys[j],ys[j+1]
            mx,my=(x0+x1)/2,(y0+y1)/2
            if 31<mx<66 and 37<my<55:continue
            if x0>=max(base_terrain.coast_x(y0)-base_terrain.beach_width(y0),base_terrain.coast_x(y1)-base_terrain.beach_width(y1)):continue
            in_core=-75<=x0 and x1<=70 and -65<=y0 and y1<=65
            radius=math.hypot(x1-x0,y1-y0)/2+.45
            near=not in_core and any(point_segment(mx,my,a,b)<half+radius for a,b,half in road_cells.get((math.floor(mx/8),math.floor(my/8)),()))
            nx=max(1,math.ceil((x1-x0)/.25)) if near else 1
            ny=max(1,math.ceil((y1-y0)/.25)) if near else 1
            refined+=near
            xx=[x0+(x1-x0)*k/nx for k in range(nx+1)]
            yy=[y0+(y1-y0)*k/ny for k in range(ny+1)]
            cells.append((xx,yy))
            register(True,y0,x0,x1,xx);register(True,y1,x0,x1,xx)
            register(False,x0,y0,y1,yy);register(False,x1,y0,y1,yy)
    for xx,yy in cells:
        x0,x1,y0,y1=xx[0],xx[-1],yy[0],yy[-1]
        boundary={
            'bottom':sorted(edges[edge_key(True,y0,x0,x1)]),
            'top':sorted(edges[edge_key(True,y1,x0,x1)]),
            'left':sorted(edges[edge_key(False,x0,y0,y1)]),
            'right':sorted(edges[edge_key(False,x1,y0,y1)])}
        for j,(a,b) in enumerate(zip(yy,yy[1:])):
            for i,(c,d) in enumerate(zip(xx,xx[1:])):
                bottom=[v for v in boundary['bottom'] if c+1e-8<v<d-1e-8] if j==0 else []
                right=[v for v in boundary['right'] if a+1e-8<v<b-1e-8] if i==len(xx)-2 else []
                top=[v for v in reversed(boundary['top']) if c+1e-8<v<d-1e-8] if j==len(yy)-2 else []
                left=[v for v in reversed(boundary['left']) if a+1e-8<v<b-1e-8] if i==0 else []
                points=[(c,a)]+[(v,a) for v in bottom]+[(d,a)]+[(d,v) for v in right]+[(d,b)]+[(v,b) for v in top]+[(c,b)]+[(c,v) for v in left]
                ids=list(dict.fromkeys(vertex(x,y) for x,y in points))
                if len(ids)>=3:faces.extend(convex_xy_triangles(ids,vertices))
    land = B('Reserve_Continuous_Land', terrain_col)
    land.poly(vertices, faces, 'Grass')
    land_objects = land.flush()
    graded_amenity_pads=[p for p in plan['pads'] if p.get('priority')==2]
    for ob in land_objects:
        # Retain the stable terrain node used by pond/runtime asset consumers.
        ob.name = 'Atlantic_Terrain_Grass'
        ob['reserve_role'] = 'terrain'
        ob['elevation_authority'] = 'reserve_plan.design_height'
        ob.data.materials.append(api['MATS']['NaturalRock'])
        for face in ob.data.polygons:
            face.use_smooth = True
            # Reserve ravines expose the same local granite as buildings and
            # stairs. Graded pads and the preserved town remain grass covered.
            x,y,z=face.center
            planted_bank=any(planner.pad_distance(x,y,p)<=p['blend_m']+2 for p in graded_amenity_pads)
            if not planted_bank and not (-75<=x<=70 and -65<=y<=65) and z>6 and face.normal.z<.89:
                face.material_index=1;face.use_smooth=False
    report['terrain_vertices'] = len(vertices)
    report['terrain_faces'] = len(faces)
    report['adaptively_refined_roadbed_cells']=refined
    report['roadbed_maximum_cell_spacing_m']=.25
    report['stair_ground_cut_policy']='Continuous land excavated beneath unchanged flights/landings; full stair width plus.35m margin, blended cut banks, same.25m local mesh refinement'
    report['bounds_xyxy_m'] = bounds
    land_surface=BVHTree.FromPolygons([v.co.copy() for v in land_objects[0].data.vertices],
        [list(p.vertices) for p in land_objects[0].data.polygons])
    quay_vertices=[];quay_faces=[]
    for ob in scene.objects:
        if ob.type=='MESH' and ob.name.startswith('Connected_Streets_and_Pavements'):
            start=len(quay_vertices)
            quay_vertices.extend([ob.matrix_world @ v.co for v in ob.data.vertices])
            quay_faces.extend([[start+i for i in p.vertices] for p in ob.data.polygons])
    quay_surface=BVHTree.FromPolygons(quay_vertices,quay_faces)
    def ground(x,y):
        hit=land_surface.ray_cast(Vector((x,y,1000)),Vector((0,0,-1)))[0]
        if hit is None and 31<=x<=66 and 37<=y<=55:
            hit=quay_surface.ray_cast(Vector((x,y,1000)),Vector((0,0,-1)))[0]
        if hit is None:raise ValueError('Reserve placement outside saved land: '+str((x,y)))
        return hit.z
    # Re-sample the shore on the same outer grid so hills meet beach/cliff
    # ribbons without cracks between the old sparse coastal chords.
    shore = B('Reserve_Coastal_Shore', terrain_col)
    shore_vertices=[]
    for y in ys:
        coast=base_terrain.coast_x(y);width=base_terrain.beach_width(y);edge=coast-width
        for k in range(9):
            t=k/8;x=edge+width*t
            z=base_terrain.beach_height(x,y)+(elevation(edge,y)-base_terrain.design_height(edge,y))*(1-t)
            shore_vertices.append((x,y,z))
    for material in ('Sand','WetSand','Granite'):
        shore_faces=[]
        for j in range(len(ys)-1):
            y=(ys[j]+ys[j+1])/2
            if 37<y<55:continue
            edge=base_terrain.coast_x(y)-base_terrain.beach_width(y)
            rocky=base_terrain.beach_width(y)<3 or elevation(edge,y)>3
            indices=range(8) if rocky and material=='Granite' else (range(6) if not rocky and material=='Sand' else (range(6,8) if not rocky and material=='WetSand' else []))
            shore_faces.extend((j*9+k,j*9+k+1,(j+1)*9+k+1,(j+1)*9+k) for k in indices)
        shore.poly(shore_vertices,shore_faces,'NaturalRock' if material=='Granite' else material)
        previous=bpy.data.objects.get('Atlantic_Terrain_'+material)
        if previous:
            previous.name='Archive_PreReserve_Shore_'+material
            for owner in list(previous.users_collection):owner.objects.unlink(previous)
            archive.objects.link(previous)
    for ob in shore.flush():
        material=ob.data.materials[0].name.removeprefix('LT_')
        if material=='NaturalRock':material='Granite'
        ob.name='Atlantic_Terrain_'+material;ob['reserve_role']='shore_transition'

    report['retaining_edges']=[]
    for edge in plan.get('site_earthworks',{}).get('retaining_edges',[]):
        a,b=edge['points_m'];dx,dy=b[0]-a[0],b[1]-a[1]
        length=math.hypot(dx,dy);angle=math.atan2(dy,dx)
        lower=edge['lower_level_m'];upper=edge['upper_level_m'];thickness=edge['thickness_m']
        wall=B(edge['id'],trails_col,((a[0]+b[0])/2,(a[1]+b[1])/2,lower-.2),angle)
        height=upper-lower+.2
        wall.box((0,0,height/2),(length,thickness,height),'Granite')
        wall.box((0,0,height+.05),(length+.14,thickness+.14,.10),'Granite')
        for z in range(1,math.ceil(height/.32)):
            wall.box((0,-thickness/2-.001,z*.32),(length,.012,.012),'Slate')
        for x in (-length/2,0,length/2):
            wall.rod((x,0,height+.1),(x,0,height+1.2),.025,'Iron',n=8)
        for z in (.65,1.2):
            wall.rod((-length/2,0,height+z),(length/2,0,height+z),.022,'Iron',n=8)
        for ob in wall.flush(.003):
            ob['reserve_role']='retaining_wall';ob['reserve_structure_id']=edge['id']
        report['retaining_edges'].append({'id':edge['id'],'height_m':upper-lower,'length_m':length})

    path_index = {}
    def index_segment(a,b,width):
        r=width/2+24
        for gx in range(math.floor((min(a[0],b[0])-r)/16),math.floor((max(a[0],b[0])+r)/16)+1):
            for gy in range(math.floor((min(a[1],b[1])-r)/16),math.floor((max(a[1],b[1])+r)/16)+1):
                path_index.setdefault((gx,gy),[]).append((a,b,width))
    new_ground_runs={path['id']:ground_runs(path) for path in plan.get('paths',[])}
    layered_route_ids=sorted(ident for ident,runs in new_ground_runs.items() if runs)
    route_bias={ident:(index-(len(layered_route_ids)-1)/2)*.00025
                for index,ident in enumerate(layered_route_ids)}
    report['trail_surface_layers']={'method':'Deterministic physical surface separation for overlapping route overlays',
        'base_overlay_height_m':.045,'layer_spacing_m':.00025,'route_count':len(layered_route_ids),
        'minimum_bias_m':min(route_bias.values(),default=0.),'maximum_bias_m':max(route_bias.values(),default=0.)}
    for path in plan.get('paths',[]):
        points=path['points_m']; width=path['width_m']
        for a,b in zip(points,points[1:]):
            index_segment(a,b,width)
        if path.get('kind') in ('bridge','stairs'):
            continue
        batch=B('Reserve_Trail_'+path['id'],trails_col)
        mat='Dirt' if ('jog' in path.get('kind','') or 'run' in path.get('kind','')) else 'Courtyard'
        sampled=[];rendered_length=0.;bias=route_bias.get(path['id'],0.)
        for part in new_ground_runs[path['id']]:
            # Authored finished road profiles also form the short new ramps
            # over the preserved urban ground. Existing land/paving stays.
            # Tiny physical separation prevents coincident independent route
            # surfaces from shadowing/depth-fighting in renders and engines.
            ribbon(batch,part,width,.045+bias,mat);sampled.extend(dense_points(part,.35))
            rendered_length+=sum(math.dist(a,b) for a,b in zip(part,part[1:]))
        objs=batch.flush()
        for ob in objs:
            ob['reserve_role']='trail';ob['reserve_route_id']=path['id'];ob['path_width_m']=width
            ob['trail_surface_bias_m']=bias;ob['trail_base_overlay_m']=.045;ob['trail_overlay_m']=.045+bias
        report['paths'].append({'id':path['id'],'sample_count':len(sampled),'length_m':rendered_length,
            'ground_run_count':len(new_ground_runs[path['id']]),'surface_bias_m':bias,'overlay_height_m':.045+bias})

    for crossing in plan.get('bridges',[]):
        a,b=crossing['points_m'];width=crossing['width_m']
        dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy)
        if length <= 0:
            raise ValueError('Zero length bridge')
        angle=math.atan2(dy,dx);nx,ny=-dy/length,dx/length
        batch=B('Reserve_Bridge_'+crossing['id'],trails_col)
        count=math.ceil(length/.25)
        for i in range(count):
            t=(i+.5)/count;x,y,z=[a[k]*(1-t)+b[k]*t for k in range(3)]
            batch.box((x,y,z-.09),(length/count-.018,width,.18),'Oak',angle)
        for side in(-1,1):
            aa=(a[0]+nx*side*width*.43,a[1]+ny*side*width*.43,a[2]-.26)
            bb=(b[0]+nx*side*width*.43,b[1]+ny*side*width*.43,b[2]-.26)
            batch.rod(aa,bb,.13,'Trunk',n=6)
            for height in(.56,crossing.get('railing_height_m',1.15)):
                batch.rod((aa[0],aa[1],aa[2]+height+.26),(bb[0],bb[1],bb[2]+height+.26),.035,'Oak',n=6)
            for i in range(math.ceil(length/1.4)+1):
                t=i/math.ceil(length/1.4)
                p=[aa[k]*(1-t)+bb[k]*t for k in range(3)]
                batch.rod((p[0],p[1],p[2]),(p[0],p[1],p[2]+1.42),.065,'Oak',n=6)
        for p in(a,b):
            batch.box((p[0],p[1],p[2]-.38),(1.1,width+.5,.7),'Granite',angle)
        # Long ravine spans use visible suspension structure, rather than
        # an unsupported thin timber beam across a forty-metre opening.
        for side in (-1,1):
            offset=side*(width/2+.13)
            for p in (a,b):
                x,y=p[0]+nx*offset,p[1]+ny*offset
                batch.rod((x,y,p[2]-.3),(x,y,p[2]+3.65),.14,'Oak',n=6)
            cable=[]
            for i in range(count+1):
                t=i/count
                z=a[2]*(1-t)+b[2]*t+1.65+2*(2*t-1)**2
                cable.append((a[0]+dx*t+nx*offset,a[1]+dy*t+ny*offset,z))
            for p,q in zip(cable,cable[1:]):batch.rod(p,q,.024,'Iron',n=6)
            for i in range(math.ceil(length/1.4)+1):
                t=i/math.ceil(length/1.4);j=min(count,round(t*count));p=cable[j]
                z=a[2]*(1-t)+b[2]*t
                batch.rod((p[0],p[1],z+.12),p,.012,'Iron',n=5)
            for endpoint,direction in ((a,-1),(b,1)):
                tx,ty=endpoint[0]+nx*offset,endpoint[1]+ny*offset
                ax=tx+direction*dx/length*3.8;ay=ty+direction*dy/length*3.8
                az=ground(ax,ay)
                batch.box((ax,ay,az+.15),(.75,.75,.5),'Granite')
                batch.rod((tx,ty,endpoint[2]+3.65),(ax,ay,az+.4),.024,'Iron',n=6)
        for p in(a,b):
            batch.rod((p[0]-nx*(width/2+.13),p[1]-ny*(width/2+.13),p[2]+3.55),
                      (p[0]+nx*(width/2+.13),p[1]+ny*(width/2+.13),p[2]+3.55),.12,'Oak',n=6)
        objects=batch.flush(.008)
        for ob in objects:
            ob['reserve_role']='bridge';ob['reserve_bridge_id']=crossing['id']
        middle=[(a[k]+b[k])/2 for k in range(3)]
        clearance=middle[2]-elevation(middle[0],middle[1])
        report['crossings'].append({'id':crossing['id'],'length_m':length,'width_m':width,'midpoint_ground_clearance_m':clearance,'endpoints_m':[a,b]})

    for stair in plan.get('stairs',[]):
        batch=B('Reserve_Stone_Stairs_'+stair['id'],trails_col)
        width=stair.get('width_m',1.8);steps=0
        flights=stair.get('flights',[{'points_m':stair['points_m']}])
        for flight in flights:
            a,b=flight['points_m'][0],flight['points_m'][-1]
            dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy)
            if length<.01:
                continue
            n=flight.get('step_count',max(1,math.ceil(abs(b[2]-a[2])/stair.get('rise_m',.15))))
            angle=math.atan2(dy,dx)
            for i in range(n):
                t=(i+.5)/n;x=a[0]+dx*t;y=a[1]+dy*t
                z=a[2]+(b[2]-a[2])*((i+1)/n if b[2]>=a[2] else i/n)
                base=min(z-.18,elevation(x,y)-.05)
                batch.box((x,y,(z+base)/2),(length/n+.03,width,z-base),'Granite',angle)
                steps+=1
            for side in(-1,1):
                nx,ny=-dy/length,dx/length
                railheight=stair.get('handrail_height_m',1.1)
                p=(a[0]+nx*side*(width/2+.08),a[1]+ny*side*(width/2+.08),a[2]+railheight)
                q=(b[0]+nx*side*(width/2+.08),b[1]+ny*side*(width/2+.08),b[2]+railheight)
                batch.rod(p,q,.035,'Iron',n=6)
                for t in (0,.33,.66,1):
                    x,y,z=[p[k]*(1-t)+q[k]*t for k in range(3)]
                    batch.rod((x,y,z-railheight),(x,y,z),.025,'Iron',n=6)
        for landing in stair.get('landings',[]):
            a,b=landing['points_m'];dx,dy=b[0]-a[0],b[1]-a[1]
            length=math.hypot(dx,dy);angle=math.atan2(dy,dx)
            x,y,z=[(a[k]+b[k])/2 for k in range(3)]
            base=min(z-.22,elevation(x,y)-.05)
            batch.box((x,y,(z+base)/2),(length+.02,width,z-base),'Granite',angle)
            for side in (-1,1):
                nx,ny=-dy/length,dx/length
                h=stair.get('handrail_height_m',1.1)
                batch.rod((a[0]+nx*side*(width/2+.08),a[1]+ny*side*(width/2+.08),a[2]+h),
                          (b[0]+nx*side*(width/2+.08),b[1]+ny*side*(width/2+.08),b[2]+h),.035,'Iron',n=6)
        for ob in batch.flush(.009):
            ob['reserve_role']='stone_stairs';ob['reserve_stair_id']=stair['id']
        report['stairs'].append({'id':stair['id'],'steps':steps,'width_m':width,'flights':len(flights),'landings':len(stair.get('landings',[]))})

    def excluded(x,y,crown=1.):
        if base_terrain.coast_x(y)-base_terrain.beach_width(y)-x<crown+2:
            return True
        core=plan['terrain']['core_preserve_rect_xyxy_m']
        if core[0]-2<x<core[2]+2 and core[1]-2<y<core[3]+2:
            return True
        for pad in plan.get('pads',[]):
            center=pad.get('center_m',pad.get('center'))
            w=pad.get('width',pad.get('size_m',[0,0])[0]);d=pad.get('depth',pad.get('size_m',[0,0])[1])
            a=math.radians(pad.get('yaw_degrees',0));dx,dy=x-center[0],y-center[1]
            if abs(dx*math.cos(a)+dy*math.sin(a))<w/2+crown+2 and abs(-dx*math.sin(a)+dy*math.cos(a))<d/2+crown+2:
                return True
        for a,b,width in path_index.get((math.floor(x/16),math.floor(y/16)),[]):
            if point_segment(x,y,a,b)<width/2+1.1:
                return True
        for clearing in plan.get('clearings',[]):
            polygon=clearing.get('polygon_xy')
            if polygon and polygon_contains(x,y,polygon):
                return True
            if 'radii_m' in clearing:
                cx,cy=clearing['center_m'];rx,ry=clearing['radii_m']
                if ((x-cx)/(rx+crown))**2+((y-cy)/(ry+crown))**2<=1:
                    return True
        return False

    # Prototypes live outside scene collections. Only linked instances export.
    prototypes=bpy.data.collections.new('Reserve_Prototype_Library_NotExported')
    meshes={}
    for species in('oak','beech','birch','pine','rowan','holly','willow','alder','maritime_pine'):
        for lod in('near','far'):
            batch=B('Reserve_Prototype_'+species+'_'+lod,prototypes)
            h={'oak':9.,'beech':11.,'birch':10.,'pine':13.,'rowan':8.,'holly':6.5,'willow':10.,'alder':11.,'maritime_pine':12.}[species]
            trunk='Linen' if species=='birch' else 'Trunk'
            batch.rod((0,0,0),(0,0,h*.78),.16 if species=='birch' else .25,trunk,n=7,r2=.06)
            if species=='birch' and lod=='near':
                for k in range(7):batch.box((0,-.155,.6+k*.69),(.15,.018,.045),'Ink',k*.11)
            if species=='maritime_pine':
                batch.ellipsoid((0,0,h*.82),(3.7,3.2,1.7),'LeafDark',n=10,rings=3)
                if lod=='near':
                    for x,y in ((-2,0),(1.4,1.6),(1,-1.8)):
                        batch.rod((0,0,h*.52),(x,y,h*.81),.10,trunk,n=6,r2=.04)
                        batch.ellipsoid((x,y,h*.85),(2,1.8,1.2),'Leaf',n=8,rings=3)
            elif species=='pine':
                for level,radius in ((.36,3.2),(.54,2.7),(.72,1.95)):
                    batch.rod((0,0,h*level),(0,0,h*(level+.29)),radius,'LeafDark',n=8,r2=.04)
            else:
                lobes=[(0,0,h*.72,2.9,2.7,3.1)]
                if species=='holly':lobes=[(0,0,h*.60,2.,1.8,2.8)]
                elif species=='alder':lobes=[(0,0,h*.72,2.3,2.1,3.7)]
                elif species=='willow':lobes=[(0,0,h*.68,3.7,3.3,3.6)]
                if lod=='near':
                    lobes.extend([(-1.7,.8,h*.65,2.2,2.1,2.4),(1.6,-.9,h*.79,2.2,2.0,2.6),(0,1.8,h*.83,2.0,2.1,2.4)])
                for j,(x,y,z,rx,ry,rz) in enumerate(lobes):
                    leaf='LeafDark' if species=='holly' else 'LeafSilver' if species=='willow' else ('Leaf','LeafLight','LeafSilver')[j%3] if species!='beech' else 'Leaf'
                    batch.ellipsoid((x,y,z),(rx,ry,rz),leaf,n=10 if lod=='near' else 8,rings=5 if lod=='near' else 4)
                    if lod=='near':
                        batch.rod((0,0,h*.4),(x,y,z),.08,trunk,n=5,r2=.025)
                if species=='willow' and lod=='near':
                    for j in range(8):
                        az=j*math.tau/8
                        batch.rod((2.7*math.cos(az),2.7*math.sin(az),h*.72),(3.2*math.cos(az),3.2*math.sin(az),h*.25),.10,'LeafSilver',n=5,r2=.025)
            meshes[species,lod]=[o.data for o in batch.flush()]

    used=set();tree_points=[];forest_records=[]
    for zone in plan.get('forest_zones',[]):
        polygon=zone.get('polygon_xy')
        if polygon:
            x0,y0,x1,y1=min(p[0] for p in polygon),min(p[1] for p in polygon),max(p[0] for p in polygon),max(p[1] for p in polygon)
        else:
            x0,y0,x1,y1=zone['bounds_xyxy_m'];polygon=[[x0,y0],[x1,y0],[x1,y1],[x0,y1]]
        target=zone.get('target_tree_count',700);made=0;attempts=0
        species_mix=zone.get('species',['oak','beech','birch','pine'])
        if isinstance(species_mix,dict):
            choices=list(species_mix);weights=list(species_mix.values())
        else:
            choices=species_mix;weights=None
        while made<target and attempts<target*35:
            attempts+=1;x=rng.uniform(x0,x1);y=rng.uniform(y0,y1)
            key=(round(x/4.8),round(y/4.8))
            if key in used or not polygon_contains(x,y,polygon) or excluded(x,y):
                continue
            z=ground(x,y)
            slope=math.hypot(elevation(x+1,y)-elevation(x-1,y),elevation(x,y+1)-elevation(x,y-1))/2
            if slope>.85:
                continue
            label=rng.choices(choices,weights=weights,k=1)[0]
            species={'sessile_oak':'oak','scots_pine':'pine','silver_birch':'birch'}.get(label,label)
            species=species if species in('oak','beech','birch','pine','rowan','holly','willow','alder','maritime_pine') else 'oak'
            near=(math.hypot(x+75,y+20)<155 or math.hypot(x+175,y+110)<85
                  or any(point_segment(x,y,a,b)<width/2+22 for a,b,width in path_index.get((math.floor(x/16),math.floor(y/16)),())))
            lod='near' if near else 'far';scale=rng.uniform(.72,1.32)
            yaw=rng.uniform(0,math.tau)
            tree_scale=(scale*rng.uniform(.94,1.06),scale*rng.uniform(.94,1.06),scale)
            for j,mesh in enumerate(meshes[species,lod]):
                ob=bpy.data.objects.new(f'Reserve_Tree_{report["tree_instances"]:04}_{species}_{j}',mesh)
                woods_col.objects.link(ob);ob.location=(x,y,z);ob.rotation_euler[2]=yaw
                ob.scale=tree_scale
                ob['reserve_role']='tree';ob['tree_species']=label;ob['reserve_zone']=zone['id'];ob['lod']=lod
            report['tree_instances']+=1;report['tree_species'][label]=report['tree_species'].get(label,0)+1
            tree_points.append((x,y,z));used.add(key);made+=1
        forest_records.append({'id':zone['id'],'target':target,'actual':made})
    report['forest_zones']=forest_records

    understory=B('Reserve_Ferns_Heather_and_Fallen_Wood',detail_col)
    geology=B('Reserve_Granite_Outcrops_and_Talus',detail_col)
    for i,(x,y,z) in enumerate(tree_points):
        if i%5==0:
            for j in range(3):
                px=x+rng.uniform(-2,2);py=y+rng.uniform(-2,2)
                if excluded(px,py,.2):
                    continue
                pz=ground(px,py)
                understory.ellipsoid((px,py,pz+.4),(.55,.5,.43),'LeafDark',n=6,rings=3)
                for k in range(3):
                    ang=k*math.tau/3
                    understory.rod((px,py,pz+.05),(px+.62*math.cos(ang),py+.62*math.sin(ang),pz+.35),.025,'LeafLight',n=4)
            if i%20==0:
                understory.rod((x+2,y,ground(x+2,y)+.18),(x+5,y+1,ground(x+5,y+1)+.18),.18,'Trunk',n=7)
        if i%9==0:
            px,py=x+2,y+1
            if not excluded(px,py,.3):
                zz=ground(px,py)
                geology.ellipsoid((px,py,zz+.35),(rng.uniform(.6,1.6),rng.uniform(.5,1.2),rng.uniform(.5,1.2)),'NaturalRock',n=7,rings=3)
        if i%17==0:
            px,py=x+3,y-2
            if not excluded(px,py,.1):
                zz=ground(px,py)
                understory.ellipsoid((px,py,zz+.26),(.8,.65,.30),'LeafSilver',n=6,rings=3)
                for j in range(7):
                    az=j*math.tau/7
                    understory.ellipsoid((px+.55*math.cos(az),py+.45*math.sin(az),zz+.48),(.13,.12,.14),'BloomPink' if i%34 else 'BloomCream',n=5,rings=3)
    # Layered exposed stone follows steep slopes rather than random flat scatter.
    for i in range(470):
        x=rng.uniform(bounds[0]+10,20);y=rng.uniform(bounds[1]+10,bounds[3]-10)
        if excluded(x,y,.8):
            continue
        z=ground(x,y)
        dx=elevation(x+2,y)-elevation(x-2,y);dy=elevation(x,y+2)-elevation(x,y-2)
        if math.hypot(dx,dy)/4<.28:
            continue
        geology.ellipsoid((x,y,z-.25),(rng.uniform(2,5),rng.uniform(1.8,4),rng.uniform(1.6,4)),'NaturalRock',n=7,rings=4)
    understory.flush();geology.flush()

    furniture=B('Reserve_Trailside_Rest_and_Wayfinding',trails_col)
    waypoint_count=0
    for path in plan.get('paths',[]):
        points=path['points_m']
        if not points or path.get('kind') in ('bridge','stairs'):
            continue
        for index in (0,len(points)//2):
            x,y,z=points[index]
            if -75<=x<=70 and -65<=y<=65:continue
            x+=path['width_m']/2+1.2
            try:z=ground(x,y)
            except ValueError:continue
            furniture.rod((x,y,z),(x,y,z+1.6),.07,'Oak',n=6)
            furniture.box((x,y,z+1.42),(.82,.08,.25),'Sage')
            furniture.box((x,y-.05,z+1.42),(.56,.015,.025),'White')
            waypoint_count+=1
        if 'jog' in path.get('kind','') or 'run' in path.get('kind',''):
            total=0.;next_marker=100.
            sampled=dense_points(points,1,elevation)
            for a,b in zip(sampled,sampled[1:]):
                total+=math.dist(a,b)
                if total>=next_marker:
                    next_marker+=100
                    x,y,z=b;px=x+path['width_m']/2+.4
                    if -75<=px<=70 and -65<=y<=65:continue
                    try:pz=ground(px,y)
                    except ValueError:continue
                    furniture.box((px,y,pz+.38),(.12,.12,.76),'Oak')
                    furniture.box((px,y-.07,pz+.58),(.2,.025,.22),'AwningBlue')
    for ob in furniture.flush(.006):
        ob['reserve_role']='wayfinding_and_trail_utilities'
    report['wayfinding_posts']=waypoint_count
    report['public_utilities']=[]
    for utility in plan.get('utilities',{}).get('points',[]):
        x,y=utility['center_m'];z=ground(x,y)
        u=B(utility['id'],trails_col,(x,y,z))
        kind=utility['kind']
        if 'drinking' in kind:
            u.box((0,0,.53),(.46,.38,1.06),'Granite')
            u.box((0,0,1.07),(.55,.43,.05),'Zinc')
            u.rod((.1,0,1.1),(.1,0,1.35),.018,'Zinc',n=8)
            u.rod((.1,0,1.35),(-.06,0,1.35),.018,'Zinc',n=8)
            u.box((0,-.21,.78),(.20,.025,.10),'BluePaint')
        elif 'tank' in kind:
            u.box((0,0,.035),(1.6,1.3,.07),'Granite')
            u.rod((0,0,.075),(0,0,.105),.40,'Iron',n=20)
            for xx in(-.15,.15):u.box((xx,0,.12),(.07,.35,.03),'Zinc')
        else:
            emergency='emergency' in kind
            u.box((0,0,.75),(.72,.36,1.5),'White' if emergency else 'Sage')
            u.box((0,-.19,1.1),(.48,.025,.35),'Burgundy' if emergency else 'Ink')
            if emergency:
                u.box((0,-.21,1.1),(.30,.02,.07),'White');u.box((0,-.21,1.1),(.07,.02,.30),'White')
                u.box((0,-.21,.65),(.13,.05,.18),'Iron')
            else:u.rod((.22,-.20,.75),(.22,-.20,.90),.015,'Zinc',n=6)
        for ob in u.flush(.005):ob['reserve_role']='public_utility';ob['reserve_utility_id']=utility['id']
        report['public_utilities'].append(utility['id'])
    visitor=plan.get('visitor_furniture',{})
    furnishings=B('Reserve_Public_Rest_Furniture',trails_col)
    for x,y in visitor.get('benches',[]):
        z=ground(x,y)
        furnishings.box((x,y,z+.46),(1.8,.48,.09),'Oak')
        furnishings.box((x,y+.21,z+.76),(1.8,.07,.55),'Oak')
        for dx in(-.65,.65):furnishings.box((x+dx,y,z+.22),(.07,.36,.44),'Iron')
    for x,y in visitor.get('picnic_tables',[]):
        z=ground(x,y)
        furnishings.box((x,y,z+.75),(1.8,.80,.08),'Oak')
        for side in(-1,1):
            furnishings.box((x,y+side*.68,z+.46),(1.8,.30,.08),'Oak')
            for dx in(-.65,.65):furnishings.rod((x+dx,y+side*.78,z),(x+dx,y,z+.72),.045,'Oak',n=6)
    for x,y in visitor.get('bike_racks',[]):
        z=ground(x,y)
        for j in range(5):
            xx=x+(j-2)*.65
            furnishings.rod((xx,y-.25,z),(xx,y-.25,z+.75),.025,'Zinc',n=8)
            furnishings.rod((xx,y+.25,z),(xx,y+.25,z+.75),.025,'Zinc',n=8)
            furnishings.rod((xx,y-.25,z+.75),(xx,y+.25,z+.75),.025,'Zinc',n=8)
    for x,y in visitor.get('trailhead_boards',[]):
        z=ground(x,y)
        for dx in(-.65,.65):furnishings.rod((x+dx,y,z),(x+dx,y,z+2.0),.055,'Oak',n=7)
        furnishings.box((x,y,z+1.4),(1.4,.10,.8),'Oak')
        furnishings.box((x,y-.06,z+1.4),(1.25,.015,.65),'Linen')
        for j in range(5):furnishings.box((x-.45+j*.22,y-.075,z+1.4),(.018,.01,.45),'Sage')
    for ob in furnishings.flush(.004):ob['reserve_role']='public_rest_and_trailhead_furniture'
    pitches=B('Reserve_Serviced_Tent_Pitches',trails_col)
    for i,(x,y) in enumerate(visitor.get('tent_pitches',[])):
        z=ground(x,y)
        pitches.box((x,y,z+.025),(5.4,5.4,.05),'Dirt')
        for dx in(-2.7,2.7):pitches.box((x+dx,y,z+.08),(.12,5.5,.12),'Oak')
        for dy in(-2.7,2.7):pitches.box((x,y+dy,z+.08),(5.5,.12,.12),'Oak')
        if i%2==0:
            pitches.poly([(x-1.4,y-1.7,z+.07),(x+1.4,y-1.7,z+.07),(x,y-1.7,z+1.9),
                          (x-1.4,y+1.7,z+.07),(x+1.4,y+1.7,z+.07),(x,y+1.7,z+1.9)],
                         [(0,2,5,3),(2,1,4,5),(3,5,4)],'Canvas')
            for side in(-1,1):pitches.rod((x,y+side*1.7,z+1.9),(x,y+side*2.5,z+.05),.01,'Linen',n=4)
            pitches.box((x-.5,y,z+.09),(.65,1.85,.07),'AwningBlue')
            pitches.box((x+.5,y,z+.09),(.65,1.85,.07),'Sage')
    for ob in pitches.flush():ob['reserve_role']='tent_pitches'
    for key,location,target,ortho in [
        ('15_Reserve_Overview',(235,-375,235),(-110,0,12),None),
        ('16_Reserve_Topography',(-200,70,920),(-200,70,0),880),
        ('17_Reserve_Visitor_Hub',(-58,-165,69),(-128,-70,4),None),
        ('18_Reserve_Camp',(-114,-189,55),(-175,-112,5),None),
    ]:
        ob=api['camera'](key,location,target,lens=45,ortho=ortho);ob.data.clip_end=2500
    for ob in scene.objects:
        if ob.type=='CAMERA':
            ob.data.clip_end=max(ob.data.clip_end,1800)
    scene.render.threads_mode='FIXED';scene.render.threads=6
    scene['reserve_plan_sha256']=__import__('hashlib').sha256((ROOT/'reserve_plan.json').read_bytes()).hexdigest()
    scene['reserve_plan_module_sha256']=__import__('hashlib').sha256((ROOT/'tools/reserve_plan.py').read_bytes()).hexdigest()
    scene['reserve_geometry']=json.dumps(report)
    return report
