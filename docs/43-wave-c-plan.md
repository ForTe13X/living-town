# 43 · Wave C 路线图与分棒计划——从「研究仓库」转向「像个游戏」

**2026-07-26 立。** 本文是 Wave C 的**唯一权威计划**：路线图 §A 的更新在 §一，每一棒的 brief 在 §三。
派棒时**不要重抄 brief**——只给「读 docs/41（共同契约）+ 本文 §三-CN（你那一棒）」。
这条规矩本身来自 docs/41 §0 的写作动机：**抄第 N 遍就会漏第 N 条**。

---

## 〇、这一波的判据（一句话）

前 42 份文档回答的是「**这台机器对不对**」。现在有 23 条硬不变量、金标逐字节锚、
逐 tick 前缀链、观察无关门——**机器是对的**。而 2026-07-26 的现场眼验（`shot1.sh seed=3 day=5`）
拍出来的是：**一个信息面板占满右侧的调试视图**，不是游戏画面。

> **Wave C 的验收不是"CI 更绿"，是"把新录屏发给一个不认识这个项目的人，他会问'这是什么游戏'而不是'这是什么工具'"。**

---

## 一、路线图更新（docs/05 §A 的差量）

三份并行只读评审（产品面 / 视觉面 / 开放线程面）交叉核对后，**docs/05 §A 有 5 处已经过期**，
且**有两条最高杠杆的工作已经写完但没合进来**。以代码为准：

### 1.1 docs/05 §A 里已经不成立的行

| docs/05 原文 | 实测 |
|---|---|
| §A-NOW「让已仿真的戏剧变得可读……只 `_log_event` 从不 `emit_signal`」 | **已做**。五类全部 emit：betray `Sim.gd:1850`、conflict-born `:2027`、election `:2474`、pact dissolved `:3284`、pact formed `:3348` |
| §A-NEXT「`buildings.json`（现在 `buildings: []`）」 | **已填**：7 栋楼 / 12 间房（`b7780c8`） |
| §A-NEXT「灯笼节对象在 [12,7]，四次节日到场 0」 | **已移到 [31,24] 广场内**，到场 9.94 人/节日日（`3d38c0f`） |
| §A-NOW「`ZOOM_MIN 0.6` 意味着回到全镇只显示约 14%」 | **混了两个 bug**：14% 来自 `go_home()` 硬设 `zoom=1.0`；0.6 地板本身到 38.5%（docs/13:1064 已更正）。**但开局取景仍然是坏的**——`ProbeController.setup()` 从不调 `go_home()`/`fit_zoom()`，首帧约 13.9% 可见 |
| §A-NOW「把确定性钉在单一二进制之外」 | **已做**：金标 + 逐 tick 前缀链 + FNV-1a 自有哈希 + 稳定候选身份加盐，全在 `tools/ci.sh` step 4 |

### 1.2 两条已经写完、但没合进 `integration/batons` 的工作

**这是本轮成本最低、价值最高的两项，且读 docs/34-42 完全看不出来**（它们不是研究任务，是 merge 任务）：

| 分支 | 内容 | 为什么重要 |
|---|---|---|
| `claude/objective-lumiere-e6f125` | `game/bench/BackendGate.{gd,tscn}`(160行) + `Sim.gd`+108 + `tools/ci.sh`+13 + 一份 268 行文档 | **正是 docs/38 §八-2 / docs/41:41 声称"至今无门覆盖"的那道门**。docs/42 §7.3 明写：任何 prompt 修复**必须先有这道门**，否则又是一次"CI 全绿而产品已破" |
| `claude/stoic-shamir-e08cef` | `tools/audit_map.py`+54：节日对象的越界/压阻挡/压家具/**可达交互格**校验 | `festivals.json` 在 HEAD 上**零 CI 覆盖**。`471d3e3 merge(B17)` 合的是**另一个** B17（挪锚点），能抓住这次错放的那道**门从未落地** |

⚠️ **合并 lumiere 会撞文号**：它带一份 `docs/40-external-backend-invariant-gate.md`，而 HEAD 已有
`docs/40-device-n60-slm-the-shipping-intersection.md`。不是 git 冲突（文件名不同），但编号体系会静默破掉，
`lint_links.py` 抓不到。**必须改号为 `docs/45@claude/objective-lumiere-e6f125`**。

### 1.2b ★ C0 回执（2026-07-26 当日）——两道门都已落地，且**上面 §1.2 有一句是错的**

两道门都合进来了（`33ca14d` / `8f8efcf` / `5561ab4`，文号已改 45），`tools/ci.sh` → **CI PASS**，
金标 12/12 + 逐 tick 前缀链 12 条 + DetGate 16/16 逐字节未动（lumiere 自称的"金标零扰动"**已被独立复验**：
两条新边界只长在 `backend != null` 分支里，金标路走 `else`）。新的 4d BackendGate：硬 8/8、两跑一致 8/8、无饿穿 8/8。

**负对照才是这一棒的产出**（一道从没红过的门，不算已知是门）：

| 负对照 | 硬不变量臂 | 确定性臂 | 饿穿臂 |
|---|---|---|---|
| 阳性（合入后） | 8/8 ✅ | 8/8 ✅ | 8/8 ✅ |
| 把 P2-3 否决短路掉（= lumiere 之前的树） | **0/8 ❌** | 8/8 ✅ | **0/8 ❌** |
| 给 `Sim._rng_at` 掺 `randi()`（破红线 #1） | 8/8 ✅ | **0/8 ❌** | 8/8 ✅ |

两个正交的注入各自只点亮**自己那条臂**——这比"门是绿的"强得多。确定性臂每个 seed 都精确报出 `首个分叉 tick_no=1`。

> **★ §1.2 那句「能抓住这次错放的那道门从未落地」是错的，撤回。**
> 按 §三-C0 的验收去做负对照——把灯笼节锚点挪回 `[12,7]`——**门是绿的（exit 0, AUDIT PASS）**。
> 原因写在 shamir 自己的 commit message 里：`[12,7]` 在 home2 屋内，经门 `[12,8]` 可达、不叠格，
> 且 `fest_` 对象按 `Sim.gd:2882` 不入导航网 ⇒ 三条规则全满足。
> **这道门抓的是「非法 / 够不着 / 叠格」，抓不到「合法但语义不对」（该在广场却在屋里）。**
> 真要拦住 B17 那次错放，得另加一条**区域归属**规则。C0 改用 8 个真正非法的构造证明了门不空转。
> 教训与 docs/41 §4 同源：**派棒者写进 brief 的那条"必红"的负对照，本身就是一个未经验证的断言。**

**两条新发现（C0 越出 brief 范围挖到的，均已复核）：**

1. **★ 熔断器一旦触发，换模型也救不回来，且零 CI 覆盖。**
   `AIBackend.gd` 里 `_slm_circuit_open` 只在声明处为 `false`、在 `:813` 被置 `true`，**全文件没有任何一处把它置回 `false`**。
   `_slm_fail_streak` 有两条清零路（`:329` 任何 worker 完成、`:800` 成功），但那只防止**再次**触发，不解除已触发的熔断。
   会话内永久回退是**故意的**（`:814` 的告警原文就写着"永久回退 logic 地板"，防 docs/34 那个原生泄漏 OOM）——
   **但 `set_model_path()`(:467) 与 `request_backend()`(:225) 也不复位它**，而设置面板里正有"SLM 模型 cycle"这一行，
   且 C3 正在把设置面板做成触屏可达。⇒ **用户熔断后去"换个模型试试"，得到的是无声的失败。**
   换一个权重文件是一个**全新的失败假设**，没有理由继承旧假设的熔断。已并入 §三-C6。
2. **被否决的 intent 不再进 S4 决策 trace。** lumiere 的新 `elif` 插在 `elif record_decisions` 之前 ⇒ 否决触发时
   `_record_decision` 不被调用。`s4_replay_test` 在 CI 里是绿的，但它跑 `backend=null` 路 ⇒ **这条没有任何门覆盖**。
   C0 只读出来、没测。**记为 Wave D 待查项**，别当成已知无害。

**另外三条（非结论，供后续避坑）**：①`claude/objective-sinoussi-2d8005` **先别删**——`breaker_test.{tscn,gd}` 只在它上面，
且**不能 cherry-pick**（它测的 `BREAKER_MAX_FAILS`/`breaker_tripped`/`_note_ai_fail` 在 HEAD 一个都不存在，
HEAD 走的是 `scale-diagnostic` 并集带来的另一套实现）。②**文号 44 现在悬空**——§三-C5 说"取下一个空闲文号"会取到 44、排在 45 前面，
可接受但要有意识。③`analysis/` 的去留：`phase-d-contract-hardening` 上的 `bench/bakeoff/phase_d_repro/` 是**更新且策展过**的那份
（晚 47 分钟，8 个同名文件逐字节相同），但两边互不为超集——**唯一没有副本的是 `gen_judge_wf.py` / `gen_combined_payload.py`**。
`.gitignore` 只挡了 `analysis/**/packet_*.jsonl`，**故意不挡整个 `analysis/`**（它在 `codex/repository-review-2026-07-12` 上是被跟踪路径）。

### 1.2c ★ C2 回执——小镇有声音了，**但"CI PASS"在这一棒上比别处弱**

`game/scripts/Audio.gd`（约 380 行）+ `project.godot` 的 `[autoload]` 一行，**没有任何音频文件入库**
（全部运行时数学合成为内存 `AudioStreamWAV` ⇒ 红线 #4 没有受力面）。内容：昼/夜环境床（交叉淡入）、脚步、UI 点击、
5 个挂在 `Sim.social_event` 上的事件音 + 1 个节日音。接线全在 `Audio.gd` 自己的 `_ready()` 里，**只读 `Sim`**。

**证据不是"RMS 非零"**（一条环境床就能过这个门）。它给了两把更硬的尺子：环境床的峰值有**解析上界**，
超过 2× 上界的 20ms 帧才算一次 onset；外加逐 cue 计数。5 段采集 5/5、9/9、22/22 窗口非零，
夜间那段 `{step:21, warm:5}` = 26，与检出的 26 次 onset **对得上**。负对照 `--no-audio`：**每一个采样点精确为 0**。
昼夜交叉淡入也不是自称——过零率 414.3/s(正午) vs 338.3/s(夜)，与两张床的基频（A2 110Hz / E2 82.4Hz）吻合。
仿真零影响是**直接量的**：同一路径 `--digest-at 520` 只切换那一行 autoload，两侧逐字节相同。

> **★ 这一棒最重要的产出是一条契约级发现，已写进 docs/41 §2：`--script` 模式不加载 autoload。**
> 而 S0 门(4)、LOD 门(4b)、DetGate(4c) **全部走 `--script`** ⇒ **autoload 里的代码在那张 12 seed × 60 天的网格上零覆盖**。
> 真正加载它的只有 step 3(`--import`) 与 step 5(6 个场景)。**这一棒的"CI PASS"证明的东西比字面上少**，
> 它自己另造了 `--digest-at` 的 autoload 逐字节 A/B 来补——这才是有效证据。

**这份 brief（§三-C2）有两处是错的，已确认：**
1. **「`tools/ci.sh` 在 `--audio-driver Dummy` 下」——`ci.sh` 里根本没有这个旗标**，它传 `--headless`（隐含哑驱动）。
   硬编码该旗标的是 `shot1.sh`/`shot_tick.sh`/`shot_scale.sh`/`chat-shoot.sh`/`observe-shoot.sh`/`probe_digest_test.sh`/
   `pan_test.sh`/`record-godot.sh` 这八个。**结论对、机制错**，同样的措辞错误已在 docs/41 §2 一并更正。
2. **「节日音挂 `Sim.social_event`」——挂不上。** 根本没有 festival 事件类型：`_update_festival()` 只发无节日语义的
   `world` spawn/despawn，`festival_active` 是日边界设的普通变量。只能挂 `day_changed` + 读 `Sim.festival_active`。

**一个由测量而非设计逼出来的修正**（值得记）：第一次调音后，40 秒/2000 tick 的采集里 `warm` 响了 51 次、
`resolve` **响了 0 次**。不是"没有和解发生"，是**和解被日常打招呼挤出了全局限流配额**——
**最稀有、最有戏的事件恰恰是被静音的那些**。现在 `resolve`/`bell`/`festive` 走单独的宽松配额。

**代价与未测**：启动一次性 +140ms（`_ready()` 里烘 9 个 PCM 缓冲；n=2、±90ms 噪声 ⇒ 读作"0.1-0.2s"）。
**没有真机数据**，外推 3-5× 是 0.4-0.7s；若真机启动画像里看得见，最小修法是把三个 `_build_*` 推离首帧
（照抄 `Main.gd` 已有的 SLM 探针延后）。`click` 与整条 `_input` 路径 headless 生不出输入事件 ⇒ **零覆盖**。
**执行者听不到声音**——上面每一条都是测量，不是审美判断。**Stride 4 必须有人真的戴上耳机听一遍。**

**Stride 4 要用的**：`tools/record-godot.sh` 现在录不到声音。改法（C2 按契约没动它）：保留 `--audio-driver Dummy`
（它仍在推进混音，headless 采集正是靠这个），在 `--` 后追加 `--audiocap /out/town_audio.wav <SECS+2>`，
去掉 `kill $GODOT_PID`（hook 自己退出），最后补偿脚本里那 3 秒 `sleep` 再混流：
`ffmpeg -i town_raw.mp4 -ss 3 -i town_audio.wav -c:v copy -c:a aac -shortest town.mp4`。**别装 PulseAudio**，容器里没有声卡也不需要。

### 1.3 新的 NOW（Wave C）

按 (玩家可感知增量) / (工作量 × 风险) 排序。**前四条全是 View 层，碰不到红线 #1。**

1. **手机上能玩而不只是能看**——7 个玩家动词全部锁在 `--player` **启动旗标 + 物理键盘**后面
   （`Main.gd:131`、`:1284-1294`）。出货目标是 Android APK，**两样都没有**。设置面板 7 行里没有"玩家模式"。
   引擎侧早已完整且被 CI 守着（`Sim.player_act/_move/_mediate`、`player_agency_test.tscn`）。
   **在真出货平台上，Living Town 现在是一块屏保。**
2. **第一眼像个游戏**——①开局取景约 13.9%；②全镇视角 **57.7%** 的画面是 Godot 未改的默认清屏色
   `#4d4d4d`（室内 63.1%），小镇是灰色虚空里的一座孤岛；③居民**每秒瞬移 12.5 次 48 像素**
   （`_center()` 直接返回格心，无插值）；④顶栏状态条是全屏最密的文字，**唯独没有背板**。
3. **给小镇声音**——全仓库 `grep` 不到一个 `AudioStream`。一个 19.2 秒走完昼夜的镇子是全哑的。
4. **仿真了却看不见的东西**——四季与天气每天边界都在算（`Sim.gd:1076-1078`）并进效用乘子，
   而 `WorldView.gd` 里 `season|weather` **零命中**：四季渲染逐像素相同。21 个 `social_event` 发射点
   只有 10 个表情图标。
5. **模型路径的两个字符串**（docs/42 §7.3）——`如 3` 字面示例 + `0-9` 编号字母表，
   直接导致 **1.5B 只有 4.8% 的选择是吃饭或睡觉**（随机 18.5%、引擎 36.9%）→ 硬不变量 #01 在模型路径上 8/8 seed 破。
   **零训练、改两个字符串**，但**必须等 §1.2 那道门先落地**。

### 1.4 明确推到 Wave D 的（不是忘了，是排序）

- **单局形状与目标**（docs/01 §3.2 承诺的社会成就；`grep quest|achievement|tutorial` → 0 命中）。
  这是**最大的**缺口，但它是 L 且需要设计。**必须做成对 `event_log` 的只读派生**（与 `ProbeController` 同一纪律），
  否则会污染仿真。留到画面与手感立住之后。
- **真机 3B 代价实测**（docs/42 §8-10：时延/落地率/FPS/电量/Native Heap 一个都没量）。设备独占，与任何真机棒互斥。
- **黑边 24.7%**（`aspect=keep`）——`bd17bed` 试过 `expand`，真机黑屏，`3557c26` 只回滚了旗标。
  这是 Adreno + `gl_compatibility` 的驱动排查，不是布局活；且**只能用 adb screencap 验**（docs/41 §6 盲区③）。
- 教师上界 / crisis 档覆盖 / 世界级反事实（docs/42 §8）。

---

## 二、Wave C 共同规则（docs/41 的**增补**，不替代）

docs/41 全文仍然逐条生效。本节只加这一波特有的六条。

- **R1 · `game/project.godot` 按节分权。** 它是唯一被多棒共享的文件。
  **C1 只能改 `[rendering]` 段，C2 只能改 `[autoload]` 段**，谁都不许碰 `[display]`（黑边归 Wave D）。
  改完在报告里贴出你新增的**整行**。
- **R2 · AI 生成的图片不是美术资产。** 红线 #4 要求 CC0 或自绘，**AI 出图两者都不是**。
  仓库唯一的例外是 `docs/media/cover.png`，而 docs/09 已标注它需要在商用前重审条款。
  docs/12 A-art-5 早有裁决：GPT 产出**仅对话框头像、绝不进精灵帧**。
  **本波的硬规矩：生成图只能当情绪板 / 配色参考，产出物是 `.gpl` 调色板和文字，图片不入库。**
  新的游戏内美术一律走 `tools/fetch_assets.py` + 附 `LICENSE.txt` 的 CC0 源。
  已点名禁用：LimeZu Modern Interiors（非 CC0）、Bonsaiheldin Interior（CC-BY-SA 传染）、2DPIXX（CC-BY）。
- **R3 · 证据落到固定目录，供后续拼片用。** 每棒把改前/改后 PNG 写进
  `<scratchpad>/wave_c/<棒号>/`，命名 `before_<场景>.png` / `after_<场景>.png`，
  并在报告里**逐张写出 `im.size`**（docs/41 §6 盲区③：画幅问题只体现在尺寸上）。
  Stride 4 要靠这批图拼录屏与 README，**不重跑**。
- **R4 · 契约 §6 的工具链盲区补两条**（本波实测新增，已同步进 docs/41 §6）：
  **④ `--shot` 永远渲不出昼夜**——`_modulate` 建出来是白的（`Main.gd:223`），
  `_daylight` 只在 `_on_tick`/`_after_jump`/`_after_load` 里施加，而 `--shot` 把 `auto_run=false`（`:245`），
  三条路一条都不走。**证据**：`town_integrated.png`（HUD 写 `00:38 夜`）与 `shot-town-roads.png`（`12:00 昼`）
  的主草地色**逐字节都是 (133,166,67)**。
  **⑤ `--shot` 恒显示 `第N天 00:48 夜`，`--speed` 不推进时钟**（`b7780c8` 记录）。
- **R5 · 纯 View 棒的双向断言。** ①`tools/ci.sh` 金标逐字节不动；②`tools/probe_digest_test.sh` 绿；
  ③对**未受影响的区域**做 `ImageChops.difference(...).getbbox()`——**该动的地方 bbox 非 None，不该动的地方 bbox 必须是 None**。
  「看起来一样」不是证据。
- **R6 · 并发纪律。** 本波多棒同时在独立 worktree 里跑。**完整 `tools/ci.sh` 全程只跑一次**（收尾时），
  迭代期用定向检查。跑之前先清场游离的 `godot.exe`（docs/41 §1），并断言每个输出文件只有一段汇总。
- **R7 · worktree 不会自动同步到派棒基线。**（2026-07-26 实测，C0 与 C2 各独立踩到一次）
  新建的 worktree checkout 可能停在**派棒基线之前**——C2 拿到的是 `38ba4a7`，那棵树上**本文根本不存在**。
  ⇒ **每根棒起手第一件事**：`git log --oneline -3` 对照 brief 里写的基线 SHA，落后就先确认是祖先再 ff。
  这正是 docs/41 §1 记的那个坑，只是这一波它来自派棒机制本身而不是人。
- **R8 · 合并要验在合并后的树上。**（journal 第二波方法论第 4 条）各棒的 CI 是在**各自的基线**上跑的；
  Wave C 的棒基线不同（C0/C6 在 `ef92d53`，C1/C2/C3 在 `fdb212f`）。
  ⇒ **合并后必须再跑一次全量 CI**，不能拿"每根棒自己都绿过"当合并树的证据。

---

## 三、分棒（disjoint by file）

**文件所有权表**——越界前必须先在报告里说明（docs/41 §1）：

| 棒 | 独占文件 | 共享（按 R1 分权） |
|---|---|---|
| **C0** | `tools/audit_map.py`、`game/bench/BackendGate.*`、`.gitignore`、`docs/45@claude/objective-lumiere-e6f125` | `Sim.gd`（仅接受 lumiere 的既有 diff）、`tools/ci.sh` |
| **C1** | `game/scripts/WorldView.gd` | `project.godot` **仅 `[rendering]`** |
| **C2** | `game/scripts/Audio.gd`（新建） | `project.godot` **仅 `[autoload]`** |
| **C3** | `game/scripts/Main.gd` | — |
| **C5** | `game/assets/art/palette.gpl`（新建）、新建的美术方向文档（本波产出，落盘时取下一个空闲文号） | — |
| **C6**（Stride 2，blocked on C0） | `game/scripts/AIBackend.gd` | — |

> `Sim.gd`、`golden_digests.json`、`Invariants.gd`、`Harness.gd` **本波任何棒都不得主动改**。
> C0 是唯一例外，且它只是把一份已经写好并自称"金标零扰动"的 diff 接进来——**必须自己复验这句话**。

---

### C0 · 把两道已经写完的门接回来（**先做，解除 C6 的阻塞**）

**为什么**：见 §1.2。这不是研究任务，是 merge + 复验。**读 docs/34-42 完全看不出这两件东西已经存在**——
任何只基于文档排的优先级都会把它们低估一个数量级。

**做什么**
1. `claude/objective-lumiere-e6f125`（1 commit `6e2ba78`）合进来。**把它带的 `docs/40-external-backend-invariant-gate.md`
   改号为 `docs/45@claude/objective-lumiere-e6f125`（合入时改名为 45 号）**，并修好所有指向它的链接。
2. `claude/stoic-shamir-e08cef`（1 commit `b93d15f`）合进来（`tools/audit_map.py` 的节日门，纯工具、不碰仿真）。
3. `.gitignore` 补 `__pycache__/`、`*.pyc`。
4. **不要**提交 `analysis/`——它 723 MB，其中 `phase_d/packet_c30.jsonl` 638 MB + `packet_smoke.jsonl` 84 MB
   是 2026-07-19 的 LLM-judge 负载。给 `.gitignore` 加 `analysis/**/packet_*.jsonl`。
   `analysis/phase_d/` 其余 ~1.3 MB 与 `phase-d-contract-hardening` 分支上的 `bench/bakeoff/phase_d_repro/` 近乎重复——
   **在报告里说清哪份更新，别自己决定删**。⚠️ `analysis/` 在 `codex/repository-review-2026-07-12` 上是**被跟踪路径**。
5. `claude/objective-sinoussi-2d8005` 的内容**已经**通过 `scale-diagnostic 5707247` 的三方并集进了 HEAD
   （`SLM_CIRCUIT_TRIP`/`PROBE_TIMEOUT_MS`/`_slm_reload_pending`/`_slm_log` 都在）——
   但**先花 30 秒确认 `game/scenes/breaker_test.tscn` / `game/scripts/breaker_test.gd` 是否被漏下**，再谈删分支。

**验收**
- `GODOT=C:/Users/yp/.local/bin/godot bash tools/ci.sh` → `CI PASS`，且**金标逐字节未动**
  （lumiere 自称"金标零扰动"，`Sim.gd` 却 +108 行——**这句话必须由你复验，不能采信**）。
- 新的 BackendGate 步骤**真的在跑**：给它一个**故意失败**的负对照（例如临时把某条硬不变量的阈值调到必红），
  证明这道门不是空转。跑完还原。
- `tools/audit_map.py` 的节日门同样要负对照：把 `festivals.json` 的锚点临时挪回 `[12,7]`，门必须变红。跑完还原。
- 报告里给出：两个负对照的输出、`git log --oneline -3`、新文号的链接全绿（`tools/lint_links.py`）。

---

### C1 · 第一眼像个游戏（世界层）

**独占 `game/scripts/WorldView.gd`；`project.godot` 只许动 `[rendering]`。**

四件事，按杠杆排序：

1. **杀掉灰色虚空。** 全镇视角 **57.7%**、室内 **63.1%** 的画面是 `#4d4d4d`（Godot 未设 `default_clear_color`）。
   室内早已有解（`_draw_interior_backdrop`，`WorldView.gd:533-554`，`68fe0cb` 落地），
   **小镇分支没有对应物**——草地被钳在 `[0,w)×[0,h)`（`:771-774`）。
   加 `[rendering] default_clear_color` + 一个 `_draw_town_backdrop()`（界外的暗色林/水环 + 暗角），
   在 `_draw()` 的草地循环之前调。
2. **给居民插值。** `_center()`（`:987-989`）直接返回格心，而 `Sim.tick_interval=0.08` ⇒
   **每秒瞬移 12.5 次、每次 48 像素**。在 `WorldView` 内维护 `_render_pos: {id → Vector2}`，
   在 `_process(delta)`（**渲染时钟**）里向 `_center(ag)` lerp，`queue_redraw()`；
   agent 绘制、关系连线、交谈连线统一改用 `_render_pos`。
   ⚠️ **只读 Sim，永不写 Sim**；`_render_pos` 不得参与任何喂给绘制之外的剔除（`WorldView.gd:22` 的 LOD 红线）。
3. **让四季与天气看得见。** `Sim.weather_today` / `season_today` 每天边界都在算并进效用乘子（`Sim.gd:2305`、`:2322`），
   而 `WorldView.gd` 里这两个词**零命中**。加季节色调（草地变体选择 `:138-142` 附近）+ 一层降水叠加。
4. **软化脚下阴影。** `:1157` 的 `draw_circle(feet, T*0.22, α=.25)` 几乎和精灵一样宽，读起来像人浮在一个圆盘上。
   压成椭圆、缩到约 `0.15*T`、加 2-3 圈 alpha 衰减。

**验收**（严格按 R5 的双向断言）
- 灰虚空：`shot1.sh` 在 1280×768 **与** `--shot-fit` 1920×1152 各拍一张。
  断言 `#4d4d4d` 占比从 ~58% 掉到 <5%；**`im.size` 不变**；`ImageChops.difference` 的 bbox
  **必须完全落在地图矩形之外**——界内世界要逐像素相同。
- 插值：**静帧拍不出来**，必须走 `tools/record-godot.sh`。同时：因为 `--shot` 会 `auto_run=false`（`Main.gd:245`），
  lerp 会收敛 ⇒ 冻结 tick 的 `--shot` 前后 diff bbox **必须是 `None`**。这是这条改动的关键守门。
- 四季：`--warmup` 取四个分别落在春/夏/秋/冬的天数 + 一个雨天，两两 `getbbox() is not None`（必须不同）。
- 全程：`tools/ci.sh` 金标逐字节不动、`game/bench/lod_verify.gd` 绿、`tools/probe_digest_test.sh` 绿。
  **纯 View 改动移动了 digest = 你改到仿真了，回滚查因。**

---

### C2 · 给小镇声音

**新建 `game/scripts/Audio.gd`；`project.godot` 只许动 `[autoload]`。不得修改 `Main.gd` / `WorldView.gd` / `Sim.gd`。**

全仓库 `grep -rn "AudioStream" game --include=*.gd` → **0 命中**。一个 19.2 秒走完完整昼夜的镇子是全哑的。

**做什么**：数学合成（`AudioStreamGenerator` / 程序化 `AudioStreamWAV`），**零外部音频文件、零许可风险**。
`godot-game-pipeline` 技能里有现成的合成 SFX/BGM 配方与 headless 采集配方，**先读它再动手**（红线 #5 复用优先）。
最小可用集：环境底噪（昼/夜两层交叉淡入）、脚步、UI 点击、以及 3-5 个挂在 `Sim.social_event` 上的事件音
（问候 / 冲突 / 和解 / 节日 / 选举）。

**接线方式很关键**：`Audio.gd` 作为 autoload 在自己的 `_ready()` 里直接连 `Sim` 的信号
（`social_event`、`day_changed`）。**这样它不需要碰任何别人的文件**——这是它能与 C1/C3 并行的全部原因。

**验收**
- headless 采集（`AudioEffectRecord`，配方见技能）：断言 ≥3 个**互不相交**的 2 秒窗内 RMS 非零。
- `tools/ci.sh` 在 `--audio-driver Dummy` 下**必须仍然全绿且不出现任何新的 ERROR 行**——
  注意 `ci.sh` 的 `scan()`（`:30-36`）会抓 `push_error`/`SCRIPT ERROR`，**因为 GDScript 的退出码抓不到它们**。
  哑驱动下建生成器是最容易出这类静默错误的地方。
- 金标逐字节不动。
- ⚠️ `tools/record-godot.sh` 现在写死 `--audio-driver Dummy`——**录屏是没有声音的**。
  你**不要**改那个脚本（Stride 4 会做），但在报告里写清需要怎么改才能录到声音。

---

### C3 · 手机上能玩（玩家外壳）

**独占 `game/scripts/Main.gd`。不得修改 `Sim.gd`（引擎侧早已完整且被 CI 守着）。**

1. **玩家模式搬进设置面板。** 现在要 `--player` 启动旗标（`:131`）。设置面板（`_build_settings`，`:503-585`）
   加一行开关。⚠️ **打开它会合法地移动 digest**（它调 `Sim.add_player()`）——这是**受控动作**，
   走 docs/41 §3 的流程；但**关着的时候 digest 必须逐字节等于今天的金标**。
2. **触屏动作条。** 7 个玩家动词（greet/give/gossip/invite/confront/apologize/mediate，`:1284-1294`）
   现在只有物理键。加一排屏幕按钮，走 `_player_do`（`:1047`）**同一条路径**。
3. **顶栏状态条补背板。** `:270` 是全屏最密的文字却**唯独没有** `_mk_panel`（对比：日志 `:285`、观察 `:295`、
   滚动条 `:301` 都有）。实测device图 y=14 行草地 (133,166,67) 与浅墙 (216,189,147) 直接透上来。
   `_scrub_hint` 当初正是为这个原因补的板，**状态条被漏了**。
4. **开局取景。** `ProbeController.setup()`（`:45-52`）从不调 `go_home()`（`:114-121`）⇒ 首帧只看得见约 13.9% 的地图。
   在 `Main.gd` 的 `setup` 之后调一次。
5. **键位提示** `:321` 只列了约 25 个绑定里的 6 个，**恰好漏掉 `Home`**（那个能修好取景的键）。
6. **顺手修 R4-④：`--shot` 渲不出昼夜。** `--shot` 分支（`:244-263`）里在截图前施加一次 `_daylight`。
   这条**必须做**——它是整个项目所有视觉判断的量具，现在这把尺子是坏的。

**验收**
- **按钮路径 ≡ 按键路径**：新建一个 headless 断言，对 7 个动词逐一验证按钮触发与 `Sim.player_act(verb, target)`
  在同一 fixture 上返回**同一个字符串**。
- **画幅**：`shot1.sh` 在 1280×768 **和** 2688×1216 各拍一张，用 PIL 断言 7 个按钮**全部落在 `im.size` 之内**
  （docs/41 §6 盲区③：只看画面会漏掉画幅问题）。
- **关着的时候 digest 不动**：`tools/probe_digest_test.sh` 与 `tools/ci.sh` 金标逐字节等于今天。
- **昼夜量具修好了**：`shot_tick.sh` 在一个夜 tick 与一个正午 tick 各拍一张，**主草地色必须不同**，
  且夜那张 ≈ `(133,166,67) × _daylight(night)`。把这条做成可复跑的脚本片段留在报告里——Stride 4 要把它变成 CI 里第一条视觉断言。
- 状态条：采样 y=10 一整行，每个采样点亮度 < 40%；diff bbox **完全落在** HUD 面板矩形内，世界区域必须没动。

---

### C5 · 美术方向与调色板（由主 session 驱动，不派棒）

**产出物是 `game/assets/art/palette.gpl` + 一份新的美术方向文档（落盘时取下一个空闲文号）。图片不入库（R2）。**

要解决的是一个**已经在打架的**问题：vendored 的 CC0 精灵包是奇幻 RPG 原型
（`Mage-Red` / `Archer-Green` / `Warrior-Blue` / `Soldier-*`）——**戴尖帽拿法杖的法师**走在咖啡馆、澡堂、工坊之间；
而 `docs/media/cover.png` 承诺的是一座 3/4 透视的黄昏村庄，`docs/16:44` 明确 **SKIP** 伪等距。
**封面承诺了一个永远不会被造出来的游戏。**

同时 `docs/12` §3 的 **A-art-0（32-48 色 `palette.gpl`）至今 OPEN**——
现在每个颜色都是散在 `WorldView.gd`（`BLD_PAL:119`、`_mat_wall:1228`、`_mat_floor:1244`、`_draw_room_decor:1349-1353`）
和 `Art.gd:7-15` 里的硬编码十六进制字面量。

**怎么做**：用 Chrome 里的 GPT 出图当**情绪板**（只作设计输入），定下「温暖现代小镇」的色域与建筑语汇，
再把它落成一份 `.gpl`。**生成的图留在 scratchpad，不进仓库、不进精灵帧。**

---

### C6 · 模型路径：两个字符串 + 一个救不回来的熔断器（**C0 已落地，解除阻塞**）

**独占 `game/scripts/AIBackend.gd`。** C0 已把 BackendGate 接进 `tools/ci.sh` 第 4d 关（硬 8/8、两跑一致 8/8、无饿穿 8/8），
docs/42 §7.3 要求的前置条件**已满足**。两件事，都在同一个文件里，所以合成一棒。

**C6-a · docs/42 §7.3 的三条改法**（原文在那里，不重抄）。预期收益必须说实话：
这三条**买不到判断力**（八种编码下名次恒在 0.46-0.50 = 随机），
它们买到的是**去掉"系统性跳过吃饭睡觉"这个 bug**——1.5B 在出货 prompt 下只有 **4.8%** 的选择是吃饭或睡觉，
随机是 18.5%、引擎是 36.9%。**这是修 bug，不是加能力。**
注意第 2 条（编号字母表 `0-9/A-Z` → `A-Z`）会把可编号候选上限从 36 降到 26，`_cap_for_llm` 的 36 要跟着改——
这是**会移动模型路径行为**的改动，正是 4d 那道门存在的理由。

**C6-b · 熔断器复位**（新，见 §1.2b 发现 1）。`_slm_circuit_open` 全文件只被置 `true`（`:813`）、从不被置回 `false`。
会话内永久熔断是**故意的**（防 docs/34 的原生泄漏 OOM，`:814` 告警原文就这么写），**这一条不要动**。
要动的是：**`set_model_path()`(:467) 应当复位熔断**——换一个权重文件是一个全新的失败假设，
没有理由继承旧假设的熔断；否则用户熔断后从设置面板"换个模型试试"会得到**无声的失败**，
而 C3 正在把那个面板做成触屏可达。`request_backend()`(:225) 是否也该复位，**由你判断并给出理由**
（论据两边都有：切走再切回像是"重试"，但它并没有改变任何失败假设）。

**验收**
- `tools/ci.sh` → CI PASS，**金标逐字节不动**（这两处都在模型路径上，金标路 `backend=null` 根本不进 ⇒
  金标不动是**必要不充分**条件，docs/41 §2）。真正的证据是下面两条。
- **C6-a**：用 `game/bench/PickCtxDump.{gd,tscn}` 导出改前/改后的出货 prompt，逐字节 diff，证明改的正是那两个字符串
  且**没有连带改到别的**。`PickCtxDump` 直接调 `AIBackend` 的真函数（`_system_prompt`/`_cap_for_llm`/`build_prompt`），
  零重实现——**不要**用 `bench/log_decisions.gd`（它的 `_cap_order()` 会按 score 重排候选，对位置类问题会给出相反结论，
  docs/42 §9-4）也**不要**信仓库里那份 `bench/distill_contexts.jsonl`（是过期的老 JSON-schema prompt）。
- **C6-b**：写一个能证伪的对照——构造连续 ≥`SLM_CIRCUIT_TRIP` 次失败把熔断打开，断言
  ①熔断确实开了、②`set_model_path()` 之后它是关的、③在你**不改**的那条路上它仍然是开的。
  三条缺一条都说明你测的不是这个东西。
- 报告里写清：`_slm_circuit_open` 的每一处读点（`:747` / `:1085` / `:1126`）在复位后的行为是否都符合预期。

---

## 四、Stride 计划与阶段性产出

| Stride | 内容 | 产出 |
|---|---|---|
| 1 | C0 / C1 / C2 / C3 并行开跑；主 session 做 C5 与本文 | 本文 + docs/41 §6 增补 |
| 2 | 合并 stride-1 的棒；C6 开跑；C4（工具链 + **第一条视觉 CI 断言**，依赖 C3 的昼夜修复） | 合并后一次全量 CI |
| 3 | analyze & fix：眼验新画面，把 stride 1-2 暴露的问题收口 | 改前/改后对照图 |
| 4 | 阶段性产出：新录屏 → **整数倍缩放**的 GIF（现在 README 主图是 680×408，从 1280×768 做的 **0.53× 非整数**降采样，像素糊、文字全不可读）、截图集、docs/13 札记、README 中英双语更新 | `docs/media/*` + README |
| 5 | 新一轮评审：多 agent + 外部对抗评审（指令"REFUTE"），analyze & fix | 评审记录进 docs/13 |

**README 已知的自相矛盾（Stride 4 必修）**：`README.md:34` 仍写「最戏剧的五类社交事件目前**不会**出现在事件日志里」，
而 14 行之后的 `:48` 写「现在背叛、盟约、选举、结怨、和解都会自己浮上来」。**48 行是对的，34 行是过期的自我低估**——
正是 docs/41 §4 存在的理由。
