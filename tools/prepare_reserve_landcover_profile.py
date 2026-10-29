"""Freeze an Editor landcover profile from an existing native ready receipt.

Stdlib only. No engine launch, GUID override, asset save, painting or Git action.
Checksums record local provenance; the native Apply/Read still checks the world.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import re
import tempfile

SIDE = 505
COUNT = SIDE * SIDE
ROLES = ("Meadow", "WoodlandLitter", "SteepRock", "PondSoil")
SCHEMA = "LivingTown.NativeLandcoverProfile.v2"
MODE = "owned_editor_preview_no_runtime_paint"
VISIBILITY = "exact_engine_singleton_zero_unallocated_edit_and_merged"
HEIGHT_RELATIVE = "Content/ReserveLandscapeSource_v001/Height505.r16"
WEIGHTS_RELATIVE = "Content/ReserveLandcoverSource_v001/Landcover_Actual229_505_RGBA8.bin"
ROOT_KEYS = {"schema", "mode", "map_path", "landscape_actor_label", "landscape_guid",
             "edit_layer_guid", "material_path", "height", "weights", "layout", "roles",
             "visibility_policy", "source_scene", "prerequisite_read_receipt_sha256"}


def need(condition, message):
    if not condition:
        raise ValueError(message)


def file_sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def bytes_sha(raw):
    return hashlib.sha256(raw).hexdigest()


def no_duplicate_keys(rows):
    result = {}
    for key, value in rows:
        need(key not in result, "Duplicate JSON key: " + key)
        result[key] = value
    return result


def reject_constant(value):
    raise ValueError("Nonfinite JSON number: " + value)


def decode(raw):
    return json.loads(raw, object_pairs_hook=no_duplicate_keys, parse_constant=reject_constant)


def bound_json(path, expected):
    raw = Path(path).read_bytes()
    need(valid_hash(expected) and bytes_sha(raw) == expected, "Evidence SHA differs: " + str(path))
    return decode(raw)


def keys(value, expected):
    need(type(value) is dict and set(value) == set(expected), "Closed object keys required")


def number(value):
    try:
        return type(value) in (int, float) and math.isfinite(value)
    except OverflowError:
        return False


def equal_number(value, expected):
    return number(value) and value == expected


def valid_hash(value):
    return type(value) is str and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def package(value):
    return (type(value) is str and 7 <= len(value) <= 256
            and re.fullmatch(r"/Game/[A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)*", value) is not None)


def object_package(value):
    need(type(value) is str and value.count(".") == 1, "Project object path required")
    parent, asset = value.rsplit(".", 1)
    need(package(parent) and asset == parent.rsplit("/", 1)[1], "Exact package.asset path required")
    return parent


def relative_source(value):
    return (type(value) is str and 9 <= len(value) <= 256 and value.startswith("Content/")
            and ".." not in value and "//" not in value and not value.endswith("/")
            and re.fullmatch(r"[A-Za-z0-9_/.]+", value) is not None)


def tag(value):
    return type(value) is str and re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", value) is not None


def guid(value):
    return (type(value) is str and re.fullmatch(r"[0-9a-fA-F]{32}", value) is not None
            and int(value, 16) != 0)


def vector(value):
    return type(value) is list and len(value) == 3 and all(number(v) and abs(v) <= 1e8 for v in value)


def validate_profile(data):
    """Match the bounded native format, including its cross-field constraints."""
    keys(data, ROOT_KEYS)
    need(data["schema"] == SCHEMA and data["mode"] == MODE and data["visibility_policy"] == VISIBILITY,
         "Version/mode/Visibility policy differs")
    need(package(data["map_path"]) and tag(data["landscape_actor_label"]), "Map/actor label required")
    material_package = object_package(data["material_path"])
    need(material_package != data["map_path"], "Material and Map packages must differ")
    need(guid(data["landscape_guid"]) and guid(data["edit_layer_guid"])
         and data["landscape_guid"].upper() != data["edit_layer_guid"].upper(), "Distinct nonzero GUIDs required")
    for name, size in (("height", COUNT * 2), ("weights", COUNT * 4)):
        record = data[name]
        expected = {"project_relative_path", "bytes", "sha256"}
        keys(record, expected | ({"encoding", "per_vertex_sum"} if name == "weights" else set()))
        need(relative_source(record["project_relative_path"]) and equal_number(record["bytes"], size)
             and valid_hash(record["sha256"]), "Bounded source record differs")
    need(data["height"]["project_relative_path"] != data["weights"]["project_relative_path"], "Source paths alias")
    need(data["weights"]["encoding"] == "uint8_interleaved_RGBA_no_header"
         and equal_number(data["weights"]["per_vertex_sum"], 255), "Exact semantic weight encoding required")
    layout = data["layout"]
    keys(layout, {"width", "height", "subsection_size_quads", "num_subsections", "component_count_xy",
                  "origin_cm", "scale_xyz", "row0", "rotation_pitch_yaw_roll"})
    for key, value in (("width", SIDE), ("height", SIDE), ("subsection_size_quads", 63), ("num_subsections", 2)):
        need(equal_number(layout[key], value), "Only qualified505/63x2 layout is supported")
    for key, expected in (("component_count_xy", [4, 4]), ("scale_xyz", [100, 100, 25]),
                          ("rotation_pitch_yaw_roll", [0, 0, 0])):
        values = layout[key]
        need(type(values) is list and len(values) == len(expected)
             and all(equal_number(a, b) for a, b in zip(values, expected)), "Exact layout vector required")
    need(vector(layout["origin_cm"]) and layout["row0"] == "minimum_UE_Y", "Finite explicit origin/row direction required")
    roles = data["roles"]
    need(type(roles) is list and len(roles) == 4, "Exactly four semantic role rows required")
    seen = {data["map_path"], material_package}
    for channel, role in enumerate(roles):
        keys(role, {"channel", "name", "layer_info_path"})
        need(equal_number(role["channel"], channel) and role["name"] == ROLES[channel], "Role channel/order differs")
        role_package = object_package(role["layer_info_path"])
        need(role_package not in seen, "LayerInfo packages must be unique and distinct from Map/Material")
        seen.add(role_package)
    scene = data["source_scene"]
    keys(scene, {"lineage", "manifest_sha256", "population_census_sha256"})
    need(tag(scene["lineage"]) and valid_hash(scene["manifest_sha256"])
         and valid_hash(scene["population_census_sha256"])
         and valid_hash(data["prerequisite_read_receipt_sha256"]), "Explicit evidence hashes required")
    return data


def validate_raw_profile(raw, expected=None):
    need(2 <= len(raw) <= 65536 and all(c in (9, 10, 13) or 32 <= c <= 127 for c in raw),
         "Native profile requires ASCII UTF8, no BOM/control bytes, at most64KiB")
    if expected is not None:
        need(valid_hash(expected) and bytes_sha(raw) == expected, "Raw profile SHA differs")
    return validate_profile(decode(raw))


def source_record(path, relative, size):
    need(relative_source(relative), "Contained project-relative source path required")
    path = Path(path)
    need(path.stat().st_size == size, "Raw source has wrong byte count")
    return {"project_relative_path": relative, "bytes": size, "sha256": file_sha(path)}


def build_profile(native, scene, scene_sha, census_sha, native_sha, height, weights, lineage, namespace):
    need(native.get("schema") == "LivingTown.ReserveLandscapeNative.v1"
         and native.get("status") == "READY_NATIVE_LANDSCAPE_SOURCE_HEIGHT_COMPONENTS_AND_COLLISION",
         "Actual source-ready native receipt required")
    need(native.get("all_source_uint16_samples_exact") is True
         and equal_number(native.get("height_mismatch_count"), 0)
         and native.get("source_height_sha256") == native.get("merged_height_sha256") == height["sha256"],
         "Native source/merged/declared heights must match")
    for key, value in (("width", 505), ("height", 505), ("subsection_size_quads", 63), ("num_subsections", 2),
                       ("component_size_quads", 126), ("component_count", 16), ("collision_component_count", 16),
                       ("collision_mip", 0), ("simple_collision_mip", 0), ("edit_layer_count", 1)):
        need(equal_number(native.get(key), value), "Native bounded layout/physics field differs: " + key)
    need(native.get("nanite") is False and native.get("native_layers_up_to_date") is True,
         "Native nonNanite/merge-ready receipt required")
    need(native.get("sample_extent_xy_inclusive") == [0, 0, 504, 504]
         and native.get("scale_xyz") == [100, 100, 25]
         and native.get("rotation_pitch_yaw_roll") == [0, 0, 0], "Native transform/extent differs")
    layers = native.get("edit_layers")
    need(type(layers) is list and len(layers) == 1 and type(layers[0]) is dict, "One actual edit layer required")
    need(guid(native.get("guid")) and guid(layers[0].get("guid")), "Actual nonzero GUID values required")
    need(type(scene.get("files")) is list and scene["files"], "Saved source closure required")
    for row in scene["files"]:
        need(type(row) is dict and type(row.get("path")) is str and valid_hash(row.get("sha256")), "Malformed scene file binding")
        path = Path(row["path"])
        need(type(row.get("bytes")) is int and path.stat().st_size == row["bytes"]
             and file_sha(path) == row["sha256"], "Source-scene file changed: " + str(path))
    need(package(namespace), "New project LayerInfo namespace required")
    profile = {"schema": SCHEMA, "mode": MODE, "map_path": native.get("map"),
               "landscape_actor_label": native.get("actor_label"), "landscape_guid": native["guid"].upper(),
               "edit_layer_guid": layers[0]["guid"].upper(), "material_path": native.get("material"),
               "height": height, "weights": {**weights, "encoding": "uint8_interleaved_RGBA_no_header", "per_vertex_sum": 255},
               "layout": {"width": SIDE, "height": SIDE, "subsection_size_quads": 63, "num_subsections": 2,
                          "component_count_xy": [4, 4], "origin_cm": native.get("location_cm"), "scale_xyz": [100, 100, 25],
                          "row0": "minimum_UE_Y", "rotation_pitch_yaw_roll": [0, 0, 0]},
               "roles": [{"channel": i, "name": name, "layer_info_path": namespace + "/LI_" + name + "_v001.LI_" + name + "_v001"}
                         for i, name in enumerate(ROLES)], "visibility_policy": VISIBILITY,
               "source_scene": {"lineage": lineage, "manifest_sha256": scene_sha, "population_census_sha256": census_sha},
               "prerequisite_read_receipt_sha256": native_sha}
    validate_profile(profile)
    actor = native.get("actor")
    need(type(actor) is str and actor.startswith(profile["map_path"] + "." + profile["map_path"].rsplit("/", 1)[1] + ":PersistentLevel."),
         "Native actor belongs to another Map")
    return profile


def encode_profile(profile, line_ending="lf"):
    raw = (json.dumps(profile, indent=2, allow_nan=False) + "\n").encode("ascii")
    need(line_ending in ("lf", "crlf"), "Explicit LF or CRLF serialization required")
    if line_ending == "crlf":
        raw = raw.replace(b"\n", b"\r\n")
    validate_raw_profile(raw)
    return raw


def write_new_pair(output, raw, provenance):
    output = Path(output)
    receipt = output.with_suffix(".provenance.json")
    need(not output.exists() and not receipt.exists(), "Refusing an existing profile or provenance file")
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("xb") as stream:
        stream.write(raw)
    with receipt.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(provenance, stream, indent=2, allow_nan=False)
        stream.write("\n")


def self_test():
    refused = 0
    def rejects(call):
        nonlocal refused
        try:
            call()
        except (ValueError, json.JSONDecodeError):
            refused += 1
            return
        raise AssertionError("Negative profile control accepted")
    with tempfile.TemporaryDirectory(prefix="lt_profile_selftest_") as temporary:
        root = Path(temporary).resolve()
        need(root.is_relative_to(Path(tempfile.gettempdir()).resolve()), "Owned temporary self-test directory")
        h = root / "height.r16"; h.write_bytes(b"\x00\x80" * COUNT)
        w = root / "weights.rgba8"; w.write_bytes(bytes([255, 0, 0, 0]) * COUNT)
        asset = root / "Map.cpu_fixture"; asset.write_bytes(b"CPU_ONLY_NOT_UNREAL")
        native = {"schema": "LivingTown.ReserveLandscapeNative.v1", "status": "READY_NATIVE_LANDSCAPE_SOURCE_HEIGHT_COMPONENTS_AND_COLLISION",
                  "map": "/Game/Test/L_Source", "actor": "/Game/Test/L_Source.L_Source:PersistentLevel.Landscape_0",
                  "actor_label": "LT_Test", "guid": "1" * 32, "edit_layers": [{"guid": "2" * 32}],
                  "material": "/Game/Test/M_Surface.M_Surface", "source_height_sha256": file_sha(h),
                  "merged_height_sha256": file_sha(h), "all_source_uint16_samples_exact": True,
                  "height_mismatch_count": 0, "width": 505, "height": 505, "subsection_size_quads": 63,
                  "num_subsections": 2, "component_size_quads": 126, "component_count": 16,
                  "collision_component_count": 16, "collision_mip": 0, "simple_collision_mip": 0, "edit_layer_count": 1,
                  "nanite": False, "native_layers_up_to_date": True, "sample_extent_xy_inclusive": [0, 0, 504, 504],
                  "scale_xyz": [100, 100, 25], "rotation_pitch_yaw_roll": [0, 0, 0], "location_cm": [-60000, -22400, 4000]}
        scene = {"files": [{"path": str(asset), "bytes": asset.stat().st_size, "sha256": file_sha(asset)}]}
        height = source_record(h, HEIGHT_RELATIVE, COUNT * 2); weights = source_record(w, WEIGHTS_RELATIVE, COUNT * 4)
        profile = build_profile(native, scene, "a" * 64, "b" * 64, "c" * 64, height, weights, "CPU_fixture", "/Game/Test/Roles")
        raw = encode_profile(profile); validate_raw_profile(raw, bytes_sha(raw))
        rejects(lambda: validate_raw_profile(raw, "0" * 64))
        rejects(lambda: validate_raw_profile(raw.replace(b'"schema":', b'"schema":"duplicate","schema":', 1)))
        rejects(lambda: validate_raw_profile(b"\xef\xbb\xbf" + raw))
        for mutate in (lambda x: x.update(foreign_key=0), lambda x: x["layout"].update(width=True),
                       lambda x: x["layout"].update(width=1025), lambda x: x["layout"].update(origin_cm=[0, 0, float("nan")]),
                       lambda x: x["height"].update(project_relative_path="Content/../foreign.r16"),
                       lambda x: x["weights"].update(project_relative_path="C:/foreign.bin"),
                       lambda x: x.update(landscape_guid="0" * 32), lambda x: x.update(edit_layer_guid=x["landscape_guid"]),
                       lambda x: x["roles"][1].update(layer_info_path=x["roles"][0]["layer_info_path"]),
                       lambda x: x["roles"][0].update(layer_info_path="/Engine/Foreign.Foreign")):
            candidate = decode(raw); mutate(candidate); rejects(lambda c=candidate: validate_profile(c))
        rejects(lambda: build_profile({**native, "source_height_sha256": "0" * 64}, scene, "a"*64, "b"*64, "c"*64, height, weights, "CPU", "/Game/Test/Roles"))
        output = root / "profile.json"; write_new_pair(output, raw, {"CPU_fixture_only": True})
        rejects(lambda: write_new_pair(output, raw, {})); need(output.read_bytes() == raw, "Existing profile preserved")
        asset.write_bytes(b"changed"); rejects(lambda: build_profile(native, scene, "a"*64, "b"*64, "c"*64, height, weights, "CPU", "/Game/Test/Roles"))
    return {"status": "PASS_CPU_PROFILE_CONTRACT_NOT_NATIVE_WORLD", "negative_controls": refused}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--validate", type=Path, help="Validate existing raw profile format; does not inspect a native world")
    parser.add_argument("--expected-profile-sha256")
    parser.add_argument("--line-ending", choices=("lf", "crlf"), default="lf",
                        help="Deterministic LF by default; CRLF reproduces retained Windows profile bytes")
    for name in ("native-read", "source-scene-manifest", "population-census"):
        parser.add_argument("--" + name, type=Path)
        parser.add_argument("--expected-" + name + "-sha256")
    parser.add_argument("--height", type=Path); parser.add_argument("--weights", type=Path)
    parser.add_argument("--height-project-relative", default=HEIGHT_RELATIVE)
    parser.add_argument("--weights-project-relative", default=WEIGHTS_RELATIVE)
    parser.add_argument("--lineage"); parser.add_argument("--layer-namespace"); parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    if args.self_test:
        print(json.dumps(self_test())); return
    if args.validate:
        raw = args.validate.read_bytes(); validate_raw_profile(raw, args.expected_profile_sha256)
        print(json.dumps({"status": "PASS_PROFILE_FORMAT_NOT_NATIVE_WORLD", "bytes": len(raw), "sha256": bytes_sha(raw)})); return
    need(all(getattr(args, name) is not None for name in ("native_read", "expected_native_read_sha256", "source_scene_manifest",
         "expected_source_scene_manifest_sha256", "population_census", "expected_population_census_sha256", "height", "weights",
         "lineage", "layer_namespace", "output")), "Native/source/census evidence paths+SHAs, height/weights, lineage, namespace and output are required")
    native = bound_json(args.native_read, args.expected_native_read_sha256)
    scene = bound_json(args.source_scene_manifest, args.expected_source_scene_manifest_sha256)
    bound_json(args.population_census, args.expected_population_census_sha256)
    height = source_record(args.height, args.height_project_relative, COUNT * 2)
    weights = source_record(args.weights, args.weights_project_relative, COUNT * 4)
    data = args.weights.read_bytes()
    need(all(sum(v) == 255 for v in zip(data[0::4], data[1::4], data[2::4], data[3::4])), "Every semantic sample must sum255")
    profile = build_profile(native, scene, args.expected_source_scene_manifest_sha256, args.expected_population_census_sha256,
                            args.expected_native_read_sha256, height, weights, args.lineage, args.layer_namespace)
    raw = encode_profile(profile, args.line_ending)
    inputs = {name: {"path": str(getattr(args, name).resolve()), "sha256": file_sha(getattr(args, name))}
              for name in ("native_read", "source_scene_manifest", "population_census", "height", "weights")}
    result = {"status": "PROFILE_FROZEN_NATIVE_APPLY_READ_COLD_NOT_EXECUTED", "profile_sha256": bytes_sha(raw),
              "line_ending": args.line_ending,
              "profile_bytes": len(raw), "evidence": inputs, "GUIDs_copied_from_native_receipt": True,
              "native_population_or_art_qualified": False, "engine_or_FCommandLine_changed": False}
    write_new_pair(args.output, raw, result)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
