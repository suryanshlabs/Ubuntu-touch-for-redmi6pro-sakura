#!/usr/bin/env bash
#
# Merge device/halium.config into the kernel's sakura_defconfig.
#
# The upstream build tools run `make <defconfig>` and know nothing about extra config
# fragments, so the fragment has to live inside the defconfig file itself. This script
# is idempotent: the fragment is always the last block of the file and is replaced
# (not appended twice) on every run, with no leftover blank lines.
#
# Usage: scripts/prepare-kernel-config.sh [build-dir]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${1:-${BUILD_DIR:-$ROOT/workdir}}"
FRAGMENT="$ROOT/device/halium.config"

# shellcheck source=/dev/null
source "$ROOT/deviceinfo"

# The build tools clone into <downloads>/<basename of kernel_source> (minus .git).
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

# Drop a previously injected block. It is always the tail of the file, so truncate from
# the marker onwards (walking back over the blank separator line) instead of relying on
# a sed range, which would leave one more blank line behind on every run.
if grep -qF "$MARK_BEGIN" "$DEFCONFIG"; then
    LINE="$(grep -nF "$MARK_BEGIN" "$DEFCONFIG" | head -n1 | cut -d: -f1)"
    START="$LINE"
    while [ "$START" -gt 1 ] && [ -z "$(sed -n "$((START - 1))p" "$DEFCONFIG")" ]; do
        START=$((START - 1))
    done
    sed -i "${START},\$d" "$DEFCONFIG"
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
for opt in CONFIG_ANDROID_BINDER_IPC CONFIG_SECURITY_SELINUX CONFIG_CONFIGFS_FS \
           CONFIG_DEVTMPFS CONFIG_OVERLAY_FS CONFIG_UTS_NS CONFIG_PID_NS; do
    if ! grep -q "^${opt}=y" "$DEFCONFIG"; then
        echo "prepare-kernel-config: warning: $opt is not enabled after the merge" >&2
    fi
done
