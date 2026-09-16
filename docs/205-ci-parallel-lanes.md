# 205 · 把 CI 拆成并行 lane（零金标）

> 触发：用户 2026-09-15「proceed split CI」。docs/113 §四·2 从 2026-08-06 起就写着正式方案是
> 「拆成全部 required 的并行 jobs」，此前三次都只做了过渡动作（`timeout-minutes` 15 → 35 → 55 → 65）。
> 建在 [204 P4a 镇公所与财政](204-p4a-town-hall-finances.md) 之上。**一条判据都没改** ⇒ 零金标、零产品改动。

## 一、做了什么

| 改动 | 内容 |
|---|---|
| 先量 | PR #65 那一跑（`ci` job 42m26s）逐步墙钟：step 4 S0 **404s**、4a 宏观池 **445s**、4b-4h 六道门 **729s**（其中 4d BackendGate 一个 **281s**）、step 5 场景 **958s**（其中 `story_test` 一个 **633s**、`goals_test` **216s**、其余 23 个合计 109s）、step 6 视觉门在 GHA 上 **0s**（按 `visual_gate.sh` 的显式判断 SKIP）、0-pre..3 静态门合计 **9s**。**setup 只要 18s**（checkout 4s + python 1s + pillow 1s + godot 2s + import 9s）—— 这一条是拆并行便不便宜的关键：复制 setup 几乎不要钱。 |
| lane | `tools/ci.sh` 认一个 `CI_LANE`：`lint / s0 / pool / gates / backend / scenes / story / visual` 八条。**默认 `all`** ⇒ 本机 `bash tools/ci.sh` 与改动之前逐步同义（同样的步、同样的顺序、同样的判据）。 |
| 切法 | 守卫是 `if lane <名>; then … fi`，**一行正文都没动、没重排缩进**：判据仍然是原来那几行。step 5 的场景表改成 `CI_SCENES_ALL`（单一真源）+ `CI_SCENES_STORY`，两条 lane 按构造取补集 ⇒ 想漏掉一个场景，只能从全表里删它。 |
| workflow | 七个并行 job（`lint` 兼跑 `visual`），共用一个 composite action `.github/actions/lt-setup`（GHA 的 workflow 不支持 YAML 锚点，抄七遍就是七份会各自漂移的副本）。`ci` 变成**汇总 job**：不跑门，只收七条 lane 的 result。 |
| 分支保护 | **不动**。required context 仍是 `ci` 与 `visual_canary`（`enforce_admins` 开着，改它要另走一趟）——`ci` 现在是汇总 job，七条 lane 任一红它就红。 |
| 新门 1c | `tools/assert_ci_lanes.py`：把 `ci.sh` 的 `CI_LANES_ALL` 与 `ci.yml` 里各 job 的 `CI_LANE` 逐字对账。五条判据、五条负对照，见 §三。 |

## 二、量出来的

| | 改前（PR #65 实测） | 改后（估，= 最贵那条 lane + setup） |
|---|---|---|
| `ci` 关键路径 | 42m26s（一条串行链） | **≈ 11 分钟**（`story` lane 633s + setup 18s） |
| 计费分钟合计 | ≈ 42.4 | ≈ 45（2545s 的门 + 七份 18s setup，**+5%**） |
| `visual_canary` | 12m01s（不动） | 12m01s（不动） |
| PR 整体墙钟 | 42m26s | **≈ 12 分钟**（这时瓶颈换成了 `visual_canary`） |

七条 lane 的实测代价（同一跑）：

| lane | 步 | GHA 墙钟 | timeout |
|---|---|---|---|
| `story` | step 5 的 `story_test` 一个场景 | **633s** | 25 min |
| `pool` | 4a 宏观池尺度门 | 445s | 20 min |
| `gates` | 4b LOD · 4c DetGate · 4e ModelPath · 4f Voice · 4g #43 · 4h state_projection | 448s | 20 min |
| `s0` | 4 S0 门（不变量 + 确定性 + 金标） | 404s | 20 min |
| `scenes` | step 5 其余 24 个场景 | 325s | 20 min |
| `backend` | 4d BackendGate | 281s | 15 min |
| `lint` + `visual` | 0-pre..3 静态门 + step 6（GHA 上 SKIP） | 9s | 10 min |

- **关键路径的下界是 `story_test` 那一个场景（633s）**，拆得再细也快不过它。要再快只能改它自己的网格
  （seeds 1-12 × 40 天，40 这个数的代价曲线与"为什么不是 14 也不是 60"写在 `ci.sh` 第 5 步那段 ★ 里）——
  **那是把判别力换速度，不在本棒的行里**，所以没动。
- `4d` 从 `gates` 里单拎出来不是为了配平，是因为它是**唯一一道模型真的在挑动作**的门
  （其余每一道都恒 `backend=null`，硬不变量 #01 只在这条路上验过）。它值一个自己的名字。
- `timeout-minutes` 按实测约 2 倍给：够未来几片长肉，又还能抓住真的挂死。**这次没有再抬任何上限。**

## 三、新开的这道门（1c）在守什么

拆并行开出了一个**新的失败模式**，而且是最贵的那一种：

> 一道门可以不被删掉、只是不再被任何 job 点到，于是它从此永远不跑，而每一个 PR 依旧全绿。

`tools/assert_ci_lanes.py` 对两份文本逐字对账（不跑 godot、不读产品数据，0s）：

| # | 判据 | 漏掉它会怎样 |
|---|---|---|
| ① | `ci.sh` 里每处 `lane <名>` 的名字都在 `CI_LANES_ALL` 里 | 拼错的 lane 名恒为假 ⇒ 那一段再也不跑，而 bash 一声不吭 |
| ② | `CI_LANES_ALL` 里每条 lane 都至少被一处守卫用到 | 留下一个空名字，下次有人照它挂 job |
| ③ | workflow 各 job 的 `CI_LANE` 并起来 **恰好等于** `CI_LANES_ALL` | 少一条 = 那道门在 GHA 上一次都不跑 |
| ④ | 同一条 lane 不挂在两个 job 上 | 白花分钟；更要紧的是"它在哪儿跑"不再有唯一答案 |
| ⑤ | 汇总 job `ci` 的 `needs` 覆盖每一个 lane job | 漏一个 ⇒ 那条 lane 红了也拦不住合并，而 required check 依旧显示绿 |

负对照 `python tools/assert_ci_lanes.py --self-test`：五条各造一例变异体，**实测五条全部变红**。

还有三条不在这道门里、但被写进 workflow 的坑，记在这儿免得以后重新踩：

- **汇总 job 必须 `if: always()`**。默认 `needs` 有失败就**跳过**本 job，而**被跳过的 required check 在
  GitHub 那里算作通过** —— 不写这一行，拆并行反而把必红变成了必绿。
- **仓库内的 composite action 不能自己带 `actions/checkout`**：GHA 要先把仓库检出来才找得到
  `.github/actions/lt-setup/action.yml`，不然那一步直接 "Can't find action.yml" 挂掉。⇒ checkout 留在
  每个 job 的第一步，composite 从第二步接手。（本棒第一版就是这么写错的，落地前改掉了。）
- **每个 job 各自 checkout**，所以那条 exact-SHA 回执（`CI_SOURCE … sha=…`）现在七个 job 各打一遍：
  它从"证明这次看的是事件 SHA"升级成"证明七个 job 看的是**同一个** SHA"。

## 四、验收回执

- `python tools/assert_ci_lanes.py` ⇒ 七个 job 的 lane 逐条对上；`--self-test` ⇒ 五条负对照全红。
- **lane 划分是穷尽且不重叠的**（实测，不是读出来的）：逐条 lane 跑一遍 `ci.sh` 收集它打印的 `###` 步头，
  23 个步头（0-pre, 0, 1, 1b, 1c, 2, 2b, 2c, 2d, 2e, 2f, 3, 4, 4a, 4b, 4c, 4d, 4e, 4f, 4g, 4h, 5, 6）
  **每个恰好出现在一条 lane 里**；step 5 的 25 个场景按 24 + 1 分给 `scenes` / `story`。
- 本机 `bash tools/ci.sh`（默认 `all`，= 改动之前的全跑）：回执见 PR。
- 金标：**一个都没重烘**。本棒不碰 `game/`。

## 五、没做 / 留给后面

- **`story_test` 的网格**：它是关键路径的下界（633s）。真要再快，得先回答"40 天这一档能不能按 seed 切成两半跑"——
  那要重新量一次判别力（`ci.sh` 第 5 步 ★ 段里那条 M2 变异体得在切开之后仍然被抓住），是独立一棒。
- **`visual_canary` 没有收进 composite action**：它是唯一自带渲染运行时的 job（ubuntu-24.04 + Xvfb + mesa），
  setup 形状本来就不同。硬合并只会造出一个满是 `if` 的 setup。
- docs/113 §四·2 还写着"由同一 phase manifest 驱动本地全量与 GHA matrix"。本棒选了更轻的一步：
  **lane 表就写在 `ci.sh` 里**，workflow 只引用它，由 1c 对账 —— 没有第二份门列表要维护，也就不需要 manifest。
