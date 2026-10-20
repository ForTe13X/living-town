"""Verify actual scanned glTF materials against a hero's recorded PBR inputs.

This checks exporter fidelity, not artistic approval or current-generator
freshness. Historical hero manifests retain their own recorded source pins.
No engine, network, model or inference is invoked. Pillow is needed for the
pixel acceptance gate; without it the report is explicitly incomplete.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
from pathlib import Path
import struct


def _need(condition, message):
    if not condition:
        raise ValueError(message)


def _sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def _close(actual, expected, label, tolerance=1e-5):
    _need(len(actual) == len(expected) and all(
        math.isfinite(float(a)) and abs(float(a) - float(b)) <= tolerance
        for a, b in zip(actual, expected)
    ), f"{label}: expected {expected}, exported {actual}")


class _GLB:
    """Read only each embedded image or accessor span when it is needed."""
    def __init__(self, path):
        self.path = Path(path)
        with self.path.open("rb") as stream:
            header = stream.read(12)
            _need(len(header) == 12, "Truncated GLB header")
            magic, version, size = struct.unpack("<4sII", header)
            _need((magic, version, size) == (b"glTF", 2, self.path.stat().st_size), "Invalid GLB header")
            length, kind = struct.unpack("<I4s", stream.read(8))
            _need(kind == b"JSON" and length % 4 == 0, "Invalid GLB JSON chunk")
            self.doc = json.loads(stream.read(length))
            self.bin_length, kind = struct.unpack("<I4s", stream.read(8))
            _need(kind == b"BIN\0" and stream.tell() + self.bin_length == size, "Invalid GLB BIN chunk")
            self.bin_offset = stream.tell()
        _need(set(self.doc.get("extensionsRequired", [])) <= {"KHR_texture_transform"},
              "Unsupported required extension in scanned export profile")
        buffers = self.doc.get("buffers", [])
        _need(len(buffers) == 1 and "uri" not in buffers[0], "Expected embedded GLB buffer")
        self.buffer_length = buffers[0]["byteLength"]
        _need(self.buffer_length <= self.bin_length <= self.buffer_length + 3, "Invalid GLB buffer size")

    def view(self, index):
        view = self.doc["bufferViews"][index]
        offset, length = view.get("byteOffset", 0), view["byteLength"]
        _need(view.get("buffer") == 0 and offset >= 0 and length > 0
              and offset + length <= self.buffer_length, "Invalid embedded bufferView")
        with self.path.open("rb") as stream:
            stream.seek(self.bin_offset + offset)
            data = stream.read(length)
        _need(len(data) == length, "Truncated embedded bufferView")
        return data

    def image(self, texture_info):
        texture = self.doc["textures"][texture_info["index"]]
        _need("source" in texture, "Expected core PNG/JPEG texture source")
        source = self.doc["images"][texture["source"]]
        _need("bufferView" in source and "uri" not in source, "Scan image is not embedded")
        data = self.view(source["bufferView"])
        return data, {"image_index": texture["source"], "mime_type": source.get("mimeType"),
                      "embedded_image_sha256": hashlib.sha256(data).hexdigest()}

    def accessor(self, index, kind, count):
        accessor = self.doc["accessors"][index]
        _need(accessor["type"] == kind and accessor["count"] == count
              and accessor["componentType"] == 5126 and "sparse" not in accessor,
              f"Invalid dense float {kind} vertex attribute")
        view = self.doc["bufferViews"][accessor["bufferView"]]
        components = {"VEC2": 2, "VEC3": 3, "VEC4": 4}[kind]
        stride = view.get("byteStride", components * 4)
        offset = accessor.get("byteOffset", 0)
        _need(stride >= components * 4 and offset >= 0 and count > 0
              and offset + (count - 1) * stride + components * 4 <= view["byteLength"],
              "Vertex attribute exceeds bufferView")
        data = self.view(accessor["bufferView"])
        values = [struct.unpack_from("<" + "f" * components, data, offset + row * stride)
                  for row in range(count)]
        _need(all(math.isfinite(value) for row in values for value in row), "Non-finite vertex attribute")
        return values


def _transform(info, expected_scale, label):
    transform = info.get("extensions", {}).get("KHR_texture_transform", {})
    _close(transform.get("scale", [1, 1]), expected_scale, label + " physical repeat scale")
    # Exported glTF UVs flip Blender V. For POINT scale with zero location,
    # Vg' = scaleV * Vg + (1 - scaleV), not a zero-offset transformation.
    _close(transform.get("offset", [0, 0]), [0, 1 - expected_scale[1]], label + " Blender V-flip offset")
    _close([transform.get("rotation", 0)], [0], label + " unexpected rotation")
    texcoord = transform.get("texCoord", info.get("texCoord", 0))
    _need(isinstance(texcoord, int) and texcoord >= 0, label + " invalid texCoord")
    return texcoord


def _pixels(data, source, role, dimensions):
    try:
        from PIL import Image, ImageChops
    except ImportError:
        return {"status": "INCOMPLETE_PILLOW_UNAVAILABLE"}
    with Image.open(io.BytesIO(data)) as embedded, Image.open(source) as original:
        embedded.load()
        original.load()
        _need(list(original.size) == dimensions and embedded.size == original.size,
              f"{role}: image resolution changed during export")
        if role == "roughness":
            _need(original.mode in ("L", "RGB", "RGBA"),
                  "Use a correctly normalized prepared 8-bit roughness source for pixel comparison")
            actual, expected = embedded.convert("RGB").getchannel("G"), original.convert("L")
        else:
            actual, expected = embedded.convert("RGB"), original.convert("RGB")
        extrema = ImageChops.difference(actual, expected).getextrema()
        maximum = max(pair[1] for pair in extrema) if isinstance(extrema[0], tuple) else extrema[1]
        _need(maximum <= 1, f"{role}: embedded image pixels differ from source by {maximum}/255")
        return {"status": "PASS", "dimensions": list(actual.size),
                "compared_channels": "ORM green vs source L" if role == "roughness" else "RGB",
                "maximum_absolute_channel_difference": maximum, "acceptance_tolerance": 1,
                "exact_pixels": maximum == 0,
                "source_pixel_sha256": hashlib.sha256(expected.tobytes()).hexdigest(),
                "embedded_pixel_sha256": hashlib.sha256(actual.tobytes()).hexdigest()}


def _material(glb, material_index, record):
    material = glb.doc["materials"][material_index]
    name = record["material"]
    expected_scale = [2 / float(value) for value in record["uv"]["repeat_metres"]]
    _close(record["uv"]["mapping_scale"], expected_scale, name + " reported UV basis")
    _need(record["uv"]["layer"] == "MetricUV" and record["uv"]["basis_metres_per_uv_unit"] == 2,
          name + " unexpected physical UV basis")
    pbr = material["pbrMetallicRoughness"]
    _close(pbr.get("baseColorFactor", [1, 1, 1, 1]), [*record["tint_linear_multiplier"], 1], name + " tint")
    _close([pbr.get("roughnessFactor", 1)], [record["roughness"]["effective_scale"]], name + " roughness factor")
    _close([material["normalTexture"].get("scale", 1)], [record["normal"]["strength"]], name + " normal strength")
    _close([pbr.get("metallicFactor", 1)], [0], name + " dielectric metallic factor")
    _need(material.get("alphaMode", "OPAQUE") == "OPAQUE", name + " scan unexpectedly became transparent")
    _need(record["context"]["applied"] is False and record["normal"]["reconstructed_from_rgb"] is False,
          name + " unexpected contextual bake or inferred normal route")
    infos = {"basecolor": pbr["baseColorTexture"], "roughness": pbr["metallicRoughnessTexture"],
             "normal": material["normalTexture"]}
    coordinates, images = {}, {}
    for role, info in infos.items():
        coordinates[role] = _transform(info, expected_scale, name + "/" + role)
        source_record = record["source_images"][role]
        source = Path(source_record["path"])
        _need(source.is_file() and _sha(source) == source_record["sha256"], name + "/" + role + " source SHA changed")
        _need(source_record["color_space"] == ("sRGB" if role == "basecolor" else "Non-Color"),
              name + "/" + role + " source color-space record changed")
        data, image_info = glb.image(info)
        image_info.update({"source_file_sha256": source_record["sha256"],
                           "pixel_comparison": _pixels(data, source, role, source_record["dimensions"])})
        images[role] = image_info
    _need(len(set(coordinates.values())) == 1, name + " PBR roles use different texture-coordinate sets")
    texcoord = next(iter(coordinates.values()))
    primitive_count = vertex_count = 0
    for mesh in glb.doc["meshes"]:
        for primitive in mesh["primitives"]:
            if primitive.get("material") != material_index:
                continue
            attrs = primitive["attributes"]
            _need({"POSITION", "NORMAL", "TANGENT", f"TEXCOORD_{texcoord}"}.issubset(attrs),
                  name + " lacks matching POSITION/NORMAL/TANGENT/TEXCOORD coverage")
            count = glb.doc["accessors"][attrs["POSITION"]]["count"]
            glb.accessor(attrs[f"TEXCOORD_{texcoord}"], "VEC2", count)
            normals = glb.accessor(attrs["NORMAL"], "VEC3", count)
            tangents = glb.accessor(attrs["TANGENT"], "VEC4", count)
            _need(all(sum(value * value for value in row) > .1 for row in normals), name + " zero normal")
            _need(all(sum(value * value for value in row[:3]) > .1 and abs(abs(row[3]) - 1) < .001
                      for row in tangents), name + " invalid tangent basis")
            primitive_count += 1
            vertex_count += count
    _need(primitive_count > 0, name + " exported material has no mesh consumers")
    complete = all(row["pixel_comparison"]["status"] == "PASS" for row in images.values())
    return {"status": "PASS" if complete else "INCOMPLETE_PIXELS_UNCHECKED", "material": name,
            "physical_mapping_scale": expected_scale, "texcoord": texcoord,
            "base_color_factor": pbr.get("baseColorFactor", [1, 1, 1, 1]),
            "roughness_factor": pbr.get("roughnessFactor", 1),
            "normal_strength": material["normalTexture"].get("scale", 1),
            "matched_primitives": primitive_count, "matched_vertices": vertex_count,
            "images": images}


def verify(hero):
    hero = Path(hero).resolve()
    manifest_path = hero / "hero_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    _need(manifest.get("schema") == "living_town.reconstructed_cafe_hero.v1", "Unknown hero manifest schema")
    records = {row["material"]: row for row in manifest["scanned_materials"]}
    _need(records, "Hero manifest contains no scanned materials")
    files = {key.replace("\\", "/"): row for key, row in manifest["files"].items()}
    results = {}
    for relative in ("cafe_hero.glb", "input/counter.glb"):
        path = hero / relative
        _need(_sha(path) == files[relative]["sha256"], relative + " GLB differs from its source-bound hero manifest")
        glb = _GLB(path)
        material_ids = {row["name"]: index for index, row in enumerate(glb.doc["materials"])}
        selected = records if relative == "cafe_hero.glb" else {
            name: row for name, row in records.items() if name in material_ids
        }
        _need(selected, relative + " contains no expected scanned materials")
        if relative == "input/counter.glb":
            _need(manifest["counter"]["materials"]["cabinet_oak"] in selected,
                  "Counter lost its scanned cabinet oak material")
        for name in selected:
            _need(name in material_ids, relative + " missing source scanned material " + name)
        material_results = [_material(glb, material_ids[name], row) for name, row in selected.items()]
        results[relative] = {"sha256": _sha(path), "materials": material_results,
                             "extensions_required": glb.doc.get("extensionsRequired", []),
                             "extensions_used": glb.doc.get("extensionsUsed", [])}
    complete = all(material["status"] == "PASS" for file in results.values() for material in file["materials"])
    return {"schema": "living_town.scanned_export_verification.v1",
            "status": "PASS" if complete else "INCOMPLETE_PIXELS_UNCHECKED",
            "hero_manifest_sha256": _sha(manifest_path),
            "verifier_source_sha256": _sha(Path(__file__)),
            "recorded_hero_source_modules": manifest["source_modules"],
            "current_hero_source_freshness_checked": False,
            "scope": "Actual embedded scanned image pixels, ORM green, physical UV transform with Blender V-flip, PBR factors and vertex tangent coverage; independent from artistic approval and current-source acceptance.",
            "exports": results, "engine_executed": False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hero", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        result = verify(args.hero)
    except (ValueError, OSError, KeyError, IndexError, struct.error) as error:
        result = {"schema": "living_town.scanned_export_verification.v1", "status": "FAIL", "error": str(error)}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open("x", encoding="utf-8") as stream:
        json.dump(result, stream, indent=2)
        stream.write("\n")
    print(json.dumps({key: result[key] for key in ("status", "error") if key in result}))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
