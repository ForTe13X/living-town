"""Prepare four owned Blender views and offline MIT workflow variants.

No models, installers, network requests or ComfyUI queue operations are invoked.
The raw renders remain intact. Outputs use white-composited RGB for LoadImage's
IMAGE socket and retain original alpha for any separately audited MASK consumer.
"""
import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path

from PIL import Image

try:
    from .workflows import build_variants
except ImportError:
    from workflows import build_variants

VIEWS = ("front", "left", "back", "right")


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def prepare(hero, output, workflows):
    hero, output, workflows = (Path(p).resolve() for p in (hero, output, workflows))
    if output.exists() or workflows.exists() or output.is_relative_to(workflows):
        raise FileExistsError("Prepared views and workflow destinations must be new, separate directories")
    manifest_path = hero / "hero_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("ai_inference_executed") is not False:
        raise ValueError("Expected offline original-asset hero")
    if [v["name"] for v in manifest["conditioning_views"]] != list(VIEWS):
        raise ValueError("Expected front, left, back, right camera order")
    images = []
    for name, row in zip(VIEWS, manifest["conditioning_views"]):
        source = hero / "input" / (name + ".png")
        if row["image"] != "input/" + name + ".png" or sha(source) != row["sha256"]:
            raise ValueError("Owned render source hash/path mismatch: " + name)
        with Image.open(source) as image:
            image.load()
            if image.mode != "RGBA" or image.size != (1024, 1024):
                raise ValueError("Expected 1024 square RGBA: " + name)
            alpha = image.getchannel("A")
            if alpha.getextrema() != (0, 255):
                raise ValueError("Expected visible object and transparent background: " + name)
            composite = Image.alpha_composite(Image.new("RGBA", image.size, "white"), image)
            composite.putalpha(alpha)
            images.append((source, composite))
    source_mesh = hero / "input/counter.glb"
    if sha(source_mesh) != manifest["files"]["input\\counter.glb" if "input\\counter.glb" in manifest["files"] else "input/counter.glb"]["sha256"]:
        raise ValueError("Counter source hash mismatch")
    output.mkdir(parents=True, exist_ok=False)
    sheet = Image.new("RGBA", (4096, 1024))
    rows = []
    for index, (name, (source, image)) in enumerate(zip(VIEWS, images)):
        target = output / (name + ".png")
        image.save(target)
        sheet.paste(image, (index * 1024, 0))
        rows.append({"name": name, "source_path": Path(os.path.relpath(source, output)).as_posix(),
                     "source_sha256": sha(source), "path": target.name, "sha256": sha(target),
                     "dimensions": [1024, 1024], "mode": "RGBA"})
    sheet_path = output / "turnaround_sheet.png"
    sheet.save(sheet_path)
    mesh = output / "counter.glb"
    shutil.copyfile(source_mesh, mesh)
    result = {"schema": "living_town.owned_view_preparation.v1",
              "source_hero_manifest_sha256": sha(manifest_path), "view_order": list(VIEWS),
              "ai_inference_executed": False, "views": rows,
              "mesh": {"path": mesh.name, "source_path": Path(os.path.relpath(source_mesh, output)).as_posix(), "sha256": sha(mesh)},
              "sheet": {"path": sheet_path.name, "sha256": sha(sheet_path), "dimensions": [4096, 1024]},
              "rgb_background": "White composite; original alpha retained; ComfyUI IMAGE takes RGB and MASK is separate.",
              "atlas_validated": False,
              "limitations": ["Views are prepared inputs, not generated AI outputs.", "Repeating metric UVs are not a validated unique 0..1 atlas."]}
    (output / "preparation_manifest.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    build_variants(workflows, mesh, output / "front.png", sheet_path, atlas_validated=False)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hero", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--workflows", type=Path, required=True)
    args = parser.parse_args(argv)
    prepare(args.hero, args.output, args.workflows)
    print(json.dumps({"status": "PREPARED_NOT_EXECUTED", "output": str(args.output), "ai_inference_executed": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
