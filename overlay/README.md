# overlay/

Port-root overlay, copied into the device tarball by the upstream
`build-tarball-mainline.sh`:

```bash
cp -av overlay/* "${dir}/"
```

That copy is **unconditional**, so this directory must exist and must contain at least one
file — without it the build stops with

```
cp: cannot stat 'overlay/*': No such file or directory
```

**This file never reaches the phone.** `build-tarball-mainline.sh` only packs `partitions/`
and `system/` into `out/device_sakura.tar.xz`, so a file at the top level of `overlay/`
lands in `workdir/tmp/` and is then dropped.

## Layout when you do need it

Anything under `overlay/system/` ends up inside the overlay store, which is mounted over
`/` on the device:

```
overlay/system/etc/example.conf      ->  /etc/example.conf        on the phone
overlay/system/usr/share/foo/bar     ->  /usr/share/foo/bar       on the phone
```

Put rootfs-only files in `device/overlay/system/` instead (they are baked into
`rootfs.img`), and files that must replace something in the boot ramdisk in
`ramdisk-overlay/`.
