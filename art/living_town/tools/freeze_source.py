"""Record a source freeze only after a fresh native reopen and plan audits."""
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
def read(name):return json.loads((ROOT/name).read_text(encoding='utf-8'))
def sha(name):return hashlib.sha256((ROOT/name).read_bytes()).hexdigest()

native=read('evidence/native_scene_audit.json')
interior=read('evidence/interior_planning_audit.json')
geometry=read('evidence/planning_revision_geometry_audit.json')
town=read('town_manifest.json');terrain=read('terrain_plan.json');plan=read('interior_plan.json')
assert native['status']==interior['status']==geometry['status']=='PASS'
contact = next(c for c in native['checks'] if c['id']=='all57_chimney_bases_intersect_actual_roof_surfaces')
assert contact['status']=='PASS'
assert native['source_blend_sha256']==sha('living_town_complete.blend')
assert geometry['masterplan_sha256']==terrain['masterplan_sha256']==sha('masterplan.json')
assert interior['interior_plan_sha256']==sha('interior_plan.json')
assert interior['interior_module_sha256']==sha('tools/interior_design.py')
for key,name in [('masterplan_sha256','masterplan.json'),('terrain_plan_sha256','terrain_plan.json'),
                 ('terrain_profile_sha256','tools/terrain_profile.py'),('landscape_plan_sha256','landscape_plan.json'),
                 ('landscape_details_sha256','tools/landscape_details.py'),('interior_plan_sha256','interior_plan.json'),
                 ('interior_module_sha256','tools/interior_design.py')]:
    assert native[key]==town[key]==sha(name),(key,'stale native/manifest binding')
assert not terrain['validation']['public_street_over_8_percent']
assert not terrain['validation']['other_grade_reviews']
assert terrain['park_pond']['bank_grade_pass']
names=['living_town_complete.blend','living_town_building_study.blend','masterplan.json','terrain_plan.json',
       'landscape_plan.json','interior_plan.json','tools/build_living_town.py','tools/terrain_profile.py',
       'tools/interior_design.py','tools/refine_environment.py','tools/landscape_details.py']
record={'schema':'living_town.source_freeze.v5','generated_utc':datetime.now(timezone.utc).isoformat(),
        'scope':'Reference-led urban/interior/landscape revision with actual roof-contact repair for all chimney bases; exports and media must bind these saved native bytes.',
        'files':{name:sha(name) for name in names},'native_checks':len(native['checks']),
        'buildings':plan['building_count'],'levels':plan['floor_count'],'zones':plan['room_count'],
        'activity_rooms':interior['purposeful_activity_rooms'],'furnishing_assemblies':plan['furnishing_count'],
        'stair_flights':interior['stair_flights'],'objects':native['native']['objects'],
        'mesh_vertices':native['native']['mesh_vertices'],'cameras':len(native['native']['cameras']),
        'reference_tree_count':len(read('landscape_plan.json')['street_trees']),
        'pond_water_z_m':terrain['park_pond']['water_z_m'],'pond_bed_z_m':terrain['park_pond']['bed_z_m'],
        'pond_maximum_sampled_bank_grade_percent':terrain['park_pond']['maximum_sampled_bank_grade_percent'],
        'chimney_roof_contact':contact['detail']}
target=ROOT/'evidence/final_source_freeze.json';temporary=target.with_suffix('.tmp')
with temporary.open('w',encoding='utf-8') as stream:
    json.dump(record,stream,indent=2);stream.flush();os.fsync(stream.fileno())
temporary.replace(target)
print(json.dumps(record,indent=2))
