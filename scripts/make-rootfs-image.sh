#!/usr/bin/env bash
#
# Build out/rootfs.img: a mountable ext4 image of the Ubuntu Touch rootfs with the
# sakura device overlay applied.
#
# This is the same image halium-install would build on your PC (qemu-img + mkfs.ext4 +
# tar extraction); doing it here means the recovery zip can simply gunzip it onto /data.
#
# Requires root (ext4 creation + loop mount), so run with sudo. On GitHub Actions the
# runner user already has passwordless sudo.
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
MNT="$(mktemp -d /tmp/sakura-rootfs.XXXXXX)"
trap 'umount "$MNT" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true' EXIT

echo "==> Creating $IMG ($SIZE)"
rm -f "$IMG"
truncate -s "$SIZE" "$IMG"
# ^metadata_csum/^64bit keeps the filesystem mountable by the Android 4.9 kernel in
# recovery (mke2fs on modern hosts would otherwise enable features it cannot read).
mkfs.ext4 -q -F -L ubuntu-rootfs -O ^metadata_csum,^64bit -E lazy_itable_init=0 "$IMG"

echo "==> Extracting rootfs"
mount -o loop "$IMG" "$MNT"
tar --numeric-owner -xzf "$ROOTFS_TAR" -C "$MNT"

if [ -d "$OVERLAY" ]; then
    echo "==> Applying device overlay from $OVERLAY"
    cp -a "$OVERLAY/." "$MNT/"
fi

# Halium convention: the Android GSI is mounted by systemd from /data/system.img or
# /var/lib/lxc/android/. The installer drops it at /data/android-rootfs.img, so nothing
# has to be baked in here.

sync
umount "$MNT"
rmdir "$MNT"
trap - EXIT

echo "==> Shrinking to minimum size"
e2fsck -fy "$IMG" >/dev/null || true
resize2fs -M "$IMG" >/dev/null
e2fsck -fy "$IMG" >/dev/null || true

if [ "${COMPRESS:-1}" = "1" ]; then
    echo "==> Compressing (gzip -1, tuned for install speed on the phone)"
    gzip -1 -c "$IMG" > "$IMG.gz.tmp"
    mv "$IMG.gz.tmp" "$IMG.gz"
    ls -lh "$IMG" "$IMG.gz"
else
    ls -lh "$IMG"
fi

echo "==> rootfs image ready"
