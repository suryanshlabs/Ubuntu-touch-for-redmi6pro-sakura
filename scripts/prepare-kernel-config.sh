#!/usr/bin/env bash
#
# Merge device/halium.config into the kernel's sakura_defconfig.
#
# The upstream build tools run `make <defconfig>` and know nothing about extra config
# fragments, so the fragment has to live inside the defconfig file itself. This script is
# idempotent: the fragment is wrapped in marker comments and replaced on every run.
#
# Usage: scripts/prepare-kernel-config.sh [build-dir]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${1:-${BUILD_DIR:-$ROOT/workdir}}"
FRAGMENT="$ROOT/device/halium.config"

# shellcheck source=/dev/null
source "$ROOT/deviceinfo"

KERNEL_DIR_NAME="$(basename "${deviceinfo_kernel_source}")"
KERNEL_DIR_NAME="${KERNEL_DIR_NAME%.git}"
KERNEL_DIR="$BUILD_DIR/downloads/$KERNEL_DIR_NAME"
DEFCONFIG="$KERNEL_DIR/arch/arm64/configs/${deviceinfo_kernel_defconfig%% *}"

if [ ! -f "$DEFCONFIG" ]; then
    echo "prepare-kernel-config: $DEFCONFIG not found." >&2
    echo "Run './build.sh -c' first to clone the kernel source." >&2
    exit 1
fi

MARK_BEGIN="# >>> ubuntu-touch-sakura halium.config >>>"
MARK_END="# <<< ubuntu-touch-sakura halium.config <<<"

# Drop a previously injected block, if present.
if grep -qF "$MARK_BEGIN" "$DEFCONFIG"; then
    sed -i.bak "/^${MARK_BEGIN}$/,/^${MARK_END}$/d" "$DEFCONFIG"
    rm -f "$DEFCONFIG.bak"
fi

{
    echo ""
    echo "$MARK_BEGIN"
    echo "# Generated from device/halium.config by scripts/prepare-kernel-config.sh"
    grep -vE '^\s*(#|$)' "$FRAGMENT"
    echo "$MARK_END"
} >> "$DEFCONFIG"

echo "==> Merged $(grep -cvE '^\s*(#|$)' "$FRAGMENT") config options into $DEFCONFIG"

# Sanity check: the options Halium cannot boot without.
for opt in CONFIG_ANDROID_BINDER_IPC CONFIG_SECURITY_SELINUX CONFIG_CONFIGFS_FS; do
    if ! grep -q "^${opt}=" "$DEFCONFIG"; then
        echo "prepare-kernel-config: warning: $opt missing from the merged defconfig" >&2
    fi
done
