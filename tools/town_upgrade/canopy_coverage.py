"""Terrain-grounded woodland infill, measured as canopy envelopes, not counts.

Authored access routes, public clearings and roofs remain protected. Crown
envelopes are a geometric planning measure; alpha leaf coverage is reviewed in
actual images separately. This module never opens, saves or exports a scene.
"""
from collections import Counter
import json
import math
from pathlib import Path
import random


def inside_domain(x,y):
    return -560<x<25 and -285<y<455 and (x < -125 or y > 137)


def populate(api,cache,entries,radii,placements,ground,collection):
    bpy=api['bpy'];module=api['module'];root=Path(__file__).resolve().parents[2]
    understory=module('canopy_siting_rules',Path(__file__).with_name('understory.py'))
    baseline=root/'art/living_town';expansion=api['expansion_dir']
    docs={key:json.loads(path.read_text(encoding='utf-8')) for key,path in {
        'master':baseline/'masterplan.json','landscape':baseline/'landscape_plan.json',
        'reserve':baseline/'reserve_plan.json','expansion':expansion/'territory_plan.json'}.items()}
    siting=understory.Siting(docs['master'],docs['landscape'],docs['reserve'],docs['expansion'],api['buildings'])
    trees=understory.Spatial(10.);rejected=Counter();rng=random.Random(20261020_7631)
    for tree in placements:
        x,y,_=tree['position_m'];radius=tree['crown_radius_m'];trees.add(tree,[x-radius,y-radius,x+radius,y+radius])

    def roof_overlap(x,y,radius):
        for building in siting.parcels.near(x,y,radius+1):
            lx,ly=understory._local(building,x,y);w,d=building['footprint_m']
            dx=max(0,abs(lx)-w/2-.45);dy=max(0,abs(ly)-d/2-.45)
            if math.hypot(dx,dy)<radius:return True
        return False

    def covered(x,y):
        return any(math.hypot(x-tree['position_m'][0],y-tree['position_m'][1])<tree['crown_radius_m']*.93 for tree in trees.near(x,y))

    # Eight-metre stratified samples track change over the same protected
    # authored habitat, independently of the later randomized placement grid.
    samples=[]
    for iy in range(-280,456,8):
        for ix in range(-552,26,8):
            if not inside_domain(ix,iy) or siting.reason(ix,iy,.45,'woodland_root_drift'):continue
            z=ground(ix,iy,float('nan'))
            if math.isfinite(z):samples.append((ix,iy))
    before=sum(covered(x,y) for x,y in samples)
    added=[];max_new=int(api.get('canopy_infill_limit',6500))
    candidates=[]
    for iy in range(-280,456,5):
        for ix in range(-552,26,5):
            x,y=ix+rng.uniform(-1.9,1.9),iy+rng.uniform(-1.9,1.9)
            if inside_domain(x,y):candidates.append((x,y))
    rng.shuffle(candidates)
    for x,y in candidates:
        if len(added)>=max_new:break
        if covered(x,y):rejected['existing_canopy_coverage']+=1;continue
        reason=siting.reason(x,y,.55,'woodland_root_drift')
        if reason:rejected[reason.split(':')[0]]+=1;continue
        # Keep a few irregular glades between continuous woodland stands.
        openness=(math.sin(x*.037+y*.019)+math.sin(y*.051-x*.021))*.5
        if openness>.77:rejected['authored_infill_glade']+=1;continue
        if any(math.hypot(x-tree['position_m'][0],y-tree['position_m'][1])<3.2 for tree in trees.near(x,y,4)):
            rejected['minimum_trunk_spacing']+=1;continue
        z=ground(x,y,float('nan'))
        nearby=[ground(x+dx,y+dy,float('nan')) for dx,dy in ((.6,0),(-.6,0),(0,.6),(0,-.6))]
        if not math.isfinite(z) or not all(math.isfinite(v) for v in nearby) or max(nearby)-min(nearby)>.95:
            rejected['cliff_or_unsupported_root']+=1;continue
        asset=rng.choices(('tree_small_02','pine_sapling_medium','island_tree_02'),(.63,.29,.08))[0]
        variant=rng.randrange(3) if asset=='pine_sapling_medium' else 0
        near=any(math.hypot(x-b['center_m'][0],y-b['center_m'][1])<24 for b in api['buildings'])
        lod='near' if near else 'far';key=asset,variant,lod;entry=entries[key]
        scale=rng.uniform(1.16,1.72) if asset!='island_tree_02' else rng.uniform(1.4,1.9)
        horizontal=scale*rng.uniform(.90,1.10);radius=radii[key]*horizontal
        if roof_overlap(x,y,radius):rejected['actual_crown_to_roof_clearance']+=1;continue
        ident=f'Botanical_Infill_{len(added):05d}';yaw=rng.uniform(0,math.tau)
        for index,mesh in enumerate(cache[key]):
            ob=bpy.data.objects.new(ident+'_'+str(index),mesh);collection.objects.link(ob);ob.location=(x,y,z);ob.rotation_euler.z=yaw;ob.scale=(horizontal,horizontal,scale)
            ob['botanical_instance_id']=ident;ob['vegetation_role']='tree';ob['tree_species']='mixed_reserve_canopy';ob['source_asset']=asset;ob['source_license']='CC0-1.0';ob['lod']=lod;ob['stable_id']='botanical/'+ob.name
        tree={'id':ident,'position_m':[x,y,z],'species':'mixed_reserve_canopy','source_asset':asset,'lod':lod,'scale':[horizontal,horizontal,scale],
              'crown_radius_m':radius,'height_m':entry['height_m']*scale,'placement_program':'terrain_grounded_woodland_coverage_infill'}
        trees.add(tree,[x-radius,y-radius,x+radius,y+radius]);placements.append(tree);added.append(tree)
    after=sum(covered(x,y) for x,y in samples)
    return {'schema':'living_town.canopy_coverage.v1','status':'BUILT_REQUIRES_RENDERED_COVERAGE_REVIEW',
            'measurement':'Actual shared-mesh XY crown envelopes; alpha-tested leaf silhouette and apparent cover are separate visual checks.',
            'sample_cell_m':8,'eligible_sample_count':len(samples),'covered_samples_before':before,'covered_samples_after':after,
            'canopy_envelope_fraction_before':before/max(1,len(samples)),'canopy_envelope_fraction_after':after/max(1,len(samples)),
            'new_trees':len(added),'infill_limit':max_new,'rejected':dict(rejected),
            'policy':'Protect all authored routes, clearings, utilities, entrances and actual roof footprints; reject cliffs/unsupported roots; shared source meshes, mixed height and species programs, retained irregular glades.'}
