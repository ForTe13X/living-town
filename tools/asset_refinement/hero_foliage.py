"""Original opaque geometric foliage for a coastal plane-tree hero vignette.

Run inside Blender. No external meshes, images, model weights or add-ons. The
tree has open branching and individually lobed leaves, not solid crown volumes.
Repeated leafy twigs share eight small mesh prototypes; all dimensions are m.
"""
from __future__ import annotations

import math
import random

import bpy
from mathutils import Vector


TAU = 2 * math.pi


def _material(name, color, roughness):
    material = bpy.data.materials.get(name)
    if material is None:
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        rgb = tuple(((c + .055) / 1.055) ** 2.4 if c > .04045 else c / 12.92 for c in color)
        material.diffuse_color = (*rgb, 1.)
        bsdf = material.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*rgb, 1.)
        bsdf.inputs["Roughness"].default_value = roughness
        # Opaque surfaces work without texture-alpha sorting in any glTF viewer.
        bsdf.inputs["Alpha"].default_value = 1.
        material.use_backface_culling = False
    return material


def _materials(materials):
    supplied = dict(materials or {})
    palette = {
        "bark": ((.46, .45, .37), .87),
        "leaf_dark": ((.22, .32, .14), .67),
        "leaf_mid": ((.34, .44, .19), .61),
        "leaf_light": ((.44, .52, .25), .64),
        "bloom_blue": ((.48, .57, .72), .71),
        "bloom_cream": ((.86, .83, .66), .76),
    }
    for key, (color, rough) in palette.items():
        if key not in supplied:
            supplied[key] = _material("HeroFoliage_" + key, color, rough)
    return supplied


class _Mesh:
    def __init__(self):
        self.vertices = []
        self.faces = []
        self.indices = []
        self.uvs = []

    def poly(self, points, faces, material=0, uv=None):
        start = len(self.vertices)
        self.vertices.extend(tuple(p) for p in points)
        for face in faces:
            self.faces.append(tuple(start + i for i in face))
            self.indices.append(material)
            self.uvs.append([uv[i] if uv is not None else (points[i][0], points[i][1]) for i in face])

    def rod(self, start, end, r0, r1, material=0, sides=7):
        start, end = Vector(start), Vector(end)
        direction = end - start
        if direction.length < 1e-7:
            return
        axis = direction.normalized()
        tangent = axis.cross(Vector((0, 0, 1)))
        if tangent.length < .01:
            tangent = axis.cross(Vector((0, 1, 0)))
        tangent.normalize()
        other = axis.cross(tangent)
        vertices = []
        uv = []
        for ring, (point, radius) in enumerate(((start, r0), (end, r1))):
            for i in range(sides):
                angle = TAU * i / sides
                vertices.append(point + radius * (math.cos(angle) * tangent + math.sin(angle) * other))
                uv.append((i / sides, ring * direction.length))
        faces = [tuple(range(sides - 1, -1, -1)), tuple(range(sides, sides * 2))]
        faces += [(i, (i + 1) % sides, (i + 1) % sides + sides, i + sides) for i in range(sides)]
        self.poly(vertices, faces, material, uv)

    def object(self, name, collection, materials):
        mesh = bpy.data.meshes.new(name + "_Mesh")
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        for material in materials:
            mesh.materials.append(material)
        uv = mesh.uv_layers.new(name="FoliageUV")
        for face, index, coords in zip(mesh.polygons, self.indices, self.uvs):
            face.material_index = index
            # Flat leaf facets preserve a slight midrib fold and leaf silhouette.
            for loop, coord in zip(face.loop_indices, coords):
                uv.data[loop].uv = coord
        ob = bpy.data.objects.new(name, mesh)
        collection.objects.link(ob)
        return ob


def _frame(normal):
    normal = Vector(normal).normalized()
    right = normal.cross(Vector((0, 0, 1)))
    if right.length < .01:
        right = normal.cross(Vector((0, 1, 0)))
    right.normalize()
    return right, normal.cross(right).normalized(), normal


def _plane_leaf(mesh, center, length, normal, spin, material):
    """Five-lobed palmate silhouette with a shallow, geometric midrib fold."""
    right, up, n = _frame(normal)
    right, up = (right * math.cos(spin) + up * math.sin(spin),
                 -right * math.sin(spin) + up * math.cos(spin))
    outline = [(0, -.50), (-.12, -.35), (-.43, -.24), (-.24, -.06),
               (-.48, .22), (-.18, .15), (-.18, .48), (0, .70),
               (.17, .43), (.18, .15), (.48, .22), (.24, -.06),
               (.43, -.24), (.12, -.35)]
    center = Vector(center)
    points = [center + n * length * .055]
    points += [center + length * (x * right + y * up + abs(x) * .07 * n) for x, y in outline]
    uv = [(.5, .42)] + [(x + .5, (y + .5) / 1.2) for x, y in outline]
    # This botanical outline runs clockwise; reverse the triangle winding so
    # the leaf front normal points toward the supplied canopy/light direction.
    mesh.poly(points, [(0, (i + 1) % len(outline) + 1, i + 1) for i in range(len(outline))], material, uv)


def _broad_leaf(mesh, center, length, normal, spin, material):
    right, up, n = _frame(normal)
    right, up = (right * math.cos(spin) + up * math.sin(spin),
                 -right * math.sin(spin) + up * math.cos(spin))
    # Small serrations are geometry; no billboards or cutout textures.
    outline = [(0., -.5)]
    for side, order in ((-1, range(1, 10)), (1, range(9, 0, -1))):
        for j in order:
            t = j / 10
            width = .34 * math.sin(math.pi * t) * (1.08 if j % 2 else .94)
            outline.append((side * width, t - .5))
    outline.insert(10, (0., .55))
    center = Vector(center)
    points = [center + n * length * .055]
    points += [center + length * (x * right + y * up - abs(x) * .08 * n) for x, y in outline]
    mesh.poly(points, [(0, (i + 1) % len(outline) + 1, i + 1) for i in range(len(outline))], material,
              [(.5, .5 / 1.05)] + [(x + .5, (y + .5) / 1.05) for x, y in outline])


def _triangle_count(objects):
    return sum(sum(len(p.vertices) - 2 for p in ob.data.polygons) for ob in objects if ob.type == "MESH")


def _metadata(objects, kind, seed, origin, detail, ceiling):
    triangles = _triangle_count(objects)
    if triangles > ceiling:
        raise RuntimeError(f"{kind} has {triangles} expanded triangles; budget {ceiling}")
    points = [ob.matrix_world @ vertex.co for ob in objects if ob.type == "MESH" for vertex in ob.data.vertices]
    bounds = [[round(min(p[i] for p in points), 6) for i in range(3)],
              [round(max(p[i] for p in points), 6) for i in range(3)]]
    return {"objects": [ob.name for ob in objects], "kind": kind,
            "seed": seed, "origin_m": list(origin), "bounds_world_m": bounds,
            "height_actual_m": round(bounds[1][2] - bounds[0][2], 6),
            "expanded_triangles": triangles, "triangle_budget": ceiling,
            "unique_meshes": len({ob.data.name for ob in objects if ob.type == "MESH"}),
            "style": "Original refined stylized botanical geometry; opaque individual leaves with negative canopy gaps",
            "source": "tools/asset_refinement/hero_foliage.py; original mathematical geometry, no external assets",
            **detail}


def build_tree(collection, origin=(0, 0, 0), seed=20261019, height=6.0,
               crown_radius=2.5, materials=None):
    """Build a young coastal plane-inspired tree; approximately 70k triangles.

    Eight shared leafy-twig prototypes are instanced with varied rotations and
    scale. Botanical species is an artistic approximation, not a species survey.
    """
    if height <= 0 or crown_radius <= 0:
        raise ValueError("height and crown_radius must be positive")
    rng = random.Random(seed)
    mats = _materials(materials)
    origin = Vector(origin)
    scale = height / 6.
    crown_scale = crown_radius / 2.5
    stem = _Mesh()
    # A mild coastal lean and multiple asymmetrical tiers keep the silhouette
    # irregular. The trunk remains open below its primary limbs.
    trunk = [(0, 0, 0), (.055, -.025, height * .17), (.10, -.04, height * .34),
             (.19, .015, height * .50), (.24, .04, height * .65), (.27, .06, height * .82)]
    for i, (a, b) in enumerate(zip(trunk[:-1], trunk[1:])):
        stem.rod(a, b, scale * (.18 - i * .027), scale * (.153 - i * .027), sides=11)
    tips = []
    for i in range(9):
        azimuth = i * 2.399963 + rng.uniform(-.24, .24)
        tier = i % 3
        z0 = height * (.34 + .075 * tier) + rng.uniform(-.07, .07) * scale
        reach = crown_radius * rng.uniform(.57, .84)
        radial = Vector((math.cos(azimuth), math.sin(azimuth), 0))
        side = Vector((-radial.y, radial.x, 0))
        a = Vector((.10 + .10 * tier / 3, 0, z0))
        b = a + radial * reach * .45 + Vector((0, 0, height * .13))
        c = a + radial * reach + side * rng.uniform(-.25, .25) * crown_scale + Vector((0, 0, height * (.20 + .018 * tier)))
        stem.rod(a, b, .083 * scale, .052 * scale, sides=9)
        stem.rod(b, c, .052 * scale, .020 * scale, sides=8)
        for j in range(3):
            launch = b.lerp(c, .22 + j * .30)
            direction = (radial * rng.uniform(.35, .65) + side * (j - 1) * .75 + Vector((0, 0, rng.uniform(.35, .62)))).normalized()
            end = launch + direction * scale * rng.uniform(.65, 1.03)
            stem.rod(launch, end, .023 * scale, .008 * scale, sides=7)
            for k in range(2):
                twig_start = launch.lerp(end, .48 + k * .42)
                twig_end = twig_start + direction * .24 * scale + side * (1 if k else -1) * .28 * crown_scale + Vector((0, 0, .14 * scale))
                stem.rod(twig_start, twig_end, .009 * scale, .0035 * scale, sides=6)
                tips.append((twig_end, direction))
            tips.append((end, direction))
    # Upright young shoots complete the open upper crown, not a solid sphere.
    for i in range(8):
        a = Vector(trunk[-2])
        azimuth = i * 2.399963 + .45
        end = Vector((.25 + math.cos(azimuth) * crown_radius * .43,
                      math.sin(azimuth) * crown_radius * .43,
                      height * rng.uniform(.83, .92)))
        mid = a.lerp(end, .57) + Vector((0, 0, .12 * scale))
        stem.rod(a, mid, .026 * scale, .016 * scale, sides=8)
        stem.rod(mid, end, .016 * scale, .004 * scale, sides=6)
        tips.append((end, (end - mid).normalized()))
        tips.append((mid, (end - mid).normalized()))
    trunk_ob = stem.object("Hero_Plane_Branchwork", collection, [mats["bark"]])
    trunk_ob.location = origin
    trunk_ob["hero_foliage_role"] = "tapered_trunk_and_branches"
    objects = [trunk_ob]
    prototypes = []
    leaf_count = 44
    for i in range(8):
        prng = random.Random(seed + 1000 + i)
        cluster = _Mesh()
        # Several short twig sprays leave visible air between leaves. Their
        # positions occupy an irregular open volume; no canopy surface exists.
        for spray in range(4):
            azimuth = spray * 2.399963 + prng.uniform(-.45, .45)
            end = Vector((math.cos(azimuth) * prng.uniform(.29, .49),
                          math.sin(azimuth) * prng.uniform(.29, .49), prng.uniform(.06, .25)))
            cluster.rod((0, 0, -.10), end, .004, .0015, sides=5)
            for j in range(11):
                t = .17 + j * .075
                leaf_center = Vector((0, 0, -.10)).lerp(end, t)
                leaf_center += Vector((prng.uniform(-.13, .13), prng.uniform(-.13, .13), prng.uniform(-.10, .10)))
                normal = (prng.uniform(-.75, .75), prng.uniform(-.75, .75), prng.uniform(.35, 1.))
                _plane_leaf(cluster, leaf_center, prng.uniform(.14, .21), normal,
                            prng.uniform(0, TAU), prng.choices([1, 2, 3], weights=[2, 6, 2])[0])
        ob = cluster.object(f"Hero_Plane_LeafSpray_Prototype_{i:02d}", collection,
                            [mats["bark"], mats["leaf_dark"], mats["leaf_mid"], mats["leaf_light"]])
        prototypes.append(ob)
    for i, (position, direction) in enumerate(tips):
        proto = prototypes[i % len(prototypes)]
        if i < len(prototypes):
            ob = proto
        else:
            ob = bpy.data.objects.new(f"Hero_Plane_LeafSpray_{i:03d}", proto.data)
            collection.objects.link(ob)
        ob.location = origin + position
        ob.rotation_euler = (rng.uniform(-.35, .35), rng.uniform(-.35, .35), rng.uniform(0, TAU))
        variation = rng.uniform(.80, 1.12)
        ob.scale = (variation * crown_scale, variation * crown_scale, variation * scale)
        ob["hero_foliage_role"] = "shared_individual_palmate_leaf_spray"
        objects.append(ob)
    bpy.context.view_layer.update()
    return _metadata(objects, "plane_tree_artistic_approximation", seed, origin,
                     {"height_requested_m": height, "crown_radius_requested_m": crown_radius,
                      "leaf_prototypes": len(prototypes), "spray_instances": len(tips),
                      "individual_leaves_expanded": len(tips) * leaf_count,
                      "prototype_leaf_count": leaf_count, "alpha_textures": False}, 100000)


def _floret(mesh, center, normal, radius, spin, material):
    right, up, n = _frame(normal)
    center = Vector(center)
    for j in range(4):
        angle = spin + j * math.pi / 2
        along = right * math.cos(angle) + up * math.sin(angle)
        across = -right * math.sin(angle) + up * math.cos(angle)
        petal_center = center + along * radius * .47
        ring = [petal_center + along * (math.cos(k * TAU / 6) * radius * .62)
                + across * (math.sin(k * TAU / 6) * radius * .45) + n * radius * .045 for k in range(6)]
        points = [petal_center - n * radius * .11] + ring
        mesh.poly(points, [(0, k + 1, (k + 1) % 6 + 1) for k in range(6)], material,
                  [(.5, .5)] + [(.5 + .5 * math.cos(k * TAU / 6), .5 + .5 * math.sin(k * TAU / 6)) for k in range(6)])


def build_hydrangea(collection, origin=(0, 0, 0), seed=20261019,
                    radius=.5, materials=None):
    """Build serrated broad leaves, woody stems and real four-petal florets."""
    if radius <= 0:
        raise ValueError("radius must be positive")
    rng = random.Random(seed)
    mats = _materials(materials)
    size = radius / .5
    mesh = _Mesh()
    heads = []
    leaf_total = 0
    for i in range(9):
        angle = i * 2.399963 + rng.uniform(-.2, .2)
        reach = radius * rng.uniform(.30, .72)
        top = Vector((math.cos(angle) * reach, math.sin(angle) * reach, rng.uniform(.46, .69) * size))
        base = Vector((math.cos(angle) * radius * .10, math.sin(angle) * radius * .10, .015 * size))
        mid = base.lerp(top, .54)
        mesh.rod(base, mid, .009 * size, .006 * size, sides=7)
        mesh.rod(mid, top, .006 * size, .003 * size, sides=6)
        for level in (.36, .66):
            for side in (-1, 1):
                outward = Vector((math.cos(angle + side * 1.05), math.sin(angle + side * 1.05), .25))
                start = base.lerp(top, level)
                center = start + outward * rng.uniform(.085, .13) * size
                mesh.rod(start, center, .0025 * size, .0012 * size, sides=5)
                _broad_leaf(mesh, center, rng.uniform(.20, .28) * size,
                            (outward.x * .35, outward.y * .35, 1.), angle + side * .65,
                            rng.choices([1, 2, 3], weights=[3, 6, 1])[0])
                leaf_total += 1
        heads.append((top, rng.uniform(.145, .185) * size))
    florets = 0
    for center, head_radius in heads:
        count = 42
        for j in range(count):
            # Flower heads are open disks/domes made solely from florets.
            z = .08 + .90 * (j + .5) / count
            angle = j * 2.399963 + rng.uniform(-.12, .12)
            radial = math.sqrt(1 - z * z)
            normal = Vector((radial * math.cos(angle), radial * math.sin(angle), z))
            position = center + normal * head_radius
            _floret(mesh, position, normal, rng.uniform(.026, .033) * size,
                    rng.uniform(0, TAU), 5 if rng.random() < .14 else 4)
            florets += 1
    ob = mesh.object("Hero_Hydrangea_Leaves_And_FourPetal_Florets", collection,
                     [mats["bark"], mats["leaf_dark"], mats["leaf_mid"], mats["leaf_light"],
                      mats["bloom_blue"], mats["bloom_cream"]])
    ob.location = Vector(origin)
    ob["hero_foliage_role"] = "hydrangea_stems_serrated_leaves_and_individual_florets"
    bpy.context.view_layer.update()
    return _metadata([ob], "hydrangea_artistic_approximation", seed, origin,
                     {"radius_requested_m": radius, "flower_heads": len(heads),
                      "individual_four_petal_florets": florets, "individual_leaves": leaf_total,
                      "leaf_prototypes": 0, "alpha_textures": False}, 30000)
