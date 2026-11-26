#!/usr/bin/env bash
#
# Build Ubuntu Touch boot images for Xiaomi Redmi 6 Pro (sakura).
#
# Thin wrapper around the official UBports tooling:
#   https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools
#
# It does three things the upstream script does not do on its own:
#   1. clones the build tools into ./build (git-ignored)
#   2. merges device/halium.config into the kernel defconfig (clone-only pass first)
#   3. runs the upstream build against ./workdir, producing ./out/device_sakura.tar.xz
#      plus workdir/tmp/partitions/boot.img
#
# Output:
#   out/device_sakura.tar.xz        device tarball (overlaystore + modules)
#   workdir/tmp/partitions/boot.img Halium boot image (kernel + initramfs)
#
# Usage:
#   ./build.sh                 full build
#   ./build.sh -c              clone only (kernel sources + prebuilts)
#   ./build.sh -k              rebuild the kernel/boot image only
#   BUILD_DIR=/tmp/wd ./build.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

BUILD_TOOLS_DIR="${BUILD_TOOLS_DIR:-$ROOT/build}"
BUILD_TOOLS_REPO="${BUILD_TOOLS_REPO:-https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools.git}"
BUILD_TOOLS_BRANCH="${BUILD_TOOLS_BRANCH:-main}"
BUILD_DIR="${BUILD_DIR:-$ROOT/workdir}"

if [ ! -f "$BUILD_TOOLS_DIR/build.sh" ]; then
    echo "==> Cloning halium-generic-adaptation-build-tools ($BUILD_TOOLS_BRANCH)"
    rm -rf "$BUILD_TOOLS_DIR"
    git clone --depth 1 -b "$BUILD_TOOLS_BRANCH" "$BUILD_TOOLS_REPO" "$BUILD_TOOLS_DIR"
fi

# 1. clone-only pass: downloads prebuilts and the kernel source, builds nothing.
echo "==> Preparing kernel sources (clone-only pass)"
"$BUILD_TOOLS_DIR/build.sh" -b "$BUILD_DIR" -c "$@"

# 2. merge the Halium kernel config fragment into the device defconfig.
"$ROOT/scripts/prepare-kernel-config.sh" "$BUILD_DIR"

# 3. real build.
echo "==> Building kernel + boot image"
"$BUILD_TOOLS_DIR/build.sh" -b "$BUILD_DIR" "$@"

mkdir -p "$ROOT/out"
if [ -f "$BUILD_DIR/tmp/partitions/boot.img" ]; then
    cp -f "$BUILD_DIR/tmp/partitions/boot.img" "$ROOT/out/boot.img"
fi

echo
echo "==> Done"
ls -lh "$ROOT/out" 2>/dev/null || true
echo "Next: ./scripts/fetch-prebuilts.sh && sudo ./scripts/make-rootfs-image.sh && ./scripts/build-zip.sh"
