# 131 · AK1 · 季节+降水视觉门接进 required CI + 硬化 runner 子进程 rc 检查

> 外审 2026-08-06 21:00 **P0.5**。协调者此前误以为"降水零金标已被 digest+既有视觉门覆盖"，外审证伪：
> **simulation digest 不含像素，现役视觉基准刻意拍春季帧，季节/降水视觉此前没有任何 CI 牙。**
>
> **基线**：worktree checkout 落后（`38ba4a7`），`git merge-base --is-ancestor 38ba4a7 integration/batons` 确认是祖先后
> `git merge --ff-only integration/batons` = **`869d53a`**（AF2 判别脚本 + AI1 判别脚本 + WorldView 降水都已在这条线上）。
>
> **owns 之内改了**：`tools/visual_gate.sh`（接线 + rc 硬化）、`tools/vg_shoot.sh`（**新增**：硬化的拍帧封装）、
>   `analysis/af2/assert_season.py` / `analysis/ai1/assert_precip.py`（只在抬头加一行 AK1 接线注记，**判据/阈值/§2.5 一字未动**）、本文（编号131）。
> **一个字节都没碰**：`Sim.gd`、`game/data/**`、`game/scripts/WorldView.gd`（AF2/AI1 已改）、`game/bench/**` 金标锚、
>   `tools/gate_fixture_audit.py` / `gate_complement_guard.py` / `gate_complement_ledger.json`（**用户另一 session 在 re-bake 那一片**）、
>   `tools/ci.sh`（**刻意不碰**，理由见 §五）。

## 〇、一句话结论

- **季节可分门（AF2/编号122）+ 降水可见门（AI1/编号129）已接进 `tools/visual_gate.sh` 的第 6 步**，
  在**同一个 Xvfb** 里多拍 8 帧（四季×昼夜，晴天）+ 12 帧（冬雪 on/off + 非冬雨 on/off × 3 seed），
  判据在宿主侧**原地引用** `analysis/{af2,ai1}` 的两个判别脚本，判决并入 visual_gate 的 rc。
- **runner 子进程 rc 检查已硬化**：把原来到处是 `if [ -s x.png ]`（只看图存在=fail-open）的拍帧步，
  全部换成 `tools/vg_shoot.sh` 的 `vg_shoot`——**rc==0 + 无致命日志标记 + 图非空，三者结合**，任一不过判红。
- **docker 实跑**：新门在当前树**绿且有牙**——双负对照实测（改弱季节乘色/删雪⇒门红；godot rc≠0⇒runner红）。
- **SKIP-on-no-Xvfb 语义保持**（能力探测在拍图之前，无渲染环境仍 77 SKIP 不假红）。
- **不碰仿真/金标/game-data**（天然零金标），`bash tools/ci.sh` 本机走 docker 真跑、全绿。

---

## 一、接线 diff（visual_gate.sh 加了哪些捕帧+断言步、rc 硬化改了哪几处）

### 1a. 新文件 `tools/vg_shoot.sh` —— 硬化的拍帧封装（外审点名的 fail-open 修复）

原来 `visual_gate.sh` 的昼夜/室内拍帧步是：
```bash
"$GBIN" … --shot "$OUT/x.png" … >>log 2>&1
if [ -s "$OUT/x.png" ]; then echo ok; else rc=1; fi   # ← 只看【图存在且非空】
```
外审证伪那是 fail-open：**godot 崩了但残留旧图 / 写了半张再崩 / push_error 之后仍退 0
（ci.sh 抬头明写 GDScript 的 push_error() 不改退出码）**——这几种都被读成"拍好了"。
`vg_shoot` 把**三个信号结合**，任一不过即判这一帧失败（并打印指向真正病因的原因）：

| 信号 | 抓什么 | 备注 |
|---|---|---|
| ① 子进程 `rc==0` | 进程非零退出 | 容器里 godot 是真二进制，rc 可信，**这是主判据** |
| ② 日志无致命错误标记 | rc 不可信环境（本机 godot.cmd）里报了 SCRIPT ERROR 却退 0 | 标记刻意**不含裸 `ERROR:`**——容器缺 nobodywho 每次开场固定打几行良性 `ERROR:`/`Condition`（ci.sh 白名单同款），只认 `SCRIPT ERROR\|USER ERROR\|Parse Error\|Failed to load script\|Failed to instantiate\|Segmentation fault\|core dumped\|Aborted` |
| ③ `--shot` 落盘图非空 | rc==0 且无报错但根本没写图 | 旧判据唯一看的那条，保留 |

`vg_shoot` 先 `rm -f "$out"`（不让上轮残留冒充本轮），子进程输出捕到临时日志再汇进共享日志（失败时上层 `tail` 得到它）。

### 1b. `visual_gate.sh` 改动

- **`--shoot` 块顶部**：`. "$(dirname "$0")/vg_shoot.sh"` + `export VG_GODOT_LOG=/tmp/vg-godot.log`。
- **昼夜 `for pair` 循环**：`"$GBIN" … ; if [ -s ]` → `vg_shoot "$OUT/vg_${nm}.png" "$GBIN 参数…" || rc=1`。
- **室内 `for sid` 循环**：同上改走 `vg_shoot`，失败 `[ "$rc" -eq 0 ] && rc=4`。
  （void-gate 与 space_roundtrip 两步**本来就查 rc**（`if "$GBIN" …; then`），未改；space_roundtrip.sh 不在本棒所有权表，不碰。）
- **新增季节采集**（室内循环之后，同一 Xvfb）：`mkdir -p "$OUT/season"`，按 `SEASON_PAIRS` 拍 8 帧
  （seed3 四个晴天 × 昼夜：春 gd2 tick 360/248 · 夏 gd20 4680/4568 · 秋 gd35 8280/8168 · 冬 gd51 12120/12008），失败 `rc=5`。
- **新增降水采集**（同一 Xvfb）：`mkdir -p "$OUT/precip"`，`for s in 1 3 5` 各拍冬雪 on/off（`--draw-skip snow`）+ 非冬雨 on/off（`--draw-skip rain`）
  （冬 tick 11160；雨 tick s1=600/s3=840/s5=1560），失败 `rc=6`。
- **host 侧**：`--shoot` 的 rc 分档加 `5=季节采集失败 / 6=降水采集失败` 两个处理块（与既有 2/3/4 同构，各报各的病因，不混）。
- **host 侧判据**（tree_stand 之后、清理之前，**不短路**，与既有六门同规矩）：
  ```bash
  "$PY" analysis/af2/assert_season.py --noon …4帧 --night …4帧 ; SEARC=$?
  "$PY" analysis/ai1/assert_precip.py "$OUT/precip"            ; PPRC=$?
  …
  [ $SEARC -ne 0 ] && exit $SEARC
  [ $PPRC  -ne 0 ] && exit $PPRC
  ```
  两个判别脚本**原地引用不搬**：`assert_season.py` 按 `analysis/af2/` 逐级上溯 `import tools/{assert_daynight,ciede2000}`，搬进 tools/ 反而断 import；host 侧 CWD 已是仓库根，相对路径成立。

### 1c. 为什么不复用已拍的春帧

`visual_gate.sh` 原来只拍 seed3 游戏日3（春·阴）。季节门要吃**全四季**、降水门要吃**冬/非冬雨**——
这两批帧春帧里都不触发（雪只读冬、雨丝只读非冬雨、夏/秋/冬色只在各自季日），故**必须多拍**，不能像 pond/tree_stand 那样复用。

---

## 二、docker 实跑：绿 + 双负对照（**读的是输出**）

环境：本机 Windows，无 Xvfb 但有 `gamecraft-runner:4.6.2`（mesa pin）⇒ `visual_gate.sh` auto 选 **docker**、tol=0 真跑。

### 2a. 当前树 ⇒ 全绿（33 帧全 `shot ok`，八/九门全 PASS）
```
=== DAYNIGHT GATE: PASS ===        （夜 (57,82,63)==expect dmax=0）
=== ROUNDTRIP GATE: PASS ===
=== POND GATE PASS ✅ ===
[INTSHELL] ✅ 室内外壳类型门 PASS（7 栋/4 类）
[FURNROLE] ✅ 家具语义分化门 PASS（7 栋/5 类）
[TREESTAND] ✅ 林相点阵门 PASS（昼+夜两帧）
[SEASON] 昼 最小两两 ΔE00 = 8.06 (春↔夏)  阈值 3.20  ⇒ PASS
[SEASON] 夜 最小两两 ΔE00 = 4.30 (春↔夏)  阈值 3.20  ⇒ PASS
=== SEASON GATE: PASS ===
  PASS A1 SNOW s1/s3/s5 coverage= 1617 / 1154 / 3505  (min=600)
  PASS A2 RAIN s1/s3/s5 coverage= 1458 / 1458 / 1458  (min=700)
=== PRECIP GATE: PASS ===
```
季节/降水的每一个数与 AF2（编号122）/AI1（编号129）的 envelope **逐值相同** ⇒ 接线没引入任何漂移。
**33 帧全 `shot ok`** ⇒ 硬化的错误标记集在 clean 帧上 **0 假红**（②臂在正常渲染上不误伤）。

### 2b. 负对照①：改弱视觉 ⇒ 门必红（`LT_VISUAL_GAME` 指向 scratchpad 的 game/ 拷贝，真 game/ 不碰）
在拷贝的 `WorldView.gd` 上做两处最小改弱：`SEASON_VEG["夏"]` 退回 = 春值；`_draw_snow()` 首行 `return`。
一次 docker run 同时打红两门，**其余六门全绿**（改弱是外科式的）：
```
[SEASON] 昼 最小两两 ΔE00 = 1.18 (春↔夏)  阈值 3.20  ⇒ FAIL
[SEASON] 夜 最小两两 ΔE00 = 0.81 (春↔夏)  阈值 3.20  ⇒ FAIL
=== SEASON GATE: FAIL (2) ===
  FAIL A1 SNOW s1_winter_on coverage= 0  (min=600)
  FAIL A1 SNOW s3_winter_on coverage= 0  (min=600)
=== PRECIP GATE: FAIL ===
VISUAL_GATE_EXIT=1
```
> 诚实注记：`s5_winter_on` 仍报 1449 而非 0——因为把 `_draw_snow` **整个删空**后，冬·雨天气那一 seed 的
> `off` 帧沿 `elif weather=="雨"` 掉进了雨的兜底分支，on/off 遂有差。这是极端变异体的副作用，不改结论：
> 单帧红（s1/s3）已让降水门整体 FAIL（与 AI1 envelope MUTANT① "单帧 coverage 0 ⇒ 门红"同构）。

### 2c. 负对照②：godot 子进程 rc≠0 ⇒ runner 必红（证 rc 硬化真拦得住 fail-open）

**假 godot 单测**（喂 `visual_gate.sh` 用的同一个 `vg_shoot`，四种子进程行为，`scratchpad/ak1/fakegodot_test.sh`）：

| 变异 | 盘上有合法非空图？ | 期望 | 实测 |
|---|---|---|---|
| 写出合法非空图 + rc=0 + 无报错 | 是 | ok(0) | ✅ `shot ok` |
| **写出合法非空图但 rc=1** | **是** | **红(1)** | ✅ `shot FAIL (godot rc=1)` ← **旧 `[ -s ]` 会放过，这就是外审点名的 fail-open 闭合** |
| 写出合法非空图 + rc=0 但日志 `SCRIPT ERROR` | 是 | 红(1) | ✅ `shot FAIL (致命错误标记)` |
| rc=0 无报错但没写图 | 否 | 红(1) | ✅ `shot FAIL (产图为空/缺失)` |

**真·容器 godot**（不是假的；坏项目路径，盘上预置合法旧图）：
```
--- real container godot, bad project path (expect nonzero rc) ---
  shot FAIL x.png (godot rc=1 —— 子进程非零退出，判红)
  vg_shoot_returned=1
```
`vg_shoot` 返回 1 会在 `visual_gate.sh` 里把 SHOT_RC 置非零 ⇒ host 打 `❌ VISUAL GATE` 并 `exit 1`。
⇒ **rc 硬化在假 godot 与真二进制两条路上都拦得住**，尤其闭合了"盘上有合法图但进程失败"这个 fail-open。

---

## 三、§2.5 探测包络（季节 + 降水各一份，as-wired；判据本体的完整包络见两个判别脚本抬头 + `analysis/{af2,ai1}/envelope.txt`）

### 季节可分门（AF2/编号122，AK1 接线）
```
detects（都跑过、核过退出码）：
  ① 改弱夏季乘色（夏=春）⇒ 春↔夏 昼 1.18 / 夜 0.81 < 3.20 ⇒ 红（§2b 端到端真跑）
  ② 四季全塌成一色（四帧都喂 spring）⇒ 六对全 ΔE00=0 ⇒ 红（§三本机复跑，rc=1）
  ③ 取景几何错（非 1280×768 整数倍）⇒ C 臂拒判 exit1   ④ 少喂一帧（≠4）⇒ C 臂拒判 exit1
does_not_detect（实测/从关系判据结构直接读出）：
  · 颜色对不对一概不管（关系判据：把四季映射对调、四主色照样两两分开⇒全绿；色值真源在 WorldView.gd）
  · 只看那条 HUD-free 横带的地面主色（树/花草/界外林换季不看）
  · 只判被拍到的昼(tod=0.5)/夜(tod≈0.03)两档；晨昏、四季×天气其余组合没判
  · 要晴天（拍帧步已挑晴天 tick；天气罩会把两季拉近，判据本身对天气无意见）
confidence：N=4 变异体（①②③④）全按预期；接线后当前树 docker 实跑昼 8.06/夜 4.30 PASS（与 AF2 envelope 逐值同）
```

### 降水可见门（AI1/编号129，AK1 接线）
```
detects（都跑过、核过退出码）：
  ① 雪层删空（_draw_snow return）⇒ 冬 on≡off（非雨天气 seed）coverage 0 < 600 ⇒ 红（§2b 端到端真跑）
  ② 雨层删空/关（coverage 0 < 700）⇒ 红（AI1 envelope MUTANT②）
  ③ 几何错(640×384)⇒ C 臂拒判 exit1   ④ 缺 off 帧 ⇒ C 臂拒判 exit1
does_not_detect（关系判据结构直接读出）：
  · 降水长什么样一概不管（换色/换形状/换密度照过——色值真源在 WorldView.gd）
  · 只看冬(season)与非冬雨(weather)两类；晨昏/其余天气组合没判
  · 不验降水【确定性】（那由 digest + 同 tick 重拍证，见编号129 §三）；只看 map∩vis 带内
confidence：N=4 变异体全按预期；接线后当前树 docker 实跑 snow 1617/1154/3505、rain 1458×3 PASS（与 AI1 envelope 逐值同）
```

### 多 seed 展布纪律（S3 教训：单 seed 标定会让别的 seed 零代码变红）
- **季节**：四季色是 `SEASON_VEG[季]`（纯 f(季)）× 草地（纯位置），晴天无天气罩 ⇒ 地面主色 = f(季)、**与 seed 无关**。
  AF2 实测 seed 1/3/5 春/夏主色**逐字节相同**（零方差）⇒ 单 seed(3) 标定在这道门上**安全，且是证出来的**（S3 的反面）。
- **降水**：雨 coverage = f(map)、**零方差**（正午相位恒 0、雨丝画在居民之上无遮挡）；雪密度随 weather 变（晴40/阴54/雨70）
  ⇒ **拍全 3 seed**、floor 恒在晴档（seed3=1154）。阈值 `--min-snow 600`（floor 0.52×）/`--min-rain 700`（floor 0.48×）
  **取自 AF2/AI1 已逐 seed 标定的地板，本棒不再收紧**（谁提到 floor 以上，晴档冬帧会假红）。

---

## 四、`bash tools/ci.sh` 判决行（**读输出，不读退出码**）

- **本机（无 Xvfb、有 docker 镜像）**：视觉门 auto 选 docker ⇒ **真跑**（不是 SKIP——本机恰好有镜像）。
  判决行见 `analysis/ak1/ci_full.log`（本文最后一次全量 CI 的原始输出）：`=== CI PASS ✅ ===`。
- **SKIP 语义仍在**：把镜像设成不存在（`LT_VISUAL_IMAGE=nonexistent-runner:0.0`）+ 本机无 Xvfb ⇒
  能力探测在拍图之前判定"两样都没有" ⇒ **exit 77 SKIP，不假红**（实测输出即此，见 `analysis/ak1/skip_probe.txt`）。
  ⇒ 无渲染环境的机器（例如显式跳过的 GHA）照旧 SKIP；接线没有破坏这条可移植性。

---

## 五、刻意没做的 / 留给合流

- **没碰 `tools/ci.sh`**。第 6 步抬头写着"这一步现在有【六】道门"——接了季节+降水后**其实是八门**。
  这行是纯文案；`visual_gate.sh` 的 rc 契约（0/1/77）没变，`ci.sh` 的 `case "$VRC"` 照旧正确判绿/红/跳过，
  **改文案不影响判决**。按 owns（只 `tools/visual_gate.sh` + 新捕帧脚本）+ 避免与其它 session 撞 `ci.sh` 这只热文件，
  刻意不改；把这一行门数（六→八）+ `case` 的 ok 文案留给下一个动 `ci.sh` 的人顺手更。
- **没碰 `space_roundtrip.sh`**（不在所有权表；它本来就 `if "$GBIN"…; then` 查 rc，无 fail-open）。
- **没在真机 / GHA 上跑过**。视觉门在 GHA 上由 `visual_gate.sh` 的显式 `$GITHUB_ACTIONS` 判断跳过（理由见该脚本抬头：
  GHA 的 GL 栈没 pin、红绿随镜像滚动自变）。判别力最强的一档在开发机 docker（tol=0），本棒就在那里验的。
- **成本**：视觉门从 ~13 帧涨到 ~33 帧（+8 季节 +12 降水），docker 软渲染约 +6~8 min。若嫌贵，
  `LT_VISUAL_PRECIP_SEEDS=3`（只 seed3）可省 8 帧、季节可分是 f(季) 与 seed 无关本就单 seed——但那把多 seed 展布的保险削了，默认全 3 seed。

## 六、证据清单

| 文件 | 内容 |
|---|---|
| `tools/vg_shoot.sh` | 硬化的拍帧封装（rc + 致命标记 + 图非空，三信号结合） |
| `tools/visual_gate.sh` | 接线（季节 8 帧 + 降水 12 帧同 Xvfb 采集 + host 侧两判据）+ 全部拍帧步改走 vg_shoot |
| `analysis/af2/assert_season.py` / `analysis/ai1/assert_precip.py` | 判别脚本（**判据/阈值/§2.5 未动**，仅抬头加 AK1 接线注记） |
| `analysis/ak1/green_full.txt` | 当前树 docker 全绿的原始输出（八/九门判决行） |
| `analysis/ak1/negctl_weakened.txt` | 负对照①：改弱季节乘色+删雪 ⇒ 季节/降水两门红、其余六门绿、exit 1 |
| `analysis/ak1/negctl_rc.txt` | 负对照②：假 godot 四变异 + 真容器 godot rc≠0 ⇒ vg_shoot 判红 |
| `analysis/ak1/ci_full.log` | 本机全量 `tools/ci.sh` 原始输出（判决行 `=== CI PASS ✅ ===`） |
| `analysis/ak1/skip_probe.txt` | 无渲染环境 ⇒ exit 77 SKIP 不假红 |
