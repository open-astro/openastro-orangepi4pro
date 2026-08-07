# OpenAstro for the Orange Pi 4 Pro

<img src="https://www.openastro.net/wp-content/uploads/2026/04/OpenAstro_logo.png" alt="OpenAstro logo" width="420">

OpenAstro OS for the **Orange Pi 4 Pro** (Allwinner A733): an
[Armbian](https://www.armbian.com/)-based **Debian 13 (Trixie)** minimal CLI
image (no GUI) with a WiFi access point and everything ready for
[AlpacaBridge](https://github.com/open-astro/AlpacaBridge).

The OS **runs from the microSD card** — flash it, insert it, power on. There is
no internal-storage install step.

## Supported hardware

| Device | SoC | Kernel | Status |
|--------|-----|--------|--------|
| Orange Pi 4 Pro | Allwinner A733 (sun60iw2) | Armbian vendor 6.6 | In validation |

> **⚠️ ZWO EAF/EFW note:** AlpacaBridge's ZWO focuser/filter-wheel support is
> validated on kernel **6.12.75+**. This board currently only has a **vendor
> 6.6** kernel (no mainline/`current` branch exists for the A733 yet), so ZWO
> EAF/EFW compatibility is **unverified** until ConformU validation passes on
> this image — or the relevant fix is backported via a kernel patch.

## Install

### 1. Download + flash

Grab the latest `openastro-orangepi4pro.img.xz` from the
[Releases](../../releases) page and flash it to a microSD card (8 GB+) with
[Raspberry Pi Imager](https://www.raspberrypi.com/software/),
[balenaEtcher](https://etcher.balena.io/), or `dd`:

```bash
xzcat openastro-orangepi4pro.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

### 2. Boot

Insert the microSD and power on. The board boots and runs entirely from the SD
card — leave it in.

## First boot defaults

| Setting | Value |
|---------|-------|
| Hostname | `openastro` |
| Login | `astro` / `astro` — **change immediately:** `passwd` |
| WiFi AP | `OpenAstro` (2.4 GHz), password `12345678` |
| AP address | `172.24.1.1` (DHCP for clients) |
| Ethernet | DHCP |

Reach it over ethernet (`ssh astro@<ip>`) or by joining the `OpenAstro` WiFi.

### Connect to your own network instead (optional)

NetworkManager manages the wired port; `wlan0` is reserved for the access
point. To put the board on your LAN, use the ethernet port.

## Install AlpacaBridge

AlpacaBridge is **not** baked into the image. Install it by following the
[AlpacaBridge install guide](https://github.com/open-astro/AlpacaBridge), which
adds the OpenAstro apt repository and installs the package — the same as on
every other platform.

## Build the image yourself

The release image is built from a stock Armbian *Orange Pi 4 Pro* image plus
the OpenAstro layer. On an **aarch64** host (an arm64 Debian/Armbian box, or
the board itself — it's a native chroot, no emulation):

```bash
# 1. grab the upstream Armbian "Orange Pi 4 Pro" (Trixie, vendor kernel) image
wget -O armbian.img.xz https://dl.armbian.com/orangepi4pro/Trixie_vendor_minimal

# 2. bake in the OpenAstro layer and repack
sudo apt install parted e2fsprogs
sudo build/build-openastro-image.sh armbian.img.xz images/openastro-orangepi4pro.img.xz
```

- [`build/build-openastro-image.sh`](build/build-openastro-image.sh) — customizes
  the Armbian image in a chroot and produces a compressed, flashable `.img.xz`.
- [`openastro/openastro-setup.sh`](openastro/openastro-setup.sh) — the OpenAstro
  layer (WiFi AP, baked-in credentials). Idempotent; also runnable directly on a
  booted Armbian board.

## Hardware documentation

See [`hardware/orangepi4pro-a733/inventory.md`](hardware/orangepi4pro-a733/inventory.md).

## License

See [LICENSE.md](LICENSE.md).
