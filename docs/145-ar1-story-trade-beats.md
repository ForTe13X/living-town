# 145 · AR1 · 叙事内容棒：已有弧新幕「银钱往来」（lane-3 storylet 第一片，零金标）

> 底稿 docs/143 §三（L3-a）。owns：`game/scripts/Story.gd`（ARCS + 一条 PHRASE_LOCK）+ `game/scripts/story_test.gd`（F10 正对照）+ 本文 + `analysis/ar1/`。**没碰** Sim.gd / Inv / golden / gate_* / goals.json / Main.gd / WorldView / compositor。
> worktree `agent-a24ff7e167fc44e16` · 分支 `worktree-agent-a24ff7e167fc44e16` · ff 自 `integration/batons`@7dbc13a。

## 〇、一句话
往三条**已有弧**（grudge/pact/craft）各加一幕 `traded`：`{"type":["pay"]}` ⇒ 「%A 与 %B 之间的银钱往来（一直没断）」。这是 docs/113 §四「买卖弧进 storylet」的落点——但**不是**它设想的那个方向（那个方向被普查判了死），见 §二。

## 一、命门：先跑普查（`analysis/ar1/census_probe.gd`，12 seed × 60 天，N=12）

⚠️**先纠正 docs/143/协调者的一处断言**：命门段写「跑 `story_test --stats` 读 `stats()` 逐弧种矩阵——量『有几条事件落在已开着的弧的有向对上』」。**实读发现 `--stats` 给不出这个量**：`stats()`(Story.gd:939) 只吐每条弧的 opened/closed/ends/open/kept（弧的生命周期），**不吐候选事件的落地数**。docs 里那些参照数（sided=147、give=4/432、discuss 1151→319）是 docs/98/90 用**专门探针**跑的，不是 `--stats`。故我照那个口径**重写了探针**（`analysis/ar1/census_probe.gd`）：逐事件折叠，在折入第 i 条**之前**用当下 `_open` 探这条事件落在哪些弧的哪个方向——纯幕候选不改弧生命周期 ⇒ 上界良定义。

### 弧量（聚合 `stats()`，终身口径）
| arc | opened | closed | open | kept |
|---|---|---|---|---|
| grudge | 1096 | 909 | 187 | 13 |
| promise | 993 | 993 | 0 | 371 |
| secret | 85 | 1 | 84 | 0 |
| pact | 43 | 3 | 40 | 0 |
| craft | 496 | 92 | 404 | 0 |

⇒ **有真正开着的有向对的只有 grudge / craft**（各 187 / 404 在跑）；promise 秒开秒收（invite→meet，0 中间幕可落）；secret/pact 到 60 天才开出几十条（20 天时 0，docs/143 那条「short horizon 全 0」实测确认）。

### 可落地上界 · PAIR_TARGET=(actor,target)，每格 fwd+rev=合计
| type（全局总数） | grudge | secret | pact | craft |
|---|---|---|---|---|
| **pay**（13573） | **947** (475+472) | 385 | **181** (122+59) | **1440** (880+560) |
| discuss（1215） | 358 ←已 `talked` | 0 | 0 | 329 ←已 `talked` |
| gossip（602） | 122 ←已 `whisper` | 0 | 0 | 113 ←已 `whisper` |
| give（432） | 2 | 0 | 0 | 1 |
| aid（90） | 1 | 96 ←已 `aid` | 90 ←已 `aid` | 28 ←已 `handed` |
| endorse（201, **subject 维**） | 136 ←已 `sided` | 0 | 0 | **157**（30 fwd + 127 rev） |

### pay 的 note 组成（全局）与落地拆分（这是选幕的**决定性**一步）
`pay` note 全局：`buy:`=832 · `rent`=2666 · `price:`=6321 · `wage:`=3754。
其中 `price:`(人→镇库) / `wage:`(镇库→人) **一端是 NON_AGENT** ⇒ 一条都落不了地（矩阵里 price:/wage: 行全 0，机器证）。能落地的只有 person→person 的 `buy:`(找商贩买货，Sim.gd:1523) 与 `rent`(房客→房东，Sim.gd:1599)。

| note | grudge | secret | pact | craft |
|---|---|---|---|---|
| buy: | 202 (118+84) | 109 | 60 (1+59) | **338 (0 fwd + 338 rev)** |
| rent | 745 | 276 | 121 | **1102 (880 fwd + 222 rev)** |

## 二、被普查判死的天真设想（本片的头条发现，与 give=4/432 同形）
我本以为最顺的一幕是 **craft +「看客买下了匠人的活」**——买家=看客(A)、卖家=匠人(B) 那个 `buy:` **fwd** 方向。
实测：**craft 弧上 `buy:` 的干净 fwd 方向落地 = 0 条**（rev 338、fwd 0）。匠人未必是摊贩，看他干活的人也未必回头买他的货。craft 那个诱人的 880 fwd **全是 `rent`**（看他干活的人也住他屋檐下缴租），不是买卖。
⇒「手艺 = 最好卖 / 看客会买」这个先验是错的，**只有量才看得出来**（同 docs 里 give 的下场：「送礼是最有关系含量的动作」也是错的先验）。本次 `give` 实测 grudge 2 / craft 1 / 其余 0，比 docs 的 4/432 **更死**。

## 三、选幕（据实测，3 幕；都 > sided=147 那条下界，都不认是买是租）
活下来的读法：**不认哪一笔**——`matcher` 不筛 note（price:/wage: 反正落不了地），`buy:` 与 `rent` 的共同真值只有一件事「**钱在两人之间动过**」。措辞只说「银钱往来」，不说买了什么、谁付给谁、是买是租。

| 弧 | 幕 id | matcher | dir | 落地上界 | 文案 |
|---|---|---|---|---|---|
| grudge (cold) | traded | `{"type":["pay"]}` | any | **947** | 梁子归梁子，%A 与 %B 之间的银钱往来一直没断 |
| pact (warm) | traded | `{"type":["pay"]}` | any | **181** | %A 与 %B 之间，银钱往来也没断过 |
| craft (grey) | traded | `{"type":["pay"]}` | any | **1440** | %A 与 %B 之间还牵着一条银钱往来 |

**没选 / 判死的**（守普查纪律，不为凑数加沾边幕）：
- `give`（全死，2/1/0）；`aid` on grudge（1，敌对不互助）；`meet`/`invite`/`confide` on grudge（≤2）。
- **craft 口碑幕**（endorse via subject，V1「看他干活→改看法」的正主）：总量 157 **但干净 fwd 只有 30 < 147**，rev 127 的语义是「匠人反看看客干活」那条反向弧，混。低于下界 ⇒ 判死（同 give 的纪律），**不加**。
- **secret + pay**（385）：secret 弧 `cold:0` 永不冷场、到 60 天盖住 84/132 有向对 ⇒ 任何事件落它上面都虚高、低信号；docs 刻意把 secret 留窄（只 confide/aid）。**不加**。

## 四、三道文案守卫的相容性（Story.gd 最贵的资产，逐条核）
三幕 `accepted` 维：pay 恒 `accepted=true`；`note` 维：buy:/rent。文案里**不含任何**极性短语。
- **PHRASE_LOCK**：三幕文案都含新短语「银钱往来」，我把它锁到 `["pay"]`（Story.gd 新增一行）。与既有锁**无子串相交**（rule ①）；`phrase_conflicts("…银钱往来…", ["pay"])` → allow 含 pay → 0 违规。三幕文案**不含**其它任何锁定短语（尤其避开了 `出活`(produce)/`如约`/`积起了怨气` 等）。⇒ `lint_grammar().bad` 空（PL1 ✅，槽位 35→38，**已上锁 38/38**）。
- **POLARITY_LOCK**：三幕文案不含任何极性短语 ⇒ matcher 不筛极性也不假红；运行期 `polarity_conflicts_ev` 无短语可查 ⇒ 0 违规。
- **REPEAT_MARK**：三幕都是 `beat`（非 `open`）⇒ `repeat_conflicts` 只在 `kind=="open"` 触发 ⇒ 不适用。
- **PL4 交叉验**：`pay` 在 `Main.FEED_SKIP`、`_event_prose` 无 pay 臂（落「# 兜底」被 `_prose_by_type` 切掉）、`Sim._verb("pay")` 走 default 返回裸 `"pay"` ⇒「银钱往来」在独立渲染里对不上任何一条 ⇒ 佐证向 +0（「对不上不算错」），安全向（不出现在【不允许】的类型里）成立。PL4 ✅。
- **PL3 变异空间**：700 变异体、三锁认出 691（98.7%）；跨类型 678/678（新锁贡献了 pay 幕的跨类型捕获）；同类型 13/22。三条 pay 幕之间的对调是**同类型近义**（都 allow pay、无极性/复述）⇒ 落进诚实的 `漏网` 名单（`grudge:traded↔pact:traded` 等），**不假装抓得住**——这正是 `does_not_detect` 的定义域。

## 五、零金标三证据（**含 chain**；跑不动就是碰了仿真侧——没跑动）
1. **story_test A0≡A1 逐字节零扰动**（挂追踪器前后 Inv.digest / event_digest / 事件数）——**12/12 seed 全等**（`analysis/ar1/story_test_full.txt`）：
   seed1 Inv 167033571/167033571 · event_digest 8104691641259946542/8104691641259946542 · 事件 2177/2177 … 直到 seed12 全 X/X。
2. **S0 金标 12/12 seed 逐字节相同 + 逐 tick 前缀链**（`analysis/ar1/s0_golden.txt`，Harness.gd --golden 12×60）：
   `✅ 金标一致 12/12 seed（含逐 tick 前缀链 12 条）` · `✅ 同 seed 两跑摘要一致(批量+增量滚动+逐tick前缀链) 3/3` · `=== S0 GATE: PASS ✅ ===`（硬不变量 12/12、金标过、det 3/3）。
3. **A 段三臂等价**（增量折 ≡ 全量折 ≡ 回放 @T 与 @T/2，比 digest+chain+逐弧快照）——12/12 seed 全绿；每 seed 79–102 条弧、300–433 行叙述**逐行回 event_log 核出处 0 违规**（含新 pay 幕）。
⇒ S0 与 A0≡A1 都**没动** ⇒ 本片确在 View 侧、没碰仿真态。

## 六、story_test（本片的牙齿：F10 正对照 + F1/F10′ 负对照）
- `✅ F10 三条弧各落一笔 pay → traded 幕逐条被讲出、系对人`（grudge/aria>ben、pact/coco>dan【反向付款 dan→coco 也认，dir=any】、craft/fred>ed）
- `✅ F10 三行都成文为『银钱往来』且无占位符残留（3 处）`
- `✅ F10 三条 pay 幕逐行可追溯（audit 0 违规）`
- `✅ F10′ 只喂 pay（无弧在跑）→ 故事 0 条`（pay 不是任何弧的开头，同 F1 的 greet）
- `✅ F1 只喂 200 条 greet → 故事 0 条` 不破；`✅ PL1 0 违规`；`✅ 小镇故事验收全绿（fixture 6 组 + 12 seed × 40 天）`

## 七、眼验（真引擎）
`docs/media/ar1_story_panel.png`：把 Story.gd 的**真 `panel_text()`** 喂进与 `Main._story_box` 逐项同配的 RichTextLabel（bbcode + `Art.font()` 得意黑 + 字号 14），windowed 真 framebuffer 渲一帧。面板「近来收场的」那段全文里清清楚楚一行：
「第1天 **梁子归梁子，阿丽 与 本 之间的银钱往来一直没断**」——真中文字形（非豆腐块）、BBCode 配色对、`%A/%B/%d` 全部填好无残留；下方「还在往下走」露出盟约/手艺两条也各牵着这条往来（各 2 幕）。

## 八、diff
```
 game/scripts/Story.gd      | 38 +++++  (PHRASE_LOCK 一行 + grudge/pact/craft 各一幕 traded)
 game/scripts/story_test.gd | 57 +++++  (F10 正对照 + F10′ 负对照)
 2 files changed, 95 insertions(+)
```

## 九、CI 判决行
（见 §末尾，`analysis/ar1/ci.txt`；提交前互补性守卫不算数，协调者 committed 树重烘重跑，docs/140。）

<!-- CI_VERDICT_PLACEHOLDER -->
