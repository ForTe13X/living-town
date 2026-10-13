"""Measured, deterministic interior kit for the authored Living Town.

Pure planning works without Blender. build_interior receives the root builder's
geometry API; it never writes a native scene file or changes the masterplan.
All dimensions are local metres, frontage south, finished floors .38+2.85*n.
"""
from __future__ import annotations
import hashlib
import json
import math
import random
from collections import deque
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
FLOOR_HEIGHT=2.85
WALL=.12
DOOR=.92
HALL=1.10
HOUSE_KINDS={'home','home2','cottage','longere','townhouse','belleepoque','terrace','halftimber','whitehouse','ochre'}


def intersects(a,b,margin=0):
    return min(a[2],b[2])-max(a[0],b[0])>margin and min(a[3],b[3])-max(a[1],b[1])>margin


def stair_core(w,d):
    xmax=w/2-.30;ymax=d/2-.30
    x=min(w*.40,xmax-.62)
    start=-d*.22
    tread=min(.24,(ymax-.95-start)/13.5)
    y0=start-.20;y1=min(start+13*tread+.30,ymax-.95)
    return {'bounds':[x-.62,y0,x+.62,y1],'center_x':x,'first_tread_y':start,
        'tread_m':tread,'risers':14,'riser_m':FLOOR_HEIGHT/14,'flight_width_m':1.,
        'landing_clear_m':.95,'note':'Cafe keeps the audited legacy shaft; smaller cores are clamped within the clear shell.'}


def plan_for_building(ident,w,d,floors,kind,doorx=0):
    xmin,ymin,xmax,ymax=-w/2+.30,-d/2+.30,w/2-.30,d/2-.30
    core=stair_core(w,d) if floors>1 else None
    levels=[]
    def floor(level,template):
        f={'level':level,'finished_floor_local_z_m':.38+level*FLOOR_HEIGHT,'template':template,
           'rooms':[],'partitions':[],'access_keepouts':[],'slab_voids':[]}
        levels.append(f);return f
    def room(f,name,purpose,bounds,edge=None,finish='Oak'):
        r={'id':f"{ident}_L{f['level']:02d}_{name}",'name':name,'purpose':purpose,
            'bounds_m':[round(v,6) for v in bounds],'access_edge':edge,'finish':finish,
            'assets':[],'door_gaps':[],'circulation_keepouts':[]}
        if edge:
            a,b,c,e=bounds
            if edge=='E':r['circulation_keepouts'].append([c-.96,b,c,e])
            if edge=='N':r['circulation_keepouts'].append([a,e-.96,c,e])
            if edge=='S':r['circulation_keepouts'].append([a,b,c,b+.96])
        f['rooms'].append(r);return r
    def wall(f,axis,coordinate,lo,hi,doors=(),hatches=()):
        openings=[{'kind':'door','center_m':c,'width_m':width,'bottom_m':0.,'height_m':2.08} for c,width in doors]
        openings.extend({'kind':'service_hatch','center_m':c,'width_m':width,'bottom_m':1.10,'height_m':1.12} for c,width in hatches)
        openings=[o for o in openings if lo+.03<o['center_m']-o['width_m']/2 and o['center_m']+o['width_m']/2<hi-.03]
        f['partitions'].append({'axis':axis,'coordinate_m':coordinate,'span_m':[lo,hi],
            'thickness_m':WALL,'height_m':2.70 if f['level']<floors-1 else 2.43,'openings':openings})
    def core_rooms(f):
        a,b,c,e=core['bounds'];left=a-HALL
        room(f,'Hall','clear circulation and stair access',[left,ymin,a,ymax],None,'Tile')
        room(f,'Stairwell','protected vertical circulation',[a,b,c,e],None,'Oak')
        room(f,'Lower_Landing','bottom stair landing',[a,ymin,c,b],None,'Tile')
        room(f,'Upper_Landing','top stair landing',[a,e,c,ymax],None,'Oak')
        wall(f,'x',a,b,e)
        if f['level']>0:f['slab_voids']=[core['bounds']]
        return left
    def two_rooms(f,front,rear,front_finish='Oak',rear_finish='Oak'):
        left=core_rooms(f);split=.1
        room(f,'Front_Room',front,[xmin,ymin,left,split],'E',front_finish)
        room(f,'Rear_Room',rear,[xmin,split,left,ymax],'E',rear_finish)
        # The compact mill's hall divider lies close to its centered front
        # door. Leave an entrance return before the wall, then turn into hall.
        divider_start=ymin+1.05 if kind=='windmill' and f['level']==0 else ymin
        wall(f,'x',left,divider_start,ymax,doors=[((divider_start+split)/2,DOOR),((split+ymax)/2,DOOR)])
        wall(f,'y',split,xmin,left)
        # Entry from the unchanged central facade door crosses a clear front
        # zone, then turns into the hall or the stair's lower landing.
        f['access_keepouts'].append([min(doorx-.58,left),ymin,max(doorx+.58,core['bounds'][2]),ymin+1.05])
    def grid(f,purposes,finish='Oak'):
        left=core_rooms(f) if core else xmax
        hx=(xmin+left)/2;half=.62 if kind in ('work','cannery','netshed') else .55
        entry_spine=f['level']==0 and core is None
        entry_half=.60
        spans=[(xmin,ymin,-entry_half if entry_spine else hx,-half),
               (entry_half if entry_spine else hx,ymin,left,-half),
               (xmin,half,hx,ymax),(hx,half,left,ymax)]
        for i,(purpose,bounds) in enumerate(zip(purposes,spans)):
            room(f,('Front_Left','Front_Right','Rear_Left','Rear_Right')[i],purpose,bounds,'N' if i<2 else 'S',finish)
        room(f,'Cross_Hall','clear shared room circulation',[xmin,-half,left,half],None,'Tile')
        if entry_spine:
            room(f,'Entry_Spine','clear entrance circulation',[-entry_half,ymin,entry_half,-half],None,'Tile')
            entry_y=(ymin-half)/2
            for x in (-entry_half,entry_half):wall(f,'x',x,ymin,-half,doors=[(entry_y,DOOR)])
            # The central opening belongs to a continuous, furniture-free
            # entrance spine, rather than a wall on the facade door axis.
            wall(f,'y',-half,xmin,left,doors=[((xmin-entry_half)/2,DOOR),(0,1.10),((entry_half+left)/2,DOOR)])
            for r in f['rooms'][:2]:
                a,b,c,e=r['bounds_m']
                r['circulation_keepouts'].append([c-.96,entry_y-.55,c,entry_y+.55] if r['name']=='Front_Left'
                    else[a,entry_y-.55,a+.96,entry_y+.55])
        else:
            wall(f,'y',-half,xmin,left,doors=[((xmin+hx)/2,DOOR),((hx+left)/2,DOOR)])
            wall(f,'x',hx,ymin,-half)
        wall(f,'y',half,xmin,left,doors=[((xmin+hx)/2,DOOR),((hx+left)/2,DOOR)])
        wall(f,'x',hx,half,ymax)
        if core:
            # Rooms stop at the side hall, not at the stair shaft. Close that
            # boundary while keeping the shared cross-hall connection open.
            # Access to ordinary grid rooms is through their cross-hall doors.
            wall(f,'x',left,ymin,-half)
            wall(f,'x',left,half,ymax)
        if f['level']==0:f['access_keepouts'].append([doorx-.58,ymin,doorx+.58,.55])
    if kind in HOUSE_KINDS:
        if floors==1:
            f=floor(0,'single_storey_home');split=.15
            room(f,'Living_Kitchen','living kitchen and dining',[xmin,ymin,xmax,split],None,'Oak')
            room(f,'Bedroom','quiet bedroom',[xmin,split,-.55,ymax],'E','Oak')
            room(f,'Bathroom','bathroom laundry',[.55,split,xmax,ymax],'W','Tile')
            room(f,'Rear_Hall','private-room access',[-.55,split,.55,ymax],None,'Tile')
            wall(f,'y',split,xmin,xmax,doors=[(0,DOOR)])
            wall(f,'x',-.55,split,ymax,doors=[((split+ymax)/2,DOOR)])
            wall(f,'x',.55,split,ymax,doors=[((split+ymax)/2,DOOR)])
            f['access_keepouts']=[[doorx-.58,ymin,doorx+.58,split+.2]]
        else:
            for n in range(floors):
                f=floor(n,'compact_house_with_straight_stair')
                purposes=('living room','kitchen dining') if n==0 else (('bedroom','bathroom dressing') if n==1 else ('artist study guest room','linen storage and sewing'))
                two_rooms(f,*purposes,rear_finish='Tile' if n==1 else 'Oak')
    elif kind in ('cafe','shop','bakery','creperie'):
        f=floor(0,'street_business_with_separate_service');left=core_rooms(f) if core else xmax;split=.55
        front={'cafe':'cafe dining','shop':'grocery sales','bakery':'bakery retail','creperie':'creperie dining'}[kind]
        rear={'cafe':'coffee preparation','shop':'grocery stock room','bakery':'bakery preparation','creperie':'crepe kitchen'}[kind]
        room(f,'Public_Room',front,[xmin,ymin,left,split],'E','Tile')
        room(f,'Service_Room',rear,[xmin,split,left,ymax],'E','Tile')
        wall(f,'x',left,ymin,ymax,doors=[((ymin+split)/2,1.0),((split+ymax)/2,.95)])
        hatch=(min(3.2,left-xmin-1.55))
        wall(f,'y',split,xmin,left,doors=[(left-.60,.95)],hatches=[] if kind=='shop' else [((xmin+left-1.2)/2,hatch)])
        f['access_keepouts']=[[doorx-.60,ymin,doorx+.60,split-.75]]
        # The generous rear core bay contains a small staff WC. The top
        # landing remains at least .95m deep, independent of this room.
        if core and ymax-core['bounds'][3]>=2.70:
            a,b,c,e=core['bounds'];wc_y=ymax-1.75
            landing=next(r for r in f['rooms'] if r['name']=='Upper_Landing')
            landing['bounds_m'][3]=wc_y
            wc=room(f,'Staff_WC','compact staff WC',[a,wc_y,c,ymax],None,'Tile')
            wc['circulation_keepouts']=[[a,wc_y,a+.95,wc_y+.85]]
            wall(f,'y',wc_y,a,c)
            wall(f,'x',a,wc_y,ymax,doors=[(wc_y+.52,.90)])
            wall(f,'x',c,wc_y,ymax)
        for n in range(1,floors):
            f=floor(n,'owners_apartment');left=core_rooms(f);split=.10;rear_split=(split+ymax)/2
            room(f,'Owner_Bed_Living','owner living bedroom',[xmin,ymin,left,split],'E','Oak')
            room(f,'Owner_Kitchen','private owner kitchenette',[xmin,split,left,rear_split],'E','Tile')
            room(f,'Owner_Bathroom','private owner bathroom',[xmin,rear_split,left,ymax],'E','Tile')
            wall(f,'x',left,ymin,ymax,doors=[((ymin+split)/2,DOOR),((split+rear_split)/2,DOOR),((rear_split+ymax)/2,DOOR)])
            wall(f,'y',split,xmin,left);wall(f,'y',rear_split,xmin,left)
    elif kind=='library':
        for n in range(floors):
            f=floor(n,'public_library')
            grid(f,['reading lounge','library reception','circulating book stacks','staff archive'] if n==0 else ['quiet study','local history reading','reference book stacks','staff bathroom utility'])
    elif kind=='mairie':
        programs=[['public waiting','registry reception','records archive','staff bathroom utility'],
            ['council meeting','administration office','municipal archive','staff study'],
            ['planning office','community meeting','paper archive','staff bathroom utility']]
        for n in range(floors):grid(floor(n,'municipal_rooms'),programs[min(n,2)])
    elif kind=='hotel':
        for n in range(floors):
            f=floor(n,'hotel_ground' if n==0 else 'hotel_guest_floor')
            grid(f,['hotel reception','breakfast lounge','hotel kitchen','linen staff office'] if n==0 else ['guest bedroom']*4)
            if n:
                bedrooms=[r for r in f['rooms'] if r['purpose']=='guest bedroom']
                for r in bedrooms:
                    a,b,c,e=r['bounds_m'];front=r['access_edge']=='N'
                    # Keep the sleeping area on the exterior facade. A small
                    # private entry beside the internal bathroom connects the
                    # shared hall to both rooms without crossing sanitary space.
                    cut=e-1.60 if front else b+1.60
                    lo,hi=(cut,e) if front else(b,cut)
                    bath_right=c-1.10;door=c-.55;hall_edge=e if front else b
                    r['bounds_m']=[a,b,c,cut] if front else[a,cut,c,e]
                    r['circulation_keepouts']=[[door-.52,cut-.90,door+.52,cut] if front else
                        [door-.52,cut,door+.52,cut+.90]]
                    r['exterior_boundary_required']=True
                    for p in f['partitions']:
                        if p['axis']=='y' and abs(p['coordinate_m']-hall_edge)<.001:
                            for o in p['openings']:
                                if o['kind']=='door' and a<o['center_m']<c:o['center_m']=door
                    room(f,r['name']+'_Ensuite','private ensuite shower bathroom',[a,lo,bath_right,hi],'E','Tile')
                    room(f,r['name']+'_Suite_Entry','private suite entry circulation',[bath_right,lo,c,hi],None,'Oak')
                    wall(f,'y',cut,a,c,doors=[(door,DOOR)])
                    wall(f,'x',bath_right,lo,hi,doors=[((lo+hi)/2,DOOR)])
                    if abs(c-(core['bounds'][0]-HALL))<.001:
                        # A side-hall doorway reaches the private entry only;
                        # the exterior sleeping area keeps a continuous wall.
                        for p in f['partitions']:
                            if p['axis']=='x' and abs(p['coordinate_m']-c)<.001 and p['span_m'][0]<=lo and p['span_m'][1]>=hi:
                                p['openings'].append({'kind':'door','center_m':(lo+hi)/2,
                                    'width_m':DOOR,'bottom_m':0.,'height_m':2.08})
    elif kind=='wash':
        grid(floor(0,'public_baths'),['bath reception','changing lockers','individual shower cubicles','bath washing room'],'Tile')
    elif kind=='work':
        grid(floor(0,'repair_workshop'),['repair workshop','workshop reception','tool material store','staff wash locker'],'Stone')
    elif kind=='cannery':
        grid(floor(0,'cannery_workrooms'),['packing benches','wash preparation','canning equipment store','label store staff wash'],'Tile')
    elif ident=='Port_Warehouse_Exterior':
        grid(floor(0,'port_warehouse_interior_proposal'),['cargo receiving','inventory office','dry rack storage','rope crate store'],'Stone')
    elif kind=='netshed':
        f=floor(0,'netmakers_shed');split=.10
        room(f,'Net_Work','net repair bench',[xmin,ymin,xmax,split],None,'Stone')
        f['rooms'][-1]['circulation_keepouts']=[[xmin,split-.96,xmax,split]]
        room(f,'Net_Store','net and rope storage',[xmin,split,0,ymax],'S','Oak')
        room(f,'Tool_Store','hand tools storage',[0,split,xmax,ymax],'S','Oak')
        wall(f,'y',split,xmin,xmax,doors=[((xmin)/2,.88),(xmax/2,.88)])
        wall(f,'x',0,split,ymax)
        f['access_keepouts']=[[doorx-.55,ymin,doorx+.55,split]]
    elif kind=='windmill':
        for n in range(floors):two_rooms(floor(n,'working_mill'),'grain milling equipment' if n==0 else 'mill drive mechanism','sack and hand tool storage' if n==0 else 'mill maintenance workbench',rear_finish='Stone')
    elif kind=='chapel':
        f=floor(0,'chapel_nave_and_vestry');left=core_rooms(f);split=ymax-2.3
        room(f,'Nave','chapel nave pews altar',[xmin,ymin,left,split],None,'Stone')
        room(f,'Vestry','vestry and ceremonial storage',[xmin,split,left,ymax],'E','Oak')
        wall(f,'y',split,xmin,left,doors=[((xmin+left)/2,.95)])
        f['access_keepouts']=[[-.70,ymin,.70,split]]
        if floors>1:
            f=floor(1,'partial_choir_gallery');left=core_rooms(f);end=core['bounds'][3]+1.0
            room(f,'Choir_Gallery','chapel music and choir gallery',[xmin,ymin,left,end],None,'Oak')
            f['partial_slab_bounds']=[xmin,ymin,xmax,end]
            f['nave_void']=[xmin,end,xmax,ymax]
            for r in f['rooms']:r['bounds_m'][3]=min(r['bounds_m'][3],end)
            for p in f['partitions']:
                if p['axis']=='x':p['span_m'][1]=min(p['span_m'][1],end)
    elif kind=='halles':
        f=floor(0,'open_market_with_booths')
        room(f,'Market_Aisle','crossed public market aisles',[xmin,ymin,xmax,ymax],None,'Stone')
        f['access_keepouts']=[[-.70,ymin,.70,ymax],[xmin,-.70,xmax,.70]]
        f['booths']=[{'bounds':[x-1.05,y-.75,x+1.05,y+.75],'purpose':p} for x,y,p in [(-4.4,-1.9,'flowers'),(-2.0,-1.9,'bread'),(2,-1.9,'vegetables'),(4.4,-1.9,'fish'),(-4.4,1.9,'linen'),(-2,1.9,'produce'),(2,1.9,'dairy'),(4.4,1.9,'dry goods')]]
    else:two_rooms(floor(0,'general_workrooms'),'public reception','working storage') if core else grid(floor(0,'general_workrooms'),['reception','work room','store','staff room'])
    if core:
        for f in levels:f['stair_to_next_level']=core if f['level']<floors-1 else None
    # Attach real partition apertures to the rooms they actually border.
    for f in levels:
        for r in f['rooms']:
            a,b,c,e=r['bounds_m']
            for p in f['partitions']:
                axis,co=p['axis'],p['coordinate_m']
                touches=abs(co-a)<.001 or abs(co-c)<.001 if axis=='x' else abs(co-b)<.001 or abs(co-e)<.001
                if not touches:continue
                lo,hi=(b,e) if axis=='x' else(a,c)
                for o in p['openings']:
                    if o['kind']=='door' and lo<o['center_m']<hi:
                        r['door_gaps'].append({'axis':axis,'coordinate_m':co,**o})
    result={'id':ident,'kind':kind,'footprint_m':[w,d],'floors':floors,'floor_height_m':FLOOR_HEIGHT,
        'clear_bounds_m':[xmin,ymin,xmax,ymax],'core':core,'levels':levels,
        'entrance_local_m':[doorx,ymin],
        'coordinate_system':'Local metres; front south; root origin/yaw transform retained.',
        'scope':'New detailed offline interior proposal; not the existing game Spaces or a runtime navigation certification.'}
    assign_assets(result)
    return result


def assign_assets(plan):
    rng=random.Random(int(hashlib.sha256(plan['id'].encode()).hexdigest()[:12],16))
    for f in plan['levels']:
        for room in f['rooms']:
            x0,y0,x1,y1=room['bounds_m'];purpose=room['purpose'];occupied=[]
            blockers=room['circulation_keepouts']+f['access_keepouts']
            if room['access_edge']=='W':blockers=blockers+[[x0,y0,x0+.96,y1]]
            room['circulation_keepouts']=[list(p) for p in blockers if intersects(p,[x0,y0,x1,y1])]
            def place(kind,w,d,h,rot=0,wall_decor=False,positions=()):
                fw,fd=(d,w) if rot%180 else (w,d)
                candidates=list(positions)+[(x0+fw/2+.09,y1-fd/2-.09),(x0+fw/2+.09,y0+fd/2+.09),
                    (x1-fw/2-.09,y1-fd/2-.09),(x1-fw/2-.09,y0+fd/2+.09),
                    ((x0+x1)/2,(y0+y1)/2)]
                # A 0.18m deterministic search finds remaining perimeter bays.
                for y in (y0+fd/2+.07+i*.18 for i in range(max(0,int((y1-y0-fd-.14)/.18))+1)):
                    for x in (x0+fw/2+.07+i*.18 for i in range(max(0,int((x1-x0-fw-.14)/.18))+1)):candidates.append((x,y))
                for x,y in candidates:
                    rect=[x-fw/2,y-fd/2,x+fw/2,y+fd/2]
                    if rect[0]<x0+.04 or rect[2]>x1-.04 or rect[1]<y0+.04 or rect[3]>y1-.04:continue
                    if any(intersects(rect,p) for p in blockers):continue
                    if any(intersects([rect[0]-.06,rect[1]-.06,rect[2]+.06,rect[3]+.06],p) for p in occupied):continue
                    asset={'id':room['id']+f'_A{len(room["assets"]):02d}_{kind}','kind':kind,'center_m':[x,y],
                        'dimensions_m':[w,d,h],'rotation_degrees':rot,'footprint_m':rect,
                        'accent':rng.choice(['Sage','BluePaint','TealCloth','Linen']),'collision_proxy':not wall_decor}
                    if kind=='kitchen_run':asset['integrated_fixtures']=['recessed_sink','tap','hob','undercounter_fridge']
                    if kind=='dining_table':asset['integrated_seating']=2
                    if kind=='sewing_table':asset['integrated_seating']=1
                    room['assets'].append(asset)
                    if not wall_decor:occupied.append(rect)
                    return asset
                return None
            if any(k in purpose for k in('circulation','landing','vertical','access')):continue
            if purpose=='crossed public market aisles':
                for booth in f.get('booths',[]):
                    a,b,c,e=booth['bounds'];room['assets'].append({'id':room['id']+'_Booth_'+str(len(room['assets'])),
                        'kind':'market_stall','center_m':[(a+c)/2,(b+e)/2],'dimensions_m':[c-a,e-b,1.3],
                        'rotation_degrees':0,'footprint_m':[a,b,c,e],'accent':'Sage','collision_proxy':True,'goods':booth['purpose']})
            elif any(k in purpose for k in ('bedroom','guest room')):
                bed=place('bed',1.35,1.95,.62) or place('bed',1.25,1.95,.62,90) or place('bed',.95,1.95,.62,90)
                if 'artist study' in purpose:
                    place('writing_desk',.85,.45,.77);place('task_stool',.34,.34,.47)
                place('wardrobe',.75,.42,1.95);place('bedside',.32,.32,.52)
                if 'ensuite' in purpose:place('shower_screen',1.15,1.15,2.05);place('toilet',.48,.74,.75);place('basin',.45,.38,.90)
                if 'living' in purpose:place('sofa',1.35,.70,.90)
            elif purpose=='compact staff WC':
                place('toilet',.48,.74,.75,90,positions=[(x1-.74/2-.05,y1-.48/2-.05)])
                place('basin',.32,.26,.90,positions=[(x0+.32/2+.05,y1-.26/2-.05)])
            elif any(k in purpose for k in ('bathroom','wash locker','staff wash','shower','bath washing')):
                if 'ensuite' in purpose:
                    place('shower_screen',.95,.95,2.05)
                elif 'shower' in purpose:
                    for _ in range(2):place('shower_screen',.95,.95,2.05)
                else:place('bathtub',1.45,.70,.65) or place('bathtub',1.45,.70,.65,90) or place('shower_screen',.80,.80,2.05)
                place('toilet',.48,.74,.75);place('basin',.52,.42,.90)
                place('lockers' if 'locker' in purpose else 'linen_cabinet',.55,.38,1.85 if 'locker' in purpose else 1.5)
                if 'kitchenette' in purpose or 'pantry' in purpose:place('kitchen_run',1.1,.56,.92)
                if purpose=='staff bathroom utility':
                    # Retain downstream room palettes after removing the
                    # former pantry assembly from this sanitary room.
                    rng.choice(['Sage','BluePaint','TealCloth','Linen'])
            elif any(k in purpose for k in ('kitchen','preparation','coffee')):
                place('kitchen_run',min(2.1,max(1.1,(x1-x0)-1.3)),.58,.92)
                if 'bakery' in purpose:place('oven',.9,.72,1.25);place('bread_rack',.8,.48,1.65)
                elif 'coffee' in purpose:place('coffee_machine',1.2,.65,1.45)
                elif 'crepe' in purpose:place('cooker',1.05,.65,.95)
                else:place('dining_table',1.0,1.15,.78)
                place('cupboard',.65,.38,1.75)
                if 'living' in purpose:place('sofa',1.35,.70,.90)
            elif any(k in purpose for k in ('cafe dining','creperie dining','breakfast lounge')):
                if 'cafe dining' in purpose:
                    hatch=next(o for p in f['partitions'] for o in p['openings'] if o['kind']=='service_hatch')
                    place('cafe_counter',min(3.0,hatch['width_m']),.60,1.08,
                        positions=[(hatch['center_m'],y1-.38)])
                place('banquette',min(2.2,(x1-x0)-1.1),.68,.95)
                for _ in range(4 if 'cafe dining' in purpose else(3 if x1-x0>5 else 2)):place('cafe_table_set',1.35,1.0,.95)
                place('service_console',.95,.45,.9)
            elif 'grocery sales' in purpose or 'bakery retail' in purpose:
                place('retail_counter',1.35,.65,1.05)
                for _ in range(2):place('grocery_shelf',.9,.38,1.7)
                if 'bakery' in purpose:place('bread_rack',.8,.48,1.65)
            elif any(k in purpose for k in ('book stacks','archive','paper archive','reference')):
                for _ in range(3):place('bookshelf',.9,.32,1.95)
                place('writing_desk',1.0,.55,.77)
            elif any(k in purpose for k in ('reading','study','office','registry','reception','meeting','council','planning')):
                if 'meeting' in purpose or 'council' in purpose:place('meeting_table',1.6,1.0,.95)
                elif 'reading' in purpose or 'quiet' in purpose:place('reading_table',1.25,.85,.95)
                else:place('writing_desk',1.1,.58,.77)
                place('linen_cabinet' if 'linen staff office' in purpose else 'bookshelf',.8,.30,1.75)
                place('lounge_chair',.62,.68,.9)
                if 'meeting' in purpose or 'council' in purpose:place('lounge_chair',.62,.68,.9)
            elif 'living' in purpose or 'waiting' in purpose:
                place('sofa',1.65,.74,.90);place('coffee_table',.65,.45,.48)
                if 'kitchen' in purpose:place('kitchen_run',1.5,.58,.92)
                place('bookshelf',.65,.30,1.5)
            elif 'changing' in purpose:
                for _ in range(2):place('lockers',.8,.45,1.85)
                place('bench',1.2,.42,.48)
            elif 'chapel nave' in purpose:
                for _ in range(6):place('pew',1.55,.62,.9)
                place('altar',1.5,.60,1.05)
            elif 'choir' in purpose:
                place('organ',1.25,.65,1.65);place('bench',1.2,.42,.48);place('music_stand',.5,.4,1.25)
            elif 'milling' in purpose or 'drive mechanism' in purpose:
                place('mill_mechanism',1.30,1.30,1.65) or place('mill_mechanism',1.0,1.0,1.65)
                place('sacks',.65,.65,.8)
            elif any(k in purpose for k in ('workshop','repair bench','workbench','packing benches','net repair')):
                place('workbench',min(1.8,(x1-x0)-.9),.66,.95) or place('workbench',.90,.55,.95)
                place('tool_rack',.8,.30,1.8);place('crate_stack',.65,.6,.9)
            elif 'sewing' in purpose:
                place('sewing_table',1.10,1.0,1.12)
                place('storage_rack',.9,.40,1.85);place('crate_stack',.65,.6,.9)
            elif any(k in purpose for k in ('store','stock','storage','receiving','linen','vestry')):
                for _ in range(2):place('storage_rack',.9,.40,1.85)
                place('crate_stack',.65,.6,.9)
            else:place('writing_desk',1.0,.55,.77);place('cupboard',.65,.38,1.7)
            # Small rooms retain a real program fixture even where a large
            # secondary cabinet cannot fit. Skipped extras are never squeezed.
            if not room['assets']:place('wall_tool_cabinet',min(.55,(x1-x0)-.2),.22,1.2)
            room['furnishing_count']=len(room['assets'])
    refine_furniture_layout(plan)


# Every front-facing recipe below has its back on local +Y and its usable
# front on local -Y. Keep this convention shared by the planner and meshes.
WALL_BACKED={'bed','sofa','banquette','bookshelf','grocery_shelf','storage_rack',
    'bread_rack','tool_rack','cupboard','wardrobe','linen_cabinet','lockers',
    'wall_tool_cabinet','writing_desk','kitchen_run','oven','cooker',
    'coffee_machine','toilet','basin','shower_screen','workbench','organ','altar','service_console'}
FRONT_CLEARANCE={'wardrobe':.58,'cupboard':.55,'linen_cabinet':.50,
    'lockers':.50,'bookshelf':.50,'grocery_shelf':.55,'storage_rack':.50,
    'bread_rack':.50,'tool_rack':.50,'wall_tool_cabinet':.45,
    'kitchen_run':.80,'oven':.80,'cooker':.80,'coffee_machine':.80,
    'toilet':.55,'basin':.50,'shower_screen':.50,'workbench':.65,
    'organ':.55,'banquette':.40,'cafe_counter':.60}


def rotated_xy(x,y,rotation):
    """Exact cardinal rotation prevents tiny phantom footprint overlaps."""
    return ((x,y),(-y,x),(-x,-y),(y,-x))[int(round(rotation/90))%4]


def asset_footprint(asset,center=None,rotation=None):
    x,y=center or asset['center_m'];w,d=asset['dimensions_m'][:2]
    rotation=asset.get('rotation_degrees',0) if rotation is None else rotation
    if int(round(rotation/90))%2:w,d=d,w
    return [x-w/2,y-d/2,x+w/2,y+d/2]


def local_rect(asset,left,bottom,right,top):
    x,y=asset['center_m'];rot=asset.get('rotation_degrees',0)
    corners=[rotated_xy(xx,yy,rot) for xx in(left,right) for yy in(bottom,top)]
    return [x+min(p[0] for p in corners),y+min(p[1] for p in corners),
        x+max(p[0] for p in corners),y+max(p[1] for p in corners)]


def furniture_front(asset,depth):
    w,d=asset['dimensions_m'][:2]
    # The front band covers the usable middle, without requiring the same
    # standing position at both ends of a long shared work surface.
    half=min(w*.42,.38)
    return local_rect(asset,-half,-d/2-depth,half,-d/2-.015)


def furniture_groups(room):
    """Preserve semantic IDs while connecting actual furnished activities."""
    remaining=list(room['assets']);groups=[];relations=[]
    def take(kind):
        asset=next((q for q in remaining if q['kind']==kind),None)
        if asset:remaining.remove(asset)
        return asset
    def add(label,members,wall=False):
        groups.append({'label':label,'members':members,'wall':wall})
    if room['purpose']=='chapel nave pews altar':
        altar=take('altar');members=[(altar,0.,0.,0)]
        for i,pew in enumerate([q for q in remaining if q['kind']=='pew']):
            remaining.remove(pew);members.append((pew,0.,-1.25-i*1.10,180))
            relations.append({'type':'pew_altar','source':pew['id'],'target':altar['id']})
        add('chapel_ordered_rows',members,True)
    sofa=take('sofa');coffee=take('coffee_table') if sofa else None
    if sofa:
        members=[(sofa,0.,0.,0)]
        if coffee:
            gap=.40;dy=-(sofa['dimensions_m'][1]+coffee['dimensions_m'][1])/2-gap
            members.append((coffee,0.,dy,0))
            relations.append({'type':'sofa_coffee_table','source':sofa['id'],'target':coffee['id'],
                'edge_gap_m':gap})
        add('living_group',members,True)
    bed=take('bed');bedside=take('bedside') if bed else None
    if bed:
        members=[(bed,0.,0.,0)]
        if bedside:
            members.append((bedside,(bed['dimensions_m'][0]+bedside['dimensions_m'][0])/2+.10,
                (bed['dimensions_m'][1]-bedside['dimensions_m'][1])/2,0))
            relations.append({'type':'bed_bedside','source':bed['id'],'target':bedside['id']})
        add('sleeping_group',members,True)
    table=take('meeting_table')
    if table:
        members=[(table,0.,0.,0)]
        for side in(-1,1):
            seat=take('lounge_chair')
            if seat:
                dy=side*((table['dimensions_m'][1]+seat['dimensions_m'][1])/2+.12)
                members.append((seat,0.,dy,180 if side==-1 else 0))
                relations.append({'type':'seat_table','source':seat['id'],'target':table['id']})
        add('meeting_group',members)
    for table_kind in('writing_desk','reading_table'):
        table=take(table_kind)
        if not table:continue
        seat=take('task_stool') or take('lounge_chair');members=[(table,0.,0.,0)]
        if seat:
            dy=-(table['dimensions_m'][1]+seat['dimensions_m'][1])/2-.12
            members.append((seat,0.,dy,180))
            relations.append({'type':'seat_table','source':seat['id'],'target':table['id']})
        add('work_reading_group',members,table_kind=='writing_desk')
    kitchen=take('kitchen_run')
    if kitchen:
        members=[(kitchen,0.,0.,0)];end=kitchen['dimensions_m'][0]/2
        for kind in('oven','coffee_machine','cooker'):
            machine=take(kind)
            if machine:
                xx=end+.12+machine['dimensions_m'][0]/2
                # Align the cabinet backs, not the centres of unequal depths.
                yy=(kitchen['dimensions_m'][1]-machine['dimensions_m'][1])/2
                members.append((machine,xx,yy,0));end=xx+machine['dimensions_m'][0]/2
                relations.append({'type':'kitchen_work_line','source':kitchen['id'],'target':machine['id']})
        add('kitchen_work_line',members,True)
    for asset in remaining:add(asset['kind'],[(asset,0.,0.,0)],asset['kind'] in WALL_BACKED)
    # Large related arrangements are resolved before minor wall storage.
    groups.sort(key=lambda g:(-len(g['members']),-sum(q['dimensions_m'][0]*q['dimensions_m'][1]
        for q,_,_,_ in g['members']),g['label']))
    return groups,relations


def furniture_clearance_sets(members):
    """Alternative usable clearances; bands may share circulation, not solids."""
    reservations=[]
    for asset in members:
        kind=asset['kind'];w,d=asset['dimensions_m'][:2]
        if kind in FRONT_CLEARANCE:reservations.append(furniture_front(asset,FRONT_CLEARANCE[kind]))
        if kind=='sofa':reservations.append(furniture_front(asset,.34))
        if kind=='bed':
            reservations.append(furniture_front(asset,.52))
            # The head end contains the bedside. One long side and the foot
            # must remain usable; either handed layout is valid.
        if kind in('lounge_chair','task_stool'):
            # A connected desk chair faces the table; entry is from behind.
            reservations.append(local_rect(asset,-min(w*.40,.25),d/2+.015,
                min(w*.40,.25),d/2+.35))
    beds=[q for q in members if q['kind']=='bed']
    if beds:
        bed=beds[0];w,d=bed['dimensions_m'][:2]
        return [reservations+[local_rect(bed,-w/2-.50,-d/2,-w/2-.015,d*.12)],
            reservations+[local_rect(bed,w/2+.015,-d/2,w/2+.50,d*.12)]]
    return [reservations]


def refine_furniture_layout(plan):
    """Bounded deterministic composition search, with no inventory changes.

    The original allocator remains the fixture-program/ID authority. This pass
    places those same assets as activity groups and gives their physical fronts
    room to work. Cardinal furniture follows building walls rather than adding
    arbitrary chair yaw or dense unrelated objects to empty floor area.
    """
    binding_path=ROOT.parents[1]/'game/data/town3d/projection.json'
    bound=set()
    if binding_path.exists():
        projection=json.loads(binding_path.read_text(encoding='utf-8'))
        def bindings(value):
            if isinstance(value,dict):
                if value.get('model_asset_id'):bound.add(value['model_asset_id'])
                for child in value.values():bindings(child)
            elif isinstance(value,list):
                for child in value:bindings(child)
        bindings(projection)
    for floor in plan['levels']:
        for room in floor['rooms']:
            if not room['assets'] or room['purpose']=='crossed public market aisles':continue
            bounds=room['bounds_m'];a,b,c,e=bounds
            omitted=[]
            if room['purpose']=='cafe dining':
                omitted=[q for q in room['assets'] if q['kind']=='service_console' and q['id'] not in bound]
            elif room['purpose']=='breakfast lounge':
                tables=[q for q in room['assets'] if q['kind']=='cafe_table_set']
                omitted=[q for q in tables[2:] if q['id'] not in bound]
            if omitted:
                room['assets']=[q for q in room['assets'] if q not in omitted]
                room['omitted_optional_assets']=[{'id':q['id'],'kind':q['kind'],
                    'reason':'retain essential and game-bound fixtures while opening useful dining circulation'} for q in omitted]
            if room['purpose']=='private owner kitchenette' and c-a<3.20:
                # A compact single-person kitchen uses a genuine 1.10m work
                # module, keeping its sink/hob/fridge recipe and semantic ID.
                for asset in room['assets']:
                    if asset['kind']=='kitchen_run':asset['dimensions_m'][0]=1.10
                    if asset['kind']=='cupboard':asset['dimensions_m'][:2]=[.55,.32]
            if room['purpose']=='cafe dining':
                # The real two-chair bistro mesh is .68m deep. A .90m proxy
                # retains a .11m buffer on both sides without inventing a full
                # metre of solid furniture across the staff-door approach.
                for asset in room['assets']:
                    if asset['kind']=='cafe_table_set':asset['dimensions_m'][1]=.90
            desks=[q for q in room['assets'] if q['kind']=='writing_desk']
            if desks and not any(q['kind'] in('task_stool','lounge_chair') for q in room['assets']):
                # Six archive work surfaces formerly had no usable seat at all.
                # Add a small connected stool without renumbering any old ID.
                desk=desks[0]
                room['assets'].append({'id':desk['id']+'_Seat','kind':'task_stool',
                    'center_m':[desk['center_m'][0],desk['center_m'][1]-.56],
                    'dimensions_m':[.34,.34,.47],'rotation_degrees':180,
                    'accent':desk['accent'],'collision_proxy':True})
            # The old packer reserved an entire .96m room edge even where
            # only one local doorway needed that width. Replace those generic
            # strips with actual aperture approaches; retain entrance spines,
            # custom reserves and every dedicated hall/stair zone unchanged.
            blockers=[]
            for reserve in room['circulation_keepouts']:
                edge=room['access_edge'];generic=False
                if room['door_gaps']:
                    generic=(edge=='E' and all(abs(x-y)<.001 for x,y in zip(reserve,[c-.96,b,c,e]))) or (
                        edge=='W' and all(abs(x-y)<.001 for x,y in zip(reserve,[a,b,a+.96,e]))) or (
                        edge=='N' and all(abs(x-y)<.001 for x,y in zip(reserve,[a,e-.96,c,e]))) or (
                        edge=='S' and all(abs(x-y)<.001 for x,y in zip(reserve,[a,b,c,b+.96])))
                if not generic:blockers.append(list(reserve))
            for reserve in floor['access_keepouts']:
                if intersects(reserve,bounds) and reserve not in blockers:blockers.append(list(reserve))
            # Actual door thresholds receive a local .90m approach in addition
            # to the wider cross-hall/entry reserves authored by the room plan.
            for door in room['door_gaps']:
                co=door['coordinate_m'];mid=door['center_m'];half=door['width_m']/2
                if door['axis']=='x':
                    blockers.append([co if abs(co-a)<.001 else co-.90,mid-half,
                        co+.90 if abs(co-a)<.001 else co,mid+half])
                else:blockers.append([mid-half,co if abs(co-b)<.001 else co-.90,
                    mid+half,co+.90 if abs(co-b)<.001 else co])
            blockers=[[round(value,6) for value in rect] for rect in blockers]
            groups,relations=furniture_groups(room)
            salt=int(hashlib.sha256(room['id'].encode()).hexdigest()[:8],16)
            def inside(rect,margin=.035):
                return rect[0]>=a+margin-1e-7 and rect[1]>=b+margin-1e-7 and rect[2]<=c-margin+1e-7 and rect[3]<=e-margin+1e-7
            def candidates(group):
                choices=[];members=group['members']
                for rotation in((0,180,90,270) if salt%2==0 else(180,0,270,90)):
                    transformed=[]
                    for asset,x,y,rot in members:
                        xx,yy=rotated_xy(x,y,rotation)
                        q={**asset,'center_m':[xx,yy],'rotation_degrees':(rot+rotation)%360}
                        q['footprint_m']=asset_footprint(q);transformed.append(q)
                    lo=min(q['footprint_m'][0] for q in transformed);hi=max(q['footprint_m'][2] for q in transformed)
                    bottom=min(q['footprint_m'][1] for q in transformed);top=max(q['footprint_m'][3] for q in transformed)
                    wall_gap=.04 if room['purpose']=='compact staff WC' else .07
                    xs=[a+wall_gap-lo,c-wall_gap-hi,(a+c-lo-hi)/2]
                    ys=[b+wall_gap-bottom,e-wall_gap-top,(b+e-bottom-top)/2]
                    # A .16m perimeter search can use a narrow bay beside an
                    # aperture while keeping the actual furniture back flush.
                    xs+= [a+.07-lo+i*.16 for i in range(max(0,int((c-a-(hi-lo)-.14)/.16))+1)]
                    ys+= [b+.07-bottom+i*.16 for i in range(max(0,int((e-b-(top-bottom)-.14)/.16))+1)]
                    if group['wall']:
                        anchor=transformed[0];w,d=anchor['dimensions_m'][:2]
                        bx,by=rotated_xy(0,d/2,rotation)
                        if rotation==0:offsets=[(xx,e-wall_gap-by-anchor['center_m'][1]) for xx in xs]
                        elif rotation==180:offsets=[(xx,b+wall_gap-by-anchor['center_m'][1]) for xx in xs]
                        elif rotation==90:offsets=[(a+wall_gap-bx-anchor['center_m'][0],yy) for yy in ys]
                        else:offsets=[(c-wall_gap-bx-anchor['center_m'][0],yy) for yy in ys]
                    else:offsets=[(xx,yy) for xx in xs[:3] for yy in ys[:3]]+[(xx,yy) for yy in ys for xx in xs]
                    original=members[0][0]
                    preferred=None
                    if not group['wall'] and rotation==original.get('rotation_degrees',0):
                        offsets.insert(0,(original['center_m'][0]-transformed[0]['center_m'][0],
                            original['center_m'][1]-transformed[0]['center_m'][1]))
                    if room['purpose']=='cafe dining':
                        if original['kind']=='banquette' and rotation==180:
                            preferred=(a+original['dimensions_m'][0]/2+.09,b+original['dimensions_m'][1]/2+.09)
                        elif original['kind']=='cafe_table_set' and rotation==0:
                            index=[q['id'] for q in room['assets'] if q['kind']=='cafe_table_set'].index(original['id'])
                            preferred=[(c-.745,b+.52),(a+.745,b+1.65),(a+2.70,b+2.80),
                                (c-.745,e-1.35)][index]
                        if preferred is not None:offsets.insert(0,preferred)
                    # The existing cafe service counter stays below its real
                    # partition hatch, preserving the established serving side.
                    if members[0][0]['kind']=='cafe_counter':
                        if rotation!=0:continue
                        q=members[0][0];offsets=[tuple(q['center_m'])]
                    seen=set()
                    for dx,dy in offsets:
                        key=(round(dx,5),round(dy,5))
                        if key in seen:continue
                        seen.add(key);placed=[]
                        for q in transformed:
                            p={**q,'center_m':[round(q['center_m'][0]+dx,6),round(q['center_m'][1]+dy,6)]}
                            p['footprint_m']=[round(v,6) for v in asset_footprint(p)];placed.append(p)
                        rects=[q['footprint_m'] for q in placed]
                        if any(not inside(r) or any(intersects(r,z,1e-6) for z in blockers) for r in rects):continue
                        valid=[]
                        for clear in furniture_clearance_sets(placed):
                            if any(not inside(z,.015) or any(intersects(z,r,1e-6) for r in rects) for z in clear):continue
                            valid.append(clear)
                        if not valid:continue
                        # Prefer a quiet perimeter and grouped centre with a
                        # little stable handedness rather than random clutter.
                        center=(sum(q['center_m'][0] for q in placed)/len(placed),sum(q['center_m'][1] for q in placed)/len(placed))
                        score=min((center[0]-a)**2,(center[0]-c)**2)+min((center[1]-b)**2,(center[1]-e)**2)
                        score+=((dx if salt%2 else -dx)+(dy if salt%3 else -dy))*.01
                        if not group['wall']:
                            score+=.80*((placed[0]['center_m'][0]-original['center_m'][0])**2+
                                (placed[0]['center_m'][1]-original['center_m'][1])**2)
                        if preferred and abs(dx-preferred[0])<1e-6 and abs(dy-preferred[1])<1e-6:score-=1000
                        for clear in valid:choices.append((score,placed,clear))
                choices.sort(key=lambda p:p[0])
                # Include the best candidates from every cardinal orientation;
                # otherwise a crowded perimeter can starve the rotated bay.
                buckets={rotation:[] for rotation in(0,90,180,270)}
                for choice in choices:buckets[choice[1][0]['rotation_degrees']].append(choice)
                return sorted([q for bucket in buckets.values() for q in bucket[:48]],key=lambda p:p[0])
            all_choices=[candidates(g) for g in groups];visits=0;answer=None
            def solve(index,placed,clear):
                nonlocal visits,answer
                visits+=1
                if visits>18000:return False
                if index==len(groups):answer=(placed,clear);return True
                for _,group_assets,reserves in all_choices[index]:
                    rects=[q['footprint_m'] for q in group_assets]
                    if any(intersects([r[0]-.065,r[1]-.065,r[2]+.065,r[3]+.065],p['footprint_m'],1e-6) for r in rects for p in placed):continue
                    if any(intersects(r,z,1e-6) for r in rects for z in clear):continue
                    if any(intersects(z,p['footprint_m'],1e-6) for z in reserves for p in placed):continue
                    if solve(index+1,placed+group_assets,clear+reserves):return True
                return False
            solved=solve(0,[],[])
            if solved:
                mapped={q['id']:q for q in answer[0]}
                room['assets']=[mapped[q['id']] for q in room['assets']]
                room['furniture_clearances_m']=answer[1]
                room['circulation_keepouts']=blockers
            room['furnishing_count']=len(room['assets'])
            room['furniture_composition']={'schema':'living_town.furniture_composition.v1',
                'status':'PASS' if solved else 'UNRESOLVED','search_nodes':visits,
                'candidate_counts':[len(q) for q in all_choices],'relationships':relations,
                'inventory_preserved':not omitted,'omitted_optional_asset_ids':[q['id'] for q in omitted],
                'policy':'wall-supported backs, activity groups, clear fronts and actual door approaches'}


def audit_furniture_compositions(record):
    """Measure physical orientation, linked activities and clear usable space.

    Reconstruct the expected relationships from fixture kinds; declared PASS
    labels or stored facing vectors cannot make backwards geometry pass.
    Native mesh contact and visual refinement still need separate review.
    """
    failures=[];orientations=[];relationships=[];clearances=[];density=[]
    for building in record['buildings']:
        for floor in building['levels']:
            for room in floor['rooms']:
                assets=room['assets']
                if not assets or room['purpose']=='crossed public market aisles':continue
                a,b,c,e=room['bounds_m'];by_id={q['id']:q for q in assets}
                if room.get('furniture_composition',{}).get('status')!='PASS':
                    failures.append({'room':room['id'],'reason':'room composition search did not resolve'})
                for asset in assets:
                    rot=asset.get('rotation_degrees',0);kind=asset['kind']
                    actual=asset_footprint(asset)
                    if rot%90 or max(abs(x-y) for x,y in zip(actual,asset['footprint_m']))>.00001:
                        failures.append({'asset':asset['id'],'reason':'rotation and footprint disagree'})
                    if kind not in WALL_BACKED:continue
                    x,y=asset['center_m'];back=rotated_xy(0,asset['dimensions_m'][1]/2,rot)
                    distances={0:e-(y+back[1]),90:(x+back[0])-a,
                        180:(y+back[1])-b,270:c-(x+back[0])}
                    gap=distances[int(round(rot))%360];passed=.025<=gap<=.14
                    orientations.append({'asset':asset['id'],'kind':kind,
                        'rotation_degrees':rot,'back_to_wall_gap_m':round(gap,6),'pass':passed})
                    if not passed:failures.append({'asset':asset['id'],'reason':'physical back is not supported by the facing wall','gap_m':gap})
                _,expected=furniture_groups(room)
                for relation in expected:
                    source=by_id[relation['source']];target=by_id[relation['target']]
                    dx=target['center_m'][0]-source['center_m'][0]
                    dy=target['center_m'][1]-source['center_m'][1]
                    side,forward=rotated_xy(dx,dy,-source.get('rotation_degrees',0))
                    sw,sd=source['dimensions_m'][:2];tw,td=target['dimensions_m'][:2]
                    typ=relation['type'];measure={};passed=True
                    if typ in('sofa_coffee_table','seat_table'):
                        gap=-forward-(sd+td)/2
                        passed=abs(side)<.045 and forward<0 and (.34<=gap<=.56 if typ=='sofa_coffee_table' else .08<=gap<=.20)
                        if typ=='seat_table':
                            front=rotated_xy(0,-1,source.get('rotation_degrees',0));distance=math.hypot(dx,dy)
                            dot=(front[0]*dx+front[1]*dy)/max(distance,.00001)
                            passed=passed and dot>.995;measure['front_toward_table_dot']=dot
                        measure.update({'lateral_offset_m':round(side,6),'edge_gap_m':round(gap,6)})
                    elif typ=='kitchen_work_line':
                        sr=source.get('rotation_degrees',0);tr=target.get('rotation_degrees',0)
                        back_delta=forward+(td-sd)/2;gap=abs(side)-(sw+tw)/2
                        passed=sr==tr and abs(back_delta)<.015 and .08<=gap<=.18
                        measure.update({'back_alignment_error_m':round(abs(back_delta),6),'module_gap_m':round(gap,6)})
                    elif typ=='bed_bedside':
                        gap=abs(side)-(sw+tw)/2;head_error=abs(forward-(sd-td)/2)
                        passed=.06<=gap<=.16 and head_error<.03
                        measure.update({'bedside_gap_m':round(gap,6),'head_end_alignment_error_m':round(head_error,6)})
                    elif typ=='pew_altar':
                        passed=abs(side)<.04 and forward<-.50
                        measure.update({'altar_in_front_m':round(-forward,6),'row_axis_offset_m':round(side,6)})
                    relationships.append({**relation,**measure,'pass':passed})
                    if not passed:failures.append({'room':room['id'],'reason':'misaligned '+typ,'source':source['id'],'target':target['id'],**measure})
                valid=[]
                for alternative in furniture_clearance_sets(assets):
                    bad=[]
                    for rect in alternative:
                        if rect[0]<a+.014 or rect[1]<b+.014 or rect[2]>c-.014 or rect[3]>e-.014:
                            bad.append({'clearance_m':rect,'reason':'usable front or bed access crosses wall'})
                        hits=[q['id'] for q in assets if intersects(rect,q['footprint_m'],1e-6)]
                        if hits:bad.append({'clearance_m':rect,'reason':'usable front or bed access blocked','assets':hits})
                    valid.append((alternative,bad))
                best=min(valid,key=lambda v:len(v[1]));passed=not best[1]
                clearances.append({'room':room['id'],'reservation_count':len(best[0]),'pass':passed,'failures':best[1]})
                if not passed:failures.append({'room':room['id'],'reason':'functional furniture clearance blocked','details':best[1]})
                area=(c-a)*(e-b);covered=sum((q['footprint_m'][2]-q['footprint_m'][0])*(q['footprint_m'][3]-q['footprint_m'][1]) for q in assets)
                ratio=covered/area;limit=.58 if any(k in room['purpose'] for k in('store','archive','stacks','storage','cafe dining')) else .48
                passed=ratio<=limit
                density.append({'room':room['id'],'solid_fixture_coverage_ratio':round(ratio,6),
                    'maximum_ratio':limit,'free_floor_area_m2':round(area-covered,4),'pass':passed})
                if not passed:failures.append({'room':room['id'],'reason':'excessive solid furniture density','ratio':ratio,'limit':limit})
    return {'schema':'living_town.furniture_composition_audit.v1','status':'PASS' if not failures else 'FAIL',
        'rooms_tested':len(density),'wall_back_orientations_tested':len(orientations),
        'related_activity_groups_tested':len(relationships),'functional_clearance_rooms_tested':len(clearances),
        'wall_back_orientations':orientations,'activity_relationships':relationships,
        'functional_clearances':clearances,'furniture_density':density,'failures':failures,
        'limits':'Measured plan proxies and mesh-recipe orientation convention, not accessibility certification or native visual acceptance.'}


def build_interior(api,ident,interiorc,upper_cover_col,origin,angle,w,d,floors,kind,doorx):
    plan=plan_for_building(ident,w,d,floors,kind,doorx)
    Batch,coll=api['Batch'],api['coll'];all_objects=[];asset_count=0
    def world(x,y,z=0):return(origin[0]+x*math.cos(angle)-y*math.sin(angle),origin[1]+x*math.sin(angle)+y*math.cos(angle),origin[2]+z)
    def flush(batch,bevel=.008,room_id=None,role=None):
        objs=batch.flush(bevel)
        for ob in objs:
            ob['interior_building_id']=ident
            if room_id:ob['interior_room_id']=room_id
            if role:ob['interior_role']=role
        all_objects.extend(o.name for o in objs);return objs
    def slab_parts(bounds,hole):
        x0,y0,x1,y1=bounds
        if not hole:return [bounds]
        a,b,c,e=hole;a=max(a,x0);b=max(b,y0);c=min(c,x1);e=min(e,y1)
        return [[x0,y0,a,y1],[c,y0,x1,y1],[a,y0,c,b],[a,e,c,y1]]
    for f in plan['levels']:
        n=f['level'];ff=f['finished_floor_local_z_m'];parent=interiorc if n==0 else upper_cover_col
        levelc=coll(ident+f'_Interior_L{n:02d}',parent);levelc['floor_index']=n;levelc['finished_floor_local_z_m']=ff
        if n>0:
            slab=Batch(ident+f'_Floor{n+1}',levelc,origin,angle)
            bounds=f.get('partial_slab_bounds',plan['clear_bounds_m'])
            for a,b,c,e in slab_parts(bounds,plan['core']['bounds']):
                if c-a>.01 and e-b>.01:slab.box(((a+c)/2,(b+e)/2,ff-.06),(c-a,e-b,.12),'Oak')
            flush(slab,.006,role='floor_slab')
        walls=Batch(ident+f'_L{n:02d}_Partitions',levelc,origin,angle)
        trims=Batch(ident+f'_L{n:02d}_Joinery',levelc,origin,angle)
        for i,wall in enumerate(f['partitions']):
            axis=wall['axis'];co=wall['coordinate_m'];lo,hi=wall['span_m'];height=wall['height_m'];opens=wall['openings']
            cuts=sorted(set([lo,hi]+[o['center_m']+s*o['width_m']/2 for o in opens for s in(-1,1)]))
            zcuts=sorted(set([0,height]+[o['bottom_m']+h for o in opens for h in(0,o['height_m'])]))
            for a,b in zip(cuts,cuts[1:]):
                for z0,z1 in zip(zcuts,zcuts[1:]):
                    mid=(a+b)/2;zz=(z0+z1)/2
                    if any(abs(mid-o['center_m'])<o['width_m']/2-1e-6 and o['bottom_m']-1e-6<zz<o['bottom_m']+o['height_m']+1e-6 for o in opens):continue
                    center=(co,mid,ff+zz) if axis=='x' else(mid,co,ff+zz)
                    size=(WALL,b-a,z1-z0) if axis=='x' else(b-a,WALL,z1-z0)
                    walls.box(center,size,'Plaster')
                # Baseboard and restrained wainscot stop at real door gaps.
                if not any(abs((a+b)/2-o['center_m'])<o['width_m']/2 for o in opens if o['kind']=='door'):
                    for z,sizez in((.10,.16),(.84,.045)):
                        center=(co,(a+b)/2,ff+z) if axis=='x' else((a+b)/2,co,ff+z)
                        size=(.16,b-a,sizez) if axis=='x' else(b-a,.16,sizez)
                        trims.box(center,size,'White' if z<.2 else 'Sage')
            for j,o in enumerate(opens):
                c=o['center_m'];gap=o['width_m'];bottom=o['bottom_m'];oh=o['height_m']
                for s in(-1,1):
                    p=(co,c+s*(gap/2+.035),ff+bottom+oh/2) if axis=='x' else(c+s*(gap/2+.035),co,ff+bottom+oh/2)
                    size=(.20,.065,oh+.06) if axis=='x' else(.065,.20,oh+.06);trims.box(p,size,'White')
                p=(co,c,ff+bottom+oh+.035) if axis=='x' else(c,co,ff+bottom+oh+.035)
                trims.box(p,(.20,gap+.14,.07) if axis=='x' else(gap+.14,.20,.07),'White')
                if o['kind']=='door':
                    # Show the leaf fully open against a spare length of
                    # partition. Its folded position leaves the aperture
                    # physically empty and avoids guessing a swing through
                    # the authored furniture/circulation reservation.
                    leafw=gap-.065;edge=c+gap/2+.025;leafend=edge+leafw
                    spare=leafend<hi-.035 and not any(q is not o and q['center_m']-q['width_m']/2<leafend and q['center_m']+q['width_m']/2>edge for q in opens)
                    if spare:
                        leaf=Batch(ident+f'_L{n:02d}_DoorLeaf_{i}_{j}',levelc,origin,angle)
                        center=(co+.115,edge+leafw/2,ff+1.015) if axis=='x' else(edge+leafw/2,co+.115,ff+1.015)
                        leaf.box(center,(.045,leafw,2.02) if axis=='x' else(leafw,.045,2.02),'Sage')
                        for zz,hh in((.49,.70),(1.49,.70)):
                            pp=(co+.143,edge+leafw/2,ff+zz) if axis=='x' else(edge+leafw/2,co+.143,ff+zz)
                            leaf.box(pp,(.018,leafw-.15,hh) if axis=='x' else(leafw-.15,.018,hh),'Oak')
                        knob=(co+.17,leafend-.08,ff+1.02) if axis=='x' else(leafend-.08,co+.17,ff+1.02)
                        leaf.ellipsoid(knob,(.035,.035,.035),'Brass',n=8,rings=4)
                        for ob in flush(leaf,.003,role='open_interior_door'):
                            ob['door_aperture_width_m']=gap;ob['door_state']='open against partition'
        flush(walls,.007,role='partition_with_openings');flush(trims,.005,role='interior_joinery')
        if f.get('stair_to_next_level'):
            s=f['stair_to_next_level'];stairs=Batch(ident+f'_L{n:02d}_Stairs',levelc,origin,angle)
            for j in range(s['risers']):
                top=ff+(j+1)*s['riser_m'];y=s['first_tread_y']+j*s['tread_m']
                stairs.box((s['center_x'],y,(ff+top)/2),(s['flight_width_m'],s['tread_m']+.01,top-ff),'Oak')
                stairs.box((s['center_x'],y-s['tread_m']/2,top+.008),(s['flight_width_m']+.025,.035,.018),'White')
            last_end=s['first_tread_y']+13*s['tread_m']+s['tread_m']/2
            bridge_end=s['bounds'][3]+.025
            if bridge_end>last_end:
                stairs.box((s['center_x'],(last_end+bridge_end)/2,ff+FLOOR_HEIGHT-.06),
                    (s['flight_width_m'],bridge_end-last_end,.12),'Oak')
            for side in(-1,1):
                x=s['center_x']+side*.515
                for j in range(0,s['risers'],2):
                    y=s['first_tread_y']+j*s['tread_m'];z=ff+(j+1)*s['riser_m']
                    stairs.rod((x,y,z),(x,y,z+.88),.018,'Iron',n=6)
                stairs.rod((x,s['first_tread_y'],ff+s['riser_m']+.9),(x,s['first_tread_y']+13*s['tread_m'],ff+FLOOR_HEIGHT+.9),.032,'Oak',n=8)
            flush(stairs,.005,role='functional_stair')
        if n>0:
            guards=Batch(ident+f'_L{n:02d}_ShaftGuard',levelc,origin,angle);a,b,c,e=plan['core']['bounds']
            api['railing'](guards,(a,b),(c,b),ff+.02,.9)
            if 'nave_void' in f:
                q=f['nave_void'];api['railing'](guards,(q[0],q[1]),(q[2],q[1]),ff+.02,.9)
            flush(guards,.004,role='stair_and_gallery_guard')
        for room in f['rooms']:
            rc=coll(room['id'],levelc);rc['purpose']=room['purpose'];rc['bounds_local_m']=room['bounds_m'];rc['room_id']=room['id']
            a,b,c,e=room['bounds_m'];finish=Batch(room['id']+'_Finish',rc,origin,angle)
            if room['purpose'] not in ('protected vertical circulation',):
                finish.box(((a+c)/2,(b+e)/2,ff+.006),(max(.01,c-a-.025),max(.01,e-b-.025),.012),room['finish'])
            flush(finish,.002,room['id'],'floor_finish')
            for asset in room['assets']:
                build_asset(api,asset,rc,world,angle,ff,room['id'],all_objects);asset_count+=1
            if room['assets']:
                decor=Batch(room['id']+'_Decor',rc,origin,angle)
                # A hanging task/room light, an original framed composition,
                # switch plate and skirting supply tertiary scale without
                # consuming the protected floor circulation strip.
                cx,cy=(a+c)/2,(b+e)/2;top=ff+(2.60 if n<floors-1 else 2.34)
                decor.rod((cx,cy,top),(cx,cy,top-.32),.009,'Iron',n=6)
                decor.rod((cx,cy,top-.39),(cx,cy,top-.25),.16,'Sage',n=12,r2=.055)
                decor.rod((cx,cy,top-.405),(cx,cy,top-.39),.10,'Lamp',n=12)
                # Art is on an internal/front room edge below generic windows.
                decor.box((a+.09,(b+e)/2,ff+1.55),(.055,min(.65,(e-b)*.35),.48),'Oak')
                decor.box((a+.055,(b+e)/2,ff+1.55),(.025,min(.55,(e-b)*.30),.38),'Linen')
                decor.box((a+.035,(b+e)/2-.12,ff+1.59),(.012,.12,.14),'BluePaint')
                decor.box((a+.035,(b+e)/2+.10,ff+1.49),(.012,.15,.11),'Sage')
                decor.box((c-.09,b+.16,ff+1.18),(.035,.09,.14),'White')
                decor.box((c-.115,b+.16,ff+1.18),(.012,.025,.055),'Zinc')
                flush(decor,.003,room['id'],'surface_detail')
    plan['room_count']=sum(len(f['rooms']) for f in plan['levels'])
    plan['furnishing_count']=asset_count;plan['object_names']=all_objects
    plan['stair_flights']=max(0,floors-1)
    # Root manifest contract: floors is the actual list, floor_count its
    # declared count. The standalone planning file retains the compact count.
    return {**plan,'floor_count':floors,'floors':plan['levels'],
        'rooms':[{**r,'level':f['level']} for f in plan['levels'] for r in f['rooms']]}


def build_asset(api,asset,parent,world,angle,ff,room_id,object_names):
    x,y=asset['center_m'];w,d,h=asset['dimensions_m'];typ=asset['kind'];accent=asset['accent']
    b=api['Batch'](asset['id'],parent,world(x,y,ff),angle+math.radians(asset.get('rotation_degrees',0)))
    def box(x,y,z,w,d,h,mat):b.box((x,y,z),(w,d,h),mat)
    def legs(width=w,depth=d,height=.72):
        for xx in(-width/2+.09,width/2-.09):
            for yy in(-depth/2+.09,depth/2-.09):b.rod((xx,yy,.04),(xx,yy,height),.025,'Oak',n=6)
    if typ=='bed':
        box(0,0,.20,w,d,.30,'Oak');box(0,0,.42,w-.05,d-.06,.17,'White');box(0,-.10,.52,w-.08,d*.72,.10,accent)
        box(0,d/2-.14,.60,w,.10,.75,'Oak')
        for xx in(-w*.23,w*.23):box(xx,d*.32,.55,w*.40,.34,.13,'Linen')
        for j in range(4):box(0,-d*.27+j*.12,.578,w*.84,.018,.012,'Linen')
    elif typ in('sofa','banquette','lounge_chair'):
        box(0,0,.24,w,d,.34,accent);box(0,-.02,.46,w-.10,d-.12,.14,accent)
        box(0,d*.40,.68,w,.12,.53,accent)
        for xx in(-w/2+.07,w/2-.07):box(xx,0,.57,.14,d,.25,accent)
        for xx in(-w*.23,w*.23):box(xx,d*.22,.65,w*.30,.15,.32,'Linen')
    elif typ in('bookshelf','grocery_shelf','storage_rack','bread_rack','tool_rack','cupboard','wardrobe','linen_cabinet','lockers','wall_tool_cabinet'):
        closed=typ in('cupboard','wardrobe','linen_cabinet','lockers','wall_tool_cabinet')
        box(0,d/2-.025,h/2,w,.05,h,'Oak')
        for xx in(-w/2+.025,w/2-.025):box(xx,0,h/2,.05,d,h,'Oak')
        rows=max(2,int(h/.38))
        for j in range(rows+1):box(0,0,.08+j*(h-.13)/rows,w,d,.045,'Oak')
        if closed:
            for xx in(-w*.25,w*.25):
                box(xx,-d/2-.008,h/2,w*.46,.035,h-.08,accent);b.rod((xx+w*.12,-d/2-.04,h*.48),(xx+w*.12,-d/2-.04,h*.55),.012,'Brass',n=6)
        else:
            for j in range(rows):
                for k in range(max(2,int(w/.13))):
                    xx=-w/2+.10+k*.13;z=.14+j*(h-.13)/rows
                    if typ=='bookshelf':box(xx,-.025,z+.12,.085,d*.72,.22,('Sage','Burgundy','BluePaint','Linen')[k%4])
                    elif typ=='bread_rack':b.ellipsoid((xx,-.015,z+.10),(.09,.14,.07),'Oak',n=8,rings=4)
                    elif typ=='tool_rack':b.rod((xx,-d/2,z),(xx,-d/2,z+.20),.018,'Iron',n=6)
                    else:box(xx,-.015,z+.09,.10,d*.70,.16,('Sage','Linen','Oak')[k%3])
    elif typ=='task_stool':
        b.rod((0,0,.43),(0,0,.48),min(w,d)*.48,'Oak',n=12)
        for xx in(-w*.26,w*.26):
            for yy in(-d*.26,d*.26):b.rod((xx,yy,.04),(xx,yy,.43),.022,'Oak',n=6)
    elif typ=='dining_table':
        # Seating belongs to the assembly's full 1.00 x 1.15m proxy.
        # The narrow table permits two genuinely modeled backless stools.
        tw,td=w-.06,.60
        legs(tw,td,.72);box(0,0,.76,tw,td,.08,'Oak')
        for yy in(-.36,.36):
            b.rod((0,yy,.43),(0,yy,.48),.18,'Oak',n=12)
            for xx in(-.11,.11):
                for dy in(-.10,.10):b.rod((xx,yy+dy,.03),(xx,yy+dy,.43),.022,'Oak',n=6)
        box(-w*.22,0,.82,.20,.18,.025,'Linen')
    elif typ=='sewing_table':
        legs(w,.50,.72);box(0,.18,.76,w,.50,.08,'Oak')
        box(-w*.13,.17,.85,.32,.20,.11,'Iron');box(-w*.20,.17,.98,.10,.10,.22,'Iron')
        box(-w*.08,.17,1.08,.28,.10,.06,'Iron');b.rod((w*.02,.17,.80),(w*.02,.17,1.05),.012,'Zinc',n=6)
        box(w*.25,.19,.82,.23,.25,.025,'Linen')
        b.rod((0,-.27,.43),(0,-.27,.48),.17,'Oak',n=12)
        for xx in(-.10,.10):
            for yy in(-.37,-.17):b.rod((xx,yy,.03),(xx,yy,.43),.022,'Oak',n=6)
    elif typ in('writing_desk','reading_table','meeting_table','coffee_table','retail_counter','cafe_counter','service_console','workbench','altar','bench'):
        height=.43 if typ in('bench','coffee_table') else (.76 if 'table' in typ or typ=='writing_desk' else h-.08)
        legs(height=height);box(0,0,height,w,d,.09,'Granite' if typ in('workbench','altar') else 'Oak')
        if typ=='retail_counter':box(0,0,height/2,w-.08,d-.08,height,'Oak');box(0,0,height+.10,w-.08,d-.08,.12,'Glass')
        if typ=='cafe_counter':
            box(0,0,.48,w-.06,d-.06,.91,'Oak')
            for j in range(max(2,int(w/.48))):
                xx=-w/2+.27+j*.48
                if xx+w*.02<w/2-.10:box(xx,-d/2-.025,.49,.38,.04,.65,'Sage');box(xx,-d/2-.05,.49,.28,.015,.53,'Oak')
            box(0,0,1.04,w+.025,d+.025,.09,'Granite')
            box(-w*.25,0,1.21,w*.40,d*.74,.30,'Glass')
            for j in range(4):b.ellipsoid((-w*.38+j*.11,0,1.13),(.05,.075,.045),'Terracotta',n=8,rings=4)
            for xx in(w*.15,w*.32):b.rod((xx,0,1.09),(xx,0,1.20),.05,'White',n=10)
        if typ in('writing_desk','reading_table','meeting_table'):
            box(-w*.15,0,height+.065,.30,.22,.035,'Linen');box(-w*.10,.02,height+.09,.26,.18,.028,'BluePaint')
            b.rod((w*.24,d*.10,height+.05),(w*.24,d*.10,height+.40),.018,'Brass',n=8)
            b.rod((w*.24,d*.10,height+.35),(w*.24,d*.10,height+.44),.10,'Sage',n=10,r2=.035)
        if typ=='workbench':
            for k in range(4):box(-w*.3+k*w*.2,0,height+.07,.08,.20,.08,'Zinc')
    elif typ=='cafe_table_set':
        api['table'](b,0,0,0,.34,False)
        for xx,rot in((-.43,math.pi/2),(.43,-math.pi/2)):api['chair'](b,xx,0,0,rot)
        box(-.12,.06,.82,.18,.12,.025,'Linen')
    elif typ=='kitchen_run':
        # Hollow carcass and four counter pieces leave an actual sink hole.
        # No solid base or stone plate fills the recessed ceramic bowl.
        box(0,d/2-.025,.43,w,.05,.86,'Oak');box(0,0,.085,w,d,.055,'Oak')
        for xx in(-w/2+.025,w/2-.025,w*.08):box(xx,0,.43,.05,d,.86,'Oak')
        sx=-w*.30;sw=w*.25;sd=d*.52;sy=.025
        a,c=sx-sw/2,sx+sw/2;bb,e=sy-sd/2,sy+sd/2
        for xa,xb,ya,yb in((-w/2,a,-d/2,d/2),(c,w/2,-d/2,d/2),(a,c,-d/2,bb),(a,c,e,d/2)):
            box((xa+xb)/2,(ya+yb)/2,.90,xb-xa,yb-ya,.07,'Granite')
        box(sx,sy,.765,sw,sd,.028,'White')
        for xx in(a+.015,c-.015):box(xx,sy,.835,.03,sd,.14,'White')
        for yy in(bb+.015,e-.015):box(sx,yy,.835,sw,.03,.14,'White')
        b.rod((sx,sy,.780),(sx,sy,.788),.025,'Zinc',n=12)
        b.rod((sx,e+.045,.925),(sx,e+.045,1.12),.016,'Zinc',n=8)
        b.rod((sx,e+.045,1.12),(sx,sy,1.12),.016,'Zinc',n=8)
        b.rod((sx,sy,1.12),(sx,sy,1.075),.016,'Zinc',n=8)
        # Left cabinet doors, central two-ring hob, and a distinct cool box.
        box(-w*.245,-d/2+.005,.44,w*.46,.025,.70,accent)
        b.rod((-w*.29,-d/2-.025,.70),(-w*.20,-d/2-.025,.70),.012,'Brass',n=6)
        for yy in(-d*.18,d*.18):b.rod((0,yy,.94),(0,yy,.952),.073,'Iron',n=14)
        fw=w*.31;fx=w*.31
        box(fx,0,.455,fw,d-.07,.77,'Zinc')
        box(fx,-d/2-.006,.455,fw-.025,.035,.75,'White')
        for zz in(.19,.68):box(fx,-d/2-.026,zz,fw-.055,.008,.012,'Zinc')
        b.rod((fx+fw*.31,-d/2-.045,.46),(fx+fw*.31,-d/2-.045,.66),.014,'Zinc',n=8)
        box(fx,-d/2-.028,.76,.10,.006,.035,'BluePaint')
    elif typ in('cooker','oven','coffee_machine'):
        box(0,0,.43,w,d,.86,'Oak');box(0,0,.90,w+.02,d+.025,.07,'Granite')
        for xx in(-w*.25,w*.25):
            box(xx,-d/2-.01,.43,w*.46,.025,.76,accent);b.rod((xx-.08,-d/2-.045,.70),(xx+.08,-d/2-.045,.70),.012,'Brass',n=6)
        if typ=='coffee_machine':
            box(0,.03,1.15,w*.78,d*.68,.43,'Zinc');box(0,-d*.33,1.15,w*.69,.03,.22,'Ink')
            for xx in(-w*.2,w*.2):b.rod((xx,-d*.38,1.05),(xx,-d*.38,1.20),.045,'Brass',n=8);b.rod((xx,d*.12,1.38),(xx,d*.12,1.50),.06,'White',n=10)
        else:
            for xx in(-w*.22,w*.22):
                for yy in(-d*.18,d*.18):b.rod((xx,yy,.94),(xx,yy,.952),.08,'Iron',n=14)
            b.rod((w*.24,d*.16,.95),(w*.24,d*.16,1.12),.11,'Brass',n=12)
        if typ=='oven':box(0,-d/2-.025,.50,w*.70,.03,.40,'Ink')
    elif typ in('basin','toilet','bathtub','shower_screen'):
        if typ=='toilet':
            b.ellipsoid((0,-d*.10,.38),(w*.43,d*.35,.32),'White',n=12,rings=6);box(0,d*.30,.53,w*.8,d*.25,.45,'White')
            b.rod((0,-d*.1,.65),(0,-d*.1,.67),w*.32,'Ink',n=16);b.rod((0,-d*.1,.668),(0,-d*.1,.678),w*.39,'White',n=16)
        elif typ=='bathtub':
            box(0,0,.32,w,d,.55,'White');box(0,0,.61,w-.14,d-.14,.025,'Shallows')
            for yy in(-d/2+.035,d/2-.035):box(0,yy,.62,w,.07,.07,'White')
            b.rod((-w*.32,d*.25,.63),(-w*.32,d*.25,.82),.018,'Zinc',n=8)
        elif typ=='basin':
            box(0,0,.42,w*.86,d*.82,.80,'Oak');box(0,0,.85,w,d,.12,'White');box(0,0,.92,w*.65,d*.52,.018,'Shallows')
            b.rod((0,d*.35,.91),(0,d*.35,1.06),.018,'Zinc',n=8)
        else:
            box(0,0,.05,w,d,.10,'White')
            for xx in(-w/2+.025,w/2-.025):box(xx,0,1.02,.035,d,1.95,'Glass');b.rod((xx,d/2,0),(xx,d/2,2.05),.018,'Zinc',n=8)
            b.rod((0,d/2-.06,1.2),(0,d/2-.06,1.95),.018,'Zinc',n=8);b.rod((0,d/2-.13,1.95),(0,d/2-.23,1.95),.07,'Zinc',n=12)
    elif typ in('crate_stack','sacks','market_stall'):
        if typ=='sacks':
            for xx in(-w*.22,w*.22):b.ellipsoid((xx,0,h*.45),(w*.27,d*.42,h*.45),'Linen',n=10,rings=6)
        elif typ=='market_stall':
            legs(height=.80);box(0,0,.84,w,d,.10,'Oak')
            for j in range(6):b.ellipsoid((-w*.35+j*w*.13,0,.99),(.12,.15,.12),('LeafLight','Terracotta','Linen')[j%3],n=8,rings=4)
        else:
            for z in(.2,.62):
                box(0,0,z,w,d,.38,'Oak')
                for yy in(-d/2-.008,d/2+.008):
                    for zz in(-.12,.12):box(0,yy,z+zz,w,.018,.035,'White')
    elif typ=='pew':
        legs(height=.45);box(0,0,.47,w,d,.09,'Oak');box(0,d*.38,.72,w,.08,.50,'Oak')
    elif typ in('organ','mill_mechanism','music_stand'):
        if typ=='organ':
            box(0,0,.50,w,d,1.0,'Oak')
            for j in range(9):b.rod((-w*.4+j*w*.1,d*.20,.80),(-w*.4+j*w*.1,d*.20,1.35+abs(j-4)*.06),.035,'Zinc',n=8)
            for j in range(12):box(-w*.42+j*w*.075,-d*.38,.85,.06,.20,.03,'White')
        elif typ=='mill_mechanism':
            b.rod((0,0,.06),(0,0,.48),w*.46,'Granite',n=20);b.rod((0,0,.48),(0,0,1.55),.10,'Oak',n=12)
            b.rod((0,0,.57),(0,0,.72),w*.39,'Oak',n=20)
            for j in range(12):
                a=j*math.tau/12;b.box((math.cos(a)*w*.4,math.sin(a)*w*.4,.65),(.12,.12,.15),'Oak',a)
        else:b.rod((0,0,.03),(0,0,1.0),.03,'Iron',n=8);box(0,0,1.12,w,d,.035,'Oak')
    else:
        box(0,0,h/2,w,d,h,'Oak');box(0,-d/2-.01,h*.55,w*.8,.02,h*.70,accent)
    objects=b.flush(.008)
    for ob in objects:
        ob['interior_building_id']=room_id.split('_L')[0]
        ob['interior_asset_id']=asset['id'];ob['interior_room_id']=room_id;ob['asset_role']=typ
        ob['collision_proxy_local_xy']=asset['footprint_m'];ob['reusable_asset']=True
        ob['furniture_rotation_degrees']=asset.get('rotation_degrees',0)
        ob['furniture_front_building_xy']=rotated_xy(0,-1,asset.get('rotation_degrees',0))
        if asset.get('integrated_fixtures'):ob['integrated_fixtures']=json.dumps(asset['integrated_fixtures'])
        if asset.get('integrated_seating'):ob['integrated_seating']=asset['integrated_seating']
    object_names.extend(o.name for o in objects)
    asset['object_names']=[o.name for o in objects]


def write_plan():
    master=json.loads((ROOT/'masterplan.json').read_text(encoding='utf-8'))
    buildings=[plan_for_building(b['id'],b['width'],b['depth'],b['floors'],b['kind']) for b in master['buildings']]
    record={'schema':'living_town.detailed_interiors.v1','masterplan_sha256':hashlib.sha256((ROOT/'masterplan.json').read_bytes()).hexdigest(),
        'authority':'Current user request for purposeful room segmentation, circulation and fine interior detail.',
        'building_count':len(buildings),'floor_count':sum(b['floors'] for b in buildings),
        'room_count':sum(len(f['rooms']) for b in buildings for f in b['levels']),
        'furnishing_count':sum(len(r['assets']) for b in buildings for f in b['levels'] for r in f['rooms']),
        'buildings':buildings,'construction':{'partition_m':WALL,'default_door_gap_m':DOOR,'hall_nominal_zone_width_m':HALL,
        'hall_width_note':'Zone widths are measured between partition centerlines; .12m walls reduce a two-wall 1.10m hall to .98m net, and a nominal 1.20m entrance spine to 1.08m net.',
        'floor_spacing_m':FLOOR_HEIGHT,'ground_finished_floor_local_z_m':.38,'equal_risers_per_storey':14},
        'limits':['New offline interior proposals, not existing runtime Spaces.','Door/passage clearances are authored dimensions, not code or accessibility certification.','Reusable semantic geometry and collision proxies support future engine preparation; no engine integration is claimed.']}
    (ROOT/'interior_plan.json').write_text(json.dumps(record,indent=2),encoding='utf-8',newline='\n')
    audit=audit_plan(record)
    evidence=ROOT/'evidence';evidence.mkdir(exist_ok=True)
    (evidence/'interior_planning_audit.json').write_text(json.dumps(audit,indent=2),encoding='utf-8',newline='\n')
    print(json.dumps({k:record[k] for k in('building_count','floor_count','room_count','furnishing_count')},indent=2))
    print(json.dumps({'planning_audit':audit['status'],'failures':len(audit['failures']),'rooms_tested':audit['room_zones_tested']}))
    return record


def essential_requirements(purpose):
    """Purpose-specific minimums. A decorative fallback cannot satisfy these.

    Counts describe usable assemblies, not mesh-object or decorative counts.
    Unknown activity programs deliberately fail rather than silently inheriting
    a desk/cupboard. Integrated sink and seating recipes are audited separately.
    """
    def need(label,*kinds,count=1):return {'label':label,'kinds':list(kinds),'minimum':count}
    if any(k in purpose for k in('circulation','landing','vertical','access')):return []
    if purpose=='crossed public market aisles':return [need('eight produce booths','market_stall',count=8)]
    if any(k in purpose for k in('bedroom','guest room')):
        out=[need('sleeping place','bed'),need('clothing storage','wardrobe')]
        if 'artist study' in purpose:out.extend([need('study work surface','writing_desk'),need('study seat','task_stool')])
        if 'living' in purpose:out.append(need('living seat','sofa'))
        return out
    if purpose=='compact staff WC':return [need('toilet','toilet'),need('handwash basin','basin')]
    if any(k in purpose for k in('bathroom','wash locker','staff wash','shower','bath washing')):
        out=[need('toilet','toilet'),need('handwash basin','basin')]
        out.append(need('bathing fixture','bathtub','shower_screen',count=2 if purpose=='individual shower cubicles' else 1))
        out.append(need('personal storage','lockers' if 'locker' in purpose else 'linen_cabinet'))
        return out
    if any(k in purpose for k in('kitchen','preparation','coffee')):
        out=[need('food or wash preparation run','kitchen_run')]
        if 'bakery' in purpose:out.extend([need('baking oven','oven'),need('bread cooling rack','bread_rack')])
        elif 'coffee' in purpose:out.append(need('coffee machine','coffee_machine'))
        elif 'crepe' in purpose:out.append(need('crepe cooker','cooker'))
        else:out.append(need('seated dining or staff table','dining_table'))
        if 'living' in purpose:out.append(need('domestic living seat','sofa'))
        return out
    if any(k in purpose for k in('cafe dining','creperie dining','breakfast lounge')):
        out=[need('seated public tables','cafe_table_set',count=4 if purpose=='cafe dining' else 2),need('banquette seat','banquette')]
        if purpose=='cafe dining':out.append(need('service counter','cafe_counter'))
        return out
    if purpose in('grocery sales','bakery retail'):
        out=[need('sales counter','retail_counter'),need('goods display','grocery_shelf')]
        if purpose=='bakery retail':out.append(need('bread display','bread_rack'))
        return out
    if any(k in purpose for k in('book stacks','archive','reference')):return [need('document shelving','bookshelf',count=2)]
    if purpose=='artist study guest room':raise AssertionError('Handled by bedroom program')
    if any(k in purpose for k in('reading','study','office','registry','reception','meeting','council','planning')):
        if 'meeting' in purpose or 'council' in purpose:return [need('meeting table','meeting_table'),need('meeting seats','lounge_chair',count=2)]
        table='reading_table' if 'reading' in purpose or 'quiet' in purpose else 'writing_desk'
        out=[need('work or reading surface',table),need('staff or visitor seat','lounge_chair')]
        if purpose=='linen staff office':out.append(need('closed linen storage','linen_cabinet'))
        return out
    if purpose in('living room','public waiting'):return [need('seating','sofa'),need('occasional table','coffee_table')]
    if purpose=='changing lockers':return [need('changing lockers','lockers',count=2),need('changing bench','bench')]
    if purpose=='chapel nave pews altar':return [need('congregation seating','pew',count=4),need('altar','altar')]
    if purpose=='chapel music and choir gallery':return [need('organ','organ'),need('choir bench','bench'),need('music stand','music_stand')]
    if purpose in('grain milling equipment','mill drive mechanism'):return [need('milling mechanism','mill_mechanism')]
    if purpose in('repair workshop','net repair bench','mill maintenance workbench','packing benches'):
        return [need('working bench','workbench'),need('working tools','tool_rack')]
    if purpose=='linen storage and sewing':return [need('sewing work surface and seat','sewing_table'),need('linen shelving','storage_rack')]
    if purpose in('grocery stock room','canning equipment store','cargo receiving','dry rack storage','hand tools storage',
        'net and rope storage','rope crate store','sack and hand tool storage','tool material store','vestry and ceremonial storage'):
        return [need('program storage','storage_rack')]
    return None


def audit_plan(record):
    """Conservative plan-only pedestrian test; independent of mesh counts."""
    failures=[];tested=0;step=.12;radius=.25;activity_rooms=0;stairs=0;essential=[]
    entrances=[];sleeping_boundaries=[];privacy=[]
    for b in record['buildings']:
        stairs+=max(0,b['floors']-1)
        for f in b['levels']:
            xmin,ymin,xmax,ymax=b['clear_bounds_m'];xmin+=radius;ymin+=radius;xmax-=radius;ymax-=radius
            blocks=[]
            for p in f['partitions']:
                lo,hi=p['span_m'];last=lo
                for o in sorted([q for q in p['openings'] if q['kind']=='door'],key=lambda q:q['center_m'])+[{'center_m':hi,'width_m':0}]:
                    end=o['center_m']-o['width_m']/2
                    if end>last:
                        co=p['coordinate_m']
                        blocks.append([co-.06-radius,last-radius,co+.06+radius,end+radius] if p['axis']=='x' else[last-radius,co-.06-radius,end+radius,co+.06+radius])
                    last=o['center_m']+o['width_m']/2
            if b['core']:
                a,bb,c,e=b['core']['bounds'];blocks.append([a-radius,bb-radius,c+radius,e+radius])
            if f.get('nave_void'):
                a,bb,c,e=f['nave_void'];blocks.append([a-radius,bb-radius,c+radius,e+radius])
            for r in f['rooms']:
                a,bb,c,e=r['bounds_m'];occupied=[]
                if c<=a or e<=bb:failures.append({'room':r['id'],'reason':'non-positive room bounds'})
                if ('bedroom' in r['purpose'] or 'guest room' in r['purpose'] or
                    'bathroom' in r['purpose'] or any(q['kind'] in ('toilet','bathtub','shower_screen') for q in r['assets'])):
                    # Room labels and exterior contact cannot establish privacy.
                    # Prove every interior edge has actual full-height partition
                    # spans, with only authored door apertures interrupting them.
                    edge_checks=[];sx0,sy0,sx1,sy1=b['clear_bounds_m']
                    for axis,co,lo,hi,shell in (('x',a,bb,e,sx0),('x',c,bb,e,sx1),('y',bb,a,c,sy0),('y',e,a,c,sy1)):
                        if abs(co-shell)<.001:
                            edge_checks.append({'axis':axis,'coordinate_m':co,'span_m':[lo,hi],
                                'boundary':'exterior shell','pass':True});continue
                        parts=[p for p in f['partitions'] if p['axis']==axis and abs(p['coordinate_m']-co)<.001 and
                            p['height_m']>=2.08 and min(hi,p['span_m'][1])-max(lo,p['span_m'][0])>.001]
                        spans=sorted((max(lo,p['span_m'][0]),min(hi,p['span_m'][1])) for p in parts)
                        uncovered=[];last=lo
                        for L,H in spans:
                            if L>last+.001:uncovered.append([last,L])
                            last=max(last,H)
                        if last<hi-.001:uncovered.append([last,hi])
                        doors=[{'center_m':o['center_m'],'width_m':o['width_m']} for p in parts for o in p['openings']
                            if o['kind']=='door' and lo<o['center_m']<hi]
                        non_door_openings=[o for p in parts for o in p['openings'] if o['kind']!='door' and
                            min(hi,o['center_m']+o['width_m']/2)>max(lo,o['center_m']-o['width_m']/2)]
                        passed=not uncovered and not non_door_openings
                        edge_checks.append({'axis':axis,'coordinate_m':co,'span_m':[lo,hi],
                            'boundary':'partition with authored door apertures','partition_spans_m':spans,
                            'door_apertures':doors,'uncovered_spans_m':uncovered,'pass':passed})
                    passed=all(q['pass'] for q in edge_checks)
                    privacy.append({'room':r['id'],'purpose':r['purpose'],'edges':edge_checks,'pass':passed})
                    if not passed:failures.append({'room':r['id'],'reason':'sleeping or sanitary room has an unenclosed interior edge'})
                functional=not any(k in r['purpose'] for k in('circulation','landing','vertical','access'))
                if functional:
                    activity_rooms+=1
                    if not r['assets']:failures.append({'room':r['id'],'reason':'purposeful room has no fixture'})
                    if 'bedroom' in r['purpose'] and not any(q['kind']=='bed' for q in r['assets']):failures.append({'room':r['id'],'reason':'bedroom has no bed'})
                    if r['purpose']=='compact staff WC' and not {'toilet','basin'}<=set(q['kind'] for q in r['assets']):failures.append({'room':r['id'],'reason':'staff WC lacks toilet or basin'})
                    specs=essential_requirements(r['purpose']);checks=[]
                    if specs is None:failures.append({'room':r['id'],'reason':'activity purpose lacks an explicit essential fixture specification'})
                    for spec in specs or []:
                        count=sum(q['kind'] in spec['kinds'] for q in r['assets']);passed=count>=spec['minimum']
                        checks.append({**spec,'actual':count,'pass':passed})
                        if not passed:failures.append({'room':r['id'],'reason':'missing essential '+spec['label'],'required':spec['minimum'],'actual':count})
                    for q in r['assets']:
                        if q['kind']=='kitchen_run':
                            passed={'recessed_sink','tap','hob','undercounter_fridge'}<=set(q.get('integrated_fixtures',[]))
                            checks.append({'label':'kitchen sink, tap, hob and fridge recipe','pass':passed})
                            if not passed:failures.append({'asset':q['id'],'reason':'kitchen run lacks essential integrated fixture recipe'})
                        if q['kind']=='dining_table':
                            passed=q.get('integrated_seating',0)>=2 and q['dimensions_m'][1]>=1.15
                            checks.append({'label':'two dining seats inside assembly proxy','pass':passed})
                            if not passed:failures.append({'asset':q['id'],'reason':'dining table lacks two contained seats'})
                    essential.append({'room':r['id'],'purpose':r['purpose'],'checks':checks,'pass':specs is not None and all(q['pass'] for q in checks)})
                    if 'bedroom' in r['purpose'] or 'guest room' in r['purpose']:
                        x0,y0,x1,y1=b['clear_bounds_m']
                        exterior_lengths=[e-bb if abs(a-x0)<1e-5 else 0,e-bb if abs(c-x1)<1e-5 else 0,
                            c-a if abs(bb-y0)<1e-5 else 0,c-a if abs(e-y1)<1e-5 else 0]
                        passed=max(exterior_lengths)>=1.20
                        sleeping_boundaries.append({'room':r['id'],'exterior_contact_lengths_m':exterior_lengths,'pass':passed})
                        if not passed:failures.append({'room':r['id'],'reason':'sleeping room has no usable exterior boundary'})
                for q in r['assets']:
                    x,y,X,Y=q['footprint_m']
                    if x<a-.001 or X>c+.001 or y<bb-.001 or Y>e+.001:failures.append({'asset':q['id'],'reason':'fixture outside room'})
                    if any(intersects(q['footprint_m'],z) for z in occupied):failures.append({'asset':q['id'],'reason':'fixture footprint overlap'})
                    if any(intersects(q['footprint_m'],z) for z in r['circulation_keepouts']):failures.append({'asset':q['id'],'reason':'fixture crosses circulation reserve'})
                    occupied.append(q['footprint_m']);blocks.append([x-radius,y-radius,X+radius,Y+radius])
            nx=int((xmax-xmin)/step)+1;ny=int((ymax-ymin)/step)+1;free=set()
            for iy in range(ny):
                y=ymin+iy*step
                for ix in range(nx):
                    x=xmin+ix*step
                    if not any(a<x<c and bb<y<e for a,bb,c,e in blocks):free.add((ix,iy))
            if not free:failures.append({'building':b['id'],'level':f['level'],'reason':'no pedestrian clearance'});continue
            desired=(b.get('entrance_local_m',[0,0])[0],ymin+.05) if f['level']==0 else(b['core']['center_x'],b['core']['bounds'][3]+.35)
            if f['level']==0:
                # A nearest-free search can jump around a partition placed on
                # the actual facade-door axis. Test the real entrance sweep
                # and its exact raster seed before traversing the interior.
                doorx=desired[0];shell_y=b['clear_bounds_m'][1]
                sweep=[(doorx,shell_y+radius+i*.05) for i in range(11)]
                blocked=[p for p in sweep if any(a<p[0]<c and bb<p[1]<e for a,bb,c,e in blocks)]
                seed=(round((desired[0]-xmin)/step),round((desired[1]-ymin)/step))
                passed=not blocked and seed in free
                entrances.append({'building':b['id'],'entrance_local_m':[doorx,shell_y],
                    'tested_centerline_length_m':.50,'pedestrian_diameter_m':radius*2,
                    'blocked_sweep_samples':len(blocked),'exact_raster_seed_free':seed in free,'pass':passed})
                if not passed:
                    failures.append({'building':b['id'],'level':0,'reason':'actual entrance axis or exact interior seed is blocked'})
                    continue
            else:
                seed=min(free,key=lambda q:(xmin+q[0]*step-desired[0])**2+(ymin+q[1]*step-desired[1])**2)
            reached={seed};queue=deque([seed])
            while queue:
                ix,iy=queue.popleft()
                for q in((ix+1,iy),(ix-1,iy),(ix,iy+1),(ix,iy-1)):
                    if q in free and q not in reached:reached.add(q);queue.append(q)
            for r in f['rooms']:
                if r['purpose']=='protected vertical circulation':continue
                a,bb,c,e=r['bounds_m'];tested+=1
                if not any(a<xmin+q[0]*step<c and bb<ymin+q[1]*step<e for q in reached):
                    failures.append({'room':r['id'],'reason':'not reachable by .50m pedestrian from entrance/upper landing'})
    composition=audit_furniture_compositions(record)
    failures.extend(composition['failures'])
    return {'schema':'living_town.interior_planning_audit.v3','status':'PASS' if not failures else'FAIL',
        'interior_plan_sha256':hashlib.sha256(json.dumps(record,indent=2).encode('utf-8')).hexdigest(),
        'interior_module_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'building_count':len(record['buildings']),'floor_count':record['floor_count'],'room_zones_tested':tested,
        'purposeful_activity_rooms':activity_rooms,'stair_flights':stairs,'cell_m':step,'pedestrian_diameter_m':radius*2,
        'essential_activity_rooms_tested':len(essential),'essential_fixture_requirements_tested':sum(len(q['checks']) for q in essential),
        'essential_fixture_coverage':essential,
        'entrance_threshold_checks':entrances,'sleeping_room_exterior_boundary_checks':sleeping_boundaries,
        'privacy_enclosure_rooms_tested':len(privacy),'privacy_enclosure_checks':privacy,
        'furniture_composition':composition,
        'door_width_min_m':min(o['width_m'] for b in record['buildings'] for f in b['levels'] for p in f['partitions'] for o in p['openings'] if o['kind']=='door'),
        'limits':'Plan footprint, exact interior entrance-axis and partition-edge enclosure tests; exterior contact is not proof of a native window/daylight. Native doors, meshes and final visuals require separate evidence.','failures':failures}


if __name__=='__main__':write_plan()
