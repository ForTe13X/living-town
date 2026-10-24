"""Pure geometry/authority tests for the real game's upgraded town compiler."""
import copy
import json
import math
from pathlib import Path
import struct
import tempfile
import unittest

from tools.town_upgrade.compile_playable_town import (SurfaceIndex, asset_records, compile_interior,
    GLBPositionBounds, glb_building_bounds, glb_height_bounds, normalized_building, stage_assets,
    stairwell_room_metadata, structural_floor_metadata)
from tools.stage_town_assets import sha256


def room_plan(block_door=False):
    return {"id":"Test_Building_L04", "footprint_m":[6,6], "clear_bounds_m":[-2.8,-2.8,2.8,2.8],
        "core":None,"entrance_local_m":[0,-2.75],"levels":[{"level":0,"finished_floor_local_z_m":.2,
        "partitions":[{"axis":"y","coordinate_m":0,"span_m":[-2.8,2.8],"thickness_m":.12,
            "openings":[] if block_door else [{"kind":"door","center_m":0,"width_m":1.1,"bottom_m":0,"height_m":2.1}]}],
        "rooms":[{"id":"front","purpose":"living","bounds_m":[-2.8,-2.8,2.8,0],"assets":[]},
                 {"id":"back","purpose":"bedroom","bounds_m":[-2.8,0,2.8,2.8],
                  "assets":[{"id":"bed","kind":"bed","center_m":[2,2],"footprint_m":[1.5,1.1,2.5,2.7]}]}]}]}


def three_floor_document():
    """Recipe-shaped structures with measurable GLB bounds and a parcel L04 ID."""
    ident = "Test_Building_L04"
    building = normalized_building({"id": ident, "center_m": [10, 20, 3], "width": 6, "depth": 6})
    plan = {"id": ident, "floor_height_m": 2.85, "core": {"bounds": [-1,-1,1,1]}, "levels": []}
    document = {"asset": {"version": "2.0"}, "nodes": [{"name": "Root", "translation": [10, 3, -20], "children": []}], "meshes": [], "accessors": []}
    def add(name, role, ff, low, high, extras=None):
        accessor = len(document["accessors"]); mesh = len(document["meshes"])
        document["accessors"].append({"componentType": 5126, "type": "VEC3", "count": 8, "min": [-1, low, -1], "max": [1, high, 1]})
        document["meshes"].append({"primitives": [{"attributes": {"POSITION": accessor}}]})
        e = {"building_id": ident, "presentation_layer": "upper" if ff > .2 else "structure"}
        if role: e["interior_role"] = role
        e.update(extras or {})
        document["nodes"][0]["children"].append(len(document["nodes"]))
        document["nodes"].append({"name": name, "mesh": mesh, "translation": [0, ff, 0], "extras": e})
    for index in range(3):
        ff = .2 + index * 2.85
        room = {"id": f"room{index}", "assets": []}
        stairwell = {"id": ident + f"_L{index:02d}_Stairwell", "purpose": "protected vertical circulation", "bounds_m": [-1,-1,1,1], "assets": []}
        level = {"level": index, "finished_floor_local_z_m": ff, "rooms": [room, stairwell]}
        if index < 2: level["stair_to_next_level"] = {"risers": 14}
        plan["levels"].append(level)
        add(ident + f"_L{index:02d}_Partitions_Plaster", "partition_with_openings", ff, 0, 2.6)
        add(ident + f"_L{index:02d}_Joinery_White", "interior_joinery", ff, .02, 2.2)
        add(ident + f"_L{index:02d}_DoorLeaf_1_0_Oak", "open_interior_door", ff, .005, 2.025)
        add(ident + f"_L{index:02d}_Room_Finish", "floor_finish", ff, 0, .012, {"interior_room_id": room["id"]})
        if index:
            add(ident + f"_Floor{index+1}_Oak", "floor_slab", ff, -.12, 0)
            add(ident + f"_L{index:02d}_ShaftGuard_Iron", "stair_and_gallery_guard", ff, .02, .92)
        if index < 2:
            add(ident + f"_L{index:02d}_Stairs_Oak", "functional_stair", ff, 0, 3.78)
    add(ident + "_UpperEnvelope_Plaster", None, 3.05, 0, 5.45)
    return building, plan, document


def write_test_glb(path, document, binary=None):
    document = copy.deepcopy(document)
    if binary is None:
        chunks = []; document["bufferViews"] = []
        for accessor in document.get("accessors", []):
            points = [(x,y,z) for x in (accessor["min"][0],accessor["max"][0])
                      for y in (accessor["min"][1],accessor["max"][1]) for z in (accessor["min"][2],accessor["max"][2])]
            data = b"".join(struct.pack("<fff", *p) for p in points)
            accessor.update(bufferView=len(chunks), count=len(points))
            document["bufferViews"].append({"buffer":0,"byteOffset":sum(len(c) for c in chunks),"byteLength":len(data)})
            chunks.append(data)
        binary = b"".join(chunks)
    binary += b"\0" * (-len(binary) % 4)
    document["buffers"] = [{"byteLength":len(binary)}]
    payload = json.dumps(document).encode(); payload += b" " * (-len(payload) % 4)
    path.write_bytes(struct.pack("<4sIII4s", b"glTF", 2, 28 + len(payload) + len(binary), len(payload), b"JSON") + payload
                     + struct.pack("<I4s", len(binary), b"BIN\0") + binary)


class PlayableTownTests(unittest.TestCase):
    def setUp(self):
        self.building=normalized_building({"id":"Test_Building_L04","center_m":[10,20,3],"width":6,"depth":6,"yaw_degrees":30})

    def test_activity_room_reachable_through_actual_door(self):
        _,planes,_,grids,rooms,checks=compile_interior(self.building,room_plan(),"home",{})
        self.assertEqual(len(planes),1)
        self.assertGreater(checks[-1]["reachable_open_cells"],0)
        self.assertEqual(planes["home/1f"]["finished_floor_z_m"],3.2)
        self.assertNotIn((20,4),grids["home/1f"]["labels"])

    def test_filled_partition_is_not_rescued_by_carving(self):
        with self.assertRaisesRegex(ValueError,"disconnected from entrance"):
            compile_interior(self.building,room_plan(True),"home",{})

    def test_service_hatch_cannot_become_a_walk_door(self):
        plan=room_plan()
        plan["levels"][0]["partitions"][0]["openings"][0]["bottom_m"]=.9
        with self.assertRaisesRegex(ValueError,"disconnected from entrance"):
            compile_interior(self.building,plan,"home",{})

    def test_bridge_deck_overrides_ravine_route_with_exact_height(self):
        index=SurfaceIndex([{"id":"ravine","points_m":[[-5,0,1],[5,0,1]],"width_m":3},
            {"id":"bridge","points_m":[[0,-5,12],[0,5,14]],"width_m":2,"priority":4}])
        self.assertAlmostEqual(index.sample(0,0),13)
        self.assertIsNone(index.sample(5,5))

    def test_real_landing_stays_level(self):
        index=SurfaceIndex([{"id":"stair","points_m":[[0,0,1],[0,10,5]],"width_m":2,"priority":4},
            {"id":"landing","points_m":[[0,4,2.6],[0,6,2.6]],"width_m":2,"priority":5}])
        self.assertAlmostEqual(index.sample(0,5),2.6)

    def test_exact_owner_not_name_suffix(self):
        rooms,assets=asset_records(room_plan(),"Test_Building_L04")
        self.assertEqual(assets["bed"],("Test_Building_L04",0,"back"))
        self.assertEqual(rooms["front"],("Test_Building_L04",0))

    def test_final_native_north_facing_pose_replaces_stale_frontage(self):
        b=normalized_building({"id":"north_house","group":"urban","center":[0,0],"width":8,"depth":6,
            "yaw_degrees":180,"door_local_x":1.1,"front_threshold":[0,-3],"front_outward":[0,-1]})
        self.assertAlmostEqual(b["front_threshold"][0],-1.1)
        self.assertAlmostEqual(b["front_threshold"][1],3)
        self.assertAlmostEqual(b["front_outward"][1],1)

    def test_offset_vehicle_entrance_does_not_become_a_service_hatch(self):
        b=normalized_building({"id":"truck","center":[0,0],"width":8,"depth":3,"entry_local":[2.7,-1.5]})
        self.assertEqual(b["front_threshold"],[2.7,-1.5])

    def test_staged_three_floor_structures_survive_their_active_cutaway(self):
        building, plan, document = three_floor_document()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source = root / "native.glb"; manifest_path = root / "manifest.json"
            write_test_glb(source, document); manifest_path.write_text("{}")
            manifest = {"source_blend_sha256": "a" * 64, "assets": [{"path": "native.glb", "sha256": sha256(source)}]}
            stage = stage_assets(manifest_path, manifest, {building["id"]: building}, {plan["id"]: plan}, root / "stage")
            catalog = json.loads((root / "stage" / stage["assets"][0]["catalog"]).read_text())
        records = {row["name"]: row["extras"] for row in catalog["nodes"]}
        ident = building["id"]
        for active in range(3):
            # Exercise the existing consumer's explicit floor contract. Each
            # active room retains its physical slab, partitions and joinery;
            # higher authored structures must all be excluded from the view.
            for index in range(3):
                for suffix in ("Partitions_Plaster", "Joinery_White", "DoorLeaf_1_0_Oak"):
                    e = records[ident + f"_L{index:02d}_" + suffix]
                    self.assertEqual(e["model_floor_index"] <= active, index <= active)
                if index:
                    for name in (ident + f"_Floor{index+1}_Oak", ident + f"_L{index:02d}_ShaftGuard_Iron"):
                        self.assertEqual(records[name]["model_floor_index"] <= active, index <= active)
        self.assertNotIn("model_floor_index", records[ident + "_UpperEnvelope_Plaster"])
        self.assertEqual(stage["structural_floor_indexing"]["indexed_meshes"], 15)
        self.assertEqual(stage["structural_floor_indexing"]["transformed_bounds_verified"], 15)
        self.assertEqual(stage["open_stairwell_geometry_bindings"], 4)
        for index in range(3):
            bound = [e for e in records.values() if e.get("room_id") == ident + f"_L{index:02d}_Stairwell"]
            self.assertTrue(bound)
            self.assertTrue(all(e.get("model_room_binding") == "existing_open_stairwell_structure.v1" for e in bound))
            self.assertTrue(all(e["model_floor_index"] == index for e in bound))

    def test_stairs_belong_to_departure_floor_and_span_the_real_arrival(self):
        building, plan, _ = three_floor_document()
        for index in (0, 1):
            name = building["id"] + f"_L{index:02d}_Stairs_Iron"
            ff = 3.2 + index * 2.85
            e = structural_floor_metadata(name, {"interior_role": "functional_stair"}, building, plan, (ff + .9, ff + 3.78))
            self.assertEqual((e["model_floor_index"], e["model_floor_end_index"]), (index, index + 1))
            self.assertEqual([active for active in range(3) if e["model_floor_index"] <= active], list(range(index, 3)))
        with self.assertRaisesRegex(ValueError, "no authored next-floor"):
            structural_floor_metadata(building["id"] + "_L02_Stairs_Oak", {"interior_role": "functional_stair"}, building, plan)

    def test_structure_name_must_match_exact_owner_role_and_authored_level(self):
        building, plan, _ = three_floor_document()
        for name, role in (("Other_L01_Partitions_Plaster", "partition_with_openings"),
                           (building["id"] + "_L01_Partitions_Plaster", "interior_joinery"),
                           (building["id"] + "_Floor4_Oak", "floor_slab")):
            with self.assertRaises(ValueError):
                structural_floor_metadata(name, {"interior_role": role}, building, plan)

    def test_wrong_floor_geometry_is_rejected_despite_plausible_name(self):
        building, plan, _ = three_floor_document()
        with self.assertRaisesRegex(ValueError, "transformed GLB bounds"):
            structural_floor_metadata(building["id"] + "_Floor2_Oak", {"interior_role": "floor_slab"}, building, plan, (8.78, 8.9))

    def test_open_zone_requires_actual_stair_geometry_inside_the_authored_core(self):
        building, plan, _ = three_floor_document()
        name = building["id"] + "_L00_Stairs_Oak"
        e = {"interior_role": "functional_stair"}
        e.update(structural_floor_metadata(name, e, building, plan, (3.2, 6.98)))
        for bounds in (None, ((2,3),(-1,1),(.2,3.98))):
            with self.assertRaises(ValueError):
                stairwell_room_metadata(name, e, building, plan, bounds)
        plan["levels"][0]["rooms"][1]["purpose"] = "bedroom"
        with self.assertRaisesRegex(ValueError, "authored zone"):
            stairwell_room_metadata(name, e, building, plan, ((-1,1),(-1,1),(.2,3.98)))

    def test_missing_top_guard_cannot_waive_stairwell_geometry_coverage(self):
        building, plan, document = three_floor_document()
        node = next(n for n in document["nodes"] if n["name"].endswith("L02_ShaftGuard_Iron"))
        node["extras"].pop("interior_role")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source = root / "native.glb"; manifest_path = root / "manifest.json"
            write_test_glb(source, document); manifest_path.write_text("{}")
            manifest = {"source_blend_sha256": "a" * 64, "assets": [{"path": "native.glb", "sha256": sha256(source)}]}
            with self.assertRaisesRegex(ValueError, "lacks authored room geometry.*L02_Stairwell"):
                stage_assets(manifest_path, manifest, {building["id"]: building}, {plan["id"]: plan}, root / "stage")

    def test_bounds_apply_parent_matrix_rotation_and_negative_scale(self):
        _, _, document = three_floor_document()
        # Rotate a local XY rectangle into the horizontal XZ plane, then use
        # column-major parent translation. This tests both glTF transform forms.
        document["nodes"][0].pop("translation")
        document["nodes"][0]["matrix"] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,6.05,0,1]
        node = document["nodes"][1]; node["translation"] = [0,0,0]
        node["rotation"] = [math.sin(math.pi/4),0,0,math.cos(math.pi/4)]; node["scale"] = [-2,1,1]
        document["accessors"][0].update(min=[-2,-2,-.12], max=[2,2,0])
        low, high = glb_height_bounds(document, 1, {1:0}, {})
        self.assertAlmostEqual(low, 6.05)
        self.assertAlmostEqual(high, 6.17)

    def test_rotated_baked_stairs_use_actual_strided_vertices_not_inflated_boxes(self):
        building, plan, _ = three_floor_document(); building["yaw_degrees"] = 45
        angle = math.pi/4; co, si = math.cos(angle), math.sin(angle)
        points = [(10+x*co-y*si, 3+z, -20-x*si-y*co)
                  for x,y,z in [(-1,-1,.2),(-1,1,3.98),(1,-1,.2),(1,1,3.98)]]
        lows = [min(p[c] for p in points) for c in range(3)]; highs = [max(p[c] for p in points) for c in range(3)]
        binary = b"HEAD" + b"SKIP" + b"".join(struct.pack("<fff", *p) + b"PAD!" for p in points)
        document = {"asset":{"version":"2.0"}, "nodes":[{"name":"stairs","mesh":0}],
            "meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}],
            "accessors":[{"bufferView":0,"byteOffset":4,"componentType":5126,"type":"VEC3","count":4,"min":lows,"max":highs}],
            "bufferViews":[{"buffer":0,"byteOffset":4,"byteLength":len(binary)-4,"byteStride":16}]}
        name = building["id"] + "_L00_Stairs_Oak"; e = {"interior_role":"functional_stair"}
        e.update(structural_floor_metadata(name, e, building, plan, (3.2,6.98)))
        with self.assertRaisesRegex(ValueError, "misses its authored"):
            stairwell_room_metadata(name, e, building, plan, glb_building_bounds(document,0,{}, {},building))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/"stairs.glb"; write_test_glb(path, document, binary)
            local = glb_building_bounds(document,0,{}, {},building,GLBPositionBounds(path,document))
        for measured in local[:2]:
            self.assertAlmostEqual(measured[0], -1, places=5)
            self.assertAlmostEqual(measured[1], 1, places=5)
        self.assertEqual(stairwell_room_metadata(name,e,building,plan,local)["room_id"], building["id"]+"_L00_Stairwell")


if __name__=="__main__":unittest.main()
