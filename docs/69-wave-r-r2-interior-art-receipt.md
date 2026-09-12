# 69 · Wave R · R2 回执——**室内不是"没有贴图"，是"七栋楼共用一张写死的住宅皮"**

> 依据：docs/41 全文（§0.5 / §0.8 / §1.5 / **§2.5 探测包络** / §6 视觉条款）、docs/43 §二-R2（素材红线）、
> docs/67 §二（本棒 brief）、docs/51（H1 的美术眼验，"先确认你量的是哪个对象"）。
> **owns 之内**：`game/scripts/WorldView.gd`、`tools/ci.sh`、`tools/visual_gate.sh`、`tools/assert_interior_shell.py`（新）、`docs/media/r2_*`。
> **一个字节都没碰**：`game/scripts/Sim.gd`、`game/data/**`（含 `interiors.json`）、`game/bench/**`、`game/assets/**`、`docs/README.md`。

## 〇、一句话结论

**改前七栋楼、八个楼层的室内墙是【同一条写死的配方】，八个楼层两两 ΔE = 0.00，一对都分不开。**
而同一批楼的**外墙**早就按 `map.json areas[].type` 分成四类上色了（`BLD_PAL`，`_wall_type` 一直在用）。
⇒ 病不是"室内缺美术"，是**室内把外面已经有的那套建筑类型信息整个丢掉了**：
澡堂/图书馆在外面是灰蓝石墙、工坊是暖灰石墙，**一进门全部变成住宅的暖木墙**。

修法因此不是画新素材，是**把外面那套接进来**（红线#5 复用优先）：
`_interior_shell()` 从 `areas[].type` 取 `BLD_PAL` / `FLOOR_PAL`。**零新素材、零数据改动、仿真侧逐字节不变。**

### 仿真侧不变的证据（两条独立的，不是"声称"）

1. **自造 A/B**：改前先跑 `Harness --seeds 1-6 --days 20` 记下三个见证
   （`digest` / `event_digest` / 逐 tick `chain`），改后同一条命令重跑 ⇒ **6/6 三个见证逐字节全同**。
2. **金标**（更强，因为它烘在我动手之前）：`bash tools/ci.sh` 的 S0 门
   `seeds=1-12 days=60` ⇒ **金标一致 12/12 seed，含逐 tick 前缀链 12 条**；40 条不变量 12/12 全绿。
   ⇒ 一个**我没有参与烘焙**的基准在我改完之后仍然逐字节对得上。

**机制上为什么必然如此**：本棒只读 `Sim.world.areas[*].type`，而 `Sim` 侧**从不读**这个字段
（只读 `rect` 与 `label`；F5 的 `dock` 注释已记过这条）。没有改任何 `game/data/**`，
特别是**没有碰 `interiors.json`**——那个文件是有仿真副作用的，见 §四·2。

> ⚠️ **brief 说"进七栋楼各截一张图，逐栋列出地板/墙/家具各用了哪些贴图"——这个问法在本仓库不可满足。**
> **室内路径上的贴图数是 0。** 见 §四·1。这正是 docs/51 那条教训（"先确认你量的是哪个对象"）在本棒的复发点，
> 只是方向反过来了：H1 量的是"一张 sheet 服务 5 个对象"，本棒差点去量一个**根本不存在的贴图集合**。

---

## 一、改前逐栋清点表（**实测，不是读代码推的**）

采集：真引擎（`gamecraft-runner:4.6.2` + Xvfb + opengl3 软渲染），
`--probe-space <sid> --probe-floor <fid> --shot-fit --shot`，seed 20260626、`--warmup-tick 600`（第 3 天 12:00 正午）。
八张 1280×768 全在 `docs/media/r2_interior_before_8.png`。

### 1.1 家具与外壳（数据侧，`interiors.json` + `spaces.json` + `map.json`）

| space | 楼层 | 标签 | `areas[].type` | 尺寸(格) | 地板材质 | 家具 slot |
|---|---|---|---|---|---|---|
| `cafe` | 1f | 阿丽的咖啡馆 | commercial | 8×6 | wood | chair×2 coffee counter plant rug shelf stairs table×2 |
| `cafe` | 2f | 阿丽的居所 | commercial | 8×6 | wood | bed desk plant rug shelf stairs window |
| `home` | 1f | 住宅区 | residential | 9×7 | wood | bed×2 chair plant rug shelf table |
| `home2` | 1f | 民居 | residential | 6×5 | wood | bed chair rug shelf table |
| `wash` | 1f | 澡堂 | public | 9×7 | stone | bath bench×2 plant rug shelf |
| `work` | 1f | 工坊 | workshop | 9×7 | stone | crate×2 desk rug shelf stool |
| `shop` | 1f | 杂货铺 | commercial | 7×6 | wood | counter crate×2 rug shelf×2 |
| `library` | 1f | 图书馆 | public | 7×6 | stone | desk plant shelf×3 stool |

**合计 7 栋 / 8 个楼层 / 53 件家具 / 15 种 slot。**

### 1.2 "各用了哪些贴图" —— **0 张**

`_draw_space_placeholder → _draw_interior → _draw_interior_furniture` 这条路径上
**`Art.*_tex()` 的调用数是 0**（实测 `grep`，见 §四·1）。地板、墙、全部 15 种家具**都是
`draw_rect`/`draw_circle` 程序化画的**。室内画面里唯一的贴图是**居民精灵**（`_draw_agent → Art.agent_tex`）。
⇒ 本棒的清点对象因此是**程序化画法**，不是贴图文件。

### 1.3 别名率（**这一栏才是 H1 那条教训真正对应的东西**）

| 被复用的东西 | 一份画法服务几个对象 | 覆盖 |
|---|---|---|
| **室内墙 `_interior_wall()`** | **8 / 8 个楼层**（唯一一份配方，墙主面写死 `P_RES_FOOT`） | **100%** |
| 地板 | 2 份配方（wood / stone）服务 8 个楼层 | — |
| **家具 `shelf`** | **11 个实例，分布在 8/8 个楼层**，全部画成"带三色书脊的书架" | **100%** |
| 家具 `rug` | 7 实例 / 7 层 | — |
| 家具 `plant` | 5 实例 / 5 层 | — |

**复制品对数（改前）**：
- **墙**：`C(8,2) = 28` 对**全部**是逐像素相同的配方 ⇒ **28/28**。
- **外壳（墙+地板）**：wood 5 层 `C(5,2)=10` + stone 3 层 `C(3,2)=3` = **13/28 对外壳配方完全相同**。

### 1.4 像素侧的复核（不只是读代码）

从八张真引擎帧里量墙主面的众数色：

```
cafe_2f  #836a48   home2_1f #836a48   wash_1f #836a48
work_1f  #836a48   shop_1f  #836a48   library_1f #836a48
cafe_1f  #866c49 ← 屋里有人           home_1f  #886d49 ← 屋里有人
```
后两栋的偏差**不是**另一种墙：是 `_draw_interior_night()` 的**占用暖光**——屋里有人时整层压一层
`X_GLOW_DEEP` α≈0.02（`lit = min(0.12, occ*0.04)·0.5 > 0.001`，**正午也画**）。
逐通道 ≤ (5,3,1)/255，**ΔE(CIE76) 0.88–1.98**。⇒ 八个楼层的墙实际上是同一个值。

> **这条噪声后来变成了新门阈值的定标点**，见 §三。它也是一条**不能靠"拍正午"绕开**的噪声——
> 我一开始以为可以，量完才发现 `lit` 的占用项与昼夜无关。

---

## 二、改了什么

**只改了 `game/scripts/WorldView.gd` 一个文件的绘制层。**

1. 新增 `_interior_shell(sid, floor_mode)`：从 `Sim.world.areas[sid].type` 取建筑类型，
   返回 `{wall, wall_top, wall_foot, floor, floor_line, checker, slab}`。
   - 墙主面 = `BLD_PAL[typ]["foot"]`；顶棱/墙脚沿用原来的 `lightened(0.20)` / `darkened(0.28)` 派生式。
   - 地板 = `FLOOR_PAL[typ]` 的 `base`/`line`；石板亮格 = `base.lightened(0.18)`。
   - 认不出的 type → 退回 `residential`（= 改前行为），**不是**退回 `workshop`。
2. `_interior_wall(sg, …)` → `_interior_wall(shell, …)`。
   **原来的第一个参数 `sg` 函数体里一次都没用过**——那个没人用的参数正好是这道缺口的形状。
3. 删掉三个因此归零的常量：`D_INT_WALL_TOP` / `D_INT_WALL_FOOT` / `P_KERB`（派生式搬进 `_interior_shell`）。
   `P_KERB` 的注释还写着 D6 的"此前代码零使用，本棒启用"——本棒把它唯一那处用掉的地方拿走了，故一并删。

**为什么墙取 `foot` 而不是 `face`（实测理由，不是审美）**：`P_RES_FACE #c2a071` 与住宅木地板 `#c8a273`
逐通道只差 6/6/2，拿它当墙会让住宅的墙和地板糊成一块；而 `foot` 档**恰好等于改前写死的那个值**
⇒ **住宅两栋（home / home2）逐像素不变**，其余三类各自跟着自己的族走。

**`mode`(plank/slab) 仍取 `interiors.json` 的 `floor` 字段**，不从 `FLOOR_PAL.mode` 取——两处都有 mode 必然漂。
实测这 8 层的 authored `floor` 与 `FLOOR_PAL[typ].mode` **逐条一致**（wood↔plank 5 条、stone↔slab 3 条），
今天两种取法等价；写成 authored 优先，是为了将来有人蓄意写一间"石头地的住宅"时不被静默覆盖。

### 前后对照（同一栋、同一机位、同一 tick）

`docs/media/r2_interior_ba_4types.png`（四类各一栋，左改前 / 右改后）、
`r2_interior_before_8.png` / `r2_interior_after_8.png`（八层全景）。

**逐像素 diff（`ImageChops.difference(a.convert("RGB"), b.convert("RGB")).getbbox()`
——照 docs/41 §6 的 `getbbox()` 陷阱写法，不是裸 `getbbox()`）**：

| 楼层 | type | bbox | 变化像素 |
|---|---|---|---|
| `home_1f` | residential | **None** | **0** |
| `home2_1f` | residential | **None** | **0** |
| `cafe_1f` | commercial | (288,120,992,648) | 343 218 |
| `cafe_2f` | commercial | (288,120,992,648) | 352 424 |
| `wash_1f` | public | (301,120,979,648) | 343 687 |
| `work_1f` | workshop | (301,120,979,648) | 248 238 |
| `shop_1f` | commercial | (332,120,948,648) | 299 008 |
| `library_1f` | public | (332,120,948,648) | 298 965 |

两条都要读：**住宅 bbox=None** 兑现了上面那句"逐像素不变"；
其余六层的 bbox **全部落在房间矩形之内**（HUD、背板、界外层一个像素没动）。
八张 `im.size` 全是 `(1280, 768)`（docs/41 §6 盲区③：画幅问题只体现在尺寸上）。

### 改后四类墙主面的两两可分度

| | commercial | public | residential | workshop |
|---|---|---|---|---|
| **commercial** `#5a4028` | — | 29.50 | 17.72 | 18.28 |
| **public** `#556169` | | — | 30.54 | 15.43 |
| **residential** `#836a48` | | | — | 27.71 |
| **workshop** `#44423e` | | | | — |

ΔE(CIE76)，最小 **15.43**（public↔workshop）。**改前这张表全是 0.00。**

---

## 三、新门：室内外壳类型门（`tools/assert_interior_shell.py`）

守的性质一句话：**进屋之后，这栋楼还得是这栋楼。**
采集接在 `tools/visual_gate.sh` 已有的那个 Xvfb 上（多拍 5 帧，不另起容器），
判据在宿主侧跑。`tools/ci.sh` 第 6 步随之从"三道门"更正为**五道**（§四·4）。

**两条臂**：
- **A（异类必须分开）**：`areas[].type` 不同的两栋，墙主面众数色 ΔE ≥ **8.0**。
- **B（同类必须相同）**：type 相同的两栋，ΔE ≤ **4.0**。

B 臂不是凑数：它挡的是"**干脆给每栋楼各挑一个色**"这种 A 臂照样能过的假修法。
**为此必须拍第五栋**（`library`，与 `wash` 同为 public）——只拍四栋（四类各一）时 B 臂根本没有可比的对子。

**阈值是量出来的**：异类实测最小 15.43、最大 30.54；同类内唯一噪声源是占用暖光的 ΔE 0.88–1.98（§一·4）。
8.0 / 4.0 两侧各有约 2 倍余量，都不贴边。

### §2.5 探测包络

```
detects:
  ① 改前那棵树（墙写死住宅色）⇒ 红：10 对里 9 对异类全部越界（ΔE 0.00–1.98 < 8.0），exit 1。
     ——这一条同时就是 docs/41 §6★ 要求的"先在未改动的树上跑一遍"：它在那里【是红的】，故有判别力。
  ② 假修法「按 space id 各挑一个调色板」（隔离副本 ng_game，改 _interior_shell 一行）⇒ 红 5 条，exit 1。
     其中 B 臂那条是结构性的：`library(public) vs wash(public) ΔE=30.54 > 4.00`。
     ⚠️ 同一次里的 4 条 A 臂失败是 **hash 撞车的巧合**（cafe/wash/work 恰好落到同一档），不算独立证据。
  ③ 把 library 的墙主面整片改成一个谁都没用的颜色（`#556169`→`#6b4a78`，78 301 px，fixture 级）
     ⇒ **恰好红 1 条，且正是 B 臂那条**；其余 9 对全 ok。这一条把 B 臂单独隔离出来了。
  ④ 采样几何自检（**跑过，不是写在那儿好看**）：把一张帧换成 160×96 的小图模拟"取景公式算错"
     ⇒ `vg_int_home.png：墙面采样点只有 0 个（<2000）`，exit 1。
     防的是最难看的那种失效：**几何算错 ⇒ 众数色无意义 ⇒ 门照常全绿**。

does_not_detect:（逐条都是跑出来的或从代码结构直接读出来的，不是想出来的）
  · **颜色对不对，它一概不管。** 它是【关系判据】不是【取值判据】：把四类的色值整体换成四种荧光色，
    A/B 两臂照样全绿。**没做成取值判据是蓄意的**——BLD_PAL 的真源在 WorldView.gd，
    把色值抄进判据文件等于给同一份真相立第二个副本，本仓库已经因为这种抄写吃过亏。
  · **只看墙。** 地板、家具、夜光一条都不在判据里。实测：把 `_interior_shell` 的 `floor`/`floor_line`
    全部改回写死的住宅木地板（隔离副本），**本门 10/10 全绿、exit 0** —— 地板整个塌回改前它一声不吭。
  · **只看被拍到的那五栋。** `shop` / `home2` / `cafe/2f` 不在 `INT_SPACES` 里 ⇒ 它们单独回归，门不响。
  · **只看正午、单 seed(3)、logic 地板、无玩家。** 夜间乘色下的可分度**没测**（docs/41 §6 盲区④ 的方向）。
  · **只看 1f。** `--probe-floor` 写死 `1f`，`cafe/2f` 结构上进不了这道门。
  · 不保证屏幕上"好看"，也不保证家具语义对（§五 那条 `shelf` 的病它完全看不见）。

confidence: N=5（5 个变异体，**每一个都亲眼看着跑完并核过退出码**）：
            4 红 —— ① 改前的树 ② 按 space id 挑色 ③ fixture 级单栋改色 ④ 采样几何算错；
            1 绿 —— ⑤ 地板整个塌回住宅木地板（`#96a5ab`→`#c8a273`，肉眼一眼看穿）**门 10/10 全绿、exit 0**。
            ⑤ 不是失败，是**这道门边界的实测坐标**：它列在 does_not_detect 第 2 条，
            而我原本只是"想当然"写下那一条——跑完才敢说它是真的。
```

**措辞**：本门**阻断了一类已观测的失效模式**（室内外壳不再跟着建筑类型走），
**不是**"补上了室内美术缺失的保护"——它连地板都不看。

---

## 四、这份 brief（和相邻文档）哪里是错的

### 1. **"逐栋列出地板/墙/家具各用了哪些贴图、有几种"——不可满足：室内贴图数是 0**

```
$ sed -n '1189,1330p' game/scripts/WorldView.gd | grep -n "_tex\|Texture"
（无输出）
```
`_draw_interior` / `_draw_interior_furniture` / `_interior_wall` / `_draw_interior_night` 四个函数里
**没有任何一次纹理调用**。室内的地板/墙/15 种家具全部是 `draw_rect`/`draw_circle`。
⇒ 同一句 brief 里的 **"故意抽掉一张贴图，门必须红"这个负对照在本棒【结构上不可执行】**：
室内没有任何一张贴图可抽，抽掉 `game/assets/art/**` 的任何一张，室内画面**逐像素不变**。
我用 §三 那四个变异体替代，其中 ①（改前的树）是最强的一个。

### 2. **`interiors.json` 不是"纯渲染"——它自己的 `_note` 是过期的，而 brief 沿用了它**

`interiors.json:2` 写着"纯渲染 / Probe inspect-only（Tier-A）：**不进 Sim 仿真**…→ digest 逐字节不变"。
**假的。** `Sim.gd` 读它，而且是两条路：
- `Sim.gd:646 _compile_interiors()`：把**带 `advertises`** 的家具编译成 world 对象，
  **`id` 里就含 slot 字符串**（`oid = space+floor+slot`）；
- `Sim.gd:3653 _build_interior_grids()`：`const WALKABLE_SLOTS := ["stairs","rug","window"]`
  ——**slot 字符串直接决定那一格能不能走**。

⇒ **"改 `interiors.json` 的 slot 名"是一个会移动 digest 的动作**（把某个 slot 改进/改出 `WALKABLE_SLOTS`
就改了导航网 ⇒ 改了寻路 ⇒ 改了轨迹）。brief 把 R2 描述成纯表现层的棒，
**照它的字面去改 `interiors.json` 会踩进这个坑而毫无警告**。
**本棒因此一个字节都没改 `interiors.json`**——`_interior_shell` 走的是 `map.json areas[].type`，
而 `Sim` 侧**从不读** `areas[*].type`（只读 `rect` 与 `label`；F5 的 `dock` 注释已记过这条）。

### 3. **docs/67 §一-② 说 docs/58 与 docs/13 "互相矛盾，请你去代码里判"——【两边都是对的，因为吧台有两个】**

这条不在我的行里（`jobs.json` 归 R1），但答案的另一半在我的文件里，所以我把它查清楚交出去。
docs/67 的原文是："docs/58 说 `counter_1` 也没有 `staff` 标志，**但 docs/13:830 写着"阿丽的吧台标 `staff:true`"
——这两条互相矛盾，请你去代码里判，别采信任何一边**。"

**它们不矛盾。镇上有两件吧台，分在两个平面、两个文件里：**

| | 文件 | id | 平面 | `staff` | `advertises` |
|---|---|---|---|---|---|
| 街面吧台 | `map.json` objects | `counter_1` | town/outdoor，pos `[42,16]` | **无** | 闲聊 42 |
| 店内吧台 | `interiors.json` `cafe/1f` | `cafe1f_counter`（`_compile_interiors` 现造的 id） | cafe/1f | **`true`** | **看摊 30** + 闲聊 40 |

⇒ **docs/58:110（"`counter_1` 没有 `staff` 标志"）对**，它说的是街面那件；
**docs/13:830（"阿丽的吧台标 `staff:true`"）也对**，它说的是店内那件。
⚠️ 而且 docs/67 §一-② 说的 `jobs.json.extra_advertises` 注入的 `看摊` 是 **`amount:20`**，
`interiors.json` 里那条 `看摊` 是 **`amount:30`**——**两条不同的广告、两个不同的数、两件不同的家具。**
⇒ **R1 若按"只有一件吧台"去加岗位门，会量错对象**（这正是 docs/51 那条教训的第三次发作）。
`jobs.json` / `production.json` 一侧仍归 R1，我一个字节都没碰。

### 4. **`tools/ci.sh` 第 6 步的抬头写着"这一步现在有【三】道门"——实际早就是四道**

第四道是 G5 的岸线判据（`tools/pond.py`），它落地时没有回头改这段抬头。
我把它连同本棒的第五道一起更正为五。
**同一份文件里两处相反的说法，这是第二次**（上一次是 GHA 那段，2026-07-28 外部评审抓到）。

### 5. ~~docs/51 §四·7 的 `flower_white` 今天已经不成立~~ —— **这条是我写错的，我自己抓的，留在这里**

我本来在这一栏写的是：「实测 `decor/flower_white.png` **存在**（H2/G 波之后补上的），docs/51 那条已经过期」。
**假的。** 提交之前顺手 `ls` 了一下：

```
$ ls game/assets/art/decor/
bush.png  flower_red.png  flower_yellow.png  mushroom.png  rock.png  stump.png  tree_big.png  tree_small.png
```
**`flower_white.png` 不存在，docs/51 §四·7 当时是对的。**
它今天之所以不再是问题，是因为 **H3-c 已经修了**——`WorldView.gd:673` 的 `DECOR_POOL` 里那个死名字被删掉，
并补了一条 `verify_decor_pool()`（声明了却没有贴图 ⇒ `push_error`）。

⇒ **我把"缺口被补上了"和"缺口被修好了"讲反了，而这两件事的下一步完全相反**：
前者会让人去用那张并不存在的图，后者才是实况。docs/41 §1.5① 说的是"零调用点"要先跑 `git log -S`；
**这一次的教训是同族的更便宜版本——`ls` 一下再下结论。**
（我没动这一处，不在我的行里。）

### 6. 协调者中途来的三条更正，我照做了

`lint_links` 在基线上的红源是 `docs/67` 自己（已由 `1fbcc62` 修掉，我收尾前把 `integration/batons` 拉进来了）；
本文**不引用 R1 那份尚未落盘的编号文档**（`lint_links` 的检查 (2) 认纯文本 `docs/NN`、与文件在不在无关，
正是那三行"替你占号"把基线弄红的）；**也不引用 H4 / `tools/brief_mutate.py` / 它那个五十二号文号**（从未交付，R3 查证）。

> 顺带一条自证，比上面那句更值得记：**本文第一版自己就踩了这个雷。**
> 我在上一句里原样写出了那个编号（`docs/` 加数字的形状），`lint_links` 当场把我抓红，指名本文件那一行。
> 更难看的是**第二版**：我把失败信息原样引进来当教训，而引文里那个编号**又被同一条规则抓了一次**——
> 一行红变两行红。⇒ **这道门认的是【字符串形状】，不是【引用意图】**：讨论一个不存在的文号，
> 与引用它，在 `lint_links` 眼里完全一样。所以本文全程只能把它写成汉字。
> docs/67 那句"本 session 已经两次因为写死未来文档名把 `lint_links` 弄红了，别成为第三次"——
> 第三次是 docs/67 自己，我是第四和第五次。

---

## 五、我没做的 / 我证伪掉的自己的假设 / 留给下一棒

### 我一开始认定、后来被自己的数据推翻的

1. **"最差的那几栋是澡堂和工坊，因为它们的 `stone` 地板太素"** —— 错。
   量完发现**地板本来就分了两档，而墙一档都没分**：`stone`/`wood` 至少还跟着 authored 数据走，
   墙是 8/8 全同。**我差点去改那个已经分过档的东西。**
2. **"占用暖光只在夜里画，所以拍正午就能拿到干净的墙色"** —— 错。
   `lit = 0.20·night + min(0.12, occ·0.04)·(0.5+0.5·night)`，第二项**与 night 无关**，
   正午有人时 `lit = 0.02 > 0.001` 照画。这条错误直接决定了新门必须用**带余量的 ΔE 阈值**而不是逐字节相等。

### 明写没测到的（不用推断填空）

- **没测夜间**：新门与前后对照都只在正午（`--warmup-tick 600`）跑过。夜乘子下四类的可分度**没量**。
- **没测四季 / 天气**：只有春晴。
- **没在真机上验**：全部是 Docker 软渲染 1280×768。**没有出 APK、没有连 NX789J。**
- **没录像**：brief §二·4 提到可以出一段室内短片（`record-godot.sh`→`make_gif.sh`），**我没做**。
- **`cafe/2f` 与 `shop` / `home2` 不在新门的采集集合里**（理由与代价都写在 §三 的 `does_not_detect`）。
- **没碰 `game/assets/**` 一个字节** ⇒ docs/43 §二-R2 的素材红线（CC0 或自绘、生成图不得入库）
  在本棒**不适用**：本棒零新素材、零素材改动。

### 留给下一棒的两条（**都量过，都不是猜的**）

1. **`shelf` 是本仓库室内版的 `bench.png`**：**一份画法（三色书脊的书架）× 11 个实例 × 8/8 个楼层**。
   它在图书馆和阿丽卧室是**对的**，在**杂货铺（该是货架）、工坊（该是工具架）、澡堂（该是毛巾架）是错的**。
   ⇒ 这是 docs/51 §二·2 那条"一张贴图 = 五种物件"的**同形病**，只是载体从贴图换成了程序化分支。
   ⚠️ **修它有一个 brief 不会告诉你的约束**：正确的修法是给它们不同的 `slot`（`interiors.json` 自己的
   `_note` 就写着 slot 是"渲染前缀、决定程序化画法"），**而 slot 会进导航网与对象 id**（§四·2）。
   `shelf` 今天既无 `advertises`、也不在 `WALKABLE_SLOTS` 里 ⇒ 改名**应当**是 digest 中性的，
   **但必须实测证明，不能假设**。
2. **新门的两个已知缺口**（都在 §三 `does_not_detect` 里）：地板整个塌回住宅色它不响；`shop`/`home2`/`cafe 2f` 不在采集集合里。

## 六、CI（**读的是输出，不是退出码**）

`GODOT=C:/Users/yp/.local/bin/godot bash tools/ci.sh` 在**合并了 `integration/batons`（`1fbcc62`）之后**跑完整一遍：

```
=== CI PASS ✅ ===
```
逐步：0 版权红线 ✅ · 1 data lint ✅ · 1b map audit ✅ · 2 link lint ✅（76 篇 md / 67 篇编号文档）·
2b art gate ✅ · 2c terrain gate ✅ · 2d asset gate ✅ · 3 import/parse ✅ ·
**4 S0 门 ✅（40 条不变量 12/12 全绿、金标一致 12/12 含逐 tick 前缀链、det 3/3）** ·
4a 宏观池尺度门 ✅（N=16）· 4b LOD 观察无关 ✅（V2/V3a/V3b/V3c）· 4c DetGate ✅ ·
4d BackendGate ✅ · 4e ModelPathGate ✅ · 4f VoiceGate ✅ · 5 集成场景 8/8 ✅ ·
**6 视觉门 ✅（昼夜 / 界外层重画 / 空间往返 / 岸线 / 室内外壳）**。

本棒新门在 CI 内部真的跑了（不是我单独跑的那次）：

```
shot ok   vg_int_home.png / vg_int_cafe.png / vg_int_wash.png / vg_int_work.png / vg_int_library.png
[INTSHELL] cafe    type=commercial   墙主面众数=#5a4028  (12272/16224 采样点)
[INTSHELL] home    type=residential  墙主面众数=#866c49  (11616/14520 采样点)
[INTSHELL] library type=public       墙主面众数=#556169  (12168/16224 采样点)
[INTSHELL] wash    type=public       墙主面众数=#556169  (11616/14520 采样点)
[INTSHELL] work    type=workshop     墙主面众数=#44423e  (11616/14520 采样点)
[INTSHELL] ✅ 室内外壳类型门 PASS（5 栋 / 4 类，异类最小 ΔE ≥ 8.0、同类最大 ΔE ≤ 4.0）
```
> `home` 那行是 `#866c49` 而不是 `#836a48`：seed=3 时住宅里有人，占用暖光把墙推了 ≤3/255（§一·4）。
> **这正是阈值留余量的那条噪声，它在 CI 里真的出现了**——不是理论上的担心。

⚠️ **基线上 `lint_links` 本来是红的**（红源是 docs/67 自己替三根棒"占号"的三行纯文本 `docs/NN`），
协调者已在 `1fbcc62` 修掉。我**先合并再改 `ci.sh` 再跑最终 CI**（docs/41 §1.5②：
bash 按字节偏移读脚本，别在 CI 正跑的时候改它）。跑之前确认过没有任何进程在跑本 worktree 的 `ci.sh`；
**同时确认了另有 6 个 Godot 进程属于并行棒的其他 worktree —— 一个都没杀**（docs/41 §1 的并行期纪律）。

## 七、证据清单

| 文件 | 内容 |
|---|---|
| `docs/media/r2_interior_before_8.png` | 改前八个楼层全景（1280×768 各一，2×4 拼） |
| `docs/media/r2_interior_after_8.png` | 改后同上，同 seed / 同 tick / 同机位 |
| `docs/media/r2_interior_ba_4types.png` | 四类各一栋的 before\|after 并排（住宅那一行是"逐像素不变"的直观形态） |
