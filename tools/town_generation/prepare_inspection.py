"""Bind a generated expansion and unchanged baseline GLB to inspection cameras."""
import argparse
import hashlib
import json
import math
from pathlib import Path

REPO=Path(__file__).resolve().parents[2]


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream,"sha256").hexdigest()


def local(b,x,y,z):
    a=math.radians(b["yaw_degrees"])
    return [b["center"][0]+x*math.cos(a)-y*math.sin(a),
            b["center"][1]+x*math.sin(a)+y*math.cos(a),b["pad_level_m"]+z]


def prepare(run_root, output, baseline=None, duration_seconds=360, fps=18):
    root=Path(run_root).resolve(strict=True)
    output=Path(output).resolve()
    if output.exists():raise FileExistsError(output)
    manifest=json.loads((root/"scene/expansion_manifest.json").read_text(encoding="utf-8"))
    plan=json.loads((root/"territory_plan.json").read_text(encoding="utf-8"))
    chunks=json.loads((root/"scene/chunk_manifest.json").read_text(encoding="utf-8"))
    baseline=Path(baseline or REPO/"art/living_town/game_assets_reserve/living_town_game.glb").resolve(strict=True)
    assets=[{"path":str(baseline),"sha256":sha(baseline),"baseline":True}]
    for row in chunks["chunks"]:
        file=(root/"scene"/row["path"]).resolve(strict=True)
        if sha(file)!=row["sha256"]:raise ValueError("Stale GLB chunk")
        assets.append({"path":str(file),"sha256":row["sha256"],"baseline":False})
    views=[]
    c=manifest["cameras"]["overview"]
    end=[c["position"][0]-30,c["position"][1]+15,c["position"][2]+20]
    views.append({"id":"compound_overview","title":"A larger inhabited territory",
                  "subtitle":f"{len(plan['buildings'])} new buildings / five connected districts / retained coast and reserve",
                  "from":c["position"],"to":end,"target":c["target"],"projection":"orthographic","size":c["ortho"]})
    for district in plan["districts"]:
        members=[b for b in plan["buildings"] if b["district"]==district["id"]]
        cx=sum(b["center"][0] for b in members)/len(members)
        cy=sum(b["center"][1] for b in members)/len(members)
        z=sum(b["pad_level_m"] for b in members)/len(members)
        spread=max(max(b["center"][k] for b in members)-min(b["center"][k] for b in members) for k in (0,1))
        distance=max(45,spread*.78)
        views.append({"id":district["id"],"title":district["name"],
                      "subtitle":f"{len(members)} furnished buildings / irregular frontage and planted courts",
                      "from":[cx+distance*.65,cy-distance,z+distance*.85],
                      "to":[cx+distance*.4,cy-distance*.85,z+distance*.70],"target":[cx,cy,z+3]})
    c=manifest["cameras"]["street"]
    views.append({"id":"street_materials","title":"Street scale / plaster, slate and joinery",
                  "subtitle":"Metric CC0 PBR maps and contextual limewash weathering",
                  "from":c["position"],"to":[*c["position"][:2],c["position"][2]+.45],"target":c["target"],
                  "fov_degrees":math.degrees(2*math.atan(36/(2*c.get("lens",28)*1.6)))})
    focus=next(b for b in plan["buildings"] if b["id"]==plan["detailed_focus_ids"][0])
    ownership=next(b for b in manifest["ownership_metadata"]["buildings"] if b["building_id"]==focus["id"])
    c=manifest["cameras"]["interior"]
    views.append({"id":"furnished_interior","title":"Rooms, furniture and circulation / local cutaway",
                  "subtitle":"Front cover and upper floors hidden for architectural inspection",
                  "from":c["position"],"to":local(focus,-focus["width"]*.20,-focus["depth"]/2-5,8.2),
                  "fov_degrees":math.degrees(2*math.atan(36/(2*c.get("lens",37)*1.6))),
                  "target":c["target"],"cutaway":{"building_id":focus["id"],
                      "expected_layer_counts":ownership["presentation_layer_counts"]}})
    c=manifest["cameras"]["terrain"]
    views.append({"id":"terrain_and_reserve","title":"Terrain, foundations and the reserve edge",
                  "subtitle":"Graded streets, supported pads and retained natural relief",
                  "from":c["position"],"to":[*c["position"][:2],c["position"][2]+.7],"target":c["target"],
                  "fov_degrees":math.degrees(2*math.atan(36/(2*c.get("lens",35)*1.6)))})
    removed=set(chunks["replace_baseline_nodes"]+manifest["terrain"]["removed_baseline_object_names"])
    config={"schema":"living_town.territory_inspection_config.v1","assets":assets,
            "removed_baseline_object_names":sorted(removed),"cameras":views,
            "duration_seconds":duration_seconds,"fps":fps,
            "report":str(output.parent/(output.stem+"_report.json")),
            "capture_directory":str(output.parent/(output.stem+"_captures")),
            "source_manifest_sha256":sha(root/"scene/expansion_manifest.json"),
            "scope":"Independent architectural inspection. Does not import the expansion into the playable simulation."}
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(config,indent=2)+"\n",encoding="utf-8")
    return config


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run",dest="run_root",required=True,type=Path)
    parser.add_argument("--output",required=True,type=Path)
    parser.add_argument("--baseline",type=Path)
    parser.add_argument("--duration-seconds",type=int,default=360)
    parser.add_argument("--fps",type=int,default=18)
    result=prepare(**vars(parser.parse_args()))
    print(json.dumps({"assets":len(result["assets"]),"cameras":len(result["cameras"])}))
