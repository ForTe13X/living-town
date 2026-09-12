#!/usr/bin/env python3
"""Fail-closed café density plus capture-command provenance gate.

The receipt is not a filename label table.  Each row carries the exact normalized
Godot argv that produced its fresh PNG; the verifier derives observed floor/mode/
viewport/seed/tick from that transcript and rejects any mismatch before pixels.
This detects accidental capture-pipeline drift and stale/substituted evidence. It
does not claim to defend against someone who deliberately rewrites both tools.
"""
import argparse
import contextlib
import copy
import hashlib
import io
import json
import math
import os
import shutil
import sys
import tempfile

try:
    from PIL import Image, ImageChops, ImageDraw
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

# This is a small semantic layout contract, not a color or frame-pixel golden.
# It is projected from the exact authored cafe furniture layout in
# game/data/interiors.json: 1F has public service furniture in the first group,
# while Aria's 2F room has the private bed/desk/vanity group.  The slots are
# deliberately disjoint across floors, so changing a palette cannot satisfy the
# wrong floor's geometry.  A later intentional layout change must review this
# projection together with the source layout instead of silently rebaking image
# pixels.
PUBLIC_CAFE_LANDMARKS = (
    ("counter", (4, 1)),
    ("coffee machine", (5, 1)),
    ("table", (5, 3)),
    ("barstool", (5, 4)),
)
PRIVATE_ROOM_LANDMARKS = (
    ("bed", (2, 2)),
    ("desk", (5, 2)),
    ("vanity", (6, 4)),
)
LANDMARK_MIN_COVERAGE = 0.08
LANDMARK_MAX_COVERAGE = 0.03
# A landmark is an authored furniture footprint, not merely an occupied cell.
# Its changed pixels must therefore extend materially on both tile axes.  This
# leaves room for palette, rasterizer, and small shot-fit variation, while a
# thin horizontal/vertical stripe cannot impersonate a bed, desk, or vanity.
LANDMARK_MIN_AXIS_COVERAGE = 0.25
# A meaningful furniture footprint occupies most of its own local bounding box.
# This rejects a broad cross/T made from thin orthogonal bands without requiring
# the furniture to be a particular rectangle or color.  The real 320px
# barstool is the tightest authored example (about 0.59 bounding-box fill).
LANDMARK_MIN_BOUNDING_FILL = 0.50
# A one-axis stripe has a very elongated local box; authored landmarks stay
# compact even when their occupied tile coverage is deliberately small.
LANDMARK_MAX_ASPECT = 2.5
# Thin-band unions can have a plausible bounding fill (notably a T at low
# resolution).  A furniture footprint instead has substantial occupancy across
# the median local row and column, so neither axis can be carried by one arm.
LANDMARK_MIN_MEDIAN_CROSS_SECTION = 0.50
# A named room is not three copies of one generic occupancy stamp.  The
# authored bed, desk, and vanity have independently drawn local silhouettes;
# at either supported scale their changed-pixel coverages span this much.  This
# deliberately compares local shapes to each other, rather than to a palette,
# a frame hash, or a baked reference image.
PRIVATE_SILHOUETTE_MIN_COVERAGE_SPREAD = 0.06
# A checkerboard is dense enough to pass coverage, but it is fragmented rather
# than one furniture silhouette.  Small sprite details may disconnect, so the
# meaningful criterion is that one 4-connected body carries most changed
# pixels, not that every pixel belongs to it.
LANDMARK_MIN_LARGEST_COMPONENT = 0.80
# A hollow ring has the right outer box and two-axis extent but no authored
# furniture body.  Limit only voids enclosed by changed pixels inside the
# local silhouette box; ordinary background outside the sprite is ignored.
LANDMARK_MAX_ENCLOSED_VOID = 0.20


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


def cell_rect(size, cell):
    """Return one authored 8x6 cafe tile in a shot-fit frame."""
    w, h = size
    x, y = cell
    if not (0 <= x < 8 and 0 <= y < 6):
        raise ValueError("invalid semantic landmark cell %r" % (cell,))
    scale = min((w - PAD[0] * w / BASE_VP[0]) / (8 * T),
                (h - PAD[1] * h / BASE_VP[1]) / (6 * T))
    sx = lambda v: (v - 4 * T) * scale + w / 2.0
    sy = lambda v: (v - 3 * T) * scale + h / 2.0
    x0, y0 = math.ceil(sx(x * T)), math.ceil(sy(y * T))
    x1, y1 = math.floor(sx((x + 1) * T)), math.floor(sy((y + 1) * T))
    if x1 <= x0 or y1 <= y0:
        raise ValueError("invalid semantic landmark geometry for viewport %r" % (size,))
    return x0, y0, x1, y1


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


def landmark_geometry(mask, size, landmarks):
    """Measure palette-independent local furniture occupancy and compactness."""
    w, h = size
    measured = []
    for name, cell in landmarks:
        x0, y0, x1, y1 = cell_rect(size, cell)
        changed = rows = cols = 0
        min_x = min_y = None
        max_x = max_y = None
        for y in range(y0, y1):
            row_changed = False
            for x in range(x0, x1):
                if mask[y * w + x]:
                    changed += 1
                    row_changed = True
                    min_x = x if min_x is None else min(min_x, x)
                    max_x = x if max_x is None else max(max_x, x)
                    min_y = y if min_y is None else min(min_y, y)
                    max_y = y if max_y is None else max(max_y, y)
            rows += row_changed
        for x in range(x0, x1):
            cols += any(mask[y * w + x] for y in range(y0, y1))
        area = (x1 - x0) * (y1 - y0)
        if changed:
            box_width, box_height = max_x - min_x + 1, max_y - min_y + 1
            bounding_fill = changed / (box_width * box_height)
            aspect = max(box_width / box_height, box_height / box_width)
            row_fills = sorted(sum(mask[y * w + x] for x in range(min_x, max_x + 1)) / box_width
                               for y in range(min_y, max_y + 1))
            col_fills = sorted(sum(mask[y * w + x] for y in range(min_y, max_y + 1)) / box_height
                               for x in range(min_x, max_x + 1))
            row_median = row_fills[len(row_fills) // 2]
            col_median = col_fills[len(col_fills) // 2]
            body, void = silhouette_topology(mask, w, min_x, min_y, max_x, max_y, changed)
        else:
            bounding_fill = aspect = row_median = col_median = body = void = 0.0
        measured.append((name, cell, changed / area, rows / (y1 - y0), cols / (x1 - x0),
                         bounding_fill, aspect, row_median, col_median, body, void))
    return measured


def silhouette_topology(mask, width, min_x, min_y, max_x, max_y, changed):
    """Return the largest 4-connected body and enclosed-void fractions."""
    occupied = {(x, y) for y in range(min_y, max_y + 1) for x in range(min_x, max_x + 1)
                if mask[y * width + x]}
    pending, largest = set(occupied), 0
    while pending:
        stack, component = [pending.pop()], 0
        while stack:
            x, y = stack.pop(); component += 1
            for neighbor in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if neighbor in pending:
                    pending.remove(neighbor); stack.append(neighbor)
        largest = max(largest, component)
    # Flood from the bounding-box edge through empty pixels.  What remains is
    # a true hole, so a surrounding empty room cannot be mistaken for one.
    empty = {(x, y) for y in range(min_y, max_y + 1) for x in range(min_x, max_x + 1)
             if (x, y) not in occupied}
    outside = {(x, y) for x, y in empty if x in (min_x, max_x) or y in (min_y, max_y)}
    stack = list(outside)
    while stack:
        x, y = stack.pop()
        for neighbor in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if neighbor in empty and neighbor not in outside:
                outside.add(neighbor); stack.append(neighbor)
    box_area = (max_x - min_x + 1) * (max_y - min_y + 1)
    return largest / changed, (len(empty) - len(outside)) / box_area


def semantic_geometry(one, one_bare, two, two_bare):
    """Require public 1F and private 2F landmark shapes in their authored cells."""
    masks = {
        "1F": changes(one, one_bare),
        "2F": changes(two, two_bare),
    }
    observed = {
        ("1F", "public"): landmark_geometry(masks["1F"], one.size, PUBLIC_CAFE_LANDMARKS),
        ("1F", "private"): landmark_geometry(masks["1F"], one.size, PRIVATE_ROOM_LANDMARKS),
        ("2F", "public"): landmark_geometry(masks["2F"], two.size, PUBLIC_CAFE_LANDMARKS),
        ("2F", "private"): landmark_geometry(masks["2F"], two.size, PRIVATE_ROOM_LANDMARKS),
    }
    for floor, kind in (("1F", "public"), ("1F", "private"), ("2F", "public"), ("2F", "private")):
        values = ", ".join("%s@%s=%.3f rows=%.3f cols=%.3f fill=%.3f aspect=%.3f median=%.3f/%.3f" %
                           (name, cell, coverage, rows, cols, fill, aspect, row_median, col_median)
                           for name, cell, coverage, rows, cols, fill, aspect, row_median, col_median, body, void in observed[(floor, kind)])
        print("[CAFEDENSITY] semantic geometry %s %s [%s]" % (floor, kind, values))

    failures = []
    for floor, kind, present in (("1F", "public", True), ("1F", "private", False),
                                 ("2F", "private", True), ("2F", "public", False)):
        for name, cell, coverage, rows, cols, fill, aspect, row_median, col_median, body, void in observed[(floor, kind)]:
            if present and coverage < LANDMARK_MIN_COVERAGE:
                failures.append(
                    "%s %s landmark %s at %s has changed coverage %.3f < %.3f" %
                    (floor, kind, name, cell, coverage, LANDMARK_MIN_COVERAGE))
            if present and (rows < LANDMARK_MIN_AXIS_COVERAGE or cols < LANDMARK_MIN_AXIS_COVERAGE):
                failures.append(
                    "%s %s landmark %s at %s lacks authored two-axis footprint "
                    "(rows %.3f, cols %.3f; each >= %.3f)" %
                    (floor, kind, name, cell, rows, cols, LANDMARK_MIN_AXIS_COVERAGE))
            if present and fill < LANDMARK_MIN_BOUNDING_FILL:
                failures.append(
                    "%s %s landmark %s at %s lacks compact authored footprint "
                    "(bounding fill %.3f < %.3f)" %
                    (floor, kind, name, cell, fill, LANDMARK_MIN_BOUNDING_FILL))
            if present and aspect > LANDMARK_MAX_ASPECT:
                failures.append(
                    "%s %s landmark %s at %s is a one-axis band, not furniture "
                    "(aspect %.3f > %.3f)" %
                    (floor, kind, name, cell, aspect, LANDMARK_MAX_ASPECT))
            # The reproduced bypass targets only the claimed private 2F group.
            # Public café furniture includes an intentionally sparse table, so
            # apply this finer topology discriminator at the authored private
            # landmarks rather than falsely imposing one silhouette vocabulary.
            if present and kind == "private" and (row_median < LANDMARK_MIN_MEDIAN_CROSS_SECTION or
                                                   col_median < LANDMARK_MIN_MEDIAN_CROSS_SECTION):
                failures.append(
                    "%s %s landmark %s at %s lacks a compact furniture cross-section "
                    "(median rows %.3f, cols %.3f; each >= %.3f)" %
                     (floor, kind, name, cell, row_median, col_median,
                     LANDMARK_MIN_MEDIAN_CROSS_SECTION))
            if present and body < LANDMARK_MIN_LARGEST_COMPONENT:
                failures.append(
                    "%s %s landmark %s at %s is fragmented, not one authored silhouette "
                    "(largest body %.3f < %.3f)" %
                    (floor, kind, name, cell, body, LANDMARK_MIN_LARGEST_COMPONENT))
            if present and void > LANDMARK_MAX_ENCLOSED_VOID:
                failures.append(
                    "%s %s landmark %s at %s is hollow, not an authored furniture body "
                    "(enclosed void %.3f > %.3f)" %
                    (floor, kind, name, cell, void, LANDMARK_MAX_ENCLOSED_VOID))
            if not present and coverage > LANDMARK_MAX_COVERAGE:
                failures.append(
                    "%s received %s landmark geometry %s at %s (coverage %.3f > %.3f)" %
                    (floor, kind, name, cell, coverage, LANDMARK_MAX_COVERAGE))
    private_coverages = [entry[2] for entry in observed[("2F", "private")]]
    if max(private_coverages) - min(private_coverages) < PRIVATE_SILHOUETTE_MIN_COVERAGE_SPREAD:
        failures.append(
            "2F private landmarks repeat one generic silhouette "
            "(coverage spread %.3f < %.3f)" %
            (max(private_coverages) - min(private_coverages), PRIVATE_SILHOUETTE_MIN_COVERAGE_SPREAD))
    return failures


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
    failures.extend(semantic_geometry(one, one_bare, two, two_bare))
    if failures:
        print("[CAFEDENSITY] FAIL " + "; ".join(failures)); return 1
    print("[CAFEDENSITY] PASS command-bound density, footprint, and floor-semantic geometry are bounded"); return 0


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
    def fill_landmark(draw, cell, color):
        x0, y0, x1, y1 = cell_rect(size, cell)
        draw.rectangle((x0 + 1, y0 + 1, x1 - 2, y1 - 2), fill=color)

    for _, filename, floor, mode, _ in CAPTURES:
        im = Image.new("RGB", size, (20, 20, 20) if floor == "1f" else (24, 24, 30))
        if mode == "normal":
            d = ImageDraw.Draw(im)
            color = (220, 110, 50) if floor == "1f" else (50, 150, 220)
            landmarks = PUBLIC_CAFE_LANDMARKS if floor == "1f" else PRIVATE_ROOM_LANDMARKS
            for index, (_, cell) in enumerate(landmarks):
                if floor == "2f" and index == 1:
                    x0, y0, x1, y1 = cell_rect(size, cell)
                    d.rectangle((x0 + 1, y0 + 1, x0 + (x1 - x0) * 3 // 5, y1 - 2), fill=color)
                    d.rectangle((x0 + 1, y1 - (y1 - y0) * 3 // 5, x1 - 2, y1 - 2), fill=color)
                elif floor == "2f" and index == 2:
                    x0, y0, x1, y1 = cell_rect(size, cell)
                    d.rectangle((x0 + (x1 - x0) // 4, y0 + (y1 - y0) // 4,
                                 x1 - 2, y1 - (y1 - y0) // 3), fill=color)
                else:
                    fill_landmark(d, cell, color)
        im.save(os.path.join(out_dir, filename))
    _fixture_receipt(out_dir, size)


def refresh_row(receipt, filename, path):
    row = next(x for x in receipt["captures"] if x["file"] == filename)
    row["sha256"] = digest(path)
    row["argv_sha256"] = argv_digest(row["argv"])


def refresh_rows(receipt, out_dir, filenames):
    for filename in filenames:
        refresh_row(receipt, filename, os.path.join(out_dir, filename))


def expect_reject(label, out_dir, reason):
    stream = io.StringIO()
    try:
        with contextlib.redirect_stdout(stream):
            rc = check(out_dir)
    except ValueError as e:
        transcript = stream.getvalue()
        if transcript:
            print(transcript, end="")
        if reason and reason not in str(e):
            print("[CAFEDENSITY] FAIL self-test %s wrong reason: %s" % (label, e)); return False
        print("[CAFEDENSITY] self-test rejected %s: %s" % (label, e)); return True
    transcript = stream.getvalue()
    print(transcript, end="")
    if rc == 0: print("[CAFEDENSITY] FAIL self-test %s passed unexpectedly" % label); return False
    if reason and reason not in transcript:
        print("[CAFEDENSITY] FAIL self-test %s wrong rejection stage (expected %s)" % (label, reason)); return False
    print("[CAFEDENSITY] self-test rejected %s at assertion stage" % label); return True


def self_test():
    root = tempfile.mkdtemp(prefix="cafe-density-self-test-")
    try:
        for size in sorted(SUPPORTED_VIEWPORTS):
            case = os.path.join(root, "%dx%d" % size); os.mkdir(case); make_fixture(case, size)
            if check(case) != 0: return 1
            print("[CAFEDENSITY] self-test positive command-bound %s" % (size,))
        base = os.path.join(root, "1280x768")
        def clone(name, size=(1280, 768)):
            path = os.path.join(root, name)
            shutil.copytree(os.path.join(root, "%dx%d" % size), path)
            return path
        # REFUTE: color-inverted 1F normal/bare PNGs replace the 2F payloads while
        # the receipt retains a legitimate 2F transcript/session/mode/seed/tick and
        # recomputes every per-row hash.  Provenance must pass; semantic geometry must
        # reject the public-cafe furniture pattern in the claimed private room.
        palette = clone("palette-1f-as-2f")
        for source, target in (("vg_int_cafe.png", "vg_cafe2f.png"), ("vg_cafe1f_bare.png", "vg_cafe2f_bare.png")):
            im = Image.open(os.path.join(palette, source)).convert("RGB")
            im = im.point(lambda v: 255 - v); im.save(os.path.join(palette, target))
        with open(os.path.join(palette, RECEIPT_NAME), encoding="utf-8") as f: receipt = json.load(f)
        for fn in ("vg_cafe2f.png", "vg_cafe2f_bare.png"):
            refresh_row(receipt, fn, os.path.join(palette, fn))
        with open(os.path.join(palette, RECEIPT_NAME), "w", encoding="utf-8") as f: json.dump(receipt, f)
        if not expect_reject("self-consistent palette-inverted 1F-as-2F", palette, "semantic geometry"): return 1
        # REFUTE: each claimed private landmark contains an 11%-high horizontal
        # band, with sufficient unrelated changed pixels elsewhere in the valid
        # footprint.  Rebuild the receipt so this reaches semantic geometry;
        # occupancy alone must not make these stripes furniture.
        coarse = clone("alternate-coarse-geometry")
        normal = Image.open(os.path.join(coarse, "vg_cafe2f_bare.png")).convert("RGB")
        draw = ImageDraw.Draw(normal)
        for _, cell in PRIVATE_ROOM_LANDMARKS:
            x0, y0, x1, y1 = cell_rect(normal.size, cell)
            band_height = max(1, round((y1 - y0) / 9))
            draw.rectangle((x0, y0 + (y1 - y0) // 2, x1 - 1,
                            y0 + (y1 - y0) // 2 + band_height - 1), fill=(50, 150, 220))
        x0, y0, x1, y1 = cell_rect(normal.size, (1, 1))
        draw.rectangle((x0 + 4, y0 + 4, x1 - 5, y1 - 5), fill=(50, 150, 220))
        normal.save(os.path.join(coarse, "vg_cafe2f.png"))
        with open(os.path.join(coarse, RECEIPT_NAME), encoding="utf-8") as f: receipt = json.load(f)
        refresh_rows(receipt, coarse, ("vg_cafe2f.png",))
        with open(os.path.join(coarse, RECEIPT_NAME), "w", encoding="utf-8") as f: json.dump(receipt, f)
        if not expect_reject("self-consistent alternate coarse geometry", coarse, "authored two-axis footprint"): return 1
        # REFUTE: both independently reproduced topology false-positive families
        # are internally consistent at both evidence resolutions.  Crosses/Ts
        # have enough extent in each axis but sparse bounding boxes; the exact
        # quarter-height stripe is dense in its own box but too elongated.
        for size in sorted(SUPPORTED_VIEWPORTS):
            # REFUTE: a uniform solid stamp, hollow frame, or checkerboard can
            # be receipt-valid and dense at either viewport, but none carries
            # the independent authored silhouettes of bed/desk/vanity.
            for topology in ("solid", "hollow", "checker"):
                case = clone("%s-%dx%d" % (topology, size[0], size[1]), size)
                normal = Image.open(os.path.join(case, "vg_cafe2f_bare.png")).convert("RGB")
                draw = ImageDraw.Draw(normal)
                for _, cell in PRIVATE_ROOM_LANDMARKS:
                    x0, y0, x1, y1 = cell_rect(size, cell)
                    if topology == "solid":
                        draw.rectangle((x0 + (x1 - x0) // 5, y0 + (y1 - y0) // 5,
                                        x1 - (x1 - x0) // 5 - 1, y1 - (y1 - y0) // 5 - 1),
                                       fill=(50, 150, 220))
                    elif topology == "hollow":
                        inset = max(1, min(x1 - x0, y1 - y0) // 5)
                        draw.rectangle((x0 + inset, y0 + inset, x1 - inset - 1, y1 - inset - 1),
                                       outline=(50, 150, 220), width=max(1, inset // 2))
                    else:
                        step = max(2, min(x1 - x0, y1 - y0) // 5)
                        for y in range(y0, y1, step):
                            for x in range(x0, x1, step):
                                if ((x - x0) // step + (y - y0) // step) % 2 == 0:
                                    draw.rectangle((x, y, min(x + step - 1, x1 - 1),
                                                    min(y + step - 1, y1 - 1)), fill=(50, 150, 220))
                normal.save(os.path.join(case, "vg_cafe2f.png"))
                with open(os.path.join(case, RECEIPT_NAME), encoding="utf-8") as f: receipt = json.load(f)
                refresh_rows(receipt, case, ("vg_cafe2f.png",))
                with open(os.path.join(case, RECEIPT_NAME), "w", encoding="utf-8") as f: json.dump(receipt, f)
                reason = "hollow" if topology == "hollow" else (
                    "fragmented" if topology == "checker" else "repeat one generic silhouette")
                if not expect_reject("self-consistent %s %dx%d" % (topology, size[0], size[1]), case, reason): return 1
            for topology in ("cross", "tee", "quarter-stripe"):
                case = clone("%s-%dx%d" % (topology, size[0], size[1]), size)
                normal = Image.open(os.path.join(case, "vg_cafe2f_bare.png")).convert("RGB")
                draw = ImageDraw.Draw(normal)
                for _, cell in PRIVATE_ROOM_LANDMARKS:
                    x0, y0, x1, y1 = cell_rect(size, cell)
                    width, height = x1 - x0, y1 - y0
                    if topology == "quarter-stripe":
                        thick = max(1, math.ceil(height / 4))
                        draw.rectangle((x0, y0 + (height - thick) // 2, x1 - 1,
                                        y0 + (height - thick) // 2 + thick - 1), fill=(50, 150, 220))
                    else:
                        thick = max(1, round(min(width, height) * 0.24))
                        cx, cy = x0 + width // 2, y0 + height // 2
                        draw.rectangle((x0, cy - thick // 2, x1 - 1,
                                        cy - thick // 2 + thick - 1), fill=(50, 150, 220))
                        if topology == "cross":
                            draw.rectangle((cx - thick // 2, y0, cx - thick // 2 + thick - 1,
                                            y1 - 1), fill=(50, 150, 220))
                        else:
                            draw.rectangle((cx - thick // 2, cy, cx - thick // 2 + thick - 1,
                                            y1 - 1), fill=(50, 150, 220))
                # Unrelated, valid-footprint density keeps this a topology test.
                x0, y0, x1, y1 = cell_rect(size, (1, 1))
                draw.rectangle((x0 + 2, y0 + 2, x1 - 3, y1 - 3), fill=(50, 150, 220))
                normal.save(os.path.join(case, "vg_cafe2f.png"))
                with open(os.path.join(case, RECEIPT_NAME), encoding="utf-8") as f: receipt = json.load(f)
                refresh_rows(receipt, case, ("vg_cafe2f.png",))
                with open(os.path.join(case, RECEIPT_NAME), "w", encoding="utf-8") as f: json.dump(receipt, f)
                reason = "compact furniture cross-section" if topology == "tee" else (
                    "one-axis band" if topology == "quarter-stripe" else "compact authored footprint")
                if not expect_reject("self-consistent %s %dx%d" % (topology, size[0], size[1]), case, reason): return 1
            # A compact block, compact L, and compact stepped footprint are
            # positive neighbors: the discriminator is about topology, not a
            # demand for one rectangular sprite silhouette.
            furniture = clone("furniture-like-%dx%d" % size, size)
            normal = Image.open(os.path.join(furniture, "vg_cafe2f_bare.png")).convert("RGB")
            draw = ImageDraw.Draw(normal)
            for index, (_, cell) in enumerate(PRIVATE_ROOM_LANDMARKS):
                x0, y0, x1, y1 = cell_rect(size, cell)
                width, height = x1 - x0, y1 - y0
                left, top = x0 + width // 6, y0 + height // 6
                right, bottom = x1 - width // 6 - 1, y1 - height // 6 - 1
                if index == 0:
                    draw.rectangle((left, top, right, bottom), fill=(50, 150, 220))
                elif index == 1:
                    arm = max(2, min(right - left + 1, bottom - top + 1) * 3 // 5)
                    draw.rectangle((left, top, left + arm - 1, bottom), fill=(50, 150, 220))
                    draw.rectangle((left, bottom - arm + 1, right, bottom), fill=(50, 150, 220))
                else:
                    for step in range(3):
                        sx = left + step * (right - left + 1) // 5
                        sy = top + step * (bottom - top + 1) // 5
                        draw.rectangle((sx, sy, right - step * (right - left + 1) // 8,
                                        bottom - step * (bottom - top + 1) // 8), fill=(50, 150, 220))
            normal.save(os.path.join(furniture, "vg_cafe2f.png"))
            with open(os.path.join(furniture, RECEIPT_NAME), encoding="utf-8") as f: receipt = json.load(f)
            refresh_rows(receipt, furniture, ("vg_cafe2f.png",))
            with open(os.path.join(furniture, RECEIPT_NAME), "w", encoding="utf-8") as f: json.dump(receipt, f)
            if check(furniture) != 0: return 1
        # Positive robustness controls: color is not identity, and a small
        # capture-space translation remains a valid local furniture footprint.
        palette_positive = clone("benign palette transform")
        for filename in EXPECTED_BY_FILE:
            path = os.path.join(palette_positive, filename)
            im = Image.open(path).convert("RGB").point(lambda v: min(255, 20 + 3 * v // 4))
            im.save(path)
        with open(os.path.join(palette_positive, RECEIPT_NAME), encoding="utf-8") as f: receipt = json.load(f)
        refresh_rows(receipt, palette_positive, EXPECTED_BY_FILE)
        with open(os.path.join(palette_positive, RECEIPT_NAME), "w", encoding="utf-8") as f: json.dump(receipt, f)
        if check(palette_positive) != 0: return 1
        translated = clone("small normalized capture translation")
        for filename in ("vg_int_cafe.png", "vg_cafe2f.png"):
            path = os.path.join(translated, filename)
            ImageChops.offset(Image.open(path).convert("RGB"), 2, 1).save(path)
        with open(os.path.join(translated, RECEIPT_NAME), encoding="utf-8") as f: receipt = json.load(f)
        refresh_rows(receipt, translated, ("vg_int_cafe.png", "vg_cafe2f.png"))
        with open(os.path.join(translated, RECEIPT_NAME), "w", encoding="utf-8") as f: json.dump(receipt, f)
        if check(translated) != 0: return 1
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
        one_bit = clone("one-bit PNG tamper")
        one_bit_path = os.path.join(one_bit, "vg_cafe2f.png")
        with open(one_bit_path, "rb") as f: payload = bytearray(f.read())
        payload[-1] ^= 1
        with open(one_bit_path, "wb") as f: f.write(payload)
        if not expect_reject("one-bit PNG tamper", one_bit, "receipt hash mismatch"): return 1
        for label, source, target in (("swapped floors", "vg_cafe2f.png", "vg_int_cafe.png"),):
            case = clone(label); shutil.copyfile(os.path.join(case, source), os.path.join(case, target))
            if not expect_reject(label, case, "stale-provenance"): return 1
        missing = clone("missing receipt"); os.remove(os.path.join(missing, RECEIPT_NAME))
        if not expect_reject("missing receipt", missing, "missing receipt/metadata"): return 1
        partial = clone("partial receipt")
        with open(os.path.join(partial, RECEIPT_NAME), encoding="utf-8") as f: receipt = json.load(f)
        receipt["captures"].pop()
        with open(os.path.join(partial, RECEIPT_NAME), "w", encoding="utf-8") as f: json.dump(receipt, f)
        if not expect_reject("partial receipt", partial, "capture session"): return 1
        malformed = clone("malformed receipt")
        with open(os.path.join(malformed, RECEIPT_NAME), "w", encoding="utf-8") as f: f.write("{")
        if not expect_reject("malformed receipt", malformed, "invalid receipt/metadata"): return 1
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
        print("[CAFEDENSITY] PASS self-test rejects semantic, provenance, mode, crop, and footprint controls"); return 0
    finally: shutil.rmtree(root)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("out_dir", nargs="?"); ap.add_argument("--self-test", action="store_true"); a = ap.parse_args()
    if a.self_test: return self_test()
    if not a.out_dir: ap.error("out_dir is required unless --self-test")
    try: return check(a.out_dir)
    except ValueError as e: print("[CAFEDENSITY] FAIL " + str(e)); return 1


if __name__ == "__main__": sys.exit(main())
