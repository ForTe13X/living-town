"""Build non-production Blender proxy scenes and GLBs from frozen WorldPackage JSON.

Run inside Blender's Python environment from the repository root:
  blender --background --python tools/blender/build_worldgen_preview.py -- \
    --packages game/addons/worldgen/builds --output out/worldgen-blender

The script preserves all existing scenes and writes a new, atomic output folder.
Its geometry is semantic/debug proxy geometry, not approved production art.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import re
import shutil
from pathlib import Path

import bpy

CELL = 1.0
RENDER_SIZE = (1280, 960)
SCHEMA = "worldgen.blender-proxy/1"
PALETTE = {
    "ground": (0.50, 0.60, 0.42, 1.0),
    "parcel": (0.65, 0.72, 0.55, 1.0),
    "road": (0.48, 0.43, 0.36, 1.0),
    "driveway": (0.58, 0.53, 0.45, 1.0),
    "home": (0.76, 0.50, 0.32, 1.0),
    "cafe": (0.84, 0.64, 0.40, 1.0),
    "shop": (0.70, 0.46, 0.31, 1.0),
    "civic": (0.62, 0.54, 0.42, 1.0),
    "work": (0.55, 0.49, 0.40, 1.0),
    "public_room": (0.78, 0.55, 0.33, 1.0),
    "prep_room": (0.42, 0.60, 0.49, 1.0),
    "storage_room": (0.47, 0.52, 0.64, 1.0),
    "wall": (0.78, 0.74, 0.65, 1.0),
    "water": (0.28, 0.62, 0.70, 1.0),
    "sand": (0.76, 0.67, 0.49, 1.0),
    "marker": (0.95, 0.82, 0.42, 1.0),
    "staff": (0.83, 0.85, 0.82, 1.0),
}


def _safe(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", value).strip("_") or "unnamed"


def _material(name: str, color: tuple[float, float, float, float], cache: dict) -> bpy.types.Material:
    if name in cache:
        return cache[name]
    mat = bpy.data.materials.get("WG_" + name) or bpy.data.materials.new("WG_" + name)
    mat.diffuse_color = color
    mat.use_nodes = True
    principled = mat.node_tree.nodes.get("Principled BSDF")
    if principled:
        principled.inputs["Base Color"].default_value = color
        principled.inputs["Roughness"].default_value = 0.82
    cache[name] = mat
    return mat


def _link_mesh(scene, name: str, verts, faces, location, material, props: dict):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(material)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    scene.collection.objects.link(obj)
    for key, value in props.items():
        obj[key] = value
    return obj


def _box(scene, name, x, y, z, width, depth, height, material, props):
    hx, hy, hz = width / 2.0, depth / 2.0, height / 2.0
    verts = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
             (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return _link_mesh(scene, name, verts, faces, (x, y, z), material, props)


def _slab(scene, name, x, y, width, depth, z, thickness, material, props):
    return _box(scene, name, x + width / 2.0, y + depth / 2.0, z,
                width, depth, thickness, material, props)


def _curve(scene, name, points, width, material, props):
    data = bpy.data.curves.new(name + "_Curve", "CURVE")
    data.dimensions = "3D"
    data.resolution_u = 1
    data.bevel_resolution = 2
    data.bevel_depth = max(0.025, width / 2.0)
    spline = data.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, coordinate in zip(spline.points, points):
        point.co = (float(coordinate[0]), float(coordinate[1]), float(coordinate[2]) if len(coordinate) > 2 else 0.0, 1.0)
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.data.materials.append(material)
    for key, value in props.items():
        obj[key] = value
    return obj


def _label(scene, name, text, x, y, z, size, material, props):
    data = bpy.data.curves.new(name + "_Text", "FONT")
    data.body = text
    data.size = size
    data.extrude = 0.004
    obj = bpy.data.objects.new(name, data)
    obj.location = (x, y, z)
    scene.collection.objects.link(obj)
    obj.data.materials.append(material)
    for key, value in props.items():
        obj[key] = value
    return obj


def _program_style(building: dict) -> tuple[str, float]:
    program = str(building.get("program", building.get("type", "home"))).lower()
    if any(x in program for x in ("cafe", "food", "restaurant")):
        return "cafe", 3.1
    if any(x in program for x in ("shop", "grocery", "market")):
        return "shop", 3.6
    if any(x in program for x in ("library", "civic", "public")):
        return "civic", 3.8
    if any(x in program for x in ("work", "industrial", "workshop")):
        return "work", 4.0
    if any(x in program for x in ("home", "residence", "veranda")):
        return "home", 3.2
    return "civic", 3.4


def _add_buildings(scene, buildings, mats):
    for building in buildings:
        x, y, width, depth = map(float, building["box"])
        ident = str(building.get("id", "building"))
        style, height = _program_style(building)
        material = _material(style, PALETTE[style], mats)
        props = {"worldgen_id": ident, "worldgen_kind": "building", "worldgen_program": str(building.get("program", building.get("type", "")))}
        body = _box(scene, "Bld_" + _safe(ident), (x + width / 2) * CELL, (y + depth / 2) * CELL,
                    height / 2 + 0.10, width * 0.91 * CELL, depth * 0.91 * CELL, height, material, props)
        body["worldgen_box_cells"] = list(building["box"])
        entry = building.get("entry", {})
        entry_at = entry.get("position", entry.get("at", []))
        if len(entry_at) == 2:
            _box(scene, "Entry_" + _safe(ident), float(entry_at[0]) * CELL,
                        float(entry_at[1]) * CELL, 0.62, 0.55, 0.20, 1.24,
                        _material("marker", PALETTE["marker"], mats),
                        {"worldgen_id": ident + "/entry", "worldgen_kind": "entry", "worldgen_access": str(entry.get("access", "public"))})
        _label(scene, "Lbl_" + _safe(ident), ident, (x + 0.25) * CELL, (y + 0.3) * CELL, (height + 0.22),
               min(0.78, max(0.40, min(width, depth) * 0.085)),
               _material("label", (0.12, 0.11, 0.10, 1.0), mats),
               {"worldgen_id": ident, "worldgen_kind": "label"})


def _build_inland(scene, semantic, mats):
    width, depth = map(float, semantic["extent_cells"])
    _slab(scene, "Ground_Inland", 0, 0, width, depth, -0.18, 0.36,
          _material("ground", PALETTE["ground"], mats), {"worldgen_kind": "ground"})
    for parcel in semantic.get("parcels", []):
        x, y, w, h = map(float, parcel["bounds"])
        _slab(scene, "Lot_" + _safe(parcel["id"]), x + 0.08, y + 0.08, w - 0.16, h - 0.16,
              0.015, 0.025, _material("parcel", PALETTE["parcel"], mats),
              {"worldgen_id": parcel["id"], "worldgen_kind": "parcel", "worldgen_building_id": parcel.get("building_id", "")})
    graph = semantic.get("street_graph", {})
    by_id = {node["id"]: node["at"] for node in graph.get("nodes", [])}
    for edge in graph.get("edges", []):
        a, b = by_id.get(edge.get("from")), by_id.get(edge.get("to"))
        if a is None or b is None:
            continue
        role = str(edge.get("role", "public_access"))
        color = "road" if role == "public_street" else "driveway"
        width_cells = float(edge.get("width_cells", 1))
        _curve(scene, "Road_" + _safe(edge["id"]),
               [(float(a[0]) * CELL, float(a[1]) * CELL, 0.04), (float(b[0]) * CELL, float(b[1]) * CELL, 0.04)],
               width_cells * 0.84, _material(color, PALETTE[color], mats),
               {"worldgen_id": edge["id"], "worldgen_kind": "road", "worldgen_role": role})
    _add_buildings(scene, semantic.get("buildings", []), mats)


def _wall(scene, name, x1, y1, x2, y2, height, thickness, material, ident):
    dx, dy = x2 - x1, y2 - y1
    width = math.hypot(dx, dy)
    angle = math.atan2(dy, dx)
    obj = _box(scene, name, (x1 + x2) / 2, (y1 + y2) / 2, height / 2 + 0.08,
               width, thickness, height, material,
               {"worldgen_id": ident, "worldgen_kind": "proxy_wall"})
    obj.rotation_euler[2] = angle
    return obj


def _build_cafe(scene, semantic, mats):
    width, depth = map(float, semantic["extent_cells"])
    colors = {"public": "public_room", "prep": "prep_room", "storage": "storage_room"}
    _slab(scene, "Interior_Base", 0, 0, width, depth, -0.08, 0.16,
          _material("ground", PALETTE["ground"], mats), {"worldgen_kind": "interior_base"})
    rooms = {str(room["id"]): room for room in semantic.get("rooms", [])}
    for room in semantic.get("rooms", []):
        x, y, w, h = map(float, room["bounds"])
        color = colors.get(str(room.get("id")), "public_room")
        _slab(scene, "Room_" + _safe(room["id"]), x, y, w, h, 0.035, 0.07,
              _material(color, PALETTE[color], mats),
              {"worldgen_id": room["id"], "worldgen_kind": "room", "worldgen_access": room.get("access", "")})
    wall_mat = _material("wall", PALETTE["wall"], mats)
    _wall(scene, "Outer_West", 0, 0, 0, depth, 2.7, 0.18, wall_mat, "wall/west")
    _wall(scene, "Outer_East", width, 0, width, depth, 2.7, 0.18, wall_mat, "wall/east")
    _wall(scene, "Outer_North", 0, depth, width, depth, 2.7, 0.18, wall_mat, "wall/north")
    hall = rooms.get("public", {}).get("bounds", [0, 0, width, depth / 2])
    partition_y = float(hall[1]) + float(hall[3])
    public_door = float(width / 2)
    _wall(scene, "Outer_South_L", 0, 0, public_door - 0.9, 0, 2.7, 0.18, wall_mat, "wall/south_a")
    _wall(scene, "Outer_South_R", public_door + 0.9, 0, width, 0, 2.7, 0.18, wall_mat, "wall/south_b")
    staff_mid = float(depth - (depth - partition_y) / 2)
    _wall(scene, "Outer_Staff_A", 0, 0, 0, staff_mid - 0.9, 2.7, 0.18, wall_mat, "wall/west_a")
    _wall(scene, "Outer_Staff_B", 0, staff_mid + 0.9, 0, depth, 2.7, 0.18, wall_mat, "wall/west_b")
    prep_door = float(width / 4)
    _wall(scene, "Partition_A", 0, partition_y, prep_door - 0.75, partition_y, 2.3, 0.12, wall_mat, "wall/public_prep_a")
    _wall(scene, "Partition_B", prep_door + 0.75, partition_y, width, partition_y, 2.3, 0.12, wall_mat, "wall/public_prep_b")
    storage = rooms.get("storage", {}).get("bounds", [width / 2, partition_y, width / 2, depth - partition_y])
    partition_x = float(storage[0])
    prep_to_storage_y = float(depth - (depth - partition_y) / 2)
    _wall(scene, "Storage_Partition_A", partition_x, partition_y, partition_x, prep_to_storage_y - 0.65, 2.3, 0.12, wall_mat, "wall/prep_storage_a")
    _wall(scene, "Storage_Partition_B", partition_x, prep_to_storage_y + 0.65, partition_x, depth, 2.3, 0.12, wall_mat, "wall/prep_storage_b")
    _build_affordances(scene, semantic.get("affordances", []), mats)


def _build_affordances(scene, slots, mats):
    for slot in slots:
        x, y = map(float, slot.get("position", [0, 0]))
        action = str(slot.get("action_type", ""))
        ident = str(slot.get("id", "slot"))
        if action == "sit":
            _box(scene, "Furniture_" + _safe(ident), x, y, 0.46, 0.62, 0.62, 0.86,
                 _material("home", PALETTE["home"], mats),
                 {"worldgen_id": ident, "worldgen_kind": "furniture_proxy", "worldgen_action": action})
        elif action == "buy_food":
            _box(scene, "Furniture_" + _safe(ident), x, y, 0.55, 1.4, 0.65, 1.05,
                 _material("cafe", PALETTE["cafe"], mats),
                 {"worldgen_id": ident, "worldgen_kind": "furniture_proxy", "worldgen_action": action})
        elif action == "work":
            _box(scene, "Furniture_" + _safe(ident), x, y, 0.48, 1.0, 0.8, 0.94,
                 _material("staff", PALETTE["staff"], mats),
                 {"worldgen_id": ident, "worldgen_kind": "furniture_proxy", "worldgen_action": action})
        approach = slot.get("approach", [0, 0])
        _curve(scene, "Approach_" + _safe(ident),
               [(float(approach[0]), float(approach[1]), 0.16), (x, y, 0.18)], 0.07,
               _material("marker", PALETTE["marker"], mats),
               {"worldgen_id": ident, "worldgen_kind": "affordance_approach"})
        route = slot.get("route", [])
        if len(route) > 1:
            _curve(scene, "Route_" + _safe(ident), [(float(p[0]), float(p[1]), 0.12) for p in route], 0.035,
                   _material("staff", PALETTE["staff"], mats),
                   {"worldgen_id": ident, "worldgen_kind": "declared_route", "worldgen_access": slot.get("access", "")})


def _build_coastal(scene, semantic, mats):
    topology = semantic.get("topology", {})
    width, depth = map(float, semantic["extent_cells"])
    shoreline = topology.get("shoreline", {})
    bands = shoreline.get("bands", [])
    dune_x = float(bands[0].get("dune_edge_x", width - 24)) if bands else width - 24
    offsets = shoreline.get("offsets_cells", {})
    water_x = min(width, dune_x + float(offsets.get("high_water", 16)))
    _slab(scene, "Ground_Coastal", 0, 0, width, depth, -0.18, 0.36,
          _material("ground", PALETTE["ground"], mats), {"worldgen_kind": "ground"})
    _slab(scene, "Dry_Beach", dune_x, 0, max(0.1, water_x - dune_x), depth, 0.015, 0.025,
          _material("sand", PALETTE["sand"], mats), {"worldgen_kind": "beach"})
    if water_x < width:
        _slab(scene, "Water", water_x, 0, width - water_x, depth, 0.045, 0.035,
              _material("water", PALETTE["water"], mats), {"worldgen_kind": "water", "worldgen_sea_side": shoreline.get("sea_side", "east")})
    nodes = {node["id"]: node["at"] for node in topology.get("road_nodes", [])}
    for road in topology.get("roads", []):
        a, b = nodes.get(road.get("from")), nodes.get(road.get("to"))
        if a is None or b is None:
            continue
        _curve(scene, "Road_" + _safe(road["id"]),
               [(float(a[0]), float(a[1]), 0.05), (float(b[0]), float(b[1]), 0.05)],
               float(road.get("width_cells", 1)) * 0.78,
               _material("road", PALETTE["road"], mats),
               {"worldgen_id": road["id"], "worldgen_kind": "road", "worldgen_class": road.get("class", "")})
    _add_buildings(scene, topology.get("buildings", []), mats)


def _setup_scene(scene, semantic, mats):
    kind = str(semantic.get("kind", ""))
    if kind == "inland_neighborhood":
        _build_inland(scene, semantic, mats)
    elif kind == "standalone_interior":
        _build_cafe(scene, semantic, mats)
    elif kind == "coastal_neighborhood":
        _build_coastal(scene, semantic, mats)
    else:
        raise ValueError("unsupported semantic kind: " + kind)
    extent = semantic.get("extent_cells", [16, 16])
    width, depth = float(extent[0]), float(extent[1])
    center = (width / 2.0, depth / 2.0)
    max_dimension = max(width, depth)
    camera_data = bpy.data.cameras.new("CameraData_" + _safe(scene.name))
    camera = bpy.data.objects.new("Camera_" + _safe(scene.name), camera_data)
    camera.location = (center[0], center[1], max_dimension * 1.45)
    camera.rotation_euler = (0.0, 0.0, 0.0)
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = max_dimension * 1.45
    camera["worldgen_kind"] = "preview_camera"
    scene.collection.objects.link(camera)
    scene.camera = camera
    light_data = bpy.data.lights.new("Key_" + _safe(scene.name), "AREA")
    light_data.energy = max(900.0, max_dimension * max_dimension * 3.0)
    light_data.shape = "DISK"
    light_data.size = max_dimension * 0.75
    light = bpy.data.objects.new("Key_" + _safe(scene.name), light_data)
    light.location = (center[0] - width * 0.15, center[1] - depth * 0.18, max_dimension * 0.9)
    scene.collection.objects.link(light)
    # EEVEE keeps the semantic preview fast and makes the proxy nature explicit.
    engine_ids = {item.identifier for item in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items}
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engine_ids else "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = RENDER_SIZE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("WG_World_" + _safe(scene.name))
    scene.world.color = (0.68, 0.70, 0.68)
    if scene.world.use_nodes:
        background = scene.world.node_tree.nodes.get("Background")
        if background:
            background.inputs["Color"].default_value = (0.68, 0.70, 0.68, 1.0)
            background.inputs["Strength"].default_value = 0.8
    scene.view_settings.view_transform = "AgX"
    scene.render.filepath = "//preview.png"
    scene["worldgen_kind"] = kind
    scene["worldgen_semantic_sha256"] = ""


def _build(packages_dir: str, output_dir: str):
    packages_path = Path(packages_dir).resolve()
    final = Path(output_dir).resolve()
    final.parent.mkdir(parents=True, exist_ok=True)
    stage = final.with_name(final.name + ".staging")
    if final.exists():
        raise FileExistsError("refusing to overwrite existing output: " + str(final))
    if stage.exists():
        raise FileExistsError("staging directory already exists; inspect before continuing: " + str(stage))
    stage.mkdir()
    inputs = [packages_path / name for name in ("coastal_neighborhood.world.json", "inland_neighborhood.world.json", "standalone_cafe.world.json")]
    loaded = []
    for path in inputs:
        package = json.loads(path.read_text(encoding="utf-8"))
        if package.get("schema") != "WorldPackage/1":
            raise ValueError("invalid package schema: " + str(path))
        for section in ("semantic", "presentation"):
            actual = hashlib.sha256(json.dumps(package.get(section, {}), sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest()
            if actual != package.get("digests", {}).get(section + "_sha256"):
                raise ValueError("package digest mismatch: %s:%s" % (path.name, section))
        loaded.append((path, package))

    original_scene = bpy.context.window.scene if bpy.context.window else bpy.context.scene
    mats = {}
    manifests = []
    for path, package in loaded:
        semantic = package["semantic"]
        scene = bpy.data.scenes.new("WG_" + _safe(package["world_id"]))
        _setup_scene(scene, semantic, mats)
        scene["worldgen_semantic_sha256"] = package["digests"]["semantic_sha256"]
        scene["worldgen_world_id"] = package["world_id"]
        glb_path = stage / (_safe(package["world_id"]) + ".glb")
        props = {prop.identifier for prop in bpy.ops.export_scene.gltf.get_rna_type().properties}
        kwargs = {"filepath": str(glb_path), "export_format": "GLB"}
        for key, value in {"use_active_scene": True, "export_extras": True, "export_cameras": False, "export_lights": False,
                           "export_materials": "EXPORT", "export_apply": True}.items():
            if key in props:
                kwargs[key] = value
        if bpy.context.window:
            bpy.context.window.scene = scene
        with bpy.context.temp_override(scene=scene, view_layer=scene.view_layers[0]):
            result = bpy.ops.export_scene.gltf(**kwargs)
        if "FINISHED" not in result or not glb_path.is_file():
            raise RuntimeError("Godot GLB export failed for " + package["world_id"])
        render_path = stage / (_safe(package["world_id"]) + ".png")
        scene.render.filepath = str(render_path)
        with bpy.context.temp_override(scene=scene, view_layer=scene.view_layers[0]):
            bpy.ops.render.render(write_still=True, scene=scene.name)
        manifests.append({"world_id": package["world_id"], "source_package": path.name,
                          "semantic_sha256": package["digests"]["semantic_sha256"],
                          "kind": semantic["kind"], "glb": glb_path.name, "preview_png": render_path.name,
                          "object_count": len(scene.objects), "production_art": False})

    blend_path = stage / "worldgen_proxy_previews.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=False)
    if bpy.context.window and original_scene:
        bpy.context.window.scene = next(scene for scene in bpy.data.scenes if scene.name == "Scene") if any(scene.name == "Scene" for scene in bpy.data.scenes) else original_scene
    (stage / "manifest.json").write_text(json.dumps({"schema": SCHEMA, "geometry_profile": "semantic_proxy/1",
        "source_revision": "WorldPackage/1", "worlds": manifests}, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(stage, final)
    return {"status": "ok", "output": str(final), "worlds": manifests}


def build(packages_dir: str, output_dir: str):
    """Preserve the caller's open scene and roll back only this run on failure."""
    scenes_before = set(bpy.data.scenes)
    objects_before = set(bpy.data.objects)
    materials_before = set(bpy.data.materials)
    original_scene = bpy.context.window.scene if bpy.context.window else bpy.context.scene
    final = Path(output_dir).resolve()
    stage = final.with_name(final.name + ".staging")
    can_remove_stage = not final.exists() and not stage.exists()
    try:
        return _build(packages_dir, output_dir)
    except Exception:
        if bpy.context.window and original_scene:
            bpy.context.window.scene = original_scene
        for obj in list(bpy.data.objects):
            if obj not in objects_before:
                bpy.data.objects.remove(obj, do_unlink=True)
        for scene in list(bpy.data.scenes):
            if scene not in scenes_before:
                bpy.data.scenes.remove(scene, do_unlink=True)
        for material in list(bpy.data.materials):
            if material not in materials_before and material.users == 0:
                bpy.data.materials.remove(material)
        if can_remove_stage and stage.exists():
            shutil.rmtree(stage)
        raise


if __name__ == "__main__":
    import argparse
    import sys
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--packages", required=True)
    parser.add_argument("--output", required=True)
    parsed = parser.parse_args(args)
    print(json.dumps(build(parsed.packages, parsed.output), indent=2))
