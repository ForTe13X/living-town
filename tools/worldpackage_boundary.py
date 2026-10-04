"""LT-22 frozen cafe and adjoining street mapping; not a generator or v5 consumer.

The explicit snapshot profile cannot be loaded by the existing WorldPackage
validator. Host action definitions stay outside the package and are hash-bound.
No live topology replacement or TownState mutation is provided.
"""
import copy
import hashlib
import json
from fractions import Fraction
from pathlib import Path

FRAME = {"id": "plan_xz_q48/1", "q_per_cell": 48,
         "x_axis": "east", "z_axis": "south", "height": "floor_id_only"}
ROOT_KEYS = {"schema_id", "schema_version", "logical_scope", "coordinate_frame",
             "producer_ref", "input_refs", "payload", "capabilities", "validation_ref"}
PROFILE = "lt22.cafe_street_snapshot/1"
FROZEN_TOPOLOGY_SHA256 = "508cebb8815419f4e0db4e6389825c49090a9bc103037b53595ce5b904ce7620"


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=True,
                                    separators=(",", ":")).encode()).hexdigest()


def canonical_value(value):
    if value is None or type(value) is bool:
        return True
    if type(value) is int:
        return -(2**31) <= value < 2**31
    if type(value) is str:
        return value.isascii()
    if type(value) is list:
        return all(canonical_value(v) for v in value)
    if type(value) is dict:
        return all(type(k) is str and k.isascii() and canonical_value(v)
                   for k, v in value.items())
    return False


def load_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON key: " + key)
            result[key] = value
        return result
    return json.loads(Path(path).read_text(encoding="utf-8"), object_pairs_hook=unique)


def integer(value):
    # Godot JSON emits authored integer cells as whole-valued doubles.
    if isinstance(value, bool) or not isinstance(value, (int, float)) or int(value) != value:
        raise ValueError("nonintegral cell or capacity")
    value = int(value)
    if not -(2**31) <= value < 2**31:
        raise ValueError("int32 overflow")
    return value


def _logical_ids(records, label, errors):
    if not isinstance(records, list):
        errors.append("E_" + label + "_LIST")
        return set()
    result = set()
    for record in records:
        logical_id = record.get("id") if isinstance(record, dict) else None
        if type(logical_id) is not str or not logical_id or logical_id in result:
            errors.append("E_" + label + "_ID")
            continue
        result.add(logical_id)
    return result


def _check_occupied(occupied, available, label, errors):
    if not isinstance(occupied, (tuple, list, set, frozenset)):
        errors.append("E_OCCUPIED_" + label + "_INPUT")
        return
    for identity in occupied:
        if type(identity) is not str or not identity:
            errors.append("E_OCCUPIED_" + label + "_INPUT")
        elif identity not in available:
            errors.append("E_OCCUPIED_" + label + "_REMOVED")


def _frontage(plan, ledger, door, town_bounds):
    """Freeze the authored market-walk segment and its cafe entrance link.

    Source street width is a decimal cell count, so preserve it as an exact
    rational. The clipped town navigation plane remains the walkability oracle.
    """
    spec = ledger["streets"]["market_walk"]
    street, = [s for s in plan["streets"] if s["id"] == "market_walk"]
    geometry = {"id": street["id"], "width": street["width"], "points": street["points"]}
    if digest(geometry) != spec["source_geometry_sha256"]:
        raise ValueError("market_walk geometry changed; explicit ledger revision required")
    segment = integer(spec["segment_index"])
    if segment < 0 or segment + 1 >= len(street["points"]):
        raise ValueError("market_walk frontage segment is missing")
    width = Fraction(str(street["width"]))
    if width <= 0:
        raise ValueError("market_walk width must be positive")
    link, = [item for item in plan["links"] if item["entrance"] == door["from"]["pos"]]
    if digest(link) != spec["source_link_sha256"]:
        raise ValueError("cafe entrance link changed; explicit ledger revision required")
    return {"id": spec["logical_id"], "source_id": street["id"],
            "space": "town", "floor": "outdoor",
            "sample_bounds_q": [integer(v) * 48 for v in town_bounds],
            "segment_index": segment,
            "path_q": [[integer(v) * 48 for v in point]
                       for point in street["points"][segment:segment + 2]],
            "width_cells_ratio": [width.numerator, width.denominator],
            "entrance_link_q": [[integer(v) * 48 for v in cell]
                                for cell in link["cells"]],
            "portal_id": ledger["portals"][door["id"]]}


def export_reference(inventory, ledger, coastal_plan):
    if ledger["profile"] != PROFILE:
        raise ValueError("unsupported identity ledger")
    for field in ("navigation", "portals"):
        if digest(inventory[field]) != ledger[field + "_sha256"]:
            raise ValueError("native %s changed; explicit ledger revision required" % field)
    if {o["id"] for o in inventory["objects"]} != set(ledger["objects"]):
        raise ValueError("object identity set changed; explicit ledger revision required")
    if {p["id"] for p in inventory["portals"]} != set(ledger["portals"]):
        raise ValueError("portal identity set changed")
    slots, affordances, bindings = [], [], {}
    for obj in inventory["objects"]:
        entry = ledger["objects"][obj["id"]]
        if digest(obj) != entry["source_sha256"]:
            raise ValueError("source object changed: " + obj["id"])
        slots.append({"id": entry["logical_id"], "source_id": obj["id"],
                      "space": obj["space"], "floor": obj["floor"],
                      "home_space": obj.get("home_space", obj["space"]),
                      "position_q": [integer(v) * 48 for v in obj["pos"]],
                      "staff_only": bool(obj.get("staff", False))})
        for advert in obj["advertises"]:
            binding = entry["bindings"][advert["action"]]
            if binding in bindings:
                raise ValueError("duplicate logical affordance")
            bindings[binding] = copy.deepcopy(advert)
            affordances.append({"id": binding, "slot_id": entry["logical_id"],
                                "host_binding_sha256": digest(advert),
                                "seats": integer(advert.get("seats", 0))})
    planes = []
    for plane in inventory["navigation"]:
        planes.append({"space": plane["space"], "floor": plane["floor"],
                       "bounds_q": [integer(v) * 48 for v in plane["bounds_cells"]],
                       "blocked_cells_q": [[integer(v) * 48 for v in p]
                                           for p in plane["blocked_cells"]]})
    portals = []
    for source in inventory["portals"]:
        portal = {"id": ledger["portals"][source["id"]], "source_id": source["id"],
                  "kind": source["kind"],
                  "access": source["access"], "bidirectional": source["bidirectional"],
                  "owner_space": source.get("owner_space", ""),
                  "staff_titles": copy.deepcopy(source.get("staff_titles", [])),
                  "cost": integer(source["traversal_cost"])}
        for side in ("from", "to"):
            endpoint = source[side]
            portal[side] = {"space": endpoint["space"], "floor": endpoint["floor"],
                            "position_q": [integer(v) * 48 for v in endpoint["pos"]]}
        portals.append(portal)
    door, = [p for p in inventory["portals"] if p["id"] == "p_cafe_door"]
    town, = [p for p in inventory["navigation"] if p["space"] == "town" and p["floor"] == "outdoor"]
    topology = {"planes": planes, "portals": portals, "slots": slots,
                "affordances": affordances,
                "streets": [_frontage(coastal_plan, ledger, door, town["bounds_cells"])]}
    compatibility = {"topology_sha256": digest(topology),
                     "host_bindings_sha256": digest(bindings),
                     "identity_ledger_sha256": digest(ledger)}
    if compatibility["topology_sha256"] != FROZEN_TOPOLOGY_SHA256:
        raise ValueError("frozen topology changed; explicit profile and adapter revision required")
    presentation = {"profile": "reference", "pixels_per_cell": 48}
    presentation["digest_sha256"] = digest(presentation)
    package = {"schema_id": "WorldPackage", "schema_version": 1,
               "logical_scope": "living_town.cafe_street_reference",
               "coordinate_frame": copy.deepcopy(FRAME),
               "producer_ref": {"id": "living_town.boundary_snapshot", "version": 1},
               "input_refs": {"native_inventory_sha256": digest(inventory)},
               "payload": {"topology": topology, "compatibility": compatibility,
                           "presentation": presentation},
               "capabilities": {"profile": PROFILE, "read_only": True,
                                "live_topology_swap": False, "metric_height": False},
               "validation_ref": {"native_inventory_save_parity": bool(inventory["save_bytes_identical"]),
                                  "external_v5_conformance": False}}
    # Detached host data is not a package-supplied action authorization.
    return package, bindings


def check_compatible(package, reference, occupied_portals=(), occupied_affordances=()):
    """Validate a presentation replacement against a trusted frozen reference.

    reference must be receiver-owned, never supplied by the package sender.
    Structural changes are rejected even when no portal is occupied.
    """
    errors = []
    if not canonical_value(package):
        return {"ok": False, "errors": ["E_CANONICAL_VALUE"]}
    if not isinstance(package, dict) or set(package) != ROOT_KEYS:
        return {"ok": False, "errors": ["E_ENVELOPE"]}
    if package["schema_id"] != "WorldPackage" or type(package["schema_version"]) is not int or package["schema_version"] != 1:
        errors.append("E_VERSION")
    if digest(package["coordinate_frame"]) != digest(FRAME):
        errors.append("E_UNITS")
    if digest(package["capabilities"]) != digest(reference["capabilities"]):
        errors.append("E_CAPABILITIES")
    payload = package.get("payload")
    if not isinstance(payload, dict) or set(payload) != {"topology", "compatibility", "presentation"}:
        return {"ok": False, "errors": errors + ["E_PAYLOAD"]}
    topology = payload["topology"]
    if not isinstance(topology, dict) or set(topology) != {"planes", "portals", "slots", "affordances", "streets"}:
        return {"ok": False, "errors": errors + ["E_TOPOLOGY"]}
    if digest(topology) != digest(reference["payload"]["topology"]):
        errors.append("E_TOPOLOGY_CHANGED")
    if digest(payload["compatibility"]) != digest(reference["payload"]["compatibility"]):
        errors.append("E_STATE_COMPATIBILITY")
    if not isinstance(payload["compatibility"], dict) or payload["compatibility"].get("topology_sha256") != digest(topology):
        errors.append("E_TOPOLOGY_HASH")
    portal_ids = _logical_ids(topology.get("portals"), "PORTAL", errors)
    _check_occupied(occupied_portals, portal_ids, "PORTAL", errors)
    affordance_ids = _logical_ids(topology.get("affordances"), "AFFORDANCE", errors)
    _check_occupied(occupied_affordances, affordance_ids, "AFFORDANCE", errors)
    for key in ("logical_scope", "producer_ref", "input_refs", "validation_ref"):
        if digest(package[key]) != digest(reference[key]):
            errors.append("E_PROVENANCE_" + key.upper())
    presentation = payload["presentation"]
    if not isinstance(presentation, dict) or set(presentation) != {"profile", "pixels_per_cell", "digest_sha256"} or type(presentation.get("pixels_per_cell")) is not int or presentation.get("pixels_per_cell", 0) <= 0 or not isinstance(presentation.get("profile"), str) or not presentation.get("profile", "") or not presentation.get("profile", "").isascii() or presentation.get("digest_sha256") != digest({k: presentation[k] for k in ("profile", "pixels_per_cell")}):
        errors.append("E_PRESENTATION")
    return {"ok": not errors, "errors": errors,
            "topology_sha256": payload["compatibility"].get("topology_sha256") if isinstance(payload["compatibility"], dict) else "",
            "presentation_sha256": presentation.get("digest_sha256", "") if isinstance(presentation, dict) else ""}


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--coastal-plan", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    package, bindings = export_reference(load_json(args.inventory), load_json(args.ledger),
                                         load_json(args.coastal_plan))
    checked = check_compatible(package, package)
    if not checked["ok"]:
        raise ValueError(checked["errors"])
    args.out.mkdir(parents=True, exist_ok=True)
    for name, value in (("lt22_cafe_street.world.json", package),
                        ("host_action_bindings.json", bindings)):
        (args.out / name).write_text(json.dumps(value, sort_keys=True, ensure_ascii=True,
                                               indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"result": "mapped", "external_v5_qualified": False,
                      "topology_sha256": package["payload"]["compatibility"]["topology_sha256"]}))
