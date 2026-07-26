#!/usr/bin/env bash
# make_gif.sh — 从录屏 mp4 出 README 主图 GIF，**只允许整数倍缩放**。
#
# ── 为什么需要它 ────────────────────────────────────────────────────────────
# `docs/media/town_chronicle.gif` 现在是 **680×408**，素材是 **1280×768** ⇒ 比例 **0.53125×**，
# **非整数**。像素美术在非整数倍缩放下，每个源像素被摊到 0.53 个目标像素上，行与行的取样相位还不一样 ⇒
# 边缘发糊、HUD 文字直接不可读。修法不是换个更好的缩放算法，而是**只走整数倍**：
# 1280×768 的整数因子只有 1 / 2 / 4 ⇒ **1280×768、640×384、320×192**，别的都不行。
# 本脚本把这条**机检**：算出来除不尽就直接拒绝，而不是"尽量接近"。
#
# ── 用法 ────────────────────────────────────────────────────────────────────
#   bash tools/make_gif.sh <in.mp4> <out.gif> [divisor=2] [fps=10] [start=0] [dur=]
#     divisor  1=原尺寸 2=一半 4=四分之一（必须整除源宽高，否则拒绝）
#     start/dur 用来跳过片头 / 只取一段（单位秒）
#   环境变量：
#     GIF_FLAGS=neighbor|area   缩放算法，**默认 area**（divisor=1 时两者都不生效）
#         area    ：N×N 盒式平均。整数倍下这是干净的一次降采样，笔画不会整根消失。
#         neighbor：整数倍下就是"每 N 个像素取 1 个"，**零模糊**——但对 12px 的中文字形来说，
#                   "每两列取一列"会**整根丢掉笔画**。实测（见抬头 ★）眼验直接判它比现状还差，
#                   所以它不是默认值。只在画面里没有小字、纯像素图块时才值得用。
#     GIF_DITHER=bayer|none|sierra2_4a  默认 bayer
#         none 在 1280×768 上实测**又小又清楚**（3.48MB vs bayer 3.87MB），大图优先试 none。
#
# ── ★ 实测推翻了"换成整数倍就能看清 HUD 文字"这个前提 ────────────────────────
# 同一段素材、同一套调色板策略，只变缩放（`docs/media/town_chronicle_demo.mp4` 的 6-16s）：
#   680×408 0.53125× bicubic（复现现状的配方）  4.26 MB   HUD 字：勉强可读
#   640×384 0.5× neighbor                       3.57 MB   HUD 字：**更差**，笔画整根丢失
#   640×384 0.5× area                           3.51 MB   HUD 字：与 680 相当，仍不可读
#   1280×768 1× dither=bayer  6fps×6s           3.87 MB   HUD 字：**完全可读**
#   1280×768 1× dither=none   6fps×6s           3.48 MB   HUD 字：**完全可读**（推荐）
# ⇒ 让 HUD 文字不可读的**不是**重采样相位，是**"12px 的中文字形再砍一半"**。
#   非整数倍确实该修（它还额外引入逐行相位差），但**只修它拿不到"文字可读"**。
#   唯一拿得到的是 divisor=1；把时长/帧率压到 6fps×6s 之后，体积与现状持平（3.48 vs 3.28 MB）。
#   我一开始用"HUD 横带的水平梯度能量"当可读性指标，它给 neighbor 打了 **+42.5%** 的最高分——
#   **那个指标量的是锯齿，不是可读性**，眼验当场推翻。记在这里，免得下一个人再造一遍同样的假指标。
#
# ── 输出 ────────────────────────────────────────────────────────────────────
# 脚本自己把改前/改后的**尺寸与字节数**打出来（docs/41 §6 盲区③：画幅问题只体现在尺寸上）。
set -uo pipefail
IN="${1:?用法: make_gif.sh <in.mp4> <out.gif> [divisor] [fps] [start] [dur]}"
OUT="${2:?缺 out.gif}"
DIV="${3:-2}"; FPS="${4:-10}"; START="${5:-0}"; DUR="${6:-}"
FLAGS="${GIF_FLAGS:-area}"; DITHER="${GIF_DITHER:-bayer}"

command -v ffmpeg >/dev/null 2>&1 || { echo "❌ 没有 ffmpeg"; exit 1; }
[ -s "$IN" ] || { echo "❌ 源不存在: $IN"; exit 1; }

SW=$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of csv=p=0 "$IN")
SH=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$IN")
[ -n "$SW" ] && [ -n "$SH" ] || { echo "❌ 读不出源尺寸"; exit 1; }

# ★ 整数倍红线：除不尽就拒绝，不做"尽量接近"。
if [ $((SW % DIV)) -ne 0 ] || [ $((SH % DIV)) -ne 0 ]; then
  echo "❌ ${SW}x${SH} 除以 $DIV 除不尽 —— 拒绝做非整数倍缩放（这正是现在那张 680x408 的病因）。"
  echo "   ${SW}x${SH} 的合法 divisor："
  for d in 1 2 3 4 5 6 8; do
    [ $((SW % d)) -eq 0 ] && [ $((SH % d)) -eq 0 ] && echo "     $d -> $((SW/d))x$((SH/d))"
  done
  exit 1
fi
DW=$((SW / DIV)); DH=$((SH / DIV))

SS_ARG=""; [ "$START" != "0" ] && SS_ARG="-ss $START"
T_ARG="";  [ -n "$DUR" ] && T_ARG="-t $DUR"

# divisor=1 时不插 scale 滤镜——不缩放永远比"缩放 1 倍"少一次重采样。
if [ "$DIV" = "1" ]; then VF="fps=$FPS"; else VF="fps=$FPS,scale=${DW}:${DH}:flags=${FLAGS}"; fi

PAL="$(dirname "$OUT")/.$(basename "$OUT").palette.png"
# 两遍法：先按整段统计出 256 色调色板，再套用。stats_mode=diff 让调色板偏向"会动的那部分"，
# 对"大片静止草地 + 小块运动 HUD"这种画面比 full 好。
ffmpeg -v error -y $SS_ARG $T_ARG -i "$IN" -vf "$VF,palettegen=stats_mode=diff" "$PAL" || { echo "❌ palettegen 失败"; exit 1; }
case "$DITHER" in
  none) DOPT="dither=none" ;;
  bayer) DOPT="dither=bayer:bayer_scale=5" ;;
  *) DOPT="dither=$DITHER" ;;
esac
ffmpeg -v error -y $SS_ARG $T_ARG -i "$IN" -i "$PAL" \
  -lavfi "$VF[x];[x][1:v]paletteuse=$DOPT" -loop 0 "$OUT" || { echo "❌ paletteuse 失败"; exit 1; }
rm -f "$PAL"

OW=$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of csv=p=0 "$OUT")
OH=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$OUT")
NF=$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of csv=p=0 "$OUT" 2>/dev/null)
SZ=$(wc -c <"$OUT" | tr -d ' ')
if [ "$OW" != "$DW" ] || [ "$OH" != "$DH" ]; then
  echo "❌ 出图尺寸 ${OW}x${OH} != 期望 ${DW}x${DH}"; exit 1
fi
echo "  src  ${SW}x${SH}  $IN"
echo "  out  ${OW}x${OH}  (1/${DIV}, 整数倍 ✅)  fps=$FPS  frames=${NF:-?}  scale_flags=$FLAGS  dither=$DITHER"
echo "  size $SZ B ($(awk "BEGIN{printf \"%.2f\", $SZ/1048576.0}") MB)  -> $OUT"
