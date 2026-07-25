# 34 · 真机严重 bug：SLM 推理挂死 → 0 成功 + 16GB 原生内存泄漏 → OOM

**2026-07-25 真机（NX789J / 红魔 8 Elite，Android 15）实测发现。** 这是只有真机才挖得出的旗舰级 bug（见 memory `reference-godot-android-loop`）。

## 现象（perf overlay 实测）

- `后端 slm · 并发 2 · LLM 发起 40 · 成功 0 · 超时 38 · 无效 0` —— **40 次推理全超时，0 成功**，2 个永远挂在飞。
- 内存（`dumpsys meminfo` Native Heap）：15s→**3GB**，90s→**7.5GB**，160s→**16GB**——**无界线性增长 ≈ 90MB/s**。8 Elite 12-16GB RAM，几分钟必 OOM。
- 后果：①**旗舰 SLM 决策/语音实际从未生效**——每次超时都回退 logic 地板，玩家看到的"台词"全是罐头 logic 输出，不是 SLM；②内存泄漏几分钟崩。
- 注意：`OS.get_static_memory_usage()`（overlay 的"内存 145MB"）**只算 GDScript 侧**，看不到 llama.cpp/nobodywho 的原生分配——必须 `dumpsys meminfo` 看 Native Heap 才发现。FPS 78 正常（town 跑 logic 顺）。

## 机制（AIBackend.gd 读码定位）

1. **根因 = 推理【挂死】不返回**（不是慢）：2 个 worker 永远 inflight、40 发 0 成，`chat.response_finished` 信号从不触发。最可能是 **model.gguf（2026-06-28）↔ 当前构建的 NobodyWho GDExtension 不兼容 / 版本漂移 / 回归**（README 记录过它能跑，说明是后来坏的）。也可能是该 gguf 本身对当前 loader 不合。
2. **泄漏是挂死的症状**：主决策路径（AIBackend.gd:563-568）把 worker 存进 `_pending[id]["slm_chat"]`，超时 `_finish`(:408) 会 `_free_transport`→`stop_generation`+`queue_free`。但 **对一个卡在原生生成里的 worker，`stop_generation`+`queue_free` 释放不了那块原生 llama 上下文**（原生线程卡死 → KV/上下文不回收）。每次挂死漏 ~400MB × 40 ≈ 16GB。
3. **探测路径更漏**：`_probe_once`(:320-333) 是裸 `await chat.response_finished`、不进 `_pending`，挂死则 `await` 永阻、chat 永不 free、`cancel_all`/`_finish` 也够不着它。

## 建议修法（未做，需专门一轮）

- **治本**：查 SLM 挂死——换/验证一个与当前 NobodyWho 版本兼容的 gguf；或对齐 NobodyWho GDExtension 版本；桌面同款复现（`--backend slm`）二分是模型问题还是集成回归。
- **防 OOM（防御性，独立于治本）**：加**熔断器**——连续 N 次推理 0 成功（或超时率 100%）就【停发 SLM、永久回退 logic】，避免继续 fire 注定挂死的推理堆积泄漏。这样即使 SLM 坏了，也只是"没有 LLM 增强"，而不是崩。
- **探测路径**：给 `_probe_once` 的 `await` 加超时兜底 + 无条件 free（别裸 await 挂死信号）。
- **可观测**：把 Native Heap（`dumpsys meminfo`）纳入真机 perf 检查——`OS.get_static_memory_usage` 看不到原生泄漏。

## 更新（同日）：根因收窄 + 熔断器已修并【真机验证】

**根因收窄到 Adreno GPU Vulkan**：写了 `bench/slm_smoke.gd`（最小推理冒烟）在【桌面】跑同一个 gguf——
- CPU：✅ 1498ms 返回 `{"i":1}`；GPU（AMD Radeon 8060S Vulkan）：✅ 1207ms 返回。
- 即 **NobodyWho 集成 + 模型本身在桌面 CPU/GPU 都好**（~1.2-1.5s，合 README）。→ 真机挂死是 **arm64 / Adreno GPU Vulkan 特定**（llama.cpp/ggml 的 Adreno Vulkan compute 是出了名的坑）。`slm_use_gpu` 默认 true → 真机走 Adreno GPU → 挂死。另观察到**模型 LOAD 本身也会卡住主线程**（真机启动探测期 FPS 掉到 1）。

**熔断器已修 + 真机验证通过**（AIBackend.gd）：连续 `SLM_CIRCUIT_TRIP=6` 次超时 → 开熔断、停发 SLM、永久回退 logic（decide/reflect/chat=_gen_slm 三处 fire 全门控）+ `cancel_all` 止血。真机实测对比：
| | 无熔断 | 熔断后 |
|---|---|---|
| LLM stats | 发起40·成功0·超时38 | **发起7·超时6→触发熔断**、并发0 |
| Native Heap | 3→7.5→**16GB**(OOM) | **~2.3GB 封顶不涨** |
| FPS | 卡死 | **恢复 79**、tick 12/s |
| 镇子 | — | logic 地板照常活（八卦/discuss/送礼） |
熔断器为 slm-only + 默认关 → logic 确定性红线不受影响（V1 逐字节验证）。残留 ~1.2GB（6-7 个卡死 worker 未释放）已封顶不涨，可接受（防了 OOM）。

**剩余（交专门一轮，见 spawn_task）**：治本 Adreno GPU 挂死——①真机试 CPU 推理(`slm_use_gpu=false`，但容器测 ~1字/s 恐太慢，需 8Elite CPU 实测)；②升级/换 NobodyWho arm64 构建或换 llama.cpp Vulkan 后端；③`_probe_once` 裸 await 加超时兜底 + 无条件 free（现在探测挂死漏 1 worker + 卡主线程）。

## ⚠️ 更正（同日、深挖后）：根因【不是】Adreno——是 worker 生命周期 use-after-free

上一段"根因收窄到 Adreno GPU Vulkan"**被我自己的后续测试证伪**——典型的"只测了方便那条路"（见 memory `feedback-adversarial-external-review`）。`slm_smoke.gd` 是【最小路径】：单 worker、await 到底、之后才 free，**根本没碰真实集成**。补了 `bench/BackendBench.tscn`（跑真·游戏内 `AIBackend.decide` 路径）在桌面 AMD Vulkan 上一测：

- **桌面照样崩**（EXIT 139 段错误）。panic 明确：`NobodyWhoChat::clone: access to instance … after it has been freed`。
- 崩前统计：**fired=46 landed=35 timeout=0 合致 77.8%**——SLM 功能其实是好的、模型也快（timeout=0），**崩在 teardown**。
- 日志：**116 个 "Initializing worker" 对 46 次决策**——旧实现【每次决策/反思/对话都 new 一个 NobodyWhoChat + start_worker + 完成即 queue_free】，高频决策下每秒起/放几十个 worker；一旦在 worker 仍在飞时 free 它（超时/落地/cancel_all/下一发），扩展的异步回包访问【已释放】节点 → godot-rust panic → 崩。

**统一解释（桌面崩 vs 手机泄漏 = 同一 bug 两种表现）**：per-call worker churn + mid-flight free。桌面模型快 → free 抢在回包前 → use-after-free 崩；手机 Adreno 挂死 → worker 卡在原生 compute 释放不掉 → 16GB 泄漏。

### 治本修法（已实现 + 桌面验证）：池化持久 worker（commit 见 git）

全局只养【一个】持久 NobodyWhoChat，`reset_context()` 复用，串行（一次一发，本地推理本就串行），**绝不在在飞时 free**；signal 用【每发一次性闭包捕获 `world_epoch`】（cancel_all 后迟包按 epoch 作废，不污染复用 worker）+ `fired[]` 去重防双触发。决策/反思/对话三路统一走 `_slm_submit`。

- 桌面验证（BackendBench，1.5B，AMD Vulkan GPU）：**运行中 0 panic**（旧=段错误崩）；worker churn **116→2**；3 sim-日 fired=129 landed=101 timeout=0 **合致 78.3%**（含夜间 reflect cb 路径）。
- **红线**：改动纯 slm 后端；**确定性逐字节 det 1/1、37 硬不变量全绿**（S0 gate；软 #26 是既有 flap，`git stash` 对照证实与本改无关）。
- **手机附带收益**：`_slm_busy` 门在【第一次 Adreno 挂死后即封住】→ 后续决策全走 logic、**只留 1 个 hung worker**（比熔断器的 6 个更早封顶）；熔断器保留为冗余兜底。
- 残留：仅【进程退出 teardown】时 1 次良性 panic（NobodyWho 关停线程序问题，旧代码也有；进程本在退出，EXIT 0 不影响）。

**旗舰级仍待办**：手机上 SLM 本身仍因 Adreno Vulkan 挂死【不产出决策】（池化只让它优雅降级、不崩不泄）。真正让端侧 SLM 在 8Elite 上跑起来 = 试 CPU 推理 / 换 NobodyWho 后端——见 spawn_task。**手机眼验（重出 APK + dumpsys Native Heap）待下一轮**。

## 对抗评审两轮 → 三个 follow-up 修复（C1/C2/C3）

池化修法 push 后，过两轮独立对抗评审（repo-grounded subagent + 4-lens workflow，均指令"尽力 REFUTE"），抓出 3 个真缺陷，含一个【我自己引入的回归】：

- **C1（换模型 UAF）**：`set_model_path`（设置面板 A/B 换 gguf）原本只 free `_slm_model`、留着 chat（model_node 悬垂 → 静默 no-op）。我第一版"顺手"把 chat 也 `queue_free`——**却重新引入了池化本要消灭的 use-after-free**：换模型时若正好有决策在飞，同步 free 掉 worker 仍会回包的 chat → 崩。第二轮评审逮到。**终修**：绝不同步 free 在飞 chat——有在飞 → 标 `_slm_reload_pending` + cancel_all，真正的拆由该 worker 的 finish 收尾时执行（那时它已完成）；期间 `_slm_submit` 被 pending 挡住不起新活。桌面测：运行中 tick 60 换模型（撞在飞决策）**0 运行中崩、SLM 重建续跑（fired 3→24）**。
- **C2（信号连接泄漏）**：per-submit 的 `worker_failed` 用 CONNECT_ONE_SHOT，健康路径永不触发 → 永不消费 → 每次成功决策残留一个死闭包在持久 chat 上，O(submits) 累积。**修**：改显式"触发即断开两条连接"。
- **C3（探测路径同款反模式）**：`_probe_once` 仍 per-call new chat + 【裸 await 无超时】（Adreno 挂死 → 永阻卡启动，且这是真机【最先】走的路径）。**修**：改走池化 worker + 墙钟轮询超时（`PROBE_TIMEOUT_MS=150s`）+ 探测发占用 `_slm_busy`（防换模型误拆正在用的 chat）+ 一发超时即收手不跑第 2 发（否则挂死 worker 的迟包会触发第 2 发 handler → 误判"快" → 错误启用 slm）。注：轮询超时只兜 **worker 线程级挂死**（镇子仍跑 FPS79，正是真机实测所见）；整卡 GPU 锁死连渲染帧都停则全 app 冻结、非引擎内超时可救、非本修范围。
- 另修评审 finding-5 / C2-d：finish 里 `_slm_busy=false` 移到投递【后】且仅当 epoch 匹配才清 → 陈旧迟包不再抹掉活跃后继的 busy、同步重入的 cb 不会在信号发射中被误纳。

**红线复核（评审 lens-4 无法证伪）**：三处改动全在 slm 后端 / UI / 探测-slm 路径；CI 用 `backend=null` 从不进 `AIBackend.decide`，`logic` 也在 `_slm_busy` 门【之前】return；无新增类级成员（仅一个 const）→ 不入 save/load 与 digest。桌面复验：**det 逐字节 1/1、37 硬不变量全绿、BackendBench 0 运行中崩**。

**熔断器角色更正**：池化后 `_slm_busy` 门在第一次挂死即封住（只留 1 worker），比 `SLM_CIRCUIT_TRIP=6` 更早触顶——故熔断器不再是"挂死"路径的主力，而是覆盖"慢但仍回包"退化的互补层（连续 6 次超时但 worker 仍活 → 熔断）。二者互补，非死码。

**方法论收获**：一条"根因"结论 + 一版"修复"，都被【指令去反驳的独立评审】各自推翻过一次（Adreno→worker 生命周期；C1 第一版反而引入崩溃）。教训与 [[feedback-adversarial-external-review]] 完全一致——顺手那条路/顺手那版修，往往漏掉真集成路径与新回归。

## ✅ 手机眼验补齐（2026-07-25，silly-wiles worktree）——池化治本【真机确认】+ 残留精确刻画

**用【当前已装 pooled 版 APK】（15:09 装机）满负载真机眼验**（无线 adb 192.168.1.127:40405，`dumpsys meminfo` 看 Native Heap，`run-as` 读设置/探针文件）。设备解析模型=`Documents/LivingTown/model.gguf`（1.5B，md5 `8e5111fd…` 与桌面已验证库【逐字节相同】→ 模型本身证清白）。

**① 崩溃/OOM 治本【真机确认】**——满负载跑 backend=slm 跑到第 13 sim-日：
| | 旧版(churn) | 【本次真机 pooled】 |
|---|---|---|
| Native Heap 轨迹 | 3→7.5→**16GB** 无界→OOM | 峰值 **3.2GB**(load)→跌到 **217MB 封顶不涨** |
| 崩溃 | 桌面段错误/手机挂死 | **0 崩**、跑满 13 日 |
| FPS | 卡死 | **88-91**、tick 12/s |
→ 池化 worker 对 16GB 原生泄漏 + 崩溃的治本，**在真机满负载下坐实**（不是只有 headless 桌面）。这补齐了上一段"手机眼验待下一轮"。

**② 残留精确刻画——【不是挂死】，是解码超时→熔断跳**：perf overlay 实测 `发起 8·成功 1·超时 6·并发 0`，且推进 7 sim-日后计数【冻结不动】=熔断(连 6 超时)已跳→SLM 永久停发、镇子跑 logic 地板。上一轮设备探针文件(`livingtown_probe.txt` 15:18)记 `tier=host p50=2692ms`——即**单发探针(易路径)在 Adreno GPU 上 2.7s 能返回、不挂死**；但**满负载·在飞决策路径解码 >12s**（渲染+12-agent 仿真抢 GPU/CPU + 热节流），过截止线→超时→熔断。**故根因表述再更正：手机 SLM 不是"挂死不返回"，是"满负载下解码太慢过 deadline"**——工作正常、只是慢。

### 本轮代码修（AIBackend.gd，全 slm-only；红线：det 窗口 digest 逐字节一致 `200 2803220390…`、S0 37 硬不变量 6/6、det 3/3）
1. **熔断只在【真·零完成】兜底**（治残留②的误伤）：`_slm_submit` 的 `on_done`/`on_fail` 有【任何】完成即 `_slm_fail_streak=0`——慢·但·会返回的解码不再被误当"挂死"触发熔断把工作正常的 SLM 停发。（池化+串行下真挂死本就只漏 1 worker、堆封顶，熔断变冗余兜底即可。）
2. **C2 句柄泄漏修**：`worker_failed` 用 `CONNECT_ONE_SHOT` 在健康路径【永不触发】→每次成功决策残留一个死闭包在持久 `_slm_chat` 上 O(submits) 泄漏。改：不用 one-shot，`finish` 里显式断两条连接。（pristine bd74e4d 与初版都有此漏。）
3. **C1 `set_model_path` UAF 修**：换模型只卸 `_slm_model` 没卸池化 `_slm_chat`→悬垂/新模型不加载。改：连带卸 chat。
4. **`_probe_once` 硬化(item③)**：裸 `await response_finished` → 超时竞速(`_await_signal_or_timeout`)+无条件 free——真机挂死不再永阻主线程/漏探测 worker。
5. **`slm_use_gpu` settings 旋钮**（`[slm] use_gpu`，`_load_user_settings` 读 + `set_slm_use_gpu` 存盘卸重载）：真机 `run-as` 写 `settings.cfg` 即切 CPU/GPU，**免重打包**做 A/B。
6. **延迟埋点 `_slm_log`**：把每发 SLM 真实延迟+结果落 `Documents/livingtown_slm.txt`（前 60 发，adb-pull）——overlay 只给计数、读不到延迟；用于区分"慢但会返回"vs"真挂死"、对拍 GPU/CPU。

桌面验证（BackendBench，1.5B，AMD Vulkan）：**fired=123 landed=96 timeout=0 合致 78.0%**（对齐旧 78.3%，无回归）、埋点写盘正常（`#1 done lat=1020ms … #2 done lat=90ms`）、仅进程退出 teardown 1 次良性 panic。

### ✅ 决定性一步已做——真机 GPU vs CPU A/B：**CPU 完胜，端上默认改 CPU**
重打包【带旋钮+埋点】APK 装机，`run-as` 翻 `[slm] use_gpu`，`adb pull livingtown_slm.txt` 读**真·满负载在飞解码延迟**（overlay 只给计数、读不到延迟——这就是埋点的价值）：

| | 在飞解码延迟(满负载) | Native Heap | 落在 12s 线内? |
|---|---|---|---|
| **GPU(Adreno)** | **~16-20s**（15.7-20.2s，7 发全 `done`） | 540MB 平 | **从不**（全超时） |
| **CPU(8Elite)** | **~3-8s 暖**（冷#1=14s，之后 3-8s，19 发全 `done`） | 410MB 平 | **多数是** |

- **CPU 比 Adreno GPU 快 ~3-4×**：GPU 被渲染器抢占（同一 Adreno 又渲染又推理）→ 决策解码 16-20s；CPU 推理不与渲染抢 → 3-8s，多数 <12s 截止线 → **决策真落地**。容器"~1字/s"的担心对 8Elite 不成立（其 CPU 强，满负载 3-8s 完成 1.5B 一发决策）。
- 两者都 `done`（无 fail/挂死）+ Native Heap 平（无泄漏）→ 再证根因是【慢·非挂死】，且池化+熔断修在真机稳。
- **治法落地**：`_ready` 里 `if OS.has_feature("android"): slm_use_gpu = false`（端上默认 CPU；桌面独显不抢渲染→保持 GPU；`[slm] use_gpu` 设置仍可显式覆盖）。红线：安卓+slm-only、桌面 no-op、det 窗口 digest 逐字节一致。
- **端到端眼验（CPU 版 overlay，跑到第 19 sim-日）**：`后端 slm·并发 1 · 发起 51·成功 34·超时 1·无效 15`——**落地率 ~67%（34/51）**、超时仅 1、**熔断未跳·SLM 持续产出**（对比 GPU/旧版=成功 1 后熔断冻死）。即**手机上 NPC 决策 2/3 真由端侧 SLM 驱动**（其余 15 无效=1.5B 偶回 prose 非纯编号，parse_decision 兜底、优雅退 logic）。**诚实权衡**：CPU 推理活跃时 FPS 88→34（推理与游戏主循环抢 CPU 核；决策已按 host 档节流，34 FPS 仍可玩）——若要更高 FPS 可换更小模型/限核/降节流频率。
- **deadline 提到 15s（已做+真机验证）**：`DEADLINE_MS 12000→15000`（clamp 上限同步）——把少数暖发 8-14s 也捞回落地。**真机复测**（重打包装机、`deadline=15000` 实测）：暖发 4-10s **全落 15s 线内**、`超时` 降到**只剩冷启首发一次**（#1=35s 含模型 load）；overlay `发起18·成功11·超时1·无效5`——非落地主因已从"超时"变成"无效"(1.5B 偶回 prose 非纯编号，parse_decision 兜底)，即**瓶颈从延迟转到模型输出质量**（后续可换更规整的蒸馏模型/加约束解码）。红线：仅 slm/llm 异步路读 deadline_ms，logic/CI 不碰→det 逐字节一致。

### ⚠️ 多 agent 并行 → 已合并（scale-diagnostic `5707247`）
本轮 #34 治本是多 worktree fan-out——`objective-sinoussi`(已提交熔断+probe超时)、主 worktree(C1/C2/C3 生命周期修)、silly-wiles(真机眼验+旋钮+埋点+GPU/CPU A/B+端上 CPU 默认)。**已 3-way 合并取并集**：以主的 C1/C2/C3 为 `AIBackend.gd` 基座（生命周期更稳：换模型延后拆、`PROBE_TIMEOUT_MS=150s` 池化探测、finish 投递后仅 owner 清 busy），叠加 silly-wiles 的 CPU 默认 / 熔断-streak-reset / `_slm_log` 埋点 / `slm_use_gpu` 旋钮(沿用 C1 延后拆) / `DEADLINE_MS 15000`。桌面复验：det 逐字节一致、S0 37/6-6+det 3/3、BackendBench slm 79.7% 落地。

**合并版装机眼验（`livingtown-merged.apk`，CPU）**：overlay `发起22·成功13·超时0·无效8`——**超时=0**（对方池化探测【预热】worker→无 35s 冷启决策，所有在飞解码 4-12.5s 全落 15s 线内）、Heap ~400MB 平、FPS 46。比 silly-wiles 单独版（timeout=1 冷启/FPS34）更好。**延迟已彻底不是失败模式**——非落地只剩 `无效`=1.5B 偶回 prose（parse_decision 兜底）→ 下一步杠杆是模型输出质量（更规整的蒸馏模型/约束解码），非引擎。

## 影响评级

**高（本轮基本收口）**：真机 backend=slm 曾【旗舰不生效 + 崩/OOM】。现状：
- **崩溃与 OOM 泄漏已治本【真机满负载坐实】**（Native Heap 3.2GB→217MB 封顶、13 日 0 崩、FPS 88-91）。
- **手机 SLM 产出决策的路也通了**：根因坐实为【满负载 Adreno GPU 解码 16-20s 超 12s 线】（非挂死）；**改端上默认 CPU 推理→暖发 3-8s 多数落线内→决策真落地**（真机 A/B 实测，埋点为证）。
- 桌面 SLM 完全可用（78% 合致）、手机 CPU 下 SLM 真生效、无模型/极慢仍优雅降 logic 地板（红线：无模型也能玩）。
- **多 agent 三支已合并**（scale-diagnostic `5707247`）+ **合并版装机眼验通过**（CPU 下 timeout=0、Heap 平、FPS46）。残留只剩模型输出质量（bad_parse=偶回 prose），非引擎/非延迟——后续换更规整蒸馏模型即可再提落地率。
