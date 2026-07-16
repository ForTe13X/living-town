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

persona_ids = set(personas.keys()) if isinstance(personas, dict) else set()
agent_defs = agents_d.get("agents", []) if isinstance(agents_d, dict) else []
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
    b = s.get("bounds", [])
    if len(b) != 4 or b[2] <= 0 or b[3] <= 0:
        errs.append(f"space '{sid}': bounds must be [x,y,w,h] with w/h>0")
    fl = s.get("floors", [])
    if not fl:
        errs.append(f"space '{sid}': floors must not be empty")
    if "default_floor" in s and s["default_floor"] not in fl:
        errs.append(f"space '{sid}': default_floor '{s['default_floor']}' not in floors {fl}")
seen_pid = set()
for p in (portals if isinstance(portals, list) else []):
    pid = p.get("id", "")
    if not pid:
        errs.append("portal missing id"); continue
    if pid in seen_pid:
        errs.append(f"duplicate portal id '{pid}'")
    seen_pid.add(pid)
    for side in ("from", "to"):
        e = p.get(side, {})
        sid, fid = e.get("space", ""), e.get("floor", "")
        if sid not in sp:
            errs.append(f"portal '{pid}'.{side}: unknown space '{sid}'")
        elif fid not in sp[sid].get("floors", []):
            errs.append(f"portal '{pid}'.{side}: space '{sid}' has no floor '{fid}'")
        if len(e.get("pos", [])) != 2:
            errs.append(f"portal '{pid}'.{side}: pos must be [x,y]")

n_json = len(glob.glob(os.path.join(ROOT, "*.json")))
if errs:
    print(f"lint_data: FAIL ({len(errs)} issue(s)):")
    for e in errs: print("  -", e)
    sys.exit(1)
print(f"lint_data: OK — {n_json} json parsed, FKs resolve "
      f"({len(agent_ids)} agents, {len(persona_ids)} personas, {len(object_ids)} objects)")
