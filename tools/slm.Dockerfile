# gamecraft-slm:24 — 跑嵌入式 SLM（NobodyWho GDExtension）的 headless Godot 镜像。
# 为何不复用 gamecraft-runner:4.6.2：那是 Ubuntu 22.04(glibc 2.35)，而 NobodyWho v9.4.0 的 .so 需 GLIBC_2.38。
# 本镜像 = Ubuntu 24.04(glibc 2.39) + Vulkan loader(libvulkan1) + OpenMP(libgomp1) + 从旧镜像拷入的 godot 二进制。
# 注：apt 大索引(noble/universe)经 http 常被宿主网络截断(500/EOF) → 用 ca-certificates 后切 https 镜像取 libvulkan1。
#
# 构建：  docker build -t gamecraft-slm:24 -f tools/slm.Dockerfile tools
# 运行：  docker run --rm -v "E:/Documents/Dev/June/26th/game:/game" \
#           gamecraft-slm:24 godot --headless --path /game res://scenes/slm_live_test.tscn
# 前置：  game/addons/nobodywho/（扩展，仅留 linux x86_64 release .so + .gdextension）
#         game/models/qwen2.5-1.5b-instruct-q4_k_m.gguf
#         game/.godot/extension_list.cfg 内含 res://addons/nobodywho/nobodywho.gdextension

FROM gamecraft-runner:4.6.2 AS old
FROM ubuntu:24.04
RUN apt-get update 2>/dev/null || true; \
    apt-get install -y --no-install-recommends ca-certificates libgomp1 2>&1 | tail -1; \
    sed -i "s|http://archive.ubuntu.com/ubuntu|https://mirrors.edge.kernel.org/ubuntu|g; s|http://security.ubuntu.com/ubuntu|https://mirrors.edge.kernel.org/ubuntu|g" /etc/apt/sources.list.d/ubuntu.sources; \
    apt-get -o Acquire::Retries=10 update; \
    apt-get install -y --no-install-recommends libvulkan1; \
    rm -rf /var/lib/apt/lists/*
COPY --from=old /opt/godot/godot /usr/local/bin/godot
RUN chmod +x /usr/local/bin/godot && /usr/local/bin/godot --headless --version
