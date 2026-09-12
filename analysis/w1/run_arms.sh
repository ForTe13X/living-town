#!/usr/bin/env bash
# W1：aid 漏斗六臂。写文件再读（`tee | tail` 会吃掉退出码，docs/41）。
set -u
G="C:/Users/yp/.local/bin/godot"
cd "$(dirname "$0")/../.."
run() {  # $1=tag  $2..=额外参数
  local tag="$1"; shift
  "$G" --headless --path game -s res://bench/w1_aid_funnel.gd -- \
      --agents 12 --seeds 1-12 --days 60 "$@" > "analysis/w1/log_${tag}.txt" 2>&1
  echo "${tag} rc=$?" >> analysis/w1/rc.txt
}
run "$@"
