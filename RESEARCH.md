# Ubuntu Touch on Redmi 6 Pro (sakura) — research

Everything below was gathered while setting this port up. Every claim has a source, every
open question is marked. Nothing here is a promise that the port boots; see
`docs/PORTING_LOG.md` for the current state.

---

## 1. Device

| | |
| --- | --- |
| Marketing name | Xiaomi Redmi 6 Pro (India) / Mi A2 Lite (global, `daisy`) |
| Codename | **sakura** |
| SoC | Qualcomm Snapdragon 625, **MSM8953**, 8x Cortex-A53 @ 2.0 GHz |
| GPU | Adreno 506 |
| RAM | 3 GB (also 4 GB variants) |
| Storage | 32 GB eMMC 5.1 |
| Display | 5.84" IPS, 1080x2280, ~432 ppi |
| Kernel | Linux **4.9.x** (msm-4.9) |
| Userspace | **arm64** (`arm64-v8a` + `armeabi-v7a`) |
| Partitions | dedicated `boot`, `recovery`, `system` (3.0 GiB), `vendor`, **no `super`**, A-only |
| Treble | yes, Android 8.1 launch, `PRODUCT_FULL_TREBLE_OVERRIDE := true` |
| Camera | 12 MP main (IMX486) + 5 MP front (OV5675) |
| Fingerprint | FPC1020 / Goodix (two variants) |
| Current state of the test phone | EvolutionX (Android 15) |

Sources: `mahajant99/device_xiaomi_sakura` and `geopd/device_xiaomi_sakura` `BoardConfig.mk`
(kernel 4.9, `sakura_defconfig`, partition sizes, base addresses), plus the device
specification sheet.

Important consequence: sakura is **not** a dynamic-partition device. There is no `super`
partition, so the `dynparts` Halium initramfs variant is the wrong one, and there is no
vendor_boot/init_boot (Android 8.1 launch, boot header v0).

### Does a port already exist?

No. Checked:

* UBports device list and `ubports/installer-configs/v2/devices` (no `sakura.yml`, no
  `daisy.yml`) — <https://github.com/ubports/installer-configs/tree/master/v2/devices>
* the UBports forum porting section and the `#ubports-porting` Telegram history for
  "sakura" / "daisy"
* GitHub code search for `deviceinfo_halium` + `sakura`

There are Droidian and postmarketOS attempts for MSM8953 Xiaomi devices, but no Ubuntu
Touch port. This repository starts from zero.

---

## 2. Which Halium version, and why 10.0

Ubuntu Touch does not drive the hardware itself. It runs on top of an Android system image
(the "Halium GSI") that already contains the vendor HALs, and libhybris translates
Android HAL calls into glibc calls. The Android version of that GSI must match the Android
version of the **vendor blobs on the phone**. That is what fixes the Halium version.

| Base | Android | Vendor blobs for sakura | Kernel tree | Verdict |
| --- | --- | --- | --- | --- |
| Halium 7.1 | 7.1 | sakura shipped 8.1, so only by downgrading | old, unmaintained | rejected: 32-bit era, no GSI |
| Halium 9.0 | 9 | would need a Pie vendor image | exists (LineageOS 16) | possible fallback |
| **Halium 10.0** | **10** | **LineageOS 17.1 is the best-maintained sakura base** | **`kernel_xiaomi_msm8953`, branch `lineage-17.1`** | **chosen** |
| Halium 11.0 | 11 | unofficial LineageOS 18.1 exists (device tree does) | 4.9 kernel, needs forward-porting | more work, no benefit |
| Halium 12.0 | 12 | sakura never got Android 12 vendor blobs | none | impossible |

So: **Halium 10.0, Android 10, LineageOS 17.1 vendor base.**

Two ties to keep consistent from now on:

* the phone must run an **Android 10 firmware** (LineageOS 17.1 or stock Android 10) before
  Ubuntu Touch is installed — the vendor partition is what Halium talks to
* the kernel must be the **4.9** LineageOS 17.1 tree, because the Halium 10 GSI was built
  against the Android 10 vendor ABI and the 4.9 kernel headers

## 3. Which Ubuntu Touch release

`deviceinfo_ubuntu_touch_release="24.04-2.x"` — Noble, the current stable series. The
build tools accept `24.04-1.x`, `24.04-2.x`, `26.04-1.x` and the legacy `focal` (20.04).

The rootfs comes prebuilt from the UBports CI; there is nothing to compile:

```
https://ci.ubports.com/job/ubuntu-touch-rootfs/job/ubports%2F24.04-2.x/lastStableBuild/artifact/ubuntu-touch-android9plus-rootfs-arm64.tar.gz
```

(Named `android9plus` because one rootfs covers every Halium 9+ device. Verified
`HTTP 200`, `content-length: 971546560` — ~927 MiB.)

## 4. Build method: standalone kernel + prebuilt GSI

There are two ways to produce a Halium port:

| Method | What you build | Size of a source sync | Used here |
| --- | --- | --- | --- |
| Full AOSP/Halium tree (`repo init -u .../Halium/android -b halium-10.0`) | kernel **and** your own `android-rootfs.img` | 60-120 GB, 8+ h build, needs a beefy PC | no |
| **Standalone kernel** (UBports `halium-generic-adaptation-build-tools`) | kernel + `boot.img` + device tarball, prebuilt GSI and rootfs are downloaded | ~2 GB downloads, 20-25 GB working dir, 30-60 min build | **yes** |

Standalone is the documented modern path
(<https://docs.ubports.com/en/latest/porting/build_and_boot/standalone_kernel_build.html>)
and it is the only realistic one here: the phone's 3 GB RAM / 15 GB free storage cannot
host a build, and a full Halium tree is several times larger than a typical dev machine's
free space. It also means the zip can be produced by a GitHub Actions runner.

## 5. Sources, with branches

| Component | Repository | Branch / pin | Used for |
| --- | --- | --- | --- |
| Build tools | <https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools> | `main` | the whole build |
| Kernel | <https://github.com/mahajant99/kernel_xiaomi_msm8953> | `lineage-17.1` | `Image.gz-dtb` |
| Device tree (reference) | <https://github.com/geopd/device_xiaomi_sakura> | `sapphire` | boot image values, partition layout, driver list |
| Device tree (reference) | <https://github.com/mahajant99/device_xiaomi_sakura> | `lineage-18.1` | newer board config, blob list |
| Halium 10 generic device tree | <https://github.com/Halium/android_device_halium_halium> | `halium-10.0` | how the GSI is built (reference only) |
| Example Halium 10 Xiaomi port | <https://github.com/KrutosVIP/halium_device_xiaomi_olivelite> | `halium-10.0` | comparison port on the same SoC family |
| Halium initramfs | <https://github.com/halium/initramfs-tools-halium> | release `continuous`, `initrd.img-touch-arm64` | boot ramdisk |
| Halium 10 arm64 GSI | `ci.ubports.com/.../generic_arm64/job/halium-10.0/lastSuccessfulBuild/artifact/halium_halium_arm64.tar.xz` | latest successful | `android-rootfs.img` (~137 MiB, verified `HTTP 200`) |
| Ubuntu Touch rootfs | `ci.ubports.com/job/ubuntu-touch-rootfs/job/ubports%2F24.04-2.x/...` | `lastStableBuild` | `rootfs.img` (~927 MiB) |
| Installer configs (for later) | <https://github.com/ubports/installer-configs/tree/master/v2/devices> | `master` | `sakura.yml` once the port works |
| Flashable-zip reference port | <https://github.com/itswill00/tanzanite-ubuntu-touch> | `main` | proof that a recovery installer zip is viable, zip layout |
| Docs — porting | <https://docs.ubports.com/en/latest/porting/> | | |
| Docs — Halium install | <https://docs.ubports.com/en/latest/porting/build_and_boot/Halium_install.html> | | |
| Docs — standalone kernel | <https://docs.ubports.com/en/latest/porting/build_and_boot/standalone_kernel_build.html> | | |
| Halium docs — distribution | <https://docs.halium.org/en/latest/Distribution.html> | | `rootfs.img` / `boot.img` contract |

## 6. `deviceinfo` values and where they come from

The build tools read a shell `deviceinfo` file (`deviceinfo.sample` in the build tools
repo is the authority). The keys suggested in the original request are mostly Android
device-tree/Halium-CI keys; the table maps them.

| Requested key | Actually used | Value | Source |
| --- | --- | --- | --- |
| `deviceinfo_name` | ✔ | Redmi 6 Pro | `ro.product.model` |
| `deviceinfo_manufacturer` | ✔ | Xiaomi | |
| `deviceinfo_codename` | ✔ | sakura | `ro.product.name` |
| `deviceinfo_device_type` | — (runtime YAML key) | `DeviceType: phone` | `device/overlay/.../sakura.yaml` |
| `deviceinfo_kernel_codename` | — (not a key) | — | |
| `deviceinfo_architecture` | `deviceinfo_arch` | `aarch64` | SoC |
| — | `deviceinfo_kernel_arch` | `arm64` | SoC |
| `deviceinfo_halium_version` | ✔ | `10` | §2 |
| `deviceinfo_ubuntu_touch_release` | ✔ | `24.04-2.x` | §3 |
| `deviceinfo_kernel_defconfig` | ✔ | `sakura_defconfig` | `TARGET_KERNEL_CONFIG` in `BoardConfig.mk` |
| `deviceinfo_kernel_header_version` | `deviceinfo_bootimg_header_version` | `0` | Android 8.1 launch, LineageOS sets no header version |
| `deviceinfo_bootimg_prebuilt_dtb` | omitted | — | MSM8953 4.9 emits `Image.gz-dtb` with the DTB appended |
| `deviceinfo_kernel_cmdline` | ✔ | stock LineageOS cmdline + `console=tty0` + `androidboot.selinux=permissive` | `BoardConfig.mk` + Halium docs (`console=tty0` is mandatory) |
| `deviceinfo_kernel_clang_compile` | ✔ | `true` | LineageOS builds this kernel with clang |
| `deviceinfo_build_number`, `deviceinfo_operating_system`, `deviceinfo_security_patch` | — | not used by the build tools | |
| — | `deviceinfo_flash_pagesize` | `2048` | `BOARD_KERNEL_PAGESIZE` |
| — | `deviceinfo_flash_offset_base` | `0x80000000` | `BOARD_KERNEL_BASE` |
| — | `deviceinfo_flash_offset_kernel` | `0x00008000` | default, base+0x8000 = `0x80008000` |
| — | `deviceinfo_flash_offset_ramdisk` | `0x01000000` | `--ramdisk_offset` |
| — | `deviceinfo_flash_offset_tags` | `0x00000100` | `--tags_offset` |
| — | `deviceinfo_bootimg_partition_size` | `67108864` | `BOARD_BOOTIMAGE_PARTITION_SIZE` |
| — | `deviceinfo_prebuilt_boot_ramdisk_source` | Halium `continuous` arm64 initrd | non-dynparts, see §7 |
| — | `deviceinfo_rootfs_image_sector_size` | `4096` | eMMC logical sector size |
| — | `deviceinfo_system_partition_size` | `4096M` | rootfs image size cap (system is only 3.0 GiB, hence /data install) |
| — | `deviceinfo_use_overlaystore` | `true` | required for 20.04+ |
| — | `deviceinfo_kernel_image_name` | `Image.gz-dtb` | `BOARD_KERNEL_IMAGE_NAME` |

GridUnit 21 in `sakura.yaml`: 420 dpi (`TARGET_SCREEN_DENSITY := 420`) is xxhdpi class, and
DeviceInfo's `GridUnit` is 21 for that class on a 5.8" panel.

## 7. Initramfs / boot images

The upstream tools default to the **dynparts** initramfs
(`.../releases/download/dynparts/initrd.img-touch-arm64`), which expects a `super` partition
and lvm. sakura has neither, so `deviceinfo` pins the plain Halium 10 ramdisk from the
`continuous` release instead.

What the initramfs does at boot (from `halium/initramfs-tools-halium`, script
`scripts/halium`):

* mounts the Android partitions from the fstab (`/vendor`, `/system`, ...)
* looks for the Ubuntu rootfs image at `/data/rootfs.img` and mounts it as the new root
* looks for the Android system image: `/data/system.img` (mounted at `/android/system`) or
  `/data/android-rootfs.img` (mounted at `/android`), or
  `/halium-system/var/lib/lxc/android/{system,android-rootfs}.img`
* writes `persist.halium.*` props and `switch_root`s into the rootfs

This is why the installer writes exactly `/data/rootfs.img` and `/data/android-rootfs.img`,
and why `systempart=` is **not** in the cmdline (that would be the system-as-root path).

Halium 10 GSIs are system-as-root, so the file must be named `android-rootfs.img`
(`halium-install -s` does the same rename). `halium-install`'s own layout is the reference:
`rootfs.img` + `system.img`, renamed to `android-rootfs.img` for system-as-root.

## 8. Size, storage and RAM

| Item | Size |
| --- | --- |
| `workdir/downloads` after the clone pass (clang, gcc 4.9, mkbootimg, kernel) | ~1.8-2.2 GB |
| kernel build output (`workdir/downloads/KERNEL_OBJ`) | ~2-4 GB |
| `out/device_sakura.tar.xz` | ~25-35 MB |
| `out/boot.img` | ~18-22 MB |
| rootfs tarball download | ~927 MiB |
| Halium 10 GSI download | ~137 MiB |
| `out/rootfs.img` (4 GiB filesystem) | ~2.3-2.6 GiB used |
| `out/rootfs.img.gz` | ~800 MiB-1.1 GiB |
| `dist/*.zip` | ~1.0-1.3 GiB |
| **Total disk for a full build** | **20-30 GB** (60 GB comfortable) |
| **RAM for the kernel build** | 6 GB minimum, 8 GB+ comfortable (`-j$(nproc)`) |
| **Build time** | 30-60 min first run on 4 cores, 5-15 min incremental |
| **Install space on the phone** | `/data/rootfs.img` ~3 GB + `/data/android-rootfs.img` ~1 GB + 2 GB headroom = ~7 GB free |

The phone cannot build this: 3 GB RAM + 2 GB swap is below what the kernel build needs, and
15 GB free storage is less than half of what a build consumes. Termux can only `git clone`
for reading, edit files, and run the small scripts.

## 9. Bootloader and firmware hurdles

1. **Unlock**: Xiaomi's process needs the Mi Unlock tool (Windows/VM), a Mi account bound to
   the phone for 7 days, and a SIM/network check. `fastboot oem unlock` afterwards.
2. **Anti-rollback (ARB)**: index 4 on sakura Android 9+ firmware — never flash an older
   firmware package, or the phone hard-bricks. Only flash Android 10 or newer ROMs.
3. **AVB/vbmeta**: the Halium boot image is not signed. Installations normally work because
   the bootloader is unlocked and `fastboot oem` verification is relaxed, but if the phone
   refuses to boot, flash a vbmeta with verification disabled
   (`fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img`).
4. **FBE**: Android 9+ userdata is file-based encrypted. A Halium initramfs cannot mount it.
   The device must be formatted to ext4 without FBE first (this destroys Android data), or
   the recovery must decrypt it. This is the single most common reason a first install
   fails.
5. **Treble**: sakura is a Treble device, so `vendor` is a separate partition with the HALs.
   Keeping the Android 10 vendor partition intact is what makes the Halium 10 GSI work.
6. **A-only, no super**: no slot suffixes, no dynamic partitions, no vendor_boot — the
   deviceinfo reflects that (boot header v0, plain ramdisk, no dtbo).

## 10. Known issues from comparable ports

* **Display/touch**: MSM8953 Xiaomi devices with multiple panel vendors need the right DTB
  compatible string; a wrong panel gives a black screen with a working `adb`.
* **Adreno + Mir**: older Adreno blobs sometimes need `deviceinfo_lomiri_disable_hardware_acceleration`
  or a `mir` platform config in the rootfs overlay; the tanzanite port ships
  `/usr/lib/aarch64-linux-gnu/mir/` platform files for the same reason.
* **Audio**: needs the correct `audio_platform_info.xml`/mixer paths from the Android 10
  vendor partition; missing `halium-override` modules produce silent devices.
* **Kernel modules**: if `CONFIG_MODULES` modules are built but not installed into the
  overlay store, Wi-Fi/BT/sensors silently fail. `deviceinfo_use_overlaystore="true"` +
  the device tarball handles this.
* **SELinux**: permissive is fine for bring-up; enforcing needs a device policy for the
  Halium binder/ashmem nodes.
* **Fingerprint**: FPC vs Goodix halves the chance of a working sensor on the first try —
  the correct HAL (`fpc` or `gf_fingerprint`) depends on the hardware variant.

## 11. Bring-up / test plan

1. **Kernel only**: flash `boot.img`, boot with `fastboot boot` is not possible (Android
   boot image with Halium ramdisk needs `/data`), so flash it and watch `adb devices`.
   Success: the phone enumerates as a USB device and `/data/rootfs.img` gets mounted.
2. **Initramfs**: `adb shell dmesg | grep -i halium`, check that `/android` and the rootfs
   mounted, then watch systemd start.
3. **UI**: Lomiri greeter appears -> display and touch work.
4. **Per-feature**, one flash each: Wi-Fi (`nmcli`), audio (`pactl`), calls (`ofono`),
   Bluetooth (`bluetoothctl`), camera (`qtmultimedia` test app), fingerprint (Settings ->
   Security), sensors (`sensorfw` / `lomiri-system-settings`).
5. Record every result in `docs/PORTING_LOG.md` — the log is the only source of truth for
   what actually works.

## 12. Alternatives considered

| Option | Why not |
| --- | --- |
| Build the full Halium 10 Android tree + own GSI | 60-120 GB, hours of build, no benefit while the generic GSI works |
| Halium 11 on the LineageOS 18.1 device tree | no Android 11 vendor blobs for sakura; the vendor partition runs Android 10 |
| System-as-root install on the `system` partition | the partition is 3.0 GiB, the 24.04 rootfs is ~2.4 GiB *before* the GSI — no room for updates |
| `adb`-based install with `halium-install` (no zip) | works, but the request is a recovery-flashable zip; the zip also works without a PC |
| Porting via Droidian forks | different project, different packaging; useful only as a kernel reference |

## 13. Sources index

* UBports porting docs — <https://docs.ubports.com/en/latest/porting/>
* Halium docs — <https://docs.halium.org/en/latest/>
* Halium boot/rootfs contract — <https://docs.halium.org/en/latest/Distribution.html>
* Build tools + `deviceinfo.sample` — <https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools>
* Shared CI pipeline — `gsi-port-ci.yml` in the same repository
* Halium initramfs — <https://github.com/halium/initramfs-tools-halium>
* Reference flashable-zip port — <https://github.com/itswill00/tanzanite-ubuntu-touch>
* Installer configs — <https://github.com/ubports/installer-configs>
