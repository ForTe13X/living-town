"""Stage a hashed desktop logic candidate without changing the source project."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OMIT = ('.godot/', 'addons/godot_mcp/', 'addons/nobodywho/', 'models/', 'android/',
        'addons/worldgen/templates/')  # standalone consumer templates are not game scenes
PRESET = '''[preset.0]
name="Windows Desktop Logic"
platform="Windows Desktop"
runnable=true
advanced_options=false
dedicated_server=false
custom_features="desktop_logic"
export_filter="all_resources"
include_filter="*.json,*.csv,*.txt"
exclude_filter=""
export_path="../LivingTown.exe"
script_export_mode=2

[preset.0.options]
custom_template/debug=""
custom_template/release=""
binary_format/embed_pck=true
binary_format/architecture="x86_64"
application/modify_resources=false
codesign/enable=false
debug/export_console_wrapper=1
'''


def digest(data):
    return hashlib.sha256(data).hexdigest()


def project_config(text):
    lines, section = [], ''
    for line in text.splitlines():
        if line.startswith('['):
            section = line.strip('[]')
        if section in {'editor_plugins', 'godot_mcp_pro'}:
            continue
        if section == 'autoload' and line.startswith(('MCPScreenshot=', 'MCPInputService=', 'MCPGameInspector=')):
            if 'res://addons/godot_mcp/' not in line:
                raise ValueError('MCP autoload name points to an unexpected script')
            continue
        lines.append(line)
    return '\n'.join(lines) + '\n'


def input_files(game):
    return sorted(p for p in game.rglob('*') if p.is_file()
                  and not any(p.relative_to(game).as_posix().startswith(x) for x in OMIT)
                  and not any(part.startswith('.') for part in p.relative_to(game).parts)
                  and p.name != 'export_presets.cfg' and p.suffix != '.import')


def verify(stage):
    manifest = json.loads((stage / 'manifest.json').read_text(encoding='utf-8'))
    game = stage / 'game'
    expected = manifest['staged_sha256']
    errors = []
    for rel, sha in expected.items():
        p = game / rel
        if not p.is_file():
            errors.append('missing: ' + rel)
        elif digest(p.read_bytes()) != sha:
            errors.append('changed: ' + rel)
    extras = [p.relative_to(game).as_posix() for p in game.rglob('*') if p.is_file()
              and '.godot' not in p.relative_to(game).parts and p.suffix not in {'.uid', '.import'}
              and p.relative_to(game).as_posix() not in expected]
    errors.extend('unexpected: ' + rel for rel in extras)
    if errors:
        raise ValueError('\n'.join(errors))
    return manifest


def prepare(stage, allow_dirty=False):
    stage = stage.resolve()
    game = ROOT / 'game'
    if stage.exists() or stage == ROOT or ROOT in stage.parents or stage in ROOT.parents:
        raise ValueError('Use a new staging directory outside the source checkout')
    status = subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).decode('utf-8')
    paths = input_files(game)
    tracked = set(subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode('utf-8').split('\0'))
    untracked_inputs = [p.relative_to(ROOT).as_posix() for p in paths if p.relative_to(ROOT).as_posix() not in tracked]
    source_clean = not status and not untracked_inputs
    if not source_clean and not allow_dirty:
        raise ValueError('Source is dirty; use --allow-dirty-candidate only for an unaccepted candidate')
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT).decode().strip()
    source, staged = {}, {}
    for p in paths:
        rel = p.relative_to(game).as_posix()
        data = p.read_bytes()
        source[rel] = digest(data)
        if rel == 'project.godot':
            data = project_config(data.decode('utf-8')).encode('utf-8')
        target = stage / 'game' / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        staged[rel] = digest(data)
    preset = stage / 'game/export_presets.cfg'
    preset.write_text(PRESET, encoding='utf-8')
    staged['export_presets.cfg'] = digest(preset.read_bytes())
    after = {p.relative_to(game).as_posix(): digest(p.read_bytes()) for p in input_files(game)}
    if source != after:
        raise ValueError('Source changed while staging; discard this incomplete stage')
    head_after = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT).decode().strip()
    status_after = subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).decode('utf-8')
    if head_after != head or status_after != status:
        raise ValueError('Git identity changed while staging; discard this incomplete stage')
    manifest = {'schema': 'living-town.desktop-stage/1', 'git_head': head,
                'source_clean': source_clean, 'untracked_runtime_inputs': untracked_inputs,
                'acceptance': 'unaccepted_candidate',
                'platform': 'Windows x86_64', 'backend_scope': 'logic, no bundled model',
                'source_root': str(ROOT), 'omitted_prefixes': list(OMIT),
                'transformations': ['remove editor plugins and MCP autoloads', 'desktop export preset'],
                'source_sha256': source, 'staged_sha256': staged}
    (stage / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    verify(stage)
    return manifest


def export(stage, godot):
    manifest = verify(stage)
    version = subprocess.check_output([str(godot), '--version']).decode().strip()
    if not version.startswith('4.6.2.stable.'):
        raise ValueError('Expected Godot 4.6.2.stable, got ' + version)
    receipt = {'engine': version, 'engine_sha256': digest(godot.read_bytes()),
               'staging_manifest_sha256': digest((stage / 'manifest.json').read_bytes()),
               'source_clean': manifest['source_clean'], 'acceptance': 'unaccepted_candidate',
               'steps': []}
    for name, args in [('import', ['--editor', '--import']),
                       ('export', ['--export-release', 'Windows Desktop Logic', str(stage / 'LivingTown.exe')])]:
        command = [str(godot), '--headless', '--path', str(stage / 'game'), *args]
        run = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
        (stage / (name + '.log')).write_bytes(run.stdout)
        text = run.stdout.decode('utf-8', errors='replace')
        errors = [line for line in text.splitlines() if re.search(r'(?:SCRIPT ERROR|ERROR|WARNING):', line)]
        receipt['steps'].append({'step': name, 'command': command, 'exit_code': run.returncode,
                                 'log_sha256': digest(run.stdout), 'errors': errors})
        (stage / 'export_receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
        if run.returncode or errors:
            raise ValueError(name + ' failed; see ' + str(stage / (name + '.log')))
    verify(stage)
    receipt['artifacts'] = {'LivingTown.exe': digest((stage / 'LivingTown.exe').read_bytes())}
    receipt['export_result'] = 'PASS'
    (stage / 'export_receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'verify', 'export'])
    parser.add_argument('stage', type=Path)
    parser.add_argument('--allow-dirty-candidate', action='store_true')
    parser.add_argument('--godot', type=Path)
    args = parser.parse_args()
    if args.action == 'export':
        if args.godot is None:
            parser.error('--godot is required for export')
        result = export(args.stage.resolve(), args.godot.resolve())
    else:
        result = prepare(args.stage, args.allow_dirty_candidate) if args.action == 'prepare' else verify(args.stage)
    print(json.dumps({'result': 'PASS', 'files': len(result['staged_sha256']),
                      'source_clean': result['source_clean'], 'acceptance': result['acceptance']}))


if __name__ == '__main__':
    main()
