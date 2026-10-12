"""Export explicit Blender overhead polygons and sockets to a Godot-neutral JSON kit.

Usage in Blender:
  blender --background source.blend --python tools/blender/export_coastal_kit.py -- --output game/coastal/kit

Only tagged EXPORT_2D geometry and SOCKETS empties are serialized. Source scenes,
materials, cameras, lights, and the existing project are never edited.
"""
import argparse
import hashlib
import json
import math
import os
import sys
import tempfile

import bpy

EXPORT_COLLECTION = "EXPORT_2D"
SOCKET_COLLECTION = "SOCKETS"
Q_PER_CELL = 48
EXPORT_SCHEMA = "living-town.coastal-kit/1"


def fail(message):
    raise RuntimeError("COAST_EXPORT_ERROR: " + message)


def stable_json(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_bytes(value):
    return hashlib.sha256(value).hexdigest()


def quantize(value, label):
    scaled = float(value) * Q_PER_CELL
    integer = int(round(scaled))
    if abs(scaled - integer) > 1e-4:
        fail("%s is off the 1/48-cell authoring grid: %.8f" % (label, value))
    return integer


def rotation_quadrants(obj):
    if any(abs(float(s) - 1.0) > 1e-5 for s in obj.scale):
        fail("%s must have unit scale" % obj.name)
    if obj.scale.x <= 0 or obj.scale.y <= 0 or obj.scale.z <= 0:
        fail("%s has a negative or zero scale" % obj.name)
    turns = []
    for axis, value in zip("XYZ", obj.rotation_euler):
        quarter_turns = round(float(value) / (math.pi * 0.5))
        if abs(float(value) - quarter_turns * math.pi * 0.5) > 1e-5:
            fail("%s rotation on %s is not cardinal" % (obj.name, axis))
        turns.append(quarter_turns % 4)
    if turns[0] or turns[1]:
        fail("%s must lie in the export XY plane" % obj.name)
    return turns[2]


def export_modules(collection):
    modules = []
    seen = set()
    module_origins = {}
    for obj in sorted(collection.all_objects, key=lambda item: str(item.get("module_id", ""))):
        if obj.type != "MESH":
            fail("EXPORT_2D accepts mesh objects only; got %s" % obj.name)
        module_id = str(obj.get("module_id", "")).strip()
        palette_id = str(obj.get("palette_id", "")).strip()
        layer_id = str(obj.get("layer_id", "")).strip()
        license_ref = str(obj.get("license_ref", "")).strip()
        if not all((module_id, palette_id, layer_id, license_ref)):
            fail("%s needs module_id, palette_id, layer_id, and license_ref custom properties" % obj.name)
        if module_id in seen:
            fail("duplicate module_id: " + module_id)
        seen.add(module_id)
        module_origins[module_id] = obj.matrix_world.translation.copy()
        rotation = rotation_quadrants(obj)
        world = obj.matrix_world
        polygons = []
        for face_index, face in enumerate(obj.data.polygons):
            points = []
            for vertex_index in face.vertices:
                point = world @ obj.data.vertices[vertex_index].co
                point -= module_origins[module_id]
                qx = quantize(point.x, obj.name + ".x")
                qy = quantize(point.y, obj.name + ".y")
                qz = quantize(point.z, obj.name + ".z")
                if qz != 0:
                    fail("%s has nonzero height in the top-down 2D export" % obj.name)
                points.append([qx, qy])
            if len(set(tuple(point) for point in points)) < 3:
                fail("%s face %d is degenerate" % (obj.name, face_index))
            polygon = {"shape_id": "%s/f%03d" % (module_id, face_index), "points_q": points}
            if face.material_index < len(obj.data.materials):
                face_material = obj.data.materials[face.material_index]
                face_palette = str(face_material.get("palette_id", "")).strip() if face_material else ""
                if face_palette and face_palette != palette_id:
                    polygon["palette_id"] = face_palette
            polygons.append(polygon)
        if not polygons:
            fail("%s has no faces" % obj.name)
        all_q = [point for polygon in polygons for point in polygon["points_q"]]
        modules.append({
            "module_id": module_id,
            "module_revision": str(obj.get("module_revision", "1")),
            "palette_id": palette_id,
            "layer_id": layer_id,
            "draw_order": int(obj.get("draw_order", 0)),
            "allowed_rotations": [0, 1, 2, 3] if bool(obj.get("allow_cardinal_rotation", True)) else [rotation],
            "bounds_min_q": [min(point[0] for point in all_q), min(point[1] for point in all_q)],
            "dimensions_q": [max(point[0] for point in all_q) - min(point[0] for point in all_q),
                             max(point[1] for point in all_q) - min(point[1] for point in all_q)],
            "license_ref": license_ref,
            "author": str(obj.get("author", "")),
            "source_object": obj.name,
            "polygons": polygons,
        })
    return modules


def export_sockets(collection, module_origins):
    sockets = []
    seen = set()
    if collection is None:
        return sockets
    for obj in sorted(collection.all_objects, key=lambda item: str(item.get("socket_id", ""))):
        socket_id = str(obj.get("socket_id", "")).strip()
        module_id = str(obj.get("module_id", "")).strip()
        socket_type = str(obj.get("socket_type", "")).strip()
        if obj.type != "EMPTY" or not all((socket_id, module_id, socket_type)):
            fail("SOCKETS entries must be empties tagged socket_id, module_id, socket_type")
        if socket_id in seen:
            fail("duplicate socket_id: " + socket_id)
        seen.add(socket_id)
        p = obj.matrix_world.translation
        if module_id not in module_origins:
            fail("socket %s refers to a missing module %s" % (socket_id, module_id))
        p = p - module_origins[module_id]
        sockets.append({"socket_id": socket_id, "module_id": module_id, "socket_type": socket_type,
                        "at_q": [quantize(p.x, socket_id + ".x"), quantize(p.y, socket_id + ".y"), quantize(p.z, socket_id + ".z")]})
    return sockets


def atomic_json(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    fd, temporary = tempfile.mkstemp(prefix=".coastal-", suffix=".tmp", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.remove(temporary)


def main():
    raw = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, help="Godot project path for the exported coastal kit")
    args = parser.parse_args(raw)
    source_path = bpy.data.filepath
    if not source_path or not os.path.isfile(source_path):
        fail("save the .blend source before exporting so source provenance can be recorded")
    export_collection = bpy.data.collections.get(EXPORT_COLLECTION)
    if export_collection is None:
        fail("missing collection EXPORT_2D; author explicit overhead proxy geometry first")
    source_digest = sha256_bytes(open(source_path, "rb").read())
    modules = export_modules(export_collection)
    module_origins = {str(obj.get("module_id")): obj.matrix_world.translation.copy()
                      for obj in export_collection.all_objects if obj.get("module_id")}
    sockets = export_sockets(bpy.data.collections.get(SOCKET_COLLECTION), module_origins)
    module_ids = {module["module_id"] for module in modules}
    for socket in sockets:
        if socket["module_id"] not in module_ids:
            fail("socket %s refers to missing module %s" % (socket["socket_id"], socket["module_id"]))
    kit = {"schema": EXPORT_SCHEMA, "q_per_cell": Q_PER_CELL, "source_sha256": source_digest,
           "blender_version": bpy.app.version_string, "source_blend": os.path.basename(source_path),
           "modules": modules, "sockets": sockets}
    kit_digest = sha256_bytes(stable_json(kit).encode("utf-8"))
    output = os.path.abspath(args.output)
    atomic_json(os.path.join(output, "coastal_modules.json"), kit)
    atomic_json(os.path.join(output, "manifest.json"), {
        "schema": "living-town.coastal-kit-manifest/1", "kit_sha256": kit_digest,
        "source_sha256": source_digest, "module_count": len(modules), "socket_count": len(sockets),
        "blender_version": bpy.app.version_string, "runtime_blender_dependency": False,
        "approval_status": "authoring_export_requires_art_review"})
    print("COAST_KIT_EXPORTED modules=%d sockets=%d sha256=%s output=%s" % (len(modules), len(sockets), kit_digest, output))


if __name__ == "__main__":
    main()
