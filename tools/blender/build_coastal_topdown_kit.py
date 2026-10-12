"""Build a review-only, top-down coastal roof kit in a clean Blender scene.

Run with Blender background and -- --output <directory>. This does not touch the user's active scene.
"""
import argparse
import math
import os
import sys

import bpy

AUTHOR = "Living Town procedural study"
LICENSE = "generated:living-town/coastal-kit-procedural-study/1"
PALETTE = {
    "shadow": (0.18, 0.20, 0.19, 1),
    "roof/limewash_clay": (0.59, 0.37, 0.24, 1),
    "roof/civic_slate": (0.31, 0.42, 0.44, 1),
    "roof/workshop_seam": (0.34, 0.35, 0.34, 1),
    "roof/beach_canopy": (0.73, 0.62, 0.39, 1),
    "trim": (0.83, 0.76, 0.61, 1),
    "wood": (0.40, 0.25, 0.14, 1),
    "wall_base": (0.70, 0.63, 0.50, 1),
}


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])


def material(role):
    name = "Palette - " + role
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = PALETTE[role]
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = PALETTE[role]
        bsdf.inputs["Roughness"].default_value = 0.88
    mat["palette_id"] = role
    return mat


def ensure_collection(name):
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    return collection


def add_module(collection, preview_collection, module_id, base_role, x, y, width, height, style, draw_order):
    # Coordinates use 1/48 units and every roof piece is an explicit flat face.
    materials = [material(role) for role in dict.fromkeys([base_role, "shadow", "trim", "wood", "wall_base"])]
    role_to_index = {mat["palette_id"]: index for index, mat in enumerate(materials)}
    faces = []
    face_roles = []

    def polygon(points, role):
        faces.append(points)
        face_roles.append(role)

    # Slightly irregular footprint creates a readable eave/shadow silhouette.
    notch = 0.25 if style == "cottage" else 0.0
    outer = [(0, notch), (0.25, 0), (width - 0.25, 0), (width, notch),
             (width, height - 0.2), (width - 0.2, height), (0.2, height), (0, height - 0.2)]
    inset = 0.18
    polygon(outer, "shadow")
    polygon([(inset, inset), (width - inset, inset), (width - inset, height - inset), (inset, height - inset)], base_role)

    if style == "cottage":
        # Clay tile bands with a central ridge and chimney.
        for row in range(1, 5):
            yy = height * row / 5
            polygon([(0.27, yy), (width - 0.27, yy), (width - 0.27, yy + 0.045), (0.27, yy + 0.045)], "trim")
        polygon([(width * .48, .18), (width * .53, .18), (width * .53, height - .18), (width * .48, height - .18)], "wood")
        polygon([(width * .70, height * .68), (width * .86, height * .68), (width * .86, height * .90), (width * .70, height * .90)], "wall_base")
    elif style == "civic":
        # Slate panels around an inset central skylight.
        for xx in (width * .25, width * .50, width * .75):
            polygon([(xx, .18), (xx + .035, .18), (xx + .035, height - .18), (xx, height - .18)], "trim")
        polygon([(width * .36, height * .36), (width * .64, height * .36), (width * .64, height * .64), (width * .36, height * .64)], "wall_base")
        polygon([(width * .40, height * .40), (width * .60, height * .40), (width * .60, height * .60), (width * .40, height * .60)], "trim")
    elif style == "workshop":
        # Strong parallel standing seams, loading strip, and vents.
        for xx in (width * .2, width * .4, width * .6, width * .8):
            polygon([(xx, .16), (xx + .055, .16), (xx + .055, height - .16), (xx, height - .16)], "trim")
        polygon([(.18, height * .77), (width - .18, height * .77), (width - .18, height * .88), (.18, height * .88)], "wood")
        for xx in (width * .28, width * .72):
            polygon([(xx, height * .34), (xx + .18, height * .34), (xx + .18, height * .44), (xx, height * .44)], "shadow")
    else:
        # Lightweight awning slats and timber supports for the beach canopy.
        for row in range(5):
            yy = .22 + row * (height - .44) / 5
            polygon([(.16, yy), (width - .16, yy), (width - .16, yy + .08), (.16, yy + .08)], "trim" if row % 2 == 0 else "wood")
        for xx in (.22, width - .28):
            polygon([(xx, .12), (xx + .08, .12), (xx + .08, height - .12), (xx, height - .12)], "wood")

    vertices, mesh_faces = [], []
    for points in faces:
        indices = []
        for px, py in points:
            indices.append(len(vertices))
            vertices.append((round(px * 48) / 48, round(py * 48) / 48, 0))
        mesh_faces.append(indices)
    mesh = bpy.data.meshes.new(module_id + "_mesh")
    mesh.from_pydata(vertices, [], mesh_faces)
    mesh.materials.clear()
    for mat in materials:
        mesh.materials.append(mat)
    mesh.update()
    for face, role in zip(mesh.polygons, face_roles):
        face.material_index = role_to_index[role]
    obj = bpy.data.objects.new("Kit - " + module_id, mesh)
    collection.objects.link(obj)
    obj.location = (x, y, 0)
    obj["module_id"] = module_id
    obj["module_revision"] = "1"
    obj["palette_id"] = base_role
    obj["layer_id"] = "roof"
    obj["draw_order"] = draw_order
    obj["license_ref"] = LICENSE
    obj["author"] = AUTHOR
    obj["allow_cardinal_rotation"] = True

    # Render-only duplicate: slight depth steps keep Blender's z-buffer from
    # hiding coplanar detail faces. EXPORT_2D remains exactly z=0.
    preview_vertices, preview_faces = [], []
    for face_index, points in enumerate(faces):
        indices = []
        z = (face_index + 1) * 0.006
        for px, py in points:
            indices.append(len(preview_vertices))
            preview_vertices.append((round(px * 48) / 48, round(py * 48) / 48, z))
        preview_faces.append(indices)
    preview_mesh = bpy.data.meshes.new(module_id + "_render_preview_mesh")
    preview_mesh.from_pydata(preview_vertices, [], preview_faces)
    for mat in materials:
        preview_mesh.materials.append(mat)
    preview_mesh.update()
    for face, role in zip(preview_mesh.polygons, face_roles):
        face.material_index = role_to_index[role]
    preview_obj = bpy.data.objects.new("Preview only - " + module_id, preview_mesh)
    preview_collection.objects.link(preview_obj)
    preview_obj.location = (x, y, 0)
    return obj


def add_socket(collection, module_id, socket_id, x, y, sx, sy, socket_type):
    obj = bpy.data.objects.new(socket_id, None)
    collection.objects.link(obj)
    obj.location = (x + sx, y + sy, 0)
    obj.empty_display_type = "CIRCLE"
    obj.empty_display_size = .12
    obj["socket_id"] = socket_id
    obj["module_id"] = module_id
    obj["socket_type"] = socket_type


def configure_review_scene(output_dir):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 1500
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (0.12, 0.16, 0.16)
    scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.background_type = "WORLD"
    scene.display.shading.show_cavity = True
    scene.display.shading.cavity_type = "BOTH"
    scene.display.shading.curvature_ridge_factor = 1.2
    scene.display.shading.curvature_valley_factor = 0.8
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "Medium High Contrast"
    scene.view_settings.exposure = 0
    scene.view_settings.gamma = 1
    camera_data = bpy.data.cameras.new("Review overhead camera")
    camera = bpy.data.objects.new("Review overhead camera", camera_data)
    scene.collection.objects.link(camera)
    camera.location = (7.1, 1.7, 22)
    # Camera local -Z points down; local +Y is scene north.
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 17.2
    scene.camera = camera
    # Blender camera looks along local -Z, world -Z at zero rotation.
    scene.render.filepath = os.path.join(output_dir, "coastal_kit_reference.png")


def main():
    args = parse_args()
    output = os.path.abspath(args.output)
    os.makedirs(output, exist_ok=False)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        if collection != bpy.context.scene.collection:
            bpy.data.collections.remove(collection)
    export_collection = ensure_collection("EXPORT_2D")
    sockets = ensure_collection("SOCKETS")
    preview_collection = ensure_collection("PREVIEW_RENDER_ONLY")
    layout = [
        ("roof/limewash_clay", "roof/limewash_clay", 2.0, 2.4, 4.0, 3.0, "cottage"),
        ("roof/civic_slate", "roof/civic_slate", 8.2, 2.4, 4.0, 3.0, "civic"),
        ("roof/workshop_seam", "roof/workshop_seam", 2.0, -2.0, 4.0, 3.0, "workshop"),
        ("roof/beach_canopy", "roof/beach_canopy", 8.2, -2.0, 4.0, 3.0, "canopy"),
    ]
    for draw_order, (module_id, role, x, y, width, height, style) in enumerate(layout):
        add_module(export_collection, preview_collection, module_id, role, x, y, width, height, style, draw_order)
        add_socket(sockets, module_id, module_id.replace("/", "_") + "_entry", x, y, width / 2, 0, "entry")
        add_socket(sockets, module_id, module_id.replace("/", "_") + "_ridge", x, y, width / 2, height / 2, "ridge")
    configure_review_scene(output)
    blend_path = os.path.join(output, "coastal_topdown_kit_candidate.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    bpy.ops.render.render(write_still=True)
    print("COAST_KIT_SOURCE_CREATED modules=4 blend=%s preview=%s" % (blend_path, bpy.context.scene.render.filepath))


if __name__ == "__main__":
    main()
