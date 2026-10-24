"""Shared, engine-free contracts for v1/v2 playable town assets and evidence."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path, PurePosixPath

STAGE = "game/assets/town3d/stage_manifest.json"
CHARACTERS = "game/data/town3d/characters.json"
RELEASE = "game/assets/town3d/release_manifest.json"
STATIC_CACHE = "game/assets/town3d/static_render_cache.json"
STATIC_CACHE_RESOURCE = "game/assets/town3d/static_render_cache.res"
PROFILE = "game/data/town3d/profile.json"
PROJECTION = "game/data/town3d/projection.json"
UPGRADE_LOGICAL = "game/data/town3d/upgrade_runtime_report.json"
UPGRADE_CAPTURE = "docs/town_walkthrough/final/walkthrough_report.json"
UPGRADE_REVIEW = "docs/town_walkthrough/final/visual_review.json"


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def sha(path):
    digest=hashlib.sha256()
    with Path(path).open("rb") as source:
        for block in iter(lambda:source.read(1024*1024),b""):digest.update(block)
    return digest.hexdigest()


def safe_relative(name):
    p=PurePosixPath(name)
    if not name or p.is_absolute() or ".." in p.parts or any(":" in v or "\\" in v for v in p.parts):
        raise ValueError("Unsafe runtime-relative path: "+str(name))
    return p.as_posix()


def model_relative(uri):
    if not isinstance(uri,str) or not uri.startswith("res://assets/characters3d/"):
        raise ValueError("Character model must be inside res://assets/characters3d")
    return "game/"+safe_relative(uri.removeprefix("res://"))


def is_v2(root):
    return read(Path(root)/STAGE).get("schema")=="living_town.game_stage.v2"


def runtime_records(root, allow_observed_character_hashes=False):
    """Expected records from authored stage/config; no network or mutation."""
    root=Path(root);stage=read(root/STAGE)
    if stage.get("status")!="PASS":raise ValueError("Runtime stage is not passing")
    result={}
    for item in stage.get("files",[]):
        rel="game/assets/town3d/"+safe_relative(item["file"])
        if rel in result:raise ValueError("Duplicate staged file: "+rel)
        result[rel]={"path":rel,"bytes":int(item["bytes"]),"sha256":str(item["sha256"])}
    for rel in (STAGE,):result[rel]={"path":rel,"bytes":(root/rel).stat().st_size,"sha256":sha(root/rel)}
    if stage.get("schema")=="living_town.game_stage.v2":
        data=read(root/CHARACTERS);entries=data.get("characters",{})
        if len(entries)<25 or "player" not in entries:raise ValueError("Upgraded runtime requires all24personas plus player")
        result[CHARACTERS]={"path":CHARACTERS,"bytes":(root/CHARACTERS).stat().st_size,"sha256":sha(root/CHARACTERS)}
        for entry in entries.values():
            rel=model_relative(entry["model"]);path=root/rel
            digest=entry.get("model_sha256");size=entry.get("model_bytes")
            if (not digest or size is None) and allow_observed_character_hashes and path.is_file():
                digest=sha(path);size=path.stat().st_size
            if not digest or size is None:raise ValueError("Character config needs model_sha256/model_bytes: "+rel)
            record={"path":rel,"bytes":int(size),"sha256":str(digest)}
            if rel in result and result[rel]!=record:raise ValueError("Conflicting character source identity: "+rel)
            result[rel]=record
    # The small manifest travels in Git; the exact engine-specific binary is a
    # required release/offline-source member whenever that manifest is present.
    # Historical v2 stages without this optional acceleration remain supported.
    if stage.get("schema")=="living_town.game_stage.v2" and (root/STATIC_CACHE).is_file():
        cache=read(root/STATIC_CACHE)
        proof=cache.get("full_build_validation",{})
        if cache.get("schema")!="living_town.static_render_cache.v1" or cache.get("status")!="PASS_FULL_BUILDER_CODEC_VALIDATION_AND_RESOURCE_READBACK" or cache.get("resource_file")!="static_render_cache.res":
            raise ValueError("Unsupported static render cache manifest")
        digest=cache.get("resource_sha256","");size=cache.get("resource_bytes")
        if not isinstance(digest,str) or len(digest)!=64 or any(c not in "0123456789abcdef" for c in digest) or type(size) is not int or size<=0:
            raise ValueError("Static render cache resource identity is invalid")
        if not isinstance(proof,dict) or any(proof.get(k) is not True for k in ("ok","original_mesh_buffers_unchanged","batch_buffers_unchanged","semantic_ray_registry_unchanged")):
            raise ValueError("Static render cache producer proof is incomplete")
        result[STATIC_CACHE]={"path":STATIC_CACHE,"bytes":(root/STATIC_CACHE).stat().st_size,"sha256":sha(root/STATIC_CACHE)}
        result[STATIC_CACHE_RESOURCE]={"path":STATIC_CACHE_RESOURCE,"bytes":size,"sha256":digest}
    elif (root/STATIC_CACHE_RESOURCE).exists():
        raise ValueError("Static render cache resource lacks its required manifest")
    if len({name.casefold() for name in result})!=len(result):raise ValueError("Runtime paths collide on Windows")
    return result


def verify_runtime(root, records=None):
    root=Path(root);records=runtime_records(root) if records is None else records
    for rel,item in records.items():
        path=root/safe_relative(rel)
        if not path.resolve().is_relative_to(root.resolve()) or not path.is_file() or path.is_symlink() or path.stat().st_size!=item["bytes"] or sha(path)!=item["sha256"]:
            raise ValueError("Runtime file missing or changed: "+rel)
    return records


def release_document(root, base_url=None):
    records=verify_runtime(root,runtime_records(root,allow_observed_character_hashes=True))
    files=[]
    for rel,record in sorted(records.items()):
        item=dict(record)
        # Release assets use stable unique flattened names, including characters.
        item["asset_name"]=rel.replace("/","__")
        item["url"]=base_url.rstrip("/")+"/"+item["asset_name"] if base_url else None
        files.append(item)
    return {"schema":"living_town.runtime_release.v2","status":"URLS_CONFIGURED_PUBLICATION_UNVERIFIED" if base_url else "LOCAL_VERIFIED_URLS_PENDING",
        "stage_manifest_sha256":sha(Path(root)/STAGE),"characters_manifest_sha256":sha(Path(root)/CHARACTERS),
        "source_asset_set_sha256":read(Path(root)/STAGE).get("source_asset_set_sha256"),"files":files,
        "local_policy":"Matching installed bytes require no network. Missing bytes require --local-source or explicitly published URLs."}


def read_release(root,path=None):
    root=Path(root);data=read(path or root/RELEASE)
    if data.get("schema")!="living_town.runtime_release.v2":raise ValueError("Unsupported upgraded asset release manifest")
    if data.get("stage_manifest_sha256")!=sha(root/STAGE) or data.get("characters_manifest_sha256")!=sha(root/CHARACTERS):
        raise ValueError("Release manifest belongs to another staged town or character set")
    records={}
    for item in data.get("files",[]):
        rel=safe_relative(item["path"])
        if rel in records:raise ValueError("Duplicate release path: "+rel)
        records[rel]=item
    expected=runtime_records(root,allow_observed_character_hashes=False)
    if set(records)!=set(expected):raise ValueError("Release manifest omits or adds runtime files")
    for rel,item in expected.items():
        if any(records[rel].get(k)!=item[k] for k in ("bytes","sha256")):raise ValueError("Release source binding differs: "+rel)
    return data,records


def validate_upgrade_evidence(root, hashes, require_visual=True):
    """A v2 package must bind fresh logical AND actual Main/LifeMode evidence."""
    root=Path(root);stage=read(root/STAGE);profile=read(root/PROFILE)
    records=verify_runtime(root)
    for rel,item in records.items():
        if hashes.get(rel)!=item["sha256"]:raise ValueError("Package omits or changes runtime file: "+rel)
    for name,digest in profile["file_hashes"].items():
        rel="game/data/town3d/"+safe_relative(name)
        if hashes.get(rel)!=digest:raise ValueError("Packaged authored topology changed: "+rel)
    if hashes.get(PROJECTION)!=profile.get("projection_sha256") or profile.get("source_asset_set_sha256")!=stage.get("source_asset_set_sha256"):
        raise ValueError("Packaged gameplay profile differs from exact visual asset set")
    for rel,digest in profile.get("presentation_source_hashes",{}).items():
        if hashes.get(safe_relative(rel))!=digest:raise ValueError("Presentation source changed after profile freeze: "+rel)
    logical=read(root/UPGRADE_LOGICAL)
    if logical.get("status")!="PASS" or logical.get("failures",logical.get("failure_count",0))!=0 or not logical.get("checks") or not all(c.get("passed") is True for c in logical["checks"]):
        raise ValueError("Upgraded logical gameplay gate is not passing")
    if logical.get("source_asset_set_sha256")!=stage.get("source_asset_set_sha256") or logical.get("projection_sha256")!=hashes.get(PROJECTION) or logical.get("profile_sha256")!=hashes.get(PROFILE):
        raise ValueError("Upgraded logical report is stale")
    visual=read(root/UPGRADE_CAPTURE) if require_visual else {}
    if require_visual:
        if visual.get("status")!="PASS" or visual.get("failure_count")!=0 or visual.get("direct_agent_writes") is not False or not visual.get("route_complete") or visual.get("preview") is not False:
            raise ValueError("Require a completed actual upgraded Main/LifeMode walkthrough")
        if visual.get("fps")!=18 or visual.get("tour_frames_elapsed")!=15120 or not visual.get("checks") or not all(c.get("passed") is True for c in visual["checks"]):
            raise ValueError("Upgraded walkthrough is incomplete or contains failed input/actions")
        for field,rel in (("projection_sha256",PROJECTION),("profile_sha256",PROFILE),("stage_manifest_sha256",STAGE),("characters_manifest_sha256",CHARACTERS),("harness_sha256","game/scripts/town_walkthrough.gd")):
            if visual.get(field)!=hashes.get(rel):raise ValueError("Upgraded walkthrough is stale: "+field)
        if visual.get("source_glb_sha256")!=stage.get("source_asset_set_sha256"):raise ValueError("Upgraded walkthrough binds another visual chunk set")
        review=read(root/UPGRADE_REVIEW)
        if review.get("status")!="PASS" or review.get("walkthrough_report_sha256")!=hashes.get(UPGRADE_CAPTURE) or review.get("stage_manifest_sha256")!=hashes.get(STAGE) or review.get("characters_manifest_sha256")!=hashes.get(CHARACTERS):
            raise ValueError("Actual upgraded gameplay image review is missing or stale")
    captures=[]
    for c in visual.get("captures",[]):
        rel="docs/town_bridge/captures/"+Path(c["file"]).name
        if hashes.get(rel)!=c["sha256"]:raise ValueError("Packaged actual gameplay screenshot differs: "+rel)
        captures.append({"package_file":rel,"sha256":c["sha256"],"tick":c.get("tick"),"chapter":c.get("chapter")})
    return {"source_blend_sha256":stage["source_blend_sha256"],"source_glb_sha256":stage["source_asset_set_sha256"],
        "source_asset_set_sha256":stage["source_asset_set_sha256"],"profile_sha256":hashes[PROFILE],"projection_sha256":hashes[PROJECTION],
        "characters_manifest_sha256":hashes[CHARACTERS],"runtime_file_count":len(records),"town_chunk_count":len(stage.get("assets",[])),
        "building_count":stage.get("building_count"),"logical_check_count":len(logical["checks"]),"visual_check_count":len(visual.get("checks",[])),
        "captures":captures,"native_boot_report_included":False,"packaging_does_not_rerun_game":True}
