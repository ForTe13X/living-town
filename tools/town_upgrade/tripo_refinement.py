"""Offline GLB preservation evidence for an optional Tripo retexture pilot.

No CLI, network, engine, authentication or generation is invoked. PASS means
the compared preservation contract passed; it never means artistic approval.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import math
from pathlib import Path
import struct


SCHEMA = "living_town.tripo_refinement.v1"
COMPONENTS = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
              5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
SHAPES = {"SCALAR": (1, 1), "VEC2": (1, 2), "VEC3": (1, 3),
          "VEC4": (1, 4), "MAT2": (2, 2), "MAT3": (3, 3), "MAT4": (4, 4)}
SUPPORTED_REQUIRED = {"KHR_texture_transform", "KHR_materials_unlit", "KHR_mesh_quantization"}
COMPRESSION = {"KHR_draco_mesh_compression", "EXT_meshopt_compression"}
SCOPE = ("Exact decoded core glTF geometry, UV, skin, morph, rest-node and clip preservation. "
         "Material/image changes are allowed; normal/tangent changes need separate visual review. "
         "No aesthetic acceptance, task completion, entitlement or CC0 claim is inferred.")


def need(condition, reason):
    if not condition:
        raise ValueError(reason)


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False, allow_nan=False).encode("utf-8")


def fingerprint(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def integer(value, label, minimum=0):
    need(type(value) is int and value >= minimum, "Invalid " + label)
    return value


def reference(items, index, label):
    integer(index, label)
    need(index < len(items), "Out-of-range " + label)
    return items[index]


def reject_constant(value):
    raise ValueError("Nonfinite JSON constant: " + value)


def check_json(value):
    if isinstance(value, float):
        need(math.isfinite(value), "Nonfinite JSON number")
    elif isinstance(value, list):
        for item in value:
            check_json(item)
    elif isinstance(value, dict):
        need(not COMPRESSION.intersection(value.get("extensions", {})),
             "Compressed geometry is unsupported; preservation unverified")
        for item in value.values():
            check_json(item)


class GLB:
    """Strict embedded GLB reader, including interleaved and sparse accessors.

    Compare decoded element values, not buffer offsets or accessor identifiers.
    Matrix columns honor glTF's four-byte alignment for small integer types.
    External resources and unsupported required extensions fail closed.
    """
    def __init__(self, path):
        self.path = Path(path).resolve()
        self.size = self.path.stat().st_size
        need(20 <= self.size <= 150 * 1024 * 1024, "GLB size outside 20B..150MiB pilot limit")
        self.source_sha256 = sha(self.path)
        with self.path.open("rb") as stream:
            magic, version, declared = struct.unpack("<4sII", stream.read(12))
            need((magic, version, declared) == (b"glTF", 2, self.size), "Invalid GLB header")
            chunks = []
            while stream.tell() < self.size:
                header = stream.read(8)
                need(len(header) == 8, "Truncated GLB chunk header")
                length, kind = struct.unpack("<I4s", header)
                need(length % 4 == 0 and stream.tell() + length <= self.size, "Invalid GLB chunk span")
                chunks.append((kind, stream.tell(), length))
                stream.seek(length, 1)
            need(len(chunks) == 2 and [c[0] for c in chunks] == [b"JSON", b"BIN\0"],
                 "Expected exactly JSON then embedded BIN chunk")
            stream.seek(chunks[0][1])
            self.doc = json.loads(stream.read(chunks[0][2]), parse_constant=reject_constant)
        need(isinstance(self.doc, dict) and self.doc.get("asset", {}).get("version") == "2.0", "Not glTF 2.0")
        check_json(self.doc)
        need(not COMPRESSION.intersection(self.doc.get("extensionsUsed", [])),
             "Compressed geometry is unsupported; preservation unverified")
        required = set(self.doc.get("extensionsRequired", []))
        need(required <= SUPPORTED_REQUIRED, "Unsupported required extensions: " + ", ".join(sorted(required - SUPPORTED_REQUIRED)))
        # An unknown optional geometry extension can also refer to accessor data
        # (for example instancing). Its JSON alone cannot prove preservation.
        for collection in ("nodes", "meshes", "skins", "animations", "accessors", "bufferViews"):
            for item in self.doc.get(collection, []):
                need(not item.get("extensions"), "Unsupported geometry extension in " + collection)
                for child in item.get("primitives", []) + item.get("channels", []) + item.get("samplers", []):
                    need(not child.get("extensions"), "Unsupported geometry extension in " + collection)
        buffers = self.doc.get("buffers", [])
        need(len(buffers) == 1 and "uri" not in buffers[0], "Expected one embedded buffer; external resources unsupported")
        self.buffer_length = integer(buffers[0].get("byteLength"), "buffer length", 1)
        self.bin_offset, self.bin_length = chunks[1][1:]
        need(self.buffer_length <= self.bin_length <= self.buffer_length + 3, "Invalid GLB BIN length")
        for index in range(len(self.doc.get("bufferViews", []))):
            self.view(index)  # validate even an unused view

    def view(self, index):
        view = reference(self.doc.get("bufferViews", []), index, "bufferView")
        offset = integer(view.get("byteOffset", 0), "bufferView offset")
        length = integer(view.get("byteLength"), "bufferView length", 1)
        need(view.get("buffer") == 0 and offset + length <= self.buffer_length,
             "bufferView span exceeds embedded buffer")
        with self.path.open("rb") as stream:
            stream.seek(self.bin_offset + offset)
            data = stream.read(length)
        need(len(data) == length, "Truncated bufferView")
        return data

    def accessor(self, index):
        a = reference(self.doc.get("accessors", []), index, "accessor")
        count = integer(a.get("count"), "accessor count", 1)
        need(count <= 10_000_000, "Accessor exceeds local pilot element limit")
        need(a.get("componentType") in COMPONENTS and a.get("type") in SHAPES, "Unsupported accessor type")
        code, size = COMPONENTS[a["componentType"]]
        columns, rows = SHAPES[a["type"]]
        column_stride = ((rows * size + 3) // 4) * 4 if columns > 1 else rows * size
        width = columns * column_stride
        offsets = [column * column_stride + row * size for column in range(columns) for row in range(rows)]
        need(type(a.get("normalized", False)) is bool, "Invalid accessor normalized flag")
        need(not a.get("normalized", False) or a["componentType"] in (5120, 5121, 5122, 5123), "Invalid normalized component type")

        def unpack(view_id, offset, n, stride=None, packed=False):
            view = reference(self.doc.get("bufferViews", []), view_id, "accessor bufferView")
            data = self.view(view_id)
            integer(offset, "accessor offset")
            need(not packed or "byteStride" not in view, "Sparse bufferView must be tightly packed")
            stride = view.get("byteStride", width) if stride is None else stride
            integer(stride, "accessor stride", 1)
            need(stride >= width and stride % size == 0 and offset % size == 0
                 and (view.get("byteOffset", 0) + offset) % size == 0, "Invalid accessor alignment/stride")
            if columns > 1:
                need((view.get("byteOffset", 0) + offset) % 4 == 0 and stride % 4 == 0, "Invalid matrix column alignment")
            need(offset + (n - 1) * stride + width <= len(data), "Accessor span exceeds bufferView")
            result = [tuple(struct.unpack_from("<" + code, data, offset + i * stride + j)[0]
                            for j in offsets) for i in range(n)]
            need(all(math.isfinite(v) for row in result for v in row), "Nonfinite accessor data")
            return result

        if "bufferView" in a:
            values = unpack(a["bufferView"], a.get("byteOffset", 0), count)
        else:
            need(a.get("byteOffset", 0) == 0, "Zero-base accessor has byte offset")
            zero = 0. if a["componentType"] == 5126 else 0
            values = [(zero,) * (columns * rows) for _ in range(count)]
        if "sparse" in a:
            sparse = a["sparse"]
            n = integer(sparse.get("count"), "sparse count", 1)
            need(n <= count, "Invalid sparse count")
            ids = sparse["indices"]
            need(ids.get("componentType") in (5121, 5123, 5125), "Invalid sparse index component type")
            index_code, index_size = COMPONENTS[ids["componentType"]]
            view = reference(self.doc.get("bufferViews", []), ids["bufferView"], "sparse indices view")
            offset = integer(ids.get("byteOffset", 0), "sparse indices offset")
            data = self.view(ids["bufferView"])
            need("byteStride" not in view and offset % index_size == 0
                 and (view.get("byteOffset", 0) + offset) % index_size == 0
                 and offset + n * index_size <= len(data), "Sparse indices span/alignment invalid")
            indices = struct.unpack_from("<" + index_code * n, data, offset)
            need(all(i < count for i in indices) and all(x < y for x, y in zip(indices, indices[1:])),
                 "Sparse indices must be sorted, unique and in range")
            patches = sparse["values"]
            replacement = unpack(patches["bufferView"], patches.get("byteOffset", 0), n, width, packed=True)
            for i, row in zip(indices, replacement):
                values[i] = row
        return values

    def accessor_record(self, index):
        a = self.doc["accessors"][index]
        values = self.accessor(index)
        descriptor = {k: a[k] for k in ("componentType", "count", "type")}
        descriptor["normalized"] = a.get("normalized", False)
        digest = hashlib.sha256(canonical(descriptor))
        code = COMPONENTS[a["componentType"]][0]
        for row in values:
            digest.update(struct.pack("<" + code * len(row), *row))
        def semantic(value):
            if not a.get("normalized", False):
                return value
            scale = {5120: 127, 5121: 255, 5122: 32767, 5123: 65535}[a["componentType"]]
            return max(-1., value / scale)
        return {**descriptor, "sha256": digest.hexdigest(),
                "minimum": [semantic(min(row[j] for row in values)) for j in range(len(values[0]))],
                "maximum": [semantic(max(row[j] for row in values)) for j in range(len(values[0]))]}

    def binary_sha256(self):
        digest = hashlib.sha256()
        with self.path.open("rb") as stream:
            stream.seek(self.bin_offset)
            remaining = self.buffer_length
            while remaining:
                block = stream.read(min(1024 * 1024, remaining))
                need(bool(block), "Truncated binary buffer")
                digest.update(block)
                remaining -= len(block)
        return digest.hexdigest()

    def image_record(self, index):
        image = self.doc["images"][index]
        if "bufferView" in image:
            need("uri" not in image, "Image cannot have both URI and bufferView")
            data = self.view(image["bufferView"])
        else:
            uri = image.get("uri", "")
            need(uri.startswith("data:") and ";base64," in uri, "External image URI unsupported")
            data = base64.b64decode(uri.split(",", 1)[1], validate=True)
        result = {"index": index, "name": image.get("name"), "mime_type": image.get("mimeType"),
                  "byte_length": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                  "dimensions": None, "pixel_sha256": None}
        try:
            from PIL import Image
        except ImportError:
            result["pixel_check"] = "NOT_RUN_PILLOW_UNAVAILABLE"
        else:
            try:
                with Image.open(io.BytesIO(data)) as decoded:
                    decoded.load()
                    result.update(dimensions=list(decoded.size), pixel_sha256=hashlib.sha256(decoded.convert("RGBA").tobytes()).hexdigest(), pixel_check="DECODED")
            except (OSError, ValueError):
                result["pixel_check"] = "UNSUPPORTED_OR_INVALID_IMAGE_ENCODING"
        return result


def inspect_glb(path):
    glb = GLB(path)
    doc = glb.doc
    accessors = [glb.accessor_record(i) for i in range(len(doc.get("accessors", [])))]

    def attr(index):
        return reference(accessors, index, "attribute accessor")

    geometry, shading, bindings, bounds = [], [], [], []
    for mesh_id, mesh in enumerate(doc.get("meshes", [])):
        primitives, surface = [], []
        for primitive_id, primitive in enumerate(mesh.get("primitives", [])):
            attrs = primitive.get("attributes", {})
            need("POSITION" in attrs, "Mesh primitive has no POSITION")
            position = attr(attrs["POSITION"])
            need(position["type"] == "VEC3", "POSITION is not VEC3")
            count = position["count"]
            need(all(attr(i)["count"] == count for i in attrs.values()), "Vertex attribute counts differ")
            mode = primitive.get("mode", 4)
            need(type(mode) is int and 0 <= mode <= 6, "Invalid primitive mode")
            indices = None
            if "indices" in primitive:
                indices = attr(primitive["indices"])
                need(indices["type"] == "SCALAR" and indices["componentType"] in (5121, 5123, 5125)
                     and not indices["normalized"] and indices["maximum"][0] < count, "Invalid primitive indices")
            elements = indices["count"] if indices else count
            need(mode != 4 or elements % 3 == 0, "Triangle primitive element count is not divisible by three")
            targets = []
            for target in primitive.get("targets", []):
                need(all(attr(i)["count"] == count for i in target.values()), "Morph target vertex count differs")
                targets.append({key: attr(value) for key, value in sorted(target.items())})
            primitives.append({"mode": mode, "indices": indices,
                               "attributes": {key: attr(value) for key, value in sorted(attrs.items()) if key not in ("NORMAL", "TANGENT")},
                               "targets": targets, "extensions": primitive.get("extensions", {})})
            surface.append({key: attr(value) for key, value in sorted(attrs.items()) if key in ("NORMAL", "TANGENT")})
            bounds.append({"mesh": mesh_id, "primitive": primitive_id,
                           "minimum": position["minimum"], "maximum": position["maximum"],
                           "vertex_count": count, "element_count": elements,
                           "triangle_count": elements // 3 if mode == 4 else max(0, elements - 2) if mode in (5, 6) else 0})
            bindings.append({"mesh": mesh_id, "primitive": primitive_id, "material": primitive.get("material")})
            if "material" in primitive:
                reference(doc.get("materials", []), primitive["material"], "primitive material")
        geometry.append({"name": mesh.get("name"), "weights": mesh.get("weights", []),
                         "target_names": mesh.get("extras", {}).get("targetNames", []), "primitives": primitives})
        shading.append(surface)
    need(bool(bounds), "No mesh primitives to inspect")

    nodes = doc.get("nodes", [])
    for node in nodes:
        for child in node.get("children", []):
            reference(nodes, child, "node child")
        if "mesh" in node:
            reference(doc.get("meshes", []), node["mesh"], "node mesh")
        if "skin" in node:
            reference(doc.get("skins", []), node["skin"], "node skin")
    skins = []
    for skin in doc.get("skins", []):
        need(bool(skin.get("joints")), "Skin has no joints")
        for joint in skin["joints"]:
            reference(nodes, joint, "skin joint")
        if "skeleton" in skin:
            reference(nodes, skin["skeleton"], "skin skeleton")
        inverse = attr(skin["inverseBindMatrices"]) if "inverseBindMatrices" in skin else None
        need(inverse is None or (inverse["type"] == "MAT4" and inverse["componentType"] == 5126 and inverse["count"] == len(skin["joints"])), "Invalid inverse bind matrices")
        skins.append({**{k: v for k, v in skin.items() if k != "inverseBindMatrices"}, "inverse_bind_matrices": inverse})
    clips = []
    for animation in doc.get("animations", []):
        samplers = [{**{k: v for k, v in s.items() if k not in ("input", "output")},
                     "input": attr(s["input"]), "output": attr(s["output"])} for s in animation.get("samplers", [])]
        for channel in animation.get("channels", []):
            reference(samplers, channel["sampler"], "animation sampler")
            reference(nodes, channel["target"]["node"], "animation target node")
        clips.append({**{k: v for k, v in animation.items() if k != "samplers"}, "samplers": samplers})
    images = [glb.image_record(i) for i in range(len(doc.get("images", [])))]
    materials = {"materials": doc.get("materials", []), "textures": doc.get("textures", []),
                 "samplers": doc.get("samplers", []), "bindings": bindings}
    critical = {"geometry": fingerprint(geometry), "nodes_rest_hierarchy": fingerprint(nodes),
                "skins_inverse_bind": fingerprint(skins), "morph_clips": fingerprint(clips),
                "scene_roots": fingerprint({k: doc.get(k) for k in ("scene", "scenes")})}
    binary_sha = glb.binary_sha256()
    need(sha(glb.path) == glb.source_sha256, "GLB changed during inspection; freeze input before comparing")
    return {"path": str(glb.path), "sha256": glb.source_sha256, "byte_length": glb.size,
            "json_sha256": fingerprint(doc), "bin_sha256": binary_sha, "bin_byte_length": glb.bin_length,
            "mesh_count": len(geometry), "node_count": len(nodes), "skin_count": len(skins),
            "clips": [{"name": a.get("name"), "channels": len(a.get("channels", []))} for a in clips],
            "accessor_count": len(accessors), "accessors": accessors, "primitives": bounds,
            "bounds_space": "mesh-local rest POSITION data; no world or posed bounds claim",
            "critical_fingerprints": critical, "normal_tangent_sha256": fingerprint(shading),
            "materials_sha256": fingerprint(materials), "material_count": len(doc.get("materials", [])),
            "images": images, "extensions_required": doc.get("extensionsRequired", []),
            "extensions_used": doc.get("extensionsUsed", [])}


def compare_glbs(source, candidate):
    original, proposed = inspect_glb(source), inspect_glb(candidate)
    changed = [key for key, value in original["critical_fingerprints"].items()
               if value != proposed["critical_fingerprints"][key]]
    shading_changed = original["normal_tangent_sha256"] != proposed["normal_tangent_sha256"]
    images_changed = [(x["sha256"], x["mime_type"]) for x in original["images"]] != [(x["sha256"], x["mime_type"]) for x in proposed["images"]]
    warnings = ["Normal/tangent values changed; inspect shading and normal maps."] if shading_changed else []
    for label, record in (("source", original), ("candidate", proposed)):
        if any(x.get("pixel_check") != "DECODED" for x in record["images"]):
            warnings.append(label + ": at least one image has not been decoded; image validity/appearance unverified.")
    return {"schema": SCHEMA, "status": "FAIL" if changed else "PASS",
            "scope": SCOPE, "preservation_pass": not changed, "changed_contracts": changed,
            "normal_tangent_changed": shading_changed,
            "material_changed": original["materials_sha256"] != proposed["materials_sha256"],
            "image_changed": images_changed, "source": original, "candidate": proposed,
            "aesthetic_acceptance": "NOT_EVALUATED", "license_entitlement": "NOT_EVALUATED",
            "warnings": warnings,
            "engine_executed": False, "network_executed": False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    inspect = commands.add_parser("inspect", help="Validate and fingerprint the actual local GLB")
    inspect.add_argument("source", type=Path)
    compare = commands.add_parser("compare", help="Compare a retexture candidate with its untouched source")
    compare.add_argument("source", type=Path)
    compare.add_argument("candidate", type=Path)
    for sub in (inspect, compare):
        sub.add_argument("--report", type=Path, help="Write a new report; existing files are never overwritten")
    args = parser.parse_args(argv)
    try:
        if args.command == "compare":
            result = compare_glbs(args.source, args.candidate)
        else:
            result = {"schema": SCHEMA, "status": "PASS", "scope": SCOPE,
                      "inspection": inspect_glb(args.source), "aesthetic_acceptance": "NOT_EVALUATED",
                      "engine_executed": False, "network_executed": False}
    except (ValueError, OSError, KeyError, IndexError, TypeError, struct.error) as error:
        result = {"schema": SCHEMA, "status": "FAIL", "scope": SCOPE,
                  "preservation_pass": False, "error": str(error),
                  "aesthetic_acceptance": "NOT_EVALUATED", "engine_executed": False, "network_executed": False}
    result["verifier_sha256"] = sha(__file__)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        with args.report.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(result, stream, indent=2, allow_nan=False)
            stream.write("\n")
        print(json.dumps({"status": result["status"], "report": str(args.report.resolve())}))
    else:
        print(json.dumps(result, indent=2, allow_nan=False))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
