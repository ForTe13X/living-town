# 136 · AN1 · AE2 fail-open 收口——把互补性锚从「能把旧树盖成当前树」改成真 fail-closed

> 派单：外审 2026-08-06 21:00 CST **P0.①**（`analysis/main-repo-review/reviews/2026-08-06-2100-cst.md`
> @`origin/codex/main-repo-review` §三 P1）。契约 [docs/41](41-baton-contract.md) 全文，尤其 §2.5、§3、§4。
> 前一轮 AE2 回执：[docs/119](119-wave-ae-ae2-verification-tools-fail-closed.md)。
> owns：`tools/gate_fixture_audit.py`、`tools/gate_complement_guard.py`、本文。
> **`game/**` 零改动、`tools/gate_complement_ledger.json` 一个字节没动（没重烘）、`Sim.gd`/golden 未碰。**
>
> 一句话结论：**docs/119 把烘锚流水线的三面 fail-open 补齐了，但外审隔离复现出【它漏了两条】——
> 都在"树来源闭环"上：① `--from OLD --bake-ledger` 不带 `--run` ⇒ `tree_sha=None` ⇒ 树比较被跳过、
> 盖章路 `tree_sha or cur_tree` 拿当前 HEAD:game 顶包，旧/伪输出被盖成当前树；② consumer
> `gate_complement_guard` 只打印 metadata、从不比锚的 `baked_game_tree` 与当前 `HEAD:game`。
> 本棒把这两条都改成 fail-closed，各带一个跑出来的负对照，当前 fresh 锚上不假红。**

---

## 〇、这份 brief / 前置状态哪里是错的（[docs/41 §4](41-baton-contract.md)）

### ① 「基线 integration/batons（ace2a7e）是祖先才 ff」——**我的 worktree 根本不是它的后代，且没有 ledger**

派单说"确认基线 integration/batons（当前 ace2a7e 或更新），是祖先才 ff"。实测：本 worktree 开工时停在
**`38ba4a7`**（一条讲"决策路失败=格式 bug"的 readme/docs 分支），`git merge-base --is-ancestor ace2a7e 38ba4a7`
= **NO**，而且 `38ba4a7` 树里**根本没有 `tools/gate_complement_ledger.json`**（`git show 38ba4a7:…` fatal）。
⇒ 在 `38ba4a7` 上改根本无从验证。**处置**：worktree clean，直接 `git checkout -B an1-fixture-audit-failclosed ace2a7e`，
从正确基线起步。`ace2a7e:game=b19a8e6`、ledger `baked_game_tree=b19a8e6` ⇒ 与派单说的"当前 fresh"一致。

### ② brief 给的行号/字面量——**对得上 ace2a7e，逐条复核属实**

`bake_ledger` 定义 `:428`、树比较 `:452 if tree_sha is not None`、盖章 `:498 tree_sha or cur_tree`、
`main` 里 `run_fails, tree_sha = [], None`（`:712`）——在 `ace2a7e` 上**逐条命中**。这次 brief 的行号没漂。

### ③ 「当前 ledger 是 fresh 的」——**对，但 fresh 的判据是 game 树、不是 commit**

入库 ledger 的 `baked_game_tree=b19a8e6` == `HEAD:game`（fresh ✅），但它的 `baked_commit=f9e2f27`
**不等于**当前 HEAD `ace2a7e`。这不是矛盾：`game/` 树在若干个 commit 间没动，所以一份烘于早先 commit 的锚，
其 game 树仍可能等于当前。**这正好印证了本棒 consumer 侧的判据要键在 `HEAD:game`（依赖树）、而不是 `baked_commit`**
——外审 §三 P1 第 4 点举的历史例子（`baked_commit=3412b253 / baked_game_tree=6c13be2 vs HEAD:game=a176d686`）
是评审冻结点上那份**当时就 stale** 的锚；协调者其后按正确 `--run` 路重烘，现在 `ace2a7e` 上已 fresh。
⇒ **本棒的硬化 guard 必须在当前树上 PASS，这一条我实证了（见 §二）。**

---

## 一、两条 fail-open 的修复 diff（只动 `tools/` 两个工具）

### 1. `gate_fixture_audit.py`：不跑 run 就绝不盖章（堵"把旧树盖成当前树"的后门）

| 位置 | 改法 |
|---|---|
| `main()` bake 块**最前** | `--bake-ledger` 不带 `--run`（典型 `--from OLD --bake-ledger`）⇒ **拒**：`--from` 只解析、测不到当前 game 树。失败要快，省掉 ~12 min godot。 |
| `main()` bake 块（run 前） | 探针 `tools/gate_fixture_probe.gd` 相对 HEAD 脏 ⇒ **拒**（外审 §三 P1 第 2 点；见 §四·item 4）。 |
| `bake_ledger()` 树闭环 | 删掉 `if tree_sha is not None` 这道**把校验挡在门外**的守卫；改成三道硬闸：`tree_sha is None ⇒ 拒`、`cur_tree is None ⇒ 拒`、`tree_sha != cur_tree ⇒ 拒`。 |
| `bake_ledger()` 盖章 | `"baked_game_tree": tree_sha or cur_tree` → **`tree_sha`**（已校验非空且 == cur_tree，不再拿 HEAD:game 顶包）。 |

**为什么两道闸都要（main + bake_ledger）**：`main()` 的 `--from` 拒是快闸（好错误信息）；`bake_ledger()` 里
`tree_sha is None` 的拒是**第二道**——防有人绕过 CLI 直接调 `bake_ledger`（防御纵深）。

### 2. `gate_complement_guard.py`：consumer 加依赖树闭环（比 `baked_game_tree` vs `HEAD:game`）

新增纯函数 `check_ledger_freshness(ledger, cur_game_tree)` + `_head_game_tree()`（现读 `git rev-parse HEAD:game`），
在 `gate()` 里折进 `fails`：

- `baked_game_tree` 缺 ⇒ 红（无证据的锚不放过）；
- 当前 `HEAD:game` 读不到 ⇒ 红（不假装新鲜）；
- `baked_game_tree != HEAD:game` ⇒ **红，点名 `STALE` + 打出重烘命令**（别打谜语）。

默认现读 git；`gate(..., cur_game_tree=None)` 显式传 None 表示"git 读不到"（fail-closed）——`_UNSET` 哨兵区分两者，
让 self-test 能纯函数地喂合成树 sha、不碰 git。

`git diff --stat`：

```
 tools/gate_complement_guard.py | 60 +++++++++++++++++
 tools/gate_fixture_audit.py    | 71 +++++++++++++++++++++
 docs/136-an1-ae2-fail-closed-tree-provenance.md | (本文)
```
**只有 `tools/` 两个工具 + 本 doc。零 `game/` 改动 ⇒ 天然零金标移动。**

---

## 二、负对照实际输出（fail-closed 的牙）

### 2.1 后门①：`--from OLD --bake-ledger` —— 改前盖成当前树、改后被拒

先造一份**完整**的合成"旧 iso"（7 个非 none 夹具各非空，过得了旧的"缺格"拦截；脚本见本 session scratchpad）。

**改前（原封 `ace2a7e` 的工具，指到 scratch 锚，入库锚不碰）**：

```
🔨 已烘 …before_backdoor_ledger.json（7 夹具 × 35 条 C/G 不变量）
TOOL_EXIT=0
   → baked_commit  = ace2a7e…   （当前 HEAD）
   → baked_game_tree = b19a8e6…  （当前 HEAD:game）   ← 旧/伪输出被盖成当前树，正是 confirmed bypass
```

**改后（硬化工具，同一份 `--from` 输入）**：

```
❌ 拒绝烘锚：--bake-ledger 必须与 --run 同用。
   `--from <目录>` 只解析已有输出、【测不到当前 game 树】⇒ 会把旧/伪输出盖成当前 HEAD:game
   （外审 2026-08-06 21:00 §三 P1 confirmed bypass）。要烘就跑 `--run --bake-ledger`。
TOOL_EXIT=1
   → after_backdoor_ledger.json: 未创建（No such file）   ← 拒绝后一个字节都没盖
```

### 2.2 后门②：synthetic stale ledger 喂 consumer —— 改前返 0、改后红

造一份把入库锚的 `baked_game_tree` 改成 `deadbeef…` 的 synthetic stale ledger。

**改前（原封 consumer）**：`GUARD_EXIT=0`（只打印 metadata，从不比依赖树 ⇒ fail-open）。

**改后（硬化 consumer）**：

```
  ❌ 锚 STALE：baked_game_tree=deadbeefdead ≠ 当前 HEAD:game=b19a8e6fa4fe ⇒ 锚烘自另一棵 game 树，
     它记录的活输入来源可能与当前依赖树不符。请重烘：GODOT=… python tools/gate_fixture_audit.py --run --bake-ledger
GUARD_EXIT=1
```

### 2.3 正对照：当前 **fresh** 入库锚 ⇒ 硬化 consumer PASS（不假红）

```
互补性守卫：锚烘于 2026-08-07（commit f9e2f27，7 个夹具 × 35 条不变量）
    S0             ← #20
FRESH_GUARD_EXIT=0
```

⇒ **硬化后的 guard 在当前 fresh 锚上照常绿；只有依赖树对不上才红。**

---

## 三、探测包络（[docs/41 §2.5](41-baton-contract.md)）

本棒**没有新增或收紧任何一道 CI 判据**——把两个既有量具补成默认 fail-closed。两份包络。

### 3.1 `gate_fixture_audit` 的树来源闭环

```
detects（跑出来的）：
  · `--from OLD --bake-ledger`（无 --run）⇒ 工具退 1、不盖锚（§2.1 before/after：旧 0 / 新 1，锚未创建）。
  · bake_ledger(tree_sha=None) ⇒ 拒（self-test，不需 godot）——即"不跑 run 就盖当前树"那条路的 bake 层闸。
  · bake_ledger(tree_sha ≠ HEAD:game) ⇒ 拒（self-test）。
  · bake_ledger(tree_sha == HEAD:game) ⇒ 正常烘（self-test，证明上面不是"一律拒绝"）。
  · dirty probe（tools/gate_fixture_probe.gd 相对 HEAD 有改动）⇒ 拒（§四负对照跑出来的）。
does_not_detect（跑出来的 / 明写的盲区）：
  · 探针 push_error 但 quit(0)：rc 拦截看不见（docs/119 已列，未变）。
  · **未提交的 game/ 改动**：`git archive HEAD` 量 committed 树 ⇒ 工作树改动不进测量（性质，非 bug）。
  · **完整性/去重/completion sentinel**：parser 仍信任文件内 tag、扫所有 .txt、每 tag 非空即过——
    外审 §三 P1 第 3 点点的这条【本棒未做】，明写留作跟进（见 §四）。它不是本棒 P0.① 的两条路。
  · **probe hash 未绑进锚**：本棒只在烘锚前拒 dirty probe，未把 probe sha256 写进 ledger 让 consumer 现比
    （那需要重烘去填字段，本棒禁碰入库锚）——明写留作跟进。
confidence: N=6（§2.1 后门 before/after 2 + bake 三态 self-test 3 + dirty probe 1）；全 self-test 12/12。
```

### 3.2 `gate_complement_guard` 的依赖树闭环

```
detects（跑出来的）：
  · baked_game_tree ≠ 当前 HEAD:game ⇒ 红并点名 STALE + 叫重烘（§2.2 synthetic stale ⇒ EXIT 1；self-test M10）。
  · 锚缺 baked_game_tree ⇒ 红（self-test M11）。
  · 当前 HEAD:game 读不到（git 失败）⇒ 红（self-test M12，不假装新鲜）。
  · baked_game_tree == 当前 HEAD:game ⇒ 不红（§2.3 当前 fresh 锚 EXIT 0；self-test M9，不假红）。
does_not_detect（明写的盲区）：
  · **game 树内容级漂移**它不看：它比的是 `HEAD:game` 的 tree sha，不是逐 provider 重算——
    锚里的 providers 表是否与今天的世界一致，仍要靠"重烘"这个受控动作（docs/41 §3）。
  · 工作树 vs HEAD 的差异：consumer 比的是 committed `HEAD:game`，与 docs/119 里 guard 读工作树文本做结构比对
    是两条正交的轴；本棒只补"锚烘自哪棵 committed game 树"这一轴。
confidence: N=4（M9/M10/M11/M12，纯函数每跑一次 CI self-test 复现一次）；全 self-test 14/14。
```

---

## 四、报给用户 / 测了之后决定留作跟进的（[docs/41 §4.2](41-baton-contract.md)）

1. **外审 §三 P1 第 3 点（parser 完整性）本棒未做，明写留作跟进。** 「每 run 新唯一目录、原子输出、
   run-id manifest、严格校验 filename/tag/seed/invariant/live/completion 全集并拒 duplicate/extra」是外审
   Phase 0.2 的**另一半**，不是本棒 P0.① 的两条 confirmed 路。它是**一整块**（改默认输出目录、加 manifest、
   改 parser 契约），成本高于本棒该动的面；且现有 `bake_ledger` 的"缺格拒烘"挡住了最粗的一类（少跑一格）。
   ⇒ 单列一根棒做，别塞进本棒。
2. **probe hash 绑进锚 = 跟进项。** 本棒在烘锚前**拒 dirty probe**（低成本、fail-closed、在 owned 文件里），
   但没把 `probe_sha256` 写进 ledger 让 consumer 现比——那要**重烘**去填字段，而重烘会动一份喂着 CI 门的入库锚
   （[docs/41 §3](41-baton-contract.md) 的受控动作），本棒禁碰。低成本落地方式（留给带重烘权限的那根棒）：
   `bake_ledger` 的 `_meta` 多写一条 `probe_sha256`，`check_fixture`/`gate` 侧现读 `tools/gate_fixture_probe.gd`
   的 sha256 比对，不符即红。
3. **没重烘、没碰入库 `gate_complement_ledger.json`。** 与 docs/119 §三·3 同一条纪律：本棒硬化的是**工具的判据**，
   不是那份数据。当前锚 fresh，硬化 guard 在它上面 PASS（§2.3）。

---

## 五、CI 判决 + 复跑命令

### `bash tools/ci.sh` 的实际输出（读输出，不是读退出码）

落地时全量 CI 跑绿（判决行 = CI PASS，rc0；S0 12/12 含链、新硬化 guard 三负控过——正/负对照见 §二本棒实证）。
⚠️**审查 F4 纠**：该 run 的 stdout **未归档**（`analysis/an1` 未建），roadmap 曾引"1286s PASS"属**无存证的精确秒数**——已不作存证。硬化 guard 的独立复核由外审 AE2 审计员 2026-08-07 完成（**确认真 fail-closed、未找到第二条绕过路径**）。

**✅ 整轮 CI 归档（2026-08-07，`analysis/review-2026-08-07-ci/verdict.txt`，HEAD `1fcbfc8`/game `c244322`）**：判决行 = **`=== CI PASS ✅ ===`**；其中 **complement guard 在 fresh ledger（`baked_game_tree==HEAD:game c244322`）过、无 STALE** ⇒ 本棒硬化 guard 在真流水线上 fail-closed 且不假红，得实证。S0 12/12 含链、state_projection 4h PASS 同轮绿。下面的复跑命令每条都能本地重算（不需 godot 的两个 self-test 尤其快）。

### 复跑命令（每条都能重算，均不碰入库锚 / game）

```bash
# 两个 self-test（不需要 godot）
python tools/gate_fixture_audit.py --self-test        # 12 条（含 3 条 AE2 P0.① 树闭环）
python tools/gate_complement_guard.py --self-test     # 14 条（含 M9-M12 依赖树闭环）

# 后门① 负对照：--from + --bake-ledger ⇒ 拒（指 scratch 锚，入库锚不碰）
python tools/gate_fixture_audit.py --from <old_iso> --bake-ledger --ledger <scratch>.json   # ⇒ 退 1、不盖锚

# 后门② 负对照：synthetic stale ledger ⇒ consumer 红
#   （把入库锚的 baked_game_tree 改成 deadbeef… 存到 scratch，再喂 consumer）
python tools/gate_complement_guard.py --ledger <scratch_stale>.json                          # ⇒ 退 1、点名 STALE

# 正对照：当前 fresh 入库锚 ⇒ consumer PASS
python tools/gate_complement_guard.py                                                        # ⇒ 退 0
```

**本棒不移动任何 digest**：没改 `game/**`、没改 `tools/ci.sh`、没重烘任何入库的锚。

---

## 六、如果只读一句

**docs/119 把烘锚流水线补到 fail-closed，但漏了"树来源闭环"的两条路——不跑 run 就把旧树盖成当前树、
consumer 从不比依赖树。本棒各补一道 fail-closed 闸（bake 侧没有可信 tree_sha 就拒盖、consumer 侧
`baked_game_tree != HEAD:game` 就红点名 STALE），各带一个跑出来的负对照，且在当前 fresh 锚上不假红。
parser 完整性与 probe-hash 绑锚是外审 Phase 0.2/0.3 的另外两块，明写留作跟进，不塞进本棒。**
