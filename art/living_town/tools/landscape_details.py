"""Reference-led landscape props, material-batched through the town mesh API.

This module does not excavate terrain, create water, alter parcels, or move
existing routes. All coordinates are metres in the authored Blender XY plan.
The caller owns landscape_plan.json and the terrain/clearance implementations.
"""
from __future__ import annotations

import hashlib
import json
import math
import random


def _distance_to_segment(p, a, b):
    dx, dy = b[0]-a[0], b[1]-a[1]
    d = dx*dx+dy*dy
    t = max(0., min(1., ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/d)) if d else 0.
    return math.hypot(p[0]-a[0]-t*dx, p[1]-a[1]-t*dy)


def _inside(p, polygon):
    inside = False
    for a, b in zip(polygon, polygon[1:]+polygon[:1]):
        if _distance_to_segment(p, a, b) < 1.e-7:
            return True
        if (a[1] > p[1]) != (b[1] > p[1]):
            if p[0] < (b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]:
                inside = not inside
    return inside


def _sample_line(points, spacing=.35):
    out = []
    for a, b in zip(points, points[1:]):
        count = max(1, math.ceil(math.dist(a, b)/spacing))
        out.extend([(a[0]+(b[0]-a[0])*i/count,
                     a[1]+(b[1]-a[1])*i/count) for i in range(count)])
    if points:
        out.append(tuple(points[-1]))
    return out


def _ellipse(center, radii, count=20, angle=0.):
    co, si = math.cos(angle), math.sin(angle)
    return [(center[0]+radii[0]*math.cos(t)*co-radii[1]*math.sin(t)*si,
             center[1]+radii[0]*math.cos(t)*si+radii[1]*math.sin(t)*co)
            for t in [i*math.tau/count for i in range(count)]]


def _shape(record, default_radii=(1.2, .7)):
    if record.get('polygon'):
        return [tuple(p) for p in record['polygon']]
    center = record.get('center', record.get('xy'))
    if center is None:
        raise ValueError('Landscape patch needs polygon, center or xy: '+str(record))
    radii = record.get('radii', record.get('radii_m', default_radii))
    return _ellipse(center, radii, angle=math.radians(record.get('yaw_degrees', 0.)))


def _footprint_samples(polygon, spacing=.25):
    """Boundary and interior samples; .13 m query margins cover the grid gaps."""
    out = _sample_line(polygon+polygon[:1], spacing)
    x0, x1 = min(p[0] for p in polygon), max(p[0] for p in polygon)
    y0, y1 = min(p[1] for p in polygon), max(p[1] for p in polygon)
    nx, ny = max(1, math.ceil((x1-x0)/spacing)), max(1, math.ceil((y1-y0)/spacing))
    for i in range(nx+1):
        for j in range(ny+1):
            p = (x0+(x1-x0)*i/nx, y0+(y1-y0)*j/ny)
            if _inside(p, polygon):
                out.append(p)
    return out


def build_reference_landscape(api, landscape_plan, route_clear, parcel_clear):
    """Build approved metric landscape data and return counts + placement evidence.

    Supported records: paths[{id,points,width_m}], street_trees[{id,xy,...}],
    gardens[{id,polygon|center/radii}], park{willows,benches,reeds,flowerbeds},
    coastal_grass{patches,access_gaps}. Unknown keys are harmless; missing lists
    are empty. New props query both caller clearances and new path envelopes.
    """
    Batch, coll = api['Batch'], api['coll']
    terrain, ground = api['TERRAIN'], api['ground_z']
    rng = random.Random(landscape_plan.get('seed', 20261012))
    parent = coll('05_Reference_Landscape')
    batches = {name: Batch('Reference_'+name, parent) for name in
               ('Garden_Paths', 'Pocket_Gardens', 'Street_Trees', 'Pond_Planting',
                'Park_Furniture', 'Coastal_Dune_Grass')}
    paths = landscape_plan.get('paths', [])
    park = landscape_plan.get('park', {})
    coastal = landscape_plan.get('coastal_grass', {})
    rules = landscape_plan.get('clearance_rules', {})
    drains = api.get('TOPO_PLAN', {}).get('drainage', {}).get('grates_and_outfalls', [])
    pond = landscape_plan.get('pond', park.get('pond', {}))
    counts = {key: 0 for key in ('paths', 'path_stations', 'garden_beds',
              'street_trees', 'willows', 'benches', 'reed_clumps',
              'flower_clusters', 'meadow_clumps', 'beach_grass_patches', 'beach_grass_clumps')}
    evidence = {'schema': 'living_town.reference_landscape_build.v1',
                'plan_content_sha256': hashlib.sha256(json.dumps(
                    landscape_plan, sort_keys=True, separators=(',', ':')).encode()).hexdigest(),
                'seed': landscape_plan.get('seed', 20261012), 'counts': counts,
                'accepted': [], 'rejected': [], 'terrain_authority':
                'TERRAIN.design_height / beach_height; no terrain or water authored here',
                'triangle_budget': min(150000, landscape_plan.get('triangle_budget', 145000))}

    def reject(role, record, why):
        evidence['rejected'].append({'role': role, 'id': record.get('id'), 'reason': why})

    def new_path_clear(x, y, margin=.13):
        for path in paths:
            width = path.get('width_m', path.get('width', 1.5))
            if any(_distance_to_segment((x, y), a, b) < width/2+margin
                   for a, b in zip(path['points'], path['points'][1:])):
                return False
        return True

    def clear(x, y, margin=.13):
        if pond:
            cx, cy = pond['center']; rx, ry = pond['water_radii_m']
            if ((x-cx)/(rx+margin))**2+((y-cy)/(ry+margin))**2 < 1.:
                return False
        if any(math.dist((x, y), d['center']) <
               rules.get('drainage_hardware_keepout_radius_m', .7)+margin for d in drains):
            return False
        return (route_clear(x, y, margin) and parcel_clear(x, y, margin)
                and new_path_clear(x, y, margin))

    def patch_clear(polygon):
        return all(clear(x, y, .13) for x, y in _footprint_samples(polygon))

    def accepted(role, record, **extra):
        evidence['accepted'].append({'role': role, 'id': record.get('id'), **extra})

    def surface_patch(batch, polygon, material, height=ground, offset=.021):
        # Centroid fan works for the plan's ellipses/convex garden polygons.
        center = tuple(sum(p[k] for p in polygon)/len(polygon) for k in (0, 1))
        vertices = [(center[0], center[1], height(*center)+offset)]
        vertices += [(x, y, height(x, y)+offset) for x, y in polygon]
        batch.poly(vertices, [(0, i+1, (i+1) % len(polygon)+1)
                              for i in range(len(polygon))], material)

    # Paths are sampled on both edges and down the center, not placed as slabs.
    for record in paths:
        points = _sample_line(record['points'], .4)
        width = float(record.get('width_m', record.get('width', 1.5)))
        if len(points) < 2 or width <= 0:
            reject('path', record, 'degenerate path'); continue
        vertices = []
        closed = math.dist(points[0], points[-1]) < 1.e-8
        for i, (x, y) in enumerate(points):
            if closed and i in (0, len(points)-1):
                a, b = points[-2], points[1]
            else:
                a, b = points[max(0, i-1)], points[min(len(points)-1, i+1)]
            dx, dy = b[0]-a[0], b[1]-a[1]
            length = math.hypot(dx, dy) or 1.
            for side in (-.5, 0., .5):
                xx, yy = x-dy/length*width*side, y+dx/length*width*side
                vertices.append((xx, yy, ground(xx, yy)+.026))
        if not all(parcel_clear(x, y, rules.get('new_path_building_clearance_m', .3))
                   for x, y, _ in vertices):
            reject('path', record, 'ribbon intersects protected parcel'); continue
        faces = []
        for i in range(len(points)-1):
            for j in range(2):
                a, b = i*3+j, (i+1)*3+j
                faces.extend([(a, b, b+1), (a, b+1, a+1)])
        batches['Garden_Paths'].poly(vertices, faces, record.get('material', 'Courtyard'))
        counts['paths'] += 1; counts['path_stations'] += len(points)
        accepted('path', record, width_m=width, stations=len(points),
                 length_m=round(sum(math.dist(a, b) for a, b in zip(points, points[1:])), 3),
                 surface_offset_m=.026, terrain_sampled_vertices=len(vertices))

    def slender_tree(record, willow=False):
        x, y = record.get('xy', record.get('center'))
        height = float(record.get('height_m', 5.8 if willow else 6.4))
        radius = float(record.get('crown_radius_m', 2.0 if willow else 1.45))
        trunk_margin = float(record.get('trunk_radius_m', .2))+rules.get(
            'minimum_ground_obstacle_to_route_edge_m', .45)
        crown_margin = radius+rules.get('minimum_canopy_to_building_footprint_m', .35)
        if not clear(x, y, trunk_margin) or not parcel_clear(x, y, crown_margin):
            reject('willow' if willow else 'street_tree', record,
                   'trunk/path or crown/parcel clearance'); return
        z = ground(x, y)
        stem = max(2.5, float(record.get('clear_stem_height_m', 2.5)))
        if height < stem+1.2:
            reject('willow' if willow else 'street_tree', record, 'height cannot provide clear stem'); return
        batch = batches['Pond_Planting' if willow else 'Street_Trees']
        # Bent narrow trunk, visible fork and branch hierarchy; no orchard balls.
        lean = rng.uniform(-.12, .12)
        p0, p1 = (x, y, z), (x+lean, y+.05, z+height*.46)
        p2 = (x+lean*1.6, y+.11, z+height*.90)
        batch.rod(p0, p1, .115 if not willow else .16, 'Trunk', n=7, r2=.072)
        batch.rod(p1, p2, .072, 'Trunk', n=6, r2=.018)
        # Connected inner foliage makes a complete crown rather than a necklace
        # of pointed pods. All horizontal leaf extents stay inside declared R.
        canopy = height-stem
        for j, zz in enumerate((z+stem+canopy*.50, z+height*.88)):
            batch.ellipsoid((x+lean, y+.05, zz),
                            (radius*.48, radius*.42, height*.12),
                            'LeafDark' if j == 0 else 'Leaf', n=8, rings=4)
        for i in range(9):
            a = i*2.39996+rng.uniform(-.16, .16)
            reach = radius*rng.uniform(.45, .61)
            bz = z+stem+(height-stem)*(.04+i*.045)
            end = (x+math.cos(a)*reach, y+math.sin(a)*reach,
                   min(z+height-height*.11, z+stem+(height-stem)*(.45+rng.uniform(.0, .38))))
            batch.rod((x+lean, y+.05, bz), end, .043, 'Trunk', n=5, r2=.012)
            if willow:
                batch.ellipsoid(end, (radius*.34, radius*.29, height*.11),
                                'Leaf', n=8, rings=4)
                tail = (end[0]+math.cos(a)*radius*.08, end[1]+math.sin(a)*radius*.08,
                        max(z+stem+radius*.22, end[2]-height*rng.uniform(.21, .32)))
                batch.rod(end, tail, .012, 'Trunk', n=4, r2=.003)
                for j in range(3):
                    t = .25+j*.29
                    q = tuple(end[k]*(1-t)+tail[k]*t for k in range(3))
                    batch.ellipsoid(q, (radius*.18, radius*.16, radius*.22),
                                    'LeafSilver' if i % 3 == 0 else 'Leaf', n=8, rings=4)
            else:
                for j in range(2):
                    q = (end[0]+math.cos(a+j)*radius*.04,
                         end[1]+math.sin(a+j)*radius*.04,
                         min(z+height-height*.11, end[2]+(.14 if j else -.14)))
                    batch.ellipsoid(q, (radius*.34, radius*.29, height*.11),
                                    ('Leaf', 'LeafLight', 'Leaf')[i % 3], n=8, rings=4)
        counts['willows' if willow else 'street_trees'] += 1
        accepted('willow' if willow else 'street_tree', record, xy=[x, y],
                 root_z_m=round(z, 5), height_m=height, crown_radius_m=radius,
                 clear_stem_height_m=stem, route_query_margin_m=trunk_margin,
                 parcel_query_margin_m=crown_margin)

    willow_ids = {record for record in park.get('willows', []) if isinstance(record, str)}
    for record in landscape_plan.get('street_trees', []):
        slender_tree(record, willow=record.get('id') in willow_ids)
    for record in park.get('willows', []):
        if isinstance(record, dict):
            slender_tree(record, willow=True)

    def garden(record):
        polygon = _shape(record)
        batch = batches['Pocket_Gardens']
        # Garden polygons are compositional envelopes. Individual irregular soil
        # islands and plants are clipped around every protected route and door.
        samples = _footprint_samples(polygon, .7)
        rng.shuffle(samples)
        area = abs(sum(a[0]*b[1]-b[0]*a[1] for a, b in
                       zip(polygon, polygon[1:]+polygon[:1])))/2
        limit = max(0, min(int(record.get('plant_count', max(5, area*.36))), 48))
        used = []
        for x, y in samples:
            if len(used) >= limit: break
            if any(math.dist((x, y), p) < .9 for p in used): continue
            island = _ellipse((x, y), (.42, .35), count=10, angle=rng.random()*math.pi)
            if not all(_inside(p, polygon) for p in island) or not patch_clear(island): continue
            if any(math.dist((x, y), t['xy']) < .8 for t in landscape_plan.get('street_trees', [])): continue
            bench_near = False
            for bench in park.get('benches', []):
                bx, by = bench.get('center', bench.get('xy'))
                a = math.radians(bench.get('yaw_degrees', 0.))
                dx, dy = x-bx, y-by
                if abs(dx*math.cos(a)+dy*math.sin(a)) < 1.3 and abs(-dx*math.sin(a)+dy*math.cos(a)) < .8:
                    bench_near = True
            if bench_near: continue
            surface_patch(batch, island, 'Dirt')
            used.append((x, y)); z = ground(x, y)
            for side in (-1, 1):
                batch.ellipsoid((x+side*.07, y+side*.045, z+.27), (.26, .25, .27),
                                'LeafSilver' if len(used) % 3 == 0 else 'Leaf', n=8, rings=4)
            max_h = record.get('max_height_m', record.get('height_range_m', [.15, .85])[1])
            flower_h = min(.68, max_h-.15)
            for j in range(5):
                a = j*2.39996
                batch.ellipsoid((x+.15*math.cos(a), y+.14*math.sin(a), z+flower_h+.035*(j % 2)),
                                (.115, .11, .10), ('BloomCream', 'BloomBlue', 'BloomPink')[len(used) % 3], n=7, rings=4)
            # Small divided fern fronds give lower planting a distinct leaf form.
            for j in range(6):
                a = j*math.tau/6+.3; dx, dy = math.cos(a), math.sin(a)
                start, mid, tip = (x, y, z+.08), (x+dx*.16, y+dy*.16, z+.37), (x+dx*.32, y+dy*.32, z+.27)
                batch.rod(start, mid, .006, 'LeafDark', n=3, r2=.004)
                batch.rod(mid, tip, .004, 'LeafDark', n=3, r2=.001)
                for t in (.35, .65):
                    px, py, pz = x+dx*.32*t, y+dy*.32*t, z+.12+.22*math.sin(t*math.pi)
                    for side in (-1, 1):
                        batch.poly([(px, py, pz), (px+side*dy*.055+dx*.055, py-side*dx*.055+dy*.055, pz+.015),
                                    (px+dx*.08, py+dy*.08, pz+.025)], [(0, 1, 2)], 'LeafLight')
            counts['flower_clusters'] += 1
        if not used:
            reject('garden_bed', record, 'no safe planting island within envelope'); return
        counts['garden_beds'] += 1
        accepted('garden_bed', record, polygon=[list(p) for p in polygon],
                 clipped_planting_islands=len(used), plants=len(used),
                 requested_plants=record.get('plant_count'),
                 mask='existing/new routes, parcels, pond, drains, tree wells, benches')

    for record in landscape_plan.get('gardens', [])+park.get('flowerbeds', []):
        garden(record)
    if pond and not park.get('flowerbeds'):
        garden({'id': 'pond_south_flower_pocket', 'center': [30.1, -52.0],
                'radii': [1.2, .65], 'plant_count': 5})
        garden({'id': 'pond_west_flower_pocket', 'center': [15.0, -45.2],
                'radii': [.65, 1.0], 'plant_count': 4})

    # Approved meadow envelopes receive small clustered forbs, not a blanket
    # mesh across paths, bank geometry, furniture or tree wells.
    for record in landscape_plan.get('meadow_polygons', []):
        polygon = _shape(record); candidates = _footprint_samples(polygon, 1.4)
        rng.shuffle(candidates); used = []
        for x, y in candidates:
            if len(used) >= 18: break
            if not clear(x, y, .38): continue
            if pond:
                cx, cy = pond['center']; rx, ry = pond['outer_bank_radii_m']
                if ((x-cx)/(rx+.4))**2+((y-cy)/(ry+.4))**2 < 1.: continue
            if any(math.dist((x, y), t['xy']) < .85 for t in landscape_plan.get('street_trees', [])): continue
            if any(math.dist((x, y), p) < 1.1 for p in used): continue
            if any(math.dist((x, y), b.get('center', b.get('xy'))) < 1.5 for b in park.get('benches', [])): continue
            used.append((x, y)); zz = ground(x, y)
            b = batches['Pocket_Gardens']
            b.ellipsoid((x, y, zz+.14), (.28, .22, .15), 'LeafSilver', n=6, rings=3)
            for j in range(3):
                a = j*2.4; px, py = x+.14*math.cos(a), y+.14*math.sin(a)
                b.ellipsoid((px, py, zz+.29), (.065, .06, .05),
                            'BloomCream' if j else 'BloomBlue', n=5, rings=3)
            counts['meadow_clumps'] += 1
        accepted('meadow', record, safe_low_forb_clumps=len(used),
                 mask='all routes, parcels, outer pond bank, tree wells, benches, drains')

    for record in park.get('benches', []):
        x, y = record.get('xy', record.get('center'))
        angle = math.radians(record.get('yaw_degrees', 0.))
        co, si = math.cos(angle), math.sin(angle)
        def point(dx, dy): return (x+dx*co-dy*si, y+dx*si+dy*co)
        polygon = [point(dx, dy) for dx, dy in [(-.92, -.38), (.92, -.38), (.92, .38), (-.92, .38)]]
        if not patch_clear(polygon):
            reject('bench', record, 'bench footprint intersects protected circulation'); continue
        batch = batches['Park_Furniture']
        feet = [point(dx, dy) for dx in (-.65, .65) for dy in (-.24, .24)]
        seat_z = max(ground(*p) for p in feet)+.45
        for fx, fy in feet:
            batch.rod((fx, fy, ground(fx, fy)), (fx, fy, seat_z-.06), .035, 'Iron', n=5)
        for dy in (-.22, -.075, .075, .22):
            px, py = point(0., dy)
            batch.box((px, py, seat_z), (1.75, .12, .07), 'Oak', angle)
        for dx in (-.69, .69):
            fx, fy = point(dx, .27)
            batch.rod((fx, fy, seat_z-.06), (fx, fy, seat_z+.45), .03, 'Iron', n=5)
        for dz in (.18, .34):
            px, py = point(0., .27)
            batch.box((px, py, seat_z+dz), (1.75, .065, .12), 'Oak', angle)
        counts['benches'] += 1
        accepted('bench', record, xy=[x, y], foot_ground_z_m=[round(ground(*p), 5) for p in feet],
                 level_seat_z_m=round(seat_z, 5))

    reed_records = list(park.get('reeds', []))
    if pond and not reed_records:
        cx, cy = pond['center']; rx, ry = pond['water_radii_m']
        for i, a in enumerate((.2, .4, .6, 2.5, 2.7, 2.9, 4.0, 4.2, 4.4)):
            reed_records.append({'id': 'pond_reed_arc_'+str(i),
                                 'center': [cx+rx*1.15*math.cos(a), cy+ry*1.15*math.sin(a)],
                                 'radii': [.27, .20]})
    for record in reed_records:
        polygon = _shape(record, (.55, .35))
        if not patch_clear(polygon):
            reject('reeds', record, 'reed patch intersects route or parcel'); continue
        batch = batches['Pond_Planting']
        for i in range(9):
            x, y = rng.choice(_footprint_samples(polygon, .2))
            z = ground(x, y)
            h = rng.uniform(.65, 1.05)
            a = rng.random()*math.tau
            end = (x+.10*math.cos(a), y+.10*math.sin(a), z+h)
            batch.rod((x, y, z), end, .012, 'LeafSilver', n=4, r2=.005)
            batch.rod((end[0], end[1], end[2]-.13), end, .023, 'Trunk', n=5)
            batch.poly([(x, y, z+h*.22), (x+.20*math.cos(a), y+.20*math.sin(a), z+h*.65),
                        (x+.025*math.sin(a), y-.025*math.cos(a), z+h*.4)], [(0, 1, 2)], 'Leaf')
        counts['reed_clumps'] += 1
        accepted('reeds', record, stems=9, terrain_sampled=True)

    gaps = coastal.get('access_gaps', [])
    def in_gap(x, y, radius=.35):
        for gap in gaps:
            if isinstance(gap, (list, tuple)) and len(gap) == 2:
                if gap[0]-radius <= y <= gap[1]+radius: return True
            elif gap.get('polygon') and _inside((x, y), gap['polygon']): return True
            elif gap.get('y_range') and gap['y_range'][0]-radius <= y <= gap['y_range'][1]+radius: return True
            elif 'center_y' in gap and abs(y-gap['center_y']) <= gap['clear_width_m']/2+radius: return True
        return False

    if coastal.get('patches') and not callable(getattr(terrain, 'beach_height', None)):
        raise ValueError('Coastal vegetation requires TERRAIN.beach_height(x,y)')
    for record in coastal.get('patches', []):
        polygon = _shape(record, (1.4, .6))
        if not patch_clear(polygon):
            reject('beach_grass', record, 'patch intersects route or parcel'); continue
        if any(in_gap(x, y) for x, y in _footprint_samples(polygon, .5)):
            reject('beach_grass', record, 'reserved beach access/view gap'); continue
        samples = _footprint_samples(polygon, .3); rng.shuffle(samples)
        used = []
        for x, y in samples:
            if len(used) >= min(int(record.get('clumps', 12)), 22): break
            if any(math.dist((x, y), p) < .3 for p in used): continue
            if not clear(x, y, .17) or in_gap(x, y): continue
            z = terrain.beach_height(x, y)
            used.append((x, y))
            for i in range(7):
                a = rng.random()*math.tau; h = rng.uniform(.18, .46)
                dx, dy = math.cos(a), math.sin(a); w = .018
                batches['Coastal_Dune_Grass'].poly(
                    [(x-dy*w, y+dx*w, z), (x+dy*w, y-dx*w, z),
                     (x+dx*.08+dy*w*.7, y+dy*.08-dx*w*.7, z+h*.6),
                     (x+dx*.08-dy*w*.7, y+dy*.08+dx*w*.7, z+h*.6),
                     (x+dx*.16, y+dy*.16, z+h)],
                    [(0, 1, 2), (0, 2, 3), (3, 2, 4)],
                    'LeafSilver' if i % 3 else 'LeafLight')
            counts['beach_grass_clumps'] += 1
        counts['beach_grass_patches'] += 1
        accepted('beach_grass', record, clumps=len(used), height_function='TERRAIN.beach_height')

    triangles = {name: sum(max(0, len(face)-2) for _, faces, _ in batch.parts.values()
                           for face in faces) for name, batch in batches.items()}
    evidence['triangles_by_role'] = triangles
    evidence['added_triangles'] = sum(triangles.values())
    if evidence['added_triangles'] > evidence['triangle_budget']:
        raise ValueError('Reference landscape exceeds triangle budget: '+str(evidence['added_triangles']))
    evidence['objects'] = []
    for name, batch in batches.items():
        for obj in batch.flush():
            obj['landscape_role'] = name
            obj['landscape_plan_content_sha256'] = evidence['plan_content_sha256']
            obj['authored_metric_landscape'] = True
            evidence['objects'].append(obj.name)
    api['SCENE']['reference_landscape'] = json.dumps(evidence)
    return evidence
