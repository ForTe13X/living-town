# `pro/` — 角色去道具 pass 的产物（Wave E · E3）

这里的 9 张 PNG 是对 CC0 素材包 `puny-characters` 的**改绘衍生**，不是新素材、不是生成图。
`Art.gd:73-78` 的三级回退第一级就是本目录（`pro/<name>.png` > `library/.../<name>.png`），
所以它们**不需要任何代码改动**即生效，删掉本目录就逐字节回到原始奇幻外观。

## 源与许可（红线 #4）

| | |
|---|---|
| 源 | `../library/puny-characters/Puny-Characters/*.png` |
| 源许可 | **CC0**（作者 Shade，见 [`../library/puny-characters/LICENSE.txt`](../library/puny-characters/LICENSE.txt)，条目在 [`../../../../tools/assets_catalog.json`](../../../../tools/assets_catalog.json)） |
| 本目录产物 | CC0 允许修改 ⇒ 仍是 CC0 / 自绘衍生 |
| 生成图参与度 | **零**。依 docs/43 §二-R2，AI 出图只能当情绪板，绝不进精灵帧 |

## 改了什么

裁决在 docs/44 §一：角色收向"现代日常小镇居民"，淘汰尖帽/法杖/弓箭/盔甲。
产出脚本 [`../../../../tools/deprop_characters.py`](../../../../tools/deprop_characters.py)，
**只做两件事：alpha 掩膜 + 查表换色。不缩放、不插值、不新增任何一个像素位置。**

1. **去道具**＝把 `Character-Base.png` 的 alpha 当掩膜。
   实测：它是其余 9 张表**全部 192 帧**的严格子集（`base AND NOT other` 恒为 0 像素）——
   这个包是「一具共用身体 + 在身体**之外**叠画的装束」。于是一次掩膜就整块去掉
   尖顶兜帽、羽毛、牛角、盔缨、披肩，以及攻击行里的法杖/弓/剑；
   而**身体剪影按构造逐字节等于 `Character-Base`**，轮廓不可能被改糊。
2. **换色**＝去掉掩膜后仍留在剪影内的道具残根（Mage/Archer 前额金属搭扣、Warrior 角根、Soldier 缨根），
   并把 Warrior/Soldier 的**盔甲灰阶换成布料色阶**（docs/44 §一 原话「盔甲改围裙/工作服」）。
   布料色阶保留盔甲灰阶的**明度剖面**，只换色相/饱和度 ⇒ 明暗结构逐档不变。

## 为什么必须换衣服颜色，而不是只做掩膜

掩膜后逐像素比对（192 帧全表）：

```
Soldier-Blue vs Soldier-Red      原 3898 px 不同 → 掩膜后   91
Soldier-Blue vs Soldier-Yellow   原 3880 px 不同 → 掩膜后   73
Warrior-Blue vs Warrior-Red      原 1544 px 不同 → 掩膜后  423
```

三个 Soldier 的**全部身份就是那撮盔缨**，两个 Warrior 的**全部身份就是那对角**，且都长在剪影之外。
只做掩膜 ⇒ **4 个居民（Soldier-Yellow×2 + Blue + Red）变成同一个灰人**。
把身份搬到衣服上之后，同族两两差 14286-14477 px。

## 逐张对照

| 文件 | 谁在用（`data/personas.json`） | 去掉了 | 现在是 |
|---|---|---|---|
| `Mage-Red.png` | 阿丽 | 尖顶兜帽 + 披肩 + 前额搭扣 | 深红连帽便服（长袍色阶留用） |
| `Mage-Cyan.png` | 可可 | 同上 | 青绿连帽便服 |
| `Archer-Green.png` | 小薇 | 羽饰 + 披肩 + 前额搭扣 | 橄榄绿连帽便服 |
| `Archer-Purple.png` | 阿菲、苏琴 | 同上 | 紫色连帽便服 |
| `Warrior-Blue.png` | 阿本 | 牛角 + 护肩 + 盔甲 | 靛蓝工装 |
| `Warrior-Red.png` | 阿林 | 同上 | 赭褐皮围裙 |
| `Soldier-Blue.png` | 老海 | 盔缨 + 盔甲 | 藕紫衬衫 |
| `Soldier-Red.png` | 沈书 | 同上 | 草绿工服 |
| `Soldier-Yellow.png` | 老邓、铁牛 | 同上 | 芥黄工服 |

`Character-Base.png` **不在本目录**：它本来就没有职业道具，原样走 `library/`。
阿梅用它，`WorldView.FALLBACK_SPRITE` 的玩家回退皮也用它，两条路都不受本 pass 影响。

> ⚠️ **文件名与外观已经对不上了**（`Soldier-Red` 现在穿草绿）。名字是 `personas.json` 的外键，
> 改名要连着改数据，本棒不动数据，所以留着。看外观请查上表。

## 重跑

```bash
python tools/deprop_characters.py            # 重新生成本目录
python tools/deprop_characters.py --probe    # 只跑三条自检断言，不写文件
```

自检 A：`Character-Base` 剪影是 9 张表的严格子集；
自检 B：产物剪影逐像素等于 `Character-Base`；
自检 C：同族之间差 > 3000 px（身份没被掩膜吃掉）。
