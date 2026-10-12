"""Original landscape enclosure, architectural accents and camera movement.

Builds through the coordinator's metric mesh API. No masterplan or terrain edits.
"""
import math
import random
import json
import importlib.util


def enrich_environment(api, plan, route_clear, parcel_clear):
    Batch, coll, tree, pot, roof = [api[k] for k in ('Batch','coll','tree','pot','gable_roof')]
    ground, WORLD, VEG, PROPS, MATS = [api[k] for k in ('ground_z','WORLD','VEG','PROPS','MATS')]
    rng=random.Random(971126)
    landscape=coll('05_Landscape_Detail')
    planting=Batch('Layered_Street_and_Orchard_Planting',landscape)
    boundaries=Batch('Bocage_Field_Walls_and_Hedges',landscape)
    structures=Batch('Garden_Outbuildings',landscape)
    detail=Batch('Coastal_And_Facade_Detail',landscape)
    counts={'added_trees':0,'hedge_segments':0,'garden_sheds':0,'field_walls':0,'facade_accents':0}

    def hedge(a,b,height=.95,width=.65,stone=False):
        dist=math.dist(a,b);n=max(1,math.ceil(dist/.55))
        for i in range(n):
            t=(i+.5)/n;x=a[0]+(b[0]-a[0])*t;y=a[1]+(b[1]-a[1])*t
            if not route_clear(x,y,width/2+.3) or not parcel_clear(x,y,width/2+.15):continue
            z=ground(x,y);ang=math.atan2(b[1]-a[1],b[0]-a[0])
            if stone:
                boundaries.box((x,y,z+height*.42),(dist/n+.035,width,height*.84),'Granite',ang)
                boundaries.box((x,y,z+height*.88),(dist/n+.06,width+.09,.12),'Stone',ang)
                counts['field_walls']+=1
            else:
                boundaries.box((x,y,z+.16),(dist/n+.03,width*.72,.32),'Granite',ang)
                for j in range(3):
                    boundaries.ellipsoid((x+rng.uniform(-.18,.18),y+rng.uniform(-.16,.16),z+height*(.55+j*.15)),(.43,width*.65,.32),('LeafDark','Leaf','LeafLight')[j],n=7,rings=4)
                counts['hedge_segments']+=1

    # Irregular wooded margins leave a legible town edge and open approaches.
    # A few short old stone runs replace the former five closed field boxes.
    for a,b in [((-87,-31),(-72,-26)),((-91,8),(-78,16)),((-65,62),(-51,66))]:
        hedge(a,b,.58,.4,stone=True)
    woodland_centres=[(-79,-34),(-83,-10),(-78,14),(-74,44),(-64,65),(-44,67),(-23,70),(0,73)]
    for i in range(80):
        cx,cy=woodland_centres[i//10];a=rng.random()*math.tau;r=math.sqrt(rng.random())*10
        xx=cx+math.cos(a)*r;yy=cy+math.sin(a)*r*.65
        if route_clear(xx,yy,2.4) and parcel_clear(xx,yy,2.5):
            tree(planting,xx,yy,scale=rng.uniform(.65,1.30));counts['added_trees']+=1
    # A distant wooded skyline keeps the town grounded in a larger landscape.
    for i in range(50):
        x=rng.uniform(-145,-96);y=rng.uniform(-75,110)
        tree(planting,x,y,scale=rng.uniform(1,1.65));counts['added_trees']+=1
    for i in range(30):
        x=rng.uniform(-90,30);y=rng.uniform(95,130)
        tree(planting,x,y,scale=rng.uniform(.9,1.5));counts['added_trees']+=1

    # Individual domestic enclosures retain actual gates at verified paths.
    for a in plan['buildings']:
        if a['kind'] in ('halles','cannery','work','netshed','mairie','wash','hotel','chapel','windmill'):continue
        cx,cy=a['center'];w,d=a['width'],a['depth'];ang=math.radians(a['yaw_degrees'])
        def point(x,y):return (cx+x*math.cos(ang)-y*math.sin(ang),cy+x*math.sin(ang)+y*math.cos(ang))
        ly=d/2+2.6
        aa=point(-w*.4,ly);bb=point(w*.4,ly)
        hedge(aa,bb,.9,.6)
        for side in (-1,1):hedge(point(side*w*.43,d/2+.7),point(side*w*.43,ly),.9,.55)
        xx,yy=point(w*.23,d/2+1.6)
        if route_clear(xx,yy,1.5) and parcel_clear(xx,yy,1.6) and counts['garden_sheds']<9:
            local=Batch('Garden_Shed_'+a['id'],landscape,(xx,yy,ground(xx,yy)),ang)
            local.box((0,0,1.05),(2.3,1.75,2.1),'Plaster')
            local.box((-.55,-.89,.95),(.65,.06,1.85),'Sage')
            for dz in (.45,1.35):local.box((-.55,-.94,dz),(.55,.035,.1),'Oak')
            roof(local,2.3,1.75,2.1,.55);local.flush(.012);counts['garden_sheds']+=1
        xx,yy=point(-w*.3,d/2+1.8)
        if route_clear(xx,yy,1.2) and parcel_clear(xx,yy,1.5):
            tree(planting,xx,yy,scale=.6+rng.random()*.2);counts['added_trees']+=1

    # The central square has one large shelter tree; its trunk stays off circulation.
    for x,y,sc in [(-9,4.2,1.15),(-21,18,.8),(16,20,.8),(5,33,.8),(-14,-28,.8),(17,-32,.7)]:
        if route_clear(x,y,.5) and parcel_clear(x,y,.65):
            tree(planting,x,y,scale=sc);counts['added_trees']+=1

    # Scale-readable cornice, flashing and ivy accents, respecting the street face.
    for a in plan['buildings']:
        if a['kind']=='halles':continue
        x,y=a['center'];z=api['TOPO_PADS'][a['id']]['pad_base_z_m'];w,d=a['width'],a['depth'];ang=math.radians(a['yaw_degrees']);h=a['floors']*2.85
        facade=Batch(a['id']+'_Crafted_Accents',api['bpy'].data.collections[a['id']+'_FrontWall'],(x,y,z),ang)
        for zz in (h-.32,h-.19):facade.box((0,-d/2-.20,zz),(w+.24,.14,.055),'Granite')
        if a['kind'] in ('cafe','bakery','library','hotel','creperie'):
            for side in (-1,1):
                sx=side*(w/2-.48);facade.box((sx,-d/2-.24,1.5),(.10,.12,2.0),'Oak')
                for j in range(7):
                    zz=.7+j*.26
                    for k in range(3):
                        px=sx+math.sin(j*1.7+k)*.23;facade.ellipsoid((px,-d/2-.28,zz),(.17,.08,.12),'LeafDark' if k==0 else 'Leaf',n=6,rings=3)
                        if j%2==0:facade.ellipsoid((px,-d/2-.38,zz+.1),(.075,.06,.07),'BloomCream',n=6,rings=3)
        facade.flush(.008);counts['facade_accents']+=1

    # Low stone headland variation and visible wet tidal sand break the straight edge.
    beacon=Batch('Quay_Entrance_Beacon',landscape,(63.8,53.2,api['TERRAIN'].QUAY_Z))
    beacon.rod((0,0,0),(0,0,.5),1.2,'Granite',n=20,r2=1.05)
    beacon.rod((0,0,.5),(0,0,6.0),.74,'White',n=20,r2=.52)
    beacon.rod((0,0,3.9),(0,0,4.65),.62,'Sage',n=20,r2=.59)
    beacon.rod((0,0,6.0),(0,0,6.16),.83,'Granite',n=20)
    beacon.rod((0,0,6.15),(0,0,7.1),.46,'Glass',n=12)
    for i in range(8):
        a=i*math.tau/8;xx=math.cos(a)*.47;yy=math.sin(a)*.47
        beacon.rod((xx,yy,6.12),(xx,yy,7.13),.025,'Iron',n=6)
    beacon.rod((0,0,7.1),(0,0,7.55),.66,'Zinc',n=16,r2=.08)
    beacon.rod((0,0,6.4),(0,0,6.9),.20,'Lamp',n=12)
    beacon.flush(.008);counts['quay_beacon']=1
    for i in range(24):
        yy=rng.uniform(-49,29);xx=api['coast_x'](yy)+rng.uniform(.4,2.4)
        if i%5==0:
            detail.ellipsoid((xx,yy,-.72),(rng.uniform(.25,.7),rng.uniform(.3,.8),rng.uniform(.13,.3)),'DarkStone',n=7,rings=4)
    planting.flush();boundaries.flush(.012);detail.flush(.008)
    spec=importlib.util.spec_from_file_location('living_town_landscape_details',api['ROOT']/'tools/landscape_details.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    landscape_plan=json.loads((api['ROOT']/'landscape_plan.json').read_text(encoding='utf-8'))
    counts['reference_landscape']=module.build_reference_landscape(api,landscape_plan,route_clear,parcel_clear)
    return counts


def camera_movement(api):
    bpy, camera, scene=api['bpy'],api['camera'],api['SCENE']
    beauty=scene.camera
    beauty.data.type='PERSP';beauty.data.lens=54
    from mathutils import Vector
    beauty.location=(115,-162,111)
    beauty.rotation_euler=(Vector((-4,3,3.5))-beauty.location).to_track_quat('-Z','Y').to_euler()
    scene.frame_start=1;scene.frame_end=240;scene.render.fps=24
    move=camera('08_Coastal_Flythrough',(73,-77,32),(23,-32,1.5),lens=40)
    keyframes=[(1,(73,-77,32),(23,-32,1.5)),(80,(67,-22,24),(13,6,4)),(160,(71,23,28),(14,25,4)),(240,(86,61,41),(24,38,3))]
    for frame,pos,target in keyframes:
        move.location=pos;move.rotation_euler=(Vector(target)-move.location).to_track_quat('-Z','Y').to_euler()
        move.keyframe_insert(data_path='location',frame=frame);move.keyframe_insert(data_path='rotation_euler',frame=frame)
    scene.timeline_markers.new('Pond park and coast',frame=1);scene.timeline_markers.new('Town square',frame=80);scene.timeline_markers.new('Hotel turn',frame=160);scene.timeline_markers.new('Working harbor',frame=240)
    scene.frame_set(1);scene.camera=beauty
    return {'camera':move.name,'frames':[1,240],'fps':24,'seconds':10,'keyframes':4,'intent':'Slow exterior coastal dolly; editable presentation rig, separate from game assets.'}
