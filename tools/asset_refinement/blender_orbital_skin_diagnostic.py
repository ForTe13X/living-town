"""Render the Breton cafe-worker v001 lower-orbital material diagnostic.

Run against the preserved, already loaded source-review Blend, under an external
resource/process supervisor. This script does not supervise Blender or other apps:

    blender --background --factory-startup SOURCE_REVIEW.blend -t 2 \
      --python-exit-code 1 --python tools/asset_refinement/blender_orbital_skin_diagnostic.py \
      -- --expected-review-sha256 e03164c1c1345e4f717a894c5d3148dc49c385fecd1b5295b0eeef7e36dc8077 \
      --output-dir NEW_OUTPUT_DIRECTORY

Only that specific review source is accepted. Its original nominal 1.79 m parent,
Face camera, lighting and packed source maps are retained. A local, feathered
lower-orbital POINT attribute raises roughness to at least 0.38 and removes
metallic response where fully weighted. The bands exclude the eye opening by
height; they are not anatomical segmentation or a general skin classifier.

Outputs are a new derivative Blend, Face.png and WORKER_REPORT.json. The output
directory must not exist. Rendering uses the Radeon 8060S through HIP, 64 samples,
1280 square, with persistent data and CPU ray tracing disabled. Geometry, corner
normals, UVs, packed image bytes/color spaces and the source file are checked
unchanged. Only the local attribute, copied material and review output settings
are added or changed; the source file is never saved.

This is a Blender-only diagnostic, not a portable glTF/PBR fix. The point
attribute and Blender shader nodes require a downstream bake before portable
export. It does not qualify eye anatomy, rigging, actions, runtime or final art.
"""

import argparse
from array import array
import hashlib
import json
from pathlib import Path
import re
import sys
import time
import traceback


FAMILY = "cafe_worker_breton_v001"
REVIEW_SHA256 = "e03164c1c1345e4f717a894c5d3148dc49c385fecd1b5295b0eeef7e36dc8077"
ATTRIBUTE = "LT_LowerOrbitalSkin_Diagnostic_v001"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def mesh_fingerprint(mesh):
    result = {"vertices": len(mesh.vertices), "triangles": len(mesh.polygons), "loops": len(mesh.loops)}
    for key, sequence, field, code, width in [
        ("positions", mesh.vertices, "co", "f", 3),
        ("edges", mesh.edges, "vertices", "i", 2),
        ("loop_indices", mesh.loops, "vertex_index", "i", 1),
        ("polygon_loop_start", mesh.polygons, "loop_start", "i", 1),
        ("polygon_loop_total", mesh.polygons, "loop_total", "i", 1),
        ("polygon_material_indices", mesh.polygons, "material_index", "i", 1),
        ("corner_normals", mesh.corner_normals, "vector", "f", 3),
    ]:
        values = array(code, [0]) * (len(sequence) * width)
        sequence.foreach_get(field, values)
        result[key] = hashlib.sha256(values.tobytes()).hexdigest()
    result["UV_layers"] = {}
    for layer in mesh.uv_layers:
        values = array("f", [0]) * (len(layer.data) * 2)
        layer.data.foreach_get("uv", values)
        result["UV_layers"][layer.name] = hashlib.sha256(values.tobytes()).hexdigest()
    return result


def packed_images(bpy):
    result = []
    for image in bpy.data.images:
        if image.source != "FILE":
            continue
        require(image.packed_file is not None, "A source image is not packed")
        result.append({"name": image.name, "size": list(image.size),
                       "color_space": image.colorspace_settings.name,
                       "sha256": hashlib.sha256(image.packed_file.data).hexdigest()})
    return sorted(result, key=lambda row: row["name"])


def smooth(a, b, value):
    t = min(1.0, max(0.0, (value - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def orbital_weight(x, y, z):
    """Local diagnostic bands in this source's original glTF Y-up/front+Z frame."""
    return (smooth(.006, .009, abs(x)) * (1 - smooth(.036, .040, abs(x))) *
            smooth(.878, .881, y) * (1 - smooth(.89575, .8975, y)) * smooth(.028, .034, z))


def configure_hip(bpy, scene):
    require("cycles" in bpy.context.preferences.addons, "Cycles preferences unavailable")
    prefs = bpy.context.preferences.addons["cycles"].preferences
    require("HIP" in [row[0] for row in prefs.get_device_types(bpy.context)], "HIP unavailable")
    prefs.compute_device_type = "HIP"
    prefs.refresh_devices()
    selected = [device for device in prefs.devices if device.type == "HIP" and "8060S" in device.name]
    require(bool(selected), "The review Radeon 8060S HIP device is unavailable")
    selected_ids = {device.id for device in selected}
    for device in prefs.devices:
        device.use = device.type == "HIP" and device.id in selected_ids
    scene.render.engine = "CYCLES"
    scene.cycles.device = "GPU"
    enabled = [{"name": device.name, "type": device.type, "id": device.id}
               for device in prefs.devices if device.use]
    require(enabled and all(row["type"] == "HIP" and "8060S" in row["name"] for row in enabled),
            "GPU-only HIP selection did not read back")
    return {"backend": "HIP", "enabled_devices": enabled, "CPU_enabled": False,
            "preferences_saved": False, "blender_version": bpy.app.version_string,
            "blender_build": bpy.app.build_hash.decode()}


def apply_material_diagnostic(obj, parent):
    mesh = obj.data
    require(mesh.attributes.get(ATTRIBUTE) is None, "Diagnostic attribute already exists")
    to_source_blender = parent.matrix_world.inverted() @ obj.matrix_world
    weights = array("f", [0]) * len(mesh.vertices)
    selected_source = []
    for index, vertex in enumerate(mesh.vertices):
        point = to_source_blender @ vertex.co
        # Blender's glTF conversion is (X,-Z,Y), before the review parent scale.
        x, y, z = point.x, point.z, -point.y
        weights[index] = orbital_weight(x, y, z)
        if weights[index] > 0:
            selected_source.append((x, y, z))
    require(500 < len(selected_source) < 6000 and max(weights) > .99, "Unexpected local mask coverage")
    attribute = mesh.attributes.new(name=ATTRIBUTE, type="FLOAT", domain="POINT")
    attribute.data.foreach_set("value", weights)
    material = mesh.materials[0].copy()
    material.name += "_LT_OrbitalDiagnostic_v001"
    mesh.materials[0] = material
    nodes, links = material.node_tree.nodes, material.node_tree.links
    bsdfs = [node for node in nodes if node.type == "BSDF_PRINCIPLED"]
    require(len(bsdfs) == 1, "Expected one Principled material")
    rough, metal = bsdfs[0].inputs["Roughness"], bsdfs[0].inputs["Metallic"]
    require(len(rough.links) == 1 and len(metal.links) == 1, "Source PBR links differ")
    rough_source, metal_source = rough.links[0].from_socket, metal.links[0].from_socket
    before_links = [(link.from_node.name, link.from_socket.name, link.to_node.name, link.to_socket.name)
                    for link in links]
    attribute_node = nodes.new("ShaderNodeAttribute")
    attribute_node.attribute_name = ATTRIBUTE
    attribute_node.label = "Local skin diagnostic only"
    floor = nodes.new("ShaderNodeMath")
    floor.operation = "MAXIMUM"
    floor.inputs[1].default_value = .38
    links.new(rough_source, floor.inputs[0])
    mix = nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MIX"
    links.new(attribute_node.outputs["Fac"], mix.inputs[0])
    links.new(rough_source, mix.inputs[1])
    links.new(floor.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], rough)
    inverse = nodes.new("ShaderNodeMath")
    inverse.operation = "SUBTRACT"
    inverse.inputs[0].default_value = 1
    links.new(attribute_node.outputs["Fac"], inverse.inputs[1])
    skin_metal = nodes.new("ShaderNodeMath")
    skin_metal.operation = "MULTIPLY"
    links.new(metal_source, skin_metal.inputs[0])
    links.new(inverse.outputs[0], skin_metal.inputs[1])
    links.new(skin_metal.outputs[0], metal)
    after_links = [(link.from_node.name, link.from_socket.name, link.to_node.name, link.to_socket.name)
                   for link in links]
    removed = [link for link in before_links if link not in after_links]
    require(len(removed) == 2 and {link[3] for link in removed} == {"Roughness", "Metallic"},
            "A material link outside roughness/metallic changed")
    return {"mask": {"attribute": ATTRIBUTE, "coordinate_frame": "Original glTF Y-up/front+Z",
                     "weighted_vertices": len(selected_source),
                     "fully_weighted_vertices": sum(weight > .999 for weight in weights),
                     "source_min": [min(point[k] for point in selected_source) for k in range(3)],
                     "source_max": [max(point[k] for point in selected_source) for k in range(3)],
                     "roughness_floor": .38,
                     "limitation": "Local lower-orbital bands; eye opening excluded by height, not semantic labels."},
            "material_links_removed": removed,
            "material_links_added": [link for link in after_links if link not in before_links]}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-review-sha256", required=True)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args(argv)
    require(re.fullmatch("[0-9a-f]{64}", args.expected_review_sha256) is not None,
            "Expected review SHA must be 64 lowercase hex characters")
    require(args.expected_review_sha256 == REVIEW_SHA256, "This diagnostic requires its original family review")
    import bpy
    from mathutils import Vector
    require(bpy.app.background and bool(bpy.data.filepath), "Load the source review in background Blender first")
    source = Path(bpy.data.filepath).resolve(strict=True)
    before = (source.stat().st_size, source.stat().st_mtime_ns, sha(source))
    require(before[2] == args.expected_review_sha256, "Loaded review Blend identity differs")
    out = args.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=False)
    report = {"status": "STARTED", "appearance_family": FAMILY, "art_accepted": False,
              "rig_actions_or_engine_qualified": False, "portable_PBR_export_qualified": False,
              "diagnostic_only_not_full_skin_segmentation": True,
              "source_blend": {"path": str(source), "bytes": before[0], "sha256": before[2]}, "renders": []}
    try:
        scene = bpy.context.scene
        require(scene.cycles.samples == 64 and scene.render.resolution_percentage == 100,
                "Source review sampling/resolution differs")
        candidates = [obj for obj in scene.objects if obj.type == "MESH" and len(obj.data.vertices) == 991378]
        require(len(candidates) == 1, "Source character mesh differs")
        obj = candidates[0]
        mesh = obj.data
        require(len(mesh.polygons) == 1928055 and len(mesh.materials) == 1, "Source topology/material count differs")
        geometry_before, images_before = mesh_fingerprint(mesh), packed_images(bpy)
        parent = bpy.data.objects["Review_Stature_1p79m_Unapplied"]
        require(abs(parent.scale.x - 1.8275345069325442) < 1e-6 and
                all(abs(value - parent.scale.x) < 1e-6 for value in parent.scale), "Review parent scale differs")
        report.update(apply_material_diagnostic(obj, parent))
        require(geometry_before == mesh_fingerprint(mesh) and images_before == packed_images(bpy),
                "Source geometry/normals/UVs or packed image bytes/color spaces changed")
        report.update(geometry_exact=geometry_before, geometry_unchanged=True, packed_images=images_before,
                      packed_image_bytes_and_color_spaces_unchanged=True)
        scene.camera = bpy.data.objects["Review_Face"]
        require(scene.camera.data.type == "ORTHO" and abs(scene.camera.data.ortho_scale - .48) < 1e-6 and
                (scene.camera.location - Vector((0, -2, 1.66))).length < 1e-6, "Fixed Face camera differs")
        scene.render.resolution_x = scene.render.resolution_y = 1280
        scene.render.use_persistent_data = False
        report["device"] = configure_hip(bpy, scene)
        derivative = out / "CafeWorker_LocalOrbitalMaterial_Diagnostic.blend"
        image = out / "Face.png"
        require(not derivative.exists() and not image.exists(), "Diagnostic output already exists")
        scene.render.filepath = str(image)
        bpy.ops.wm.save_as_mainfile(filepath=str(derivative), check_existing=False)
        report["derivative_blend"] = {"path": str(derivative), "bytes": derivative.stat().st_size,
                                      "sha256": sha(derivative)}
        started = time.monotonic()
        bpy.ops.render.render(write_still=True)
        require(image.is_file() and image.stat().st_size > 1000, "Actual Face render missing")
        require(geometry_before == mesh_fingerprint(mesh) and images_before == packed_images(bpy),
                "Source geometry/normals/UVs or packed images changed during render")
        report.update(status="LOCAL_ORBITAL_MATERIAL_DIAGNOSTIC_RENDERED_REVIEW_PENDING",
                      persistent_data=False,
                      renders=[{"name": "Face", "path": str(image), "sha256": sha(image),
                                "bytes": image.stat().st_size, "seconds": time.monotonic() - started,
                                "width": 1280, "height": 1280}])
    except BaseException:
        report.update(status="FAILED_PARTIALS_PRESERVED", error=traceback.format_exc())
        raise
    finally:
        report["source_blend_size_mtime_hash_unchanged"] = before == (
            source.stat().st_size, source.stat().st_mtime_ns, sha(source))
        with (out / "WORKER_REPORT.json").open("x", encoding="utf-8") as stream:
            stream.write(json.dumps(report, indent=2, allow_nan=False) + "\n")
        require(report["source_blend_size_mtime_hash_unchanged"], "Source review file changed")


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else None)
