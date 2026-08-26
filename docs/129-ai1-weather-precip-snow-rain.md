# 129 · AI1 · 天气/季节降水视觉——**冬雪补齐 + 强化雨**，AF2 同款零金标

> 依据：docs/41（红线四条 / §2.5 探测包络 / §6 视觉条款）、docs/122（AF2 夜间光照+季节视觉，手法/包络/三证据规格照抄）。
>
> **基线**：worktree checkout 落后很多 commit（`38ba4a7`），`git merge-base --is-ancestor` 确认是祖先后
> ff 到 `integration/batons` = **`6b1b6d4`**。
>
> **owns 之内**：`game/scripts/WorldView.gd`（降水渲染）、`docs/media/ai1_*`、本文（编号129）。
> **声明的越界**：`analysis/ai1/`（新门 `assert_precip.py` + 端到端复现 `run_precip_gate.sh` + 包络原始输出 `envelope.txt`）——
>   理由见 §四·接线，与 AF2 的 `analysis/af2/`、V3 的 `analysis/v3/` 同形（新门先落 analysis/，接线留给合流的人）。
> **一个字节都没碰**：`Sim.gd`/`Main.gd`、`game/data/**`（含 `weather.json`/`lifecycle.json`）、`game/bench/**`、`tools/**`、`narrative/**`、`game/assets/**`（零新素材）。

## 〇、一句话结论

- **冬雪**：树上**确实没有落雪**（`grep 雪|snow` 全仓 0 命中，实测证）。但协调者"冬天**只有**冷色调"这半句**证伪**——
  冬天有 `SEASON_VEG["冬"]`(冷褪乘算) **+ `SEASON_WASH["冬"]` 霜白 α0.24（全季最强的一层 wash）**。缺的是**飘落的雪**（动），不是"冷色调"。
  before 真帧眼验：冬天读作"偏冷的绿镇"，**说不出"冬天"**——本棒补的正是那层落雪。
- **强化雨**：brief 已经提醒"别假设 rain 层是空的，先看它画什么"——**对**：`_draw_rain()` 早就在画雨丝（36% 密度、单档 1.5px 短丝）+ `WEATHER_WASH["雨"]` 蓝罩。
  实测**在、但偏淡**（before 帧眼验雨丝稀疏、几乎读不出下雨）。本棒把它做明显：两档景深雨丝（52%）+ 地面涟漪。
- **仿真侧逐字节不变**（三证据，digest 证）、**既有视觉门全绿且 CI 帧逐字节不变**、**新增一道降水可见门**（改前红/改后绿，含 §2.5 包络）。

---

## 一、改前清点（**给行号；都是 `6b1b6d4` 上的原始行**）

| 对象 | 原始行 | 画了什么（实读，不是声称） |
|---|---|---|
| `SEASON_VEG` | `:475-484` | 四季植被乘算色偏。`"冬": Color(0.84,0.92,1.00)`（冷、褪色）——**乘在草地/花草/树上** |
| `SEASON_WASH` | `:485-490` | 四季大气罩。**`"冬": Color(0.80,0.89,1.00,0.24)` 霜白，α 0.24 = 全季最强**（旧注："多亏了它，冬天才不是'绿得冷一点'"） |
| `WEATHER_WASH` | `:491-494` | `"阴" α0.16` / `"雨" α0.24`（蓝）。**晴无罩** |
| `_draw_climate_wash` | `:501-510` | 把 season wash + weather wash 画在**地图矩形 ∩ 视口**（界外暗林不变季）；居民之下 |
| `_draw_rain` | `:514-529` | **雨丝在**：cell=T×1.5，`_hash(gx,gy,57)`，36% 密度，单档 `draw_line` 短丝 1.5px，下落相位 `tick%6`。确定性（无 RNG） |
| 降水调度 | `:2649-2650` | `weather=="雨"` 时 `_draw_rain()` 画在**居民之上**（雨在人前面落） |
| **雪** | — | **全仓 0 处**（`grep -i snow|雪` 命中 0）。**冬天没有任何落雪** |
| `AUDIT_PASSES` | `:172` | 含 `"rain"` pass，**无 `"snow"`** |

⇒ 现状核对结论：**协调者两条断言里，"没雪"对、"冬天只有冷色调"错（有全季最强的霜白罩）、"rain 层"非空（brief 自己提醒过，实证在画）。**

---

## 二、改了什么（**只动 `WorldView.gd` 一个文件；零新素材、零数据改动**）

1. **新增 `_draw_snow()`**：冬季落雪。两层视差（~1/3 大片 `draw_rect` T×0.14 近景慢飘 / 其余小点 T×0.09 远景快落）+ 侧向漂移（相位 `sin`，循环外算一次）。
   密度随 weather：晴 40 / 阴 54 / **雨 70（暴风雪）**。确定性：位置 `_hash(gx,gy,91)`、相位 `tick%10`/`tick%5`——**不抽 RNG、不读墙钟**。
2. **强化 `_draw_rain()`**：密度 36→**52**；雨丝分**两档景深**（近：亮/长 0.56T/粗 1.9px；远：淡/短 0.34T/细 1.1px）；
   新增**地面涟漪**（独立散布 `_hash(rx,ry,43)`，扩大环 `draw_arc`，每 8 tick 亮 3 tick、半径随亮度扩大/透明度衰减——读作雨点打在地上；独立一套散布 ⇒ 不连成"相框"，docs/41 §6）。
3. **调度**（`:2649` 处）：`season=="冬"` ⇒ 雪；`elif weather=="雨"` ⇒ 雨。**冬季降水统一走雪**（`_draw_rain` 在冬季不调）⇒ 雪/雨不叠加成"雨夹雪"糊层。
4. **新增 `_precip_area()`**：把降水铺设**夹到 `地图矩形 ∩ 视口`**（与 `_draw_climate_wash` 同一条界）。**这是一个实测逼出来的必须改**，见下 §二·A。
5. **`--draw-skip <pass>` CLI 解析**（`_ready` user-args，与既有 `--draw-audit`/`--void-gate` 同处）：视觉门/dev 用来拍 on/off 负对照。**缺旗 ⇒ `_askip` 保持 settings.cfg 值（出货为 ""）⇒ 逐字节不变。**
6. **`AUDIT_PASSES` 加 `"snow"`**（`:172`），`AUDIT_PRIMARY` 23→24（dev 量具的闭合校验实际用 `not begins_with("bd:")` 自动纳入，此常量仅存文档）。

### 二·A · **实测逼出来的坑：全镇取景下降水被守卫吞掉**（docs/41 §6"先量再动"第 N 次发作）

第一版按 `_vis` 直接铺格，`--shot-fit`（或 go_home 全镇）下 **`_vis` 远大于地图**（含界外背板）：展开后的镇上冬帧实测
`_vis = 7129×4162 世界px ⇒ 97×60 = 5820 雪格 > VOID_DECOR_MAX_CELLS(4096)` ⇒ **守卫触发、整层不画**——
第一次 after 帧**冬帧一片雪都没有**，而 debug 打印证 `season=冬、_ap(snow)=true`（**调度进了，是守卫吞的**）。
雨在**小镇**（游戏日4）上 cell 更大、格数刚好没超，所以雨看着"能画、雪不能画"——典型的"量的是哪个对象"。
**改法**：夹到 `map∩vis`（64×48 图恒 ≤ ~2000 格），既保红线#3 手机填充率上限，又让降水在全镇视角画得出来。
> 附带的诚实边界：**在真机 go_home（zoom≈0.229，ProbeController 实测）看展开后的大镇时**，界外背板本来也会被夹掉——
> 但降水本就该只落在镇上（climate wash 同界），所以这是"对齐既有设计"，不是新增限制。

### 前后对照（同 seed3 / 同机位 / 同 tick，逐像素 diff；getbbox 陷阱安全写法：先 convert("RGB")）

| 帧 | on vs off / before vs after | 读法 |
|---|---|---|
| **CI 帧**（春·阴 游戏日3，seed3 tick600） | **bbox=None，0 px，maxdev 0** | **逐字节不变**——雪只读冬、雨丝只读非冬雨，**CI 帧（春·阴）两者都不触发** |
| 冬·晴 落雪（seed3 t11160，snow on vs off） | 1154 px，bbox 落在镇内 (288,120)-(1003,656)，maxdev 236 | 雪真在画（近白笔画），且只在地图带内 |
| 春·雨 雨丝（seed3 t840，rain on vs off） | 1458 px，bbox (287,122)-(996,651) | 雨丝+涟漪真在画 |

对照图（均为**真引擎截图 = 程序化美术、非生成图** ⇒ docs/41 §6 素材红线不适用；本棒零新素材）：
- [`docs/media/ai1_winter_before_after.png`](media/ai1_winter_before_after.png)：冬 before(无雪)|after(落雪)，游戏日46 暴风雪、seed3。
- [`docs/media/ai1_rain_before_after.png`](media/ai1_rain_before_after.png)：雨 before(稀疏)|after(两档雨丝+涟漪)，游戏日4 春雨、seed3。
- [`docs/media/ai1_winter_town.png`](media/ai1_winter_town.png)：全镇 --shot-fit 冬暴风雪（落雪铺满全镇）。

---

## 三、仿真侧逐字节不变——**三条独立证据，用 digest 证，不是声称**

`WorldView` 是纯渲染、`Sim` 从不读它（headless Harness 根本不实例化 WorldView）⇒ 机制上不可能动 digest。但照 docs/122 规格**跑出来证**：

### ① 自造 A/B（基线烘在我动手之前）
开工前 `Harness --seeds 1-6 --days 20 --chain-dump`，改完同命令重跑。全量逐 tick 前缀链 sha256 **两侧完全相同**：
```
9501cdb65cbf85c1e1612a6e34dd1ddc57c253c616aa5e1d309b01b3d06c50bf
```

### ② 金标（更强，烘在我动手之前、且不是我烘的）
`golden_digests.json` 是本棒开工前就在树上的。CI 第 4 步 S0 门带 `--golden` 比对（见 §五 判决行）。

### ③ 留出种子 31-36（CI 网格 seed 全在 1-12，从没覆盖这段）
`Harness --seeds 31-36 --days 20 --chain-dump` 改前改后各一遍，sha256 两侧同为：
```
c791484a6f14ca57f638c92038e84183f84155d650d7d4d73e67d234b360ddaa
```

> 顺带一条基线性质（**不是我的回归**，docs/122 §三 已记）：两侧 `--days 20` 跑都报 `S0 GATE FAIL`——红的是"软通过率门 ≥5/6"（按 60 天标定，20 天窗口天然不满），
> **改前改后红得一模一样**，硬不变量两侧 6/6 全绿、det 3/3。
>
> **另一条**：本棒两个 baseline sha 与 AF2（docs/122）逐字相同 ⇒ AF2 到本棒之间的所有 baton **没有一个动过这两段 digest**，是一个强的 tree-fresh 佐证。

---

## 四、新门：降水可见门（`analysis/ai1/assert_precip.py`，**未接线**）

守的性质一句话：**冬天必须真有落雪、雨必须真有雨丝——不许悄无声息退回"只有色调"。**
形状照抄 R2/S3/V3/AF2：**关系判据（on/off，不锚死绝对色）、吃已拍好的帧、判据在宿主侧跑、阈值量出来、几何有自检、只数 delta>8 的像素（忽略光栅器 LSB 抖动）。**

- **A1 臂（有雪）**：同 tick「雪 pass 开 / `--draw-skip snow` 关」两帧的差异像素数 ≥ `--min-snow`（默认 600）。
- **A2 臂（有雨）**：同 tick「雨 pass 开 / `--draw-skip rain` 关」两帧 ≥ `--min-rain`（默认 700）。
- **C 臂（几何自检，先跑）**：每对两帧都在、尺寸相等且 == 期望 fit 尺寸（否则取样带取歪，拒判）。
- **负对照【内建】**：off 帧**本身就是**"降水层被删空"的参照 ⇒ 谁把 `_draw_snow`/`_draw_rain` 删空 ⇒ on≡off ⇒ coverage 0 ⇒ 红。

### 阈值：多 seed 展布（逐 seed 报，S3 教训）
拍帧：冬用 tick 11160（游戏日47=冬，**season 与 seed 无关 ⇒ 全 seed 下雪**，密度随该 seed 当日 weather 变）；雨用各 seed 最早**非冬**雨日正午（seed1=t600/seed3=t840/seed5=t1560，都春·雨）。

| 量 | seed1 | seed3 | seed5 | 展布 |
|---|---|---|---|---|
| SNOW coverage(delta>8) | 1617(阴) | **1154(晴)** | 3505(雨) | [1154, 3505]，floor=1154（晴=密度地板40） |
| RAIN coverage(delta>8) | 1458 | 1458 | 1458 | **[1458,1458]，零方差** |

- 雪的方差来自 **weather 驱动的密度**（season 本身与 seed 无关，故 floor 恒在"晴"档）。
- 雨**零方差且这是证出来的**：雨丝画在居民**之上**（无遮挡）+ 铺设夹到 map∩vis + 正午 tick 降水相位恒 0（240k+120 恒 %6==0/%8==0）⇒ coverage=f(map)，与 seed 无关。
  与 AF2 季节门同形（f(季) 非 f(seed)）⇒ **单 seed 标定在这道门上安全，且这句话是证出来的**（S3 的反面）。
- `--min-snow=600`（floor 1154 的 0.52×，且 >> 负对照 0）；`--min-rain=700`（floor 1458 的 0.48×）。谁把它们提到 floor 以上，"晴"档冬帧会假红（那是**改后**的地板）。

### §2.5 探测包络（三行摘要；完整逐条 + 原始输出见 `analysis/ai1/assert_precip.py` 抬头与 `analysis/ai1/envelope.txt`）
```
detects:      ① 雪层删空/关（on≡off，coverage 0<600）⇒ 红 exit1（off 帧作负对照＝"在未画雪的树上它是红的"）
              ② 雨层删空/关（coverage 0<700）⇒ 红 exit1   ③ 几何错(640×384)⇒ C 臂拒判 exit1   ④ 缺 off 帧 ⇒ C 臂拒判 exit1
does_not_detect: 降水【长什么样】一概不管（关系判据，换色/换形状/换密度照过——色值真源在 WorldView.gd）；只看冬(season)与非冬雨(weather)两类，
              晨昏/其余天气组合没判；不验降水【确定性】（那由 digest+同 tick 重拍证，见 §三附）；只看 map∩vis 带内。
confidence:   N=4 变异体全按预期（各核过退出码）；does_not_detect 逐条从关系判据结构直接读出，非臆测。
              端到端复现（analysis/ai1/run_precip_gate.sh，docker 拍 12 帧 + 判据）：改后树上 **PRECIP GATE PASS，exit 0**（宿主 docker 实跑过）。
```

### 附：降水【确定性】另证（视觉侧，门不管这条所以单列）
两次**独立的 docker 渲染**（不同容器、不同 run）拍 seed3 同 tick（冬 t11160 / 雨 t840）⇒ **两帧逐字节相同（bbox=None）**。
⇒ 位置来自 `_hash`、相位来自 `tick_no`，无 RNG 无墙钟 ⇒ 同 tick 重拍逐像素可复现（这正是 on/off 门可比的前提）。

### 怎么接进 CI（本棒**不许碰 tools/**，接线留给合流的人）
降水门要吃**冬/非冬雨**帧，而 `visual_gate.sh` 现在只拍 seed3 春·阴 ⇒ 不能复用已拍帧，得多拍这 12 张。
`run_precip_gate.sh` 是端到端参照（与 `visual_gate.sh` 同构：docker 起 Xvfb 拍 12 帧 → 宿主判据）。
接线：把 `assert_precip.py` 挪到 `tools/`，把 12 条拍帧命令并进 `visual_gate.sh` 已有的 Xvfb，`ci.sh` 第 6 步抬头门数 +1。
拍帧 tick 已算好（冬=11160；雨=各 seed 最早非冬雨日）。⚠️ 照 V3/AF2 教训：`assert_precip.py` 抬头已 `sys.stdout.reconfigure(utf-8)`，加 stdout 时别再引入非 UTF-8。

---

## 五、既有视觉门 + CI（**读的是输出，不是退出码**）

### 既有视觉门：改后仍绿，且 CI 帧**逐字节**绿
`visual_gate.sh` 的全部判据（`assert_daynight` / `pond` / `assert_interior_shell` / `assert_furniture_role` / `assert_tree_stand` / `space_roundtrip`）
判的都是 **seed3 游戏日3（春·阴）** 帧（tick 488/600）。**雪只读冬、雨丝只读非冬雨 ⇒ 这两帧两者都不触发 ⇒ 逐字节不变**（§二 pixel-diff：CI 帧 bbox=None）。
本机（Windows）无 Xvfb ⇒ `visual_gate.sh` 自动选 **docker**（镜像在位、mesa pin、tol=0）真跑。

### 全量 CI
`GODOT=C:/Users/yp/.local/bin/godot bash tools/ci.sh`：**判决行见 §八 证据清单 `ci_final.txt`**。
并行期纪律（docs/41 §1）：跑前确认本 worktree 无 CI 在跑；docker 容器名带 PID、只杀自己的。

---

## 六、这份 brief 哪里是错的

1. **"冬天大概率只有冷色调、没有雪"** —— **一半对一半错**。"没雪"对（实证 grep 0 命中）；"只有冷色调"**错**：冬有 `SEASON_WASH["冬"]` 霜白 α0.24（全季最强）+ `SEASON_VEG["冬"]` 冷褪。缺的是**落雪的动**，不是色调。
2. **"rain 层大概率是空的"** —— brief 自己已经加了"别假设、先量"，量的结果是**非空**：`_draw_rain:514` 一直在画雨丝，只是**偏淡**。方向和 AF2 一样（"以为没做其实做了，只是没做透"）。
3. **brief 未提、量出来的真坑**：全镇取景（--shot-fit / go_home）下 `_vis ≫ 地图` ⇒ 降水铺格冲破 `VOID_DECOR_MAX_CELLS` 守卫、整层被吞（§二·A）。夹到 map∩vis 才修好。**这条不夹的话，冬帧一片雪都没有，而 debug 证调度进了——"有 X≠X 做好了"。**

---

## 七、我没做的 / 我证伪掉的自己的假设 / 留给下一棒

### 测了之后决定不做的
- **动 `WEATHER_WASH["雨"]`/`SEASON_WASH["冬"]` 的罩色**：能让雨更蓝、冬更白，但**阴罩（`WEATHER_WASH["阴"]`）就在 CI 帧里**，动罩色风险面大；而雨丝/雪花是**独立层**、碰不到任何 CI 帧 ⇒ 只动降水层更安全。没动罩。
- **给雪加地面积雪层**：冬季地面霜白已由 `SEASON_WASH["冬"]` 负责，再加积雪要碰 climate 带、且可能压到昼夜门采样的草地区。收益（落雪已足够读作冬天）不抵风险。没做。

### 明写没测到的（不用推断填空）
- **门没接进 CI**（不许碰 `tools/**`）。`run_precip_gate.sh` 在**宿主 docker** 上真跑过并 PASS，但**没在 `visual_gate.sh` 的 Xvfb 里真跑过**。
- **只测了 docker 软渲染 1280×768**：没出 APK、**没在真机验**（真机 go_home 全镇 zoom≈0.229 下降水会不会太密/太稀没量过——§二·A 的夹取只在 docker 全镇帧上验过）。
- **只测了 seed 1/3/5、正午 tod**：晨昏相位、冬×四天气的全组合、雨的其余季节没逐一判。
- **没测雪/雨在真机上的填充率**（红线#3）：夹到 map∩vis 后格数恒 ≤ ~2000、每格一个小 `draw_rect`/`draw_line`，机制上远轻于既有 void canopy（同 4096 档、画更大的图案），但**没在真机量 FPS**。

### 留给下一棒
1. **接门**：§四 的 12 帧并进 `visual_gate.sh`；顺手可加一条"同 season 跨 seed 雪 pattern 一致"的弱臂（今天没加：雪 coverage 已随 weather 变，pattern 一致性靠 `_hash` 纯函数+同 tick 重拍已证）。
2. **真机验降水密度**：go_home 全镇下眼验冬雪/暴雨是否合适；若太密，密度档（40/54/70）与 cell（雪 T×1.25/雨 T×1.5）是唯一旋钮。

## 八、证据清单

| 文件 | 内容 |
|---|---|
| `docs/media/ai1_winter_before_after.png` | 冬 before(无雪)\|after(落雪)，真引擎截图 |
| `docs/media/ai1_rain_before_after.png` | 雨 before(稀疏)\|after(两档雨丝+涟漪) |
| `docs/media/ai1_winter_town.png` | 全镇 --shot-fit 冬暴风雪 |
| `analysis/ai1/assert_precip.py` | 降水可见门（判据 + 阈值标定 + §2.5 包络写在抬头） |
| `analysis/ai1/run_precip_gate.sh` | 端到端复现（docker 拍 12 帧 + 判据），与 `visual_gate.sh` 同构 |
| `analysis/ai1/envelope.txt` | 1 绿 + 4 红变异体的原始输出 + 退出码 |
| `analysis/ai1/ci_final.txt` | 本棒最终那次全量 CI 的原始输出（判决行） |
