# Building Ubuntu Touch for Redmi 6 Pro (sakura)

Everything is built on an **x86_64 Linux host**. The phone (Termux) cannot build this: a
Halium kernel build plus the rootfs image needs roughly 25 GB of disk and 6-8 GB of RAM,
and the ARM toolchain prebuilts the UBports tools download are `linux-x86` binaries.

Two ways to build:

* [GitHub Actions](#github-actions-recommended) — nothing to install, push and download
* [Local host](#local-host) — Ubuntu 22.04 / 24.04, ~30-60 min per build after the first

The first build is the slow one: it downloads ~2 GB of prebuilts (clang, gcc 4.9,
mkbootimg, kernel source) and compiles the kernel.

---

## GitHub Actions (recommended)

`.github/workflows/build.yml` does the whole thing on `ubuntu-22.04`:

1. installs the build dependencies
2. runs `./build.sh` (clones build tools + kernel, merges `device/halium.config`, builds
   `Image.gz-dtb` and `boot.img`, packs `device_sakura.tar.xz`)
3. runs `./scripts/fetch-prebuilts.sh` (UT 24.04 rootfs + Halium 10 GSI)
4. runs `sudo ./scripts/make-rootfs-image.sh` (ext4 rootfs image + overlay)
5. runs `./scripts/build-zip.sh` (flashable zip)
6. uploads the zip as a workflow artifact; on a `v*` tag it also creates a GitHub Release

To trigger it:

```bash
git push origin main                 # build only
git tag v0.1.0 && git push origin v0.1.0   # build + release
```

or *Actions -> build-ubuntu-touch-sakura -> Run workflow* and fill in `release_tag`.

Downloads: the workflow's *Artifacts*, or the *Releases* page for tagged builds.

---

## Local host

### 1. Host requirements

| | Minimum | Recommended |
| --- | --- | --- |
| OS | Ubuntu 22.04 x86_64 | Ubuntu 22.04 / 24.04 x86_64 |
| Disk | 30 GB free | 60 GB free |
| RAM | 6 GB | 8 GB+ (kernel build uses `-j$(nproc)`) |
| CPU | 4 cores | 8 cores |

```bash
sudo apt update
sudo apt install -y --no-install-recommends \
    bc bison build-essential ca-certificates cpio curl fakeroot flex git kmod \
    libelf-dev libssl-dev libtinfo5 lz4 python2 python3 sudo unzip wget xz-utils \
    pahole libbpf-dev zip android-sdk-libsparse-utils
sudo ln -sf /usr/bin/python2 /usr/bin/python    # kernel 4.9 scripts still use python2
```

`libtinfo5` and `python2` only exist on 22.04; on 24.04 either use the 22.04 container
(`docker run -it --privileged -v "$PWD:$PWD" -w "$PWD" ubuntu:22.04 bash`) or install the
older packages from the 22.04 archive. GitHub Actions uses 22.04 for this reason.

### 2. Get the repository

```bash
git clone https://github.com/suryanshlabs/Ubuntu-touch-for-redmi6pro-sakura
cd Ubuntu-touch-for-redmi6pro-sakura
```

### 3. Build the kernel and the boot image

```bash
./build.sh
```

What it does, step by step:

1. clones `halium-generic-adaptation-build-tools` into `./build`
2. runs its `build.sh -c` — downloads clang (`android10-gsi`, `r353983c`), GCC 4.9,
   `mkbootimg`, `avb`, and clones `kernel_xiaomi_msm8953` (branch `lineage-17.1`)
   into `workdir/downloads/`
3. `scripts/prepare-kernel-config.sh` appends `device/halium.config` to
   `arch/arm64/configs/sakura_defconfig`
4. runs the real build: `make sakura_defconfig` + `make -j`, then
   `make-bootimage.sh` -> `workdir/tmp/partitions/boot.img`
5. copies the boot image to `out/boot.img`

Useful variants:

```bash
./build.sh -c     # only clone/download, no compile
./build.sh -k     # kernel + boot image only
./build.sh -m     # menuconfig before building (kernel tuning)
```

Expected output, near the end:

```
out/device_sakura.tar.xz             ~30 MB
out/boot.img                         ~18-22 MB (64 MiB partition, padded)
```

Add ~30-60 min of compile time on 4 cores for the first run; later runs reuse
`workdir/downloads` and take 5-15 min.

### 4. Rootfs and GSI

```bash
./scripts/fetch-prebuilts.sh
```

Downloads:

| File | Size | What it is |
| --- | --- | --- |
| `ota/ubuntu-touch-android9plus-rootfs-arm64.tar.gz` | ~927 MiB | Ubuntu Touch 24.04 rootfs, arm64, `android9plus` |
| `ota/halium_halium_arm64.tar.xz` | ~137 MiB | Halium 10.0 generic arm64 GSI (`android-rootfs.img`) |

### 5. rootfs.img

```bash
sudo -E ./scripts/make-rootfs-image.sh
```

Creates a 4 GiB ext4 image, extracts the rootfs tarball into it, applies
`device/overlay/system`, then shrinks it with `resize2fs -M` and gzips it.
Output: `out/rootfs.img` (~2.5 GiB) and `out/rootfs.img.gz` (~800 MiB-1 GiB).

`ROOTFS_SIZE=6G` gives more headroom if you plan to install many click packages; the
screen of an untouched 24.04 rootfs is ~2.3 GiB, so 4 GiB is fine for normal use.

### 6. Flashable zip

```bash
./scripts/build-zip.sh
```

Output in `dist/`:

```
sakura-ut24.04-halium10-v0.1.0-YYYYMMDD-<sha>.zip
sakura-ut24.04-halium10-v0.1.0-YYYYMMDD-<sha>.zip.sha256
sakura-ut24.04-halium10-v0.1.0-YYYYMMDD-<sha>.buildinfo
```

Zip contents:

```
META-INF/com/google/android/update-binary   installer script (shell)
META-INF/com/google/android/updater-script  stub, required by recoveries
META-INF/sakura/build.prop                  build identification
partitions/boot.img                         Halium kernel + initramfs
images/rootfs.img.gz                        Ubuntu Touch rootfs (ext4, gzipped)
images/android-rootfs.img                   Halium 10 GSI
device_sakura.tar.xz                        device tarball (overlay store + modules)
```

### 7. Optional: the official OTA path

If the port ever gets an OTA channel (or you want a system-as-root image for a
partition-based install), `./scripts/prepare-ota.sh` runs the upstream
`fetch-and-prepare-latest-ota.sh` + `system-image-from-ota.sh` and writes
`out/system.img` + `out/rootfs.img`. This is not used by the flashable zip.

---

## Verify before flashing

```bash
# kernel is really an arm64 Linux image?
file out/boot.img                    # "Android bootimg, kernel size ..."
unzip -l dist/*.zip                  # all five pieces present
sha256sum -c dist/*.sha256
tar -tJf out/device_sakura.tar.xz | head   # partitions/boot.img, system/lib/modules/...
```

`boot.img` sanity-check with the upstream tool:

```bash
git clone --depth 1 https://github.com/LineageOS/android_system_tools_mkbootimg
python3 android_system_tools_mkbootimg/unpack_bootimg.py --boot_img out/boot.img
```

Expected: `pagesize: 2048`, `kernel load address: 0x80008000`,
`ramdisk load address: 0x81000000`, `tags load address: 0x80000100`.

---

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `No rule to make target 'halium.config'` | you put `halium.config` in `deviceinfo_kernel_defconfig`; this project merges the fragment instead — remove it from `deviceinfo` |
| `clang: error: unknown argument` / `-Werror` failures | kernel built with a newer host compiler; always use the prebuilt clang from `workdir/downloads`, never the distro clang |
| `libtinfo.so.5: cannot open shared object file` | `sudo apt install libtinfo5` (22.04 only) |
| `ImportError: No module named ...` | `sudo ln -sf /usr/bin/python2 /usr/bin/python`, then `make mrproper` in the kernel out dir |
| build dies in `prepare-kernel-config.sh` | you ran it before `./build.sh -c`; the kernel source is not downloaded yet |
| `resize2fs: Operation not permitted` | `make-rootfs-image.sh` was not run as root |
| zip > 2 GiB and Windows tools choke | the images are stored (no deflate); use `unzip`/OrangeFox, not old Windows extractors |
| `mke2fs` error `metadata_csum` on device | rootfs was built with `mkfs.ext4` defaults; `make-rootfs-image.sh` already passes `-O ^metadata_csum,^64bit` |

Full build logs: keep the terminal output, and on CI the workflow log. Paste the failing
command plus ~30 lines around it into `docs/PORTING_LOG.md` when you fix something.
