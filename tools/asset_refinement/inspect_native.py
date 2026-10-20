"""Independently reopen the pilot native file with Blender; never save it.

blender --background --threads 6 --python-exit-code 1 --python this.py --
  --hero <hero directory> --report <new JSON path>
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hero", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    native = args.hero.resolve() / "cafe_hero.blend"
    if args.report.exists():
        raise FileExistsError(args.report)
    before = sha(native)
    bpy.ops.wm.open_mainfile(filepath=str(native))
    scene = bpy.context.scene
    assert scene.name == "Living_Town_Concept_Cafe_Hero", "Unexpected native scene"
    assert len(scene.objects) > 100, "Incomplete native scene"
    failures = []
    for obj in scene.objects:
        if obj.type != "MESH":
            continue
        for material in obj.data.materials:
            if material is None or material.node_tree is None:
                continue
            for node in material.node_tree.nodes:
                if node.type in ("UVMAP", "NORMAL_MAP") and node.uv_map and node.uv_map not in obj.data.uv_layers:
                    failures.append(obj.name + ":" + node.uv_map)
    assert not failures, failures
    def bounds(obj):
        points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
        return {"min": [min(p[axis] for p in points) for axis in range(3)],
                "max": [max(p[axis] for p in points) for axis in range(3)]}
    terrace = bpy.data.objects.get("Street_Hero_Paving")
    floor = bpy.data.objects.get("Architecture_Hero_InteriorFloor_Scan") or bpy.data.objects.get("Architecture_Hero_Paving")
    assert terrace is not None and floor is not None, "Expected authored floor meshes"
    terrace_bounds, floor_bounds = bounds(terrace), bounds(floor)
    assert abs(terrace_bounds["max"][2]) < .00001, "Terrace feet datum differs from floor"
    assert abs(floor_bounds["max"][2]) < .00001, "Indoor floor differs from feet datum"
    assert terrace_bounds["max"][1] <= floor_bounds["min"][1] + .00001, "Coplanar floor overlap"
    assert before == sha(native), "Read-only inspection changed native source"
    record = {"schema": "living_town.hero_native_reopen.v1", "status": "PASS",
              "native_sha256": before, "inspector_sha256": sha(Path(__file__)),
              "scene": scene.name, "objects": len(scene.objects),
              "all_named_material_uvs_resolve": True,
              "floor_contact_metres": {"terrace": terrace_bounds, "interior": floor_bounds,
                                      "shared_feet_datum_z": 0.0, "coplanar_overlap": False},
              "packed_images": sum(bool(image.packed_file) for image in bpy.data.images),
              "blender_version": bpy.app.version_string,
              "scope": "Independent native reopen, scene identity and all mesh material named UV/normal-map bindings. No whole-town/gameplay claim."}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open("x", encoding="utf-8") as stream:
        json.dump(record, stream, indent=2)
        stream.write("\n")
    print("NATIVE_REOPEN_PASS", json.dumps(record), flush=True)


if __name__ == "__main__":
    main()
