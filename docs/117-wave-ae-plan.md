# 117 · Wave AE 计划——**清 Phase-1 两笔正确性欠账：纪事把被拒讲成成功；验证工具 fail-open**

> 前置：docs/113 路线图（§二 正确性欠账、§五 相位）、docs/116（AD2 事件结果模型设计，档0 就是本波 AE1）、
> docs/41 合同。外部评审 Codex red #2（fixture fail-open）与 red #3（被拒叙述成成功）。
> **回执带 §2.5 三行包络，`does_not_detect` 必须跑出来。两根 owns 文件级不相交。**

## 〇、为什么这两根、为什么现在

分支实测：trunk `16e1880` 当前；narrative/AC 空闲；只有 Codex 在做 docs 评审 ⇒ 低争抢窗口。
路线图 §五：**Phase 1（清正确性欠账）优先于新内容**。上一波做了 wiki（功能），本波回到 Phase 1。选这两根，因为：
- **AE1（档0 纪事修复）** 是 AD2 实测出来的**零 schema、零金标低垂果实**（docs/116），从**表现层**消掉 27.4%。
- **AE2（fixture fail-closed）** 是 Codex red #2、**低成本复用**的基建加固——它硬化的是全 session 依赖的量具。
两根 owns：AE1=`game/scripts/Main.gd`，AE2=`tools/**`ᐧᐧᐧ⇒ **文件级不相交**。

## 一、AE1 · 纪事不再把被拒讲成成功（**表现层，零金标**）

**owns**：`game/scripts/Main.gd`（只动 `_event_prose`）、新建一个**新的** bench 测试（**别碰 `story_test.gd`**——那是 AC2 wip）
**不得触碰**：`game/scripts/Sim.gd`、`game/scripts/Story.gd`、`game/data/**`、`game/bench/` 现有文件、`tools/**`、`game/scripts/narrative/**`
**你的编号文档**：**118**（正文别写 `docs/`+数字纯文本指向 119）

### 现状（我已实读 `Main.gd:2120-2148`，给你坐标）

`_event_prose(e)` **读了** `accepted`（`:2125` `var ok := bool(e.get("accepted", false))`），
且 `meet/confront/apologize/mediate` **已按 `ok` 分岔**（成/败两套文案）。
**bug 是**：`greet·give·gossip·invite·confide·gossip_rep·endorse·discuss·aid` 这些社交类型**不看 `ok`，恒讲成发生了** ⇒
`accepted=false` 的那一笔在纪事里被写成"做成了"。这正是 AA2 实测的 976 条（3565 里 27.4%），
也是真机 docs/111 那屏"想找阿丽聊起了看法，被婉拒了"→纪事却说"聊起了看法"的活证。

### 要做的

给上面那批社交类型加 `if ok else` 的**被拒**分岔（照抄 `meet`/`apologize` 已有的写法：接受走原文案、被拒走"被婉拒/没接茬/话没递进去"这类）。
⚠️ **按事件族拆清楚**（AD1/AD2 两路已证的那条纪律）：
- 只给**真能被拒的社交类型**加分岔（`KNOWN_SOCIAL_ACTIONS`，走 `_acceptance_rule` 的那些）；
- **经济族/固定标记别碰**（produce/pay 恒 true、conflict/shortage 恒 false，它们不进 `_event_prose` 的社交分支就别管）。
- `leak`/`betray` 已有各自文案，判断它们的 `accepted` 语义再决定动不动。

### 硬要求

1. **仿真侧逐字节不变**——`_event_prose` 是表现层，不在 Harness 金标路上。**用 digest 证明**（自造 A/B + 留出 seed）。
   ⚠️ 若你发现 `_event_prose` 竟然进了某条金标路（不该，但去查），那就停下写进回执，别硬改。
2. **新增一道回归门**（新 bench 文件，**不是** story_test.gd）：构造每个受影响社交类型的 `accepted=true/false` 两版事件，
   喂给 `_event_prose`，断言**被拒版的文案与接受版可区分**（含被拒语义、不含"做成了"语义）。
   §2.5 三行包络 + **双向负对照**：把某类型的被拒分岔删掉 ⇒ 门必须红；正常 ⇒ 门绿。
3. **量修好了多少**：跑一格（seed 7 或你选的，60 天），统计 `_event_prose` 输出里
   "被拒事件被讲成成功"的条数**改前 vs 改后**（改前应≈AA2 那条量级，改后应≈0）。**给数字。**
4. `bash tools/ci.sh` 全绿（**读输出**）。

### 验收（AE1）
1. diff（只 `Main._event_prose` + 新门文件）；digest 不变的两条证据。
2. 新回归门 + 双向负对照的实际输出。
3. 改前/改后"被拒讲成成功"条数对照。
4. CI 判决行。§2.5 三行包络。

## 二、AE2 · 验证工具默认 fail-closed（**只 `tools/`，Codex red #2**）

**owns**：`tools/**`（具体见下）、你的编号文档 **119**
**不得触碰**：任何 `game/**`、`docs/` 下除你自己那份外
**你的编号文档**：**119**（正文别写 `docs/`+数字纯文本指向 118）

### 要回答的

Codex red #2：fixture/scale 验证工具可能 **fail-open**——旧产物复用、子进程非零退出码只被打印没被计失败、
产物来源/ledger HEAD 没成可信闭环。**先量，别假设很多**（U3/X3 两次先验"很多"、实测"集中在少数"）：

1. **普查 `tools/` 下会跑子进程或复用产物的量具**（`n_sweep.py`/`n_curve.py`/`n_window.py`/`gate_fixture_audit.py`/
   `recalc*.py`/`brief_mutate.py` 等）：逐个判**子进程非零退出码有没有被可靠计入失败**、**产物是不是 fresh 或 content-addressed**、
   **有没有绑 commit/tree/godot 版本**。**给一张表：哪个工具在哪一点 fail-open。**
2. **把确实 fail-open 的改成 fail-closed**：子进程非零 ⇒ 立即失败（非只打印）；产物 ⇒ fresh 或内容寻址；
   **每处改动带负对照**（造一个子进程返回非零 / 喂一份旧产物 ⇒ 工具必须失败）。
3. ⚠️ **别把 CI 弄红**：若某工具改成 fail-closed 后**当前树上就会失败**（说明它一直在放过真问题），
   **那是发现不是要当场硬压绿的 bug**——照实报，说明它失败是因为真有问题还是因为夹具本身要调。
4. ⚠️ **"打印了却不阻止就不是检查"**——本 session 在 `gate_fixture_audit` 上撞过（打印"❌对不上"然后照样烘）。
   **你改完的每个工具，都要能真的拦住**，跑一次负对照证明。

### 验收（AE2）
1. fail-open 普查表（**给比例**，别一上来假设很多）。
2. 逐处 fail-closed 改动 + 负对照实际输出。
3. `bash tools/ci.sh` 全绿（读输出）；若某工具改后当前树会红，照实报并说明原因。§2.5 三行包络。

## 三、共同约束（见 docs/113 §六，照抄）

- docs/41 红线四条；**改契约/金标口径/判据/schema 是用户的决定**。
- **红数不是判据**；**"金标 N/N 不变" ≠ "该 N 不变"**；**可比性 ⟺ 两棵树 `game/scripts/`+`game/data/` 逐字节相同**。
- **先确认你量的是哪个对象**（H1/S3/V3/W3/Z2/AA3 一串教训）；**看到"零引用"先 `git log -S`**。
- **一个检查若"打印了却不阻止"就不是检查**；**一次 push 可退出码 0 报"已同步"却什么都没推**。
- **别在别的 session 的分支/checkout 上写**；**别在 CI 跑时改它正在读的文件**；**tee|tail 吃退出码 ⇒ 写文件再读**。
- 编号三位数；**118 属 AE1、119 属 AE2**；正文别写指向对方号的 `docs/`+数字纯文本（lint_links 检查(2) 本 session 抓过我多次）。
- **worktree checkout 可能落后很多 commit**：先确认基线 `integration/batons`（`16e1880`）是祖先才 ff。
- 隔离副本做负对照；越界要声明。
