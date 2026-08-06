# 126 · Wave AG · AG3 设计——**"整镇纵切"的现状是"已建九成，缺的是收口 + 门 + 证据"，不是"从零实现"**

> 依据：docs/41（红线四条，尤其 R1 确定性/R2 素材 CC0；§2.5 探测包络；§6 视觉/工具链盲区）、
> docs/113 §三（功能轨道 map/interior、并行纪律）、docs/123（Wave AG 计划，本棒 brief）、
> **手法与包络规格照抄**：docs/69（R2 室内外壳）、docs/86（V3 镇外立面）、docs/122（AF2 夜/季视觉门）、
> docs/46 §二·九（界外层 `_void_key` bug 与"计数器≠像素"）、docs/47 §五-E6（空间往返采集 W7）。
>
> **基线**：本 worktree checkout 开工时在 `38ba4a7`（落后 319 commit）。`git merge-base --is-ancestor` 确认它是
> `integration/batons`=`091411c` 的祖先后 **ff 到 `091411c`**（docs/123 在 ff 之前不在这棵树上）。
>
> **只设计不实现（§0.8）。单根只读棒。owns：只写本文（编号 126）。除此之外一个字节都不改**
> ——读代码、隔离副本跑探针=可以；改 trunk=不行。收尾 `git diff --stat` 只应有 docs/126。

---

## 〇、一句话结论（**先说清楚，免得照 brief 的假设去"从零实现"**）

brief（docs/123 §四·P2B 那条）把这一轨写成"选一栋建筑 + 街区，做完整：外立面→室内布局→多楼层 portal→
拖拽/探查→返回世界坐标→视觉回归"，读起来像一块**绿地**。**实测证伪**：这六段**在 trunk 上全部已经在跑**，
而且**阿丽的咖啡馆（cafe）就是那栋已经手工精修过的两层纵切样板**。这是 docs/51 那条 H1/S3 教训的**反向发作**
（与 docs/122 §六·1 的季节同型）：不是"以为做了其实没做"，是**"以为要从头做，其实九成已在"**。

⇒ 本设计的产出**不是**"实现一个纵切"，而是回答两个真问题：
1. **收口**：这九成里唯一一个**出货路径上的真功能缺陷**是什么、怎么补（**暂停时点门画面不刷新**，§二·P-A）；
2. **立证**：这九成里**哪些性质今天没有门守着**、要补哪几道门才能让用户敢在它上面拍下一波（多楼层视觉回归 + 楼层/空间切换的观察者无关性，§二·P-B/P-D、§四）。

并且**纠正一处会误导下一波的坐标腐烂**：`spaces.json` 的 cafe `_note` 还写着"Tier-A：只 Probe inspect，**居民不进**、
digest 逐字节不变"，而 `agents.json` 里 **阿丽（aria）此刻就住在 cafe/2f**、按 portal 真的在镇↔店之间走动（Tier-B，
见 §三）。那句注释描述的是一个**已经翻篇的阶段**，照它去设计会把"agent 平面地址是仿真态"当成"纯 Probe 观察态"——
而这正好是本棒 R1 边界最要命的一刀（§三）。

---

## 一、现状盘点——**先说清楚每一行量的是什么对象，再给行号**

量的对象：`integration/batons`=`091411c` 这棵树上的 `game/scripts/*.gd` + `game/data/*.json` + `tools/*` + `game/bench/*`，
用 grep/read 静态读 + 结构核对（**未在真机、未跑全量 CI**——本棒只读设计，见 §七）。行号以本基线为准（docs/41 §1.5①：行号是本仓库最易腐烂的事实，故引符号也引行号，且都实读过）。

### 1.1 地理（纵切选址的事实底座）

`game/data/map.json` 的 `areas`（**量的是 map.json 里每个 area 的 type + rect**，格坐标）：

| area | type | rect [x,y,w,h] | 有街门 portal | 有楼梯 portal（多层） |
|---|---|---|---|---|
| **cafe（阿丽的咖啡馆）** | **commercial** | **[37,13,9,7]** | ✅ p_cafe_door | ✅ **p_cafe_stairs（1f↔2f）** |
| work（工坊） | workshop | [37,28,9,7] | ✅ p_work_door | — |
| plaza（广场，镇心） | plaza | [28,21,8,6] | —（开放区） | — |
| shop（杂货铺） | commercial | [49,5,7,6] | ✅ p_shop_door | — |
| home / home2 | residential | [18,13,9,7] / [9,4,6,5] | ✅ | — |
| wash / library | public | [18,28,9,7] / [9,38,7,6] | ✅ | — |

镇是 64×48 格（`spaces.json` town.bounds）。**cafe 是全镇唯一一栋有手工两层室内 + owner 权限楼梯的建筑**，
它南邻 work、西接 plaza、东北是 shop——**"一栋建筑 + 周边街区"的天然答案就是 cafe 街区**（§二）。

### 1.2 六段纵切的现状（**各给行号 + 已有/缺**）

| 纵切段 | 现状（量到的对象 + 行号） | 判决 |
|---|---|---|
| **① 外立面** | `WorldView._draw_facades()`（`WorldView.gd:1014-1050`）：按 `areas[].type` 取 `BLD_PAL` 上色，等距开窗（`_draw_window` :1056）、夜窗点灯（`_window_lit`）、住宅/工坊烟囱冒烟。**上色手法=R2**（型别→调色板），非新增仿真态。 | **已有** |
| **② 室内布局** | `interiors.json`：**cafe 1f（咖啡区：吧台/咖啡机/桌椅）+ 2f（阿丽居所：床/书桌/书架）手工精修**；其余 7 栋由 `interior_templates.json` 按型别（residential/commercial/public/workshop）生成。绘制：`WorldView._draw_interior()`（`:1310-1359`）=地板+外墙(门口留缺)+家具+夜氛围+在场居民+楼层标签；外壳配方 `_interior_shell()`（`:1412-1431`，R2：型别→墙/地板，与外立面同源 `areas[].type`）；家具按 slot 程序化 `_draw_interior_furniture()`（`:1489+`）+ 按房间用途分化 `_furniture_role()`（S3）。 | **已有**（cafe 是精修样板） |
| **③ 多楼层 portal** | `spaces.json` portals：`p_cafe_door`（town/outdoor[41,19]↔cafe/1f[4,5]，public）、`p_cafe_stairs`（cafe/1f[1,1]↔cafe/2f[1,1]，**owner** 权限）。读取/查询/校验：`SpaceGraph.gd`（`portals_from` :71-83，`validate` :98-130）。交互：`Main._portal_click()`（`:2439-2467`）自然穿门（点门=进/上下楼/出）、`_probe_cycle_floor()`（PgUp/PgDn，`:2427`）、`_probe_toggle_space()`（I 键循环，`:2417`）。 | **已有** |
| **④ 相机/拖拽/缩放/探查** | `ProbeController.gd`（**纯 View，拥有 Camera2D**，抬头 :2-8）：`handle_input()`（拖/平移/滚轮缩/点选/双击，`:245-292`）、`zoom_at()`（zoom-to-cursor，`:137`）、`set_space/go_home/go_back/focus/follow`（:190/:163/:151/:171/:177）。选点→hit-test：`Main._on_probe_tap/_on_probe_double_tap`（`:2469-2483`）。 | **已有** |
| **⑤ 返回世界坐标** | `Main._portal_click` 出门分支 → `_probe.go_home()`（`:2456-2457`，固定取景，与启动逐字节同源）；返回栈 `ProbeController.go_back()`（`:151`）。SpaceShot 把"出店后取景 == 进店前"**断言**下来（`SpaceShot.gd:130` cam_same）。 | **已有** |
| **⑥ 视觉回归** | `game/bench/SpaceShot.gd` + `tools/space_roundtrip.sh` + `tools/assert_space_roundtrip.py`（进店→室内→出店三帧 A/B/C 判据，阈值实测、带回滚负对照）。已接进 `visual_gate.sh`（rc=3）→ `ci.sh` 第 6 步。另有 `assert_daynight`/`assert_interior_shell`/`assert_furniture_role`/`assert_tree_stand` + `--void-gate` 同步在守。 | **已有**（但只守 town↔cafe/**1f**，见下） |

### 1.3 缺什么（**这才是纵切"没做完"的部分**）

盘完六段，"缺"的不是段本身，是**这三处收口 + 立证**（量出来的，非估计）：

1. **暂停时点门，世界层不刷新**（**唯一的出货路径真 bug**）：`Main._portal_click`（`:2439-2467`）只做 View（`set_space`/相机）+ HUD（`_push`/`_update_status`），**一处都不排 WorldView 重画**。而 WorldView 只在三处 `queue_redraw`：`Sim.ticked`/`Sim.agent_changed`（`WorldView.gd:558-559`→`_redraw_all`）与 `_process` 渲染坐标脏（SpaceShot 归因 `:2177`）。⇒ `Sim.running=false`（空格暂停，出货键位）时 tick 永不到 ⇒ **暂停点门进店，画面一直停在小镇上**（`SpaceShot.gd:149-164` 实测记录，报给 E4/E5，**至今 trunk 未修**，我在 `091411c` 上复核 `_portal_click` 仍无 `queue_redraw`）。
2. **多楼层视觉回归=零**：`visual_gate.sh:161` 把室内采集**写死 `--probe-floor 1f`**，7 栋都只拍 1f。⇒ **cafe 2f（阿丽居所——"多楼层"这四个字的全部意义）从没有任何一帧被任何门看过。** `assert_space_roundtrip` 也只走 town↔cafe/1f，**楼梯往返（1f↔2f）无门**。
3. **楼层/空间切换的观察者无关性=未被门覆盖**：R1 硬门 `probe_digest_test.sh` 只注入**平移+缩放**（拖 8 段 + `plus/minus`），**从不按 I/PgUp/PgDn/点门**。⇒ "Probe 换 Space/换 Floor 不动 digest"今天是**靠构造成立、非靠门守**（`set_space`/`active_floor` 写在 ProbeController、结构上就不进 digest，但门没测过这条路）。

---

## 二、纵切的最小可玩范围——**选 cafe 街区，补收口三件 + 立证两件，全部用已有数据/手法**

**选址**：**阿丽的咖啡馆（cafe，commercial [37,13,9,7]）+ 其街区**（南邻 work 工坊、西接 plaza 广场、东北 shop 杂货铺）。
理由：它已是唯一手工两层样板（1f 公共咖啡区 + 2f 阿丽私人居所=**两种真不同的室内布局**）、唯一 owner 权限楼梯（**多楼层 portal**）、
阿丽真住 2f（**返回世界坐标 = 她按 portal 在镇↔店走动**，§三）。**"不同室内布局 + 多楼层 portal"这两项，cafe 单栋已足**，
不必新造第二栋——街区里其余三栋（work/plaza/shop）提供"外立面 + 单层室内 + 街门"的**对照面**，让纵切在一个连续视野里成立。

**红线自检**（§二共同约束）：以下**每一项都不新增仿真态、不动社会决策 schema（事件/关系/信念）、不引入生成图素材**——
消费的是**已有的 R2 型别上色、已有的 spaces/interiors/portal 数据、已有的 Probe/SpaceShot 采集路径**。

| 编号 | 收口/立证项 | 用什么已有数据/手法（**不新增仿真态**） | 触碰文件（实现波的 owns，本设计不写） |
|---|---|---|---|
| **P-A** | **修"暂停点门不刷新"** | 在 `Main._portal_click` 末尾加**一行** `_view.queue_redraw()`——**照抄** trunk 已有的同型修法：`dbg_nav` 切换时 `Main.gd:2047` 就是这么补的（`WorldView.gd:609` 注释点名"这条**不在** signal 之列，Main 自己补了 `_view.queue_redraw()"`）。纯 View，WorldView 是渲染层、Sim 从不读它。 | `game/scripts/Main.gd`（一行） |
| **P-B** | **多楼层视觉回归** | ① 让 `visual_gate.sh` 对 **cafe 额外拍一张 `--probe-floor 2f`**（现成的 `--probe-space/--probe-floor` 启动参数，`Main.gd:381-384,482-484`，无需改引擎）；② 给 SpaceShot 加一条**楼梯往返腿**（town→cafe/1f→**上楼 2f**→**下楼 1f**→出门），复用它已有的 portal 驱动（`tapped`→`_portal_click`，`SpaceShot.gd:180-199`）；③ 判据扩到"2f 与 1f 可分 + 1f 往返逐像素不变"（§四）。 | `game/bench/SpaceShot.gd`、`tools/space_roundtrip.sh`、`tools/assert_space_roundtrip.py`、`tools/visual_gate.sh` |
| **P-C**（可选） | **外立面↔室内型别一致门** | `_draw_facades` 与 `_interior_shell` **同源读 `areas[].type`**（分别 `WorldView.gd:1026` / `:1413`）⇒ 今天天然一致。补一道**关系判据**门锁住"外面看到的建筑型别 == 进门后的外壳型别"，防将来两处分叉。低成本、纯 B 臂。 | `tools/`（新判据） |
| **P-D** | **补 R1 观察者无关性的楼层/空间腿** | 给 `probe_digest_test.sh` 的"狂拖狂缩"臂 B **加注入**：`i`（进/出测试 Space）、`Prior`/`Next`（PgUp/PgDn 换层）、点门（`space` 单步之外的键）。断言 A/B 两跑 `(tick,digest,event_digest)` 仍逐字节相同——**把"换空间/换层是 view-only"从"靠构造"升级为"有门守"**。 | `tools/probe_digest_test.sh` |
| **P-E** | **纠正腐烂注释 + 冻结接口** | 把 `spaces.json` cafe `_note` 的"Tier-A：居民不进"改成实况（阿丽住 2f，Tier-B）；冻结 space/floor schema 面（§五）。 | `game/data/spaces.json`（注释）；本设计给冻结清单 |

**明确不做**（§二/task 边界）：不新增居民、不给 cafe 加新 advertises 家具、不改 `Sim.gd` 的 agent 状态布局、
不碰事件/关系/信念——**任何会移动金标的 Sim 改动都不在本纵切内**（§三给出为什么这样纵切能与 semi-macro/state_projection 波并行）。

---

## 三、R1 红线边界——**哪些是 view-only（给证据）、哪些碰 `space·floor` 要进金标路**

这是本棒最实质的一节。task 问"拖拽/相机/楼层切换是表现层还是会碰仿真态"。**答案分两半，而两半在代码里【已经】干净分开**：

### 3.1 View-only（**绝不进 digest**）——逐条给证据

| 字段/操作 | 归属 | 证据（行号 + 门） |
|---|---|---|
| 相机 pos/zoom/mode/follow/focus/返回栈 | `ProbeController` | 抬头红线"ProbeState 不进 digest/event_log/RNG/存档"（`ProbeController.gd:2-8`）。**硬门**：`probe_digest_test.sh`——同 seed 同步进步数，A 不碰相机 vs B 狂拖狂缩+捏合，两跑 `(tick,digest,event_digest)` 逐字节相同才 PASS。 |
| `active_space` / `active_floor`（Probe 观察哪个平面） | `ProbeController` | `set_space`（`:190-197`）/`active_floor`（`:193`）只改 Probe 自己的 bounds/相机，**不移动任何 Agent、不写 Sim**（`Main._demo_go_space` 注释 `Main.gd:1151`；`_probe_toggle_space/_probe_cycle_floor` 注释"观察者切空间；居民没动" `:2424`）。⚠️ **但今天没有门专门测这条路**——见 §一·1.3-③、§二·P-D。 |
| `WorldView` 全部绘制（外立面/室内/夜氛围/型别上色） | `WorldView` | WorldView 是纯渲染，`Sim` 从不读它（`_interior_shell` 注释"Sim 侧从不读 `areas[].type`，D6/F5 已记" `:1411`；SpaceShot 抬头"一个字节都不改 game/scripts" `:41`）。改绘制常量不动 digest 已被 docs/122 §三三条独立证据钉死。 |
| **P-A 的修法**（`_portal_click` 里补 `queue_redraw`） | `WorldView` 调度 | `queue_redraw()` 只让本 CanvasItem 下一帧重画，**不碰任何 Sim 态/缓存**（与 `Main.gd:2047` 的 `dbg_nav` 补丁同型，SpaceShot `:166-171` 已论证 `_redraw_all` 只 `queue_redraw` 本节点+灯层、不碰缓存）。⇒ **是 view-only**，但 §五要求它**用逐字节 digest A/B 证出来、不假设**。 |

⇒ **纵切的相机/拖拽/缩放/Probe 换层换空间——全是表现层**。P-A/P-B/P-C/P-D 都落在这一侧：**不碰 `space·floor` 的【仿真】态，因此不需要 R12 重烘金标**。

### 3.2 仿真态（**在 digest 里，走金标路**）——已经在了，本纵切【只消费、不扩张】

⚠️ **这是必须纠正的坐标腐烂**：`agent.space` / `agent.floor` / `agent.spatial_address` / `agent.area` / `agent.room` 是**仿真态**，不是观察态。实测（`agents.json` + `Sim.gd`）：

- **阿丽（aria）此刻住 cafe/2f/[2,2]**；8/12 居民带 `spatial_address`（ben/coco/dan/evy/lin/hai/tie 住 home/1f），其余 4 人兜底 town/outdoor。
- 候选枚举**按 agent 的 space/floor 过滤**（`Sim.gd:1633-1650`：只有同平面的对象才进候选）。
- 居民**真的按 portal 跨平面走**：`_journey_candidates`（`:1630`）发起"回咖啡馆"承诺行程，`_route_next_hop`（`:4067`）+ `_move_agent`（`:3881`）逐跳更新平面感知 `area`/`room`。
- ⇒ **agent 换平面 = 一次 Sim 动作，经 Portal，进 digest**。这是 P3 **Tier-B**（`Sim.gd:240` 注释），它落地时（按构造）已经蓄意移动过金标。

**结论（R1 的那一刀）**：
> **Probe 侧的 `active_space/active_floor` 是 view-only（不进 digest，靠 ProbeController 结构 + probe_digest_test 门）；
> agent 侧的 `space/floor/spatial_address` 是仿真态（在 digest，靠金标 + 硬不变量）。二者同名不同物，是本纵切最容易被 `spaces.json` 那句腐烂注释带偏的地方。**

**因此本纵切【不碰】agent 侧那一半**：不加居民、不加 advertises、不改 agent 状态布局 ⇒ **纵切自身不移动金标、不需要 R12**。
**反过来的红线要写清**：*若*将来有人想"让更多居民入住 cafe / 给 2f 加可交互家具" —— 那**会**移动 digest、**必须**走完整 R12（§三·3 的金标烘烤 + 留出种子 + rebake_history）。本纵切**刻意停在这条线的 View 一侧**，这正是它能与别的波并行的根据（§五）。

---

## 四、视觉回归门设计——**照 docs/122/86 的 §2.5 三行包络规格，扩多楼层，不另立真源**

守的性质一句话：**"多楼层纵切"里，2f 必须真被看见、楼梯往返必须逐像素稳、外面看到的型别必须和进门后的一致。**

### 4.1 门 G1 · 多楼层往返（扩 `assert_space_roundtrip.py`，**不重写**）

复用 SpaceShot 的 portal 驱动路径（出货路径 `tapped`→`_portal_click`）与 `assert_daynight._png_rgb_rows`（同一份 PNG 解码器，红线#5 复用优先，两份必漂）+ 现役 `ciede2000.py`。采集序列：**town_before → cafe_1f → cafe_2f → cafe_1f_back → town_after**（5 帧）。

- **A 臂（往返不变式）**：`town_after` ≡ `town_before` **且** `cafe_1f_back` ≡ `cafe_1f`（下楼回到的那层），在地图矩形+界外带上逐像素相同（世界冻结 `auto_run=false`；取景由 `go_home()`/楼梯往返复位）。**A 单独会空过**（docs/41 §6-★），故必配 B/C。
- **B 臂（楼层可分——判别力，新增的那条）**：`cafe_2f` 与 `cafe_1f` 主色/内容必须**大不相同**（2f=床/书桌 vs 1f=吧台/桌椅，是两张真不同的布局）。判据：地图矩形内 %变化像素 ≥ 阈值（或采样带 ΔE00 ≥ 阈值）。**这条挡的是"楼梯往返其实没换层/两层画成一样"的空过。**
- **C 臂（真的走了一趟）**：`cafe_1f` 与 `town_before` %变化像素 ≥ `MIN_INTERIOR_DIFF`（现役 0.20，`assert_space_roundtrip.py`）——沿用，证明采集没有"压根没进店"。

**阈值=实测，不是拍的**（照 docs/122 §四、`assert_space_roundtrip.py` 抬头）：在**未改动的树**上、同机同 docker 镜像、seed3 warmup-tick 昼/夜各拍一遍，量 2f-vs-1f 的真实 %diff 与 1f 往返的真实残差，阈值取**两侧各留约 3× 余量**（不贴任一侧实测值——贴修复侧下次美术改动假红，贴回滚侧漏轻回归）。

**§2.5 三行包络（形状照 docs/122 §四；数字待实现波在真跑环境量出后填）**：
```
detects:      ① 回滚 P-A（暂停点门不刷新）：LT_RT_REDRAW=none 拍到的 cafe_2f 是"停在镇上"的帧 ⇒ B 臂红（2f 与 town 反而相同 / 与 1f 不可分）
              ② 楼层往返没真上楼（楼梯 portal 断）⇒ B 臂红（cafe_2f ≈ cafe_1f）
              ③ 1f 往返被污染（下楼取景没复位）⇒ A 臂红（cafe_1f_back ≠ cafe_1f）
              ④ 少拍一帧 / 帧尺寸非 1280×768 整数倍 ⇒ C 臂（几何自检）拒判 exit≠0
does_not_detect: 颜色对不对一概不管（关系判据，色值真源留在 WorldView.gd 不抄进判据）；只看 cafe 一栋（其余楼层的 2f 不存在，不测）；
              只看昼/夜两个 tick、晴天（天气罩会拉近，判据自己不验天气——照 docs/122 §一开头那个坑）；
              软渲染 docker、非真机；只看地图矩形+界外带取样条，不看逐件家具。
confidence:   N=? 变异体全红（①②③④ 逐条跑完核退出码）；does_not_detect 逐条从关系判据结构直接读出，非臆测。
              端到端：先在【未改动的树】上跑一遍——A/C 应绿、B 是**新增**的判别力（未改动树上 2f 本就≠1f ⇒ B 该绿）。
```
**负对照（判据没过这关就不是判据）**：照 `space_roundtrip.sh` 已有的 `LT_RT_GAME` 逃生门——把 `game/` 拷进 scratchpad、
在拷贝上回滚 P-A（或把 2f 家具清空成和 1f 一样），指过去，**G1 必须变红**。

⚠️ **三条工具链纪律必须写进门**（docs/41 §6）：
① **`getbbox()` 陷阱**：逐像素比先 `convert("RGB")`（美术全不透明，RGBA 上 `getbbox` 恒空真）——沿用 `assert_space_roundtrip.py` 已有的 stdlib 读取器就绕开了。
② **"计数器≠像素"**：G1 量**像素**，与 `--void-gate` 量**计数器**（`_void_draws`）是两层证据（docs/46 §二·九、`SpaceShot.gd:12-19`）——不可用 draw 计数替代。
③ **别写死绝对帧数/次数**：机器快慢会让写死的次数在别的机器变红（docs/41 §2.5 那条 `_void_draws==0` 的教训）。G1 只用"%diff/ΔE00 过线"这种对机器速度不敏感的判据 + SpaceShot 已有的"数够帧 **且** 够毫秒"双条件暖机（`SpaceShot.gd:257-263`）+ 180s 看门狗（`:75-82`，防"挂住而不变红"）。

### 4.2 门 G2 · 外立面↔室内型别一致（P-C，可选、纯 B 臂）

关系判据：对 cafe 街区每栋楼，断言"`_draw_facades` 用的 `BLD_PAL[areas[type]]`"与"`_interior_shell` 用的 `FLOOR_PAL/BLD_PAL[areas[type]]`"**读的是同一个 type**。今天同源 ⇒ 未改动树上恒绿；它守的是**将来两处分叉**。低价值密度，列为可选。

### 4.3 接进 CI（本设计不碰 tools/，接线留实现波）

G1 扩在 `visual_gate.sh` 已有的 Xvfb 里（多拍 cafe 2f 一帧 + SpaceShot 加楼梯腿），`ci.sh` 第 6 步门数 +1，rc 段照 `visual_gate.sh:239-263` 的分档风格新增一个码。**照 docs/122 §四那条 V3 教训**：新门第一次接 CI 常红在 `✅` 的 GBK 编码上——判据抬头先 `sys.stdout.reconfigure(encoding="utf-8", errors="replace")`。

---

## 五、分阶段 + 风险 + 接口冻结

### 5.1 分阶段（每阶段的 R12 归属写明；**碰金标就停**）

| 阶段 | 做什么 | R12/金标 | 出口判据 |
|---|---|---|---|
| **P0 · 设计+评审** | 本文 + 过 §0.8 外部对抗评审（Codex repo session 真读代码 + 本文档独立评审）。**动手前**。 | 无 | 用户拍板下一波实现 |
| **P1 · P-A（view-only 修 + 立证）** | `_portal_click` 补 `queue_redraw`；**逐字节 digest A/B**（`Harness --chain-dump` 改前/改后 + 留出种子 31-36）+ P-D 扩 `probe_digest_test`（加换层/换空间注入）。 | **应零金标移动**。若 digest 动了 ⇒ **停下报告**（说明"修法碰到了 Sim"，回滚）——不重烘（docs/41 §3）。 | 两跑逐字节相同；暂停点门真刷新（眼验一帧） |
| **P2 · P-B（多楼层视觉门）** | 2f 采集 + 楼梯往返 + G1 判据 + 三行包络 + `LT_RT_GAME` 负对照；先在未改动树跑（B 应有判别力）。 | 无（纯 tools/bench，不碰 Sim） | G1 未改动树 PASS、负对照 FAIL、包络三行填数 |
| **P3 · P-C + P-E** | 型别一致门（可选）；纠 `spaces.json` 注释；落接口冻结清单。 | 无 | lint/CI 绿 |

⚠️ **P1 的 digest A/B 是【出口门】不是事后诸葛**：docs/41 §2 三个结构盲区之一是"金标全绿≠改动被验证"——P-A 走 View，金标网格 `backend=null` 本就不覆盖 view 层，所以**必须自造对照**（chain-dump A/B），不能拿"金标没红"当证据。

### 5.2 风险（照实列，不装作想清楚了）

1. **P-A 被误写成碰 Sim**：一行 `queue_redraw` 若手滑写成动了 `Sim.*` 就破 R1。**缓释**：P1 出口门=逐字节 digest A/B，红即停。
2. **软渲染 5-10 fps（docs/41 §6⑧）**：G1 加 2 帧 ⇒ 采集更长；`--headless` 拿空图。**缓释**：SpaceShot 已有双条件暖机 + 180s 看门狗（rc=1 不挂住）；`visual_gate.sh` 已有 `GITHUB_ACTIONS` 显式跳过（GL 栈没 pin）。
3. **2f 只 cafe 独有**：G1 若对别栋楼也拍 `--probe-floor 2f` 会拿到占位/空图假红。**缓释**：楼层门**只 scope cafe**（其余楼层门仍 1f）。
4. **机器速度/getbbox/计数器三坑**：见 §四三条纪律。**缓释**：判据只用 %diff/ΔE00 + convert RGB + 量像素不量计数器 + 无写死帧数。
5. **与并行波的语义漂移（Codex §三.3：文件级 owns 只减文本冲突、不证语义正交）**：AG1（半宏观生产，编号 124 那份设计）与 AF1（state_projection，docs/121 若在树上）都改 `Sim.gd`。若它们改 agent 状态布局或 `_area_key` 平面感知，**本纵切消费的 Tier-B（`agent.space/floor/area`）会静默失配**。**缓释**：§5.3 冻结 schema 面 + 本纵切**只碰 Main.gd 一行**（P-A），而 `Main.gd`/`Sim.gd` 是高冲突面（docs/113 §三），**同一时刻只能一根波碰**——P-A 那一行必须与写 Sim.gd 的波错开落地。
6. **纵切的 does_not_detect 面**（G1 抓不到的）：只 cafe、只昼/夜两 tick、只晴天、软渲染、非真机、不看逐件家具——照实记入包络，不用推断填空。

### 5.3 接口冻结建议（**让 semi-macro / state_projection 波能并行不漂**）

本纵切**消费**下列 schema，建议在实现波开工前把它们标为"冻结面"（改它=跨波协调，不是单波私事）：

| 冻结面 | 形状（真源） | 谁消费 |
|---|---|---|
| Space/Floor 记录 | `spaces.json` `{kind,label,bounds:[x,y,w,h],floors:[],default_floor}` | WorldView 绘制、Probe 取景、SpaceGraph |
| Portal 记录 | `{id,kind,from/to:{space,floor,pos},bidirectional,access,traversal_cost}` | `_portal_click`、SpaceShot、SpaceGraph、Sim 路由 |
| agent 平面地址 | `agent.spatial_address{space_id,floor_id,position,room_id}` + 派生 `agent.space/floor/area/room` | **Sim（仿真态，金标）** + WorldView 画在场居民 |
| 建筑型别 | `map.json areas[].type`（residential/commercial/public/workshop/plaza） | 外立面 `BLD_PAL` + 室内 `_interior_shell` + 家具 `_furniture_role` |
| SpaceGraph 读 API | `bounds_px/portals_from/address_of/floors_of/default_floor/label_of/has_space/has_floor` | Main/Probe/WorldView/SpaceShot |

**明写纵切消费什么、不消费什么**：消费上表；**不消费也不产出**事件/关系/信念/决策候选那套（社会决策 schema）——
这就是它能和 AG1（产业到达过程）/AF1（state_projection）并行的关键：**文件级 owns 错开**（WorldView/ProbeController/bench/SpaceShot/tools + Main 一行 + spaces/interiors 注释）**且语义上只碰 View + 上表的读侧**，不碰 Sim 的写侧（除 P-A 那一行 View 调度）。

---

## 六、这份 brief 哪里是错的（docs/41 §4，最有价值的一节）

1. **brief 把这一轨写成"做完整：外立面→…→视觉回归"，读起来像绿地实现任务——证伪。** 六段全在 trunk（§一·1.2），cafe 已是精修两层样板。正确的任务不是"实现纵切"，是"**收口那一个真 bug + 补那几道缺失的门 + 纠正腐烂注释**"。这是 docs/51 H1/S3 教训的反向发作（同 docs/122 §六·1）：**"以为要从头做，其实九成已在"**。
2. **`spaces.json` cafe `_note` 与 Sim 实况自相矛盾（会把 R1 边界带偏）——本棒纠正。** 注释写"Tier-A：只 Probe inspect，**居民不进**、digest 逐字节不变"，而 `agents.json` 里 **aria 住 cafe/2f**、`Sim.gd` 的 Tier-B 让她按 portal 真走动（§三·3.2）。**这是本 session 又一次"坐标腐烂"**：那句注释描述的是一个翻过篇的阶段，照它设计会把"agent 平面地址=仿真态"误当"纯观察态"。brief 转述这套时也隐含了旧口径（§三 是纠正）。
3. **brief 让我"照 assert_daynight.py/树丛门的规格设计一道视觉门"——口径需更新**：空间往返视觉门（`assert_space_roundtrip.py`）+ 室内外壳门 + 家具语义门**已经在 `visual_gate.sh` 里跑着**。本设计不是"新设计一道门"，是"**把已有的门从 1f 扩到多楼层**"（§四）。
4. **brief 的坐标提示本身没腐烂**（区别于 AG1 那份 §三·58 记的 ~110 行漂移）：它只给文件名 + grep 词（WorldView.gd/portal/floor/camera/drag），我实读全部命中，无行号漂移。**brief 该表扬的一点**：它明写"坐标本 session 常腐烂，你实读为准"——本节正是照办的产物。

---

## 七、我没测到什么 / 证伪掉的自己的假设 / 留给实现波

### 明写没测到的（不用推断填空，docs/41 §4）
- **没跑任何 CI / 视觉门 / 真机**：本棒只读设计。§一的现状是**静态读码 + 数据核对**得出，未在真跑环境验证过一帧。G1 的实测阈值、包络里的 `N=?`，**必须由实现波在 docker Xvfb 里量出来填**——本设计只给形状与纪律，不给编造的数字（docs/41 §5：数字要有零假设 + 校准点才可解读）。
- **没确认 P-A 修完是否真的零金标**：§三推断它 view-only（`queue_redraw` 不碰 Sim），但**推断≠实测**——P1 的 chain-dump A/B 才是判决。
- **没测 `probe_digest_test` 加了换层/换空间注入后是否仍绿**：§二·P-D 是设计，实测留 P1。理论上 view-only 该绿；若红=发现了一条"换空间偷偷写了 Sim"的真 bug（那就是收获，不是失败）。
- **没量 cafe 2f 与 1f 的真实 %diff / ΔE00**：G1 的 B 臂阈值待实测（§四·4.1）。

### 证伪掉的自己的假设
- 开工假设"纵切要从外立面开始一路实现"——读码后证伪（九成已在）。
- 一度假设"cafe 是 Tier-A、居民不进"（照 `spaces.json` 注释）——被 `agents.json`（aria@cafe/2f）+ `Sim.gd` 路由证伪。

### 留给实现波
1. **P1 先行**（最高价值、最小面）：一行 `queue_redraw` + 它的逐字节证明 + P-D 的门。它把"暂停点门看室内"这个**核心交互**从坏修成好。
2. **P2 的 G1** 是第二优先：它让"多楼层"这四个字第一次有门守着（今天 2f 从没被任何门看过）。
3. **P-E 的注释纠正**建议单独一个小 commit（数据/注释，别混进 View 改动，免得污染 P1 的 digest A/B 边界）。
4. **§0.8**：本设计动手前应过外部对抗评审（Codex repo session 能真读 `Sim.gd` 的 Tier-B 路由 + 跑 chain-dump 验 P-A 的 view-only 断言）。

## 附 · 证据清单（file:line，均本基线 `091411c` 实读）

| 断言 | 证据 |
|---|---|
| 外立面按型别上色 | `WorldView.gd:1014-1050`（`_draw_facades`）、`:1026`（`BLD_PAL[type]`） |
| 室内布局绘制 + R2 外壳 | `WorldView.gd:1310-1359`（`_draw_interior`）、`:1412-1431`（`_interior_shell`）、`interiors.json`（cafe 1f/2f 手工） |
| 多楼层 portal | `spaces.json`（p_cafe_door / p_cafe_stairs）、`SpaceGraph.gd:71-83`、`Main.gd:2439-2467`（`_portal_click`）、`:2427`（`_probe_cycle_floor`） |
| 相机/拖拽/缩放 view-only + 硬门 | `ProbeController.gd:2-8,137,245-292`、`tools/probe_digest_test.sh`（拖+缩→逐字节 digest） |
| 返回世界坐标 | `Main.gd:2456-2457`（`go_home`）、`ProbeController.gd:151`（`go_back`）、`SpaceShot.gd:130`（cam_same） |
| 视觉回归已有（只到 1f） | `game/bench/SpaceShot.gd`、`tools/space_roundtrip.sh`、`tools/assert_space_roundtrip.py`、`tools/visual_gate.sh:136-164`（`--probe-floor 1f` 写死 :161） |
| 暂停点门不刷新（真 bug 未修） | `Main.gd:2439-2467`（`_portal_click` 无 `queue_redraw`）、`WorldView.gd:558-559`（重画只挂 Sim 信号）、`SpaceShot.gd:149-164`（复现记录） |
| agent 平面地址=仿真态（Tier-B） | `agents.json`（aria→cafe/2f）、`Sim.gd:896-939,1630,1633-1650,4067`（journey/route/平面过滤候选） |
| P-A 修法有现成同型样板 | `Main.gd:2047`（`dbg_nav` 补 `_view.queue_redraw()`）、`WorldView.gd:609`（注释点名它不在 signal 之列） |
