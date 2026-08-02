#!/bin/sh
# AA1 · 金标对 k 的覆盖【靠几个 seed】？
# 由来：k=1.1..1.85 八档全破金标，而**每一档移动的都只有 seed 8 一个**。
#   ⇒ 那条覆盖是"12 个 seed 里恰好抽中了一个探测器"。它有多脆，只有把非金标 seed 也跑一遍才知道。
#   这是 Y1「金标 12/12 不动 ≠ N=12 不动」那条更正的**镜像**：不动是抽样，动同样是抽样。
# 两侧同一批 seed（13-30，Y1 的留出段），只换 utility.obj_survival_pull。不传 --golden（金标没烘这些 seed）。
GODOT="C:/Users/yp/AppData/Local/Programs/Godot/4.6.2-stable/Godot_v4.6.2-stable_win64_console.exe"
SP="$1"
OUT="$2"
mkdir -p "$OUT"
for arm in kbase k1_50; do
  (
    cd "$SP/$arm" || exit 1
    "$GODOT" --headless --path game --script res://bench/Harness.gd -- \
      --seeds 13-30 --days 60 --det 1 \
      > "$OUT/heldout_$arm.txt" 2>&1
    echo "rc=$? arm=$arm" >> "$OUT/heldout.rc"
  ) &
done
wait
echo "=== kheldout done ==="
