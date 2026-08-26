#!/usr/bin/env python3
"""Fail-closed café-density gate with renderer-capture provenance.

The four café PNGs are evidence only when their receipt, written immediately by
``visual_gate.sh`` after the real capture commands, binds each pixel payload to
the requested café floor, dimensions, and furniture draw mode. Names alone are
not provenance: stale, swapped, or substituted PNGs fail before density is read.
"""
import argparse
import hashlib
import json
import math
import os
import shutil
import sys
import tempfile

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("[CAFEDENSITY] FAIL Pillow is required; refusing to skip")
    sys.exit(1)

BASE_VP = (1280, 768)
SUPPORTED_VIEWPORTS = {(1280, 768), (320, 192)}
T, PAD, DTOL = 48.0, (120.0, 240.0), 28
RECEIPT_NAME = "cafe_density_receipt.json"
CAPTURES = (
    ("vg_int_cafe.png", "1f", "normal", "none"),
    ("vg_cafe1f_bare.png", "1f", "bare", "interior_furniture"),
    ("vg_cafe2f.png", "2f", "normal", "none"),
    ("vg_cafe2f_bare.png", "2f", "bare", "interior_furniture"),
)


def rect(size):
    """The 8x6 café inner cells [1..6]x[1..4] in a shot-fit frame."""
    w, h = size
    scale = min((w - PAD[0] * w / BASE_VP[0]) / (8 * T),
                (h - PAD[1] * h / BASE_VP[1]) / (6 * T))
    sx = lambda v: (v - 4 * T) * scale + w / 2.0
    sy = lambda v: (v - 3 * T) * scale + h / 2.0
    return (math.ceil(sx(T)), math.ceil(sy(T)),
            math.floor(sx(7 * T)), math.floor(sy(5 * T)))


def footprint(size):
    """Scale C1's 1280x768 authored café footprint without expanding it."""
    w, h = size
    return (math.ceil(261 * w / BASE_VP[0]), math.ceil(100 * h / BASE_VP[1]),
            math.floor(1019 * w / BASE_VP[0]), math.floor(668 * h / BASE_VP[1]))


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def load(path, expected_size):
    if not os.path.isfile(path):
        raise ValueError("missing frame: " + path)
    im = Image.open(path).convert("RGB")
    if im.size != expected_size:
        raise ValueError("wrong-resolution/cropped evidence: %s is %s, expected %s" %
                         (os.path.basename(path), im.size, expected_size))
    return im


def read_receipt(out_dir):
    path = os.path.join(out_dir, RECEIPT_NAME)
    if not os.path.isfile(path):
        raise ValueError("missing receipt/metadata")
    try:
        with open(path, encoding="utf-8") as f:
            receipt = json.load(f)
    except (OSError, ValueError) as e:
        raise ValueError("invalid receipt/metadata: %s" % e)
    if receipt.get("schema") != "cafe-density-receipt-v1" or receipt.get("source") != "visual_gate.sh":
        raise ValueError("invalid receipt/metadata schema")
    captures = receipt.get("captures")
    if not isinstance(captures, list) or len(captures) != len(CAPTURES):
        raise ValueError("invalid receipt/metadata capture set")
    return captures


def verify_provenance(out_dir):
    by_file = {}
    for item in read_receipt(out_dir):
        if not isinstance(item, dict) or not isinstance(item.get("file"), str):
            raise ValueError("invalid receipt/metadata entry")
        if item["file"] in by_file:
            raise ValueError("invalid receipt/metadata duplicate filename")
        by_file[item["file"]] = item
    if set(by_file) != {item[0] for item in CAPTURES}:
        raise ValueError("invalid receipt/metadata capture names")

    images, image_digests, common_size = {}, set(), None
    for filename, floor, mode, draw_skip in CAPTURES:
        item = by_file[filename]
        expected = {"file": filename, "space": "cafe", "floor": floor,
                    "mode": mode, "draw_skip": draw_skip}
        for key, value in expected.items():
            if item.get(key) != value:
                raise ValueError("wrong-floor/stale-provenance: %s has %s=%r, expected %r" %
                                 (filename, key, item.get(key), value))
        size = (item.get("width"), item.get("height"))
        if size not in SUPPORTED_VIEWPORTS:
            raise ValueError("wrong-resolution/cropped evidence: %s receipt dimensions %r" %
                             (filename, size))
        if common_size is None:
            common_size = size
        elif size != common_size:
            raise ValueError("wrong-resolution/cropped evidence: mixed receipt dimensions")
        path = os.path.join(out_dir, filename)
        actual = digest(path) if os.path.isfile(path) else None
        if actual != item.get("sha256"):
            raise ValueError("wrong-floor/stale-provenance: receipt hash mismatch for %s" % filename)
        if actual in image_digests:
            raise ValueError("duplicated evidence: %s reuses another capture payload" % filename)
        image_digests.add(actual)
        images[filename] = load(path, common_size)
    return common_size, images


def changes(normal, bare):
    return [max(abs(a - b) for a, b in zip(p, q)) > DTOL
            for p, q in zip(normal.getdata(), bare.getdata())]


def assess(normal, bare):
    w, h = normal.size
    changed = changes(normal, bare)
    x0, y0, x1, y1 = footprint(normal.size)
    inside = outside = 0
    for y in range(h):
        row = y * w
        for x in range(w):
            if changed[row + x]:
                if x0 <= x < x1 and y0 <= y < y1:
                    inside += 1
                else:
                    outside += 1
    return inside, outside


def check(out_dir):
    size, images = verify_provenance(out_dir)
    one, one_bare = images["vg_int_cafe.png"], images["vg_cafe1f_bare.png"]
    two, two_bare = images["vg_cafe2f.png"], images["vg_cafe2f_bare.png"]
    a_in, a_out = assess(one, one_bare)
    b_in, b_out = assess(two, two_bare)
    r = rect(size)
    floor_pixels = (r[2] - r[0]) * (r[3] - r[1])
    floor_diff = sum(changes(one, two))
    print("[CAFEDENSITY] viewport=%s footprint=%s density-region=%s 1F inside=%d outside=%d 2F inside=%d outside=%d 1F-v-2F=%d" %
          (size, footprint(size), r, a_in, a_out, b_in, b_out, floor_diff))
    failures = []
    if a_in < floor_pixels // 25:
        failures.append("1F furniture is too sparse or draw-skip was not applied")
    if b_in < floor_pixels // 25:
        failures.append("2F furniture is too sparse or draw-skip was not applied")
    if a_out or b_out:
        failures.append("furniture pixels escaped the authored inner-cell footprint")
    if floor_diff < floor_pixels // 12:
        failures.append("1F public café and 2F private room are insufficiently distinct")
    if failures:
        print("[CAFEDENSITY] FAIL " + "; ".join(failures))
        return 1
    print("[CAFEDENSITY] PASS renderer-bound density and footprint are bounded")
    return 0


def write_fixture_receipt(out_dir, size):
    captures = []
    for filename, floor, mode, draw_skip in CAPTURES:
        captures.append({"file": filename, "space": "cafe", "floor": floor,
                         "mode": mode, "draw_skip": draw_skip, "width": size[0],
                         "height": size[1], "sha256": digest(os.path.join(out_dir, filename))})
    with open(os.path.join(out_dir, RECEIPT_NAME), "w", encoding="utf-8") as f:
        json.dump({"schema": "cafe-density-receipt-v1", "source": "visual_gate.sh",
                   "captures": captures}, f,
                  sort_keys=True, separators=(",", ":"))


def make_fixture(out_dir, size):
    fp, r = footprint(size), rect(size)
    for filename, floor, mode, _ in CAPTURES:
        # Bare frames are still distinct rooms, so a duplicated payload is a real
        # provenance failure rather than an accidental property of the fixture.
        im = Image.new("RGB", size, (20, 20, 20) if floor == "1f" else (24, 24, 30))
        if mode == "normal":
            d = ImageDraw.Draw(im)
            color = (220, 110, 50) if floor == "1f" else (50, 150, 220)
            d.rectangle((r[0] + 2, r[1] + 2, r[2] - 3, r[3] - 3), fill=color)
            d.rectangle((fp[0] + 2, fp[1] + 2, fp[0] + 20, fp[1] + 20), fill=color)
        im.save(os.path.join(out_dir, filename))
    write_fixture_receipt(out_dir, size)


def expect_reject(label, out_dir, reason):
    try:
        rc = check(out_dir)
    except ValueError as e:
        if reason and reason not in str(e):
            print("[CAFEDENSITY] FAIL self-test %s wrong reason: %s" % (label, e))
            return False
        print("[CAFEDENSITY] self-test rejected %s: %s" % (label, e))
        return True
    if rc == 0:
        print("[CAFEDENSITY] FAIL self-test %s passed unexpectedly" % label)
        return False
    print("[CAFEDENSITY] self-test rejected %s at density stage" % label)
    return True


def self_test():
    root = tempfile.mkdtemp(prefix="cafe-density-self-test-")
    try:
        for size in sorted(SUPPORTED_VIEWPORTS):
            case = os.path.join(root, "%dx%d" % size)
            os.mkdir(case)
            make_fixture(case, size)
            if check(case) != 0:
                print("[CAFEDENSITY] FAIL self-test positive %s" % (size,))
                return 1
            print("[CAFEDENSITY] self-test positive provenance+density %s" % (size,))

        base = os.path.join(root, "1280x768")
        for label, source, target in (
            ("mirrored-1f-as-2f", "vg_int_cafe.png", "vg_cafe2f.png"),
            ("swapped-1f-2f", "vg_cafe2f.png", "vg_int_cafe.png"),
            ("normal-as-bare", "vg_int_cafe.png", "vg_cafe1f_bare.png"),
            ("bare-as-normal", "vg_cafe1f_bare.png", "vg_int_cafe.png"),
        ):
            case = os.path.join(root, label)
            shutil.copytree(base, case)
            shutil.copyfile(os.path.join(case, source), os.path.join(case, target))
            if not expect_reject(label, case, "wrong-floor/stale-provenance"):
                return 1

        duplicated = os.path.join(root, "duplicated-normal")
        shutil.copytree(base, duplicated)
        shutil.copyfile(os.path.join(duplicated, "vg_int_cafe.png"),
                        os.path.join(duplicated, "vg_cafe2f.png"))
        write_fixture_receipt(duplicated, (1280, 768))
        if not expect_reject("duplicated normal", duplicated, "duplicated evidence"):
            return 1

        wrong_mode = os.path.join(root, "wrong-mode")
        shutil.copytree(base, wrong_mode)
        receipt_path = os.path.join(wrong_mode, RECEIPT_NAME)
        with open(receipt_path, encoding="utf-8") as f:
            receipt = json.load(f)
        receipt["captures"][1]["mode"] = "normal"
        with open(receipt_path, "w", encoding="utf-8") as f:
            json.dump(receipt, f, sort_keys=True, separators=(",", ":"))
        if not expect_reject("wrong draw mode", wrong_mode, "wrong-floor/stale-provenance"):
            return 1

        missing = os.path.join(root, "missing-receipt")
        shutil.copytree(base, missing)
        os.remove(os.path.join(missing, RECEIPT_NAME))
        if not expect_reject("missing receipt", missing, "missing receipt/metadata"):
            return 1

        cropped = os.path.join(root, "wrong-resolution")
        shutil.copytree(base, cropped)
        Image.open(os.path.join(cropped, "vg_cafe2f.png")).resize((640, 384)).save(
            os.path.join(cropped, "vg_cafe2f.png"))
        write_fixture_receipt(cropped, (1280, 768))
        if not expect_reject("wrong resolution/crop", cropped, "wrong-resolution/cropped evidence"):
            return 1

        escaped = os.path.join(root, "escaped-pixel")
        shutil.copytree(base, escaped)
        im = Image.open(os.path.join(escaped, "vg_int_cafe.png")).convert("RGB")
        ImageDraw.Draw(im).point((1, 1), fill=(255, 255, 255))
        im.save(os.path.join(escaped, "vg_int_cafe.png"))
        write_fixture_receipt(escaped, (1280, 768))
        if not expect_reject("out-of-footprint pixel", escaped, ""):
            return 1
        print("[CAFEDENSITY] PASS self-test rejects provenance, mode, crop, and footprint controls")
        return 0
    finally:
        shutil.rmtree(root)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir", nargs="?")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    if not a.out_dir:
        ap.error("out_dir is required unless --self-test")
    try:
        return check(a.out_dir)
    except ValueError as e:
        print("[CAFEDENSITY] FAIL " + str(e))
        return 1


if __name__ == "__main__":
    sys.exit(main())
