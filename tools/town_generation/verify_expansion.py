"""Read back the generated native bindings and portable district GLB payloads.

This offline check complements native reopening and real consumer captures. It
does not certify runtime physics/navigation or substitute for visual review.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
import mmap
from pathlib import Path
import struct


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def need(condition, message):
    if not condition:
        raise ValueError(message)


def relative(root, name):
    path = (root / name).resolve(strict=True)
    need(path.is_relative_to(root.resolve()), "Artifact path escapes its root")
    return path


def inspect_glb(path, expected_buildings=None):
    # Parse metadata without materializing millions of accessor tuples.
    with path.open("rb") as stream:
        header = stream.read(20)
        need(len(header) == 20, "Truncated GLB header")
        magic, version, total, size, kind = struct.unpack("<4sIIII", header)
        need(magic == b"glTF" and version == 2 and total == path.stat().st_size and kind == 0x4E4F534A,
             "Invalid GLB header: " + path.name)
        need(size <= total-28, "JSON chunk overflows GLB")
        doc = json.loads(stream.read(size))
        bin_size, bin_kind = struct.unpack("<II", stream.read(8))
        need(bin_kind == 0x004E4942 and stream.tell()+bin_size == total, "Invalid embedded BIN chunk")
    need(doc.get("asset", {}).get("version") == "2.0", "Not glTF 2.0")
    need(len(doc["buffers"]) == 1 and "uri" not in doc["buffers"][0], "External geometry buffer")
    need(all("uri" not in i and "bufferView" in i for i in doc.get("images", [])), "External texture image")
    need(set(doc.get("extensionsRequired", [])) <= {"KHR_texture_transform"}, "Unreviewed required glTF extension")
    views = doc.get("bufferViews", [])
    for view in views:
        need(type(view.get("byteOffset",0)) is int and view.get("byteOffset",0)>=0
             and type(view.get("byteLength")) is int and view["byteLength"]>0,
             "Invalid buffer view offset/length")
        need(view.get("buffer", 0) == 0 and view.get("byteOffset",0)+view["byteLength"] <= bin_size,
             "Buffer view outside embedded BIN")
    accessors = doc.get("accessors", [])
    components={5120:("i1",1),5121:("u1",1),5122:("<i2",2),5123:("<u2",2),5125:("<u4",4),5126:("<f4",4)}
    elements={"SCALAR":1,"VEC2":2,"VEC3":3,"VEC4":4,"MAT4":16}
    def ref(value,rows,label):
        need(type(value) is int and 0<=value<len(rows),"Invalid "+label+" reference")
        return rows[value]
    for accessor in accessors:
        need("sparse" not in accessor and "bufferView" in accessor,"Expected dense embedded accessors")
        view=ref(accessor["bufferView"],views,"accessor bufferView")
        need(accessor.get("componentType") in components and accessor.get("type") in elements,"Invalid accessor format")
        width=components[accessor["componentType"]][1]
        packed=width*elements[accessor["type"]]
        stride=view.get("byteStride",packed)
        offset=accessor.get("byteOffset",0)
        count=accessor.get("count",0)
        need(type(count) is int and count>0 and type(offset) is int and offset>=0 and offset%width==0,
             "Invalid accessor count/offset")
        need(type(stride) is int and stride>=packed and stride%width==0,"Invalid accessor stride")
        need(offset+(count-1)*stride+packed<=view["byteLength"],"Accessor exceeds buffer view")
    for material in doc.get("materials",[]):
        pbr=material.get("pbrMetallicRoughness",{})
        slots=[material.get("normalTexture"),material.get("occlusionTexture"),material.get("emissiveTexture"),pbr.get("baseColorTexture"),pbr.get("metallicRoughnessTexture")]
        for slot in slots:
            if slot is not None:ref(slot["index"],doc.get("textures",[]),"material texture")
    for texture in doc.get("textures",[]):
        ref(texture["source"],doc.get("images",[]),"texture image")
    for image in doc.get("images",[]):
        ref(image["bufferView"],views,"image bufferView")
    owners=set();layers=Counter()
    expected=None if expected_buildings is None else set(expected_buildings)
    if expected is not None:
        need(all(isinstance(owner,str) and owner for owner in expected),"Invalid expected building owner")
    for node in doc.get("nodes",[]):
        if "mesh" in node:
            ref(node["mesh"],doc["meshes"],"node mesh")
            if expected is not None:
                extras=node.get("extras",{})
                need(isinstance(extras,dict),"Mesh lacks building metadata")
                owner=extras.get("building_id")
                need(isinstance(owner,str) and owner in expected,"Mesh building owner is not in expected district")
                layer=extras.get("presentation_layer")
                need(isinstance(layer,str) and layer in {"structure","front","roof","upper"},"Mesh lacks valid presentation layer")
                if "interior_building_id" in extras:
                    need(extras["interior_building_id"]==owner,"Interior building owner differs from exact building_id")
                if "interior_room_id" in extras:
                    room=extras["interior_room_id"]
                    need(isinstance(room,str) and room.startswith(owner+"_L"),"Interior room owner differs from exact building_id")
                owners.add(owner);layers[layer]+=1
        for child in node.get("children",[]):ref(child,doc["nodes"],"node child")
    if expected is not None:
        need(owners==expected,"District building owner coverage differs from plan")
    triangles = 0
    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:
            attrs = primitive["attributes"]
            for value in attrs.values():ref(value,accessors,"primitive attribute")
            if "indices" in primitive:ref(primitive["indices"],accessors,"primitive indices")
            if "material" in primitive:ref(primitive["material"],doc.get("materials",[]),"primitive material")
            need({"POSITION", "NORMAL", "TEXCOORD_0"} <= set(attrs), "Mesh lacks position, normal or UV")
            vertex_count=accessors[attrs["POSITION"]]["count"]
            for label,dimension in (("POSITION","VEC3"),("NORMAL","VEC3"),("TEXCOORD_0","VEC2"),("TANGENT","VEC4")):
                if label not in attrs:continue
                attribute=accessors[attrs[label]]
                need(attribute["type"]==dimension and attribute["count"]==vertex_count,
                     "Invalid "+label+" dimension or vertex count")
                need(attribute["componentType"]==5126 or label=="TEXCOORD_0" and attribute["componentType"] in (5121,5123) and attribute.get("normalized") is True,
                     "Invalid "+label+" component representation")
            need(primitive.get("mode", 4) == 4, "Mesh is not triangulated")
            if "material" in primitive and "normalTexture" in doc["materials"][primitive["material"]]:
                need("TANGENT" in attrs, "Normal-mapped primitive lacks tangents")
            for key in ("POSITION", "NORMAL", "TEXCOORD_0"):
                a = accessors[attrs[key]]
                need(a["count"] > 0 and "bufferView" in a, "Empty or external attribute")
                for field in ("min", "max"):
                    need(all(math.isfinite(v) for v in a.get(field, [])), "Non-finite attribute bound")
            count = accessors[primitive["indices"]]["count"] if "indices" in primitive else accessors[attrs["POSITION"]]["count"]
            need(count % 3 == 0, "Incomplete triangle indices")
            triangles += count//3
    # Inspect actual accessor bytes with zero-copy bounded views. Metadata-only
    # bounds cannot prove finite positions or valid index payloads.
    import numpy as np
    bin_offset=28+size
    with path.open("rb") as stream, mmap.mmap(stream.fileno(),0,access=mmap.ACCESS_READ) as mapped:
        def payload(index):
            a=accessors[index];v=views[a["bufferView"]]
            code,width=components[a["componentType"]]
            cols=elements[a["type"]]
            return np.ndarray((a["count"],cols),dtype=code,buffer=mapped,
                              offset=bin_offset+v.get("byteOffset",0)+a.get("byteOffset",0),
                              strides=(v.get("byteStride",width*cols),width))
        for mesh in doc["meshes"]:
            for primitive in mesh["primitives"]:
                attrs=primitive["attributes"]
                for label,index in attrs.items():
                    need(bool(np.isfinite(payload(index)).all()),"Non-finite actual "+label+" payload")
                if "indices" in primitive:
                    accessor=accessors[primitive["indices"]]
                    need(accessor["type"]=="SCALAR" and accessor["componentType"] in (5121,5123,5125),"Invalid index format")
                    need(int(payload(primitive["indices"]).max())<accessors[attrs["POSITION"]]["count"],"Index payload references a missing vertex")
    used = Counter(n["mesh"] for n in doc.get("nodes", []) if "mesh" in n)
    metadata={} if expected is None else {"building_owner_count":len(owners),"building_ids":sorted(owners),
                                        "presentation_layer_counts":dict(sorted(layers.items()))}
    return {"path": path.name, "bytes": path.stat().st_size, "sha256": sha(path),
            "mesh_nodes": sum(used.values()), "unique_meshes": len(used),
            "shared_mesh_references": sum(used.values())-len(used),
            "unique_geometry_triangles": triangles,
            "images": len(doc.get("images", [])), "materials": len(doc.get("materials", [])),
            "normal_mapped_materials": sum("normalTexture" in m for m in doc.get("materials", [])),
            "pbr_color_images": sum("baseColorTexture" in m.get("pbrMetallicRoughness", {}) for m in doc.get("materials", [])),
            **metadata}


def verify(run_root, baseline_override=None):
    root = Path(run_root).resolve(strict=True)
    scene = root / "scene"
    manifest = json.loads((scene / "expansion_manifest.json").read_text(encoding="utf-8"))
    plan = json.loads((root / "territory_plan.json").read_text(encoding="utf-8"))
    need(manifest["status"] == "BUILT", "Scene did not complete")
    need(plan["validation"]["status"] == "PASS", "Territory validation failed")
    need(sha(root / "territory_plan.json") == manifest["plan"]["sha256"], "Scene/plan binding differs")
    native = relative(scene, manifest["native"]["path"])
    need(sha(native) == manifest["native"]["sha256"], "Native source SHA differs")
    baseline = Path(baseline_override or manifest["baseline"]["path"])
    need(sha(baseline) == manifest["baseline"]["sha256"], "Canonical baseline was changed")
    need(manifest["building_count"] == len(plan["buildings"]), "Missing expansion buildings")
    need({b["id"] for b in manifest["buildings"]} == {b["id"] for b in plan["buildings"]}, "Scene building ids differ from plan")
    need(manifest["floor_count"] == sum(b["floors"] for b in plan["buildings"]), "Scene floor count differs from plan")
    chunks=[];district_expected={d["id"]:{b["id"] for b in plan["buildings"] if b["district"]==d["id"]} for d in plan["districts"]}
    districts_seen=set();layer_counts=Counter()
    for row in manifest["chunks"]:
        file = relative(scene, row["path"])
        need(sha(file) == row["sha256"] and file.stat().st_size == row["bytes"], "Chunk content differs: " + file.name)
        expected=district_expected.get(file.stem)
        stats = inspect_glb(file,expected_buildings=expected)
        if expected is not None:
            need(file.stem not in districts_seen,"Duplicate district chunk: "+file.stem)
            districts_seen.add(file.stem);layer_counts.update(stats["presentation_layer_counts"])
        need(stats["mesh_nodes"] == row["source_mesh_objects"], "Export lost source mesh instances: " + file.name)
        chunks.append(stats)
    need(len(chunks) >= manifest["district_count"]+2, "Missing district/public realm/terrain chunks")
    need(districts_seen==set(district_expected),"Missing planned district chunks")
    need(sum(c.get("building_owner_count",0) for c in chunks)==manifest["building_count"],"Export district owner count differs from plan")
    shared = sum(c["shared_mesh_references"] for c in chunks)
    need(shared > 20, "Export lost shared prototype mesh references")
    need(all(c["normal_mapped_materials"] > 0 for c in chunks if c["path"].startswith("D")), "District lacks physical PBR maps")
    for row in manifest["render_views"]:
        need(sha(relative(scene,row["path"])) == row["sha256"], "Render binding differs")
    report={"schema":"living_town.expansion_offline_review.v1","status":"PASS",
            "plan_sha256":sha(root/"territory_plan.json"),"native_sha256":sha(native),
            "baseline_unchanged":True,"building_count":manifest["building_count"],
            "floor_count":manifest["floor_count"],"room_count":manifest["room_count"],
            "furnishing_count":manifest["furnishing_count"],"chunks":chunks,
            "export_shared_mesh_references":shared,
            "district_building_owner_count":sum(c.get("building_owner_count",0) for c in chunks),
            "presentation_layer_counts":dict(sorted(layer_counts.items())),
            "scope":"Source hashes, plan ids/counts, GLB payload bounds/UV/normals/tangents/materials/instances and render bindings. Actual mesh positions, native reopening, visual quality and runtime captures have separate reports."}
    (root/"offline_review.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    return report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run",type=Path,required=True)
    parser.add_argument("--baseline",type=Path,help="Override the historical baseline path after unpacking")
    args=parser.parse_args()
    result=verify(args.run,args.baseline)
    print(json.dumps({k:result[k] for k in ("status","building_count","room_count","export_shared_mesh_references")}))


if __name__=="__main__":
    main()
