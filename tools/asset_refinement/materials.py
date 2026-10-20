"""Original, deterministic seamless finishes for the isolated cafe-counter pilot.

These are continuous cabinet timber and honed stone, not floorboards or masonry.
No photographs, model weights, generated images, lighting or upstream code enter
their construction. UV repeat is two metres; normal slopes use that same scale.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


TILE_METRES = 2.0
FAMILIES = ("cabinet_oak", "honed_granite")


def _field(rng, u, v, lo, hi, count=22, along_grain=False):
    """Smooth periodic noise from integer-frequency waves, with no grid cells."""
    result = np.zeros_like(u)
    for _ in range(count):
        kx = int(rng.integers(lo, hi + 1))
        ky = int(rng.integers(-2, 3) if along_grain else rng.integers(-hi, hi + 1))
        phase = float(rng.uniform(0, 2 * np.pi))
        result += np.sin(2 * np.pi * (kx * u + ky * v) + phase)
    result -= result.mean()
    result /= max(float(result.std()), 1e-12)
    return np.tanh(result * .65)


def _finish(family, size, rng):
    axis = np.arange(size - 1, dtype=np.float64) / (size - 1)
    u, v = np.meshgrid(axis, axis)
    broad = _field(rng, u, v, 1, 4)
    # Keep frequencies below Nyquist even in the small fixtures used by tests.
    limit = max(4, (size - 1) // 3)
    if family == "cabinet_oak":
        warp = .035 * np.sin(2 * np.pi * v) + .018 * broad
        grain = _field(rng, u + warp, v, 7, min(37, limit), along_grain=True)
        fine = _field(rng, u + warp, v, min(17, limit), min(73, limit), along_grain=True)
        pores = np.maximum(0, -fine - .28) ** 2
        variation = broad * 6 + grain * 7 + fine * 2 - pores * 9
        rgb = np.array([151., 111., 65.]) + variation[..., None] * np.array([1., .85, .62])
        rgb += broad[..., None] * np.array([1.7, .2, -1.4])
        roughness = .53 + broad * .035 + grain * .025 + pores * .045
        height = grain * .00008 + fine * .000025 - pores * .00004
    else:
        minerals = _field(rng, u, v, min(15, limit), min(63, limit), count=30)
        fine = _field(rng, u, v, min(39, limit), min(109, limit), count=26)
        quartz = np.maximum(0, minerals - .12)
        mica = np.maximum(0, -minerals - .22)
        variation = broad * 2.4 + minerals * 13 + fine * 4 + quartz * 7 - mica * 9
        rgb = np.array([132., 132., 121.]) + variation[..., None] * np.array([1., .99, .94])
        rgb += broad[..., None] * np.array([1.6, .7, -.3])
        roughness = .43 + minerals * .038 + broad * .022 - quartz * .025
        height = minerals * .000035 + fine * .000012
    return np.clip(rgb, 0, 255), np.clip(roughness, 0, 1), height


def _seal(array):
    return np.pad(array, ((0, 1), (0, 1)) + ((0, 0),) * (array.ndim - 2), mode="wrap")


def _normal(height):
    pixel_metres = TILE_METRES / height.shape[0]
    du = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) / (2 * pixel_metres)
    # PNG rows increase downward, opposite to tangent +V; this is OpenGL +Y.
    dv_image = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) / (2 * pixel_metres)
    xyz = np.stack((-du, dv_image, np.ones_like(height)), axis=-1)
    xyz /= np.linalg.norm(xyz, axis=-1, keepdims=True)
    return np.rint(np.clip(_seal(xyz) * .5 + .5, 0, 1) * 255).astype(np.uint8)


def _seams(array):
    return {"opposite_rows_equal": bool(np.array_equal(array[0], array[-1])),
            "opposite_columns_equal": bool(np.array_equal(array[:, 0], array[:, -1]))}


def generate_materials(output_dir, size=512, seed=20261019):
    """Write six PNGs and material_manifest.json; return relative-file metadata.

    This never touches existing town textures unless deliberately given their
    exact directory. Inputs/output bytes are deterministic on the same NumPy/
    Pillow implementation; records include versions rather than claiming cross-
    platform bitwise floating-point identity.
    """
    if not isinstance(size, int) or isinstance(size, bool) or not 32 <= size <= 4096:
        raise ValueError("size must be an integer from 32 through 4096")
    if not isinstance(seed, int) or isinstance(seed, bool) or seed < 0:
        raise ValueError("seed must be a nonnegative integer")
    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema": "living_town.original_refinement_materials.v1",
        "generator": "tools/asset_refinement/materials.py",
        "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "source": "Original deterministic mathematical synthesis; no external media, AI inference or model weights",
        "seed": seed,
        "numpy_version": np.__version__, "pillow_version": Image.__version__,
        "normal_convention": "OpenGL tangent-space +Y",
        "normal_derivation": "Periodic central height differences in metres; image rows point opposite to tangent +V",
        "edge_policy": "Periodic U/V; duplicated final edge pixels match the opposite edges exactly",
        "materials": {},
    }
    for index, family in enumerate(FAMILIES):
        rng = np.random.default_rng(np.random.SeedSequence([seed, index]))
        rgb, roughness, height = _finish(family, size, rng)
        arrays = {"basecolor": np.rint(_seal(rgb)).astype(np.uint8),
                  "roughness": np.rint(_seal(roughness) * 255).astype(np.uint8),
                  "normal": _normal(height)}
        maps = {}
        for kind, array in arrays.items():
            checks = _seams(array)
            if not all(checks.values()):
                raise RuntimeError(f"{family}/{kind}: periodic edge check failed")
            filename = f"{family}_{kind}.png"
            target = output / filename
            Image.fromarray(array).save(target, optimize=True)
            maps[kind] = {"file": filename, "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                          "dimensions": [size, size], "channels": 1 if array.ndim == 2 else 3,
                          "color_space": "sRGB" if kind == "basecolor" else "Non-Color",
                          "seam_checks": checks}
        record = {
            "tile_size_metres": TILE_METRES,
            "palette_base_srgb": "#976f41" if family == "cabinet_oak" else "#848479",
            "description": ("Warm rubbed continuous cabinet oak grain, without plank joints" if family == "cabinet_oak"
                            else "Continuous fine-mineral honed granite, without mortar or slab joints"),
            "lighting_baked": False, "metallic": 0.0,
            "roughness_range": [round(float(roughness.min()), 6), round(float(roughness.max()), 6)],
            "height_range_metres": [round(float(height.min()), 9), round(float(height.max()), 9)],
            "maps": maps,
        }
        # Plain aliases make this usable by the existing town-style image loader.
        record.update({kind: entry["file"] for kind, entry in maps.items()})
        manifest["materials"][family] = record
    (output / "material_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--size", default=512, type=int)
    parser.add_argument("--seed", default=20261019, type=int)
    args = parser.parse_args()
    manifest = generate_materials(args.output, args.size, args.seed)
    print(json.dumps({"status": "PASS", "output": str(args.output.resolve()),
                      "materials": list(manifest["materials"]), "size": args.size, "seed": args.seed}))


if __name__ == "__main__":
    main()
