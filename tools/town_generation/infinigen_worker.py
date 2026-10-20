#!/usr/bin/env python3
"""Isolated, bounded Infinigen 2 plant-pot experiment for Living Town.

This file does not import bpy until --execute is supplied. Use Python 3.11 in
an isolated venv with infinigen==2.0.0a3, procfunc==0.37.0, bpy==4.2.0,
numpy==1.26.4, pandas==2.3.3 and pillow==11.3.0. Infinigen is installed
without its full dependency set: only the selected BSD factory path is used.
No terrain, pretrained models, external assets, or addon installation occurs.

Factory code remains upstream and unmodified. The project supplies portable
PBR images, explicit dimensions, a mesh budget and export/measurement code.
See INFINIGEN_NOTICES.txt for upstream notices and runtime license boundaries.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata as metadata
import json
import math
import os
from pathlib import Path
import struct
import shutil
import sys
import time


PINS = {
    "infinigen": "2.0.0a3", "procfunc": "0.37.0", "bpy": "4.2.0",
    "numpy": "1.26.4", "pandas": "2.3.3", "pillow": "11.3.0",
}
INFINIGEN_WHEEL_SHA256 = "7e9f096e4a9a6138af2a496826c8b97db62be9243157126b08776f364616f781"
PROCFUNC_WHEEL_SHA256 = "85ac05b559a3d735e04dea3b50e348ec460d9eb4591b811fd4efecb507b9a660"
FACTORY_PATHS = (
    "infinigen2/objects/plant_pot.py", "infinigen2/objects/bowl.py",
    "infinigen2/objects/phyllo_plant.py", "infinigen2/objects/leaf.py",
)


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def audit_dependencies() -> dict:
    """Read wheel metadata and source bytes; deliberately do not import bpy."""
    if sys.version_info[:2] != (3, 11):
        raise RuntimeError("Run this isolated worker with Python 3.11, not project Blender/Python")
    for package, expected in PINS.items():
        actual = metadata.version(package)
        if actual != expected:
            raise RuntimeError(f"{package}: expected {expected}, got {actual}")
    installed = []
    for distribution in sorted(metadata.distributions(), key=lambda d: d.metadata["Name"].lower()):
        info = distribution.metadata
        license_names = info.get_all("License-File") or []
        # Older wheels do not expose License-File metadata consistently.
        files = [str(p) for p in distribution.files or [] if "dist-info" in str(p)
                 and ("LICENSE" in str(p).upper() or "COPYING" in str(p).upper())]
        installed.append({
            "name": info["Name"], "version": distribution.version,
            "license_expression": info.get("License-Expression"),
            "license_metadata": info.get("License"),
            "license_classifiers": [c for c in info.get_all("Classifier", []) if c.startswith("License")],
            "license_files": sorted(set(license_names + files)),
        })
    dist = metadata.distribution("infinigen")
    source_hashes = {name: hashlib.sha256(Path(dist.locate_file(name)).read_bytes()).hexdigest()
                     for name in FACTORY_PATHS}
    return {
        "schema": "living_town.infinigen_worker.v1", "status": "READY_NOT_EXECUTED",
        "python": sys.version, "executable": sys.executable, "pins": PINS,
        "infinigen_wheel_sha256": INFINIGEN_WHEEL_SHA256,
        "procfunc_wheel_sha256": PROCFUNC_WHEEL_SHA256,
        "factory_source_sha256": source_hashes,
        "dependency_scope": "Minimal selected-factory environment; full CLI/terrain/sim dependencies intentionally absent",
        "runtime_license_note": "Infinigen and ProcFunc BSD-3-Clause; bpy metadata GPL-3.0 authoring runtime, not redistributed here",
        "installed_distributions": installed,
    }


def block_network() -> None:
    """Prevent an upstream code path from fetching an addon/model at runtime."""
    import socket

    def denied(*args, **kwargs):
        raise RuntimeError("Network is disabled in the isolated Infinigen factory worker")

    socket.socket.connect = denied
    socket.socket.connect_ex = denied
    socket.create_connection = denied


def texture_set(output: Path, label: str, seed: int, size: int) -> dict[str, Path]:
    """Own deterministic image PBR, with no source scans or external models."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:size, 0:size].astype(np.float32) / size
    grain = rng.normal(0.0, 1.0, (size, size)).astype(np.float32)
    # Integer frequencies keep texture boundaries periodic.
    broad = np.sin(x * 2 * math.pi * 3) * np.cos(y * 2 * math.pi * 5)
    if label == "terracotta":
        rings = np.sin(y * 2 * math.pi * 32 + 0.3 * np.sin(x * 2 * math.pi * 2))
        height = broad * 0.18 + grain * 0.12 + rings * 0.10
        base = np.array([0.62, 0.30, 0.17], dtype=np.float32)
        color = base + height[..., None] * np.array([0.055, 0.045, 0.030])
        # Small pale mineral flecks; maintained, sun-warmed earthenware.
        flecks = (rng.random((size, size)) > 0.992).astype(np.float32)
        color += flecks[..., None] * 0.12
        roughness = 0.79 + height * 0.08
        normal_strength = 1.1
    elif label == "leaf":
        midrib = np.exp(-((x - 0.5) / 0.018) ** 2)
        veins = np.maximum(0, np.cos((y - np.abs(x - 0.5) * 0.72) * 2 * math.pi * 15)) ** 18
        height = 0.22 * midrib + 0.08 * veins + grain * 0.015
        base = np.array([0.18, 0.34, 0.095], dtype=np.float32)
        color = base + (broad * 0.012 + grain * 0.004)[..., None]
        color += midrib[..., None] * np.array([0.05, 0.075, 0.018])
        color += veins[..., None] * np.array([0.009, 0.023, 0.004])
        roughness = 0.53 + grain * 0.015
        normal_strength = 0.7
    else:
        clumps = (np.sin(x * 2 * math.pi * 19) * np.sin(y * 2 * math.pi * 23))
        height = clumps * 0.18 + grain * 0.18 + broad * 0.2
        base = np.array([0.13, 0.095, 0.055], dtype=np.float32)
        color = base + height[..., None] * 0.085
        roughness = 0.93 + height * 0.03
        normal_strength = 1.5
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * normal_strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * normal_strength
    normal = np.stack([-dx, -dy, np.ones_like(dx)], axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    orm = np.stack([np.ones_like(roughness), np.clip(roughness, 0, 1), np.zeros_like(roughness)], axis=-1)
    data = {"basecolor": np.clip(color, 0, 1), "normal": normal * 0.5 + 0.5, "orm": orm}
    paths = {}
    for channel, pixels in data.items():
        path = output / f"{label}_{channel}.png"
        Image.fromarray(np.rint(pixels * 255).astype(np.uint8)).save(path)
        paths[channel] = path
    return paths


def assign_portable_material(bpy, material, name: str, images: dict[str, Path], tiling: float = 1.0):
    """Keep glTF-recognized image -> Principled paths; no procedural baking debt."""
    material.name = name
    material.use_nodes = True
    tree = material.node_tree
    tree.nodes.clear()
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    bsdf = tree.nodes.new("ShaderNodeBsdfPrincipled")
    tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    uv = tree.nodes.new("ShaderNodeTexCoord")
    mapping = tree.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (tiling, tiling, 1)
    tree.links.new(uv.outputs["UV"], mapping.inputs["Vector"])
    textures = {}
    for channel, path in images.items():
        image = bpy.data.images.load(str(path), check_existing=True)
        if channel != "basecolor":
            image.colorspace_settings.name = "Non-Color"
        tex = tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        tree.links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
        textures[channel] = tex
    tree.links.new(textures["basecolor"].outputs["Color"], bsdf.inputs["Base Color"])
    normal = tree.nodes.new("ShaderNodeNormalMap")
    normal.inputs["Strength"].default_value = 0.35
    tree.links.new(textures["normal"].outputs["Color"], normal.inputs["Color"])
    tree.links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])
    split = tree.nodes.new("ShaderNodeSeparateColor")
    tree.links.new(textures["orm"].outputs["Color"], split.inputs["Color"])
    tree.links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
    tree.links.new(split.outputs["Blue"], bsdf.inputs["Metallic"])
    # No alpha cutout: upstream generates leaf silhouettes as actual geometry.
    material.diffuse_color = (0.2, 0.4, 0.1, 1) if "Leaf" in name else (0.62, 0.30, 0.17, 1)
    return material


def glb_summary(path: Path) -> dict:
    blob = path.read_bytes()
    if blob[:4] != b"glTF":
        raise RuntimeError("Invalid GLB header")
    length, kind = struct.unpack_from("<II", blob, 12)
    if kind != 0x4E4F534A:
        raise RuntimeError("GLB JSON chunk is absent")
    doc = json.loads(blob[20:20 + length])
    primitive_triangles = 0
    for mesh in doc.get("meshes", []):
        for primitive in mesh["primitives"]:
            if "indices" in primitive:
                primitive_triangles += doc["accessors"][primitive["indices"]]["count"] // 3
    return {"bytes": len(blob), "nodes": len(doc.get("nodes", [])),
            "meshes": len(doc.get("meshes", [])), "materials": len(doc.get("materials", [])),
            "images": len(doc.get("images", [])), "triangles": primitive_triangles,
            "all_images_embedded": all("bufferView" in i for i in doc.get("images", [])),
            "material_pbr": [{"name": m.get("name"),
                              "basecolor_texture": "baseColorTexture" in m.get("pbrMetallicRoughness", {}),
                              "metallic_roughness_texture": "metallicRoughnessTexture" in m.get("pbrMetallicRoughness", {}),
                              "normal_texture": "normalTexture" in m}
                             for m in doc.get("materials", [])]}


def generate(args, audit: dict) -> dict:
    # No GPU device discovery, display API or UI process is used by this worker.
    for key in ("CUDA_VISIBLE_DEVICES", "HIP_VISIBLE_DEVICES", "ROCR_VISIBLE_DEVICES"):
        os.environ[key] = "-1"
    os.environ["OMP_NUM_THREADS"] = str(args.threads)
    os.environ["OPENBLAS_NUM_THREADS"] = str(args.threads)
    os.environ["BLENDER_USER_CONFIG"] = str(args.output / "isolated_blender_config")
    os.environ["BLENDER_USER_SCRIPTS"] = str(args.output / "isolated_blender_scripts")
    block_network()
    import bpy
    import numpy as np
    import procfunc as pf
    from infinigen2.objects import leaf, phyllo_plant, plant_pot
    from mathutils import Vector

    if not bpy.app.background:
        raise RuntimeError("This worker must run as background bpy, with no UI/display context")
    start = time.monotonic()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.render.threads_mode = "FIXED"
    scene.render.threads = args.threads
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    texture_output = args.output / "textures"
    texture_output.mkdir(parents=True, exist_ok=True)
    images = {name: texture_set(texture_output, name, args.seed + n, args.texture_size)
              for n, name in enumerate(("terracotta", "leaf", "soil"))}
    materials = {}
    for name in images:
        materials[name] = pf.Material(surface=pf.nodes.shader.principled_bsdf())
        assign_portable_material(bpy, materials[name].item(), "LivingTown_" + name.title(), images[name])
    rng = np.random.default_rng(args.seed)
    first_leaf = leaf.leaf_simple_rand(rng.spawn(1)[0], material=materials["leaf"]).mesh
    for modifier in first_leaf.item().modifiers:
        if modifier.type == "SUBSURF":
            modifier.levels = modifier.render_levels = 1
    plant = phyllo_plant.phyllo_plant(
        rng.spawn(1)[0], leaf_mesh=first_leaf, stem_material=materials["leaf"],
        count=16, count_override=True, height=0.08, radius=0.018,
        leaf_length=0.62, leaf_width=0.58, min_angle=0.38, max_angle=1.30,
        petiole_length_fraction=0.12, stem_warble=0.0, stem_handles=6,
        leaf_bend=0.10, leaf_droop=0.16, leaf_twist_degrees=12,
    ).mesh
    for modifier in plant.item().modifiers:
        if modifier.type == "SUBSURF":
            modifier.levels = modifier.render_levels = 1
    prototype = plant_pot.plant_pot(
        plant=plant, base_radius=0.235, rim_ratio=1.22, height=0.44,
        profile_fullness=0.62, profile_slope=0.45,
        rib_count=18, rib_depth=0.025, twist=0.08,
        material=materials["terracotta"], soil_material=materials["soil"],
    ).mesh.item()
    prototype.name = "Infinigen_Breton_Courtyard_Planter"
    prototype["generator"] = "Infinigen 2.0.0a3 BSD plant_pot + phyllo_plant + leaf_simple_rand"
    prototype["seed"] = args.seed
    prototype["asset_role"] = "linked-mesh courtyard and shopfront planter prototype"
    # Realize only this one prototype; callers can instance this shared mesh.
    for modifier in prototype.modifiers:
        if modifier.type == "SUBSURF":
            modifier.levels = modifier.render_levels = 1
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(prototype.evaluated_get(depsgraph), depsgraph=depsgraph)
    old_mesh = prototype.data
    prototype.modifiers.clear()
    prototype.data = mesh
    if old_mesh.users == 0:
        bpy.data.meshes.remove(old_mesh)
    # The upstream generator uses temporary leaf source objects. Export one final mesh.
    for obj in list(bpy.data.objects):
        if obj != prototype:
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.context.view_layer.objects.active = prototype
    prototype.select_set(True)
    # Geometry-node argument reconstruction may create a default material from
    # pf.Material.surface. Bind the final portable materials by the upstream
    # POINT semantic attribute after realizing, instead of relying on node IDs.
    parts = prototype.data.attributes.get("plant_pot_part")
    if parts is None or parts.domain != "POINT":
        raise RuntimeError("Upstream plant-pot semantic part attribute is absent")
    prototype.data.materials.clear()
    for name in ("terracotta", "leaf", "soil"):
        prototype.data.materials.append(materials[name].item())
    part_counts = {0: 0, 1: 0, 2: 0}
    for polygon in prototype.data.polygons:
        part = parts.data[polygon.vertices[0]].value
        if part not in part_counts:
            raise RuntimeError(f"Unknown upstream plant_pot_part: {part}")
        polygon.material_index = part
        part_counts[part] += 1
    if len(prototype.data.uv_layers) == 0:
        raise RuntimeError("Selected factory did not provide UV coordinates")
    prototype.data.calc_loop_triangles()
    tri_count = len(prototype.data.loop_triangles)
    if tri_count > args.max_triangles:
        raise RuntimeError(f"Prototype budget exceeded: {tri_count}>{args.max_triangles}")
    vertices = [prototype.matrix_world @ v.co for v in prototype.data.vertices]
    if not vertices or not all(math.isfinite(c) for v in vertices for c in v):
        raise RuntimeError("Empty or nonfinite generated geometry")
    bounds_min = [min(v[i] for v in vertices) for i in range(3)]
    bounds_max = [max(v[i] for v in vertices) for i in range(3)]
    prototype.location.z -= bounds_min[2]
    blend = args.output / "courtyard_planter.blend"
    glb = args.output / "courtyard_planter.glb"
    # Pack while keeping external PNG PBR sources beside the native file.
    for image in bpy.data.images:
        if image.source == "FILE":
            image.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", use_selection=True,
                              export_apply=False, export_extras=True, export_yup=True,
                              export_materials="EXPORT", export_texcoords=True)
    portable = glb_summary(glb)
    if not portable["all_images_embedded"] or portable["images"] < 9:
        raise RuntimeError("Portable export lost expected embedded PBR images")
    if not all(all(m[k] for k in ("basecolor_texture", "metallic_roughness_texture", "normal_texture"))
               for m in portable["material_pbr"]):
        raise RuntimeError("Portable export dropped a PBR texture channel")
    report = {
        **audit, "status": "UPSTREAM_FACTORY_EXECUTED", "seed": args.seed,
        "engine": bpy.app.version_string, "background": bpy.app.background,
        "compute": "CPU_ONLY", "threads": args.threads, "network": "socket connections blocked",
        "geometry": {"objects": 1, "vertices": len(prototype.data.vertices),
                     "triangles": tri_count, "uv_layers": len(prototype.data.uv_layers),
                     "materials": len(prototype.data.materials),
                     "semantic_polygon_counts": {"pot": part_counts[0], "plant": part_counts[1], "soil": part_counts[2]},
                     "bounds_min_before_grounding_m": bounds_min,
                     "bounds_max_before_grounding_m": bounds_max,
                     "size_m": [bounds_max[i] - bounds_min[i] for i in range(3)]},
        "glb": portable, "outputs": {"blend": str(blend), "glb": str(glb), "textures": str(texture_output)},
        "texture_origin": "Own deterministic synthetic PBR images; no external raster or model assets",
        "scope_limit": "One plant-pot factory, not an upstream whole-town/terrain run or full Infinigen installation",
    }
    notice = Path(__file__).with_name("INFINIGEN_NOTICES.txt")
    if notice.exists():
        shutil.copyfile(notice, args.output / notice.name)
        report["outputs"]["notices"] = str(args.output / notice.name)
    if args.render:
        # Optional single image; explicit CPU renderer with four threads maximum.
        bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.006))
        ground = bpy.context.object
        ground.name = "Preview_Ground_Not_Exported"
        mat = bpy.data.materials.new("Preview_Sand")
        mat.diffuse_color = (0.58, 0.54, 0.43, 1)
        ground.data.materials.append(mat)
        bpy.ops.object.camera_add(location=(1.75, -2.15, 1.48))
        camera = bpy.context.object
        camera.rotation_euler = (Vector((0, 0, 0.48)) - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = 1.85
        scene.camera = camera
        bpy.ops.object.light_add(type="AREA", location=(1.2, -1.4, 2.7))
        bpy.context.object.data.energy = 180
        bpy.context.object.data.shape = "DISK"
        bpy.context.object.data.size = 2.8
        scene.world = bpy.data.worlds.new("Preview_Summer_Sky")
        scene.world.use_nodes = True
        scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.65, 0.77, 1, 1)
        scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.65
        scene.render.resolution_x = scene.render.resolution_y = 512
        scene.render.resolution_percentage = 100
        scene.render.image_settings.file_format = "PNG"
        scene.render.filepath = str(args.output / "courtyard_planter_preview.png")
        bpy.ops.render.render(write_still=True)
        report["outputs"]["preview"] = scene.render.filepath
    report["elapsed_seconds"] = round(time.monotonic() - start, 3)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=20261020)
    parser.add_argument("--texture-size", type=int, choices=(256, 512, 1024), default=512)
    parser.add_argument("--threads", type=int, choices=range(1, 5), default=4)
    parser.add_argument("--max-triangles", type=int, default=40000)
    parser.add_argument("--execute", action="store_true", help="Explicitly permit loading background bpy and generating one prototype")
    parser.add_argument("--render", action="store_true", help="Also render one 512px 24-sample CPU preview")
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    audit = audit_dependencies()
    write_json(args.output / "environment_audit.json", audit)
    if not args.execute:
        print(json.dumps({"status": audit["status"], "audit": str(args.output / "environment_audit.json")}))
        return 0
    try:
        result = generate(args, audit)
    except BaseException as exc:
        write_json(args.output / "worker_result.json", {**audit, "status": "FAILED", "error": repr(exc)})
        raise
    write_json(args.output / "worker_result.json", result)
    print(json.dumps({"status": result["status"], "triangles": result["geometry"]["triangles"],
                      "report": str(args.output / "worker_result.json")}))
    return 0


if __name__ == "__main__":
    exit_code = 1
    try:
        exit_code = main()
    except BaseException:
        import traceback
        traceback.print_exc()
    if "bpy" in sys.modules:
        # Upstream provides this explicitly for the C-level bpy shutdown crash.
        from procfunc.util.teardown import exit_skipping_teardown
        exit_skipping_teardown(exit_code)
    raise SystemExit(exit_code)
