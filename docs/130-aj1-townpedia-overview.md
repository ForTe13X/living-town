# 130 · AJ1 · 镇民百科【横切总览】——关系图谱 + 镇级年表 + 派系/冲突（回执）

> wiki 轨道续作。基线 `integration/batons`（本 worktree ff 到 `6666d6a`）。
> 前置：docs/41（红线 #2 / §2.5）、docs/115（AD1 逐居民百科）、docs/114 §一。
> **纯渲染层：只动 `tools/gen_town_wiki.py`（Python），仿真侧一字节没动**——
> 导出 JSON `analysis/wiki/seed07/town_wiki.json` git diff 为空即证（见 §四）。

## 〇、一句话

在 AD1 逐居民百科之上，**从同一份只读投影 JSON 归纳出三个【横切总览】视图**——
① 全镇关系网络图（自包含 SVG），② 镇级大事年表（跨居民），③ 派系与冲突概览。
**不重复逐 NPC 已有内容，也不发明情节**：每条边指回一条真实 `relationship`、每条年表项指回一条真实 `event.id`。
渲染器纪律由扩展的 `--gate` 守（§2.5 三行包络 + 4 种伪造项的负对照）。

## 一、现状清点（先量，别假设）——AD1 已经渲染了什么

实读 `tools/gen_town_wiki.py`（改前 699 行）与 `game/bench/wiki_dump.gd`：

| 已有（逐 NPC，`render_agent` 行号为改前） | 出处 |
|---|---|
| 花名册 + 每人一页 | `build_html` :538-548 |
| 五需求条 / 关系账本表（亲密·信任·怨气·名声） | `render_agent` :351-373 |
| 信念（CR/TR/SH/W/秘密）+ 反向声誉 | :377-380, `render_beliefs`/`render_reputation` |
| 故事弧（数据归纳）| `render_arc` :444-478 |
| **逐 NPC 大事记**（每条 `#<id>` + `data-ev`，被拒 `accepted=false` 如实标）| `render_chronicle` :481-500 |
| 高频事件聚合 | `render_ambient` :503-521 |
| 可追溯性门（逐条追溯 + 社交被拒如实标）| `run_gate` :563-613 |

导出 JSON（`town_wiki/v1`，`wiki_dump.gd:134-149`）字段：`agents[]`（含
`relationships{oid→{affinity,trust,resentment,familiarity,standing,last_pos,last_neg}}` :164-173、
`faction`/`faction_size` :213-214、`beliefs`/`memory`）、**整条 `events[]`**（`{id,tick,type,actor,target,subject,accepted,witnesses,note}` :120-127）。

**⚠️ 协调者断言"要加横切总览"——实读证实这三样确实【不存在】**（`grep -iE 'svg|network|timeline|overview'` 改前仅命中 1 处 JS 无关行）：
- 关系**只**逐 NPC 成表，**无全镇网络图**；
- 大事记**只**逐 NPC，**无跨居民的镇级时间线**；
- `faction` **只**出现在单人 tags/roster，**无派系花名册/施压/高怨气对的聚合页**。
⇒ 我加的是**横切新视图**，不是重复逐 NPC。

## 二、做了什么（三视图，纯从已有 JSON 建）

新增全在 `tools/gen_town_wiki.py`（`build_overview` / `render_overview` / `render_network_svg` /
`town_prose` / `build_overview_doc` + 门 `validate_overview` / `overview_negative_control`）。

1. **① 关系图谱（自包含 SVG，离线，无外部依赖）**：12 节点、**按派系分弧的确定性圆布局**（`i·2π/N`，
   无随机、无力导——见 `build_overview` 的 `fac_rank`）。节点填色=人格 color，描边=派系色。
   边=无向对（有向账本聚合：亲密取均值、怨气取最大），**绿=亲密 / 红=怨气·结怨，粗细+透明度=强度**。
   收边阈值写进图注：`|亲密|≥20 或 怨气≥8` ⇒ 49 条边 / 全镇 66 对（友好 23·敌对 26；此镇敌对多于友好）。
   每条 `<line>` 带 `data-a/data-b/data-aff/data-res`（机读+可追溯）；节点是指向 `#npc-<id>` 的链接。
2. **② 镇级大事年表**：跨居民、按 `(tick,id)` 升序，收录 `TOWN_TIMELINE_TYPES`（选举·盟约·施压·背叛·
   调解·接济·吐露·结盟·对质，本 seed 88 条）。**每条 `#<id>` + `data-ev`**，`outcome` 直接复用
   `Wiki.prose(e,actor)[1]`（与逐 NPC 页同一真源）⇒ 被拒/未成/冲突按 `accepted` **如实标**。
   高频摩擦（口角 76·断货 40）**不刷屏**，聚合进③（在图注里明说取舍，不悄悄砍）。
3. **③ 派系与冲突概览**：派系花名册（4 派：阿丽/老邓/阿林 派 + 散居 4 人）、**联合施压**（`rally_oust`
   按 target 聚合：谁被围攻、谁牵头、场次、最多响应、event 引用）、**高怨气对 Top**（源自关系账本，
   附彼此 `conflict` 次数与 event 引用）。

产物：主页 `town_wiki.html` 顶部加"横切总览"段 + 独立自包含 `town_overview.html`（docs/media 交付用）。

## 三、可追溯性门（§2.5 三行包络 + 负对照）——`--gate` 实际输出

```
[gate] PASS
[gate] 大事记行=1961 全部可追溯=True；社交被拒 932/932 如实标注；全镇社交被拒 event=498
[gate] 总览：边=49/66对 年表=88 施压目标=5 怨气对=48 全部可追溯=True（违规 0）
[gate] 负对照：注入 V1/V2/V3/V4 → 逐项抓到=True（毒化后违规 4 条）
```

**detects**（实测变红）：
- 大事记引用不存在的 event id（发明/串号）⇒ 红（逐 NPC，沿用 AD1）。
- 社交类 `accepted=false` 谎标成 happened（AA2 的 27.4% 病）⇒ 红。
- **【总览】网络边指向账本里不存在的一对，或边的 亲密/怨气 与账本重算不符 ⇒ 红**（负对照 V1/V2）。
- **【总览】年表引用不存在的 event id，或把社交被拒谎标 happened ⇒ 红**（负对照 V3/V4）。

**负对照实测**（`overview_negative_control` 每次 `--gate` 自跑）：往【真】总览注入 4 种伪造项——
V1 幽灵边(aria—__ghost__)、V2 篡改 qin—shu 亲密、V3 不存在 event #13234、V4 社交被拒 #17 谎标 done
——`validate_overview` **逐一抓到（4/4）**。另端到端复核：把幽灵边/假年表项塞进 live overview 跑 `run_gate`
⇒ `verdict=FAIL`（"网络边引用了不存在的居民"/"年表引用了不存在的 event id"）。

**does_not_detect**（明写抓不到的）：
- 年表/边**措辞的语义保真度**（subject 指错人、器物/年代错）——只校 `accepted` 与 `id` 两位。
- Sim 自身把事件标错 `accepted`（wiki 层如实转写，不复核 Sim 判定）。
- 非社交 `accepted=false`（shortage/conflict 结构性 false）——不套被拒框。
- **收边阈值 / 年表类型选择是否"合适"**——门只校"被显示的每一项有真源且数值一致"，不评判取舍口径（阈值透明写在图注）。
- **有向→无向的聚合口径**（亲密均值 / 怨气最大）是否"最优"——门只断言渲染值 = 按此口径重算值。

**confidence**：seed 7 / 60 天 / 12 NPC；负对照 N=4 变异体逐一被抓。收据 `analysis/wiki/seed07/traceability_report.json`。

## 四、零仿真改动的证据

- `git status` 中 **`game/` 无任何改动**（`git status --short -- game/` 为空）。
- 导出投影 `analysis/wiki/seed07/town_wiki.json` **git diff 为空**（byte-identical）⇒ 未碰 `wiki_dump.gd`/`Sim.gd`/`game/data`。
- 改动仅：`tools/gen_town_wiki.py`（渲染器）+ 其**再生成**的 `town_wiki.html`/`traceability_report.json`
  + 新增 `town_overview.html`、`docs/media/aj1_*`、`analysis/aj1/`、本 doc。
- wiki **未接进 `tools/ci.sh` / `.github`**（`grep -iE 'wiki|gen_town'` 均无命中）⇒ 无 CI wiki 步骤需跑；
  相关门即 wiki 自带 `--gate`（上 §三 PASS）。

## 五、这份 brief 哪里对不上（§4 诚实节）

- brief 说"betray/施压…按时间线排"——实读本 seed **betray/mediate/leak = 0 条**（`pact`3·`election`4·
  `rally_oust`20·`aid`8·`confide`7·`endorse`13·`confront`33）。代码对 0 条类型有兜底，年表照常成立，
  只是这三类此局不出现（换 seed 会出）。
- brief 提示"现有 wiki 可能已很全，先量"——**确认属实**：逐 NPC 关系/冲突/信念/故事弧/大事记 AD1 都做了，
  且 election/施压/betray 都在逐 NPC 页渲染。我严格只加**横切聚合**，未重造逐 NPC 轮子。
- brief 担心"可能缺某聚合字段要碰 `wiki_dump.gd`"——**不需要**：关系账本 + 整条 event_log 已全量导出，
  三视图纯从 `town_wiki/v1` 建成，导出器一字节没碰。
- brief 举例年表应含"冲突"——我**有意**把 76 条口角 + 40 条断货移出年表、聚合进③（否则淹掉 55 条真正
  改变格局的高信息事件）。此取舍写进图注、不藏；门对此显式 `does_not_detect`（不评判取舍，只校每项有真源）。

## 六、交付

- 代码：`tools/gen_town_wiki.py`（+548 行，纯渲染）。
- 页面：`analysis/wiki/seed07/town_wiki.html`（顶部加总览段）、`analysis/wiki/seed07/town_overview.html`（独立总览页）。
- 媒体：`docs/media/aj1_overview.png`（关系图谱截图，headless Chrome 眼验）、`docs/media/aj1_town_overview.html`、
  `analysis/aj1/aj1_town_overview.html` + `aj1_overview.png` + `traceability_report.json`。
- 门收据：`analysis/wiki/seed07/traceability_report.json`（§2.5 包络 + 负对照 4/4）。
