"""Original periodic natural granite PBR, independent of masonry materials.

Only natural_rock_* maps and their manifest are written. Existing texture maps
are not regenerated. Fourier noise, physical normal derivation and edge sealing
reuse the original project material helper without invoking its generator.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "tools/generate_materials.py"
spec = importlib.util.spec_from_file_location("living_town_material_helpers", HELPER)
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
TILE_METRES = 4.0


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def natural_rock():
    n = helpers.noise
    smooth = helpers.smooth
    broad = n(111, 1, 4, 16)
    weather = n(112, 3, 13, 20)
    undulation = n(113, 8, 28, 20)
    aggregate = n(114, 90, 310, 36)
    fine = n(115, 210, 470, 28)
    mica = smooth(.13, .47, -aggregate)
    feldspar = smooth(.06, .42, aggregate)
    quartz = smooth(.16, .46, n(116, 34, 110, 24))

    # Broad, domain-warped mineral seams. These are continuous natural fields,
    # never a tile/grid/cell layout or a regular masonry-joint pattern.
    warp = n(117, 1, 5, 18)
    seam_field = np.sin(helpers.TAU * (2 * helpers.U - helpers.V + .31 * warp))
    seam_field += .45 * n(118, 2, 9, 16)
    quartz_vein = np.exp(-(np.abs(seam_field) / .19) ** 1.5)
    weathered_edge = np.exp(-(np.abs(seam_field) / .46) ** 1.4)

    # Uneven-width fractures lose continuity where weathering fills the crevice.
    # A separate, gated field creates short offshoots rather than a tiled network.
    fracture_field = n(119, 2, 7, 20) + .18 * n(120, 13, 36, 16)
    width = .013 + .014 * smooth(-.25, .32, weather)
    fracture = np.exp(-(np.abs(fracture_field) / width) ** 1.6)
    fracture *= .25 + .75 * smooth(-.22, .20, n(121, 1, 8, 16))
    branch_field = n(122, 5, 15, 20) + .13 * undulation
    branches = np.exp(-(np.abs(branch_field) / .009) ** 1.6)
    branches *= smooth(.10, .35, n(123, 2, 8, 16))
    cracks = np.clip(fracture + branches * .52, 0, 1)

    lichen_patch = smooth(.19, .45, n(124, 4, 17, 24))
    lichen = lichen_patch * smooth(-.03, .35, n(125, 28, 110, 24))
    rust = smooth(.20, .48, n(126, 2, 10, 20)) * .45
    rgb = helpers.tint("#85877e", broad * 13 + weather * 7 + undulation * 4 + fine * 3)
    rgb += feldspar[..., None] * np.array([15, 13, 11], dtype=np.float32)
    rgb -= mica[..., None] * np.array([25, 24, 21], dtype=np.float32)
    rgb += quartz[..., None] * 9
    rgb += quartz_vein[..., None] * np.array([12, 12, 9], dtype=np.float32)
    rgb += weathered_edge[..., None] * np.array([2, 1, -2], dtype=np.float32)
    rgb += rust[..., None] * np.array([15, 7, -5], dtype=np.float32)
    rgb -= cracks[..., None] * np.array([27, 27, 25], dtype=np.float32)
    lichen_color = np.array([142, 147, 108], dtype=np.float32)
    rgb = rgb * (1 - lichen[..., None] * .46) + lichen_color * lichen[..., None] * .46

    height = broad * .012 + weather * .006 + undulation * .003
    height += aggregate * .0014 + fine * .00035 + quartz_vein * .0015
    height -= cracks * .014
    height += lichen * .001
    roughness = .89 + weather * .055 + mica * .035 - feldspar * .055
    roughness += cracks * .045 + lichen * .035
    return rgb, roughness, height, lichen


def generate(out, contact_sheet=None):
    out.mkdir(parents=True, exist_ok=True)
    rgb, roughness, height, lichen = natural_rock()
    arrays = {
        "basecolor": np.round(np.clip(helpers.seal(rgb), 0, 255)).astype(np.uint8),
        "roughness": np.round(np.clip(helpers.data_map(roughness), 0, 1) * 255).astype(np.uint8),
        "normal": helpers.normal_map(height, TILE_METRES),
    }
    records = {}
    for kind, array in arrays.items():
        assert np.array_equal(array[0], array[-1]), (kind, "V seam")
        assert np.array_equal(array[:, 0], array[:, -1]), (kind, "U seam")
        path = out / ("natural_rock_" + kind + ".png")
        Image.fromarray(array).save(path, optimize=True)
        with path.open("rb+") as stream:
            os.fsync(stream.fileno())
        records[kind] = {"file": path.name, "bytes": path.stat().st_size, "sha256": sha(path), "resolution": list(Image.fromarray(array).size)}
    manifest = {
        "schema": "living_town.natural_rock_material.v1", "name": "natural_rock",
        "generator": "tools/generate_reserve_materials.py", "generator_sha256": sha(__file__),
        "helper": "tools/generate_materials.py", "helper_sha256": sha(HELPER),
        "helper_seed": helpers.SEED, "recipe_noise_seeds": list(range(111, 127)),
        "license": "Original project-generated procedural material; no external media used",
        "description": "Natural fractured warm/cool grey granite, mineral aggregate, weathered quartz veins, irregular crevices and restrained sage lichen; no masonry joints",
        "tile_size_metres": TILE_METRES, "palette_base_srgb": "#85877e",
        "basecolor": records["basecolor"]["file"], "roughness": records["roughness"]["file"], "normal": records["normal"]["file"],
        "basecolor_color_space": "sRGB", "roughness_color_space": "Non-Color", "normal_color_space": "Non-Color",
        "normal_convention": "OpenGL tangent-space +Y", "normal_strength": .85,
        "uv_hint": "MetricUV/4m; repeat; natural rock only, never replace the core Granite masonry material",
        "roughness_mean": round(float(np.mean(arrays["roughness"]) / 255), 5),
        "height_range_metres": round(float(np.max(height) - np.min(height)), 5),
        "lichen_mean_coverage": round(float(np.mean(lichen)), 5),
        "periodicity": "Opposite edge pixels exactly equal in all three maps; wrapped physical height gradients",
        "edge_checks": "PASS", "maps": records,
    }
    path = out / "natural_rock_material.json"
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(manifest, stream, indent=2);stream.write("\n");stream.flush();os.fsync(stream.fileno())
    if contact_sheet:
        contact_sheet.parent.mkdir(parents=True, exist_ok=True)
        canvas = Image.new("RGB", (1200, 760), "#eee9dc")
        draw = ImageDraw.Draw(canvas)
        draw.text((24, 18), "ORIGINAL NATURAL GRANITE / 4m repeat / no masonry", fill="#344044")
        thumb = Image.fromarray(arrays["basecolor"]).resize((320, 320), Image.Resampling.LANCZOS)
        for y in (70, 390):
            for x in (24, 344):
                canvas.paste(thumb, (x, y))
        canvas.paste(Image.fromarray(arrays["roughness"]).convert("RGB").resize((230, 230)), (720, 70))
        canvas.paste(Image.fromarray(arrays["normal"]).resize((230, 230)), (720, 390))
        draw.text((720, 310), "Roughness / 512px", fill="#344044")
        draw.text((720, 630), "Physical OpenGL normals / 512px", fill="#344044")
        draw.text((24, 726), "2 x 2 tiling preview / basecolor 1024px / opposing pixel edges verified", fill="#344044")
        canvas.save(contact_sheet)
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "textures")
    parser.add_argument("--contact-sheet", type=Path)
    options = parser.parse_args()
    generate(options.out, options.contact_sheet)
