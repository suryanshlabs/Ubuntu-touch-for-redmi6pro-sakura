# Porting log

Chronological record of what was decided, built, broken and fixed. Newest entry first.
Status legend: **[done]** verified in this repository · **[open]** needs hardware/build
time · **[blocked]** needs something outside the repository.

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

**[open]** First real build. Nothing has been compiled or flashed yet: the CI workflow is
the first place this will actually run. Until a workflow run succeeds, the build is
unproven and the port status stays *WIP / Planning*.

**[open]** Device-info values that could not be verified without the phone:

* `deviceinfo_bootimg_header_version="0"` — inferred from Android 8.1 launch + LineageOS
  `BoardConfig.mk` which sets no header version. If the phone bootloops at the logo,
  rebuild with `"1"` or `"2"`.
* `deviceinfo_kernel_cmdline` — copied from the LineageOS `BoardConfig.mk`, plus
  `console=tty0` (Halium) and `androidboot.selinux=permissive` (bring-up). Unpack the stock
  `boot.img` with `unpack_bootimg.py` and compare before trusting it.

**[open]** Kernel config: `device/halium.config` enables `CONFIG_ANDROID_BINDERFS`. If the
4.9 tree has no binderfs Kconfig entry, `make` will print `unknown option` — apply the
binderfs backport (see `kernel/README.md`) or drop that line for the first boot.

**[open]** Toolchain: `deviceinfo_kernel_clang_compile="true"` follows LineageOS 17.1,
which builds this kernel with clang. If the first CI run fails in the kernel with clang
specific errors (`-Werror`, unsupported `-mllvm` flags, missing `CLANG_TRIPLE` handling),
set `deviceinfo_kernel_clang_compile="false"` — the build tools then fall back to the
GCC 4.9 prebuilts, which this 4.9 msm tree definitely supports.

**[open]** `mahajant99/kernel_xiaomi_msm8953` must actually have
`arch/arm64/configs/sakura_defconfig` on branch `lineage-17.1` (verified by download on
2026-11-26). If the branch disappears, the fallbacks are
`geopd/kernel_xiaomi_sakura` (branch `sapphire`) or the LineageOS 17.1 `msm8953` common
kernel.

---

## Backlog (next steps, in order)

1. Run the GitHub Actions workflow, fix whatever the kernel build complains about, get
   `boot.img` + `device_sakura.tar.xz` produced. **(this is the gate: nothing else matters
   until it compiles)**
2. Flash `boot.img` on a phone that already runs an Android 10 base with `/data` unencrypted
   ext4, and confirm `adb devices` works from the initramfs (kernel + binder + USB).
3. Full install with the zip, confirm `/data/rootfs.img` boots into Lomiri.
4. Bring-up order, one item per flash: display/touch -> Wi-Fi -> audio -> telephony ->
   Bluetooth -> camera -> fingerprint -> sensors.
5. Per-feature device overlays go into `device/overlay/system/`; kernel-side fixes into
   `device/halium.config` or a patch applied by `scripts/prepare-kernel-config.sh`.
6. When everything works: switch SELinux to enforcing, remove `androidboot.selinux=permissive`,
   and open a merge request to `ubports/installer-configs` for a `sakura.yml`.
