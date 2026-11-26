#!/usr/bin/env bash
#
# Fast sanity checks that run before the expensive kernel build.
#
# Every one of these catches a mistake that would otherwise cost a full build cycle
# (the kernel alone is 30-60 minutes), so the CI runs this first.
#
# Usage: ./scripts/preflight.sh
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ERRORS=0
ok()   { echo "  ok    $*"; }
bad()  { echo "  FAIL  $*"; ERRORS=$((ERRORS + 1)); }
warn() { echo "  warn  $*"; }

echo "==> deviceinfo"
if ! bash -n deviceinfo 2>/dev/null; then
    bad "deviceinfo does not parse as shell"
else
    # shellcheck source=/dev/null
    . ./deviceinfo

    REQUIRED="deviceinfo_name deviceinfo_manufacturer deviceinfo_codename
              deviceinfo_arch deviceinfo_halium_version deviceinfo_ubuntu_touch_release
              deviceinfo_kernel_source deviceinfo_kernel_source_branch
              deviceinfo_kernel_defconfig deviceinfo_kernel_cmdline
              deviceinfo_bootimg_header_version deviceinfo_bootimg_os_version
              deviceinfo_bootimg_os_patch_level deviceinfo_flash_pagesize
              deviceinfo_prebuilt_boot_ramdisk_source deviceinfo_kernel_image_name"
    for key in $REQUIRED; do
        if [ -z "${!key:-}" ]; then bad "$key is empty (the build tools need it)"; fi
    done

    case "${deviceinfo_arch:-}" in
        arm|aarch64|x86|x86_64) ok "deviceinfo_arch=$deviceinfo_arch" ;;
        *) bad "deviceinfo_arch='${deviceinfo_arch:-}' is not one of arm|aarch64|x86|x86_64" ;;
    esac
    case "${deviceinfo_kernel_arch:-$deviceinfo_arch}" in
        arm|arm64|aarch64|x86|x86_64) ;;
        *) bad "deviceinfo_kernel_arch must be arm|arm64|aarch64|x86|x86_64" ;;
    esac
    # The toolchain prefix comes from this value; "arm64" produces arm64-linux-android-,
    # which does not exist in the prebuilt toolchains.
    if [ "$deviceinfo_arch" = "arm64" ]; then
        bad "deviceinfo_arch must be aarch64, not arm64 (see docs/PORTING_LOG.md)"
    fi
    case "${deviceinfo_bootimg_os_version:-}" in
        ''|*[!0-9.]*) bad "deviceinfo_bootimg_os_version='${deviceinfo_bootimg_os_version:-}' must be numeric (e.g. 10)" ;;
        *) ok "boot img os_version=$deviceinfo_bootimg_os_version patch=${deviceinfo_bootimg_os_patch_level:-}" ;;
    esac
    case "${deviceinfo_kernel_cmdline:-}" in
        *console=tty0*) ok "cmdline has console=tty0" ;;
        *) bad "deviceinfo_kernel_cmdline must contain console=tty0 or the rootfs will not boot" ;;
    esac
    if [ -n "${deviceinfo_bootimg_partition_size:-}" ]; then
        warn "deviceinfo_bootimg_partition_size is set: make-bootimage.sh will call avbtool without a key"
    fi
fi

echo "==> kernel repository"
if git ls-remote --exit-code --heads "${deviceinfo_kernel_source:-}" "${deviceinfo_kernel_source_branch:-}" >/dev/null 2>&1; then
    ok "$deviceinfo_kernel_source ($deviceinfo_kernel_source_branch)"
else
    bad "cannot reach $deviceinfo_kernel_source branch $deviceinfo_kernel_source_branch"
fi

echo "==> download URLs"
check_url() {
    local url="$1" name="$2" code
    code="$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 60 -r 0-0 "$url" 2>/dev/null)"
    case "$code" in
        200|206) ok "$name ($code)" ;;
        *) bad "$name -> HTTP $code: $url" ;;
    esac
}
check_url "${deviceinfo_prebuilt_boot_ramdisk_source:-}" "halium boot ramdisk"
check_url "${ROOTFS_URL:-https://ci.ubports.com/job/ubuntu-touch-rootfs/job/ubports%2F24.04-2.x/lastStableBuild/artifact/ubuntu-touch-android9plus-rootfs-arm64.tar.gz}" "ubuntu touch rootfs"
check_url "${GSI_URL:-https://ci.ubports.com/job/UBportsCommunityPortsJenkinsCI/job/ubports%2Fporting%2Fcommunity-ports%2Fjenkins-ci%2Fgeneric_arm64/job/halium-10.0/lastSuccessfulBuild/artifact/halium_halium_arm64.tar.xz}" "halium 10 gsi"

echo "==> port-root overlay"
# build-tarball-mainline.sh runs `cp -av overlay/* "$dir/"` unconditionally, so the
# directory must exist and contain at least one file.
if [ -d overlay ] && [ -n "$(ls -A overlay 2>/dev/null)" ]; then
    ok "overlay/ exists and is not empty"
else
    bad "overlay/ is missing or empty: build-tarball-mainline.sh fails with 'cp: cannot stat overlay/*'"
fi

echo "==> scripts"
for f in build.sh scripts/*.sh; do
    [ -f "$f" ] || continue
    if bash -n "$f" 2>/dev/null; then ok "$f (bash syntax)"; else bad "$f has a bash syntax error"; fi
done
# The installer runs under busybox/toybox ash, so it must stay POSIX sh.
if sh -n installer/META-INF/com/google/android/update-binary 2>/dev/null; then
    ok "installer update-binary (posix sh syntax)"
else
    bad "installer update-binary is not valid POSIX sh"
fi

echo
if [ "$ERRORS" -ne 0 ]; then
    echo "preflight: $ERRORS problem(s) found, refusing to start a 1-hour build" >&2
    exit 1
fi
echo "preflight: all checks passed"
