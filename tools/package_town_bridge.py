"""Inventory or publish the playable bridge's portable Godot SOURCE package.

Default is inventory only. --publish is deliberately explicit and must be used
only after the coordinator freezes the integrated game and grants the I/O slot.
No Godot, Blender, export, original art delivery, or game source is modified.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import struct
import time
import uuid
import zipfile

CHUNK = 1024 * 1024
TOP = "LivingTown_Interactive_Source"
TOOLS = ("tools/fetch_town_assets.py", "tools/run-town3d.ps1", "tools/prepare-godot-optional.ps1",
         "tools/build_town_profile.py", "tools/stage_town_assets.py",
         "tools/package_town_bridge.py")
EXTRA = ("LICENSE", "THIRD_PARTY_NOTICES.md", "docs/09-美术资产与版权.md",
         "docs/town_walkthrough/ASSET_RELEASE.md",
         "art/living_town/external_assets/fonts/LICENSE.md",
         "art/living_town/external_assets/fonts/PROVENANCE.json")
SKIP_DIRS = {".godot", ".git", "models", "android", "__pycache__"}
SKIP_SUFFIXES = {".log", ".uid", ".import", ".tmp", ".staging", ".pyc"}
BUILD_REL = Path("build/town_bridge/source_package")


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha_stream(stream):
    digest = hashlib.sha256()
    for block in iter(lambda: stream.read(CHUNK), b""):
        digest.update(block)
    return digest.hexdigest()


def sha(path):
    with path.open("rb") as stream:
        return sha_stream(stream)


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def contained(path, parent):
    resolved = path.resolve()
    if not resolved.is_relative_to(parent.resolve()):
        raise ValueError(f"Path escapes intended directory: {path}")
    return resolved


def safe_relative(name):
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or any(":" in x or "\\" in x for x in path.parts):
        raise ValueError("Unsafe package-relative path: " + name)
    return path


def choose_files(root):
    files = {}
    excluded = {}
    visual_report = root/'docs/town_bridge/visual_test_report.json'
    current_captures = {Path(c['file']).name for c in read(visual_report).get('screenshots',[])} if visual_report.exists() else set()
    native_report = root/'docs/town_bridge/windows_export_verification.json'
    if native_report.exists():
        current_captures.update(Path(c['file']).name for c in read(native_report).get('screenshots',[]))
    for folder in ("game", "docs/town_bridge"):
        for current, dirs, names in os.walk(root / folder, followlinks=False):
            current_path = Path(current)
            keep = []
            for name in sorted(dirs):
                p = current_path / name
                rel = p.relative_to(root).as_posix()
                if name in SKIP_DIRS or rel == "game/addons/nobodywho":
                    excluded[rel + "/"] = "generated cache/toolchain, models, or omitted optional native addon"
                else:
                    if p.is_symlink():
                        raise ValueError("Source directory symlink is not portable: " + rel)
                    contained(p, root)
                    keep.append(name)
            dirs[:] = keep
            for name in sorted(names):
                p = current_path / name; rel = p.relative_to(root).as_posix()
                reason = None
                if p.suffix.lower() in SKIP_SUFFIXES or name == ".gdignore":
                    reason = "generated import/cache/local marker"
                elif rel.startswith("game/assets/town3d/living_town_game_") and p.suffix.lower() == ".png":
                    reason = "Godot-extracted duplicate of an image embedded in the GLB"
                elif rel.startswith('docs/town_bridge/') and p.suffix.lower() == '.png' and not (
                        rel.startswith('docs/town_bridge/captures/') and name in current_captures):
                    reason = 'diagnostic or historical image not referenced by the current gameplay visual report'
                if reason:
                    excluded[rel] = reason; continue
                if p.is_symlink() or not p.is_file():
                    raise ValueError("Source file is not a regular portable file: " + rel)
                contained(p,root); safe_relative(rel); files[rel] = p
    for rel in TOOLS + EXTRA:
        p = contained(root / rel, root)
        if not p.is_file():
            raise ValueError("Required package source missing: " + rel)
        files[rel] = p
    return dict(sorted(files.items())), excluded


def glb_embedded(path):
    with path.open("rb") as stream:
        magic, version, total = struct.unpack("<4sII", stream.read(12))
        length, kind = struct.unpack("<II", stream.read(8))
        if magic != b"glTF" or version != 2 or total != path.stat().st_size or kind != 0x4E4F534A:
            raise ValueError("Runtime asset is not a valid GLB2")
        document = json.loads(stream.read(length))
    external = [x['uri'] for field in ('images','buffers') for x in document.get(field,[]) if 'uri' in x]
    if external:
        raise ValueError("Runtime GLB has unpackaged external dependencies: " + str(external))
    return len(document.get('images',[]))


def validate_sources(root, hashes):
    """Bind already-produced proof to included bytes; never re-run the engine."""
    def match(rel,expected):
        if not expected or hashes.get(rel) != expected:
            raise ValueError("Current packaged bytes do not match validated evidence: " + rel)
    profile_path = 'game/data/town3d/profile.json'
    projection_path = 'game/data/town3d/projection.json'
    profile = read(root/profile_path)
    for name,digest in profile['file_hashes'].items():
        safe_relative(name)
        match('game/data/town3d/'+name,digest)
    match(projection_path,profile['projection_sha256'])
    stage = read(root/'game/assets/town3d/stage_manifest.json')
    if stage.get('status') != 'PASS':
        raise ValueError('Runtime staging did not pass')
    for record in stage['files']:
        safe_relative(record['file']); match('game/assets/town3d/'+record['file'],record['sha256'])
    glb_sha=hashes['game/assets/town3d/living_town_game.glb']
    if glb_sha != stage['source_glb_sha256']:
        raise ValueError('Staged GLB is stale')
    logical=read(root/'docs/town_bridge/logical_test_report.json')
    visual=read(root/'docs/town_bridge/visual_test_report.json')
    for name,report in (('logical',logical),('visual',visual)):
        if report.get('status') != 'PASS' or report.get('failure_count') != 0 or not report.get('checks') or not all(c.get('passed') for c in report.get('checks',[])):
            raise ValueError(name+' gameplay evidence is not passing')
        if report.get('source_blend_sha256') != stage['source_blend_sha256']:
            raise ValueError(name+' report describes another native source')
        if report.get('projection_sha256') != hashes[projection_path]:
            raise ValueError(name+' report describes another spatial profile')
    if logical.get('profile_sha256') != hashes[profile_path] or visual.get('source_glb_sha256') != glb_sha:
        raise ValueError('Gameplay reports are stale relative to profile/model bytes')
    captures=[]
    for capture in visual.get('screenshots',[]):
        # Original absolute capture paths remain evidence provenance. The
        # generated portable index provides local archive paths without altering
        # the test report or requiring the author's machine directory to exist.
        filename=Path(capture['file']).name
        safe_relative(filename)
        rel='docs/town_bridge/captures/'+filename
        match(rel,capture['sha256'])
        captures.append({'original_file':capture['file'],'package_file':rel,'sha256':capture['sha256'],
                         'space':capture.get('space'),'floor':capture.get('floor'),'tick':capture.get('tick')})
    native_path=root/'docs/town_bridge/windows_export_verification.json'
    native=None
    if native_path.exists():
        native=read(native_path)
        if native.get('status') != 'PASS' or native.get('profile_sha256') != hashes[profile_path] or native.get('source_glb_sha256') != glb_sha:
            raise ValueError('Native export evidence is failing or belongs to another source profile')
        for capture in native.get('screenshots',[]):
            rel=capture['file']; safe_relative(rel); match(rel,capture['sha256'])
            captures.append({'package_file':rel,'sha256':capture['sha256'],'scope':'Normal exported product entry; GPU boot proof'})
    return {'source_blend_sha256':stage['source_blend_sha256'],'source_glb_sha256':glb_sha,
            'profile_sha256':hashes[profile_path],'projection_sha256':hashes[projection_path],
            'logical_check_count':len(logical['checks']),'visual_check_count':len(visual['checks']),
            'captures':captures,'native_boot_report_included':native is not None}


def readme():
    return """# Living Town: interactive 3D source package

This is the existing Living Town simulation, LifeMode UI and characters bridged
to the completed town model. The supplied spatial profile is already compiled.
No Blender, Python, model download or original art archive is needed to play.

1. Extract this ZIP completely.
2. Install Godot 4.6.2 for Windows, or use an existing compatible Godot 4.6 engine.
3. In PowerShell at this folder, run:

```powershell
./tools/run-town3d.ps1 -EnginePath 'C:/path/to/Godot.exe'
# Optional: skip resident selection
./tools/run-town3d.ps1 -EnginePath 'C:/path/to/Godot.exe' --life-as ben
```

The launcher imports clean assets first, then launches the real game. First
import takes longer and creates local Godot caches and extracted texture images.
Choose a resident; WASD/arrows or a ground click walks, E opens nearby actions,
and F5/F8 save/load. The existing touch controls and dialogue remain available.
`-Legacy` runs the original 2D layout. 3D and legacy saves use separate files.
See [the bridge guide](docs/town_bridge/README.md) and the included current
logical/visual reports and captures for behavior and limitations.

The source package requires a Godot editor executable; it is not an exported
Windows executable. Models/GGUF weights and optional NobodyWho native binaries
are omitted. The existing logic backend plays offline. A separately installed
complete NobodyWho addon remains supported by the game's backend and launcher.

The town GLB embeds its images. Import caches, extracted image duplicates and
local settings are omitted. No .blend files, reference movies or earlier art ZIP
are included. Nothing depends on the author's absolute filesystem paths.

## Editing and rebuilding

Open game/project.godot in Godot to edit the included game/scripts and data.
The included compiler/staging scripts document the build, but rebuilding the
profile or re-staging the model requires the separate full art/living_town source
delivery in its original repository layout. This source package does not contain
that art-generation dependency tree; do not run those scripts just to play.

PACKAGE_FILES.json binds every payload file except its own self-hash. Archive
CRC, extracted file hashes and the manifest hash are recorded in an external
publication report, which is intentionally outside the ZIP. PORTABLE_EVIDENCE_INDEX.json
maps capture provenance paths to files in this package. No engine re-test is
implied by the packaging check; gameplay evidence is included separately.

See [LICENSE](LICENSE), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and
[ASSET_CREDITS.md](ASSET_CREDITS.md) for asset and font notices.
""".encode('utf-8')


def credits():
    return """# Packaged asset credits

Game code: MIT, Copyright (c) 2026 Yang Peng; full text in LICENSE.

Original characters and pixel assets: Puny Characters / PunyWorld by Shade,
16x16 Food / Emotes by admurin, CC0. Original pack notices are retained below
game/assets/art/library. The project's edited character sheets and authored
pixel art remain included. See docs/09-美术资产与版权.md for the original asset
provenance narrative; its historical documentation links refer to the full repo.

UI font: Smiley Sans, atelierAnchor, SIL OFL 1.1. Unmodified font and full license
are included together in game/assets/fonts. THIRD_PARTY_NOTICES.md records its
provenance and reserved names.

Town: authored procedural geometry and textures from the completed Living Town
delivery. Its optimized GLB embeds all runtime images and text-shaped meshes.
Adobe Source Serif 4 was used for the modeled signage; its original OFL notice
and provenance are included under art/living_town/external_assets/fonts.
The original font binary, HDRI, reference movies and native Blender sources are
not needed for this runtime package and are not included.

Godot is installed separately for this source package; no engine binary is
redistributed here. NobodyWho native libraries and model weights are optional
separate installations and are not included.
""".encode('utf-8')


def archive_info(name):
    safe_relative(name)
    item=zipfile.ZipInfo(TOP+'/'+name,date_time=(2026,1,1,0,0,0))
    item.compress_type=zipfile.ZIP_DEFLATED
    item.external_attr=(0o100644 << 16)
    item.create_system=3
    return item


def publish(root,files,excluded,freeze_id):
    build=contained(root/BUILD_REL,root/'build/town_bridge')
    build.mkdir(parents=True,exist_ok=True)
    archive=build/(TOP+'.zip');temporary=build/(TOP+'.zip.partial')
    if temporary.exists():
        raise ValueError('A prior unfinished archive exists; inspect it before retrying: '+str(temporary))
    hashes={rel:sha(p) for rel,p in files.items()}
    proof=validate_sources(root,hashes)
    embedded=glb_embedded(files['game/assets/town3d/living_town_game.glb'])
    generated={'README.md':readme(),'ASSET_CREDITS.md':credits(),
               'PORTABLE_EVIDENCE_INDEX.json':encoded(proof)}
    payload=[{'path':rel,'bytes':p.stat().st_size,'sha256':hashes[rel]} for rel,p in files.items()]
    payload += [{'path':rel,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()} for rel,data in generated.items()]
    payload.sort(key=lambda x:x['path'])
    manifest={'schema':'living_town.bridge_source_package.v1','freeze_id':freeze_id,
              'package_kind':'Godot source; engine installed separately',
              'root_folder':TOP,'payload_count':len(payload),'payload_bytes':sum(x['bytes'] for x in payload),
              'files':payload,'manifest_self_hash':'Recorded externally to avoid a circular self-hash.',
              'runtime_proof':proof,'embedded_glb_image_count':embedded,
              'excluded_categories':['Godot/import caches','models/GGUF','optional NobodyWho native addon',
                    'generated extracted GLB PNG duplicates','logs','UID/import sidecars','native Blender/reference sources'],
              'rebuild_source_included':False}
    generated['PACKAGE_FILES.json']=encoded(manifest)
    started=time.monotonic()
    with zipfile.ZipFile(temporary,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6,allowZip64=True) as z:
        for rel in sorted(set(files)|set(generated)):
            with z.open(archive_info(rel),'w',force_zip64=True) as dest:
                if rel in generated:
                    dest.write(generated[rel])
                else:
                    with files[rel].open('rb') as incoming:
                        for block in iter(lambda:incoming.read(CHUNK),b''):
                            dest.write(block)
    with temporary.open('rb+') as stream:
        stream.flush();os.fsync(stream.fileno())
    # A new bounded verification directory is retained as evidence. There is no
    # recursive delete/move or computed destination outside this ignored build.
    extract=contained(build/('verify_'+uuid.uuid4().hex[:12]),build)
    extract.mkdir()
    expected={TOP+'/'+entry['path']:entry for entry in payload}
    manifest_bytes=generated['PACKAGE_FILES.json']
    expected[TOP+'/PACKAGE_FILES.json']={'path':'PACKAGE_FILES.json','bytes':len(manifest_bytes),
        'sha256':hashlib.sha256(manifest_bytes).hexdigest()}
    with zipfile.ZipFile(temporary) as z:
        infos=z.infolist()
        if len(infos)!=len(expected) or {i.filename for i in infos}!=set(expected):
            raise ValueError('ZIP contains missing, duplicate or unexpected entries')
        for item in infos:
            safe_relative(item.filename)
            destination=contained(extract/Path(*PurePosixPath(item.filename).parts),extract)
            destination.parent.mkdir(parents=True,exist_ok=True)
            # Fully consuming each ZipExtFile checks its CRC. Stream both the
            # compressed-entry and extracted-file hashes, never whole-archive RAM.
            digest=hashlib.sha256();size=0
            with z.open(item) as incoming,destination.open('xb') as outgoing:
                for block in iter(lambda:incoming.read(CHUNK),b''):
                    outgoing.write(block);digest.update(block);size+=len(block)
            record=expected[item.filename]
            if size!=record['bytes'] or digest.hexdigest()!=record['sha256'] or sha(destination)!=record['sha256']:
                raise ValueError('ZIP/extracted file hash mismatch: '+item.filename)
    extracted_root=extract/TOP
    extracted_hashes={entry['path']:entry['sha256'] for entry in payload}
    validate_sources(extracted_root,extracted_hashes)
    if glb_embedded(extracted_root/'game/assets/town3d/living_town_game.glb')!=embedded:
        raise ValueError('Extracted model dependency inventory changed')
    # Atomic publication occurs only after exact-list/CRC/hash/extracted static
    # validation succeeds. A prior published archive is untouched on failure.
    os.replace(temporary,archive)
    report={'schema':'living_town.bridge_source_package_verification.v1','status':'PASS',
        'freeze_id':freeze_id,'archive':str(archive),'archive_sha256':sha(archive),
        'archive_bytes':archive.stat().st_size,'payload_count':len(payload),'zip_entry_count':len(expected),
        'payload_bytes':manifest['payload_bytes'],'manifest_sha256':expected[TOP+'/PACKAGE_FILES.json']['sha256'],
        'extracted_directory':str(extracted_root),'checks':{
            'exact_entry_list':True,'all_entry_crcs':True,'all_zip_entry_sha256':True,
            'all_extracted_file_sha256':True,'extracted_runtime_profile_and_asset_bindings':True,
            'embedded_glb_has_no_external_images_or_buffers':True,
            'gameplay_reports_bound_to_packaged_profile_and_model':True},
        'runtime_proof':proof,'excluded_file_count':len(excluded),'elapsed_seconds':round(time.monotonic()-started,3),
        'engine_retest_in_extracted_copy':'Not performed by this packaging script; included current runtime reports are source evidence.',
        'report_location':'External; intentionally excluded from the ZIP to avoid circular archive identity.'}
    report_path=build/'package_verification.json';report_path.write_bytes(encoded(report))
    print(json.dumps(report,ensure_ascii=False))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
    parser.add_argument('--publish',action='store_true',help='Create ZIP only after coordinator freeze and I/O authorization')
    parser.add_argument('--freeze-id',help='Required publication label supplied by the coordinator after the final freeze')
    args=parser.parse_args();root=args.root.resolve()
    files,excluded=choose_files(root)
    if args.publish:
        if not args.freeze_id:
            parser.error('--publish requires --freeze-id from the final coordinator freeze')
        publish(root,files,excluded,args.freeze_id)
    else:
        sizes=sorted(((p.stat().st_size,rel) for rel,p in files.items()),reverse=True)
        print(json.dumps({'status':'INVENTORY_ONLY','file_count':len(files),
            'uncompressed_bytes':sum(n for n,_ in sizes),'largest_files':sizes[:10],
            'excluded_file_count':len(excluded),'archive_created':False,
            'publish_output_directory':str(root/BUILD_REL),
            'required_at_freeze':['Current PASS logical/visual reports matching profile/model',
                'All stage/profile SHA bindings and capture PNG checksums',
                'Coordinator freeze-id and permission for ZIP I/O']},ensure_ascii=False))


if __name__=='__main__':
    main()
