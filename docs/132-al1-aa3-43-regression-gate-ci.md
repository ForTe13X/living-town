# 132 · AL1 回执——#43「买卖社会痕迹」观察侧【抗回归门】接进 CI（外审 2026-08-06 21:00 P0.③）

> **一句话**：#43 的负控（`natural` 真第三方目击者必绿 / `vendoronly`·`buyeronly`·`partiesonly`
> 合成自证必红 `hard=[43]`）此前只在 docs/112 §四、docs/125 §五 的**手动 census** 里各跑过一次，
> **没有任何机器在守**。外审证伪那是纸门：将来若有人把观察侧判据退回「只排商贩」，`buyeronly`
> 会从红变绿而普通 S0 仍全绿 ⇒ 谁都不会发现。本棒把那 4 例接进 `tools/ci.sh`（新步 4g），
> 任一例判决与预期不符即判红。**零 game 改动、天然零金标**（只调既有 census、不碰 `game/**`，避开用户 re-bake）。

## ★ 交付状态

- 分支 `worktree-agent-ae132f5cfdd1d44a8`（基线 `348ff4e` = `integration/batons` 顶端；开工前
  `git merge-base --is-ancestor 38ba4a7 integration/batons` 确认祖先后 `git merge --ff-only` 上去）。
  worktree 路径 `E:/Documents/Dev/June/26th/.claude/worktrees/agent-ae132f5cfdd1d44a8`。**不 push、不 merge。**
- **owns 之内改了**（`git diff --stat` 只这两项）：
  - `tools/ci.sh`——新增第 **4g** 步（接线 + 判绿靠打印的判决行，17 行）；
  - `tools/aa3_regression_gate.sh`——**新增**，4 臂 runner + assert（四信号硬化）；
  - 本回执 `docs/132`。
- **一个字节都没碰**：`game/**`（含 `game/bench/aa3fix_census.gd`——**只调不改**）、`Sim.gd`、
  `game/data/**`、`golden`/`game/bench/*.json` 锚、`tools/gate_fixture_audit.py` /
  `gate_complement_guard.py` / `gate_complement_ledger.json`（**用户另一 session 在 re-bake 那一片**）。
- **天然零金标**：census 是量具（恒 `quit(0)`），判据只读 `hard_fails`；不动 Sim/数据 ⇒ 结构上碰不到任何锚。

## 〇、先量再定 scope——「4 臂能否共用一次 sim」的实测答案：**不能，除非改 game/**

派单 §八与协调者 §八 P0.③ 都写着「4 臂尽量共用一次 sim 求快」（理想：跑 1 次 sim → 4 个
post-hoc mutation + check_all）。**我先量了再定**（派单点名的「census 每臂是否重跑 sim」）：

- `game/bench/aa3fix_census.gd:33-34`——`--mutate` 每次**只收一个臂**（`mutate = args[i+1]`，覆盖式赋值）。
- `:36-38`——`for sd in seeds: _run_once(sd, …, mutate)`，**每 seed 一次** `_run_once`。
- `:41-52`——`_run_once` 里 `S = SimScript.new()` … `for _t in range(days*TICKS_PER_DAY): S.tick()`，**每次都从头跑一遍 sim**，
  mutation（`:63-96`）是这遍 sim 跑完后对 `event_log` 副本的后处理。

⇒ 「1 次 sim 复用 4 臂」需要把 CLI 改成一次接多个 mutate、或把 mutation 抽成对同一份 `event_log` 的循环——
**两者都要改 `aa3fix_census.gd`，而 `game/**` 是本棒禁区**（撞用户 re-bake）。派单本身给了 fallback：
> 「若 aa3fix_census.gd 现在的 CLI 是每 --mutate 跑一次 sim，你不能改它——那就用最少 seed(1) + 够触发成交的最短天数」。

**本棒取 fallback**：seed 1 × 30 天 × 4 臂各一次 sim。这是在「不碰 game/」约束下能达到的最快，见 §四耗时。

## 一、做快的两个数（都是实测标定，不是猜）

| 天数 | seed 1 `buy_total` | 单臂墙钟 | 4 臂总耗时 |
|---|---|---|---|
| 60（派单参照） | ≈84 | —— | —— |
| **30（本门取值）** | **43** = **8.6× 豁免线** | ≈4s | **≈16-20s** |
| 15（更短，量过） | 21 = 4.2× 豁免线 | ≈2.4s | ≈10s |

- **为什么不取 15**：4s 里绝大半是 godot 启动+import（`user`/`sys` 各 0.05/0.17s，`real` 4s 全在子进程），
  15→30 只省约 6s；而 30 天给的 8.6× 余量比 15 天的 4.2× 稳得多，总耗时（≈16-20s）**远 ≪ 单个视觉门量级**
  （视觉门 docker 软渲染 6-8 min）。派单也是提示「可试更短如 30 天够不够出成交」——30 天足够且稳，取它。
- **豁免线是硬边界**：#43 在「人→人成交 < `TRADE_MIN_SALES=5`」时跳过①②（`Invariants.gd:1143`）。
  天数压到 `buy_total<5` ⇒ 三负例被**豁免**成绿 ⇒ 与预期 `[43]` 不符 ⇒ **本门仍判红（fail-closed）**，
  但门内从源码 grep 出 `TRADE_MIN_SALES` 并在 natural 臂核 `buy_total ≥ 它`，把「谜语式失败」翻译成
  「是豁免线放的、不是判据坏了，把天数调回去」。

## 二、接了什么（ci.sh 第 4g 步 + 新 runner/assert 脚本）

### 2.1 `tools/ci.sh` 第 4g 步（VoiceGate 之后、场景步之前）

```bash
step "4g. #43 观察侧抗回归门 (natural 必绿 / vendoronly·buyeronly·partiesonly 必红；外审 2026-08-06 P0.③)"
# …为什么必须有它 / 成本 / 判绿靠打印的判决行而非退出码（注释见源码）…
GODOT="$GODOT" PYTHON="$PY" LT_LOG="$LT_LOG" bash tools/aa3_regression_gate.sh 2>&1 | tee "$LT_LOG/aa3.log"
grep -q 'AA3 #43 REGRESSION GATE: PASS' "$LT_LOG/aa3.log" \
  && ok "#43 观察侧抗回归门（4 例判决 == 预期：natural 绿 / 三负例红 hard=[43]）" \
  || bad "#43 观察侧抗回归门（有例判决与抗回归预期不符，见上——观察侧可能退回只排 vendor）"
```

**判绿靠打印的判决行 `AA3 #43 REGRESSION GATE: PASS ✅`，不靠退出码**（派单硬约束：本机 godot `.cmd`
退出码不可信）。gate 自身是纯 bash `exit $FAIL`（可信），但为贯彻「读输出」纪律，ci.sh 只认那行 grep。
env 三个透传（`GODOT`/`PYTHON`/`LT_LOG`）与既有 `visual_gate.sh` 接线（`GODOT="$GODOT" bash "$0"`）同构。

### 2.2 `tools/aa3_regression_gate.sh`——四信号硬化的 4 臂 runner + assert

判据以 census 打印的 `hard_fails` JSON 为准（census 恒 `quit(0)`、push_error 不改退出码）。对**每一臂**做
四信号（前三条同 `tools/vg_shoot.sh`，第四条是本门的牙）：

| 信号 | 抓什么 |
|---|---|
| ① godot 子进程 `rc==0` | 进程非零退出（真二进制/容器里 rc 可信，主判据） |
| ② 日志无致命标记 | rc 不可信环境里报了 `SCRIPT ERROR` 却退 0（标记刻意**不含裸 `ERROR:`**——缺 nobodywho 的良性开场白，同 ci.sh `ERR_OK`/vg_shoot `VG_GERR`） |
| ③ 本臂 `[FIXCENSUS]` 行在位 | rc=0 无报错但 census 根本没跑到本臂（产物缺失） |
| ④ 该行 `hard_fails` **恰好等于**预期 | `natural=[]` / 三负例 `=[43]`，任一不符即红——**这是牙** |

- **预期表**（`expect_for`）：`natural→[]`、`vendoronly|buyeronly|partiesonly→[43]`。
- **豁免线自证**：grep `TRADE_MIN_SALES`（读不到 ⇒ 红，判据搬家不静默放行），natural 的 `buy_total ≥ 它`。
- `hard_fails` 用 python 稳解 JSON、紧凑输出便于字符串比；每臂 godot 日志落 `$LT_LOG/aa3_<arm>.log`（失败时 tail 出病因）。

## 三、四例实际输出（正绿三负红）+ 牙的实证（断言反转 → 步红）

### 3.1 四例（`bash tools/aa3_regression_gate.sh`，seed 1 × 30 天 × N=12，**逐字抄**）

```
### #43 观察侧抗回归门 (natural 必绿 / vendoronly·buyeronly·partiesonly 必红；seed=1 days=30 N=12)
  ✅ natural: hard_fails=[]（预期 []） buy_total=43
  ✅ vendoronly: hard_fails=[43]（预期 [43]） buy_total=43
  ✅ buyeronly: hard_fails=[43]（预期 [43]） buy_total=43
  ✅ partiesonly: hard_fails=[43]（预期 [43]） buy_total=43
  ✅ 豁免线自证：buy_total=43 ≥ TRADE_MIN_SALES=5（负例的红是判据咬的，不是豁免线放的）
=== AA3 #43 REGRESSION GATE: PASS ✅ ===
```

`inv43.detail` 逐臂（census 原样打印，摘）：natural=`开[商贩:成交43 被看见36 知情9人]`；
三负例均=`开[商贩:成交43 被看见0…]；【异常】商贩 成交43笔但【一笔都没被看见】(pay 的 witnesses 通道断了)`。
三负例 `buy_total` 都是 43（mutation 只改 witnesses、不改成交计数），`被看见=0` ⇒ 判据咬红。

### 3.2 牙的实证：把 `buyeronly` 的预期从 `[43]`（红）翻成 `[]`（绿）⇒ 步必红

**这正是外审点名的回归场景**：观察侧退回只排 vendor ⇒ buyeronly 会绿。我把 `expect_for` 里
`buyeronly` 从 `[43]` 移到 `[]` 分支（模拟「回归后本该有的预期」），真实 census 仍打 `[43]` ⇒ 不符 ⇒ 红：

```
  ✅ natural: hard_fails=[]（预期 []） buy_total=43
  ✅ vendoronly: hard_fails=[43]（预期 [43]） buy_total=43
  ❌ buyeronly: hard_fails=[43] ≠ 预期 []（buy_total=43）—— 观察侧判决与抗回归预期不符
  ✅ partiesonly: hard_fails=[43]（预期 [43]） buy_total=43
=== AA3 #43 REGRESSION GATE: FAIL ❌ ===        # exit 1
```

⇒ 断言反转 → gate 打 `FAIL ❌`、`exit 1` → ci.sh 的 `grep -q …PASS` 落空 → `bad "#43 观察侧抗回归门…"`
→ `FAIL=1` → 整份 CI `=== CI FAIL ❌ ===`。**牙咬得住**（测毕已把 `expect_for` 改回 `buyeronly→[43]`）。

## 四、§2.5 探测包络（docs/41 §2.5；as-wired，判据本体的包络见 docs/112 §五、docs/125 §五）

```
detects（都跑过、核过判决行与退出码）：
  ① 观察侧判据退回「只排商贩」（Invariants.gd #43 ①臂 wn_other 去掉 `!= actor` 那半，
     = docs/112 基线 / AG2 收紧之前）⇒ buyeronly 从红变绿、而预期仍 [43] ⇒ 本门红。
     实证方式：翻 expect_for 里 buyeronly 的预期 [43]→[]（同构于「观察侧回归后的预期」）⇒ FAIL ❌ exit 1（§3.2）。
  ② 采集侧过滤被撤 / 观察侧判据整个失效 ⇒ vendoronly/partiesonly 同样会与 [43] 不符 ⇒ 红（三负例各自独立咬）。
  ③ census 没跑到（godot rc≠0 / SCRIPT ERROR / 没打 [FIXCENSUS] 行）⇒ 四信号①②③各自判红（fail-closed，非 fail-open）。
  ④ 判据搬家：grep 不到 TRADE_MIN_SALES ⇒ 预检红（不静默放行）。
does_not_detect（跑出来的/从结构直接读出，不是想出来的）：
  · **豁免线以下一概不设防的正确性**：把天数压到 buy_total<5，三负例会被 #43 豁免成绿 ——
    本门此时【仍判红】（预期 [43] 对不上），但那是「夹具选坏了」的红，不是「回归」的红；
    门内 grep TRADE_MIN_SALES + natural buy_total 自证会点名是豁免线，避免误读。**它不能在 buy_total<5 时守 #43**（结构性，非本门能补）。
  · **只在 seed 1 × 30 天 × N=12 这一格**：不扫 seed 网格、不扫 N≠12、不扫短/长 horizon（docs/112/125 已在 seeds 1-6/1-12 上验过判据本体；本门是抗回归牙，不是判据的再验证）。
  · **只认 `hard_fails` 恰好 [43]/[]**：若将来某格上别的硬不变量也红（如短 horizon 的 #01），[1,43]≠[43] 会让本门红——这是刻意的严（负例的唯一效应就该是 #43），但意味着换配置需重标预期。
  · **不查 witnesses 里那个人当时真在场 / standing 真动 / 文案**：继承 docs/112 §八、docs/125 §八 的盲区（本门只消费 census 的 hard_fails，不加新判别力）。
  · **不守判据【本身还在不在】**：若有人把 #43 从 Invariants.gd 整个删掉，census 的 check_all 里就没有 43，natural/负例可能都回 []——本门会因负例 []≠[43] 而红，但报的是「判决不符」不是「判据没了」（与 gate_complement_guard 的 M8 盲区同类）。
confidence：N=4 臂（1 正 + 3 负，各一次真 sim）× 1 牙实证（buyeronly 断言反转 → 步红）；
  另加豁免线自证（buy_total=43 ≥ 5）与四信号硬化（rc/致命标记/产物在位/hard_fails 恰配）。
  全量 `bash tools/ci.sh` 复跑：见 §五。
```

## 五、`bash tools/ci.sh` 全量（**读输出，判决行照抄**）

<!-- CI_VERDICT_PLACEHOLDER -->

## 六、没能测到什么（"没测"明写）

- **判据本体没重验**：本门是抗回归牙，不重跑 docs/112/125 的 seeds 1-6/1-12 网格；只在 seed 1 × 30 天验 4 例。
- **豁免线以下的 #43** 结构上守不住（§四 does_not_detect 头条）——那是 #43 判据自己的性质，不是本门能补。
- **没重烘任何锚**：本改动不动 Sim/数据/digest（census 是只读量具）⇒ 无需 R12；实测 `git diff` 只有 `tools/`+doc。
- **没在真机 / GHA 上跑**：本门纯 headless（4 次 godot bench），不吃渲染环境；GHA 上照跑（与 4a-4f 同构）。
- **N≠12 / seed≠1 的格没跑**：出货网格由第 4 步 S0（seeds 1-12）覆盖判据；本门刻意最小化求快。
