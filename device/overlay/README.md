# device/overlay

Files copied on top of the Ubuntu Touch rootfs when `scripts/make-rootfs-image.sh` builds
`out/rootfs.img`. The tree mirrors the rootfs layout (`system/` is the root of `/`).

```
system/etc/deviceinfo/devices/sakura.yaml      DeviceInfo: UI scale, orientation
system/usr/lib/udev/rules.d/70-sakura.rules    permissions for the Android-backed devices
```

Add a file here instead of editing the rootfs tarball; the overlay is applied on every
build and is the only device-specific part of the rootfs.

Things that do **not** belong here:

* kernel modules — they ship in the device tarball (overlay store), built by `./build.sh`
* vendor blobs — they come from the Halium GSI / vendor partition, see `proprietary/`
* deviceinfo build configuration — that is the `deviceinfo` file in the repository root,
  a completely different format from the YAML used by libdeviceinfo at runtime
