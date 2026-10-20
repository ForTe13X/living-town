"""Run a bounded, local full-precision Klein base 4B RGB material experiment.

The three Apache-2.0 components and MIT Vulkan runtime are pinned in the license
registry. This never downloads anything or claims to generate calibrated PBR.
Requires Windows and psutil for the shared-memory safety monitor. CPU is the
default. A recorded Vulkan interruption blocks retrying that cached GPU setup.
"""
import argparse
import hashlib
import json
import subprocess
import time
from pathlib import Path

MODELS = {
    "flux-2-klein-base-4b.safetensors": "9c5fed22b76baea749d88fc2abe3ad53245e7b21a0d353a762665eea00043b92",
    "qwen_3_4b.safetensors": "6c671498573ac2f7a5501502ccce8d2b08ea6ca2f661c458e708f36b36edfc5a",
    "flux2-vae.safetensors": "868fe7b343cc8f3a19dbcfcafbc3d5f888802be3f89bd81b65b3621a066ce8f3",
}
RUNTIME_ARCHIVE_SHA = "17398d07ba89c2fba21b8662db69ecdd917888373e4f82779b7599e97a6b4bd3"


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--prompt-file", type=Path, required=True)
    parser.add_argument("--reference", type=Path)
    parser.add_argument("--steps", type=int, default=20)
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--seconds", type=int, default=1800)
    parser.add_argument("--backend", choices=("cpu", "vulkan"), default="cpu")
    args = parser.parse_args(argv)
    cache, output = args.cache.resolve(), args.output.resolve()
    if args.backend == "vulkan" and (cache / "vulkan_interruption_receipt.json").exists():
        raise RuntimeError("This cached Vulkan configuration was interrupted by a host reboot; GPU retries are disabled")
    import psutil
    if output.exists():
        raise FileExistsError(output)
    prompt = args.prompt_file.read_text(encoding="utf-8-sig").strip()
    if not prompt or not 1 <= args.steps <= 100 or not 512 <= args.size <= 2048:
        raise ValueError("Invalid bounded experiment settings")
    hashes = {}
    for name, expected in MODELS.items():
        actual = sha(cache / name)
        if actual != expected:
            raise ValueError("Unverified model bytes: " + name)
        hashes[name] = actual
    archive = cache / "sd-master-95b3090-bin-win-vulkan-x64.zip"
    if sha(archive) != RUNTIME_ARCHIVE_SHA:
        raise ValueError("Unverified Vulkan runtime archive")
    runtime = cache / "sd_cpp_95b3090/sd-cli.exe"
    output.mkdir(parents=True, exist_ok=False)
    command = [str(runtime), "--diffusion-model", str(cache / next(iter(MODELS))),
               "--llm", str(cache / "qwen_3_4b.safetensors"), "--vae", str(cache / "flux2-vae.safetensors"),
               "--backend", "cpu" if args.backend == "cpu" else "diffusion=vulkan0,te=cpu,vae=cpu", "--params-backend", "cpu",
               "--flash-attn", "auto", "--batched-cfg", "off",
               "--sampling-method", "euler", "--cfg-scale", "4", "--steps", str(args.steps),
               "--width", str(args.size), "--height", str(args.size), "--seed", "20261020",
               "--rng", "cpu", "--threads", "6", "--prompt", prompt,
               "--output", str(output / "candidate.png"), "--metadata-format", "json", "-v"]
    if args.backend == "vulkan":
        command += ["--max-vram", "vulkan0=12"]
    reference = None
    if args.reference:
        reference = args.reference.resolve()
        command += ["--ref-image", str(reference)]
    before_available = psutil.virtual_memory().available
    if before_available < 24 * 1024**3:
        raise MemoryError("Experiment requires at least 24 GiB currently available RAM")
    started = time.monotonic()
    (output / "started.json").write_text(json.dumps({"status": "RUNNING", "command": command,
        "runner_sha256": sha(Path(__file__)), "model_sha256": hashes,
        "backend": args.backend, "quality_verified": False}, indent=2) + "\n", encoding="utf-8")
    minimum_available, peak_process = before_available, 0
    stopped = None
    with (output / "runtime.log").open("wb") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        monitor = psutil.Process(process.pid)
        while process.poll() is None:
            available = psutil.virtual_memory().available
            minimum_available = min(minimum_available, available)
            try:
                peak_process = max(peak_process, monitor.memory_info().rss)
            except psutil.NoSuchProcess:
                pass
            if available < 6 * 1024**3:
                stopped = "Shared system RAM below 6 GiB safety floor"
            if time.monotonic() - started > args.seconds:
                stopped = "Bounded experiment wall-clock limit reached"
            if stopped:
                process.terminate()
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    process.kill()
                break
            time.sleep(2)
        code = process.wait()
    candidate = output / "candidate.png"
    result = {"schema": "living_town.permissive_model_rgb_experiment.v1",
              "status": "GENERATED_REQUIRES_VISUAL_AND_SEAM_REVIEW" if code == 0 and candidate.exists() else "FAILED",
              "inference_executed": True, "model_precision": "Unquantized source BF16 weights; no --type override",
              "model_sha256": hashes, "runtime_archive_sha256": RUNTIME_ARCHIVE_SHA,
              "runtime_executable_sha256": sha(runtime), "runner_sha256": sha(Path(__file__)),
              "command": command, "prompt": prompt, "reference_sha256": sha(reference) if reference else None,
              "seconds": round(time.monotonic() - started, 2), "exit_code": code,
              "safety_stop": stopped, "minimum_system_available_bytes": minimum_available,
              "peak_process_rss_bytes": peak_process, "gpu_allocation_measured_separately": False,
              "candidate_sha256": sha(candidate) if candidate.exists() else None,
              "calibrated_pbr_generated": False, "seamless_verified": False, "quality_equivalence_verified": False,
              "scope": "Standalone RGB material candidate. Existing UltraTex 9B adapters were not used. Requires actual visual, repeat and PBR-coherence review before any asset promotion."}
    (output / "run_receipt.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if code == 0 and candidate.exists() else 1


if __name__ == "__main__":
    raise SystemExit(main())
