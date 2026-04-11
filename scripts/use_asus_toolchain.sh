#!/usr/bin/env bash
# Export ASUS Android11 kernel toolchain environment.
# Usage:
#   source scripts/use_asus_toolchain.sh
# Optional override:
#   TOOLROOT=/custom/path source scripts/use_asus_toolchain.sh

TOOLROOT="${TOOLROOT:-/home/codespace/toolchains/asus-android11-kernel}"
CLANG_BIN="$TOOLROOT/clang-r416183b/bin"
A64_BIN="$TOOLROOT/aarch64-linux-android-4.9/bin"
A32_BIN="$TOOLROOT/arm-linux-androideabi-4.9/bin"

[[ -x "$CLANG_BIN/clang" ]] || { echo "Missing: $CLANG_BIN/clang" >&2; return 1 2>/dev/null || exit 1; }
[[ -x "$A64_BIN/aarch64-linux-androidkernel-gcc" ]] || { echo "Missing: $A64_BIN/aarch64-linux-androidkernel-gcc" >&2; return 1 2>/dev/null || exit 1; }
[[ -x "$A32_BIN/arm-linux-androideabi-gcc" ]] || { echo "Missing: $A32_BIN/arm-linux-androideabi-gcc" >&2; return 1 2>/dev/null || exit 1; }

export PATH="$CLANG_BIN:$A64_BIN:$A32_BIN:$PATH"
export ARCH=arm64
export CC=clang
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-androidkernel-
export CROSS_COMPILE_COMPAT=arm-linux-androideabi-
export LD=ld.lld
export NM=llvm-nm
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export STRIP=llvm-strip

echo "ASUS kernel toolchain loaded from: $TOOLROOT"
clang --version | head -n 1
"${CROSS_COMPILE}gcc" --version | head -n 1
"${CROSS_COMPILE_COMPAT}gcc" --version | head -n 1
