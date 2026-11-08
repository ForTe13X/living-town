#!/usr/bin/env bash
set -euo pipefail

GV="${1:?Godot release tag required}"
if [[ "$GV" != "4.6.2-stable" ]]; then
  echo "Unsupported Godot release: $GV (expected 4.6.2-stable)" >&2
  exit 2
fi

# Use the Linux x86_64 link published on the official 4.6.2 archive page;
# GitHub release asset routes can return 504 on hosted runners.
# Retry transient failures, with limits on each transfer and the retry window.
curl --fail --location --show-error \
  --retry 3 --retry-delay 2 --retry-max-time 180 \
  --connect-timeout 15 --max-time 120 \
  --output godot.zip \
  "https://downloads.godotengine.org/?version=${GV%-stable}&flavor=stable&platform=linux.64&slug=linux.x86_64.zip"

# Keep corrupt or truncated downloads from reaching either installation path.
unzip -tq godot.zip
