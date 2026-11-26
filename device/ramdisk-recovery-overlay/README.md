# device/ramdisk-recovery-overlay

Overlay for a **custom** Halium recovery ramdisk (`ramdisk-recovery.img`).

This port does **not** ship its own recovery: installation is done from OrangeFox/TWRP,
which is a complete, maintained recovery with a working UI, decryption and ADB. Building a
recovery image is therefore disabled in `deviceinfo` (no `deviceinfo_has_recovery_partition`,
no `deviceinfo_use_unified_recovery`).

Keep this directory for the day a UBports-style recovery is wanted:

1. add `deviceinfo_use_unified_recovery="true"` to `deviceinfo`
   (or drop a `ramdisk-recovery.img` next to it),
2. add `deviceinfo_has_recovery_partition="true"` and
   `deviceinfo_recovery_partition_size="67108864"` (sakura's recovery partition is 64 MiB),
3. put files here that must replace files inside that ramdisk — the upstream
   `make-bootimage.sh` copies this tree over the extracted ramdisk.

Typical contents would be a device `fstab.qcom` (already present in the LineageOS device
tree, `rootdir/etc/fstab.qcom`) and a `prop.default` with
`ro.halium.fastbootd=true` for debugging.
