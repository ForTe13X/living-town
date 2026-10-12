"""Generate the user-authorized replacement offline urban masterplan.

The game map supplies program IDs only. Coordinates, parcel sizes and streets
are newly authored in metres. No game files or Blender scene are changed.
"""
from __future__ import annotations
import heapq
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1] if len(ROOT.parents)>1 else ROOT.parent
GRID = .5
CLEAR = .2


def polygon(b):
    x,y=b['center'];a=math.radians(b['yaw_degrees']);co,si=math.cos(a),math.sin(a)
    return [[x+u*co-v*si,y+u*si+v*co] for u,v in [(-b['width']/2,-b['depth']/2),(b['width']/2,-b['depth']/2),(b['width']/2,b['depth']/2),(-b['width']/2,b['depth']/2)]]


def local(p,b):
    x,y=p[0]-b['center'][0],p[1]-b['center'][1];a=math.radians(b['yaw_degrees'])
    return x*math.cos(a)+y*math.sin(a),-x*math.sin(a)+y*math.cos(a)


def point_blocked(p,b,margin):
    x,y=local(p,b)
    return abs(x)<b['width']/2+margin-1e-8 and abs(y)<b['depth']/2+margin-1e-8


def crosses(p,q,b,margin):
    p,q=local(p,b),local(q,b);lo,hi=0.,1.
    for axis,half in ((0,b['width']/2+margin),(1,b['depth']/2+margin)):
        d=q[axis]-p[axis]
        if abs(d)<1e-10:
            if abs(p[axis])>=half-1e-8:return False
        else:
            t0,t1=(-half-p[axis])/d,(half-p[axis])/d
            lo=max(lo,min(t0,t1));hi=min(hi,max(t0,t1))
            if hi-lo<1e-8:return False
    return hi-lo>1e-8


def overlaps(a,b):
    pa,pb=a['footprint_polygon'],b['footprint_polygon']
    for p in (pa,pb):
        for u,v in zip(p,p[1:]+p[:1]):
            axis=(-(v[1]-u[1]),v[0]-u[0]);aa=[x*axis[0]+y*axis[1] for x,y in pa];bb=[x*axis[0]+y*axis[1] for x,y in pb]
            if min(max(aa),max(bb))-max(min(aa),min(bb))<=1e-6:return False
    return True


def create_buildings(data):
    out=[];adjust=[]
    def add(ident,kind,x,y,w,d,f,yaw,typology,district,ref):
        b=dict(id=ident,kind=kind,center=[x,y],width=w,depth=d,floors=f,yaw_degrees=yaw,source_ref=ref,typology=typology,district=district)
        b['footprint_polygon']=polygon(b);a=math.radians(yaw);normal=[math.sin(a),-math.cos(a)]
        b['front_threshold']=[x+normal[0]*d/2,y+normal[1]*d/2];b['front_outward']=normal
        b['interior_clear_span']=[w-.6,d-.6]
        b['program_authority']='New offline architectural proposal; existing runtime Space geometry is not embedded.'
        out.append(b)
        return b
    main=[('cafe',11.5,0,10,9,2,-90),('shop',11.5,8,6,9,2,-90),('home',-49,17.5,6,7,2,0),('home2',-42.75,19,6.5,7,1,0),('library',-18,11,10,8,2,0),('wash',-1,28,10,8,1,0),('work',13,32,12,8,1,0)]
    for n,x,y,w,d,f,a in main:add('Main_'+n,n,x,y,w,d,f,a,'mixed_use' if n=='cafe' else 'civic' if n in ('library','wash') else 'workshop' if n=='work' else 'shop_house','D02' if n not in ('home','home2','work') else 'D01' if n.startswith('home') else 'D06','program_inventory.map.areas.'+n)
    specs={'chapel':(-23,29,8,14,2,0,'chapel','D01'),'mairie':(-3,12,10,8,3,0,'civic','D02'),'windmill':(-56,35,5,6,2,0,'windmill','D05'),'netshed':(50,44,6,4,1,0,'working_shed','D06'),'bakery':(-17.5,-2,8,9,2,90,'shop_house','D02'),'creperie':(11.5,-8,6,9,2,-90,'shop_house','D02'),'halles':(-3,-16,13,7,1,180,'market_hall','D02'),'hotel':(30,30,14,11,3,90,'mansard_hotel','D03'),'cannery':(22,47,12,10,1,0,'warehouse','D06')}
    pool=[]
    for lot in data['solid_lots']:
        k=lot['sprite']
        if k in specs:
            x,y,w,d,f,a,t,dist=specs[k];add(lot['id'],k,x,y,w,d,f,a,t,dist,'program_inventory.map.solid_lots.'+lot['id'])
        else:pool.append(lot)
    add('Port_Warehouse_Exterior','netshed',39,47,10,10,1,0,'warehouse','D06','program_inventory.spaces.port_warehouse / proposed_exterior')
    preference={'belleepoque':0,'cottage':1,'whitehouse':2,'longere':3,'terrace':4}
    coastal=sorted(pool,key=lambda p:(preference.get(p['sprite'],9),p['id']))[:11]
    remaining=[p for p in pool if p not in coastal]
    angle=math.degrees(math.atan2(2.3,6));joined=math.hypot(6,2.3)
    groups=[('A',[(-46.45,-13.06),(-40.45,-10.76),(-34.45,-8.46),(-28.45,-6.16)],joined,7,angle,'shop_house'),('B',[(-42.5,-25.5),(-36.5,-23.2),(-30.5,-20.9),(-24.5,-18.6),(-18.5,-16.3)],joined,7.5,angle+180,'shop_house'),('C',[(-36.25,19),(-29.75,17.8)],6.5,7,0,'terraced_home'),('D',[(-49,6),(-42.3,6.5),(-35.6,7),(-28.9,7.5)],6.7,7,180,'terraced_home'),('G',[(-7,-39),(0,-39),(7,-39)],7,7,180,'terraced_home'),('H',[(-8,-26),(0,-26),(8,-26)],8,8,0,'shop_house')]
    idx=0
    for group,centers,w,d,a,t in groups:
        for j,(x,y) in enumerate(centers):
            lot=remaining[idx];idx+=1;b=add(lot['id'],lot['sprite'],x,y,w,d,1 if group in ('C','G') else (3 if group=='A' and j==1 else 2),a,t,'D01','program_inventory.map.solid_lots.'+lot['id']);b['row_group']=group
    for j,y in enumerate([-27.4,-20.7,-14,-7.3,2.2,8.9,15.6]):
        lot=coastal[j];b=add(lot['id'],lot['sprite'],33,y,6.7,8,2,90,'cross_gable_villa' if j<4 else 'coastal_shop_house','D03','program_inventory.map.solid_lots.'+lot['id']);b['row_group']='E_south' if j<4 else 'E_north'
    for j,y in enumerate([-25,-18.5,-12,14.5]):
        lot=coastal[7+j];b=add(lot['id'],lot['sprite'],22,y,6.5 if j<3 else 6,8,2,90,'coastal_shop_house','D03','program_inventory.map.solid_lots.'+lot['id']);b['row_group']='F_south' if j<3 else 'F_north'
    adjust.extend([{'scope':'library','change':'Move X -1m to clear civic plaza.'},{'scope':'home2 and row C','change':'Shift X at most0.45m and match6.5m widths for party-wall contact.'},{'scope':'rows A/B/D/G/H','change':'Fit frontage widths to actual row pitch; A/B use exact20.9735degree orientation.'},{'scope':'row E','change':'Widen to6.7m; lowerfour moveY-1.4m, upperthreeY+1.4m, creating2.8m sea-opening aperture.'},{'scope':'cannery/warehouse/netshed','change':'Move Y +1m so4m service street fits behind hotel.'}])
    return out,adjust


def plan_roads(buildings,seeds=None,preserve_waypoints=False,round_corners=False):
    if seeds is None:seeds=[('main_west',[(-58,-25),(-48,-21),(-30,-14),(-16,-9),(-11,-9)],4.2),('south_east',[(-13,-9),(-15,-12),(-15,-32.5),(-10,-33),(16,-33),(40,-33),(40,-11)],4),('civicnorth',[(-25,18),(-15,18),(1,20),(19,21),(39,21)],3.6),('upperwest',[(-56,10),(-45,12),(-35,12),(-25,12),(-25,18)],3),('westconnector',[(-51,-15),(-54,-4),(-55,8),(-55,15)],2.5),('seaside',[(40,-42),(40,-25),(40,-8),(40,10),(40,24),(43,35)],3.2),('southloop',[(-15,-17),(-15,-26),(-15,-33),(10,-33),(15,-29),(15,-17)],3.2),('backlane',[(27.5,-30),(27.5,-12),(27.5,18.5),(27.5,21),(25,21)],2),('northwork',[(19,21),(21.5,29),(21.5,39.5),(47,39.5)],4),('northservice',[(31,39.5),(31,54)],4),('plaza_north',[(5,0),(5,8),(5,20)],2.5),('library_church',[(-25,12),(-25,20)],2),('sea_opening',[(27.5,-2.5),(40,-2.5)],2),('cafe_rear_lane',[(15,-17),(17,-16),(17,-5.5),(17,10.5),(25,10.5)],1.4)]
    caches={};roads=[];network=set();adjust=[]
    def key(p):return (round(p[0]/GRID),round(p[1]/GRID))
    def pt(k):return (k[0]*GRID,k[1]*GRID)
    def safe(p,q,w,owner=None):return not any(b['id']!=owner and crosses(p,q,b,w/2+CLEAR) for b in buildings)
    def blocked(w):
        if w not in caches:
            out=set();m=w/2+CLEAR
            for b in buildings:
                p=b['footprint_polygon'];loX=math.floor((min(v[0] for v in p)-m*1.5)/GRID);hiX=math.ceil((max(v[0] for v in p)+m*1.5)/GRID);loY=math.floor((min(v[1] for v in p)-m*1.5)/GRID);hiY=math.ceil((max(v[1] for v in p)+m*1.5)/GRID)
                for x in range(loX,hiX+1):
                    for y in range(loY,hiY+1):
                        if point_blocked(pt((x,y)),b,m):out.add((x,y))
            caches[w]=out
        return caches[w]
    def snap(p,w):
        k=key(p);bad=blocked(w)
        for radius in range(15):
            opts=[(math.dist(pt((k[0]+dx,k[1]+dy)),p),k[0]+dx,k[1]+dy) for dx in range(-radius,radius+1) for dy in range(-radius,radius+1) if max(abs(dx),abs(dy))==radius and (k[0]+dx,k[1]+dy) not in bad]
            if opts:
                _,x,y=min(opts);return(x,y)
        raise ValueError('No free street waypoint near '+str(p))
    def path(a,z,w):
        bad=blocked(w);queue=[(0,0,a)];cost={a:0};parent={};goal=z
        while queue:
            _,g,c=heapq.heappop(queue)
            if g>cost[c]+1e-8:continue
            if c==goal:
                p=[c]
                while c in parent:c=parent[c];p.append(c)
                return list(reversed(p))
            for dx,dy in ((1,0),(0,1),(-1,0),(0,-1)):
                n=(c[0]+dx,c[1]+dy)
                if n in bad or not(-126<=n[0]<=136 and-94<=n[1]<=112) or not safe(pt(c),pt(n),w):continue
                ng=g+(.60 if n in network else 1)
                if ng+1e-8<cost.get(n,math.inf):cost[n]=ng;parent[n]=c;heapq.heappush(queue,(ng+.60*(abs(n[0]-goal[0])+abs(n[1]-goal[1])),ng,n))
        raise ValueError(f'No route {a}->{z} width{w}')
    def simplify(nodes,w):
        # Remove stair-stepping only when the actual diagonal segment clears
        # every rotated footprint at the complete road-width margin.
        out=[nodes[0]];i=0
        while i<len(nodes)-1:
            chosen=i+1
            for j in range(len(nodes)-1,i,-1):
                if safe(pt(nodes[i]),pt(nodes[j]),w):chosen=j;break
            out.append(nodes[chosen]);i=chosen
        return [list(pt(k)) for k in out]
    def soften(points,w):
        if len(points)<3:return points
        out=[points[0]]
        for a,b,c in zip(points,points[1:],points[2:]):
            la,lc=math.dist(a,b),math.dist(b,c)
            if min(la,lc)<.1:out.append(b);continue
            ua=[(a[k]-b[k])/la for k in (0,1)];uc=[(c[k]-b[k])/lc for k in (0,1)]
            dot=sum(ua[k]*uc[k] for k in (0,1))
            if dot<-.995 or dot>.95:out.append(b);continue
            radius=min(1.35,la*.22,lc*.22)
            p=[b[k]+ua[k]*radius for k in (0,1)];q=[b[k]+uc[k]*radius for k in (0,1)]
            curve=[[p[k]*(1-t)**2+2*b[k]*t*(1-t)+q[k]*t*t for k in (0,1)] for t in (0,.2,.4,.6,.8,1)]
            if all(safe(u,v,w) for u,v in zip([out[-1]]+curve,curve)):
                out.extend(curve)
            else:out.append(b)
        out.append(points[-1]);return out
    def add_route(ident,nodes,w,prescribed_points=None,**extra):
        if len(nodes)>1:
            points=prescribed_points if prescribed_points is not None else simplify(nodes,w)
            roads.append(dict(id=ident,points=points,width=w,**extra))
            # Reuse/connect the street that will actually be rendered, rather
            # than stale A* stair-step nodes removed by simplification.
            radius=w/2-.1
            for p,q in zip(points,points[1:]):
                vx,vy=q[0]-p[0],q[1]-p[1];length2=vx*vx+vy*vy
                for gx in range(math.floor((min(p[0],q[0])-radius)/GRID),math.ceil((max(p[0],q[0])+radius)/GRID)+1):
                    for gy in range(math.floor((min(p[1],q[1])-radius)/GRID),math.ceil((max(p[1],q[1])+radius)/GRID)+1):
                        x,y=pt((gx,gy));t=max(0,min(1,((x-p[0])*vx+(y-p[1])*vy)/length2)) if length2 else 0
                        if math.hypot(x-p[0]-t*vx,y-p[1]-t*vy)<=radius:network.add((gx,gy))
    for ident,points,w in seeds:
        nodes=[];authored=[]
        for a,z in zip(points,points[1:]):
            ka,kz=snap(a,w),snap(z,w)
            if math.dist(pt(ka),a)>.76 or math.dist(pt(kz),z)>.76:adjust.append({'street':ident,'seed_segment':[a,z],'snapped_endpoints':[pt(ka),pt(kz)]})
            seg=path(ka,kz,w);nodes.extend(seg if not nodes else seg[1:])
            short=simplify(seg,w);authored.extend(short if not authored else short[1:])
        if preserve_waypoints:
            if round_corners:authored=soften(authored,w)
            add_route(ident,nodes,w,prescribed_points=authored,kind='public_street',authored_waypoints=points,
                character='Clearance-tested authored bends and rounded corners; no random street jitter.')
        else:add_route(ident,nodes,w,kind='public_street')
    # Connect public street components on the same safe pedestrian graph.
    hub=snap((-3,0),2)
    for i in range(30):
        reachable=set();todo=[hub]
        while todo:
            k=todo.pop()
            if k in reachable or k not in network:continue
            reachable.add(k);todo.extend((k[0]+dx,k[1]+dy) for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)))
        rest=network-reachable
        if not rest:break
        target=min((k for k in rest if k not in blocked(2)),key=lambda k:(math.dist(pt(k),pt(hub)),k));add_route('network_link_'+str(i),path(hub,target,2),2,kind='pedestrian_link')
    for b in buildings:
        p=b['front_threshold'];v=b['front_outward'];start=snap((p[0]+v[0]*1.3,p[1]+v[1]*1.3),1.4)
        choices=sorted((k for k in network if k not in blocked(1.4)),key=lambda k:(math.dist(pt(k),pt(start)),k))[:40]
        chosen=None
        for target in choices:
            try:chosen=path(start,target,1.4);break
            except ValueError:continue
        if chosen is None:raise ValueError('Entrance unreachable: '+b['id'])
        add_route('approach_'+b['id'],chosen,1.4,kind='entrance_approach',building_id=b['id'])
        if not safe(pt(start),p,1.4,b['id']):raise ValueError('Threshold crosses neighbor: '+b['id'])
        roads.append(dict(id='threshold_'+b['id'],points=[list(pt(start)),p],width=1.4,kind='threshold',threshold_owner=b['id']))
        b['entrance_approach']=list(pt(start))
    collisions=[]
    for r in roads:
        for p,q in zip(r['points'],r['points'][1:]):
            for b in buildings:
                if b['id']!=r.get('threshold_owner') and crosses(p,q,b,r['width']/2+CLEAR):collisions.append({'street':r['id'],'building':b['id'],'segment':[p,q]})
    return roads,collisions,adjust


def make_svg(plan,target=None):
    def pos(p):return [100+(p[0]+65)*7,850-(p[1]+48)*7]
    def pts(points):return ' '.join(f'{pos(p)[0]:.2f},{pos(p)[1]:.2f}' for p in points)
    out=['<svg xmlns="http://www.w3.org/2000/svg" width="1300" height="1000" viewBox="0 0 1300 1000"><rect width="1300" height="1000" fill="#f2efe4"/><g font-family="Segoe UI,Arial,sans-serif"><text x="60" y="48" font-size="26" fill="#303e42" font-weight="700">LIVING TOWN / REVISED INHABITED MASTERPLAN</text><text x="60" y="78" font-size="14" fill="#64716c">New authored layout in metres · 49 buildings · adjoining rows, civic heart, garden courts and sea-opening lane</text>']
    coast=[]
    for i in range(107):
        y=-48+i;water=49+2*math.sin(y*.055)-7*math.exp(-((y-43)/10)**2);coast.append([water,y])
    out.append(f'<polygon points="{pts(coast+[[72,58],[72,-48]])}" fill="#789ca7"/>')
    beach=[]
    for x,y in coast:beach.append([x-(7 if y<24 else 7-(min(11,y-24)/11)*6),y])
    out.append(f'<polygon points="{pts(beach+list(reversed(coast)))}" fill="#d7c6a2"/>')
    out.append(f'<polygon points="{pts([[31,37],[66,37],[66,55],[31,55]])}" fill="#b8b8a8"/>')
    out.append(f'<polygon points="{pts(plan["plaza"]["polygon"])}" fill="#d5c7ad"/>')
    out.append(f'<polygon points="{pts([[17,-7],[26.25,-7],[26.25,11],[17,11]])}" fill="#a6b38f"/>')
    for r in plan['streets']:out.append(f'<polyline points="{pts(r["points"])}" fill="none" stroke="#c3bbb0" stroke-width="{r["width"]*7:.2f}" stroke-linejoin="round" stroke-linecap="round"/>')
    colors={'D01':'#768b82','D02':'#dcc7a8','D03':'#9baeb2','D05':'#a9a591','D06':'#8a9695'}
    for b in plan['buildings']:
        out.append(f'<polygon points="{pts(b["footprint_polygon"])}" fill="{colors.get(b["district"],"#9ca89c")}" stroke="#3f5358" stroke-width="1.2"/>');x,y=pos(b['front_threshold']);out.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="2.8" fill="#aa5c41"/>')
        if b['id'].startswith('Main_') or b['kind'] in ('hotel','chapel','mairie','halles','cannery') or b['id']=='Port_Warehouse_Exterior':
            x,y=pos(b['center']);out.append(f'<text x="{x:.2f}" y="{y+3:.2f}" text-anchor="middle" font-size="10" fill="#283b40">{b["kind"].upper()}</text>')
    out.extend(['<g fill="#35474b"><text x="1050" y="155" font-size="18" font-weight="700">THE CIVIL HEART</text><text x="1050" y="185" font-size="13">Cafe / mairie / halles</text><text x="1050" y="206" font-size="13">20 × 16m civic plaza</text><text x="1050" y="245" font-size="18" font-weight="700">CONTINUOUS STREETS</text><text x="1050" y="275" font-size="13">Shared party-wall rows</text><text x="1050" y="296" font-size="13">True sea-opening aperture</text><text x="1050" y="317" font-size="13">Rear garden court</text><text x="1050" y="356" font-size="18" font-weight="700">CLEAR DISTRICTS</text><text x="1050" y="386" font-size="13">Residential lanes inland</text><text x="1050" y="407" font-size="13">Coastal facades east</text><text x="1050" y="428" font-size="13">Working harbor north-east</text><text x="1050" y="467" font-size="18" font-weight="700">VERIFIED GEOMETRY</text><text x="1050" y="497" font-size="13">49 non-overlapping parcels</text><text x="1050" y="518" font-size="13">49 connected approaches</text><text x="1050" y="539" font-size="13">No street crosses a parcel</text><text x="1050" y="578" font-size="13">Red dots: facade thresholds</text><text x="1050" y="599" font-size="13">Orthogonal planning view</text></g><text x="60" y="946" font-size="14" fill="#42534f">The prior game map is retained unchanged as a legacy reference. This masterplan supersedes its detached parcel layout for the native Blender model.</text><text x="60" y="972" font-size="12" fill="#68776e">No runtime projection, save or navigation migration is implied. Rooms and exterior parcels are new architectural proposals, designed together.</text></g></svg>'])
    (target or ROOT/'concept/03_revised_masterplan.svg').write_text('\n'.join(out),encoding='utf-8')


def generate():
    data=json.loads((REPO/'game/data/map.json').read_text(encoding='utf-8'));buildings,adjustments=create_buildings(data)
    overlaps_found=[(a['id'],b['id']) for i,a in enumerate(buildings) for b in buildings[i+1:] if overlaps(a,b)]
    if overlaps_found:raise ValueError('Parcel overlaps: '+str(overlaps_found))
    streets,collisions,street_adjustments=plan_roads(buildings)
    if collisions:raise ValueError('Street collisions: '+str(collisions))
    plan={'schema':'living_town.revised_masterplan.v1','title':'Inhabited Breton Town — Revised Native Masterplan','layout_authority':'Current user-authorized offline redesign; original source coordinates are superseded.','coordinate_system':'Metres, X east, Y north, ground Z supplied by terrain; yaw rotates local frontage south about Z.','program_source_head':'f204276','buildings':buildings,'streets':streets,'plaza':{'polygon':[[-13,-8],[7,-8],[7,8],[-13,8]],'purpose':'Civic/social heart; actual cafe, mairie and bakery thresholds face the public space.'},'courtyards':[{'id':'cafe_rear_garden','rect':[17,-7,9.25,18],'classification':'Rear garden/court, not an invented through-building street.'}],'districts':[{'id':'D01','role':'Inland adjoining homes and quiet lanes'},{'id':'D02','role':'Central mixed-use frontage and civic plaza'},{'id':'D03','role':'Coastal row and promenade'},{'id':'D04','role':'Open sand and Atlantic shore'},{'id':'D05','role':'Inland windmill/headland edge'},{'id':'D06','role':'Separated north-east working harbor'}],'coast':{'water_x':'49 + 2*sin(y*.055) - 7*exp(-((y-43)/10)^2)','beach_width':'7m belowY24, taper to1m byY35','harbor_quay_rect':[31,37,35,18],'terrain_height':'.35 + max(0,-x-10)*.055 + max(0,y-12)*.035'},'adjustments':adjustments,'street_waypoint_adjustments':street_adjustments,'validation':{'building_count':len(buildings),'program_inventory_main':7,'program_inventory_lots':41,'extra_warehouse':1,'parcel_overlap_count':len(overlaps_found),'street_collision_count':len(collisions),'street_collision_clearance_m':CLEAR,'thresholds':len(buildings),'all_entrances_connected':True,'street_count':len(streets),'smoothing':'Clearance-tested straight/diagonal segment simplification only; no blind spline. Explicit facade connectors.','scope':'Architectural offline geometry; no runtime integration or game playtest claimed.'}}
    (ROOT/'masterplan.json').write_text(json.dumps(plan,indent=2),encoding='utf-8');make_svg(plan);print(json.dumps(plan['validation'],indent=2));return plan


if __name__=='__main__':generate()
