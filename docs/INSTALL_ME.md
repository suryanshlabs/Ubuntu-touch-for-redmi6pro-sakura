# Installing on Redmi 6 Pro (sakura)

**Read this whole page before flashing.** This replaces your OS — it is *not* a dual-boot
install and there is no boot menu. The installer overwrites the boot image with the Halium
kernel and initramfs, so the phone boots straight into Ubuntu Touch and Android stops booting.
The Ubuntu rootfs is kept as two files in `/data` only because sakura's 3.0 GiB system
partition cannot hold the 4 GiB image; Android's own files there are left untouched, and
flashing the saved `boot-stock.img` brings Android back.

> **Status:** the zip produced by this repository has **never been flashed to hardware**.
> Treat the first flash as an experiment on a phone whose data you can lose.

---

## 1. Prerequisites

| Requirement | Why | How |
| --- | --- | --- |
| Unlocked bootloader | nothing can be flashed otherwise | Xiaomi Mi Unlock: 7-day waiting period, Windows tool or a Windows VM, then `fastboot oem unlock` |
| OrangeFox (or TWRP) for sakura | the installer is a recovery zip | `fastboot flash recovery OrangeFox-sakura.img`, then boot straight into recovery |
| Android 10 firmware (LineageOS 17.1 or stock Android 10) | Halium 10 links against the Android 10 vendor HALs | flash a LineageOS 17.1 build first if the phone runs something newer |
| `/data` formatted as **ext4** and **not encrypted** | the Halium initramfs mounts `/data` without FBE/FDE support | see step 2 |
| ~7 GB free in `/data` | rootfs image (~3 GB) + GSI (~1 GB) + headroom | check with `df -h /data` |
| A PC with `adb`/`fastboot` | backups and rollback | `sudo apt install android-tools-adb android-tools-fastboot` |

Ubuntu Touch does **not** support FBE-encrypted `/data`. If your Android install uses file
based encryption (all Android 9+ builds do by default), the recovery must decrypt it with
your PIN/pattern. If your recovery cannot, the only path is formatting `/data` (Android data
is lost).

## 2. Prepare the phone

1. Boot into OrangeFox (Power + Volume Down -> *Recovery*).
2. *Wipe -> Advanced Wipe -> Data -> Repair or Change File System -> ext4*.
   Keep the filesystem as ext4; do **not** choose f2fs.
3. If you want to keep Android data, do **not** format — instead make sure recovery can
   decrypt `/data` (it asks for the PIN when you open the *Files* tab). If it cannot
   decrypt, stop: this install would corrupt your Android data.
4. Back up `boot` (the recovery can do it: *Backup -> Boot*). The installer also writes
   `/sdcard/sakura-ut-backup/boot-stock.img` before touching anything.

## 3. Flash

1. Copy the zip to the phone (`adb push sakura-ut24.04-halium10-*.zip /sdcard/`).
2. In OrangeFox: *Install -> select the zip -> swipe to confirm*.
3. Watch the log. It prints each stage:

```
[*] Device check passed (sakura)
[*] /data mounted
[*] Free space check passed (20480 MiB available, 6246 MiB needed)
[*] Unpacking images into /data (this takes a minute)...
[*] Backing up the current boot image to /data/media/0/sakura-ut-backup
[*] Boot image fits the partition (67108864 of 67108864 bytes)
[*] Flashing Halium boot image to /dev/block/by-name/boot
[*] Writing /data/rootfs.img (usually 2-4 minutes)...
[*] Writing /data/android-rootfs.img
[+] Ubuntu Touch 24.04 for sakura has been installed.
```

4. Reboot to **system** (not recovery, not bootloader — the first boot must not go through
   fastboot, it would only boot Android's kernel).

## 4. Fastboot alternative (no recovery zip)

If you only want the boot image (for example to debug the kernel), the zip also contains it:

```bash
unzip -o sakura-ut24.04-halium10-*.zip partitions/boot.img
fastboot flash boot partitions/boot.img
fastboot reboot
```

This alone will **not** give you a working Ubuntu Touch: `/data/rootfs.img` and
`/data/android-rootfs.img` must exist. Use the recovery zip for a full install.

## 5. First boot

* 5-10 minutes is normal. The screen stays dark/backlit for several minutes while the
  rootfs is resized and the Android container starts.
* Then the Lomiri welcome wizard appears (language, Wi-Fi, no Google account).
* If nothing happens after 15 minutes, connect USB and check the kernel log from a PC:

```bash
sudo apt install android-tools-adb
adb devices            # if adb sees the phone, the kernel + initramfs work
adb shell dmesg | tail -50
```

* If `adb devices` shows nothing, the kernel did not reach the initramfs — see below.

## 6. Rollback to Android

The installer keeps Android's boot image:

```bash
adb pull /sdcard/sakura-ut-backup/boot-stock.img
adb reboot bootloader
fastboot flash boot boot-stock.img
fastboot reboot
```

or from OrangeFox: *Install image -> boot-stock.img -> Boot*.

To remove the Ubuntu files as well (they are just two files in `/data`):

```bash
adb shell rm -f /data/rootfs.img /data/android-rootfs.img /data/sakura-ubuntu-touch-build.prop
```

## 7. Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Installer aborts with *"This package is for sakura"* | recovery reports a different codename; create `/tmp/sakura.force` in recovery (`adb shell touch /tmp/sakura.force`) only if you are certain |
| *"/data is not mounted"* | encrypted `/data` the recovery cannot decrypt, or f2fs — reformat as ext4 |
| *"Not enough free space"* | `/data` has less than ~7 GB free; delete files or build a smaller rootfs (`ROOTFS_SIZE=3G`) |
| Boot loop at the Xiaomi logo | wrong boot header version or offsets; rebuild with `deviceinfo_bootimg_header_version="1"` (or `"2"`) and try again |
| Boot loop after the logo, then recovery | rootfs image missing/corrupt: check `/data/rootfs.img` exists and is ~3 GB |
| Black screen, `adb` works, no UI | Mir/Adreno problem — check `adb shell systemctl status lomiri` and `journalctl -b` |
| Wi-Fi/modem dead, everything else fine | the Halium GSI is not matching the Android 10 vendor blobs; reflash the Android 10 base and the GSI |
| Touch inverted / wrong axis | panel variant; needs a device-specific kernel dts fix, see `docs/PORTING_LOG.md` |

## 8. Where things live

| Path | Size | What |
| --- | --- | --- |
| `/dev/block/by-name/boot` | 64 MiB | Halium kernel + initramfs (replaces Android's boot) |
| `/data/rootfs.img` | ~3 GB | Ubuntu Touch rootfs, ext4 |
| `/data/android-rootfs.img` | ~1 GB | Halium 10 GSI (Android rootfs, mounted at `/android`) |
| `/data/sakura-ubuntu-touch-build.prop` | few bytes | build identification |
| `/sdcard/sakura-ut-backup/boot-stock.img` | 64 MiB | original Android boot image |
