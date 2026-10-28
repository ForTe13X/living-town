"""Append one PNG to an embedded GLB and repoint its sole metallic-roughness image.

No remeshing, glTF re-export, image conversion, bake, rendering or UV inference.
Original BIN bytes remain a prefix. Only the selected image bufferView/mimeType,
one appended bufferView and the buffer byteLength change in JSON. Aliased image
consumers are refused. Caller supplies both input SHA-256 identities; output must
be new. This checks container/PNG structure, not texture meaning or art quality.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import struct
import zlib

MAX_GLB_BYTES = 256 * 1024**2
MAX_PNG_BYTES = 128 * 1024**2
MAX_JSON_BYTES = 8 * 1024**2


def _need(condition, message):
    if not condition:
        raise ValueError(message)


def _sha(data):
    return hashlib.sha256(data).hexdigest()


def _bound_input(path, expected_sha256, limit):
    _need(re.fullmatch(r"[a-f0-9]{64}", expected_sha256 or "") is not None,
          "Expected input SHA-256 must be 64 lowercase hexadecimal characters")
    before = path.stat()
    _need(0 < before.st_size <= limit, "Input size exceeds bound or is empty")
    data = path.read_bytes()
    after = path.stat()
    _need((before.st_size, before.st_mtime_ns) == (after.st_size, after.st_mtime_ns),
          "Input changed during read")
    _need(_sha(data) == expected_sha256, "Input SHA-256 mismatch")
    return data, (after.st_size, after.st_mtime_ns)


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        _need(key not in result, "Duplicate JSON object key")
        result[key] = value
    return result


def _bad_number(value):
    raise ValueError("Non-finite JSON number")


def _parse_glb(raw):
    _need(len(raw) >= 28, "Truncated GLB")
    magic, version, total = struct.unpack_from("<III", raw)
    _need((magic, version, total) == (0x46546C67, 2, len(raw)), "Invalid GLB header/length")
    chunks = []
    offset = 12
    while offset < len(raw):
        _need(offset + 8 <= len(raw), "Truncated GLB chunk header")
        length, kind = struct.unpack_from("<II", raw, offset)
        offset += 8
        _need(length % 4 == 0 and length <= len(raw) - offset, "Invalid GLB chunk extent/alignment")
        chunks.append((kind, raw[offset:offset + length]))
        offset += length
    _need(len(chunks) == 2 and chunks[0][0] == 0x4E4F534A and chunks[1][0] == 0x004E4942,
          "Exactly one JSON chunk followed by one BIN chunk is required")
    _need(len(chunks[0][1]) <= MAX_JSON_BYTES, "GLB JSON exceeds bound")
    doc = json.loads(chunks[0][1].decode().rstrip(" \0"),
                     object_pairs_hook=_unique_object, parse_constant=_bad_number)
    binary = chunks[1][1]
    _need(isinstance(doc, dict) and isinstance(doc.get("asset"), dict) and doc["asset"].get("version") == "2.0", "glTF2 asset required")
    buffers = doc.get("buffers", [])
    _need(isinstance(buffers, list) and len(buffers) == 1 and isinstance(buffers[0], dict) and "uri" not in buffers[0], "One embedded buffer required")
    declared = buffers[0].get("byteLength")
    _need(type(declared) is int and 0 <= len(binary) - declared <= 3, "Invalid embedded buffer length")
    views = doc.get("bufferViews", [])
    _need(isinstance(views, list), "bufferViews must be an array")
    for view in views:
        _need(isinstance(view, dict), "bufferView must be an object")
        start, length = view.get("byteOffset", 0), view.get("byteLength")
        _need(view.get("buffer", 0) == 0 and type(start) is int and type(length) is int
              and start >= 0 and length >= 0 and start + length <= declared,
              "bufferView outside embedded buffer")
    return doc, binary


def _validate_png(raw):
    _need(raw[:8] == b"\x89PNG\r\n\x1a\n", "PNG signature required")
    offset, kinds, size = 8, [], None
    while offset < len(raw):
        _need(offset + 12 <= len(raw), "Truncated PNG chunk")
        length = struct.unpack_from(">I", raw, offset)[0]
        kind = raw[offset + 4:offset + 8]
        end = offset + 12 + length
        _need(end <= len(raw), "PNG chunk outside file")
        payload = raw[offset + 8:offset + 8 + length]
        crc = struct.unpack_from(">I", raw, offset + 8 + length)[0]
        _need(zlib.crc32(kind + payload) & 0xFFFFFFFF == crc, "PNG CRC mismatch")
        if not kinds:
            _need(kind == b"IHDR" and length == 13, "PNG IHDR must be first")
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", payload)
            _need(0 < width <= 8192 and 0 < height <= 8192 and depth == 8 and color in (2, 6)
                  and compression == filtering == 0 and interlace in (0, 1),
                  "8-bit RGB/RGBA PNG within8192 square required")
            size = (width, height)
        else:
            _need(kind != b"IHDR", "Duplicate PNG IHDR")
        kinds.append(kind)
        offset = end
        if kind == b"IEND":
            _need(length == 0 and offset == len(raw), "Invalid PNG IEND/trailing bytes")
            break
    _need(kinds and kinds[-1] == b"IEND" and b"IDAT" in kinds, "PNG IDAT/IEND missing")
    return size


def _target_image(doc, material_index):
    _need(type(material_index) is int and 0 <= material_index < len(doc.get("materials", [])),
          "Material index outside source")
    material = doc["materials"][material_index]
    _need(isinstance(material, dict), "Material must be an object")
    info = material.get("pbrMetallicRoughness", {}).get("metallicRoughnessTexture", {})
    texture_index = info.get("index")
    textures, images = doc.get("textures", []), doc.get("images", [])
    _need(type(texture_index) is int and 0 <= texture_index < len(textures), "Existing MR texture required")
    texture = textures[texture_index]
    _need(isinstance(texture, dict), "Texture must be an object")
    _need(not texture.get("extensions"), "Texture source extensions are outside this operation")
    image_index = texture.get("source")
    _need(type(image_index) is int and 0 <= image_index < len(images), "Existing MR image required")
    image = images[image_index]
    _need(isinstance(image, dict), "Image must be an object")
    _need("uri" not in image and type(image.get("bufferView")) is int
          and 0 <= image["bufferView"] < len(doc["bufferViews"]), "MR image must already be embedded")
    _need(image.get("mimeType") in ("image/jpeg", "image/png"), "Unsupported existing MR image type")
    # Repointing an image would affect every alias. Refuse any second consumer.
    consumers = []
    def walk(value, path):
        if isinstance(value, dict):
            for key, child in value.items():
                if key.lower().endswith("texture") and isinstance(child, dict) and type(child.get("index")) is int:
                    ti = child["index"]
                    _need(0 <= ti < len(textures), "Invalid material texture reference")
                    if textures[ti].get("source") == image_index:
                        consumers.append(path + (key,))
                walk(child, path + (key,))
        elif isinstance(value, list):
            for index, child in enumerate(value):
                walk(child, path + (index,))
    walk(doc["materials"], ())
    _need(consumers == [(material_index, "pbrMetallicRoughness", "metallicRoughnessTexture")],
          "MR image is aliased by another material texture consumer")
    return image_index


def append_metallic_roughness_png(source_glb, orm_png, output_glb, *,
                                  expected_source_sha256, expected_png_sha256, material_index=0):
    """Write one new append-only derivative; return byte-preservation facts, not acceptance."""
    source, png, output = map(Path, (source_glb, orm_png, output_glb))
    _need(output.resolve() not in (source.resolve(), png.resolve()), "Output aliases an input")
    _need(not output.exists(), "Output already exists")
    raw, source_state = _bound_input(source, expected_source_sha256, MAX_GLB_BYTES)
    raw_png, png_state = _bound_input(png, expected_png_sha256, MAX_PNG_BYTES)
    dimensions = _validate_png(raw_png)
    doc, binary = _parse_glb(raw)
    image_index = _target_image(doc, material_index)
    original = copy.deepcopy(doc)
    # EXACT construction/serialization used by the actual native-bake v002 worker.
    start = len(binary)
    new_binary = binary + raw_png
    new_binary += b"\0" * ((-len(new_binary)) % 4)
    new_view = len(doc["bufferViews"])
    doc["bufferViews"].append({"buffer": 0, "byteOffset": start, "byteLength": len(raw_png)})
    doc["images"][image_index]["bufferView"] = new_view
    doc["images"][image_index]["mimeType"] = "image/png"
    doc["buffers"][0]["byteLength"] = len(new_binary)
    proof = copy.deepcopy(doc)
    proof["bufferViews"].pop()
    proof["images"][image_index] = copy.deepcopy(original["images"][image_index])
    proof["buffers"][0] = copy.deepcopy(original["buffers"][0])
    _need(proof == original and new_binary[:len(binary)] == binary, "Internal preservation failure")
    encoded = json.dumps(doc, separators=(",", ":")).encode()
    encoded += b" " * ((-len(encoded)) % 4)
    result = (struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(encoded) + 8 + len(new_binary))
              + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
              + struct.pack("<II", len(new_binary), 0x004E4942) + new_binary)
    for path, state, digest in ((source, source_state, expected_source_sha256), (png, png_state, expected_png_sha256)):
        _need((path.stat().st_size, path.stat().st_mtime_ns) == state and _sha(path.read_bytes()) == digest,
              "Input changed before output creation")
    # Exclusive creation also closes the exists()/open() race. Never create parent directories.
    with output.open("xb") as stream:
        stream.write(result)
    return {"status": "APPENDED_EXISTING_METALLIC_ROUGHNESS_IMAGE", "source_sha256": expected_source_sha256,
            "PNG_sha256": expected_png_sha256, "PNG_dimensions": list(dimensions),
            "output": str(output), "bytes": len(result), "sha256": _sha(result),
            "material_index": material_index, "image_index": image_index,
            "original_BIN_prefix_bytes": len(binary), "original_BIN_prefix_sha256": _sha(binary),
            "original_BIN_prefix_preserved": True, "other_JSON_fields_unchanged": True,
            "image_semantics_UV_registration_art_rig_engine_or_performance_qualified": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-glb", required=True, type=Path)
    parser.add_argument("--orm-png", required=True, type=Path)
    parser.add_argument("--output-glb", required=True, type=Path)
    parser.add_argument("--expected-source-sha256", required=True)
    parser.add_argument("--expected-png-sha256", required=True)
    parser.add_argument("--material-index", type=int, default=0)
    args = parser.parse_args()
    try:
        result = append_metallic_roughness_png(args.source_glb, args.orm_png, args.output_glb,
                    expected_source_sha256=args.expected_source_sha256,
                    expected_png_sha256=args.expected_png_sha256, material_index=args.material_index)
    except (ValueError, OSError, KeyError, TypeError, UnicodeError, struct.error) as error:
        parser.exit(1, "Refused: " + str(error) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
