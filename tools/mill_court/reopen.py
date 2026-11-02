"""Separate factory process: reopen exact authored file, compare all saved geometry/material state; no save/render."""

from pathlib import Path
import os, sys, json, hashlib, traceback, struct, math, argparse
import bpy
from mathutils import Matrix

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parents[1]))
from tools.mill_court.snapshot import state, canonical_sha
from tools.mill_court.inputs import saved_blend_path, expected_asset_counts

ap = argparse.ArgumentParser()
ap.add_argument("--floorplans", required=True)
ap.add_argument("--output", required=True)
ap.add_argument("--source-output", required=True)
args = ap.parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])
OUT = Path(args.output).resolve()
OUT.mkdir(parents=True, exist_ok=False)
assert (
    bpy.app.background and not bpy.data.filepath
), "Use a fresh factory-startup background Blender process"


def write(n, v):
    (OUT / n).write_text(json.dumps(v, indent=2) + "\n", encoding="utf-8")


try:
    SRC = Path(args.source_output).resolve()
    saved = json.loads((SRC / "SAVED_BLEND.json").read_text())
    blend_path = saved_blend_path(SRC, saved)
    meta = blend_path.stat()
    assert (
        meta.st_size == saved["bytes"]
        and hashlib.sha256(blend_path.read_bytes()).hexdigest() == saved["sha256"]
    )
    bpy.ops.wm.open_mainfile(filepath=str(blend_path), load_ui=False, use_scripts=False)
    assert (
        bpy.context.scene.get("floorplan_sha256")
        == hashlib.sha256(Path(args.floorplans).read_bytes()).hexdigest()
    ), "Reopen must use the exact authored floorplan input"
    actual = state(bpy)
    expected = json.loads((SRC / "SAVED_SOURCE_STATE.json").read_text())
    write("REOPENED_SOURCE_STATE.json", actual)
    assert (
        actual == expected
    ), "Saved scene geometry/transforms/hierarchy/material graph differs on independent reopen"
    spec = json.loads((SRC / "COMPILED_GEOMETRY.json").read_text())
    ids = {
        ob.get("mc_geometry_spec_id")
        for ob in bpy.data.objects
        if ob.get("mc_geometry_spec_id")
    }
    assert ids == {x["id"] for x in spec["objects"]}
    byid = {
        ob.get("mc_geometry_spec_id"): ob
        for ob in bpy.data.objects
        if ob.get("mc_geometry_spec_id")
    }
    # Independent source-to-actual positions, not merely a writer/reader self-consistency count.
    for r in spec["objects"]:
        ob = byid[r["id"]]
        assert ob.get("mc_owner") == r["owner"] and ob.get("mc_asset") == r["asset"]
        if r["kind"] in ("BOX", "MESH"):
            assert ob.matrix_world == Matrix.Identity(4), (
                "Worldbaked geometry must retain identitytransform",
                r["id"],
            )
        if r["kind"] == "BOX":
            lo = r["low"]
            hi = r["high"]
            expected = {
                (struct.pack("<f", x), struct.pack("<f", y), struct.pack("<f", z))
                for x in (lo[0], hi[0])
                for y in (lo[1], hi[1])
                for z in (lo[2], hi[2])
            }
            got = {tuple(struct.pack("<f", c) for c in v.co) for v in ob.data.vertices}
            assert got == expected and len(ob.data.polygons) == 6, (
                "ExactFloat32Box",
                r["id"],
            )
        elif r["kind"] == "MESH":
            assert [
                tuple(struct.pack("<f", c) for c in v.co) for v in ob.data.vertices
            ] == [tuple(struct.pack("<f", c) for c in v) for v in r["vertices"]]
    plans = json.loads(Path(args.floorplans).read_text())["plans"]
    counts = expected_asset_counts(plans, spec)
    headrooms = []

    def bounds(ob):
        return [min(v.co[i] for v in ob.data.vertices) for i in range(3)] + [
            max(v.co[i] for v in ob.data.vertices) for i in range(3)
        ]

    for p in plans:
        if p["level_index"]:
            assert (
                p["floor_slab"]["opening_bounds_m"]
                == p["stair_void_bounds_m"]
                == p["stair"]["opening_bounds_m"]
            )
            x, y = p["world_inner_southwest_xy_m"]
            a, b, c, d = p["stair_void_bounds_m"]
            for r in spec["objects"]:
                if r["plan"] == p["id"] and r["category"] == "slab":
                    bb = bounds(byid[r["id"]])
                    assert not (
                        min(bb[3], x + c) - max(bb[0], x + a) > 1e-5
                        and min(bb[4], y + d) - max(bb[1], y + b) > 1e-5
                    ), "Actual upper slab intersects declared void"
        else:
            x, y = p["world_inner_southwest_xy_m"]
            z = p["FF_world_m"]
            sample = [(x + 0.5, y + 0.5, z), (x + 0.5, y + 4.4, z + 2.7)]
            for r in spec["objects"]:
                if r["plan"] == p["id"] and r["category"] == "stair_tread":
                    bb = bounds(byid[r["id"]])
                    sample.append(((bb[0] + bb[3]) / 2, (bb[1] + bb[4]) / 2, bb[5]))
            overhead = [
                bounds(byid[r["id"]])
                for r in spec["objects"]
                if r["owner"] == p["owner_id"] and r["category"] in ("slab", "ceiling")
            ]
            values = []
            for xx, yy, feet in sample:
                ceilings = [
                    b[2]
                    for b in overhead
                    if b[0] < xx < b[3] and b[1] < yy < b[4] and b[2] > feet + 0.03
                ]
                assert ceilings
                values.append(min(ceilings) - feet)
            # Exact Float32 vertices checkedabove; bound only the sourcefloat/nativefloat quantization.
            magnitude = max(abs(v) for b in overhead for v in b)
            ulp = 2.0 ** (math.floor(math.log2(magnitude)) - 23)
            assert min(values) + 8 * ulp >= 2.5, (
                "Actual conservative headroom",
                p["owner_id"],
                values,
            )
            headrooms.append(
                dict(
                    owner=p["owner_id"],
                    samples=len(values),
                    minimum_m=min(values),
                    Float32_quantization_bound_m=8 * ulp,
                )
            )
    assert (
        len([x for x in spec["objects"] if x["category"] == "stair_tread"])
        == counts["treads"]
    )
    assert (
        len([x for x in spec["objects"] if x["category"] == "stair_riser"])
        == counts["risers"]
    )
    assert (
        blend_path.stat().st_mtime_ns == meta.st_mtime_ns
        and hashlib.sha256(blend_path.read_bytes()).hexdigest() == saved["sha256"]
    )
    write(
        "INDEPENDENT_REOPEN_PASS.json",
        dict(
            status="PASS_EXACT_INDEPENDENT_REOPEN_NO_SAVE_NO_RENDER",
            saved=saved,
            actual_state_sha256=canonical_sha(actual),
            geometry_specs=len(ids),
            **counts,
            resolved_local_blend=str(blend_path),
            author_path_provenance=saved["path"],
            actual_geometric_headroom=headrooms,
            source_file_byte_and_mtime_exact=True,
            limits="Source shape/readback only; visual art/access/export equivalence requires root review"
        ),
    )
except BaseException:
    write(
        "REOPEN_PRIMARY_FAILURE.json",
        dict(status="FAIL_RETAINED", failure=traceback.format_exc()),
    )
    raise
