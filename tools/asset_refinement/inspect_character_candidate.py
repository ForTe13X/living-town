"""Read-only GLB intake facts for one explicitly named character appearance.

No normalization, repair, image generation, engine import or qualification.
Uses the repository's existing strict embedded/sparse/interleaved GLB reader.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import struct
import sys
import zlib

sys.dont_write_bytecode = True
for _root in (Path(__file__).resolve().parents[2], Path.cwd()):
    if (_root / "tools/town_upgrade/tripo_refinement.py").is_file():
        if str(_root) not in sys.path:
            sys.path.insert(0, str(_root))
        break
from tools.town_upgrade.tripo_refinement import GLB, sha
# This standalone CPU inspector needs small matrix operations, not a large
# BLAS thread pool. Defaults are process-local; explicit caller settings win.
_NUMPY_PRELOADED = "numpy" in sys.modules
for _thread_variable in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS"):
    os.environ.setdefault(_thread_variable, "1")
import numpy as np
from PIL import Image

SCHEMA = "living-town.character-candidate-inspection.v1"
ORIGINS = ("provider_original", "bridge_payload", "blender_reexport", "other_derivative")
LIMITS = {"nodes": 4096, "meshes": 1024, "primitives": 4096, "materials": 256,
          "images": 64, "skins": 128, "animations": 256, "accessors": 16384,
          "vertices_per_accessor": 2_000_000, "scalar_accessor_elements": 8_000_000,
          "triangles": 2_500_000, "decoded_scalars": 20_000_000,
          "image_pixels": 8192 * 8192, "image_bytes": 150 * 1024 * 1024,
          "image_strip_pixels": 512 * 1024,
          "report_bytes": 4 * 1024 * 1024}


def extension_declarations(path, size):
    """Bounded header metadata for refusals; the strict GLB reader validates data."""
    with path.open("rb") as stream:
        header = stream.read(20)
        need(len(header) == 20, "Truncated GLB header")
        magic, version, total, count, kind = struct.unpack("<4sIII4s", header)
        need((magic, version, total, kind) == (b"glTF", 2, size, b"JSON"), "Invalid GLB header")
        need(count <= 8 * 1024 * 1024 and count <= size-20, "JSON chunk exceeds intake bound")
        doc = json.loads(stream.read(count))
    need(isinstance(doc, dict), "GLB JSON is not an object")
    result = {}
    for key in ("extensionsUsed", "extensionsRequired"):
        values = doc.get(key, [])
        need(isinstance(values, list) and len(values) <= 256 and all(isinstance(v, str) and len(v) <= 128 for v in values), "Invalid extension declarations")
        result["used" if key == "extensionsUsed" else "required"] = values
    return result


def need(value, reason):
    if not value:
        raise ValueError(reason)


def index(items, value, label):
    need(type(value) is int and 0 <= value < len(items), "Invalid " + label)
    return items[value]


def vector(value, count, label):
    need(isinstance(value, list) and len(value) == count
         and all(type(x) in (int, float) and math.isfinite(x) for x in value), "Invalid " + label)
    return np.asarray(value, dtype=np.float64)


def node_matrix(node):
    if "matrix" in node:
        need(not any(k in node for k in ("translation", "rotation", "scale")), "Node has both matrix and TRS")
        m = vector(node["matrix"], 16, "node matrix").reshape(4, 4).T
        need(np.allclose(m[3], [0, 0, 0, 1], rtol=0, atol=1e-8), "Non-affine node matrix")
        return m
    t = vector(node.get("translation", [0, 0, 0]), 3, "node translation")
    s = vector(node.get("scale", [1, 1, 1]), 3, "node scale")
    x, y, z, w = vector(node.get("rotation", [0, 0, 0, 1]), 4, "node rotation")
    need(abs(x*x+y*y+z*z+w*w-1) <= 1e-4, "Non-unit node quaternion")
    r = np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                  [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                  [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])
    m = np.eye(4); m[:3, :3] = r @ np.diag(s); m[:3, 3] = t
    return m


def scene_graph(doc):
    nodes = doc.get("nodes", []); parents = [None] * len(nodes)
    local = [node_matrix(n) for n in nodes]
    for parent, n in enumerate(nodes):
        seen = set()
        for child in n.get("children", []):
            index(nodes, child, "child node")
            need(child not in seen and parents[child] is None, "Duplicate child or multiple node parents")
            seen.add(child); parents[child] = parent
    queue = [i for i, p in enumerate(parents) if p is None]; world = [None] * len(nodes)
    for i in queue:
        world[i] = local[i] if parents[i] is None else world[parents[i]] @ local[i]
        queue.extend(nodes[i].get("children", []))
    need(len(queue) == len(nodes), "Cyclic node graph")
    scenes = doc.get("scenes", [])
    need(bool(scenes), "No explicit scene; active-scene bounds unavailable")
    selected = doc.get("scene", 0); scene = index(scenes, selected, "active scene")
    roots = scene.get("nodes", [])
    need(len(roots) == len(set(roots)), "Duplicate active scene roots")
    active = []
    for root in roots:
        index(nodes, root, "scene root")
        need(parents[root] is None, "Scene root has a parent")
        active.append(root)
    for i in active:
        active.extend(nodes[i].get("children", []))
    return selected, active, world


class Decoded:
    def __init__(self, glb):
        self.glb = glb; self.cache = {}; self.scalars = 0

    def get(self, accessor_id):
        if accessor_id not in self.cache:
            a = index(self.glb.doc.get("accessors", []), accessor_id, "accessor")
            count_limit = LIMITS["scalar_accessor_elements"] if a.get("type") == "SCALAR" else LIMITS["vertices_per_accessor"]
            need(type(a.get("count")) is int and 0 < a["count"] <= count_limit, "Accessor count exceeds intake limit")
            width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}.get(a.get("type"))
            need(width is not None, "Unsupported accessor shape")
            self.scalars += a["count"] * width
            need(self.scalars <= LIMITS["decoded_scalars"], "Decoded scalar budget exceeded")
            need(type(a.get("normalized", False)) is bool, "Invalid accessor normalization flag")
            if (a["type"] == "SCALAR" and a.get("componentType") in (5121, 5123, 5125)
                    and not a.get("normalized", False) and "bufferView" in a and "sparse" not in a):
                # A two-million-triangle source has six million indices. Reuse the
                # strict reader's embedded view/span boundary without six million
                # transient Python tuples. Bytes remain immutable and referenced.
                view = index(self.glb.doc.get("bufferViews", []), a["bufferView"], "index bufferView")
                data = self.glb.view(a["bufferView"])
                dtype = np.dtype({5121: "u1", 5123: "<u2", 5125: "<u4"}[a["componentType"]])
                size = dtype.itemsize; offset = a.get("byteOffset", 0); stride = view.get("byteStride", size)
                need(type(offset) is int and offset >= 0 and type(stride) is int and stride >= size
                     and stride % size == 0 and offset % size == 0
                     and (view.get("byteOffset", 0)+offset) % size == 0
                     and offset+(a["count"]-1)*stride+size <= len(data), "Invalid dense scalar index span/alignment")
                raw = np.ndarray((a["count"], 1), dtype=dtype, buffer=data, offset=offset, strides=(stride, size))
            else:
                raw = np.asarray(self.glb.accessor(accessor_id))
            need(raw.shape == (a["count"], width), "Accessor shape mismatch")
            if a.get("normalized", False):
                scale = {5120: 127, 5121: 255, 5122: 32767, 5123: 65535}[a["componentType"]]
                raw = np.maximum(-1, raw.astype(np.float64) / scale)
            self.cache[accessor_id] = raw
        return self.cache[accessor_id]

    def require(self, accessor_id, kind, components=None, normalized=None):
        a = index(self.glb.doc.get("accessors", []), accessor_id, "accessor")
        need(a.get("type") == kind, "Wrong accessor shape, expected " + kind)
        need(components is None or a.get("componentType") in components, "Wrong accessor component type")
        need(normalized is None or a.get("normalized", False) is normalized, "Wrong accessor normalization")
        return self.get(accessor_id)


def triangles(elements, mode):
    if mode == 4:
        need(len(elements) % 3 == 0, "Triangle element count not divisible by three")
        return elements.reshape(-1, 3)
    if mode == 5:
        return np.column_stack((elements[:-2], elements[1:-1], elements[2:])) if len(elements) >= 3 else np.empty((0, 3), int)
    if mode == 6:
        return np.column_stack((np.full(max(0, len(elements)-2), elements[0]), elements[1:-1], elements[2:])) if len(elements) >= 3 else np.empty((0, 3), int)
    return np.empty((0, 3), int)


def image_header(data):
    """Read bounded PNG/JPEG header facts without allocating its pixel bitmap."""
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        need(len(data) >= 33, "Truncated PNG IHDR")
        length, kind = struct.unpack_from(">I4s", data, 8)
        need((length, kind) == (13, b"IHDR"), "Invalid PNG IHDR")
        need(zlib.crc32(data[12:29]) & 0xffffffff == struct.unpack_from(">I", data, 29)[0], "PNG IHDR CRC mismatch")
        width, height, depth, color, compression, filtering, interlace = struct.unpack_from(">IIBBBBB", data, 16)
        valid_depths = {0: (1, 2, 4, 8, 16), 2: (8, 16), 3: (1, 2, 4, 8), 4: (8, 16), 6: (8, 16)}
        need(0 < width <= 2147483647 and 0 < height <= 2147483647, "Invalid PNG dimensions")
        need(depth in valid_depths.get(color, ()) and compression == filtering == 0 and interlace in (0, 1), "Unsupported PNG IHDR encoding")
        return {"actual_encoding": "PNG", "dimensions": [width, height],
                "header_bit_depth": depth, "header_color_type": color}
    need(data.startswith(b"\xff\xd8"), "Unsupported image encoding; PNG/JPEG only")
    position = 2
    sof = {0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf}
    for _ in range(4096):
        need(position < len(data) and data[position] == 0xff, "Invalid JPEG marker")
        while position < len(data) and data[position] == 0xff:
            position += 1
        need(position < len(data), "Truncated JPEG marker")
        marker = data[position]; position += 1
        need(marker not in (0x00, 0xda, 0xd9), "JPEG dimensions not present before image data")
        if marker == 0x01 or 0xd0 <= marker <= 0xd8:
            continue
        need(position+2 <= len(data), "Truncated JPEG segment")
        size = struct.unpack_from(">H", data, position)[0]
        need(size >= 2 and position+size <= len(data), "Invalid JPEG segment span")
        if marker in sof:
            need(size >= 8, "Truncated JPEG frame")
            depth, height, width, components = struct.unpack_from(">BHHB", data, position+2)
            need(width > 0 and height > 0 and size == 8+3*components, "Invalid or deferred-dimension JPEG frame")
            return {"actual_encoding": "JPEG", "dimensions": [width, height],
                    "header_bit_depth": depth, "header_components": components}
        position += size
    raise ValueError("JPEG header marker budget exceeded")


def rgba_strip_facts(decoded):
    """Hash RGBA8 in row order; only a small diagnostic strip becomes bytes/NumPy."""
    width, height = decoded.size
    decoded.load()  # One native Pillow bitmap, never resized or saved.
    digest = hashlib.sha256(); histogram = np.zeros(256, dtype=np.uint64)
    budget = LIMITS["image_strip_pixels"]
    if width <= budget:
        rows = max(1, min(64, budget // width))
        regions = ((0, top, width, min(height, top+rows)) for top in range(0, height, rows))
    else:
        # Horizontal pieces must be a single row to preserve the full RGBA row order.
        regions = ((left, top, min(width, left+budget), top+1)
                   for top in range(height) for left in range(0, width, budget))
    for region in regions:
        with decoded.crop(region) as strip:
            with strip.convert("RGBA") as rgba:
                raw = rgba.tobytes()
        digest.update(raw)
        alpha = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 4)[:, 3]
        histogram += np.bincount(alpha, minlength=256).astype(np.uint64)
    present = np.flatnonzero(histogram)
    return digest.hexdigest(), {"minimum": int(present[0]), "maximum": int(present[-1]),
        "zero": int(histogram[0]), "full": int(histogram[255]),
        "partial": int(histogram[1:255].sum()),
        "histogram": {str(int(i)): int(histogram[i]) for i in present}}


def image_facts(glb, image_id):
    im = index(glb.doc.get("images", []), image_id, "image")
    if "bufferView" in im:
        need("uri" not in im, "Image has both embedded view and URI")
        data = glb.view(im["bufferView"])
    else:
        uri = im.get("uri", "")
        need(uri.startswith("data:") and ";base64," in uri, "External image unsupported")
        need(len(uri) <= LIMITS["image_bytes"] * 4//3 + 512, "Encoded image byte limit exceeded")
        data = base64.b64decode(uri.split(",", 1)[1], validate=True)
    need(len(data) <= LIMITS["image_bytes"], "Image byte limit exceeded")
    header = image_header(data)
    rec = {"index": image_id, "name": str(im.get("name", ""))[:128], "bytes": len(data),
           "sha256": hashlib.sha256(data).hexdigest(), **header,
           "declared_mime_type": im.get("mimeType"), "decoded_mode": None,
           "RGBA_pixel_sha256": None, "alpha": None,
           "RGBA_diagnostic_encoding": "Pillow RGBA8 without color management; original encoded bytes unchanged",
           "registration_UV_coverage_or_color_space_qualified": False}
    if header["dimensions"][0] * header["dimensions"][1] > LIMITS["image_pixels"]:
        rec.update(pixel_facts_status="DEFERRED_PIXEL_BUDGET",
            pixel_facts_reason="Dimensions exceed native per-image pixel decode budget; no resize or lowered source",
            encoding_validation="HEADER_ONLY; complete pixel stream not decoded/validated")
        return rec
    with Image.open(io.BytesIO(data)) as decoded:
        need(list(decoded.size) == header["dimensions"] and decoded.format == header["actual_encoding"], "Image decoder/header mismatch")
        rec["decoded_mode"] = decoded.mode
        rec["RGBA_pixel_sha256"], rec["alpha"] = rgba_strip_facts(decoded)
    rec.update(pixel_facts_status="DECODED_RGBA8_STRIPS", encoding_validation="FULL_PIXEL_DECODE")
    return rec


def material_facts(doc):
    result = []
    roles = [("baseColorTexture", "base_color", "RGBA; RGB=sRGB, alpha=linear"),
             ("metallicRoughnessTexture", "metallic_roughness", "G=roughness,B=metallic; linear"),
             ("normalTexture", "normal", "RGB=tangent-space XYZ; linear"),
             ("occlusionTexture", "occlusion", "R=occlusion; linear"),
             ("emissiveTexture", "emissive", "RGB=sRGB")]
    for mi, material in enumerate(doc.get("materials", [])):
        pbr = material.get("pbrMetallicRoughness", {})
        rec = {"index": mi, "name": str(material.get("name", ""))[:128],
               "alpha_mode": material.get("alphaMode", "OPAQUE"), "alpha_cutoff": material.get("alphaCutoff", .5),
               "double_sided": material.get("doubleSided", False),
               "base_color_factor": pbr.get("baseColorFactor", [1, 1, 1, 1]),
               "metallic_factor": pbr.get("metallicFactor", 1), "roughness_factor": pbr.get("roughnessFactor", 1),
               "extensions": sorted(material.get("extensions", {})), "texture_links": []}
        need(rec["alpha_mode"] in ("OPAQUE", "MASK", "BLEND"), "Invalid material alpha mode")
        vector(rec["base_color_factor"], 4, "base color factor")
        for key, role, channels in roles:
            info = pbr.get(key) if key in ("baseColorTexture", "metallicRoughnessTexture") else material.get(key)
            if info is None:
                continue
            texture = index(doc.get("textures", []), info.get("index"), "material texture")
            need(not texture.get("extensions"), "Texture source extension unsupported")
            source = texture.get("source"); index(doc.get("images", []), source, "texture image")
            transform = info.get("extensions", {}).get("KHR_texture_transform")
            need(set(info.get("extensions", {})) <= {"KHR_texture_transform"}, "Texture info extension unsupported")
            coord = info.get("texCoord", 0)
            if transform:
                coord = transform.get("texCoord", coord)
                vector(transform.get("offset", [0, 0]), 2, "texture offset")
                vector(transform.get("scale", [1, 1]), 2, "texture scale")
                need(type(transform.get("rotation", 0)) in (int, float), "Invalid texture rotation")
            need(type(coord) is int and 0 <= coord <= 7, "Invalid texture UV set")
            sampler = texture.get("sampler")
            sampler_record = index(doc.get("samplers", []), sampler, "texture sampler") if sampler is not None else {}
            sampler_record = {key: sampler_record[key] for key in ("magFilter", "minFilter", "wrapS", "wrapT") if key in sampler_record}
            transform_record = {key: transform[key] for key in ("offset", "rotation", "scale", "texCoord") if key in transform} if transform else None
            rec["texture_links"].append({"role": role, "texture": info["index"], "image": source,
                "texCoord": coord, "channels": channels, "texture_transform": transform_record,
                "sampler": sampler_record, "normal_scale": info.get("scale") if role == "normal" else None,
                "occlusion_strength": info.get("strength") if role == "occlusion" else None})
        result.append(rec)
    return result


def skeleton_facts(doc, decoded):
    records = []; matrices = []
    for si, skin in enumerate(doc.get("skins", [])):
        joints = skin.get("joints", [])
        need(bool(joints) and len(joints) <= 512 and len(joints) == len(set(joints)), "Invalid or over-limit skin joints")
        for j in joints:
            index(doc.get("nodes", []), j, "skin joint node")
        if "skeleton" in skin:
            index(doc.get("nodes", []), skin["skeleton"], "skin skeleton node")
        if "inverseBindMatrices" in skin:
            ibm = decoded.require(skin["inverseBindMatrices"], "MAT4", (5126,), False)
            need(len(ibm) == len(joints), "Inverse-bind count differs from skin joints")
            ibm = ibm.reshape(-1, 4, 4).transpose(0, 2, 1)
        else:
            ibm = np.tile(np.eye(4), (len(joints), 1, 1))
        need(np.all(np.abs(np.linalg.det(ibm)) > 1e-14), "Singular inverse-bind matrix")
        matrices.append(ibm)
        records.append({"index": si, "name": str(skin.get("name", ""))[:128], "joint_count": len(joints),
                        "joints": [{"node": j, "name": str(doc["nodes"][j].get("name", ""))[:128]} for j in joints],
                        "inverse_bind_matrices_supplied": "inverseBindMatrices" in skin,
                        "mesh_instances": [], "maximum_influences": 0, "maximum_weight_sum_error": 0.,
                        "rig_deformation_qualified": False})
    return records, matrices


def influence_data(attrs, count, skin, decoded):
    joint_sets = sorted(k for k in attrs if k.startswith("JOINTS_"))
    weight_sets = sorted(k for k in attrs if k.startswith("WEIGHTS_"))
    need(bool(joint_sets) and {k[7:] for k in joint_sets} == {k[8:] for k in weight_sets}, "Missing or unmatched skin influence sets")
    need(len(joint_sets) <= 8, "Too many influence sets")
    joints, weights = [], []
    for key in joint_sets:
        js = decoded.require(attrs[key], "VEC4", (5121, 5123), False)
        wi = attrs["WEIGHTS_" + key[7:]]
        wa = decoded.glb.doc["accessors"][wi]
        need(wa["componentType"] == 5126 or (wa["componentType"] in (5121, 5123) and wa.get("normalized", False)), "Invalid weight component encoding")
        ws = decoded.require(wi, "VEC4", (5121, 5123, 5126))
        need(len(js) == count and len(ws) == count, "Skin attribute count mismatch")
        need(np.all(js >= 0) and np.all(js < len(skin["joints"])), "Joint attribute outside skin")
        need(np.all(ws >= 0), "Negative skin weight")
        joints.append(js.astype(np.int64)); weights.append(ws.astype(np.float64))
    joints = np.column_stack(joints); weights = np.column_stack(weights)
    error = float(np.abs(weights.sum(axis=1)-1).max())
    need(error <= 1e-4, "Skin weights do not sum to one within1e-4")
    return joints, weights, int((weights > 0).sum(axis=1).max()), error


def animation_facts(doc, decoded):
    records = []
    for ai, animation in enumerate(doc.get("animations", [])):
        intervals = []; sampler_intervals = []; samplers = []
        for sampler in animation.get("samplers", []):
            times = decoded.require(sampler["input"], "SCALAR", (5126,), False).ravel()
            need(times[0] >= 0 and np.all(np.diff(times) > 0), "Animation times not strictly increasing/nonnegative")
            interpolation = sampler.get("interpolation", "LINEAR")
            need(interpolation in ("LINEAR", "STEP", "CUBICSPLINE"), "Unsupported animation interpolation")
            output = decoded.get(sampler["output"])
            sampler_intervals.append((float(times[0]), float(times[-1])))
            samplers.append((len(times), interpolation, output, doc["accessors"][sampler["output"]]))
        channels = []
        for channel in animation.get("channels", []):
            frames, interpolation, output, accessor = index(samplers, channel.get("sampler"), "animation sampler")
            intervals.append(index(sampler_intervals, channel.get("sampler"), "animation sampler interval"))
            target = channel["target"]; node = index(doc.get("nodes", []), target.get("node"), "animation node")
            path = target.get("path"); need(path in ("translation", "rotation", "scale", "weights"), "Unsupported animation path")
            need(path == "weights" or "matrix" not in node, "TRS animation targets a matrix node")
            multiplier = 3 if interpolation == "CUBICSPLINE" else 1
            if path == "weights":
                mesh = index(doc.get("meshes", []), node.get("mesh"), "animated morph mesh")
                counts = {len(p.get("targets", [])) for p in mesh.get("primitives", [])}
                need(len(counts) == 1 and next(iter(counts)) > 0, "Invalid animated morph target count")
                need(accessor["type"] == "SCALAR" and len(output) == frames*multiplier*next(iter(counts)), "Morph animation output count mismatch")
            else:
                need(accessor["type"] == ("VEC4" if path == "rotation" else "VEC3") and len(output) == frames*multiplier, "Animation output count/shape mismatch")
            channels.append({"node": target["node"], "path": path, "interpolation": interpolation, "sample_count": frames})
        need(bool(intervals) and bool(channels), "Empty animation")
        start = min(x[0] for x in intervals); end = max(x[1] for x in intervals)
        records.append({"index": ai, "name": str(animation.get("name", ""))[:128],
                        "start_seconds": start, "end_seconds": end, "duration_seconds": end-start,
                        "channels": channels, "motion_action_contact_qualified": False})
    return records


def _inspect(glb, result):
    doc = glb.doc
    for name in ("nodes", "meshes", "materials", "images", "skins", "animations", "accessors"):
        need(len(doc.get(name, [])) <= LIMITS[name], name + " exceeds intake limit")
    result["extensions"] = {"used": doc.get("extensionsUsed", []), "required": doc.get("extensionsRequired", []),
        "optional_material_behavior_not_evaluated": sorted({e for m in doc.get("materials", []) for e in m.get("extensions", {})} - {"KHR_materials_unlit"})}
    scene, active, world = scene_graph(doc)
    decoded = Decoded(glb)
    materials = material_facts(doc); result["materials"] = materials
    result["images"] = [image_facts(glb, i) for i in range(len(doc.get("images", [])))]
    deferred = [i["index"] for i in result["images"] if i["pixel_facts_status"] == "DEFERRED_PIXEL_BUDGET"]
    if deferred:
        result["warnings"].append("Pixel-derived RGBA/alpha facts deferred by budget for images " + str(deferred) + "; encoded bytes/dimensions preserved without resize.")
    skeletons, inverse = skeleton_facts(doc, decoded); result["skeletons"] = skeletons
    geometry = {"mesh_count": len(doc.get("meshes", [])), "primitive_count": 0, "vertex_count": 0,
                "triangle_count": 0, "degenerate_triangle_count": 0, "near_zero_area_triangle_count": 0,
                "count_scope": "declared mesh primitives counted once; active instances counted separately", "primitives": []}
    primitive_data = {}
    for mi, mesh in enumerate(doc.get("meshes", [])):
        need(bool(mesh.get("primitives")), "Mesh has no primitives")
        for pi, primitive in enumerate(mesh["primitives"]):
            geometry["primitive_count"] += 1
            need(geometry["primitive_count"] <= LIMITS["primitives"], "Primitive limit exceeded")
            attrs = primitive.get("attributes", {}); need("POSITION" in attrs, "Primitive lacks POSITION")
            pos = decoded.require(attrs["POSITION"], "VEC3").astype(np.float64)
            count = len(pos); attributes = {}
            for name, accessor_id in attrs.items():
                data = decoded.get(accessor_id); a = doc["accessors"][accessor_id]
                need(len(data) == count, "Primitive attribute count mismatch")
                attributes[name] = {"count": count, "type": a["type"], "component_type": a["componentType"], "normalized": a.get("normalized", False)}
                if name in ("NORMAL", "TANGENT"):
                    need(a["type"] == ("VEC3" if name == "NORMAL" else "VEC4"), "Invalid normal/tangent shape")
                    attributes[name]["zero_direction_count"] = int((np.linalg.norm(data[:, :3], axis=1) == 0).sum())
                if name.startswith("TEXCOORD_"):
                    need(a["type"] == "VEC2", "Invalid UV accessor shape")
            if "indices" in primitive:
                elements = decoded.require(primitive["indices"], "SCALAR", (5121, 5123, 5125), False).ravel().astype(np.int64)
                need(np.all(elements >= 0) and np.all(elements < count), "Primitive index outside vertices")
            else:
                elements = np.arange(count)
            mode = primitive.get("mode", 4); need(type(mode) is int and 0 <= mode <= 6, "Invalid primitive mode")
            tri = triangles(elements, mode)
            need(geometry["triangle_count"]+len(tri) <= LIMITS["triangles"], "Triangle budget exceeded")
            cross = np.cross(pos[tri[:, 1]]-pos[tri[:, 0]], pos[tri[:, 2]]-pos[tri[:, 0]])
            area2 = np.einsum("ij,ij->i", cross, cross)
            degenerate = int((area2 == 0).sum()); near = int(((area2 > 0) & (area2 <= 1e-24)).sum())
            targets = []
            for target in primitive.get("targets", []):
                for semantic, accessor_id in target.items():
                    need(semantic in ("POSITION", "NORMAL", "TANGENT"), "Unsupported morph semantic")
                    need(len(decoded.require(accessor_id, "VEC3", (5126,), False)) == count, "Morph count mismatch")
                targets.append(target.get("POSITION"))
            material = primitive.get("material")
            if material is not None:
                for link in index(materials, material, "primitive material")["texture_links"]:
                    need("TEXCOORD_"+str(link["texCoord"]) in attrs, "Referenced material UV set absent")
            primitive_data[(mi, pi)] = (pos, np.unique(elements), attrs, targets)
            geometry["vertex_count"] += count; geometry["triangle_count"] += len(tri)
            geometry["degenerate_triangle_count"] += degenerate; geometry["near_zero_area_triangle_count"] += near
            geometry["primitives"].append({"mesh": mi, "primitive": pi, "mode": mode, "material": material,
                "vertex_count": count, "referenced_vertex_count": len(np.unique(elements)), "element_count": len(elements),
                "triangle_count": len(tri), "degenerate_triangle_count": degenerate,
                "near_zero_area_triangle_count": near, "attributes": attributes, "morph_target_count": len(targets)})
    result["geometry"] = geometry
    geometry["active_instance_count"] = 0; geometry["active_triangle_count"] = 0
    instances = []; minima = []; maxima = []
    for ni, node in enumerate(doc.get("nodes", [])):
        if "mesh" not in node:
            need("skin" not in node, "Skin attached to a node without mesh"); continue
        mi = node["mesh"]; mesh = index(doc.get("meshes", []), mi, "node mesh")
        si = node.get("skin"); skin = index(doc.get("skins", []), si, "node skin") if si is not None else None
        if skin is not None:
            skeletons[si]["mesh_instances"].append(ni)
            bone_matrices = np.stack([world[j] for j in skin["joints"]]) @ inverse[si]
        lo = []; hi = []
        for pi, primitive in enumerate(mesh["primitives"]):
            pos, used, attrs, targets = primitive_data[(mi, pi)]
            weights = node.get("weights", mesh.get("weights", [0.] * len(targets)))
            morph = vector(weights, len(targets), "default morph weights")
            local = pos.copy()
            for weight, target in zip(morph, targets):
                if target is not None and weight != 0:
                    local += weight * decoded.get(target)
            homogeneous = np.column_stack((local, np.ones(len(local))))
            if skin is not None:
                joints, influence, maximum, error = influence_data(attrs, len(local), skin, decoded)
                skeletons[si]["maximum_influences"] = max(skeletons[si]["maximum_influences"], maximum)
                skeletons[si]["maximum_weight_sum_error"] = max(skeletons[si]["maximum_weight_sum_error"], error)
                transformed = np.zeros((len(local), 4))
                for column in range(joints.shape[1]):
                    transformed += np.einsum("nij,nj->ni", bone_matrices[joints[:, column]], homogeneous) * influence[:, column, None]
            else:
                need(not any(k.startswith(("JOINTS_", "WEIGHTS_")) for k in attrs), "Unbound skin attributes on mesh instance")
                transformed = homogeneous @ world[ni].T
            need(np.all(np.isfinite(transformed)), "Nonfinite evaluated rest position")
            if ni in active and len(used):
                lo.append(transformed[used, :3].min(axis=0)); hi.append(transformed[used, :3].max(axis=0))
        if ni in active and lo:
            minimum = np.min(lo, axis=0); maximum = np.max(hi, axis=0)
            minima.append(minimum); maxima.append(maximum)
            instances.append({"node": ni, "mesh": mi, "skin": si, "minimum": minimum.tolist(), "maximum": maximum.tolist(), "skin_rest_evaluated": skin is not None})
            geometry["active_instance_count"] += 1
            geometry["active_triangle_count"] += sum(p["triangle_count"] for p in geometry["primitives"] if p["mesh"] == mi)
    need(bool(minima), "Active scene has no referenced renderable positions")
    minimum = np.min(minima, axis=0); maximum = np.max(maxima, axis=0)
    result["active_scene_rest_bounds"] = {"scene": scene, "scene_was_explicit": "scene" in doc,
        "minimum": minimum.tolist(), "maximum": maximum.tolist(), "extent": (maximum-minimum).tolist(),
        "space": "glTF active-scene node-rest/default-morph coordinates; skin rest via joint-world*inverse-bind",
        "nominal_units": "glTF meters; actual physical scale unknown", "physical_scale_qualified": False,
        "posed_or_animation_bounds_qualified": False, "animation_evaluated": False, "instances": instances}
    result["animations"] = animation_facts(doc, decoded)
    result["decode_scalar_count"] = decoded.scalars
    result["decoded_accessor_count"] = len(decoded.cache)
    result["declared_accessor_count"] = len(doc.get("accessors", []))
    result["unused_accessor_data_validated"] = False


def inspect_candidate(path, appearance_family, source_origin="provider_original", provider=None, task_id=None):
    """Always return a bounded facts/refusal receipt; never change the input."""
    path = Path(path).resolve()
    result = {"schema": SCHEMA, "status": "REFUSED", "appearance_family": appearance_family,
        "source": {"path": str(path), "sha256": None, "bytes": None, "source_origin": source_origin,
                   "origin_is_caller_declaration_not_authenticated": True, "provider": provider, "task_id": task_id},
        "refusals": [], "warnings": [], "qualification": {"art": False, "rig": False, "actions": False,
        "engine": False, "performance": False, "physical_scale": False, "license_rights": False},
        "input_rewritten_normalized_or_maps_generated": False, "engine_GPU_UI_network_or_spend": False,
        "CPU_resource_environment": {"numpy_preloaded": _NUMPY_PRELOADED,
            **{key: int(os.environ[key]) if os.environ[key].isdigit() else "caller_nonnumeric_setting"
               for key in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS")}},
        "resource_limits": LIMITS, "materials": [], "skeletons": [], "animations": []}
    before = None
    try:
        stat = path.stat(); result["source"]["bytes"] = stat.st_size
        need(stat.st_size <= 150 * 1024 * 1024, "GLB exceeds150MiB intake limit; hash not computed")
        before = (stat.st_size, stat.st_mtime_ns, sha(path))
        result["source"].update(bytes=before[0], sha256=before[2])
        need(isinstance(appearance_family, str) and re.fullmatch(r"[a-z][a-z0-9_-]{1,63}", appearance_family), "Explicit safe appearance-family ID required")
        need(source_origin in ORIGINS, "Unsupported source-origin declaration")
        for value, label in ((provider, "provider"), (task_id, "task ID")):
            need(value is None or (isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 .:_-]{0,127}", value)), "Invalid bounded " + label)
        result["extensions"] = extension_declarations(path, before[0])
        glb = GLB(path)
        need(glb.source_sha256 == before[2], "Input changed before decoder opened it")
        _inspect(glb, result)
        result["status"] = "FACTS_ONLY"
        result["warnings"].append("Static/rest bounds do not establish motion/deformation, contact, real-world stature or artistic quality.")
        if result.get("extensions", {}).get("optional_material_behavior_not_evaluated"):
            result["warnings"].append("Optional material-extension shader behavior is not evaluated; core PBR links only.")
    except (OSError, ValueError, KeyError, IndexError, TypeError, AttributeError, struct.error,
            OverflowError, RecursionError, Image.DecompressionBombError, np.linalg.LinAlgError) as error:
        result["status"] = "REFUSED"; result["refusals"].append(type(error).__name__ + ": " + str(error)[:512])
        if "unsupported" in str(error).lower():
            result["unsupported_feature_refusal"] = str(error)[:512]
    if before is not None:
        try:
            after_stat = path.stat(); after = (after_stat.st_size, after_stat.st_mtime_ns, sha(path))
            result["source"]["bytes_size_mtime_hash_unchanged"] = after == before
            if after != before:
                result["status"] = "REFUSED"; result["refusals"].append("Input changed during inspection")
        except OSError:
            result["status"] = "REFUSED"; result["refusals"].append("Input became unavailable during inspection")
    if len(json.dumps(result, allow_nan=False).encode()) > LIMITS["report_bytes"]:
        result = {k: v for k, v in result.items() if k in ("schema", "source", "qualification", "appearance_family")}
        result.update(status="REFUSED", refusals=["Report size budget exceeded"], facts_omitted=True)
    return result


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("source", type=Path); p.add_argument("--appearance-family", required=True)
    p.add_argument("--source-origin", choices=ORIGINS, default="provider_original")
    p.add_argument("--provider"); p.add_argument("--task-id"); p.add_argument("--report", required=True, type=Path)
    args = p.parse_args(argv)
    if args.source.resolve() == args.report.resolve():
        p.error("Report cannot be the input")
    if args.report.exists():
        p.error("Refusing to overwrite an existing report")
    result = inspect_candidate(args.source, args.appearance_family, args.source_origin, args.provider, args.task_id)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(result, stream, indent=2, allow_nan=False); stream.write("\n")
    print(json.dumps({"status": result["status"], "report": str(args.report.resolve()), "source_sha256": result["source"]["sha256"], "refusals": result["refusals"]}))
    return 0 if result["status"] == "FACTS_ONLY" else 1


if __name__ == "__main__":
    raise SystemExit(main())
