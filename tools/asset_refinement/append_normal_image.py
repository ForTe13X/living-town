"""Append a reviewed normal PNG to a GLB without re-exporting the source asset.

Only one new bufferView/image/texture, an optional sampler, buffer byteLength and
the selected normalTexture binding may change. Old BIN bytes (including padding)
remain a prefix. This is a bounded container writer, not a bake or art validator.
It performs no image conversion, normalization, green flip or engine invocation.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import zlib

MAX_GLB_BYTES = 256 * 1024**2
MAX_PNG_BYTES = 128 * 1024**2
MAX_JSON_BYTES = 8 * 1024**2
MAX_OUTPUT_BYTES = MAX_GLB_BYTES + MAX_PNG_BYTES + MAX_JSON_BYTES


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


def _finite_json(value):
    if isinstance(value, float):
        _need(math.isfinite(value), "Non-finite JSON number")
    elif isinstance(value, dict):
        for child in value.values():
            _finite_json(child)
    elif isinstance(value, list):
        for child in value:
            _finite_json(child)


def _parse_glb(raw):
    _need(len(raw) >= 28, "Truncated GLB")
    magic, version, total = struct.unpack_from("<III", raw)
    _need((magic, version, total) == (0x46546C67, 2, len(raw)), "Invalid GLB header/length")
    chunks, offset = [], 12
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
    doc = json.loads(chunks[0][1].decode("utf-8"),
                     object_pairs_hook=_unique_object, parse_constant=_bad_number)
    _finite_json(doc)
    _need(isinstance(doc, dict) and isinstance(doc.get("asset"), dict)
          and doc["asset"].get("version") == "2.0", "glTF2 asset required")
    binary = chunks[1][1]
    buffers = doc.get("buffers", [])
    _need(isinstance(buffers, list) and len(buffers) == 1 and isinstance(buffers[0], dict)
          and "uri" not in buffers[0], "One embedded buffer required")
    declared = buffers[0].get("byteLength")
    _need(type(declared) is int and 0 <= declared <= len(binary)
          and len(binary) - declared <= 3, "Invalid embedded buffer length")
    _need(binary[declared:] == b"\0" * (len(binary) - declared), "BIN padding must be zero")
    views = doc.get("bufferViews", [])
    _need(isinstance(views, list), "bufferViews must be an array")
    for view in views:
        _need(isinstance(view, dict), "bufferView must be an object")
        start, length = view.get("byteOffset", 0), view.get("byteLength")
        _need(type(view.get("buffer", 0)) is int and view.get("buffer", 0) == 0
              and type(start) is int and type(length) is int and start >= 0 and length > 0
              and start + length <= declared, "bufferView outside embedded buffer")
    return doc, binary


def _validate_png(raw, expected_dimensions):
    """Validate CRCs and the complete bounded zlib scanline stream; no resampling."""
    _need(isinstance(expected_dimensions, (tuple, list)) and len(expected_dimensions) == 2
          and all(type(x) is int and 0 < x <= 8192 for x in expected_dimensions),
          "Explicit PNG dimensions within8192 required")
    _need(raw[:8] == b"\x89PNG\r\n\x1a\n", "PNG signature required")
    offset, kinds, idat_closed, decoded = 8, [], False, 0
    decoder, stride, expected = zlib.decompressobj(), 0, 0

    def consume(data):
        nonlocal decoded
        _need(decoded + len(data) <= expected, "PNG decoded stream exceeds IHDR dimensions")
        for index in range((-decoded) % stride, len(data), stride):
            _need(data[index] <= 4, "Invalid PNG row filter")
        decoded += len(data)

    while offset < len(raw):
        _need(offset + 12 <= len(raw), "Truncated PNG chunk")
        length = struct.unpack_from(">I", raw, offset)[0]
        kind = raw[offset + 4:offset + 8]
        end = offset + 12 + length
        _need(end <= len(raw) and re.fullmatch(b"[A-Za-z]{4}", kind)
              and not (kind[2] & 32), "Invalid PNG chunk extent/type")
        payload = raw[offset + 8:offset + 8 + length]
        crc = struct.unpack_from(">I", raw, offset + 8 + length)[0]
        _need(zlib.crc32(kind + payload) & 0xFFFFFFFF == crc, "PNG CRC mismatch")
        if not kinds:
            _need(kind == b"IHDR" and length == 13, "PNG IHDR must be first")
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", payload)
            _need([width, height] == list(expected_dimensions) and depth == 8 and color in (2, 6)
                  and compression == filtering == interlace == 0,
                  "PNG must have explicit dimensions and noninterlaced8-bit RGB/RGBA data")
            stride = 1 + width * (3 if color == 2 else 4)
            expected = stride * height
        else:
            _need(kind != b"IHDR", "Duplicate PNG IHDR")
        if kind == b"IDAT":
            _need(not idat_closed, "PNG IDAT chunks must be consecutive")
            pending = payload
            while pending:
                scan = decoder.decompress(pending, 65536)
                consume(scan)
                _need(not decoder.unused_data, "PNG zlib trailing data")
                pending = decoder.unconsumed_tail
        elif b"IDAT" in kinds:
            idat_closed = True
        _need(kind in (b"IHDR", b"IDAT", b"IEND") or bool(kind[0] & 32),
              "Unsupported critical PNG chunk")
        kinds.append(kind)
        offset = end
        if kind == b"IEND":
            _need(length == 0 and offset == len(raw), "Invalid PNG IEND/trailing bytes")
            break
    _need(kinds and kinds[-1] == b"IEND" and b"IDAT" in kinds
          and decoder.eof and not decoder.unused_data and decoded == expected,
          "PNG IDAT/IEND or complete decoded scanlines missing")
    return list(expected_dimensions)


def _index(items, index, label):
    _need(isinstance(items, list) and type(index) is int and 0 <= index < len(items),
          "Invalid " + label)
    _need(isinstance(items[index], dict), label + " must be an object")
    return items[index]


def _validate_sampler(sampler):
    _need(isinstance(sampler, dict) and set(sampler) <= {"magFilter", "minFilter", "wrapS", "wrapT", "name"},
          "Explicit core glTF sampler required")
    for key, allowed in (("magFilter", (9728, 9729)),
                         ("minFilter", (9728, 9729, 9984, 9985, 9986, 9987)),
                         ("wrapS", (33071, 33648, 10497)), ("wrapT", (33071, 33648, 10497))):
        if key in sampler:
            _need(type(sampler[key]) is int and sampler[key] in allowed, "Invalid sampler " + key)
    _need("name" not in sampler or isinstance(sampler["name"], str), "Sampler name must be a string")


def _target_image(doc, material_index):
    material = _index(doc.get("materials"), material_index, "material index")
    info = material.get("normalTexture")
    _need(isinstance(info, dict) and set(info) <= {"index", "texCoord", "scale", "extensions"},
          "Existing explicit normalTexture binding required")
    _need(type(info.get("texCoord", 0)) is int and info.get("texCoord", 0) == 0
          and type(info.get("scale", 1)) in (int, float) and info.get("scale", 1) == 1,
          "Existing normal binding must use UV0 and strength1")
    ext = info.get("extensions", {})
    _need(isinstance(ext, dict) and set(ext) <= {"KHR_texture_transform"}, "Unsupported normal binding extension")
    transform = ext.get("KHR_texture_transform", {})
    _need(isinstance(transform, dict) and set(transform) <= {"offset", "rotation", "scale", "texCoord"}
          and transform.get("offset", [0, 0]) == [0, 0] and transform.get("scale", [1, 1]) == [1, 1]
          and transform.get("rotation", 0) == 0 and transform.get("texCoord", 0) == 0,
          "Normal UV transform must be identity on UV0")
    textures, images = doc.get("textures"), doc.get("images")
    texture = _index(textures, info.get("index"), "normal texture")
    _need(not texture.get("extensions"), "Texture source extensions are outside this operation")
    image_id = texture.get("source")
    image = _index(images, image_id, "normal image")
    _index(doc.get("bufferViews"), image.get("bufferView"), "normal image bufferView")
    _need("uri" not in image and image.get("mimeType") in ("image/jpeg", "image/png"),
          "Original normal image must be embedded JPEG/PNG")
    consumers = []

    def walk(value, path):
        if isinstance(value, dict):
            for key, child in value.items():
                if key.lower().endswith("texture") and isinstance(child, dict) and "index" in child:
                    used = _index(textures, child["index"], "material texture")
                    _need(not used.get("extensions"), "Material texture source extensions are unsupported")
                    if used.get("source") == image_id:
                        consumers.append(path + (key,))
                walk(child, path + (key,))
        elif isinstance(value, list):
            for index, child in enumerate(value):
                walk(child, path + (index,))
    walk(doc["materials"], ())
    _need(consumers == [(material_index, "normalTexture")], "Original normal image has another material texture consumer")
    return image_id


def _inputs(source_glb, normal_png, *, expected_source_sha256, expected_png_sha256,
            material_index, sampler, expected_dimensions, image_name):
    source, png = map(Path, (source_glb, normal_png))
    raw, source_state = _bound_input(source, expected_source_sha256, MAX_GLB_BYTES)
    raw_png, png_state = _bound_input(png, expected_png_sha256, MAX_PNG_BYTES)
    dimensions = _validate_png(raw_png, expected_dimensions)
    doc, binary = _parse_glb(raw)
    original_image = _target_image(doc, material_index)
    _validate_sampler(sampler)
    _need(image_name is None or isinstance(image_name, str) and bool(image_name), "Image name must be a nonempty string")
    return source, png, source_state, png_state, raw_png, dimensions, doc, binary, original_image


def _assert_unchanged(path, state, digest):
    _need((path.stat().st_size, path.stat().st_mtime_ns) == state and _sha(path.read_bytes()) == digest,
          "Input changed before/after output creation")


def verify_normal_append(source_glb, normal_png, output_glb, *, expected_source_sha256,
                         expected_png_sha256, sampler, expected_dimensions, material_index=0, image_name=None):
    """Independent fresh-file allowlist/prefix check; also usable after delivery."""
    source, png, ss, ps, raw_png, dims, old, binary, original_image = _inputs(
        source_glb, normal_png, expected_source_sha256=expected_source_sha256,
        expected_png_sha256=expected_png_sha256, material_index=material_index,
        sampler=sampler, expected_dimensions=expected_dimensions, image_name=image_name)
    output = Path(output_glb)
    _need(0 < output.stat().st_size <= MAX_OUTPUT_BYTES, "Output size outside bound")
    raw_output = output.read_bytes()
    fresh, new_binary = _parse_glb(raw_output)
    vi, ii, ti = [len(old.get(k, [])) for k in ("bufferViews", "images", "textures")]
    old_samplers = old.get("samplers", [])
    _need(isinstance(old_samplers, list), "samplers must be an array")
    si = next((i for i, row in enumerate(old_samplers) if row == sampler), len(old_samplers))
    reused = si < len(old_samplers)
    for key, count in (("bufferViews", vi), ("images", ii), ("textures", ti)):
        _need(isinstance(fresh.get(key), list) and len(fresh[key]) == count + 1,
              "Expected one appended " + key)
    expected_image = {"bufferView": vi, "mimeType": "image/png"}
    if image_name is not None:
        expected_image["name"] = image_name
    _need(fresh["bufferViews"][-1] == {"buffer": 0, "byteOffset": len(binary), "byteLength": len(raw_png)}
          and fresh["images"][-1] == expected_image
          and fresh["textures"][-1] == {"source": ii, "sampler": si}
          and fresh["materials"][material_index]["normalTexture"] == {"index": ti, "texCoord": 0, "scale": 1},
          "Appended image/view/texture/normal binding differs")
    expected_samplers = copy.deepcopy(old_samplers) + ([] if reused else [copy.deepcopy(sampler)])
    _need(fresh.get("samplers") == expected_samplers, "Sampler append/reuse differs")
    declared = len(binary) + len(raw_png)
    _need(fresh["buffers"][0]["byteLength"] == declared
          and len(new_binary) == declared + (-declared % 4)
          and new_binary[:len(binary)] == binary
          and new_binary[len(binary):declared] == raw_png
          and new_binary[declared:] == b"\0" * (-declared % 4), "BIN prefix/appended PNG/padding differs")
    restored = copy.deepcopy(fresh)
    for key in ("bufferViews", "images", "textures"):
        restored[key].pop()
    if not reused:
        restored["samplers"].pop()
        if "samplers" not in old:
            del restored["samplers"]
    restored["materials"][material_index]["normalTexture"] = copy.deepcopy(old["materials"][material_index]["normalTexture"])
    restored["buffers"][0]["byteLength"] = old["buffers"][0]["byteLength"]
    _need(restored == old, "Unexpected old JSON change (geometry/skin/clips/maps included)")
    _assert_unchanged(source, ss, expected_source_sha256)
    _assert_unchanged(png, ps, expected_png_sha256)
    return {"status": "PASS_NORMAL_ONLY_APPEND_FRESH_READBACK", "source_sha256": expected_source_sha256,
            "PNG_sha256": expected_png_sha256, "PNG_dimensions": dims, "material_index": material_index,
            "output": str(output), "bytes": len(raw_output), "sha256": _sha(raw_output),
            "original_BIN_prefix_bytes": len(binary), "original_BIN_prefix_sha256": _sha(binary),
            "original_BIN_prefix_preserved": True, "other_JSON_fields_unchanged": True,
            "original_bufferViews_preserved": vi, "original_accessors_preserved": len(old.get("accessors", [])),
            "original_normal_image_index_preserved_without_material_texture_consumer": original_image,
            "sampler_reused": reused, "appended_sampler_count": 0 if reused else 1,
            "normal_binding": {"index": ti, "texCoord": 0, "scale": 1},
            "image_conversion_or_green_flip_applied": False,
            "texture_semantics_UV_registration_basis_art_animation_or_engine_qualified": False}


def append_normal_png(source_glb, normal_png, output_glb, *, expected_source_sha256,
                      expected_png_sha256, sampler, expected_dimensions, material_index=0, image_name=None):
    """Write a new derivative; caller owns normal convention, registration and review."""
    source, png, output = map(Path, (source_glb, normal_png, output_glb))
    _need(output.resolve() not in (source.resolve(), png.resolve()), "Output aliases an input")
    _need(not output.exists(), "Output already exists")
    source, png, ss, ps, raw_png, _, old, binary, _ = _inputs(
        source, png, expected_source_sha256=expected_source_sha256, expected_png_sha256=expected_png_sha256,
        material_index=material_index, sampler=sampler, expected_dimensions=expected_dimensions, image_name=image_name)
    doc = copy.deepcopy(old)
    vi, ii, ti = [len(doc.get(k, [])) for k in ("bufferViews", "images", "textures")]
    samplers = doc.setdefault("samplers", [])
    _need(isinstance(samplers, list), "samplers must be an array")
    si = next((i for i, row in enumerate(samplers) if row == sampler), len(samplers))
    if si == len(samplers):
        samplers.append(copy.deepcopy(sampler))
    doc["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(raw_png)})
    image = {"bufferView": vi, "mimeType": "image/png"}
    if image_name is not None:
        image["name"] = image_name
    doc["images"].append(image)
    doc["textures"].append({"source": ii, "sampler": si})
    doc["materials"][material_index]["normalTexture"] = {"index": ti, "texCoord": 0, "scale": 1}
    doc["buffers"][0]["byteLength"] = len(binary) + len(raw_png)
    payload = json.dumps(doc, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
    payload += b" " * (-len(payload) % 4)
    new_binary = binary + raw_png
    new_binary += b"\0" * (-len(new_binary) % 4)
    total = 28 + len(payload) + len(new_binary)
    _need(len(payload) <= MAX_JSON_BYTES and total <= MAX_OUTPUT_BYTES, "Derivative exceeds bound")
    _assert_unchanged(source, ss, expected_source_sha256)
    _assert_unchanged(png, ps, expected_png_sha256)
    # No directory creation; exclusive creation closes the exists/open race.
    with output.open("xb") as stream:
        stream.write(struct.pack("<III", 0x46546C67, 2, total))
        stream.write(struct.pack("<II", len(payload), 0x4E4F534A))
        stream.write(payload)
        stream.write(struct.pack("<II", len(new_binary), 0x004E4942))
        stream.write(new_binary)
    report = verify_normal_append(source, png, output, expected_source_sha256=expected_source_sha256,
                                  expected_png_sha256=expected_png_sha256, sampler=sampler,
                                  expected_dimensions=expected_dimensions, material_index=material_index, image_name=image_name)
    _assert_unchanged(source, ss, expected_source_sha256)
    _assert_unchanged(png, ps, expected_png_sha256)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-glb", required=True, type=Path)
    parser.add_argument("--normal-png", required=True, type=Path)
    parser.add_argument("--output-glb", required=True, type=Path)
    parser.add_argument("--expected-source-sha256", required=True)
    parser.add_argument("--expected-png-sha256", required=True)
    parser.add_argument("--dimensions", required=True, nargs=2, type=int, metavar=("WIDTH", "HEIGHT"))
    parser.add_argument("--sampler-json", required=True, help="Explicit core glTF sampler object; no inferred filter policy")
    parser.add_argument("--material-index", type=int, default=0)
    parser.add_argument("--image-name")
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    try:
        sampler = json.loads(args.sampler_json, object_pairs_hook=_unique_object, parse_constant=_bad_number)
        operation = verify_normal_append if args.verify_only else append_normal_png
        result = operation(args.source_glb, args.normal_png, args.output_glb,
                           expected_source_sha256=args.expected_source_sha256, expected_png_sha256=args.expected_png_sha256,
                           sampler=sampler, expected_dimensions=args.dimensions, material_index=args.material_index, image_name=args.image_name)
    except (ValueError, OSError, KeyError, IndexError, TypeError, UnicodeError, struct.error, zlib.error, RecursionError) as error:
        parser.exit(1, "Refused: " + str(error) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
