"""Compare a typed Unreal plan's source references with the complete town.

This measures migration scope, not rendered density or saved-engine geometry.
Split native chunks can reference one source placement more than once.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def compare(assembly, plan, assembly_sha256):
    if plan["source_assembly_sha256"] != assembly_sha256:
        raise ValueError("Typed plan belongs to a different source assembly")
    placements = assembly["placements"]
    source = {row["id"]: row for row in placements}
    if len(source) != len(placements):
        raise ValueError("Duplicate source placement identity")
    references = Counter(
        identity for unit in plan["units"] for entry in unit["entries"]
        for identity in entry["source_placement_ids"]
    )
    unknown = sorted(references.keys() - source.keys())
    if unknown:
        raise ValueError("Unknown native-plan source identities: " + repr(unknown[:12]))
    selected = references.keys()
    categories = {key: defaultdict(lambda: [0, 0]) for key in
                  ("source_stage", "semantic_group", "vegetation_role", "tree_lod")}
    tiles = defaultdict(lambda: [0, 0, 0, 0])
    for identity, row in source.items():
        present = identity in selected
        extras = row.get("extras") or {}
        values = {"source_stage": row["source_stage"],
                  "semantic_group": row.get("semantic_group", "unclassified")}
        role = extras.get("vegetation_role")
        if role:
            values["vegetation_role"] = role
        if role == "tree":
            values["tree_lod"] = extras.get("lod", "unspecified")
        for key, value in values.items():
            categories[key][str(value)][0] += 1
            categories[key][str(value)][1] += int(present)
        if role in ("tree", "understory"):
            low, high = row["world_bounds"]
            x, z = ((low[axis] + high[axis]) * 0.5 for axis in (0, 2))
            cell = (math.floor(x / 64), math.floor(z / 64))
            offset = 0 if role == "tree" else 2
            tiles[cell][offset] += 1
            tiles[cell][offset + 1] += int(present)

    def counts(total, included):
        return {"source_placements": total, "plan_referenced_placements": included,
                "unreferenced_placements": total - included}

    return {
        "schema": "living_town.native_plan_coverage.v1",
        "status": "COMPLETE_REFERENCE_MEMBERSHIP" if len(selected) == len(source)
                  else "PARTIAL_REFERENCE_MEMBERSHIP",
        "source_assembly_sha256": assembly_sha256,
        "totals": counts(len(source), len(selected)),
        "native_plan_entries": sum(len(unit["entries"]) for unit in plan["units"]),
        "source_references_in_multiple_entries": sum(n > 1 for n in references.values()),
        "by_category": {key: {value: counts(*pair) for value, pair in sorted(rows.items())}
                        for key, rows in categories.items()},
        "vegetation_cells_64m": [
            {"x": x, "z": z, "trees": counts(row[0], row[1]),
             "understory": counts(row[2], row[3])}
            for (x, z), row in sorted(tiles.items())
        ],
        "measurement_limits": [
            "Plan source-ID membership only; saved asset or rendered coverage needs native readback.",
            "A reference to a split source does not prove that all source triangles were migrated.",
            "Vegetation counts require explicit source tags and do not count untagged street trees.",
            "64m cells use transformed bounds centres in glTF X/Z metres, not canopy coverage.",
            "These counts do not establish ecological density, appearance, startup or frame rate.",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assembly", type=Path, required=True)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Fresh coverage output required")
    report = compare(json.loads(args.assembly.read_text(encoding="utf-8-sig")),
                     json.loads(args.plan.read_text(encoding="utf-8-sig")), sha256(args.assembly))
    report["inputs"] = [{"path": str(path.resolve()), "sha256": sha256(path)}
                        for path in (args.assembly, args.plan)]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as stream:
        json.dump(report, stream, indent=2)
        stream.write("\n")
    print(json.dumps({key: report[key] for key in ("status", "totals")}))


if __name__ == "__main__":
    main()
