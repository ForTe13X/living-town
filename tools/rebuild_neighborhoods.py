"""Author street-facing terraces and venue-specific plans; rerunnable without duplication."""
from rebuild_coastal_plan import read, write, DATA, LOTS, main as rebuild_circulation


def main():
    world, lots = read(DATA/'map.json'), read(LOTS)
    # Join adjoining small plots into genuine party-wall terraces, retaining cross streets.
    rows = [([13,1,7,3], [(13,1),(18,1)], 'south'),
            ([37,1,9,3], [(37,1),(42,1)], 'south'),
            ([20,36,7,3], [(20,36),(25,36)], 'south'),
            ([9,41,11,3], [(9,41),(14,41),(17,41)], 'north')]
    for i,(rect,origins,facing) in enumerate(rows):
        row_id = f'terrace_{i}'
        lots['lots'] = [l for l in lots['lots'] if (l['x'],l['y']) not in origins and l.get('row_id') != row_id]
        world['solid_lots'] = [l for l in world['solid_lots'] if tuple(l['pos']) not in origins and l['id'] != row_id]
        x,y,w,h=rect
        lots['lots'].append(dict(sprite='attached_slate_house',x=x,y=y,w=w,h=h,architecture='terrace',facing=facing,row_id=row_id,coastal_asset='terrace_'+facing))
        world['solid_lots'].append(dict(id=row_id,sprite='attached_slate_house',pos=[x,y],footprint=[w,h],facing=facing))
    # Existing specialist PixelLab sprites regain their individual identities.
    specialists={'chapel','bakery','hotel','plaza_mixed_block','infill_market_block','infill_residential_courtyard','infill_garden_row'}
    for lot in lots['lots']:
        if lot.get('row_id'): continue
        name=lot['sprite']
        if name in specialists:
            lot['architecture']='blueprint'
            lot['coastal_asset']='house:'+name
            lot['facing']='south'
        elif name == 'district_civic_facade': lot['coastal_asset']='civic'
        elif name == 'halles': lot['coastal_asset']='market'
        elif name in ['district_industrial_facade','infill_harbor_workshops']:
            lot['coastal_asset']='workshop_south'
            lot['facing']='south'
        elif lot.get('architecture'):
            # Front doors face the nearest horizontal street; paired rows show front/back.
            facing='north' if lot['y'] in [6,41] else 'south'
            lot['facing']=facing
            lot['coastal_asset']='terrace_'+facing
        if name == 'coast_pavilion_east':
            lot['architecture']='blueprint'
            lot['coastal_asset']='house:'+name
            lot['facing']='east'
        # A horizontal mirror is not a physical building rotation (and reverses lighting).
        if lot.get('architecture'): lot['flip']=False
    for aid, area in world['areas'].items():
        if area.get('type') != 'plaza': area['facing']='north' if aid in ['wash','work'] else 'south'
    write(DATA/'map.json',world); write(LOTS,lots)
    interiors=read(DATA/'interiors.json')
    def plan(sid,fid,rooms,walls=(),cutouts=()):
        floor=interiors[sid][fid]
        floor['furniture']=[f for f in floor['furniture'] if not f.get('neighborhood_partition')]
        floor['rooms']=[dict(label=label,rect=rect,tone=tone) for label,rect,tone in rooms]
        floor['cutouts']=list(cutouts)
        taken={tuple(f['pos']) for f in floor['furniture']}
        for p in walls:
            if tuple(p) not in taken:
                floor['furniture'].append(dict(slot='wall',pos=list(p),neighborhood_partition=True))
    plan('cafe','1f', [('Coffee bar',[1,1,6,2],'#b69266'),('Window salon',[1,3,5,2],'#9eac82')],[],[[6,4,2,2]])
    plan('cafe','2f', [('Bedroom',[1,1,3,4],'#ada082'),('Study',[5,1,2,4],'#87a5a0')],[(4,2),(4,4)])
    plan('library','1f',[('Reading rotunda',[2,1,5,4],'#86a7b1'),('West stacks',[1,2,2,3],'#af926a'),('Quiet wing',[6,2,2,3],'#af926a')],[(3,3),(5,3)],[[0,0,2,2],[7,0,2,2]])
    for f in interiors['library']['1f']['furniture']:
        if f['slot']=='bookshelf' and f['pos'] in [[1,1],[7,1]]: f['pos'][1]=2
    plan('wash','1f',[('Bathing gallery',[1,1,3,5],'#7caeb0'),('Changing hall',[4,1,3,6],'#bbb397'),('Private washrooms',[8,2,2,4],'#7caeb0')],[(3,2),(3,4),(3,5),(7,3),(7,5)],[[0,6,3,2]])
    for f in interiors['wash']['1f']['furniture']:
        if f['slot']=='plant' and f['pos']==[1,6]: f['pos']=[3,6]
    plan('work','1f',[('Craft hall',[1,1,5,5],'#b8a087'),('Tool store',[7,1,2,3],'#8b9c9c')],[(6,1),(6,2),(6,4)],[[7,4,3,3]])
    for f in interiors['work']['1f']['furniture']:
        if f['slot']=='plant' and f['pos']==[8,5]: f['pos']=[8,3]
    plan('home','1f',[('Sleeping wing',[1,1,6,3],'#a3a78b'),('Living room',[1,4,6,4],'#c5a27f'),('Kitchen',[8,5,3,3],'#b9b29a'),('Bathroom',[8,1,3,3],'#83a5ab')],[(1,4),(2,4),(4,4),(5,4),(6,4)])
    plan('shop','1f',[('Produce aisle',[3,1,5,4],'#b0ae83'),('Counter',[1,1,2,2],'#ad997b'),('Stockroom',[1,4,2,2],'#949b8a')],[])
    for f in interiors['shop']['1f']['furniture']:
        if f['slot']=='crate' and f['pos']==[2,4]: f['pos']=[2,5]
        if f['slot']=='sacks' and f['pos']==[1,4]: f['pos']=[1,5]
    # Keep the atelier doorway and the staircase connected to the entrance hall.
    for f in interiors['home2']['1f']['furniture']:
        if f['slot']=='sewing': f['size']=[2,1]
        if f['slot']=='dining': f['pos']=[7,2]
        if f['slot']=='lamp': f['pos']=[1,4]
        if f['slot']=='sofa': f['size']=[2,1]
    for f in interiors['home2']['2f']['furniture']:
        if f['slot']=='plant': f['pos']=[4,1]
    write(DATA/'interiors.json',interiors)
    rebuild_circulation()


if __name__=='__main__': main()
