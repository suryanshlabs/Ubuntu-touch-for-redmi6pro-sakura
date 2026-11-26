#!/usr/bin/env bash
#
# Build out/rootfs.img: a mountable ext4 image of the Ubuntu Touch rootfs with the
# sakura device overlay applied.
#
# This is the same image halium-install would build on your PC (mkfs.ext4 + tar
# extraction); doing it here means the recovery zip can simply gunzip it onto /data.
#
# The filesystem is NOT shrunk to its minimum. The free space inside it is what the
# user has for apps, /var and updates once Ubuntu Touch runs from it.
#
# Requires root (ext4 creation, and loop mount when available), so run with sudo.
# When loop mounts are unavailable (some containers/CI sandboxes) the image is
# populated with `mkfs.ext4 -d` instead, which needs no mount at all.
#
# Output: out/rootfs.img  (also out/rootfs.img.gz when COMPRESS=1)
#
# Usage: sudo -E ./scripts/make-rootfs-image.sh [size, default 4G]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SIZE="${1:-${ROOTFS_SIZE:-4G}}"
ROOTFS_TAR="${ROOTFS_TAR:-ota/ubuntu-touch-android9plus-rootfs-arm64.tar.gz}"
OVERLAY="${OVERLAY:-device/overlay/system}"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
IMG="$OUT_DIR/rootfs.img"

if [ ! -f "$ROOTFS_TAR" ]; then
    echo "make-rootfs-image: missing $ROOTFS_TAR (run scripts/fetch-prebuilts.sh)" >&2
    exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
    echo "make-rootfs-image: must run as root (ext4 image + loop mount). Use: sudo -E $0" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
rm -f "$IMG"

# ^metadata_csum/^64bit keeps the filesystem mountable by the Android 4.9 kernel in
# recovery (mke2fs on modern hosts would otherwise enable features it cannot read).
MKFS_OPTS=(-q -F -L ubuntu-rootfs -O ^metadata_csum,^64bit)

MNT="$(mktemp -d /tmp/sakura-rootfs.XXXXXX)"
XDIR=""
cleanup() {
    umount "$MNT" 2>/dev/null || true
    rmdir "$MNT" 2>/dev/null || true
    [ -n "$XDIR" ] && rm -rf "$XDIR"
}
trap cleanup EXIT

echo "==> Creating $IMG ($SIZE)"
if truncate -s "$SIZE" "$IMG" && mkfs.ext4 "${MKFS_OPTS[@]}" -E lazy_itable_init=0 "$IMG" \
   && mount -o loop "$IMG" "$MNT" 2>/dev/null; then
    echo "==> Extracting rootfs into the loop-mounted image"
    tar --numeric-owner -xzf "$ROOTFS_TAR" -C "$MNT"
    if [ -d "$OVERLAY" ]; then
        echo "==> Applying device overlay from $OVERLAY"
        cp -a "$OVERLAY/." "$MNT/"
    fi
    sync
    umount "$MNT"
    rmdir "$MNT" 2>/dev/null || true
else
    echo "==> Loop mount unavailable, populating the image with mkfs.ext4 -d"
    umount "$MNT" 2>/dev/null || true
    XDIR="$(mktemp -d /tmp/sakura-rootfs-tree.XXXXXX)"
    tar --numeric-owner -xzf "$ROOTFS_TAR" -C "$XDIR"
    if [ -d "$OVERLAY" ]; then
        echo "==> Applying device overlay from $OVERLAY"
        cp -a "$OVERLAY/." "$XDIR/"
    fi
    rm -f "$IMG"
    mkfs.ext4 "${MKFS_OPTS[@]}" -d "$XDIR" "$IMG" "$SIZE"
    rm -rf "$XDIR"
    XDIR=""
fi

# Halium convention: the Android GSI is mounted by systemd from /data/system.img or
# /var/lib/lxc/android/. The installer drops it at /data/android-rootfs.img, so nothing
# has to be baked in here.

echo "==> Checking the filesystem"
e2fsck -fy "$IMG" >/dev/null || true

USED="$(du -h --apparent-size "$IMG" | cut -f1)"
echo "    image size: $USED"

if [ "${COMPRESS:-1}" = "1" ]; then
    if command -v pigz >/dev/null 2>&1; then
        echo "==> Compressing with pigz -6 -T$(nproc)"
        pigz -6 -p "$(nproc)" -c "$IMG" > "$IMG.gz.tmp"
    else
        echo "==> Compressing with gzip -6"
        gzip -6 -c "$IMG" > "$IMG.gz.tmp"
    fi
    mv "$IMG.gz.tmp" "$IMG.gz"
    ls -lh "$IMG" "$IMG.gz"
else
    ls -lh "$IMG"
fi

echo "==> rootfs image ready"
