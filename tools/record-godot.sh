#!/usr/bin/env bash
# record-godot.sh — 在容器内用 Xvfb + opengl3(软件渲染) + ffmpeg x11grab 录制 Main 场景，**带声音**。
# 配方照搬 22nd 的 verifier/replay.py。用法（容器内）：
#   bash /tools/record-godot.sh [秒数=135] [seed=20260626] [speed=3.0] [输出=/out/town_raw.mp4]
#
# ══ C4 改了两件事，两件都是"工具链在说谎" ═════════════════════════════════════
#
# ── ① 录得到声音（C2 的配方，docs/43 §1.2c 末尾）─────────────────────────────
# 容器里**没有声卡**，也**不要装 PulseAudio**。`--audio-driver Dummy` 保留不动——哑驱动**仍在推进混音**，
# headless 采集正是靠这个。`game/scripts/Audio.gd` 自带 `--audiocap <wav> <秒>` 钩子：在 Master 总线挂
# `AudioEffectRecord`，到点存 WAV 并 `get_tree().quit()`。
# ⇒ 因此**不能再 `kill $GODOT_PID`**：ffmpeg 在第 SECS 秒收工，而音频钩子要更晚才落盘，杀早了 WAV 是空的。
#
# ── ② ★ 原来的 `sleep 3` 远远不够，每一段录屏的开头都是【引擎启动闪屏】────────
# 实测（gamecraft-runner:4.6.2，软件渲染）：从 `godot` 拉起到游戏画面出现要 **8.3–10.4 秒**，而且随负载浮动。
# 原脚本 `sleep 3` 之后就起 ffmpeg ⇒ **前 5-7 秒录的是 Godot 的启动闪屏**（1280×768 帧里
# (36,36,36) 占 96.1%，第二色 (253,253,253) 就是 Godot logo）。
# **这不是推断，仓库里已经发的片子就是这样**：`docs/media/town_chronicle_demo.mp4` 的 t=0/0.5/1/2/3s
# 五帧全是同一张闪屏，到 t=5s 才出现草地。README 主图 GIF 正是从这段素材来的。
# 修法不是把 sleep 调大（它随机器浮动，调多少都是赌），而是**等到画面真的不是闪屏为止**：
# 把当前帧缩成 40×24 灰度，量"众数灰阶占比"——闪屏是一块平色 ⇒ 72.6%（实测 0.9s→9.0s 恒定），
# 游戏画面 ⇒ **4.1%–11.8%**。阈值取 40%，两边都有 3 倍以上余量。超时则退回固定 sleep，不会挂死。
#
# ── 对齐不是"减 3 秒"，是量出来的 ────────────────────────────────────────────
# 音频时间轴的 0 点是 `Audio._ready()`（= 上面的 BOOT），视频时间轴的 0 点是 ffmpeg 起录时刻 R。
# 两者相差 `R - BOOT`（= 就绪检测的滞后），写死 `-ss 3` 会稳定错 BOOT 秒。
# godot 是被音频钩子自己终止的、WAV 落盘时刻就是钩子触发时刻 ⇒ `BOOT = (mtime(WAV) - T0) - AUDSECS`，
# 于是 `TRIM = (R - T0) - BOOT`。全部用脚本已有的墙钟算，不需要引擎配合。
#
# ── 开关 ────────────────────────────────────────────────────────────────────
#   REC_AUDIO=1|0     默认 1。设 0 回到纯视频（出事时的退路；就绪等待仍然生效）。
#   REC_READY=1|0     默认 1。设 0 回到从前写死的 `sleep $REC_PRE`（复现旧行为用）。
#   REC_PRE=3         REC_READY=0 时的固定等待；REC_READY=1 时作为**最短**等待
#   REC_READY_MAX=45  就绪等待上限（秒），到点就按超时处理并继续
#   REC_FLAT=40       "还在闪屏"的判据：40×24 灰度帧里众数灰阶占比 ≥ 这个百分比
#   REC_APAD=4        音频比视频多录的余量秒数
set -uo pipefail
SECS="${1:-135}"; SEED="${2:-20260626}"; SPEED="${3:-3.0}"; OUT="${4:-/out/town_raw.mp4}"; BACKEND="${5:-logic}"; ENDPOINT="${6:-}"; SCENARIO="${7:-}"
W=1280; H=768; FPS=30; DISP=:77
REC_AUDIO="${REC_AUDIO:-1}"; REC_READY="${REC_READY:-1}"; PRE="${REC_PRE:-3}"
READY_MAX="${REC_READY_MAX:-45}"; FLAT="${REC_FLAT:-40}"; APAD="${REC_APAD:-4}"
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
EP_ARG=""; [ -n "$ENDPOINT" ] && EP_ARG="--endpoint $ENDPOINT"   # backend=llm 时连宿主 LM Studio
SC_ARG=""; [ -n "$SCENARIO" ] && SC_ARG="--scenario $SCENARIO"   # S3 定向场景

BASE="${OUT%.*}"
WAV="${BASE}_audio.wav"
VID="${BASE}_mute.mp4"            # 先落无声视频，混流后才产出 $OUT
AUD_ARG=""; AUDSECS=0
if [ "$REC_AUDIO" = "1" ]; then
  AUDSECS=$(awk "BEGIN{print $SECS + $APAD}")
  AUD_ARG="--audiocap $WAV $AUDSECS"
  rm -f "$WAV"
else
  VID="$OUT"                      # 纯视频路径：直接录到最终位置
fi

Xvfb $DISP -screen 0 ${W}x${H}x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
XVFB_PID=$!
sleep 1.5
export DISPLAY=$DISP

T0=$(date +%s.%N)
godot --path /game --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
  --resolution ${W}x${H} --single-window -- --seed "$SEED" --speed "$SPEED" --backend "$BACKEND" $EP_ARG $SC_ARG $AUD_ARG >/tmp/godot.log 2>&1 &
GODOT_PID=$!

# ── 等到画面不再是启动闪屏 ─────────────────────────────────────────────────
# 判据是"这一帧有多平"：闪屏是一块平色，游戏画面不是。缩到 40×24 是为了让这个探针足够便宜
# （每次 ~0.6s），同时保留足够的空间频率来区分两者。
flat_pct() {
  ffmpeg -v error -draw_mouse 0 -f x11grab -video_size ${W}x${H} -i $DISP -frames:v 1 \
    -vf scale=40:24 -pix_fmt gray -f rawvideo - 2>/dev/null \
  | od -An -tu1 -v | tr -s ' ' '\n' | grep -v '^$' \
  | sort -n | uniq -c | sort -rn | awk 'NR==1{m=$1} {n+=$1} END{if(n>0) printf "%.1f", 100.0*m/n; else print "100.0"}'
}
sleep "$PRE"
READY_NOTE="fixed sleep ${PRE}s"
if [ "$REC_READY" = "1" ]; then
  READY_NOTE="timeout ${READY_MAX}s"
  while :; do
    NOW=$(awk "BEGIN{printf \"%.2f\", $(date +%s.%N) - $T0}")
    if awk "BEGIN{exit !($NOW > $READY_MAX)}"; then
      echo "  WARN: 等了 ${NOW}s 画面仍像闪屏，按超时继续（片头可能带闪屏）"; break
    fi
    if ! kill -0 "$GODOT_PID" 2>/dev/null; then
      echo "  WARN: godot 在就绪之前就退出了"; break
    fi
    P=$(flat_pct)
    if awk "BEGIN{exit !($P < $FLAT)}"; then
      READY_NOTE="detected at ${NOW}s (flat=${P}% < ${FLAT}%)"; break
    fi
  done
fi
T_REC=$(date +%s.%N)
echo "  ready: $READY_NOTE"

# -draw_mouse 0：x11grab 默认【会把 X11 根光标画进每一帧】。Xvfb 的根光标停在屏幕正中 (640,384)，
# 于是本波发布的 town_chronicle.gif / wavec_town_noon.png / wavec_town_night.png / town_wavec_demo.mp4
# 全部在广场正中带着一个黑色光标（实测：发布 PNG 在该 30×30 框内有 32 个纯黑像素，--shot 渲染是 0）。
# 外部评审 2026-07-26 抓到。C4 审过这一行并修好了开头闪屏，但没看见光标——因为它只量"众数灰阶占比"。
ffmpeg -y -draw_mouse 0 -f x11grab -framerate $FPS -video_size ${W}x${H} -i $DISP -t "$SECS" \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p "$VID" >/tmp/ffmpeg.log 2>&1
RC=$?

TRIM=0; WLEN=0
if [ "$REC_AUDIO" = "1" ]; then
  # 等音频钩子自己收工（**不 kill**）。设上限，免得钩子没生效时脚本永久挂住。
  DEADLINE=$(awk "BEGIN{print $AUDSECS + $READY_MAX + 30}")
  while kill -0 "$GODOT_PID" 2>/dev/null; do
    sleep 0.5
    if awk "BEGIN{exit !(($(date +%s.%N) - $T0) > $DEADLINE)}"; then
      echo "  WARN: --audiocap 超时未退出，强杀"; kill "$GODOT_PID" 2>/dev/null || true; break
    fi
  done
  if [ -s "$WAV" ]; then
    # ★ 用 WAV 的【实测时长】而不是请求的 AUDSECS 来回推起点。
    #   实测 `--audiocap ... 24` 吐出来的是 **25.356s**（4s→5.57s、10s→10.96s，多出 0.96–1.57s 且不恒定）——
    #   `AudioEffectRecord` 从 `_ready()` 就在录，而定时器按进程帧计时，启动帧的抖动全落在这个差里。
    #   拿 AUDSECS 当时长会稳定错约 1.4 秒；拿实测时长则把这项误差整个消掉。
    WLEN=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WAV" 2>/dev/null || echo 0)
    TW=$(stat -c %.3Y "$WAV" 2>/dev/null || stat -c %Y "$WAV")
    A0=$(awk "BEGIN{printf \"%.3f\", ($TW-$T0)-$WLEN}")     # 音频时间轴 0 点（相对 T0）
    TRIM=$(awk "BEGIN{t=($T_REC-$T0)-$A0; if(t<0)t=0; printf \"%.3f\", t}")
    echo "  audio: audio_t0=+${A0}s  rec_start=+$(awk "BEGIN{printf \"%.3f\", $T_REC-$T0}")s  wav=${WLEN}s (asked ${AUDSECS}s)  => TRIM=${TRIM}s"
  fi
else
  kill "$GODOT_PID" 2>/dev/null || true
fi
kill $XVFB_PID 2>/dev/null || true
sleep 0.3

if [ $RC -ne 0 ] || [ ! -s "$VID" ]; then
  echo "RECORD FAILED rc=$RC"; echo "--- godot.log tail ---"; tail -20 /tmp/godot.log; echo "--- ffmpeg.log tail ---"; tail -20 /tmp/ffmpeg.log; exit 1
fi

if [ "$REC_AUDIO" = "1" ]; then
  if [ -s "$WAV" ]; then
    awk "BEGIN{exit !(($WLEN - $TRIM) < $SECS - 0.5)}" && \
      echo "  WARN: 裁掉 ${TRIM}s 后音频只剩 $(awk "BEGIN{printf \"%.1f\", $WLEN-$TRIM}")s < 视频 ${SECS}s —— -shortest 会截掉视频尾巴，调大 REC_APAD"
    # -ss 在第二个 -i 之前 ⇒ 只裁音频；-c:v copy ⇒ 视频一帧不重编码
    ffmpeg -y -i "$VID" -ss "$TRIM" -i "$WAV" -c:v copy -c:a aac -b:a 128k -shortest "$OUT" >/tmp/ffmpeg_mux.log 2>&1
    if [ $? -eq 0 ] && [ -s "$OUT" ]; then
      rm -f "$VID"
    else
      echo "  WARN: 混流失败，保留无声视频"; tail -20 /tmp/ffmpeg_mux.log; mv -f "$VID" "$OUT"
    fi
  else
    echo "  WARN: 没拿到 $WAV（Audio autoload 没起来？），退回无声视频"; mv -f "$VID" "$OUT"
  fi
fi

echo "wrote $OUT"; ls -la "$OUT"
[ -s "$WAV" ] && ls -la "$WAV"
ffprobe -v error -show_entries stream=codec_type,codec_name,width,height,duration -of default=nw=1 "$OUT" 2>/dev/null || true
