# 162 · 交通/建筑种类 scoping 收据（item#2 + 丰富building种类）· 只读

> 只读普查结论（agent 落实读，行号以 git 为准）。给下一批实现棒定型。**关键排期约束见 §三。**

## 〇、地面实况（纠"7 区/4 类"）
map.json 有 **9 区 / 5 type**（residential/commercial/public/workshop/**plaza**）；`dock` 区（`type:plaza`、滩头、北池南岸 `[30,7,4,2]`、蓄意不含水格）+ `bench_pier 渔台`worksite（借 bench 精灵）已在。typed-layer 恒等现成立：`walls(167)∪water(80)∪trees(156)==blockers(403)`。

## 一、建筑管线 + move-golden/零金标切分（命门）
- **Sim 只读 area 的 `rect`+`label`，从不读 `type`**（`_area_at` 首命中按**文件序**、`_nearby_agents`=同 area 社交桶、`_area_centroid`=寻路/克隆落位）。⇒ **`type`（及只读子字段如 `kind`）纯 View、零金标**（`BLD_PAL`/`_wall_type`/`_interior_shell` 消费）。
- **零金标**：WorldView 画 port 结构 / 加 `type`|`kind` View 值 / **加空且 N=12 永不被占用·永不当 centroid 的 area rect**（`dock` 区先例已实测 12/12 逐字节）。
- **移金标**：居民**进入/居住**的新区(新社交桶)、**advertises 的对象/worksite/家具**、新增 walls/blockers 格(改 nav,须过 audit_map ①typed-layer 集合恒等 ②BFS 连通 ⑤区内可达 ⑥双路 …)。
- **port_dock**=纯 logistics node id（**只声明不落图**，为 #44 溯源存在），无实体 pier/boat/warehouse。

## 二、gate 约束
- **INTSHELL/FURNROLE 只采 `INT_SPACES` 7 个被捕获室内**（home/home2/cafe/shop/wash/work/library）⇒ **exterior-only 新建筑(无室内)= 不被采、动不了 INTSHELL**。新 `type` 只在"新类型+被捕获室内"时才须补 `BLD_PAL`/`FLOOR_PAL`(foot ΔE≥8) + `_draw_sign` 分支；exterior 新类型的外观区分靠人眼。
- **新 type 无 `BLD_PAL` 项 = 静默渲成 workshop 灰石屋 bug**（`BLD_PAL.get(typ, workshop)`）⇒ 要么补项、要么复用现有 type、要么走 View-only `kind`。

## 三、★推荐首片 = Option A：dock 纯 View 港口结构（零金标）
新 `_draw_port()`（读 `Sim.world.areas.dock.rect`，画 pier/boat/系缆桩/货箱/小仓库 silhouette + 可选 edge 处 rail/platform·bus-stop props），注册 `AUDIT_PASSES` 的 `"port"` 段、在 `_draw()` dressing 块附近调用。**owns 仅 `WorldView.gd`**（一新函数+一调用点+一 AUDIT 项），复用现有 wood/stone/water 色常量、**不加新 type**。零金标（Sim 不动）。
- **★排期约束（命门）**：Option A **与 AV3（地面收尾，也 owns WorldView.gd）file-adjacent** ⇒ **不能并行**，须**排在 AV3 land 之后**在 AV3 树上起（各 own distinct 函数/区、merge 取并集；动前查别 worktree uncommitted）。
- **唯一真风险 = POND 门**：dock 在北池南岸，pier 画过 y6/y7 水草缝会扰 POND 的 shoreline 采样 ⇒ **结构尽量落已铺 dock 格/陆侧**、要跨水 pier 就重跑 POND 确认绿。DAYNIGHT 低风险仍验。〔POND 具体采样列未实跑确认，当风险待验非定论〕
- 验收：pure-View 零金标（S0 金标 12/12 逐字节）+ 视觉门 tol=0（重点 POND）+ 真机 --shot 眼验 + docs。

## 四、后续 Option B：一个 functional exterior 新建筑（移金标）
真·建筑种类(仓库/集市/港作为"地方")=map.json 加 area。**低风险做法**：复用现有 type(仓库=workshop/集市=commercial 免新 type/INTSHELL)、**exterior-only**(无室内免 INTSHELL/FURNROLE)。空且不占用=N=12 零金标(dock 先例)；居民占用/advertises 对象=移金标。硬处=nav 纪律(walls∪water∪trees==blockers 集合恒等不宽容)+ N>12 第 10 区扰克隆落位。排 Option A 之后。

## 五、诚实边界
POND 采样列未实跑；shipping golden 是否含 bench_pier worksite(经济 lane ON)未全溯（area-only 零金标靠 `dock` 先例，稳）。Option A/B 都避开经济 lane(Sim/logistics 不动)，唯一耦合=与地面视觉 lane 共编 WorldView.gd(§三排期)。
