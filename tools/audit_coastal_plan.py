"""Independent surface/entrance/arcade contract; fails on blocked paved routes."""
import json
from pathlib import Path
from collections import deque

ROOT=Path(__file__).resolve().parents[1]
def load(name): return json.loads((ROOT/'game/data'/name).read_text(encoding='utf8'))

def main():
    world=load('map.json'); plan=load('coastal_plan.json'); spaces=load('spaces.json')
    blocked=set(map(tuple,world['blockers']))
    for lot in world['solid_lots']:
        x,y=lot['pos'];w,h=lot['footprint']
        blocked|={(xx,yy) for yy in range(y,y+h) for xx in range(x,x+w)}-set(map(tuple,lot.get('open_cells',[])))-{tuple(lot.get('door',[-1,-1]))}
    surfaces=set()
    for material,raw in plan['surfaces'].items():
        cells=set(map(tuple,raw))
        assert not cells & surfaces, 'Materials overlap'
        assert not cells & blocked, f'{material}: paved blockers {cells & blocked}'
        assert all(0<=x<60 and 0<=y<48 for x,y in cells), 'Surface outside land bounds'
        surfaces |= cells
    def reached(start):
        q=deque([start]); seen={start}
        while q:
            x,y=q.popleft()
            for n in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
                if n in surfaces and n not in seen: seen.add(n); q.append(n)
        return seen
    network=reached((32,24))
    assert network == surfaces, f'Detached surface fragments: {surfaces-network}'
    entrances={tuple(p['from']['pos']) for p in spaces['portals'] if p['from']['space']=='town'}
    assert entrances <= network, f'Unconnected entrances: {entrances-network}'
    for p in plan['passages']:
        openings=set(map(tuple,p['open_cells']))
        assert openings<=network, f'Arcade {p["id"]} disconnected'
        lot=next(l for l in world['solid_lots'] if l['id']=='plan_passage_'+p['id'])
        assert lot['open_cells']==p['open_cells'], 'Visual and collision openings differ'
        assert {tuple(l['entrance']) for l in plan['links']} >= entrances
    print(f'COASTAL PLAN PASS: {len(plan["streets"])} streets; {len(entrances)} connected entrances; {len(plan["passages"])} traversable arcades; {len(surfaces)} legal surface cells')

if __name__=='__main__': main()
