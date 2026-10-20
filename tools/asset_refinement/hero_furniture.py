"""Original Blender cafe furniture for the concept-quality hero scene.

No imported assets, model inference, operators, or scene deletion. All dimensions
are metres. Local front is -Y; rotations are radians around local Z. The module
uses only Blender's Python API and the standard library.
"""

import math

import bpy
from mathutils import Vector


TAU = 2 * math.pi


def _material(name, color, roughness=.45, metal=0, transmission=0):
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = (*color, 1)
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metal
    shader.inputs["Transmission Weight"].default_value = transmission
    shader.inputs["IOR"].default_value = 1.46
    return material


def _grain(material, *, stone=False):
    nodes, links = material.node_tree.nodes, material.node_tree.links
    if nodes.get("Hero surface grain"):
        return
    tex = nodes.new("ShaderNodeTexNoise")
    tex.name = "Hero surface grain"
    tex.inputs["Scale"].default_value = 38 if stone else 4
    tex.inputs["Detail"].default_value = 3
    coordinates = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeVectorMath")
    mapping.operation = "MULTIPLY"
    mapping.inputs[1].default_value = (1, 1, 1) if stone else (3, 28, 2)
    links.new(coordinates.outputs["Object"], mapping.inputs[0])
    links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = .18
    ramp.color_ramp.elements[0].color = (.43, .405, .35, 1) if stone else (.22, .105, .037, 1)
    ramp.color_ramp.elements[1].position = .86
    ramp.color_ramp.elements[1].color = (.72, .69, .61, 1) if stone else (.57, .34, .13, 1)
    links.new(tex.outputs["Fac"], ramp.inputs[0])
    shader = nodes.get("Principled BSDF")
    links.new(ramp.outputs["Color"], shader.inputs["Base Color"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = .11 if stone else .13
    bump.inputs["Distance"].default_value = .0008 if stone else .0014
    links.new(tex.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], shader.inputs["Normal"])


def _materials(supplied):
    materials = dict(supplied or {})
    defaults = {
        "cabinet_oak": ((.42, .23, .085), .43, 0, 0),
        "honed_granite": ((.64, .61, .53), .56, 0, 0),
        "iron": ((.026, .045, .037), .4, .72, 0),
        "brass": ((.58, .36, .12), .29, .87, 0),
        "glass": ((.82, .92, .88), .08, 0, .97),
        "ceramic": ((.84, .80, .70), .24, 0, 0),
        "cane": ((.62, .43, .20), .72, 0, 0),
        "pastry": ((.56, .265, .075), .62, 0, 0),
        "coffee": ((.035, .012, .004), .24, 0, 0),
        "bottle_green": ((.075, .18, .095), .19, 0, .55),
    }
    for key, args in defaults.items():
        if key not in materials:
            material = _material("HeroFurniture_" + key, *args)
            if key in ("cabinet_oak", "honed_granite"):
                _grain(material, stone=key == "honed_granite")
            materials[key] = material
    return materials


def _collection(value):
    if isinstance(value, str):
        value = bpy.data.collections.get(value) or bpy.data.collections.new(value)
        if not value.users:
            bpy.context.scene.collection.children.link(value)
    return value


def _metric_uv(mesh):
    """Dominant-face physical UVs: one repeat per 2 m; not an atlas claim."""
    layer = mesh.uv_layers.new(name="HeroMetricUV_2m")
    for polygon in mesh.polygons:
        dominant = max(range(3), key=lambda axis: abs(polygon.normal[axis]))
        axes = ((1, 2), (0, 2), (0, 1))[dominant]
        for loop_index in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            layer.data[loop_index].uv = (vertex[axes[0]] / 2, vertex[axes[1]] / 2)


class _Assembly:
    def __init__(self, collection, name, kind, origin, rotation, materials):
        self.collection = _collection(collection)
        self.materials = _materials(materials)
        self.root = bpy.data.objects.new(name, None)
        self.collection.objects.link(self.root)
        self.root.empty_display_type = "PLAIN_AXES"
        self.root.empty_display_size = .12
        self.root.location = origin
        self.root.rotation_euler[2] = rotation
        self.root["asset_kind"] = kind
        self.root["original_geometry"] = True
        self.root["local_front"] = "-Y"
        self.root["dimensions_unit"] = "metre"
        self.objects = []

    def mesh(self, label, vertices, faces, material, *, smooth=False):
        mesh = bpy.data.meshes.new(self.root.name + "_" + label + "_mesh")
        mesh.from_pydata(vertices, [], faces)
        mesh.update()
        _metric_uv(mesh)
        obj = bpy.data.objects.new(self.root.name + "_" + label, mesh)
        obj.parent = self.root
        self.collection.objects.link(obj)
        obj.data.materials.append(self.materials[material])
        obj["furniture_part"] = label
        obj["original_geometry"] = True
        obj["uv_contract"] = "Dominant-face 2m metric UV; unique atlas not asserted"
        for polygon in mesh.polygons:
            polygon.use_smooth = smooth
        self.objects.append(obj)
        return obj

    def box(self, label, center, size, material, bevel=.004):
        x, y, z = (dimension / 2 for dimension in size)
        vertices = [(a * x + center[0], b * y + center[1], c * z + center[2])
                    for a, b, c in ((-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
                                    (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1))]
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                 (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        obj = self.mesh(label, vertices, faces, material)
        if material == "cabinet_oak":
            # The supplied veneer grain runs along image V. Real joinery follows
            # each board: upright door panels/stiles, lengthwise rails/shelves.
            grain_axis = 2 if "panel" in label else max(range(3), key=lambda axis: size[axis])
            layer = obj.data.uv_layers.get("HeroMetricUV_2m")
            for polygon in obj.data.polygons:
                dominant = max(range(3), key=lambda axis: abs(polygon.normal[axis]))
                axes = ((1, 2), (0, 2), (0, 1))[dominant]
                if grain_axis not in axes:
                    continue
                across = next(axis for axis in axes if axis != grain_axis)
                for loop_index in polygon.loop_indices:
                    vertex = obj.data.vertices[obj.data.loops[loop_index].vertex_index].co
                    layer.data[loop_index].uv = (vertex[across] / 2, vertex[grain_axis] / 2)
            obj["wood_grain_axis"] = "XYZ"[grain_axis]
            obj["wood_grain_contract"] = "V follows the board's long axis; door panels remain upright; end grain is not separately authored"
        if bevel:
            modifier = obj.modifiers.new("Small eased crafted edges", "BEVEL")
            modifier.width = min(bevel, min(size) / 3)
            modifier.segments = 3
            modifier.limit_method = "ANGLE"
            modifier.harden_normals = True
        return obj

    def lathe(self, label, profile, center, material, segments=40):
        vertices, rings, faces = [], [], []
        for radius, height in profile:
            ring = []
            for index in range(1 if radius == 0 else segments):
                angle = TAU * index / segments
                ring.append(len(vertices))
                vertices.append((center[0] + radius * math.cos(angle),
                                 center[1] + radius * math.sin(angle), center[2] + height))
            rings.append(ring)
        for previous, current in zip(rings, rings[1:]):
            if len(previous) == 1:
                faces.extend((previous[0], current[(index + 1) % segments], current[index])
                             for index in range(segments))
            elif len(current) == 1:
                faces.extend((previous[index], previous[(index + 1) % segments], current[0])
                             for index in range(segments))
            else:
                faces.extend((previous[index], previous[(index + 1) % segments],
                              current[(index + 1) % segments], current[index])
                             for index in range(segments))
        return self.mesh(label, vertices, faces, material, smooth=True)

    def cylinder(self, label, start, end, radius, material, segments=24, end_radius=None):
        start, end = Vector(start), Vector(end)
        direction = (end - start).normalized()
        other = Vector((0, 0, 1)) if abs(direction.z) < .95 else Vector((1, 0, 0))
        side = direction.cross(other).normalized()
        up = direction.cross(side).normalized()
        vertices = []
        for center, r in ((start, radius), (end, radius if end_radius is None else end_radius)):
            vertices.extend(tuple(center + r * (side * math.cos(TAU * index / segments)
                                                + up * math.sin(TAU * index / segments)))
                            for index in range(segments))
        faces = [(index, (index + 1) % segments, (index + 1) % segments + segments,
                  index + segments) for index in range(segments)]
        faces += [tuple(reversed(range(segments))), tuple(range(segments, 2 * segments))]
        obj = self.mesh(label, vertices, faces, material, smooth=True)
        obj.data.polygons[-1].use_smooth = False
        obj.data.polygons[-2].use_smooth = False
        return obj

    def tube(self, label, points, radius, material, *, sides=10, closed=False, radii=None):
        points = [Vector(point) for point in points]
        vertices, faces = [], []
        for index, point in enumerate(points):
            before = points[(index - 1) % len(points)] if index or closed else point
            after = points[(index + 1) % len(points)] if index + 1 < len(points) or closed else point
            tangent = (after - before).normalized()
            reference = Vector((0, 0, 1)) if abs(tangent.z) < .9 else Vector((0, 1, 0))
            side = tangent.cross(reference).normalized()
            up = tangent.cross(side).normalized()
            r = radius if radii is None else radii[index]
            vertices.extend(tuple(point + r * (side * math.cos(TAU * step / sides)
                                              + up * math.sin(TAU * step / sides)))
                            for step in range(sides))
        for index in range(len(points) if closed else len(points) - 1):
            next_index = (index + 1) % len(points)
            for step in range(sides):
                faces.append((index * sides + step, index * sides + (step + 1) % sides,
                              next_index * sides + (step + 1) % sides, next_index * sides + step))
        if not closed:
            faces += [tuple(reversed(range(sides))),
                      tuple((len(points) - 1) * sides + step for step in range(sides))]
        return self.mesh(label, vertices, faces, material, smooth=True)

    def ring(self, label, center, major, minor, material, *, steps=48, sides=10):
        points = [(center[0] + major * math.cos(TAU * index / steps),
                   center[1] + major * math.sin(TAU * index / steps), center[2])
                  for index in range(steps)]
        return self.tube(label, points, minor, material, closed=True, sides=sides)

    def cup(self, label, center, *, coffee=True, scale=1):
        x, y, z = center
        profile = [(0, 0), (.024, 0), (.031, .006), (.038, .057),
                   (.038, .063), (.0335, .063), (.028, .012), (0, .012)]
        self.lathe(label + "_hollow_cup", [(r * scale, h * scale) for r, h in profile],
                   center, "ceramic", segments=32)
        handle = [(x + scale * (.039 + .020 * math.cos(TAU * index / 28)), y,
                   z + scale * (.036 + .022 * math.sin(TAU * index / 28))) for index in range(28)]
        self.tube(label + "_open_handle", handle, .0042 * scale, "ceramic", closed=True, sides=8)
        if coffee:
            self.cylinder(label + "_coffee_surface", (x, y, z + .048 * scale),
                          (x, y, z + .049 * scale), .030 * scale, "coffee", segments=32)

    def saucer(self, label, center):
        self.lathe(label, [(0, 0), (.035, 0), (.061, .004), (.070, .009),
                           (.068, .012), (.060, .010), (.036, .004), (0, .004)],
                   center, "ceramic", segments=40)

    def finish(self, style):
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        bounds = []
        triangles = 0
        for obj in self.objects:
            evaluated = obj.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            if mesh:
                mesh.calc_loop_triangles()
                triangles += len(mesh.loop_triangles)
                bounds.extend(obj.matrix_world @ vertex.co for vertex in mesh.vertices)
            evaluated.to_mesh_clear()
        low = [min(point[axis] for point in bounds) for axis in range(3)]
        high = [max(point[axis] for point in bounds) for axis in range(3)]
        self.root["triangle_count_evaluated"] = triangles
        self.root["style"] = "Original refined stylized coastal cafe furniture"
        return {"root": self.root.name, "objects": [obj.name for obj in self.objects],
                "bounds": {"min": low, "max": high,
                           "dimensions": [high[axis] - low[axis] for axis in range(3)]},
                "triangles": triangles, "materials": {key: mat.name for key, mat in self.materials.items()},
                "style": style, "original_geometry": True,
                "uv_contract": "2m dominant-face metric UVs; atlas must be created and audited separately"}


def _pastry(assembly, label, center, rotation=0):
    points, radii = [], []
    for index in range(25):
        t = index / 24
        angle = math.radians(-30 + 240 * t)
        x, y = .041 * math.cos(angle), .041 * math.sin(angle)
        points.append((center[0] + x * math.cos(rotation) - y * math.sin(rotation),
                       center[1] + x * math.sin(rotation) + y * math.cos(rotation),
                       center[2] + .015))
        radii.append(.004 + .018 * math.sin(math.pi * t) * (1 + .10 * math.sin(t * 12 * math.pi)))
    assembly.tube(label + "_crescent_layers", points, .02, "pastry", radii=radii, sides=10)


def _pastry_case(assembly):
    x, width, depth, base = -.88, 1.04, .55, 1.05
    assembly.box("pastry_case_oak_plinth", (x, 0, base + .019), (width, depth, .038), "cabinet_oak", .008)
    # The slightly inclined front glazing is a real quadrilateral, not a cage
    # of opaque blocks. One thin solidify modifier gives its physical edge.
    front_bottom_y, front_top_y = -.267, -.19
    glass = assembly.mesh("pastry_case_inclined_front_glass",
                          [(x - .5, front_bottom_y, base + .04), (x + .5, front_bottom_y, base + .04),
                           (x + .5, front_top_y, base + .415), (x - .5, front_top_y, base + .415)],
                          [(0, 1, 2, 3)], "glass")
    glass.modifiers.new("Physical 4mm glazing", "SOLIDIFY").thickness = .004
    for side in (-1, 1):
        side_x = x + side * .502
        glass = assembly.mesh(f"pastry_case_side_{side}_glass",
                              [(side_x, front_bottom_y, base + .04), (side_x, .255, base + .04),
                               (side_x, .255, base + .415), (side_x, front_top_y, base + .415)],
                              [(0, 1, 2, 3) if side == 1 else (3, 2, 1, 0)], "glass")
        glass.modifiers.new("Physical 4mm glazing", "SOLIDIFY").thickness = .004
        for label, bottom, top in (
            ("sloped_front", (side_x, front_bottom_y, base + .035), (side_x, front_top_y, base + .425)),
            ("rear", (side_x, .255, base + .035), (side_x, .255, base + .425)),
        ):
            assembly.cylinder(f"pastry_case_{side}_{label}_brass_post", bottom, top, .006, "brass", 12)
    assembly.box("pastry_case_glass_roof", (x, .033, base + .417), (1.012, .454, .005), "glass", 0)
    for y in (front_top_y, .255):
        assembly.cylinder("pastry_case_top_horizontal_brass", (x - .51, y, base + .426),
                          (x + .51, y, base + .426), .006, "brass", 12)
    # Rear service opening stays clear: the case can actually be stocked.
    for tray_index, (tray_x, tray_y, tray_z) in enumerate(((x - .25, -.015, base + .048),
                                                          (x + .25, -.015, base + .048))):
        assembly.box(f"pastry_tray_{tray_index}_base", (tray_x, tray_y, tray_z), (.43, .39, .008), "brass", .003)
        for edge_x in (-.21, .21):
            assembly.box(f"pastry_tray_{tray_index}_side", (tray_x + edge_x, tray_y, tray_z + .01),
                         (.007, .39, .022), "brass", .002)
        for edge_y in (-.19, .19):
            assembly.box(f"pastry_tray_{tray_index}_end", (tray_x, tray_y + edge_y, tray_z + .01),
                         (.43, .007, .022), "brass", .002)
        for column in range(3):
            for row in range(2):
                _pastry(assembly, f"tray_{tray_index}_pastry_{column}_{row}",
                        (tray_x - .13 + column * .13, tray_y - .09 + row * .18, tray_z + .006),
                        rotation=(column % 2) * .25)


def _espresso_machine(assembly):
    x, y, z = .91, .055, 1.052
    # Rounded enamel body, separate drip tray and two brass group heads.
    for side_x in (-1, 1):
        for side_y in (-1, 1):
            assembly.cylinder(f"espresso_foot_{side_x}_{side_y}",
                              (x + side_x * .21, y + .02 + side_y * .105, 1.05),
                              (x + side_x * .21, y + .02 + side_y * .105, z + .04),
                              .018, "iron", 16)
    assembly.box("espresso_body_rounded_enamel", (x, y + .02, z + .22), (.54, .32, .37), "iron", .035)
    assembly.box("espresso_front_brass_band", (x, y - .146, z + .265), (.50, .014, .125), "brass", .012)
    assembly.box("espresso_drip_tray", (x, y - .19, z + .035), (.50, .25, .033), "iron", .008)
    for index in range(11):
        rail_x = x - .22 + index * .044
        assembly.cylinder(f"espresso_drip_grid_{index}", (rail_x, y - .305, z + .057),
                          (rail_x, y - .074, z + .057), .0021, "brass", 8)
    for index, offset in enumerate((-.13, .13)):
        assembly.cylinder(f"espresso_group_{index}", (x + offset, y - .17, z + .19),
                          (x + offset, y - .17, z + .24), .035, "brass", 24)
        assembly.cylinder(f"espresso_portafilter_{index}", (x + offset, y - .17, z + .19),
                          (x + offset, y - .29, z + .18), .013, "iron", 16)
        assembly.cylinder(f"espresso_spout_{index}", (x + offset, y - .17, z + .177),
                          (x + offset, y - .17, z + .19), .007, "brass", 12)
        assembly.cup(f"espresso_waiting_cup_{index}", (x + offset, y - .19, z + .06), coffee=False, scale=.82)
    # Readable dial with a ceramic face and a physical pointer, facing -Y.
    assembly.cylinder("espresso_pressure_dial_brass", (x, y - .154, z + .305),
                      (x, y - .171, z + .305), .032, "brass", 32)
    assembly.cylinder("espresso_pressure_dial_face", (x, y - .172, z + .305),
                      (x, y - .175, z + .305), .027, "ceramic", 32)
    assembly.cylinder("espresso_pressure_dial_needle", (x, y - .178, z + .305),
                      (x + .014, y - .178, z + .320), .0018, "iron", 8)
    for side in (-1, 1):
        for index in range(2):
            button_x = x + side * (.10 + index * .055)
            assembly.cylinder("espresso_control_button", (button_x, y - .16, z + .30),
                              (button_x, y - .177, z + .30), .009, "iron", 16)
    assembly.tube("espresso_curved_steam_wand", [(x + .23, y - .10, z + .23),
                                                (x + .27, y - .12, z + .18),
                                                (x + .28, y - .18, z + .11),
                                                (x + .28, y - .22, z + .07)],
                  .005, "brass", sides=10)
    assembly.box("espresso_cup_warming_top", (x, y + .02, z + .414), (.49, .285, .018), "brass", .009)
    for index in range(3):
        assembly.cup(f"espresso_warming_cup_{index}", (x - .15 + .15 * index, y + .03, z + .425),
                     coffee=False, scale=.78)


def build_counter(collection, origin=(0, 0, 0), materials=None):
    """Build a 3.0 x .72 x 1.05 m crafted oak counter plus service props."""
    assembly = _Assembly(collection, "Hero_Cafe_Counter", "crafted_oak_cafe_counter",
                         origin, 0, materials)
    # The carcass is constructed around a recessed plinth rather than one solid
    # block, so the cabinet panels and staff-side storage have actual depth.
    assembly.box("recessed_toe_plinth", (0, .025, .075), (2.82, .58, .15), "iron", .007)
    assembly.box("carcass_bottom", (0, .015, .162), (2.91, .65, .035), "cabinet_oak", .004)
    assembly.box("carcass_top_rail_support", (0, 0, .984), (2.94, .66, .055), "cabinet_oak", .004)
    for side in (-1, 1):
        assembly.box(f"carcass_end_{side}", (side * 1.454, .005, .576), (.045, .65, .86), "cabinet_oak", .005)
        # Recessed decorative end panel surrounded by its own narrow frame.
        panel_x = side * 1.479
        assembly.box(f"end_{side}_inset_panel", (panel_x - side * .007, .005, .572),
                     (.012, .47, .59), "cabinet_oak", .002)
        for edge_y in (-.30, .31):
            assembly.box(f"end_{side}_frame_stile", (panel_x, edge_y, .577),
                         (.027, .052, .81), "cabinet_oak", .003)
        for edge_z in (.195, .957):
            assembly.box(f"end_{side}_frame_rail", (panel_x, .005, edge_z),
                         (.027, .65, .06), "cabinet_oak", .003)
    for face_name, y, sign in (("front", -.329, -1), ("staff", .329, 1)):
        for stile in range(5):
            stile_x = -1.445 + stile * .7225
            assembly.box(f"{face_name}_frame_stile_{stile}", (stile_x, y, .578),
                         (.062, .039, .814), "cabinet_oak", .003)
        for height in (.196, .955):
            assembly.box(f"{face_name}_continuous_rail", (0, y, height),
                         (2.93, .039, .06), "cabinet_oak", .003)
        for panel in range(4):
            panel_x = -1.08375 + panel * .7225
            # Panels sit 18 mm behind the frame's exposed plane. A fine reveal
            # and inner bead make the joinery visible in oblique lighting.
            assembly.box(f"{face_name}_recessed_panel_{panel}", (panel_x, y - sign * .0075, .578),
                         (.652, .018, .684), "cabinet_oak", .002)
            for bead_x in (-.321, .321):
                assembly.box(f"{face_name}_panel_{panel}_inner_bead", (panel_x + bead_x, y - sign * .006, .578),
                             (.009, .012, .692), "cabinet_oak", .002)
            if face_name == "staff":
                for mount_x in (panel_x - .055, panel_x + .055):
                    assembly.cylinder(f"door_{panel}_pull_mount", (mount_x, y + .020, .867),
                                      (mount_x, y + .045, .867), .004, "brass", 12)
                assembly.cylinder(f"door_{panel}_small_brass_pull", (panel_x - .055, y + .045, .867),
                                  (panel_x + .055, y + .045, .867), .005, "brass", 16)
    # One continuous honed slab, with eased edges and a small natural overhang.
    assembly.box("continuous_honed_stone_worktop", (0, 0, 1.026), (3.0, .72, .048), "honed_granite", .009)
    _pastry_case(assembly)
    _espresso_machine(assembly)
    for index, position in enumerate(((-.14, -.18, 1.051), (.10, -.16, 1.051))):
        assembly.saucer(f"service_saucer_{index}", position)
        assembly.cup(f"service_cup_{index}", (position[0], position[1], position[2] + .009), coffee=index == 0)
    assembly.box("small_oak_payment_tray", (.29, -.18, 1.058), (.18, .15, .014), "cabinet_oak", .005)
    return assembly.finish({
        "counter_dimensions_m": [3.0, .72, 1.05], "front": "-Y", "staff_side": "+Y",
        "craft": ["framed recessed panels", "18mm panel setback", "recessed toe plinth",
                  "small staff-side brass pulls", "continuous honed stone slab"],
        "service_grouping": "Pastry case left; espresso right; collection cups and payment tray between",
        "pastry_case_service_access": "Rear opening toward +Y",
    })


def _chair(assembly, label, center, rotation):
    """Steam-bent frame, open cane weave and three slender back spindles."""
    before = len(assembly.objects)
    # Parts are built around zero, then one rigid transform sets their position.
    assembly.ring(label + "_steam_bent_seat_ring", (0, 0, .449), .193, .018, "cabinet_oak", steps=52)
    for axis in range(2):
        for index in range(-7, 8):
            offset = index * .023
            half = math.sqrt(max(0, .176 ** 2 - offset ** 2))
            z = .459 + axis * .0016
            size = (2 * half, .0065, .0035) if axis == 0 else (.0065, 2 * half, .0035)
            position = (0, offset, z) if axis == 0 else (offset, 0, z)
            assembly.box(f"{label}_open_cane_{axis}_{index}", position, size, "cane", .0007)
    for side_x in (-1, 1):
        for side_y in (-1, 1):
            points = []
            for index in range(9):
                t = index / 8
                # Lower feet splay while the top ends tuck underneath the ring.
                x = side_x * (.184 - .049 * t + .009 * math.sin(math.pi * t))
                y = side_y * (.179 - .045 * t)
                points.append((x, y, .026 + .397 * t))
            assembly.tube(f"{label}_bent_leg_{side_x}_{side_y}", points, .014,
                          "cabinet_oak", sides=12, radii=[.010 + .005 * index / 8 for index in range(9)])
            assembly.cylinder(f"{label}_floor_glide_{side_x}_{side_y}",
                              (side_x * .184, side_y * .179, 0),
                              (side_x * .184, side_y * .179, .026), .011, "iron", 16)
    assembly.ring(label + "_bentwood_lower_stretcher", (0, 0, .252), .16, .009, "cabinet_oak", steps=40)
    # One continuous arch runs around the upper back. Its ends continue down
    # through short back posts that meet the seat ring without floating gaps.
    arch = []
    for index in range(33):
        angle = math.pi - math.pi * index / 32
        arch.append((.184 * math.cos(angle), .145 + .035 * math.sin(angle),
                     .467 + .395 * math.sin(angle)))
    assembly.tube(label + "_continuous_bent_back_hoop", arch, .014, "cabinet_oak", sides=12)
    for side in (-1, 1):
        assembly.tube(label + f"_back_post_{side}", [(side * .184, .145, .467),
                                                    (side * .175, .143, .431),
                                                    (side * .151, .140, .414)],
                      .014, "cabinet_oak", sides=12)
    for index, spindle_x in enumerate((-.09, 0, .09)):
        top = .467 + .395 * math.sqrt(1 - (spindle_x / .184) ** 2) - .012
        points = [(spindle_x, .144 + .029 * t, .48 + (top - .48) * t)
                  for t in (0, .2, .4, .6, .8, 1)]
        assembly.tube(label + f"_open_back_spindle_{index}", points, .007, "cabinet_oak", sides=10)
    cosine, sine = math.cos(rotation), math.sin(rotation)
    for obj in assembly.objects[before:]:
        for vertex in obj.data.vertices:
            x, y, z = vertex.co
            vertex.co = (center[0] + cosine * x - sine * y,
                         center[1] + sine * x + cosine * y, center[2] + z)
        # Regenerate physical UVs after the rigid placement, without stacking a
        # new layer over a stale origin-space layer.
        obj.data.uv_layers.remove(obj.data.uv_layers.active)
        obj.data.update()
        _metric_uv(obj.data)


def build_bistro_set(collection, origin=(0, 0, 0), rotation=0, materials=None):
    """A .64 m two-seat table; seats face its center with .15 m edge gap."""
    assembly = _Assembly(collection, "Hero_Bistro_Set", "bistro_table_two_bentwood_chairs",
                         origin, rotation, materials)
    assembly.lathe("continuous_honed_round_tabletop",
                   [(0, .706), (.307, .706), (.318, .713), (.32, .724), (.318, .738),
                    (.308, .744), (0, .744)], (0, 0, 0), "honed_granite", segments=64)
    assembly.cylinder("cast_iron_pedestal", (0, 0, .11), (0, 0, .695), .026, "iron", 32,
                      end_radius=.022)
    assembly.lathe("pedestal_turned_base_collar", [(0, .06), (.057, .06), (.061, .08),
                                                  (.047, .11), (.035, .15), (0, .15)],
                   (0, 0, 0), "iron", segments=32)
    for index in range(4):
        angle = index * math.pi / 2 + math.pi / 4
        points = []
        for step in range(12):
            t = step / 11
            radial = .026 + .257 * t
            points.append((radial * math.cos(angle), radial * math.sin(angle),
                           .105 * (1 - t) ** 1.7 + .022))
        assembly.tube(f"curved_pedestal_foot_{index}", points, .017, "iron", sides=12,
                      radii=[.021 - .009 * step / 11 for step in range(12)])
        assembly.cylinder(f"pedestal_leveling_pad_{index}",
                          (.279 * math.cos(angle), .279 * math.sin(angle), 0),
                          (.279 * math.cos(angle), .279 * math.sin(angle), .023), .022, "iron", 16)
        assembly.cylinder(f"tabletop_radial_support_{index}", (0, 0, .652),
                          (.23 * math.cos(angle), .23 * math.sin(angle), .704), .009, "iron", 12)
    _chair(assembly, "south_chair", (0, -.68, 0), math.pi)
    _chair(assembly, "north_chair", (0, .68, 0), 0)
    for index, (x, y) in enumerate(((-.12, -.11), (.12, .10))):
        assembly.saucer(f"table_saucer_{index}", (x, y, .745))
        assembly.cup(f"table_cup_{index}", (x, y, .754), coffee=True)
    return assembly.finish({
        "table_diameter_m": .64, "tabletop_height_m": .744,
        "seat_height_m": .462, "chair_overall_height_m": .876,
        "chair_centers_local_m": [[0, -.68, 0], [0, .68, 0]],
        "seat_front_to_table_edge_m": .149,
        "facing": "Both chairs face the table center, never outward",
        "chair_craft": ["continuous steam-bent upper back hoop", "three back spindles",
                        "four splayed legs", "bentwood lower stretcher", "open cane lattice seat"],
        "activity": "Two seated guests; drinks within reach; pedestal avoids a four-leg knee conflict",
        "placement_note": "Reserve an external circulation aisle around the occupied furniture bounds",
    })


def build_shelf(collection, origin=(0, 0, 0), materials=None):
    """Two restrained wall shelves; origin is the wall's floor datum."""
    assembly = _Assembly(collection, "Hero_Cafe_Backbar", "cafe_backbar_shelves",
                         origin, 0, materials)
    for level, height in enumerate((1.55, 2.03)):
        assembly.box(f"shelf_{level}_oak_board", (0, 0, height), (2.08, .25, .034), "cabinet_oak", .006)
        for x in (-.79, .79):
            assembly.box(f"shelf_{level}_wall_bracket", (x, .112, height - .11),
                         (.022, .018, .22), "iron", .003)
            assembly.cylinder(f"shelf_{level}_diagonal_brace", (x, .10, height - .19),
                              (x, -.087, height - .025), .007, "iron", 12)
    for index in range(4):
        assembly.cup(f"shelf_cup_{index}", (-.76 + .17 * index, -.018, 1.569), coffee=False)
    for index in range(3):
        x = .37 + .18 * index
        assembly.lathe(f"shelf_green_bottle_{index}",
                       [(0, 0), (.035, 0), (.039, .018), (.039, .18), (.031, .202),
                        (.014, .23), (.014, .288), (.018, .294), (.018, .305), (0, .305)],
                       (x, .018, 2.049), "bottle_green", segments=28)
        assembly.cylinder(f"shelf_bottle_cork_{index}", (x, .018, 2.351),
                          (x, .018, 2.363), .014, "cane", 20)
    for index in range(5):
        assembly.saucer(f"shelf_plate_stack_{index}", (-.57, .008, 2.049 + index * .007))
    return assembly.finish({
        "wall_side": "+Y", "shelf_heights_m": [1.55, 2.03],
        "grouping": "Lower shelf: cups near service reach. Upper shelf: spare plates and bottles.",
        "mounting_note": "Place +Y edge against a supporting wall; origin is floor datum.",
    })
