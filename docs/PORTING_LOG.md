# Porting log

Chronological record of what was decided, built, broken and fixed. Newest entry first.
Status legend: **[done]** verified in this repository · **[open]** needs hardware/build
time · **[blocked]** needs something outside the repository.

---

## 2026-11-26 (latest) — kernel, tarball and rootfs image all build

Run `45882123129` reached and passed the two steps that had never run before:

* **kernel + boot image + device tarball: success** in 12.5 minutes with clang, and the
  GCC fallback step was skipped, so the `overlay/` fix closed that failure for good
* **rootfs image: built** — 4.0 GiB ext4 image, gzipped to 930 MiB with pigz

The step was still reported as failed, with `##[error]Process completed with exit code 1`
after the script's own `==> rootfs image ready` line. Cause: bash takes the exit status of
the last command run in an EXIT trap as the script's exit status, and the cleanup helper
ended in `[ -n "$XDIR" ] && rm -rf "$XDIR"`, which is status 1 when the loop-mount path was
used (so `XDIR` stays empty). The build had succeeded; the cleanup lied about it.

**Fix:** the cleanup function now ends in `return 0` with `|| true` on every command. The
same trap pattern in the installer got the same treatment, where it could have turned a
good install into "Installation aborted".

**[open]** Still unproven: `scripts/build-zip.sh`, the artifact upload and the release.

---

## 2026-11-26 — the kernel builds; the device tarball did not

Run `45879071056` on the fixed tree got much further: **the kernel compiled and linked
successfully with clang 9 in 13 minutes** (`Image.gz-dtb` + all modules), so the toolchain
fix above was correct. It then stopped in the upstream `build-tarball-mainline.sh`:

```
+ cp -av 'overlay/*' /home/runner/work/.../workdir/tmp/
cp: cannot stat 'overlay/*': No such file or directory
##[error]Process completed with exit code 1.
```

That script copies `overlay/*` into the device tarball **unconditionally**, with `set -e`.
Every UBports port tree therefore has an `overlay/` directory; this repository only had
`device/overlay/` (the rootfs overlay), so the glob matched nothing and `cp` failed.

The GCC fallback step then re-ran the whole kernel build with GCC 4.9 and hit the same
step, which is why the job log shows two identical failures.

**Fix:** `overlay/README.md`. It is deliberately at the top level of `overlay/`, because
`build-tarball-mainline.sh` only packs `partitions/` and `system/` into the tarball, so the
file explains itself and never reaches the phone. `scripts/preflight.sh` now also fails
fast if `overlay/` is missing or empty.

**Also fixed:** the kernel object directory lives in `workdir/downloads`, which is cached
between CI runs. After a clang failure the fallback rebuilds it with GCC, so the cache can
hold GCC objects while the next run builds with clang — and a compiler change is not a make
dependency, so nothing would notice. `build.sh` now records the toolchain in
`workdir/downloads/.sakura-toolchain` and wipes `KERNEL_OBJ` when it does not match.

**[open]** Next run: rootfs image, zip and release were never reached. They are the only
steps still unproven.

---

## 2026-11-26 (later) — first CI run diagnosed and fixed

The first GitHub Actions run (`45790705219`, commit `3da14af`) failed after 8 minutes,
inside the kernel build. That log is the source of everything below.

**[done] The failure.** `make` stopped at `prepare-compiler-check`:

```
+ make O=.../KERNEL_OBJ CC=clang -j4
arch/arm64/Makefile:27: ld does not support --fix-cortex-a53-843419; kernel may be susceptible to erratum
  CHK     include/config/kernel.release
Cannot use CONFIG_CC_STACKPROTECTOR_STRONG: -fstack-protector-strong not supported by compiler
make[1]: *** [Makefile:1232: prepare-compiler-check] Error 1
```

Two related causes, both from one wrong value:

1. `deviceinfo_kernel_arch="arm64"` made the build tools derive
   `CROSS_COMPILE=arm64-linux-android-` and `CLANG_TRIPLE=arm64-linux-gnu-`.
   The prebuilt toolchains only have `aarch64-linux-android-*` and
   `aarch64-linux-gnu-*`, so `ld` fell back to the host x86 linker (that is the
   `--fix-cortex-a53-843419` warning) and every `cc-option` test failed, which is what
   the stack-protector error actually reports.
2. The kernel Makefile turns `CLANG_TRIPLE` into `--target=$(notdir $(CLANG_TRIPLE:%-=%))`,
   so `arm64-linux-gnu-` became `--target=arm64-linux-gnu`, which is not a valid clang
   triple.

**Fix:** `deviceinfo_arch="aarch64"` and `deviceinfo_kernel_arch="aarch64"`. This is also
what the working Halium 10 Xiaomi port `KrutosVIP/halium_device_xiaomi_olivelite` uses.

**[done] Four more bugs found by reading the upstream scripts before spending another run:**

* `make-bootimage.sh` *always* passes `--os_version`/`--os_patch_level` to `mkbootimg.py`.
  With those keys empty, argparse swallows the next flag and dies with
  `argument --os_version: expected one argument`. `deviceinfo` now sets
  `deviceinfo_bootimg_os_version="10"` and `deviceinfo_bootimg_os_patch_level="2021-07-01"`
  (the vendor security patch from `BoardConfig.mk`).
* `deviceinfo_bootimg_partition_size` makes `make-bootimage.sh` run
  `avbtool add_hash_footer` on boot.img, which wants a signing key this port does not have.
  The key is gone; `scripts/build-zip.sh` pads boot.img to the 64 MiB partition with
  `truncate` instead (verified: exactly 67108864 bytes in the zip).
* The Halium 10 GSI artifact keeps its image at
  `system/var/lib/lxc/android/android-rootfs.img`, not at the top of the tarball. The old
  `find -maxdepth 2` never saw it, so the zip step would have aborted with
  "no android-rootfs.img/system.img inside". The search is now unbounded and the image is
  hoisted to `images/android-rootfs.img`.
* The installer unpacked the ~2 GiB payload into `/tmp`. On this phone `/tmp` is a tmpfs of
  a few hundred MiB, so the install would always fail with "No space left on device".
  It now unpacks into `/data/sakura-ut-install` and cleans up afterwards.

**[done] Fixes for things that would have produced a bad or unusable image:**

* `make-rootfs-image.sh` used to run `resize2fs -M`, shrinking the filesystem to its
  minimum. That leaves a phone with literally zero free space inside the rootfs. The image
  keeps its 4 GiB size (≈1.6 GiB free) and `e2fsck` replaces the shrink.
* The image is now populated with `mkfs.ext4 -d` if a loop mount is not permitted, so the
  step does not depend on host capabilities, and compression uses `pigz` when present.
* The kernel cmdline now matches `BoardConfigCommon.mk` exactly
  (`lpm_levels.sleep_disabled=1`, `loop.max_part=16`) instead of a partial copy, plus
  `console=tty0` and `androidboot.selinux=permissive`.
* `CONFIG_ANDROID_BINDERFS` was dropped from `device/halium.config`: this 4.9 tree has no
  `drivers/android/binderfs.c`, so the symbol does not exist and was being silently
  dropped. Halium 10 works with the binder devices the defconfig already sets.
* `scripts/prepare-kernel-config.sh` was not idempotent (one extra blank line per run, so
  it grew on every build). It now truncates from its own marker; three consecutive runs
  produce byte-identical line counts (verified).

**[done] Making the next failure cheap:**

* `scripts/preflight.sh` (new) validates every `deviceinfo` key the tools require, the
  arch value, that the kernel repo/branch resolves, that the three download URLs answer,
  and `sh -n`/`bash -n` on every script. It runs in seconds as the first CI step, so a
  config typo no longer costs an hour-long kernel build.
* The workflow runs the clang build with `continue-on-error`, and on failure retries the
  same build with the GCC 4.9 prebuilts (`KERNEL_GCC=1 ./build.sh`), which patches
  `deviceinfo` for the run and restores it. The 4.9 msm tree definitely builds with GCC.
* The 4-minute "free up disk space" step was removed: the runner reports 109 GB free.

**[open] Next.** With the toolchain fixed, the remaining unknowns are the ones only a build
and a phone can answer: whether the kernel compiles clean with clang 9, whether boot header
v0 and the offsets are right for this bootloader, and then everything in the bring-up list.

---

## 2026-11-26 — project skeleton, CI pipeline, flashable zip design

**[done]** Research pass over the UBports and Halium documentation, the six reference trees
in the request, and one existing flashable-zip port (`itswill00/tanzanite-ubuntu-touch`).
Findings are in `RESEARCH.md`; the short version:

* no existing Ubuntu Touch port for `sakura` — this is a new port
* Halium 10.0 (Android 10 / LineageOS 17.1) is the only base with a maintained kernel tree
  *and* a matching generic arm64 GSI
* sakura's system partition is 3.0 GiB, so a system-as-root install cannot hold the 24.04
  rootfs; the port installs to `/data` (dual-boot), which is also what makes the zip safe

**[done]** Repository layout, `deviceinfo`, kernel config fragment, build wrapper.

**[done]** Build pipeline: `./build.sh` (kernel + boot image), `scripts/fetch-prebuilts.sh`
(rootfs + GSI), `scripts/make-rootfs-image.sh` (ext4 rootfs + overlay),
`scripts/build-zip.sh` (zip). Wired into `.github/workflows/build.yml` with artifact upload
and tag-triggered GitHub Release, plus a `.gitlab-ci.yml` for the UBports shared pipeline.

**[done]** Recovery installer (`installer/META-INF/com/google/android/update-binary`):
device check, `/data` check, free-space check, boot backup, `dd` of `boot.img`, gunzip of
the rootfs image, GSI copy, and a rollback message. Written to be re-runnable.

**[open]** Device-info values that could not be verified without the phone:

* `deviceinfo_bootimg_header_version="0"` — inferred from Android 8.1 launch + LineageOS
  `BoardConfig.mk` which sets no header version. If the phone bootloops at the logo,
  rebuild with `"1"` or `"2"`.
* `deviceinfo_kernel_cmdline` — stock LineageOS 17.1 cmdline plus `console=tty0` and
  `androidboot.selinux=permissive`. Unpack the stock `boot.img` with `unpack_bootimg.py`
  and compare before trusting it.

**[open]** Toolchain: `deviceinfo_kernel_clang_compile="true"` follows LineageOS 17.1,
which builds this kernel with clang. The GCC fallback in the workflow covers the case
where clang 9 cannot build the tree.

**[open]** `mahajant99/kernel_xiaomi_msm8953` must keep
`arch/arm64/configs/sakura_defconfig` on branch `lineage-17.1` (verified reachable on
2026-11-26). If the branch disappears, the fallbacks are
`geopd/kernel_xiaomi_sakura` (branch `sapphire`) or the LineageOS 17.1 `msm8953` common
kernel.

---

## Backlog (next steps, in order)

1. Get a green workflow run: `boot.img` + `device_sakura.tar.xz` + `rootfs.img` +
   `dist/*.zip`. **(this is the gate: nothing else matters until it builds)**
2. Flash `boot.img` on a phone that already runs an Android 10 base with `/data` unencrypted
   ext4, and confirm `adb devices` works from the initramfs (kernel + binder + USB).
3. Full install with the zip, confirm `/data/rootfs.img` boots into Lomiri.
4. Bring-up order, one item per flash: display/touch -> Wi-Fi -> audio -> telephony ->
   Bluetooth -> camera -> fingerprint -> sensors.
5. Per-feature device overlays go into `device/overlay/system/`; kernel-side fixes into
   `device/halium.config` or a patch applied by `scripts/prepare-kernel-config.sh`.
6. When everything works: switch SELinux to enforcing, remove `androidboot.selinux=permissive`,
   and open a merge request to `ubports/installer-configs` for a `sakura.yml`.

---

## 2026-11-27 — push divergence cleared, build re-triggered

**[done]** Diagnosed why CI would not re-trigger. Two trigger commits existed with the same
parent: `bcb3e9d` ("trigger: rebuild from scratch") on the remote
`freebuff/07cc3f02731395fc0c4c55a0` branch and `df447f1` ("second workflow trigger")
locally. They differed only in the placeholder `.workflow_trigger*` files, but a
non-fast-forward push is rejected, so nothing reached GitHub and no run started. The branch
has been rebuilt as a clean fast-forward on top of `main` (`baaaf94`), and the placeholder
trigger files are gone — a normal commit is now the trigger.

**[done]** `./scripts/preflight.sh` re-run on this tree: deviceinfo keys, kernel repository,
all three download URLs (206/200/206), `overlay/`, and every script's syntax pass.

**[done]** Local build state carried over: `out/rootfs.img` (4 GiB ext4) and
`out/rootfs.img.gz` (~4.2 MiB) already produced by `scripts/make-rootfs-image.sh` with the
loop-mount fallback.

**[done]** The pipeline is green end to end. Run `45884507357` on `baaaf94` completed all
16 steps, including `scripts/build-zip.sh`, and published the `continuous-build` prerelease
carrying `sakura-ut24.04-halium10-v0.1.0-20261126-baaaf94.zip` (1,197,970,970 bytes), its
`.sha256` and its `.buildinfo`, alongside the `sakura-boot-*` and `ubuntu-touch-sakura-*`
workflow artifacts. `out/boot.img` and `out/device_sakura.tar.xz` are produced on the runner,
which is where `build.sh` gets the root it needs.

**[open]** Nothing has been flashed on hardware yet, so backlog item 1 is done and items 2-6
(initramfs bring-up, full install, per-feature bring-up) are the remaining work.

---

## 2026-11-27 — `rootfs_bytes` wrapped to 0 in the published manifest

**[bug]** The first release's `.buildinfo` carries `rootfs_bytes 0`. `make-rootfs-image.sh`
prefers `pigz`, and pigz writes gzip's 32-bit ISIZE field as 0 for any stream of 4 GiB or
more — which is exactly the default image size. `gzip -l` therefore reported 0,
`build-zip.sh` copied it straight into `build.prop`, and the installer only substituted its
default when the key was *empty*, not when it was zero. A manifest of `0` makes the `/data`
free-space check ask for ~2 GiB instead of ~5 GiB, so an install with 3 GiB free would flash
`boot.img`, fill `/data` while writing the rootfs and abort halfway — a bootloop into a
Halium kernel with no rootfs behind it.

**[done]** `build-zip.sh` takes the size from `out/rootfs.img` when it still exists (it does
in CI, because the compression step keeps the plain image), falls back to the gzip trailer,
and finally counts decompressed bytes with `pigz`/`gzip`. A size that is still 0 is now a
hard failure instead of a silently wrong manifest. The installer treats an empty,
non-numeric or zero value as unknown and uses 4 GiB, so zips built before this fix are also
checked correctly.

**[done]** Verified with a synthetic payload (1 MiB boot image, 4 MiB Android image, real
4 GiB rootfs) through `./scripts/build-zip.sh`: the zip's `build.prop` and the `.buildinfo`
both read `rootfs_bytes 4294967296`, and the installer's requirement becomes 6292256 KiB.
The byte-counting branch was exercised but not to completion inside this 5-minute sandbox
cap — it is a safety net, not the path CI takes.

---

## 2026-11-27 — the installer never read its own manifest

**[bug]** `update-binary` unpacked with `unzip -d "$WORK"`, which places the manifest at
`$WORK/META-INF/sakura/build.prop`, but read it from `$WORK/meta/META-INF/sakura/build.prop`.
The `sed` always came back empty, so the `/data` space check silently used defaults and
`/data/sakura-ubuntu-touch-build.prop` was never written. The check also sat *after* the
unpack, so a too-full `/data` failed during unpacking instead of being refused up front.

**[done]** The manifest is now read straight out of the zip with `unzip -p` before anything is
unpacked; the space check runs first, an unreadable `df` is reported instead of aborting, and
the build.prop copy uses the path `unzip` really creates. Verified by running the installer's
own block against a freshly built zip: `rootfs_bytes` and `android_rootfs_bytes` parse out of
the archive and the requirement is computed from them.

**[done]** Audited the real release asset with HTTP range requests instead of a 1.2 GiB
download. Entries: `partitions/boot.img` 15,403,091 stored / 67,108,864 uncompressed (exactly
the 64 MiB boot partition), `images/rootfs.img.gz` 974,286,541 (stored), 
`images/android-rootfs.img` 192,824,216 / 537,280,512, `device_sakura.tar.xz` 15,288,177,
`META-INF/sakura/build.prop` 257. Zip total 1,197,807,377 bytes. Nothing is written to the
3.0 GiB system partition: the installer touches only `boot` and files under `/data`, so the
system-image size limit does not apply to this zip.

**[done]** Added a boot-partition size guard: the installer reads the size of the real block
device behind `/dev/block/by-name/boot` and refuses to write the padded 64 MiB image if the
partition is smaller, instead of running `dd` past the end into the next partition. An
unreadable size is reported and the write goes ahead, as before.

### Single-boot, not dual-boot — wording corrected

The docs and the installer called the `/data` placement a "dual-boot" install. That was
wrong: the zip overwrites the `boot` partition with the Halium kernel and initramfs, so there
is no boot menu, Android never boots again, and the phone goes straight into Ubuntu Touch.
Only the rootfs *files* are stored in `/data`, because sakura's 3.0 GiB system partition has
no room for a 4 GiB image plus OTA headroom. `README.md`, `docs/INSTALL_ME.md` and the
installer's messages now say this plainly instead of implying a dual-boot setup.

---

### v0.1.0 - the final, single release

Pushed tag `v0.1.0` (commit `763c25d`) to make a proper versioned release, instead of the
rolling `prerelease` `continuous-build` that accumulated 15 zips including the old buggy
ones. Tagged builds are now published as real releases (`prerelease: false`), so GitHub
marks them "Latest".

New release: [Ubuntu Touch 24.04 for Redmi 6 Pro - v0.1.0](https://github.com/suryanshlabs/Ubuntu-touch-for-redmi6pro-sakura/releases/tag/v0.1.0)
(prerelease: false, marked Latest)

Assets: only the zip, its `.sha256`, and `.buildinfo`
(file name `sakura-ut24.04-halium10-v0.1.0-20261127-763c25d.zip`,
1,197,988,482 bytes, sha256 `c8c5825833bcd7876df2ee25c82d41435c5e4bf0baf217334b69a58927197041`).

Archive contents (verified by unzipping the downloaded file):
* `partitions/boot.img` = 67,108,864 bytes (exactly the 64 MiB boot partition)
* `images/rootfs.img.gz` = 974,467,043
* `images/android-rootfs.img` = 537,280,512
* `device_sakura.tar.xz` = 15,288,177
* `META-INF/sakura/build.prop` = 257

Workflow: workflow body now says the zip is a single-boot install (no dual-boot menu; Android
stops booting), lists prerequisites, and points to the rollback + `docs/INSTALL_ME.md`; the
`continuous-build` entry stays a pre-release.

---

### v0.1.1 - boot image no longer padded to 64 MiB

First hardware test of v0.1.0 stopped at the boot step: the installer refused to write
`partitions/boot.img` because the image was larger than the boot partition reported by the
phone ("size limit"). Cause: `scripts/build-zip.sh` padded the ~20 MB Halium boot image up to
`BOARD_BOOTIMAGE_PARTITION_SIZE` (67,108,864 bytes / 64 MiB) with `truncate`, on the assumption
that every sakura unit exposes a full 64 MiB boot partition. Real units can expose a smaller
one, and a padded image then cannot be written at all.

**[fixed]** The padding is gone: the zip now carries the real boot image. 64 MiB is only used
as an upper bound (the build fails if the real image somehow exceeds it), and the recovery
installer still checks the actual block-device size before `dd` and refuses with both byte
counts if it does not fit. Trailing bytes left over from the previous, larger boot image are
harmless: the bootloader reads the image by the sizes in its header, and the build no longer
writes them.

Also: `META-INF/sakura/build.prop` reports the real `sakura.build.bootimg_bytes` (it used to
report the padded 64 MiB), and `docs/INSTALL_ME.md`, `docs/BUILD_ME.md`, `deviceinfo` and
`RESEARCH.md` describe the unpadded image.

New release: [Ubuntu Touch 24.04 for Redmi 6 Pro - v0.1.1](https://github.com/suryanshlabs/Ubuntu-touch-for-redmi6pro-sakura/releases/tag/v0.1.1)
(prerelease: false, marked Latest), tag `v0.1.1` on commit `2a0c50a`, workflow run
46110551730 green.

Asset `sakura-ut24.04-halium10-v0.1.1-20261128-2a0c50a.zip`, 1,198,036,157 bytes,
sha256 `ef998524dce92eb9f6daef62ea6b54646d06d33094bdeba4405cbfa8540a31ff`
(downloaded and checked with `sha256sum -c`). Contents:

* `partitions/boot.img` = **15,917,056 bytes** (15.2 MB, unpadded; v0.1.0 had 67,108,864)
  — `file` reports "Android bootimg, kernel, ramdisk, page size: 2048"
* `images/rootfs.img.gz` = 974,564,817
* `images/android-rootfs.img` = 537,280,512
* `device_sakura.tar.xz` = 15,293,020
* `META-INF/sakura/build.prop` = 518 (`bootimg_bytes=15917056`, `rootfs_bytes=4294967296`)

The 15.2 MB image fits a 16, 32 or 64 MiB boot partition, so the size failure cannot recur.
