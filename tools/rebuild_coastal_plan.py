"""Reconstruct circulation, planting and actual passage collision deterministically.

Uses existing functional entrances as anchors. Does not regenerate interiors or
overwrite household/economy data. Run audit_map.py after regeneration.
"""
import json
import math
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'game/data'
LOTS = ROOT / 'game/assets/art/houses/lots.json'


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')


def cells(rect):
    x, y, w, h = rect
    return {(xx, yy) for yy in range(y, y + h) for xx in range(x, x + w)}


def distance(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = max(0, min(1, ((p[0]-a[0])*dx+(p[1]-a[1])*dy) / max(0.001, dx*dx+dy*dy)))
    return math.hypot(p[0]-a[0]-t*dx, p[1]-a[1]-t*dy)


def main():
    world = read(DATA / 'map.json')
    lots = read(LOTS)
    w, h = world['width'], world['height']
    # Natural pond shorelines replace the two rectangular basins. Ocean is canonical.
    water = {tuple(p) for p in world['water'] if p[0] >= 60}
    for cx, cy, rx, ry in [(31.5, 3.8, 3.9, 2.45), (31.5, 44.1, 4.1, 2.1)]:
        for y in range(h):
            for x in range(60):
                if ((x-cx)/rx)**2 + ((y-cy)/ry)**2 < 1:
                    water.add((x, y))
    walls = set(map(tuple, world['walls']))
    occupied = set(walls) | water
    world['solid_lots']=[l for l in world['solid_lots'] if not l['id'].startswith('plan_passage_')]
    for lot in world['solid_lots']:
        occupied |= cells([*lot['pos'], *lot['footprint']]) - set(map(tuple, lot.get('open_cells', []))) - {tuple(lot.get('door', [-1, -1]))}
    for area in world['areas'].values():
        if area.get('type') != 'plaza':
            occupied |= cells(area['rect'])
    objects = {tuple(o['pos']) for o in world['objects']}
    for o in read(DATA/'production.json').get('worksites', []):
        if isinstance(o, dict) and 'pos' in o: objects.add(tuple(o['pos']))
    protected = set(objects)
    portals = read(DATA/'spaces.json')['portals']
    entrances = [tuple(p['from']['pos']) for p in portals if p['from']['space'] == 'town']
    protected.update(entrances)
    agents = read(DATA/'agents.json')
    for a in agents.get('agents', []) + agents.get('affiliates', []):
        for k in ['home', 'spawn']:
            if k in a: protected.add(tuple(a[k]))
    streets = [
        dict(id='western_arrival', material='asphalt', width=2.0, points=[[0,25],[7,25],[8.5,27],[8.5,33],[7,35],[7,39],[10,40]]),
        dict(id='garden_boulevard', material='asphalt', width=1.8, points=[[10,40],[26,40],[36,40],[44,40],[53,39],[55,36]]),
        dict(id='coastal_boulevard', material='asphalt', width=1.8, points=[[55,36],[55,30],[54.5,25],[55,20],[55,13],[54,10],[45,10],[36,10],[27,10],[20,10]]),
        dict(id='civic_spine', material='paving', width=2.5, points=[[32,8],[32,17],[32,20],[31,23],[32,26],[35,27],[35,33],[36,34],[37,40]]),
        dict(id='market_walk', material='paving', width=1.6, points=[[9,20],[14,20],[21,21],[28,21],[36,21],[44,20],[54,20]]),
        dict(id='cross_town_passage', material='paving', width=1.7, points=[[5,25],[15,25],[24,25],[28,25],[36,25],[44,25],[51,24],[55,24],[58,24]]),
        dict(id='southern_mews', material='paving', width=1.2, points=[[9,35],[19,35],[27,35],[31,34],[36,35],[45,35],[46,39]]),
        dict(id='upper_mews', material='paving', width=1.3, points=[[3,5],[10,4],[20,4],[27,5],[27,9],[32,9],[36,9],[36,4],[45,4],[53,5],[55,10]]),
        dict(id='west_park_trail', material='gravel', width=1.0, points=[[7,14],[5,16],[4,20],[5,23],[5,27],[4,30],[5,34],[7,35]]),
        dict(id='seaside_garden_walk', material='paving', width=1.25, points=[[58,13],[57,17],[58,21],[58,27],[57,31],[58,35],[58,39],[59,40],[59,47]]),
        dict(id='south_lake_walk', material='gravel', width=1.0, points=[[26,40],[27,43],[26,46],[30,47],[35,47],[38,44],[37,40]]),
    ]
    surfaces = {}
    candidates = {(x,y) for y in range(h) for x in range(60)} - occupied
    # Sidewalks form real continuous surfaces; centre lanes override them.
    for street in streets:
        points = street['points']
        for c in candidates:
            d = min(distance(c,a,b) for a,b in zip(points, points[1:]))
            if d <= street['width']/2 + (0.65 if street['material']=='asphalt' else 0.18):
                surfaces[c] = 'paving' if street['material']=='asphalt' else street['material']
        if street['material']=='asphalt':
            for c in candidates:
                if min(distance(c,a,b) for a,b in zip(points, points[1:])) <= street['width']/2:
                    surfaces[c]='asphalt'
    for rect in [[27,20,10,8],[28,32,9,3],[19,9,9,3],[46,20,8,4]]:
        for c in cells(rect) & candidates: surfaces[c]='paving'
    # Every functional entrance gets a shortest legal path to the new network.
    # Decorative passage openings are included too; no pavement dead ends in walls.
    targets = entrances + [tuple(p) for lot in world['solid_lots'] for p in lot.get('open_cells', [])]
    links = []
    free = {(x,y) for y in range(h) for x in range(60)} - occupied - objects
    for entrance in targets:
        free.add(entrance)
        q=deque([entrance]); prev={entrance:None}; found=None
        while q:
            p=q.popleft()
            if p in surfaces: found=p; break
            for n in [(p[0]+1,p[1]),(p[0]-1,p[1]),(p[0],p[1]+1),(p[0],p[1]-1)]:
                if n in free and n not in prev: prev[n]=p; q.append(n)
        if found is None: raise RuntimeError(f'No street connection at {entrance}')
        link=[]
        while found is not None:
            surfaces[found]='paving'; link.append(list(found)); found=prev[found]
        links.append(dict(entrance=list(entrance), cells=link))
    # Porous groves replace impassable rectangular tree belts.
    trees=set()
    for x,y in candidates - protected:
        edge_grove = (x < 7 and 15 < y < 36) or (55 <= x <= 57 and 13 < y < 38)
        avenue = (y in [12,38] and 8<x<54) or (x in [29,35] and 10<y<20)
        lakeside = (27<x<38 and (y<8 or y>41))
        pocket = (x*31+y*17)%43 == 0 and 2<x<57 and 13<y<46
        if not (edge_grove or avenue or lakeside or pocket): continue
        if ((x*17+y*11)%7 != 0 and not (avenue and x%4 == 0) and not pocket): continue
        if any(abs(x-p[0])+abs(y-p[1]) < 2 for p in protected): continue
        if any((x+dx,y+dy) in surfaces for dx,dy in [(0,0),(1,0),(-1,0),(0,1),(0,-1)]): continue
        if any(abs(x-p[0])+abs(y-p[1]) < 3 for p in trees): continue
        trees.add((x,y))
    # Retain the planted cliff recess enclosed by the upper-town retaining lip.
    trees.add((12,13))
    # Arcade structures have explicit walk-through cells, matching visible openings.
    passages = [dict(id='west_garden_arch', pos=[3,23], footprint=[4,2], open_cells=[[4,23],[4,24],[5,23],[5,24]]),
                dict(id='coast_garden_arch',pos=[55,27], footprint=[4,2],open_cells=[[56,27],[56,28],[57,27],[57,28]])]
    world['solid_lots']=[l for l in world['solid_lots'] if not l['id'].startswith('plan_passage_')]
    for p in passages:
        pc=cells([*p['pos'],*p['footprint']]); op=set(map(tuple,p['open_cells']))
        if pc & occupied: raise RuntimeError(f'Passage overlap: {p["id"]}')
        trees-=pc
        for c in pc-op: surfaces.pop(c,None)
        for c in op: surfaces[c]='paving'
        world['solid_lots'].append(dict(p,id='plan_passage_'+p['id'],sprite='coastal_arcade'))
    # Narrow diagonal trail samples must remain four-neighbour connected.
    # Remove tiny detached paving fragments rather than advertising false paths.
    q=deque([(32,24)]); connected={(32,24)}
    while q:
        x,y=q.popleft()
        for n in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
            if n in surfaces and n not in connected: connected.add(n);q.append(n)
    surfaces={c:m for c,m in surfaces.items() if c in connected}
    # Regular tree belts occupy verges, never sidewalks or entrance approaches.
    belt=[]
    # Reject planting that seals a residual grass alley after all runtime props.
    runtime_blocked=walls|water|objects|trees
    runtime_blocked.update(tuple(p) for p in world.get('solid_props', []))
    for lot in world['solid_lots']:
        runtime_blocked |= cells([*lot['pos'],*lot['footprint']])-set(map(tuple,lot.get('open_cells',[])))-{tuple(lot.get('door',[-1,-1]))}
    def connected_without(cell):
        free_cells={(xx,yy) for yy in range(h) for xx in range(w)}-runtime_blocked-{cell}
        q=deque([(32,24)]); seen={(32,24)}
        while q:
            xx,yy=q.popleft()
            for n in [(xx-1,yy),(xx+1,yy),(xx,yy-1),(xx,yy+1)]:
                if n in free_cells and n not in seen: seen.add(n);q.append(n)
        return len(seen)==len(free_cells)
    for x,y in sorted(candidates-protected, key=lambda c:(c[1],c[0])):
        if (x,y) in surfaces or (x,y) in trees: continue
        if not any((x+dx,y+dy) in surfaces for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]): continue
        if any(abs(x-p[0])+abs(y-p[1])<2 for p in protected): continue
        if any(abs(x-p[0])+abs(y-p[1])<3 for p in trees): continue
        if any((x,y) in cells([*p['pos'],*p['footprint']]) for p in passages): continue
        if x%3 != 1 and y%3 != 1: continue
        if not connected_without((x,y)): continue
        trees.add((x,y)); runtime_blocked.add((x,y)); belt.append([x,y])
    world['trees']=[list(c) for c in sorted(trees,key=lambda c:(c[1],c[0]))]
    world['water']=[list(c) for c in sorted(water,key=lambda c:(c[1],c[0]))]
    world['blockers']=[list(c) for c in sorted(walls|water|trees,key=lambda c:(c[1],c[0]))]
    # Replace scattered garden fences and giant paved polygons with the authored plan.
    lots['gardens']=[]
    lots['courts']=[]
    lots['main_streets']=streets
    planting=[]
    for x,y in [(10,26),(16,26),(24,26),(28,19),(36,19),(45,24),(50,26),(20,36),(26,36),(38,39),(46,41),(52,30),(56,16),(56,34),(25,45),(37,45)]:
        if (x,y) not in occupied and (x,y) not in surfaces:
            planting.append([x,y])
    beds=[]
    for x,y in sorted(candidates-protected-trees, key=lambda c:(c[1],c[0])):
        if (x,y) in surfaces: continue
        if any((x,y) in cells([*p['pos'],*p['footprint']]) for p in passages): continue
        if not any((x+dx,y+dy) in surfaces for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]): continue
        if (x+y)%2: continue
        beds.append(dict(pos=[x,y],variant=(x*7+y*3)%6))
    plan=dict(version=2,streets=streets,links=links,passages=passages,planting=planting,tree_belt=belt,flowerbeds=beds,
              surfaces={mat:[list(c) for c in sorted(surfaces,key=lambda c:(c[1],c[0])) if surfaces[c]==mat] for mat in ['paving','asphalt','gravel']})
    write(DATA/'map.json',world);write(LOTS,lots);write(DATA/'coastal_plan.json',plan)
    print(f'Coastal plan: {len(streets)} streets, {len(links)} entrance links, {len(surfaces)} paved cells, {len(trees)} trees, {len(passages)} traversable arcades')


if __name__=='__main__': main()
