"""Prepare 8-bit game PBR copies of separately provenanced CC0 scan maps.

Untouched 16-bit authoring files and source license records remain in --sources.
This is format/resolution preparation, not model generation or a PBR inference.
"""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image
import numpy as np


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def decode8(image, role):
    mode = "L" if role == "roughness" else "RGB"
    if image.mode.startswith("I;16") or image.mode == "I":
        normalized = np.rint(np.asarray(image, dtype=np.float64) / 257).clip(0, 255).astype(np.uint8)
        return Image.fromarray(normalized).convert(mode)
    return image.convert(mode)


def paint_plaster(image):
    """Bake pale paint color while retaining scanned albedo detail and all PBR."""
    pixels = np.asarray(image, dtype=np.float64) / 255
    linear = np.where(pixels <= .04045, pixels / 12.92, ((pixels + .055) / 1.055) ** 2.4)
    target = np.array([224, 218, 204], dtype=np.float64) / 255
    target = np.where(target <= .04045, target / 12.92, ((target + .055) / 1.055) ** 2.4)
    painted = np.clip(target + .65 * (linear - linear.mean(axis=(0, 1))), 0, 1)
    srgb = np.where(painted <= .0031308, painted * 12.92, 1.055 * painted ** (1 / 2.4) - .055)
    return Image.fromarray(np.rint(srgb * 255).clip(0, 255).astype(np.uint8))


def prepare(sources, output, size=2048, stone=None, floor=None, painted=False, honed=False):
    sources, output = Path(sources).resolve(), Path(output).resolve()
    if output.exists():
        raise FileExistsError(output)
    if size < 256 or size > 4096:
        raise ValueError("Expected a game texture size between 256 and 4096")
    records = []
    for path in sorted(sources.glob("*/PROVENANCE.json")):
        source = json.loads(path.read_text(encoding="utf-8"))
        if source.get("status") != "PASS" or source.get("license") != "CC0-1.0":
            raise ValueError("Unverified scan: " + str(path))
        for name in ("Diffuse", "Rough", "Normal"):
            row = source["maps"].get(name)
            if name == "Normal" and row is None:
                row = source["maps"].get("nor_gl") or source["maps"].get("NormalGL")
            if row is None:
                # Poly Haven names this exact source channel nor_gl.
                row = next((v for k, v in source["maps"].items() if name == "Normal" and "nor_gl" in v["file"]), None)
            if row is None or sha(path.parent / row["file"]) != row["sha256"]:
                raise ValueError("Source map hash missing or different: " + name)
        records.append((path, source))
    if not records:
        raise ValueError("No fully verified CC0 source sets")
    output.mkdir(parents=True, exist_ok=False)
    materials = {}
    for path, source in records:
        asset = source["asset_id"]
        folder = output / asset
        folder.mkdir()
        images = {}
        cut_roughness = None
        for role, source_channel in (("basecolor", "Diffuse"), ("roughness", "Rough"), ("normal", "nor_gl")):
            row = source["maps"][source_channel]
            origin = path.parent / row["file"]
            with Image.open(origin) as image:
                image.load()
                # Pillow decodes RGB 16-bit PNGs to RGB8; record that conversion.
                target = decode8(image, role)
                if target.size != (size, size):
                    target = target.resize((size, size), Image.Resampling.LANCZOS)
                if painted and asset == "white_plaster_02" and role == "basecolor":
                    target = paint_plaster(target)
                if honed and asset == stone and role == "roughness":
                    raw = np.asarray(target, dtype=np.float64) / 255
                    target = Image.fromarray(np.rint((.38 + .5 * raw) * 255).clip(0, 255).astype(np.uint8))
                    cut = Image.fromarray(np.rint((.72 + .28 * raw) * 255).clip(0, 255).astype(np.uint8))
                    cut_path = folder / "cut_roughness.png"
                    cut.save(cut_path)
                    cut_roughness = {"path": cut_path.relative_to(output).as_posix(), "sha256": sha(cut_path),
                                     "source_sha256": row["sha256"], "dimensions": [size, size], "color_space": "Non-Color"}
                destination = folder / (role + ".png")
                target.save(destination)
            images[role] = {"path": destination.relative_to(output).as_posix(), "sha256": sha(destination),
                            "dimensions": [size, size], "source_sha256": row["sha256"],
                            "color_space": "sRGB" if role == "basecolor" else "Non-Color"}
        (folder / "SOURCE_PROVENANCE.json").write_bytes(path.read_bytes())
        materials[asset] = {"repeat_metres": source["physical_dimensions_metres"], "maps": images,
                            "license": "CC0-1.0", "asset_url": source["asset_url"],
                            "source_provenance_sha256": sha(path),
                            "normal_convention": "OpenGL tangent-space +Y",
                            "source_kind": source.get("source_kind", source.get("creation_method", "See source provenance")),
                            "physical_scale_authority": source.get("physical_scale_authority", "Current official API dimensions"),
                            "finish_recipe": "Authored honed counter roughness=.38+.5*source; no claim of measured roughness" if honed and asset == stone else "Source finish retained",
                            "painted_albedo": painted and asset == "white_plaster_02",
                            "paint_recipe": "Linear RGB mean shifted to sRGB224,218,204 with .65 source linear deviation. Photographed normal and roughness unchanged." if painted and asset == "white_plaster_02" else None,
                            "preparation": "16-bit originals retained separately; RGB8/L8 PNG copies; Lanczos diffuse downsample when needed. Normal source resolution retained, no RGB-to-normal estimation."}
        if cut_roughness is not None:
            materials[asset + "_cut"] = {**materials[asset], "maps": {**images, "roughness": cut_roughness},
                                         "finish_recipe": "Authored cut-stone trim roughness=.72+.28*source; source normal unchanged"}
    roles = {"cabinet_oak": "oak_veneer_01", "plaster": "white_plaster_02"}
    if stone is not None: roles["honed_granite"] = stone
    if stone is not None and honed: roles["cut_granite"] = stone + "_cut"
    if floor is not None: roles["interior_floor"] = floor
    if any(asset not in materials for asset in roles.values()):
        raise ValueError("A requested material role has no verified source")
    result = {"schema": "living_town.scanned_pbr_library.v1", "generator_sha256": sha(Path(__file__)), "roles": roles,
              "ai_inference_executed": False, "materials": materials}
    (output / "library_manifest.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--size", type=int, default=2048)
    parser.add_argument("--stone", help="Source asset ID to bind to the continuous counter stone")
    parser.add_argument("--floor", help="Source asset ID to bind to the indoor cafe floor")
    parser.add_argument("--paint-plaster", action="store_true", help="Bake pale limewash palette into the scan's basecolor")
    parser.add_argument("--hone-stone", action="store_true", help="Bake authored honed-counter and matte cut-trim roughness variants")
    args = parser.parse_args()
    result = prepare(args.sources, args.output, args.size, args.stone, args.floor, args.paint_plaster, args.hone_stone)
    print(json.dumps({"status": "PREPARED_CC0", "assets": list(result["materials"])}))
