"""Run the isolated reserve consumer serially, only when the coordinator grants a slot.

No asset copying: GLTFDocument reads the completed portable package in place.
This script's creation does not execute Godot. Every engine invocation is explicit.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

PROJECT = Path(__file__).resolve().parent
BAD_OUTPUT = ('SCRIPT ERROR', 'Parse Error', 'FATAL', 'signal 11', 'out of bounds', 'Leaked instance', 'ObjectDB instances leaked')


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024*1024), b''):
            h.update(chunk)
    return h.hexdigest()


def record(path):
    return {'path': str(path), 'bytes': path.stat().st_size, 'sha256': sha(path)}


def flush_file(path):
    with path.open('rb+') as handle:
        os.fsync(handle.fileno())


def run_stage(name, command, evidence, timeout):
    stdout = evidence/(name+'.stdout.log')
    stderr = evidence/(name+'.stderr.log')
    began = time.monotonic()
    with stdout.open('wb') as out, stderr.open('wb') as err:
        result = subprocess.run(command, cwd=PROJECT, stdout=out, stderr=err, timeout=timeout,
                                creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        out.flush();os.fsync(out.fileno());err.flush();os.fsync(err.fileno())
    combined = stdout.read_text(encoding='utf-8', errors='replace')+'\n'+stderr.read_text(encoding='utf-8', errors='replace')
    issues = [text for text in BAD_OUTPUT if text.lower() in combined.lower()]
    stage = {'name': name, 'command': command, 'exit_code': result.returncode,
             'elapsed_seconds': round(time.monotonic()-began, 3), 'stdout': record(stdout),
             'stderr': record(stderr), 'fatal_or_script_messages': issues}
    if result.returncode != 0 or issues:
        raise RuntimeError(json.dumps(stage))
    return stage


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--assets', type=Path, required=True)
    parser.add_argument('--native-manifest', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, default=PROJECT/'evidence')
    parser.add_argument('--capture', action='store_true', help='After logical checks, run a separate real-renderer process and four PNGs')
    parser.add_argument('--timeout', type=int, default=1800)
    opt = parser.parse_args()
    for attr in ('godot', 'assets', 'native_manifest', 'evidence'):
        setattr(opt, attr, getattr(opt, attr).resolve())
    for path in (opt.godot, opt.assets/'export_manifest.json', opt.native_manifest):
        if not path.is_file():
            raise FileNotFoundError(path)
    opt.evidence.mkdir(parents=True, exist_ok=True)
    output = {'schema': 'living_town.reserve_consumer_runner.v1', 'status': 'RUNNING',
              'started_utc': datetime.now(timezone.utc).isoformat(),
              'consumer': record(PROJECT/'smoke.gd'), 'project': record(PROJECT/'project.godot'),
              'export_manifest': record(opt.assets/'export_manifest.json'), 'native_manifest': record(opt.native_manifest),
              'stages': [], 'execution_policy': 'Serial processes; worker_pool/max_threads=6; imports single-threaded; max-fps30; no asset copies'}
    runner_path = opt.evidence/'runner_report.json'

    def write_report():
        with runner_path.open('w', encoding='utf-8', newline='\n') as handle:
            json.dump(output, handle, indent=2);handle.write('\n');handle.flush();os.fsync(handle.fileno())

    write_report()
    common = [str(opt.godot), '--path', str(PROJECT), '--audio-driver', 'Dummy', '--max-fps', '30']
    args = ['--asset-dir='+str(opt.assets), '--native-manifest='+str(opt.native_manifest)]
    try:
        output['stages'].append(run_stage('parser', common+['--headless', '--check-only', '-s', 'res://smoke.gd'], opt.evidence, opt.timeout))
        write_report()
        logical_path = opt.evidence/'logical_report.json'
        if logical_path.exists():
            logical_path.rename(opt.evidence/('logical_report_previous_'+str(time.time_ns())+'.json'))
        output['stages'].append(run_stage('logical', common+['--headless', '--', *args, '--report='+str(logical_path)], opt.evidence, opt.timeout))
        logical = json.loads(logical_path.read_text(encoding='utf-8'))
        if logical.get('status') != 'PASS' or logical.get('failure_count') != 0 or not logical.get('checks'):
            raise RuntimeError('Fresh logical report failed')
        flush_file(logical_path)
        output['logical_report'] = record(logical_path)
        write_report()
        if opt.capture:
            gpu_path = opt.evidence/'render_report.json'
            if gpu_path.exists():
                gpu_path.rename(opt.evidence/('render_report_previous_'+str(time.time_ns())+'.json'))
            shots = opt.evidence/'captures'
            shots.mkdir(exist_ok=True)
            output['stages'].append(run_stage('render', common+['--rendering-method', 'gl_compatibility', '--resolution', '1440x1000',
                                                               '--', *args, '--report='+str(gpu_path), '--capture='+str(shots)], opt.evidence, opt.timeout))
            gpu = json.loads(gpu_path.read_text(encoding='utf-8'))
            if gpu.get('status') != 'PASS' or gpu.get('failure_count') != 0 or len(gpu.get('images', [])) != 4:
                raise RuntimeError('Fresh renderer report failed')
            flush_file(gpu_path)
            for image in gpu['images']:
                path = Path(image['path'])
                if record(path)['sha256'] != image['sha256']:
                    raise RuntimeError('Screenshot hash changed: '+str(path))
                flush_file(path)
            output['render_report'] = record(gpu_path)
            output['actual_image_review'] = 'PENDING: inspect all four actual PNGs separately'
        output['status'] = 'PASS'
    except Exception as exc:
        output['status'] = 'FAIL'
        output['error'] = str(exc)
        raise
    finally:
        output['finished_utc'] = datetime.now(timezone.utc).isoformat()
        write_report()
    print(json.dumps({'status': output['status'], 'report': str(runner_path)}, indent=2))


if __name__ == '__main__':
    main()
