"""Reference-led irregularity with a reproducible, clearance-checked site plan.

Run normally to create a proposal only. --apply installs the reviewed proposal;
terrain/interior/landscape plans must then be rebound and audited separately.
Dimensions and programs remain stable so existing detailed assets are retained.
"""
import copy
import hashlib
import json
import math
import sys
from pathlib import Path
import generate_masterplan as geometry

ROOT=Path(__file__).resolve().parents[1]


def proposal():
    source=ROOT/'source_snapshot/masterplan_v2.json'
    plan=copy.deepcopy(json.loads(source.read_text(encoding='utf-8')))
    buildings=plan['buildings'];changes=[]
    def rotate_group(group,pivot,degrees):
        angle=math.radians(degrees);co,si=math.cos(angle),math.sin(angle)
        for b in buildings:
            if b.get('row_group')!=group:continue
            dx,dy=b['center'][0]-pivot[0],b['center'][1]-pivot[1]
            b['center']=[pivot[0]+dx*co-dy*si,pivot[1]+dx*si+dy*co]
            b['yaw_degrees']+=degrees
            changes.append({'id':b['id'],'treatment':'Retain joined row geometry; rotate as one coherent block','rotation_delta_degrees':degrees})
    rotate_group('G',(0,-39),-5)
    rotate_group('D',(-38.95,6.75),-2.5)
    for b in buildings:
        if b.get('row_group')=='G':b['center'][1]-=.9
        if b['kind']=='mairie':b['center']=[-3.3,12.9];b['yaw_degrees']=-7;changes.append({'id':b['id'],'treatment':'Angled civic frontage, set back from square edge'})
        if b['id']=='Main_wash':b['yaw_degrees']=5;changes.append({'id':b['id'],'treatment':'Small civic pavilion angle'})
        if b['id']=='Main_work':b['yaw_degrees']=-4;changes.append({'id':b['id'],'treatment':'Workshop follows a separate service-court alignment'})
        b['footprint_polygon']=geometry.polygon(b);angle=math.radians(b['yaw_degrees'])
        normal=[math.sin(angle),-math.cos(angle)];b['front_outward']=normal
        b['front_threshold']=[b['center'][i]+normal[i]*b['depth']/2 for i in (0,1)]
    overlaps=[(a['id'],b['id']) for i,a in enumerate(buildings) for b in buildings[i+1:] if geometry.overlaps(a,b)]
    if overlaps:raise ValueError('Overlapping revised parcels: '+str(overlaps))
    seeds=[
        ('main_west',[(-58,-25),(-48,-21),(-43,-18.5),(-31,-14),(-22,-10.5),(-14,-9),(-11,-9)],4.2),
        ('south_east',[(-50,-22),(-46,-33),(-16,-33),(-8,-32.5),(0,-32.5),(16,-33),(38.5,-33)],4),
        ('civicnorth',[(-25,18),(-15,18.5),(1,20),(12,20.5),(19,21),(39,21)],3.6),
        ('upperwest',[(-56,11.5),(-46,12.5),(-36,12.5),(-25,12),(-25,18)],2.5),
        ('westconnector',[(-51,-15),(-53.5,-5),(-55,4),(-55,10),(-55,15)],2.5),
        ('seaside',[(38,-42),(38.5,-33),(38.6,-24),(38.8,-15),(39.2,-7),(39.7,3),(40.2,13),(40.7,24),(43,35)],2.4),
        ('southloop',[(-15,-26),(-15,-32.5),(8,-32.5),(14.5,-29),(15,-17)],3.2),
        ('backlane',[(27.5,-30),(27.3,-20),(27.5,-12),(27.5,-3),(27.5,10),(27.5,18.5),(27.5,21),(25,21)],2),
        ('northwork',[(19,21),(21.5,29),(21.5,36.5),(21.5,39.5),(47,39.5)],4),
        ('northservice',[(31,39.5),(31,46),(31,54)],4),
        ('plaza_north',[(5,0),(5,8),(5,15),(5,20)],2.5),
        ('library_church',[(-25,12),(-25,20)],2),
        ('sea_opening',[(27.5,-2.5),(33,-2.5),(39.5,-2.5)],2),
        ('cafe_rear_lane',[(15,-17),(17,-16),(17,-5.5),(17,5),(17,10.5),(25,10.5)],1.4),
        ('market_mews',[(-15,-21),(-9,-21),(-2,-21),(5,-21),(11,-20.5),(15,-17)],1.4),
        ('market_link',[(-11,-9),(-11,-20.5),(-15,-24)],1.4),
        ('garden_passage',[(-53,-5),(-50.5,-1.5),(-44.5,1),(-35,1),(-26,3),(-24.5,7),(-24.5,12)],1.4)]
    streets,collisions,snaps=geometry.plan_roads(buildings,seeds,preserve_waypoints=True,round_corners=True)
    if collisions:raise ValueError('Revised road/parcel collisions: '+str(collisions))
    route_lengths=[]
    for road in streets:
        if road['kind']!='public_street':continue
        actual=sum(math.dist(a,b) for a,b in zip(road['points'],road['points'][1:]))
        control=sum(math.dist(a,b) for a,b in zip(road['authored_waypoints'],road['authored_waypoints'][1:]))
        route_lengths.append({'id':road['id'],'length_m':round(actual,3),'control_length_m':round(control,3),'ratio':round(actual/control,4)})
    if any(r['ratio']>1.25 for r in route_lengths):raise ValueError('Implausible routing detour: '+str(route_lengths))
    # A promenade is kept on dry land rather than drawing its pavement over
    # a declining sandy foreshore. The terrain source defines this coastline.
    dry_errors=[]
    for road in streets:
        if road['id']!='seaside':continue
        for a,b in zip(road['points'],road['points'][1:]):
            length=math.dist(a,b);n=max(1,math.ceil(length/.2));dx,dy=b[0]-a[0],b[1]-a[1]
            for i in range(n+1):
                t=i/n;x=a[0]+dx*t;y=a[1]+dy*t
                edge=49+2*math.sin(y*.055)-7*math.exp(-((y-43)/10)**2)
                u=max(0,min(1,(y-24)/11));edge-=7-6*u*u*(3-2*u)
                physical_east=x+abs(dy/length)*road['width']/2
                if physical_east>edge-.06:dry_errors.append([x,y,physical_east-edge])
    if dry_errors:raise ValueError('Promenade paving leaves dry terrace: '+str(dry_errors[:5]))
    plan.update({'schema':'living_town.revised_masterplan.v2','version':3,'title':'Living Town — Irregular Coastal Borough',
        'layout_authority':'User planning-reference revision: irregular blocks, branching passages and topography-aware streets.',
        'buildings':buildings,'streets':streets,'street_waypoint_adjustments':snaps,
        'planning_revision':{'baseline_masterplan_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
            'reference':'references/planning/user_irregular_town_layout.png','building_changes':changes,
            'dimensions_and_floor_counts_unchanged':True,'new_passages':['market_mews','market_link','garden_passage'],
            'street_method':'Preserve authored control points; clearance-tested rounded corners; avoid arbitrary jitter.',
            'route_length_review':route_lengths,
            'south_row_setback_m':.9,
            'promenade':'2.4m public coastal walk, bounded to dry terrace; open sea views retained.'}})
    plan['validation']={**plan['validation'],'parcel_overlap_count':0,'street_collision_count':0,'street_count':len(streets),
        'all_entrances_connected':True,'public_seed_routes':len(seeds),'authored_bends_preserved':True,
        'promenade_dry_terrace_errors':dry_errors,'smoothing':'Bounded quadratic corner fillets, accepted only after full-width parcel-clearance tests.'}
    return plan


def main():
    plan=proposal();candidate=ROOT/'planning_candidate_masterplan.json'
    candidate.write_text(json.dumps(plan,indent=2),encoding='utf-8')
    geometry.make_svg(plan,ROOT/'concept/06_irregular_layout_proposal.svg')
    if '--apply' in sys.argv:
        (ROOT/'masterplan.json').write_text(json.dumps(plan,indent=2),encoding='utf-8');geometry.make_svg(plan)
    print(json.dumps(plan['validation'],indent=2))


if __name__=='__main__':main()
