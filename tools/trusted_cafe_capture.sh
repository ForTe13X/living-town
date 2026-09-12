#!/usr/bin/env bash
# Protected cafe source-to-capture trust root.  This file has two explicit
# modes: build-runtime (hosted immutable OCI construction) and capture (inside
# that loaded runtime).  Neither mode grants View or pixels authority over Sim.
set -euo pipefail

fail() {
  printf 'TRUSTED_CAFE_CAPTURE FAIL: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
usage:
  trusted_cafe_capture.sh build-runtime <trusted-root> <new-output-dir>
  trusted_cafe_capture.sh capture <candidate-root> <new-output-dir> \
    <candidate-sha> <candidate-tree> <workflow-sha> <workflow-tree> \
    <repository> <run-id> <run-attempt> <runtime-archive-sha256> \
    <runtime-build-receipt> <precompiled-authored-manifest>
EOF
  exit 2
}

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

canonical_oci_archive() {
  local layout="$1" archive="$2"
  TZ=UTC tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    --format=posix --pax-option=delete=atime,delete=ctime \
    -cf "$archive" -C "$layout" .
}

build_runtime_in_pinned_toolchain() {
  [ "$#" -eq 2 ] || usage
  local trusted_root out state state_root toolchain_image skopeo_image python_index_ref
  local output_uid output_gid cleanup_trap
  trusted_root="$(cd "$1" && pwd)"
  out="$2"
  [ ! -e "$out" ] || fail "output path already exists: $out"
  mkdir -p "$out"
  chmod 0750 "$out"
  out="$(cd "$out" && pwd)"
  output_uid="$(stat -c '%u' "$out")"
  output_gid="$(stat -c '%g' "$out")"
  [[ "$output_uid" =~ ^[0-9]+$ && "$output_gid" =~ ^[0-9]+$ ]] || \
    fail "output owner is not numeric"
  state_root="${TMPDIR:-/tmp}"
  state="$(mktemp -d "$state_root/trusted-cafe-oci-toolchain.XXXXXXXX")"
  mkdir -p "$state/storage" "$state/run" "$state/tmp" "$state/input"
  toolchain_image="quay.io/podman/stable@sha256:b0173238dceedf46a10d2c3a7bf9b217a85dce19706d2d9c80b01345839ae779"
  skopeo_image="quay.io/skopeo/stable@sha256:4a16d57b37617a04b3d643079a477a2848efe892dffcdf0ce56df4262b65f810"
  python_index_ref="docker.io/library/python@sha256:0bee7276f83efd4a1ee05bbbf4281d95ed28e079220a9457f25a93e3f1e3c31b"
  cleanup_toolchain_state() {
    local cleanup_state="$1" cleanup_root="$2" cleanup_image="$3"
    case "$cleanup_state" in
      "$cleanup_root"/trusted-cafe-oci-toolchain.*) ;;
      *) printf 'TRUSTED_CAFE_CAPTURE cleanup refused unsafe path: %s\n' \
           "$cleanup_state" >&2; return 1 ;;
    esac
    if rm -rf -- "$cleanup_state" 2>/dev/null && [ ! -e "$cleanup_state" ]; then
      return 0
    fi
    [ -d "$cleanup_state" ] || return 1
    docker run --pull=never --rm --platform linux/amd64 --network none --read-only \
      --cap-drop all --cap-add DAC_OVERRIDE --cap-add FOWNER \
      --security-opt no-new-privileges --pids-limit 32 --memory 128m --cpus 1 \
      --volume "$cleanup_state:/cleanup:rw" "$cleanup_image" \
      sh -euc 'find /cleanup -mindepth 1 -depth -delete; test -z "$(find /cleanup -mindepth 1 -print -quit)"'
    rmdir -- "$cleanup_state"
  }
  cleanup_toolchain_on_exit() {
    local cleanup_state="$1" cleanup_root="$2" cleanup_image="$3" primary_status="$4"
    trap - EXIT
    cleanup_toolchain_state "$cleanup_state" "$cleanup_root" "$cleanup_image" || \
      printf 'TRUSTED_CAFE_CAPTURE cleanup failed; preserving exit %s\n' \
        "$primary_status" >&2
    exit "$primary_status"
  }
  printf -v cleanup_trap 'cleanup_toolchain_on_exit %q %q %q "$?"' \
    "$state" "$state_root" "$toolchain_image"
  trap "$cleanup_trap" EXIT
  docker run --pull=always --rm --platform linux/amd64 \
    --pids-limit 128 --memory 512m --cpus 1 --volume "$state/input:/toolchain-input:rw" \
    --entrypoint sh "$skopeo_image" -euc \
    'test "$(skopeo --version | awk "{print \$3}")" = 1.22.2; skopeo inspect --raw "$1" > /toolchain-input/python-index.json' \
    sh "docker://$python_index_ref"
  docker run --pull=always --rm --privileged --platform linux/amd64 \
    --pids-limit 4096 --memory 8g --cpus 4 \
    --env CAFE_OCI_TOOLCHAIN_ACTIVE=1 --env "CAFE_OCI_TOOLCHAIN_IMAGE=$toolchain_image" \
    --env "CAFE_SKOPEO_IMAGE=$skopeo_image" --env "CAFE_OUTPUT_UID=$output_uid" \
    --env "CAFE_OUTPUT_GID=$output_gid" \
    --volume "$trusted_root:/trusted:ro" --volume "$out:/output:rw" \
    --volume "$state/input:/toolchain-input:ro" \
    --volume "$state/storage:/var/lib/containers:rw" \
    --volume "$state/run:/run/containers:rw" --volume "$state/tmp:/tmp:rw" \
    "$toolchain_image" bash /trusted/tools/trusted_cafe_capture.sh build-runtime /trusted /output
  trap - EXIT
  cleanup_toolchain_state "$state" "$state_root" "$toolchain_image" || \
    fail "toolchain cleanup failed"
}

build_runtime() {
  [ "$#" -eq 2 ] || usage
  if [ "${CAFE_OCI_TOOLCHAIN_ACTIVE:-}" != 1 ]; then
    build_runtime_in_pinned_toolchain "$@"
    return
  fi
  local trusted_root out lock context tag validation_tag layout archive first second
  local output_uid output_gid output_mode
  local validation_first validation_second validation_archive
  local validation_delta_first validation_delta_second validation_delta_archive
  local -a validation_values validation_delta_values
  trusted_root="$(cd "$1" && pwd)"
  out="$2"
  lock="$trusted_root/evidence/cafe/runtime-lock.v1.json"
  [ -f "$lock" ] || fail "runtime lock missing"
  [ -d "$out" ] || fail "containerized output mount missing: $out"
  [ -z "$(find "$out" -mindepth 1 -maxdepth 1 -print -quit)" ] || fail "output path is not empty: $out"
  out="$(cd "$out" && pwd)"
  output_uid="${CAFE_OUTPUT_UID:-}"
  output_gid="${CAFE_OUTPUT_GID:-}"
  [[ "$output_uid" =~ ^[0-9]+$ && "$output_gid" =~ ^[0-9]+$ ]] || \
    fail "containerized output owner contract missing"
  [ "$(stat -c '%u' "$out")" = "$output_uid" ] || fail "containerized output UID drift"
  [ "$(stat -c '%g' "$out")" = "$output_gid" ] || fail "containerized output GID drift"
  output_mode="$(stat -c '%a' "$out")"
  [ "$output_mode" = 750 ] || fail "containerized output mode drift: $output_mode"
  context="$(mktemp -d "${TMPDIR:-/tmp}/trusted-cafe-runtime.XXXXXXXX")"
  chown "$output_uid:$output_gid" "$context"
  chmod 0750 "$context"
  tag="localhost/living-town/trusted-cafe-runtime:v1"
  validation_tag="localhost/living-town/trusted-cafe-validation:v1"
  trap "podman image rm -f '$tag' '$validation_tag' >/dev/null 2>&1 || true; rm -rf '$context'" EXIT

  # This literal is itself protected by the trust-root snapshot.  The
  # containerized lock parser below requires the lock to name the same digest
  # before any material recipe value is accepted.
  local validation_image="docker.io/library/python@sha256:2fc9207f64226cb05ac317cee0bab6fa55a9ea311ce5a086baddd4b4a83c2d3c"
  podman pull --platform linux/amd64 "$validation_image" >/dev/null
  container_python() {
    podman run --rm --interactive --network none --read-only --cap-drop all \
      --security-opt no-new-privileges --pids-limit 128 --memory 768m --cpus 2 \
      --user "$output_uid:$output_gid" \
      --tmpfs /tmp:rw,nosuid,nodev,size=268435456 \
      --volume "$trusted_root:/trusted:ro" \
      --volume "$context:/context:rw" \
      --volume "$out:/output:rw" \
      "$validation_image" python -B "$@"
  }

  mapfile -t lock_values < <(container_python - /trusted/evidence/cafe/runtime-lock.v1.json "$validation_image" <<'PY'
import json, sys
lock_path, validation_image = sys.argv[1:]
p = json.load(open(lock_path, encoding="utf-8"))
assert p["schema"] == "living-town.cafe-runtime-lock.v1"
assert p["validation_image"] == {"reference": validation_image, "platform": "linux/amd64"}
values = [
    p["python_image"]["build_reference"],
    p["python_image"]["amd64_manifest_digest"],
    p["python_image"]["index_reference"],
    p["pillow"]["filename"], p["pillow"]["url"], p["pillow"]["sha256"],
    p["godot"]["url"], p["godot"]["archive_sha256"], p["godot"]["binary_sha256"],
    p["debian_snapshot"]["debian"], p["debian_snapshot"]["security"],
    p["versions"]["python"], p["versions"]["pillow"], p["versions"]["godot"],
    p["host_tools"]["gh"],
    str(p["limits"]["max_runtime_archive_bytes"]),
    str(p["limits"]["max_validation_archive_bytes"]),
    str(p["limits"]["max_validation_delta_archive_bytes"]),
    p["oci_toolchain"]["podman_image"], p["oci_toolchain"]["skopeo_image"],
    p["oci_toolchain"]["versions"]["podman"], p["oci_toolchain"]["versions"]["skopeo"],
    p["oci_toolchain"]["versions"]["tar"], p["oci_toolchain"]["versions"]["python"],
    p["oci_toolchain"]["versions"]["sha256sum"],
]
for value in values:
    if "\n" in str(value) or "\r" in str(value):
        raise SystemExit("newline in runtime lock scalar")
    print(value)
PY
  )
  [ "${#lock_values[@]}" -eq 25 ] || fail "runtime lock scalar extraction failed"
  local base_ref="${lock_values[0]}" base_digest="${lock_values[1]}"
  local index_ref="${lock_values[2]}"
  local pillow_filename="${lock_values[3]}" pillow_url="${lock_values[4]}" pillow_sha="${lock_values[5]}"
  local godot_url="${lock_values[6]}" godot_archive_sha="${lock_values[7]}"
  local godot_binary_sha="${lock_values[8]}" debian_snapshot="${lock_values[9]}"
  local security_snapshot="${lock_values[10]}" python_version="${lock_values[11]}"
  local pillow_version="${lock_values[12]}" godot_version="${lock_values[13]}"
  local gh_version="${lock_values[14]}" max_archive_bytes="${lock_values[15]}"
  local max_validation_archive_bytes="${lock_values[16]}"
  local max_validation_delta_archive_bytes="${lock_values[17]}"
  local toolchain_image="${lock_values[18]}" skopeo_image="${lock_values[19]}"
  local podman_version="${lock_values[20]}" skopeo_version="${lock_values[21]}"
  local tar_version="${lock_values[22]}" toolchain_python="${lock_values[23]}"
  local sha256sum_version="${lock_values[24]}"

  [ "$toolchain_image" = "${CAFE_OCI_TOOLCHAIN_IMAGE:-}" ] || fail "OCI toolchain image drift"
  [ "$(podman --version | awk '{print $3}')" = "$podman_version" ] || fail "Podman drift"
  [ "$(tar --version | head -1)" = "$tar_version" ] || fail "tar drift"
  [ "$(python3 --version | awk '{print $2}')" = "$toolchain_python" ] || fail "toolchain Python drift"
  [ "$(sha256sum --version | head -1)" = "$sha256sum_version" ] || fail "sha256sum drift"

  [ "$skopeo_image" = "${CAFE_SKOPEO_IMAGE:-}" ] || fail "Skopeo toolchain image drift"
  [ -s /toolchain-input/python-index.json ] || fail "digest-pinned Skopeo index inspection missing"
  cp /toolchain-input/python-index.json "$context/python-index.json"
  [ "$(sha256_file "$context/python-index.json")" = "${index_ref##*@sha256:}" ] || \
    fail "Python index digest mismatch"
  container_python - /context/python-index.json "$base_digest" <<'PY'
import json, sys
index = json.load(open(sys.argv[1], encoding="utf-8"))
expected = sys.argv[2]
matches = [
    item.get("digest") for item in index.get("manifests", [])
    if item.get("platform", {}).get("os") == "linux"
    and item.get("platform", {}).get("architecture") == "amd64"
    and not item.get("platform", {}).get("variant")
]
if matches != [expected]:
    raise SystemExit(f"linux/amd64 descriptor mismatch: {matches!r} != {[expected]!r}")
PY

  curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
    --output "$context/$pillow_filename" "$pillow_url"
  curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
    --output "$context/godot.zip" "$godot_url"
  [ "$(sha256_file "$context/$pillow_filename")" = "$pillow_sha" ] || fail "Pillow wheel hash mismatch"
  [ "$(sha256_file "$context/godot.zip")" = "$godot_archive_sha" ] || fail "Godot archive hash mismatch"

  cat >"$context/Containerfile" <<'EOF'
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
ARG DEBIAN_SNAPSHOT
ARG SECURITY_SNAPSHOT
ARG PILLOW_FILENAME
ARG PILLOW_SHA256
ARG GODOT_ARCHIVE_SHA256
ARG GODOT_BINARY_SHA256
ARG PYTHON_VERSION
ARG PILLOW_VERSION
ARG GODOT_VERSION
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONHASHSEED=0 \
    SOURCE_DATE_EPOCH=0 \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    LIBGL_ALWAYS_SOFTWARE=1 \
    LP_NUM_THREADS=1 \
    GODOT_SILENCE_ROOT_WARNING=1
RUN printf '%s\n' \
      "deb [check-valid-until=no] ${DEBIAN_SNAPSHOT} bookworm main" \
      "deb [check-valid-until=no] ${DEBIAN_SNAPSHOT} bookworm-updates main" \
      "deb [check-valid-until=no] ${SECURITY_SNAPSHOT} bookworm-security main" \
      > /etc/apt/sources.list \
 && rm -f /etc/apt/sources.list.d/* \
 && mkdir -p /var/lib/apt/lists/partial \
 && apt-get -o Acquire::Check-Valid-Until=false update \
 && apt-get -o Acquire::Check-Valid-Until=false install -y --no-install-recommends \
      bash ca-certificates coreutils findutils gzip libasound2 libfontconfig1 \
      libgl1 libgl1-mesa-dri libglx-mesa0 libx11-6 libxcursor1 libxext6 libxi6 \
      libxinerama1 libxrandr2 libxrender1 tar xauth xvfb \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /var/log/apt/* \
      /var/log/dpkg.log /var/log/alternatives.log /var/cache/fontconfig/* \
      /var/cache/ldconfig/aux-cache /var/lib/systemd/random-seed \
 && rm -f /etc/machine-id /var/lib/dbus/machine-id
COPY ${PILLOW_FILENAME} /tmp/${PILLOW_FILENAME}
COPY godot.zip /tmp/godot.zip
RUN printf '%s  %s\n' "$PILLOW_SHA256" "/tmp/$PILLOW_FILENAME" | sha256sum -c - \
 && printf '%s  %s\n' "$GODOT_ARCHIVE_SHA256" /tmp/godot.zip | sha256sum -c - \
 && python -B -c "import zipfile; zipfile.ZipFile('/tmp/godot.zip').extractall('/tmp/godot')" \
 && install -m 0755 /tmp/godot/Godot_v4.6.2-stable_linux.x86_64 /usr/local/bin/godot \
 && printf '%s  %s\n' "$GODOT_BINARY_SHA256" /usr/local/bin/godot | sha256sum -c - \
 && python -B -m pip install --no-cache-dir --no-deps --no-index "/tmp/$PILLOW_FILENAME" \
 && rm -rf "/tmp/$PILLOW_FILENAME" /tmp/godot.zip /tmp/godot \
 && ! ldd /usr/local/bin/godot | grep -F 'not found' \
 && test "$(python -B -c 'import platform; print(platform.python_version())')" = "$PYTHON_VERSION" \
 && test "$(python -B -c 'import PIL; print(PIL.__version__)')" = "$PILLOW_VERSION" \
 && test "$(godot --version)" = "$GODOT_VERSION"
LABEL org.opencontainers.image.title="living-town-trusted-cafe-runtime" \
      org.opencontainers.image.version="v1"
WORKDIR /work
EOF

  build_once() {
    local label="$1" destination="$2"
    local layout_path="$context/layout-$label"
    podman image rm -f "$tag" >/dev/null 2>&1 || true
    podman build --pull=always --no-cache --layers=false --timestamp 0 \
      --format oci --platform linux/amd64 \
      --build-arg "BASE_IMAGE=$base_ref" \
      --build-arg "DEBIAN_SNAPSHOT=$debian_snapshot" \
      --build-arg "SECURITY_SNAPSHOT=$security_snapshot" \
      --build-arg "PILLOW_FILENAME=$pillow_filename" \
      --build-arg "PILLOW_SHA256=$pillow_sha" \
      --build-arg "GODOT_ARCHIVE_SHA256=$godot_archive_sha" \
      --build-arg "GODOT_BINARY_SHA256=$godot_binary_sha" \
      --build-arg "PYTHON_VERSION=$python_version" \
      --build-arg "PILLOW_VERSION=$pillow_version" \
      --build-arg "GODOT_VERSION=$godot_version" \
      --tag "$tag" "$context"
    podman run --rm --network none --read-only --cap-drop all \
      --security-opt no-new-privileges --pids-limit 128 --memory 768m --cpus 2 \
      --tmpfs /tmp:rw,nosuid,nodev,size=134217728 "$tag" python -B -c \
      'import PIL,platform; print(platform.python_version(), PIL.__version__)'
    podman run --rm --network none --read-only --cap-drop all \
      --security-opt no-new-privileges --pids-limit 128 --memory 768m --cpus 2 \
      --tmpfs /tmp:rw,nosuid,nodev,size=134217728 "$tag" godot --version
    podman save --format oci-dir --output "$layout_path" "$tag"
    canonical_oci_archive "$layout_path" "$destination"
  }

  first="$context/runtime-first.oci.tar"
  second="$context/runtime-second.oci.tar"
  build_once first "$first"
  build_once second "$second"
  container_python - /context/layout-first /context/layout-second /context/runtime-first.oci.tar \
    /context/runtime-second.oci.tar "$max_archive_bytes" <<'PY'
import hashlib, json, pathlib, sys, tarfile

def blob(layout, digest):
    algorithm, value = digest.split(":", 1)
    return pathlib.Path(layout, "blobs", algorithm, value)

def manifest(layout):
    index = json.load(open(pathlib.Path(layout, "index.json"), encoding="utf-8"))
    descriptor = index["manifests"][0]
    return json.load(open(blob(layout, descriptor["digest"]), encoding="utf-8"))

def layer_inventory(path):
    result = {}
    with tarfile.open(path, "r:*") as archive:
        for member in archive.getmembers():
            payload = b""
            if member.isfile():
                source = archive.extractfile(member)
                payload = source.read() if source else b""
            result[member.name] = (
                member.type.decode("latin1") if isinstance(member.type, bytes) else str(member.type),
                member.mode, member.uid, member.gid, member.size, member.linkname,
                hashlib.sha256(payload).hexdigest(),
            )
    return result

left_layout, right_layout, first_archive, second_archive, max_archive_bytes = sys.argv[1:]
left, right = manifest(left_layout), manifest(right_layout)
def sha256(path):
    value = hashlib.sha256()
    with open(path, "rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()
first_sha, second_sha = sha256(first_archive), sha256(second_archive)
if first_sha == second_sha:
    if pathlib.Path(first_archive).stat().st_size > int(max_archive_bytes):
        raise SystemExit("runtime archive exceeds budget")
    print(first_sha)
    raise SystemExit(0)
print("OCI_NONDETERMINISM config", left["config"]["digest"], right["config"]["digest"])
for index, (left_layer, right_layer) in enumerate(zip(left["layers"], right["layers"])):
    if left_layer["digest"] == right_layer["digest"]:
        continue
    print("OCI_NONDETERMINISM layer", index, left_layer["digest"], right_layer["digest"])
    a = layer_inventory(blob(left_layout, left_layer["digest"]))
    b = layer_inventory(blob(right_layout, right_layer["digest"]))
    differences = sorted(path for path in set(a) | set(b) if a.get(path) != b.get(path))
    for path in differences[:200]:
        print("OCI_NONDETERMINISM path", path, a.get(path), b.get(path))
    if len(differences) > 200:
        print("OCI_NONDETERMINISM truncated", len(differences))
raise SystemExit("independent runtime builds are not byte deterministic")
PY

  cat >"$context/ValidationContainerfile" <<'EOF'
ARG CAPTURE_IMAGE
FROM ${CAPTURE_IMAGE}
ARG DEBIAN_SNAPSHOT
ARG SECURITY_SNAPSHOT
RUN printf '%s\n' \
      "deb [check-valid-until=no] ${DEBIAN_SNAPSHOT} bookworm main" \
      "deb [check-valid-until=no] ${DEBIAN_SNAPSHOT} bookworm-updates main" \
      "deb [check-valid-until=no] ${SECURITY_SNAPSHOT} bookworm-security main" \
      > /etc/apt/sources.list \
 && mkdir -p /var/lib/apt/lists/partial \
 && apt-get -o Acquire::Check-Valid-Until=false update \
 && apt-get -o Acquire::Check-Valid-Until=false install -y --no-install-recommends git \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /var/log/apt/* \
      /var/log/dpkg.log /var/log/alternatives.log /var/cache/ldconfig/aux-cache \
      /usr/share/doc/* /usr/share/man/*
LABEL org.opencontainers.image.title="living-town-trusted-cafe-validation" \
      org.opencontainers.image.version="v1"
EOF
  build_validation_once() {
    local label="$1" destination="$2"
    local layout_path="$context/layout-validation-$label"
    podman image rm -f "$validation_tag" >/dev/null 2>&1 || true
    podman build --pull=never --no-cache --layers=false --timestamp 0 \
      --format oci --platform linux/amd64 \
      --build-arg "CAPTURE_IMAGE=$tag" \
      --build-arg "DEBIAN_SNAPSHOT=$debian_snapshot" \
      --build-arg "SECURITY_SNAPSHOT=$security_snapshot" \
      --file "$context/ValidationContainerfile" --tag "$validation_tag" "$context"
    podman run --rm --network none --read-only --cap-drop all \
      --security-opt no-new-privileges --pids-limit 64 --memory 256m --cpus 1 \
      --tmpfs /tmp:rw,nosuid,nodev,size=67108864 "$validation_tag" \
      bash -euo pipefail -c 'git --version && python -B -c "import PIL; print(PIL.__version__)"'
    podman save --format oci-dir --output "$layout_path" "$validation_tag"
    canonical_oci_archive "$layout_path" "$destination"
  }

  validation_first="$context/validation-first.oci.tar"
  validation_second="$context/validation-second.oci.tar"
  build_validation_once first "$validation_first"
  build_validation_once second "$validation_second"
  mapfile -t validation_values < <(container_python - \
    /context/validation-first.oci.tar /context/validation-second.oci.tar \
    "$max_validation_archive_bytes" <<'PY'
import hashlib, os, sys

def sha256(path):
    value = hashlib.sha256()
    with open(path, "rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()

first, second, max_validation_archive_bytes = sys.argv[1:]
first_sha, second_sha = sha256(first), sha256(second)
if first_sha != second_sha:
    raise SystemExit("independent validation builds are not byte deterministic")
if os.path.getsize(first) != os.path.getsize(second):
    raise SystemExit("independent validation archive sizes differ")
if os.path.getsize(first) > int(max_validation_archive_bytes):
    raise SystemExit("validation archive exceeds budget")
print(first_sha)
print(os.path.getsize(first))
PY
  )
  [ "${#validation_values[@]}" -eq 2 ] || fail "validation archive comparison failed"

  make_validation_delta() {
    local label="$1"
    container_python - "/context/layout-validation-$label" /context/layout-first \
      "/context/layout-validation-delta-$label" "/context/layout-validation-reconstructed-$label" <<'PY'
import hashlib, json, pathlib, shutil, sys

validation, runtime, delta, reconstructed = map(pathlib.Path, sys.argv[1:])

def read_json(path):
    return json.load(open(path, encoding="utf-8"))

def blob_path(layout, digest):
    algorithm, value = digest.split(":", 1)
    if algorithm != "sha256" or len(value) != 64:
        raise SystemExit(f"invalid OCI digest: {digest}")
    return layout / "blobs" / algorithm / value

def verified_blob(layout, digest):
    path = blob_path(layout, digest)
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest.split(":", 1)[1]:
        raise SystemExit(f"missing or corrupt OCI blob: {digest}")
    return path

index = read_json(validation / "index.json")
manifests = index.get("manifests")
if not isinstance(manifests, list) or len(manifests) != 1:
    raise SystemExit("validation OCI index must contain exactly one manifest")
manifest_digest = manifests[0]["digest"]
manifest_path = verified_blob(validation, manifest_digest)
manifest = read_json(manifest_path)
required = [manifest_digest, manifest["config"]["digest"]]
required.extend(item["digest"] for item in manifest.get("layers", []))

for target in (delta, reconstructed):
    (target / "blobs" / "sha256").mkdir(parents=True)
    shutil.copyfile(validation / "oci-layout", target / "oci-layout")
    shutil.copyfile(validation / "index.json", target / "index.json")

for digest in required:
    source = verified_blob(validation, digest)
    runtime_source = blob_path(runtime, digest)
    if runtime_source.is_file():
        verified_blob(runtime, digest)
    else:
        shutil.copyfile(source, blob_path(delta, digest))
    reconstruction_source = blob_path(delta, digest)
    if not reconstruction_source.is_file():
        reconstruction_source = verified_blob(runtime, digest)
    shutil.copyfile(reconstruction_source, blob_path(reconstructed, digest))

delta_blobs = sorted(path.name for path in (delta / "blobs" / "sha256").iterdir())
if len(delta_blobs) < 3:
    raise SystemExit("validation delta must retain manifest, config, and unique layer")
if sorted(path.name for path in (reconstructed / "blobs" / "sha256").iterdir()) != sorted(
    digest.split(":", 1)[1] for digest in required
):
    raise SystemExit("validation reconstruction blob set mismatch")
PY
    canonical_oci_archive "$context/layout-validation-delta-$label" \
      "$context/validation-delta-$label.oci.tar"
    canonical_oci_archive "$context/layout-validation-reconstructed-$label" \
      "$context/validation-reconstructed-$label.oci.tar"
  }

  make_validation_delta first
  make_validation_delta second
  validation_delta_first="$context/validation-delta-first.oci.tar"
  validation_delta_second="$context/validation-delta-second.oci.tar"
  mapfile -t validation_delta_values < <(container_python - \
    /context/validation-delta-first.oci.tar /context/validation-delta-second.oci.tar \
    /context/validation-reconstructed-first.oci.tar /context/validation-first.oci.tar \
    /context/validation-reconstructed-second.oci.tar /context/validation-second.oci.tar \
    "$max_validation_delta_archive_bytes" <<'PY'
import hashlib, os, sys

def sha256(path):
    value = hashlib.sha256()
    with open(path, "rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()

(first_delta, second_delta, first_reconstructed, first_full,
 second_reconstructed, second_full, max_delta_bytes) = sys.argv[1:]
first_sha, second_sha = sha256(first_delta), sha256(second_delta)
if first_sha != second_sha or os.path.getsize(first_delta) != os.path.getsize(second_delta):
    raise SystemExit("independent validation deltas are not byte deterministic")
if sha256(first_reconstructed) != sha256(first_full) or sha256(second_reconstructed) != sha256(second_full):
    raise SystemExit("runtime plus validation delta does not reconstruct the exact validation archive")
if os.path.getsize(first_delta) > int(max_delta_bytes):
    raise SystemExit("validation delta archive exceeds budget")
print(first_sha)
print(os.path.getsize(first_delta))
PY
  )
  [ "${#validation_delta_values[@]}" -eq 2 ] || fail "validation delta comparison failed"
  archive="$out/runtime.oci.tar"
  validation_archive="$out/validation.oci.tar"
  validation_delta_archive="$out/validation.delta.oci.tar"
  cp "$first" "$archive"
  cp "$validation_first" "$validation_archive"
  cp "$validation_delta_first" "$validation_delta_archive"
  layout="$context/layout-first"
  local oci_manifest_digest
  oci_manifest_digest="$(container_python - /context/layout-first/index.json <<'PY'
import json, re, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
manifests = p.get("manifests")
if not isinstance(manifests, list) or len(manifests) != 1:
    raise SystemExit("OCI index must contain exactly one manifest")
digest = manifests[0].get("digest", "")
if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
    raise SystemExit("invalid OCI manifest digest")
print(digest.removeprefix("sha256:"))
PY
  )"
  local validation_oci_manifest_digest
  validation_oci_manifest_digest="$(container_python - /context/layout-validation-first/index.json <<'PY'
import json, re, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
manifests = p.get("manifests")
if not isinstance(manifests, list) or len(manifests) != 1:
    raise SystemExit("validation OCI index must contain exactly one manifest")
digest = manifests[0].get("digest", "")
if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
    raise SystemExit("invalid validation OCI manifest digest")
print(digest.removeprefix("sha256:"))
PY
  )"
  local archive_sha lock_sha
  archive_sha="$(container_python - /output/runtime.oci.tar <<'PY'
import hashlib, sys
value = hashlib.sha256()
with open(sys.argv[1], "rb") as source:
    for block in iter(lambda: source.read(1024 * 1024), b""):
        value.update(block)
print(value.hexdigest())
PY
  )"
  local validation_archive_sha="${validation_values[0]}"
  local validation_archive_bytes="${validation_values[1]}"
  local validation_delta_archive_sha="${validation_delta_values[0]}"
  local validation_delta_archive_bytes="${validation_delta_values[1]}"
  lock_sha="$(container_python - /trusted/evidence/cafe/runtime-lock.v1.json <<'PY'
import hashlib, sys
print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())
PY
  )"
  container_python - /output/runtime-build-receipt.json "$lock_sha" "$archive_sha" \
    "$oci_manifest_digest" "${base_digest#sha256:}" "$python_version" "$pillow_version" \
    "$godot_version" "$podman_version" "$skopeo_version" "$gh_version" \
    "$validation_image" "$validation_oci_manifest_digest" "$toolchain_image" "$skopeo_image" \
    "$tar_version" "$toolchain_python" "$sha256sum_version" <<'PY'
import json, os, sys, tempfile
(out, lock_sha, archive_sha, manifest_digest, base_digest, python_version,
 pillow_version, godot_version, podman, skopeo, gh, validation_image,
 validation_oci_manifest_digest, toolchain_image, skopeo_image, tar_version,
 toolchain_python, sha256sum_version) = sys.argv[1:]
p = {
    "schema": "living-town.cafe-runtime-build-receipt.v1",
    "lock_sha256": lock_sha,
    "runtime_archive_sha256": archive_sha,
    "oci_manifest_digest": manifest_digest,
    "base_manifest_digest": "sha256:" + base_digest,
    "python": python_version,
    "pillow": pillow_version,
    "godot": godot_version,
    "podman": podman,
    "skopeo": skopeo,
    "gh": gh,
    "oci_toolchain_image": toolchain_image,
    "skopeo_image": skopeo_image,
    "toolchain_tar": tar_version,
    "toolchain_python": toolchain_python,
    "toolchain_sha256sum": sha256sum_version,
    "validation_image": validation_image,
    "validation_oci_manifest_digest": validation_oci_manifest_digest,
    "container_platform": "linux/amd64",
    "container_network": "none",
    "container_read_only": True,
    "container_cap_drop": "ALL",
    "container_no_new_privileges": True,
    "first_archive_sha256": archive_sha,
    "second_archive_sha256": archive_sha,
    "reproducible": True,
}
data = (json.dumps(p, sort_keys=True, separators=(",", ":")) + "\n").encode("ascii")
fd, tmp = tempfile.mkstemp(prefix=".runtime-receipt-", dir=os.path.dirname(out))
with os.fdopen(fd, "wb") as f:
    f.write(data)
os.replace(tmp, out)
PY
  container_python - /output/validation-build-receipt.json "$archive_sha" \
    "$validation_archive_sha" "$validation_archive_bytes" \
    "$validation_oci_manifest_digest" "$validation_delta_archive_sha" \
    "$validation_delta_archive_bytes" <<'PY'
import json, os, sys, tempfile

(out, runtime_archive_sha, validation_archive_sha, validation_archive_bytes,
 validation_oci_manifest_digest, validation_delta_archive_sha,
 validation_delta_archive_bytes) = sys.argv[1:]
p = {
    "schema": "living-town.cafe-validation-build-receipt.v1",
    "runtime_archive_sha256": runtime_archive_sha,
    "validation_archive_sha256": validation_archive_sha,
    "validation_archive_bytes": int(validation_archive_bytes),
    "validation_oci_manifest_digest": validation_oci_manifest_digest,
    "validation_delta_archive_sha256": validation_delta_archive_sha,
    "validation_delta_archive_bytes": int(validation_delta_archive_bytes),
    "validation_delta_reconstruction": "runtime.oci.tar+validation.delta.oci.tar",
    "first_archive_sha256": validation_archive_sha,
    "second_archive_sha256": validation_archive_sha,
    "container_platform": "linux/amd64",
    "container_network": "none",
    "container_read_only": True,
    "container_cap_drop": "ALL",
    "container_no_new_privileges": True,
    "reproducible": True,
}
data = (json.dumps(p, sort_keys=True, separators=(",", ":")) + "\n").encode("ascii")
fd, tmp = tempfile.mkstemp(prefix=".validation-receipt-", dir=os.path.dirname(out))
with os.fdopen(fd, "wb") as f:
    f.write(data)
os.replace(tmp, out)
PY
  chown "$output_uid:$output_gid" \
    "$archive" "$validation_archive" "$validation_delta_archive" \
    "$out/runtime-build-receipt.json" "$out/validation-build-receipt.json"
  chmod 0640 \
    "$archive" "$validation_archive" "$validation_delta_archive" \
    "$out/runtime-build-receipt.json" "$out/validation-build-receipt.json"
  printf 'TRUSTED_CAFE_RUNTIME PASS archive_sha256=%s oci_manifest_digest=%s\n' \
    "$archive_sha" "$oci_manifest_digest"
  printf 'TRUSTED_CAFE_VALIDATION PASS archive_sha256=%s oci_manifest_digest=%s bytes=%s\n' \
    "$validation_archive_sha" "$validation_oci_manifest_digest" "$validation_archive_bytes"
  printf 'TRUSTED_CAFE_VALIDATION_DELTA PASS archive_sha256=%s bytes=%s\n' \
    "$validation_delta_archive_sha" "$validation_delta_archive_bytes"
}

capture() {
  [ "$#" -eq 12 ] || usage
  local candidate_root out candidate_sha candidate_tree workflow_sha workflow_tree
  local repository run_id run_attempt runtime_archive_sha runtime_receipt authored_input trusted_root lock
  candidate_root="$(cd "$1" && pwd)"; out="$2"; candidate_sha="$3"; candidate_tree="$4"
  workflow_sha="$5"; workflow_tree="$6"; repository="$7"; run_id="$8"; run_attempt="$9"
  runtime_archive_sha="${10}"; runtime_receipt="$(cd "$(dirname "${11}")" && pwd)/$(basename "${11}")"
  authored_input="$(cd "$(dirname "${12}")" && pwd)/$(basename "${12}")"
  trusted_root="$(cd "$(dirname "$0")/.." && pwd)"
  lock="$trusted_root/evidence/cafe/runtime-lock.v1.json"
  [[ "$candidate_sha" =~ ^[0-9a-f]{40}$ ]] || fail "invalid candidate SHA"
  [[ "$candidate_tree" =~ ^[0-9a-f]{40}$ ]] || fail "invalid candidate tree"
  [[ "$workflow_sha" =~ ^[0-9a-f]{40}$ ]] || fail "invalid workflow SHA"
  [[ "$workflow_tree" =~ ^[0-9a-f]{40}$ ]] || fail "invalid workflow tree"
  [[ "$runtime_archive_sha" =~ ^[0-9a-f]{64}$ ]] || fail "invalid runtime archive digest"
  [[ "$run_id" =~ ^[1-9][0-9]{0,19}$ ]] || fail "invalid run ID"
  [[ "$run_attempt" =~ ^[1-9][0-9]{0,19}$ ]] || fail "invalid run attempt"
  [ "$repository" = "ForTe13X/living-town" ] || fail "unexpected repository"
  [ -f "$runtime_receipt" ] || fail "runtime build receipt missing"
  [ -f "$authored_input" ] || fail "precompiled authored manifest missing"
  [ ! -e "$out" ] || fail "output path already exists: $out"

  # The protected workflow performs these Git identity and cleanliness checks on
  # the host before mounting both checkouts read-only.  Keeping Git out of the
  # capture image avoids mutable package bloat without weakening that boundary.
  if [ "${CAFE_CHECKOUTS_PREVERIFIED:-0}" != 1 ]; then
    command -v git >/dev/null || fail "Git unavailable for checkout verification"
    [ "$(git -C "$candidate_root" rev-parse HEAD)" = "$candidate_sha" ] || fail "candidate SHA mismatch"
    [ "$(git -C "$candidate_root" show -s --format='%T' HEAD)" = "$candidate_tree" ] || fail "candidate tree mismatch"
    [ "$(git -C "$trusted_root" rev-parse HEAD)" = "$workflow_sha" ] || fail "workflow SHA mismatch"
    [ "$(git -C "$trusted_root" show -s --format='%T' HEAD)" = "$workflow_tree" ] || fail "workflow tree mismatch"
    [ -z "$(git -C "$candidate_root" status --porcelain=v1 --untracked-files=all)" ] || fail "candidate is dirty"
    [ -z "$(git -C "$trusted_root" status --porcelain=v1 --untracked-files=all)" ] || fail "trusted root is dirty"
  fi
  [ -z "$(find "$candidate_root/game" -type l -print -quit)" ] || fail "candidate game contains a symlink"
  cmp -s "$candidate_root/evidence/cafe/cafe-authored-ids.v1.json" \
    "$trusted_root/evidence/cafe/cafe-authored-ids.v1.json" || fail "candidate stable IDs differ from protected master"
  cmp -s "$candidate_root/evidence/cafe/cafe-authored-manifest.v1.json" \
    "$trusted_root/evidence/cafe/cafe-authored-manifest.v1.json" || fail "candidate authored manifest differs from protected master"

  mkdir -p "$out"
  out="$(cd "$out" && pwd)"
  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/trusted-cafe-candidate.XXXXXXXX")"
  trap 'rm -rf "$work"' EXIT
  cp -a "$candidate_root/game" "$work/game"

  mkdir -p "$out/authored" "$out/runtime" "$out/logs" "$out/trust-root"
  cp "$trusted_root/evidence/cafe/cafe-authored-ids.v1.json" \
    "$out/authored/cafe-authored-ids.v1.json"
  cmp -s "$authored_input" \
    "$trusted_root/evidence/cafe/cafe-authored-manifest.v1.json" || \
    fail "precompiled authored manifest differs from protected master"
  cp "$authored_input" "$out/authored/cafe-authored-manifest.v1.json"
  cp "$lock" "$out/runtime/runtime-lock.v1.json"
  cp "$runtime_receipt" "$out/runtime/runtime-build-receipt.json"
  for rel in \
    .github/workflows/trusted-cafe-attestation.yml \
    evidence/cafe/runtime-lock.v1.json \
    tools/cafe_attestation_selftest.py \
    tools/cafe_authored_manifest.py \
    tools/trusted_cafe_capture.sh \
    tools/verify_cafe_attested_evidence.py \
    tools/vg_shoot.sh; do
    mkdir -p "$out/trust-root/$(dirname "$rel")"
    cp "$trusted_root/$rel" "$out/trust-root/$rel"
  done

  mapfile -t versions < <(python -B - "$lock" "$runtime_receipt" "$runtime_archive_sha" <<'PY'
import hashlib, json, re, sys
lock_path, receipt_path, archive_sha = sys.argv[1:]
lock = json.load(open(lock_path, encoding="utf-8"))
receipt = json.load(open(receipt_path, encoding="utf-8"))
lock_sha = hashlib.sha256(open(lock_path, "rb").read()).hexdigest()
assert receipt["schema"] == "living-town.cafe-runtime-build-receipt.v1"
assert receipt["lock_sha256"] == lock_sha
assert receipt["runtime_archive_sha256"] == archive_sha
assert receipt["first_archive_sha256"] == archive_sha == receipt["second_archive_sha256"]
assert receipt["reproducible"] is True
for key in ("python", "pillow", "godot"):
    assert receipt[key] == lock["versions"][key]
assert receipt["validation_image"] == lock["validation_image"]["reference"]
assert receipt["oci_toolchain_image"] == lock["oci_toolchain"]["podman_image"]
assert receipt["skopeo_image"] == lock["oci_toolchain"]["skopeo_image"]
assert receipt["podman"] == lock["oci_toolchain"]["versions"]["podman"]
assert receipt["skopeo"] == lock["oci_toolchain"]["versions"]["skopeo"]
assert receipt["toolchain_tar"] == lock["oci_toolchain"]["versions"]["tar"]
assert receipt["toolchain_python"] == lock["oci_toolchain"]["versions"]["python"]
assert receipt["toolchain_sha256sum"] == lock["oci_toolchain"]["versions"]["sha256sum"]
assert re.fullmatch(r"[0-9a-f]{64}", receipt["validation_oci_manifest_digest"])
assert receipt["container_platform"] == lock["validation_image"]["platform"]
assert receipt["container_network"] == "none"
assert receipt["container_read_only"] is True
assert receipt["container_cap_drop"] == "ALL"
assert receipt["container_no_new_privileges"] is True
print(lock["versions"]["python"])
print(lock["versions"]["pillow"])
print(lock["versions"]["godot"])
PY
  )
  [ "${#versions[@]}" -eq 3 ] || fail "runtime receipt validation failed"
  [ "$(python -B -c 'import platform; print(platform.python_version())')" = "${versions[0]}" ] || fail "Python runtime drift"
  [ "$(python -B -c 'import PIL; print(PIL.__version__)')" = "${versions[1]}" ] || fail "Pillow runtime drift"
  local godot_bin="${GODOT:-godot}"
  [ "$("$godot_bin" --version)" = "${versions[2]}" ] || fail "Godot runtime drift"
  [ "$(sha256_file "$(command -v "$godot_bin")")" = \
    "$(python -B -c 'import json,sys; print(json.load(open(sys.argv[1]))["godot"]["binary_sha256"])' "$lock")" ] || \
    fail "Godot binary drift"

  export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
  export VG_GODOT_LOG="$out/logs/godot-capture.log"
  : >"$VG_GODOT_LOG"
  local GBIN="$godot_bin"
  # shellcheck source=tools/vg_shoot.sh
  . "$trusted_root/tools/vg_shoot.sh"
  "$godot_bin" --headless --path "$work/game" --import \
    >"$out/logs/godot-import.log" 2>&1

  capture_viewport() (
    local width="$1" height="$2" display="$3" viewport="${1}x${2}"
    local directory="$out/$viewport"
    mkdir -p "$directory"
    Xvfb "$display" -screen 0 "${width}x${height}x24" -nolisten tcp \
      >"$out/logs/xvfb-$viewport.log" 2>&1 &
    local xv=$!
    trap 'kill "$xv" 2>/dev/null || true' EXIT
    local ready=0
    for _ in $(seq 1 50); do
      if [ -S "/tmp/.X11-unix/X${display#:}" ]; then ready=1; break; fi
      kill -0 "$xv" 2>/dev/null || fail "Xvfb exited for $viewport"
      sleep 0.1
    done
    [ "$ready" -eq 1 ] || fail "Xvfb did not become ready for $viewport"
    export DISPLAY="$display"

    local slot floor mode filename
    local -a draw_skip
    for slot in cafe_1f_normal cafe_1f_bare cafe_2f_normal cafe_2f_bare; do
      case "$slot" in
        cafe_1f_normal) floor=1f; mode=normal; filename=vg_int_cafe.png ;;
        cafe_1f_bare) floor=1f; mode=bare; filename=vg_cafe1f_bare.png ;;
        cafe_2f_normal) floor=2f; mode=normal; filename=vg_cafe2f.png ;;
        cafe_2f_bare) floor=2f; mode=bare; filename=vg_cafe2f_bare.png ;;
      esac
      draw_skip=()
      [ "$mode" = normal ] || draw_skip=(--draw-skip interior_furniture)
      vg_shoot "$directory/$filename" \
        --path "$work/game" \
        --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
        --resolution "$viewport" --single-window -- \
        --backend logic --seed 3 --warmup-tick 600 \
        --probe-space cafe --probe-floor "$floor" --shot-fit \
        "${draw_skip[@]}" --shot "$directory/$filename"
    done
    kill "$xv" 2>/dev/null || true
    wait "$xv" 2>/dev/null || true
    trap - EXIT

    python -B - "$directory" "$viewport" "$repository" "$candidate_sha" "$candidate_tree" \
      "$workflow_sha" "$workflow_tree" "$run_id" "$run_attempt" \
      "$out/authored/cafe-authored-manifest.v1.json" <<'PY'
import hashlib, json, os, stat, sys, tempfile
from PIL import Image
(root, viewport, repository, candidate_sha, candidate_tree, workflow_sha,
 workflow_tree, run_id, run_attempt, authored_path) = sys.argv[1:]
width, height = map(int, viewport.split("x"))
authored = json.load(open(authored_path, encoding="utf-8"))
bindings = {item["floor"]: item["authored_binding_sha256"] for item in authored["floors"]}
slots = [
    ("cafe_1f_normal", "vg_int_cafe.png", "1f", "normal", "none"),
    ("cafe_1f_bare", "vg_cafe1f_bare.png", "1f", "bare", "interior_furniture"),
    ("cafe_2f_normal", "vg_cafe2f.png", "2f", "normal", "none"),
    ("cafe_2f_bare", "vg_cafe2f_bare.png", "2f", "bare", "interior_furniture"),
]
context = [repository, candidate_sha, candidate_tree, workflow_sha, workflow_tree, run_id, run_attempt, viewport]
session = hashlib.sha256("\0".join(context).encode("ascii")).hexdigest()
captures = []
for slot, filename, floor, mode, draw_skip in slots:
    path = os.path.join(root, filename)
    with Image.open(path) as image:
        if image.format != "PNG" or image.size != (width, height):
            raise SystemExit(f"invalid PNG geometry: {path}")
        image.verify()
    data = open(path, "rb").read()
    argv = [
        "godot", "--path", "<candidate-game-copy>", "--display-driver", "x11",
        "--rendering-driver", "opengl3", "--audio-driver", "Dummy", "--resolution",
        viewport, "--single-window", "--", "--backend", "logic", "--seed", "3",
        "--warmup-tick", "600", "--probe-space", "cafe", "--probe-floor", floor,
        "--shot-fit",
    ]
    if mode == "bare": argv += ["--draw-skip", "interior_furniture"]
    argv += ["--shot", f"<output>/{viewport}/{filename}"]
    binding = bindings[floor]
    captures.append({
        "slot": slot, "file": filename, "floor": floor, "mode": mode,
        "draw_skip": draw_skip, "width": width, "height": height, "seed": 3,
        "tick": 600,
        "pair_id": hashlib.sha256(f"{session}\0{floor}\0{binding}".encode("ascii")).hexdigest(),
        "authored_binding_sha256": binding, "argv": argv,
        "argv_sha256": hashlib.sha256(json.dumps(argv, separators=(",", ":"), ensure_ascii=True).encode("ascii")).hexdigest(),
        "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
    })
if any(captures[i]["sha256"] == captures[i+1]["sha256"] for i in (0, 2)):
    raise SystemExit("normal/bare substitution detected")
receipt = {
    "schema": "living-town.trusted-cafe-capture-receipt.v1",
    "repository": repository, "candidate_sha": candidate_sha, "candidate_tree": candidate_tree,
    "workflow_sha": workflow_sha, "workflow_tree": workflow_tree,
    "run_id": run_id, "run_attempt": run_attempt, "viewport": viewport,
    "session": session, "captures": captures,
}
data = (json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n").encode("ascii")
fd, tmp = tempfile.mkstemp(prefix=".capture-receipt-", dir=root)
with os.fdopen(fd, "wb") as f: f.write(data)
os.replace(tmp, os.path.join(root, "cafe-capture-receipt.json"))
PY
  )

  capture_viewport 1280 768 :95
  capture_viewport 320 192 :96
  local runtime_errors
  runtime_errors="$(grep -aEic 'SCRIPT ERROR|signal 11|segmentation fault|fatal error|out of bounds' \
    "$out/logs/godot-capture.log" || true)"
  [ "$runtime_errors" -eq 0 ] || fail "runtime error markers: $runtime_errors"

  python -B - "$out" "$repository" "$candidate_sha" "$candidate_tree" "$workflow_sha" \
    "$workflow_tree" "$run_id" "$run_attempt" "$runtime_archive_sha" "$trusted_root" <<'PY'
import hashlib, json, os, sys, tempfile
(out, repository, candidate_sha, candidate_tree, workflow_sha, workflow_tree,
 run_id, run_attempt, runtime_archive_sha, trusted) = sys.argv[1:]
def digest(path): return hashlib.sha256(open(path, "rb").read()).hexdigest()
receipts = []
for viewport in ("1280x768", "320x192"):
    rel = f"{viewport}/cafe-capture-receipt.json"
    receipts.append({"path": rel, "sha256": digest(os.path.join(out, rel)), "viewport": viewport})
transcript = {
    "schema": "living-town.trusted-cafe-capture-transcript.v1",
    "repository": repository, "candidate_sha": candidate_sha, "candidate_tree": candidate_tree,
    "workflow_sha": workflow_sha, "workflow_tree": workflow_tree,
    "run_id": run_id, "run_attempt": run_attempt, "frame_count": 8, "receipts": receipts,
}
open(os.path.join(out, "capture-transcript.json"), "wb").write(
    (json.dumps(transcript, sort_keys=True, separators=(",", ":")) + "\n").encode("ascii"))
authored = json.load(open(os.path.join(out, "authored/cafe-authored-manifest.v1.json"), encoding="utf-8"))
runtime_lock_path = os.path.join(out, "runtime/runtime-lock.v1.json")
runtime_receipt = json.load(open(os.path.join(out, "runtime/runtime-build-receipt.json"), encoding="utf-8"))
tool_paths = [
    ".github/workflows/trusted-cafe-attestation.yml", "evidence/cafe/runtime-lock.v1.json",
    "tools/cafe_attestation_selftest.py", "tools/cafe_authored_manifest.py",
    "tools/trusted_cafe_capture.sh", "tools/verify_cafe_attested_evidence.py", "tools/vg_shoot.sh",
]
tools = [{"authority": "protected-master", "path": p, "sha256": digest(os.path.join(trusted, p))} for p in tool_paths]
expected_payloads = sorted([
    "authored/cafe-authored-ids.v1.json",
    "authored/cafe-authored-manifest.v1.json",
    "capture-transcript.json",
    "logs/godot-capture.log",
    "logs/godot-import.log",
    "logs/xvfb-1280x768.log",
    "logs/xvfb-320x192.log",
    "runtime/runtime-build-receipt.json",
    "runtime/runtime-lock.v1.json",
    *[f"trust-root/{path}" for path in tool_paths],
    *[
        f"{viewport}/{filename}"
        for viewport in ("1280x768", "320x192")
        for filename in ("vg_int_cafe.png", "vg_cafe1f_bare.png", "vg_cafe2f.png", "vg_cafe2f_bare.png")
    ],
    *[f"{viewport}/cafe-capture-receipt.json" for viewport in ("1280x768", "320x192")],
])
actual_payloads = sorted(
    os.path.relpath(os.path.join(root, name), out).replace(os.sep, "/")
    for root, dirs, files in os.walk(out)
    for name in sorted(files)
)
if actual_payloads != expected_payloads:
    raise SystemExit(
        f"capture payload allowlist mismatch: expected={expected_payloads!r} actual={actual_payloads!r}"
    )
payloads = []
for rel in expected_payloads:
    path = os.path.join(out, *rel.split("/"))
    metadata = os.lstat(path)
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
        raise SystemExit(f"capture payload is not a unique regular file: {rel}")
    payloads.append({"path": rel, "sha256": digest(path), "bytes": metadata.st_size})
manifest = {
    "schema": "living-town.trusted-cafe-evidence.v1", "repository": repository,
    "candidate": {"sha": candidate_sha, "tree": candidate_tree},
    "workflow": {"sha": workflow_sha, "tree": workflow_tree,
                 "path": ".github/workflows/trusted-cafe-attestation.yml",
                 "ref": f"{repository}/.github/workflows/trusted-cafe-attestation.yml@refs/heads/master"},
    "run": {"id": run_id, "attempt": run_attempt},
    "runtime": {"lock_sha256": digest(runtime_lock_path), "archive_sha256": runtime_archive_sha,
                "oci_manifest_digest": runtime_receipt["oci_manifest_digest"],
                "python": runtime_receipt["python"], "pillow": runtime_receipt["pillow"],
                "godot": runtime_receipt["godot"]},
    "authored": {"ids_sha256": digest(os.path.join(out, "authored/cafe-authored-ids.v1.json")),
                 "manifest_sha256": digest(os.path.join(out, "authored/cafe-authored-manifest.v1.json")),
                 "render_closure_sha256": authored["render_closure_sha256"],
                 "game_tree_git_oid": authored["game_tree_git_oid"]},
    "capture_contract": {"space": "cafe", "viewports": ["1280x768", "320x192"],
                         "seed": 3, "tick": 600, "renderer": "opengl3", "display": "x11/Xvfb",
                         "audio": "Dummy", "slots": ["cafe_1f_normal", "cafe_1f_bare",
                         "cafe_2f_normal", "cafe_2f_bare"], "frames": 8},
    "tools": tools, "payloads": payloads, "evidence_only": True,
    "does_not_authorize": ["canon", "collision", "navigation", "pixels", "portals",
                            "replay", "save", "simulation", "view"],
}
data = (json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n").encode("ascii")
fd, tmp = tempfile.mkstemp(prefix=".evidence-manifest-", dir=out)
with os.fdopen(fd, "wb") as f: f.write(data)
os.replace(tmp, os.path.join(out, "trusted-cafe-manifest.json"))
PY

  local first_bundle second_bundle
  first_bundle="$(dirname "$out")/.trusted-cafe-evidence.first.$$.tar.gz"
  second_bundle="$(dirname "$out")/.trusted-cafe-evidence.second.$$.tar.gz"
  trap 'rm -rf "$work"; rm -f "$first_bundle" "$second_bundle"' EXIT
  write_evidence_bundle() {
    python -B - "$out" "$1" <<'PY'
import gzip, io, os, pathlib, stat, sys, tarfile
root, destination = map(pathlib.Path, sys.argv[1:])
tool_paths = [
    ".github/workflows/trusted-cafe-attestation.yml", "evidence/cafe/runtime-lock.v1.json",
    "tools/cafe_attestation_selftest.py", "tools/cafe_authored_manifest.py",
    "tools/trusted_cafe_capture.sh", "tools/verify_cafe_attested_evidence.py", "tools/vg_shoot.sh",
]
expected = sorted([
    "authored/cafe-authored-ids.v1.json",
    "authored/cafe-authored-manifest.v1.json",
    "capture-transcript.json",
    "logs/godot-capture.log",
    "logs/godot-import.log",
    "logs/xvfb-1280x768.log",
    "logs/xvfb-320x192.log",
    "runtime/runtime-build-receipt.json",
    "runtime/runtime-lock.v1.json",
    *[f"trust-root/{path}" for path in tool_paths],
    *[
        f"{viewport}/{filename}"
        for viewport in ("1280x768", "320x192")
        for filename in ("vg_int_cafe.png", "vg_cafe1f_bare.png", "vg_cafe2f.png", "vg_cafe2f_bare.png")
    ],
    *[f"{viewport}/cafe-capture-receipt.json" for viewport in ("1280x768", "320x192")],
    "trusted-cafe-manifest.json",
])
actual = sorted(path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file())
if actual != expected:
    raise SystemExit(f"bundle member allowlist mismatch: expected={expected!r} actual={actual!r}")
with destination.open("wb") as raw:
    with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0, compresslevel=9) as compressed:
        with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
            for rel in expected:
                path = root.joinpath(*rel.split("/"))
                metadata = path.lstat()
                if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
                    raise SystemExit(f"bundle member is not a unique regular file: {rel}")
                data = path.read_bytes()
                info = tarfile.TarInfo(rel)
                info.size = len(data); info.mtime = 0; info.mode = 0o644
                info.uid = info.gid = 0; info.uname = info.gname = ""
                archive.addfile(info, io.BytesIO(data))
PY
  }
  write_evidence_bundle "$first_bundle"
  write_evidence_bundle "$second_bundle"
  [ "$(sha256_file "$first_bundle")" = "$(sha256_file "$second_bundle")" ] || \
    fail "evidence bundle assembly is not deterministic"
  mv "$first_bundle" "$out/trusted-cafe-evidence.tar.gz"
  rm -f "$second_bundle"
  rm -rf "$work"
  trap - EXIT
  printf 'TRUSTED_CAFE_CAPTURE PASS candidate=%s tree=%s bundle_sha256=%s\n' \
    "$candidate_sha" "$candidate_tree" "$(sha256_file "$out/trusted-cafe-evidence.tar.gz")"
}

[ "$#" -ge 1 ] || usage
mode="$1"; shift
case "$mode" in
  build-runtime) build_runtime "$@" ;;
  capture) capture "$@" ;;
  *) usage ;;
esac
