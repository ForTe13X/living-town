"""Bake source-bound plaster scans and authored facade-scale limewash context.

This is image authoring, not image/model inference. The fine photographed scan
keeps its physical repeat. Broad paint variation, sheltered sill runoff and a
small authored relief field are baked into ordinary, portable PBR images.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image


DEFAULT_WINDOWS = ((-2.55, 3.975, 1.08, 1.55), (0, 3.975, 1.08, 1.55),
                   (2.55, 3.975, 1.08, 1.55), (-2.55, .675, 2.05, 1.95),
                   (2.55, .675, 2.05, 1.95))
HEIGHT_MIN_M, HEIGHT_MAX_M = .0007, .004


def _sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def _linear(value):
    value = np.asarray(value, dtype=np.float32)
    return np.where(value <= .04045, value / 12.92,
                    ((value + .055) / 1.055) ** 2.4)


def _srgb(value):
    value = np.clip(value, 0, 1)
    return np.where(value <= .0031308, value * 12.92,
                    1.055 * value ** (1 / 2.4) - .055)


def _noise(rng, size, width_m, height_m, spacing_m):
    """Aperiodic smooth noise with a declared physical control-point spacing."""
    shape = (max(4, math.ceil(height_m / spacing_m) + 3),
             max(4, math.ceil(width_m / spacing_m) + 3))
    grid = rng.normal(0, 1, shape).astype(np.float32)
    field = np.asarray(Image.fromarray(grid).resize((size, size), Image.Resampling.BICUBIC),
                       dtype=np.float32).copy()
    field -= field.mean()
    field /= max(float(field.std()) * 2, .001)
    return np.clip(field, -1, 1)


def _height_normal(height, width_m, height_m):
    """OpenGL +Y normals; image rows point DOWN while facade tangent V is UP."""
    rows, columns = height.shape
    down, dx = np.gradient(height, height_m / (rows - 1), width_m / (columns - 1))
    normal = np.stack((-dx, down, np.ones_like(height)), axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    return normal


def _tile_rows(source, start, stop, size, width_m, height_m, repeat):
    """Bilinearly repeat a photographed map in metres, independent of facade size."""
    h, w = source.shape[:2]
    px = np.mod(np.linspace(0, width_m, size, dtype=np.float32) / repeat[0], 1) * w
    z = np.linspace(height_m, 0, size, dtype=np.float32)[start:stop]
    py = np.mod(-z / repeat[1], 1) * h
    ix, iy = np.floor(px).astype(int), np.floor(py).astype(int)
    fx, fy = px - ix, py - iy
    if source.ndim == 3:
        fx, fy = fx[None, :, None], fy[:, None, None]
    else:
        fx, fy = fx[None, :], fy[:, None]
    a = source[iy[:, None] % h, ix[None, :] % w]
    b = source[iy[:, None] % h, (ix[None, :] + 1) % w]
    c = source[(iy[:, None] + 1) % h, ix[None, :] % w]
    d = source[(iy[:, None] + 1) % h, (ix[None, :] + 1) % w]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def _settings(size, seed, width_m, height_m, windows, palette_srgb):
    if isinstance(size, bool) or not isinstance(size, int) or not 128 <= size <= 4096:
        raise ValueError("size must be an integer from 128 to 4096")
    if isinstance(seed, bool) or not isinstance(seed, int) or seed < 0:
        raise ValueError("seed must be a nonnegative integer")
    dimensions = tuple(float(v) for v in (width_m, height_m))
    if not all(math.isfinite(v) and .5 <= v <= 50 for v in dimensions):
        raise ValueError("facade dimensions must be finite metres from .5 to 50")
    windows = DEFAULT_WINDOWS if windows is None else windows
    parsed = []
    for row in windows:
        values = tuple(float(v) for v in row)
        if len(values) != 4 or not all(math.isfinite(v) for v in values):
            raise ValueError("windows must contain (centre_x, sill_z, width, height) in metres")
        if values[2] <= 0 or values[3] <= 0 or values[1] < 0:
            raise ValueError("window widths/heights must be positive and sills nonnegative")
        parsed.append(values)
    palette = np.asarray((224, 218, 204) if palette_srgb is None else palette_srgb,
                         dtype=np.float32)
    if palette.shape != (3,) or not np.all(np.isfinite(palette)) or np.any((palette < 0) | (palette > 255)):
        raise ValueError("palette_srgb needs three finite values from 0 to 255")
    return dimensions, parsed, palette


def generate(output_dir, scan_library_manifest, size=4096, seed=20261020, *,
             width_m=8.6, height_m=6.5, windows=None, palette_srgb=None):
    """Return/write a manifest and four baked facade maps in a NEW directory.

    ``windows`` contains ``(centre_x_m, sill_z_m, width_m, height_m)`` tuples.
    x is centred on the facade, z is height above the ground. PNG top is z=max;
    UV=(0,0) is the bottom-left. Maps cover the WHOLE facade exactly once.
    ``facade_height.png`` is uint16; decode using the manifest's height_encoding.
    It is an authored 0.7–4 mm field, NOT a measured/scanned displacement map.
    Use a negative Y offset for a front wall whose outward direction is -Y.
    """
    (width_m, height_m), windows, palette = _settings(
        size, seed, width_m, height_m, windows, palette_srgb)
    output = Path(output_dir).resolve()
    if output.exists():
        raise FileExistsError(output)
    library_path = Path(scan_library_manifest).resolve(strict=True)
    library = json.loads(library_path.read_text(encoding="utf-8"))
    if library.get("schema") != "living_town.scanned_pbr_library.v1":
        raise ValueError("Expected a prepared scanned PBR library manifest")
    asset_id = library["roles"]["plaster"]
    asset = library["materials"][asset_id]
    if asset.get("license") != "CC0-1.0":
        raise ValueError("This bake accepts only an explicitly CC0-1.0 plaster source")
    if "OpenGL" not in asset.get("normal_convention", "") or "+Y" not in asset["normal_convention"]:
        raise ValueError("Source normal must declare OpenGL tangent-space +Y")
    repeat = tuple(float(v) for v in asset["repeat_metres"])
    if len(repeat) != 2 or not all(math.isfinite(v) and v > 0 for v in repeat):
        raise ValueError("Source repeat must be two positive physical dimensions")
    sources, source_records = {}, {}
    for role in ("basecolor", "roughness", "normal"):
        row = asset["maps"][role]
        path = (library_path.parent / row["path"]).resolve(strict=True)
        if not path.is_relative_to(library_path.parent) or _sha(path) != row["sha256"]:
            raise ValueError("Prepared source path or hash differs: " + role)
        with Image.open(path) as image:
            converted = image.convert("L" if role == "roughness" else "RGB")
            if list(converted.size) != row["dimensions"]:
                raise ValueError("Prepared source dimensions differ: " + role)
            # Physical repeat can be much smaller than the entire facade.
            # Prefilter to the final texel density rather than sparsely sampling
            # a 2K source every fourth texel and introducing artificial aliasing.
            filtered_size = (min(converted.width, max(8, round(size * repeat[0] / width_m))),
                             min(converted.height, max(8, round(size * repeat[1] / height_m))))
            if converted.size != filtered_size:
                converted = converted.resize(filtered_size, Image.Resampling.LANCZOS)
            sources[role] = np.asarray(converted, dtype=np.float32) / 255
        source_records[role] = {"path": path.as_posix(), "sha256": row["sha256"],
                                "source_sha256": row.get("source_sha256"),
                                "dimensions": row["dimensions"],
                                "filtered_tile_dimensions": list(filtered_size)}

    # At 4K these fields use float32 and the source is sampled in 256-row blocks.
    # No tile enlargement is used to pretend that a fine scan is a macro texture.
    rng = np.random.default_rng(seed)
    small = _noise(rng, size, width_m, height_m, .55)
    medium = _noise(rng, size, width_m, height_m, 1.3)
    broad = _noise(rng, size, width_m, height_m, 2.8)
    tone = np.clip(.17 * small + .12 * medium + .065 * broad, -.29, .25)
    warmth = _noise(rng, size, width_m, height_m, .95)
    # Relief remains shallow even at panel scale; it is authored independently
    # from the scan rather than estimated from diffuse illumination.
    relief = .62 * _noise(rng, size, width_m, height_m, .20) + .27 * small + .11 * medium
    relief -= relief.min()
    relief /= max(float(relief.max()), .001)
    height = HEIGHT_MIN_M + relief * (HEIGHT_MAX_M - HEIGHT_MIN_M)
    del relief
    x = np.linspace(-width_m / 2, width_m / 2, size, dtype=np.float32)[None, :]
    z = np.linspace(height_m, 0, size, dtype=np.float32)[:, None]
    stain = np.broadcast_to(.095 * np.exp(-z / .22), (size, size)).copy()
    stain += .045 * np.exp(-((height_m - .12 - z) / .13) ** 2) * (.78 + .22 * broad)
    for centre, sill, width, _ in windows:
        below = sill - z
        under_sill = (below >= 0) * np.exp(-np.maximum(below, 0) / .43)
        sill_band = np.exp(-((x - centre) / (width * .54)) ** 6)
        stain += .045 * sill_band * under_sill
        # Narrower runoff starts near the real sill ends, with softly wandering
        # edges; it is neither a painted shadow nor a repeating grunge stripe.
        for sign in (-1, 1):
            stream_x = centre + sign * width * .40 + .025 * np.sin(np.maximum(below, 0) * 13 + centre)
            stream = np.exp(-((x - stream_x) / .055) ** 2)
            stain += .085 * stream * (below >= 0) * np.exp(-np.maximum(below, 0) / .72)
    stain *= np.clip(1 + .12 * small, .85, 1.15)

    context_normals = _height_normal(height, width_m, height_m)
    basecolor = np.empty((size, size, 3), dtype=np.uint8)
    roughness = np.empty((size, size), dtype=np.uint8)
    normal_png = np.empty((size, size, 3), dtype=np.uint8)
    linear_source = _linear(sources["basecolor"])
    shift = _linear(palette / 255) - linear_source.mean(axis=(0, 1))
    for start in range(0, size, 256):
        stop = min(start + 256, size)
        scan = _tile_rows(linear_source, start, stop, size, width_m, height_m, repeat)
        local_tone = tone[start:stop] - stain[start:stop]
        colour = (scan + shift) * (1 + local_tone[..., None])
        # Restrained warm/cool replastering; still a pale mineral paint family.
        colour += warmth[start:stop, :, None] * np.array([.014, .002, -.016], dtype=np.float32)
        basecolor[start:stop] = np.rint(_srgb(colour) * 255).clip(0, 255).astype(np.uint8)
        rough = _tile_rows(sources["roughness"], start, stop, size, width_m, height_m, repeat)
        rough += .025 * medium[start:stop] + .06 * stain[start:stop]
        roughness[start:stop] = np.rint(np.clip(rough, .58, 1) * 255).astype(np.uint8)
        photographic = _tile_rows(sources["normal"], start, stop, size, width_m, height_m, repeat) * 2 - 1
        photographic /= np.maximum(np.linalg.norm(photographic, axis=-1, keepdims=True), .001)
        # Compose the photographed and physical context slopes. Positive normal
        # Y means height increases DOWN the stored image (towards negative V).
        authored = context_normals[start:stop]
        slopes = photographic[..., :2] / np.maximum(photographic[..., 2:3], .1)
        slopes += authored[..., :2] / authored[..., 2:3]
        combined = np.concatenate((slopes, np.ones((*slopes.shape[:2], 1), dtype=np.float32)), axis=-1)
        combined /= np.linalg.norm(combined, axis=-1, keepdims=True)
        normal_png[start:stop] = np.rint((combined * .5 + .5) * 255).clip(0, 255).astype(np.uint8)

    height_png = np.rint((height - HEIGHT_MIN_M) / (HEIGHT_MAX_M - HEIGHT_MIN_M) * 65535).clip(0, 65535).astype(np.uint16)
    output.mkdir(parents=True, exist_ok=False)
    images = {"basecolor": basecolor, "roughness": roughness, "normal": normal_png, "height": height_png}
    records = {}
    for role, pixels in images.items():
        path = output / ("facade_" + role + ".png")
        Image.fromarray(pixels).save(path)
        records[role] = {"path": path.name, "sha256": _sha(path), "dimensions": [size, size],
                         "color_space": "sRGB" if role == "basecolor" else "Non-Color",
                         "bit_depth": 16 if role == "height" else 8}
    downsample = np.asarray(Image.fromarray(basecolor).resize((950, 600), Image.Resampling.LANCZOS), dtype=np.float32)
    manifest = {
        "schema": "living_town.contextual_wall_bake.v1", "status": "BAKED_REQUIRES_RENDER_REVIEW",
        "generator_sha256": _sha(Path(__file__)), "ai_inference_executed": False, "seed": seed,
        "source_library_sha256": _sha(library_path), "source_asset": asset_id,
        "source_asset_url": asset.get("asset_url"), "source_license": asset["license"],
        "source_provenance_sha256": asset.get("source_provenance_sha256"), "sources": source_records,
        "authored_context": True, "scan_repeat_metres": list(repeat),
        "facade_dimensions_metres": [width_m, height_m], "palette_srgb": palette.tolist(),
        "windows_api": "(centre_x_m, sill_z_m, width_m, height_m); x centred on facade, z above ground",
        "windows": [list(row) for row in windows],
        "image_coordinates": "Top image row z=height_m; bottom z=0. Facade image UV=(x/width_m+.5,z/height_m).",
        "metric_uv_mapping": "For MetricUV=((x+width_m/2)/2,z/2), use Mapping scale=(2/width_m,2/height_m,1).",
        "normal_convention": "OpenGL tangent-space +Y; photographed normal plus authored physical height slopes, normalized",
        "height_encoding": {"minimum_metres": HEIGHT_MIN_M, "maximum_metres": HEIGHT_MAX_M,
                            "decode": "minimum_metres + uint16_value/65535*(maximum_metres-minimum_metres)",
                            "surface_direction": "For front outward -Y, y=original_y-decoded_height_m",
                            "physical_scale_authority": "ARTIST_AUTHORED_NOT_MEASURED",
                            "coarse_mesh_note": "Shared-vertex displacement represents coarse relief. Normal includes the full authored relief plus fine scan; reduce normal strength if also displacing the mesh to avoid overstating relief."},
        "recipe": {"macro_control_spacing_metres": [.55, 1.3, 2.8],
                   "relief_control_spacing_metres": .20, "linear_tone_clamp": [-.29, .25],
                   "style": "Pale maintained limewash, restrained warm/cool replastering, sill runoff, eave shelter and lower-wall grime. No rust, abandonment or uniform overlay.",
                   "source_normal": "Photographic OpenGL scan retained at original physical repeat; no diffuse-to-normal inference.",
                   "roughness": "Photographed roughness plus small authored mineral/context variation, clamped [.58,1]."},
        "image_metrics": {"downsample_dimensions": [950, 600],
                          "downsample_rgb_standard_deviation_8bit": downsample.std(axis=(0, 1)).tolist(),
                          "downsample_luminance_p02_p98_8bit": np.quantile(downsample.mean(axis=-1), [.02, .98]).tolist(),
                          "authored_runoff_max_linear_darkening": float(stain.max())},
        "maps": records,
    }
    (output / "wall_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scan-library-manifest", type=Path, required=True)
    parser.add_argument("--size", type=int, default=4096)
    parser.add_argument("--seed", type=int, default=20261020)
    parser.add_argument("--width-m", type=float, default=8.6)
    parser.add_argument("--height-m", type=float, default=6.5)
    args = parser.parse_args()
    generate(args.output, args.scan_library_manifest, args.size, args.seed,
             width_m=args.width_m, height_m=args.height_m)
