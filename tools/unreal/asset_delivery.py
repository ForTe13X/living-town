"""Local-only café content closure. No engine, downloader, publisher or overwrite."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import unicodedata
import zipfile

SCHEMA = 'LivingTown.NativeCafeContentClosure.v1'
EXPECTED_ASSETS = 405
EXPECTED_ASSET_BYTES = 195738288
MAX_TOTAL = 256 * 1024 * 1024
MAX_FILES = 1024
BLOCK = 1024 * 1024
MANIFEST = 'MANIFEST.json'


def need(condition, message):
    if not condition:
        raise ValueError(message)


def read(path):
    return json.loads(Path(path).read_text('utf-8'))


def write(path, value):
    with Path(path).open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(value, stream, indent=2, ensure_ascii=False, allow_nan=False)
        stream.write('\n')


def safe_relative(value):
    need(isinstance(value, str) and value and len(value) <= 240, 'Invalid bounded member path')
    need(not any(c in value for c in '\\:\x00<>"|?*'), 'Windows/absolute/alternate-stream path refused')
    parsed = PurePosixPath(value)
    need(not parsed.is_absolute() and parsed.as_posix() == value, 'Noncanonical member path')
    reserved = {'con', 'prn', 'aux', 'nul'} | {f'{p}{i}' for p in ('com', 'lpt') for i in range(1, 10)}
    for part in parsed.parts:
        need(part not in ('.', '..') and not part.endswith((' ', '.')), 'Traversal or ambiguous component')
        need(part.split('.')[0].casefold() not in reserved, 'Windows device component refused')
    return value


def unique_paths(paths):
    folded = set()
    for value in paths:
        safe_relative(value)
        key = unicodedata.normalize('NFC', value).casefold()
        need(key not in folded, 'Duplicate/case/Unicode path collision: ' + value)
        folded.add(key)
    for value in folded:
        need(not any('/'.join(value.split('/')[:n]) in folded
                     for n in range(1, len(value.split('/')))), 'File/directory prefix collision')


def no_links(path):
    path = Path(path).absolute()
    for item in (path, *path.parents):
        if item.exists() or item.is_symlink():
            state = item.lstat()
            need(not stat.S_ISLNK(state.st_mode) and
                 not (getattr(state, 'st_file_attributes', 0) & 0x400),
                 'Symlink/junction/reparse point refused: ' + str(item))
    return path


def file_record(path):
    path = no_links(path)
    before = path.stat()
    need(stat.S_ISREG(before.st_mode), 'Only regular source files are allowed')
    need(before.st_size <= MAX_TOTAL, 'Bounded source file size exceeded')
    hasher = hashlib.sha256()
    consumed = 0
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(BLOCK), b''):
            consumed += len(block)
            need(consumed <= before.st_size, 'Source grew during bounded read')
            hasher.update(block)
    after = path.stat()
    need((before.st_size, before.st_mtime_ns) == (after.st_size, after.st_mtime_ns), 'Source changed while hashing')
    return {'path': str(path), 'bytes': after.st_size, 'sha256': hasher.hexdigest()}


def verify_record(row):
    current = file_record(row['path'])
    need(current['bytes'] == row['bytes'] and current['sha256'] == row['sha256'],
         'Bound input bytes changed: ' + row['path'])
    return current


def portable_runtime_json(value):
    if isinstance(value, dict):
        for child in value.values():
            portable_runtime_json(child)
    elif isinstance(value, list):
        for child in value:
            portable_runtime_json(child)
    elif isinstance(value, str):
        need(not re.match(r'^[A-Za-z]:[/\\]', value) and not value.startswith('\\\\'),
             'Absolute host file path in runtime JSON')


def matching_map_build(owner, native_record, native):
    """A qualified map capture must use the exact build advertised to consumers."""
    verify_record(native_record)
    bootstrap_record = verify_record(owner['bootstrap_report'])
    bootstrap = read(bootstrap_record['path'])
    observed = bootstrap['native_build']
    need(bootstrap['status'] == 'PASS_ACTUAL_NATIVE_MCP_DISCOVERY_IMPORT_PENDING',
         'Map bootstrap did not complete')
    need(observed['receipt']['sha256'] == native_record['sha256'] and
         observed['source_sha256'] == native['source']['sha256'],
         'Map capture and advertised native build differ')
    return bootstrap_record


def build_plan(inputs_path, setup_path, ownership_path):
    inputs = read(inputs_path)
    for row in inputs['bindings']:
        verify_record(row)
    receipt = read(inputs['binding_receipt']['path'])
    need(receipt['status'] == 'PASS_ROOT_REVIEWED_STATIC_INPUTS_FOR_OWNED_ACTUAL_JOURNEY_ONLY',
         'Unqualified runtime binding receipt')
    need(len(receipt['seed_files']) == EXPECTED_ASSETS and sum(r['bytes'] for r in receipt['seed_files']) == EXPECTED_ASSET_BYTES,
         'This café closure requires exact 405 assets /195738288 bytes')
    setup_path, ownership_path = Path(setup_path), Path(ownership_path)
    need(setup_path.parent.resolve() == ownership_path.parent.resolve(), 'Map receipts belong to different runs')
    setup, owner = read(setup_path), read(ownership_path)
    need(owner['status'] in (
        'PASS_PROVISIONAL_NATIVE_PLAYER_LIT_FRAME_WITH_ONE_MCP_NOTICE_PROVIDER_PENDING',
        'PASS_ACTUAL_SOFTWARE_LUMEN_RESOURCE_AND_NATIVE_PLAYER_FRAME_WITH_ONE_MCP_NOTICE_ART_PENDING'),
        'Map must have a completed technical native capture; failed runs are preserved, never packaged')
    need(owner['guards'] and all(row['pass'] for row in owner['guards'].values()), 'Map ownership guard failed')
    need(setup['status'] == 'PASS_NEW_LIGHTING_ONLY_MAP_SAVED', 'Map creation receipt missing')
    need(setup['world_settings_game_mode'] == '/Script/LivingTownNative.LivingTownCafeGameMode', 'Wrong per-map native GameMode')
    map_path = setup['map']
    need(re.fullmatch(r'/Game/LivingTown_UEPilot/Presentation/[A-Za-z0-9_]+', map_path), 'Invalid café map path')
    verify_record(setup['map_file'])
    shot_path = setup_path.parent / 'NATIVE_SPAWN_SHOT_RECEIPT.json'
    shot = read(shot_path)
    need(shot['status'] == 'PASS_PROVISIONAL_REAL_NATIVE_SPAWN_PNG_PROVIDER_PENDING', 'Actual native map frame missing')
    resources = setup_path.parent / 'ACTUAL_SOFTWARE_LUMEN_RESOURCE_READBACK.json'
    if owner['status'].startswith('PASS_ACTUAL_SOFTWARE_LUMEN'):
        need(read(resources)['qualified_software_GI_observation'], 'Lumen resource proof did not pass')
    entries = []
    def add(path, source, role):
        entries.append({'path': safe_relative(path), 'source': source, 'role': role})
    seed_root = Path(receipt['seed_source_content'])
    for row in receipt['seed_files']:
        relative = safe_relative(row['content_relative'])
        need(relative.startswith('LivingTown_UEPilot/') and relative.endswith('.uasset'), 'Unexpected source asset scope')
        source = {'path': str(seed_root / relative), 'bytes': row['bytes'], 'sha256': row['sha256']}
        verify_record(source)
        add('Content/' + relative, source, 'engine_asset')
    for name in ('binding', 'route'):
        source = receipt[name]
        verify_record(source)
        portable_runtime_json(read(source['path']))
        add('Content/LivingTown/' + Path(source['path']).name, source, name)
    add('Content/' + map_path[len('/Game/'):] + '.umap', setup['map_file'], 'map')
    for row in inputs['references']:
        verify_record(row['source'])
        add(row['path'], row['source'], row['role'])
    for name, path in (('MapSetup.json', setup_path), ('MapOwnership.json', ownership_path),
                       ('NativePlayerFrame.json', shot_path)):
        add('Provenance/' + name, file_record(path), 'provenance')
    if resources.is_file():
        add('Provenance/MapLumenResources.json', file_record(resources), 'provenance')
    native = read(inputs['native_build_receipt']['path'])
    need(native['status'] == 'PASS_NATIVE_EDITOR_BUILD', 'Native source/build is not qualified')
    bootstrap_record = matching_map_build(owner, inputs['native_build_receipt'], native)
    add('Provenance/MapNativeBootstrap.json', bootstrap_record, 'provenance')
    unique_paths([r['path'] for r in entries])
    selected = shot['before']['quality_CVars']
    keys = ('r.DynamicGlobalIlluminationMethod', 'r.ReflectionMethod', 'r.GenerateMeshDistanceFields',
            'r.RayTracing', 'r.Lumen.HardwareRayTracing', 'r.Lumen.TraceMeshSDFs')
    metadata = {
        'schema': SCHEMA, 'scope': 'NATIVE_CAFE_CONTENT_CLOSURE_ONLY_NOT_FULL_TOWN_OR_COOKED_GAME',
        'asset_count': EXPECTED_ASSETS, 'asset_bytes': EXPECTED_ASSET_BYTES,
        'map': map_path, 'game_mode': '/Script/LivingTownNative.LivingTownCafeGameMode',
        'map_qualification': owner['status'], 'art_final': False,
        'required_native_source_digest': native['source']['sha256'],
        'required_native_build_receipt_sha256': inputs['native_build_receipt']['sha256'],
        'required_engine_version': native['engine']['version'], 'required_engine_build_id': native['engine']['build_id'],
        'renderer_project_defaults': {k: selected[k] for k in keys if k in selected},
        'renderer_observed_not_a_performance_guarantee': selected,
        'runtime_path_policy': 'Content-relative and /Game references only; raw Pro-venance and editor import metadata can retain historical local paths.',
        'engine_and_native_code_binaries_in_this_archive': False,
        'source_and_build_supplied_separately': True,
        'normal_play': 'Select this map and native GameMode with matching supplied project/build; no MCP server startup is needed.'
    }
    portable_runtime_json(metadata)
    return {'status': 'CPU_VERIFIED_LOCAL_PLAN_NOT_A_RELEASE', 'metadata': metadata, 'entries': entries,
            'map_input_receipts': [file_record(setup_path), file_record(ownership_path), file_record(shot_path),
                                   bootstrap_record]}


def pack(plan_path, output):
    plan = read(plan_path)
    rows = plan['entries']
    unique_paths([r['path'] for r in rows])
    need(len(rows) < MAX_FILES and sum(r['source']['bytes'] for r in rows) <= MAX_TOTAL, 'Bounded closure exceeded')
    for row in rows:
        verify_record(row['source'])
    for row in plan['map_input_receipts']:
        verify_record(row)
    manifest = {**plan['metadata'], 'manifest_excludes_itself': True,
                'files': [{k: row[k] for k in ('path', 'role')} | {k: row['source'][k] for k in ('bytes', 'sha256')} for row in rows]}
    output = no_links(output)
    need(output.parent.is_dir(), 'Output parent must already exist')
    with zipfile.ZipFile(output, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=1, allowZip64=False) as archive:
        for row in sorted(rows, key=lambda r: r['path']):
            info = zipfile.ZipInfo(row['path'], (1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | 0o644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            hasher = hashlib.sha256()
            consumed = 0
            with Path(row['source']['path']).open('rb') as source, archive.open(info, 'w') as target:
                for block in iter(lambda: source.read(BLOCK), b''):
                    consumed += len(block)
                    need(consumed <= row['source']['bytes'], 'Source grew during bounded ZIP write')
                    target.write(block)
                    hasher.update(block)
            need(hasher.hexdigest() == row['source']['sha256'], 'Source changed during ZIP write')
        info = zipfile.ZipInfo(MANIFEST, (1980, 1, 1, 0, 0, 0))
        info.create_system = 3
        info.external_attr = (stat.S_IFREG | 0o644) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, json.dumps(manifest, indent=2, ensure_ascii=False, allow_nan=False).encode('utf-8'))
    result = verify_archive(output)
    for row in rows:
        verify_record(row['source'])
    return result


def verify_archive(path):
    no_links(path)
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        need(len(infos) <= MAX_FILES and sum(i.file_size for i in infos) <= MAX_TOTAL, 'ZIP limits exceeded')
        unique_paths([i.filename for i in infos])
        for info in infos:
            mode = (info.external_attr >> 16) & 0xffff
            need(not info.is_dir() and not (info.flag_bits & 1) and not(info.external_attr & 0x400) and stat.S_IFMT(mode) in (0, stat.S_IFREG),
                 'Directory/encrypted/symlink/special ZIP member refused')
        need(sum(i.filename == MANIFEST for i in infos) == 1 and archive.getinfo(MANIFEST).file_size <= 2 * BLOCK,
             'Exactly one bounded manifest required')
        manifest = json.loads(archive.read(MANIFEST).decode('utf-8'))
        need(manifest['schema'] == SCHEMA and manifest['asset_count'] == EXPECTED_ASSETS and manifest['asset_bytes'] == EXPECTED_ASSET_BYTES,
             'Wrong café closure schema/count')
        rows = manifest['files']
        unique_paths([r['path'] for r in rows])
        need({r['path'] for r in rows} | {MANIFEST} == {i.filename for i in infos}, 'Missing or extra ZIP member')
        assets = [r for r in rows if r['role'] == 'engine_asset']
        need(len(assets) == EXPECTED_ASSETS and sum(r['bytes'] for r in assets) == EXPECTED_ASSET_BYTES, 'Missing source assets or wrong byte total')
        need(sum(r['role'] == 'map' for r in rows) == 1, 'Exactly one qualified map is allowed')
        need(sum(r['role'] == 'binding' for r in rows) == 1 and sum(r['role'] == 'route' for r in rows) == 1, 'Binding/route closure missing')
        for row in rows:
            role, member = row['role'], row['path']
            if role == 'engine_asset':
                need(member.startswith('Content/LivingTown_UEPilot/') and member.endswith('.uasset'), 'Asset outside exact native scope')
            elif role == 'map':
                need(member == 'Content/' + manifest['map'][len('/Game/'):] + '.umap', 'Map path differs from selected map')
            elif role in ('binding', 'route'):
                need(member == 'Content/LivingTown/' + ('CafeProjectionBinding.json' if role == 'binding' else 'CafeJourneyRoute.json'), 'Runtime data path differs')
            else:
                roots = {'provenance': 'Provenance', 'license': 'Licenses', 'metadata': 'Metadata'}
                need(role in roots and PurePosixPath(member).parts[0] == roots[role] and PurePosixPath(member).suffix in ('.json', '.md', '.txt', '.html'), 'Non-content payload is not bounded documentation')
            need(PurePosixPath(row['path']).parts[0] in ('Content', 'Provenance', 'Licenses', 'Metadata'), 'Unexpected payload root')
            info = archive.getinfo(row['path'])
            need(info.file_size == row['bytes'], 'Member byte count differs')
            hasher = hashlib.sha256()
            with archive.open(info) as stream:
                for block in iter(lambda: stream.read(BLOCK), b''):
                    hasher.update(block)
            need(hasher.hexdigest() == row['sha256'], 'Member SHA256 differs: ' + row['path'])
            if row['role'] in ('binding', 'route'):
                portable_runtime_json(json.loads(archive.read(info).decode('utf-8')))
        portable_runtime_json({k: v for k, v in manifest.items() if k != 'files'})
    return {'status': 'PASS_CLOSED_ZIP_BYTES_ONLY_NOT_ENGINE_GAMEPLAY_OR_ART',
            'archive': file_record(path), 'manifest': manifest, 'members': len(infos)}


def install(path, destination):
    result = verify_archive(path)  # Validate every byte before any destination is created.
    destination = no_links(destination)
    need(destination.parent.is_dir() and not destination.exists(), 'Installation requires a fresh destination')
    destination.mkdir()  # Atomic reservation; never merges into another project.
    marker = destination / 'INSTALL_INCOMPLETE.json'
    write(marker, {'status': 'INCOMPLETE_DO_NOT_USE', 'source_archive_sha256': result['archive']['sha256']})
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        need({i.filename for i in infos} == {r['path'] for r in result['manifest']['files']} | {MANIFEST}, 'Archive member set changed before extraction')
        unique_paths([i.filename for i in infos])
        need(sum(i.file_size for i in infos) <= MAX_TOTAL, 'Archive size changed before extraction')
        for info in infos:
            target = destination.joinpath(*PurePosixPath(info.filename).parts)
            need(target.resolve().is_relative_to(destination.resolve()), 'Extraction escaped reserved root')
            no_links(target)
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info) as source, target.open('xb') as output:
                for block in iter(lambda: source.read(BLOCK), b''):
                    output.write(block)
    for row in result['manifest']['files']:
        current = file_record(destination / row['path'])
        need(current['bytes'] == row['bytes'] and current['sha256'] == row['sha256'], 'Installed file differs')
    need(file_record(path) == result['archive'], 'Archive changed during extraction')
    write(destination / 'INSTALL_RECEIPT.json', {'status': 'PASS_CONTENT_ONLY_FRESH_DIRECTORY',
          'archive': result['archive'], 'source_asset_count': EXPECTED_ASSETS, 'engine_launched': False,
          'existing_content_overwritten': False, 'native_project_and_engine_required_separately': True})
    marker.unlink()
    return {'status': 'PASS_CONTENT_ONLY_FRESH_DIRECTORY', 'destination': str(destination), 'engine_launched': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    plan = commands.add_parser('plan')
    for name in ('inputs', 'map-setup', 'map-ownership', 'output'):
        plan.add_argument('--' + name, type=Path, required=True)
    package = commands.add_parser('pack')
    package.add_argument('--plan', type=Path, required=True)
    package.add_argument('--output', type=Path, required=True)
    verify = commands.add_parser('verify')
    verify.add_argument('--archive', type=Path, required=True)
    restore = commands.add_parser('install-content')
    restore.add_argument('--archive', type=Path, required=True)
    restore.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    if args.command == 'plan':
        value = build_plan(args.inputs, args.map_setup, args.map_ownership)
        write(args.output, value)
        print(json.dumps({'status': value['status'], 'files': len(value['entries']), 'output': str(args.output)}))
    elif args.command == 'pack':
        value = pack(args.plan, args.output)
        print(json.dumps({k: v for k, v in value.items() if k != 'manifest'}))
    elif args.command == 'verify':
        value = verify_archive(args.archive)
        print(json.dumps({k: v for k, v in value.items() if k != 'manifest'}))
    else:
        print(json.dumps(install(args.archive, args.destination)))


if __name__ == '__main__':
    main()
