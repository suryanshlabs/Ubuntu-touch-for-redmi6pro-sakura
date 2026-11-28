#!/usr/bin/env bash
#
# Assemble the OrangeFox/TWRP flashable zip for Redmi 6 Pro (sakura).
#
# Inputs (all produced by the earlier steps):
#   out/boot.img or workdir/tmp/partitions/boot.img   Halium boot image  (./build.sh)
#   out/device_sakura.tar.xz                          device tarball     (./build.sh)
#   out/rootfs.img.gz                                 UT rootfs image    (scripts/make-rootfs-image.sh)
#   ota/halium_halium_arm64.tar.xz                    Halium 10 GSI      (scripts/fetch-prebuilts.sh)
#   installer/META-INF/...                            installer logic
#
# Output:
#   dist/sakura-ut24.04-halium10-v<ver>-<date>-<sha>.zip
#   dist/....zip.sha256
#   dist/....buildinfo
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT_DIR="${OUT_DIR:-$ROOT/out}"
WORKDIR="${WORKDIR:-$ROOT/workdir}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
PORT_VERSION="${PORT_VERSION:-0.1.1}"
DEVICE="sakura"
UT_RELEASE="ut24.04"
HALIUM="halium10"

# Upper bound from the Android device tree (BOARD_BOOTIMAGE_PARTITION_SIZE := 67108864).
# The image is NOT padded up to it: on real sakura units the boot partition can be smaller
# than the 64 MiB the device tree declares, and a 64 MiB write is then refused (or fails
# with "No space left on device"), which is exactly what the first v0.1.0 release did.
# The boot image itself is only ~15-25 MB and the bootloader reads it by the sizes in its
# header, so trailing bytes left over from the previous image are harmless.
BOOT_PARTITION_SIZE="${BOOT_PARTITION_SIZE:-67108864}"

# GitHub refuses release assets larger than 2 GiB.
MAX_ZIP_BYTES="${MAX_ZIP_BYTES:-2000000000}"

# shellcheck source=/dev/null
source "$ROOT/deviceinfo"

BUILD_DATE="$(date -u +%Y%m%d)"
BUILD_STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
GIT_SHORT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo nogit)"
GIT_DIRTY=""
git -C "$ROOT" diff --quiet 2>/dev/null || GIT_DIRTY="-dirty"

ZIP_NAME="${DEVICE}-${UT_RELEASE}-${HALIUM}-v${PORT_VERSION}-${BUILD_DATE}-${GIT_SHORT}${GIT_DIRTY}.zip"
TARGET="$DIST_DIR/$ZIP_NAME"

ROOTFS_GZ="${ROOTFS_GZ:-$OUT_DIR/rootfs.img.gz}"
GSI_TAR="${GSI_TAR:-$ROOT/ota/halium_halium_arm64.tar.xz}"
DEVICE_TAR="${DEVICE_TAR:-$OUT_DIR/device_sakura.tar.xz}"

fail() { echo "build-zip: $*" >&2; exit 1; }

# --- boot.img: prefer out/, fall back to the build workdir
BOOT_IMG="${BOOT_IMG:-}"
if [ -z "$BOOT_IMG" ]; then
    for candidate in "$OUT_DIR/boot.img" "$WORKDIR/tmp/partitions/boot.img"; do
        [ -s "$candidate" ] && BOOT_IMG="$candidate" && break
    done
fi
[ -n "$BOOT_IMG" ] && [ -s "$BOOT_IMG" ] || fail "boot.img not found (run ./build.sh first)"
[ -s "$ROOTFS_GZ" ] || fail "missing $ROOTFS_GZ (run scripts/make-rootfs-image.sh)"
[ -s "$GSI_TAR" ]   || fail "missing $GSI_TAR (run scripts/fetch-prebuilts.sh)"
[ -s "$DEVICE_TAR" ] || fail "missing $DEVICE_TAR (run ./build.sh first)"

STAGE="$(mktemp -d /tmp/sakura-zip.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Staging $ZIP_NAME"
mkdir -p "$STAGE/META-INF/com/google/android" "$STAGE/META-INF/sakura" \
         "$STAGE/partitions" "$STAGE/images"

cp -f "$ROOT/installer/META-INF/com/google/android/update-binary" \
      "$STAGE/META-INF/com/google/android/update-binary"
cp -f "$ROOT/installer/META-INF/com/google/android/updater-script" \
      "$STAGE/META-INF/com/google/android/updater-script"
chmod 755 "$STAGE/META-INF/com/google/android/update-binary"

cp -f "$BOOT_IMG" "$STAGE/partitions/boot.img"
BOOT_BYTES="$(stat -c%s "$STAGE/partitions/boot.img")"
if [ "$BOOT_BYTES" -gt "$BOOT_PARTITION_SIZE" ]; then
    fail "boot.img is $BOOT_BYTES bytes, larger than the ${BOOT_PARTITION_SIZE} byte boot partition"
fi
echo "==> boot.img: $BOOT_BYTES bytes, written unpadded (boot partition upper bound $BOOT_PARTITION_SIZE)"

echo "==> Unpacking Halium 10 GSI"
tar -xJf "$GSI_TAR" -C "$STAGE/images"
# The CI artifact keeps the image at system/var/lib/lxc/android/android-rootfs.img;
# older artifacts use system.img at the top level. Search the whole tree.
ANDROID_ROOTFS="$(find "$STAGE/images" -type f \( -name 'android-rootfs.img' -o -name 'system.img' \) | head -n1)"
[ -n "$ANDROID_ROOTFS" ] || fail "no android-rootfs.img/system.img inside $GSI_TAR"
mv -f "$ANDROID_ROOTFS" "$STAGE/images/android-rootfs.img"
# Drop the rest of the GSI tree (partitions/, system/var/lib/lxc/...): the installer only
# needs the image itself.
find "$STAGE/images" -mindepth 1 -maxdepth 1 ! -name 'android-rootfs.img' -exec rm -rf {} +
ANDROID_BYTES="$(stat -c%s "$STAGE/images/android-rootfs.img")"
echo "    android-rootfs.img: $((ANDROID_BYTES / 1024 / 1024)) MiB"

cp -f "$ROOTFS_GZ" "$STAGE/images/rootfs.img.gz"
cp -f "$DEVICE_TAR" "$STAGE/device_${DEVICE}.tar.xz"

# The installer sizes its /data free-space check from this number, so it has to be the
# real uncompressed size. gzip stores that size in a 32-bit trailer, so an image of
# exactly 4 GiB reports 0 — prefer the plain image when it is still on disk, and fall
# back to counting the decompressed bytes if the header is unusable.
ROOTFS_BYTES=""
ROOTFS_IMG="${ROOTFS_IMG:-$OUT_DIR/rootfs.img}"
if [ -s "$ROOTFS_IMG" ]; then
    ROOTFS_BYTES="$(stat -c%s "$ROOTFS_IMG")"
    echo "==> rootfs uncompressed size from $(basename "$ROOTFS_IMG"): $ROOTFS_BYTES bytes"
fi
if [ -z "$ROOTFS_BYTES" ] || [ "$ROOTFS_BYTES" -le 0 ]; then
    ROOTFS_BYTES="$(gzip -l "$STAGE/images/rootfs.img.gz" | awk 'NR==2 {print $2}')"
fi
if [ -z "$ROOTFS_BYTES" ] || [ "$ROOTFS_BYTES" -le 0 ]; then
    echo "==> gzip trailer reports $ROOTFS_BYTES, counting decompressed bytes instead"
    if command -v pigz >/dev/null 2>&1; then
        ROOTFS_BYTES="$(pigz -dc "$STAGE/images/rootfs.img.gz" | wc -c)"
    else
        ROOTFS_BYTES="$(gzip -dc "$STAGE/images/rootfs.img.gz" | wc -c)"
    fi
fi
[ "$ROOTFS_BYTES" -gt 0 ] || fail "could not determine the uncompressed rootfs size"

cat > "$STAGE/META-INF/sakura/build.prop" <<MANIFEST
# Build identification, written to /data/sakura-ubuntu-touch-build.prop on install.
sakura.build.version=${PORT_VERSION}
sakura.build.device=${DEVICE}
sakura.build.ut_release=${UT_RELEASE}
sakura.build.halium=${HALIUM}
sakura.build.date=${BUILD_STAMP}
sakura.build.commit=${GIT_SHORT}${GIT_DIRTY}
sakura.build.codename=${deviceinfo_codename}
sakura.build.halium_version=${deviceinfo_halium_version}
sakura.build.rootfs_bytes=${ROOTFS_BYTES}
sakura.build.android_rootfs_bytes=${ANDROID_BYTES}
sakura.build.bootimg_bytes=${BOOT_BYTES}
sakura.build.installer=${ZIP_NAME}
MANIFEST

mkdir -p "$DIST_DIR"
rm -f "$TARGET"
echo "==> Creating zip"
# Already-compressed rootfs is stored, the raw Android image is deflated, the small
# metadata is deflated hard.
(cd "$STAGE" && zip -r -q -9 "$TARGET" META-INF device_"${DEVICE}".tar.xz partitions)
(cd "$STAGE" && zip -r -q -0 "$TARGET" images/rootfs.img.gz)
(cd "$STAGE" && zip -r -q -6 "$TARGET" images/android-rootfs.img)

SHA="$(sha256sum "$TARGET" | cut -d' ' -f1)"
SIZE="$(stat -c%s "$TARGET")"
printf '%s  %s\n' "$SHA" "$(basename "$TARGET")" > "$TARGET.sha256"
cat > "${TARGET%.zip}.buildinfo" <<INFO
file          $(basename "$TARGET")
size          $SIZE bytes
sha256        $SHA
port_version  $PORT_VERSION
ut_release    $UT_RELEASE
halium        $HALIUM
device        $DEVICE
commit        $GIT_SHORT$GIT_DIRTY
built         $BUILD_STAMP
bootimg       $(basename "$BOOT_IMG")
rootfs_bytes  $ROOTFS_BYTES
android_bytes $ANDROID_BYTES
INFO

echo "==> Done"
ls -lh "$TARGET" "$TARGET.sha256" "${TARGET%.zip}.buildinfo"
echo "sha256: $SHA"

if [ "$SIZE" -gt "$MAX_ZIP_BYTES" ]; then
    echo "build-zip: WARNING: the zip is $((SIZE / 1024 / 1024)) MiB, above the $((MAX_ZIP_BYTES / 1024 / 1024)) MiB" >&2
    echo "build-zip: WARNING: GitHub release asset limit, so the GitHub Release upload may fail." >&2
    echo "build-zip: WARNING: the workflow artifact is still usable. Shrink with ROOTFS_SIZE=3G." >&2
fi
