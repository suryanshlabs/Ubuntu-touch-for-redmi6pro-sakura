# installer/

The recovery installer that turns the build outputs into a flashable zip.

```
META-INF/com/google/android/update-binary   the whole installer (POSIX shell, /sbin/sh)
META-INF/com/google/android/updater-script   stub the recovery requires
```

`scripts/build-zip.sh` copies this tree into the zip and adds:

```
partitions/boot.img          Halium kernel + initramfs
images/rootfs.img.gz         Ubuntu Touch rootfs, ext4, gzipped
images/android-rootfs.img    Halium 10 GSI
device_sakura.tar.xz         device tarball (overlay store, kernel modules)
META-INF/sakura/build.prop   build identification
```

## What the installer does

1. verifies the device is `sakura` (recovery prop, `/proc/cmdline`, or `/tmp/sakura.force`)
2. mounts `/data` and verifies it is really mounted (FBE-encrypted data aborts here)
3. unpacks the zip to `/tmp/sakura-ut-install`
4. checks there is room for rootfs + GSI + 2 GiB headroom
5. backs up the current boot image to `/data/media/0/sakura-ut-backup/boot-stock.img`
6. `dd`s `partitions/boot.img` to `/dev/block/by-name/boot`
7. gunzips `images/rootfs.img.gz` to `/data/rootfs.img`
8. copies the GSI to `/data/android-rootfs.img` and removes a stale `/data/system.img`
9. writes `/data/sakura-ubuntu-touch-build.prop` and prints the reboot/rollback steps

Nothing outside `/data` and the boot partition is touched, and the script is safe to run
twice (it overwrites the two images and keeps the first boot backup).

## Requirements on the recovery side

* OrangeFox or TWRP for sakura (any recovery with toybox/busybox `unzip`, `gzip`, `dd`,
  `awk`, `getprop`)
* `/data` mounted, ext4, not encrypted (or decrypted by the recovery)
* ~7 GB free in `/data`

## Editing

Keep the script POSIX `sh` (`#!/sbin/sh`): recoveries ship busybox/toybox ash, not bash.
There is no `set -e` on purpose — every risky step has an explicit `|| die "..."`, so the
log says which step failed instead of dying silently.
