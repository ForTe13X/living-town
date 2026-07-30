# `pro/` — 角色去道具 + 各自轮廓（Wave E · E3 → Wave F · F2）

这里的 **10 张 PNG** 是对 CC0 素材包 `puny-characters` 的**改绘衍生**，不是新素材、不是生成图。
`Art.gd:73-78` 的三级回退第一级就是本目录（`pro/<name>.png` > `library/.../<name>.png`），
所以它们**不需要任何代码改动**即生效，删掉本目录就逐字节回到原始奇幻外观。

两棒接力，产物是同一批文件：

| 棒 | 脚本 | 做了什么 |
|---|---|---|
| **E3**（Wave E） | [`tools/deprop_characters.py`](../../../../tools/deprop_characters.py) | 去道具：alpha 掩膜 + 查表换色 ⇒ 现代小镇便服 |
| **F2**（Wave F） | [`tools/coif_characters.py`](../../../../tools/coif_characters.py) | 加轮廓：头部复位 + 每人一张发型/帽子模板 |

`coif_characters.py` **内部调用** `deprop_characters.py`，所以**只跑第二个脚本就能从零重建整个目录**。

## 源与许可（红线 #4）

| | |
|---|---|
| 源 | `../library/puny-characters/Puny-Characters/*.png` |
| 源许可 | **CC0**（作者 Shade，见 [`../library/puny-characters/LICENSE.txt`](../library/puny-characters/LICENSE.txt)，条目在 [`../../../../tools/assets_catalog.json`](../../../../tools/assets_catalog.json)） |
| 本目录产物 | CC0 允许修改 ⇒ 仍是 CC0 / 自绘衍生 |
| 生成图参与度 | **零**。依 docs/43 §二-R2，AI 出图只能当情绪板，绝不进精灵帧 |

两个脚本合起来只做四件事：**alpha 掩膜、查表换色、从 `Character-Base` 复制像素、写死坐标的手绘模板**。
**不缩放、不插值。**

## E3 做了什么（去道具）

裁决在 docs/44 §一。把 `Character-Base.png` 的 alpha 当掩膜——实测它是其余 9 张表**全部 192 帧**的严格子集
（`base AND NOT other` 恒为 0 像素）⇒ 这个包是「一具共用身体 + 在身体**之外**叠画的装束」。
一次掩膜就整块去掉尖顶兜帽、羽毛、牛角、盔缨、披肩以及攻击行里的法杖/弓/剑；
再把盔甲灰阶换成布料色阶（**保留明度剖面**，只换色相/饱和度）⇒ 同族两两差 14286-14477 px。

## F2 做了什么（加轮廓）——以及它顺手修掉的两处退化

E3 的代价写在 docs/44 §一·五：**十张脸的 alpha 全部等于 `Character-Base`** ⇒ 剪影完全相同。
F2 把轮廓加回来。三步：

1. **头部复位**：把 `top .. top+7` 这一带（`top` = 该帧 base 的首个非空行）整块从 `Character-Base` 复制回来。
   **纯复制、零发明**，但它同时修掉两处 E3 没注意到的退化：
   - **头顶那一圈没有描边**——兜帽自己的黑描边长在 base 之外，被掩膜切掉了，
     于是出货帧的 `Mage-Red` 在 y10 直接是 `#770000` 贴着透明，浅色地面上会糊。
   - **眼睛只剩上半截**——兜帽压到 y15，把 2px 的眼睛盖掉一半；出货的脸是一双眯着的眼 + 没有额头。
2. **戴发**：每人一张 ASCII 模板（发型 / 帽子），锚在 `(x_ref, top)` ⇒ 走路"上下颠"那一帧自动对齐。
3. **描边**：新加的像素自带 `#040404`（与身体同一根描边色）。

**新加的像素按定义就是 `out.alpha AND NOT base.alpha`**——加了多少、加在哪，是算出来的不是看出来的。

### 数字（12 个可达帧，`col 0..3 × row {0,1,3}`）

- **剪影两两可分度**：改前 **全部 0**（十张脸逐像素同一个剪影）→ 改后 **最小 120 px、中位 240、最大 480**。
  最小对是可可（贝雷帽）↔ 老邓/铁牛（毛线帽），以及老海（雨帽）↔ 老邓/铁牛。
- **脸的皮肤边界像素**：袍装 187 → **281-319**；Warrior/Soldier **106/110 → 294-318**。
  ⇒ docs/44 §一·五 记的那条**跨全体演员的不对称**（袍装的脸是 Warrior/Soldier 的两倍）**没有了**，
  现在十张全在 **281-319** 之间。唯一下降的是阿梅（408 → 304）——她本来是**光头露全脸**，戴了头发就得让出一些。
- **头 vs 世界表面 min ΔE00**（口径与 E3 同源）：最小 13.16 → **15.63**（地板抬高），
  最大 27.29 → 21.89（自然发色比饱和兜帽收敛，这是交易不是白赚）。

## 逐张对照（⚠️ 文件名与外观已经对不上）

| 文件 | 谁在用（`data/personas.json`） | 衣服（E3） | 头（F2） |
|---|---|---|---|
| `Mage-Red.png` | 阿丽（咖啡馆老板） | 深红连帽便服 | 黑发 · **侧马尾**（右耳后垂下） |
| `Mage-Cyan.png` | 可可（画家） | 青绿连帽便服 | 亚麻发 · **贝雷帽**（向左歪出 2px） |
| `Archer-Green.png` | 小薇（学生） | 橄榄绿连帽便服 | 深棕 · **双马尾**（向外撇到 x8/x23） |
| `Archer-Purple.png` | 阿菲（医生）、苏琴（琴师） | 紫色连帽便服 | 黑发 · **齐肩短发**（唯一在下半部扩轮廓的） |
| `Warrior-Blue.png` | 阿本（工坊木匠） | 靛蓝工装 | 深棕 · **鸭舌帽**（平顶 + 单侧帽舌） |
| `Warrior-Red.png` | 阿林（面点铺师傅） | 赭褐皮围裙 | 姜黄 · **头巾**（右上角一个结） |
| `Soldier-Blue.png` | 老海（渔夫） | 藕紫衬衫 | 灰白 · **宽檐雨帽**（全场最宽，y12 达 14px） |
| `Soldier-Red.png` | 沈书（教书先生） | 草绿工服 | 黑发 · **发髻**（全场最高的一个小圆钮） |
| `Soldier-Yellow.png` | 老邓（退休船长）、铁牛（铁匠） | 芥黄工服 | 灰白 · **针织毛线帽**（直筒，占"高"这条轴） |
| `Character-Base.png` | 阿梅（裁缝） | *（无衣服，原样）* | 栗棕 · **蓬松波浪短发**（顶上一个缺口） |

> ⚠️ **`Soldier-Red` 现在穿草绿。** 名字是 `personas.json` 的外键，改名要连着改数据，两棒都不动数据，
> 所以名字保留，看外观请查上表。
>
> ⚠️ **`Character-Base.png` 从 F2 起进了本目录**（E3 时它不在）。它**同时是 `WorldView.FALLBACK_SPRITE`**
> ——玩家没有 sprite 时走的回退皮。所以**给阿梅加头发 = 玩家的回退皮也长了同一头头发**。
> 这不是回归（改之前两者本来就共用同一张图），但它是一条真实的耦合：
> **删掉 `pro/Character-Base.png` 就同时退回阿梅与玩家的旧样子**，两者不能分开调。

## 重跑

```bash
python tools/coif_characters.py              # 从 library/ 全量重建本目录（含 deprop 一步）
python tools/coif_characters.py --probe      # 只跑断言，不写文件
python tools/coif_characters.py --metrics    # 断言 + 剪影可分度表 + 脸的皮肤边界表
python tools/coif_characters.py --preview D  # 改前/改后 12 帧对照图写到目录 D（R10 眼验用）

python tools/deprop_characters.py --probe    # E3 的三条自检（不含 F2 的头）
```

**⚠️ `deprop_characters.py --probe` 的自检 B（"产物剪影逐像素等于 `Character-Base`"）
只对它自己的中间产物成立，对本目录的最终产物【故意不成立】**——F2 的全部工作就是让它不成立。
`coif_characters.py` 的自检 A 守的是反过来那一半：每张表都必须真的有 alpha 外扩。

脚本是**幂等**的：连跑两次，10 个文件逐字节相同。
