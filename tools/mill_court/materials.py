"""Purposeful metre-scaled PBR materials; Blender master, portable baking recipe separate."""

PALETTE = {
    "plaster_A": ((0.73, 0.67, 0.54), 0.83, "plaster"),
    "plaster_B": ((0.79, 0.76, 0.66), 0.85, "plaster"),
    "plaster_inside": ((0.84, 0.81, 0.72), 0.87, "plaster"),
    "paint_cream": ((0.71, 0.70, 0.60), 0.57, "paint"),
    "paint_warm": ((0.59, 0.56, 0.45), 0.61, "paint"),
    "paint_sage": ((0.20, 0.29, 0.23), 0.58, "paint"),
    "paint_blue": ((0.13, 0.23, 0.28), 0.58, "paint"),
    "oak": ((0.37, 0.23, 0.105), 0.44, "wood"),
    "oak_floor": ((0.35, 0.245, 0.14), 0.53, "floor"),
    "slate": ((0.065, 0.09, 0.105), 0.74, "stone"),
    "roof_dark": ((0.035, 0.045, 0.047), 0.82, "stone"),
    "granite": ((0.27, 0.28, 0.255), 0.83, "granite"),
    "slab": ((0.43, 0.42, 0.36), 0.9, "stone"),
    "tile": ((0.64, 0.66, 0.59), 0.37, "tile"),
    "stone_worktop": ((0.24, 0.255, 0.235), 0.41, "granite"),
    "linen_oat": ((0.58, 0.52, 0.41), 0.93, "linen"),
    "linen_sage": ((0.24, 0.34, 0.27), 0.95, "linen"),
    "linen_blue": ((0.19, 0.30, 0.35), 0.95, "linen"),
    "linen_white": ((0.79, 0.76, 0.65), 0.93, "linen"),
    "linen_ochre": ((0.56, 0.31, 0.105), 0.92, "linen"),
    "ceramic": ((0.83, 0.82, 0.75), 0.20, "ceramic"),
    "iron": ((0.055, 0.065, 0.06), 0.35, "metal"),
    "metal": ((0.42, 0.45, 0.45), 0.25, "metal"),
    "brass": ((0.43, 0.29, 0.10), 0.29, "metal"),
    "glass": ((0.91, 0.96, 0.98), 0.055, "glass"),
    "frosted": ((0.80, 0.87, 0.86), 0.43, "glass"),
    "glass_dark": ((0.025, 0.035, 0.037), 0.19, "ceramic"),
    "mirror": ((0.82, 0.83, 0.82), 0.04, "metal"),
    "paper": ((0.68, 0.60, 0.43), 0.9, "paper"),
    "leaf": ((0.16, 0.28, 0.11), 0.87, "paper"),
    "flower": ((0.64, 0.27, 0.24), 0.73, "paper"),
    "ground": ((0.30, 0.34, 0.21), 0.98, "ground"),
    "path": ((0.48, 0.44, 0.34), 0.91, "stone"),
}


def create(bpy):
    materials = {}
    for key, (color, rough, style) in PALETTE.items():
        m = bpy.data.materials.new("MC_" + key)
        m.use_nodes = True
        m.diffuse_color = (*color, 1)
        nt = m.node_tree
        bs = nt.nodes.get("Principled BSDF")
        bs.inputs["Base Color"].default_value = (*color, 1)
        bs.inputs["Roughness"].default_value = rough
        m["material_key"] = key
        m["world_units"] = "metres"
        m["portable_bake_pending"] = True
        if style == "metal":
            bs.inputs["Metallic"].default_value = 1
        if style == "glass":
            bs.inputs["Transmission Weight"].default_value = 1
            bs.inputs["IOR"].default_value = 1.45
            materials[key] = m
            continue
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        n = nt.nodes.new("ShaderNodeTexNoise")
        n.name = "FineGrain_Noise"
        nt.links.new(geo.outputs["Position"], n.inputs["Vector"])
        scale = {
            "plaster": 110.0,
            "paint": 90.0,
            "wood": 8.0,
            "floor": 8.0,
            "stone": 95.0,
            "granite": 135.0,
            "tile": 50.0,
            "linen": 700.0,
            "ground": 12.0,
        }.get(style, 40.0)
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = 3.0
        n.inputs["Roughness"].default_value = 0.72
        mix = nt.nodes.new("ShaderNodeMixRGB")
        mix.blend_type = "MIX"
        mix.inputs[1].default_value = (*[x * 0.86 for x in color], 1)
        mix.inputs[2].default_value = (*[min(1, x * 1.07) for x in color], 1)
        nt.links.new(n.outputs["Fac"], mix.inputs[0])
        nt.links.new(mix.outputs[0], bs.inputs["Base Color"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.name = "SurfaceBump_Fine"
        bump.inputs["Strength"].default_value = 0.45 if style == "plaster" else 0.35
        bump.inputs["Distance"].default_value = {
            "plaster": 0.0022,
            "linen": 0.0008,
            "granite": 0.0012,
            "stone": 0.001,
            "wood": 0.0007,
            "floor": 0.0007,
            "ground": 0.018,
        }.get(style, 0.0003)
        nt.links.new(n.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bs.inputs["Normal"])
        if style in ("wood", "floor"):
            uv = nt.nodes.new("ShaderNodeUVMap")
            uv.name = "MetricPhysicalGrainUV"
            uv.uv_map = "UV0_MetreProjection"
            stretch = nt.nodes.new("ShaderNodeVectorMath")
            stretch.operation = "MULTIPLY"
            stretch.inputs[1].default_value = (2.0, 70.0, 1.0)
            nt.links.new(uv.outputs["UV"], stretch.inputs[0])
            nt.links.new(stretch.outputs["Vector"], n.inputs["Vector"])
            m["grain_coordinate_system"] = (
                "Metric UV0 U follows physical length/vertical leg/beam axis; V crossesgrain"
            )
            # Visible earlywood/latewood-scale color, separate from fine pores.
            broad_uv = nt.nodes.new("ShaderNodeVectorMath")
            broad_uv.operation = "MULTIPLY"
            broad_uv.name = "LongWoodGrain_Scale"
            broad_uv.inputs[1].default_value = (2.0, 45.0, 1.0)
            nt.links.new(uv.outputs["UV"], broad_uv.inputs[0])
            broad = nt.nodes.new("ShaderNodeTexNoise")
            broad.name = "LongWoodGrain_Noise"
            broad.inputs["Scale"].default_value = 1.0
            broad.inputs["Detail"].default_value = 2.0
            broad.inputs["Roughness"].default_value = 0.6
            nt.links.new(broad_uv.outputs["Vector"], broad.inputs["Vector"])
            wood_color = nt.nodes.new("ShaderNodeValToRGB")
            wood_color.name = "LongWoodGrain_Color"
            wood_color.color_ramp.elements[0].position = 0.28
            wood_color.color_ramp.elements[1].position = 0.72
            wood_color.color_ramp.elements[0].color = (*[x * 0.66 for x in color], 1)
            wood_color.color_ramp.elements[1].color = (
                *[min(1, x * 1.14) for x in color],
                1,
            )
            nt.links.new(broad.outputs["Fac"], wood_color.inputs["Fac"])
            nt.links.new(wood_color.outputs["Color"], bs.inputs["Base Color"])
            m["grain_color_scale_m"] = (0.5, 1 / 45)

        if style == "plaster":
            cloud = nt.nodes.new("ShaderNodeTexNoise")
            cloud.name = "Limewash_MacroVariation"
            cloud.inputs["Scale"].default_value = 3.2
            cloud.inputs["Detail"].default_value = 2
            nt.links.new(geo.outputs["Position"], cloud.inputs["Vector"])
            nt.links.new(cloud.outputs["Fac"], mix.inputs[0])
            mix.inputs[1].default_value = (*[x * 0.93 for x in color], 1)
            mix.inputs[2].default_value = (*[min(1, x * 1.04) for x in color], 1)
        if style in ("floor", "tile"):
            # Metric mortar/plank seams are visible at interior-camera scale.
            brick = nt.nodes.new("ShaderNodeTexBrick")
            brick.name = "MetricPlankOrTileSeams"
            nt.links.new(
                uv.outputs["UV"] if style == "floor" else geo.outputs["Position"],
                brick.inputs["Vector"],
            )
            brick.offset = 0.5
            brick.offset_frequency = 2
            brick.inputs["Scale"].default_value = 1
            brick.inputs["Brick Width"].default_value = (
                1.15 if style == "floor" else 0.20
            )
            brick.inputs["Row Height"].default_value = (
                0.16 if style == "floor" else 0.20
            )
            brick.inputs["Mortar Size"].default_value = (
                0.0025 if style == "floor" else 0.003
            )
            brick.inputs["Mortar Smooth"].default_value = 0.001
            brick.inputs["Color1"].default_value = (*[x * 0.90 for x in color], 1)
            brick.inputs["Color2"].default_value = (*[x * 1.04 for x in color], 1)
            brick.inputs["Mortar"].default_value = (0.17, 0.16, 0.135, 1)
            if style == "floor":
                ramp = nt.nodes.new("ShaderNodeValToRGB")
                ramp.name = "WoodGrain_Grayscale"
                ramp.color_ramp.elements[0].color = (0.62, 0.62, 0.62, 1)
                ramp.color_ramp.elements[1].color = (1.12, 1.12, 1.12, 1)
                ramp.color_ramp.elements[0].position = 0.28
                ramp.color_ramp.elements[1].position = 0.72
                nt.links.new(broad.outputs["Fac"], ramp.inputs["Fac"])
                multiply = nt.nodes.new("ShaderNodeMixRGB")
                multiply.name = "PlankGrain_Multiply"
                multiply.blend_type = "MULTIPLY"
                multiply.inputs[0].default_value = 1
                nt.links.new(brick.outputs["Color"], multiply.inputs[1])
                nt.links.new(ramp.outputs["Color"], multiply.inputs[2])
                nt.links.new(multiply.outputs[0], bs.inputs["Base Color"])
            else:
                nt.links.new(brick.outputs["Color"], bs.inputs["Base Color"])
            seam = nt.nodes.new("ShaderNodeBump")
            seam.name = "PlankOrTileSeam_Bump"
            seam.invert = True
            seam.inputs["Strength"].default_value = 0.32
            seam.inputs["Distance"].default_value = 0.0015
            nt.links.new(brick.outputs["Fac"], seam.inputs["Height"])
            nt.links.new(seam.outputs["Normal"], bump.inputs["Normal"])
            # Fine-noise remains the final bump HEIGHT; seam normal feeds its NORMAL.
            # Neither plank color nor seam construction can replace the woodgrain.
        if style == "linen":
            bs.inputs["Sheen Weight"].default_value = 0.2
        m["detail_scale_per_m"] = scale
        m["bump_distance_m"] = bump.inputs["Distance"].default_value
        materials[key] = m
    for i, factor in enumerate((0.83, 0.92, 1.0, 1.07, 1.13)):
        m = materials["slate"].copy()
        m.name = "MC_slate_variant_" + str(i)
        materials["slate_" + str(i)] = m
        bs = m.node_tree.nodes.get("Principled BSDF")
        mix = next(x for x in m.node_tree.nodes if x.bl_idname == "ShaderNodeMixRGB")
        for pin in (1, 2):
            c = mix.inputs[pin].default_value
            mix.inputs[pin].default_value = (
                c[0] * factor,
                c[1] * factor,
                c[2] * factor,
                1,
            )
    return materials
