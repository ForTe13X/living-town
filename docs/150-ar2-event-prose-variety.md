# 150 · AR2 · 叙事内容棒：编年史散文质量提升（措辞变体）（lane-3 storylet 第二片 L3-b，零金标）

> 底稿 docs/143 §三/§四（L3-b）。首选 A（`Main._event_prose` 散文更生动/更多样），不动 goals（见 §六，B 面天花板实测）。
> owns：`game/scripts/Main.gd`（`_event_prose` + 新 `_pick`）+ 本文 + `analysis/ar2/`。**没碰** Sim.gd / event_log / RNG / Inv.digest / event_digest / chain / golden / gate_* / goals.json / Goals.gd / Story.gd / WorldView / personas / 经济。
> worktree `agent-a0582c57c690c48df` · 分支 `worktree-agent-a0582c57c690c48df` · ff 自 `integration/batons`@`b505771`（含 AR1/AT1/E1，祖先已核）。

## 〇、一句话
每类事件此前**逐类只有一条模板** ⇒ 同类事件在播报栏/编年史里**逐字刷屏**。本片给 19 个上屏事件类型各配 2-3 条同义变体，用一个纯 View 的稳定折叠器 `_pick` 按事件身份选一条 —— 同一事件实时播报与回放重建必得同一句，对金标零扰动。AE1（被拒叙述"被拒"）**逐条变体都守住**。

## 一、现状清点（**实读核对，纠正协调者/docs 三处断言**）

### `_event_prose` 覆盖面（改前）
`func _event_prose`（改前 Main.gd:2123）逐 `type` 一条 `match` 臂，成文口径为**实时播报 `_push_event` 与回放重建 `_rebuild_feed` 共用**。上屏路径先过 `FEED_SKIP = [pay, world, produce, consume, spoil, shortage, import]`（Main.gd:287）⇒ 这 7 类**永不到达 `_event_prose`**（经济族 + world；world 的纪事只在 `goals.json` 里被 Goals.gd 只读折算）。
- ⇒ **实际上屏的 19 类**：greet/give/gossip/invite/meet/conflict/confront/apologize/mediate/betray/confide/leak/gossip_rep/endorse/discuss/aid/rally_oust/pact/election，**每类都已有专臂**；未知类落 `Sim._verb(t)` 兜底、再退到"起了点事"。
- **纠正协调者断言①**（"给更多 event type 好措辞"）：不是有类型**缺**措辞 —— 19 个上屏类**都已有**措辞。真缺口是**每类只有一条模板**（重复），这才是本片治的。
- **纠正协调者断言②**（"`_event_prose` 约 2120"）：改前在 **2123**。

### 被拒叙述现状（AE1，docs/118）
改前 AE1 **已完整落地**：10 个通用社交类（greet/give/gossip/invite/confide/leak/gossip_rep/endorse/discuss/aid）+ meet/confront/apologize/mediate 都已 `if ok else` 分岔，被拒讲"被婉拒/没接茬"。`event_prose_test`（AE1 门）改前**已 PASS**（`analysis/ar2/`：改动前基线绿）。
- **纠正协调者断言③**（"被拒事件叙述'被拒'"当作待做项）：AE1 **不是待做**，是**已成立的不变量**。本片的义务是**在每条新变体上维持它**（做到了，§四）。

### goals 面板行预算（B 面天花板，实测）
`Goals.panel_text()`（Goals.gd:250）实际逻辑行 = 标题 1 + 11 目标各 1 + **仅 1 条**"下一步"提示（`hinted` 标志只在**首个**未达成目标后插一次）+ 页脚 1 = **14 逻辑行**（全达成时 13）。
面板容量：`GOALS_SZ=(344,280)`（Main.gd:314）⇒ 正文框高 `280-12=268px`，字号 **14**（Main.gd:710）⇒ 渲染行距 ≈ `14+4=18px`（项目冻结经验式，Main.gd:303）⇒ **≈14.9 视觉行**。中文提示行可能折 1 行 ⇒ 现绘 ~14-15 视觉行 **已顶到容量**。`scroll_active=false` 溢出**静默裁尾**（D2 教训）。
- **纠正/精化协调者断言④**（"11 条目标×2 行已逼近行预算"）：那句里的"11×2=22"是**最坏假设**（若每条目标都显 2 行）不是现状；现状是 **14 逻辑行 vs ~15 视觉行容量**，即**当前就在天花板**、再加第 12 条目标必**静默裁尾**。面板下沿到 `LOG_SCRIM_TOP=414` 尚有 92px（~5 行）竖向余量 ⇒ **要加 goal 必先抬 `GOALS_SZ.y`**（碰 HUD 几何/scrim，blast radius 大）。
- **决定：不动 goals**（B 面）—— 加 goal 的净收益低、且要碰面板几何，超出"最小 blast radius 只在 Main.gd 散文侧"的取舍。见 §六。

## 二、改动（纯 View：`_pick` 折叠器 + 逐臂变体数组）
1. **新 `_pick(variants, e)`**（Main.gd:2126）：从事件身份 `id|actor|target|subject|tick` 拼 key，`String.hash()` 取模选一条变体。
   - **确定性**：纯读 `e` 的字段 + 项目无关的 `hash()`，**绝不碰 Sim/RNG/不进 event_log** ⇒ 同一事件实时/回放必同句（`_rebuild_feed` 回扫 event_log 尾部重渲，事件字段不变 ⇒ 折出同一下标）。
   - `id` 进 key 是为了**打散**同类连续事件（`id` 是账本单调计数、回放稳定）；合成测试事件无 `id/tick` ⇒ 折到固定下标（故每条变体都须自洽 AE1）。
2. **逐臂改写**：19 个臂 `return X` → `return _pick([X, X', X''], e)`；带 `ok/reject` 的臂两侧各一组变体；带 `C`（subject）分支的 gossip_rep/endorse 保持 2×2 结构、每叶 2 变体；betray 保持 `C==""`/`C!=""` 两分支各 2 变体；rally_oust/pact/election 保持各自条件分支、每分支 2 变体。颜色 BBCode **逐臂逐极性不变**（语义配色不动）。
3. **文案纪律**：① 每条**接受**变体含该类型 `event_prose_test.SUCCESS_PHRASES` 的关键短语、不含任何被拒词库词；② 每条**被拒**变体含 `REJECT_LEXICON` 一个词、不含成功短语；③ **不新增"口"字形**（R10 豆腐块规矩，goals.json `_meta` 记）——新变体一律回避 `口`（既有 `统一了口径` 是 test 必需关键短语且早已出货，保留）。

`git diff --stat`：`game/scripts/Main.gd | 202 +++++-- ` · **1 file changed, 181 insertions(+), 21 deletions(-)**。`_pick`@2126、`_event_prose`@2137-2338。

## 三、改前/改后眼验（真引擎，windowed 真 framebuffer · AMD Radeon OpenGL3 · 700×600）
同一批**固定** 18 条事件（真居民名，`analysis/ar2/eyeball_probe.gd`）喂进【真】`Main._event_prose`、铺进与 `Main._logbox` 同配的 RichTextLabel（`Art.font()` 得意黑 + 字号 15），renderer 渲一帧。改前=`git stash` Main.gd（HEAD 旧版）、改后=working。
- **`docs/media/ar2_feed_before.png`**（改前，单模板刷屏）：3 条 greet **逐字相同**「X 找 Y 唠了两句」；3 条 discuss 全「X 和 Y 聊起了各自的看法」；2 条 gossip 全「X 悄悄向 Y 传了个八卦」。
- **`docs/media/ar2_feed_after.png`**（改后，同类轮换）：greet →「找…唠了两句」/「在路上碰见…站住唠了两句」/「拉着…唠了两句家常」**三条各异**；discuss/gossip/give/… 同类多措辞；被拒仍讲「没接茬/被婉言谢绝」。
- 两图**真中文字形**（非豆腐块）、BBCode 配色对、`%A/%B/%C/%d` 全填好无占位符残留。

## 四、AE1 逐条守住（本片的牙齿）
- **可分性门**（`event_prose_test.tscn`，CI 口径）：10 受影响类 × {接受/被拒} × {C!=""/C==""}（gossip_rep/endorse）共 **36 断言全绿** —— 每类被拒版≠接受版、接受含成功短语无被拒词、被拒含被拒词无成功短语。**改后 PASS**（`analysis/ar2/event_prose_census.txt` 抬头）。
- **普查门**（`--census`，真 event_log，**跑了 seed 7 与 seed 3 两轮**）：seed7 受影响类**被拒 565 条**（greet 98 / gossip 36 / gossip_rep 374 / discuss 57）、seed3 **被拒 653 条**（greet 138 / gossip 26 / gossip_rep 445 / discuss 44），**两轮都 0 条被讲成成功** ⇒ 真事件上（id 轮换出的**多条被拒变体**）AE1 逐条成立。`✅ 普查门：0 条`（`analysis/ar2/event_prose_census.txt` seed7 · `census_seed3.log` seed3）。
- **诚实边界（实测）**：两轮普查里**只有 greet/gossip/gossip_rep/discuss 会 accepted=false**；give/invite/confide/leak/aid/endorse 在默认沙盘上**运行期一条都不被拒**（这也说明它们的被拒变体是"稳健兜底"而非高频路径）。故这 6 类的被拒 v1/v2 未被普查直接命中：v0 由**可分性门**逐类验、v1/v2 由**构造保证**（每条逐字含库词、不含成功短语，§二纪律，已逐条静读复核）。高频被拒的 4 类则被 2 seed × 数百条真事件机器验穿。

## 五、零金标三证据（**含 chain**；跑不动就是碰了仿真侧 —— 没跑动）
1. **S0 金标 12/12 seed 逐字节相同 + 逐 tick 前缀链**：改前 `analysis/ar2/s0_before.txt`、改后 `s0_after.txt`（`Harness.gd --seeds 1-12 --days 60 --det 3 --golden`）。
   两份的 12 条 `[S0] {digest, event_digest, chain, events}` 行**逐字节相同**：`s0_before_lines.txt` 与 `s0_after_lines.txt` **sha256 同为 `95ebf168…7bb95`**。改后判决 `=== S0 GATE: PASS ✅（硬 12/12、软≥11/12、活性、金标、det 3/3）===` · `✅ 金标一致 12/12 seed（含逐 tick 前缀链 12 条）`。
   ⇒ **chain 逐条未动** ⇒ Sim 读不到本片的改动 ⇒ 确在 View 侧。
2. **event_prose_test A0≡A1**：门只 `.new()` 一个 Main 调 `_event_prose`、从不写世界态（与 goals_test 同路）；改前/改后都 PASS ⇒ 挂/不挂本渲染对仿真态零扰动。
3. **owns 面外零触**：`git status` 仅 `M game/scripts/Main.gd`；未碰 Sim.gd/event_log/RNG/Inv/golden/gate_*/goals.json/Goals.gd/Story.gd。

## 六、B 面（goals 小扩）决定：**不做**，附实测预算（对齐 docs/143 §四要求"先量清"）
§一已量：面板**现绘 14 逻辑行 vs ~15 视觉行容量、当前即天花板**。加第 12 条目标必**静默裁尾**，除非先抬 `GOALS_SZ.y`（碰 scrim 几何、chrome 占屏，docs/46 §一 #5 已警"25.5% 是 chrome"）。净收益低、blast radius 大 ⇒ 本片**只落 A 面**（Main.gd 散文），goals.json/Goals.gd **一字未动**。

## 七、CI 判决行
提交前互补性守卫**不算数**（比 committed HEAD:game，docs/140；协调者 committed 树重烘重跑）。本片跑 `bash tools/ci.sh`（`analysis/ar2/ci_full.txt`）：
- 与本片相关的门**全绿**：S0 金标 12/12 含链、`import/parse clean`、`event_prose_test PASS`、goals_test/story_test（未碰，绿）、asset/recalc 等。
- **唯一红**：`互补性守卫` 报 `锚 STALE：baked_game_tree=f17ac3f9… ≠ HEAD:game=24b441f7…`。**实证此红与本片无关**：`git show HEAD:tools/gate_complement_ledger.json` 的 `baked_game_tree=f17ac3f9…` 与 `git rev-parse HEAD:game=24b441f7…` **两个 committed 值本就不等**，且**我没碰 ledger**（`git status tools/gate_complement_ledger.json` 空）⇒ 这是 integration/batons **committed 树自带的锚陈旧**（AT1 等改了 game/ 子树后 ledger 未随committed HEAD 重烘），正是 docs/140 说的"协调者 committed 树重烘"那一类。**留给协调者 finalize 重烘。**

<!-- CI_VERDICT_PLACEHOLDER: 待 ci_full.txt 收尾回填末行 -->
