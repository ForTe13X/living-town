#!/usr/bin/env bash
# V2：等后台扫描推进的小工具（本仓库禁止杀进程，只能等）。
# 用法：bash analysis/v2/wait.sh <目标 chunk 数> <最多等多少个 10 秒>
set -u
TARGET="${1:-100}"
MAX="${2:-50}"
i=0
while [ "$i" -lt "$MAX" ]; do
  n=$(grep -c '^\[' analysis/v2/sweep_main.txt 2>/dev/null || echo 0)
  if [ "$n" -ge "$TARGET" ]; then break; fi
  command sleep 10
  i=$((i+1))
done
date
echo "main: $(grep -c '^\[' analysis/v2/sweep_main.txt)/144  $(tail -1 analysis/v2/sweep_main.txt)"
echo "deep: $(tail -1 analysis/v2/sweep_deep.txt)"
cat analysis/v2/cost_ab.txt
