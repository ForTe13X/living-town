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

## ★★★ APK 已产出（2026-07-04，headless 一把过）

`build/out/livingtown.apk`（**117.7 MB**，arm64-v8a，签名 `CN=Android Debug`，package `com.forte13x.livingtown`，label「小镇有灵 Living Town」，minSdk 24 / targetSdk 35）。`lib/arm64-v8a/` 含 `libgodot_android.so`(引擎) + **`libnobodywho-godot-aarch64-linux-android-release.so`(端上 LLM)** + `libc++_shared.so`。**纯 headless CLI 产出，无需 GUI。**

**制胜配方（那个空配置错误的真凶 + 全部修法，按序）**：
1. **`project.godot` 开 `[rendering] textures/vram_compression/import_etc2_astc=true`**——**这才是空错误的真凶**：`has_valid_project_configuration()`（export_plugin.cpp）未开此项时把 valid 置 false 却【不落任何错误文字】（Godot **issue #89910**，4.7 才补文字，4.6.2 留空）。安卓导出必需。开后**删 `game/.godot/imported` 强制重导**（`--headless --editor --quit-after 2000`）生成 ETC2/ASTC 纹理变体。
2. **`addons/nobodywho/nobodywho.gdextension` 设 `reloadable = false`**——`reloadable=true` 时 Godot 在 Windows 上把 dll 复制成 `~` 临时副本再加载、复制失败 → 另一路空错误/segfault（issue #107089 / #66231）。headless 不需热重载。
3. **装 `build-tools;35.0.1`**——Build Template `config.gradle` 写死 `buildTools '35.0.1'`；只装 34/35.0.0 会报"build tools 与 Target SDK 不匹配"。
4. **`use_gradle_build=true` + 装 Android Build Template**（GDExtension 原生库走自定义 gradle 构建；`--headless --editor --quit` 或从 export_templates 的 android_source.zip 解到 `game/android/build/`，`.build_version`="4.6.2.stable"）。
5. **导出**：`godot --headless --export-debug "Android" out.apk`（gradle 首跑 ~4-6 分钟拉依赖，**别用 2 分钟超时误判卡死**；保持 `package/signed=true`——关签名会 segfault）。

装机：`adb install -r build/out/livingtown.apk`。端上 LLM：把一个 gguf 侧载到 `user://model.gguf`（`adb push <model>.gguf /storage/emulated/0/Android/data/com.forte13x.livingtown/files/model.gguf`）；缺模型自动降 logic 地板，镇子照跑。**（引擎侧全绿；端上渲染/SLM 推理以你设备实测为准。）**

## ★★ 手机可用性升级（2026-07-05：应用内切后端 + MTP 放模型 + release 签名）

**都已 headless 验证：parse 绿、Main 场景 smoke 绿、12-seed S0 门 digest 与基线逐字节一致（确定性红线一寸没让）、对抗式评审（15 findings→13 refuted→1 真 bug 已修）。**

- **应用内 logic↔slm 切换**（手机无 CLI）：`AIBackend` 拆 `backend`(生效档，可被算力探测降级) / `backend_requested`(用户意图)，`decide()` 仅在**无在飞请求的安全点**才应用切换（否则旧后端异步回包会被新后端误解析）；右上角 `Button` 轮换（emulate_mouse_from_touch 默认开→点按即触发），状态栏诚实显示当前生效档（`🤖slm` / 切换排队 `🤖logic→slm…`）。持久化到 `user://settings.cfg`；**优先级 CLI --backend > settings.cfg > 默认 logic**；headless CI 走 `Sim.backend=null` 根本不经此路 → 确定性不受影响。**评审修的真 bug**：算力探测 `>8s` 自动降级 logic 时也要同步 `backend_requested`，否则运行期切换会立刻把降级撤销（慢机每决策空烧 12s）。
- **端上模型改走公共可 MTP 位置**（红魔 MTP 只暴露 `Documents`、不暴露 `Android/data/<pkg>`）：`_resolve_model_path()` 安卓按序找 `Documents/LivingTown/model.gguf` → `Documents/model.gguf` → `Download/model.gguf` → `user://model.gguf`(adb)。加 `MANAGE_EXTERNAL_STORAGE`（"所有文件访问"）权限——**用户需在 设置→应用→小镇有灵→权限→文件 里手动开一次**（此权限不能运行时弹窗授予）。boot 时 log 面板打印"模型✓就位/未找到 + 路径"给无控制台的手机反馈。
- **release 签名版**：`build/release.keystore`（alias `livingtown`，RSA-4096，PKCS12，100yr；**在 build/ 被 gitignore，密码不入库**）。`export_presets.cfg` 只填 `keystore/release` 路径 + user，密码走环境变量 `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`（Godot 4.6 支持，**免把密码提交进 git**）。`godot --headless --export-release "Android"` 产出 `livingtown-release.apk`（**111 MB，签名 `CN=Living Town, O=ForTe13X`**，非 debug 证书）。
- **手机显示**：`project.godot` 加 `window/stretch/mode=canvas_items` + `aspect=keep` + `handheld/orientation=landscape`（1280×768 桌面下是恒等变换→桌面/录屏行为不变，只在手机上等比放大 HUD）。
- **gradle 卡死教训**：`godot --export` 起的 gradle daemon(java) 会**继承后台任务的输出管道不放**→任务显示"永远在跑"（其实 APK 早在 ~2 分钟产出）。修法：`game/android/build/gradle.properties` 加 `org.gradle.daemon=false`（重建 ~36s 干净退出）。

**装机两法**（package 同名但签名不同的 debug/release **不能相互覆盖安装**，Android 报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE` → 先 `adb uninstall com.forte13x.livingtown` 再装另一个）：
- **release**：`adb install -r build/out/livingtown-release.apk`（或手机侧载）。
- 放模型（推荐免 adb）：把一个 gguf 用资源管理器拷到 `此电脑\手机\...\Documents\model.gguf` → 设置里给 app 开"所有文件访问" → 重开 app（log 面板应显示"✓就位"）。骁龙 8 Elite 推荐 `qwen2.5-3b-instruct-q4_k_m`(~2GB)。备选 adb：`adb push <gguf> /storage/emulated/0/Android/data/com.forte13x.livingtown/files/model.gguf`。

---

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
- **首帧 CJK 字体**：`Art.font()` 运行时喂 `assets/fonts/smiley-sans.ttf` 字节——安卓上路径/加载须实测（大概率 OK，同 headless）。
