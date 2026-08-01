#!/usr/bin/env bash
# 独立复核 docs/73 §一·2-3 的那条：`docs/52@worktree-agent-a0c76a3f96ae5dbcf`
# 指向的文件在【任何分支上】都不存在。S2 说它逐个 git ls-tree 查过；这里独立重跑一次。
# ⚠ 中文文件名会被 git ls-tree 加引号输出，所以 pattern 要容许开头的 `"`。
cd "$1"
n=0; hit=0
for r in $(git branch -a --format='%(refname)'); do
  n=$((n+1))
  if git ls-tree --name-only "$r:docs" 2>/dev/null | grep -qE '^"?52-'; then
    echo "命中: $r"; hit=$((hit+1))
  fi
done
echo "扫了 $n 条 ref；命中 $hit 条"
