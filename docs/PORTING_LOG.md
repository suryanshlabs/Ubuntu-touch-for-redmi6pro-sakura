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

**[open]** `out/boot.img` and `out/device_sakura.tar.xz` still only come from `build.sh`,
which needs a root-capable host; the CI runner produces them. `scripts/build-zip.sh` is
therefore still unproven — it is the next thing to watch in the run.
