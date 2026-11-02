"""Blender-only construction from the pure geometry specification; no machine paths."""

import math
from .materials import create
from .physical_uv import grain_axis, project


def build_scene(bpy, spec, data, site, patch, floorplan_sha256):
    from mathutils import Vector

    if not bpy.app.background or bpy.data.filepath:
        raise RuntimeError(
            "Use a fresh factory-startup background Blender process; existing scenes are never opened."
        )
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for sc in list(bpy.data.scenes):
        if sc != bpy.context.scene:
            bpy.data.scenes.remove(sc)
    scene = bpy.context.scene
    scene.name = "MillCourt_TwoHouse_Prototype"
    scene.unit_settings.system = "METRIC"
    scene["scope"] = (
        "Two new design prototypes; fulltown/source model not opened or changed"
    )
    scene["floorplan_sha256"] = floorplan_sha256
    scene["roof_ridge_above_GF_FF_m"] = 7.7
    scene["portable_material_bake_pending"] = True
    mats = create(bpy)
    parents = {}
    objects = {}

    def root(key, parent=None, props=None):
        if key not in parents:
            ob = bpy.data.objects.new(key, None)
            scene.collection.objects.link(ob)
            ob.parent = parent
            for k, v in (props or {}).items():
                ob[k] = v
            parents[key] = ob
        return parents[key]

    for r in spec["objects"]:
        owner = root(
            r["owner"], props={"owner_id": r["owner"], "world_identity_root": True}
        )
        floor = root(
            r["owner"] + "/" + (r["plan"] or "Site"),
            owner,
            {"plan_id": r["plan"] or "Site", "level": r["level"]},
        )
        room = root(
            floor.name + "/" + (r["room"] or "Shared"),
            floor,
            {"room_id": r["room"] or "Shared"},
        )
        asset = root(
            floor.name + "/ASSET/" + r["asset"], room, {"asset_id": r["asset"]}
        )
        kind = r["kind"]
        if kind == "BOX":
            a, b = r["low"], r["high"]
            v = [
                (a[0], a[1], a[2]),
                (b[0], a[1], a[2]),
                (b[0], b[1], a[2]),
                (a[0], b[1], a[2]),
                (a[0], a[1], b[2]),
                (b[0], a[1], b[2]),
                (b[0], b[1], b[2]),
                (a[0], b[1], b[2]),
            ]
            faces = [
                (0, 3, 2, 1),
                (4, 5, 6, 7),
                (0, 1, 5, 4),
                (1, 2, 6, 5),
                (2, 3, 7, 6),
                (3, 0, 4, 7),
            ]
            me = bpy.data.meshes.new(r["id"])
            me.from_pydata(v, [], faces)
            me.update()
            ob = bpy.data.objects.new(r["id"], me)
            scene.collection.objects.link(ob)
            if r["bevel"]:
                mod = ob.modifiers.new("PurposefulEdgeBevel", "BEVEL")
                mod.width = r["bevel"]
                mod.segments = 2
                if r["material"].startswith("linen_"):
                    # Upholstery needs a continuous soft edge at room distance.
                    # Keep the plan footprint and bevel width; extra segments
                    # are limited to these small fabric-covered pieces.
                    mod.segments = 6
                    mod.harden_normals = True
                    for poly in me.polygons:
                        poly.use_smooth = True
                    normal = ob.modifiers.new(
                        "UpholsteryFaceNormals", "WEIGHTED_NORMAL"
                    )
                    normal.keep_sharp = True
        elif kind == "MESH":
            me = bpy.data.meshes.new(r["id"])
            me.from_pydata(r["vertices"], [], r["faces"])
            me.update()
            ob = bpy.data.objects.new(r["id"], me)
            scene.collection.objects.link(ob)
        elif kind == "ELLIPSOID":
            bpy.ops.mesh.primitive_uv_sphere_add(
                segments=24, ring_count=12, location=r["center"]
            )
            ob = bpy.context.object
            ob.name = r["id"]
            ob.scale = r["scale"]
            for poly in ob.data.polygons:
                poly.use_smooth = True
        elif kind == "CYLINDER":
            a = Vector(r["a"])
            b = Vector(r["b"])
            delta = b - a
            bpy.ops.mesh.primitive_cylinder_add(
                vertices=16,
                radius=r["radius"],
                depth=delta.length,
                location=(a + b) / 2,
            )
            ob = bpy.context.object
            ob.name = r["id"]
            ob.rotation_euler = delta.to_track_quat("Z", "Y").to_euler()
            for poly in ob.data.polygons:
                poly.use_smooth = len(poly.vertices) == 4
        elif kind == "EMPTY":
            ob = bpy.data.objects.new(r["id"], None)
            scene.collection.objects.link(ob)
            ob.location = r["location"]
        else:
            raise ValueError(kind)
        if ob.type == "MESH":
            for layer in list(ob.data.uv_layers):
                ob.data.uv_layers.remove(layer)
            uv = ob.data.uv_layers.new(name="UV0_MetreProjection")
            grain = grain_axis(r)
            ob["mc_grain_axis_world"] = list(grain)

            def world_point(v):
                if kind == "ELLIPSOID":
                    return Vector(
                        [v[i] * r["scale"][i] + r["center"][i] for i in range(3)]
                    )
                if kind == "CYLINDER":
                    return delta.to_track_quat("Z", "Y") @ v + (a + b) / 2
                return v

            def world_normal(n):
                if kind == "ELLIPSOID":
                    return Vector([n[i] / r["scale"][i] for i in range(3)]).normalized()
                if kind == "CYLINDER":
                    return delta.to_track_quat("Z", "Y") @ n
                return n

            for poly in ob.data.polygons:
                for loop in poly.loop_indices:
                    v = ob.data.vertices[ob.data.loops[loop].vertex_index].co
                    uv.data[loop].uv = project(
                        world_point(v), world_normal(poly.normal), grain
                    )
                if r.get("smooth"):
                    poly.use_smooth = True
        if r["label"] == "RoofDeck":
            mod = ob.modifiers.new("RoofDeckThickness", "SOLIDIFY")
            mod.thickness = 0.06
            mod.offset = -1
        if r.get("cloth_thickness"):
            mod = ob.modifiers.new("TextileThickness", "SOLIDIFY")
            mod.thickness = r["cloth_thickness"]
            mod.offset = 0
        ob.parent = asset
        for k in (
            "id",
            "owner",
            "plan",
            "level",
            "asset",
            "room",
            "category",
            "label",
            "side",
            "cut_upper",
        ):
            if r.get(k) is not None:
                ob["mc_" + k] = r[k]
        ob["mc_engine_asset"] = kind != "EMPTY"
        ob["mc_geometry_spec_id"] = r["id"]
        if r["material"]:
            ob.data.materials.append(mats[r["material"]])
            if r.get("material_variants"):
                ob.data.materials.clear()
                for i in range(5):
                    ob.data.materials.append(mats["slate_" + str(i)])
                assert len(ob.data.polygons) == len(r["face_material_indices"])
                for poly, idx in zip(ob.data.polygons, r["face_material_indices"]):
                    poly.material_index = idx
        objects[r["id"]] = ob
    # Small site support, not a claim that the whole graded town/path network is finished.
    # Use source heightfield and exact owner pads; no disconnected floating route ribbons.
    vv = patch["vertices"]
    ff = patch["faces"]
    me = bpy.data.meshes.new("StudySupport_Contour")
    me.from_pydata(vv, [], ff)
    me.update()
    ground = bpy.data.objects.new("StudySupport_Contour", me)
    scene.collection.objects.link(ground)
    me.materials.append(mats["ground"])
    ground["mc_category"] = "site"
    # Flush entry stones sit at the actual source souththreshold FF, not inferred from terrain.
    for p in data["plans"]:
        if p["level_index"]:
            continue
        dr = next(x for x in p["doors"] if x.get("external"))
        x, y, z = dr["south_threshold_world_m"]
        # Threshold is partofhouse; route landing beyond it remains a visible study obligation.
        me = bpy.data.meshes.new(p["owner_id"] + "_Threshold")
        me.from_pydata(
            [
                (x - 0.65, y - 0.12, z),
                (x + 0.65, y - 0.12, z),
                (x + 0.65, y + 0.3, z),
                (x - 0.65, y + 0.3, z),
            ],
            [],
            [(0, 1, 2, 3)],
        )
        me.update()
        ob = bpy.data.objects.new(p["owner_id"] + "_Threshold", me)
        scene.collection.objects.link(ob)
        me.materials.append(mats["granite"])
        ob["mc_category"] = "site"
    world = bpy.data.worlds.new("Breton_ClearSummer_Daylight")
    world.use_nodes = True
    scene.world = world
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (
        0.60,
        0.72,
        0.90,
        1,
    )
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.40
    sun = bpy.data.lights.new("WarmAfternoonSun", "SUN")
    sun.energy = 2.4
    sun.angle = math.radians(3)
    ob = bpy.data.objects.new(sun.name, sun)
    scene.collection.objects.link(ob)
    ob.rotation_euler = (math.radians(29), math.radians(-24), math.radians(-32))
    for p in data["plans"]:
        x, y = p["world_inner_southwest_xy_m"]
        ld = bpy.data.lights.new(p["id"] + "_CeilingBounce", "AREA")
        ld.energy = 50 if p["level_index"] else 75
        ld.color = (1.0, 0.86, 0.66)
        ld.shape = "DISK"
        ld.size = 1.5
        lo = bpy.data.objects.new(ld.name, ld)
        scene.collection.objects.link(lo)
        lo.location = (x + p["clear_width_m"] * 0.60, y + 2.4, p["FF_world_m"] + 2.42)
        lo["mc_light_plan"] = p["id"]
    camdata = bpy.data.cameras.new("PrototypeCamera")
    cam = bpy.data.objects.new(camdata.name, camdata)
    scene.collection.objects.link(cam)
    scene.camera = cam
    camdata.clip_start = 0.05
    camdata.clip_end = 200
    return scene, cam, camdata
