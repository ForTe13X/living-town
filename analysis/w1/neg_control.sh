#!/usr/bin/env bash
# W1 负对照：隔离副本里把 aid 的三个门退回 B7 之前（AID_NEED_TH 60→30、COMPLEMENT_LOW 50→35），
# 也就是 Harness 注释里"aid=0"那棵树。期望：法定覆盖门变红。
set -u
G="C:/Users/yp/.local/bin/godot"
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
SP="C:/Users/yp/AppData/Local/Temp/claude/E--Documents-Dev-June-26th/4ab4ceee-f2b5-4791-b52a-1f1d70c374f4/scratchpad/w1neg"
rm -rf "$SP"
mkdir -p "$SP"
cp -r "$SRC/game" "$SP/game"
python - "$SP/game/scripts/Sim.gd" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
a = 'const AID_NEED_TH := 60.0'
b = 'const COMPLEMENT_LOW := 50.0'
assert a in s and b in s, "常量串没找到——请以代码为准重取"
s = s.replace(a, 'const AID_NEED_TH := 30.0', 1)
s = s.replace(b, 'const COMPLEMENT_LOW := 35.0', 1)
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("mutated:", p)
PY
"$G" --headless --path "$SP/game" -s res://bench/Harness.gd -- \
    --seeds 1-12 --days 60 --det 0 > "$SRC/analysis/w1/neg_quorum.txt" 2>&1
echo "neg rc=$?" >> "$SRC/analysis/w1/rc.txt"
