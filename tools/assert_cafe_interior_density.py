#!/usr/bin/env python3
"""Fail-closed café density plus capture-command provenance gate.

The receipt is not a filename label table.  Each row carries the exact normalized
Godot argv that produced its fresh PNG; the verifier derives observed floor/mode/
viewport/seed/tick from that transcript and rejects any mismatch before pixels.
This detects accidental capture-pipeline drift and stale/substituted evidence. It
does not claim to defend against someone who deliberately rewrites both tools.
"""
import argparse
import copy
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
    ("cafe_1f_normal", "vg_int_cafe.png", "1f", "normal", "none"),
    ("cafe_1f_bare", "vg_cafe1f_bare.png", "1f", "bare", "interior_furniture"),
    ("cafe_2f_normal", "vg_cafe2f.png", "2f", "normal", "none"),
    ("cafe_2f_bare", "vg_cafe2f_bare.png", "2f", "bare", "interior_furniture"),
)
EXPECTED_BY_FILE = {row[1]: row for row in CAPTURES}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def argv_digest(argv):
    return hashlib.sha256(canonical(argv).encode("ascii")).hexdigest()


def rect(size):
    w, h = size
    scale = min((w - PAD[0] * w / BASE_VP[0]) / (8 * T),
                (h - PAD[1] * h / BASE_VP[1]) / (6 * T))
    sx = lambda v: (v - 4 * T) * scale + w / 2.0
    sy = lambda v: (v - 3 * T) * scale + h / 2.0
    return (math.ceil(sx(T)), math.ceil(sy(T)), math.floor(sx(7 * T)), math.floor(sy(5 * T)))


def footprint(size):
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


def parse_argv(argv, filename):
    """Strictly parse the actual renderer command transcript for one evidence slot."""
    if not isinstance(argv, list) or not all(isinstance(x, str) for x in argv):
        raise ValueError("missing/invalid capture-command transcript")
    try:
        divider = argv.index("--")
    except ValueError:
        raise ValueError("missing capture-command transcript divider")
    prefix, tail = argv[:divider], argv[divider + 1:]
    if len(prefix) != 11 or prefix[0::2] != ["--path", "--display-driver", "--rendering-driver", "--audio-driver", "--resolution", "--single-window"]:
        raise ValueError("invalid capture-command transcript prefix")
    if prefix[3] != "x11" or prefix[5] != "opengl3" or prefix[7] != "Dummy":
        raise ValueError("invalid capture-command transcript renderer settings")
    game_path, resolution = prefix[1], prefix[9]
    try:
        width, height = (int(v) for v in resolution.split("x", 1))
    except (ValueError, AttributeError):
        raise ValueError("invalid capture-command transcript resolution")
    required = ["--backend", "logic", "--seed", "3", "--warmup-tick", "600",
                "--probe-space", "cafe", "--probe-floor"]
    if tail[:len(required)] != required or len(tail) < len(required) + 3:
        raise ValueError("invalid capture-command transcript simulation parameters")
    floor = tail[len(required)]
    tail = tail[len(required) + 1:]
    if not tail or tail[0] != "--shot-fit":
        raise ValueError("invalid capture-command transcript shot-fit")
    tail = tail[1:]
    draw_skip = "none"
    if tail[:2] == ["--draw-skip", "interior_furniture"]:
        draw_skip = "interior_furniture"
        tail = tail[2:]
    if len(tail) != 2 or tail[0] != "--shot" or os.path.basename(tail[1]) != filename:
        raise ValueError("invalid capture-command transcript output slot")
    if not game_path or not os.path.dirname(tail[1]):
        raise ValueError("invalid capture-command transcript path")
    return {"space": "cafe", "floor": floor, "draw_skip": draw_skip,
            "mode": "bare" if draw_skip == "interior_furniture" else "normal",
            "width": width, "height": height, "seed": 3, "tick": 600,
            "game_path": game_path, "output_root": os.path.normpath(os.path.dirname(tail[1]))}


def read_receipt(out_dir):
    path = os.path.join(out_dir, RECEIPT_NAME)
    if not os.path.isfile(path):
        raise ValueError("missing receipt/metadata")
    try:
        with open(path, encoding="utf-8") as f:
            receipt = json.load(f)
    except (OSError, ValueError) as e:
        raise ValueError("invalid receipt/metadata: %s" % e)
    if receipt.get("schema") != "cafe-density-receipt-v2" or receipt.get("source") != "visual_gate.sh":
        raise ValueError("invalid receipt/metadata schema")
    session = receipt.get("session")
    captures = receipt.get("captures")
    if not isinstance(session, str) or len(session) < 16 or not isinstance(captures, list) or len(captures) != 4:
        raise ValueError("invalid receipt/metadata capture session")
    return session, captures


def verify_provenance(out_dir):
    session, entries = read_receipt(out_dir)
    by_file, image_digests, images, shared = {}, set(), {}, None
    for item in entries:
        if not isinstance(item, dict) or not isinstance(item.get("file"), str):
            raise ValueError("invalid receipt/metadata entry")
        filename = item["file"]
        if filename in by_file or filename not in EXPECTED_BY_FILE:
            raise ValueError("invalid receipt/metadata duplicate or unknown slot")
        by_file[filename] = item
    if set(by_file) != set(EXPECTED_BY_FILE):
        raise ValueError("invalid receipt/metadata capture names")

    for filename, (slot, _, floor, mode, draw_skip) in EXPECTED_BY_FILE.items():
        item = by_file[filename]
        if item.get("session") != session or item.get("slot") != slot:
            raise ValueError("mixed-session/stale-provenance: %s" % filename)
        argv = item.get("argv")
        if item.get("argv_sha256") != argv_digest(argv):
            raise ValueError("stale-provenance: command transcript digest mismatch for %s" % filename)
        observed = parse_argv(argv, filename)
        for key, value in {"space": "cafe", "floor": floor, "mode": mode,
                           "draw_skip": draw_skip, "width": observed["width"],
                           "height": observed["height"], "seed": 3, "tick": 600}.items():
            if item.get(key) != value or observed.get(key) != value:
                raise ValueError("wrong-floor/mode command transcript for %s: expected %s=%r" %
                                 (filename, key, value))
        size = (observed["width"], observed["height"])
        if size not in SUPPORTED_VIEWPORTS:
            raise ValueError("wrong-resolution/cropped evidence: unsupported transcript viewport %r" % (size,))
        common = (observed["game_path"], observed["output_root"], observed["seed"], observed["tick"], size)
        if shared is None:
            shared = common
        elif shared != common:
            raise ValueError("mixed-session/mixed-parameter evidence")
        path = os.path.join(out_dir, filename)
        actual = digest(path) if os.path.isfile(path) else None
        if actual != item.get("sha256"):
            raise ValueError("stale-provenance: receipt hash mismatch for %s" % filename)
        if actual in image_digests:
            raise ValueError("duplicated evidence: %s reuses another capture payload" % filename)
        image_digests.add(actual)
        images[filename] = load(path, size)
    return shared[-1], images


def changes(normal, bare):
    return [max(abs(a - b) for a, b in zip(p, q)) > DTOL for p, q in zip(normal.getdata(), bare.getdata())]


def assess(normal, bare):
    w, h = normal.size
    changed, (x0, y0, x1, y1) = changes(normal, bare), footprint(normal.size)
    inside = outside = 0
    for y in range(h):
        for x in range(w):
            if changed[y * w + x]:
                if x0 <= x < x1 and y0 <= y < y1: inside += 1
                else: outside += 1
    return inside, outside


def check(out_dir):
    size, images = verify_provenance(out_dir)
    one, one_bare = images["vg_int_cafe.png"], images["vg_cafe1f_bare.png"]
    two, two_bare = images["vg_cafe2f.png"], images["vg_cafe2f_bare.png"]
    a_in, a_out, b_in, b_out = *assess(one, one_bare), *assess(two, two_bare)
    r, floor_diff = rect(size), sum(changes(one, two))
    floor_pixels = (r[2] - r[0]) * (r[3] - r[1])
    print("[CAFEDENSITY] viewport=%s footprint=%s density-region=%s 1F inside=%d outside=%d 2F inside=%d outside=%d 1F-v-2F=%d" %
          (size, footprint(size), r, a_in, a_out, b_in, b_out, floor_diff))
    failures = []
    if a_in < floor_pixels // 25: failures.append("1F furniture is too sparse or draw-skip was not applied")
    if b_in < floor_pixels // 25: failures.append("2F furniture is too sparse or draw-skip was not applied")
    if a_out or b_out: failures.append("furniture pixels escaped the authored inner-cell footprint")
    if floor_diff < floor_pixels // 12: failures.append("1F public café and 2F private room are insufficiently distinct")
    if failures:
        print("[CAFEDENSITY] FAIL " + "; ".join(failures)); return 1
    print("[CAFEDENSITY] PASS command-bound density and footprint are bounded"); return 0


def _fixture_receipt(out_dir, size):
    """Private --self-test-only fixture; no CLI writes receipts for supplied images."""
    rows = []
    for slot, filename, floor, mode, draw_skip in CAPTURES:
        argv = ["--path", "/synthetic/game", "--display-driver", "x11", "--rendering-driver", "opengl3",
                "--audio-driver", "Dummy", "--resolution", "%dx%d" % size, "--single-window", "--",
                "--backend", "logic", "--seed", "3", "--warmup-tick", "600", "--probe-space", "cafe",
                "--probe-floor", floor, "--shot-fit"]
        if draw_skip != "none": argv += ["--draw-skip", draw_skip]
        argv += ["--shot", "/synthetic/out/" + filename]
        rows.append({"session": "self-test-session-0001", "slot": slot, "file": filename, "space": "cafe",
                     "floor": floor, "mode": mode, "draw_skip": draw_skip, "width": size[0], "height": size[1],
                     "seed": 3, "tick": 600, "argv": argv, "argv_sha256": argv_digest(argv),
                     "sha256": digest(os.path.join(out_dir, filename))})
    with open(os.path.join(out_dir, RECEIPT_NAME), "w", encoding="utf-8") as f:
        json.dump({"schema": "cafe-density-receipt-v2", "source": "visual_gate.sh",
                   "session": "self-test-session-0001", "captures": rows}, f, sort_keys=True, separators=(",", ":"))


def make_fixture(out_dir, size):
    fp, r = footprint(size), rect(size)
    for _, filename, floor, mode, _ in CAPTURES:
        im = Image.new("RGB", size, (20, 20, 20) if floor == "1f" else (24, 24, 30))
        if mode == "normal":
            d, color = ImageDraw.Draw(im), ((220, 110, 50) if floor == "1f" else (50, 150, 220))
            d.rectangle((r[0] + 2, r[1] + 2, r[2] - 3, r[3] - 3), fill=color)
            d.rectangle((fp[0] + 2, fp[1] + 2, fp[0] + 20, fp[1] + 20), fill=color)
        im.save(os.path.join(out_dir, filename))
    _fixture_receipt(out_dir, size)


def refresh_row(receipt, filename, path):
    row = next(x for x in receipt["captures"] if x["file"] == filename)
    row["sha256"] = digest(path)
    row["argv_sha256"] = argv_digest(row["argv"])


def expect_reject(label, out_dir, reason):
    try: rc = check(out_dir)
    except ValueError as e:
        if reason and reason not in str(e):
            print("[CAFEDENSITY] FAIL self-test %s wrong reason: %s" % (label, e)); return False
        print("[CAFEDENSITY] self-test rejected %s: %s" % (label, e)); return True
    if rc == 0: print("[CAFEDENSITY] FAIL self-test %s passed unexpectedly" % label); return False
    print("[CAFEDENSITY] self-test rejected %s at density stage" % label); return True


def self_test():
    root = tempfile.mkdtemp(prefix="cafe-density-self-test-")
    try:
        for size in sorted(SUPPORTED_VIEWPORTS):
            case = os.path.join(root, "%dx%d" % size); os.mkdir(case); make_fixture(case, size)
            if check(case) != 0: return 1
            print("[CAFEDENSITY] self-test positive command-bound %s" % (size,))
        base = os.path.join(root, "1280x768")
        def clone(name):
            path = os.path.join(root, name); shutil.copytree(base, path); return path
        # REFUTE: transformed 1F pixels and recomputed PNG hash/labels still carry a 1F argv transcript.
        palette = clone("palette-1f-as-2f")
        for source, target in (("vg_int_cafe.png", "vg_cafe2f.png"), ("vg_cafe1f_bare.png", "vg_cafe2f_bare.png")):
            im = Image.open(os.path.join(palette, source)).convert("RGB")
            im = im.point(lambda v: (v * 7 + 31) % 256); im.save(os.path.join(palette, target))
        with open(os.path.join(palette, RECEIPT_NAME), encoding="utf-8") as f: receipt = json.load(f)
        for source, fn in (("vg_int_cafe.png", "vg_cafe2f.png"), ("vg_cafe1f_bare.png", "vg_cafe2f_bare.png")):
            source_row = next(x for x in receipt["captures"] if x["file"] == source)
            target_row = next(x for x in receipt["captures"] if x["file"] == fn)
            target_row["argv"] = list(source_row["argv"])
            target_row["argv"][-1] = "/synthetic/out/" + fn
            refresh_row(receipt, fn, os.path.join(palette, fn))
        with open(os.path.join(palette, RECEIPT_NAME), "w", encoding="utf-8") as f: json.dump(receipt, f)
        if not expect_reject("palette-transformed 1F-as-2F", palette, "command transcript"): return 1
        swap = clone("normal-bare-swap")
        shutil.copyfile(os.path.join(swap, "vg_cafe2f_bare.png"), os.path.join(swap, "vg_cafe2f.png"))
        with open(os.path.join(swap, RECEIPT_NAME), encoding="utf-8") as f: receipt = json.load(f)
        source_row = next(x for x in receipt["captures"] if x["file"] == "vg_cafe2f_bare.png")
        target_row = next(x for x in receipt["captures"] if x["file"] == "vg_cafe2f.png")
        target_row["argv"] = list(source_row["argv"])
        target_row["argv"][-1] = "/synthetic/out/vg_cafe2f.png"
        refresh_row(receipt, "vg_cafe2f.png", os.path.join(swap, "vg_cafe2f.png"))
        with open(os.path.join(swap, RECEIPT_NAME), "w", encoding="utf-8") as f: json.dump(receipt, f)
        if not expect_reject("normal/bare swap", swap, "command transcript"): return 1
        wrong_call = clone("actual-2f-call-ran-1f")
        with open(os.path.join(wrong_call, RECEIPT_NAME), encoding="utf-8") as f: receipt = json.load(f)
        row = next(x for x in receipt["captures"] if x["file"] == "vg_cafe2f.png")
        row["argv"][row["argv"].index("--probe-floor") + 1] = "1f"; row["argv_sha256"] = argv_digest(row["argv"])
        with open(os.path.join(wrong_call, RECEIPT_NAME), "w", encoding="utf-8") as f: json.dump(receipt, f)
        if not expect_reject("actual 2F slot executed 1F", wrong_call, "command transcript"): return 1
        mixed_session = clone("mixed session")
        with open(os.path.join(mixed_session, RECEIPT_NAME), encoding="utf-8") as f: receipt = json.load(f)
        next(x for x in receipt["captures"] if x["file"] == "vg_cafe2f.png")["session"] = "other-self-test-session"
        with open(os.path.join(mixed_session, RECEIPT_NAME), "w", encoding="utf-8") as f: json.dump(receipt, f)
        if not expect_reject("mixed session", mixed_session, "mixed-session"): return 1
        for label, flag, value, field in (("mixed seed", "--seed", "4", "seed"), ("mixed tick", "--warmup-tick", "601", "tick")):
            case = clone(label)
            with open(os.path.join(case, RECEIPT_NAME), encoding="utf-8") as f: receipt = json.load(f)
            row = next(x for x in receipt["captures"] if x["file"] == "vg_cafe2f.png")
            row["argv"][row["argv"].index(flag) + 1] = value; row[field] = int(value); row["argv_sha256"] = argv_digest(row["argv"])
            with open(os.path.join(case, RECEIPT_NAME), "w", encoding="utf-8") as f: json.dump(receipt, f)
            if not expect_reject(label, case, "command transcript"): return 1
        duplicated = clone("duplicate payload")
        shutil.copyfile(os.path.join(duplicated, "vg_int_cafe.png"), os.path.join(duplicated, "vg_cafe2f.png"))
        with open(os.path.join(duplicated, RECEIPT_NAME), encoding="utf-8") as f: receipt = json.load(f)
        refresh_row(receipt, "vg_cafe2f.png", os.path.join(duplicated, "vg_cafe2f.png"))
        with open(os.path.join(duplicated, RECEIPT_NAME), "w", encoding="utf-8") as f: json.dump(receipt, f)
        if not expect_reject("duplicate payload", duplicated, "duplicated evidence"): return 1
        for label, source, target in (("swapped floors", "vg_cafe2f.png", "vg_int_cafe.png"),):
            case = clone(label); shutil.copyfile(os.path.join(case, source), os.path.join(case, target))
            if not expect_reject(label, case, "stale-provenance"): return 1
        missing = clone("missing receipt"); os.remove(os.path.join(missing, RECEIPT_NAME))
        if not expect_reject("missing receipt", missing, "missing receipt/metadata"): return 1
        cropped = clone("crop"); Image.open(os.path.join(cropped, "vg_cafe2f.png")).resize((640, 384)).save(os.path.join(cropped, "vg_cafe2f.png"))
        with open(os.path.join(cropped, RECEIPT_NAME), encoding="utf-8") as f: receipt = json.load(f)
        refresh_row(receipt, "vg_cafe2f.png", os.path.join(cropped, "vg_cafe2f.png"))
        with open(os.path.join(cropped, RECEIPT_NAME), "w", encoding="utf-8") as f: json.dump(receipt, f)
        if not expect_reject("crop", cropped, "wrong-resolution/cropped"): return 1
        escaped = clone("escaped pixel"); im = Image.open(os.path.join(escaped, "vg_int_cafe.png")).convert("RGB"); ImageDraw.Draw(im).point((1, 1), fill=(255, 255, 255)); im.save(os.path.join(escaped, "vg_int_cafe.png"))
        with open(os.path.join(escaped, RECEIPT_NAME), encoding="utf-8") as f: receipt = json.load(f)
        refresh_row(receipt, "vg_int_cafe.png", os.path.join(escaped, "vg_int_cafe.png"))
        with open(os.path.join(escaped, RECEIPT_NAME), "w", encoding="utf-8") as f: json.dump(receipt, f)
        if not expect_reject("out-of-footprint pixel", escaped, ""): return 1
        print("[CAFEDENSITY] PASS self-test rejects transcript, session, mode, crop, and footprint controls"); return 0
    finally: shutil.rmtree(root)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("out_dir", nargs="?"); ap.add_argument("--self-test", action="store_true"); a = ap.parse_args()
    if a.self_test: return self_test()
    if not a.out_dir: ap.error("out_dir is required unless --self-test")
    try: return check(a.out_dir)
    except ValueError as e: print("[CAFEDENSITY] FAIL " + str(e)); return 1


if __name__ == "__main__": sys.exit(main())
