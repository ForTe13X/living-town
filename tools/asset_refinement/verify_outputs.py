"""Offline source, GLB and owned-view checks for a reconstructed cafe hero.

PASS covers file provenance, portable geometry/material attributes and explicit
input bindings. It does not claim native Blender reopening, visual approval,
ComfyUI inference, engine performance, collisions, or navigation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct


REPO = Path(__file__).resolve().parents[2]
VIEW_ORDER = ("front", "left", "back", "right")
SOURCE_MODULES = {f"tools/asset_refinement/{name}.py" for name in (
    "hero_scene", "hero_furniture", "hero_foliage", "hero_surfaces", "materials", "hero_pbr"
)}
TYPES = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
COMPONENTS = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
              5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def _need(condition, message):
    if not condition:
        raise ValueError(message)


def _relative(base, name):
    path = (base / str(name).replace("\\", "/")).resolve()
    _need(path.is_relative_to(base.resolve()), f"Path escapes its artifact: {name}")
    return path


def _bound_file(base, name, row):
    path = _relative(base, name)
    _need(path.is_file(), f"Missing bound file: {name}")
    _need(sha(path) == row["sha256"], f"SHA mismatch: {name}")
    if "bytes" in row:
        _need(path.stat().st_size == row["bytes"], f"Byte count mismatch: {name}")
    return path


class GLB:
    def __init__(self, path):
        self.path = Path(path)
        data = self.path.read_bytes()
        _need(len(data) >= 28, "Truncated GLB")
        magic, version, size = struct.unpack_from("<4sII", data)
        _need((magic, version, size) == (b"glTF", 2, len(data)), "Invalid GLB header")
        chunks, offset = [], 12
        while offset < len(data):
            _need(offset + 8 <= len(data), "Truncated GLB chunk header")
            length, kind = struct.unpack_from("<I4s", data, offset)
            offset += 8
            _need(length % 4 == 0 and offset + length <= len(data), "Invalid GLB chunk bounds")
            chunks.append((kind, data[offset:offset + length]))
            offset += length
        _need([kind for kind, _ in chunks] == [b"JSON", b"BIN\0"],
              "Expected exactly embedded JSON and BIN GLB chunks")
        self.doc = json.loads(chunks[0][1])
        self.binary = chunks[1][1]
        _need(self.doc.get("asset", {}).get("version") == "2.0", "Expected glTF 2.0")
        _need(set(self.doc.get("extensionsRequired", [])) <= {"KHR_texture_transform"},
              "This portable profile only supports required KHR_texture_transform")
        buffers = self.doc.get("buffers", [])
        _need(len(buffers) == 1 and "uri" not in buffers[0], "Buffer must be embedded; URI forbidden")
        self.length = buffers[0]["byteLength"]
        _need(self.length <= len(self.binary) <= self.length + 3, "Embedded buffer length mismatch")
        self.cache = {}
        self._validate_buffers()

    def _validate_buffers(self):
        for index, view in enumerate(self.doc.get("bufferViews", [])):
            _need(view.get("buffer") == 0, f"Invalid bufferView buffer: {index}")
            offset, length = view.get("byteOffset", 0), view["byteLength"]
            _need(offset >= 0 and length > 0 and offset + length <= self.length,
                  f"Invalid bufferView span: {index}")
        for image in self.doc.get("images", []):
            _need("uri" not in image and "bufferView" in image, "Image must be embedded; URI forbidden")
            _need(image.get("mimeType") in ("image/png", "image/jpeg"), "Unsupported embedded image MIME")
            view = self.doc["bufferViews"][image["bufferView"]]
            start = view.get("byteOffset", 0)
            prefix = self.binary[start:start + 8]
            _need(prefix == b"\x89PNG\r\n\x1a\n" if image["mimeType"] == "image/png"
                  else prefix[:3] == b"\xff\xd8\xff", "Embedded image signature mismatch")
        for index in range(len(self.doc.get("accessors", []))):
            self.accessor(index)

    def accessor(self, index):
        if index in self.cache:
            return self.cache[index]
        _need(isinstance(index, int) and 0 <= index < len(self.doc["accessors"]), "Invalid accessor index")
        accessor = self.doc["accessors"][index]
        _need("sparse" not in accessor and "bufferView" in accessor,
              "This authored-asset profile expects dense embedded accessors")
        _need(accessor["componentType"] in COMPONENTS and accessor["type"] in TYPES,
              "Unsupported accessor component/type")
        component, width = COMPONENTS[accessor["componentType"]]
        count, elements = accessor["count"], TYPES[accessor["type"]]
        _need(isinstance(count, int) and count > 0, "Accessor has no elements")
        view = self.doc["bufferViews"][accessor["bufferView"]]
        stride = view.get("byteStride", elements * width)
        offset = accessor.get("byteOffset", 0)
        _need(stride >= elements * width and stride % width == 0 and offset >= 0,
              "Invalid accessor stride/offset")
        _need(offset + (count - 1) * stride + elements * width <= view["byteLength"],
              "Accessor exceeds its embedded bufferView")
        start = view.get("byteOffset", 0) + offset
        values = [struct.unpack_from("<" + component * elements, self.binary, start + row * stride)
                  for row in range(count)]
        _need(all(math.isfinite(value) for row in values for value in row), "Non-finite accessor data")
        self.cache[index] = values
        return values


def _identity():
    return [[float(row == column) for column in range(4)] for row in range(4)]


def _multiply(a, b):
    return [[sum(a[row][k] * b[k][column] for k in range(4)) for column in range(4)] for row in range(4)]


def _matrix(node):
    if "matrix" in node:
        _need(len(node["matrix"]) == 16, "Invalid node matrix")
        return [[node["matrix"][column * 4 + row] for column in range(4)] for row in range(4)]
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    result = [[1 - 2 * (y*y + z*z), 2 * (x*y - z*w), 2 * (x*z + y*w), 0],
              [2 * (x*y + z*w), 1 - 2 * (x*x + z*z), 2 * (y*z - x*w), 0],
              [2 * (x*z - y*w), 2 * (y*z + x*w), 1 - 2 * (x*x + y*y), 0],
              [0, 0, 0, 1]]
    scale, translation = node.get("scale", [1, 1, 1]), node.get("translation", [0, 0, 0])
    for row in range(3):
        for column in range(3):
            result[row][column] *= scale[column]
        result[row][3] = translation[row]
    _need(all(math.isfinite(value) for row in result for value in row), "Invalid node TRS")
    return result


def _world_nodes(document):
    nodes = document.get("nodes", [])
    result, stack = {}, set()
    def visit(index, parent):
        _need(0 <= index < len(nodes) and index not in stack and index not in result,
              "Cyclic, duplicate-parent or invalid scene node")
        stack.add(index)
        world = _multiply(parent, _matrix(nodes[index]))
        result[index] = world
        for child in nodes[index].get("children", []):
            visit(child, world)
        stack.remove(index)
    scene = document["scenes"][document.get("scene", 0)]
    for index in scene["nodes"]:
        visit(index, _identity())
    return result


def _point(matrix, value):
    return tuple(sum(matrix[row][column] * value[column] for column in range(3)) + matrix[row][3]
                 for row in range(3))


def _texture_coordinates(material):
    slots = []
    for key in ("normalTexture", "occlusionTexture", "emissiveTexture"):
        if key in material:
            slots.append(material[key])
    slots.extend(value for key, value in material.get("pbrMetallicRoughness", {}).items()
                 if key.endswith("Texture"))
    coordinates = []
    for slot in slots:
        transform = slot.get("extensions", {}).get("KHR_texture_transform", {})
        _need(isinstance(transform, dict), "Invalid KHR_texture_transform object")
        for name, default in (("offset", [0, 0]), ("scale", [1, 1])):
            values = transform.get(name, default)
            _need(isinstance(values, list) and len(values) == 2
                  and all(isinstance(value, (int, float)) and math.isfinite(value) for value in values),
                  "Invalid KHR_texture_transform " + name)
            if name == "scale":
                _need(all(value != 0 for value in values), "Degenerate KHR_texture_transform scale")
        rotation = transform.get("rotation", 0)
        _need(isinstance(rotation, (int, float)) and math.isfinite(rotation),
              "Invalid KHR_texture_transform rotation")
        coordinate = transform.get("texCoord", slot.get("texCoord", 0))
        _need(isinstance(coordinate, int) and coordinate >= 0, "Invalid texture-coordinate index")
        coordinates.append(coordinate)
    return coordinates


def inspect_glb(path, *, expected_nodes=(), expected_bounds_blender=None, expected_root=None):
    """Read actual binary arrays, indices and mesh-node transforms independently."""
    glb = GLB(path)
    document = glb.doc
    meshes, materials = document.get("meshes", []), document.get("materials", [])
    _need(meshes and materials and document.get("images"), "Expected authored meshes, PBR materials and embedded images")
    triangles = degenerate = normal_primitives = tangent_primitives = 0
    for mesh in meshes:
        _need(mesh.get("primitives"), "Empty mesh")
        for primitive in mesh["primitives"]:
            _need(primitive.get("mode", 4) == 4, "Expected explicitly triangulated primitives")
            attributes = primitive.get("attributes", {})
            _need({"POSITION", "NORMAL", "TEXCOORD_0"}.issubset(attributes),
                  "Mesh primitive lacks POSITION, NORMAL or TEXCOORD_0")
            positions = glb.accessor(attributes["POSITION"])
            count = len(positions)
            for key, accessor in attributes.items():
                _need(len(glb.accessor(accessor)) == count, f"Vertex attribute count mismatch: {key}")
            _need(all(len(row) == 3 for row in positions), "POSITION must be VEC3")
            _need(all(len(row) == 3 and sum(v*v for v in row) > .1
                      for row in glb.accessor(attributes["NORMAL"])), "Invalid mesh normal vectors")
            material = materials[primitive["material"]]
            for texcoord in _texture_coordinates(material):
                _need(f"TEXCOORD_{texcoord}" in attributes, "Texture uses a missing TEXCOORD set")
                _need(all(len(row) == 2 for row in glb.accessor(attributes[f"TEXCOORD_{texcoord}"])),
                      "Texture coordinates must be VEC2")
            if "normalTexture" in material:
                normal_primitives += 1
                _need("TANGENT" in attributes, "Normal-mapped mesh lacks explicit TANGENT")
                tangents = glb.accessor(attributes["TANGENT"])
                _need(all(len(row) == 4 and sum(v*v for v in row[:3]) > .1
                          and abs(abs(row[3]) - 1) < .001 for row in tangents), "Invalid tangent basis")
                tangent_primitives += 1
            _need("indices" in primitive, "Expected explicit triangle indices")
            index_accessor = document["accessors"][primitive["indices"]]
            _need(index_accessor["type"] == "SCALAR" and index_accessor["componentType"] in (5121, 5123, 5125),
                  "Invalid triangle index component/type")
            indices = [row[0] for row in glb.accessor(primitive["indices"])]
            _need(len(indices) > 0 and len(indices) % 3 == 0, "Invalid triangle index count")
            _need(min(indices) >= 0 and max(indices) < count, "Triangle index outside POSITION array")
            nonzero = 0
            for offset in range(0, len(indices), 3):
                a, b, c = (positions[indices[offset + step]] for step in range(3))
                ab, ac = [b[k]-a[k] for k in range(3)], [c[k]-a[k] for k in range(3)]
                cross = (ab[1]*ac[2]-ab[2]*ac[1], ab[2]*ac[0]-ab[0]*ac[2], ab[0]*ac[1]-ab[1]*ac[0])
                nonzero += sum(v*v for v in cross) > 1e-24
            _need(nonzero > 0, "Primitive has no nonzero-area triangles")
            triangles += len(indices) // 3
            degenerate += len(indices) // 3 - nonzero
    _need(normal_primitives > 0, "Expected normal-mapped authored surfaces")
    world = _world_nodes(document)
    by_name = {}
    for index in world:
        node = document["nodes"][index]
        name = node.get("name")
        if name:
            _need(name not in by_name, "Duplicate scene node name")
            by_name[name] = index
    expected_nodes = set(expected_nodes)
    _need(expected_nodes.issubset(by_name), "Missing source-bound semantic node names: "
          + ", ".join(sorted(expected_nodes.difference(by_name))[:4]))
    root_retained = False
    if expected_root:
        _need(expected_root in by_name, "Standalone authoring root hierarchy is missing")
        root_index = by_name[expected_root]
        root_node = document["nodes"][root_index]
        _need(root_node.get("extras", {}).get("original_geometry") is True,
              "Standalone root lost its semantic extras")
        descendants = set()
        def collect(index):
            for child in document["nodes"][index].get("children", []):
                descendants.add(child)
                collect(child)
        collect(root_index)
        _need(all(by_name[name] in descendants for name in expected_nodes),
              "Standalone component escaped its source authoring root")
        root_retained = True
    points = []
    for name in expected_nodes:
        index = by_name[name]
        node = document["nodes"][index]
        _need("mesh" in node, f"Semantic object lost its mesh: {name}")
        extras = node.get("extras", {})
        _need(extras.get("original_geometry") is True and extras.get("furniture_part"),
              f"Semantic furniture extras missing: {name}")
        for primitive in meshes[node["mesh"]]["primitives"]:
            points.extend(_point(world[index], point) for point in glb.accessor(primitive["attributes"]["POSITION"]))
    actual_bounds = None
    if points:
        actual_bounds = [[min(point[axis] for point in points) for axis in range(3)],
                         [max(point[axis] for point in points) for axis in range(3)]]
    if expected_bounds_blender:
        _need(actual_bounds is not None, "Expected bound semantic nodes for bounds comparison")
        low, high = expected_bounds_blender["min"], expected_bounds_blender["max"]
        expected = [[low[0], low[2], -high[1]], [high[0], high[2], -low[1]]]
        _need(max(abs(actual_bounds[side][axis] - expected[side][axis])
                  for side in range(2) for axis in range(3)) <= .0002,
              "GLB semantic bounds do not match Blender source after x,z,-y transform")
    return {"status": "PASS", "sha256": sha(path), "bytes": Path(path).stat().st_size,
            "meshes": len(meshes), "scene_nodes": len(world), "triangles_unique": triangles,
            "degenerate_triangles_recorded": degenerate, "embedded_images": len(document["images"]),
            "normal_mapped_primitives": normal_primitives, "explicit_tangent_primitives": tangent_primitives,
            "expected_semantic_nodes": len(expected_nodes), "semantic_bounds_gltf_m": actual_bounds,
            "standalone_root_retained": root_retained,
            "extensions_used": document.get("extensionsUsed", []),
            "extensions_required": document.get("extensionsRequired", []),
            "scope": "Dense embedded uncompressed glTF arrays, PBR texcoord/tangent coverage, indices, semantic child IDs and actual scene transforms"}


def png_info(path, expected):
    with Path(path).open("rb") as stream:
        header = stream.read(33)
    _need(len(header) == 33 and header[:16] == b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR", "Invalid PNG header")
    width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", header[16:29])
    _need((width, height) == expected and (depth, color, compression, filtering, interlace) == (8, 6, 0, 0, 0),
          "Expected correctly sized 8-bit RGBA owned view")
    result = {"dimensions": [width, height], "rgba": True, "pixel_alpha_checked": False}
    try:
        from PIL import Image
    except ImportError:
        return result
    with Image.open(path) as image:
        image.load()
        extrema = image.getchannel("A").getextrema()
        _need(extrema == (0, 255), "Owned view must contain visible geometry and transparent background")
        result["pixel_alpha_checked"] = True
        result["alpha_extrema"] = list(extrema)
    return result


def native_info(path):
    with Path(path).open("rb") as stream:
        header = stream.read(32)
    if header.startswith(b"BLENDER"):
        return {"container": "Blender native uncompressed", "native_header_verified": True,
                "native_reopened": False}
    if header.startswith(b"\x28\xb5\x2f\xfd"):
        # Blender 5.x saves Zstandard-framed .blend files by default. The
        # standard library on the supported Python runtime has no Zstd reader;
        # recognizing this envelope is not proof of its decompressed contents.
        return {"container": "Zstandard framed .blend", "compression_magic_verified": True,
                "native_header_verified": False, "native_reopened": False,
                "content_validation": "Requires independent Blender reopen; this static verifier does not decompress Zstandard."}
    if header.startswith(b"\x1f\x8b"):
        import gzip
        with gzip.open(path, "rb") as stream:
            _need(stream.read(7) == b"BLENDER", "Gzip file does not contain a Blender native header")
        return {"container": "Gzip compressed Blender native", "native_header_verified": True,
                "native_reopened": False}
    raise ValueError("Native file has neither Blender, Zstandard nor gzip container header")


def _source_path(base, name):
    path = Path(str(name).replace("\\", "/"))
    return path.resolve() if path.is_absolute() else (base / path).resolve()


def _prepared_checks(prepared, hero, hero_manifest_sha, workflows=None):
    preparation_path = prepared / "preparation_manifest.json"
    preparation = json.loads(preparation_path.read_text(encoding="utf-8"))
    _need(preparation.get("schema") == "living_town.owned_view_preparation.v1",
          "Unknown owned-view preparation schema")
    _need(preparation.get("source_hero_manifest_sha256") == hero_manifest_sha,
          "Prepared inputs refer to another hero manifest")
    _need(preparation.get("ai_inference_executed") is False, "Prepared input inference gate changed")
    _need(preparation["view_order"] == list(VIEW_ORDER)
          and [row["name"] for row in preparation["views"]] == list(VIEW_ORDER),
          "Prepared conditioning view order changed")
    for row in preparation["views"]:
        source = _source_path(prepared, row["source_path"])
        _need(source == (hero / "input" / (row["name"] + ".png")).resolve()
              and sha(source) == row["source_sha256"], "Prepared view source binding differs from hero")
        _need(row["dimensions"] == [1024, 1024] and row["mode"] == "RGBA",
              "Prepared view dimensions/mode mismatch")
        png_info(_bound_file(prepared, row["path"], row), (1024, 1024))
    mesh = preparation["mesh"]
    _need(_source_path(prepared, mesh["source_path"]) == (hero / "input/counter.glb").resolve()
          and sha(hero / "input/counter.glb") == mesh["sha256"], "Prepared mesh differs from source counter")
    _bound_file(prepared, mesh["path"], mesh)
    sheet = preparation["sheet"]
    _need(sheet["dimensions"] == [4096, 1024], "Prepared sheet dimensions mismatch")
    png_info(_bound_file(prepared, sheet["path"], sheet), (4096, 1024))
    sheet_pixels_checked = False
    try:
        from PIL import Image, ImageChops
    except ImportError:
        pass
    else:
        with Image.open(prepared / sheet["path"]) as image:
            for index, row in enumerate(preparation["views"]):
                with Image.open(prepared / row["path"]) as view, Image.open(
                    _source_path(prepared, row["source_path"])
                ) as original:
                    _need(ImageChops.difference(view.getchannel("A"), original.getchannel("A")).getbbox() is None,
                          "Prepared view changed original alpha")
                    crop = image.crop((index * 1024, 0, (index + 1) * 1024, 1024))
                    _need(crop.tobytes() == view.tobytes(), "Prepared sheet panel differs from its owned view")
        sheet_pixels_checked = True
    workflow_base = workflows if workflows is not None else prepared
    path = workflow_base / "workflow_manifest.json"
    if not path.exists():
        candidates = list(workflow_base.rglob("workflow_manifest.json"))
        _need(len(candidates) == 1, "Expected exactly one prepared workflow_manifest.json")
        path = candidates[0]
    record = json.loads(path.read_text(encoding="utf-8"))
    _need(record.get("schema") == "living-town.asset-refinement-workflows.v1", "Unknown prepared workflow schema")
    _need(record["execution"]["performed"] is False and record["execution"]["permitted"] is False,
          "Offline workflow execution gate changed")
    _need(record["uv"]["atlas_validated_by_caller"] is False and record["uv"]["ultratex_mode"] != "keep_existing",
          "Metric hero UVs cannot be treated as a validated existing atlas")
    _need(record["image_contract"]["owned_views"] == list(VIEW_ORDER), "Prepared view order changed")
    # Input paths intentionally point outside the workflow subfolder. Explicit
    # SHA bindings are the authority; artifact-internal confinement is unsuitable.
    inputs = {}
    for role, row in record["inputs"].items():
        source = (path.parent / row["path"]).resolve()
        _need(source.is_file() and sha(source) == row["sha256"], f"Prepared input SHA mismatch: {role}")
        inputs[role] = {"sha256": row["sha256"], "bytes": source.stat().st_size}
        if role == "mesh":
            _need(source == (prepared / mesh["path"]).resolve(), "Workflow mesh does not use prepared counter")
        elif role == "sheet":
            _need(source == (prepared / sheet["path"]).resolve(), "Workflow sheet does not use prepared owned sheet")
        elif role == "reference":
            _need(source == (prepared / preparation["views"][0]["path"]).resolve(), "Workflow front reference binding changed")
        elif role.startswith("view_"):
            index = VIEW_ORDER.index(role.removeprefix("view_"))
            _need(source == (prepared / preparation["views"][index]["path"]).resolve(), "Workflow owned view binding changed")
    for name, row in record["workflows"].items():
        graph_path = _bound_file(path.parent, name, row)
        graph = json.loads(graph_path.read_text(encoding="utf-8"))
        _need(graph["extra"]["living_town_refinement"]["execution_permitted"] is False,
              "Workflow graph execution gate changed")
    _need(record["gates"]["ultratex_9b"]["status"] == "BLOCKED_NONCOMMERCIAL"
          and record["gates"]["qwen_research"]["status"] == "BLOCKED_RESEARCH_LICENSE"
          and record["gates"]["owned_multiview"]["status"] == "MANUAL_REVIEW_REQUIRED",
          "Model license gate changed")
    return {"status": "PASS", "workflow_manifest_sha256": sha(path), "inputs": inputs,
            "preparation_manifest_sha256": sha(preparation_path),
            "sheet_pixels_and_original_alpha_checked": sheet_pixels_checked,
            "inference_performed": False, "metric_uv_not_atlas": True}


def verify(hero, prepared=None, *, repo=REPO, workflows=None):
    hero, repo = Path(hero).resolve(), Path(repo).resolve()
    path = hero / "hero_manifest.json"
    record = json.loads(path.read_text(encoding="utf-8"))
    _need(record.get("schema") == "living_town.reconstructed_cafe_hero.v1", "Unknown hero schema")
    _need(record.get("ai_inference_executed") is False, "Hero is not the offline original-asset route")
    modules = {name.replace("\\", "/"): digest for name, digest in record["source_modules"].items()}
    _need(set(modules) == SOURCE_MODULES, "Unexpected hero source module inventory")
    for name, digest in modules.items():
        _need(sha(_relative(repo, name)) == digest, f"Current source module differs: {name}")
    _need(sha(repo / "art/living_town/concept/01_idealized_presentation.png") == record["concept_sha256"],
          "Concept reference SHA mismatch")
    files = {name.replace("\\", "/"): row for name, row in record["files"].items()}
    required = {"cafe_hero.blend", "cafe_hero.glb", "input/counter.glb",
                *(f"input/{name}.png" for name in VIEW_ORDER),
                "renders/01_cafe_street.png", "renders/02_cafe_interior.png"}
    _need(required.issubset(files), "Hero manifest omits a required output")
    for name, row in files.items():
        _bound_file(hero, name, row)
    native = native_info(hero / "cafe_hero.blend")
    counter = record["counter"]
    whole = inspect_glb(hero / "cafe_hero.glb", expected_nodes=counter["objects"],
                        expected_bounds_blender=counter["bounds"])
    standalone = inspect_glb(hero / "input/counter.glb", expected_nodes=counter["objects"],
                             expected_bounds_blender=counter["bounds"], expected_root=counter["root"])
    _need(whole["meshes"] > standalone["meshes"], "Whole hero unexpectedly contains only the standalone counter")
    _need(record["counter"]["triangles"] + sum(item["triangles"] for item in record["bistro_sets"][:2]) < 150000,
          "Counter and two dining sets exceed the agreed geometry budget")
    views = record["conditioning_views"]
    _need([view["name"] for view in views] == list(VIEW_ORDER), "Hero conditioning view order changed")
    view_results = []
    for view in views:
        image = _bound_file(hero, view["image"], view)
        view_results.append({"view": view["name"], "sha256": view["sha256"], **png_info(image, (1024, 1024))})
    positions = [view["camera_position_blender_m"] for view in views]
    _need(len({view["ortho_scale_m"] for view in views}) == 1 and views[0]["ortho_scale_m"] > 0,
          "Owned views have inconsistent orthographic scale")
    _need(abs(positions[0][0] - positions[2][0]) < 1e-6
          and abs(positions[1][1] - positions[3][1]) < 1e-6
          and max(point[2] for point in positions) - min(point[2] for point in positions) < 1e-6
          and positions[1][0] < positions[0][0] < positions[3][0]
          and positions[0][1] < positions[1][1] < positions[2][1],
          "Owned view camera positions are not front/left/back/right orthographic axes")
    report = {"schema": "living_town.concept_hero_static_verification.v1", "status": "PASS",
              "hero_manifest_sha256": sha(path), "source_modules_current": True,
              "native_container": native,
              "bound_file_count": len(files), "whole_glb": whole, "counter_glb": standalone,
              "conditioning_views": view_results, "ai_inference_executed": False,
              "visual_review_performed": False,
              "scope": "Current source/file hashes, GLB dense geometry/PBR/semantic child IDs/transforms, four owned RGBA input records. Separate visual and engine checks remain required."}
    if prepared is not None:
        report["prepared"] = _prepared_checks(Path(prepared).resolve(), hero, sha(path),
                                               Path(workflows).resolve() if workflows else None)
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hero", type=Path, required=True)
    parser.add_argument("--prepared", type=Path)
    parser.add_argument("--workflows", type=Path, help="Separate offline workflow output directory")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        _need(args.prepared is not None or args.workflows is None, "--workflows requires --prepared")
        result = verify(args.hero, args.prepared, workflows=args.workflows)
    except (ValueError, KeyError, IndexError, OSError, json.JSONDecodeError, struct.error) as error:
        result = {"schema": "living_town.concept_hero_static_verification.v1", "status": "FAIL",
                  "error": str(error), "visual_review_performed": False}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open("x", encoding="utf-8") as stream:
        json.dump(result, stream, indent=2)
        stream.write("\n")
    print(json.dumps({key: result[key] for key in ("status", "error") if key in result}, indent=2))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
