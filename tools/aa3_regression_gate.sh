#!/usr/bin/env bash
# aa3_regression_gate.sh — #43「买卖的社会痕迹」观察侧【抗回归门】（AL1，外审 2026-08-06 21:00 P0.③）。
#
# 为什么存在：#43 的负控——natural（真第三方目击者）必绿、vendoronly / buyeronly / partiesonly
#   （witnesses 合成为只剩交易一方/双方自证）必红 hard=[43]——此前只在 docs/112 §四、docs/125 §五 的
#   【手动 census】里各跑过一次，**没有任何机器在守**。外审证伪那是纸门：将来若有人把观察侧判据
#   （Invariants.gd #43 ①臂 `wn_other`）退回「只排商贩」（docs/112 基线，AG2/docs/125 收紧之前），
#   `buyeronly` 会从红变绿，而普通 S0 全绿 ⇒ 谁都不会发现。本门把那 4 例接进 CI，任一例判决与预期
#   不符即判红——**这就是牙**：观察侧退回只排 vendor ⇒ buyeronly 红→绿 ⇒ 本门红 ⇒ 抓住回归。
#
# ⚠ 判据以 census 打印的 `hard_fails` JSON 为准，**不以进程退出码为准**：
#   census 恒 `quit(0)`（它是量具不是门，docs/125 §五），且本机 godot 是 .cmd／sh 包装、
#   GDScript 的 push_error() 不改退出码（ci.sh 抬头明写）。故对每一臂做【四信号】硬化
#   （前三条同 tools/vg_shoot.sh 的思路，第四条是本门的牙）：
#     ① godot 子进程 rc==0                         —— 抓「进程非零退出」（容器/真二进制里 rc 可信，主判据）
#     ② 日志无致命脚本/引擎级错误标记              —— 抓「rc 不可信环境里报了 SCRIPT ERROR 却退 0」
#     ③ 本臂的 [FIXCENSUS] 行确实打出来了          —— 抓「rc=0 且无报错，但 census 根本没跑到本臂」
#     ④ 该行的 hard_fails 恰好等于预期             —— natural=[] / 三负例=[43]，任一不符即红
#   致命标记刻意【不含裸 ERROR:】：缺 nobodywho GDExtension 每次开场固定打几行良性 ERROR:/Condition
#   （与 ci.sh 的 ERR_OK 白名单、vg_shoot 的 VG_GERR 同一批噪声），认它们会每臂假红。
#
# ── 为什么是 seed 1 × 30 天 × 4 次 sim（做快）──────────────────────────────────────
# census 的 --mutate 是 sim 跑完后对 `event_log` 副本的【后处理】（改 witnesses、不重跑 sim），
# 理想是「跑 1 次 sim → 4 个后处理 + check_all」。但 aa3fix_census.gd 的 CLI 每次 --mutate 只收
# 一个臂、且每 seed 各跑一次 sim（game/bench/aa3fix_census.gd:33-38、:41-52）——想一次 sim 复用 4 臂
# 就得改它，而 game/** 是本棒禁区（避免与用户 re-bake 撞车）。故退而求其次：取【最少 seed(1) +
# 够过豁免线的最短天数】把 4 次调用压到最小。实测 seed 1 × 30 天 ⇒ buy_total=43 = 8.6× 豁免线
# TRADE_MIN_SALES=5，负例稳红；4 臂总耗时约 16s（≪ 单个视觉门量级）。
# ⚠ 豁免线自证（§does_not_detect 的头号盲区）：#43 在「人→人成交 < TRADE_MIN_SALES」时跳过①②
#   （Invariants.gd:1143）。若把天数压到 buy_total<5，三负例会被【豁免】成绿 ⇒ 与预期 [43] 不符
#   ⇒ 本门仍判红（fail-closed），但为了给出【指向真病因】的信息而不是「[]≠[43]」这种谜语，
#   本门从源码 grep TRADE_MIN_SALES，并在 natural 臂上核 buy_total ≥ 它——不够就当场点名豁免线。
#
# 环境变量（默认值就是出货配置，覆盖仅供本地调试/掐表）：
#   GODOT（缺省 godot） PYTHON（缺省 python） CI_AA3_SEED(1) CI_AA3_DAYS(30) CI_AA3_AGENTS(12)
#   LT_LOG（每臂 godot 日志目录；缺省 /tmp 下按仓库路径+PID 隔离，同 ci.sh 的口径）

set -uo pipefail
cd "$(dirname "$0")/.."
GBIN="${GODOT:-godot}"
PY="${PYTHON:-python}"
SEED="${CI_AA3_SEED:-1}"
DAYS="${CI_AA3_DAYS:-30}"
AGENTS="${CI_AA3_AGENTS:-12}"
LOGDIR="${LT_LOG:-/tmp/aa3-$(printf '%s' "$PWD" | tr -c 'A-Za-z0-9' '_' | tail -c 40)-$$}"
mkdir -p "$LOGDIR"

# 致命标记：真正的脚本/引擎级失败；nobodywho 缺库的良性 ERROR:/Condition 不在内（同 vg_shoot.VG_GERR）。
AA3_GERR='SCRIPT ERROR|USER ERROR|Parse Error|Failed to load script|Failed to instantiate|Segmentation fault|core dumped|Aborted'

# 从源码 grep 豁免线（不写魔数：判据改名/搬家 ⇒ 读不到 ⇒ 红，而不是静默放行）。
TMIN=$(grep -oE 'const[[:space:]]+TRADE_MIN_SALES[[:space:]]*:=[[:space:]]*[0-9]+' game/bench/Invariants.gd | grep -oE '[0-9]+$')

# 预期表：臂 => 预期 hard_fails（紧凑 JSON，便于字符串比）。
#   ⚠ 这就是「牙」所在的判据行：把 buyeronly 的 [43] 改成 [] ＝ 模拟「观察侧退回只排 vendor」的
#   回归后【本该有的】预期 ⇒ 真实 census 仍打 [43] ⇒ 本门判红（外审 P0.③ 点名的抗回归缺口）。
ARMS="natural vendoronly buyeronly partiesonly"
expect_for(){ case "$1" in
  natural)                            echo "[]"   ;;
  vendoronly|buyeronly|partiesonly)   echo "[43]" ;;
  *)                                  echo "??"   ;;
esac; }

FAIL=0
NAT_BT=""   # natural 臂的 buy_total，供豁免线自证

# 从一行 [FIXCENSUS] JSON 里取一个字段（python 稳解；hard_fails 输出紧凑数组）。
_field(){ printf '%s' "$1" | "$PY" -c 'import sys,json;d=json.load(sys.stdin);k=sys.argv[1]
v=d.get(k)
print(json.dumps(v,separators=(",",":")) if isinstance(v,list) else v)' "$2" 2>/dev/null; }

run_arm(){
  local arm="$1" want; want="$(expect_for "$arm")"
  local log="$LOGDIR/aa3_$arm.log"
  rm -f "$log"                                    # 先删旧日志：不让上一轮残留冒充本轮
  "$GBIN" --headless --path game --script res://bench/aa3fix_census.gd -- \
    --seeds "$SEED" --days "$DAYS" --agents "$AGENTS" --mutate "$arm" >"$log" 2>&1
  local grc=$?
  local err; err="$(grep -aE "$AA3_GERR" "$log" 2>/dev/null | head -1)"
  local line; line="$(grep -a '\[FIXCENSUS\]' "$log" | tail -1)"   # seed 单值 ⇒ 一行；取末行稳妥
  # ① rc
  if [ "$grc" -ne 0 ]; then echo "  ❌ $arm: godot rc=$grc（子进程非零退出，判红）"; tail -6 "$log"; FAIL=1; return; fi
  # ② 致命标记
  if [ -n "$err" ]; then echo "  ❌ $arm: godot 日志含致命错误标记: $err"; FAIL=1; return; fi
  # ③ 产物在位
  if [ -z "$line" ]; then echo "  ❌ $arm: 没有 [FIXCENSUS] 行（census 没跑到本臂/产物缺失）"; tail -6 "$log"; FAIL=1; return; fi
  local json="${line#*\[FIXCENSUS\] }"
  local got bt; got="$(_field "$json" hard_fails)"; bt="$(_field "$json" buy_total)"
  [ "$arm" = "natural" ] && NAT_BT="$bt"
  # ④ 牙：hard_fails 恰好等于预期
  if [ "$got" = "$want" ]; then
    echo "  ✅ $arm: hard_fails=$got（预期 $want） buy_total=$bt"
  else
    echo "  ❌ $arm: hard_fails=$got ≠ 预期 $want（buy_total=$bt）—— 观察侧判决与抗回归预期不符"
    # 指向真病因：负例本该红却回了 []，且成交低于豁免线 ⇒ 是被豁免了，不是判据坏了
    if [ "$want" = "[43]" ] && [ "$got" = "[]" ] && [ -n "$bt" ] && [ -n "${TMIN:-}" ] && [ "$bt" -lt "$TMIN" ]; then
      echo "       ↳ buy_total=$bt < TRADE_MIN_SALES=$TMIN ⇒ 本局被 #43 豁免线跳过①② ⇒ 负例假绿。"
      echo "         把 CI_AA3_DAYS 调回够触发成交的天数（出货默认 30 天 ⇒ buy_total≈43），别在这里收紧判据。"
    fi
    FAIL=1
  fi
}

echo "### #43 观察侧抗回归门 (natural 必绿 / vendoronly·buyeronly·partiesonly 必红；seed=$SEED days=$DAYS N=$AGENTS)"
if ! [ "${TMIN:-x}" -gt 0 ] 2>/dev/null; then
  echo "  ❌ 预检：从 Invariants.gd 读不到 TRADE_MIN_SALES（豁免线判据可能改名或搬家）"; FAIL=1
fi
for a in $ARMS; do run_arm "$a"; done
# 豁免线自证：natural 的 buy_total 必须 ≥ 豁免线，否则三负例其实是被豁免、不是被判据咬红。
if [ "$FAIL" -eq 0 ] && [ -n "$NAT_BT" ] && [ -n "${TMIN:-}" ]; then
  if [ "$NAT_BT" -ge "$TMIN" ]; then
    echo "  ✅ 豁免线自证：buy_total=$NAT_BT ≥ TRADE_MIN_SALES=$TMIN（负例的红是判据咬的，不是豁免线放的）"
  else
    echo "  ❌ 豁免线自证：buy_total=$NAT_BT < TRADE_MIN_SALES=$TMIN ⇒ 三负例本应被豁免，本门此刻无牙"; FAIL=1
  fi
fi
[ $FAIL -eq 0 ] && echo "=== AA3 #43 REGRESSION GATE: PASS ✅ ===" || echo "=== AA3 #43 REGRESSION GATE: FAIL ❌ ==="
exit $FAIL
