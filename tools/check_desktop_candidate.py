"""Run the exported executable from a clean install directory and fresh app data."""
import argparse
import json
import os
import re
import shutil
import stat
import subprocess
from pathlib import Path
try:
    from .stage_desktop_logic import digest, verify
except ImportError:
    from stage_desktop_logic import digest, verify


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    args = parser.parse_args()
    stage = args.stage.resolve()
    verify(stage)
    build = json.loads((stage / 'export_receipt.json').read_text(encoding='utf-8'))
    if build.get('export_result') != 'PASS':
        raise ValueError('Export has no passing receipt')
    if build['staging_manifest_sha256'] != digest((stage / 'manifest.json').read_bytes()):
        raise ValueError('Export and staging manifest differ')
    install = stage / 'checked-install'
    install.mkdir()
    for name, sha in build['artifacts'].items():
        if digest((stage / name).read_bytes()) != sha:
            raise ValueError('Export artifact changed: ' + name)
        shutil.copyfile(stage / name, install / name)
    cases = [('startup', ['--quit-after', '60'], ''),
             ('journey', ['--', '--desktop-check', 'journey'], '=== PLAYER JOURNEY: PASS (0 failures) ==='),
             ('save-resume', ['--', '--desktop-check', 'save-resume'], 'save_resume_test: PASS (0 fail)'),
             ('resume-write', ['--', '--desktop-check', 'resume-write'], 'desktop_resume_test: PASS (0 fail) mode=resume-write'),
             ('resume-read', ['--', '--desktop-check', 'resume-read'], 'desktop_resume_test: PASS (0 fail) mode=resume-read'),
             ('save-denied', ['--', '--desktop-check', 'save-denied'], 'desktop_resume_test: PASS (0 fail) mode=save-denied'),
             ('resume-recover', ['--', '--desktop-check', 'resume-read'], 'desktop_resume_test: PASS (0 fail) mode=resume-read')]
    receipt = {'schema': 'living-town.desktop-runtime/1', 'artifacts': build['artifacts'],
               'source_clean': build['source_clean'], 'acceptance': 'unaccepted_candidate',
               'host_os_input_covered': False, 'rendered': False, 'cases': [],
               'expected_cases': [case[0] for case in cases], 'runtime_result': 'INCOMPLETE'}
    (stage / 'runtime_receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    for name, tail, marker in cases:
        user = stage / ('checked-user-' + ('process-resume' if name.startswith('resume-') or name == 'save-denied' else name))
        if name not in {'resume-read', 'resume-recover', 'save-denied'}:
            user.mkdir()
        elif not user.is_dir():
            raise ValueError('Prior resume process did not create its user directory')
        env = {k: v for k, v in os.environ.items() if 'API_KEY' not in k.upper()}
        env.update(APPDATA=str(user), LOCALAPPDATA=str(user))
        log = stage / ('checked-' + name + '.log')
        command = [str(install / 'LivingTown.exe'), '--headless', '--log-file', str(log), *tail]
        denied_path = None
        denied_before = None
        if name == 'save-denied':
            saves = list(user.rglob('quicksave.dat'))
            if len(saves) != 1:
                raise ValueError('Expected exactly one prior save for denied-write check')
            denied_path = saves[0]
            denied_before = digest(denied_path.read_bytes())
            denied_path.chmod(stat.S_IREAD)
        try:
            run = subprocess.run(command, cwd=install, env=env, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, timeout=240,
                                 creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        finally:
            if denied_path is not None:
                denied_path.chmod(stat.S_IREAD | stat.S_IWRITE)
        (stage / ('checked-' + name + '.stdout.log')).write_bytes(run.stdout)
        text = log.read_text(encoding='utf-8') if log.exists() else ''
        errors = [s for s in text.splitlines() if re.search(r'(?:SCRIPT ERROR|ERROR):|^\s*FAIL\b', s)]
        routed = [json.loads(s.removeprefix('DESKTOP_CHECK ')) for s in text.splitlines() if s.startswith('DESKTOP_CHECK ')]
        route_ok = not marker or (len(routed) == 1 and Path(routed[0]['user_dir']).is_relative_to(user)
                                  and routed[0]['embedded_model_available'] is False)
        denied_ok = denied_path is None or digest(denied_path.read_bytes()) == denied_before
        passed = run.returncode == 0 and not errors and (not marker or marker in text) and route_ok and denied_ok
        receipt['cases'].append({'case': name, 'command': command, 'exit_code': run.returncode,
                                 'pass': passed, 'errors': errors, 'log_sha256': digest(log.read_bytes()),
                                 'warnings': [s for s in text.splitlines() if 'WARNING:' in s],
                                 'runtime_identity': routed,
                                 'denied_write': {'method': 'Windows read-only file attribute', 'prior_sha256': denied_before,
                                                  'bytes_preserved': denied_ok} if denied_path else None,
                                 'user_files': [p.relative_to(user).as_posix() for p in user.rglob('*') if p.is_file()]})
        receipt['runtime_result'] = 'INCOMPLETE' if all(r['pass'] for r in receipt['cases']) else 'FAIL'
        (stage / 'runtime_receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
        print(name, 'PASS' if passed else 'FAIL', flush=True)
        if not passed:
            raise ValueError('Packaged ' + name + ' check failed; inspect ' + str(log))
    for name, sha in build['artifacts'].items():
        if digest((install / name).read_bytes()) != sha:
            receipt['runtime_result'] = 'FAIL'
            (stage / 'runtime_receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
            raise ValueError('Installed artifact changed: ' + name)
    receipt['runtime_result'] = 'PASS'
    (stage / 'runtime_receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
