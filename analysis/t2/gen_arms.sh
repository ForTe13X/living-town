#!/usr/bin/env bash
# T2 前瞻注入实验 · 生成全部实验臂（一条命令可复现）
# 用法：bash gen_arms.sh <repo> <outdir>
set -eu
REPO="$1"; OUT="$2"
cd "$REPO"
P="python tools/brief_mutate.py"

# ── 主臂（明写"§4 指出 brief 哪里错"）───────────────────────────────────
$P inject --brief docs/71-wave-s-plan.md --out "$OUT/A1.md" --key "$OUT/A1.key.json" --seed 11 --count 12
$P inject --brief docs/64-wave-q-plan.md --out "$OUT/A2.md" --key "$OUT/A2.key.json" --seed 12 --count 12
$P inject --brief docs/47-wave-e-plan.md --out "$OUT/A3.md" --key "$OUT/A3.key.json" --seed 13 --count 12

# ── B1 剂量对照：同一份 brief，注入数减半 ──────────────────────────────
$P inject --brief docs/71-wave-s-plan.md --out "$OUT/B1.md" --key "$OUT/B1.key.json" --seed 14 --count 6

# ── C1 提法对照：与 A2 逐字节同一份变异 brief，只换派棒 prompt 的重心 ──
cp "$OUT/A2.md" "$OUT/C1.md"; cp "$OUT/A2.key.json" "$OUT/C1.key.json"

# ── D0 空白对照：未注入的 docs/71 原件 ─────────────────────────────────
cp docs/71-wave-s-plan.md "$OUT/D0.md"

# ── S2 负对照的复现（先复现再往上加，docs/75 §二 硬要求 5）────────────
$P inject --brief docs/67-wave-r-plan.md --out "$OUT/repro67.md" --key "$OUT/repro67.key.json" \
    --seed 7 --count 10 --legacy
