#!/usr/bin/env bash
# 隔离臂逐格 chain 同一性核对
cd "E:/Documents/Dev/June/26th/.claude/worktrees/agent-ab28d7dd9fe535470/analysis/q1" || exit 1
TAG="${1:-post}"
for f in ${TAG}_n*_s*.txt; do
  line=$(grep -A 8 'QATT1' "$f" | grep 'chain同')
  iso=$(grep -A 8 'QATT1' "$f" | grep '隔离自证')
  echo "$f | $iso | $line"
done
