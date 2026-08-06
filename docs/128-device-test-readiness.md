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
| 设置面板（NPC数/速度/后端） | `O` | ⚙/「设」按钮（`Main.gd:106` `_settings_panel`，截图左上「设」） | ⬜ 待测 |
| 详情/完整卷宗 | `V` | 「详情」钮（`Main.gd:51` 注释：**手机上唯一够得着的入口**，截图右上） | ⬜ 待测 |
| 暂停 | `Space` | 设置面板速度栏「暂停」钮 | ⬜ 待测 |
| 后端切换 | （无 CLI） | 后端钮（`Main.gd:61` `_backend_btn`，截图右上「推理 logic」） | ⬜ 待测 |
| SLM 模型选择 | — | 设置面板 `_model_btn`（`Main.gd:116`） | ⬜ 待测 |
| 玩家模式 | — | 设置面板 `_player_btn`（`Main.gd:166`） | ⬜ 待测 |
| 纪事查看 | `J` | 可点的纪事摘要 | ⬜ 待测 |
| 存/读档 | `F5`/`F8` | 设置面板存/读档钮 | ⬜ 待测 |
| 选居民 | 点选 | 直接点居民（截图底栏「点居民查看」） | ✅ 旧 APK 实测可用（docs/111） |

⚠️ 旧 APK 是 **07-30** 的，**早于 Wave I 之后一大串改动（含 T3 的 HUD 修复）** ⇒ docs/111 的每条都要在**当前 HEAD 构建**上重测，别拿旧包截图代表当前 HEAD。

## 四、当前 HEAD APK provenance（构建成后填）

<!-- 装好 gradle 模板、导出成功后填：apk_sha256 / versionCode / 内嵌 git SHA（应=8325e0e 或更新）/ 导出命令 / 工具链版本 -->
（本轮未构建成——见 §一卡点。）

## 五、音频/HUD 复测要点（Codex P4，别过度外推）

docs/111 说"音频 state:started"被 Codex 判过度外推——`started` 不等于用户真听到、音质/路由/音量对。复测要：**实际听感回执**（录音或主观）、**并发 focus**（来电/前后台切换时让不让路，需并发实验）、**HUD 在 2688×1216(2.21:1) 真机比例**下的排版（`_relayout_hud`，`Main.gd:153`）。这些都**没有一条能只靠截图证**。
