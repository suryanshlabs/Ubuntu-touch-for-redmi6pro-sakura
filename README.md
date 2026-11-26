# Ubuntu Touch for Redmi 6 Pro (sakura)

A community Ubuntu Touch 24.04 (Halium 10) port for the **Xiaomi Redmi 6 Pro — codename
`sakura`**, delivered as an **OrangeFox / TWRP flashable zip**.

> **Status: WIP / Planning.** This repository contains a complete build pipeline, but the
> port has not been compiled or flashed on hardware yet. The status stays WIP until a build
> in GitHub Actions succeeds *and* that zip boots on a phone. See
> [docs/PORTING_LOG.md](docs/PORTING_LOG.md) for exactly what is verified and what is not.

---

## Device

| | |
| --- | --- |
| Name | Xiaomi Redmi 6 Pro (India) / Mi A2 Lite (global, `daisy`) |
| Codename | **sakura** |
| SoC | Qualcomm Snapdragon 625 (MSM8953), 8x Cortex-A53 @ 2.0 GHz, Adreno 506 |
| RAM / storage | 3 GB / 32 GB (a 4 GB variant exists) |
| Display | 5.84" IPS, 1080x2280, ~432 ppi |
| Kernel | Linux 4.9 (msm-4.9), arm64 |
| Partitions | boot, recovery, system (3.0 GiB), vendor, **no super**, A-only |
| Camera | 12 MP IMX486 rear + 5 MP OV5675 front |
| Fingerprint | FPC1020 / Goodix, depending on the device variant |

Full research, sources and decisions: [RESEARCH.md](RESEARCH.md).

## What is targeted

| Piece | Choice | Why |
| --- | --- | --- |
| Halium version | **10.0** (Android 10) | LineageOS 17.1 is the best-maintained sakura base and matches the Android 10 vendor blobs |
| Ubuntu Touch release | **24.04-2.x** (Noble) | current stable series |
| Kernel | 4.9, `mahajant99/kernel_xiaomi_msm8953`, branch `lineage-17.1` | the tree the sakura device trees build against |
| Build method | Standalone kernel (UBports `halium-generic-adaptation-build-tools`) | 20-30 GB and one CI runner; a full Halium tree needs 60-120 GB |
| Install method | **Flashable zip via OrangeFox / TWRP**, dual-boot in `/data` | sakura's system partition is only 3.0 GiB |

`systempart=` is deliberately **not** in the kernel cmdline: the rootfs lives at
`/data/rootfs.img` and the Android GSI at `/data/android-rootfs.img`.

## Build (GitHub Actions)

```bash
git push origin main                        # build only -> workflow artifacts
git tag v0.1.0 && git push origin v0.1.0    # build + GitHub Release
```

`.github/workflows/build.yml` installs the dependencies, runs `./scripts/preflight.sh`
(seconds; validates `deviceinfo`, the download URLs and every script), runs `./build.sh`
(kernel + boot image), downloads the UT rootfs and the Halium 10 GSI, builds `rootfs.img`,
and packages `dist/sakura-ut24.04-halium10-v*.zip` together with its `.sha256` and
`.buildinfo`. If the clang toolchain cannot build the kernel, the workflow retries the
build with the GCC 4.9 prebuilts instead of failing.

Local build, with the exact apt packages and the expected output of each step:
[docs/BUILD_ME.md](docs/BUILD_ME.md).

```bash
./scripts/preflight.sh                  # validate config/URLs/scripts first
./build.sh                              # kernel + boot.img + device tarball
./scripts/fetch-prebuilts.sh            # rootfs (927 MiB) + Halium 10 GSI (137 MiB)
sudo -E ./scripts/make-rootfs-image.sh  # ext4 rootfs image + device overlay
./scripts/build-zip.sh                  # -> dist/*.zip
```

## Install

Requirements: unlocked bootloader, OrangeFox/TWRP for sakura, Android 10 firmware installed,
`/data` formatted ext4 and not encrypted, ~7 GB free in `/data`.

The installer backs up the Android boot image to
`/sdcard/sakura-ut-backup/boot-stock.img` before touching anything, so the phone can always
go back to Android. Full step-by-step instructions, including rollback:
[docs/INSTALL_ME.md](docs/INSTALL_ME.md).

## Hardware status

Nothing has been booted yet, so this table is a **plan**, not a result:

| Feature | Status |
| --- | --- |
| Display, touch | untested |
| Wi-Fi, Bluetooth | untested |
| Cellular, SMS, data | untested |
| Audio, mic, speaker | untested |
| Camera | untested |
| Fingerprint | untested |
| Sensors, vibration | untested |

Each row gets a real result in [docs/PORTING_LOG.md](docs/PORTING_LOG.md) once the build
has run and someone flashes it.

## Repository layout

```
.
├── README.md                     this file
├── RESEARCH.md                   specs, Halium choice, sources, sizes, hurdles
├── deviceinfo                    Halium build config (sakura, Halium 10, arm64)
├── build.sh                      wrapper around the UBports build tools
├── .github/workflows/build.yml   CI: build -> zip -> artifacts / GitHub Release
├── .gitlab-ci.yml                UBports shared pipeline (optional)
├── device/
│   ├── halium.config             kernel config fragment (binder, namespaces, cgroups)
│   ├── overlay/system/...        rootfs overlay: deviceinfo YAML, udev rules
│   └── ramdisk-recovery-overlay/ overlay for a future UBports recovery
├── kernel/README.md              which kernel, why, what is still open
├── proprietary/README.md         vendor blobs: where they come from, how to extract
├── installer/                    recovery installer (update-binary + updater-script)
├── scripts/
│   ├── preflight.sh
│   ├── prepare-kernel-config.sh
│   ├── fetch-prebuilts.sh
│   ├── make-rootfs-image.sh
│   ├── build-zip.sh
│   ├── prepare-ota.sh
│   └── extract-blobs.sh
└── docs/
    ├── BUILD_ME.md
    ├── INSTALL_ME.md
    └── PORTING_LOG.md
```

## Contribute

1. Build it (or wait for a CI run) and flash it. Every result is useful.
2. Fix one feature at a time and put the fix where it belongs:
   * userspace / permissions -> `device/overlay/system/...`
   * kernel config -> `device/halium.config`
   * boot or kernel arguments -> `deviceinfo`
   * installer bugs -> `installer/META-INF/com/google/android/update-binary`
3. Write what you learned into `docs/PORTING_LOG.md`, including the failing command and the
   fix. A port without a log is a port nobody can continue.
4. When everything works, open a merge request against `ubports/installer-configs` with a
   `sakura.yml`.

## Credits

* **UBports** — Ubuntu Touch, `halium-generic-adaptation-build-tools`, rootfs CI
* **Halium** — `initramfs-tools-halium`, generic GSI (`Halium/android_device_halium_halium`)
* **LineageOS** — `android_system_tools_mkbootimg`, sakura device trees
* **Xiaomi sakura devs**:
  * `geopd/device_xiaomi_sakura` (branch `sapphire`)
  * `mahajant99/device_xiaomi_sakura` (branch `lineage-18.1`)
  * `mahajant99/kernel_xiaomi_msm8953` (branch `lineage-17.1`)
* `KrutosVIP/halium_device_xiaomi_olivelite` — Halium 10 Xiaomi example port
* `itswill00/tanzanite-ubuntu-touch` — reference for the recovery-installer zip format
* **libhybris** — the Android driver compatibility layer

## Links

* UBports porting guide — <https://docs.ubports.com/en/latest/porting/>
* Halium docs — <https://docs.halium.org/en/latest/>
* UBports forum — <https://forums.ubports.com>
* Telegram: porting <https://t.me/ubports_porting> · general <https://t.me/ubports> ·
  Halium <https://t.me/HaliumOS>
* XDA Ubuntu Touch — <https://xdaforums.com/c/ubuntu-touch.2068/>

## License

Build scripts, deviceinfo, overlays and documentation in this repository: MIT-style, use
them freely. Kernel: GPL-2.0 (upstream). Ubuntu Touch and Halium: their own licenses.
Xiaomi vendor blobs are not distributed here — see `proprietary/`.
