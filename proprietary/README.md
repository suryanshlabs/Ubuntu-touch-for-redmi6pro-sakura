# proprietary/

No vendor blobs are stored in this repository. This directory documents where they come
from and when you need them.

## Do I need blobs to build the flashable zip?

**No.** The normal path uses the prebuilt generic Halium 10 arm64 GSI, which already talks
to the vendor partition through libhybris. The vendor partition itself (drivers, firmware,
HALs) comes from the Android 10 firmware that is already on the phone.

You only need blobs if you want to:

* rebuild the Halium GSI yourself (`android_device_halium_halium`, halium-10.0), or
* build a device-specific Android system image instead of the generic GSI, or
* debug a HAL that is missing from the generic GSI.

## Sources

| What | Where | Notes |
| --- | --- | --- |
| Android 10 vendor tree | `vendor/xiaomi/sakura` from a LineageOS 17.1 build | extracted from the ROM, not redistributable here |
| Stock firmware | Xiaomi `sakura` Android 10 fastboot ROM (`sakura_global_images_...`) | `vendor.img`, `system.img`, `firmware_mnt` |
| LineageOS 17.1 ROM | the latest official/unofficial `sakura` build | easiest source: unpack `vendor.img` |

Blobs must always come from a **sakura Android 10** firmware, never from Android 11/12 —
a Halium 10 port links against the Android 10 HAL ABI.

## Extracting

```bash
# from a connected device running Android 10 / LineageOS 17.1
./scripts/extract-blobs.sh --adb

# or from an unpacked ROM directory (system/vendor/ tree on disk)
./scripts/extract-blobs.sh --dir /path/to/unpacked_rom

# just look at what would be copied
./scripts/extract-blobs.sh --list /path/to/unpacked_rom
```

Output lands in `vendor/xiaomi/sakura/proprietary/` plus a generated
`vendor/xiaomi/sakura/sakura-vendor.mk`. Both are git-ignored on purpose.

## Not included, and why

Nothing in `proprietary/` is GPL-clean to redistribute: the Xiaomi blobs are proprietary,
and the firmware images are also carrier/Xiaomi licensed. Keep them local; do not open a PR
that adds them.
