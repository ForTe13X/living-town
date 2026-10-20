"""Inspect the actual exported contextual wall geometry and its height sources.

This supplements verify_scanned_exports: it does not repeat embedded image pixel
parity, render an engine, or grant artistic acceptance. Only the three authored
wall skins are decoded, so fine foliage arrays are not expanded into Python.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct

try:
    from .verify_outputs import GLB, _world_nodes, _point
except ImportError:
    from verify_outputs import GLB, _world_nodes, _point


CENTRES = {"WallSkin_cafe": 0., "WallSkin_left": -7.2, "WallSkin_right": 7.2}
REPO = Path(__file__).resolve().parents[2]
TOLERANCE = .00002


def _need(value, message):
    if not value:
        raise ValueError(message)


def _sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


class WallGLB(GLB):
    """Use the existing GLB reader, decoding vertex accessors only on demand."""
    def _validate_buffers(self):
        for view in self.doc.get("bufferViews", []):
            start, length = view.get("byteOffset", 0), view["byteLength"]
            _need(view.get("buffer") == 0 and start >= 0 and length > 0
                  and start + length <= self.length, "Invalid embedded bufferView")
        for image in self.doc.get("images", []):
            _need("uri" not in image and "bufferView" in image,
                  "Wall export must contain embedded images")
            view = self.doc["bufferViews"][image["bufferView"]]
            start = view.get("byteOffset", 0)
            prefix = self.binary[start:start + 8]
            mime = image.get("mimeType")
            _need((mime == "image/png" and prefix == b"\x89PNG\r\n\x1a\n")
                  or (mime == "image/jpeg" and prefix[:3] == b"\xff\xd8\xff"),
                  "Invalid embedded image signature")


def _area(points):
    return abs(sum(points[i][0] * points[(i + 1) % len(points)][1]
                   - points[(i + 1) % len(points)][0] * points[i][1]
                   for i in range(len(points)))) * .5 if len(points) >= 3 else 0.


def _clip(points, axis, boundary, greater):
    """Clip a 2D polygon to one inclusive rectangle half-plane."""
    if not points:
        return []
    result = []
    previous = points[-1]
    previous_in = previous[axis] >= boundary if greater else previous[axis] <= boundary
    for current in points:
        current_in = current[axis] >= boundary if greater else current[axis] <= boundary
        if current_in != previous_in:
            ratio = (boundary - previous[axis]) / (current[axis] - previous[axis])
            result.append(tuple(previous[k] + ratio * (current[k] - previous[k]) for k in range(2)))
        if current_in:
            result.append(current)
        previous, previous_in = current, current_in
    return result


def _aperture_overlap(triangle, aperture, center_x):
    x, z, width, height = aperture
    # Shrinking by one micrometre accepts shared aperture boundary edges without
    # accepting even a thin triangle that crosses the opening's interior.
    bounds = ((0, x + center_x - width / 2 + 1e-6, True),
              (0, x + center_x + width / 2 - 1e-6, False),
              (1, z - height / 2 + 1e-6, True),
              (1, z + height / 2 - 1e-6, False))
    points = [(point[0], point[1]) for point in triangle]
    for axis, boundary, greater in bounds:
        points = _clip(points, axis, boundary, greater)
    return _area(points)


def check_geometry_arrays(positions, normals, uvs, indices, geometry, center_x):
    """Validate world-space glTF [Blender X, Z, -Y] arrays independently."""
    width, height = geometry["width_m"], geometry["height_m"]
    low, high = geometry["height_range_m"]
    front_y = geometry["base_front_y_m"]
    _need(positions and len(positions) == len(normals) == len(uvs), "Wall attribute counts differ")
    _need(indices and len(indices) % 3 == 0 and min(indices) >= 0
          and max(indices) < len(positions), "Invalid wall triangle indices")
    _need(all(len(p) == 3 and all(math.isfinite(v) for v in p) for p in positions),
          "Invalid wall positions")
    depths = []
    maximum_uv_error = 0.
    for position, normal, uv in zip(positions, normals, uvs):
        x, z, depth = position
        _need(center_x - width / 2 - TOLERANCE <= x <= center_x + width / 2 + TOLERANCE
              and -TOLERANCE <= z <= height + TOLERANCE, "Wall vertex escapes facade dimensions")
        displacement = depth + front_y
        _need(low - TOLERANCE <= displacement <= high + TOLERANCE,
              "Wall displacement has wrong front direction or height decode")
        depths.append(displacement)
        _need(len(normal) == 3 and all(math.isfinite(v) for v in normal)
              and abs(sum(v * v for v in normal) - 1) < .005 and normal[2] > .9,
              "Wall normal is not a unit outward +Z vector")
        _need(len(uv) == 2 and all(math.isfinite(v) for v in uv), "Invalid wall UV")
        expected = ((x - center_x + width / 2) / 2, 1 - z / 2)
        maximum_uv_error = max(maximum_uv_error, *(abs(a - b) for a, b in zip(uv, expected)))
    _need(maximum_uv_error <= TOLERANCE, "Wall MetricUV orientation or facade origin changed")
    actual_bounds = [min(depths), max(depths)]
    expected_bounds = geometry["actual_displacement_range_m"]
    # The authoring grid retains isolated vertices inside aperture holes. glTF
    # exports only vertices consumed by triangles, so its extrema may be narrower
    # than the report's range over ALL original grid vertices.
    _need(expected_bounds[0] - TOLERANCE <= actual_bounds[0] <= actual_bounds[1]
          <= expected_bounds[1] + TOLERANCE,
          "Exported used-vertex displacement escapes the authoring grid range")
    for axis, bounds in ((0, (center_x - width / 2, center_x + width / 2)), (1, (0, height))):
        _need(abs(min(p[axis] for p in positions) - bounds[0]) <= TOLERANCE
              and abs(max(p[axis] for p in positions) - bounds[1]) <= TOLERANCE,
              "Wall no longer spans the complete facade")
    max_grid = geometry["maximum_grid_spacing_m"]
    triangle_count = len(indices) // 3
    for offset in range(0, len(indices), 3):
        ids = indices[offset:offset + 3]
        a, b, c = triangle = [positions[index] for index in ids]
        # Positive projected XY area is outward +Z in exported glTF space.
        winding = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        _need(winding > 1e-12, "Wall triangle is degenerate or has inward winding")
        _need(all(max(p[axis] for p in triangle) - min(p[axis] for p in triangle)
                  <= max_grid + TOLERANCE for axis in (0, 1)), "Wall triangle bridges grid cells")
        uv_triangle = [uvs[index] for index in ids]
        _need(_area(uv_triangle) > 1e-13, "Wall triangle has zero UV area")
        for aperture in geometry["apertures_x_z_width_height_m"]:
            _need(_aperture_overlap(triangle, aperture, center_x) <= 1e-12,
                  "Wall triangle bridges a true aperture interior")
    _need(triangle_count == 2 * geometry["mesh_quad_count"],
          "Wall triangle count differs from its source quads")
    return {"vertices": len(positions), "triangles": triangle_count,
            "actual_displacement_range_m": actual_bounds,
            "authoring_all_grid_vertex_displacement_range_m": expected_bounds,
            "displacement_comparison": "Exported triangle-used vertex range must be contained in the authoring range over all grid vertices, including unused aperture vertices; equality is not required.",
            "maximum_metric_uv_error": maximum_uv_error,
            "apertures_checked": len(geometry["apertures_x_z_width_height_m"]),
            "triangle_winding": "outward +Z", "zero_uv_area_triangles": 0,
            "aperture_crossing_triangles": 0}


def _normal_world(matrix, normal):
    a, b, c = (row[:3] for row in matrix[:3])
    # Cofactor matrix / determinant is the inverse transpose for normal vectors.
    cofactors = ((b[1]*c[2]-b[2]*c[1], b[2]*c[0]-b[0]*c[2], b[0]*c[1]-b[1]*c[0]),
                 (a[2]*c[1]-a[1]*c[2], a[0]*c[2]-a[2]*c[0], a[1]*c[0]-a[0]*c[1]),
                 (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]))
    determinant = sum(a[k] * cofactors[0][k] for k in range(3))
    _need(abs(determinant) > 1e-12, "Wall node has singular transform")
    result = [sum(row[k] * normal[k] for k in range(3)) / determinant for row in cofactors]
    length = math.sqrt(sum(v * v for v in result))
    _need(length > .001, "Wall has zero transformed normal")
    return tuple(v / length for v in result)


def _material(document, material, width, height):
    pbr = material["pbrMetallicRoughness"]
    _need(pbr.get("metallicFactor", 1) == 0 and material.get("alphaMode", "OPAQUE") == "OPAQUE",
          "Wall must retain an opaque dielectric material")
    slots = (pbr["baseColorTexture"], pbr["metallicRoughnessTexture"], material["normalTexture"])
    coordinates = set()
    for slot in slots:
        transform = slot.get("extensions", {}).get("KHR_texture_transform", {})
        coordinates.add(transform.get("texCoord", slot.get("texCoord", 0)))
        scale = transform.get("scale", [1, 1])
        offset = transform.get("offset", [0, 0])
        _need(len(scale) == len(offset) == 2
              and all(abs(a-b) < 1e-5 for a,b in zip(scale, (2/width, 2/height)))
              and all(abs(a-b) < 1e-5 for a,b in zip(offset, (0, 1-2/height)))
              and abs(transform.get("rotation", 0)) < 1e-6,
              "Wall texture transform lost physical facade scale or Blender V flip")
        texture = document["textures"][slot["index"]]
        image = document["images"][texture["source"]]
        _need("bufferView" in image and "uri" not in image, "Wall PBR image is not embedded")
    _need(coordinates == {0}, "Wall PBR roles must use the single MetricUV export set")
    return {"name": material["name"], "normal_strength": material["normalTexture"].get("scale", 1),
            "pbr_roles": ["basecolor", "roughness", "normal"],
            "physical_mapping_scale": [2/width, 2/height], "embedded_pixels_checked": False}


def _source(geometry, scan, generator_sha, library_sha):
    from PIL import Image
    baked = scan["source_asset"]["wall_bake"]
    source_images = scan["source_images"]
    folder = Path(source_images["basecolor"]["path"]).parent
    path = folder / "wall_manifest.json"
    expected_sha = geometry["wall_manifest_sha256"]
    _need(path.is_file() and _sha(path) == expected_sha
          == scan["source_asset"]["wall_bake_manifest_sha256"], "Wall bake manifest SHA changed")
    _need(json.loads(path.read_text(encoding="utf-8")) == baked, "Recorded wall bake differs from source")
    _need(baked["generator_sha256"] == generator_sha, "Wall bake generator is stale")
    _need(baked["source_library_sha256"] == library_sha, "Wall bake source library differs from hero")
    _need(baked["facade_dimensions_metres"] == [geometry["width_m"], geometry["height_m"]],
          "Wall bake dimensions disagree with source mesh")
    _need(baked["source_license"] == "CC0-1.0" and baked["ai_inference_executed"] is False,
          "Unexpected wall source route")
    for role, row in baked["maps"].items():
        file = (folder / row["path"]).resolve()
        _need(file.is_relative_to(folder.resolve()) and file.is_file() and _sha(file) == row["sha256"],
              "Wall source map SHA changed: " + role)
        with Image.open(file) as image:
            _need(list(image.size) == row["dimensions"], "Wall map dimensions changed: " + role)
            if role == "height":
                _need(image.mode in ("I;16", "I;16L", "I;16B", "I") and row["bit_depth"] == 16,
                      "Wall height is not declared uint16")
                _need(0 <= image.getextrema()[0] <= image.getextrema()[1] <= 65535,
                      "Wall height pixels are outside uint16 range")
        if role in source_images:
            _need(file == Path(source_images[role]["path"]).resolve()
                  and row["sha256"] == source_images[role]["sha256"],
                  "Material no longer binds the contextual wall bake: " + role)
    encoding = baked["height_encoding"]
    _need([encoding["minimum_metres"], encoding["maximum_metres"]] == geometry["height_range_m"],
          "Wall mesh height decode differs from bake")
    return {"wall_manifest_sha256": expected_sha, "height_sha256": baked["maps"]["height"]["sha256"],
            "generator_sha256": generator_sha, "height_range_m": geometry["height_range_m"],
            "height_authority": encoding["physical_scale_authority"]}


def verify(hero):
    hero = Path(hero).resolve()
    manifest_path = hero / "hero_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    _need(manifest.get("schema") == "living_town.reconstructed_cafe_hero.v1", "Unknown hero schema")
    geometry = {row["object"]: row for row in manifest["contextual_wall_skins"]}
    _need(set(geometry) == set(CENTRES), "Expected exactly cafe, left and right contextual wall skins")
    generator_sha = _sha(REPO / "tools/asset_refinement/hero_walls.py")
    modules = {key.replace("\\", "/"): value for key, value in manifest["source_modules"].items()}
    _need(modules["tools/asset_refinement/hero_walls.py"] == generator_sha, "Hero recorded a stale wall generator")
    files = {key.replace("\\", "/"): row for key, row in manifest["files"].items()}
    path = hero / "cafe_hero.glb"
    _need(_sha(path) == files["cafe_hero.glb"]["sha256"], "Hero GLB differs from its source-bound manifest")
    glb = WallGLB(path)
    world = _world_nodes(glb.doc)
    selected = {}
    for index in world:
        name = glb.doc["nodes"][index].get("name", "")
        if name.startswith("WallSkin_"):
            _need(name not in selected, "Duplicate exported wall node name")
            selected[name] = index
    _need(set(selected) == set(CENTRES), "Missing or unexpected exported wall skin")
    scan_records = {row["material"]: row for row in manifest["scanned_materials"]}
    results = []
    material_indices = set()
    for name, node_index in selected.items():
        node = glb.doc["nodes"][node_index]
        row = geometry[name]
        _need(node.get("extras", {}).get("wall_bake_manifest_sha256") == row["wall_manifest_sha256"],
              "Wall node lost its bake source binding")
        primitives = glb.doc["meshes"][node["mesh"]]["primitives"]
        _need(len(primitives) == 1, "Each authored wall skin should have one PBR primitive")
        primitive = primitives[0]
        _need(primitive.get("mode", 4) == 4, "Wall is not explicitly triangulated")
        attributes = primitive["attributes"]
        _need({"POSITION", "NORMAL", "TEXCOORD_0", "TANGENT"}.issubset(attributes),
              "Wall lacks portable position/normal/UV/tangent attributes")
        positions = [_point(world[node_index], p) for p in glb.accessor(attributes["POSITION"])]
        raw_normals = glb.accessor(attributes["NORMAL"])
        _need(all(len(n) == 3 and abs(sum(v*v for v in n)-1) < .005 for n in raw_normals),
              "Wall source normal is invalid")
        normals = [_normal_world(world[node_index], n) for n in raw_normals]
        uvs = glb.accessor(attributes["TEXCOORD_0"])
        tangents = glb.accessor(attributes["TANGENT"])
        _need(len(tangents) == len(positions) and all(len(t) == 4
              and abs(sum(v*v for v in t[:3])-1) < .005 and abs(abs(t[3])-1) < .001 for t in tangents),
              "Wall tangent basis is invalid")
        accessor = glb.doc["accessors"][primitive["indices"]]
        _need(accessor["type"] == "SCALAR" and accessor["componentType"] in (5121, 5123, 5125),
              "Invalid wall index accessor")
        indices = [index[0] for index in glb.accessor(primitive["indices"])]
        arrays = check_geometry_arrays(positions, normals, uvs, indices, row, CENTRES[name])
        material_index = primitive["material"]
        material_indices.add(material_index)
        material = glb.doc["materials"][material_index]
        expected_name = "Hero_" + name + "_BakedLimewash"
        _need(material["name"] == expected_name, "Wall has the wrong contextual PBR material")
        material_report = _material(glb.doc, material, row["width_m"], row["height_m"])
        source_report = _source(row, scan_records[expected_name], generator_sha,
                                manifest["pbr_library_sha256"])
        results.append({"object": name, "status": "PASS", "center_x_m": CENTRES[name],
                        "center_authority": "Exact authored WallSkin name contract; source report has no center field",
                        "geometry": arrays, "material": material_report, "source": source_report})
    _need(len(material_indices) == 3, "Wall skins lost their three distinct contextual materials")
    return {"schema": "living_town.wall_export_verification.v1", "status": "PASS",
            "hero_manifest_sha256": _sha(manifest_path), "glb_sha256": _sha(path),
            "verifier_source_sha256": _sha(Path(__file__)), "walls": results,
            "scope": "Actual world-space wall arrays, outward normals/winding, MetricUV orientation, nonzero UV area, grid span, true aperture intersection, source-bound uint16 height maps, current bake generator and three embedded PBR materials.",
            "limits": "No engine or visual acceptance; embedded PBR pixel parity is covered by verify_scanned_exports. Exported triangle-used displacement range must be contained in the authoring all-grid range, which can include unused aperture vertices. Does not reproduce Blender height resampling point by point or audit the rest of the town.",
            "engine_executed": False, "ai_inference_executed": False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hero", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args(argv)
    _need(not args.report.exists(), "Report already exists; refusing overwrite")
    try:
        result = verify(args.hero)
    except (ValueError, OSError, KeyError, IndexError, TypeError, struct.error) as error:
        result = {"schema": "living_town.wall_export_verification.v1", "status": "FAIL", "error": str(error)}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open("x", encoding="utf-8") as stream:
        json.dump(result, stream, indent=2)
        stream.write("\n")
    print(json.dumps({key: result[key] for key in ("status", "error") if key in result}))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
