# 125 · AG2 回执——#43 观察侧买家防线：`wn_other` 从"只排商贩"收紧成"排交易双方"

> **一句话**：docs/112 的观察侧判据（#43 ①臂 `wn_other`）当初**只排了商贩(收款方=target)一端**，
> 买家(actor)混进 witnesses 仍被当"被看见"数——这是外审 Codex 2026-08-06 附录 §六.1 点名的 **P2 抗回归缺口**。
> 本棒把 `wn_other` 收紧成**同时排掉买家(actor)与商贩(target)**，观察侧这才真正做到"交易双方之外"。
> **纯判据收紧、零行为变更、零金标**（自然轨迹逐字节 inert），加两条真牙负对照。

## ★ 交付状态

- 分支 `worktree-agent-a32039665ed300dc8`（基线 `091411c` = `integration/batons` 顶端，091411c 是本分支祖先 ⇒ 可 ff）。
  worktree 路径 `E:/Documents/Dev/June/26th/.claude/worktrees/agent-a32039665ed300dc8`。**不 push、不 merge。**
- 改动（三个文件 + 本回执）：
  - `game/bench/Invariants.gd`——#43 ①臂 `wn_other` 加排 `buyer43 = actor`（+ 两处注释订正）。
  - `game/bench/aa3fix_census.gd`——加 `buyeronly` / `partiesonly` 两条负控臂（+ 抬头注释）。
  - `docs/112` §九.1——订正"witnesses 语义从此是『交易双方之外』"那句过强表述（原文只做了商贩一端）。
  - 本回执 `docs/125`。
- **`TRADE_MIN_SALES=5` 豁免线一个字节没动**（Z2 的口径，改判据要用户拍板——同 docs/112 §六）。
- **未重烘任何金标锚**（`golden_digests.json` / `modelpath_anchor.json` / DetGate 锚全未动）——本改动结构上碰不到它们（见 §二）。

## 一、Codex §六.1 的断言——实读复核（都属实）

| Codex/协调者断言 | 实读结论 |
|---|---|
| `Invariants.gd` `wn_other` 只数 `String(w43) != v_id` ⇒ 只排商贩、没排买家 | **属实**。改前 `:1121-1124` 就是 `if String(w43) != v_id: wn_other += 1`。 |
| `aa3fix_census.gd` 只有 `vendoronly`/`keepone`，没有 `buyeronly`/`partiesonly` | **属实**。 |
| `docs/112` §九.1 声称"交易双方之外"、与代码不符 | **属实**。§一② 自己写的是"去掉【商贩】后非空"（只一端）；§九.1 却说"交易双方之外"（两端）——文档内部就自相矛盾。 |
| 采集侧(Sim.gd `twits`)已不把商贩写进 witnesses | **属实**（`Sim.gd:1500-1516`，AA3-FIX 的 payee 过滤 + `_nearby_agents` 本就跳过买家自己）。 |

## 二、买家的字段名是 `actor`——证据链（不假设，读源码 + `git log -S`）

buy `pay` 事件里**买家**存在 `actor` 字段（商贩在 `target`）。三段源码逐跳对齐：

1. **赶集付款调用点** `Sim.gd:1516`：
   `if transfer(String(ag["id"]), payee, price, ("buy:" if payee != "town" else "price:") + String(opt["action"]), twits):`
   ⇒ `from = ag["id"]`（**买家**），`to = payee`（**商贩**）。
2. **transfer** `Sim.gd:3197,3205`：
   `func transfer(from_id, to_id, amt, reason, witnesses=[])` → `_log_event("pay", from_id, to_id, "", true, witnesses, reason)`。
3. **_log_event** `Sim.gd:3797,3801-3802`：
   `func _log_event(type, actor_id, target_id, …)` 存 `{… "actor": actor_id, "target": target_id, "witnesses": wids, …}`。

⇒ buy `pay` 事件 `actor = from_id = 买家`，`target = to_id = 商贩 = v_id`。
`git log -S '"actor": actor_id' -- game/scripts/Sim.gd` ⇒ 该字段自 `ebac5a3`（首个公开快照）起就叫 `actor`，稳定。
#43 现有代码本来就用 `String(e.get("target","")) == v_id` 匹配 buy 事件 ⇒ 买家就是 `String(e.get("actor",""))`。

## 三、改了什么（判据一处，收紧一句）

`game/bench/Invariants.gd` #43 ①臂：

```gdscript
var buyer43 := String(e.get("actor", ""))     # 买家=pay 事件的 actor（见 §二证据链）
var wn_other := 0
for w43 in wits43:
    var ws43 := String(w43)
    if ws43 != v_id and ws43 != buyer43:       # 改前只有 `!= v_id`（只排商贩）
        wn_other += 1
if wn_other > 0:
    sales_w += 1
```

语义：`sales_w`（被看见的成交）只数**交易双方以外**的目击者——既排商贩(target=v_id)、也排买家(actor)。
唯一改动是**收紧**（多排一个 id），没有放松任何判据、没有动豁免结构、没有动其余臂。

## 四、零金标——三锚证据（自然轨迹逐字节 inert）

**结构性理由（先说清为什么本改动碰不到金标）**：金标 `Inv.digest(S)`（`Invariants.gd:1392`）折的是
**每条事件的原始字段**（id/type/actor/target/accepted/subject/tick/witnesses串/note），**不折 `check_all` 的判据结论**。
`wn_other` 只影响 `#43` 的 pass/fail，**结构上进不了 digest / event_digest / chain** ⇒ 金标不可能因它而动。
（docs/41 §247 明写"金标全绿≠改动被验证"，故下面另造能证伪的 A/B + 负控，不只靠金标。）

**① 自造 A/B 摘要**（`aa3fix_census --seeds 1-6 --days 60 --agents 12`，自然臂 `mutate=`）：
改前(baseline Invariants) vs 改后(本棒) **逐字节相同**——同一个 SHA256 `6bf9585502…`：

```
census_natural_BEFORE.txt  6bf958550232b9833c985a71f4a2dc37d834f82051487a8adb3c5b3d4d0a053b
census_natural_AFTER.txt   6bf958550232b9833c985a71f4a2dc37d834f82051487a8adb3c5b3d4d0a053b
```
每 seed `digest` / `event_digest` / `inv43` / `hard_fails=[]` 全同；`buy_vendor_in`=0、`buy_vendor_only`=0（自然轨迹里
商贩与买家本就不在 witnesses：商贩被采集侧过滤、买家=ag 被 `_nearby_agents` 跳过）⇒ 多排一个 id 逐位无差。

**② 开工前金标 baseline**（`Harness --seeds 1-6 --days 60 --det 3 --golden golden_digests.json`，改动落盘**前**跑）：
`✅ 金标一致 6/6 seed` · `✅ #43 [硬]买卖的社会痕迹 6/6` · `=== S0 GATE: PASS ✅ ===`（exit 0）。
改后由第七节全量 CI 复跑（S0 金标仍 12/12，逐 seed digest 与本 baseline 逐位同，见 §七 seed 1-4 抽样）。

**③ 留出 seed**：census A/B 与负控都在 seeds 1-6 上跑（非只 1-4）；全量 CI 覆盖 seeds 1-12（S0）。
自然臂 6/6 全绿、逐字节同 ⇒ 收紧判据在留出格上同样 inert。

## 五、负对照——两条真牙（跑出来的，附退出码，不是"打印❌照样放行"）

census 探针始终 `quit(0)`（它是量具不是门）⇒ **"红"以真实 `Inv.check_all` 的 `hard_fails`/`inv43.ok` 为准，
不以进程退出码为准**。为堵"打印❌照样放行"，把 JSON 里的真判据结论转成带退出码的断言（`verify_teeth.sh`）。

**5.1 收紧后（本棒判据）· seeds 1-6 · 两臂各 6/6 红**：

| 臂 | witnesses 合成为 | `hard_fails` | `inv43.ok` | `被看见` | `buy_witnessed`(wn>0) |
|---|---|---|---|---|---|
| `buyeronly` | `[买家=actor]` | `[43]` ×6 | `false` ×6 | 0 | = buy_total（84/64/71/63/71/63） |
| `partiesonly` | `[买家, 商贩]` | `[43]` ×6 | `false` ×6 | 0 | = buy_total |

detail（逐 seed 同形）：`成交84笔但【一笔都没被看见】(pay 的 witnesses 通道断了)`。
`verify_teeth.sh` 判决：`natural 0/6 · buyeronly 6/6 · partiesonly 6/6 红` ⇒ **exit 0（断言全部成立）**。

**5.2 这是"牙"不是巧合——同一账本，旧门瞎、新门咬（`buyeronly` × 旧判据 vs 新判据）**：
把 `Invariants.gd` 临时换回 baseline（只排 v_id），同一条 `--mutate buyeronly` 再跑 seeds 1-2：

```
旧判据(只排 v_id)  hard_fails=[]   inv43.ok=true   被看见84 / 被看见64   ← 绿：买家混进 witnesses 被当"被看见"
新判据(排交易双方)  hard_fails=[43] inv43.ok=false  被看见0  / 被看见0     ← 红：本棒新增的检出力
```
`buy_witnessed = buy_total`（每笔都有 witness）却 `被看见=0` ⇒ 旧门(wn>0)会绿、新门(排双方)咬 ⇒
**本棒收紧的正是买家端软点**，与 docs/112 对商贩端做的 `vendoronly` 牙同构。测毕已把 Invariants 换回本棒版本。

## 六、订正 docs/112 §九.1

原文第 1 句：`witnesses 的语义从此是"交易双方之外"——谁再往 transfer 的 witnesses 里塞交易当事人，#43 ①臂会把那笔当"没被看见"数`。
**过强**：docs/112 §一② 的观察侧改动只把 `wn_other` 排了【商贩】一端，买家端没排 ⇒ 这句对买家不成立。
已订正为：本回执观察侧**只排商贩一端**、买家端由 AG2(docs/125) 补全；收紧后（AG2）观察侧才真正做到"交易双方之外"，
并指到本回执的 `buyeronly`/`partiesonly` 负控。采集侧(§一①/§二)两端都排，未动、仍准确。

## 七、`bash tools/ci.sh` 全量（判决行照抄）

由协调者在 `main-integration` worktree（把本棒改动应用其上、基线 trunk `990cf2c`）复跑，避免与本棒自己那次 CI 撞同一 worktree：

```
=== CI PASS ✅ ===
全程 895s（现算的，机器忙闲浮动）
✅ 视觉门（昼夜 / 界外层重画 / 空间往返 / 岸线 / 室内外壳 / 家具语义 / 树丛点阵）
```
exit 0。S0 金标 12/12、DetGate/BackendGate/ModelPathGate/VoiceGate、场景/story/save-load、7 道视觉门全绿。
日志里两类**已知非根因噪声**（与本改动无关）：`nobodywho.gdextension` 缺库（Codex 也记过，测试照跑）；
`AIBackend.gd:894 parse_decision` 那条 `Parse JSON failed got 'A'` 是**故意的 fail-closed 负控**（喂非法串验证被拒，其上一行 ✅ 断言已过）。

**独立复核（协调者亲跑 census 三臂，非抄本棒）**：seeds 1-6 × 60 天 × N=12——
- `natural`：6/6 `hard_fails:[]`、`inv43.ok:true`（被看见 71/43/59/51/62/51）⇒ 收紧后自然轨迹**仍绿**；
- `buyeronly`：6/6 `hard_fails:[43]`、"成交…笔但一笔都没被看见" ⇒ **红**（旧判据会绿，牙咬住买家端）；
- `partiesonly`：6/6 `hard_fails:[43]` ⇒ **红**；
- **零金标直证**：三臂逐 seed 的 `digest`/`event_digest` **逐位相同**（seed1 均 `2354668902`/`7824884320643865142`）——
  谓词只在 `check_all`（读侧断言），不进 Sim digest ⇒ 结构上不可能移金标。

## 八、没能测到什么（"没测"明写）

- **只改了 `#43 ①臂 sales_w` 的计数口径**；docs/112 §八 的盲区（m5-m8、keepone 那条 does_not_detect、
  BackendGate/ModelPathGate 里商贩成交绝对频次）本棒**没重跑**，原样继承。
- **豁免线没动**：`buyeronly`/`partiesonly` 在 seeds 1-6 上 buy_total 58-84 ≫ 5 ⇒ 红不受豁免线影响；
  但短 horizon / 随机后端下 buy_total<5 的格仍会被豁免（与商贩端同一条，未改）。
- 负控只在 N=12、seeds 1-6/1-2 上跑；未扫 N≠12 网格（全量 CI 的 4a N=16 由 CI 覆盖，非本棒 census）。
- **未重烘任何锚**：本改动结构上不动 digest（§四），故无需 R12 重烘；若将来有人让它动了金标——那是判据以外的
  行为变更，**停下报用户**，别自行重烘（R12 + docs/113 §0.8 territory）。本棒实测：没动。
