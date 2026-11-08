#!/usr/bin/env bash
set -euo pipefail

GV="${1:?Godot release tag required}"

# Release binaries live in godot-builds. Retry transient HTTP failures (including
# 504), but cap both each transfer and the retry window so setup cannot hang.
curl --fail --location --show-error \
  --retry 3 --retry-delay 2 --retry-max-time 180 \
  --connect-timeout 15 --max-time 120 \
  --output godot.zip \
  "https://github.com/godotengine/godot-builds/releases/download/${GV}/Godot_v${GV}_linux.x86_64.zip"

# Keep corrupt or truncated downloads from reaching either installation path.
unzip -tq godot.zip
