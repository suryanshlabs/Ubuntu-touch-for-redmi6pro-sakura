#!/usr/bin/env bash
#
# Build Ubuntu Touch boot images for Xiaomi Redmi 6 Pro (sakura).
#
# Thin wrapper around the official UBports tooling:
#   https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools
#
# It does four things the upstream script does not do on its own:
#   1. clones the build tools into ./build (git-ignored)
#   2. runs a clone-only pass, then merges device/halium.config into the kernel defconfig
#   3. runs the upstream build against ./workdir, producing ./out/device_sakura.tar.xz
#      plus workdir/tmp/partitions/boot.img
#   4. optionally retries the whole build with GCC 4.9 instead of clang
#
# Output:
#   out/device_sakura.tar.xz        device tarball (overlaystore + modules)
#   out/boot.img                    Halium boot image (kernel + initramfs)
#   workdir/tmp/partitions/boot.img the same image, where the build tools leave it
#
# Usage:
#   ./build.sh                 full build (clang, as deviceinfo says)
#   ./build.sh -c              clone only (kernel sources + prebuilts)
#   ./build.sh -k              rebuild the kernel/boot image only
#   KERNEL_GCC=1 ./build.sh    same build, but with the GCC 4.9 prebuilts instead of clang
#   BUILD_DIR=/tmp/wd ./build.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

BUILD_TOOLS_DIR="${BUILD_TOOLS_DIR:-$ROOT/build}"
BUILD_TOOLS_REPO="${BUILD_TOOLS_REPO:-https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools.git}"
BUILD_TOOLS_BRANCH="${BUILD_TOOLS_BRANCH:-main}"
BUILD_DIR="${BUILD_DIR:-$ROOT/workdir}"
KERNEL_GCC="${KERNEL_GCC:-0}"

if [ ! -f "$BUILD_TOOLS_DIR/build.sh" ]; then
    echo "==> Cloning halium-generic-adaptation-build-tools ($BUILD_TOOLS_BRANCH)"
    rm -rf "$BUILD_TOOLS_DIR"
    git clone --depth 1 -b "$BUILD_TOOLS_BRANCH" "$BUILD_TOOLS_REPO" "$BUILD_TOOLS_DIR"
fi

# Optional GCC fallback: the upstream scripts source ./deviceinfo themselves, so the only
# way to switch the toolchain from outside is to patch that file for the duration of the
# build. It is restored on exit, including on failure.
if [ "$KERNEL_GCC" = "1" ]; then
    echo "==> KERNEL_GCC=1: building with the GCC 4.9 prebuilts instead of clang"
    cp -f "$ROOT/deviceinfo" "$ROOT/.deviceinfo.orig"
    trap 'mv -f "$ROOT/.deviceinfo.orig" "$ROOT/deviceinfo" 2>/dev/null || true' EXIT
    sed -i 's/^deviceinfo_kernel_clang_compile=.*/deviceinfo_kernel_clang_compile="false"/' "$ROOT/deviceinfo"
    grep -q '^deviceinfo_kernel_clang_compile="false"' "$ROOT/deviceinfo" \
        || { echo "build.sh: could not switch deviceinfo to GCC" >&2; exit 1; }
    # Objects and .config from the failed toolchain must not be reused.
    rm -rf "$BUILD_DIR/downloads/KERNEL_OBJ" "$BUILD_DIR/tmp"
fi

# 1. clone-only pass: downloads prebuilts and the kernel source, builds nothing.
echo "==> Preparing kernel sources (clone-only pass)"
"$BUILD_TOOLS_DIR/build.sh" -b "$BUILD_DIR" -c "$@"

# 2. merge the Halium kernel config fragment into the device defconfig.
"$ROOT/scripts/prepare-kernel-config.sh" "$BUILD_DIR"

# 3. Refuse to reuse objects from a different compiler. The kernel object directory is
#    cached between CI runs, and objects built by clang and by GCC cannot be mixed; the
#    compiler is not a make dependency, so nothing else would notice the change.
KERNEL_OBJ_DIR="$BUILD_DIR/downloads/KERNEL_OBJ"
TOOLCHAIN_STAMP="$BUILD_DIR/downloads/.sakura-toolchain"
WANTED_TOOLCHAIN=clang
if grep -q '^deviceinfo_kernel_clang_compile="\(false\|0\)"' "$ROOT/deviceinfo"; then
    WANTED_TOOLCHAIN=gcc
fi
if [ -d "$KERNEL_OBJ_DIR" ] && [ "$(cat "$TOOLCHAIN_STAMP" 2>/dev/null)" != "$WANTED_TOOLCHAIN" ]; then
    echo "==> Kernel objects were not built with $WANTED_TOOLCHAIN (or unknown); rebuilding them"
    rm -rf "$KERNEL_OBJ_DIR"
fi

# 4. real build.
echo "==> Building kernel + boot image"
"$BUILD_TOOLS_DIR/build.sh" -b "$BUILD_DIR" "$@"
printf '%s\n' "$WANTED_TOOLCHAIN" > "$TOOLCHAIN_STAMP"

mkdir -p "$ROOT/out"
if [ -f "$BUILD_DIR/tmp/partitions/boot.img" ]; then
    cp -f "$BUILD_DIR/tmp/partitions/boot.img" "$ROOT/out/boot.img"
fi

echo
echo "==> Done"
ls -lh "$ROOT/out" 2>/dev/null || true
echo "Next: ./scripts/fetch-prebuilts.sh && sudo ./scripts/make-rootfs-image.sh && ./scripts/build-zip.sh"
