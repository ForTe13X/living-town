# docs/191 · 端上推理换道：`local` 档 = APK 自带 llama.cpp 服务

> 状态：**已实现 + 桌面 E2E 通过 + 真机微基准已测**；真机游戏内 E2E 见 §5。
> 前情：[docs/34](34-slm-device-hang-leak.md)（NobodyWho 真机泄漏/挂死）、[docs/22](22-npu-decision-path.md)/[docs/23](23-hybrid-inference-vision.md)（NPU/GPU 路判断）。

## 1. 结论先行

- **旧路已死**：life 包里 `libnobodywho-…-android-release.so` 是 **0 字节**（本机 checkout 没有该库，docs/190 §102 已记）⇒ 手机上 slm 档根本起不来；更早能跑时（7 月装机日志）真机决策 **3–28 s/发**。
- **新路**：自编 llama.cpp `llama-server`（i8mm/dotprod、Q4_0 在线重排、flash-attn、前缀 KV 复用、决策 GBNF），以 `lib/arm64-v8a/libllamad.so` 打进 APK，游戏起成常驻子进程，`AIBackend` 新 `local` 档经 127.0.0.1 HTTP 调用（与 `llm` 档共用传输/解析）。
- **旋钮都在我们手里**，且推理崩/泄漏只死子进程，不拖垮游戏（docs/34 那类原生泄漏被进程边界封顶）。

## 2. 为什么是子进程而不是 GDExtension

| 选项 | 取舍 |
|---|---|
| 继续 NobodyWho | 预编译黑盒（线程/量化重排/flash-attn/前缀缓存都不可控），每发 `reset_context` 全量重 prefill；安卓库本机缺失 |
| 自写 C++ GDExtension | 进程内、要维护 godot-cpp 绑定与 ABI；崩溃带走游戏 |
| **llama-server 子进程（选）** | 零新绑定：复用已有 `llm` 档 HTTP 路；上游每次升级只需重编一个文件；进程隔离 |

安卓硬约束：targetSdk≥29 禁止 exec 应用数据目录里的文件（W^X）；唯一合法可执行位置是 APK 解出的 `nativeLibraryDir`。
⇒ 可执行文件以 `lib*.so` 名走 jniLibs，导出预设 `gradle_build/compress_native_libraries=true`（legacy packaging，系统才会把它解到磁盘）。
Godot 4.6 `OS_Android::create_process` 对非 `ANDROID_EXEC_PATH` 路径直落 `OS_Unix` 的 fork/exec（源码核实）；`nativeLibraryDir` 从 `/proc/self/maps` 里 `libgodot_android.so` 的目录取。

## 3. 真机测量（NX789J / SM8750，Qwen2.5 Instruct，同一 llama.cpp 790cf51 build）

**方法纪律（踩过的坑，别再踩）**：
- 熄屏 doze 会把 CPU 钳在 ~1 GHz ⇒ 数字慢 10×。设备端跑 `input keyevent 224` 保活循环。
- 连续跑几分钟就热降频（同配置可掉一半）⇒ 每配置间冷却 60–75 s；相对比较只在相邻、同热态内做。
- 主机 adb daemon 会被另一份 adb（Godot 用的 SDK platform-tools vs winget 版）反复重启 ⇒ `adb forward` 会断；基准改走 LAN 直连。
  LAN（Wi-Fi 省电）给每发加 ~2 s 传输延迟，游戏内是回环、没有这段 ⇒ **下表报服务端时间（prefill_ms + gen_ms）**。

### 3.1 微基准（llama-bench，t/s，热态，8 线程除注明）

| 模型/量化 | fa | pp256 | tg32 |
|---|---|---|---|
| 1.5B Q4_K_M（≈旧路同款 gguf） | off | 159 | 40 |
| 1.5B Q4_0（i8mm 重排） | off | 208 | 42 |
| 0.5B Q4_0 | off | 584 | 103 |
| 0.5B Q8_0 | on | 654 | 77 |

冷机单发：1.5B Q4_K_M pp256 277 / tg 50；Q4_0+fa pp256 257（冷热差比配置差还大 ⇒ 热管理是一等公民）。
KleidiAI 构建对 Q4_0 反而更慢（213 vs 257）⇒ 不用。6 vs 8 线程：单跑时 8 线程 +25–30% prefill，但游戏里主线程+渲染线程要核 ⇒ 默认 6（§4）。

### 3.2 真实工作负载（游戏同款 prompt，服务端时间，中位，热态，冷却 60–75 s 后逐配置跑）

`decide10/26` = 10/26 个候选的闭集选号（GBNF 钉成 1 个字母），`approaches` = 生活模式「说法」（≤120 token 生成）。

| 配置 | decide10 prefill | decide26 prefill | approaches prefill | approaches decode |
|---|---|---|---|---|
| **A 基线**：1.5B Q4_K_M、8 线程、无 fa、无前缀缓存 | 1486 ms（184 tok，125 t/s） | 1958 ms（253 tok） | 1384 ms | 33 t/s |
| **B 出货**：1.5B Q4_0、6 线程、fa、前缀缓存 | **886 ms**（128 tok 新算 + 56 复用） | **1230 ms** | 1123 ms | 36 t/s |
| **D** = B + 0.5B 投机解码 | 930 ms | 961 ms | 862 ms | **44 t/s**（输出与 B 逐字相同） |
| **C** 0.5B Q4_0（同 B） | 328 ms | 447 ms | 352 ms | 100 t/s——但说法输出是垃圾（`> 相见 </think>…`） |

- 决策 prefill **A→B 1.6–1.7×**（Q4_0 i8mm 重排 + fa + 系统前缀 56–82 tok 不再重算），且用 **6 线程**打赢 A 的 8 线程——游戏里空出来的两个核给渲染。
- 台词 decode 在 CPU 上是带宽墙：Q4_0 只 +9%；**投机解码再 +22%**（贪心等价）⇒ 作为可选项（模型旁放 `draft.gguf` 即开）。
- 0.5B 快 4.5× 但**生成质量不可用**；只配做决策。默认 1.5B Q4_0。
- GBNF 让决策输出 100% 合法（0 解析失败），decode 恰 1 token。

## 4. 接入（代码）

- `game/scripts/LocalLlama.gd`：找 `nativeLibraryDir` → 起服务（`-t 6 -c 4096 -np 1 -fa on --cache-reuse 64`，可选 `-md draft.gguf`）→ 轮询 `/health` → 退出/换模型时杀进程；
  手机上 stdout/stderr 落 `user://llamad.log`，关键节点落 `user://local_llama.log`（Godot print 进不了 logcat）。
- `AIBackend.gd`：新 `local` 档（`available_backends()` 在库存在时列出）；传输复用 `llm` 档；决策请求加 `grammar: root ::= [A-<n>]` + `max_tokens:1`，所有请求 `cache_prompt`；
  `probe_capability("local")` 先起服务再测暖延迟；服务死了下一发自动重起；`parse_approaches` 丢弃小模型的模板回声行。
- `Main.gd` / `LifeMode.gd`：`local` 与 `slm`/`llm` 同等对待（启动探测、对话）。
- 打包：`tools/build_llamad_android.sh` 编好放进 `game/android/build/libs/{debug,release}/arm64-v8a/libllamad.so`；预设 `compress_native_libraries=true` + `permissions/internet=true`。

### 真机才暴露的四个坑（桌面一个都测不到）

1. Godot 安卓 `FileAccess` 打不开 `/proc/self/maps`，也判 `/data/app/…/lib/*.so` "不存在" ⇒ 目录经系统 `sh` 读 `/proc/$PPID/maps`，存在性用 `test -x`。
2. `JavaClassWrapper` 读 `ApplicationInfo.nativeLibraryDir` 字段得 `null`（只包方法）。
3. 旧模型解析会选公共 `Documents/…/model.gguf`：Godot 判"存在"，但子进程（应用 uid）读它 **Permission denied** ⇒ `local` 档优先 `user://model.gguf`。
4. 没有 `INTERNET` 权限连回环端口都 bind 不上 ⇒ 预设开 `permissions/internet=true`（服务只绑 127.0.0.1）。

## 5. 真机游戏内 E2E（NX789J，debug 包 `com.forte13x.livingtown.life`，模型 1.5B Q4_0 放 `user://model.gguf`）

| 事件 | 时间 |
|---|---|
| 启动 → spawn `libllamad.so` | 1.9 s（首帧已出、镇子跑 logic 地板） |
| 服务就绪（/health，含 1 GB 模型 mmap + 重排） | +2.6 s |
| 探测暖决策（单发、整链 HTTP） | **728 ms** → tier=fast，启用 `local` |
| 镇上决策在飞（14 发，7–26 候选，最多 2 发排队共用一个 slot） | **1.1–3.5 s**，14/14 合法编号 |
| 对照：7 月 NobodyWho 真机日志（1.5B Q4_K_M） | 3–28 s，中位 ~16 s，常超 15 s 截止线 |

桌面 E2E（`game/scripts/local_backend_test.gd`，1.5B Q4_0）：探测 p50 55 ms、5/5 决策落地 0 解析失败、说法 1.8 s 出 3 条合法行、对话 0.7 s、退出后子进程已杀 → PASS。

## 6. 诚实边界

- 游戏内**说法/对话**只在桌面 E2E 验过（同一 HTTP 路）；真机只量了决策（进人生、走到人跟前按 E 需要手点）。
- 在飞 1.1–3.5 s 含排队：`MAX_INFLIGHT=2` 共用一个 slot，第二发要等第一发。
- 热：持续跑几分钟后 prefill 会掉到冷机的一半；长会话节奏下的热稳态未测（docs/22 G6 同款缺口）。
- 出货预设的包名仍是 `com.forte13x.livingtown`；验收包用了 `.life` 包名并存（未提交）。
- NPU（Genie/QNN）仍是 prefill 最快的硅（docs/22：~1600 t/s），但专有 `.so` 的再分发许可未清；本路全 MIT。
