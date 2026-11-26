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
PORT_VERSION="${PORT_VERSION:-0.1.0}"
DEVICE="sakura"
UT_RELEASE="ut24.04"
HALIUM="halium10"

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

# --- boot.img: prefer out/, fall back to the build workdir, last resort the device tarball
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

echo "==> Unpacking Halium 10 GSI"
tar -xJf "$GSI_TAR" -C "$STAGE/images"
ANDROID_ROOTFS="$(find "$STAGE/images" -maxdepth 2 -type f \( -name 'android-rootfs.img' -o -name 'system.img' \) | head -n1)"
[ -n "$ANDROID_ROOTFS" ] || fail "no android-rootfs.img/system.img inside $GSI_TAR"
if [ "$(basename "$ANDROID_ROOTFS")" != "android-rootfs.img" ]; then
    mv "$ANDROID_ROOTFS" "$STAGE/images/android-rootfs.img"
fi

cp -f "$ROOTFS_GZ" "$STAGE/images/rootfs.img.gz"
cp -f "$DEVICE_TAR" "$STAGE/device_${DEVICE}.tar.xz"

ROOTFS_BYTES="$(gzip -l "$STAGE/images/rootfs.img.gz" | awk 'NR==2 {print $2}')"

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
sakura.build.installer=${ZIP_NAME}
MANIFEST

mkdir -p "$DIST_DIR"
rm -f "$TARGET"
echo "==> Creating zip (store-only for the images, deflate for the rest)"
(cd "$STAGE" && zip -r -q -9 "$TARGET" META-INF device_"${DEVICE}".tar.xz partitions)
(cd "$STAGE" && zip -r -q -0 "$TARGET" images)

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
INFO

echo "==> Done"
ls -lh "$TARGET" "$TARGET.sha256" "${TARGET%.zip}.buildinfo"
echo "sha256: $SHA"
