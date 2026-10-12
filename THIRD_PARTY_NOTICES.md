# Third-party notices · 第三方组件与授权

本文件列出随本仓库分发（或打进 APK/发行包）的第三方素材与代码，及其授权与出处。
新增任何随包分发物时**必须**在此登记：名称 / 版本 / 出处 URL / 授权 / 校验和 / 用途。

> 红线 4（无版权风险）：仓库内一切随包分发物必须是 CC0 / 自绘 / 程序化生成 / 或明确允许嵌入再发行的许可。

## 字体

### 得意黑 Smiley Sans

| 项 | 值 |
|---|---|
| 版本 | v2.0.1（`Smiley Sans Oblique`, name[5]=`Version 2.0.1`） |
| 出处 | https://github.com/atelier-anchor/smiley-sans （release `v2.0.1`） |
| 授权 | **SIL Open Font License 1.1**（全文见 [`game/assets/fonts/LICENSE-SmileySans.txt`](game/assets/fonts/LICENSE-SmileySans.txt)） |
| 版权 | Copyright (c) 2022--2024, atelierAnchor <https://atelier-anchor.com> |
| 保留字体名 | **Reserved Font Name: `Smiley` / `得意黑`** |
| 仓库内路径 | `game/assets/fonts/smiley-sans.ttf`（2,629,764 bytes） |
| 发行 zip sha256 | `299c0be6c960ae37361762eca76f7d0cd516615435bb96c0d4b98a1e70178a07`（`smiley-sans-v2.0.1.zip`） |
| 用途 | 全部游戏内中文/UI 文本渲染（`Art.font()`） |

**OFL 合规要点（务必遵守）**

- 随包必须附带版权声明与 OFL 全文 → 已随字体同目录放置 `LICENSE-SmileySans.txt`，并在此登记。
- **保留字体名**：若**修改**字体（改字形/改内部名/子集化后改名等），**不得**继续使用 `Smiley` 或 `得意黑` 作为字体名。
  本项目**原样嵌入、不做修改** → 可继续沿用原名。（仅把**文件名**改为 `smiley-sans.ttf` 不构成修改，OFL 限制的是字体名而非文件名。）
- OFL 字体**不得单独售卖**；随游戏一起分发不受影响。

## 像素美术

- **Puny Characters / Puny World**（`game/assets/art/library/…`）：CC0，见各自目录下的 `LICENSE.txt`。
- 其余地形/装饰/物件/emote：项目自绘或**程序化生成**（`WorldView.gd` 内 `_draw_*`），无第三方权利。

## 运行时 / 引擎

- **Godot Engine 4.6.2** — MIT。
- Windows 3D 桥接发行包附带 Godot 4.6.2-stable 的 [MIT 全文](docs/town_bridge/licenses/GODOT_LICENSE.txt) 与 [第三方版权全文](docs/town_bridge/licenses/GODOT_COPYRIGHT.txt)。出处、原文校验和见 [来源记录](docs/town_bridge/licenses/PROVENANCE.json)。
- **NobodyWho**（`game/addons/nobodywho/`，llama.cpp GDExtension，端上 SLM 可选皮肤）— 见插件自带授权；**默认后端为 `logic` 地板，无模型也完整可玩**（红线 2）。
- 模型权重（`*.gguf`）**不入库**、不随包分发；由用户自行放置（见 `docs/18`）。

## 3D 小镇美术交付

- 建筑、地形、植物与家具由本项目程序化生成；原始来源与构建记录保存在独立 Blender 交付中，桥接包携带同一 GLB 的 SHA-256 绑定。
- **Kloofendal 48d Partly Cloudy (Pure Sky)** — Poly Haven, Greg Zaal / Jarod Guest，CC0 1.0。未修改的 2K HDRI 打包在 Blender 环境中；GLB 材质独立于该环境。来源与文件校验和见 `art/living_town/external_assets/polyhaven/PROVENANCE.json`。
- **Adobe Source Serif 4 Regular** — 未修改，SIL Open Font License 1.1，用于模型内招牌文字。字体 SHA-256：`e5a4ee6a3d87bb9024796be390c6771e2a0eb1883dae25effaf57ca01668e24b`；来源与许可见 `art/living_town/external_assets/fonts/PROVENANCE.json` 和同目录 `LICENSE.md`，发行包内保留副本。

## 历史遗留（已清除）

- ~~`game/assets/fonts/cjk.ttf`（SimHei，取自本机 Windows 字体）~~ —— **无可再发行证明，已于 R0-1 移除**，由上述得意黑（OFL-1.1）替换。
  这是 codex 评审 §R0-1 标记的**发行阻塞项**：它此前会随 `export_filter="all_resources"` 一起打进 APK。
