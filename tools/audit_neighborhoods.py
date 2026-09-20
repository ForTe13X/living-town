"""Independent reachability check for authored interior recesses and partitions."""
from collections import deque
from rebuild_coastal_plan import read, DATA, LOTS, cells


def main():
    spaces=read(DATA/'spaces.json'); interiors=read(DATA/'interiors.json')
    checked=0
    for sid in ['cafe','library','wash','work','home','home2','shop']:
        w,h=spaces['spaces'][sid]['bounds'][2:]
        for fid,content in interiors[sid].items():
            portals={tuple(p[side]['pos']) for p in spaces['portals'] for side in ['from','to'] if p[side]['space']==sid and p[side]['floor']==fid}
            blocked={(x,y) for y in range(h) for x in range(w) if x in [0,w-1] or y in [0,h-1]}-portals
            cut=set().union(*(cells(r) for r in content.get('cutouts',[])))
            assert not cut&portals, f'{sid}: recess covers entrance'
            blocked |= cut
            for f in content['furniture']:
                if f['slot'] in ['stairs','rug','window','doorway','archway']:continue
                x,y=f['pos'];fw,fh=f.get('size',[1,1]);occupied=cells([x,y-fh+1,fw,fh])
                assert not occupied&cut, f'{sid}: furniture in recess: {f}'
                blocked |= occupied-portals
            free=cells([0,0,w,h])-blocked
            start=sorted(portals)[0];q=deque([start]);seen={start}
            while q:
                x,y=q.popleft()
                for p in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
                    if p in free and p not in seen:seen.add(p);q.append(p)
            assert portals<=seen, f'{sid}/{fid}: disconnected portal'
            assert free<=seen, f'{sid}/{fid}: isolated floor {free-seen}'
            for f in content['furniture']:
                if f.get('advertises'):
                    x,y=f['pos']
                    assert any(p in seen for p in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]),f'{sid}: inaccessible interaction {f["slot"]}'
            checked+=1
    terraces=[l for l in read(LOTS)['lots'] if l.get('row_id')]
    assert len(terraces)==4
    assert {l['facing'] for l in terraces}=={'north','south'}
    world=read(DATA/'map.json')
    for lot in read(LOTS)['lots']:
        if not lot.get('architecture'): continue
        assert not lot.get('flip',False), 'Physical facing cannot be represented by a sprite mirror'
        facing=lot.get('facing','south')
        assert facing in ['north','south','east','west']
        if lot.get('coastal_asset','').startswith('terrace_'):
            assert lot['coastal_asset']=='terrace_'+facing
    for sid,area in world['areas'].items():
        if area.get('type')=='plaza':continue
        door=next(p['from']['pos'] for p in spaces['portals'] if p['from']['space']=='town' and p['to']['space']==sid)
        x,y,w,h=area['rect']
        assert door[1] == (y if area['facing']=='north' else y+h-1), f'{sid}: facade and actual portal disagree'
    print(f'NEIGHBORHOOD PASS: {checked} connected interior floors, legal recesses, reachable interactions, 4 aligned terraces')


if __name__=='__main__':main()
