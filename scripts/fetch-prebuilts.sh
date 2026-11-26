#!/usr/bin/env bash
#
# Download the two prebuilt pieces every Halium 9+ port needs:
#   ota/ubuntu-touch-android9plus-rootfs-arm64.tar.gz  Ubuntu Touch 24.04 rootfs (arm64)
#   ota/halium_halium_arm64.tar.xz                     Halium 10.0 generic arm64 GSI
#
# Both URLs were verified reachable (HTTP 200) while writing RESEARCH.md; the rootfs is
# ~927 MiB and the GSI ~137 MiB. Downloads are resumable and skipped if already present.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p ota

ROOTFS_URL="${ROOTFS_URL:-https://ci.ubports.com/job/ubuntu-touch-rootfs/job/ubports%2F24.04-2.x/lastStableBuild/artifact/ubuntu-touch-android9plus-rootfs-arm64.tar.gz}"
GSI_URL="${GSI_URL:-https://ci.ubports.com/job/UBportsCommunityPortsJenkinsCI/job/ubports%2Fporting%2Fcommunity-ports%2Fjenkins-ci%2Fgeneric_arm64/job/halium-10.0/lastSuccessfulBuild/artifact/halium_halium_arm64.tar.xz}"

ROOTFS_FILE="ota/ubuntu-touch-android9plus-rootfs-arm64.tar.gz"
GSI_FILE="ota/halium_halium_arm64.tar.xz"

fetch() {
    local url="$1" dest="$2"
    if [ -s "$dest" ]; then
        echo "==> $(basename "$dest") already present ($(du -h "$dest" | cut -f1)), skipping"
        return 0
    fi
    echo "==> Downloading $(basename "$dest")"
    curl --fail --location --retry 5 --retry-all-errors --continue-at - \
        --output "$dest" "$url"
}

fetch "$ROOTFS_URL" "$ROOTFS_FILE"
fetch "$GSI_URL" "$GSI_FILE"

echo "==> Verifying archives"
gzip -t "$ROOTFS_FILE"
xz -t "$GSI_FILE"

echo "==> Prebuilts ready:"
ls -lh "$ROOTFS_FILE" "$GSI_FILE"
