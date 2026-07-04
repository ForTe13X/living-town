# docs/18 · Android APK 构建（骁龙 8 Elite / arm64 + 端上 SLM）

> 目标：给自有设备（Red Magic·骁龙 8 Elite·24GB）出一份带**端上 LLM**的 APK。
> 现状：项目已接好 arm64 安卓 SLM 库 + 安卓专属模型路径；工具链 + 导出 + 装机验证按下述步骤。
> **诚实边界**：构建环境无安卓真机，**端上渲染/SLM 推理/模型加载无法在此验证**，最终以你设备实测为准；本文把所有可控项都锁死，剩下就是装机跑一次。

## 已就绪（已提交）
- **arm64 安卓 NobodyWho 库**：`addons/nobodywho/libnobodywho-godot-aarch64-linux-android-release.so`（v9.4.0 官方，38MB；**大二进制被 .gitignore 排除，从 `nobodywho-godot-v9.4.0` release 的 zip 里取那个文件放进 addons/nobodywho/**），`.gdextension` 已加 `android.{debug,release}.arm64` 条目（已提交）。类名与旧版一致（NobodyWhoModel/NobodyWhoChat）→ `AIBackend` 无需改 API。
- **安卓模型路径**：`AIBackend._resolve_model_path()`——安卓上不读 `res://`（PCK 内不可 mmap），改读 `user://model.gguf`（安卓映射到应用外部 files 目录=真实路径可 mmap）；**缺模型→加载失败→算力探针超时→自动降确定性 logic**（镇子照常跑，只是没声音）。
- **渲染**：`GL Compatibility`（移动端友好）。
- **确定性**：跨平台审计通过（docs/15 §1.5，零 transcendental、整数哈希 + PCG32 + IEEE 基本运算）——同存档跨设备逐字节同回放【架构上成立】，待真机对拍黄金 digest 坐实。

## 工具链（一次性，约 3GB）
1. **JDK 17**（已装 Temurin 17）。
2. **Android SDK**：cmdline-tools → `sdkmanager "platform-tools" "build-tools;34.0.0" "platforms;android-34"`。
3. **Godot 4.6.2 导出模板**（.tpz）→ 解压到 `%APPDATA%\Godot\export_templates\4.6.2.stable\`。
4. **debug keystore**：`keytool -genkeypair -keystore debug.keystore -storepass android -alias androiddebugkey -keypass android -dname "CN=Android Debug" -keyalg RSA -validity 10000`。

`tools/build_android.ps1` 把 2–4 + 导出串起来（设 `ANDROID_HOME`/`JAVA_HOME`、写 editor settings 的 SDK/keystore 路径、跑 `godot --headless --export-debug "Android"`）。

## 现状（2026-07-04 本次做到哪）
**工具链已由我装好并验证齐全**：JDK 17（Temurin）、Android SDK（platform-tools + build-tools;34.0.0 + platforms;android-34，adb/apksigner 都在）、Godot 4.6.2 导出模板、debug keystore、editor settings 里 SDK/Java 路径已填。arm64 安卓 SLM 库 + gdextension 条目 + 安卓模型路径都接好了，`Android` 导出预设也写好了（`game/export_presets.cfg`，arm64-only、排除桌面库）。

**★ 诊断突破（2026-07-04 二轮）**：那个"空配置错误"的根因找到了——**Android Build Template 要的是 build-tools `35.0.1`**（`config.gradle` 写死；我先前只装了 34/35.0.0，故 Godot 报"build tools 与 Target SDK 不匹配"→ 校验静默失败）。**装上 `build-tools;35.0.1` 后配置校验就过了**。但紧接着 **headless 导出【驱动】自己 segfault（0xC0000005，gradle 还没起就崩，C++ backtrace 无符号）**——这是 Godot headless 安卓导出的 bug，本环境修不了。**好消息：GUI 编辑器导出走的是另一条不崩的路，且配置这道坎已被我扫平（35.0.1 + Build Template 都装好了），所以你在编辑器里导出大概率一把过。** 另：`godot --headless --export-pack "Android" game.pck` 【能成】（产出了 6.5MB 的 game.pck），故最坏情况可拿这个 pck + Build Template 的 gradlew 手动组 APK（绕开崩溃的导出驱动）。

**（旧记录）headless CLI 导出曾卡死在空配置错误**：`godot --headless --export-debug "Android"` 反复报一个**空的**「配置错误」（"Cannot export project with preset Android due to configuration errors:" 后面**没有任何具体行**）。我把能试的都试遍了，全是同一个空错误：填好 SDK/Java 路径、keystore 就位、apksigner/adb 齐全、**去掉 nobodywho 扩展**、**关签名（还 segfault）**、**装了 Android Build Template + `use_gradle_build=true`**、**补装 SDK 35 + build-tools 35**（消掉了"target SDK 不匹配"的告警但错误依旧）。结论：这是 Godot **headless** 安卓导出的坑，那个空错误只有 **GUI 编辑器的导出对话框**才会把真正缺的校验项显出来。本环境无 GUI → **这一步得在你机器的 Godot 编辑器里完成**（工具链 + 预设 + 扩展 + 模型路径我都铺好了，就差 GUI 点一下）。预设已设 `use_gradle_build=true`、Android Build Template 也在（`game/android/`，被 gitignore，编辑器会按需重装）。

## 构建（在你机器的 Godot 4.6.2 编辑器 GUI 里）
1. 用 Godot 4.6.2 打开 `game/` 工程。
2. **项目 → 导出**：`Android` 预设已在（我写好的）。编辑器会自动校验 + 提示缺什么（大概率就是**装 Android Build Template**：点导出对话框里的「Install Android Build Template」，或菜单 项目→安装 Android 生成模板——这一步 headless 干不了、GUI 一键搞定）。若提示 SDK 路径，编辑器设置里指到 `build/android-sdk`（我已填过一次，可能需你确认）。
3. **导出项目** → 出 `livingtown.apk`（arm64-v8a；GDExtension 的 arm64 .so 会进 `lib/arm64-v8a/`；桌面 .dll/.so 被 exclude_filter 排除）。

> 排查提示：那个"空配置错误"多半是 Godot 4.6 安卓导出要求 **Use Gradle Build**（自定义安卓生成）来打 GDExtension 原生库——GUI 装了 Android Build Template 后把预设的 `use_gradle_build` 勾上即可（headless 装模板不便，故留 GUI）。首次 gradle 会联网拉依赖。

## 装机 + 端上模型（你的设备）
1. **装 APK**：`adb install -r build/out/livingtown.apk`（或手机侧载）。
2. **放模型**：端上 SLM 需要一个 GGUF。推荐骁龙 8 Elite 上跑 **qwen2.5-3b-instruct-q4_k_m.gguf**（~2GB，24GB 内存绰绰有余；更轻可用 1.5B）。
   `adb push qwen2.5-3b-instruct-q4_k_m.gguf /storage/emulated/0/Android/data/com.forte13x.livingtown/files/model.gguf`
   （即 `user://model.gguf`。装 APK 后该 files 目录才存在。）
3. **跑**：默认 `--backend logic`（纯确定性，先确认镇子能跑/能看/能点）；要端上 LLM 用带 `--backend slm` 的入口（或加个设置项切换——见"待办"）。GGUF 在位 → 算力探针测一发 → 够快就有声，太慢自动降 logic。

## 待办 / 风险（真机实测才知）
- **GDExtension arm64 .so 是否被标准导出正确打进 APK**：Godot 4.x 应自动从 `.gdextension` 收 arm64 .so 进 `lib/arm64-v8a/`（`use_gradle_build=false`，无需 NDK）。若加载失败 → 改 `use_gradle_build=true` + 装 Android Build Template（+ NDK）重试。
- **端上切 slm 后端的入口**：当前窗口构建默认 logic；手机上想开 LLM 需一个 UI 开关或改默认（小改，装机确认 logic 能跑后再加）。
- **存储/权限**：用 `user://`（应用外部 files 目录）免运行时存储权限；若改走 `/sdcard/Download` 则需 `MANAGE_EXTERNAL_STORAGE`。
- **触控**：镇子自主运行 + 点选居民（tap=click）即观察台可用；玩家 WASD/快捷键在手机上无键盘（观察模式已足够；触控玩法后续）。
- **首帧 CJK 字体**：`Art.font()` 运行时喂 `assets/fonts/cjk.ttf` 字节——安卓上路径/加载须实测（大概率 OK，同 headless）。
