#!/usr/bin/env python3
"""Fetch the pinned public town GLB without Git LFS or Python dependencies.

Only a fully size/hash-verified temporary file is installed. Existing matching
files are left untouched; replacing a mismatched file requires an explicit flag.
The repository stage manifest remains the verification authority even when the
destination or download URL is overridden.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import http.client
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request


REPOSITORY = "ForTe13X/living-town"
RELEASE_TAG = "town3d-walkthrough-2026-10-12"
ASSET_NAME = "living_town_game.glb"
EXPECTED_BYTES = 203_666_604
EXPECTED_SHA256 = "b90b37e40f6f38e61b095a45671fed40008e9423dfef52ef7db74cb34cb0c00c"
RELEASE_URL = f"https://github.com/{REPOSITORY}/releases/download/{RELEASE_TAG}/{ASSET_NAME}"
CHUNK_BYTES = 1024 * 1024
ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "game" / "assets" / "town3d" / "stage_manifest.json"


class FetchError(RuntimeError):
    """An actionable, credential-free retrieval error."""


class NetworkError(FetchError):
    pass


class IntegrityError(FetchError):
    pass


@dataclass(frozen=True)
class ExpectedAsset:
    name: str
    size: int
    sha256: str


def expected_asset(manifest_path: Path = MANIFEST_PATH) -> ExpectedAsset:
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        matches = [item for item in manifest["files"] if item.get("file") == ASSET_NAME]
        if len(matches) != 1:
            raise ValueError("Expected one town GLB entry")
        item = matches[0]
        result = ExpectedAsset(ASSET_NAME, int(item["bytes"]), str(item["sha256"]).lower())
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as exc:
        raise FetchError("Cannot read the repository town stage manifest; restore game/assets/town3d/stage_manifest.json.") from exc
    pinned = ExpectedAsset(ASSET_NAME, EXPECTED_BYTES, EXPECTED_SHA256)
    if result != pinned or manifest.get("source_glb_sha256") != EXPECTED_SHA256:
        raise IntegrityError("The stage manifest does not match this pinned release. Update the source package and downloader together.")
    return result


def file_matches(path: Path, expected: ExpectedAsset) -> bool:
    if not path.is_file() or path.stat().st_size != expected.size:
        return False
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(CHUNK_BYTES), b""):
            digest.update(chunk)
    return digest.hexdigest() == expected.sha256


def verify_file(path: Path, expected: ExpectedAsset) -> None:
    if not file_matches(path, expected):
        raise IntegrityError(f"Downloaded {expected.name} failed its required byte count or SHA256; no asset was installed.")


def validate_url(url: str) -> None:
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise FetchError("The asset URL must use HTTP or HTTPS.")
    if parsed.username is not None or parsed.password is not None:
        raise FetchError("Credential-bearing asset URLs are not supported. This release is public.")


def download_urllib(url: str, temporary: Path, expected: ExpectedAsset) -> None:
    validate_url(url)
    request = urllib.request.Request(url, headers={"User-Agent": "living-town-public-asset-fetch/1.0", "Accept": "application/octet-stream"})
    try:
        response = urllib.request.urlopen(request, timeout=60)
    except urllib.error.HTTPError as exc:
        raise NetworkError(f"Public release download returned HTTP {exc.code}.") from exc
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise NetworkError("Public release download could not connect. Check the network/proxy or use the GitHub CLI fallback.") from exc
    digest = hashlib.sha256()
    received = 0
    next_progress = 16 * CHUNK_BYTES
    with response, temporary.open("wb") as output:
        length = response.headers.get("Content-Length")
        if length is not None:
            try:
                declared = int(length)
            except ValueError as exc:
                raise IntegrityError("The download returned an invalid Content-Length.") from exc
            if declared != expected.size:
                raise IntegrityError(f"Download advertised {declared} bytes; expected {expected.size}. No asset was installed.")
        while True:
            try:
                chunk = response.read(CHUNK_BYTES)
            except (urllib.error.URLError, http.client.HTTPException, TimeoutError, OSError) as exc:
                raise NetworkError("The public release download was interrupted; the existing asset was preserved.") from exc
            if not chunk:
                break
            received += len(chunk)
            if received > expected.size:
                raise IntegrityError("Download exceeded the pinned asset size; no asset was installed.")
            output.write(chunk)
            digest.update(chunk)
            if received >= next_progress:
                print(f"Downloaded {received:,} / {expected.size:,} bytes", file=sys.stderr)
                next_progress += 16 * CHUNK_BYTES
        output.flush()
        os.fsync(output.fileno())
    if received != expected.size or digest.hexdigest() != expected.sha256:
        raise IntegrityError(f"Downloaded {expected.name} failed its required byte count or SHA256; no asset was installed.")


def download_gh(temporary: Path, expected: ExpectedAsset) -> None:
    executable = shutil.which("gh")
    if executable is None:
        raise NetworkError("GitHub CLI fallback is unavailable. Install gh, fix the network/proxy, or download the release asset manually.")
    print("Trying GitHub CLI for the same public release asset...", file=sys.stderr)
    # Capture, never forward CLI diagnostics: local gh debug/auth settings must not
    # leak headers or credentials into this tool's output. No token is requested.
    try:
        completed = subprocess.run(
            [executable, "release", "download", RELEASE_TAG, "--repo", REPOSITORY,
             "--pattern", ASSET_NAME, "--output", str(temporary), "--clobber"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=600, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise NetworkError("GitHub CLI could not complete the public asset download.") from exc
    if completed.returncode != 0:
        raise NetworkError(f"GitHub CLI download failed (exit {completed.returncode}). Check that the tagged public release exists and is reachable.")
    verify_file(temporary, expected)
    with temporary.open("rb+") as handle:
        os.fsync(handle.fileno())


def install_verified(temporary: Path, target: Path, expected: ExpectedAsset, replace_mismatched: bool) -> None:
    # Recheck at the final boundary in case another launcher installed the asset
    # while this process was downloading it.
    if target.exists():
        if file_matches(target, expected):
            return
        if not replace_mismatched:
            raise IntegrityError("An existing mismatched asset was preserved. Use --replace-mismatched to replace it explicitly.")
    if replace_mismatched:
        os.replace(temporary, target)
    else:
        try:
            if os.name == "nt":
                # Windows rename fails if the destination exists: no clobber.
                os.rename(temporary, target)
            else:
                # Link creation is atomic and refuses an existing destination.
                # Temporary and destination share one directory/filesystem.
                os.link(temporary, target)
        except FileExistsError as exc:
            if not file_matches(target, expected):
                raise IntegrityError("An existing mismatched asset was preserved. Use --replace-mismatched to replace it explicitly.") from exc
            return
    with target.open("rb+") as handle:
        os.fsync(handle.fileno())
    if os.name != "nt":
        directory = os.open(target.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)


def retrieve_asset(asset_dir: Path, expected: ExpectedAsset, url: str = RELEASE_URL,
                   replace_mismatched: bool = False, gh_fallback: bool = True) -> Path:
    asset_dir = asset_dir.expanduser().resolve()
    target = asset_dir / expected.name
    if target.exists():
        if file_matches(target, expected):
            print(f"Verified existing asset; preserved: {target}")
            return target
        if not replace_mismatched:
            raise IntegrityError(f"Existing {expected.name} does not match the pinned release and was preserved. Use --replace-mismatched only when you intend to replace it.")
    asset_dir.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix=f".{expected.name}.", suffix=".download", dir=asset_dir)
    os.close(descriptor)
    temporary = Path(name)
    try:
        print(f"Fetching {expected.name} ({expected.size:,} bytes) from public release {RELEASE_TAG}...", file=sys.stderr)
        try:
            download_urllib(url, temporary, expected)
        except NetworkError:
            if not gh_fallback or url != RELEASE_URL:
                raise
            download_gh(temporary, expected)
        install_verified(temporary, target, expected, replace_mismatched)
        print(f"Installed verified asset: {target}")
        print(f"SHA256 {expected.sha256}")
        return target
    finally:
        temporary.unlink(missing_ok=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset-dir", type=Path, default=ROOT / "game" / "assets" / "town3d", help="Destination directory; verification still uses the repository stage manifest.")
    parser.add_argument("--url", default=RELEASE_URL, help="HTTP(S) source override, e.g. a local test server. Never changes expected size/hash.")
    parser.add_argument("--replace-mismatched", action="store_true", help="Explicitly replace an existing incorrect asset after a verified download.")
    parser.add_argument("--no-gh-fallback", action="store_true", help="Disable the optional GitHub CLI fallback. URL overrides never invoke it.")
    args = parser.parse_args(argv)
    try:
        retrieve_asset(args.asset_dir, expected_asset(), args.url, args.replace_mismatched, not args.no_gh_fallback)
    except (FetchError, OSError) as exc:
        print(f"Town asset fetch failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
