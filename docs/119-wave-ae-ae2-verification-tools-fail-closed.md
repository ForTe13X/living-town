# 119 · Wave AE · AE2 回执——**量具的 fail-open 集中在一处：烘锚那条流水线，而它喂着一道真门**

> 派单：[docs/117 §二](117-wave-ae-plan.md)（AE2，Codex red #2）。契约 [docs/41](41-baton-contract.md) 全文，尤其 §2.5、§6。
> 前置的另外两半：[docs/73](73-wave-s-s2-denominator-and-gate-teeth.md)（S2 查**阈值余量**过没过期）与
> [docs/94](94-wave-x-x3-fixture-validity.md)（X3 查**夹具**空不空）。**本棒查的是第三样：量具自己会不会 fail-open。**
> 基线：开工时本 worktree 停在 `38ba4a7`（是 `integration/batons` 的祖先），ff 到 **`103d951`**。
> owns：`tools/**` 与本文。**`game/**` 一个字节没动。** 未碰 `tools/ci.sh`（下面说明为什么不需要碰）。
>
> 一句话结论：**S2/X3 已经把量具查得很干净了——普查下来，真正 fail-open 的面【集中在一个工具】：
> `gate_fixture_audit.py` 的 `--run/--bake-ledger` 流水线。** 它同时踩中派单点的**三类**病
> （旧产物复用、子进程非零只打印不计失败、来源/ledger 章没成闭环），而且它烘出来的锚
> **正是一道真 CI 门（`gate_complement_guard`）每次现读的那一份**。其余约十几个量具早已 fail-closed。

---

## 〇、这份 brief 哪里是错的（[docs/41 §4](41-baton-contract.md)）

### ① 「别假设很多」——**对，而且比 U3/X3 那两次还更集中**

派单逐字提醒：「U3/X3 两次先验"很多"、实测"集中在少数"——**别假设很多**」。
实测下来收敛得更狠：**过一遍会跑子进程 / 复用产物的约 18 个量具，真正 fail-open 且【喂着一道门】的只有 1 个**
（`gate_fixture_audit.py`）。另有 1 个诊断器有一处 swallow（`recalc_scan.py`，已修）、
4 个诊断汇总器复用 jsonl 时不绑树（低危、照实报、没修）。**其余约 12 个已经 fail-closed**
（`check=True` / 现查 rc / 内容重建 / 自带 selftest）。比例见 §一。

### ② 「子进程非零退出码只被打印没被计失败」——**命中，但要点名【是哪一次子进程】**

派单把它讲成一类普遍现象。实测：**大多数工具的子进程 rc 都被正确处理了**
（`assert_no_weights` 用 `check=True`、`recalc.py` 明写 `if rc != 0: fail`、`brief_mutate` 判 `rc not in (0,1)`）。
"打印了却不计失败"这条**具体命中的是 `gate_fixture_audit.run_fixtures`**：它把 `godot --import`
与每一次探针的 rc **打印成一行 `rc=%d` 就往下走**（`:538`/`:549-552`）。而这不是无害的——
它烘出来的锚喂着 `gate_complement_guard`（第 2f 步，一道真门）。逐处见 §二。

### ③ 「`tee|tail 吃退出码 ⇒ 写文件再读」——本波在 `ci.sh` 里【没有】发现这个病**

派单把它列进纪律。我逐行核过 `tools/ci.sh`：它 `set -uo pipefail`（`:13`），
且每一处 `… | tee …` 后面都紧跟 `[ "${PIPESTATUS[0]}" -eq 0 ]`（`:259`/`:311`）。
⇒ **recalc 门与互补性守卫这两道走 tee 的门，退出码是被 PIPESTATUS 接住的，不是被 tee 吃掉的。**
这一条 S2/X3 那两波（它们改过 `ci.sh`）已经收干净了。**所以本棒不需要碰 `ci.sh`**
——省掉了派单最担心的那件事（"别在 CI 正跑时改 ci.sh"）。

### ④ 「gate_fixture_audit 上撞过：打印"❌对不上"然后照样烘，后来才补了拦截」——**对，但补的拦截【漏了三面】**

派单说这条已经补过。实测：补的是 `HARD_IDS` 副本对账（`:616-621`）、缺格拒烘（`:433-436`）、
`--only` 与 `--bake-ledger` 互斥（`:632-634`）。**但同一个工具里还剩三面同样形状的 fail-open 没补**：
子进程非零 rc、隔离副本旧树复用、**以及 `_check_ci_defaults` 那条对账本身也是"打印了却不阻止"**
（`report()` 印它，烘锚路径不看它）。⇒ 派单说的"后来才补了拦截"是真的，但**那次补得不完整**。本波补齐。

---

## 一、fail-open 普查表（**给比例**）

判据三列（派单逐字）：**①子进程非零退出码有没有可靠计入失败 · ②产物是不是 fresh 或内容寻址 ·
③有没有绑 commit/tree/godot 版本**。分母 = 会跑子进程**或**复用产物的量具（18 个）。

| 工具 | 进 CI？ | ①子进程 rc | ②产物 fresh/内容寻址 | ③绑 tree/commit | 判决 |
|---|---|---|---|---|---|
| **`gate_fixture_audit.py`** | 否，但**烘的锚喂 2f 门** | ❌ import+探针 rc 只打印（`:538/:549`） | ❌ 隔离副本 `if not isdir` 复用旧树（`:524`） | ❌ baked_commit=HEAD 但量的树可能是旧的；ci 默认漂了照烘 | **FAIL-OPEN（本波修）** |
| `recalc_scan.py` | 只 selftest 进 | ❌ `git ls-files` rc swallow（`:95`）⇒ 空语料读成"0 个数字" | — | — | **FAIL-OPEN（本波修，低危）** |
| `n_sweep.py` | 否 | ⚠ 探针 rc 只打印，**但有内容 `_verify` 兜底**（seed 集/无重复/单段抬头/无 MISMATCH） | ⚠ skip-if-exists 复用 jsonl | ❌ 不绑树/digest | 复用 fail-open（**报，未修**，见 §三） |
| `n_curve/n_window/n_margin.py` | 否 | 无子进程 | ⚠ 聚合 jsonl，有去重+半行拦截 | ❌ 不绑树/digest | 复用 fail-open（诊断，低危，报） |
| `assert_no_weights.py` | **是（0 步）** | ✅ `git ls-files -z` `check=True` | ✅ 每跑现扫 | n/a | fail-closed |
| `recalc.py` | **是（2e）** | ✅ `if rc != 0: 计失败` + selftest | ✅ 现跑现比 | n/a | fail-closed |
| `gate_complement_guard.py` | **是（2f）** | 无子进程 | ✅ 纯结构、两侧读 HEAD 文本 | ✅ 锚带 baked_commit | fail-closed |
| `brief_mutate.py` | 否 | ✅ `rc not in (0,1) ⇒ -1` | n/a | n/a | fail-closed |
| `lint_links.py` | **是（2）** | ✅ rc==127 判定；`@branch` 只打印是**明写的决定**（X3 §4.2） | n/a | n/a | fail-closed（按设计） |
| `art_gate/terrain_gate.py` | **是（2b/2c）** | 无子进程（PIL/numpy 现建） | ✅ 解码后逐像素重建对比 | 内容寻址即绑 | fail-closed |
| `asset_gate.py` | **是（2d）** | 配方走 in-process spy，非真子进程 | ✅ 现建对比 + 1px 自检 | 内容寻址 | fail-closed |
| `slice*.py` / `build_video.py` | 否（媒体） | `check=True` / 媒体非门 | n/a | n/a | 非门，不计 |

**比例**：18 个里 —— **喂门且真 fail-open：1（`gate_fixture_audit`）**；诊断器 swallow：1（`recalc_scan`，已修）；
诊断汇总器复用不绑树：4（报，多数未修）；**已 fail-closed：≥12**。
⇒ **派单点的三类病，在【喂着门的那条路上】全部集中在同一个工具里。** 这正是 §六。

> ⚠ 一条诚实边界：`n_sweep`/`n_curve` 系那 4 个诊断汇总器**确实**能被喂旧产物
> （换棵树、旧 jsonl 还在 raw 目录里 ⇒ 静默聚合），这是真 fail-open。没修的理由见 §三——
> 不是"它没事"，是**它的正确 provenance 句柄（gamedir 内容哈希）比 git 绑定更重，而它一道门都不喂**。

---

## 二、逐处 fail-closed 改动 + 负对照实际输出

**全部改在 `tools/gate_fixture_audit.py` 与 `tools/recalc_scan.py`。没碰 `game/**`、没碰 `tools/ci.sh`、没烘任何入库的锚。**

### 2.1 `gate_fixture_audit.run_fixtures`：子进程非零 ⇒ 立即失败（不再只打印 rc）

**改法**：`run_fixtures` 现在**返回** `(fails, tree_sha)`；`godot --import` 与每一次探针的 rc
非零就进 `fails`；`main()` 见到 `fails` 非空即 `return 1`，且 `--bake-ledger` **拒绝烘**。

**负对照（跑出来的，before/after 同一份输入）**：造一个假 godot——`--import` 返回 0、探针**打印一份合法的
DET_default 采集（所以 `data[tag]` 非空、旧的"缺格"拦截过不了它）然后退出码 7**。

```
# 改后（fail-closed）：
$ python tools/gate_fixture_audit.py --run --only DET_default --godot <fake(exit 7)>
  跑完 DET_default    (4c DetGate/default)  rc=7  ❌ 非零退出 ⇒ 该格测量不可信
  ❌ 子进程非零退出 / 导入失败（fail-closed，不再打印 rc 就往下走）：
     · DET_default：探针子进程退出码 7（打印 rc 却不阻止 = fail-open，AE2 改为阻止）
  TOOL_EXIT=1                                     ← 拦住了

# 改前（原封的 HEAD 版本，同一个假 godot、同一份非零退出）：
  跑完 DET_default    (4c DetGate/default)  rc=7
  OLD_TOOL_EXIT=0                                 ← 打印了 rc=7，然后照样退 0（fail-open）
```

⇒ **同一份"探针退出码 7 但输出看似完整"的输入，改前退 0、改后退 1。** 这一条最该被读到：
负对照特意让 `data[tag]` **非空**，就是为了证明新增的 rc 拦截**补的是旧的"缺格拦截"补不到的那一面**。

### 2.2 `run_fixtures`：隔离副本**内容寻址**到 committed game 树（不再复用旧树）

**改法**：把上次抽取的 `git rev-parse HEAD:game`（committed game/ 的 tree sha）记在 `iso/.lt_game_tree`；
进来时**只有 marker 与今天的 HEAD:game 逐位相同才复用**，否则擦掉重抽。

**负对照（种一个旧树的 marker，再跑）**：

```
# 种入 deadbeef… 冒充"这份副本是别的 commit 抽出来的"，再跑：
  ♻ 隔离副本原是 game@deadbeefdead ≠ 当前 HEAD:game@7cc8c41fc95e ⇒ 已擦掉重抽（不复用旧树）
# 正对照——紧接着再跑一次（marker 已被写成真值）：
  ↺ 复用隔离副本 game@7cc8c41fc95e（与当前 HEAD:game 逐位相同）
```

⇒ **旧树被识别并擦掉重抽；真树才复用。** 这把派单点的"旧产物复用"这一类在**喂门的那条路上**关掉了。

### 2.3 `bake_ledger`：来源闭环合拢——不盖空 commit、量的树必须==要盖的章的树

**改法**：①`git rev-parse HEAD` 现读，读不到（rc≠0 或空）就**拒绝烘**（旧版只 `except OSError`
⇒ git 非零但不抛异常时 `baked_commit` 被静默盖成 `""`）；②测量用的 `tree_sha` 与当前 `HEAD:game` 不符 ⇒ 拒绝；
③锚里多记一条 `baked_game_tree`，让"量的哪棵树"也留痕。

**负对照（`--self-test`，每次跑，不需要 godot）**：

```
[✅] AE2 来源闭环：非 git 目录 rev-parse HEAD ⇒ None（不冒充成空 sha）
```

### 2.4 `main()`：`_check_ci_defaults` 对不上 ⇒ **拒绝烘**（此前"打印了却不阻止"）

**改法**：旧版 `report()` 印一行"❌ 与 ci.sh 对不上（下面的表在量另一个格子）"然后照样烘。
现在 `main()` 在烘锚前看这条对账，`❌` 开头就 `return 1`——与已有的 `HARD_IDS` 拦截同一个形状。

**负对照（`--self-test`）**：

```
[✅] AE2 ci 对账：默认值全对 ⇒ 不判 ❌（不假红）
[✅] AE2 ci 对账：CI_DAYS 60→20 漂了 ⇒ 判 ❌（拦住烘锚）
```

### 2.5 `recalc_scan.tracked_files`：`git ls-files` 非零 ⇒ 立即失败（不再把空语料读成"0 个数字"）

**负对照**：把 `ROOT` 指到一个非 git 临时目录再调：

```
NC-PASS: SystemExit -> git ls-files 退出码 128（cwd=…\nogit_…）—— 扫描无法建立语料，拒绝返回空集冒充'没有数字'
```

**自检不受影响**：`python tools/recalc_scan.py --self-test` ⇒ `=== SELFTEST PASS ✅（三条分类翻面全部复现）===`。

### 2.6 全 selftest 复跑（不需要 godot）

```
$ python tools/gate_fixture_audit.py --self-test        ⇒ [夹具普查] 负对照 PASS ✅（9 条，含 3 条 AE2 新增）
$ python tools/recalc_scan.py --self-test               ⇒ === SELFTEST PASS ✅ ===
```

---

## 三、报给用户 / 测了之后决定不做的（[docs/41 §4.2](41-baton-contract.md)）

1. **`n_sweep` / `n_curve` / `n_window` / `n_margin` 复用 jsonl 时不绑树——报，不修。**
   它们**确实**是 fail-open（换棵树、旧 jsonl 还在 raw 目录 ⇒ 静默聚合成过期结论）。没修，两条理由：
   - **它们一道门都不喂**（诊断汇总器，产出的是回执里的数，不进 `ci.sh`）。风险面比 `gate_fixture_audit`（喂 2f 门）低一个量级。
   - **正确的 provenance 句柄是 gamedir 的【内容哈希】，不是 git**：`n_sweep` 的 `gamedir` 来自 plan，
     常是工作树 `game`（HEAD 绑定漏掉未提交改动），也可能是每跑一次就换的隔离副本。
     绑 `git rev-parse HEAD` 会给**假**信心。做对要算整个 gamedir 的内容哈希——那是比本波值当的更重的一件事。
   ⇒ **缓解办法是纪律（换树就清 raw 目录），已有的去重 + 半行拦截挡住了最坏的交织。** 若要机器化，这是一张标好价的菜单。
2. **`lint_links` 的 `@branch` 逃生门仍只打印。** X3（[docs/94 §4.2](94-wave-x-x3-fixture-validity.md)）明写这是决定
   （本地分支在别的机器上不存在，判红=换台机器全假红）。**本波不动它**，与那个决定一致。
3. **没重烘入库的 `gate_complement_ledger.json`。** 本波硬化的是**烘它的工具**，不是那份锚。
   重烘要 godot ~12 min 且会移动一份**喂着 CI 门**的入库产物（`baked_at`/`providers` 会随树演化而变）——
   那是一次会动 digest 的受控动作（[docs/41 §3](41-baton-contract.md)），不该顺手做。
   **我用一份 throwaway 锚端到端验了硬化后的烘锚路径不假拒、不改锚的实质**（见 §五）。

---

## 四、§2.5 探测包络（[docs/41 §2.5](41-baton-contract.md)）

本波**没有新增或收紧任何一道 CI 判据**——硬化的是两个**量具**默认 fail-closed。三份包络。

### 4.1 `gate_fixture_audit` 的 fail-closed 硬化（子进程 rc / 隔离副本内容寻址 / 来源闭环 / ci 对账拦截）

```
detects（全部跑出来的）：
  · 探针子进程退出码 7、输出却看似完整 ⇒ 工具退 1（§2.1，before/after 各跑一次：旧 0 / 新 1）。
  · 隔离副本 marker=旧树 sha ⇒ 擦掉重抽；marker=真值 ⇒ 复用（§2.2，负+正各一次）。
  · 非 git 目录 rev-parse HEAD ⇒ None ⇒ bake 拒绝盖空 commit（§2.3 selftest）。
  · ci.sh 默认值漂（CI_DAYS 60→20）⇒ _check_ci_defaults 判 ❌ ⇒ bake 拒绝（§2.4 selftest）。
does_not_detect（跑出来的 / 明写的盲区）：
  · **探针 push_error 但仍 quit(0)**：GDScript 的 push_error 不改退出码 ⇒ rc=0 ⇒ 本次 rc 拦截看不见它。
    兜底是"缺格/缺 seed"的内容拦截（bake 侧），但**单格里某几个 seed 静默少了**这一类，rc 拦截不覆盖。
  · **未提交的 game/ 改动**：`git archive HEAD` 量的是 committed 树 ⇒ 工作树里没提交的改动不进测量
    （这是"从已提交态烘"的**性质**，不是 bug；但读的人要知道量的是 HEAD 不是工作树）。
  · **gamedir 内容哈希级别的漂移**它不管——它绑的是 `HEAD:game` 的 tree sha，不是逐文件内容比对。
  · 它**不判**前件够不够、余量够不够（那是 X3/S2 那两半）；只保证"量的树==盖的章、子进程真成功了"。
confidence: N=6 个变异体——§2.1 子进程 rc（before/after 2 次）、§2.2 隔离副本（负+正 2 次）、
            §2.3 空 sha（selftest 1）、§2.4 ci 漂移（selftest 1）；另 §2.6 全 selftest 9/9。
```

### 4.2 `recalc_scan` 的 `git ls-files` fail-closed

```
detects: 非 git 目录 ⇒ SystemExit(rc=128 那条)（§2.5 跑出来的）。
does_not_detect: git 成功但**返回了别的树的文件清单**（cwd 指错）它不查——它只查"git 到底成功没有"。
confidence: N=1 负对照 + 自检三条分类翻面照常绿。
```

### 4.3 没动的那些量具（复用优先，只复核不改）

`n_curve`/`n_window`/`n_margin`/`recalc`/`gate_complement_guard`/`assert_no_weights`/`brief_mutate` 逐个读过，
它们各自的 selftest 与 rc 处理已经 fail-closed（§一表），**本波一个字节没改**。

---

## 五、CI 判决 + 端到端烘锚验证 + 复跑命令

### 端到端：硬化后的烘锚路径（写 throwaway 锚，不碰入库那份）

```
GODOT=… python tools/gate_fixture_audit.py --run --bake-ledger --ledger <scratch>/probe_ledger.json
```

端到端跑通（写 `<scratch>/probe_ledger.json`，**入库那份 `tools/gate_complement_ledger.json` 没动**）：
`🔨 已烘 …probe_ledger.json（7 夹具 × 35 条 C/G 不变量）· 烘锚时处处空转：（无）· 单点依赖 S0 ← #20`。
锚里新写了 `baked_commit=103d951` 与 **`baked_game_tree=7cc8c41`**（= 本次量的 `HEAD:game` 树，来源闭环留痕）。

> ⚠ **过程中撞出一个既有的假红并顺手修了**：`bake_ledger` 收尾那行 `os.path.relpath(path, ROOT)`
> 在 `--ledger` 指到**别的盘**（C: vs 仓库所在的 E:）时抛 `ValueError` ⇒ 一份**已经烘好**的锚在最后
> print 上崩掉、退出码变 1。这是**假红**（锚已落盘），不是 fail-open，但它会把成功报成失败 ⇒
> 回退到绝对路径。顺带把 `sys.stderr` 也 reconfigure 成 utf-8（否则 traceback 在 GBK 控制台成乱码）。

> ### 一个真发现：**入库的 `gate_complement_ledger.json` 已经过期两波，而没有任何机器在提醒**
> 我把硬化工具**新鲜烘的锚**（HEAD=`103d951`）与**入库那份**（烘于 `abc74b3`，两波前）逐键比：
> `fixtures` 与 `invariant_kinds` **逐位相同**；`providers` 有 **6 条**不同——
> `#22/#23/#24` 入库记「唯一来源 DET_betray」，今天 S0/POOL16 **也**给它们活输入了；
> `#31/#32` 少了 BG30；`#41` 从 7 个来源缩到 3 个（S0/POOL16/BG30）。
> **这正是本波要治的那一类：入库锚的 `baked_commit`（abc74b3）与 HEAD（103d951）不是同一棵树，
> 而 `gate_complement_guard` 不查 `baked_commit==HEAD`** ⇒ 它照着一份两波前的测量在守。
> **它今天【不是】活的 fail-open**：`gate_complement_guard` 现在 `PASS`（exit 0），且新鲜锚的
> `dead_at_bake=[]`（HEAD 上没有任何不变量真的处处空转）；`#22-24` 那个方向是**过严**（fail-safe，
> 入库锚会因 DET_betray 被删而红，即便 S0/POOL16 今天已补上），`#31/32/#41` 都不是单点来源 ⇒ 没有孤儿漏网。
> **但它是一份该重烘的锚。** 重烘会移动一份喂着 CI 门的入库产物（[docs/41 §3](41-baton-contract.md) 的受控动作），
> **本棒不做**——照实报，交用户拍板。这与 `gate_complement_guard` 自己 does_not_detect 里那条
> 「锚过期它一概不知道」是同一件事，现在有了一个**具体的、可复核的过期实例**。

### `bash tools/ci.sh` 的实际输出（**读输出，不是读退出码**）

<!-- CI_RESULT -->

### 复跑命令（每一条都能重算）

```bash
# 全 selftest（不需要 godot）
python tools/gate_fixture_audit.py --self-test          # 9 条，含 3 条 AE2
python tools/recalc_scan.py --self-test                 # 三条分类翻面

# §2.1 子进程 rc 负对照（fake godot：--import 退 0、探针退 7）
python tools/gate_fixture_audit.py --run --only DET_default --godot <fake_godot(exit 7)>   # ⇒ 退 1

# §2.2 隔离副本内容寻址负对照
printf 'deadbeef…\n' > <tmp>/lt_gate_fixture_iso/.lt_game_tree
GODOT=… python tools/gate_fixture_audit.py --run --only DET_default    # ⇒ ♻ 已擦掉重抽
GODOT=… python tools/gate_fixture_audit.py --run --only DET_default    # ⇒ ↺ 复用

# §2.5 recalc_scan 负对照
python -c "import sys,tempfile;sys.path.insert(0,'tools');import recalc_scan as R;R.ROOT=tempfile.mkdtemp();R.tracked_files()"  # ⇒ SystemExit
```

原始输出留在本次 session 的 scratchpad（探针输出不是资产，不入库）。
**本棒不移动任何 digest**：没改 `game/**`、没改 `tools/ci.sh`、没重烘任何入库的锚。

---

## 六、如果只读一句

**这个仓库的量具绝大多数早已 fail-closed；派单点的三类 fail-open（旧产物复用 / 子进程非零只打印 /
来源没成闭环）在【喂着门的那条路上】集中在同一个工具——`gate_fixture_audit` 的烘锚流水线——
而它此前补过的拦截恰好漏了这三面。** 本波把这三面补齐，每一面带一个跑出来的负对照；
`recalc_scan` 那处 `git ls-files` 的 swallow 顺手也关了。**其余量具一个字节没动。**
