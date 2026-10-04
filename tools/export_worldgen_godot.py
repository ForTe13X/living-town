#!/usr/bin/env python3
"""Export a frozen WorldPackage and the read-only loader into a clean Godot project."""
import argparse
import json
import shutil
from pathlib import Path

import worldgen_catalog

def main():
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--package", type=Path, help="WorldPackage/1 JSON file")
    source.add_argument("--catalog-root", type=Path, help="Authoring catalog root; resolves the active or selected immutable build")
    parser.add_argument("--world-id", help="Required with --catalog-root")
    parser.add_argument("--revision", type=int, help="Optional historical revision; defaults to the active catalog head")
    parser.add_argument("--output", required=True, help="New or existing Godot project directory")
    parser.add_argument("--blender-preview-dir", help="Optional directory with worldgen.blender-proxy/1 manifest and matching GLB")
    args = parser.parse_args()
    if args.package and (args.world_id or args.revision is not None):
        raise SystemExit("E_SOURCE_OPTIONS: --world-id/--revision are only valid with --catalog-root")
    if args.catalog_root and not args.world_id:
        raise SystemExit("E_CATALOG_WORLD: --world-id is required with --catalog-root")
    repo = Path(__file__).resolve().parents[1]
    source_game = repo / "game"
    output = Path(args.output).resolve()
    if args.package:
        package_path = args.package.resolve()
        package = json.loads(package_path.read_text(encoding="utf-8"))
        source_package = package_path.name
    else:
        if not args.world_id:
            raise SystemExit("E_CATALOG_WORLD: --world-id is required with --catalog-root")
        try:
            selected = worldgen_catalog.resolve(args.catalog_root.resolve(), args.world_id, args.revision)
        except worldgen_catalog.CatalogError as exc:
            raise SystemExit(f"E_CATALOG_RESOLVE: {exc}") from exc
        package = selected["package"]
        source_package = f"catalog:{selected['world_id']}@{selected['revision']}"
    try:
        worldgen_catalog.validate_package(package)
    except worldgen_catalog.CatalogError as exc:
        raise SystemExit(str(exc)) from exc
    blender_asset = None
    if args.blender_preview_dir:
        preview_dir = Path(args.blender_preview_dir).resolve()
        preview_manifest_path = preview_dir / "manifest.json"
        if not preview_manifest_path.is_file():
            raise SystemExit("E_BLENDER_PREVIEW_MANIFEST: missing manifest.json")
        preview_manifest = json.loads(preview_manifest_path.read_text(encoding="utf-8"))
        if preview_manifest.get("schema") != "worldgen.blender-proxy/1":
            raise SystemExit("E_BLENDER_PREVIEW_SCHEMA: expected worldgen.blender-proxy/1")
        entry = next((item for item in preview_manifest.get("worlds", []) if item.get("world_id") == package.get("world_id")), None)
        if not entry or entry.get("semantic_sha256") != package.get("digests", {}).get("semantic_sha256"):
            raise SystemExit("E_BLENDER_PREVIEW_SOURCE: proxy manifest does not match this package identity and semantic digest")
        blender_asset = (preview_dir / str(entry.get("glb", ""))).resolve()
        if preview_dir not in blender_asset.parents or blender_asset.suffix.lower() != ".glb" or not blender_asset.is_file():
            raise SystemExit("E_BLENDER_PREVIEW_PATH: GLB must be a file contained in the preview directory")
    manifest_path = output / "export_manifest.json"
    if output.exists() and any(output.iterdir()):
        if not manifest_path.is_file():
            raise SystemExit("E_OUTPUT_NOT_EMPTY: refusing to overwrite a directory without this exporter's manifest")
        existing = json.loads(manifest_path.read_text(encoding="utf-8"))
        if existing.get("schema") != "worldgen.godot-export/1":
            raise SystemExit("E_OUTPUT_OWNERSHIP: output directory is not a WorldPackage export")
    target_core = output / "addons" / "worldgen" / "core"
    target_core.mkdir(parents=True, exist_ok=True)
    for name in ("worldgen_canonical.gd", "worldgen_package_validator.gd", "worldgen_package_loader.gd", "worldgen_validate_package_cli.gd", "world_package_scene_builder.gd", "world_package_spatial_queries.gd"):
        shutil.copy2(source_game / "addons" / "worldgen" / "core" / name, target_core / name)
    tests_dir = output / "tests"
    tests_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source_game / "addons" / "worldgen" / "tests" / "worldgen_package_validator_test.gd", tests_dir / "worldgen_package_validator_test.gd")
    shutil.copy2(source_game / "addons" / "worldgen" / "templates" / "minimal_viewer.gd", output / "minimal_viewer.gd")
    shutil.copy2(source_game / "addons" / "worldgen" / "templates" / "minimal_viewer.tscn", output / "minimal_viewer.tscn")
    shutil.copy2(source_game / "addons" / "worldgen" / "templates" / "proxy_3d_viewer.gd", output / "proxy_3d_viewer.gd")
    shutil.copy2(source_game / "addons" / "worldgen" / "templates" / "proxy_3d_viewer.tscn", output / "proxy_3d_viewer.tscn")
    worldgen_catalog.atomic_export(package, output / "world.world.json")
    if blender_asset:
        asset_dir = output / "assets"
        asset_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(blender_asset, asset_dir / "worldgen_proxy.glb")
    main_scene = "res://proxy_3d_viewer.tscn" if blender_asset else "res://minimal_viewer.tscn"
    (output / "project.godot").write_text(f'''config_version=5

[application]
config/name="WorldPackage Viewer"
run/main_scene="{main_scene}"
config/features=PackedStringArray("4.6", "GL Compatibility")

[display]
window/size/viewport_width=960
window/size/viewport_height=640

[rendering]
renderer/rendering_method="gl_compatibility"
''', encoding="utf-8")
    export_manifest = {"schema": "worldgen.godot-export/1", "world_id": package["world_id"], "source_package": source_package, "semantic_sha256": package["digests"]["semantic_sha256"], "presentation_sha256": package["digests"]["presentation_sha256"], "private_game_dependency": False, "authoring_tools_required_at_runtime": False}
    if not args.package:
        export_manifest["catalog_revision"] = selected["revision"]
        export_manifest["catalog_build_id"] = selected["build_id"]
    if blender_asset:
        export_manifest["blender_proxy_asset"] = "assets/worldgen_proxy.glb"
        export_manifest["blender_proxy_production_art"] = False
    manifest_path.write_text(json.dumps(export_manifest, indent=2) + "\n", encoding="utf-8")
    (output / "README.md").write_text(f'''# {package["world_id"]} — WorldPackage Godot project

This folder is a standalone Godot 4 project generated from `WorldPackage/1`.

- `world.world.json` is the immutable semantic and presentation package.
- `addons/worldgen/core/worldgen_validate_package_cli.gd` runs the included read-only package oracle and emits a candidate-digest-bound validation receipt.
- `tests/worldgen_package_validator_test.gd` contains coastal shoreline/crossing and massing mutation cases; for the other recipe kinds it verifies the base package and reports that coastal-only mutations were skipped.
- `proxy_3d_viewer.tscn` creates an editable 3D preview scene and loads the optional Blender GLB.
- `minimal_viewer.tscn` previews the semantic layout as native Godot 2D nodes.
- `addons/worldgen/core/world_package_scene_builder.gd` builds IDs, roads, parcels, segmented building footprints/collisions, rooms, portals, and affordance markers from package data. Coastal L/U footprints keep their authored voids, and crossing roads retain their intermediate route points.
- `addons/worldgen/core/world_package_spatial_queries.gd` exposes detached read-only room, portal, affordance, building, and road queries for a host game adapter. Its access profile is package policy only; the host game still decides legal actions and owns reservations and state changes.

Example host-side setup:

```gdscript
var loaded := WorldGenPackageLoader.new().load_package("res://world.world.json")
if loaded.ok:
    var spatial := WorldPackageSpatialQueries.new()
    var configured := spatial.configure(loaded.package)
    if configured.ok:
        var nearby := spatial.query_affordances_near(Vector2i(6, 4), 8, "public")
```

The Blender GLB is semantic proxy geometry (`production_art: false`), included for layout iteration. It has no production building kit or simulation behavior. Replace or augment it with reviewed assets as development continues.

To preview the 2D node hierarchy, change `run/main_scene` in `project.godot` to `res://minimal_viewer.tscn`.
''', encoding="utf-8")
    print(f"WORLDGEN_GODOT_EXPORT_OK world={package['world_id']} output={output}")


if __name__ == "__main__":
    main()
