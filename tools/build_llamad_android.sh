#!/usr/bin/env bash
# Build llama.cpp's llama-server for Android arm64 (Snapdragon 8 Elite tuned) and drop it into the
# Godot gradle template as a jniLib, so the APK ships it as lib/arm64-v8a/libllamad.so (docs/191).
#
#   tools/build_llamad_android.sh [LLAMA_SRC] [NDK]
#
# Why these flags (measured on NX789J / SM8750, docs/191 §3):
#   armv8.6-a+dotprod+i8mm+fp16  → enables the int8-matmul (i8mm) path + Q4_0 online repack (the big prefill win)
#   GGML_OPENMP=OFF              → static, single-file exe (no libomp.so to ship); ggml's own threadpool is on par
#   static + c++_static          → NEEDED only libc/libm/libdl; nothing else to package
# Packaging requires export preset `gradle_build/compress_native_libraries=true` (legacy packaging), otherwise
# Android keeps the .so inside the APK and there is no file on disk to exec (targetSdk>=29 forbids exec from app data).
set -euo pipefail
SRC="${1:-${LLAMA_SRC:-E:/lt-llama}}"
NDK="${2:-${ANDROID_NDK_ROOT:-E:/Documents/Dev/June/26th/build/android-sdk/ndk/26.3.11579264}}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$SRC/build-llamad"
cmake -S "$SRC" -B "$OUT" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=armv8.6-a+dotprod+i8mm+fp16 \
  -DGGML_OPENMP=OFF -DLLAMA_CURL=OFF -DLLAMA_OPENSSL=OFF -DLLAMA_BUILD_WEBUI=OFF
cmake --build "$OUT" -j 16 --target llama-server
STRIP="$(ls "$NDK"/toolchains/llvm/prebuilt/*/bin/llvm-strip* | head -1)"
for v in debug release; do
  d="$HERE/game/android/build/libs/$v/arm64-v8a"
  mkdir -p "$d"
  "$STRIP" -o "$d/libllamad.so" "$OUT/bin/llama-server"
  echo "-> $d/libllamad.so ($(du -h "$d/libllamad.so" | cut -f1))"
done
echo "llama.cpp $(git -C "$SRC" rev-parse --short HEAD)"
