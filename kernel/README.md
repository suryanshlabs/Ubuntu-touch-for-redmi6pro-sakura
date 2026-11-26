# kernel/

The kernel is **not vendored** in this repository (a 4.9 msm tree is ~1.5 GB with history).
It is cloned by `./build.sh` into `workdir/downloads/kernel_xiaomi_msm8953` from:

```
https://github.com/mahajant99/kernel_xiaomi_msm8953   branch: lineage-17.1
```

## Why this tree

* LineageOS 17.1 = Android 10 = the Halium 10 base, so the Android driver ABI matches the
  Halium 10 GSI exactly.
* It is the tree the sakura device trees are built against
  (`TARGET_KERNEL_SOURCE := kernel/xiaomi/msm8953`, `TARGET_KERNEL_CONFIG := sakura_defconfig`).
* Kernel 4.9.x is supported by UBports' Halium 10 initramfs and by the Halium 10 clang
  prebuilts (`android10-gsi` / `r353983c`).

Alternatives considered and rejected are listed in `../RESEARCH.md`.

## What this project adds to the kernel

Nothing, except one config fragment: `../device/halium.config`, appended to
`arch/arm64/configs/sakura_defconfig` by `scripts/prepare-kernel-config.sh` right before
the build. The fragment only enables what Halium needs (binder, binderfs, namespaces,
cgroups, configfs) and leaves the Android driver config untouched.

## Kernel-space bring-up that is still open

These are the parts of a Halium port that live in the kernel tree and are **not** done yet.
They are documented here so the next person knows where to look, not because they are
implemented:

1. **Binder / binderfs** — the 4.9 msm tree has `CONFIG_ANDROID_BINDER_IPC`. binderfs was
   added in 4.9 but is only in the msm tree if the `ANDROID_BINDERFS` patches are present;
   `device/halium.config` enables it and the build will warn if it does not exist. If it
   does not, apply the binderfs backport from `halium/android_kernel_*` or the upstream
   patch (`f251548e...`, `binderfs` v2 series) and rebuild.
2. **SELinux policy** — the boot cmdline sets `androidboot.selinux=permissive` for
   bring-up. Do not ship a release with permissive SELinux; fix the denials first.
3. **Overlay store** — `deviceinfo_use_overlaystore="true"` mounts the device tarball over
   `/usr/lib/modules` and `/vendor`. The kernel needs `CONFIG_OVERLAY_FS` (already in the
   fragment and in the LineageOS defconfig).

If a future kernel is used, update `deviceinfo` (`deviceinfo_kernel_source`,
`deviceinfo_kernel_source_branch`, `deviceinfo_kernel_defconfig`) and re-run `./build.sh`.
