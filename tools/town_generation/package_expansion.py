"""Curate a verified, portable town asset ZIP without copying the workspace.

No engine or network process is started. Historical evidence is copied intact;
new inspection paths are generated after extraction with prepare_inspection.py.
All gates and source hashing finish before a fresh delivery directory is made.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import zipfile

REPO = Path(__file__).resolve().parents[2]
ZIP_NAME = "LivingTown_Territory_Expansion_v1.zip"
MAX_BYTES = 2_000_000_000
CHUNK = 1024*1024
BASELINE = REPO/"art/living_town"


def need(condition, message):
    if not condition:raise ValueError(message)


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream,"sha256").hexdigest()


def encoded(value):
    return (json.dumps(value,indent=2,ensure_ascii=False,allow_nan=False)+"\n").encode("utf-8")


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def beneath(root, value):
    root=Path(root).resolve(strict=True)
    path=(root/value).resolve(strict=True)
    need(path.is_relative_to(root),"Curated input escapes its declared root: "+str(value))
    need(path.is_file(),"Expected a file: "+str(path))
    return path


def member_name(name):
    need(isinstance(name,str) and "\\" not in name,"ZIP member must use forward slashes")
    path=PurePosixPath(name)
    need(name and not path.is_absolute() and ":" not in name and
         all(p not in (".","..","") for p in name.split("/")),"Unsafe ZIP member: "+name)
    need(path.suffix.lower() not in (".blend1",".ogv",".log",".pyc"),"Excluded artifact type: "+name)
    need(not any(p.lower() in ("__pycache__",".git",".godot","venv",".venv","node_modules","models","voice_cache") for p in path.parts),"Excluded cache/runtime path: "+name)
    return path.as_posix()


def fresh_output(output, roots):
    output=Path(output).resolve()
    protected=[REPO/"art",REPO/"tools",REPO/"game",REPO/".git",*[Path(p).resolve() for p in roots]]
    need(not any(output==p or output.is_relative_to(p) or p.is_relative_to(output) for p in protected),
         "Delivery output overlaps an input or canonical source")
    if output.exists():raise FileExistsError("Use a fresh delivery directory: "+str(output))
    return output


def pass_receipt(path, statuses=("PASS",)):
    value=load(path)
    need(value.get("status") in statuses,"Required receipt did not pass: "+str(path))
    return value


def check_consumer_sources(report, label="Consumer"):
    """Bind runtime proof to the exact viewer source curated into the ZIP."""
    viewer=REPO/"tools/town_generation/godot_viewer"
    need(report.get("consumer_source_sha256")==sha(viewer/"main.gd"),
         label+" used another consumer source")
    need(report.get("project_sha256")==sha(viewer/"project.godot"),
         label+" used another viewer project")


def check_binding(binding, label="input"):
    path=Path(binding["path"]).resolve(strict=True)
    need(path.is_file(),label+" is not a file")
    if "bytes" in binding:need(path.stat().st_size==binding["bytes"],label+" length differs")
    need(sha(path)==binding["sha256"],label+" SHA differs: "+str(path))
    return path


def check_bindings(value):
    """Verify historical file bindings, including excluded raw capture input."""
    if isinstance(value,dict):
        if isinstance(value.get("path"),str) and isinstance(value.get("sha256"),str):
            check_binding(value)
        for child in value.values():check_bindings(child)
    elif isinstance(value,list):
        for child in value:check_bindings(child)


class Catalog:
    def __init__(self):
        self.records={}
        self.case_names={}

    def _put(self,name,row):
        name=member_name(name)
        previous=self.case_names.get(name.casefold())
        need(previous is None or previous==name,"Case-colliding ZIP member: "+name)
        if name in self.records:
            need(self.records[name]["sha256"]==row["sha256"],"Conflicting member content: "+name)
            return
        self.case_names[name.casefold()]=name
        self.records[name]=dict(row,path=name)

    def add(self,path,name,expected=None):
        path=Path(path)
        need(not path.is_symlink(),"Symlink files are not curated payloads: "+str(path))
        path=path.resolve(strict=True)
        need(path.is_file(),"Expected a curated input file: "+str(path))
        digest=sha(path)
        if expected is not None:need(digest==expected,"Curated source SHA differs: "+str(path))
        self._put(name,{"source":path,"bytes":path.stat().st_size,"sha256":digest})

    def text(self,name,text):
        data=text.encode("utf-8") if isinstance(text,str) else bytes(text)
        self._put(name,{"data":data,"bytes":len(data),"sha256":hashlib.sha256(data).hexdigest()})

    def manifest_rows(self):
        return [{"path":name,"bytes":row["bytes"],"sha256":row["sha256"]}
                for name,row in sorted(self.records.items())]


def write_archive(catalog,output,metadata):
    """Write fresh output and verify every archive member by streaming readback."""
    output=Path(output)
    if output.exists():raise FileExistsError(output)
    total=sum(row["bytes"] for row in catalog.records.values())
    need(total<MAX_BYTES,"Curated payload exceeds the 2GB release target")
    manifest={"schema":"living_town.territory_bundle.v1",**metadata,
              "files":catalog.manifest_rows(),"payload_bytes":total,
              "hash_policy":"Every payload is bound here. The detached package receipt additionally binds this manifest and every ZIP member, avoiding a circular manifest self-hash."}
    manifest_bytes=encoded(manifest)
    members=dict(catalog.records)
    members["bundle_manifest.json"]={"data":manifest_bytes,"bytes":len(manifest_bytes),"sha256":hashlib.sha256(manifest_bytes).hexdigest()}
    need(total+len(manifest_bytes)+len(members)*200<MAX_BYTES,"Curated payload and ZIP metadata exceed the 2GB release target")
    output.mkdir(parents=True,exist_ok=False)
    archive=output/ZIP_NAME
    try:
        with zipfile.ZipFile(archive,"x",allowZip64=True,compression=zipfile.ZIP_DEFLATED,compresslevel=4) as zipped:
            for name,row in sorted(members.items()):
                info=zipfile.ZipInfo(name,date_time=(2026,10,20,0,0,0))
                info.compress_type=zipfile.ZIP_STORED if PurePosixPath(name).suffix.lower() in (".blend",".png",".jpg",".gif",".mp4",".mp3",".wav") else zipfile.ZIP_DEFLATED
                info.external_attr=0o100644<<16
                digest=hashlib.sha256();count=0
                with zipped.open(info,"w",force_zip64=True) as target:
                    if "data" in row:
                        target.write(row["data"]);digest.update(row["data"]);count=len(row["data"])
                    else:
                        with row["source"].open("rb") as source:
                            for block in iter(lambda:source.read(CHUNK),b""):
                                target.write(block);digest.update(block);count+=len(block)
                need(count==row["bytes"] and digest.hexdigest()==row["sha256"],"Source changed during packaging: "+name)
        need(archive.stat().st_size<MAX_BYTES,"ZIP exceeds the 2GB release target")
        readback=[]
        with zipfile.ZipFile(archive,"r") as zipped:
            need(set(zipped.namelist())==set(members) and len(zipped.infolist())==len(members),"ZIP member inventory differs")
            for name,row in sorted(members.items()):
                digest=hashlib.sha256();count=0
                with zipped.open(name) as source:
                    for block in iter(lambda:source.read(CHUNK),b""):
                        digest.update(block);count+=len(block)
                need(count==row["bytes"] and digest.hexdigest()==row["sha256"],"ZIP readback differs: "+name)
                readback.append({"path":name,"bytes":count,"sha256":digest.hexdigest()})
        for name,row in catalog.records.items():
            if "source" in row:
                need(row["source"].stat().st_size==row["bytes"] and sha(row["source"])==row["sha256"],
                     "Source changed before packaging completed: "+name)
        (output/"bundle_manifest.json").write_bytes(manifest_bytes)
        report={"schema":"living_town.territory_package_review.v1","status":"PASS","archive":{"path":archive.name,"bytes":archive.stat().st_size,"sha256":sha(archive)},
                "archive_members":readback,"readback":"Every member streamed and SHA-256 checked after ZIP close", "source_files_unchanged":True}
        (output/"package_report.json").write_bytes(encoded(report))
        return report
    except Exception as exc:
        (output/"package_failure.json").write_bytes(encoded({"status":"FAIL","error":str(exc)}))
        raise


def _readme(manifest,seed):
    return f"""# Living Town — territory expansion

Open **generation/scene/expanded_town.blend** in Blender. It contains the packed
original town/reserve and {manifest['building_count']} additional furnished buildings.
The five expansion districts and replacement terrain are also separate portable
GLB chunks in generation/scene/chunks/. Keep the original baseline GLB and hide
the exact removed/replaced source nodes listed in the scene manifests.

The six-minute actual Godot architectural tour is in media/. This is an asset
inspection, with engine-agnostic glTF geometry and conventional PBR maps.
Navigation, physics and real-time performance require separate game integration.

Historical reports and original_inspection.json retain their original bytes and
machine paths. bundle_manifest.json maps source paths to the bundled payload.
Regenerate a local inspection configuration after extracting this ZIP, from the
extraction root (Python and Godot must be installed; the Python planning/map
and GLB verification tools also use Pillow and NumPy):

```sh
python tools/town_generation/prepare_inspection.py --run generation --baseline baseline/living_town_game.glb --output inspection/local_inspection.json --duration-seconds 360 --fps 18
godot --path tools/town_generation/godot_viewer -- --config="<absolute path to inspection/local_inspection.json>"
```

To generate a fresh native scene, use a fresh output directory and your own
Blender executable. The authoring worker uses CPU and six threads:

```sh
python tools/town_generation/generate_town.py --output rebuilt_generation --seed {seed} --blender "<Blender executable>" --pbr-library art/living_town/refinement_pilot/scanned_pbr_v3/library_manifest.json --infinigen-asset upstream/infinigen/courtyard_planter.blend
```

The original packed native is art/living_town/living_town_complete.blend; the
unchanged original consumer asset is baseline/living_town_game.glb. Canonical
planning sources, authoring helpers, prepared scanned PBR maps/provenance,
selected upstream prototype and notices are included. No authoring runtime,
venv, model weights, raw movie capture, film references or caches are included.
Native reopening and offline verification accept explicit --plan/--baseline
overrides when historical absolute source paths no longer exist.

LICENSE covers this project's original code. Scan provenance records CC0-1.0
sources. See upstream/infinigen/INFINIGEN_NOTICES.txt for the selected BSD factory
contribution and authoring/runtime license boundaries. The upstream contribution
is one reusable plant-pot prototype, rather than an upstream whole-town run.
"""


def curate(run,inspection_config,media,output,stills_config=None):
    run=Path(run).resolve(strict=True);media=Path(media).resolve(strict=True)
    inspection_config=Path(inspection_config).resolve(strict=True)
    output=fresh_output(output,[run,media,inspection_config])
    scene=run/"scene";catalog=Catalog()
    generation=pass_receipt(run/"generation_run.json",("GENERATED_REQUIRES_REVIEW",))
    need(generation.get("baseline_unchanged") is True and generation.get("exit_code")==0,"Generation has no unchanged-baseline success receipt")
    plan=load(run/"territory_plan.json");manifest=pass_receipt(scene/"expansion_manifest.json",("BUILT",))
    need(plan.get("validation",{}).get("status")=="PASS","Territory validation failed")
    need(sha(run/"territory_plan.json")==generation["plan_sha256"]==manifest["plan"]["sha256"],"Plan bindings differ")
    baseline_native=BASELINE/"living_town_complete.blend"
    need(sha(baseline_native)==generation["baseline_sha256"]==manifest["baseline"]["sha256"],"Canonical native baseline differs")
    native=beneath(scene,manifest["native"]["path"])
    need(sha(native)==manifest["native"]["sha256"],"Expanded native SHA differs")
    offline=pass_receipt(run/"offline_review.json")
    native_review=pass_receipt(scene/"native_review.json")
    need(offline["native_sha256"]==native_review["native_sha256"]==sha(native),"Native review bindings differ")
    need(offline["plan_sha256"]==sha(run/"territory_plan.json"),"Offline review uses another plan")
    for path in (scene/"interior_preflight.json",scene/"actual_interior_audit.json"):
        pass_receipt(path)
    config=load(inspection_config)
    need(config.get("source_manifest_sha256")==sha(scene/"expansion_manifest.json"),"Inspection config uses another scene")
    consumer_path=Path(config["report"]).resolve(strict=True)
    need(consumer_path.is_relative_to(inspection_config.parent),"Consumer report escaped the inspection directory")
    consumer=pass_receipt(consumer_path)
    need(consumer.get("config_sha256")==sha(inspection_config),"Consumer used another inspection config")
    check_consumer_sources(consumer,"Movie consumer")
    need(consumer.get("movie_mode") is True and consumer.get("tour_frames")==6480,"Consumer has no complete six-minute route")
    need(all(c.get("passed") is True for c in consumer.get("checks",[])) and consumer.get("checks"),"Consumer checks did not all pass")
    verification=pass_receipt(media/"verification_report.json")
    composition=pass_receipt(media/"composition_report.json")
    voice=pass_receipt(media/"voice_report.json")
    for report in (verification,composition,voice):check_bindings(report)
    need(verification.get("checks") and all(c.get("passed") is True for c in verification["checks"]),"Media technical checks did not all pass")
    need(composition["config"]["sha256"]==sha(inspection_config) and composition["capture_report"]["sha256"]==sha(consumer_path),"Movie/config/consumer bindings differ")
    need(voice["config"]["sha256"]==sha(inspection_config),"Voice belongs to another configuration")
    need(verification["composition_report"]["sha256"]==sha(media/"composition_report.json") and composition["voice_report"]["sha256"]==sha(media/"voice_report.json"),"Media receipt chain differs")
    for label,name in (("output","expanded_town_architectural_tour.mp4"),("gif","expanded_town_tour.gif")):
        need(check_binding(verification[label])==(media/name),"Verified final media path differs: "+label)
    baseline_glb=BASELINE/"game_assets_reserve/living_town_game.glb"
    chunks=load(scene/"chunk_manifest.json")
    expected_assets={str(baseline_glb.resolve()):sha(baseline_glb)}
    for row in manifest["chunks"]:
        path=beneath(scene,row["path"]);expected_assets[str(path)]=row["sha256"]
        catalog.add(path,"generation/scene/"+row["path"],row["sha256"])
    actual_assets={str(Path(a["path"]).resolve(strict=True)):a["sha256"] for a in config["assets"]}
    need(actual_assets==expected_assets and len(config["assets"])==len(expected_assets),"Inspection asset identities differ from baseline and final chunks")
    for path,digest in expected_assets.items():need(sha(path)==digest,"Inspection source asset SHA differs")
    need({r["path"]:r["sha256"] for r in chunks["chunks"]}=={r["path"]:r["sha256"] for r in manifest["chunks"]},"Chunk manifests disagree")
    for name in ("territory_plan.json","territory_map.png","generation_run.json","offline_review.json"):
        catalog.add(run/name,"generation/"+name)
    for name in ("expansion_manifest.json","chunk_manifest.json","interiors.json","collision_proxies.json","interior_preflight.json","actual_interior_audit.json","native_review.json","plaster_weather_basecolor.png"):
        catalog.add(scene/name,"generation/scene/"+name)
    catalog.add(native,"generation/scene/"+manifest["native"]["path"],manifest["native"]["sha256"])
    for row in manifest["render_views"]:catalog.add(beneath(scene,row["path"]),"generation/scene/"+row["path"],row["sha256"])
    for folder in ("review","terrain_review","retaining_review_final"):
        review=scene/folder/"render_manifest.json"
        if review.is_file():
            rendered=load(review)
            need(rendered.get("native_sha256")==sha(native),"High-resolution review uses another native: "+folder)
            if "status" in rendered:need(rendered["status"] in ("PASS","RENDERED"),"High-resolution render receipt failed: "+folder)
            catalog.add(review,"generation/scene/"+folder+"/render_manifest.json")
            for row in rendered["views"]:
                catalog.add(beneath(review.parent,row["path"]),"generation/scene/"+folder+"/"+row["path"],row["sha256"])
    for name in ("terrain_review_cameras.json","retaining_review_final_cameras.json"):
        if (run/name).is_file():catalog.add(run/name,"generation/"+name)
    for name in ("visual_review.json","movie_visual_review.json"):
        if (run/name).is_file():
            reviewed=pass_receipt(run/name)
            need(reviewed.get("native_sha256")==manifest["native"]["sha256"],"Visual review uses another native: "+name)
            catalog.add(run/name,"generation/"+name)
    catalog.add(baseline_native,"art/living_town/living_town_complete.blend",manifest["baseline"]["sha256"])
    catalog.add(baseline_glb,"baseline/living_town_game.glb")
    for name in ("masterplan.json","landscape_plan.json","terrain_plan.json","reserve_plan.json","interior_plan.json","street_plan.json","presentation_camera_overrides.json"):
        catalog.add(BASELINE/name,"art/living_town/"+name)
    for relative,digest in plan["source_bindings"].items():
        catalog.add(beneath(BASELINE,relative),"art/living_town/"+relative,digest)
    for file in sorted((BASELINE/"tools").glob("*.py")):catalog.add(file,"art/living_town/tools/"+file.name)
    for file in sorted((REPO/"tools/town_generation").glob("*.py")):catalog.add(file,"tools/town_generation/"+file.name)
    for name in ("breton_summer.json","INFINIGEN_NOTICES.txt"):
        catalog.add(REPO/"tools/town_generation"/name,"tools/town_generation/"+name)
    for name in ("project.godot","Main.tscn","main.gd"):
        catalog.add(REPO/"tools/town_generation/godot_viewer"/name,"tools/town_generation/godot_viewer/"+name)
    for name in ("hero_scene.py","hero_furniture.py","hero_foliage.py","hero_pbr.py","hero_walls.py","hero_surfaces.py","materials.py","prepare_scans.py","component_licenses.json"):
        catalog.add(REPO/"tools/asset_refinement"/name,"tools/asset_refinement/"+name)
    catalog.add(REPO/"tools/build_town_walkthrough.py","tools/build_town_walkthrough.py")
    catalog.add(REPO/"LICENSE","LICENSE")
    for relative in ("external_assets/polyhaven/PROVENANCE.json","external_assets/fonts/PROVENANCE.json","external_assets/fonts/LICENSE.md"):
        file=BASELINE/relative
        if file.is_file():catalog.add(file,"art/living_town/"+relative)
    projection=REPO/"game/data/town3d/projection.json"
    if projection.is_file():catalog.add(projection,"game/data/town3d/projection.json")
    library_path=Path(manifest["materials"]["library_path"]).resolve(strict=True)
    need(library_path.is_relative_to(BASELINE),"Prepared PBR library is outside the curated canonical art directory")
    library=load(library_path);library_dest=library_path.relative_to(REPO).as_posix()
    catalog.add(library_path,library_dest,manifest["materials"]["library_sha256"])
    for material in library["materials"].values():
        need(material["license"]=="CC0-1.0","Unreviewed scan license")
        for raster in material["maps"].values():
            file=beneath(library_path.parent,raster["path"])
            catalog.add(file,file.relative_to(REPO).as_posix(),raster["sha256"])
        parent=beneath(library_path.parent,material["maps"]["basecolor"]["path"]).parent
        provenance=parent/"SOURCE_PROVENANCE.json"
        catalog.add(provenance,provenance.relative_to(REPO).as_posix(),material.get("source_provenance_sha256"))
    upstream=manifest.get("upstream_planter")
    need(upstream,"Expected the bounded upstream factory contribution")
    catalog.add(beneath(scene,upstream["license_notices"]),"generation/scene/"+upstream["license_notices"],upstream["license_notices_sha256"])
    prototype=Path(upstream["path"]).resolve(strict=True);worker_root=prototype.parent
    worker=pass_receipt(worker_root/"worker_result.json",("UPSTREAM_FACTORY_EXECUTED",))
    need(Path(worker["outputs"]["blend"]).resolve(strict=True)==prototype,"Worker prototype identity differs")
    catalog.add(prototype,"upstream/infinigen/courtyard_planter.blend",upstream["sha256"])
    for name in ("courtyard_planter.glb","worker_result.json","environment_audit.json","INFINIGEN_NOTICES.txt"):
        catalog.add(worker_root/name,"upstream/infinigen/"+name)
    for name in ("terracotta_basecolor.png","terracotta_normal.png","terracotta_orm.png","leaf_basecolor.png","leaf_normal.png","leaf_orm.png","soil_basecolor.png","soil_normal.png","soil_orm.png"):
        catalog.add(worker_root/"textures"/name,"upstream/infinigen/textures/"+name)
    if (worker_root/"courtyard_planter_preview.png").is_file():catalog.add(worker_root/"courtyard_planter_preview.png","upstream/infinigen/courtyard_planter_preview.png")
    catalog.add(inspection_config,"inspection/original_inspection.json")
    catalog.add(consumer_path,"inspection/consumer_report.json")
    capture_root=Path(config["capture_directory"]).resolve(strict=True)
    for row in consumer["captures"]:
        file=Path(row["path"]).resolve(strict=True)
        need(file.is_relative_to(capture_root),"Runtime capture escaped its declared directory")
        catalog.add(file,"inspection/captures/"+file.relative_to(capture_root).as_posix(),row["sha256"])
    if stills_config is not None:
        stills_config=Path(stills_config).resolve(strict=True);still_config=load(stills_config)
        need(still_config.get("source_manifest_sha256")==sha(scene/"expansion_manifest.json"),"Still inspection uses another native manifest")
        need(still_config["assets"]==config["assets"],"Still inspection uses different source assets")
        still_report_path=Path(still_config["report"]).resolve(strict=True)
        need(still_report_path.is_relative_to(stills_config.parent),"Still consumer report escaped inspection directory")
        still_report=pass_receipt(still_report_path)
        need(still_report.get("config_sha256")==sha(stills_config) and still_report.get("movie_mode") is False,"Still inspection binding or mode differs")
        check_consumer_sources(still_report,"Still consumer")
        need(len(still_report.get("captures",[]))==len(config["cameras"]) and all(c.get("passed") is True for c in still_report.get("checks",[])),"Still inspection lacks all accepted camera captures")
        catalog.add(stills_config,"inspection/still_inspection.json")
        catalog.add(still_report_path,"inspection/still_consumer_report.json")
        still_root=Path(still_config["capture_directory"]).resolve(strict=True)
        for row in still_report["captures"]:
            file=Path(row["path"]).resolve(strict=True)
            need(file.is_relative_to(still_root),"Still capture escaped declared directory")
            catalog.add(file,"inspection/still_captures/"+file.relative_to(still_root).as_posix(),row["sha256"])
    for name in ("media_context.json","narration_script.json","narration.wav","narration_normalized.wav","narration.ass","narration.srt","captions.json","voice_report.json","composition_report.json","verification_report.json","chapters.ffmetadata","composition_filters.txt","expanded_town_architectural_tour.mp4","expanded_town_tour.gif"):
        catalog.add(media/name,"media/"+name)
    packet_proof=composition.get("timeline",{}).get("theora_packet_proof")
    if packet_proof and packet_proof.get("table"):
        binding=packet_proof["table"];file=check_binding(binding,"Raw packet timing proof")
        need(file==media/"raw_video_packets.json","Unexpected raw packet proof filename")
        catalog.add(file,"media/raw_video_packets.json",binding["sha256"])
    for row in verification["qa_frames"]:
        binding=row["file"];file=Path(binding["path"]).resolve(strict=True)
        need(file.is_relative_to(media/"qa_frames"),"Media QA frame escaped its directory")
        catalog.add(file,"media/qa_frames/"+file.name,binding["sha256"])
    catalog.text("README.md",_readme(manifest,plan["seed"]))
    path_map={str(row["source"]):name for name,row in catalog.records.items() if "source" in row}
    metadata={"release_tag":"town-territory-2026-10-20","seed":plan["seed"],"building_count":manifest["building_count"],
              "historical_source_path_map":path_map,"historical_reports_unmodified":True,
              "review_gates":{"generation":generation["status"],"offline":offline["status"],"native":native_review["status"],"consumer":consumer["status"],"media":verification["status"]},
              "portable_inspection":"Run the README prepare_inspection command after extraction; historical absolute-path reports remain preserved evidence."}
    if stills_config is not None:metadata["review_gates"]["consumer_stills"]="PASS"
    return catalog,output,metadata


def package(*,run,inspection_config,media,output,stills_config=None):
    catalog,output,metadata=curate(run,inspection_config,media,output,stills_config)
    return write_archive(catalog,output,metadata)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run",required=True,type=Path)
    parser.add_argument("--inspection-config",required=True,type=Path)
    parser.add_argument("--stills-config",type=Path,help="Also curate the accepted separate still-camera import review")
    parser.add_argument("--media",required=True,type=Path)
    parser.add_argument("--output",required=True,type=Path)
    args=parser.parse_args()
    report=package(**vars(args))
    print(json.dumps({"status":report["status"],"archive":report["archive"]}))


if __name__=="__main__":main()
