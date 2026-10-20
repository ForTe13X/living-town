"""Conventional Blender/glTF material wiring for externally provenanced scans.

Run inside Blender. No engine, downloads, scan synthesis, roughness inference or
normal reconstruction. Existing MetricUV coordinates encode world metres / 2.
Returns ``(material, report)``. A supplied contextual facade image is retained as
an UNLINKED baking reference; the portable material continues to show the scan.
"""

import hashlib
import math
from pathlib import Path

import bpy


def _file(value, role):
    path = Path(value).expanduser().resolve(strict=True)
    if not path.is_file():
        raise ValueError(f"{role} must be an existing image file: {path}")
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    return path, {"path": path.as_posix(), "sha256": digest,
                  "bytes": path.stat().st_size}


def _finite(value, label):
    value = float(value)
    if not math.isfinite(value):
        raise ValueError(f"{label} must be finite")
    return value


def _repeat(value):
    if isinstance(value, (int, float)):
        values = (_finite(value, "repeat_metres"),) * 2
    else:
        values = tuple(_finite(item, "repeat_metres") for item in value)
        if len(values) != 2:
            raise ValueError("repeat_metres must be a scalar or an (U, V) pair")
    if min(values) <= 0:
        raise ValueError("repeat_metres must be positive")
    return values


def _image(path, color_space):
    image = bpy.data.images.load(str(path), check_existing=True)
    # Color space belongs to the image datablock, not the texture node. Do not
    # silently change an existing material if it uses this file in another role.
    if image.colorspace_settings.name != color_space and image.users:
        image = image.copy()
        image.name = path.stem + "_" + color_space.replace("-", "")
    image.colorspace_settings.name = color_space
    return image


def _texture(nodes, links, label, image, coordinates, location):
    node = nodes.new("ShaderNodeTexImage")
    node.name = label
    node.label = label
    node.image = image
    node.extension = "REPEAT"
    node.interpolation = "Linear"
    node.location = location
    links.new(coordinates, node.inputs["Vector"])
    return node


def build_scanned_material(name, *, basecolor, roughness, normal, repeat_metres,
                           tint=(1, 1, 1), roughness_scale=1, normal_strength=1,
                           context_map=None):
    """Build a source-bound scanned dielectric material and explicit report.

    ``tint`` is a LINEAR RGB multiplier in [0, 1], not an sRGB swatch. The scalar
    ``roughness_scale`` is clamped to [.04, 1] and multiplies the scanned map;
    this does NOT assert that every resulting roughness texel is at least .04.
    A pixel-wise floor/brightening requires an explicitly baked map instead.

    Positive UV scale is ``(2 / repeat_U, 2 / repeat_V)``. A standard Mapping
    node allows Blender's glTF exporter to represent it with KHR_texture_transform.
    Texture normal data must already use OpenGL tangent-space +Y; no convention
    conversion, image-derived height or normal reconstruction is performed.

    A supplied ``context_map`` is loaded with FacadeContextUV into an UNLINKED
    reference node. Proposed contextual grime is a normalized luminance ratio
    clamped to [.88, 1] (at most 12 percent darkening) multiplying the fine scan.
    It is not applied here: combining separate context and repeating scan UVs
    requires a baked basecolor for faithful glTF export. The report exposes this
    pending bake; an unbaked custom shader is never advertised as portable.
    """
    repeat_u, repeat_v = _repeat(repeat_metres)
    tint = tuple(_finite(value, "tint") for value in tint)
    if len(tint) != 3 or min(tint) < 0 or max(tint) > 1:
        raise ValueError("Linear tint needs three values in [0,1]; brightening above 1 must be baked")
    requested_roughness_scale = _finite(roughness_scale, "roughness_scale")
    effective_roughness_scale = max(.04, min(1., requested_roughness_scale))
    normal_strength = _finite(normal_strength, "normal_strength")
    if normal_strength < 0:
        raise ValueError("normal_strength must be nonnegative")
    paths, provenance = {}, {}
    for role, value in (("basecolor", basecolor), ("roughness", roughness), ("normal", normal)):
        paths[role], provenance[role] = _file(value, role)
    if paths["basecolor"] in (paths["roughness"], paths["normal"]):
        raise ValueError("Basecolor sRGB and non-color PBR roles require distinct source files")
    context_path = None
    if context_map is not None:
        context_path, provenance["context_reference"] = _file(context_map, "context_map")

    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = (*tint, 1)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    output.location = (800, 100)
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.location = (520, 100)
    shader.inputs["Metallic"].default_value = 0
    shader.inputs["Alpha"].default_value = 1
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])

    uv = nodes.new("ShaderNodeUVMap")
    uv.name = "Physical MetricUV source"
    uv.uv_map = "MetricUV"
    uv.location = (-900, 120)
    mapping = nodes.new("ShaderNodeMapping")
    mapping.name = "Scan repeat in metres"
    mapping.label = f"2m UV basis / scan repeat ({repeat_u:g}, {repeat_v:g}) m"
    mapping.vector_type = "POINT"
    mapping.inputs["Scale"].default_value = (2 / repeat_u, 2 / repeat_v, 1)
    mapping.location = (-700, 120)
    links.new(uv.outputs["UV"], mapping.inputs["Vector"])
    textures = {}
    for index, (role, color_space) in enumerate((
        ("basecolor", "sRGB"), ("roughness", "Non-Color"), ("normal", "Non-Color")
    )):
        image = _image(paths[role], color_space)
        provenance[role]["color_space"] = color_space
        provenance[role]["dimensions"] = list(image.size)
        textures[role] = _texture(nodes, links, "Scanned " + role, image,
                                  mapping.outputs["Vector"], (-400, 300 - 300 * index))

    # Blender 5.2's glTF exporter recognizes the modern RGBA Mix Multiply with
    # one constant operand as baseColorFactor. Legacy MixRGB is not used.
    if tint == (1., 1., 1.):
        links.new(textures["basecolor"].outputs["Color"], shader.inputs["Base Color"])
    else:
        multiply = nodes.new("ShaderNodeMix")
        multiply.name = "Linear scan tint factor"
        multiply.data_type = "RGBA"
        multiply.blend_type = "MULTIPLY"
        multiply.clamp_factor = True
        multiply.clamp_result = False
        multiply.inputs[0].default_value = 1
        if multiply.inputs[6].type != "RGBA" or multiply.inputs[7].type != "RGBA":
            raise RuntimeError("Blender RGBA Mix socket layout changed; inspect before export")
        multiply.inputs[7].default_value = (*tint, 1)
        multiply.location = (0, 300)
        links.new(textures["basecolor"].outputs["Color"], multiply.inputs[6])
        links.new(multiply.outputs[2], shader.inputs["Base Color"])

    if effective_roughness_scale == 1:
        links.new(textures["roughness"].outputs["Color"], shader.inputs["Roughness"])
    else:
        rough_scale = nodes.new("ShaderNodeMath")
        rough_scale.name = "Scanned roughness factor"
        rough_scale.operation = "MULTIPLY"
        rough_scale.use_clamp = False
        rough_scale.inputs[1].default_value = effective_roughness_scale
        rough_scale.location = (0, 0)
        links.new(textures["roughness"].outputs["Color"], rough_scale.inputs[0])
        links.new(rough_scale.outputs[0], shader.inputs["Roughness"])

    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.name = "OpenGL +Y scanned normal"
    normal_map.space = "TANGENT"
    normal_map.uv_map = "MetricUV"
    normal_map.inputs["Strength"].default_value = normal_strength
    normal_map.location = (0, -300)
    links.new(textures["normal"].outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], shader.inputs["Normal"])

    if context_path is not None:
        context_uv = nodes.new("ShaderNodeUVMap")
        context_uv.name = "UNLINKED context UV for future bake"
        context_uv.uv_map = "FacadeContextUV"
        context_uv.location = (-900, -650)
        context = _texture(nodes, links, "UNLINKED facade context - bake before applying",
                           _image(context_path, "sRGB"), context_uv.outputs["UV"], (-650, -650))
        context.extension = "EXTEND"
        # Deliberately no link to the surface shader. The caller receives an
        # explicit pending-bake record rather than a silent lossy glTF material.

    material["pbr_source_kind"] = "Externally provenanced coherent PBR images; photographed or procedural origin is recorded per source; no AI-derived PBR maps"
    material["pbr_uv_basis"] = "MetricUV = world metres / 2"
    material["pbr_context_applied"] = False
    material["pbr_requested_context_requires_bake"] = context_path is not None
    report = {
        "schema": "living_town.scanned_hero_material.v1", "material": material.name,
        "source_images": provenance,
        "license": "Not inferred from images or filenames. Caller must retain and verify the actual CC0 scan provenance.",
        "uv": {"layer": "MetricUV", "basis_metres_per_uv_unit": 2.,
               "repeat_metres": [repeat_u, repeat_v], "mapping_scale": [2 / repeat_u, 2 / repeat_v],
               "expected_export_extension": "KHR_texture_transform when scale differs from 1"},
        "tint_linear_multiplier": list(tint),
        "roughness": {"requested_scale": requested_roughness_scale,
                      "effective_scale": effective_roughness_scale,
                      "scale_clamp": [.04, 1.], "pixel_floor_applied": False},
        "normal": {"convention": "OpenGL tangent-space +Y supplied by caller",
                   "strength": normal_strength, "reconstructed_from_rgb": False},
        "context": {"supplied": context_path is not None, "applied": False,
                    "uv_layer": "FacadeContextUV", "bake_required_for_requested_context": context_path is not None,
                    "proposed_bake_formula": "scan_linear_rgb * clamp(context_linear_luminance / mean_context_linear_luminance, .88, 1.0)",
                    "maximum_context_darkening": .12,
                    "notes": "Context node is an unlinked reference. No flat contextual color replaces the fine scan; apply contextual grime only after an explicit basecolor bake."},
        "current_surface_graph": "Single MetricUV, Mapping, scan image textures, constant linear factors and tangent normal; conventional glTF material pattern",
        "export_verification_required": ["Every assigned mesh has MetricUV", "TANGENT coverage on normal-mapped primitives",
                                         "Embedded images and physical UV scale retained", "Tint/roughness factors retained in actual GLB"],
        "inference_executed": False,
    }
    return material, report
