#!/usr/bin/env bash
#
# Optional: produce the images the *official* UBports way, from an OTA channel, using the
# build tools' prepare-fake-ota.sh + system-image-from-ota.sh.
#
# This is what UBports CI runs for ports that already have an OTA channel. sakura has no
# OTA channel yet, so the flashable zip path (scripts/build-zip.sh) is the default and this
# script is only useful once the port has been accepted upstream or for system-as-root
# experiments.
#
# Inputs:
#   out/device_sakura.tar.xz   from ./build.sh
# Output:
#   out/system.img, out/rootfs.img, out/ubuntu_command
#
# Usage: ./scripts/prepare-ota.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD_TOOLS_DIR="${BUILD_TOOLS_DIR:-$ROOT/build}"
OTA_CHANNEL="${OTA_CHANNEL:-24.04-2.x/arm64/android9plus/stable}"
DEVICE="${DEVICE:-sakura}"
DEVICE_TAR="out/device_${DEVICE}.tar.xz"

[ -f "$DEVICE_TAR" ] || { echo "prepare-ota: missing $DEVICE_TAR (run ./build.sh)" >&2; exit 1; }
[ -x "$BUILD_TOOLS_DIR/fetch-and-prepare-latest-ota.sh" ] || {
    echo "prepare-ota: build tools missing (run ./build.sh once)" >&2; exit 1; }

echo "==> Fetching OTA channel $OTA_CHANNEL"
"$BUILD_TOOLS_DIR/fetch-and-prepare-latest-ota.sh" "$OTA_CHANNEL" "$DEVICE" ota

echo "==> Building system image from OTA"
mkdir -p out
"$BUILD_TOOLS_DIR/system-image-from-ota.sh" ota/ubuntu_command out

echo "==> OTA images ready:"
ls -lh out/*.img out/ubuntu_command 2>/dev/null || true
