"""Fitted original facade details for the additive town builder.

No engine import or external assets. The caller supplies its metric Batch and
mesh-lettering callback; the central door and upper-floor openings stay owned
by the building shell. Local frontage is -Y and dimensions are metres.
"""
from __future__ import annotations

import math

COMMERCIAL = {"cafe", "shop", "workshop", "creperie", "bakery"}


def front_opening_spec(building, finished_floor=None):
    """Ground-front *window* apertures, or None for the residential template.

    The caller must both cut these holes and frame/glaze them. Do not retain
    the generic ground-front windows under the large shop bays. The central
    1.04m doorway is deliberately absent from this return value.
    """
    if building["kind"] not in COMMERCIAL:
        return None
    width=float(building["width"])
    floor=float(building.get("finished_floor_offset_m",.38) if finished_floor is None else finished_floor)
    if width<4.8:
        raise ValueError("Commercial front is too narrow for two bays and a 1.04m door")
    bay_width=min(width*.26, width*.57-1.04-.32)
    return [(side*width*.285,floor+1.20,bay_width,1.60) for side in (-1,1)]


def business_label(building):
    district=building.get("district","")
    kind=building["kind"]
    if kind=="cafe":
        return {"D06":"CAFÉ DU RIVAGE","D07":"CAFÉ DE LA PLACE","D09":"CAFÉ DES JARDINS",
                "D10":"CAFÉ DE LA FORÊT"}.get(district,"CAFÉ DES TILLEULS")
    if kind=="shop":
        return {"D06":"ÉPICERIE DU PORT","D07":"LA PETITE ÉPICERIE","D09":"LA PÉPINIÈRE",
                "D10":"MAISON DU RANDONNEUR"}.get(district,"ÉPICERIE DU VILLAGE")
    if kind=="workshop":
        return {"D06":"ATELIER DES VOILES","D07":"ATELIER DES ARTISANS","D09":"ATELIER DU VERGER",
                "D10":"CYCLES DE LA FORÊT"}.get(district,"ATELIER DU VILLAGE")
    return {"creperie":"LA PETITE CRÊPERIE","bakery":"BOULANGERIE DU BOURG"}.get(kind,"")


def add_facade_details(api, building, front_collection, shell_collection=None, focus=False):
    """Emit modest real trim, fitted commercial fabric, fascia and lettering.

    Required API: Batch(name,collection,origin,angle), MATS and
    shop_sign(building,collection,text). Batch.flush must supply the builder's
    normal stable-ID/owner tags; this helper adds semantic/building metadata.
    The sign callback emits UV-mapped mesh letters using a bundled/packed font.
    """
    Batch=api["Batch"]
    ident=building["id"];width=float(building["width"]);depth=float(building["depth"])
    floor=float(building.get("finished_floor_offset_m",.38));floors=int(building["floors"])
    origin=(*building["center"],building["pad_level_m"])
    angle=math.radians(building["yaw_degrees"])
    front=-depth/2
    kind=building["kind"];commercial=kind in COMMERCIAL
    variant=int(building.get("seed",0))
    paint=("BluePaint","Sage","Burgundy")[variant%3]
    if kind in ("cafe","creperie"):paint="BluePaint"
    required={"Stone","White","Iron","Zinc",paint}
    if commercial:required.add("Brass")
    missing=required-set(api["MATS"])
    if missing:raise ValueError("Facade palette is missing: "+", ".join(sorted(missing)))
    trim=Batch(ident+"_FacadeDetail",front_collection,origin,angle)
    # A low plinth course and small ledged cornice give the actual scanned
    # plaster a coherent architectural scale without covering window openings.
    # A real open door must remain open down to the finished-floor datum.
    # Split the low course outside both the 1.04m opening and its stone jambs.
    door_course_gap=1.24
    course_width=(width+.10-door_course_gap)/2
    for side in (-1,1):
        trim.box((side*(door_course_gap/2+course_width/2),front-.07,floor+.14),
                 (course_width,.16,.18),"Stone")
    eave=floor+floors*2.85-.16
    trim.box((0,front-.10,eave-.06),(width+.18,.28,.13),"White")
    trim.box((0,front-.06,eave-.18),(width+.06,.17,.07),"Stone")
    if floors>1:
        for level in range(1,floors):
            z=floor+level*2.85-.04
            trim.box((0,front-.05,z),(width+.06,.14,.10),"White")
    # Alternating short quoins are fitted outside the outer bay reveals.
    # The narrow corner strip never covers the large shop windows.
    quoins=focus or commercial or variant%3==0
    if quoins:
        for side in (-1,1):
            for course in range(max(1,int((eave-floor)/.43))):
                z=floor+.31+course*.43
                if z+.11>eave-.25:break
                strip=.30 if course%2 else .40
                trim.box((side*(width/2-.11),front-.065,z),(strip,.16,.22),"Stone")
    # Edge caps articulate the existing two-tread stoop without occupying its
    # central 1.4m approach or adding another, incorrect fourth riser.
    step_width=float(building.get("entry_steps",{}).get("width_m",1.4))
    for side in (-1,1):
        trim.box((side*(step_width/2+.17),front-.32,.11),(.14,.52,.22),"Stone")
        trim.box((side*(step_width/2+.17),front-.32,.235),(.20,.57,.06),"White")
    awning=None
    label=business_label(building)
    if commercial:
        fascia_width=min(width-.65,7.2)
        trim.box((0,front-.17,floor+2.60),(fascia_width,.13,.42),paint)
        for z in (floor+2.37,floor+2.83):
            trim.box((0,front-.19,z),(fascia_width+.10,.16,.055),"White")
        for side in (-1,1):
            trim.box((side*(fascia_width/2+.015),front-.19,floor+2.60),(.055,.16,.46),"White")
        if kind!="workshop":
            # Fabric stays inside the private setback and all valance/support
            # geometry is >2.20m above the finished floor, clearing the door.
            projection=min(1.10,max(.38,float(building.get("setback_m",2.0))-.85))
            canopy_width=width-.52
            count=max(10,math.ceil(canopy_width/.31))
            rear_z=floor+2.42;edge_z=floor+2.30
            rear_y=front-.14;edge_y=front-projection
            for stripe in range(count):
                xa=-canopy_width/2+canopy_width*stripe/count
                xb=-canopy_width/2+canopy_width*(stripe+1)/count
                material="White" if stripe%2 else paint
                # A tiny thickness is real geometry; glTF has no reliance on
                # double-sided material flags to show the underside.
                vertices=[(xa,rear_y,rear_z),(xb,rear_y,rear_z),(xb,edge_y,edge_z),(xa,edge_y,edge_z),
                          (xa,rear_y,rear_z-.012),(xb,rear_y,rear_z-.012),(xb,edge_y,edge_z-.012),(xa,edge_y,edge_z-.012)]
                trim.poly(vertices,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],material)
                trim.box(((xa+xb)/2,edge_y,edge_z-.04),(xb-xa,.025,.08),material)
            for x in (-canopy_width/2+.06,canopy_width/2-.06):
                trim.rod((x,front-.03,floor+2.24),(x,edge_y,edge_z-.025),.016,"Iron",n=6)
            trim.rod((-canopy_width/2,edge_y,edge_z-.015),(canopy_width/2,edge_y,edge_z-.015),.023,"Zinc",n=8)
            awning={"projection_m":projection,"width_m":canopy_width,"stripes":count,
                    "lowest_clearance_above_finished_floor_m":2.22,"palette":[paint,"White"]}
        else:
            # An artisan workshop gets restrained brass-shaded task lamps
            # instead of the cafe's full canvas, preserving a distinct role.
            for x in (-width*.285,width*.285):
                trim.rod((x,front-.03,floor+2.26),(x,front-.30,floor+2.34),.018,"Iron",n=7)
                trim.rod((x,front-.30,floor+2.30),(x,front-.30,floor+2.34),.09,"Brass",n=10,r2=.045)
    objects=trim.flush()
    for ob in objects:
        ob["building_id"]=ident
        ob["semantic_role"]="commercial_facade_details" if commercial else "residential_facade_details"
    if commercial:
        if "shop_sign" not in api:raise ValueError("Commercial facade requires the mesh-lettering callback")
        api["shop_sign"](building,front_collection,label)
    return {"building_id":ident,"commercial":commercial,"label":label,"paint":paint,
            "ground_front_bays":front_opening_spec(building,floor),"awning":awning,
            "quoin_courses":quoins,"trim_mesh_objects":len(objects),
            "policy":"Original metric facade geometry; UV-mapped through the builder; physical lettering callback; no external assets or image-only shop signs."}
