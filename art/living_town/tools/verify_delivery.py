"""Read-only audit of saved Living Town delivery artifacts; never imports bpy.

Writes only evidence/delivery_verification.json. Requires Pillow for PNG pixels.
Missing final-render evidence is PENDING, never silently accepted as a preview.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import math
import re
import subprocess
import struct
import sys
from datetime import datetime, timezone
from fractions import Fraction
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1] if len(ROOT.parents)>1 else ROOT.parent
BASELINE = "f204276"
S = 1.8
EXPECTED_MATERIALS = {"slate", "lime_plaster", "granite", "cobbles", "oak", "sand", "grass", "ceramic_tile", "canvas"}
CHECKS = []
DETAILS = {}
SOURCE_MAP = REPO / "game/data/map.json"
if not SOURCE_MAP.is_file():
    SOURCE_MAP = ROOT / "source_snapshot/map.json"


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def check(ident, condition, detail=None, pending=False):
    CHECKS.append({"id": ident, "status": "PASS" if condition else ("PENDING" if pending else "FAIL"),
                   "detail": detail})


def read_json(path):
    if not path.is_file():
        check("required_file:" + str(path.relative_to(ROOT)), False, "File is not present yet.", pending=True)
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError) as exc:
        check("read_json:" + path.name, False, str(exc))
        return None


def inside(path):
    try:
        path.resolve().relative_to(ROOT.resolve())
        return True
    except ValueError:
        return False


def source_freeze_audit():
    freeze = read_json(ROOT / 'evidence/final_source_freeze.json')
    if not freeze:
        return
    expected = {'living_town_complete.blend', 'living_town_building_study.blend',
        'masterplan.json', 'terrain_plan.json', 'landscape_plan.json', 'interior_plan.json',
        'tools/build_living_town.py', 'tools/terrain_profile.py', 'tools/interior_design.py',
        'tools/refine_environment.py', 'tools/landscape_details.py'}
    if freeze.get('schema')=='living_town.source_freeze.v6':
        expected.update({'reserve_plan.json','tools/reserve_plan.py','tools/reserve_environment.py','tools/reserve_amenities.py',
                         'tools/generate_reserve_materials.py','textures/natural_rock_material.json',
                         'textures/natural_rock_basecolor.png','textures/natural_rock_roughness.png','textures/natural_rock_normal.png'})
    recorded = freeze.get('files', {})
    errors = []
    for relative, checksum in recorded.items():
        path = ROOT / relative
        if not inside(path) or not path.is_file():
            errors.append({'file': relative, 'reason': 'missing or outside delivery'})
        elif sha(path) != checksum:
            errors.append({'file': relative, 'reason': 'current bytes differ from source freeze'})
    check('frozen_native_and_source_files_match_current_bytes',
        set(recorded) == expected and not errors,
        {'expected_files': len(expected), 'recorded_files': len(recorded),
         'missing_records': sorted(expected - set(recorded)), 'errors': errors})
    DETAILS['final_source_freeze'] = freeze


def xy(x, y):
    return ((x - 32) * S, (24 - y) * S)


def close(a, b):
    return len(a) == len(b) and all(math.isclose(float(x), float(y), abs_tol=1e-6) for x, y in zip(a, b))


def source_audit(data, town, study):
    raw_hash = sha(SOURCE_MAP)
    check("source_map_hash_vs_manifests", all(m and m.get("source_map_sha256") == raw_hash for m in (town, study)), raw_hash)
    if SOURCE_MAP == ROOT / "source_snapshot/map.json":
        DETAILS["source_baseline"]={"mode":"portable_source_snapshot","snapshot_sha256":raw_hash,
            "git_HEAD_comparison":"Unavailable in this standalone artifact; snapshot integrity is checked against the delivered town and study records.",
            "declared_source_head":BASELINE}
    else:
        try:
            proc = subprocess.run(["git", "show", BASELINE + ":game/data/map.json"], cwd=REPO,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
            git_hash = hashlib.sha256(proc.stdout).hexdigest()
            check("source_map_unchanged_from_HEAD", git_hash == raw_hash,
                  {"baseline": BASELINE, "baseline_sha256": git_hash, "current_sha256": raw_hash})
        except (OSError, subprocess.CalledProcessError) as exc:
            check("source_map_unchanged_from_HEAD", False, str(exc), pending=True)
    masterplan_audit(data, town)


def masterplan_audit(data, town):
    plan = read_json(ROOT / "masterplan.json")
    if not plan:
        return
    expected_ids = {"Main_" + n for n, a in data["areas"].items() if a["type"] != "plaza"}
    expected_ids.update(a["id"] for a in data["solid_lots"])
    expected_ids.add("Port_Warehouse_Exterior")
    planned = {b["id"]: b for b in plan["buildings"]}
    check("revised_program_inventory_7_plus_41_plus_warehouse", set(planned) == expected_ids and len(plan["buildings"]) == 49,
          {"expected": len(expected_ids), "actual": len(plan["buildings"]), "missing": sorted(expected_ids-set(planned)), "unexpected": sorted(set(planned)-expected_ids)})
    if town:
        check("native_model_matches_masterplan_SHA", town.get("masterplan_sha256") == sha(ROOT / "masterplan.json"),
              {"masterplan_sha256": sha(ROOT / "masterplan.json"), "native_recorded_sha256": town.get("masterplan_sha256")})
        actual = {b["id"]: b for b in town.get("buildings", [])}
        errors = []
        for ident, b in planned.items():
            a = actual.get(ident)
            if not a:
                errors.append({"id":ident,"error":"Missing native building"});continue
            if (not close(a.get("center_m",[])[:2],b["center"]) or not close(a.get("footprint_m",[]),[b["width"],b["depth"]])
                    or not math.isclose(a.get("yaw_degrees",math.inf),b["yaw_degrees"],abs_tol=1e-6)
                    or a.get("floors")!=b["floors"] or a.get("source_ref")!=b["source_ref"] or a.get("district")!=b["district"]):
                errors.append({"id":ident,"error":"Native geometry/program metadata differs from masterplan"})
        check("native_parcels_match_revised_plans", not errors and set(actual)==set(planned), errors)
    spec=importlib.util.spec_from_file_location("lt_masterplan_audit",ROOT/"tools/generate_masterplan.py")
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    buildings=plan["buildings"]
    overlaps=[(a["id"],b["id"]) for i,a in enumerate(buildings) for b in buildings[i+1:] if module.overlaps(a,b)]
    check("revised_parcels_no_positive_area_overlap",not overlaps,overlaps)
    room_errors=[];threshold_errors=[]
    for b in buildings:
        if not close(b["interior_clear_span"],[b["width"]-.6,b["depth"]-.6]) or min(b["interior_clear_span"])<2:
            room_errors.append(b["id"])
        angle=math.radians(b["yaw_degrees"]);expected=[b["center"][0]+math.sin(angle)*b["depth"]/2,b["center"][1]-math.cos(angle)*b["depth"]/2]
        if not close(b["front_threshold"],expected):threshold_errors.append(b["id"])
    check("new_room_envelopes_fit_parcels",not room_errors,{"errors":room_errors,"scope":"Clear envelope spans only; actual furniture/partition meshes require native inspection."})
    check("49_yaw_aware_front_thresholds",not threshold_errors and len(buildings)==49,threshold_errors)
    roads=plan["streets"];collisions=[]
    for r in roads:
        for a,z in zip(r["points"],r["points"][1:]):
            for b in buildings:
                if r.get("threshold_owner")!=b["id"] and module.crosses(a,z,b,r["width"]/2+.2):
                    collisions.append({"road":r["id"],"building":b["id"]})
    check("revised_streets_clear_rotated_parcels",not collisions,{"collisions":collisions,"clearance_m":.2,"road_count":len(roads)})
    def point_distance(p,a,z):
        vx,vy=z[0]-a[0],z[1]-a[1];den=vx*vx+vy*vy
        t=max(0,min(1,((p[0]-a[0])*vx+(p[1]-a[1])*vy)/den)) if den else 0
        return math.hypot(p[0]-a[0]-t*vx,p[1]-a[1]-t*vy)
    def distance(a,b,c,d):
        def cross(p,q,r):return(q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0])
        if max(min(a[0],b[0]),min(c[0],d[0]))<=min(max(a[0],b[0]),max(c[0],d[0]))+1e-9 and max(min(a[1],b[1]),min(c[1],d[1]))<=min(max(a[1],b[1]),max(c[1],d[1]))+1e-9:
            if cross(a,b,c)*cross(a,b,d)<=0 and cross(c,d,a)*cross(c,d,b)<=0:return 0.
        return min(point_distance(a,c,d),point_distance(b,c,d),point_distance(c,a,b),point_distance(d,a,b))
    parents=list(range(len(roads)))
    def find(i):
        while parents[i]!=i:parents[i]=parents[parents[i]];i=parents[i]
        return i
    for i,r in enumerate(roads):
        for j,q in enumerate(roads[:i]):
            if find(i)==find(j):continue
            if any(distance(a,b,c,d)<=(r["width"]+q["width"])/2-.02 for a,b in zip(r["points"],r["points"][1:]) for c,d in zip(q["points"],q["points"][1:])):parents[find(i)]=find(j)
    components=len({find(i) for i in range(len(roads))})
    owners={r.get("threshold_owner") for r in roads if r.get("kind")=="threshold"}
    check("rendered_street_ribbons_connect_all49_entrances",components==1 and owners==set(planned),
          {"connected_components":components,"threshold_owners":len(owners),"method":"Geometric segment/ribbon intersection after final line simplification."})
    DETAILS["current_layout_authority"]={"masterplan":"masterplan.json","building_count":len(buildings),"street_count":len(roads),"old_source_anchors":"Legacy reference only; not an acceptance constraint for the redesigned town."}


def ownership_audit(manifest, stage):
    if not manifest:
        return
    names, bad = [], []
    for b in manifest.get("buildings", []):
        for key in ("collection", "roof_collection", "front_collection", "upper_cover_collection"):
            value = b.get(key)
            if not isinstance(value, str) or not value:
                bad.append({"id": b.get("id"), "missing": key})
            else:
                names.append(value)
    check(stage + "_unique_building_reveal_ownership", not bad and len(names) == len(set(names)),
          {"named_groups": len(names), "unique_groups": len(set(names)), "missing": bad})
    check(stage + "_camera_inventory", len(manifest.get("cameras", [])) == (14 if stage == "town" else 3)
          and (stage != "town" or "14_Pond_Park" in manifest.get("cameras", [])),
          manifest.get("cameras"))


def blend_audit(stage, filename):
    path = ROOT / filename
    if not path.exists():
        check(stage + "_blend_exists", False, filename, pending=True)
        return
    with path.open("rb") as stream:
        magic = stream.read(12)
    compression = "none" if magic.startswith(b"BLENDER") else ("zstd" if magic.startswith(b"\x28\xb5\x2f\xfd") else ("gzip" if magic.startswith(b"\x1f\x8b") else "unknown"))
    check(stage + "_blend_exists", path.stat().st_size > 1_000_000 and compression != "unknown",
          {"file": filename, "bytes": path.stat().st_size, "sha256": sha(path), "header_hex": magic.hex(),
           "compression": compression, "note": "File existence/signature check; separate native reopen verifies Blender contents."})


def terrain_audit(town):
    plan=read_json(ROOT/'terrain_plan.json')
    if not plan:return
    check('terrain_bound_to_frozen_masterplan',plan.get('masterplan_sha256')==sha(ROOT/'masterplan.json'),plan.get('masterplan_sha256'))
    spec=importlib.util.spec_from_file_location('lt_terrain_audit',ROOT/'tools/terrain_profile.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    current=module.make_plan()
    def equal(a,b):
        if isinstance(a,(int,float)) and isinstance(b,(int,float)):return math.isclose(a,b,abs_tol=1e-6)
        if isinstance(a,dict) and isinstance(b,dict):return set(a)==set(b) and all(equal(a[k],b[k]) for k in a)
        if isinstance(a,list) and isinstance(b,list):return len(a)==len(b) and all(equal(x,y) for x,y in zip(a,b))
        if isinstance(a,(list,tuple)) and isinstance(b,(list,tuple)):return len(a)==len(b) and all(equal(x,y) for x,y in zip(a,b))
        return a==b
    sections=('levels','roads','building_pads','beach_cross_sections','park_pond','drainage','contour_segments','validation')
    different=[key for key in sections if not equal(plan.get(key),current.get(key))]
    check('terrain_plan_reproduces_from_profile',not different,{'different_sections':different,'profile_sha256':sha(ROOT/'tools/terrain_profile.py')})
    v=plan['validation']
    check('continuous_streets_within8percent_grade',v['public_street_max_grade_percent']<=8 and v['public_ribbon_edge_max_grade_percent']<=8
          and v['public_paving_apron_edge_max_grade_percent']<=8 and not v['other_grade_reviews'],
          {'public_max_grade_percent':v['public_street_max_grade_percent'],'grade_reviews':v['other_grade_reviews'],
           'ribbon_edge_max_grade_percent':v['public_ribbon_edge_max_grade_percent'],'paving_apron_edge_max_grade_percent':v['public_paving_apron_edge_max_grade_percent'],
           'stepped_threshold_routes':len(v['entry_step_routes']),'sample_spacing_m':v['sample_spacing_m']})
    check('coherent_water_quay_and_level_pads',len(plan['building_pads'])==49 and module.WATER_Z==-.88 and module.QUAY_Z==1.615
          and v['maximum_parcel_cut_m']<1 and v['maximum_parcel_fill_m']<1,
          {'water_z_m':module.WATER_Z,'quay_z_m':module.QUAY_Z,'cut_m':v['maximum_parcel_cut_m'],'fill_m':v['maximum_parcel_fill_m']})
    if town:
        bindings={'terrain_plan_sha256':sha(ROOT/'terrain_plan.json'),'terrain_profile_sha256':sha(ROOT/'tools/terrain_profile.py'),
                  'landscape_plan_sha256':sha(ROOT/'landscape_plan.json')}
        missing=[key for key in bindings if not town.get(key)]
        wrong=[key for key in bindings if town.get(key) and town[key]!=bindings[key]]
        check('native_model_matches_terrain_sources',not missing and not wrong,{'missing':missing,'different':wrong,'expected':bindings},pending=bool(missing) and not wrong)
        pads={p['id']:p for p in plan['building_pads']};errors=[]
        for b in town.get('buildings',[]):
            if b['id'] not in pads or not math.isclose(b['center_m'][2],pads[b['id']]['pad_base_z_m'],abs_tol=1e-6):errors.append(b['id'])
        # Older models are pending until rebound to the new terrain sources.
        check('native_building_baselevels_match_pads',not errors and town.get('stepped_approaches')==len(v['entry_step_routes']),
              {'different_baselevels':errors,'native_stepped_routes':town.get('stepped_approaches'),'expected_stepped_routes':len(v['entry_step_routes'])},pending=bool(missing))
    DETAILS['topography']={'plan':'terrain_plan.json','profile':'tools/terrain_profile.py','validation':v,
        'scope':'Fictional authored elevations; native mesh/step geometry is covered only by the separate Blender audit.'}
    landscape_audit(plan, module, town)


def landscape_audit(terrain, module, town=None):
    """Independent metric siting checks; Blender audits the actual meshes."""
    plan=read_json(ROOT/'landscape_plan.json')
    if not plan:return
    expected={'masterplan_sha256':sha(ROOT/'masterplan.json'),
        'interior_plan_sha256':sha(ROOT/'interior_plan.json'),'interior_module_sha256':sha(ROOT/'tools/interior_design.py'),
        'baseline_terrain_profile_sha256':'4589711f3812b617ae11e15f1ec5cd28f0e396acc17627b339dac759adb147c7'}
    bindings=plan.get('source_bindings',{})
    check('landscape_siting_preserves_frozen_architecture_and_interiors',all(bindings.get(k)==v for k,v in expected.items()),expected)
    check('terrain_matches_current_landscape_siting',terrain.get('landscape_plan_sha256')==sha(ROOT/'landscape_plan.json'),
        {'recorded':terrain.get('landscape_plan_sha256'),'current':sha(ROOT/'landscape_plan.json')},
        pending=terrain.get('landscape_plan_sha256')!=sha(ROOT/'landscape_plan.json'))
    master=json.loads((ROOT/'masterplan.json').read_text(encoding='utf-8'))
    buildings=master['buildings'];roads=master['streets'];paths=plan.get('paths',[])
    def pd(p,a,b):
        dx,dy=b[0]-a[0],b[1]-a[1];den=dx*dx+dy*dy
        t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/den)) if den else 0
        return math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy)
    def bd(p,b):
        angle=math.radians(b['yaw_degrees']);dx,dy=p[0]-b['center'][0],p[1]-b['center'][1]
        x=dx*math.cos(angle)+dy*math.sin(angle);y=-dx*math.sin(angle)+dy*math.cos(angle)
        return math.hypot(max(0,abs(x)-b['width']/2),max(0,abs(y)-b['depth']/2))
    def route_distance(p,routes,width):
        return min(pd(p,a,b)-r[width]/2 for r in routes for a,b in zip(r['points'],r['points'][1:]))
    pond=plan.get('pond',{});p=terrain.get('park_pond') or {};errors=[]
    if pond!=plan.get('park',{}).get('pond'):errors.append('Top-level and park pond definitions differ.')
    for key in ('center','water_radii_m','outer_bank_radii_m'):
        if not close(pond.get(key,[]),p.get(key,[])):errors.append(key+' differs from terrain authority')
    for key in ('water_z_m','bed_z_m'):
        if not math.isclose(pond.get(key,math.inf),p.get(key,-math.inf),abs_tol=1e-6):errors.append(key+' differs from terrain authority')
    dimensions=(pond.get('center')==[26,-42] and pond.get('water_radii_m')==[5,3]
        and pond.get('outer_bank_radii_m')==[7,5] and pond.get('water_z_m')==-.12 and pond.get('bed_z_m')==-.92)
    metrics=(p.get('water_is_level') is True and p.get('bank_grade_pass') is True
        and 0<p.get('maximum_sampled_bank_grade_percent',math.inf)<=100/3+1e-4
        and math.isclose(p.get('maximum_water_depth_m',math.inf),.8,abs_tol=1e-6)
        and math.isclose(p.get('wet_surface_area_m2',math.inf),math.pi*15,abs_tol=1e-6)
        and math.isclose(p.get('bed_height_at_center_m',math.inf),-.92,abs_tol=1e-6)
        and p.get('grade_sample_spacing_m',math.inf)<=.1 and p.get('gradient_central_difference_m',math.inf)<=.025)
    cx,cy=pond.get('center',[0,0]);rx,ry=pond.get('outer_bank_radii_m',[0,0])
    perimeter=[[cx+rx*math.cos(i*math.tau/128),cy+ry*math.sin(i*math.tau/128)] for i in range(128)]
    parcel_clear=min(bd(q,b) for q in perimeter for b in buildings)
    route_clear=min(route_distance(q,roads,'width') for q in perimeter)
    check('required_pond_is_level_recessed_and_banks_at_most_one_in_three',dimensions and metrics and not errors,
        {'errors':errors,'terrain_pond':p,'scope':'Deterministic profile and independently reproduced terrain-plan metrics; actual water/bank meshes require native checks.'})
    check('pond_grading_ends_clear_of_frozen_parcels_and_routes',parcel_clear>=6.5 and route_clear>=1.99,
        {'outer_bank_to_parcel_m':parcel_clear,'outer_bank_to_existing_route_edge_m':route_clear})
    trees=plan.get('street_trees',[]);tree_errors=[];minima=[math.inf]*4
    for t in trees:
        q=t['xy'];radius=t['crown_radius_m']
        values=[min(bd(q,b) for b in buildings)-radius,route_distance(q,roads,'width'),
            route_distance(q,paths,'width_m'),module.coast_x(q[1])-module.beach_width(q[1])-q[0]]
        minima=[min(a,b) for a,b in zip(minima,values)]
        if (values[0]<.35-1e-6 or values[1]<.65-1e-6 or values[2]<.65-1e-6 or values[3]<.2
                or module.pond_radius(*q,outer=True)<1.02 or t.get('clear_stem_height_m',0)<2.5):tree_errors.append(t['id'])
    check('landscape_tree_crowns_trunks_and_surface_contacts_clear',len(trees)==plan.get('validation',{}).get('tree_count')
        and len(trees)>0 and len({t['id'] for t in trees})==len(trees) and not tree_errors,
        {'tree_count':len(trees),'failed_tree_ids':tree_errors,'minimum_crown_to_parcel_m':minima[0],
         'minimum_trunk_to_existing_route_edge_m':minima[1],'minimum_trunk_to_new_path_edge_m':minima[2],
         'minimum_root_inland_of_beach_edge_m':minima[3]})
    path_reports=[]
    for path in paths:
        clearance=math.inf;grade=0.
        for a,b in zip(path['points'],path['points'][1:]):
            n=max(1,math.ceil(math.dist(a,b)/.25));previous=None
            for i in range(n+1):
                q=[a[k]+(b[k]-a[k])*i/n for k in (0,1)];z=module.design_height(*q)
                clearance=min(clearance,min(bd(q,bld) for bld in buildings)-path['width_m']/2)
                if previous:
                    grade=max(grade,100*abs(z-previous[1])/math.dist(q,previous[0]))
                previous=(q,z)
        path_reports.append({'id':path['id'],'minimum_parcel_clearance_m':clearance,'maximum_grade_percent':grade,
            'pass':clearance>=.3-1e-6 and grade<=8+1e-6})
    park_paths=[r for r in paths if r['id'] in {'park_loop','park_west_gate','park_east_gate'}]
    check('new_landscape_walks_fit_parcels_and_grades',len(paths)==5 and all(r['pass'] for r in path_reports)
        and len(park_paths)==3 and all(r['width_m']>=1.5 and r.get('material')=='Sand' for r in park_paths),path_reports)
    coverage=plan.get('coverage_assessment',{});areas=coverage.get('areas',{})
    check('landscape_coverage_is_spatial_and_distinguishes_woodland',set(areas)=={'southeast_park','civic_plaza','cafe_court'}
        and all(0<a.get('canopy_projection_percent',0)<100 and a.get('sample_spacing_m',math.inf)<=.25 for a in areas.values())
        and len(coverage.get('routes',[]))==10 and bool(coverage.get('distant_woodland')) and len(coverage.get('horticulture_layers',[]))>=4,
        {'areas':areas,'routes':coverage.get('routes'),'limit':'Canopy envelopes are plan projections, not formal solar shading or dense-leaf coverage.'})
    if town:
        evidence=town.get('environment_refinement',{}).get('reference_landscape',{})
        accepted=evidence.get('accepted',[]);counts=evidence.get('counts',{})
        native_trees={a['id']:a for a in accepted if a.get('role') in ('street_tree','willow')}
        expected_trees={t['id']:t for t in trees};tree_differences=[]
        for ident,t in expected_trees.items():
            actual=native_trees.get(ident,{})
            if not close(actual.get('xy',[]),t['xy']) or not math.isclose(actual.get('crown_radius_m',math.inf),t['crown_radius_m'],abs_tol=1e-6):
                tree_differences.append(ident)
        actual_paths={a['id'] for a in accepted if a.get('role')=='path'}
        actual_meadows={a['id'] for a in accepted if a.get('role')=='meadow'}
        expected_meadows={a['id'] for a in plan.get('meadow_polygons',[])}
        canonical=hashlib.sha256(json.dumps(plan,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        stale=(town.get('landscape_plan_sha256')!=sha(ROOT/'landscape_plan.json')
            or town.get('landscape_details_sha256')!=sha(ROOT/'tools/landscape_details.py')
            or evidence.get('plan_content_sha256')!=canonical)
        complete=(set(native_trees)==set(expected_trees) and not tree_differences
            and counts.get('street_trees',0)+counts.get('willows',0)==len(trees)
            and actual_paths=={a['id'] for a in paths} and counts.get('paths')==len(paths)
            and actual_meadows==expected_meadows and counts.get('meadow_clumps',0)>0
            and counts.get('garden_beds',0)>=len(plan.get('gardens',[]))+len(plan.get('park',{}).get('flowerbeds',[]))
            and counts.get('flower_clusters',0)>0 and counts.get('beach_grass_clumps',0)>0
            and counts.get('beach_grass_patches')==len(plan.get('coastal_grass',{}).get('patches',[]))
            and counts.get('benches')==len(plan.get('park',{}).get('benches',[])) and counts.get('reed_clumps',0)>0)
        check('native_landscape_accepts_all_planned_trees_paths_and_horticulture',not stale and complete,
            {'source_bindings_stale':stale,'counts':counts,'missing_trees':sorted(set(expected_trees)-set(native_trees)),
             'different_tree_envelopes':tree_differences,'accepted_paths':sorted(actual_paths),'accepted_meadows':sorted(actual_meadows),
             'rejections':evidence.get('rejected',[]),'scope':'Source-bound placement records with native geometry coverage supplied by the separate planting audit.'},pending=stale)
    DETAILS['landscape']={'plan_sha256':sha(ROOT/'landscape_plan.json'),'source_bindings':bindings,'coverage':coverage,'pond':p}


def native_evidence_audit():
    record=read_json(ROOT/'evidence/native_scene_audit.json')
    if not record:return
    required={'packed_image_dependencies','packed_external_fonts','no_linked_libraries','metric_scene',
        'all57_chimney_bases_intersect_actual_roof_surfaces',
        'true_xy_orthographic_camera','native_building_ownership','interior_collections','local_cutaway_only',
        'cutaway_restored','real_stair_floor_opening','cafe_has_no_party_wall_windows',
        'native_foundations_reach_design_toes','stepped_thresholds_modelled','gable_roof_rise_preserved',
        'native_water_datum','quay_has_one_ground_surface','optional_native_contour_layer',
        'native_interiors_bound_to_current_sources','all89_native_floor_levels_and_cover_ownership',
        'all40_upper_slabs_have_real_shaft_voids','all40_stair_flights_have14_equal_rises_and_bridge',
        'native_partition_apertures_are_geometric','native104_private_room_internal_boundaries_are_solid','native_room_and_reusable_furniture_ownership',
        'native_essential_program_fixtures_and_integrated_kitchens',
        'reference_landscape_bound_to_saved_source','native_pond_has_level_water_and_recessed_basin',
        'native_pond_banks_meet_water_and_are_graded','native_reference_landscape_paths_and_planting'}
    checks=record.get('checks',[]);names={c.get('id') for c in checks}
    check('native_Blender_audit_passes',record.get('status')=='PASS' and required.issubset(names) and all(c.get('status')=='PASS' for c in checks),
          {'missing_checks':sorted(required-names),'failed':[c for c in checks if c.get('status')!='PASS']})
    landscape=json.loads((ROOT/'landscape_plan.json').read_text(encoding='utf-8'))
    planted=next((c.get('detail',{}) for c in checks if c.get('id')=='native_reference_landscape_paths_and_planting'),{})
    layers=planted.get('native_layer_mesh_vertices',{})
    planned_trees=len(landscape.get('street_trees',[]))+sum(isinstance(a,dict) for a in landscape.get('park',{}).get('willows',[]))
    planting_counts=planted.get('counts',{})
    planting_current=record.get('landscape_plan_sha256')==sha(ROOT/'landscape_plan.json')
    check('native_landscape_has_all_trees_and_nonempty_vegetation_mesh_layers',planting_current
        and planted.get('planned_trees')==planned_trees
        and planting_counts.get('street_trees',0)+planting_counts.get('willows',0)==planned_trees
        and all(layers.get(role,0)>100 for role in ('Street_Trees','Pond_Planting','Pocket_Gardens','Coastal_Dune_Grass')),
        {'planned_tree_count':planned_trees,'native_counts':planting_counts,'native_layer_mesh_vertices':layers},pending=not planting_current)
    current={'source_blend_sha256':sha(ROOT/'living_town_complete.blend'),'masterplan_sha256':sha(ROOT/'masterplan.json'),
        'terrain_plan_sha256':sha(ROOT/'terrain_plan.json'),'terrain_profile_sha256':sha(ROOT/'tools/terrain_profile.py'),
        'landscape_plan_sha256':sha(ROOT/'landscape_plan.json'),'landscape_details_sha256':sha(ROOT/'tools/landscape_details.py'),
        'interior_plan_sha256':sha(ROOT/'interior_plan.json'),
        'interior_module_sha256':sha(ROOT/'tools/interior_design.py')}
    mismatched=[key for key in current if record.get(key)!=current[key]]
    check('native_audit_matches_delivered_model',not mismatched,{'different_bindings':mismatched},pending=bool(mismatched))
    DETAILS['native_audit']=record


def interior_audit(town,study):
    plan=read_json(ROOT/'interior_plan.json')
    if not plan:return
    spec=importlib.util.spec_from_file_location('lt_interior_audit',ROOT/'tools/interior_design.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    master=json.loads((ROOT/'masterplan.json').read_text(encoding='utf-8'))
    reproduced=[module.plan_for_building(b['id'],b['width'],b['depth'],b['floors'],b['kind']) for b in master['buildings']]
    check('interior_plan_reproduces_from_frozen_programs',reproduced==plan['buildings'] and plan['masterplan_sha256']==sha(ROOT/'masterplan.json'),
        {'building_count':len(reproduced),'masterplan_sha256':plan.get('masterplan_sha256')})
    # Compare serialized evidence structurally: JSON encodes analytic span
    # tuples as arrays, preserving their values and order.
    audit=json.loads(json.dumps(module.audit_plan(plan)))
    check('all_interior_rooms_pass_pedestrian_and_fixture_plan_audit',audit['status']=='PASS' and audit['floor_count']==89 and audit['stair_flights']==40,audit)
    entrances=audit.get('entrance_threshold_checks',[])
    sleeping=audit.get('sleeping_room_exterior_boundary_checks',[])
    check('all49_actual_entrance_axes_are_clear_before_route_traversal',len(entrances)==49 and all(r['pass'] and r['exact_raster_seed_free'] for r in entrances),entrances)
    check('all47_sleeping_rooms_have_usable_exterior_boundary',len(sleeping)==47 and all(r['pass'] for r in sleeping),
        {'rooms':sleeping,'limit':'Exterior wall contact, not a window-area or daylight calculation.'})
    privacy_boundaries=audit.get('privacy_enclosure_checks',[])
    check('all_sleeping_and_sanitary_rooms_have_closed_internal_boundaries',len(privacy_boundaries)==104 and all(r['pass'] for r in privacy_boundaries),privacy_boundaries)
    saved_audit=read_json(ROOT/'evidence/interior_planning_audit.json')
    coverage=audit.get('essential_fixture_coverage',[])
    expected_bindings={'interior_plan_sha256':sha(ROOT/'interior_plan.json'),'interior_module_sha256':sha(ROOT/'tools/interior_design.py')}
    check('all223_activity_programs_have_current_essential_fixture_evidence',len(coverage)==223 and all(r['pass'] for r in coverage)
        and saved_audit==audit and all(audit.get(k)==v for k,v in expected_bindings.items()),
        {'activity_rooms':len(coverage),'purpose_requirements':audit.get('essential_fixture_requirements_tested'),
        'current_source_bindings':expected_bindings,'failed_rooms':[r['room'] for r in coverage if not r['pass']]})
    privacy=[];ensuites=owners=0
    for b in plan['buildings']:
        for f in b['levels']:
            for room in f['rooms']:
                if 'ensuite' in room['purpose']:
                    ensuites+=1;kinds={a['kind'] for a in room['assets']}
                    if not {'shower_screen','toilet','basin'}<=kinds or not room['door_gaps']:privacy.append(room['id'])
            if b['kind'] in ('cafe','shop','bakery','creperie') and f['level']:
                owners+=1;purposes={r['purpose'] for r in f['rooms']}
                if not {'private owner kitchenette','private owner bathroom'}<=purposes:privacy.append(b['id'])
    cafe=next(b for b in plan['buildings'] if b['kind']=='cafe')
    dining=next(r for r in cafe['levels'][0]['rooms'] if r['purpose']=='cafe dining')
    check('private_bathrooms_and_purposeful_cafe_program',not privacy and ensuites==8 and owners==4
        and sum(a['kind']=='cafe_table_set' for a in dining['assets'])==4 and any(a['kind']=='cafe_counter' for a in dining['assets']),
        {'private_hotel_ensuites':ensuites,'separate_owner_kitchens_and_baths':owners,'privacy_errors':privacy})
    bindings={'interior_plan_sha256':sha(ROOT/'interior_plan.json'),'interior_module_sha256':sha(ROOT/'tools/interior_design.py')}
    for stage,m in (('town',town),('study',study)):
        if not m:continue
        missing=[k for k in bindings if not m.get(k)];different=[k for k,v in bindings.items() if m.get(k) and m[k]!=v]
        check(stage+'_interiors_match_current_sources',not missing and not different,{'missing':missing,'different':different,'expected':bindings},pending=bool(missing or different))
    if town:
        records=town.get('interiors',[]);actual={b['id']:b for b in records};expected={b['id']:b for b in plan['buildings']};errors=[]
        for ident,b in expected.items():
            native=actual.get(ident)
            if not native:errors.append({'id':ident,'reason':'missing native interior record'});continue
            native_floors=native.get('levels',native.get('floors',[]))
            if len(native_floors)!=b['floors'] or native.get('floor_count')!=b['floors']:errors.append({'id':ident,'reason':'native floor inventory differs'})
            expected_rooms={r['id'] for f in b['levels'] for r in f['rooms']}
            native_rooms={r['id'] for f in native_floors for r in f['rooms']}
            if native_rooms!=expected_rooms:errors.append({'id':ident,'reason':'native room inventory differs'})
        check('native_manifests_cover49_buildings89_floors_and_detailed_rooms',not errors and set(actual)==set(expected)
            and town.get('interior_floor_count')==89 and town.get('interior_room_count')==plan['room_count']
            and town.get('interior_furnishing_count')==plan['furnishing_count'],
            {'buildings':len(records),'floors':town.get('interior_floor_count'),'room_zones':town.get('interior_room_count'),
                'furniture_assemblies':town.get('interior_furnishing_count'),'errors':errors},pending=bool(errors))
    DETAILS['interiors']={'plan':'interior_plan.json','module':'tools/interior_design.py','audit':audit,
        'room_count_definition':'Logical activity rooms, halls, stairs and landings; not all enclosed habitable rooms.',
        'scope':'Plan clearance and native-manifest coverage; actual shaft/tread/aperture meshes covered by native audit.'}


def texture_audit():
    manifest = read_json(ROOT / "textures/material_manifest.json")
    if not manifest:
        return
    materials = manifest.get("materials", {})
    check("nine_original_material_families", set(materials) == EXPECTED_MATERIALS and "Original" in manifest.get("license", ""),
          {"materials": sorted(materials), "declared_license": manifest.get("license"), "generator": manifest.get("generator")})
    maps, errors = [], []
    for name, material in materials.items():
        for kind in ("basecolor", "roughness", "normal"):
            path = ROOT / "textures" / material.get(kind, "__missing__")
            if not inside(path):
                errors.append({"file": str(path), "error": "asset reference escapes delivery"})
                continue
            if not path.is_file():
                errors.append({"file": str(path.relative_to(ROOT)), "error": "missing texture"})
                continue
            expected = (1024, 1024) if kind == "basecolor" else (512, 512)
            try:
                with Image.open(path) as im:
                    im.load()
                    w, h = im.size
                    periodic = (im.crop((0, 0, w, 1)).tobytes() == im.crop((0, h - 1, w, h)).tobytes()
                                and im.crop((0, 0, 1, h)).tobytes() == im.crop((w - 1, 0, w, h)).tobytes())
                    if im.size != expected or not periodic:
                        errors.append({"file": path.name, "size": list(im.size), "expected": list(expected), "periodic": periodic})
                    maps.append({"file": str(path.relative_to(ROOT)), "size": [w, h], "periodic_uv": periodic, "sha256": sha(path)})
            except OSError as exc:
                errors.append({"file": path.name, "error": str(exc)})
    check("27_texture_maps_dimensions_and_periodicity", len(maps) == 27 and not errors, {"map_count": len(maps), "errors": errors})
    DETAILS["texture_maps"] = maps


def render_audit(stage, manifest):
    record_path = ROOT / "evidence" / ("renders_" + stage + ".json")
    records = read_json(record_path)
    if records is None:
        return
    blend_path = ROOT / ("living_town_complete.blend" if stage == "town" else "living_town_building_study.blend")
    stale = []
    if blend_path.exists():
        for r in records:
            image_path = ROOT / "renders" / r.get("image", "__missing__")
            if r.get("source_blend_sha256"):
                if r["source_blend_sha256"] != sha(blend_path):
                    stale.append({"image": r.get("image"), "reason": "source Blender hash differs"})
            elif (record_path.stat().st_mtime < blend_path.stat().st_mtime
                  or (image_path.exists() and image_path.stat().st_mtime < blend_path.stat().st_mtime)):
                stale.append({"image": r.get("image"), "reason": "render predates current native model"})
            for key,filename in (("interior_plan_sha256","interior_plan.json"),("interior_module_sha256","tools/interior_design.py")):
                if r.get(key)!=sha(ROOT/filename):stale.append({"image":r.get("image"),"reason":key+" missing or differs"})
            if stage == "town":
                for key,filename in (("masterplan_sha256","masterplan.json"),("terrain_plan_sha256","terrain_plan.json"),
                                     ("terrain_profile_sha256","tools/terrain_profile.py"),("landscape_plan_sha256","landscape_plan.json")):
                    if r.get(key)!=sha(ROOT/filename):stale.append({"image":r.get("image"),"reason":key+" missing or differs"})
    check(stage + "_render_generation_matches_current_model", not stale,
          {"stale": stale, "method": "Recorded model hash when available, otherwise generation/file modification times."}, pending=bool(stale))
    expected = 13 if stage == "town" else 3
    expected_images = ({"01_town_overview.png", "02_cafe_street.png", "03_cafe_cutaway.png", "04_promenade.png", "05_harbor.png", "06_orthogonal_plan.png", "07_material_detail.png",
                        "08_home_section.png","09_hotel_section.png","10_library_section.png","11_cafe_interior.png","12_cafe_upperfloor.png","13_pond_park.png"}
                       if stage == "town" else {"study_exterior.png", "study_cutaway.png", "study_restored.png"})
    actual_images = {r.get("image") for r in records}
    check(stage + "_final_render_count", len(records) == expected and actual_images == expected_images,
          {"actual": len(records), "expected": expected, "missing": sorted(expected_images - actual_images),
           "unexpected": sorted(str(s) for s in actual_images - expected_images)},
          pending=len(records) < expected and actual_images.issubset(expected_images))
    if stage == 'town':
        recipe_path = ROOT / 'presentation_camera_overrides.json'
        recipe = read_json(recipe_path)
        shot = next((r for r in records if r.get('image') == '07_material_detail.png'), {})
        override = shot.get('presentation_camera_override', {})
        planned = recipe.get('shots', {}).get('07_material_detail', {}) if recipe else {}
        matches = (bool(planned) and bool(override)
            and recipe.get('source_blend_sha256') == sha(blend_path)
            and override.get('recipe') == recipe_path.name
            and override.get('recipe_sha256') == sha(recipe_path)
            and override.get('native_file_saved') is False
            and all(override.get(k) == planned.get(k) for k in ('location_m', 'target_m', 'lens_mm')))
        check('material_closeup_binds_documented_read_only_camera_recipe', matches,
            {'shot': shot.get('image'), 'override': override,
             'scope': 'Reproducible presentation pose; source geometry and native bytes remain frozen.'},
            pending=not override)
    errors, missing = [], []
    for r in records:
        path = ROOT / "renders" / r.get("image", "__missing__")
        if not inside(path):
            errors.append({"image": str(path), "error": "asset path escapes delivery"})
        elif not path.is_file():
            missing.append(path.name)
        else:
            with Image.open(path) as im:
                if list(im.size) != r.get("resolution"):
                    errors.append({"image": path.name, "error": "image dimensions disagree with record"})
            if sha(path) != r.get("sha256"):
                errors.append({"image": path.name, "error": "image SHA disagrees with record"})
            if "preview" in path.name or r.get("samples", 0) < 32:
                errors.append({"image": path.name, "error": "preview is not final render evidence"})
            if manifest and r.get("camera") not in manifest.get("cameras", []):
                errors.append({"image": path.name, "error": "camera absent from source manifest"})
    check(stage + "_render_files_match_evidence", not errors and not missing,
          {"errors": errors, "missing": missing}, pending=bool(missing) and not errors)
    cut = [r for r in records if r.get("cutaway")]
    if stage=='study':
        check('study_cutaway_scoped_to_cafe',len(cut)==1 and cut[0].get('roof_scope')=='Study_Cafe',cut,pending=len(records)<expected)
    else:
        hotel=next((b['id'] for b in manifest.get('buildings',[]) if b['kind']=='hotel'),None) if manifest else None
        expected_scopes={'03_cafe_cutaway.png':('Main_cafe','ground'),'08_home_section.png':('Main_home','ground'),
            '09_hotel_section.png':(hotel,'ground'),'10_library_section.png':('Main_library','ground'),'12_cafe_upperfloor.png':('Main_cafe','upper')}
        actual_scopes={r['image']:(r.get('roof_scope'),r.get('section_mode')) for r in cut}
        check('town_sections_have_local_building_and_floor_scope',actual_scopes==expected_scopes,
            {'expected':expected_scopes,'actual':actual_scopes},pending=len(records)<expected)
    if stage == "study":
        a, b = ROOT / "renders/study_exterior.png", ROOT / "renders/study_restored.png"
        if a.exists() and b.exists():
            with Image.open(a) as ia, Image.open(b) as ib:
                pixels_a, pixels_b = ia.convert("RGBA").tobytes(), ib.convert("RGBA").tobytes()
                pixel_equal = ia.size == ib.size and pixels_a == pixels_b
                diff_box = ImageChops.difference(ia.convert("RGB"), ib.convert("RGB")).getbbox() if ia.size == ib.size else None
                if ia.size == ib.size:
                    channels = ImageChops.difference(ia.convert('RGBA'), ib.convert('RGBA')).split()
                    maximum = channels[0]
                    for channel in channels[1:]:maximum = ImageChops.lighter(maximum, channel)
                    histogram = maximum.histogram()
                    changed_pixels = sum(histogram[1:])
                    max_channel_error = max(i for i, count in enumerate(histogram) if count)
                    total_pixels = ia.width * ia.height
                else:changed_pixels, max_channel_error, total_pixels = 1, 255, 1
            equivalent = pixel_equal or (max_channel_error <= 1 and changed_pixels / total_pixels <= .0001)
            check("study_exterior_restoration_image_equivalent", equivalent,
                  {"exterior_sha256": sha(a), "restored_sha256": sha(b), "decoded_pixels_equal": pixel_equal,
                   "decoded_rgba_sha256": hashlib.sha256(pixels_a).hexdigest(), "difference_bbox": diff_box,
                   "restored_decoded_rgba_sha256": hashlib.sha256(pixels_b).hexdigest(),
                   "changed_pixels": changed_pixels, "total_pixels": total_pixels,
                   "maximum_channel_error_8bit": max_channel_error,
                   "acceptance_limits": {"maximum_channel_error_8bit": 1, "maximum_changed_pixel_fraction": .0001},
                   "note": "Exact decoded equality is reported separately. Sparse one-unit 8-bit differences are permitted for independently rendered CPU images; this bounded quantization tolerance does not permit changed visible geometry. Native cover-state restoration is checked independently."},
                  pending=len(records)<expected or bool(stale))
        else:
            check("study_exterior_restoration_image_equivalent", False, "Restoration images not ready.", pending=True)
    DETAILS[stage + "_renders"] = records


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        self.links.extend(value for key, value in attrs if key in ("src", "href") and value)


def html_audit():
    path = ROOT / "PRESENTATION.html"
    if not path.exists():
        check("presentation_local_links", False, "HTML presentation not present yet.", pending=True)
        return
    text = path.read_text(encoding="utf-8")
    parser = Links()
    parser.feed(text)
    links = set(parser.links + re.findall(r"\bsrc\s*:\s*['\"]([^'\"]+)['\"]", text))
    escaped, missing, checked = [], [], []
    for value in sorted(links):
        url = urlsplit(value)
        if url.scheme or value.startswith("#") or not url.path:
            continue  # Remote citations and in-page links are not local assets.
        target = ROOT / unquote(url.path)
        if not inside(target):
            escaped.append(value)
        elif not target.exists():
            missing.append(value)
        else:
            checked.append(value)
    check("presentation_local_links", not escaped and not missing,
          {"checked_count": len(checked), "escaped": escaped, "missing": missing}, pending=bool(missing) and not escaped)
    DETAILS["presentation_checked_links"] = checked


def game_assets_audit():
    manifest=read_json(ROOT/'game_assets/export_manifest.json')
    if not manifest:return
    source_matches=(manifest.get('source_blend_sha256')==sha(ROOT/'living_town_complete.blend')
        and manifest.get('source_manifest_sha256')==sha(ROOT/'town_manifest.json')
        and manifest.get('source_interior_plan_sha256')==sha(ROOT/'interior_plan.json')
        and manifest.get('source_interior_module_sha256')==sha(ROOT/'tools/interior_design.py'))
    check('game_assets_bind_final_native_model',source_matches and manifest.get('status')=='PASS',
        {'source_blend_sha256':manifest.get('source_blend_sha256'),'source_manifest_sha256':manifest.get('source_manifest_sha256'),
            'source_interior_plan_sha256':manifest.get('source_interior_plan_sha256'),'source_interior_module_sha256':manifest.get('source_interior_module_sha256'),'status':manifest.get('status')},
        pending=not source_matches)
    main={b['id'] for b in json.loads((ROOT/'masterplan.json').read_text(encoding='utf-8'))['buildings']}
    exports=manifest.get('buildings',[]);errors=[];embedded_errors=[];verified=[]
    def inspect(record):
        if not record:return None
        path=ROOT/'game_assets'/record.get('file','__missing__')
        if not inside(path) or not path.is_file():errors.append({'file':record.get('file'),'reason':'missing/escaped exported asset'});return None
        if sha(path)!=record.get('sha256'):errors.append({'file':record.get('file'),'reason':'GLB hash differs from export record'})
        try:
            with path.open('rb') as stream:
                magic,version,length=struct.unpack('<4sII',stream.read(12))
                size,typ=struct.unpack('<II',stream.read(8));doc=json.loads(stream.read(size).decode('utf-8').rstrip('\0 \t\r\n'))
            if magic!=b'glTF' or version!=2 or length!=path.stat().st_size or typ!=0x4E4F534A:errors.append({'file':record.get('file'),'reason':'invalid GLB container'})
            for category in('buffers','images'):
                for ref in doc.get(category,[]):
                    if ref.get('uri') and not ref['uri'].startswith('data:'):embedded_errors.append({'file':record['file'],'external_uri':ref['uri']})
            verified.append(record['file']);return doc
        except (OSError,ValueError,struct.error) as exc:errors.append({'file':record.get('file'),'reason':str(exc)});return None
    town=inspect(manifest.get('town_game'));high=inspect(manifest.get('town_high_detail'))
    for b in exports:inspect(b.get('standalone'))
    camera=inspect(manifest.get('camera_rig'))
    prefabs=sum(bool(b.get('standalone')) for b in exports)
    check('portable_glb_town49_prefabs_and_camera_files',not errors and set(b['id'] for b in exports)==main and prefabs==49 and town is not None and high is not None and camera is not None,
        {'prefabs':prefabs,'files_verified':len(verified),'errors':errors})
    check('portable_glb_images_and_buffers_embedded',not embedded_errors and bool(verified),embedded_errors)
    if town:
        nodes=town.get('nodes',[]);floor_nodes=[n for n in nodes if n.get('extras',{}).get('floor_index') is not None]
        room_nodes=[n for n in nodes if n.get('extras',{}).get('room_id')]
        asset_ids={n.get('extras',{}).get('interior_asset_id') for n in nodes if n.get('extras',{}).get('interior_asset_id')}
        planned=json.loads((ROOT/'interior_plan.json').read_text(encoding='utf-8'))
        check('portable_glb_preserves_detailed_floor_room_asset_metadata',len(floor_nodes)==89 and len(room_nodes)==planned['room_count'] and len(asset_ids)==planned['furnishing_count'],
            {'floor_nodes':len(floor_nodes),'room_nodes':len(room_nodes),'unique_furniture_ids':len(asset_ids)})
    reports=[]
    for name in('logical_report','render_report'):
        report=read_json(ROOT/'integration/godot/evidence'/f'{name}.json')
        if not report:continue
        stale=report.get('source_blend_sha256')!=sha(ROOT/'living_town_complete.blend') or report.get('glb_sha256')!=manifest.get('town',{}).get('sha256')
        checks=report.get('checks',[])
        check('Godot_'+name+'_passes_current_export',not stale and report.get('status')=='PASS' and bool(checks) and all(c.get('passed') for c in checks),
            {'status':report.get('status'),'checks':len(checks),'evidence_label':report.get('evidence_label'),'source_binding_stale':stale,'failed':[c for c in checks if not c.get('passed')]},pending=stale)
        reports.append(report)
    screenshots=['overview.png','cafe_cutaway.png','standalone_cafe_cutaway.png','interior_eyeview.png','pond_park.png'];missing=[];black=[]
    for name in screenshots:
        path=ROOT/'integration/godot/evidence'/name
        if not path.is_file():missing.append(name);continue
        with Image.open(path) as im:
            extrema=im.convert('RGB').getextrema()
            if max(hi for lo,hi in extrema)-min(lo for lo,hi in extrema)<20:black.append(name)
    check('Godot_consumer_exterior_sections_and_closed_interior_images',not missing and not black,
        {'missing':missing,'low_variation_images':black,'scope':'File/colour-variation check plus consumer renderer assertions; visual review remains separate.'},pending=bool(missing))
    DETAILS['game_assets']={'manifest':'game_assets/export_manifest.json','verified_files':verified,'consumer_reports':reports,
        'scope':'Portable visual meshes and isolated Godot import/reveal/render evidence. Existing game integration, collision/navigation and shipping performance are not asserted.'}


def flythrough_audit():
    record=read_json(ROOT/'evidence/flythrough_render.json')
    if not record:return
    path=ROOT/record.get('video','__missing__');safe_path=inside(path);exists=safe_path and path.is_file()
    header=b''
    if exists:
        with path.open('rb') as stream:header=stream.read(12)
    current={'source_blend_sha256':sha(ROOT/'living_town_complete.blend'),'masterplan_sha256':sha(ROOT/'masterplan.json'),
        'terrain_plan_sha256':sha(ROOT/'terrain_plan.json'),'terrain_profile_sha256':sha(ROOT/'tools/terrain_profile.py'),
        'landscape_plan_sha256':sha(ROOT/'landscape_plan.json'),'interior_plan_sha256':sha(ROOT/'interior_plan.json'),
        'interior_module_sha256':sha(ROOT/'tools/interior_design.py')}
    stale_bindings=[k for k,v in current.items() if record.get(k)!=v];stale=bool(stale_bindings)
    dimensions=record.get('resolution')==[1280,720]
    metrics=record.get('frames')==240 and record.get('fps')==24 and record.get('seconds')==10
    actual_sha=sha(path) if exists else None
    checksum=bool(record.get('video_sha256')) and record['video_sha256']==actual_sha
    raw_probe=record.get('ffprobe');probe=raw_probe if isinstance(raw_probe,dict) else {}
    probe_fields={'video_sha256','width','height','frame_count','fps','duration_seconds','frame_count_source'}
    missing_probe=sorted(probe_fields-set(probe))
    try:
        probe_fps=float(Fraction(str(probe.get('fps'))));probe_seconds=float(probe.get('duration_seconds'))
    except (ValueError,TypeError,ZeroDivisionError):probe_fps=probe_seconds=float('nan')
    probed=(not missing_probe and probe.get('video_sha256')==actual_sha and checksum
        and probe.get('width')==1280 and probe.get('height')==720 and probe.get('frame_count')==240
        and probe.get('frame_count_source')=='nb_read_frames'
        and math.isclose(probe_fps,24,abs_tol=.001) and math.isfinite(probe_seconds) and abs(probe_seconds-10)<=.05+1e-9)
    pending=(safe_path and not exists) or stale or not record.get('video_sha256') or bool(missing_probe)
    check('camera_movement_video_rendered_from_current_model',safe_path and exists and path.stat().st_size>10_000 and header[4:8]==b'ftyp' and not stale and dimensions and metrics and checksum and probed,
        {'file':record.get('video'),'source_binding_stale':stale,'different_bindings':stale_bindings,'frames':record.get('frames'),'fps':record.get('fps'),
         'resolution':record.get('resolution'),'bytes':path.stat().st_size if exists else None,'video_sha256':actual_sha,
         'video_sha256_matches':checksum,'ffprobe':probe,'missing_probe_fields':missing_probe,'probe_metrics_match':probed,
         'scope':'Exact encoded MP4 hash and source binding, plus ffprobe read-frame count, measured frame rate, dimensions and duration bound to the same file. Playback quality requires separate visual review.'},pending=pending and safe_path)
    DETAILS['flythrough']=record


def program_detail_audit():
    records=read_json(ROOT/'evidence/program_detail_renders.json')
    if records is None:return
    expected={'kitchen_fixture_detail.png':'kitchen_run','dining_seating_detail.png':'dining_table','mill_mechanism_detail.png':'mill_mechanism'}
    current={'source_blend_sha256':sha(ROOT/'living_town_complete.blend'),'interior_plan_sha256':sha(ROOT/'interior_plan.json')}
    actual={r.get('image') for r in records};missing=sorted(set(expected)-actual);errors=[];stale=[]
    plan=json.loads((ROOT/'interior_plan.json').read_text(encoding='utf-8'))
    planned_assets={a['id']:a['kind'] for b in plan['buildings'] for f in b['levels'] for r in f['rooms'] for a in r['assets']}
    for record in records:
        name=record.get('image');path=ROOT/'evidence'/str(name)
        wrong=[key for key,value in current.items() if record.get(key)!=value]
        if wrong:stale.append({'image':name,'different_bindings':wrong})
        if name not in expected:errors.append({'image':name,'reason':'unexpected fixture plate'});continue
        if not inside(path):errors.append({'image':name,'reason':'plate path escapes delivery'});continue
        if not path.is_file():missing.append(name);continue
        if sha(path)!=record.get('sha256'):errors.append({'image':name,'reason':'image SHA disagrees with record'})
        try:
            with Image.open(path) as im:
                if list(im.size)!=record.get('resolution') or min(im.size)<900:errors.append({'image':name,'reason':'invalid final plate dimensions'})
        except OSError as exc:errors.append({'image':name,'reason':str(exc)})
        if record.get('samples',0)<32:errors.append({'image':name,'reason':'preview sampling is not final evidence'})
        if record.get('role')!=expected[name] or planned_assets.get(record.get('asset_id'))!=expected[name] or record.get('mesh_objects',0)<1:
            errors.append({'image':name,'reason':'fixture identity/actual native mesh record missing or mismatched'})
    check('three_program_fixture_plates_match_current_native_and_images',len(records)==3 and actual==set(expected) and not missing and not errors and not stale,
        {'expected':expected,'missing':missing,'errors':errors,'stale':stale,'current_bindings':current,
         'scope':'Actual-source and image integrity of isolated kitchen, dining-seat and mill plates; fixture appearance is reviewed separately.'},
        pending=(bool(missing) or bool(stale)) and not errors)
    DETAILS['program_fixture_plates']=records


def browser_evidence_audit():
    record = read_json(ROOT / 'evidence/presentation_browser_qa.json')
    if not record:
        return
    expected_tests = {'hero_is_actual_native_town', 'all_dynamic_gallery_images_decode',
        'all_sixteen_native_stills_decode', 'all_three_isolated_fixture_plates_decode',
        'all_nineteen_actual_image_reviews_current', 'desktop_no_horizontal_overflow',
        'mobile_no_horizontal_overflow', 'mobile_pond_modal_opens',
        'actual_mp4_probe', 'native_film_browser_decode_and_playback',
        'video_source_and_download_link_active', 'no_failed_image_requests',
        'no_javascript_errors'}
    tests = record.get('tests', [])
    missing_tests = sorted(expected_tests - {test.get('name') for test in tests})
    assets = record.get('asset_sha256', {})
    required_assets = {'PRESENTATION.html', 'DELIVERY_GUIDE.md',
        'presentation_camera_overrides.json', 'town_manifest.json', 'masterplan.json',
        'terrain_plan.json', 'interior_plan.json', 'landscape_plan.json',
        'evidence/final_source_freeze.json', 'evidence/native_scene_audit.json',
        'evidence/renders_town.json', 'evidence/renders_study.json',
        'evidence/program_detail_renders.json', 'evidence/FINAL_TOWN_RENDER_REVIEW.json',
        'evidence/FINAL_INTERIOR_RENDER_REVIEW.json', 'renders/coastal_flythrough.mp4',
        'evidence/flythrough_render.json'}
    native = json.loads((ROOT / 'evidence/native_scene_audit.json').read_text(encoding='utf-8'))
    native_semantics = {key: value for key, value in native.items() if key != 'generated_utc'}
    semantics_match = record.get('native_audit_snapshot') == native_semantics
    errors = []
    refreshed_native_report = False
    for relative, checksum in assets.items():
        path = ROOT / relative
        if not inside(path) or not path.is_file():
            errors.append({'file': relative, 'reason': 'missing or outside delivery'})
        elif sha(path) != checksum:
            if relative == 'evidence/native_scene_audit.json' and semantics_match:
                refreshed_native_report = True
            else:
                errors.append({'file': relative, 'reason': 'bytes differ from browser-reviewed asset'})
    film = ROOT / 'renders/coastal_flythrough.mp4'
    sources_match = (record.get('native_source_sha256') == sha(ROOT / 'living_town_complete.blend')
        and record.get('study_source_sha256') == sha(ROOT / 'living_town_building_study.blend'))
    video = record.get('video') or {}
    movie_record = video.get('record') or {}
    film_matches = (film.is_file() and video.get('current_source_bound') is True
        and movie_record.get('video_sha256') == sha(film))
    passed = (record.get('status') == 'PASS' and record.get('mode') == 'desktop/mobile Chromium'
        and not missing_tests and bool(tests) and all(test.get('status') == 'PASS' for test in tests)
        and required_assets <= set(assets) and not errors and semantics_match
        and sources_match and film_matches)
    check('fresh_desktop_mobile_browser_review_matches_delivered_assets', passed,
        {'status': record.get('status'), 'mode': record.get('mode'), 'tests': len(tests),
         'missing_tests': missing_tests, 'missing_asset_bindings': sorted(required_assets - set(assets)),
         'asset_errors': errors, 'native_semantics_match': semantics_match,
         'native_report_reopened_with_unchanged_semantics': refreshed_native_report,
         'sources_match': sources_match, 'video_matches': film_matches,
         'scope': 'Exact browser-reviewed asset bytes and actual playback tests. A fresh native reopen may replace its generated timestamp only when the complete saved audit semantics still match.'})


def main():
    source_freeze_audit()
    town = read_json(ROOT / "town_manifest.json")
    study = read_json(ROOT / "study_manifest.json")
    data = read_json(SOURCE_MAP)
    if data:source_audit(data, town, study)
    for stage, manifest, blend in (("town", town, "living_town_complete.blend"), ("study", study, "living_town_building_study.blend")):
        ownership_audit(manifest, stage)
        blend_audit(stage, blend)
        render_audit(stage, manifest)
    texture_audit()
    terrain_audit(town)
    interior_audit(town,study)
    native_evidence_audit()
    game_assets_audit()
    flythrough_audit()
    program_detail_audit()
    browser_evidence_audit()
    if (ROOT / "street_plan.json").exists():
        DETAILS["legacy_street_plan"]={"file":"street_plan.json","acceptance":False,"note":"Historical source-layout comparison; superseded by masterplan.json."}
    html_audit()
    counts = {status: sum(c["status"] == status for c in CHECKS) for status in ("PASS", "FAIL", "PENDING")}
    verdict = "FAIL" if counts["FAIL"] else ("PENDING" if counts["PENDING"] else "PASS")
    report = {"schema_version": 1, "generated_utc": datetime.now(timezone.utc).isoformat(), "status": verdict,
              "counts": counts, "checks": CHECKS, "details": DETAILS,
              "limits": ["No Blender mutation or bpy import; collection names are checked from manifests, not native mesh contents.",
                         "Texture originality is declared procedural provenance, not an independent copyright determination.",
                         "Asset boundary checks cover manifest texture/render references and HTML links. Packed Blender dependencies require the separate native Blender audit.",
                         "No native game integration, accessibility, interaction or runtime fit is asserted."]}
    out = ROOT / "evidence/delivery_verification.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"status": verdict, "counts": counts, "unresolved": [c for c in CHECKS if c["status"] != "PASS"],
                      "report": str(out)}, indent=2))
    return 0 if verdict == "PASS" else (2 if verdict == "PENDING" else 1)


if __name__ == "__main__":
    sys.exit(main())
