#!/usr/bin/env python
# CI lint: every game/data/*.json must parse, and cross-file foreign keys must resolve.
# Catches the P1-5 class of bug (jobs referenced a map object id that didn't exist / was unreachable).
# Exit 1 on any parse error or dangling reference.
import json, glob, sys, os
ROOT = os.path.join(os.path.dirname(__file__), "..", "game", "data")
errs = []

def load(name):
    p = os.path.join(ROOT, name + ".json")
    try:
        return json.load(open(p, encoding="utf-8"))
    except Exception as e:
        errs.append(f"PARSE {name}.json: {e}")
        return None

# 0) REQUIRED data files must EXIST and parse.
# Why this is a separate check from (1): (1) only walks the files that are *there*, so deleting or
# renaming a data file makes the lint pass with one fewer file. Several subsystems are wired to
# switch themselves OFF when their data file is missing, and their invariants are written to be
# vacuously true in that state:
#   economy.json  -> Sim.economy empty -> invariants #34 (money conservation) and #35 (no negative
#                    balance) auto-pass (Invariants.gd:331,:334) and every `pay` event disappears
#   festivals.json-> no festivals -> #36 (festival object pairing) auto-passes (Invariants.gd:347)
#   elections.json-> election_log empty -> #37 (vote tally self-consistency) auto-passes (:353)
#   skills.json   -> skill/complement signal gone -> pact formation gate (#31) loses its input
#   production.json -> town stock never moves -> invariants #38 (stock ledger), #39 (output provenance)
#                    and #40 (closed-loop liveness) all auto-pass and every produce/consume/shortage
#                    event disappears; labour goes back to being decorative with CI 100% green.
# i.e. deleting one file silently switches off a whole subsystem with CI 100% green. Not any more.
# NOTE (Wave E1, declared out-of-scope edit): this file is not in E1's ownership list. The one-word
# addition of "production" is here because THIS file's own comment block is the rule it implements;
# leaving it out would ship exactly the hole documented above. Rollback = delete the word.
REQUIRED = ["personas", "agents", "jobs", "housing", "secrets", "map", "spaces", "interiors",
            "economy", "festivals", "elections", "skills", "needs", "rhythm", "utility", "production"]
for name in REQUIRED:
    p = os.path.join(ROOT, name + ".json")
    if not os.path.exists(p):
        errs.append(f"MISSING required data file: game/data/{name}.json "
                    f"(deleting it silently switches off a subsystem while its invariants auto-pass)")
        continue
    try:
        json.load(open(p, encoding="utf-8"))
    except Exception as e:
        errs.append(f"PARSE required {name}.json: {e}")

# 1) every data json parses
for p in sorted(glob.glob(os.path.join(ROOT, "*.json"))):
    try:
        json.load(open(p, encoding="utf-8"))
    except Exception as e:
        errs.append(f"PARSE {os.path.basename(p)}: {e}")

personas = load("personas") or {}
agents_d = load("agents") or {}
jobs = load("jobs") or {}
housing = load("housing") or {}
secrets = load("secrets") or {}
mapd = load("map") or {}
logistics = load("logistics") or {}

persona_ids = set(personas.keys()) if isinstance(personas, dict) else set()
agent_defs = []
if isinstance(agents_d, dict):
    agent_defs = list(agents_d.get("agents", [])) + list(agents_d.get("affiliates", []))
agent_ids = set(a.get("id") for a in agent_defs if isinstance(a, dict))
object_ids = set(o.get("id") for o in mapd.get("objects", []) if isinstance(o, dict))

def fk(label, ref, valid, kind):
    if ref is None or ref == "":
        return
    if ref not in valid:
        errs.append(f"FK {label}: '{ref}' not a known {kind}")

# 2) agents[].persona -> personas
for a in agent_defs:
    if isinstance(a, dict):
        fk(f"agents[{a.get('id')}].persona", a.get("persona"), persona_ids, "persona")
# 3) jobs.jobs keys -> agents
for aid in (jobs.get("jobs", {}) if isinstance(jobs.get("jobs"), dict) else {}):
    fk(f"jobs.jobs key", aid, agent_ids, "agent id")

# 3b) logistics functional nodes: ids unique; advertised job titles resolve.
node_ids = set()
job_titles = set(j.get("title") for j in jobs.get("jobs", {}).values() if isinstance(j, dict))
for node in logistics.get("nodes", []) if isinstance(logistics.get("nodes"), list) else []:
    if not isinstance(node, dict):
        continue
    nid = node.get("id")
    if not nid:
        errs.append("logistics.nodes: missing id")
    elif nid in node_ids:
        errs.append(f"logistics.nodes: duplicate id '{nid}'")
    node_ids.add(nid)
    for adv in node.get("advertises", []) if isinstance(node.get("advertises"), list) else []:
        if isinstance(adv, dict):
            fk(f"logistics.nodes[{nid}].advertises.job", adv.get("job"), job_titles, "job title")
# 4) jobs.extra_advertises[].object -> map objects  (the P1-5 dangling-ref guard)
for ea in jobs.get("extra_advertises", []) if isinstance(jobs.get("extra_advertises"), list) else []:
    if isinstance(ea, dict):
        fk("jobs.extra_advertises.object", ea.get("object"), object_ids, "map object id")
# 5) secrets.seeds[].owner -> agents
for s in secrets.get("seeds", []) if isinstance(secrets.get("seeds"), list) else []:
    if isinstance(s, dict):
        fk("secrets.seeds.owner", s.get("owner"), agent_ids, "agent id")
# 6) housing.tenancies[] landlord/tenant -> agents (best-effort field names)
for t in housing.get("tenancies", []) if isinstance(housing.get("tenancies"), list) else []:
    if isinstance(t, dict):
        for f in ("landlord", "owner", "host"):
            if f in t: fk(f"housing.tenancies.{f}", t[f], agent_ids, "agent id")
        for f in ("tenant", "renter", "guest"):
            if f in t: fk(f"housing.tenancies.{f}", t[f], agent_ids, "agent id")

# 7) P1 空间合同：Space/Floor/Portal 无悬挂引用（analysis §9 P1 Gate）。与 SpaceGraph.validate 同源。
spaces_d = load("spaces") or {}
sp = spaces_d.get("spaces", {}) if isinstance(spaces_d, dict) else {}
portals = spaces_d.get("portals", []) if isinstance(spaces_d, dict) else []
for sid, s in (sp.items() if isinstance(sp, dict) else []):
    if not isinstance(s, dict):
        errs.append(f"space '{sid}': definition must be an object")
        continue
    b = s.get("bounds", [])
    if len(b) != 4 or b[2] <= 0 or b[3] <= 0:
        errs.append(f"space '{sid}': bounds must be [x,y,w,h] with w/h>0")
    fl = s.get("floors", [])
    if not fl:
        errs.append(f"space '{sid}': floors must not be empty")
    if "default_floor" in s and s["default_floor"] not in fl:
        errs.append(f"space '{sid}': default_floor '{s['default_floor']}' not in floors {fl}")
seen_pid = set()
seen_portal_endpoints = {}
for p in (portals if isinstance(portals, list) else []):
    if not isinstance(p, dict):
        errs.append("portal entry must be an object")
        continue
    pid = p.get("id", "")
    if not pid:
        errs.append("portal missing id"); continue
    if pid in seen_pid:
        errs.append(f"duplicate portal id '{pid}'")
    seen_pid.add(pid)
    if p.get("access") not in ("public", "owner"):
        errs.append(f"portal '{pid}'.access must be public|owner")
    if p.get("access") == "owner" and not isinstance(p.get("owner_space"), str):
        errs.append(f"portal '{pid}'.owner_space must be a string")
    elif p.get("access") == "owner" and p.get("owner_space") not in sp:
        errs.append(f"portal '{pid}'.owner_space is not a known space")
    elif p.get("access") == "public" and "owner_space" in p:
        errs.append(f"portal '{pid}' public access must not declare owner_space")
    if type(p.get("bidirectional")) is not bool:
        errs.append(f"portal '{pid}'.bidirectional must be bool")
    if type(p.get("traversal_cost")) is not int or p.get("traversal_cost", 0) <= 0:
        errs.append(f"portal '{pid}'.traversal_cost must be a positive int")
    for side in ("from", "to"):
        e = p.get(side, {})
        if not isinstance(e, dict):
            errs.append(f"portal '{pid}'.{side}: endpoint must be an object")
            continue
        sid, fid = e.get("space", ""), e.get("floor", "")
        if sid not in sp:
            errs.append(f"portal '{pid}'.{side}: unknown space '{sid}'")
        elif fid not in sp[sid].get("floors", []):
            errs.append(f"portal '{pid}'.{side}: space '{sid}' has no floor '{fid}'")
        if len(e.get("pos", [])) != 2:
            errs.append(f"portal '{pid}'.{side}: pos must be [x,y]")
            continue
        pos = e["pos"]
        if any(type(v) not in (int, float) or int(v) != v for v in pos):
            errs.append(f"portal '{pid}'.{side}: pos must use integer cells")
            continue
        if sid in sp:
            bounds = sp[sid].get("bounds", [])
            if len(bounds) == 4 and not (0 <= pos[0] < bounds[2] and 0 <= pos[1] < bounds[3]):
                errs.append(f"portal '{pid}'.{side}: pos is outside space bounds")
        endpoint = (sid, fid, int(pos[0]), int(pos[1]))
        if endpoint in seen_portal_endpoints:
            errs.append(f"portal '{pid}'.{side}: endpoint duplicates {seen_portal_endpoints[endpoint]}")
        else:
            seen_portal_endpoints[endpoint] = f"{pid}.{side}"

# 7b) P3 室内内容 interiors.json：space/floor 键须指向真 Space/Floor；家具坐标须落在该 Space 的 bounds 内。
interiors_d = load("interiors") or {}
for isid, floors in (interiors_d.items() if isinstance(interiors_d, dict) else []):
    if isid.startswith("_"):
        continue
    if isid not in sp:
        errs.append(f"interiors: unknown space '{isid}'"); continue
    b = sp[isid].get("bounds", [0, 0, 0, 0])
    bw, bh = int(b[2]), int(b[3])
    for ifid, content in (floors.items() if isinstance(floors, dict) else []):
        if ifid not in sp[isid].get("floors", []):
            errs.append(f"interiors '{isid}': unknown floor '{ifid}'"); continue
        for fu in (content.get("furniture", []) if isinstance(content, dict) else []):
            pos = fu.get("pos", [])
            if len(pos) != 2 or not (0 <= pos[0] < bw and 0 <= pos[1] < bh):
                errs.append(f"interiors '{isid}/{ifid}': furniture '{fu.get('slot','?')}' pos {pos} 越界 {bw}x{bh}")

n_json = len(glob.glob(os.path.join(ROOT, "*.json")))
if errs:
    print(f"lint_data: FAIL ({len(errs)} issue(s)):")
    for e in errs: print("  -", e)
    sys.exit(1)
print(f"lint_data: OK — {n_json} json parsed, {len(REQUIRED)} required files present, FKs resolve "
      f"({len(agent_ids)} agents, {len(persona_ids)} personas, {len(object_ids)} objects)")
