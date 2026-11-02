"""Raw saved-source receipt: independent reopen compares actual mesh/transform/material graph."""

import hashlib, json, struct


def digest_bytes(chunks):
    h = hashlib.sha256()
    for c in chunks:
        h.update(c)
    return h.hexdigest()


def value(v):
    if isinstance(v, (str, int, float, bool)) or v is None:
        return v
    if hasattr(v, "name_full"):
        return v.name_full
    try:
        return [value(x) for x in v]
    except TypeError:
        return str(type(v).__name__)


def state(bpy):
    rows = []
    for ob in sorted(bpy.data.objects, key=lambda x: x.name):
        r = dict(
            name=ob.name,
            type=ob.type,
            parent=ob.parent.name if ob.parent else None,
            matrix_world=[list(x) for x in ob.matrix_world],
            props={k: value(ob[k]) for k in sorted(ob.keys()) if k != "_RNA_UI"},
            hide_render=ob.hide_render,
            hide_viewport=ob.hide_viewport,
        )
        if ob.type == "MESH":
            me = ob.data
            r.update(
                mesh_name=me.name,
                vertices=len(me.vertices),
                polygons=len(me.polygons),
                geometry_sha256=digest_bytes(
                    [struct.pack("<3f", *v.co) for v in me.vertices]
                    + [
                        struct.pack("<I", len(p.vertices))
                        + struct.pack("<" + "I" * len(p.vertices), *p.vertices)
                        for p in me.polygons
                    ]
                ),
                polygon_material_sha256=digest_bytes(
                    struct.pack("<I", p.material_index) for p in me.polygons
                ),
                polygon_smooth_sha256=digest_bytes(
                    struct.pack("<?", p.use_smooth) for p in me.polygons
                ),
                materials=[m.name if m else None for m in me.materials],
                UV_layers=[
                    dict(
                        name=u.name,
                        loops=len(u.data),
                        sha256=digest_bytes(struct.pack("<2f", *q.uv) for q in u.data),
                    )
                    for u in me.uv_layers
                ],
                modifiers=[
                    dict(
                        name=m.name,
                        type=m.type,
                        properties={
                            k: value(getattr(m, k))
                            for k in (
                                "width",
                                "segments",
                                "thickness",
                                "offset",
                                "harden_normals",
                                "keep_sharp",
                                "weight",
                                "thresh",
                                "mode",
                            )
                            if hasattr(m, k)
                        },
                    )
                    for m in ob.modifiers
                ],
            )
        elif ob.type == "LIGHT":
            r["light"] = dict(
                type=ob.data.type,
                energy=ob.data.energy,
                color=list(ob.data.color),
                shape=getattr(ob.data, "shape", None),
                size=getattr(ob.data, "size", None),
                angle=getattr(ob.data, "angle", None),
            )
        elif ob.type == "CAMERA":
            r["camera"] = dict(
                type=ob.data.type,
                lens=ob.data.lens,
                ortho_scale=ob.data.ortho_scale,
                clip_start=ob.data.clip_start,
                clip_end=ob.data.clip_end,
            )
        rows.append(r)
    materials = []
    for m in sorted(bpy.data.materials, key=lambda x: x.name):
        r = dict(name=m.name, diffuse=list(m.diffuse_color), nodes=[], links=[])
        if m.use_nodes:
            for n in m.node_tree.nodes:
                props = {
                    k: value(getattr(n, k))
                    for k in ("operation", "blend_type", "invert", "uv_map")
                    if hasattr(n, k)
                }
                if hasattr(n, "color_ramp"):
                    props["color_ramp"] = [
                        dict(position=e.position, color=list(e.color))
                        for e in n.color_ramp.elements
                    ]
                r["nodes"].append(
                    dict(
                        name=n.name,
                        type=n.bl_idname,
                        properties=props,
                        inputs={
                            s.name: value(s.default_value)
                            for s in n.inputs
                            if hasattr(s, "default_value")
                        },
                    )
                )
            r["links"] = [
                [l.from_node.name, l.from_socket.name, l.to_node.name, l.to_socket.name]
                for l in m.node_tree.links
            ]
        materials.append(r)
    scenes = []
    for s in bpy.data.scenes:
        bg = s.world.node_tree.nodes.get("Background")
        scenes.append(
            dict(
                name=s.name,
                unit=s.unit_settings.system,
                world=s.world.name,
                world_background={
                    q.name: value(q.default_value)
                    for q in bg.inputs
                    if hasattr(q, "default_value")
                },
                render_engine=s.render.engine,
                resolution=[
                    s.render.resolution_x,
                    s.render.resolution_y,
                    s.render.resolution_percentage,
                ],
                color_management=[
                    s.view_settings.view_transform,
                    s.view_settings.exposure,
                ],
                camera=s.camera.name,
            )
        )
    return dict(objects=rows, materials=materials, scenes=scenes)


def canonical_sha(data):
    return hashlib.sha256(
        json.dumps(data, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
