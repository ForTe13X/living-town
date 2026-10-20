"""Build the territorial extension on a read-only packed Living Town baseline.

Run with Blender 5.2 or newer, after ``--``. This module deliberately does not
import the original town builder: that file has canonical-write side effects.
The independent metric batch below implements its small interior geometry API.
The pure, audited room planner remains the source of interior arrangements.

All authored expansion geometry is metres, Z up, local frontage -Y. Image maps
are the existing source-bound CC0 PBR library; there is no model inference.
Opening the baseline changes only memory. Saving is confined to a fresh output
directory. No add-on installation, external executable, or GPU job is started.
"""
from __future__ import annotations

import argparse
import copy
from collections import defaultdict
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import random
import sys
import time

import bpy
import bmesh
import numpy as np
from mathutils import Vector

REPO = Path(__file__).resolve().parents[2]
MATS = {}
OWNER = "living_town.territory_expansion.v1"
NEW_OBJECTS = []
BUILDING_RECORDS = []
EXCLUSION_INDEX = {}
FLOOR_NOTCHES = {}
COLLECTION_BY_ID = {}


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    sys.modules[name] = result
    spec.loader.exec_module(result)
    return result


def log(message):
    print("[town-expansion] " + message, flush=True)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def collection(name, parent=None):
    result = bpy.data.collections.new(name)
    (parent.children if parent else bpy.context.scene.collection.children).link(result)
    result["generator_owner"] = OWNER
    COLLECTION_BY_ID[name]=result
    return result


def tag(ob, role, **props):
    ob["generator_owner"] = OWNER
    ob["stable_id"] = "expansion/" + ob.name
    ob["semantic_role"] = role
    ob["dimensions_unit"] = "metre"
    for name, value in props.items():
        ob[name] = value
    NEW_OBJECTS.append(ob)
    return ob


def persistent_material(material):
    """Resolve evaluated depsgraph IDs before storing a persistent mesh slot.

    ``evaluated.to_mesh()`` can expose copy-on-write Material IDs whose lifetime
    ends at ``to_mesh_clear`` or a dependency rebuild. Attaching those pointers
    to Main meshes crashes Blender later while rebuilding material node trees.
    Only the original registered material may outlive prototype evaluation.
    """
    if material is None:
        raise ValueError("Generated mesh has an empty material slot")
    original=material.original if material.is_evaluated else material
    main=bpy.data.materials.get(original.name)
    if main is None or main.is_evaluated or main.as_pointer()!=original.as_pointer():
        raise RuntimeError("Prototype material is not a persistent Main ID: "+original.name)
    return main


def pin_material_slots(mesh):
    for index,material in enumerate(mesh.materials):
        mesh.materials[index]=persistent_material(material)


class Batch:
    """Material batches, real apertures, metric UVs, triangulated shared data.

    Bevel requests from the legacy interior interface are intentionally recorded
    as requested metadata rather than per-object modifiers. Major furniture
    joinery and rounded rods are geometry. Export therefore retains mesh sharing.
    """
    def __init__(self, name, collection, origin=(0, 0, 0), angle=0):
        self.name, self.collection = name, collection
        self.origin, self.angle = Vector(origin), angle
        self.parts = defaultdict(lambda: [[], [], []])

    def poly(self, vertices, faces, material, uvs=None):
        vs, fs, us = self.parts[material]
        offset = len(vs)
        co, si = math.cos(self.angle), math.sin(self.angle)
        vs.extend([(x*co-y*si+self.origin.x, x*si+y*co+self.origin.y, z+self.origin.z)
                   for x, y, z in vertices])
        fs.extend([tuple(offset+i for i in face) for face in faces])
        if uvs is not None:
            us.extend(uvs)
            return
        for face in faces:
            points = [Vector(vertices[i]) for i in face]
            normal = (points[1]-points[0]).cross(points[2]-points[0])
            dominant = max(range(3), key=lambda i: abs(normal[i]))
            axes = [i for i in range(3) if i != dominant]
            us.append([(vertices[i][axes[0]]/2, vertices[i][axes[1]]/2) for i in face])

    def box(self, pos, size, material, rot=0):
        if min(size) <= 0:
            return
        if self.name in FLOOR_NOTCHES and not getattr(self,"_splitting_floor",False):
            x,y,z=pos;w,d,h=size
            pieces=[(x-w/2,y-d/2,x+w/2,y+d/2)]
            for hole in FLOOR_NOTCHES[self.name]:
                remaining=[]
                for a,b,c,e in pieces:
                    x0,y0,x1,y1=max(a,hole[0]),max(b,hole[1]),min(c,hole[2]),min(e,hole[3])
                    if x1<=x0 or y1<=y0:remaining.append((a,b,c,e));continue
                    remaining.extend(((a,b,x0,e),(x1,b,c,e),(x0,b,x1,y0),(x0,y1,x1,e)))
                pieces=[p for p in remaining if p[2]-p[0]>1e-6 and p[3]-p[1]>1e-6]
            self._splitting_floor=True
            for a,b,c,e in pieces:self.box(((a+c)/2,(b+e)/2,z),(c-a,e-b,h),material,rot)
            self._splitting_floor=False
            return
        x, y, z = pos
        a, b, c = [v/2 for v in size]
        co, si = math.cos(rot), math.sin(rot)
        vertices = [(x+dx*co-dy*si, y+dx*si+dy*co, z+dz)
                    for dx, dy, dz in ((-a,-b,-c),(a,-b,-c),(a,b,-c),(-a,b,-c),
                                      (-a,-b,c),(a,-b,c),(a,b,c),(-a,b,c))]
        self.poly(vertices, [(0,3,2,1),(4,5,6,7),(0,1,5,4),
                             (1,2,6,5),(2,3,7,6),(3,0,4,7)], material)

    def rod(self, p0, p1, radius, material, n=8, r2=None):
        p0, p1 = Vector(p0), Vector(p1)
        if (p1-p0).length < 1e-7:
            return
        direction = (p1-p0).normalized()
        a = direction.cross(Vector((0, 0, 1)))
        if a.length < .01:
            a = direction.cross(Vector((0, 1, 0)))
        a.normalize()
        b = direction.cross(a)
        vertices = [tuple(p+rr*(a*math.cos(i*math.tau/n)+b*math.sin(i*math.tau/n)))
                    for p, rr in ((p0, radius), (p1, radius if r2 is None else r2)) for i in range(n)]
        self.poly(vertices, [tuple(range(n-1,-1,-1)), tuple(range(n,2*n))] +
                  [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)], material)

    def ellipsoid(self, pos, radius, material, n=10, rings=5):
        vertices = []
        for j in range(rings+1):
            latitude = -math.pi/2+math.pi*j/rings
            for i in range(n):
                angle = i*math.tau/n
                vertices.append((pos[0]+radius[0]*math.cos(latitude)*math.cos(angle),
                                 pos[1]+radius[1]*math.cos(latitude)*math.sin(angle),
                                 pos[2]+radius[2]*math.sin(latitude)))
        self.poly(vertices, [(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i)
                             for j in range(rings) for i in range(n)], material)

    def flush(self, bevel=0):
        objects = []
        for material, (vertices, faces, uvs) in self.parts.items():
            if not faces:
                continue
            mesh = bpy.data.meshes.new(self.name+"_"+material)
            mesh.from_pydata(vertices, [], faces)
            mesh.materials.append(persistent_material(MATS[material]))
            mesh.update()
            uv = mesh.uv_layers.new(name="MetricUV")
            for face, coords in zip(mesh.polygons, uvs):
                for index, co in zip(face.loop_indices, coords):
                    uv.data[index].uv = co
            bm = bmesh.new()
            bm.from_mesh(mesh)
            bmesh.ops.dissolve_degenerate(bm, dist=1e-7, edges=list(bm.edges))
            bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
            bmesh.ops.triangulate(bm, faces=list(bm.faces))
            bm.to_mesh(mesh)
            bm.free()
            mesh.update()
            ob = bpy.data.objects.new(mesh.name, mesh)
            self.collection.objects.link(ob)
            tag(ob, "authored_mesh", metric_uv="metres / 2", requested_edge_radius_m=bevel)
            objects.append(ob)
        self.parts.clear()
        return objects


def solid(name, rgb, roughness=.72, metallic=0, alpha=1):
    mat = bpy.data.materials.new("Expansion_"+name)
    mat.use_nodes = True
    mat.diffuse_color = (*rgb, alpha)
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*rgb, 1)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Alpha"].default_value = alpha
    if alpha < 1:
        mat.surface_render_method = "DITHERED"
        mat.use_transparency_overlap = False
    MATS[name] = mat
    return mat


def weather_bake(source, output):
    """Bake restrained original weathering onto provenanced scanned albedo.

    This is a conventional pixel bake, with no inferred normals or roughness.
    The 4 x 12m contextual tile has a bottom splash zone, broad limewash variation
    and narrow rain streaks. Fine normal and roughness scans keep 1m scale.
    """
    image=bpy.data.images.load(str(source),check_existing=True)
    width,height=image.size
    pixels=np.empty(width*height*4,dtype=np.float32)
    image.pixels.foreach_get(pixels)
    pixels=pixels.reshape(height,width,4)
    size=1536
    # 384 pixels per metre horizontally and 128 vertically. The fine 2K normal
    # map remains separate and is never stretched to this contextual period.
    yy,xx=np.mgrid[0:size,0:size].astype(np.float32)
    u,v=xx/size,yy/size
    fine=pixels[(v*12*height).astype(np.int32)%height,(u*4*width).astype(np.int32)%width,:3]
    low=.965+.020*np.sin(u*18+v*13)+.012*np.sin(u*43-v*21)
    splash=.075*np.exp(-v*42)*( .7+.3*np.sin(u*35)**2)
    rain=.025*np.maximum(0,np.sin(u*82+np.sin(v*7)))**9*(.5+.5*np.sin(v*13)**2)
    rgba=np.ones((size,size,4),dtype=np.float32)
    rgba[:,:,:3]=np.clip(fine*(low-splash-rain)[:,:,None],0,1)
    baked=bpy.data.images.new("Expansion_Baked_Plaster_Weather",width=size,height=size,alpha=False)
    baked.colorspace_settings.name="sRGB"
    baked.pixels.foreach_set(rgba.ravel())
    baked.filepath_raw=str(output);baked.file_format="PNG";baked.save()
    baked.pack()
    return baked,{"path":output.name,"sha256":sha(output),"source_sha256":sha(source),
                  "dimensions":[size,size],"period_m":[4,12],
                  "recipe":"Original restrained limewash variation, rain streaks and ground splash multiplied into CC0 source color; original scanned normal/roughness untouched."}


def materials(library_path, output):
    library = json.loads(library_path.read_text(encoding="utf-8"))
    pbr = module("expansion_hero_pbr", REPO/"tools/asset_refinement/hero_pbr.py")
    reports = {}
    def scan(key, role, **kwargs):
        source = library["materials"][library["roles"][role]]
        maps = {}
        for purpose in ("basecolor", "roughness", "normal"):
            record = source["maps"][purpose]
            path = library_path.parent/record["path"]
            if sha(path) != record["sha256"]:
                raise ValueError("PBR source checksum mismatch: "+str(path))
            maps[purpose] = path
        mat, report = pbr.build_scanned_material("Expansion_"+key, **maps,
                           repeat_metres=source["repeat_metres"], **kwargs)
        mat["source_license"] = source["license"]
        MATS[key], reports[key] = mat, report
    scan("Plaster", "plaster", normal_strength=.75)
    wall_source=library["materials"][library["roles"]["plaster"]]["maps"]["basecolor"]
    baked,bake_report=weather_bake(library_path.parent/wall_source["path"],output/"plaster_weather_basecolor.png")
    for index, tint in enumerate(((.96,.97,1),(.94,.91,.84),(.86,.92,.92),(.96,.87,.79),(.89,.91,.83))):
        scan("Facade"+str(index), "plaster", tint=tint, normal_strength=.8)
        material=MATS["Facade"+str(index)]
        nodes,links=material.node_tree.nodes,material.node_tree.links
        tex=nodes.get("Scanned basecolor");tex.image=baked
        mapping=nodes.new("ShaderNodeMapping");mapping.name="Baked weather 4x12 metre period"
        mapping.inputs["Scale"].default_value=(.5,1/6,1)
        links.new(nodes.get("Physical MetricUV source").outputs["UV"],mapping.inputs["Vector"])
        links.new(mapping.outputs["Vector"],tex.inputs["Vector"])
        reports["Facade"+str(index)]["contextual_basecolor_bake"]=bake_report
    scan("Oak", "cabinet_oak", normal_strength=.65)
    scan("Granite", "honed_granite", normal_strength=.55)
    scan("Stone", "cut_granite", normal_strength=.8)
    scan("Tile", "interior_floor", normal_strength=.65)
    colors = {
        "White":(.86,.84,.76),"Sage":(.24,.36,.31),"BluePaint":(.21,.34,.40),
        "Burgundy":(.35,.15,.16),"Linen":(.70,.62,.48),"Terracotta":(.43,.22,.12),
        "Slate":(.105,.135,.16),"SlateLight":(.15,.18,.20),"Zinc":(.32,.38,.39),
        "Iron":(.055,.075,.073),"Ink":(.035,.047,.042),"Brass":(.48,.32,.11),
        "Leaf":(.14,.25,.105),"LeafLight":(.23,.35,.14),"LeafDark":(.075,.15,.08),
        "Trunk":(.19,.13,.075),"BloomBlue":(.32,.43,.57),"BloomCream":(.73,.65,.43),
        "BloomPink":(.57,.29,.37),"Grass":(.24,.34,.16),"Dirt":(.31,.25,.18),
        "Road":(.33,.34,.31),"Courtyard":(.50,.46,.36),"Lamp":(.91,.71,.38),
        "Shallows":(.24,.43,.42),"Cushion":(.42,.24,.16),"TealCloth":(.27,.42,.40)}
    for name, color in colors.items():
        solid(name, color, .32 if name in ("Zinc","Brass") else .75,
              .65 if name in ("Zinc","Iron","Brass") else 0)
    solid("Glass", (.39,.60,.61), .14, alpha=.20)
    return {"library_path":str(library_path), "library_sha256":sha(library_path),
            "materials":reports, "weather_bake":bake_report,
            "source_notices":{name:{key:value for key,value in source.items() if key in ("license","asset_url","source_kind","source_provenance_sha256")} for name,source in library["materials"].items()},
            "map_policy":"Source-bound CC0 scanned PBR. Facade basecolor has a portable pixel-baked 4x12m weather tile; source fine scanned normal/roughness keep their original physical repeat. Linear palette tints remain glTF factors."}


def table(b, x, y, z, r=.34, chairs=True):
    b.rod((x,y,z+.70),(x,y,z+.76),r,"Oak",n=16)
    b.rod((x,y,z+.04),(x,y,z+.70),.04,"Iron")
    b.rod((x,y,z+.03),(x,y,z+.07),.22,"Iron",n=12)


def chair(b, x, y, z, rot=0):
    def p(dx,dy,dz):
        return (x+dx*math.cos(rot)-dy*math.sin(rot),y+dx*math.sin(rot)+dy*math.cos(rot),z+dz)
    b.rod(p(0,0,.43),p(0,0,.49),.205,"Oak",n=14)
    for dx in (-.14,.14):
        for dy in (-.14,.14):
            b.rod(p(dx,dy,.035),p(dx,dy,.44),.023,"Iron",n=6)
        b.rod(p(dx,.17,.42),p(dx,.17,.89),.023,"Oak",n=6)
    points=[p(math.cos(math.pi*i/10)*.20,.17,.69+math.sin(math.pi*i/10)*.22) for i in range(11)]
    for a,c in zip(points,points[1:]):
        b.rod(a,c,.025,"Oak",n=6)


def railing(b, p0, p1, z, h=.92):
    count=max(2,math.ceil(math.dist(p0,p1)/.65))
    for i in range(count+1):
        t=i/count;x=p0[0]*(1-t)+p1[0]*t;y=p0[1]*(1-t)+p1[1]*t
        b.rod((x,y,z),(x,y,z+h),.023,"Iron",n=6)
    for zz in (.18,h):
        b.rod((*p0,z+zz),(*p1,z+zz),.03,"Iron",n=6)


def local_world(building, x, y, z=0):
    a=math.radians(building["yaw_degrees"]);co,si=math.cos(a),math.sin(a)
    return (building["center"][0]+x*co-y*si,building["center"][1]+x*si+y*co,building["pad_level_m"]+z)


def wall_panel(batch, axis, co, low, high, bottom, top, holes, material):
    """Solid wall cells surround genuinely empty rectangular openings."""
    xs=sorted(set([low,high]+[max(low,min(high,h[0]+s*h[2]/2)) for h in holes for s in (-1,1)]))
    zs=sorted(set([bottom,top]+[max(bottom,min(top,h[1]+s*h[3]/2)) for h in holes for s in (-1,1)]))
    for a,c in zip(xs,xs[1:]):
        for b,d in zip(zs,zs[1:]):
            x,z=(a+c)/2,(b+d)/2
            if any(abs(x-h[0])<h[2]/2-1e-7 and abs(z-h[1])<h[3]/2-1e-7 for h in holes):
                continue
            pos=(x,co,z) if axis=="x" else (co,x,z)
            size=(c-a,.26,d-b) if axis=="x" else (.26,c-a,d-b)
            batch.box(pos,size,material)


def window(batch, axis, co, u, z, width, height, paint, outward, detail):
    def p(x, offset, zz):
        return (x,co+offset,zz) if axis=="x" else (co+offset,x,zz)
    def box(x,offset,zz,w,d,h,mat):
        batch.box(p(x,offset,zz),(w,d,h) if axis=="x" else (d,w,h),mat)
    box(u,0,z,width,.025,height,"Glass")
    for dx in (-width/2,width/2):
        box(u+dx,outward*.075,z,.075,.17,height+.12,"White")
    for dz in (-height/2,height/2):
        box(u,outward*.075,z+dz,width+.12,.17,.075,"White")
    box(u,outward*.10,z,.045,.12,height,"White")
    box(u,outward*.10,z-height*.12,width,.12,.035,"White")
    box(u,outward*.14,z-height/2-.09,width+.24,.32,.12,"Stone")
    if detail:
        for side in (-1,1):
            x=u+side*(width/2+.22)
            box(x,outward*.02,z,.33,.06,height+.02,paint)
            for j in range(7):
                box(x,outward*.065,z-height*.40+j*height*.133,.29,.035,.035,paint)


def shop_sign(building,col,text):
    """Physical mesh lettering; no texture-only labels or missing font export."""
    curve=bpy.data.curves.new(building["id"]+"_SignLettering","FONT")
    curve.body=text;curve.size=.30;curve.align_x="CENTER";curve.align_y="CENTER"
    curve.extrude=.003;curve.resolution_u=2;curve.materials.append(MATS["White"])
    # Reuse an already packed baseline font. There is no external font lookup
    # or untracked font dependency in the generated engine mesh assets.
    font=next((f for f in bpy.data.fonts if getattr(f,"packed_file",None)),None)
    if font:curve.font=font
    ob=bpy.data.objects.new(curve.name,curve);col.objects.link(ob)
    ob.location=local_world(building,0,-building["depth"]/2-.24,2.98)
    ob.rotation_euler=(math.pi/2,0,math.radians(building["yaw_degrees"]))
    bpy.context.view_layer.update();graph=bpy.context.evaluated_depsgraph_get()
    mesh=bpy.data.meshes.new_from_object(ob.evaluated_get(graph),depsgraph=graph)
    pin_material_slots(mesh)
    uv=mesh.uv_layers.new(name="MetricUV")
    for face in mesh.polygons:
        for li in face.loop_indices:
            p=mesh.vertices[mesh.loops[li].vertex_index].co;uv.data[li].uv=(p.x/2,p.y/2)
    mesh.transform(ob.matrix_world)
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    name=ob.name;bpy.data.objects.remove(ob,do_unlink=True);bpy.data.curves.remove(curve)
    sign=bpy.data.objects.new(name,mesh);col.objects.link(sign)
    tag(sign,"business_sign_lettering",building_id=building["id"],sign_text=text)


def building_geometry(building, district_col, interior_module, focus, height,architecture):
    ident=building["id"];w=float(building["width"]);d=float(building["depth"])
    floors=int(building["floors"]);angle=math.radians(building["yaw_degrees"])
    origin=(*building["center"],building["pad_level_m"])
    root=collection(ident,district_col)
    root["building_id"]=ident;root["district"]=building["district"]
    fronts=collection(ident+"_Front",root);shell=collection(ident+"_Shell",root)
    roof_col=collection(ident+"_Roof",root);inside=collection(ident+"_Interiors",root)
    upper=collection(ident+"_UpperCover",root)
    facade="Facade"+str(building["seed"]%5)
    paint=("Sage","BluePaint","White","Burgundy")[building["seed"]%4]
    ff=building.get("finished_floor_offset_m",.38)
    top=ff+floors*2.85-.16
    rise=max(1.4,min(2.8,d*.29))
    base=Batch(ident+"_Foundation",shell,origin,angle)
    corners=[local_world(building,x,y) for x in (-w/2,w/2) for y in (-d/2,d/2)]
    natural_min=min(height(x,y) for x,y,z in corners)-origin[2]
    base.box((0,0,(min(-.12,natural_min-.12)+ff-.06)/2),
             (w+.10,d+.10,ff-.06-min(-.12,natural_min-.12)),"Stone")
    base.box((0,0,ff-.09),(w-.22,d-.22,.18),"Oak")
    for ob in base.flush():
        ob["building_id"]=ident;ob["semantic_role"]="foundation_and_ground_slab"
    windows=[]
    count=max(2,min(5,int((w-1.3)/2.25)))
    positions=[-w/2+(i+1)*w/(count+1) for i in range(count)]
    front_holes=[];back_holes=[]
    ground_front_bays=architecture.front_opening_spec(building,ff)
    door_width=1.04
    for level in range(floors):
        floor=ff+level*2.85
        for x in positions:
            if level==0 and abs(x)<1.2:
                continue
            h=1.44 if level else 1.60
            z=floor+1.48
            for side in (-1,1):
                if side==-1 and level==0 and ground_front_bays is not None:continue
                hole=(x,z,1.02,h)
                (front_holes if side==-1 else back_holes).append(hole)
                windows.append(("x",side*d/2,x,z,1.02,h,side))
    if ground_front_bays is not None:
        for x,z,width,window_height in ground_front_bays:
            front_holes.append((x,z,width,window_height))
            windows.append(("x",-d/2,x,z,width,window_height,-1))
    front_holes.append((0,ff+1.08,door_width,2.16))
    front=Batch(ident+"_FacadeFront",fronts,origin,angle)
    back=Batch(ident+"_FacadeRear",shell,origin,angle)
    wall_panel(front,"x",-d/2,-w/2,w/2,ff-.08,top,front_holes,facade)
    wall_panel(back,"x",d/2,-w/2,w/2,ff-.08,top,back_holes,facade)
    sides=Batch(ident+"_FacadeSides",shell,origin,angle)
    for side in (-1,1):
        holes=[]
        for level in range(floors):
            for y in (-d*.27,d*.27):
                z=ff+level*2.85+1.47
                holes.append((y,z,.86,1.36))
                windows.append(("y",side*w/2,y,z,.86,1.36,side))
        wall_panel(sides,"y",side*w/2,-d/2,d/2,ff-.08,top,holes,facade)
        x=side*w/2
        # The two real gable triangles close the wall under the pitched roof.
        sides.poly([(x,-d/2,top),(x,d/2,top),(x,0,top+rise)],[(0,1,2)],facade)
    for batch in (front,back,sides):
        for ob in batch.flush():
            ob["building_id"]=ident;ob["semantic_role"]="apertured_exterior_wall"
    joinery_front=Batch(ident+"_FrontJoinery",fronts,origin,angle)
    joinery=Batch(ident+"_Joinery",shell,origin,angle)
    for axis,co,u,z,ww,hh,outward in windows:
        window(joinery_front if axis=="x" and outward==-1 else joinery,
               axis,co,u,z,ww,hh,paint,outward,(focus or axis=="x") and not(axis=="x" and outward==-1 and ground_front_bays is not None and z<ff+2.4))
    for x in (-door_width/2-.045,door_width/2+.045):
        joinery_front.box((x,-d/2-.05,ff+1.08),(.09,.18,2.24),"Stone")
    joinery_front.box((0,-d/2-.05,ff+2.23),(door_width+.22,.18,.14),"Stone")
    # Door is folded outward: it does not fill the entrance or its circulation.
    hinge=(-door_width/2,-d/2-.12)
    theta=-math.pi/2
    cx=hinge[0]+math.cos(theta)*door_width/2;cy=hinge[1]+math.sin(theta)*door_width/2
    joinery_front.box((cx,cy,ff+1.04),(door_width-.06,.055,2.08),paint,theta)
    joinery_front.rod((cx+.025,cy-.035,ff+.92),(cx+.025,cy-.035,ff+1.07),.018,"Brass",n=7)
    entry=building.get("entry_steps",{})
    risers=entry.get("risers",3);riser=entry.get("riser_m",ff/risers);tread=entry.get("tread_m",.30)
    # The floor threshold is the third landing: exactly two visible treads
    # produce three equal risers, instead of adding a spurious fourth step.
    for step in range(risers-1):
        top_z=(risers-1-step)*riser
        joinery_front.box((0,-d/2-(step+.5)*tread,top_z/2),
                         (entry.get("width_m",1.4)+.10*step,tread+.01,top_z),"Stone")
    for batch in (joinery_front,joinery):
        for ob in batch.flush():
            ob["building_id"]=ident;ob["semantic_role"]="windows_doors_joinery"
    architecture_report=architecture.add_facade_details({"Batch":Batch,"MATS":MATS,"shop_sign":shop_sign},
                                        building,fronts,shell_collection=shell,focus=focus)
    roofs=Batch(ident+"_SlateRoof",roof_col,origin,angle)
    ww=w+.54;dd=d+.54;eave=top+.035
    verts=[(-ww/2,-dd/2,eave),(ww/2,-dd/2,eave),(ww/2,0,eave+rise),(-ww/2,0,eave+rise),
           (-ww/2,dd/2,eave),(ww/2,dd/2,eave)]
    roofs.poly(verts,[(0,1,2,3),(3,2,5,4)],"Slate")
    for side in (-1,1):
        roofs.box((0,side*dd/2,eave-.035),(ww,.10,.14),"Zinc")
        roofs.rod((-ww/2,side*dd/2,eave+.025),(ww/2,side*dd/2,eave+.025),.065,"Zinc",n=8)
        for x in (-ww/2+.10,ww/2-.10):
            roofs.rod((x,side*dd/2,eave),(x,side*dd/2,.12),.037,"Zinc",n=7)
        # Actual slate courses give a roof-scale cue at street and town views.
        rows=max(7,int(math.hypot(dd/2,rise)/(.22 if focus else .37)))
        for j in range(1,rows):
            t=j/rows;y=side*dd/2*(1-t);z=eave+rise*t+.015
            roofs.rod((-ww/2,y,z),(ww/2,y,z),.012,"SlateLight",n=4)
        if focus:
            for j in range(rows):
                t=(j+.5)/rows
                for k in range(math.ceil(ww/.36)):
                    x=-ww/2+(k+.5+(j%2)*.5)*.36
                    if x>ww/2:continue
                    t0=j/rows;t1=(j+1)/rows
                    roofs.rod((x,side*dd/2*(1-t0),eave+rise*t0+.018),
                              (x,side*dd/2*(1-t1),eave+rise*t1+.018),.008,"SlateLight",n=4)
    roofs.rod((-ww/2-.04,0,eave+rise+.025),(ww/2+.04,0,eave+rise+.025),.075,"Zinc",n=9)
    chimney_x=w*.29;chimney_y=d*.17
    chimney_top=top+rise+.55
    roofs.box((chimney_x,chimney_y,(top+chimney_top)/2),(.52,.62,chimney_top-top),"Stone")
    roofs.box((chimney_x,chimney_y,chimney_top),(.68,.78,.13),"Stone")
    for xx in (-.14,.14):
        roofs.rod((chimney_x+xx,chimney_y,chimney_top+.04),(chimney_x+xx,chimney_y,chimney_top+.34),.075,"Terracotta",n=9)
    for ob in roofs.flush():
        ob["building_id"]=ident;ob["semantic_role"]="slate_roof_gutters_chimney"
    kind=building["kind"]
    kind={"workshop":"work","souvenir":"shop","convenience":"shop","farmhouse":"longere",
          "residence":"home","guesthouse":"hotel","restaurant":"creperie"}.get(kind,kind)
    api={"Batch":Batch,"coll":collection,"railing":railing,"table":table,"chair":chair}
    interior=interior_module.build_interior(api,ident,inside,upper,origin,angle,w,d,floors,kind,0)
    interior["district"]=building["district"]
    interior["world_pad_level_m"]=building["pad_level_m"]
    interior["world_pose"]={"center_m":building["center"],"yaw_degrees":building["yaw_degrees"]}
    return {"id":ident,"district":building["district"],"kind":building["kind"],
            "center_m":building["center"],"pad_level_m":building["pad_level_m"],
            "finished_floor_world_z_m":building["pad_level_m"]+ff,
            "footprint_m":[w,d],"floor_count":floors,"room_count":interior["room_count"],
            "furnishing_count":interior["furnishing_count"],"yaw_degrees":building["yaw_degrees"],
            "window_aperture_count":len(windows),"door_aperture_width_m":door_width,
            "front_door_state":"day-open 90 degrees outward",
            "front_door_clear_width_m":door_width-.055/2,
            "entry_clearance_volume_local_m":{"x":[-.25,.25],"y":[-d/2-1.2,-d/2+.5],"z":[ff+.05,ff+2.10],
                "receipt":"Authored half-metre centreline sweep is clear of fully folded door leaf, split plinth, jambs, awning and stoop edge caps. Native mesh clearance is verified separately."},
            "detail_tier":"focus" if focus else "district",
            "architecture_details":architecture_report,
            "collections":{"root":root.name,"front":fronts.name,"roof":roof_col.name,"upper":upper.name},
            "interior":interior}


def point_segment(x,y,a,b):
    dx,dy=b[0]-a[0],b[1]-a[1]
    t=max(0,min(1,((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy))) if dx*dx+dy*dy else 0
    return math.hypot(x-a[0]-dx*t,y-a[1]-dy*t),t


def terrain_function(plan, baseline_root):
    """Use the planner's exact pad/road grading implementation when available."""
    planner=module("expansion_territory",REPO/"tools/town_generation/territory.py")
    if hasattr(planner,"make_height_function"):
        return planner.make_height_function(plan,baseline_root)
    if hasattr(planner,"height_at"):
        return lambda x,y:planner.height_at(plan,x,y,baseline_root)
    raise RuntimeError("Territory planner must expose make_height_function(plan, baseline_root); divergent terrain recipes are prohibited")


def vegetation_excluded(x,y,plan,margin=3):
    key=id(plan)
    if key not in EXCLUSION_INDEX:
        lots=defaultdict(list);segments=defaultdict(list);cell=20
        def put(target,item,bounds):
            for gx in range(math.floor(bounds[0]/cell),math.floor(bounds[2]/cell)+1):
                for gy in range(math.floor(bounds[1]/cell),math.floor(bounds[3]/cell)+1):target[gx,gy].append(item)
        for b in plan["buildings"]:
            xx,yy=b["center"];r=math.hypot(b["width"],b["depth"])/2+8
            put(lots,b,(xx-r,yy-r,xx+r,yy+r))
        for road in plan["roads"]+plan.get("approaches",[]):
            radius=road["width_m"]/2+3
            for a,b in zip(road["points_m"],road["points_m"][1:]):
                put(segments,(a,b,road["width_m"]),(min(a[0],b[0])-radius,min(a[1],b[1])-radius,max(a[0],b[0])+radius,max(a[1],b[1])+radius))
        EXCLUSION_INDEX[key]=(lots,segments)
    lots,segments=EXCLUSION_INDEX[key]
    cell_key=(math.floor(x/20),math.floor(y/20))
    for b in lots.get(cell_key,()):
        a=math.radians(b["yaw_degrees"]);dx=x-b["center"][0];dy=y-b["center"][1]
        if abs(dx*math.cos(a)+dy*math.sin(a))<b["width"]/2+margin and abs(-dx*math.sin(a)+dy*math.cos(a))<b["depth"]/2+margin:
            return True
    for a,b,width in segments.get(cell_key,()):
        if point_segment(x,y,a,b)[0]<width/2+2:
            return True
    return False


def canopy_conflicts(x,y,radius,plan,building_clearance=.65,road_clearance=1.25):
    """Circle enclosing actual shared canopy vertices against urban geometry.

    The broadphase queries neighboring cells over the full crown radius. A
    trunk-only cell query misses large crowns rooted beyond the road buffer.
    """
    if id(plan) not in EXCLUSION_INDEX:vegetation_excluded(x,y,plan,0)
    lots,segments=EXCLUSION_INDEX[id(plan)];seen_lots=set();seen_segments=set()
    reach=radius+max(building_clearance,road_clearance)
    for xx in range(math.floor((x-reach)/20),math.floor((x+reach)/20)+1):
        for yy in range(math.floor((y-reach)/20),math.floor((y+reach)/20)+1):
            for b in lots.get((xx,yy),()):
                if b["id"] in seen_lots:continue
                seen_lots.add(b["id"])
                a=math.radians(b["yaw_degrees"]);dx=x-b["center"][0];dy=y-b["center"][1]
                lx=dx*math.cos(a)+dy*math.sin(a);ly=-dx*math.sin(a)+dy*math.cos(a)
                distance=math.hypot(max(0,abs(lx)-b["width"]/2),max(0,abs(ly)-b["depth"]/2))
                if distance<radius+building_clearance:return True
            for segment in segments.get((xx,yy),()):
                if id(segment) in seen_segments:continue
                seen_segments.add(id(segment));a,b,width=segment
                if point_segment(x,y,a,b)[0]<width/2+radius+road_clearance:return True
    return False


def shared_mesh_xy_radius(mesh,cache):
    pointer=mesh.as_pointer()
    if pointer not in cache:
        cache[pointer]=max((math.hypot(v.co.x,v.co.y) for v in mesh.vertices),default=0.)
    return cache[pointer]


def clear_baseline_tree_canopies(plan):
    groups=defaultdict(list);cache={};removed=[];records=[]
    for ob in bpy.context.scene.objects:
        if ob.type=="MESH" and ob.get("reserve_role")=="tree":
            groups["_".join(ob.name.split("_")[:3])].append(ob)
    for ident,objects in groups.items():
        centre=objects[0].matrix_world.translation
        radius=max(shared_mesh_xy_radius(ob.data,cache)*max(abs(ob.scale.x),abs(ob.scale.y)) for ob in objects)
        if not canopy_conflicts(centre.x,centre.y,radius,plan):continue
        records.append({"id":ident,"centre_world_xy_m":[centre.x,centre.y],"canopy_radius_m":radius,
                        "mesh_objects":len(objects),"action":"cleared from new urban roof/road/sidewalk exclusion"})
        for ob in objects:
            removed.append(ob.name);bpy.data.objects.remove(ob,do_unlink=True)
    return removed,records


def clear_new_tree_canopies(plan):
    """Diagnostic repair for an already built scene; fresh planting prechecks."""
    groups=defaultdict(list);cache={};removed=[]
    for ob in bpy.context.scene.objects:
        if ob.type!="MESH" or ob.get("prototype") not in ("hero_tree","rowan","lime","birch"):continue
        key=(ob.get("prototype"),tuple(round(v,5) for v in ob.location),tuple(round(v,5) for v in ob.rotation_euler),tuple(round(v,5) for v in ob.scale))
        groups[key].append(ob)
    for key,objects in groups.items():
        centre=objects[0].matrix_world.translation
        radius=max(shared_mesh_xy_radius(ob.data,cache)*max(abs(ob.scale.x),abs(ob.scale.y)) for ob in objects)
        if not canopy_conflicts(centre.x,centre.y,radius,plan):continue
        for ob in objects:
            removed.append(ob.name);bpy.data.objects.remove(ob,do_unlink=True)
    return removed


def triangulate_persistent_mesh(mesh):
    """Real triangles retain original UVs and support portable tangent export."""
    bm=bmesh.new();bm.from_mesh(mesh)
    bmesh.ops.triangulate(bm,faces=list(bm.faces))
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(mesh);bm.free();mesh.update()
    if any(len(face.vertices)!=3 for face in mesh.polygons):
        raise RuntimeError("Persistent export mesh is not triangulated: "+mesh.name)


def repair_pad_contacts(terrain,plan,height,tolerance=.08):
    """Refine only measured failing foundation neighborhoods, then remeasure.

    The complete terrain remains connected. A 0.20m XY edge target is smaller
    than the graded pad's 0.30m margin around the building corners, so a flat
    foundation triangle cannot borrow a vertex beyond a steep pad boundary.
    """
    inverse=terrain.matrix_world.inverted()
    def contacts():
        bpy.context.view_layer.update();records=[]
        for b in plan["buildings"]:
            points=[(*b["center"],b["pad_level_m"])]+[(*p[:2],b["pad_level_m"]) for p in b["footprint_polygon"]]+[(*b["front_threshold"][:2],b["pad_level_m"])]
            errors=[];misses=0
            for x,y,z in points:
                start=inverse@Vector((x,y,150));direction=(inverse.to_3x3()@Vector((0,0,-1))).normalized()
                hit,location,normal,index=terrain.ray_cast(start,direction,distance=400)
                if hit:errors.append(abs((terrain.matrix_world@location).z-b["pad_level_m"]))
                else:misses+=1
            records.append({"id":b["id"],"max_error_m":max(errors,default=999),"ray_misses":misses})
        return records
    before=contacts();failing={r["id"] for r in before if r["max_error_m"]>tolerance and not r["ray_misses"]}
    if not failing:return {"status":"PASS","target_tolerance_m":tolerance,"refined_pad_ids":[],"before":before,"after":before}
    targets=[b for b in plan["buildings"] if b["id"] in failing]
    index=defaultdict(list)
    for b in targets:
        x,y=b["center"];r=math.hypot(b["width"],b["depth"])/2+2
        for xx in range(math.floor((x-r)/20),math.floor((x+r)/20)+1):
            for yy in range(math.floor((y-r)/20),math.floor((y+r)/20)+1):index[xx,yy].append(b)
    def near(x,y):
        for b in index.get((math.floor(x/20),math.floor(y/20)),()):
            a=math.radians(b["yaw_degrees"]);dx=x-b["center"][0];dy=y-b["center"][1]
            lx=dx*math.cos(a)+dy*math.sin(a);ly=-dx*math.sin(a)+dy*math.cos(a)
            if abs(lx)<b["width"]/2+1.5 and abs(ly)<b["depth"]/2+1.5:return True
        return False
    bm=bmesh.new();bm.from_mesh(terrain.data);original_vertices=len(bm.verts);passes=[]
    for iteration in range(3):
        edges=set()
        for face in bm.faces:
            centre=terrain.matrix_world@face.calc_center_median()
            if not near(centre.x,centre.y):continue
            edges.update(edge for edge in face.edges if math.hypot(*(edge.verts[1].co-edge.verts[0].co)[:2])>.20)
        if not edges:break
        log("Refine measured pad contacts pass %d: %d local edges"%(iteration+1,len(edges)))
        bmesh.ops.subdivide_edges(bm,edges=list(edges),cuts=3,use_grid_fill=True)
        passes.append({"pass":iteration+1,"edges":len(edges)})
    for vertex in bm.verts:
        world=terrain.matrix_world@vertex.co
        if near(world.x,world.y):vertex.co=inverse@Vector((world.x,world.y,height(world.x,world.y)))
    bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(terrain.data);bm.free();terrain.data.update()
    terrain.update_tag(refresh={"DATA"});after=contacts()
    failures=[r for r in after if r["id"] in failing and r["max_error_m"]>.15]
    return {"status":"FAIL" if failures else "PASS","target_tolerance_m":tolerance,"maximum_required_tolerance_m":.15,
            "refined_pad_ids":sorted(failing),"added_vertices":len(terrain.data.vertices)-original_vertices,
            "passes":passes,"before":before,"after":after,"failures":failures}


def refresh_graded_terrain_faces(terrain,plan):
    """New planted earthworks must not inherit old ravine material/flat flags."""
    cells=defaultdict(list)
    def put(item,bounds):
        for xx in range(math.floor(bounds[0]/20),math.floor(bounds[2]/20)+1):
            for yy in range(math.floor(bounds[1]/20),math.floor(bounds[3]/20)+1):cells[xx,yy].append(item)
    for pad in plan["terrain"]["pads"]:
        x,y=pad["center_m"];r=math.hypot(pad["width_m"],pad["depth_m"])/2+pad["blend_m"]+.35
        put(("pad",pad),(x-r,y-r,x+r,y+r))
    for road in plan["roads"]+plan.get("approaches",[]):
        radius=road["width_m"]/2+road.get("graded_verge_m",.3)+road.get("shoulder_m",1.2)+.35
        for a,b in zip(road["points_m"],road["points_m"][1:]):
            put(("road",(a,b,radius)),(min(a[0],b[0])-radius,min(a[1],b[1])-radius,max(a[0],b[0])+radius,max(a[1],b[1])+radius))
    grass=next((i for i,m in enumerate(terrain.data.materials) if m and m.name=="Grass"),0)
    updated=0;replaced_rock=0;smoothed=0
    for face in terrain.data.polygons:
        p=terrain.matrix_world@face.center;inside=False
        for kind,value in cells.get((math.floor(p.x/20),math.floor(p.y/20)),()):
            if kind=="road":
                a,b,r=value;inside=point_segment(p.x,p.y,a,b)[0]<=r
            else:
                q=value;a=math.radians(q["yaw_degrees"]);dx=p.x-q["center_m"][0];dy=p.y-q["center_m"][1]
                lx=dx*math.cos(a)+dy*math.sin(a);ly=-dx*math.sin(a)+dy*math.cos(a)
                inside=math.hypot(max(0,abs(lx)-q["width_m"]/2),max(0,abs(ly)-q["depth_m"]/2))<=q["blend_m"]+.35
            if inside:break
        if inside:
            updated+=1;replaced_rock+=face.material_index!=grass;smoothed+=not face.use_smooth
            face.material_index=grass;face.use_smooth=True
    terrain.data.update()
    return {"graded_faces_refreshed":updated,"stale_rock_faces_replanted":replaced_rock,"flat_faces_smoothed":smoothed,
            "policy":"Planted urban cut/fill banks use original Grass and smooth shading inside new grading influence only; original outlying ravine stone materials/shading remain untouched."}


def road_sidewalk_width(road):
    """Entrance approaches keep their authored width; streets declare walks."""
    width=float(road.get("sidewalk_width_m",0. if road.get("owner") or road.get("kind")=="entrance_approach" else .78))
    if not math.isfinite(width) or width<0:raise ValueError("Invalid sidewalk width: "+road["id"])
    return width


def configure_saved_viewport(camera):
    """Show the actual mapped PBR materials under the saved scene lighting."""
    bpy.context.scene.camera=camera
    for material in bpy.data.materials:
        if not material.use_nodes or material.node_tree is None:continue
        nodes=material.node_tree.nodes;queue=[];seen=set()
        for node in nodes:
            if node.type=="BSDF_PRINCIPLED":queue.extend(link.from_node for link in node.inputs["Base Color"].links)
        while queue:
            node=queue.pop(0)
            if node.as_pointer() in seen:continue
            seen.add(node.as_pointer())
            if node.type=="TEX_IMAGE" and node.image is not None:
                nodes.active=node;break
            for socket in node.inputs:queue.extend(link.from_node for link in socket.links)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                area.spaces.active.region_3d.view_perspective="CAMERA"
                shading=area.spaces.active.shading;shading.type="MATERIAL"
                shading.use_scene_lights=True;shading.use_scene_world=True


def road_sections(road):
    """Metric cross sections from the single finished-surface authority."""
    if road.get("paved_sections_m"):
        return road["paved_sections_m"]
    # Historical diagnostic plans had flat road cross sections. New plans
    # provide explicit conforming sections; keep that old contract readable.
    width=road["width_m"];walk=road_sidewalk_width(road)
    offsets=sorted({-width/2-walk,-width/2,0.,width/2,width/2+walk});result=[]
    points=road["points_m"]
    for i,p in enumerate(points):
        a,b=points[max(0,i-1)],points[min(len(points)-1,i+1)]
        length=math.hypot(b[0]-a[0],b[1]-a[1]);nx,ny=-(b[1]-a[1])/length,(b[0]-a[0])/length
        result.append({"center_m":p,"offsets_m":offsets,"points_m":[[p[0]+nx*s,p[1]+ny*s,p[2]] for s in offsets]})
    return result


def repair_road_surface_contacts(terrain,plan,height):
    """Refine measured contact defects at explicit road section vertices only."""
    samples=[]
    for road in plan["roads"]+plan.get("approaches",[]):
        if road.get("paved_sections_m"):
            sections=road_sections(road)
            for section in sections:
                samples.extend((road["id"],*p) for p in section["points_m"])
                samples.extend((road["id"],*((a[k]+b[k])/2 for k in range(3))) for a,b in zip(section["points_m"],section["points_m"][1:]))
            for left,right in zip(sections,sections[1:]):
                # Shared diagonal matches roads()' actual two triangles,
                # including their interior centroids, rather than assuming a
                # bilinear surface that differs from the exported mesh.
                for j in range(len(left["points_m"])-1):
                    aa,ab=left["points_m"][j:j+2];ba,bb=right["points_m"][j:j+2]
                    for triangle in ((aa,ba,bb),(aa,bb,ab)):
                        samples.append((road["id"],*(sum(p[k] for p in triangle)/3 for k in range(3))))
    if not samples:return {"status":"NOT_APPLICABLE","policy":"Historical plan has no explicit conforming cross sections."}
    inverse=terrain.matrix_world.inverted()
    def measure():
        bpy.context.view_layer.update();bad=[];maximum=0.;overshoot=0.;misses=0
        for identity,x,y,z in samples:
            hit,p,_,_=terrain.ray_cast(inverse@Vector((x,y,160)),Vector((0,0,-1)),distance=400)
            # The preserved quay intentionally has no grass. Its actual built
            # deck is audited independently by the native reviewer.
            if not hit:
                if 31-.001<=x<=66+.001 and 37-.001<=y<=55+.001:continue
                misses+=1;continue
            delta=(terrain.matrix_world@p).z-z;maximum=max(maximum,abs(delta));overshoot=max(overshoot,delta)
            if delta>.025 or abs(delta)>.10:bad.append((identity,x,y,z,delta))
        return bad,maximum,overshoot,misses
    before=measure();bad=before[0];passes=[];original_vertices=len(terrain.data.vertices)
    for iteration in range(3):
        if not bad:break
        cells=defaultdict(list)
        for _,x,y,_,_ in bad:
            for gx in range(math.floor(x-.8),math.floor(x+.8)+1):
                for gy in range(math.floor(y-.8),math.floor(y+.8)+1):cells[gx,gy].append((x,y))
        def near(x,y):return any((x-a)**2+(y-b)**2<.8**2 for a,b in cells.get((math.floor(x),math.floor(y)),()))
        bm=bmesh.new();bm.from_mesh(terrain.data);edges=set()
        for face in bm.faces:
            c=terrain.matrix_world@face.calc_center_median()
            if near(c.x,c.y):edges.update(e for e in face.edges if math.hypot(*(e.verts[1].co-e.verts[0].co)[:2])>.018)
        if not edges:bm.free();break
        log("Refine measured road sections pass %d: %d local edges"%(iteration+1,len(edges)))
        bmesh.ops.subdivide_edges(bm,edges=list(edges),cuts=3,use_grid_fill=True)
        for vertex in bm.verts:
            p=terrain.matrix_world@vertex.co
            if near(p.x,p.y):vertex.co=inverse@Vector((p.x,p.y,height(p.x,p.y)))
        bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(terrain.data);bm.free();terrain.data.update();terrain.update_tag(refresh={"DATA"})
        passes.append({"iteration":iteration+1,"refined_edges":len(edges)})
        if len(terrain.data.vertices)-original_vertices>1_000_000:raise RuntimeError("Measured road repair exceeded one-million-vertex bounded budget")
        bad,_,_,_=measure()
    # A measured constrained retaining joint can be much narrower than the
    # adaptive18mm edge target. Preserve its exact low-side contact by adding
    # a connected vertex, rather than stopping at a triangle that bridges it.
    # This does not change the height authority or the contact limits.
    anchors=[]
    for anchor_pass in range(4):
        if not bad or len(bad)>64:break
        targets=[]
        bpy.context.view_layer.update()
        for row in bad:
            identity,x,y,z,delta=row
            if abs(height(x,y)-z)>.02:continue
            hit,location,normal,index=terrain.ray_cast(inverse@Vector((x,y,160)),Vector((0,0,-1)),distance=400)
            if hit:targets.append((index,row))
        bm=bmesh.new();bm.from_mesh(terrain.data);bm.faces.ensure_lookup_table();source_faces=list(bm.faces)
        uv_layer=bm.loops.layers.uv.active;used=set();added=0
        for face_index,(identity,x,y,z,delta) in targets:
            if face_index in used:continue
            face=source_faces[face_index]
            if not face.is_valid or len(face.verts)!=3:continue
            used.add(face_index);world=[terrain.matrix_world@v.co for v in face.verts]
            a,b,c=world;den=(b.y-c.y)*(a.x-c.x)+(c.x-b.x)*(a.y-c.y)
            if abs(den)<1e-16:continue
            wa=((b.y-c.y)*(x-c.x)+(c.x-b.x)*(y-c.y))/den
            wb=((c.y-a.y)*(x-c.x)+(a.x-c.x)*(y-c.y))/den;wc=1-wa-wb
            if min(wa,wb,wc)<-1e-4:continue
            target_uv=None
            if uv_layer:target_uv=sum((loop[uv_layer].uv*w for loop,w in zip(face.loops,(wa,wb,wc))),Vector((0.,0.)))
            vertex=next((v for v,p in zip(face.verts,world) if math.hypot(p.x-x,p.y-y)<1e-7),None)
            operation="existing_vertex_resample"
            if vertex is None:
                for edge in face.edges:
                    p,q=[terrain.matrix_world@v.co for v in edge.verts]
                    distance,t=point_segment(x,y,p,q)
                    if distance<1e-7 and 1e-6<t<1-1e-6:
                        _,vertex=bmesh.utils.edge_split(edge,edge.verts[0],t);operation="shared_edge_split";break
            if vertex is None:
                result=bmesh.ops.poke(bm,faces=[face],offset=0.,center_mode="MEAN_WEIGHTED")
                vertex=result["verts"][0];operation="connected_triangle_insertion"
            vertex.co=inverse@Vector((x,y,height(x,y)))
            if target_uv is not None:
                for loop in vertex.link_loops:loop[uv_layer].uv=target_uv
            anchors.append({"road_id":identity,"xy_m":[x,y],"datum_m":z,"authority_z_m":height(x,y),
                "previous_ground_overshoot_m":delta,"operation":operation,"pass":anchor_pass+1,
                "source_face_vertices_m":[list(p) for p in world]});added+=1
        if not added:bm.free();break
        bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(terrain.data);bm.free();terrain.data.update();terrain.update_tag(refresh={"DATA"})
        bad,_,_,_=measure()
    after=measure()
    return {"status":"PASS" if not after[0] and not after[3] else "FAIL","sample_count":len(samples),"passes":passes,
            "added_vertices":len(terrain.data.vertices)-original_vertices,"maximum_before_error_m":before[1],
            "maximum_after_error_m":after[1],"maximum_ground_overshoot_m":after[2],"ray_misses":after[3],
            "exact_connected_contact_anchors":anchors,
            "unresolved_samples":[{"road_id":a,"xy_m":[x,y],"datum_m":z,"ground_delta_m":dz} for a,x,y,z,dz in after[0]][:100]}


def legacy_tree_assembly_masks(plan,height,base_height):
    """Recover immutable original tree groups from verified factory strides.

    refine_environment emits only tree() calls into this material batch. Each
    tree has326trunk,1225Leaf,490LeafLight and490LeafDark source vertices. This
    exact binding lets a changed root remove its whole tree across materials.
    """
    strides={"Trunk":326,"Leaf":1225,"LeafLight":490,"LeafDark":490};objects={}
    for role,stride in strides.items():
        ob=bpy.data.objects.get("Layered_Street_and_Orchard_Planting_"+role)
        if ob is None or ob.type!="MESH" or len(ob.data.vertices)%stride:
            raise RuntimeError("Original combined tree factory binding changed: "+role)
        objects[role]=ob
    counts={len(objects[role].data.vertices)//stride for role,stride in strides.items()}
    if len(counts)!=1:raise RuntimeError("Combined tree material batches disagree on assembly count")
    count=counts.pop();trunk=objects["Trunk"];mask=[];records=[]
    for index in range(count):
        # The first rod's lower nine-vertex ring is the exact root axis.
        points=[trunk.matrix_world@trunk.data.vertices[index*326+j].co for j in range(9)]
        x=sum(p.x for p in points)/9;y=sum(p.y for p in points)/9
        radius=0.
        for role,stride in strides.items():
            ob=objects[role]
            for vertex_index in range(index*stride,(index+1)*stride):
                vertex=ob.data.vertices[vertex_index]
                world=ob.matrix_world@vertex.co;radius=max(radius,math.hypot(world.x-x,world.y-y))
        delta=height(x,y)-base_height(x,y)
        conflict=canopy_conflicts(x,y,radius,plan) or abs(delta)>.035
        mask.append(conflict)
        if conflict:records.append({"original_tree_index":index,"root_xy_m":[x,y],"canopy_radius_m":radius,"introduced_ground_delta_m":delta})
    return {role:(stride,mask) for role,stride in strides.items()},records


def clip_baseline_obstacles(plan,height=None,baseline_root=None):
    baseline_root=Path(baseline_root or REPO/"art/living_town")
    height=height or terrain_function(plan,baseline_root)
    original=module("expansion_obstacle_original_surface",baseline_root/"tools/reserve_plan.py")
    original._ensure_plan();base_height=original.design_height
    assembly_masks,assembly_records=legacy_tree_assembly_masks(plan,height,base_height)
    clipped=[]
    for ob in list(bpy.context.scene.objects):
        if ob.type!="MESH" or not ob.name.startswith(("Reserve_Ferns_Heather_and_Fallen_Wood","Reserve_Granite_Outcrops_and_Talus",
                                                   "Layered_Street_and_Orchard_Planting","Bocage_Field_Walls_and_Hedges")):
            continue
        log("Clip local reserve ground cover: "+ob.name)
        bm=bmesh.new();bm.from_mesh(ob.data);bm.verts.ensure_lookup_table();bm.verts.index_update()
        # Delete connected source primitives in the corridor. Their original
        # disconnected rods/leaves/rocks were combined into material batches.
        # This preserves outside UV/material geometry and avoids sliced rocks.
        seen=set();delete=[]
        legacy_role=ob.name.removeprefix("Layered_Street_and_Orchard_Planting_")
        if legacy_role in assembly_masks:
            stride,mask=assembly_masks[legacy_role]
            delete=[v for v in bm.verts if mask[v.index//stride]]
            seen.update(bm.verts)
        for vertex in bm.verts:
            if vertex in seen:continue
            stack=[vertex];seen.add(vertex);component=[]
            while stack:
                current=stack.pop();component.append(current)
                for edge in current.link_edges:
                    other=edge.other_vert(current)
                    if other not in seen:seen.add(other);stack.append(other)
            world=[ob.matrix_world@v.co for v in component]
            if ob.name.startswith("Bocage_Field_Walls_and_Hedges"):
                # Original-town vegetation is a combined world-space batch,
                # unlike linked reserve trees. Prune only connected crown /
                # trunk / hedge primitives crossing the new urban clearance.
                cx=sum(p.x for p in world)/len(world);cy=sum(p.y for p in world)/len(world)
                radius=max(math.hypot(p.x-cx,p.y-cy) for p in world)
                conflict=canopy_conflicts(cx,cy,radius,plan)
            else:conflict=any(vegetation_excluded(p.x,p.y,plan,3.4) for p in world)
            # Road earthworks include2m verge+3m shoulder. A source primitive
            # must also clear whenever the new field changes its old datum,
            # even outside the narrower walking/canopy exclusion.
            cx=sum(p.x for p in world)/len(world);cy=sum(p.y for p in world)/len(world)
            conflict=conflict or abs(height(cx,cy)-base_height(cx,cy))>.035
            if conflict:delete.extend(component)
        count=len(delete)
        if count:
            bmesh.ops.delete(bm,geom=delete,context="VERTS")
            bmesh.ops.triangulate(bm,faces=list(bm.faces))
            bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
            bm.to_mesh(ob.data);ob.data.update()
            if any(len(face.vertices)!=3 for face in ob.data.polygons):raise RuntimeError("Clipped reserve export mesh has nontriangles: "+ob.name)
            clipped.append({"name":ob.name,"removed_vertices":count,"remaining_triangles":len(ob.data.polygons),"triangulated":True,
                            "whole_legacy_tree_assemblies_cleared":len(assembly_records) if legacy_role in assembly_masks else 0,
                            "legacy_tree_clearance_records":assembly_records if legacy_role=="Trunk" else []})
        bm.free()
    return clipped


def update_baseline(plan,height,baseline_root=None):
    changed=0
    # Remove complete linked assemblies by measured crown extent, preserving
    # the surrounding forest and all shared source mesh data.
    removed,tree_clearance=clear_baseline_tree_canopies(plan)
    clipped=clip_baseline_obstacles(plan,height,baseline_root)
    terrain=bpy.data.objects.get("Atlantic_Terrain_Grass")
    if terrain is None or terrain.type!="MESH":
        raise RuntimeError("Baseline is missing Atlantic_Terrain_Grass")
    # Refine the existing connected mesh locally. Subdividing shared edges
    # also splits neighboring polygons, so there are no overlay z-fights or
    # T-junctions along a separate floating terrain patch.
    terrain_index=defaultdict(list);cell=20.
    def put(item,bounds):
        for xx in range(math.floor(bounds[0]/cell),math.floor(bounds[2]/cell)+1):
            for yy in range(math.floor(bounds[1]/cell),math.floor(bounds[3]/cell)+1):terrain_index[xx,yy].append(item)
    for pad in plan["terrain"]["pads"]:
        x,y=pad["center_m"];r=math.hypot(pad["width_m"],pad["depth_m"])/2+pad["blend_m"]+3
        put(("pad",pad),(x-r,y-r,x+r,y+r))
    for road in plan["roads"]+plan.get("approaches",[]):
        r=road["width_m"]/2+road.get("graded_verge_m",.3)+road.get("shoulder_m",1.2)+3
        for a,b in zip(road["points_m"],road["points_m"][1:]):
            put(("road",(a,b,r)),(min(a[0],b[0])-r,min(a[1],b[1])-r,max(a[0],b[0])+r,max(a[1],b[1])+r))
    def near(x,y):
        for kind,value in terrain_index.get((math.floor(x/cell),math.floor(y/cell)),()):
            if kind=="road":
                a,b,r=value
                if point_segment(x,y,a,b)[0]<=r:return True
            else:
                p=value;a=math.radians(p["yaw_degrees"]);dx=x-p["center_m"][0];dy=y-p["center_m"][1]
                lx=dx*math.cos(a)+dy*math.sin(a);ly=-dx*math.sin(a)+dy*math.cos(a)
                if math.hypot(max(0,abs(lx)-p["width_m"]/2),max(0,abs(ly)-p["depth_m"]/2))<=p["blend_m"]+3:return True
        return False
    bm=bmesh.new();bm.from_mesh(terrain.data);edge_set=set();faces_before=len(bm.faces);verts_before=len(bm.verts)
    for face in bm.faces:
        center=terrain.matrix_world@face.calc_center_median()
        if near(center.x,center.y):
            edge_set.update(e for e in face.edges if e.calc_length()>.8)
    log("Locally tessellate %d terrain edges"%len(edge_set))
    if edge_set:bmesh.ops.subdivide_edges(bm,edges=list(edge_set),cuts=7,use_grid_fill=True)
    bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(terrain.data);bm.free()
    tessellation={"before_vertices":verts_before,"before_faces":faces_before,
                  "after_vertices":len(terrain.data.vertices),"after_faces":len(terrain.data.polygons),
                  "refined_source_edges":len(edge_set),"maximum_original_4m_grid_diagonal_segment_m":math.sqrt(32)/8,
                  "policy":"Connected local edge subdivision around all new pad/road blend buffers; no separate floating overlay; forest outside buffers retains original topology."}
    # The baseline batch writes world-space vertices; handle transforms anyway.
    inverse=terrain.matrix_world.inverted()
    for v in terrain.data.vertices:
        world=terrain.matrix_world@v.co
        newz=height(world.x,world.y)
        if abs(newz-world.z)>.00005:
            v.co=inverse@Vector((world.x,world.y,newz));changed+=1
    terrain.data.update()
    pad_repair=repair_pad_contacts(terrain,plan,height)
    if pad_repair["status"]!="PASS":raise RuntimeError("Actual terrain pad contacts remain outside 15cm: "+str(pad_repair["failures"]))
    road_repair=repair_road_surface_contacts(terrain,plan,height)
    if road_repair["status"]=="FAIL":raise RuntimeError("Actual road cross sections remain occluded or outside contact tolerance: "+str(road_repair))
    terrain_finish=refresh_graded_terrain_faces(terrain,plan)
    return {"removed_tree_mesh_objects":len(removed),"removed_tree_names":removed,
            "removed_tree_assemblies":len(tree_clearance),"canopy_clearance_records":tree_clearance,
            "removed_baseline_object_names":removed+[r["name"] for r in clipped]+[terrain.name],
            "replacement_baseline_object_names":[terrain.name]+[r["name"] for r in clipped],
            "clipped_ground_cover":clipped,
            "local_tessellation":tessellation,
            "actual_pad_contact_repair":pad_repair,
            "actual_road_contact_repair":road_repair,
            "grading_surface_finish":terrain_finish,
            "updated_terrain_vertices":changed,"terrain_object":terrain.name,
            "policy":"Shared tree meshes retained; whole linked assemblies cleared using actual mesh-derived XY crown radius plus roof/sidewalk margins. Terrain uses the planner height authority. Clipped ground-cover batches are physically triangulated for tangent export."}


def solid_prism(batch,xy_corners,top_levels,bottom_levels,material):
    """A closed connected eight-vertex solid, with no disconnected plates."""
    vertices=[(x,y,z) for (x,y),z in zip(xy_corners,bottom_levels)]+[(x,y,z) for (x,y),z in zip(xy_corners,top_levels)]
    batch.poly(vertices,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],material)


def roads(plan,height,col):
    result=[]
    for road in plan["roads"]+plan.get("approaches",[]):
        batch=Batch(road["id"],col);support=Batch(road["id"]+"_ClosedBedding",col);support_records=[]
        points=road["points_m"];width=road["width_m"]
        pavement="Courtyard" if road.get("kind") in ("passage","footpath","lane","pedestrian") else "Road"
        sections=road_sections(road)
        for index,(a,b) in enumerate(zip(sections,sections[1:])):
            offsets=a["offsets_m"]
            if offsets!=b["offsets_m"]:raise ValueError("Road section lateral topology changed within ribbon: "+road["id"])
            for strip in range(len(offsets)-1):
                middle=(offsets[strip]+offsets[strip+1])/2
                mat=pavement if abs(middle)<width/2 else "Courtyard";offset=.035 if abs(middle)<width/2 else .055
                aa,ab=a["points_m"][strip:strip+2];ba,bb=b["points_m"][strip:strip+2]
                vertices=[(p[0],p[1],p[2]+offset) for p in (aa,ab,ba,bb)]
                batch.poly(vertices,[(0,2,3),(0,3,1)],mat)
                # Every elevated strip receives its own manifold8vertex solid;
                # variable crossfall is retained at all four top corners.
                ground=[];gaps=[]
                for t in (0.,.5,1.):
                    for s in (0.,.5,1.):
                        p=[(aa[k]*(1-s)+ab[k]*s)*(1-t)+(ba[k]*(1-s)+bb[k]*s)*t for k in range(3)]
                        datum=height(*p[:2]);ground.append(datum);gaps.append(p[2]+offset-datum)
                if max(gaps)>.10:
                    corners=[p[:2] for p in (aa,ab,bb,ba)];tops=[p[2]+offset-.01 for p in (aa,ab,bb,ba)];bottom=min(ground)-.30
                    solid_prism(support,corners,tops,[bottom]*4,"Stone")
                    support_records.append({"id":road["id"]+f"_BeddingSolid_{index}_{strip}","road_id":road["id"],
                        "source_segment":index,"lateral_strip":strip,"corners_xy_m":[list(p) for p in corners],"top_z_m":tops,
                        "bottom_z_m":[bottom]*4,"maximum_sampled_deck_gap_m":max(gaps),
                        "minimum_sampled_deck_gap_m":min(gaps),"topology":"one closed connected 8-vertex prism / 12 triangles"})
            # Curb stones remain real geometry; short gaps allow surface water
            # to reach the unpaved verge instead of a continuous retaining dam.
            if index%2==0:
                for side in (-1,1):
                    j=min(range(len(offsets)),key=lambda k:abs(offsets[k]-side*width/2))
                    pa,pb=a["points_m"][j],b["points_m"][j]
                    batch.rod((pa[0],pa[1],pa[2]+.055),(pb[0],pb[1],pb[2]+.055),.045,"Stone",n=4)
        obs=batch.flush()
        for ob in obs:ob["road_id"]=road["id"];ob["semantic_role"]="graded_street"
        support_objects=support.flush()
        for ob in support_objects:
            ob["road_id"]=road["id"];ob["semantic_role"]="raised_road_bedding";ob["closed_solid_components"]=len(support_records)
        for record in support_records:record["mesh_objects"]=[o.name for o in support_objects]
        result.append({"id":road["id"],"mesh_objects":[o.name for o in obs],"width_m":width,"profile_point_count":len(points),
                       "paving_section_count":len(sections),"paving_surface":"explicit conformed datum sections" if road.get("paved_sections_m") else "historical flat datum sections",
                       "sidewalk_width_each_m":road_sidewalk_width(road),"paved_width_m":width+2*road_sidewalk_width(road),
                       "raised_road_support_objects":[o.name for o in support_objects],
                       "raised_road_supports":support_records,"raised_road_solid_count":len(support_records)})
    return result


def constrained_retaining_walls(plan,height,col,contacts,terrain):
    """Measured inset masonry and stone bank finish at constrained contacts."""
    records=[];bank_zones=[];owners=set()
    for contact in contacts:
        x,y=contact["xy_m"];road=next((r for r in plan["roads"]+plan.get("approaches",[]) if r["id"]==contact["road_id"]),None)
        if road is None:continue
        sections=road_sections(road);edge_segments=[]
        for a,b in zip(sections,sections[1:]):
            for j in (0,-1):edge_segments.append((a["points_m"][j],b["points_m"][j]))
        def nearest(px,py):
            best=(float("inf"),None)
            for a,b in edge_segments:
                distance,t=point_segment(px,py,a,b)
                if distance<best[0]:best=(distance,[a[k]*(1-t)+b[k]*t for k in range(3)])
            return best
        for building in plan["buildings"]:
            if building["id"] in owners:continue
            pad=next(p for p in plan["terrain"]["pads"] if p["owner"]==building["id"])
            angle=math.radians(building["yaw_degrees"]);co,si=math.cos(angle),math.sin(angle)
            dx,dy=x-building["center"][0],y-building["center"][1];lx,ly=dx*co+dy*si,-dx*si+dy*co
            hw,hd=pad["width_m"]/2,pad["depth_m"]/2
            distance=math.hypot(max(0,abs(lx)-hw),max(0,abs(ly)-hd))
            if distance>.4 or building["pad_level_m"]-height(x,y)<.15:continue
            owners.add(building["id"]);batch=Batch(building["id"]+"_ConstrainedRetaining",col,(*building["center"],building["pad_level_m"]),angle)
            margin=min((pad["width_m"]-building["width"])/2,(pad["depth_m"]-building["depth"])/2)
            thickness=min(.24,margin-.04)
            if thickness<=.05:raise RuntimeError("Constrained retaining has no safe shell margin: "+building["id"])
            edges=[((-hw,-hd),(hw,-hd),(0,-1),True),((hw,hd),(-hw,hd),(0,1),False),
                   ((-hw,hd),(-hw,-hd),(-1,0),False),((hw,-hd),(hw,hd),(1,0),False)]
            owner_records=[]
            for side,(a,b,outward,front) in enumerate(edges):
                if front:continue # The entrance always keeps its explicit approach.
                if side==1:
                    # Side runs own the corner squares. Butt the rear run
                    # against them, avoiding overlapping coplanar stone tops.
                    a=(a[0]-thickness,a[1]);b=(b[0]+thickness,b[1])
                count=max(1,math.ceil(math.dist(a,b)/.25));length=math.dist(a,b)/count;rot=math.atan2(b[1]-a[1],b[0]-a[0])
                for i in range(count):
                    t=(i+.5)/count;ex,ey=a[0]*(1-t)+b[0]*t,a[1]*(1-t)+b[1]*t
                    wx,wy,_=local_world(building,ex,ey);clearance,low=nearest(wx,wy)
                    if clearance>.65 or building["pad_level_m"]-low[2]<.15:continue
                    cx,cy=ex-outward[0]*thickness/2,ey-outward[1]*thickness/2
                    toe=min(low[2]-.12,height(wx,wy)-.12);top=building["pad_level_m"]+.05
                    corners=[]
                    for along,across in ((-length/2,-thickness/2),(length/2,-thickness/2),(length/2,thickness/2),(-length/2,thickness/2)):
                        px=cx+along*math.cos(rot)-across*math.sin(rot);py=cy+along*math.sin(rot)+across*math.cos(rot)
                        corners.append(local_world(building,px,py)[:2])
                    actual_clearance=min(nearest(*p)[0] for p in corners)
                    if actual_clearance<.025:raise RuntimeError("Inset retaining would intrude on sidewalk: "+building["id"])
                    batch.box((cx,cy,(top+toe)/2-building["pad_level_m"]),(length,thickness,top-toe),"Granite",rot)
                    row={"id":building["id"]+f"_Constrained_{side}_{i}","building_id":building["id"],"road_id":road["id"],
                        "minimum_full_sidewalk_clearance_m":actual_clearance,"shell_clearance_m":margin-thickness,
                        "top_world_z_m":top,"toe_world_z_m":toe,"footprint_world_xy_m":corners,
                        "collision_obb":{"center_world_m":local_world(building,cx,cy,(top+toe)/2-building["pad_level_m"]),
                            "dimensions_m":[length,thickness,top-toe],"yaw_degrees":building["yaw_degrees"]+math.degrees(rot)}}
                    owner_records.append(row)
                    bank_zones.append((building,side,ex,ey,length,outward,low[2],top))
            objects=batch.flush()
            for ob in objects:ob["semantic_role"]="constrained_pad_retaining_wall";ob["building_id"]=building["id"]
            for row in owner_records:row["mesh_objects"]=[o.name for o in objects]
            records.extend(owner_records)
    # Exposed earth between the inset support and the paving is the measured
    # steep bank itself. Finish those actual connected terrain faces in granite
    # after the general grass refresh; no floating plate masks the contact.
    changed=0;minimum_uv_area=float("inf");degenerate_uv=0
    if bank_zones:
        material=persistent_material(MATS["Granite"]);slot=next((i for i,m in enumerate(terrain.data.materials) if m==material),None)
        if slot is None:slot=len(terrain.data.materials);terrain.data.materials.append(material)
        uv=terrain.data.uv_layers.get("MetricUV")
        if uv is None:raise RuntimeError("Constrained granite bank requires the source MetricUV layer")
        cache={};zone_index=defaultdict(list)
        for zone in bank_zones:
            building,side,ex,ey,length,*_=zone;wx,wy,_=local_world(building,ex,ey);radius=length/2+.5
            for gx in range(math.floor((wx-radius)/2),math.floor((wx+radius)/2)+1):
                for gy in range(math.floor((wy-radius)/2),math.floor((wy+radius)/2)+1):zone_index[gx,gy].append(zone)
        for face in terrain.data.polygons:
            p=terrain.matrix_world@face.center
            for building,side,ex,ey,length,outward,low,top in zone_index.get((math.floor(p.x/2),math.floor(p.y/2)),()):
                key=building["id"]
                if key not in cache:cache[key]=(math.cos(math.radians(building["yaw_degrees"])),math.sin(math.radians(building["yaw_degrees"])))
                co,si=cache[key];dx,dy=p.x-building["center"][0],p.y-building["center"][1]
                points=[terrain.matrix_world@terrain.data.vertices[i].co for i in face.vertices]
                normal=(points[1]-points[0]).cross(points[2]-points[0])
                steep=normal.length>1e-12 and abs(normal.z)/normal.length<.75
                def in_bank(point):
                    dx,dy=point.x-building["center"][0],point.y-building["center"][1]
                    lx,ly=dx*co+dy*si,-dx*si+dy*co
                    across=(lx-ex)*outward[0]+(ly-ey)*outward[1]
                    along=abs((lx-ex)*outward[1]-(ly-ey)*outward[0])
                    return (-.05<=across<=.45 and along<=length/2+.10) or (steep and (lx-ex)**2+(ly-ey)**2<.65**2)
                # Boundary triangles can straddle a narrow contact while
                # their centroid lies above the pad or just outside a zone.
                # Finish the complete adjacent triangle, avoiding green seams.
                if in_bank(p) or any(in_bank(point) for point in points):
                    face.material_index=slot;face.use_smooth=False;changed+=1
                    # The original grass uses XY projection. A near-vertical
                    # retaining bank needs metric elevation in its stone UVs,
                    # otherwise a58cm face would stretch a1cm texture strip.
                    dominant=max(range(3),key=lambda k:abs(normal[k]))
                    axes=[k for k in range(3) if k!=dominant];coords=[]
                    for loop,point in zip(face.loop_indices,points):
                        coord=(point[axes[0]]/2,point[axes[1]]/2);uv.data[loop].uv=coord;coords.append(coord)
                    area=abs((coords[1][0]-coords[0][0])*(coords[2][1]-coords[0][1])-(coords[1][1]-coords[0][1])*(coords[2][0]-coords[0][0]))/2
                    minimum_uv_area=min(minimum_uv_area,area);degenerate_uv+=area<1e-14
                    break
        terrain.data.update()
        if degenerate_uv:raise RuntimeError("Constrained bank contains degenerate granite UV triangles")
        terrain.data.calc_tangents(uvmap="MetricUV")
    if contacts and not records:raise RuntimeError("Exact retaining contact lacks a measured physical masonry case")
    return {"segments":records,"segment_count":len(records),"granite_bank_terrain_faces":changed,
            "granite_bank_uv":{"layer":"MetricUV","projection":"Per-face dominant world axes, metres /2; original grass loops preserved",
                "minimum_triangle_uv_area":minimum_uv_area if changed else None,"degenerate_triangles":degenerate_uv,
                "actual_tangent_calculation":"PASS" if changed else "NOT_APPLICABLE"},
            "policy":"Inset closed granite supports remain within the pad's shell margin; full sidewalk stays clear. Actual exposed narrow bank faces use granite after grass refresh, with original connected UV/topology retained."}


def retaining_walls(plan,height,col,baseline_root=None,constrained_contacts=None,terrain=None):
    """Explicit stone support where a terrace rises >.75m in one metre.

    The continuous terrain authority remains untouched. Visible masonry follows
    its sampled top/toe; central door approaches and public ribbons stay open.
    """
    records=[];skips=defaultdict(int)
    if id(plan) not in EXCLUSION_INDEX:vegetation_excluded(0,0,plan,0)
    lot_index,road_index=EXCLUSION_INDEX[id(plan)]
    def clear(x,y,owner):
        key=(math.floor(x/20),math.floor(y/20))
        for other in lot_index.get(key,()):
            if other["id"]==owner:continue
            a=math.radians(other["yaw_degrees"]);dx=x-other["center"][0];dy=y-other["center"][1]
            lx=dx*math.cos(a)+dy*math.sin(a);ly=-dx*math.sin(a)+dy*math.cos(a)
            if math.hypot(max(0,abs(lx)-other["width"]/2),max(0,abs(ly)-other["depth"]/2))<1.55:return False
        for a,b,width in road_index.get(key,()):
            if point_segment(x,y,a,b)[0]<width/2+1.10:return False
        return True
    for b in plan["buildings"]:
        w,d=b["width"],b["depth"];batch=Batch(b["id"]+"_GraniteRetaining",col,(*b["center"],b["pad_level_m"]),math.radians(b["yaw_degrees"]))
        edges=[((-w/2,-d/2),(w/2,-d/2),(0,-1),True),
               ((w/2,d/2),(-w/2,d/2),(0,1),False),
               ((-w/2,d/2),(-w/2,-d/2),(-1,0),False),
               ((w/2,-d/2),(w/2,d/2),(1,0),False)]
        for side,(a,c,outward,front) in enumerate(edges):
            length=math.dist(a,c);count=math.ceil(length/.85);segment=length/count
            angle=math.atan2(c[1]-a[1],c[0]-a[0])
            for i in range(count):
                t=(i+.5)/count;px=a[0]*(1-t)+c[0]*t;py=a[1]*(1-t)+c[1]*t
                if front and abs(px)<.95+segment/2:skips["door_approach"]+=1;continue
                # Graded pads extend .30m beyond the wall footprint. The
                # samples straddle that exact edge and its outside1m point.
                lx,ly=px+outward[0]*.80,py+outward[1]*.80
                x,y,z=local_world(b,lx,ly)
                if not clear(x,y,b["id"]):skips["public_or_between_building_clearance"]+=1;continue
                inner=local_world(b,lx-outward[0]*.5,ly-outward[1]*.5)
                outer=local_world(b,lx+outward[0]*.5,ly+outward[1]*.5)
                zi,zo=height(*inner[:2]),height(*outer[:2]);difference=abs(zi-zo)
                if difference<=.75:continue
                top=max(zi,zo)+.06;toe=min(zi,zo)-.16;wall_height=top-toe
                centre_z=(top+toe)/2-b["pad_level_m"]
                batch.box((lx,ly,centre_z),(segment-.02,.26,wall_height),"Stone",angle)
                batch.box((lx,ly,top-b["pad_level_m"]+.025),(segment,.36,.10),"Granite",angle)
                # Mortar reveals and half-metre blocks add readable masonry
                # scale to the existing physical 0.5m granite scan repeat.
                for j in range(1,int(wall_height/.27)):
                    zz=toe+j*.27-b["pad_level_m"]
                    batch.box((lx,ly,zz),(segment-.025,.272,.014),"Dirt",angle)
                records.append({"id":b["id"]+f"_Retaining_{side}_{i}","building_id":b["id"],
                    "grade_difference_across_1m_m":difference,"top_world_z_m":top,"toe_world_z_m":toe,
                    "collision_obb":{"center_world_m":local_world(b,lx,ly,centre_z),
                        "dimensions_m":[segment,.36,wall_height+.10],"yaw_degrees":b["yaw_degrees"]+math.degrees(angle)}})
        objects=batch.flush()
        for ob in objects:ob["semantic_role"]="granite_terrace_retaining_wall";ob["building_id"]=b["id"]
        for row in records:
            if row["building_id"]==b["id"]:row["mesh_objects"]=[o.name for o in objects]
    # Narrow preserved-core and trail shoulders can be continuous yet steep.
    # Measured masonry supports these masks; the planner explicitly leaves
    # connected-road/approach gaps open for the closed causeway bedding above.
    planner=sys.modules.get("expansion_territory") or module("expansion_territory",REPO/"tools/town_generation/territory.py")
    boundary=planner.retained_boundary_segments(plan,Path(baseline_root or REPO/"art/living_town"))
    boundary_records=[];batches={};by_source=defaultdict(list)
    for row in boundary:
        source=row["source_id"]
        if source not in batches:batches[source]=Batch("PreservationRetaining_"+source,col)
        batch=batches[source];a,b=row["points_xy"];normal=row["side_normal_xy"]
        samples=[a,[(a[k]+b[k])/2 for k in range(2)],b]
        # Two halves follow the measured midpoint, rather than bridging a
        # curved bank with an inaccurately constant elevation.
        for half in (0,1):
            p,q=samples[half:half+2];inside=-.06;outside=row["span_m"]+.06
            corners=[(p[0]+normal[0]*inside,p[1]+normal[1]*inside),
                     (p[0]+normal[0]*outside,p[1]+normal[1]*outside),
                     (q[0]+normal[0]*outside,q[1]+normal[1]*outside),
                     (q[0]+normal[0]*inside,q[1]+normal[1]*inside)]
            topa,topb=row["sampled_tops_m"][half:half+2];toea,toeb=row["sampled_toes_m"][half:half+2]
            solid_prism(batch,corners,[topa,topa,topb,topb],[toea,toea,toeb,toeb],"Stone")
            solid_prism(batch,corners,[topa+.05,topa+.05,topb+.05,topb+.05],[topa-.02,topa-.02,topb-.02,topb-.02],"Granite")
        center=[(a[k]+b[k])/2+normal[k]*row["span_m"]/2 for k in range(2)]
        top=max(row["sampled_tops_m"])+.05;toe=min(row["sampled_toes_m"])
        record={**row,"collision_obb":{"center_world_m":[*center,(top+toe)/2],
            "dimensions_m":[math.dist(a,b),row["width_m"],top-toe],"yaw_degrees":math.degrees(math.atan2(b[1]-a[1],b[0]-a[0]))}}
        boundary_records.append(record);by_source[source].append(record)
    for source,batch in batches.items():
        objects=batch.flush()
        for ob in objects:ob["semantic_role"]="preservation_boundary_retaining_wall";ob["preserved_route_id"]=source
        for row in by_source[source]:row["mesh_objects"]=[o.name for o in objects]
    constrained=constrained_retaining_walls(plan,height,col,constrained_contacts or [],terrain or bpy.data.objects["Atlantic_Terrain_Grass"])
    return {"segments":records,"segment_count":len(records),"skipped":dict(skips),"constrained_retaining":constrained,
            "preservation_boundary_segments":boundary_records,"preservation_boundary_segment_count":len(boundary_records),
            "front_approach_minimum_gap_m":1.9,
            "policy":"Actual metric stone/coping geometry at steep continuous-field terrace transitions; no terrain discontinuity is hidden or introduced. Measured OBB metadata supports consumer physics; structural certification is not claimed."}


def prototypes(col):
    """Low-cost linked urban props and trees. Full forest stays instanced."""
    hidden=bpy.data.collections.new("Expansion_Prototype_Data_NotInScene")
    result={}
    for label,leaf,radius,height in (("rowan","LeafLight",1.7,5.8),("lime","Leaf",2.5,8.0),("birch","LeafLight",1.8,8.5)):
        b=Batch("ExpansionProto_"+label,hidden)
        b.rod((0,0,0),(0,0,height*.78),.12 if label=="birch" else .18,"Trunk",n=7,r2=.045)
        for i in range(9):
            a=i*2.39996;z=height*(.48+i*.037);x=math.cos(a)*radius*.64;y=math.sin(a)*radius*.64
            b.rod((0,0,z-.8),(x,y,z+.5),.055,"Trunk",n=6,r2=.018)
            b.ellipsoid((x,y,z+1),(radius*.72,radius*.65,1.65),leaf if i%3 else "LeafDark",n=9,rings=4)
        result[label]=[o.data for o in b.flush()]
    b=Batch("ExpansionProto_FlowerPlanter",hidden)
    b.rod((0,0,0),(0,0,.35),.27,"Terracotta",n=12,r2=.36)
    for i in range(13):
        a=i*2.39996;r=.33*math.sqrt((i+.5)/13);x,y=math.cos(a)*r,math.sin(a)*r
        b.ellipsoid((x,y,.51),(.20,.19,.18),"Leaf",n=7,rings=3)
        for j in range(4):
            b.ellipsoid((x+math.cos(j*math.pi/2)*.06,y+math.sin(j*math.pi/2)*.06,.71),(.09,.085,.045),"BloomBlue" if i%3 else "BloomCream",n=6,rings=3)
    result["flowers"]=[o.data for o in b.flush()]
    b=Batch("ExpansionProto_Bench",hidden)
    for x in (-.65,.65):
        b.rod((x,0,.04),(x,0,.47),.035,"Iron",n=7)
        b.rod((x,.17,.40),(x,.17,.90),.035,"Iron",n=7)
    for j in range(4):b.box((0,-.18+j*.12,.47),(1.65,.10,.05),"Oak")
    for j in range(3):b.box((0,.21,.62+j*.11),(1.65,.05,.08),"Oak")
    result["bench"]=[o.data for o in b.flush()]
    b=Batch("ExpansionProto_Lamp",hidden)
    b.rod((0,0,0),(0,0,3.2),.045,"Iron",n=9)
    b.rod((0,0,3.05),(0,0,3.35),.23,"Iron",n=4,r2=.04)
    b.box((0,0,3.05),(.28,.28,.35),"Lamp")
    result["lamp"]=[o.data for o in b.flush()]
    # Prototypes' object containers are unused and outside the scene. Mesh
    # references remain in the cache and are shared by actual scene objects.
    for ob in list(hidden.objects):
        NEW_OBJECTS.remove(ob)
        bpy.data.objects.remove(ob,do_unlink=True)
    bpy.data.collections.remove(hidden)
    return result


def detailed_prototypes():
    """Evaluate four small crafted prototypes once, then share mesh data."""
    foliage=module("expansion_hero_foliage",REPO/"tools/asset_refinement/hero_foliage.py")
    furniture=module("expansion_hero_furniture",REPO/"tools/asset_refinement/hero_furniture.py")
    fm={"cabinet_oak":MATS["Oak"],"honed_granite":MATS["Granite"],"iron":MATS["Iron"],
        "brass":MATS["Brass"],"glass":MATS["Glass"],"ceramic":MATS["White"],
        "cane":MATS["Linen"],"pastry":MATS["Terracotta"],"coffee":MATS["Ink"],"bottle_green":MATS["Sage"]}
    leaves={"bark":MATS["Trunk"],"leaf_dark":MATS["LeafDark"],"leaf_mid":MATS["Leaf"],
            "leaf_light":MATS["LeafLight"],"bloom_blue":MATS["BloomBlue"],"bloom_cream":MATS["BloomCream"]}
    factories={"hero_tree":lambda c:foliage.build_tree(c,height=7,crown_radius=2.5,materials=leaves),
               "hydrangea":lambda c:foliage.build_hydrangea(c,radius=.55,materials=leaves),
               "hero_counter":lambda c:furniture.build_counter(c,materials=fm),
               "hero_bistro":lambda c:furniture.build_bistro_set(c,materials=fm)}
    result={};reports={}
    for name,factory in factories.items():
        log("Evaluate detailed prototype "+name)
        temp=collection("Expansion_Detailed_Prototype_Temporary_"+name)
        factory(temp);bpy.context.view_layer.update()
        originals=list(temp.objects);depsgraph=bpy.context.evaluated_depsgraph_get()
        holder=bpy.data.collections.new("Expansion_Detailed_Cache_"+name)
        batch=Batch("ExpansionProto_"+name,holder)
        for ob in originals:
            if ob.type!="MESH":continue
            evaluated=ob.evaluated_get(depsgraph);mesh=evaluated.to_mesh(preserve_all_data_layers=True,depsgraph=depsgraph)
            vertices=[tuple(ob.matrix_world@v.co) for v in mesh.vertices]
            uv=mesh.uv_layers.active
            for poly in mesh.polygons:
                material=persistent_material(mesh.materials[poly.material_index])
                MATS[material.name]=material
                coords=[[tuple(uv.data[i].uv) for i in poly.loop_indices]] if uv else None
                batch.poly([vertices[i] for i in poly.vertices],[tuple(range(len(poly.vertices)))],material.name,coords)
            evaluated.to_mesh_clear()
        cached=batch.flush();result[name]=[o.data for o in cached]
        points=[v.co for mesh in result[name] for v in mesh.vertices]
        low=[min(p[k] for p in points) for k in range(3)];high=[max(p[k] for p in points) for k in range(3)]
        if name in ("hero_counter","hero_bistro"):
            offset=Vector(((low[0]+high[0])/2,(low[1]+high[1])/2,0))
            for mesh in result[name]:
                for vertex in mesh.vertices:vertex.co-=offset
            low=[low[0]-offset.x,low[1]-offset.y,low[2]]
            high=[high[0]-offset.x,high[1]-offset.y,high[2]]
        reports[name]={"bounds":{"min":low,"max":high},"unique_meshes":len(cached),
                       "prototype_triangles":sum(len(m.polygons) for m in result[name]),
                       "recipe":"Original hero factory evaluated once; material batches preserve UVs; all placements link shared triangulated meshes."}
        for ob in cached:
            NEW_OBJECTS.remove(ob);bpy.data.objects.remove(ob,do_unlink=True)
        for ob in originals:bpy.data.objects.remove(ob,do_unlink=True)
        bpy.data.collections.remove(temp);bpy.data.collections.remove(holder)
    return result,reports


def refine_focus_furniture(plan,records,proto,prototype_reports,interior_module,adapter):
    """Fit real hero footprints before replacing selected café assemblies."""
    reports=[];buildings={b["id"]:b for b in plan["buildings"]}
    for record in records:
        if record["id"] not in plan.get("detailed_focus_ids",[]) or record["kind"] not in ("cafe","creperie"):
            continue
        b=buildings[record["id"]];interior=record["interior"]
        ground=interior["levels"][0]
        for room in ground["rooms"]:
            if not any(a["kind"]=="cafe_counter" for a in room["assets"]):continue
            for kind,source in (("cafe_counter","hero_counter"),("cafe_table_set","hero_bistro")):
                candidates=[a for a in room["assets"] if a["kind"]==kind]
                cx=(room["bounds_m"][0]+room["bounds_m"][2])/2;cy=(room["bounds_m"][1]+room["bounds_m"][3])/2
                candidates.sort(key=lambda a:(a.get("detail_source")!=source,math.dist(a["center_m"],(cx,cy))))
                fitted=False
                for asset in candidates:
                    x,y=asset["center_m"];rotation=asset.get("rotation_degrees",0)
                    angle=math.radians(rotation);co,si=math.cos(angle),math.sin(angle)
                    bounds=prototype_reports[source]["bounds"];lo,hi=bounds["min"],bounds["max"]
                    corners=[(xx*co-yy*si,xx*si+yy*co) for xx in (lo[0],hi[0]) for yy in (lo[1],hi[1])]
                    a0,b0=min(p[0] for p in corners),min(p[1] for p in corners)
                    a1,b1=max(p[0] for p in corners),max(p[1] for p in corners)
                    ra,rb,rc,rd=room["bounds_m"]
                    reserved=asset.get("detail_source")==source
                    if not reserved:
                        x=max(ra+.09-a0,min(rc-.09-a1,x));y=max(rb+.09-b0,min(rd-.09-b1,y))
                    box=[x+a0,y+b0,x+a1,y+b1]
                    def overlap(p,q,margin=.04):
                        return min(p[2],q[2])-max(p[0],q[0])>-margin and min(p[3],q[3])-max(p[1],q[1])>-margin
                    edge_margin=.014 if reserved else .075
                    if box[0]<ra+edge_margin or box[1]<rb+edge_margin or box[2]>rc-edge_margin or box[3]>rd-edge_margin:continue
                    if any(overlap(box,other["footprint_m"],0 if reserved else .04) for other in room["assets"] if other is not asset):continue
                    if not reserved and any(overlap(box,k,0) for k in room.get("circulation_keepouts",[])+ground.get("access_keepouts",[])):continue
                    snapshot=copy.deepcopy(asset)
                    asset["center_m"]=[x,y];asset["dimensions_m"]=[hi[k]-lo[k] for k in range(3)]
                    asset["footprint_m"]=interior_module.asset_footprint(asset)
                    view={**interior,"floors":record["floor_count"]}
                    composition=interior_module.audit_furniture_compositions({"buildings":[view]})
                    navigation=adapter.audit_prepared_plans([view],authority=interior_module) if composition["status"]=="PASS" else {"status":"SKIPPED"}
                    if composition["status"]!="PASS" or navigation["status"]!="PASS":
                        asset.clear();asset.update(snapshot)
                        if reserved:raise RuntimeError("Measured hero reservation failed actual plan audit: "+asset["id"]+" "+str(composition.get("failures",[]))+str(navigation.get("failures",[])))
                        continue
                    old=set(asset.get("object_names",[]))
                    for name in old:
                        ob=bpy.data.objects.get(name)
                        if ob is not None:
                            if ob in NEW_OBJECTS:NEW_OBJECTS.remove(ob)
                            bpy.data.objects.remove(ob,do_unlink=True)
                    before=len(NEW_OBJECTS)
                    col=COLLECTION_BY_ID[room["id"]]
                    position=local_world(b,x,y,ground["finished_floor_local_z_m"])
                    place(proto,source,asset["id"]+"_Crafted",col,position,math.radians(b["yaw_degrees"]+rotation))
                    objects=NEW_OBJECTS[before:]
                    for ob in objects:
                        ob["interior_asset_id"]=asset["id"];ob["interior_room_id"]=room["id"]
                        ob["semantic_role"]="crafted_cafe_furniture";ob["furniture_front"]="-Y in assembly coordinates"
                    asset["object_names"]=[o.name for o in objects]
                    asset["detail_source"]=source
                    interior["object_names"]=[n for n in interior["object_names"] if n not in old]+asset["object_names"]
                    reports.append({"building_id":b["id"],"room_id":room["id"],"asset_id":asset["id"],"source":source,
                                    "position_local_m":[x,y],"footprint_local_xy_m":box,"rotation_degrees":rotation,
                                    "composition_audit":"PASS","navigation_privacy_audit":"PASS",
                                    "reserved_by_plan":reserved,
                                    "fit":"Measured geometry within room; no neighbor overlap; unchanged composition/navigation/privacy gates passed"})
                    fitted=True;break
                if not fitted:
                    if any(a.get("detail_source")==source for a in candidates):raise RuntimeError("Required hero furniture reservation not replaced: "+b["id"]+"/"+source)
                    reports.append({"building_id":b["id"],"room_id":room["id"],"source":source,"fit":"SKIPPED: full real footprint did not fit existing audited circulation"})
    return reports


def upstream_planter(path,proto,col):
    """Append a bounded separately generated upstream asset, evaluate once.

    Its source file and mesh data remain independently attributed. A normalized
    shared mesh is reused at every placement; modifiers are evaluated only on
    this small prototype, never on the forest or complete town.
    """
    path=path.resolve(strict=True)
    with bpy.data.libraries.load(str(path),link=False) as (source,target):
        target.objects=list(source.objects)
    temporary=collection("Expansion_Upstream_Planter_Temporary")
    loaded=[ob for ob in target.objects if ob is not None]
    for ob in loaded:temporary.objects.link(ob)
    bpy.context.view_layer.update()
    meshes=[ob for ob in loaded if ob.type=="MESH"]
    if not meshes:raise ValueError("Upstream planter has no mesh geometry")
    points=[ob.matrix_world@Vector(p) for ob in meshes for p in ob.bound_box]
    low=Vector(tuple(min(p[k] for p in points) for k in range(3)))
    high=Vector(tuple(max(p[k] for p in points) for k in range(3)))
    if max(high-low)>20 or max((high-low).x,(high-low).y)<.01:
        raise ValueError("Upstream planter bounds are not a bounded plant asset: "+str(tuple(high-low)))
    # The verified courtyard plant is already a 1.40m canopy / .44m high pot.
    # Preserve its native scale; normalize only its ground/centre origin.
    scale=1.
    center=Vector(((low.x+high.x)/2,(low.y+high.y)/2,low.z))
    cache=[];depsgraph=bpy.context.evaluated_depsgraph_get()
    for ob in meshes:
        evaluated=ob.evaluated_get(depsgraph)
        mesh=bpy.data.meshes.new_from_object(evaluated,preserve_all_data_layers=True,depsgraph=depsgraph)
        pin_material_slots(mesh)
        for vertex in mesh.vertices:vertex.co=(ob.matrix_world@vertex.co-center)*scale
        bm=bmesh.new();bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
        mesh.name="Expansion_Infinigen_Planter_"+ob.name
        cache.append(mesh)
    names=[ob.name for ob in meshes]
    for ob in loaded:bpy.data.objects.remove(ob,do_unlink=True)
    bpy.data.collections.remove(temporary)
    proto["upstream_planter"]=cache
    return {"path":str(path),"sha256":sha(path),"source_mesh_objects":names,
            "source_bounds_m":[list(low),list(high)],"normalized_xy_extent_m":max((high-low).x,(high-low).y),
            "prototype_meshes":len(cache),"triangles":sum(len(m.polygons) for m in cache),
            "policy":"Upstream separately generated meshes evaluated once and reused as shared local-metre planter geometry; no model inference."}


def place(proto,kind,ident,col,position,yaw=0,scale=1):
    for i,mesh in enumerate(proto[kind]):
        ob=bpy.data.objects.new(ident+"_"+str(i),mesh);col.objects.link(ob)
        ob.location=position;ob.rotation_euler[2]=yaw;ob.scale=(scale,)*3
        tag(ob,"urban_"+kind,prototype=kind)


def planting(plan,height,col,proto):
    counts=defaultdict(int);radius_cache={}
    def tree_fits(kind,x,y,scale):
        radius=max(shared_mesh_xy_radius(mesh,radius_cache) for mesh in proto[kind])*scale
        return not canopy_conflicts(x,y,radius,plan)
    for b in plan["buildings"]:
        ident=b["id"];w,d=b["width"],b["depth"]
        # Pots flank the door without entering the 1.45m threshold zone.
        for side in (-1,1):
            x,y,z=local_world(b,side*min(w*.35,2.5),-d/2-.55)
            place(proto,"flowers",ident+"_DoorFlowers_"+str(side),col,(x,y,height(x,y)+.04))
            counts["flower_planters"]+=1
            if "upstream_planter" in proto and (side==1 or b["id"] in plan.get("detailed_focus_ids",[])):
                # Leave a separate pot at the courtyard edge, beside the local
                # flowers and outside the protected entrance/circulation strip.
                ux,uy,uz=local_world(b,side*w*.28,d/2+1.2)
                place(proto,"upstream_planter",ident+"_Infinigen_"+str(side),col,(ux,uy,height(ux,uy)+.02))
                counts["upstream_shared_planters"]+=1
        # Gardens sit behind and beside building pads, using the same surface.
        for j,(lx,ly) in enumerate(((-w*.34,d/2+3.6),(w*.34,d/2+4.5))):
            x,y,z=local_world(b,lx,ly)
            if vegetation_excluded(x,y,plan,1.7):continue
            kind="hero_tree" if j==0 else ("rowan","lime","birch")[(b["seed"]+j)%3]
            scale=.83+(b["seed"]%20)/100
            if not tree_fits(kind,x,y,scale):
                # Relocate outside the graded court rather than forcing a
                # crown through its neighbor's roof or a public walkway.
                x,y,z=local_world(b,lx,ly+3.5)
                if not tree_fits(kind,x,y,scale):counts["canopy_conflict_skips"]+=1;continue
            place(proto,kind,ident+"_GardenTree_"+str(j),col,(x,y,height(x,y)),b["seed"]*.01,scale)
            counts["linked_trees"]+=1
            if kind=="hero_tree":counts["detailed_leaf_tree_instances"]+=1
        # Paired real-floret hydrangeas reinforce a maintained Breton garden.
        for side in (-1,1):
            x,y,z=local_world(b,side*(w/2+.8),d*.15)
            if vegetation_excluded(x,y,plan,.35):continue
            place(proto,"hydrangea",ident+"_Hydrangea_"+str(side),col,(x,y,height(x,y)),b["seed"]*.03,.86)
            counts["detailed_hydrangeas"]+=1
    for road in plan["roads"]:
        points=road["points_m"]
        walked=0;next_lamp=12;next_tree=8
        for a,b in zip(points,points[1:]):
            length=math.dist(a[:2],b[:2]);walked+=length
            if length<1e-6:continue
            nx,ny=-(b[1]-a[1])/length,(b[0]-a[0])/length
            if walked>=next_lamp:
                x,y=b[0]+nx*(road["width_m"]/2+1),b[1]+ny*(road["width_m"]/2+1)
                place(proto,"lamp",road["id"]+"_Lamp_"+str(counts["lamps"]),col,(x,y,height(x,y)))
                counts["lamps"]+=1;next_lamp+=26
            if walked>=next_tree:
                x,y=b[0]-nx*(road["width_m"]/2+3),b[1]-ny*(road["width_m"]/2+3)
                if not vegetation_excluded(x,y,plan,1.8):
                    tree_kind="hero_tree" if counts["linked_trees"]%3==0 else "lime"
                    if tree_fits(tree_kind,x,y,.78):
                        place(proto,tree_kind,road["id"]+"_AvenueTree_"+str(counts["linked_trees"]),col,(x,y,height(x,y)),walked*.21,.78)
                        counts["linked_trees"]+=1
                        if tree_kind=="hero_tree":counts["detailed_leaf_tree_instances"]+=1
                    else:counts["canopy_conflict_skips"]+=1
                next_tree+=17
    return dict(counts)


def classify_building_metadata(records):
    """Exact owner and cutaway roles from the native collection hierarchy.

    A parcel name may contain ``_Loop`` or end in ``_L04``. Neither is an
    interior-level separator. Consumers receive explicit metadata rather than
    reconstructing ownership or presentation from names and bounding boxes.
    """
    total=defaultdict(int);reports=[];failures=[];claimed={};normalized=0;assigned=0;prior_incorrect=0
    for record in records:
        ident=record["id"];root=bpy.data.collections.get(record["collections"]["root"])
        if root is None:raise RuntimeError("Missing building root for owner metadata: "+ident)
        objects=list(root.all_objects);members={ob.as_pointer() for ob in objects};layers={};local=defaultdict(int);fixed=0
        for ob in objects:
            key=ob.as_pointer()
            if key in claimed and claimed[key]!=ident:
                failures.append({"object":ob.name,"reason":"Object belongs to two building roots","owners":[claimed[key],ident]})
            claimed[key]=ident
            if ob.get("building_id")!=ident:assigned+=1
            if "building_id" in ob and ob.get("building_id")!=ident:prior_incorrect+=1
            ob["building_id"]=ident;ob["presentation_layer"]="structure";layers[key]="structure"
            if "interior_building_id" in ob and ob.get("interior_building_id")!=ident:
                ob["interior_building_id"]=ident;normalized+=1;fixed+=1;prior_incorrect+=1
        for role in ("front","roof","upper"):
            collection_name=record["collections"][role];col=bpy.data.collections.get(collection_name)
            if col is None:raise RuntimeError("Missing presentation collection: "+collection_name)
            for ob in col.all_objects:
                if ob.as_pointer() not in members:
                    failures.append({"object":ob.name,"reason":"Presentation object outside its building root","building_id":ident})
                    continue
                ob["presentation_layer"]=role;layers[ob.as_pointer()]=role
        for ob in objects:
            expected=layers[ob.as_pointer()];local[expected]+=1;total[expected]+=1
            if ob.get("building_id")!=ident or ("interior_building_id" in ob and ob.get("interior_building_id")!=ident):
                failures.append({"object":ob.name,"reason":"Incorrect owner after normalization","building_id":ident})
            if ob.get("presentation_layer")!=expected:
                failures.append({"object":ob.name,"reason":"Incorrect presentation layer","expected":expected})
        reports.append({"building_id":ident,"object_count":len(objects),"normalized_interior_owner_fields":fixed,
                        "presentation_layer_counts":dict(local)})
    result={"schema":"living_town.building_owner_presentation.v1","status":"PASS" if not failures else "FAIL",
        "building_count":len(reports),"object_count":sum(total.values()),"assigned_or_corrected_building_id_fields":assigned,
        "normalized_interior_owner_fields":normalized,"incorrect_owner_fields_before":prior_incorrect,
        "incorrect_owner_fields_after":sum(row["reason"]=="Incorrect owner after normalization" for row in failures),
        "presentation_layer_counts":dict(total),"buildings":reports,"failures":failures,
        "policy":"Exact native building-root ownership; front/roof/upper mirror collection membership and structure is retained. No name parsing or height heuristics."}
    if failures:raise RuntimeError("Building ownership/presentation metadata gate failed: "+json.dumps(result))
    return result


def collision_metadata(plan,records):
    """Engine-neutral OBB proxies and walkable surfaces, not baked navigation."""
    buildings={b["id"]:b for b in plan["buildings"]}
    result=[]
    for record in records:
        b=buildings[record["id"]];interior=record["interior"]
        floors=[];furniture=[];partitions=[]
        for level in interior["levels"]:
            ff=level["finished_floor_local_z_m"]
            x0,y0,x1,y1=interior["clear_bounds_m"]
            floors.append({"level":level["level"],"polygon_world_m":[local_world(b,x,y,ff) for x,y in ((x0,y0),(x1,y0),(x1,y1),(x0,y1))],
                           "stair_voids_local_xy_m":level.get("slab_voids",[])})
            for wall in level["partitions"]:
                partitions.append({**wall,"floor_local_z_m":ff,"level":level["level"],
                                   "geometry_policy":"Split into solid cells around explicit door/hatch openings; do not make a single filled box over doors."})
            for room in level["rooms"]:
                for asset in room["assets"]:
                    x,y=asset["center_m"]
                    furniture.append({"id":asset["id"],"kind":asset["kind"],"room_id":room["id"],
                        "center_world_m":local_world(b,x,y,ff+asset["dimensions_m"][2]/2),
                        "dimensions_m":asset["dimensions_m"],
                        "yaw_degrees":b["yaw_degrees"]+asset.get("rotation_degrees",0)})
        result.append({"id":b["id"],"world_pose":{"center_m":b["center"],"pad_z_m":b["pad_level_m"],"yaw_degrees":b["yaw_degrees"]},
                       "walkable_floors":floors,"interior_partitions_local_m":partitions,"furniture_obb_proxies":furniture,
                       "exterior_policy":"Use apertured_exterior_wall mesh triangles; a solid building box would block every modeled doorway."})
    return {"schema":"living_town.expansion_collision_metadata.v1","buildings":result,
            "walkable_road_ribbons":[{"id":r["id"],"points_world_m":r["points_m"],"width_m":r["width_m"],
                "sidewalk_width_each_m":road_sidewalk_width(r),"paved_width_m":r["width_m"]+2*road_sidewalk_width(r),
                "paved_sections_m":r.get("paved_sections_m",[])} for r in plan["roads"]+plan.get("approaches",[])],
            "scope":"Measured engine-neutral metadata for consumer-created collisions and walkable surfaces. Physics layers, navigation baking, runtime reachability and accessibility are not claimed."}


def camera(name,position,target,collection,ortho=None,lens=40):
    data=bpy.data.cameras.new(name);ob=bpy.data.objects.new(name,data);collection.objects.link(ob)
    ob.location=position;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat("-Z","Y").to_euler()
    data.lens=lens;data.clip_start=.1;data.clip_end=3000
    if ortho:data.type="ORTHO";data.ortho_scale=ortho
    tag(ob,"presentation_camera")
    return ob


def footprint_view_visibility(position,target,buildings,focus_id,height):
    """Pure segment/rotated-footprint occlusion check plus terrain clearance."""
    blocked=[]
    for b in buildings:
        if b["id"]==focus_id:continue
        centre=b.get("center",b.get("center_m"));angle=math.radians(b.get("yaw_degrees",0));co,si=math.cos(angle),math.sin(angle)
        points=[]
        for p in (position,target):
            dx,dy=p[0]-centre[0],p[1]-centre[1];points.append((dx*co+dy*si,-dx*si+dy*co))
        width=b.get("width",b.get("width_m",0));depth=b.get("depth",b.get("depth_m",0))
        if width<=0 or depth<=0:continue
        low=(-width/2-.35,-depth/2-(1.15 if b.get("kind") in ("shop","cafe","creperie","bakery") else .35))
        high=(width/2+.35,depth/2+.35);near,far=0.,1.
        for axis in (0,1):
            start,end=points[0][axis],points[1][axis];delta=end-start
            if abs(delta)<1e-9:
                if start<low[axis] or start>high[axis]:near,far=2.,-1.;break
            else:
                a,c=(low[axis]-start)/delta,(high[axis]-start)/delta
                near=max(near,min(a,c));far=min(far,max(a,c))
        if near<=far and far>=0 and near<=1:blocked.append(b["id"])
    ground_block=[]
    for i in range(1,20):
        t=i/20;x=position[0]*(1-t)+target[0]*t;y=position[1]*(1-t)+target[1]*t;z=position[2]*(1-t)+target[2]*t
        if height(x,y)>z-.10:ground_block.append([x,y])
    return {"pass":not blocked and not ground_block,"building_blockers":blocked,"ground_block_samples":ground_block,
            "method":"Actual authored rotated footprints for original town, reserve services and all new buildings, with facade/awning margin; 19 height-authority samples along the view ray."}


def select_front_camera(building,all_buildings,height,terrain=False):
    distances=(5,4,6,7,8) if terrain else (6,4.8,4,7,8)
    lateral=(-.28,0,.28) if terrain else (-.10,0,.10,-.23,.23)
    attempts=[]
    for distance in distances:
        for side in lateral:
            lx=building["width"]*side
            position=list(local_world(building,lx,-building["depth"]/2-distance))
            position[2]=height(position[0],position[1])+(2.8 if terrain else 2.3)
            target=local_world(building,lx*.5 if terrain else 0,-building["depth"]/2-.20,.48 if terrain else 3.)
            visibility=footprint_view_visibility(position,target,all_buildings,building["id"],height)
            if visibility["pass"]:
                # Original combined vegetation can stand outside the plans.
                # Check actual foreground meshes as well as pure footprints.
                graph=bpy.context.evaluated_depsgraph_get();blocked=[]
                for side_ray in (-.28,0,.28):
                    for vertical in (-.8,0,.8):
                        aim=Vector(local_world(building,building["width"]*side_ray,-building["depth"]/2-.20,
                                               (.65 if terrain else 3.)+vertical))
                        ray=aim-Vector(position)
                        hit,point,normal,face,ob,matrix=bpy.context.scene.ray_cast(graph,Vector(position),ray.normalized(),distance=ray.length+.5)
                        if hit and (point-Vector(position)).length<ray.length*.60 and ob.get("building_id")!=building["id"]:
                            blocked.append(ob.name)
                visibility["actual_foreground_mesh_blockers"]=sorted(set(blocked))
                visibility["actual_foreground_rays"]=9
                visibility["pass"]=not blocked
            attempts.append({"distance_m":distance,"side_fraction":side,"pass":visibility["pass"]})
            if visibility["pass"]:
                return {"position":position,"target":target,"lens":35 if terrain else 28,
                        "focus_building_id":building["id"],"visibility":visibility,"candidate_attempts":attempts}
    return None


def presentation(plan,height,col,quick,baseline_root=None):
    bpy.context.view_layer.update()
    lots=plan["buildings"]
    x0=min(b["center"][0]-b["width"] for b in lots);x1=max(b["center"][0]+b["width"] for b in lots)
    y0=min(b["center"][1]-b["depth"] for b in lots);y1=max(b["center"][1]+b["depth"] for b in lots)
    cx,cy=(x0+x1)/2,(y0+y1)/2;span=max(x1-x0,y1-y0)
    z=height(cx,cy)
    hints=plan.get("presentation",{})
    configs={"overview":{"position":[cx+span*.70,cy-span*.95,z+span*.84],"target":[cx,cy,z+3],"ortho":span*1.13}}
    focus_id=plan.get("detailed_focus_ids",[lots[0]["id"]])[0]
    focus=next((b for b in lots if b["id"]==focus_id),lots[0])
    baseline_root=Path(baseline_root or REPO/"art/living_town")
    all_buildings=[*json.loads((baseline_root/"masterplan.json").read_text(encoding="utf-8"))["buildings"],
                   *json.loads((baseline_root/"reserve_plan.json").read_text(encoding="utf-8"))["buildings"],*lots]
    configs["street"]=select_front_camera(focus,all_buildings,height)
    if configs["street"] is None:raise RuntimeError("No unobstructed near-frontal street camera candidate for "+focus_id)
    configs["interior"]={"position":local_world(focus,-focus["width"]*.35,-focus["depth"]/2-5,7.7),
                         "target":local_world(focus,0,0,.9),"lens":37}
    hillsides=sorted((b for b in lots if b["district"]=="D08"),key=lambda b:-b.get("foundation_cut_fill_max_m",0))
    configs["terrain"]=next((choice for b in hillsides if (choice:=select_front_camera(b,all_buildings,height,True)) is not None),None)
    if configs["terrain"] is None:raise RuntimeError("No unobstructed hillside foundation camera candidate")
    cameras={}
    for name,config in configs.items():
        config.update(hints.get(name,{}))
        cameras[name]=camera("Expansion_Camera_"+name,config["position"],config["target"],col,
                             config.get("ortho"),config.get("lens",40))
    scene=bpy.context.scene
    scene.render.engine="CYCLES";scene.cycles.device="CPU";scene.render.threads_mode="FIXED";scene.render.threads=6
    scene.cycles.samples=12 if quick else 32;scene.cycles.use_denoising=True
    scene.render.resolution_x=640 if quick else 1400;scene.render.resolution_y=440 if quick else 960
    scene.render.resolution_percentage=100;scene.render.image_settings.file_format="PNG"
    scene.view_settings.view_transform="AgX"
    scene.camera=cameras["overview"]
    return cameras,focus_id,configs


def export_chunks(districts,common,terrain_col,output,landscape_report):
    target=output/"chunks";target.mkdir()
    scene=bpy.context.scene
    records=[]
    for ident,col in [*districts.items(),("expansion_public_realm",common),("replacement_terrain",terrain_col)]:
        bpy.ops.object.select_all(action="DESELECT")
        obs=[o for o in col.all_objects if o.type=="MESH"]
        for ob in obs:ob.select_set(True)
        if not obs:continue
        bpy.context.view_layer.objects.active=obs[0]
        file=target/(ident+".glb")
        log("Export chunk "+ident+": "+str(len(obs))+" mesh nodes")
        bpy.ops.export_scene.gltf(filepath=str(file),export_format="GLB",use_selection=True,
             export_apply=False,export_yup=True,export_texcoords=True,export_normals=True,export_tangents=True,
             export_materials="EXPORT",export_cameras=False,export_lights=False,export_extras=True)
        records.append({"id":ident,"path":file.relative_to(output).as_posix(),"bytes":file.stat().st_size,
                        "sha256":sha(file),"source_mesh_objects":len(obs),
                        "source_unique_meshes":len({o.data.as_pointer() for o in obs})})
    bpy.ops.object.select_all(action="DESELECT")
    write_json(output/"chunk_manifest.json",{"schema":"living_town.expansion_chunks.v1","chunks":records,
        "coordinate_system":"glTF Y up; source world metres; stable IDs stored in extras",
        "replace_baseline_nodes":[ob.name for ob in terrain_col.all_objects],
        "clear_removed_baseline_nodes":landscape_report["removed_baseline_object_names"],
        "clearing_policy":"Before loading chunks, hide or remove every clear_removed_baseline_nodes entry in baseline GLB. Replacement terrain and ground-cover nodes intentionally reuse source names; apply clearing to the baseline hierarchy only.",
        "scope":"New expansion and replacement graded terrain. Hide baseline Atlantic_Terrain_Grass before loading replacement_terrain.glb. Original core/reserve remain in the packed whole native and reusable baseline GLB."})
    return records


def args():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline",type=Path,required=True)
    parser.add_argument("--plan",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--pbr-library",type=Path,required=True)
    parser.add_argument("--quick",action="store_true",help="Bound render resolution/samples; geometry remains complete")
    parser.add_argument("--skip-render",action="store_true")
    parser.add_argument("--skip-export",action="store_true")
    parser.add_argument("--infinigen-asset",type=Path,help="Optional separately generated upstream planter .blend")
    return parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])


def main():
    start=time.time();a=args()
    a.baseline=a.baseline.resolve(strict=True);a.plan=a.plan.resolve(strict=True)
    a.pbr_library=a.pbr_library.resolve(strict=True);a.output=a.output.resolve()
    if a.output.exists():raise FileExistsError("Output must be new: "+str(a.output))
    if a.output==a.baseline.parent or a.baseline.is_relative_to(a.output):
        raise ValueError("Output may not contain the canonical baseline")
    if any(a.output.is_relative_to(REPO/directory) for directory in ("art","tools","game")):
        raise ValueError("Output must be outside canonical art/tools/game source directories")
    plan=json.loads(a.plan.read_text(encoding="utf-8"))
    if plan.get("schema")!="living_town.territory_expansion.v1":raise ValueError("Unsupported territory plan")
    if not plan.get("buildings") or not plan.get("roads"):raise ValueError("Plan has no expansion")
    if plan.get("validation",{}).get("status")!="PASS":raise ValueError("Territory plan did not pass its spatial/grade validation")
    for road in plan["roads"]+plan.get("approaches",[]):
        sections=road.get("paved_sections_m")
        if not sections or len(sections)<2:raise ValueError("Regenerate territory plan: explicit conforming paved_sections_m required for "+road["id"])
        expected=sections[0]["offsets_m"];half=road["width_m"]/2;walk=road_sidewalk_width(road)
        if any(not any(abs(s-required)<1e-6 for s in expected) for required in (-half-walk,-half,0.,half,half+walk)):
            raise ValueError("Paved section lacks exact center/curb/sidewalk offsets: "+road["id"])
        for section in sections:
            if section["offsets_m"]!=expected or len(section["points_m"])!=len(expected):
                raise ValueError("Inconsistent road-section topology: "+road["id"])
            if any(len(p)!=3 or not all(math.isfinite(v) for v in p) for p in section["points_m"]):
                raise ValueError("Invalid road-section coordinate: "+road["id"])
    if not plan.get("source_bindings"):raise ValueError("Territory plan has no preserved-source bindings")
    for relative,expected in plan.get("source_bindings",{}).items():
        source=(a.baseline.parent/relative).resolve()
        if not source.is_relative_to(a.baseline.parent) or sha(source)!=expected:
            raise ValueError("Stale or invalid territory source binding: "+relative)
    a.output.mkdir(parents=True);baseline_hash=sha(a.baseline)
    log("Prepare audited purposeful interior plans")
    adapter=module("expansion_interior_adapter",REPO/"tools/town_generation/interior_adapter.py")
    cached_plans,interior_preflight=adapter.prepare_plans(plan,a.baseline.parent)
    write_json(a.output/"interior_preflight.json",interior_preflight)
    if interior_preflight.get("status")!="PASS":
        raise RuntimeError("Expansion interior preflight did not pass; see interior_preflight.json")
    for prepared in cached_plans.values():
        for level in prepared["levels"]:
            for room in level["rooms"]:
                if room.get("nonrectangular_exclusions_m"):
                    FLOOR_NOTCHES[room["id"]+"_Finish"]=room["nonrectangular_exclusions_m"]
    interior_module=module("expansion_interior_design",a.baseline.parent/"tools/interior_design.py")
    def cached_plan(ident,w,d,floors,kind,doorx=0):
        cached=cached_plans[ident]
        if (cached["floors"]!=floors or cached["kind"]!=kind or
            abs(cached["footprint_m"][0]-w)>.00001 or abs(cached["footprint_m"][1]-d)>.00001 or doorx!=0):
            raise ValueError("Prepared interior pose/footprint mismatch: "+ident)
        return copy.deepcopy(cached)
    interior_module.plan_for_building=cached_plan
    architecture=module("expansion_architecture_details",REPO/"tools/town_generation/architecture_details.py")
    log("Open packed baseline read-only: "+str(a.baseline))
    bpy.ops.wm.open_mainfile(filepath=str(a.baseline),load_ui=False)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene;scene.unit_settings.system="METRIC";scene.unit_settings.scale_length=1
    scene["territory_expansion_plan_sha256"]=sha(a.plan)
    before={"objects":len(scene.objects),"mesh_objects":sum(o.type=="MESH" for o in scene.objects)}
    root=collection("Expansion_Territory");common=collection("Expansion_PublicRealm",root)
    roads_col=collection("Expansion_GradedStreets",common)
    plants_col=collection("Expansion_Horticulture",common)
    cameras_col=collection("Expansion_Presentation",root)
    districts={}
    for b in plan["buildings"]:
        if b["district"] not in districts:
            districts[b["district"]]=collection("Expansion_"+b["district"],root)
    log("Validate CC0 PBR sources and build portable materials")
    material_report=materials(a.pbr_library,a.output)
    height=terrain_function(plan,a.baseline.parent)
    log("Grade terrain and clear conflicting linked trees")
    landscape_report=update_baseline(plan,height,a.baseline.parent)
    terrain_col=collection("Expansion_ReplacementTerrain",root)
    # Add collection membership without copying these large shared meshes.
    for name in landscape_report["replacement_baseline_object_names"]:
        terrain_col.objects.link(bpy.data.objects[name])
    road_report=roads(plan,height,roads_col)
    retaining_col=collection("Expansion_GraniteRetainingTerraces",common)
    retaining_report=retaining_walls(plan,height,retaining_col,a.baseline.parent,
        landscape_report["actual_road_contact_repair"].get("exact_connected_contact_anchors",[]))
    focus=set(plan.get("detailed_focus_ids",[b["id"] for b in plan["buildings"][:5]]))
    for i,b in enumerate(plan["buildings"]):
        log("Building %d/%d %s"%(i+1,len(plan["buildings"]),b["id"]))
        BUILDING_RECORDS.append(building_geometry(b,districts[b["district"]],interior_module,b["id"] in focus,height,architecture))
    log("Place shared horticulture and street furniture")
    proto=prototypes(plants_col)
    detailed,prototype_reports=detailed_prototypes();proto.update(detailed)
    furniture_report=refine_focus_furniture(plan,BUILDING_RECORDS,proto,prototype_reports,interior_module,adapter)
    final_plans=[{**r["interior"],"floors":r["floor_count"]} for r in BUILDING_RECORDS]
    actual_interior_audit={"composition":interior_module.audit_furniture_compositions({"buildings":final_plans}),
                           "navigation_privacy":adapter.audit_prepared_plans(final_plans,authority=interior_module)}
    actual_interior_audit["status"]="PASS" if all(v["status"]=="PASS" for v in actual_interior_audit.values()) else "FAIL"
    write_json(a.output/"actual_interior_audit.json",actual_interior_audit)
    if actual_interior_audit["status"]!="PASS":raise RuntimeError("Actual generated furnishing audit failed; see actual_interior_audit.json")
    upstream_report=upstream_planter(a.infinigen_asset,proto,plants_col) if a.infinigen_asset else None
    if upstream_report:
        notices=a.infinigen_asset.resolve().parent/"INFINIGEN_NOTICES.txt"
        if not notices.is_file():raise FileNotFoundError("Upstream asset needs adjacent INFINIGEN_NOTICES.txt for distribution")
        license_dir=a.output/"licenses";license_dir.mkdir(exist_ok=True)
        (license_dir/notices.name).write_bytes(notices.read_bytes())
        upstream_report["license_notices"]="licenses/"+notices.name
        upstream_report["license_notices_sha256"]=sha(notices)
    planting_report=planting(plan,height,plants_col,proto)
    ownership_report=classify_building_metadata(BUILDING_RECORDS)
    cameras,focus_id,camera_configs=presentation(plan,height,cameras_col,a.quick,a.baseline.parent)
    configure_saved_viewport(cameras["overview"])
    # Pack all externally loaded maps before saving the only native deliverable.
    for image in bpy.data.images:
        if image.source=="FILE" and not image.packed_file:
            image.pack()
    write_json(a.output/"interiors.json",{"schema":"living_town.expansion_interiors.v1",
               "buildings":[r["interior"] for r in BUILDING_RECORDS]})
    collisions=collision_metadata(plan,BUILDING_RECORDS)
    collisions["retaining_wall_obb_proxies"]=[r["collision_obb"] for r in retaining_report["segments"]+retaining_report["preservation_boundary_segments"]+retaining_report["constrained_retaining"]["segments"]]
    collisions["raised_road_closed_solids"]=[record for road in road_report for record in road["raised_road_supports"]]
    write_json(a.output/"collision_proxies.json",collisions)
    chunks=[]
    if not a.skip_export:chunks=export_chunks(districts,common,terrain_col,a.output,landscape_report)
    native=a.output/"expanded_town.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(native),compress=True)
    renders=[]
    if not a.skip_render:
        render_dir=a.output/"renders";render_dir.mkdir()
        for view in ("overview","street","interior","terrain"):
            scene.camera=cameras[view]
            changes=[]
            if view=="interior":
                rec=next(r for r in BUILDING_RECORDS if r["id"]==focus_id)
                for role in ("front","roof","upper"):
                    col=bpy.data.collections[rec["collections"][role]]
                    changes.append((col,col.hide_render));col.hide_render=True
            path=render_dir/("expansion_"+view+".png")
            scene.render.filepath=str(path)
            log("CPU render "+view)
            try:bpy.ops.render.render(write_still=True)
            finally:
                for col,previous in changes:col.hide_render=previous
            renders.append({"view":view,"path":path.relative_to(a.output).as_posix(),"sha256":sha(path)})
    scene.camera=cameras["overview"]
    # Keep the saved source intact after temporary cutaway rendering.
    bpy.ops.wm.save_as_mainfile(filepath=str(native),compress=True)
    if sha(a.baseline)!=baseline_hash:raise RuntimeError("Read-only baseline checksum changed")
    meshes=[o for o in NEW_OBJECTS if o.type=="MESH" and o.name in scene.objects]
    summary={k:sum(r[k] for r in BUILDING_RECORDS) for k in ("floor_count","room_count","furnishing_count","window_aperture_count")}
    report={"schema":"living_town.expansion_scene.v1","status":"BUILT",
        "baseline":{"path":str(a.baseline),"sha256":baseline_hash,"unchanged":True,"before_counts":before},
        "plan":{"path":str(a.plan),"sha256":sha(a.plan),"schema":plan["schema"]},
        "native":{"path":native.name,"bytes":native.stat().st_size,"sha256":sha(native)},
        "building_count":len(BUILDING_RECORDS),"district_count":len(districts),**summary,
        "expansion_mesh_objects":len(meshes),"expansion_unique_meshes":len({o.data.as_pointer() for o in meshes}),
        "expansion_triangles":sum(len(o.data.polygons) for o in meshes),
        "buildings":[{k:v for k,v in r.items() if k!="interior"} for r in BUILDING_RECORDS],
        "terrain":landscape_report,"roads":road_report,"horticulture":planting_report,"upstream_planter":upstream_report,
        "retaining_terraces":retaining_report,
        "detailed_prototypes":prototype_reports,"focus_furniture_refinements":furniture_report,"ownership_metadata":ownership_report,
        "interior_preflight":"interior_preflight.json","actual_interior_audit":"actual_interior_audit.json",
        "removed_baseline_object_names":landscape_report["removed_baseline_object_names"],
        "replacement_baseline_object_names":landscape_report["replacement_baseline_object_names"],"collision_metadata":"collision_proxies.json",
        "materials":material_report,"cameras":camera_configs,"render_views":renders,"chunks":chunks,
        "elapsed_seconds":round(time.time()-start,2),"engine":{"blender":bpy.app.version_string,"render_device":"CPU","threads":6},
        "limits":["Fictional town and authored grading; no survey, structural or accessibility certification.",
                  "All expansion buildings contain partitioned furnished rooms; opening clearances are generated metric geometry, not a playable navigation certification.",
                  "GLB chunks contain new sectors, public realm and replacement terrain; original baseline core/reserve remain available in the packed whole native and baseline GLB.",
                  "Presentation renders are evidence of this generated output; quality acceptance and engine integration are separate checks."]}
    write_json(a.output/"expansion_manifest.json",report)
    log("Complete: "+json.dumps({"buildings":len(BUILDING_RECORDS),**summary,"elapsed_seconds":report["elapsed_seconds"]}))


if __name__=="__main__":main()
