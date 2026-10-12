"""Export the active Blender scene as a fresh, standalone Godot 4 review project.

Run inside Blender's Python environment. This exporter does not edit or save the source scene.
The output is an art-review/import project, not a production building kit.
"""

from __future__ import annotations

import hashlib
import json
import os
import tempfile
from pathlib import Path

import bpy
from mathutils import Vector


def _sha256(path: Path) -> str | None:
    if not path.is_file():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _scene_bounds(scene) -> tuple[Vector, Vector, Vector, Vector, int, int, int]:
    points: list[Vector] = []
    framing_points: list[Vector] = []
    mesh_objects = 0
    polygons = 0
    materials = set()
    for obj in scene.objects:
        if obj.type != "MESH" or obj.hide_render:
            continue
        mesh_objects += 1
        polygons += len(obj.data.polygons)
        materials.update(m.name for m in obj.data.materials if m is not None)
        object_points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
        points.extend(object_points)
        # Ignore landscape-scale backdrop planes for camera fitting while keeping them in the GLB.
        if max(float(axis) for axis in obj.dimensions) <= 100.0:
            framing_points.extend(object_points)
    if not points:
        raise RuntimeError("active scene has no renderable mesh objects")
    if not framing_points:
        framing_points = points
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    view_lo = Vector((min(p.x for p in framing_points), min(p.y for p in framing_points), min(p.z for p in framing_points)))
    view_hi = Vector((max(p.x for p in framing_points), max(p.y for p in framing_points), max(p.z for p in framing_points)))
    return lo, hi, view_lo, view_hi, mesh_objects, polygons, len(materials)


def _write_project(stage: Path, model_name: str, center: Vector, radius: float) -> None:
    settings = "[application]\n"
    settings += 'config/name="Coastal Mansion Art Review"\n'
    settings += 'run/main_scene="res://Review.tscn"\n\n'
    settings += "[display]\n"
    settings += "window/size/viewport_width=1440\nwindow/size/viewport_height=900\n\n"
    settings += "[rendering]\n"
    settings += 'renderer/rendering_method="gl_compatibility"\n'
    settings += 'environment/defaults/default_clear_color=Color(0.13, 0.17, 0.22, 1)\n'
    (stage / "project.godot").write_text(settings, encoding="utf-8")

    camera_script = '''extends Camera3D

@export var target := Vector3(0.0, 1.0, 0.0)
@export var distance := 24.0
@export var azimuth := deg_to_rad(38.0)
@export var elevation := deg_to_rad(25.0)

func _ready() -> void:
    _update_orbit()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            distance = maxf(2.0, distance * 0.88)
            _update_orbit()
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            distance = minf(250.0, distance / 0.88)
            _update_orbit()
    elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
        azimuth -= event.relative.x * 0.006
        elevation = clampf(elevation + event.relative.y * 0.006, deg_to_rad(-5.0), deg_to_rad(82.0))
        _update_orbit()

func _update_orbit() -> void:
    var horizontal := cos(elevation) * distance
    global_position = target + Vector3(sin(azimuth) * horizontal, sin(elevation) * distance, cos(azimuth) * horizontal)
    look_at(target, Vector3.UP)
'''
    (stage / "ReviewCamera.gd").write_text(camera_script, encoding="utf-8")

    scene = f'''[gd_scene load_steps=4 format=3]

[ext_resource type="PackedScene" path="res://{model_name}" id="1_model"]
[ext_resource type="Script" path="res://ReviewCamera.gd" id="2_camera"]

[sub_resource type="Environment" id="Environment_review"]
background_mode = 1
background_color = Color(0.13, 0.17, 0.22, 1)
ambient_light_source = 3
ambient_light_color = Color(0.72, 0.77, 0.84, 1)
ambient_light_energy = 0.8
tonemap_mode = 2

[node name="CoastalMansionReview" type="Node3D"]

[node name="Mansion" parent="." instance=ExtResource("1_model")]

[node name="ReviewCamera" type="Camera3D" parent="."]
current = true
script = ExtResource("2_camera")
target = Vector3({center.x:.5f}, {center.y:.5f}, {center.z:.5f})
distance = {radius:.5f}

[node name="KeyLight" type="DirectionalLight3D" parent="."]
rotation_degrees = Vector3(-42, -32, 0)
light_energy = 1.4
shadow_enabled = true

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment_review")
'''
    (stage / "Review.tscn").write_text(scene, encoding="utf-8")
    readme = f"""# Coastal Mansion Godot Review Project

This standalone Godot 4 project contains `{model_name}` exported from the active Blender scene and a simple orbit camera for inspection. Open this folder in Godot and run `Review.tscn`. Use the middle mouse button to orbit and the wheel to zoom.

This is a review/import candidate. It is not yet a modular building kit, a Living Town runtime integration, or approved production art. The source scene was not changed or saved by the exporter. Its dirty/clean state and source-file hash are recorded in `export_manifest.json`.
"""
    (stage / "README.md").write_text(readme, encoding="utf-8")


def export_active_scene(output_directory: str) -> dict:
    output = Path(output_directory).expanduser().resolve()
    if output.exists():
        raise FileExistsError(f"refusing to overwrite existing output: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=".godot-review-", dir=str(output.parent)))
    scene = bpy.context.scene
    source_path = Path(bpy.data.filepath).resolve() if bpy.data.filepath else None
    lo, hi, view_lo, view_hi, mesh_objects, polygons, material_count = _scene_bounds(scene)
    center_blender = (view_lo + view_hi) * 0.5
    center_godot = Vector((center_blender.x, center_blender.z, -center_blender.y))
    radius = max((view_hi - view_lo).length * 1.7, 8.0)
    model_name = "CoastalMansion.glb"
    glb_path = stage / model_name
    try:
        result = bpy.ops.export_scene.gltf(
            filepath=str(glb_path),
            export_format="GLB",
            use_selection=False,
            export_yup=True,
            export_apply=False,
            export_cameras=False,
            export_lights=False,
            export_extras=True,
        )
        if "FINISHED" not in result or not glb_path.is_file() or glb_path.stat().st_size == 0:
            raise RuntimeError(f"GLB export failed: {result}")
        _write_project(stage, model_name, center_godot, radius)
        manifest = {
            "schema": "living-town.godot-review-export/1",
            "blender_version": bpy.app.version_string,
            "scene_name": scene.name,
            "scene_dirty": bool(bpy.data.is_dirty),
            "source_blend": str(source_path) if source_path else "",
            "saved_source_file_sha256": _sha256(source_path) if source_path else None,
            "saved_source_hash_covers_current_memory_state": not bool(bpy.data.is_dirty),
            "model": model_name,
            "model_sha256": _sha256(glb_path),
            "mesh_object_count": mesh_objects,
            "source_polygon_count": polygons,
            "material_count": material_count,
            "bounds_min": [round(v, 6) for v in lo],
            "bounds_max": [round(v, 6) for v in hi],
            "camera_target_godot": [round(v, 6) for v in center_godot],
            "camera_radius": round(radius, 6),
            "production_art_approved": False,
        }
        (stage / "export_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        os.rename(stage, output)
    except Exception:
        # Leave the clearly named stage folder for inspection after a partial export.
        raise
    return {"status": "ok", "output_directory": str(output), "manifest": manifest}
