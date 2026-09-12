#!/usr/bin/env bash
# 写文件再读（`tee | tail` 会吃掉退出码，docs/41 §四）。
set -u
cd "$(dirname "$0")/../.."
GODOT=C:/Users/yp/.local/bin/godot bash tools/ci.sh > analysis/w1/ci_final.txt 2>&1
echo "ci rc=$?" >> analysis/w1/ci_rc.txt
