# 小镇有灵 · Living Town

一个可以成为居民、也可以静静观察的生活模拟小镇，提供 Blender 3D 复合小镇、滨海林地保护区与原像素地图。

居民会工作、吃饭、交朋友，也会记住承诺、传闻和矛盾。你可以选择一位居民，走进咖啡馆和家里，参与他们的日常；也可以打开观察台，看看一件小事怎样影响关系、经济和公共生活。

[English](README_EN.md) · [设计与开发记录](docs/README.md)

[![精修小镇实机导览：街区、分层室内、保护区与居民生活](docs/media/town3d-walkthrough.gif)](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Walkthrough.mp4)

30 秒无声 GIF 精选；点击预览观看带 Edge TTS 配音与字幕的 **14 分钟实机导览**。保留完整游戏画面，字幕位于额外的下方色带。

[完整导览（MP4，14:00）](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Walkthrough.mp4) · [章节、下载与录制证据](docs/town_walkthrough/README.md) · [原像素版演示存档](docs/249-gameplay-tour.md)

**Blender 3D 小镇**：当前空间配置包含 151 栋建筑、263 层室内、1,582 个房间分区、2,089 组家具设施与 784 个新增合法交互绑定，使用 11 个城镇 GLB 分块和 25 个带骨骼角色模型；普通运行实测覆盖 62 位居民。进入区域仍遵循居民、门和楼层权限。
[14 分钟配音导览、章节与下载](docs/town_walkthrough/README.md) · [运行与空间契约](docs/town_bridge/README.md)。
大型运行素材通过带校验和的 [Release 清单](docs/town_walkthrough/ASSET_RELEASE.md) 分发。Windows 使用 `./tools/run-town3d.ps1`；原像素地图使用 `-Legacy`。五个模型/输入 ZIP、可选 Blender 工作文件及本版录屏均有实际校验记录。**发布状态：本版文件以本地校验和绑定，公共回读记录见证据索引**。

[![复合城镇扩展：五个街区、室内与地形](docs/media/territory-expansion-tour.gif)](https://github.com/ForTe13X/living-town/releases/download/town-territory-2026-10-20/expanded_town_architectural_tour.mp4)

**2026-10-20 历史资产导览**：六分钟实际 Godot 导入画面，带 Edge TTS 配音与字幕；GIF 为 20 秒节选。这段旧素材保留作扩展规划与模型版本记录，不是上方新版居民导览的录屏。

## 最近更新

- 重做 3D 生活模式 HUD：保留五项需求的紧凑居民卡、顶部时钟与速度控制，近况和愿望可分别展开；两种窗口尺寸的实际输入与画面检查已通过。[HUD 与画面检查方法](docs/town_bridge/HUD_REVIEW.md)。
- 新增可复用的[素材精修工具箱](docs/ASSET_TOOLBOX.md)：用 JSON 配方串联原生模型、PBR/UV 检查、导出、Godot 与录屏证据；保留每次迭代的来源和结果，技术通过与美术评审分别记录。
- 优化房间索引与门户路线复用，保留实时权限检查、原算法回退与存档语义；62 位居民的 90 tick 对照保持状态和事件链一致。当前普通 Mobile/Vulkan 运行在 1280×768 下，室外 1× 约 30.1 FPS、4× 约 24.2 FPS，仍有卡顿空间；18 FPS 只是录屏设置。[性能实测与限制](docs/town_bridge/PERFORMANCE.md)。
- 实际 Main 已命中缓存004：保留 2,880 组、19,197 个源网格代理及完整验证。同步初始化由 80.3 秒降至 66.3 秒，首个完成绘制由 95.6 秒降至 81.7 秒；不含进程启动、autoload 解析与首次导入，加载仍然较长。[当前运行与证据](docs/town_bridge/README.md#current-performance-and-evidence)。
- 交付可选 Blender 外景工作文件，实测已打开视图重绘中位数 77.4 ms、材质预览约 169 ms；这是重绘操作耗时，不是导航 FPS。完整室内 Scene 可切回，导出仍使用独立 canonical 文件。[原生文件、GLB、角色与输入包](docs/town_walkthrough/ASSET_RELEASE.md#verified-authoring-and-interchange-deliveries)。

- 新增可实际生成的复合城镇扩展：五个相连街区、81 栋新建筑、153 层与 929 个带家具的房间分区；结合地形道路、细叶植被、CC0 PBR 与实际运行的 Infinigen 花盆工厂，输出 Blender 和分区 GLB。[规划、模型、导览与验证](docs/TERRITORY_EXPANSION.md)。

- 精修咖啡馆家具、立面和景观材质，加入细花瓣绣球、地表 PBR 与修正后的针叶图集；保留每次来源、原生保存与定向导出校验。[样区与近景](docs/CONCEPT_REFINEMENT_PILOT.md)；定向美术评审按当前图像单独记录。
- 当前 151 栋版本纳入林地保护区与露营服务区，包括拖车室内、便利店、纪念品店、浴室、公厕、餐车、山径、桥梁和跑步环线。[保护区资产记录](docs/RESERVE_EDITION.md)。
- 完整空间配置接入原有居民生活模式；实际导览区分真实居民行动与标注的建筑、地形巡览；抽样画面评审与音频技术检查已记录。[当前验证范围](docs/town_bridge/README.md#rebuild-and-evidence-boundaries)。
- 按滨海街区蓝图重建道路、庭院通道、树带和花园，加入更细致的 PixelLab 建筑与景观素材。
- 区分连排住宅、商店、公共建筑和工坊的立面；修正建筑朝向，让入口与街道对应。
- 增加不规则室内空间、房间分隔和可通行楼梯；相机平滑跟随角色进出建筑。
- 市政政策、选举反馈与合作银行已有可查看的影响回执。

## 在小镇里

- **过日子**：选择居民，照顾需求，完成愿望，工作和休息。
- **建立关系**：聊天、送礼、邀请、传闻、冲突与道歉会留下记录。
- **观察变化**：查看居民状态、小镇故事、交易账本和公共政策。
- **自由探索**：逛市场、图书馆、浴室、工坊、住宅和海边；昼夜与天气改变氛围。

这是持续开发中的可玩原型。空间配置保留公共与私人区域的权限；装饰物不会自动获得游戏功能。录屏使用 logic 后端与现有 Main/LifeMode 输入完成居民移动、楼梯、设施和存读档交互；建筑与地形巡览只移动相机并明确标注。抽样画面评审通过限定范围，音频已完成全长解码与电平检查，未记录人工听音。部分晚间画面较暗、房间和景观摆设较疏；返程的需求条出现耗尽，不应解读成生活平衡或完整概念图质量验收。导览展示选定行动与地点，不能代替全镇美术、全部机制或普通帧率的验收。

## 开始游玩

使用 **Godot 4.6.2**。从仓库根目录用启动器按本版清单获取缺失素材并启动；已有完整本地包可用 `./tools/run-town3d.ps1 -Local` 离线运行。直接在编辑器按 **F5** 前先完成素材校验与首次导入。下载身份与公共回读记录见[发布说明](docs/town_walkthrough/ASSET_RELEASE.md)。

```powershell
git clone https://github.com/ForTe13X/living-town.git
cd living-town
./tools/run-town3d.ps1
```

默认生活模式会让你选择居民。**无需大语言模型或 API key** 即可游玩；本地 LLM / NobodyWho SLM 是可选后端，权重与扩展二进制不随仓库分发。安装与降级逻辑见 [LLM 集成](docs/03-LLM集成架构.md)。

| 操作 | 按键 |
| --- | --- |
| 行走 | WASD / 方向键 / 点击地面 |
| 互动、切换目标 | E / Tab |
| 取消、关系面板 | Q / R |
| 暂停、速度 | 空格 / 1–3 |
| 展开近况、愿望 | H / Shift+H |
| 自主行动、换人 | F / C |
| 存档、读档 | F5 / F8（游戏窗口内） |

## 开发

`game/` 是 Godot 工程，`tools/` 包含审计、测试和录制工具，`docs/` 保留设计与实验记录。仿真负责裁决，模型只在合法候选与表达层工作。

```bash
python tools/lint_data.py
python tools/audit_coastal_plan.py
python tools/audit_neighborhoods.py
bash tools/ci.sh
```

Windows 本地 Godot 检查通过 `tools/run-godot-supervised.ps1` 运行，录制方法见 [当前录制方法](docs/town_walkthrough/RECORDING.md)。欢迎提交可复现的问题、玩法反馈和 PR。

代码采用 MIT License。美术包含 CC0 衍生素材与 PixelLab 生成素材；来源见 [素材说明](docs/09-美术资产与版权.md)、[滨海素材记录](docs/246-coastal-circulation-pixellab-camera.md) 和 [朝向修正](docs/248-blueprint-frontages.md)。
