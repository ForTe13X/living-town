#!/usr/bin/env bash
# 为每个实验臂建一份隔离副本（docs/75 §二 硬要求 4：不许污染出货树）
# --shared 克隆：对象库走 alternates，2 秒 / 160MB，git log -S 与 git grep 都可用（已验）
set -eu
REPO="$1"; OUT="$2"
mk () {  # mk <arm> <被替换的 docs 文件> <变异 brief>
  local arm="$1" target="$2" src="$3"
  rm -rf "$OUT/iso_$arm"
  git -C "$REPO" clone --quiet --local --shared "$REPO" "$OUT/iso_$arm"
  if [ "$src" != "-" ]; then cp "$src" "$OUT/iso_$arm/$target"; fi
  echo "iso_$arm  ->  $target  $( [ "$src" = "-" ] && echo '(未注入)' || echo "<= $(basename "$src")" )"
}
mk A1 docs/71-wave-s-plan.md "$OUT/A1.md"
mk A2 docs/64-wave-q-plan.md "$OUT/A2.md"
mk A3 docs/47-wave-e-plan.md "$OUT/A3.md"
mk B1 docs/71-wave-s-plan.md "$OUT/B1.md"
mk C1 docs/64-wave-q-plan.md "$OUT/C1.md"
mk D0 docs/71-wave-s-plan.md -
