#!/usr/bin/env bash
# v2 隔离副本 —— v1 有一个把整个实验作废的泄漏，这里修它。
#
# **v1 错在哪**：我把变异 brief `cp` 到一份 `git clone` 的工作区上。
#   于是 `git status` 显示 ` M docs/71-…`，`git diff` **一次性交出全部 10 条注入**。
#   A1 的棒第一件事就是跑 `git status`，然后逐条列出「注入整齐地落在 5 个层各 2 条」。
#   ⇒ 它不是"发现"了注入，是**被递了答案**。v1 的四臂全部作废。
#
# **v2 的做法**：`git archive` 出一份无历史的快照 → 覆盖 brief → `git init` 重新做成一次 import commit。
#   `git status` 干净、`git diff` 为空、`git grep` 可用。
#   ⚠ 代价（必须写进局限）：`git log -S` 在这些副本里查不到东西了（只有一个 import commit）。
#     契约 §1.5 那条"看到零引用先 git log -S"在 v2 的棒身上结构上不可用。
set -eu
REPO="$1"; OUT="$2"
mk () {  # mk <arm> <被替换的 docs 文件> <变异 brief 或 ->
  local arm="$1" target="$2" src="$3" d="$OUT/iso2_$1"
  rm -rf "$d"; mkdir -p "$d"
  git -C "$REPO" archive HEAD | tar -x -C "$d"
  [ "$src" = "-" ] || cp "$src" "$d/$target"
  git -C "$d" init -q
  git -C "$d" add -A
  git -C "$d" -c user.email=lt@local -c user.name=lt commit -q -m "chore: import living-town snapshot"
  echo "iso2_$arm  status=[$(git -C "$d" status --porcelain | wc -l) 处改动]  commits=$(git -C "$d" rev-list --count HEAD)"
}
mk A1 docs/71-wave-s-plan.md "$OUT/A1.md"
mk A2 docs/64-wave-q-plan.md "$OUT/A2.md"
mk A3 docs/47-wave-e-plan.md "$OUT/A3.md"
mk B1 docs/71-wave-s-plan.md "$OUT/B1.md"
mk C1 docs/64-wave-q-plan.md "$OUT/C1.md"
mk D0 docs/71-wave-s-plan.md -
