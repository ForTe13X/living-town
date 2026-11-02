"""Small input loader and construction invariants; Python standard library only."""

from pathlib import Path
import json, math, re
from .design import build

PACKAGE = Path(__file__).resolve().parent
PROJECT = PACKAGE.parents[1]
DEFAULT_PLAN = PROJECT / "art/planning_revision/mill_court/v1/floorplans.json"
BLEND_FILENAME = "MillCourt_TwoHouse_Prototype.blend"


def load_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def load_inputs(
    plan=DEFAULT_PLAN,
    site=PACKAGE / "data/site.json",
    terrain=PACKAGE / "data/terrain.json",
    views=PACKAGE / "data/views.json",
):
    return (
        load_json(plan),
        load_json(site),
        load_json(terrain),
        validate_views(load_json(views)),
    )


def _require(v, m):
    if not v:
        raise ValueError(m)


def validate_views(views):
    _require(isinstance(views, list) and bool(views), "Views must be a nonempty list")
    seen = set()
    reserved = {
        "CON",
        "PRN",
        "AUX",
        "NUL",
        *[f"COM{i}" for i in range(1, 10)],
        *[f"LPT{i}" for i in range(1, 10)],
    }
    for view in views:
        key = view.get("id") if isinstance(view, dict) else None
        _require(
            isinstance(key, str)
            and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", key) is not None
            and key.upper() not in reserved,
            "View IDs must be safe portable leaf names: letters, digits, underscores or hyphens",
        )
        _require(
            key.casefold() not in seen,
            "View IDs must be unique, including case-insensitive filesystems",
        )
        seen.add(key.casefold())
    return views


def saved_blend_path(source_output, saved):
    """Read the chosen package's exact local blend; old author path is provenance only."""
    source = Path(source_output).resolve()
    _require(
        saved.get("file", BLEND_FILENAME) == BLEND_FILENAME,
        "Unexpected saved blend filename",
    )
    blend = (source / BLEND_FILENAME).resolve()
    _require(
        blend.parent == source and blend.is_file(),
        "Saved blend must exist inside the selected source-output directory",
    )
    return blend


def expected_asset_counts(plans, spec):
    expected = [
        (p["owner_id"], p["id"], f["id"]) for p in plans for f in p["furniture"]
    ]
    actual = [(f["owner"], f["plan"], f["id"]) for f in spec["furniture"]]
    _require(
        len(actual) == len(expected) and set(actual) == set(expected),
        "Compiled furniture must match the bound floorplans",
    )
    ground = [p for p in plans if p["level_index"] == 0]
    _require(
        len(spec["stairs"]) == len(ground)
        and {(s["owner"], s["id"]) for s in spec["stairs"]}
        == {(p["owner_id"], p["stair"]["id"]) for p in ground},
        "Compiled stairs must match the bound ground plans",
    )
    return dict(
        furniture_assets=len(expected),
        stairs=len(ground),
        risers=sum(p["stair"]["risers"] for p in ground),
        treads=sum(p["stair"]["treads"] for p in ground),
    )


def _overlap(a, b):
    return (
        min(a[2], b[2]) - max(a[0], b[0]) > 1e-9
        and min(a[3], b[3]) - max(a[1], b[1]) > 1e-9
    )


def validate(plan, site):
    rows = plan["plans"]
    owners = {p["owner_id"] for p in rows}
    _require(len({p["id"] for p in rows}) == len(rows), "Plan IDs must be unique")
    _require(
        owners == {p["id"] for p in site["new_owners"]},
        "Plan owners and site bindings must agree",
    )
    for owner in owners:
        levels = sorted(
            (p for p in rows if p["owner_id"] == owner), key=lambda p: p["level_index"]
        )
        _require(
            [p["level_index"] for p in levels] == [0, 1],
            "Each house needs ground and upper records",
        )
        low, high = levels
        o = next(o for o in site["new_owners"] if o["id"] == owner)
        _require(
            math.isclose(
                high["FF_world_m"] - low["FF_world_m"],
                plan["floor_to_floor_m"],
                abs_tol=1e-9,
            ),
            "Floor-to-floor mismatch",
        )
        expected = [
            low["world_inner_southwest_xy_m"][0] + low["clear_width_m"] / 2,
            low["world_inner_southwest_xy_m"][1] + low["clear_depth_m"] / 2,
        ]
        _require(
            all(math.isclose(a, b, abs_tol=1e-9) for a, b in zip(expected, o["center"]))
            and math.isclose(low["FF_world_m"], o["finished_floor_z_m"], abs_tol=1e-9),
            "Site centre/FF must bind the actual room plan",
        )
        _require(
            math.isclose(low["clear_width_m"] + 0.6, o["width"], abs_tol=1e-9)
            and math.isclose(low["clear_depth_m"] + 0.6, o["depth"], abs_tol=1e-9),
            "Site footprint must include300mm outer walls",
        )
        _require(
            high["floor_slab"]["opening_bounds_m"]
            == high["stair_void_bounds_m"]
            == low["stair"]["opening_bounds_m"]
            == high["stair"]["opening_bounds_m"],
            "Actual upper slab, stair and room void declarations must agree",
        )
        for p in levels:
            s = p["stair"]
            _require(
                s["risers"] == 14
                and s["treads"] == 13
                and math.isclose(
                    s["risers"] * s["riser_m"], plan["floor_to_floor_m"], abs_tol=1e-9
                ),
                "Stair rise/tread declaration mismatch",
            )
            for dr in p["doors"]:
                _require(
                    dr["rough_opening_width_m"]
                    >= dr["clear_width_m"] + 2 * dr["jamb_width_m"] - 1e-9
                    and dr["rough_opening_height_m"]
                    >= dr["height_m"] + dr["jamb_width_m"],
                    "Rough openings must fit clear passages and jambs",
                )
                if dr["kind"] != "pocket":
                    continue
                vertical = dr["opening_axis"] == "vertical"
                at = dr["at_m"]
                a, b = sorted(dr["pocket_extent_m"])
                half = dr["leaf_thickness_m"] / 2
                core = (
                    [at - half, a, at + half, b]
                    if vertical
                    else [a, at - half, b, at + half]
                )
                for wall in p["walls"]:
                    axis = wall["axis"] == "vertical"
                    if (
                        axis == vertical
                        and abs(wall["at_m"] + wall["thickness_m"] / 2 - at) < 1e-9
                    ):
                        continue
                    box = (
                        [
                            wall["at_m"],
                            wall["start_m"],
                            wall["at_m"] + wall["thickness_m"],
                            wall["end_m"],
                        ]
                        if axis
                        else [
                            wall["start_m"],
                            wall["at_m"],
                            wall["end_m"],
                            wall["at_m"] + wall["thickness_m"],
                        ]
                    )
                    _require(
                        not _overlap(core, box),
                        "Partition intrudes into pocket-door travel: "
                        + p["id"]
                        + "/"
                        + wall["id"],
                    )
    return plan


def compile_geometry(plan, site):
    validate(plan, site)
    # Public geometry is JSON-native in memory too; no tuple/list discrepancy
    # between a direct compiler call and its portable file representation.
    return json.loads(json.dumps(build(plan, site), allow_nan=False))


def terrain_mesh(grid):
    if grid["schema"] == "MillCourtImmutableSourceHeightfieldStudyPatch.v1":
        return grid
    _require(
        grid["schema"] == "MillCourtHeightGrid.v1", "Unsupported heightfield format"
    )
    width = grid["width"]
    height = grid["height"]
    z = grid["height_values_z_m"]
    _require(len(z) == width * height, "Heightfield count mismatch")
    x, y = grid["origin_xy_m"]
    step = grid["spacing_m"]
    vertices = [
        [x + i * step, y + j * step, z[j * width + i]]
        for j in range(height)
        for i in range(width)
    ]
    faces = [
        [j * width + i, j * width + i + 1, (j + 1) * width + i + 1, (j + 1) * width + i]
        for j in range(height - 1)
        for i in range(width - 1)
    ]
    return dict(
        schema="MillCourtImmutableSourceHeightfieldStudyPatch.v1",
        vertices=vertices,
        faces=faces,
    )
