"""Build source geometry with Python; optionally save/render in fresh background Blender."""

from pathlib import Path
import argparse, json, sys, hashlib, traceback

sys.dont_write_bytecode = True
if not __package__:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.mill_court.inputs import (
    PACKAGE,
    DEFAULT_PLAN,
    BLEND_FILENAME,
    load_inputs,
    compile_geometry,
    terrain_mesh,
)


def write(path, value):
    Path(path).write_text(
        json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n",
        encoding="utf-8",
    )


def binding(path):
    p = Path(path)
    with p.open("rb") as f:
        h = hashlib.file_digest(f, "sha256").hexdigest()
    return dict(path=str(p.resolve()), bytes=p.stat().st_size, sha256=h)


def arguments(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--floorplans", type=Path, default=DEFAULT_PLAN)
    p.add_argument("--site", type=Path, default=PACKAGE / "data/site.json")
    p.add_argument("--terrain", type=Path, default=PACKAGE / "data/terrain.json")
    p.add_argument("--views-json", type=Path, default=PACKAGE / "data/views.json")
    p.add_argument("--output", required=True, type=Path)
    p.add_argument(
        "--geometry-only",
        action="store_true",
        help="Standard-Python JSON build; no bpy import",
    )
    p.add_argument("--render", action="store_true")
    p.add_argument(
        "--view",
        action="append",
        help="Render only this bundled view ID; repeat as needed",
    )
    p.add_argument(
        "--cycles-backend",
        choices=("AUTO", "HIP", "OPTIX", "CUDA", "ONEAPI", "METAL"),
        default="AUTO",
    )
    p.add_argument("--cycles-device-name", default="")
    p.add_argument(
        "--cpu-render",
        action="store_true",
        help="Explicit CPU opt-in; GPU never silently falls back",
    )
    p.add_argument("--samples", type=int, default=64)
    p.add_argument("--width", type=int, default=1800)
    p.add_argument("--height", type=int, default=1200)
    p.add_argument("--render-threads", type=int, default=2)
    p.add_argument(
        "--export-geometry-glb",
        action="store_true",
        help="Provisional geometry-only GLB, with no exported materials/textures",
    )
    a = p.parse_args(argv)
    if a.geometry_only and (a.render or a.export_geometry_glb):
        p.error("--geometry-only cannot render or exportGLB")
    return a


def main(argv=None):
    a = arguments(argv)
    a.output = a.output.resolve()
    data, site, grid, views = load_inputs(a.floorplans, a.site, a.terrain, a.views_json)
    spec = compile_geometry(data, site)
    if a.view:
        unknown = set(a.view) - {v["id"] for v in views}
        if unknown:
            raise ValueError("Unknown view IDs: " + str(sorted(unknown)))
        views = [v for v in views if v["id"] in set(a.view)]
    if not a.geometry_only:
        import bpy

        if not bpy.app.background or bpy.data.filepath:
            raise RuntimeError(
                "Use factory-startup background Blender, with no existing .blend opened"
            )
    # Never delete, overwrite or reuse an output directory, even when it is empty.
    a.output.mkdir(parents=True, exist_ok=False)
    try:
        write(a.output / "COMPILED_GEOMETRY.json", spec)
        recipe = dict(
            status="PROCEDURAL_BLENDER_MASTER_NOT_BAKED_ENGINE_ASSET",
            floorplans=binding(a.floorplans),
            site=binding(a.site),
            terrain=binding(a.terrain),
            views_json=binding(a.views_json),
            selected_view_ids=[v["id"] for v in views],
            geometry_specs=len(spec["objects"]),
            furniture_assets=len(spec["furniture"]),
            portable_texture_bake_pending=True,
        )
        if a.geometry_only:
            write(a.output / "GENERATION.json", recipe)
            return recipe
        from tools.mill_court.blender_scene import build_scene
        from tools.mill_court import rendering
        from tools.mill_court.snapshot import state, canonical_sha

        scene, camera, camera_data = build_scene(
            bpy, spec, data, site, terrain_mesh(grid), recipe["floorplans"]["sha256"]
        )
        # A saved master is useful without a render device. GPU admission happens only for rendering.
        scene.render.engine = "CYCLES"
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.exposure = 0.1
        gpu = (
            rendering.configure(
                bpy,
                scene,
                a.cycles_backend,
                a.cycles_device_name,
                a.cpu_render,
                a.samples,
                a.width,
                a.height,
                a.render_threads,
            )
            if a.render
            else None
        )
        rendering.pose(camera, camera_data, views[0])
        bpy.context.view_layer.update()
        for m in list(bpy.data.materials):
            if m.users == 0:
                bpy.data.materials.remove(m)
        bpy.context.preferences.filepaths.save_version = 0
        before = state(bpy)
        write(a.output / "SAVED_SOURCE_STATE.json", before)
        blend = a.output / BLEND_FILENAME
        bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
        saved = {
            **binding(blend),
            "file": BLEND_FILENAME,
            "state_sha256": canonical_sha(before),
        }
        write(a.output / "SAVED_BLEND.json", saved)
        if a.export_geometry_glb:
            bpy.ops.object.select_all(action="DESELECT")
            for ob in scene.objects:
                ob.select_set(
                    ob.type == "MESH"
                    and bool(ob.get("mc_engine_asset"))
                    and ob.get("mc_category") != "site"
                )
            target = a.output / "MillCourt.geometry-only.glb"
            bpy.ops.export_scene.gltf(
                filepath=str(target),
                export_format="GLB",
                use_selection=True,
                export_apply=True,
                export_extras=True,
                export_materials="PLACEHOLDER",
            )
            recipe["geometry_only_glb"] = binding(target)
            recipe["geometry_only_glb_materials"] = (
                "PLACEHOLDER groups only; no procedural appearance equivalence claimed"
            )
        images = []
        if a.render:
            for view in views:
                rendering.pose(camera, camera_data, view)
                rendering.visibility(scene, camera, data["plans"], view)
                bpy.context.view_layer.update()
                target = a.output / (view["id"] + ".png")
                if target.parent != a.output or target.exists():
                    raise RuntimeError(
                        "Render target must be fresh inside the selected output directory"
                    )
                scene.render.filepath = str(target)
                bpy.ops.render.render(write_still=True)
                images.append(
                    dict(
                        view=view,
                        image=binding(target),
                        camera_matrix=[list(r) for r in camera.matrix_world],
                    )
                )
                write(a.output / "RENDER_PROGRESS.json", images)
        recipe.update(
            saved_blend=saved,
            render_device=gpu,
            images=images,
            status="GENERATED_MASTER_REQUIRES_INDEPENDENT_REOPEN_AND_VISUAL_REVIEW",
        )
        write(a.output / "GENERATION.json", recipe)
        return recipe
    except BaseException:
        write(
            a.output / "FAILURE.json",
            dict(
                status="FAILED_PARTIALS_RETAINED_NO_RETRY", error=traceback.format_exc()
            ),
        )
        raise


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    print(json.dumps(main(argv), indent=2))
