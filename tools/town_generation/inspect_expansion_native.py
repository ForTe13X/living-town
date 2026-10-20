"""Read-only Blender reopen audit, including raycasts against the actual terrain.

Run: blender --background --threads 6 --python this.py -- --scene DIR
The loaded .blend is never saved or edited by this check.
"""
import argparse
import hashlib
import json
import math
from collections import Counter, defaultdict
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream,"sha256").hexdigest()


def world_mesh(ob, depsgraph):
    evaluated=ob.evaluated_get(depsgraph);mesh=evaluated.to_mesh()
    try:
        return ([tuple(ob.matrix_world@v.co) for v in mesh.vertices],
                [tuple(p.vertices) for p in mesh.polygons])
    finally:evaluated.to_mesh_clear()


def closed_support_components(ob, depsgraph):
    """Audit actual connected solids; unrelated top/bottom plates cannot pass."""
    vertices,faces=world_mesh(ob,depsgraph)
    parents=list(range(len(vertices)))
    def find(i):
        while parents[i]!=i:
            parents[i]=parents[parents[i]];i=parents[i]
        return i
    for face in faces:
        for i in face[1:]:parents[find(i)]=find(face[0])
    groups=defaultdict(list)
    for face in faces:groups[find(face[0])].append(face)
    valid=[];invalid=[]
    for index,polygons in enumerate(groups.values()):
        used=sorted({i for face in polygons for i in face});remap={old:i for i,old in enumerate(used)}
        points=[vertices[i] for i in used];local=[tuple(remap[i] for i in face) for face in polygons]
        edges=Counter(tuple(sorted((a,b))) for face in local for a,b in zip(face,face[1:]+face[:1]))
        volume=0.
        for face in local:
            a=Vector(points[face[0]])
            for i in range(1,len(face)-1):volume+=a.dot(Vector(points[face[i]]).cross(Vector(points[face[i+1]])))/6
        if not edges or any(count!=2 for count in edges.values()) or abs(volume)<1e-8:
            invalid.append({"object":ob.name,"component":index,"boundary_or_nonmanifold_edges":sum(v!=2 for v in edges.values()),"signed_volume_m3":volume})
            continue
        valid.append({"object":ob.name,"component":index,"road_id":ob.get("road_id"),
                      "bounds_xy":[min(v[0] for v in points),min(v[1] for v in points),max(v[0] for v in points),max(v[1] for v in points)],
                      "bvh":BVHTree.FromPolygons(points,local,all_triangles=False)})
    return valid,invalid


def road_audit_samples(row):
    sections=row.get("paved_sections_m")
    if sections:
        for index,section in enumerate(sections):
            if index%3!=0 and index!=len(sections)-1:continue
            for a,b,oa,ob in zip(section["points_m"],section["points_m"][1:],section["offsets_m"],section["offsets_m"][1:]):
                offset=(oa+ob)/2
                point=[(a[k]+b[k])/2 for k in range(3)]
                yield index,offset,point,.035 if abs(offset)<row["width_m"]/2 else .055
    else:
        # Historical plans can still be inspected without rewriting receipts.
        points=row["points_m"]
        for index,p in enumerate(points):
            if index%3!=0 and index!=len(points)-1:continue
            previous=points[max(0,index-1)];following=points[min(len(points)-1,index+1)]
            dx=following[0]-previous[0];dy=following[1]-previous[1];length=math.hypot(dx,dy)
            if length<1e-9:continue
            for offset in (-row["width_m"]/2+.05,0.,row["width_m"]/2-.05):
                yield index,offset,[p[0]-dy/length*offset,p[1]+dx/length*offset,p[2]],.035


def deck_surface_contact(tree, point, expected_lift):
    """Require actual deck geometry, allowing only float32 edge roundoff.

    Cross sections are shared triangle boundaries. World-space float32
    vertices around200m can round onto the opposite side of an exact ray.
    A missed ray may use a real nearest triangle only within0.2mm in3D of
    the expected contact. This cannot stand in for a missing/displaced deck.
    """
    if tree is None:return None,False
    x,y,z=point
    hit,_,_,_=tree.ray_cast(Vector((x,y,z+5)),Vector((0,0,-1)),10)
    if hit is not None:return hit,False
    expected=Vector((x,y,z+expected_lift))
    nearby,_,_,distance=tree.find_nearest(expected,.0002)
    if nearby is not None and distance<=.0002:return nearby,True
    return None,False


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scene",required=True,type=Path)
    parser.add_argument("--plan",type=Path,help="Override historical absolute plan path after unpacking")
    parser.add_argument("--baseline",type=Path,help="Override historical absolute baseline path after unpacking")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    root=args.scene.resolve(strict=True)
    manifest=json.loads((root/"expansion_manifest.json").read_text(encoding="utf-8"))
    plan_path=args.plan or Path(manifest["plan"]["path"])
    plan=json.loads(plan_path.read_text(encoding="utf-8"))
    if sha(plan_path)!=manifest["plan"]["sha256"]:
        raise ValueError("Plan checksum differs from the built native manifest")
    native=root/manifest["native"]["path"]
    before=sha(native)
    bpy.ops.wm.open_mainfile(filepath=str(native),load_ui=False)
    scene=bpy.context.scene
    objects=[o for o in scene.objects if o.get("generator_owner")=="living_town.territory_expansion.v1"]
    meshes=[o for o in objects if o.type=="MESH"]
    issues=[]
    ids=[o.get("stable_id") for o in objects]
    if len(set(ids))!=len(ids):issues.append("Duplicate stable object ids")
    for ob in meshes:
        if not ob.data.uv_layers:issues.append("Mesh lacks UV: "+ob.name)
        if not all(math.isfinite(v) for vertex in ob.data.vertices for v in vertex.co):
            issues.append("Non-finite mesh: "+ob.name)
        if not ob.data.materials or any(m is None for m in ob.data.materials):
            issues.append("Missing mesh material: "+ob.name)
    external=[i.name for i in bpy.data.images if i.source=="FILE" and not i.packed_file]
    if external:issues.append("Unpacked external image dependencies")
    expected=set(b["id"] for b in plan["buildings"])
    actual=set(c.get("building_id") for c in bpy.data.collections if c.get("building_id"))
    if not expected<=actual:issues.append("New building collections missing")
    ownership_failures=[];ownership_count=0;ownership_layers=Counter()
    for record in manifest["buildings"]:
        root_collection=bpy.data.collections.get(record["collections"]["root"])
        if root_collection is None:continue
        wanted={ob.name:"structure" for ob in root_collection.all_objects}
        for layer in ("front","roof","upper"):
            for ob in bpy.data.collections[record["collections"][layer]].all_objects:wanted[ob.name]=layer
        for ob in root_collection.all_objects:
            ownership_count+=1;ownership_layers[wanted[ob.name]]+=1
            if (ob.get("building_id")!=record["id"] or ob.get("presentation_layer")!=wanted[ob.name]
                or ob.get("interior_building_id",record["id"])!=record["id"]):
                ownership_failures.append({"object":ob.name,"expected_building":record["id"],"expected_layer":wanted[ob.name]})
    if ownership_failures:issues.append("Building ownership or native presentation layer metadata differs")
    terrain=bpy.data.objects[manifest["terrain"]["terrain_object"]]
    depsgraph=bpy.context.evaluated_depsgraph_get()
    bvh=BVHTree.FromObject(terrain,depsgraph)
    inverse=terrain.matrix_world.inverted()
    quay=bpy.data.objects.get("Connected_Streets_and_Pavements_Paving")
    quay_bvh=None;quay_surface_bvh=None;quay_faces=[]
    if quay is not None:
        qvertices,qpolygons=world_mesh(quay,depsgraph)
        # The combined legacy batch also has sloping street ribbons. Require
        # the actual flat quay top, rather than treating another road as earth.
        quay_faces=[i for i,f in enumerate(qpolygons) if all(abs(qvertices[j][2]-1.615)<.001 for j in f)]
        if quay_faces:quay_bvh=BVHTree.FromPolygons(qvertices,[qpolygons[i] for i in quay_faces],all_triangles=False)
        quay_surface_bvh=BVHTree.FromPolygons(qvertices,qpolygons,all_triangles=False)
    fallback_hits=[]
    def ground(x,y):
        origin=inverse@Vector((x,y,160))
        direction=(inverse.to_3x3()@Vector((0,0,-1))).normalized()
        hit,_,_,_=bvh.ray_cast(origin,direction,400)
        if hit is not None:return (terrain.matrix_world@hit).z
        # The frozen coast intentionally omits grass beneath its built quay.
        # Require an actual hit on that existing deck; do not fill the hole
        # with the analytic terrain height or suppress a missing support.
        if quay_bvh is not None and 31-.001<=x<=66+.001 and 37-.001<=y<=55+.001:
            qhit,_,_,_=quay_bvh.ray_cast(Vector((x,y,160)),Vector((0,0,-1)),400)
            if qhit is not None:
                height=qhit.z
                fallback_hits.append({"surface":quay.name,"source_faces":quay_faces,"xy_m":[x,y],"actual_z_m":height})
                return height
        return None
    pads=[]
    for b in plan["buildings"]:
        samples=[b["center"],*b["footprint_polygon"],b["front_threshold"]]
        zs=[ground(*p[:2]) for p in samples]
        delta=max(abs(z-b["pad_level_m"]) for z in zs if z is not None) if any(z is not None for z in zs) else None
        pads.append({"id":b["id"],"max_actual_mesh_pad_error_m":delta,"ray_misses":sum(z is None for z in zs)})
    roads=[]
    for row in plan["roads"]:
        points=row["points_m"]
        maximum=0.;misses=0
        for index,p in enumerate(points):
            if index%3!=0 and index!=len(points)-1:continue
            z=ground(*p[:2])
            if z is None:misses+=1
            else:maximum=max(maximum,abs(z-p[2]))
        roads.append({"id":row["id"],"max_actual_mesh_profile_error_m":maximum,"ray_misses":misses})
    # Limits apply to actual triangulated ground, not just the analytic callable.
    bad_pads=[r for r in pads if r["ray_misses"] or r["max_actual_mesh_pad_error_m"] is None or r["max_actual_mesh_pad_error_m"]>.15]
    bad_roads=[r for r in roads if r["ray_misses"] or r["max_actual_mesh_profile_error_m"]>.15]
    if bad_pads:issues.append("Actual terrain mesh deviates >15cm at building pad samples")
    if bad_roads:issues.append("Actual terrain mesh deviates >15cm from road centerlines")
    # A centerline can sit correctly while one edge floats above a protected
    # original path. Verify the full-width deck against actual ground and real
    # closed bedding geometry, rather than accepting a manifest assertion.
    supports=[o for o in meshes if o.get("semantic_role")=="raised_road_bedding"]
    support_solids=defaultdict(list);invalid_supports=[]
    for ob in supports:
        solids,invalid=closed_support_components(ob,depsgraph)
        for solid in solids:support_solids[solid["road_id"]].append(solid)
        invalid_supports.extend(invalid)
    if invalid_supports:issues.append("Raised road bedding contains open or degenerate components")
    road_geometry=defaultdict(list)
    for ob in meshes:
        if ob.get("semantic_role")=="graded_street":road_geometry[ob.get("road_id")].append(ob)
    edge_checks=[];bad_edges=[];precision_contacts=[];legacy_quay_junction=[]
    for row in plan["roads"]+plan.get("approaches",[]):
        vertices=[];faces=[]
        for ob in road_geometry[row["id"]]:
            vs,fs=world_mesh(ob,depsgraph);offset=len(vertices)
            vertices.extend(vs);faces.extend(tuple(offset+i for i in face) for face in fs)
        deck_bvh=BVHTree.FromPolygons(vertices,faces,all_triangles=False,epsilon=.00001) if faces else None
        maximum_gap=0.;maximum_burial=0.;supported=0;sample_count=0
        for index,offset,p,surface_lift in road_audit_samples(row):
                x,y=p[:2]
                g=ground(x,y);sample_count+=1
                deck,precision=deck_surface_contact(deck_bvh,p,surface_lift)
                if precision:precision_contacts.append({"road":row["id"],"station":index,"lateral_m":offset,
                    "distance_from_expected_m":(deck-Vector((x,y,p[2]+surface_lift))).length})
                if deck is None or abs(deck.z-(p[2]+surface_lift))>.15:
                    bad_edges.append({"road":row["id"],"station":index,"lateral_m":offset,"error":"Actual road paving missing or displaced",
                        "actual_deck_z_m":deck.z if deck is not None else None,"planned_deck_z_m":p[2]+surface_lift});continue
                if quay_surface_bvh is not None and 31<=x<=66 and 37<=y<=55:
                    old,_,_,_=quay_surface_bvh.ray_cast(Vector((x,y,160)),Vector((0,0,-1)),400)
                    if old is not None and old.z>deck.z+.0002:
                        legacy_quay_junction.append({"road":row["id"],"station":index,"xy_m":[x,y],
                            "retained_surface_above_new_paving_m":old.z-deck.z})
                        if old.z-deck.z>.08:bad_edges.append({"road":row["id"],"station":index,
                            "error":"Retained quay junction exceeds8cm transition","height_m":old.z-deck.z})
                if g is None:
                    bad_edges.append({"road":row["id"],"station":index,"lateral_m":offset,"error":"No actual ground below road width"});continue
                gap=deck.z-surface_lift-g;maximum_gap=max(maximum_gap,gap);maximum_burial=max(maximum_burial,-gap)
                if gap<-(surface_lift-.01):
                    bad_edges.append({"road":row["id"],"station":index,"lateral_m":offset,"buried_m":-gap})
                elif gap>.15:
                    valid=False
                    for solid in support_solids[row["id"]]:
                        x0,y0,x1,y1=solid["bounds_xy"]
                        if not (x0-.001<=x<=x1+.001 and y0-.001<=y<=y1+.001):continue
                        top,_,_,_=solid["bvh"].ray_cast(Vector((x,y,deck.z+.2)),Vector((0,0,-1)),200)
                        bottom,_,_,_=solid["bvh"].ray_cast(Vector((x,y,g-100)),Vector((0,0,1)),100+gap+.4)
                        if top is not None and abs(top.z-(deck.z-surface_lift))<=.15 and bottom is not None and bottom.z<=g+.15:
                            valid=True;break
                    if valid:supported+=1
                    else:bad_edges.append({"road":row["id"],"station":index,"lateral_m":offset,"exposed_gap_m":gap,
                        "error":"No same closed bedding solid connects deck to actual ground"})
        edge_checks.append({"id":row["id"],"actual_ground_samples":sample_count,"maximum_deck_ground_gap_m":maximum_gap,
                            "maximum_ground_above_deck_m":maximum_burial,"actual_bedding_supported_samples":supported})
    if bad_edges:issues.append("Actual paving is missing/displaced, has <1cm ground clearance, or has an unsupported gap >15cm")
    # Raycast the real doorway sweep at ankle, body and head height. This
    # catches trim, props or an open door leaf that the room-plan audit cannot.
    entry_contacts=[]
    for building in plan["buildings"]:
        identity=building["id"]
        parts=[o for o in meshes if o.get("building_id",o.get("interior_building_id"))==identity]
        vertices=[];faces=[]
        for ob in parts:
            evaluated=ob.evaluated_get(depsgraph)
            mesh=evaluated.to_mesh()
            offset=len(vertices)
            vertices.extend(tuple(ob.matrix_world@v.co) for v in mesh.vertices)
            faces.extend(tuple(offset+i for i in p.vertices) for p in mesh.polygons)
            evaluated.to_mesh_clear()
        if not faces:
            entry_contacts.append({"id":identity,"error":"No owned building geometry"})
            continue
        doorway=BVHTree.FromPolygons(vertices,faces,all_triangles=False)
        theta=math.radians(building["yaw_degrees"])
        def world(x,y,z):
            return Vector((building["center"][0]+x*math.cos(theta)-y*math.sin(theta),
                           building["center"][1]+x*math.sin(theta)+y*math.cos(theta),
                           building["pad_level_m"]+z))
        blocked=[]
        for x in (-.25,0,.25):
            for z in (.10,.9,1.7):
                ff=building["finished_floor_offset_m"]
                start=world(x,-building["depth"]/2-1.,ff+z)
                end=world(x,-building["depth"]/2+.75,ff+z)
                hit,_,face,distance=doorway.ray_cast(start,(end-start).normalized(),(end-start).length)
                if hit is not None:blocked.append({"local_x_m":x,"height_above_floor_m":z,"distance_m":distance})
        if blocked:entry_contacts.append({"id":identity,"blocked_rays":blocked})
    if entry_contacts:issues.append("Actual building geometry blocks a .50m doorway sweep")
    after=sha(native)
    if before!=after:issues.append("Native changed during read-only inspection")
    baseline=args.baseline or Path(manifest["baseline"]["path"])
    if sha(baseline)!=manifest["baseline"]["sha256"]:issues.append("Canonical baseline changed")
    report={"schema":"living_town.expansion_native_review.v1","status":"PASS" if not issues else "FAIL",
            "audit_source_sha256":sha(Path(__file__)),
            "issues":issues,"native_sha256":before,"native_unchanged":before==after,
            "objects":len(scene.objects),"expansion_mesh_objects":len(meshes),
            "expansion_unique_meshes":len({o.data.as_pointer() for o in meshes}),
            "shared_mesh_references":len(meshes)-len({o.data.as_pointer() for o in meshes}),
            "building_ownership":{"checked_objects":ownership_count,"layer_counts":dict(ownership_layers),"failures":ownership_failures},
            "packed_images":sum(bool(i.packed_file) for i in bpy.data.images),"unpacked_images":external,
            "terrain_contact_tolerance_m":.15,"pad_contacts":pads,"road_contacts":roads,
            "built_quay_contacts":fallback_hits,
            "retained_quay_junction":{"maximum_transition_m":max((r["retained_surface_above_new_paving_m"] for r in legacy_quay_junction),default=0),
                "maximum_allowed_transition_m":.08,"records":legacy_quay_junction,
                "scope":"Actual retained street paving can form a shallow raised junction above the new approach; the flat built quay remains its separately measured support."},
            "actual_road_width_support":{"tolerance_m":.15,"support_meshes":len(supports),
                "minimum_visible_paving_clearance_m":.01,
                "closed_support_solids":sum(len(s) for s in support_solids.values()),"invalid_support_components":invalid_supports,
                "boundary_precision_tolerance_m":.0002,"actual_nearest_boundary_contacts":precision_contacts,
                "roads":edge_checks,"failures":bad_edges},
            "actual_doorway_sweeps":{"buildings":len(plan["buildings"]),"width_m":.50,"heights_m":[.1,.9,1.7],"blocked":entry_contacts},
            "scope":"Read-only native reopening, geometry/UV/material/packed-image checks and actual terrain BVH vertical contacts. Foundations, interiors, camera quality and engine behavior have separate evidence."}
    (root/"native_review.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({k:report[k] for k in ("status","issues","objects","shared_mesh_references")}))
    if issues:raise RuntimeError("Native review failed; inspect native_review.json")


if __name__=="__main__":main()
