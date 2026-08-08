# Custom kernel build inputs

The release image ships an Armbian **vendor 6.6** kernel rebuilt with these
two inputs, both required for ZWO EAF/EFW/CAA (USB HID) support:

- `linux-sun60iw2-vendor.config` — stock Armbian
  `config/kernel/linux-sun60iw2-vendor.config` with exactly two changes:
  `CONFIG_HIDRAW=y`, `CONFIG_USB_HIDDEV=y`.
- `hid-usbhid-paper-over-wrong-bNumDescriptors.patch` — upstream commit
  [f28beb69c515](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=f28beb69c51517aec7067dfb2074e7c751542384)
  ("HID: usbhid: paper over wrong bNumDescriptors field"). ZWO HID accessories
  report a malformed HID descriptor that 6.6's usbhid rejects with
  `can't add hid device: -22`; this backport recomputes the field instead.
  (See [Debian bug #1122193](https://bugs.debian.org/1122193).)

## Rebuild

On any x86_64 or arm64 Linux host with ~30 GB free disk:

```bash
git clone --depth 1 https://github.com/armbian/build armbian-build
cd armbian-build
mkdir -p userpatches/kernel/archive/sun60iw2-opi-vendor
cp /path/to/repo/hardware/orangepi4pro-a733/kernel/linux-sun60iw2-vendor.config userpatches/
cp /path/to/repo/hardware/orangepi4pro-a733/kernel/hid-usbhid-paper-over-wrong-bNumDescriptors.patch \
    userpatches/kernel/archive/sun60iw2-opi-vendor/
sudo ./compile.sh kernel BOARD=orangepi4pro BRANCH=vendor KERNEL_CONFIGURE=no KERNEL_BTF=no
```

`KERNEL_BTF=no` avoids a libbpf host-tool build failure with GCC 15+ (BTF
isn't needed on this appliance image).

Output debs land in `output/debs/`; feed them to the image build with
`KERNEL_DEBS=` (see the top-level README).

The userpatch directory name (`sun60iw2-opi-vendor`) must match
`KERNELPATCHDIR` in Armbian's `config/sources/families/sun60iw2.conf` — check
there if patches aren't picked up after an Armbian framework update.
