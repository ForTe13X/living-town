# 128 · 真机测试就绪清单（当前 HEAD 构建可行性 + 触摸能力矩阵 + 复测协议）

> 本文**不是测试报告**——本轮真机不可达、构建被卡在一次性设置上，**没测成**。
> 它是把"要复测需要先解锁什么"钉清楚，并**订正 docs/111 被 Codex 点名的错**（把触摸未测项当成 keyboard-only）。
> 前置：docs/113 §四·4（真机门）、外审 Codex 2026-08-06（P4 + docs/111 触摸结论反证）、docs/111（旧 APK 07-30 的真机观察）。

## 〇、本轮结论（一句话）

**当前 HEAD（`8325e0e`）的 APK 既没构建成、也没上真机**——两处各卡在一次性设置上，都需要用户/GUI 介入。下面把**卡点**与**解锁步骤**钉清楚，让下次复测 turnkey。

## 一、构建可行性——实测边界（本会话亲跑）

| 组件 | 状态 | 证据 |
|---|---|---|
| Godot | ✅ `4.6.2.stable.official.71f334935` | `godot --version` |
| 导出模板（全局） | ✅ 装了 | `%APPDATA%/Godot/export_templates/4.6.2.stable/{android_debug,android_release}.apk`、`android_source.zip` |
| Java | ✅ `openjdk 17.0.19`（Adoptium） | `java -version` |
| 导出预设 | ✅ `Android`（`com.forte13x.livingtown` → `build/out/livingtown.apk`，arm64-v8a only） | `game/export_presets.cfg` |
| `--import` | ✅ 干净（0 脚本/解析错） | `godot --headless --path game --import` exit 0 |
| **导出** | ❌ **卡住** | 见下 |

**卡点（导出报的）**：`未在项目中安装 Android 构建模板`。根因：预设 **`gradle_build/use_gradle_build=true`**（项目**刻意**走 gradle 定制构建——大概率为 nobodywho GDExtension 的 arm64 原生库），需要 `res://android/build/`（editor「安装 Android 构建模板」装的，**已 gitignore**，本工作树没有），且 gradle 还需 **Android SDK**（本会话未验证在场）。附带噪声：`nobodywho.gdextension` 缺库（同 CI 里那条，非导出根因）。

**解锁步骤（需 editor GUI / 用户）**：
1. Godot 编辑器打开 `game/`，**项目 → 安装 Android 构建模板**（生成 `game/android/build/`）。
2. 编辑器设置里配好 **Android SDK / JDK 路径**（gradle 要）。
3. 之后可 headless 复现：`godot --headless --path game --export-debug "Android" <out>/livingtown.apk`。
4. 记 **APK SHA256 + versionCode + 内嵌 git SHA**（Codex P4 要的 provenance），写进本文 §四。

> ⚠️ 我**没有**改 `export_presets.cfg` 去关 gradle 换预建模板——那会动项目配置、且预建模板可能不含 nobodywho 原生库导致 app 跑不全。走 gradle 是项目的选择，尊重它。

## 二、真机可达性——实测边界

- **adb 在场**（`platform-tools 1.0.41`），**但 `adb devices` 为空**。
- 用户早前给的无线调试信息 `Pair(449874, 192.168.1.127:45557)`：`adb connect 192.168.1.127:45557`（及 :5555/:37000/:40000）**全部 `10061 目标积极拒绝`** ⇒ **端口已变/配对窗口已关，信息过期**。
- 无线调试**每次开关端口都变**，配对码**时效**（手机上「配对」对话框关掉即失效）。

**解锁步骤（需用户在手机上操作）**：手机 → 开发者选项 → 无线调试 → 开；「使用配对码配对设备」给一组**新的** `ip:配对port + 6位码`，**再**回主屏读**连接** `ip:连接port`。把**连接** ip:port 发我 ⇒ `adb connect` 即通。（配对 port ≠ 连接 port，两个都要。）

## 三、触摸能力矩阵——订正 docs/111（Codex 反证：触摸未测 ≠ keyboard-only）

docs/111 把没测的项直接判成"键盘专属"。**源码明确给了触摸等价入口**（`Main.gd` 实读 + 正午截图肉眼可见），且有 `player_touch_test` 门（`ci.sh` 第 5 步）守"名片档指出详情在哪"。下次真机按**四列**逐项测，别拿"底栏文字可点"当"功能存在"：

| 能力 | 桌面键 | 触摸等价入口（源码坐标） | exact-build 实测 |
|---|---|---|---|
| 设置面板（NPC数/速度/后端） | `O` | ⚙/「设」按钮（`Main.gd:106` `_settings_panel`，截图左上「设」） | ✅**当前 HEAD 实测**：点「设」→开设置面板（存档/读档/玩家模式/后端/SLM/NPC/速度/Dev 全在，全触摸可达） |
| 详情/完整卷宗 | `V` | 「详情」钮（`Main.gd:51` 注释：**手机上唯一够得着的入口**，截图右上） | ✅**当前 HEAD 实测**：点它→切「收起」+开观察台 |
| 暂停 | `Space` | 设置面板速度栏「暂停」钮 | ✅**当前 HEAD 实测可达**：设置面板速度栏 暂停/1x/2x/4x/8x 皆触摸钮 |
| 后端切换 | （无 CLI） | 后端钮（`Main.gd:61` `_backend_btn`，截图右上「推理 logic」） | ⬜ 待测 |
| SLM 模型选择 | — | 设置面板 `_model_btn`（`Main.gd:116`） | ⬜ 待测 |
| 玩家模式 | — | 设置面板 `_player_btn`（`Main.gd:166`） | ⬜ 待测 |
| 纪事查看 | `J` | 可点的纪事摘要 | ⬜ 待测 |
| 存/读档 | `F5`/`F8` | 设置面板存/读档钮 | ✅**当前 HEAD round-trip 实测**：点「存档 F5」→`quicksave.dat` 2.67 MB；sim 自跑到第 239 天后点「读档 F8」→屏显`读档成功（第 126 天·tick 30232）`，日/季/事件/约会/冲突计数**全revert到存档态**（239→126、冬→春、事件 13623→7270）。⚠️只证 round-trip **功能通 + 可见聚合态回退**，**不证字段级逐字节存档正确性**（AF1 已证存档能悄悄丢一条 belief 而聚合不变=state_projection 要解决的） |
| 选居民 | 点选/`Tab` | 直接点居民 / `Tab` 轮换（截图底栏「点居民查看」） | ✅**当前 HEAD 实测**：Tab 选中阿丽→出完整卡（关系/冲突/故事弧/记忆） |
| 跟随（进室内） | `L` | 选中后跟随（切到住户所在 Space） | ✅**当前 HEAD 实测**：跟随阿丽→镜头进室内空间（AG3 纵切） |

⚠️ 旧 APK 是 **07-30** 的，**早于 Wave I 之后一大串改动（含 T3 的 HUD 修复）** ⇒ docs/111 的每条都要在**当前 HEAD 构建**上重测，别拿旧包截图代表当前 HEAD。

## 四、当前 HEAD APK provenance（✅ 已构建并上真机，2026-08-06）

**用户重开无线调试给了新凭据后，走 SDK-free 路构建成功、装机实测通过。**

| 项 | 值 |
|---|---|
| built from HEAD | `957929457bc99bdf8b6d3613687bc66f4153c31c`（=当时 trunk tip） |
| apk sha256 | `f9748e5cd2880cbc5ed6ea7e54188b15a2c820b95dc92818867f14edda67de37` |
| apk 大小 | ~31 MB；versionCode=1 versionName=1.0 minSdk=24 targetSdk=35 arm64-v8a |
| 设备 | NX789J（RedMagic，2688×1216=2.21:1），装机时间 2026-08-06 17:51 |
| 构建路（**绕开 gradle/SDK 缺失**） | 临时把预设 `use_gradle_build=true→false`（**未提交**）走**预建模板**；`keytool` 自建 debug keystore 放 `build/debug.keystore`（gitignore）；`godot --headless --path game --export-debug Android` exit 0、`Signed` |
| 非致命缺项 | nobodywho GDExtension 原生库缺（`libnobodywho-*-android-release.so` 不在仓）⇒ 未接模型后端；**默认 logic/CPU 后端照跑**（出货默认也是 CPU），故 sim/触摸/HUD/音频验证不受影响；无 app 图标（用默认） |
| 工具链 | Godot 4.6.2.stable；apksigner 来自 `build/android-sdk/build-tools/35.0.0`（仓内已有,非 ANDROID_HOME）；JDK 17 |

⚠️ 这是**测试构建**（预建模板 + 自建 debug key），**不等于出货 gradle 构建**（后者含 nobodywho 原生库、正式签名）。但对 sim/触摸/HUD/音频这些不依赖模型的验证，**足够代表当前 HEAD**。

## 六、当前 HEAD 真机实测结果（2026-08-06，SHA256 见 §四）

**首个 current-HEAD 真机验证**（此前 docs/111 全在 07-30 旧包上）：

1. ✅ **构建+装机+运行**：NX789J 上跑起来，town sim 实时推进（1→4 游戏天、事件 28→185、社会动态涌现：`铁牛 对 阿菲 渐渐积起了怨气`、`冲突 1(活1)`）。
2. ✅ **触摸可用**：点「详情」钮→切「收起」+开观察台（Codex 说 docs/111 误判 keyboard-only 的那个入口，实测是触摸入口）。
3. ✅ **音频实播**（比 docs/111 强）：`dumpsys audio` 显示 `com.forte13x.livingtown` 的 PlaybackClient `mIsActive=true`、streamType=3(MUSIC)——不是仅 `started`，是**在放**。⚠️仍未验的（Codex P4 要的）：音质/路由/音量、并发 focus 让不让路——需真人听感+并发实验，截图/dumpsys 证不了。
4. ✅ **AE1 被拒叙述修复在真机活着**：纪事实见 `阿丽 想找 阿菲 咬耳朵，对方没搭理`、`阿菲 想和 铁牛 聊聊看法，对方没接茬`——旧包 docs/111 那屏"被婉拒却讲成聊成了"的 bug 没了（档0/AE1 编号 118 落地在 HEAD）。
5. ✅ **第二轮补测（2026-08-06，同连接）**：点「设」→设置面板开（存档/读档/玩家模式/后端/SLM/NPC/速度/Dev 全触摸可达，SLM=无 gguf 确认无模型）；点「存档 F5」→写出 `quicksave.dat` 2.67 MB（124 天全态）=**存档触摸路通**。顺带见 sim 自跑 124 天的涌现：**小镇纪事 11/11 全达成**、**选举「扩建咖啡馆」通过 6:4**（镇治理/投票机制在跑）、冲突 137(活78)、地图上画关系/冲突连线。
6. ✅ **第三轮（2026-08-06，同连接）·存档 round-trip 通**：存于第 126 天（tick 30232）→ sim 自跑到第 239 天 → 点读档 → 屏显 `读档成功（第 126 天·tick 30232）`、日/季/事件/约会/冲突全 revert（239→126、冬→春）。⚠️首次点没中（日照跑 237→239 未 revert），第二次精准点才触发——**触摸命中要准**（Godot 单 surface 无 Android view 层，坐标全靠截图估）。⚠️**边界**：只证 round-trip 功能通 + 聚合态回退，**不证字段级存档正确性**（AF1 的 belief 静默丢失洞仍在，需 state_projection）。
7. ✅ **第四轮（2026-08-06，同连接）·室内 + 选居民 + 跟随全通**：注入 `keyevent 61`(Tab)→选中阿丽、`keyevent 40`(L)→跟随，**镜头切进室内空间**（工位/库房/家具/夜间室内暖光）=**AG3 纵切室内在真机上跑**。关键发现：**注入 keyevent 能到 Godot Android**（Tab/L 都生效）——不必只靠像素点，可脚本化。选居民卡也全出（关系账本 阿本亲100/老邓亲-89、冲突9段、**故事弧「手艺被苏琴 14幕」**=叙事 storylet 挂角色、近期记忆）。
8. ⬜ **仍未测**：多楼层 portal 上下楼在真机（本轮进的是单层工作区、没走楼梯到 2F）；HUD 2.21:1 逐项排版；音频主观质量/路由/并发 focus。留给下次。

⚠️ 诚实边界：这是**预建模板测试构建**（无 nobodywho、非出货 gradle 签名），代表 sim/触摸/HUD/音频不依赖模型的那部分；**出货门仍需正式 gradle 构建**（装 `res://android/build/` 模板 + SDK，见 §一解锁步骤）。

## 五、音频/HUD 复测要点（Codex P4，别过度外推）

docs/111 说"音频 state:started"被 Codex 判过度外推——`started` 不等于用户真听到、音质/路由/音量对。复测要：**实际听感回执**（录音或主观）、**并发 focus**（来电/前后台切换时让不让路，需并发实验）、**HUD 在 2688×1216(2.21:1) 真机比例**下的排版（`_relayout_hud`，`Main.gd:153`）。这些都**没有一条能只靠截图证**。
