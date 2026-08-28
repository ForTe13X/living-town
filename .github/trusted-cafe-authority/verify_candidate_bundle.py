#!/usr/bin/env python3
"""Base-owned, data-only authorization for protected cafe trust-root bundles."""

from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request


SCHEMA = "living-town.trusted-cafe-authority-receipt.v2"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")


class GateError(RuntimeError):
    pass


def canonical_bytes(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode("ascii")


def load_manifest(path: Path) -> dict:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    return validate_manifest(manifest)


def validate_manifest(manifest: object) -> dict:
    if not isinstance(manifest, dict):
        raise GateError("approved-bundle manifest must be an object")
    if manifest.get("schema") != "living-town.trusted-cafe-approved-bundles.v1":
        raise GateError("unsupported approved-bundle manifest schema")
    trust_paths = manifest.get("trust_paths")
    authority_paths = manifest.get("authority_paths")
    bundles = manifest.get("bundles")
    if not isinstance(trust_paths, list) or len(trust_paths) != len(set(trust_paths)):
        raise GateError("trust paths must be a unique list")
    if not isinstance(authority_paths, list) or len(authority_paths) != len(set(authority_paths)):
        raise GateError("authority paths must be a unique list")
    if set(trust_paths) & set(authority_paths):
        raise GateError("trust and authority paths must be disjoint")
    if not isinstance(bundles, list) or not bundles:
        raise GateError("at least one approved bundle is required")
    expected = set(trust_paths)
    bundle_ids: set[str] = set()
    bundle_identities: set[tuple[str, str]] = set()
    for bundle in bundles:
        if not isinstance(bundle, dict):
            raise GateError("bundle entries must be objects")
        bundle_id = bundle.get("id")
        if not isinstance(bundle_id, str) or not bundle_id or bundle_id in bundle_ids:
            raise GateError("bundle ids must be unique non-empty strings")
        bundle_ids.add(bundle_id)
        source_head = str(bundle.get("source_head", ""))
        source_tree = str(bundle.get("source_tree", ""))
        if not HEX40.fullmatch(source_head):
            raise GateError(f"bundle {bundle_id} has invalid source head")
        if not HEX40.fullmatch(source_tree):
            raise GateError(f"bundle {bundle_id} has invalid source tree")
        identity = (source_head, source_tree)
        if identity in bundle_identities:
            raise GateError(f"bundle {bundle_id} duplicates a source identity")
        bundle_identities.add(identity)
        evidence = bundle.get("evidence")
        if not isinstance(evidence, dict):
            raise GateError(f"bundle {bundle_id} lacks review evidence")
        for review in ("security_qa", "refute"):
            if not isinstance(evidence.get(review), str) or not evidence[review]:
                raise GateError(f"bundle {bundle_id} has invalid {review} evidence")
        files = bundle.get("files")
        if not isinstance(files, list) or any(not isinstance(item, dict) for item in files):
            raise GateError(f"bundle {bundle_id} files must be objects")
        paths = [item.get("path") for item in files]
        if len(files) != len(expected) or len(paths) != len(set(paths)) or set(paths) != expected:
            raise GateError(f"bundle {bundle_id} must bind every trust path exactly once")
        for item in files:
            if not HEX40.fullmatch(str(item.get("git_blob_sha", ""))):
                raise GateError(f"bundle {bundle_id} has invalid git blob SHA")
            if not HEX64.fullmatch(str(item.get("sha256", ""))):
                raise GateError(f"bundle {bundle_id} has invalid SHA-256")
            if item.get("mode") not in ("100644", "100755"):
                raise GateError(f"bundle {bundle_id} has invalid file mode")
            if not isinstance(item.get("bytes"), int) or item["bytes"] < 0:
                raise GateError(f"bundle {bundle_id} has invalid byte count")
    return manifest


class GitHubAPI:
    def __init__(self, repository: str, token: str):
        if not token:
            raise GateError("GitHub token is required")
        self.repository = repository
        self.token = token
        self.root = "https://api.github.com"

    def get(self, path: str) -> object:
        request = urllib.request.Request(
            self.root + path,
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {self.token}",
                "User-Agent": "living-town-cafe-base-authority-gate-v1",
                "X-GitHub-Api-Version": "2022-11-28",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                if response.status != 200:
                    raise GateError(f"GitHub API returned HTTP {response.status}")
                return json.load(response)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
            raise GateError(f"GitHub API read failed: {error}") from error

    def pull(self, number: int) -> dict:
        value = self.get(f"/repos/{self.repository}/pulls/{number}")
        if not isinstance(value, dict):
            raise GateError("pull response is not an object")
        return value

    def pull_files(self, number: int) -> list[dict]:
        values: list[dict] = []
        for page in range(1, 31):
            result = self.get(
                f"/repos/{self.repository}/pulls/{number}/files?per_page=100&page={page}"
            )
            if not isinstance(result, list):
                raise GateError("pull files response is not a list")
            values.extend(result)
            if len(result) < 100:
                return values
        raise GateError("pull file pagination exceeded 3000-file safety bound")

    def tree(self, commit_sha: str) -> tuple[str, list[dict]]:
        commit = self.get(f"/repos/{self.repository}/git/commits/{commit_sha}")
        if not isinstance(commit, dict) or not isinstance(commit.get("tree"), dict):
            raise GateError("commit response lacks tree identity")
        tree_sha = commit["tree"].get("sha")
        if not HEX40.fullmatch(str(tree_sha or "")):
            raise GateError("commit tree SHA is invalid")
        value = self.get(f"/repos/{self.repository}/git/trees/{tree_sha}?recursive=1")
        if not isinstance(value, dict) or value.get("truncated") is True:
            raise GateError("candidate tree response is truncated or invalid")
        tree = value.get("tree")
        if not isinstance(tree, list):
            raise GateError("candidate tree entries are missing")
        return tree_sha, tree

    def blob(self, sha: str) -> bytes:
        value = self.get(f"/repos/{self.repository}/git/blobs/{sha}")
        if not isinstance(value, dict) or value.get("encoding") != "base64":
            raise GateError("candidate blob is not base64 encoded")
        try:
            return base64.b64decode(str(value.get("content", "")), validate=False)
        except ValueError as error:
            raise GateError("candidate blob base64 is invalid") from error


def changed_paths(files: list[dict]) -> tuple[set[str], set[str], list[str]]:
    current: set[str] = set()
    touched: set[str] = set()
    renamed_or_copied: list[str] = []
    for item in files:
        filename = item.get("filename")
        status = item.get("status")
        if not isinstance(filename, str) or not filename or not isinstance(status, str):
            raise GateError("pull file entry lacks filename or status")
        current.add(filename)
        touched.add(filename)
        previous = item.get("previous_filename")
        if previous is not None:
            if not isinstance(previous, str) or not previous:
                raise GateError("previous filename is invalid")
            touched.add(previous)
            renamed_or_copied.append(f"{previous}->{filename}")
        if status in ("renamed", "copied"):
            renamed_or_copied.append(filename)
    return current, touched, sorted(set(renamed_or_copied))


def candidate_records_from_api(
    api: GitHubAPI, head_sha: str, trust_paths: set[str]
) -> tuple[str, dict[str, dict]]:
    tree_sha, tree = api.tree(head_sha)
    entries = {
        item.get("path"): item
        for item in tree
        if item.get("type") == "blob" and item.get("path") in trust_paths
    }
    if set(entries) != trust_paths:
        missing = sorted(trust_paths - set(entries))
        raise GateError(f"candidate tree lacks trust paths: {missing}")
    records: dict[str, dict] = {}
    for path in sorted(trust_paths):
        item = entries[path]
        sha = str(item.get("sha", ""))
        mode = str(item.get("mode", ""))
        if not HEX40.fullmatch(sha) or mode not in ("100644", "100755"):
            raise GateError(f"candidate tree identity is invalid for {path}")
        data = api.blob(sha)
        records[path] = {
            "bytes": len(data),
            "git_blob_sha": sha,
            "mode": mode,
            "path": path,
            "sha256": hashlib.sha256(data).hexdigest(),
        }
    return tree_sha, records


def review_evidence_approved(bundle: dict, head_sha: str) -> bool:
    evidence = bundle["evidence"]
    exact_head = head_sha.upper()
    return (
        evidence["security_qa"] == f"APPROVED_P0_0_P1_0_EXACT_HEAD_{exact_head}"
        and evidence["refute"] == f"REFUTE_P0_0_P1_0_EXACT_HEAD_{exact_head}"
    )


def evaluate(
    manifest: dict,
    pull: dict,
    files: list[dict],
    candidate_records: dict[str, dict] | None,
    candidate_tree_sha: str | None,
    repository: str,
) -> dict:
    base_repo = pull.get("base", {}).get("repo", {}).get("full_name")
    head_repo = pull.get("head", {}).get("repo", {}).get("full_name")
    base_ref = pull.get("base", {}).get("ref")
    head_sha = pull.get("head", {}).get("sha")
    if base_repo != repository or base_ref != "master":
        raise GateError("gate only authorizes pull requests targeting this repository's master")
    if head_repo != repository:
        raise GateError("fork candidates are not authorized for the protected trust root")
    if not HEX40.fullmatch(str(head_sha or "")):
        raise GateError("candidate head SHA is invalid")

    current, touched, renames = changed_paths(files)
    trust_paths = set(manifest["trust_paths"])
    authority_paths = set(manifest["authority_paths"])
    authority_touched = sorted(touched & authority_paths)
    if authority_touched:
        raise GateError(f"base authority self-modification is forbidden: {authority_touched}")
    other_workflows = sorted(
        path
        for path in touched
        if path.startswith(".github/workflows/") and path not in trust_paths
    )
    if other_workflows:
        raise GateError(f"other workflow changes are forbidden by this authority gate: {other_workflows}")

    trust_touched = touched & trust_paths
    if not trust_touched:
        return {
            "bundle_id": None,
            "changed_count": len(current),
            "head_sha": head_sha,
            "tree_sha": None,
            "mode": "not-applicable",
            "schema": SCHEMA,
        }
    if renames:
        raise GateError(f"trust-root rename or copy is forbidden: {renames}")
    outside = sorted(touched - trust_paths)
    if outside:
        raise GateError(f"trust-root changes cannot share a PR with outside paths: {outside}")
    if current != trust_paths or touched != trust_paths:
        raise GateError("a protected bundle must change the exact complete trust-path set")
    if candidate_records is None or set(candidate_records) != trust_paths:
        raise GateError("candidate records do not cover the complete trust-path set")
    if not HEX40.fullmatch(str(candidate_tree_sha or "")):
        raise GateError("candidate tree SHA is invalid")

    matches: list[str] = []
    for bundle in manifest["bundles"]:
        approved = {item["path"]: item for item in bundle["files"]}
        if (
            bundle["source_head"] == head_sha
            and bundle["source_tree"] == candidate_tree_sha
            and review_evidence_approved(bundle, head_sha)
            and approved == candidate_records
        ):
            matches.append(bundle["id"])
    if len(matches) != 1:
        raise GateError(f"candidate bundle matched {len(matches)} approved identities")
    return {
        "bundle_id": matches[0],
        "changed_count": len(current),
        "head_sha": head_sha,
        "tree_sha": candidate_tree_sha,
        "mode": "approved-bundle",
        "schema": SCHEMA,
    }


def fixture_pull(repository: str, head_sha: str = "1" * 40, fork: bool = False) -> dict:
    return {
        "base": {"ref": "master", "repo": {"full_name": repository}},
        "head": {
            "repo": {"full_name": "someone/fork" if fork else repository},
            "sha": head_sha,
        },
    }


def run_self_test(manifest: dict) -> dict:
    repository = "ForTe13X/living-town"
    trust_files = [{"filename": path, "status": "modified"} for path in manifest["trust_paths"]]
    cases: list[dict] = []

    def case(
        name: str,
        expect: str,
        manifest_value: dict,
        pull: dict,
        files: list[dict],
        values: dict | None,
        tree_sha: str | None,
    ) -> None:
        try:
            receipt = evaluate(manifest_value, pull, files, values, tree_sha, repository)
            result = receipt["mode"]
        except GateError:
            result = "rejected"
        if result != expect:
            raise AssertionError(f"{name}: expected {expect}, got {result}")
        cases.append({"name": name, "result": result})

    def manifest_case(name: str, value: dict) -> None:
        try:
            validate_manifest(value)
            result = "accepted"
        except GateError:
            result = "rejected"
        if result != "rejected":
            raise AssertionError(f"{name}: expected rejected, got {result}")
        cases.append({"name": name, "result": result})

    case(
        "unrelated-not-applicable",
        "not-applicable",
        manifest,
        fixture_pull(repository),
        [{"filename": "README.md", "status": "modified"}],
        None,
        None,
    )
    for bundle_index, bundle in enumerate(manifest["bundles"]):
        bundle_id = bundle["id"]
        source_head = bundle["source_head"]
        source_tree = bundle["source_tree"]
        approved_manifest = copy.deepcopy(manifest)
        approved_evidence = approved_manifest["bundles"][bundle_index]["evidence"]
        approved_evidence["security_qa"] = (
            f"APPROVED_P0_0_P1_0_EXACT_HEAD_{source_head.upper()}"
        )
        approved_evidence["refute"] = f"REFUTE_P0_0_P1_0_EXACT_HEAD_{source_head.upper()}"
        records = {item["path"]: copy.deepcopy(item) for item in bundle["files"]}
        case(
            f"exact-approved-bundle-{bundle_id}",
            "approved-bundle",
            approved_manifest,
            fixture_pull(repository, source_head),
            trust_files,
            records,
            source_tree,
        )
        case(
            f"same-files-different-head-{bundle_id}",
            "rejected",
            approved_manifest,
            fixture_pull(repository, "f" * 40 if source_head != "f" * 40 else "e" * 40),
            trust_files,
            records,
            source_tree,
        )
        case(
            f"same-files-different-tree-{bundle_id}",
            "rejected",
            approved_manifest,
            fixture_pull(repository, source_head),
            trust_files,
            records,
            "f" * 40 if source_tree != "f" * 40 else "e" * 40,
        )
        pending_manifest = copy.deepcopy(approved_manifest)
        pending_manifest["bundles"][bundle_index]["evidence"]["security_qa"] = (
            f"PENDING_INDEPENDENT_EXACT_HEAD_{source_head.upper()}"
        )
        case(
            f"pending-review-{bundle_id}",
            "rejected",
            pending_manifest,
            fixture_pull(repository, source_head),
            trust_files,
            records,
            source_tree,
        )
        changes_manifest = copy.deepcopy(approved_manifest)
        changes_manifest["bundles"][bundle_index]["evidence"]["refute"] = (
            f"REQUEST_CHANGES_P0_0_P1_1_EXACT_HEAD_{source_head.upper()}"
        )
        case(
            f"request-changes-review-{bundle_id}",
            "rejected",
            changes_manifest,
            fixture_pull(repository, source_head),
            trust_files,
            records,
            source_tree,
        )
        stale = copy.deepcopy(records)
        stale[manifest["trust_paths"][0]]["sha256"] = "0" * 64
        case(
            f"stale-blob-{bundle_id}",
            "rejected",
            approved_manifest,
            fixture_pull(repository, source_head),
            trust_files,
            stale,
            source_tree,
        )

    bundle = manifest["bundles"][0]
    records = {item["path"]: copy.deepcopy(item) for item in bundle["files"]}
    duplicate_record = copy.deepcopy(manifest)
    duplicate_record["bundles"][0]["files"].append(
        copy.deepcopy(duplicate_record["bundles"][0]["files"][0])
    )
    manifest_case("duplicate-trust-path-record", duplicate_record)
    duplicate_identity = copy.deepcopy(manifest)
    duplicate = copy.deepcopy(duplicate_identity["bundles"][0])
    duplicate["id"] += "-duplicate"
    duplicate_identity["bundles"].append(duplicate)
    manifest_case("duplicate-source-identity", duplicate_identity)
    invalid_source = copy.deepcopy(manifest)
    invalid_source["bundles"][0]["source_head"] = "0" * 39
    manifest_case("invalid-source-head", invalid_source)
    missing_review = copy.deepcopy(manifest)
    del missing_review["bundles"][0]["evidence"]["security_qa"]
    manifest_case("missing-review-evidence", missing_review)
    renamed = copy.deepcopy(trust_files[1:])
    renamed.append(
        {
            "filename": ".github/workflows/renamed.yml",
            "previous_filename": manifest["trust_paths"][0],
            "status": "renamed",
        }
    )
    case("rename-old-and-new", "rejected", manifest, fixture_pull(repository), renamed, records, None)
    mixed = copy.deepcopy(trust_files) + [{"filename": "README.md", "status": "modified"}]
    case("mixed-outside-path", "rejected", manifest, fixture_pull(repository), mixed, records, None)
    authority = [{"filename": manifest["authority_paths"][0], "status": "modified"}]
    case("authority-self-modification", "rejected", manifest, fixture_pull(repository), authority, None, None)
    duplicate = [{"filename": ".github/workflows/duplicate.yml", "status": "added"}]
    case("other-workflow-duplicate-surface", "rejected", manifest, fixture_pull(repository), duplicate, None, None)
    case("fork-candidate", "rejected", manifest, fixture_pull(repository, fork=True), trust_files, records, None)
    return {"cases": cases, "schema": "living-town.trusted-cafe-authority-selftest.v1"}


def write_output(path: Path | None, value: dict) -> None:
    data = canonical_bytes(value)
    if path is None:
        sys.stdout.buffer.write(data)
    else:
        path.write_bytes(data)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--repository")
    parser.add_argument("--pull-number", type=int)
    parser.add_argument("--token-env", default="GH_TOKEN")
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--github-output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    manifest = load_manifest(args.manifest)
    if args.self_test:
        write_output(args.receipt, run_self_test(manifest))
        return 0
    token = os.environ.get(args.token_env, "")
    if not args.repository or not args.pull_number or not token:
        parser.error("live mode requires --repository, --pull-number, and a populated token env")
    api = GitHubAPI(args.repository, token)
    pull = api.pull(args.pull_number)
    files = api.pull_files(args.pull_number)
    _, touched, _ = changed_paths(files)
    trust_paths = set(manifest["trust_paths"])
    records = None
    tree_sha = None
    if touched & trust_paths:
        tree_sha, records = candidate_records_from_api(
            api, pull.get("head", {}).get("sha", ""), trust_paths
        )
    receipt = evaluate(manifest, pull, files, records, tree_sha, args.repository)
    write_output(args.receipt, receipt)
    if args.github_output:
        with args.github_output.open("a", encoding="utf-8", newline="\n") as stream:
            stream.write(f"mode={receipt['mode']}\n")
            stream.write(f"bundle_id={receipt['bundle_id'] or ''}\n")
            stream.write(f"changed_count={receipt['changed_count']}\n")
            stream.write(f"head_sha={receipt['head_sha']}\n")
            stream.write(f"tree_sha={receipt['tree_sha'] or ''}\n")
    print(
        f"CAFE_BASE_AUTHORITY_GATE mode={receipt['mode']} "
        f"changed={receipt['changed_count']} head={receipt['head_sha']} "
        f"tree={receipt['tree_sha'] or 'none'} "
        f"bundle={receipt['bundle_id'] or 'none'}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except GateError as error:
        print(f"CAFE_BASE_AUTHORITY_GATE_REJECTED {error}", file=sys.stderr)
        raise SystemExit(1)
