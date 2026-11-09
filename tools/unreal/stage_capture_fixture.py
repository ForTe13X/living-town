"""Verify the frozen capture fixture; optionally stage source to a fresh external root.

This helper never builds or launches Unreal and copies no installed engine files.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import stat
import sys

sys.dont_write_bytecode = True
FIXTURE_ID = 'continuous_capture_v003'
FAMILY = 'b1150cc9e6c1e7a9363c6052eab774e139fd59a03857fc47aa4866e35249f844'
PLUGIN = 'Plugins/LivingTownCapturePilot/'
MODULE = PLUGIN + 'Source/LivingTownCapturePilot/'
PATHS = (
    'CapturePilotHost.uproject',
    PLUGIN + 'LivingTownCapturePilot.uplugin',
    MODULE + 'LivingTownCapturePilot.Build.cs',
    MODULE + 'Private/LivingTownCapturePilotLibrary.cpp',
    MODULE + 'Private/LivingTownContinuousCapture.cpp',
    MODULE + 'Private/LivingTownDirectReadback.cpp',
    MODULE + 'Public/LivingTownCapturePilotLibrary.h',
    'Source/CapturePilotHost/CapturePilotHost.Build.cs',
    'Source/CapturePilotHost/Private/CapturePilotHost.cpp',
    'Source/CapturePilotHostEditor.Target.cs',
)
REPOSITORY = Path(__file__).absolute().parents[2]
FIXTURE = Path(__file__).absolute().parent / 'fixtures' / FIXTURE_ID


def need(condition, message):
    if not condition:
        raise ValueError(message)


def plain(path, directory=False):
    info = path.lstat()
    need(not stat.S_ISLNK(info.st_mode) and
         not getattr(info, 'st_file_attributes', 0) & 0x400,
         'Symlink or reparse point refused: ' + str(path))
    need(stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode),
         'Expected plain directory' if directory else 'Expected regular file')
    return info


def existing_ancestors(path):
    for parent in reversed(path.parents):
        plain(parent, directory=True)


def read_exact(path, size):
    before = plain(path)
    need(before.st_size == size, 'Source size changed: ' + str(path))
    data = path.read_bytes()
    after = plain(path)
    need((before.st_size, before.st_mtime_ns, before.st_ino) ==
         (after.st_size, after.st_mtime_ns, after.st_ino),
         'Source changed while reading: ' + str(path))
    need(len(data) == size, 'Source read size changed: ' + str(path))
    return data


def source_inventory(host):
    plain(host, directory=True)
    directories = {str(parent) for name in PATHS
                   for parent in PurePosixPath(name).parents if str(parent) != '.'}
    found = set()
    pending = [host]
    while pending:
        for path in pending.pop().iterdir():
            relative = path.relative_to(host).as_posix()
            info = path.lstat()
            if stat.S_ISDIR(info.st_mode):
                plain(path, directory=True)
                need(relative in directories, 'Extra source directory: ' + relative)
                pending.append(path)
            else:
                plain(path)
                need(relative in PATHS, 'Extra source file: ' + relative)
                found.add(relative)
    need(found == set(PATHS), 'Missing source files')


def verify_fixture(fixture=FIXTURE):
    """Return verified raw payloads; no writes, imports from the fixture or apps."""
    fixture = Path(fixture).absolute()
    existing_ancestors(fixture)
    plain(fixture, directory=True)
    manifest_path = fixture / 'SOURCE_MANIFEST.json'
    size = plain(manifest_path).st_size
    need(size <= 32768, 'Manifest exceeds the fixed fixture bound')
    manifest = json.loads(read_exact(manifest_path, size))
    need(manifest.get('schema') == 'living_town.capture_fixture_source_manifest.v1'
         and manifest.get('fixture_id') == FIXTURE_ID
         and manifest.get('source_root') == 'HostProject'
         and manifest.get('source_family_sha256') == FAMILY
         and manifest.get('source_file_count') == 10
         and manifest.get('source_total_bytes') == 84826,
         'Frozen fixture identity changed')
    rows = manifest.get('files')
    need(isinstance(rows, list) and len(rows) == len(PATHS), 'Ten source rows required')
    need(all(isinstance(row, dict) and set(row) == {'file', 'bytes', 'sha256'}
             for row in rows), 'Source row shape changed')
    need(tuple(row['file'] for row in rows) == PATHS,
         'Exact independent ten-path allowlist required')
    digest = hashlib.sha256(json.dumps(rows, sort_keys=True,
                                      separators=(',', ':')).encode()).hexdigest()
    need(digest == FAMILY, 'Frozen source family changed')
    host = fixture / 'HostProject'
    source_inventory(host)
    payloads = []
    for row in rows:
        data = read_exact(host / row['file'], row['bytes'])
        need(hashlib.sha256(data).hexdigest() == row['sha256'],
             'Source SHA-256 changed: ' + row['file'])
        payloads.append((row['file'], data))
    return payloads


def fresh_external_root(value):
    root = Path(value)
    need(root.is_absolute() and '..' not in root.parts,
         'Artifact root must be absolute without traversal')
    need(not str(root.anchor).startswith(('\\\\', '//')),
         'Artifact root must be on a local filesystem')
    need(not any(':' in part for part in root.parts[1:]), 'Alternate streams refused')
    try:
        root.lstat()
    except FileNotFoundError:
        pass
    else:
        raise ValueError('Existing artifact root refused before writes')
    existing_ancestors(root)
    need(not root.is_relative_to(REPOSITORY), 'Artifact root is inside repository')
    for parent in root.parents:
        need(not (parent / '.git').exists(), 'Artifact root is inside a Git workspace')
        need(not (parent / 'Engine/Build/Build.version').is_file(),
             'Artifact root is inside an installed engine')
    return root


def stage_source(payloads, root):
    """Create only a new root/project source tree; never overwrite or clean up."""
    root = fresh_external_root(root)
    root.mkdir()
    project = root / 'project'
    project.mkdir()
    for relative, data in payloads:
        destination = project / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        existing_ancestors(destination)
        with destination.open('xb') as stream:
            stream.write(data)
        need(read_exact(destination, len(data)) == data, 'Staged source differs')
    source_inventory(project)
    need(list(root.iterdir()) == [project], 'Extra staged output')
    return project


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixture', choices=[FIXTURE_ID], default=FIXTURE_ID)
    parser.add_argument('--stage-source', action='store_true')
    parser.add_argument('--artifact-root', type=Path)
    args = parser.parse_args(argv)
    try:
        need(args.stage_source == (args.artifact_root is not None),
             '--stage-source and --artifact-root must be supplied together')
        root = fresh_external_root(args.artifact_root) if args.stage_source else None
        payloads = verify_fixture()
        project = stage_source(payloads, root) if root is not None else None
        print(json.dumps({'status': 'STAGED_SOURCE_ONLY' if project else 'VERIFIED_SOURCE_ONLY',
                          'fixture': FIXTURE_ID, 'source_file_count': len(payloads),
                          'source_family_sha256': FAMILY,
                          'staged_project': str(project) if project else None,
                          'compiler_or_native_launch': False}))
        return 0
    except (ValueError, OSError, TypeError, KeyError) as error:
        print(json.dumps({'status': 'REFUSED', 'error': str(error)}), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
