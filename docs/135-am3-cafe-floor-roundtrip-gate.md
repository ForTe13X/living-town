# 135 · AM3 — cafe 全楼层 portal 往返门（`town→cafe/1f→2f→1f→town` 的 Probe 往返一致性）

> Wave AG3 纵切实现·验证棒（brief：docs/126 §四·G1「多楼层往返」）。外审 2026-08-06 Phase 1 退出条件
> ——"观察者能走完整旅程"的机器门。基线 `integration/batons`=`7997ba5`（含 AM1 cafe + AM2 shop/work 室内）。
> owns：`game/bench/SpaceShot.gd`（扩 `--rt-journey full`，纯 render/捕帧）、`tools/space_roundtrip.sh`（扩 journey 分派）、
> `tools/assert_floor_roundtrip.py`（新判据）、`tools/visual_gate.sh`（接线）、本文档 135。
> **不碰** Sim.gd / golden / gate_complement·fixture 三件套 / AM1·AM2 室内内容。

守的性质，一句话：**观察者能走完整旅程 —— town→cafe/1f→（楼梯 portal）2f→（楼梯）1f→（街门）town，
逐段落在对的 Floor、2F 那一跳真换平面、走完一圈回 town / 回 1F 的取景逐像素复位**——而这一切是 **view-only、零金标**
（Probe 的 `active_space/active_floor` 不进 digest，AG3 的 R1，`probe_digest_test.sh` 机检）。

---

## 一、现状清点（开工前实读，带行号；先量再定 scope）

### 1.1 现役 1F 往返门覆盖到哪

| 件 | 覆盖 | 行号 |
|---|---|---|
| `game/bench/SpaceShot.gd`（simple 模式） | **只 3 帧**：`town_before → interior(cafe/1f) → town_after`。进店走 `_enter`（街门 portal），出店走 `_leave`。**没有楼梯腿、没有 2F、没有 floor 参数。** | 采集主体 :91-154；`_enter`/`_leave` :199-231（原行号） |
| `tools/space_roundtrip.sh` | 宿主编排 + 容器内 `--shoot`；判据 `assert_space_roundtrip.py`。只 `town↔cafe/1f`。 | 全文件 |
| `tools/assert_space_roundtrip.py` | A 往返不变式（town_after≡town_before）+ B 界外带活 + C interior≠town。**都在 1f 一层。** | 全文件 |

⇒ **楼梯往返（1f↔2f）此前没有任何门**；cafe 2F 只被 AM1 的 `assert_cafe_2f.py`（走 `--shot` 启动即进 2f 的**静帧**路）看过，
**从没被【往返路径】看过**（docs/126 §一.3 点名的空缺）。

### 1.2 ⚠️ 纠正协调者的假设：**"SpaceShot 只传 2F 参数不改" —— 实测不成立**

协调者 brief：*"优先【只调它、传 2F 参数】，别改它"*。**实读证伪，三条硬事实**：
1. SpaceShot **结构上只拍 3 帧**（`town_before/interior/town_after` 三处 `_snap`），没有多拍 2F 的入口；
2. **没有 `--rt-floor` 之类参数**——它整条路径没有"上楼"这个动作；
3. 它取 portal 世界坐标的 `_portal_world_pos(from_space, to_space)` **按 Space 匹配**，而楼梯 portal `p_cafe_stairs`
   两端**同 Space（cafe↔cafe）、只差 Floor**（spaces.json:212-233），按 Space 匹配分辨不出方向。

⇒ **要拍 2F 往返，必须改 SpaceShot**（加"上楼/下楼"这条出货路径 + 多拍两帧 + 逐段 floor 断言）。
按 brief 的授权（*"若确实必须改 SpaceShot 才能拍 2F，keep it 纯 render/捕帧 + 给零金标证据 + 声明 tree 变化"*）——
本片改了 SpaceShot，**只加 view-only 的导航与捕帧，一个字节不写 Sim**（§四零金标）。

### 1.3 关键实读：Probe 上楼**不受 `access:owner` 拦**（这是 2F 往返可行的前提）

`p_cafe_stairs.access="owner"`（spaces.json:231）。但 `Main._portal_click`（game/scripts/Main.gd:2439-2467）
**只按当前 `active_space + active_floor + 点中的 cell** 匹配 portal，然后 `set_space(other.space, other.floor, …)`——
**一处都不查 access**。`owner` 只在 Sim 的 agent 路由里拦居民（Tier-B），**观察者不是 agent**。
⇒ 在 cafe/1f 点楼梯 cell [1,1] → 上 2f；在 cafe/2f 点同一 cell → 下 1f（`_portal_click` 按当前楼层判方向）。**实测印证**（§三绿跑逐段全对）。

---

## 二、改动（把 1F 往返门扩成全楼层）

### 2.1 `game/bench/SpaceShot.gd`（+ `--rt-journey full`，纯 render/捕帧）
- 新参数 `--rt-journey simple|full`（默认 **simple**；simple 一个字节不变 = 现役 1F 往返门原样）。
- `full` 模式：`town_before → cafe_1f →（点楼梯上）cafe_2f →（点楼梯下）cafe_1f_back → town_after` 五帧，
  **逐段断言落在对的 Floor**（进店应 1f、上楼应 2f、下楼应回 1f、出门应 town）；任一段不对 ⇒ `_rc=1`
  ⇒ 采集失败 ⇒ 门红（**这就是"某一跳目标层改错 ⇒ 门必红"的机器化，采集侧那道牙**）。
- 楼梯 cell 由新 `_stairs_world_pos(pb)` 从 `_main._sg.portals` **真源**取（不抄第二份坐标，同 `_portal_world_pos` 纪律），
  点它走**出货路径** `pb.emit_signal("tapped", …)`→`Main._on_probe_tap`→`_portal_click`——与玩家真点楼梯同一段代码。
- 纯 View：只发 `tapped` 信号 + `_snap` 截图 + 读 `active_space/active_floor`，**不写任何 Sim 态**。

### 2.2 `tools/space_roundtrip.sh`（扩 journey 分派 + 负对照旋钮）
- `LT_RT_JOURNEY=simple|full`（默认 simple）：full ⇒ 透传 `--rt-journey full`，判据分派到 `assert_floor_roundtrip.py`。
- `LT_RT_DRAW_SKIP=<pass>` / 便捷别名 `LT_RT_SKIP_FURN=1`（=`interior_furniture`）：透传 `--draw-skip`，
  **让 2F/1F 家具都不画 ⇒ 两层帧变一样 ⇒ B 臂（可分）必红**（负对照，见 §三 NC-1）。
- `LT_RT_GAME=<dir>`（**沿用现役逃生门**）：指向改过的 game/ 拷贝做负对照（见 §三 NC-2）。

### 2.3 `tools/assert_floor_roundtrip.py`（新判据，宿主侧）
复用现役 `assert_space_roundtrip` 的 stdlib PNG 解码器 + 几何换算 + 界外带下界常数（红线#5 复用优先，两份解码器必漂）。五臂：
- **L 逐段楼层/空间对**（读 meta，Requirement 1）：town_before=town · cafe_1f=cafe/1f · cafe_2f=cafe/2f · cafe_1f_back=cafe/1f · town_after=town。
- **A1 回程取景一致**（Requirement 2）：town_after≡town_before 逐像素（地图矩形）+ 界外带活（下界）+ `cam_same` 前提。
- **A2 楼梯往返 1F 复位**（Requirement 2 楼梯腿）：cafe_1f_back≡cafe_1f 逐像素（下楼回到的那层取景/内容原样）。
- **B 2F 与 1F 可分**（判别力，Requirement 3）：frac_diff(cafe_2f, cafe_1f) ≥ SEP_MIN。
- **C 真的进过店**（配对判别力）：frac_diff(cafe_1f, town_before) ≥ 0.20。

### 2.4 `tools/visual_gate.sh`（接线，同 AM1 cafe2f 手法）
`--shoot` 块补一条 `RT_JOURNEY=full … space_roundtrip.sh --shoot "$OUT/floor"`（复用同一个 Xvfb，写子目录避免撞名），
rc=8 专给采集失败；宿主侧补 `assert_floor_roundtrip.py "$OUT/floor"` + `FLRC` 退出传播（**不短路**——与前十道门守不同性质）。

`git diff --stat`：`SpaceShot.gd | 75+`、`space_roundtrip.sh | 27+`、`visual_gate.sh | 23+`、新 `assert_floor_roundtrip.py`、本文档。
**game/ 只碰 `bench/SpaceShot.gd` 一处**（bench，非 Sim 金标路）。

---

## 三、docker 实跑（gamecraft-runner:4.6.2 软渲 pin，Mesa 23.2.1 llvmpipe，tol=0；seed3 tick600）

### 3.1 绿跑（未改动树，`LT_RT_JOURNEY=full`）——完整旅程逐段对 + 回程取景一致

```
[SPACESHOT] town_before  space=town  floor=outdoor  cam=(1536,1152) zoom=0.2292
[SPACESHOT] cafe_1f      space=cafe  floor=1f       cam=(192,144)   zoom=1.9722
[SPACESHOT] cafe_2f      space=cafe  floor=2f       cam=(192,144)   zoom=1.9722
[SPACESHOT] cafe_1f_back space=cafe  floor=1f       cam=(192,144)   zoom=1.9722
[SPACESHOT] town_after   space=town  floor=outdoor  cam=(1536,1152) zoom=0.2292
[SPACESHOT] 前提 ✅ 出店后取景与进店前逐字节相同
  PASS L[town_before/cafe_1f/cafe_2f/cafe_1f_back/town_after]  逐段 space/floor 全对
  PASS A1[map] 变化像素=0/366800   A1[band_top/bot] 0/0   A1B 颜色数 99/1126 标准差 29.4/31.4
  PASS A2[cafe_1f 往返] 下楼 1F 与进店 1F 变化像素=0/424692（逐字节相等）
  PASS B[2F↔1F] 内格变化占比=0.1767 (≥0.07)
  PASS C[cafe_1f↔town] 全帧变化占比=0.9832 (≥0.20)
=== FLOOR ROUNDTRIP GATE: PASS ===   (exit 0)
```
即：五段全落在对的 Floor；出门回 town 逐字节复位（A1=0）；**楼梯往返 1F 逐字节复位（A2=0）**；2F 真换平面（B=0.177）；真进过店（C=0.98）。

### 3.2 负对照（判据没过这关就不是判据）——两条牙，都 docker 实跑读退出码

**NC-1「让 2F 帧=1F 帧」**（`LT_RT_SKIP_FURN=1` ⇒ `--draw-skip interior_furniture`，两层家具都不画）：
```
  PASS L[…全对]  A1=0  A2=0  C=0.9832 PASS
  FAIL B[2F↔1F] 内格变化占比=0.0276 (≥0.07) —— 2F 与 1F 画得太像
=== FLOOR ROUNDTRIP GATE: FAIL (1) ===   (exit 1)   ← 只 B 红，牙精确落在"2F 那一跳"
```

**NC-2「把某一跳目标 floor 改错」**（`LT_RT_GAME` 指向 game/ 拷贝，`p_cafe_stairs.to.floor` 2f→1f）：
```
[SPACESHOT] ❌ 上楼后应在 2f，实为 1f（楼梯目标层不对/portal 断）
  ❌ ROUNDTRIP GATE：采集失败（见上面的 [SPACESHOT] 行）   (exit 1)   ← 采集侧那道牙先咬
```
把同一批 NC-2 帧直接喂宿主判据（证明**宿主侧也独立有牙**，双证）：
```
  FAIL L[cafe_2f] space=cafe floor=1f(应2f)
  FAIL B[2F↔1F] 内格变化占比=0.0000 —— "2F"帧其实是 1F、与 1F 全同
=== FLOOR ROUNDTRIP GATE: FAIL (2) ===   (exit 1)
```

**阈值 SEP_MIN=0.07 是量出来的**：绿 0.1767、NC-1 0.0276 ⇒ 取几何均值 √(0.1767×0.0276)=0.070，两侧各 ~2.5× 余量，
不贴任一侧（贴绿侧下次 2F 美术微调假红，贴红侧漏轻回归）。A1/A2 是逐字节相等（mesa pin ⇒ 同内容同相机 ⇒ 0 差）。

---

## 四、零金标三证据（改了 game/bench/SpaceShot.gd，声明 tree 变化）

**tree 变化声明**：本片改了 `game/bench/SpaceShot.gd`（game/bench，**非 Sim 金标烘烤路**——金标由 `res://bench/Harness.gd` 产出，
SpaceShot 只实例化 `Main.tscn` 走 view 层）。改动是**加性**的：新 `--rt-journey full` 分支 + `_climb`/`_stairs_world_pos` 两个
helper，**只在 `--rt-journey full` 下执行**，且**零 Sim 写**（只 `emit_signal("tapped")` + 截图 + 读 `active_*`）。simple 模式逐字节不变。

| 证据 | 结论 |
|---|---|
| ① S0 金标（12 seed × 60 天 × det 3，`--golden`，本机 native godot 4.6.2.stable） | **PASS ✅**：`=== S0 GATE: PASS ✅ (硬不变量 seed 12/12 全绿, 软通过率门 ≥11/12(90%) 过, 活性 过, 金标 过, det 3/3) ===`。**金标 过 = 12/12 逐字节相同（含 chain）** ⇒ SpaceShot（bench，非金标烘烤路）+ tools 改动未移动 digest。 |
| ② R1 观察者无关性 `probe_digest_test.sh`（docker 实跑） | **A（不碰相机）与 B（狂拖狂缩）逐字节相同**：`520 3436175414 2970312921389411378` ⇒ `PROBE OBSERVER-INDEPENDENCE: PASS ✅`。我的改动没破 R1（本就 view-only）。 |
| ③ `git diff --stat` | game/ 只碰 `bench/SpaceShot.gd` 一处；其余全 tools/+doc。 |

---

## 五、§2.5 探测包络（assert_floor_roundtrip.py + 采集侧 SpaceShot 逐段断言）

```
detects（逐条状态）：
  ① 某一跳目标 Floor 改错（p_cafe_stairs.to.floor=1f）⇒ 上楼落 1f
     ⇒【采集侧】SpaceShot 逐段断言 rc=1（[SPACESHOT]「上楼后应在 2f，实为 1f」）
       +【宿主侧】L[cafe_2f] 红 且 B=0.0000 红。**双证，实测 exit 1**（NC-2）。
  ② 2F 帧==1F 帧（--draw-skip interior_furniture，两层家具都不画）⇒ B 内格 0.0276<0.07 ⇒ 红。
     **实测 exit 1，只 B 红**（NC-1）——牙精确落在"2F 那一跳"，不误伤别的臂。
  ③ 回程取景不复位（town_after≠town_before / cam_same=false）⇒ A1 红（逐像素 + cam_same 前提）。
  ④ 楼梯往返 1F 没复位（cafe_1f_back≠cafe_1f）⇒ A2 红（逐像素）。
  ⑤ 压根没进店（cafe_1f≈town）⇒ C 红。
  ⑥ 少帧 / 尺寸非一致 ⇒ 几何自检拒判（exit 1/2）。
does_not_detect（实测 / 结构直读）：
  · 颜色对不对一概不管（关系判据，色值真源留 WorldView.gd 不抄进判据）。
  · 只 cafe 一栋有 2f，只测它；其余楼层的 2F 不存在，不测。
  · 只 seed3 一个 warmup-tick、晴天、软渲 docker（镜像 pin 死 mesa）、非真机。
  · 只看地图矩形 / 内格区域取样条，不逐件家具。
  · **不守 Probe 换层/换空间是否 view-only**——那是 R1 的 probe_digest_test.sh 的活（本门自身 view-only、零金标）。
  · ③④⑤ 未单独造端到端变异体真跑：A1 复用 assert_space_roundtrip 已验过的往返臂同型逻辑 + cam_same 前提断言；
    A2/C 的红侧从"逐字节相等/占比阈值"结构直读，绿帧上量到 A1/A2=0 差、C=0.98（--measure）。诚实记为结构证据，非端到端变异体。
confidence：
  N=2 个端到端变异体 docker 实跑（NC-1 skip-furn / NC-2 wrong-floor，各读退出码 + 判决行）+ 绿帧端到端 PASS 1 次；
  A1/A2 的逐字节 0 差、B/C 的实测占比均由 --measure 在【未改动真帧】上量出（非臆测）。
  端到端：先在【未改动树】上跑 ⇒ A1/A2/L/C 绿、B 是新增判别力（未改动树上 2F 本就≠1F ⇒ B 绿 0.177）。
```

---

## 六、CI 判决 + 仍绿的证据

- **R1 `probe_digest_test.sh`**：docker 实跑 **PASS ✅**（§四证据②，A≡B 逐字节）——我的改动没破它。
- **`bash tools/ci.sh`**：落地时跑绿（step6 视觉门含新全楼层往返门；step4 S0 金标 12/12 = 零金标证据①）。⚠️**审查 F4 纠**：该 run 判决行**当时未归档**（`analysis/am3` 未建），roadmap 曾引"1596s PASS"属**无存证的精确秒数**——已不作存证。✅**整轮 CI 归档回填（2026-08-07，`analysis/review-2026-08-07-ci/verdict.txt`，HEAD `1fcbfc8`）**：**`=== FLOOR ROUNDTRIP GATE: PASS ===`**（全楼层往返门在现役树上重跑绿）+ 全流水线 **`=== CI PASS ✅ ===`**、S0 金标 12/12 含链。
- **接线纪律**：全楼层往返门与现役 `assert_space_roundtrip`（town↔1f）**不重叠**——那条只走 1f，本条补楼梯往返（1f↔2f）+ 2F 判别力；
  两门**不短路**（visual_gate 尾部各自 exit），一条红另一条读数仍有诊断价值。

## 七、这份 brief 哪里需要更正（docs/41 §4）

1. **"优先只传 2F 参数不改 SpaceShot" —— 证伪**（§一.2）：SpaceShot 结构上只 3 帧、无 floor 参数、portal helper 按 Space 匹配分辨不出楼梯方向。要拍 2F 往返**必须**改它；本片按 brief 授权改了，keep 纯 render/捕帧 + 零金标。
2. **"往返门现覆盖到哪" —— 量清**（§一.1）：现役只 `town↔cafe/1f`，楼梯往返（1f↔2f）此前**零门**；cafe 2F 只被 AM1 的 `--shot` 静帧路看过，**从没被往返路径看过**。本门补的正是这一段。
3. **`access:owner` 不拦 Probe 上楼**（§一.3）：`_portal_click` 一处不查 access，owner 只拦 Sim agent；这是 2F 往返可行的前提，实读 + 绿跑双证。
