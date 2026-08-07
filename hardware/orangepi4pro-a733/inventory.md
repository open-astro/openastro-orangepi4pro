# Orange Pi 4 Pro — hardware inventory

Status: **pre-validation** — fill in as items are confirmed on real hardware.

## SoC / board

| Item | Value |
|------|-------|
| SoC | Allwinner A733 (sun60iw2), 2× Cortex-A76 @ 2.0 GHz + 6× Cortex-A55 @ 1.8 GHz |
| Armbian board config | [`orangepi4pro.csc`](https://github.com/armbian/build/tree/main/config/boards/orangepi4pro.csc) (community-supported) |
| Kernel | vendor 6.6 BSP only — no mainline/`current` branch yet |
| DTB | `allwinner/sun60i-a733-orangepi-4-pro.dtb` |
| Boot media | microSD (this image runs from SD; board also has eMMC + 16 MB SPI-NOR, unused by us) |
| Power | 5 V / 3 A USB-C |

## WiFi / BT

| Item | Value |
|------|-------|
| Chip | AIC8800D80 combo (vendor driver in Armbian image) |
| BT | UART HCI on ttyS1, needs userspace bring-up (`SUN60IW2_UART_BT`) |
| AP mode | TODO: validate hostapd 2.4 GHz ch6 HT20; then test 5 GHz |

## To validate on hardware

- [ ] Stock Armbian `Trixie_vendor_minimal` boots from SD
- [ ] `wlan0` appears; hostapd AP comes up (SSID `OpenAstro`)
- [ ] NAT/DHCP for AP clients works over the ethernet uplink
- [ ] USB: ZWO camera, EAF, EFW enumerate (vendor 6.6 kernel — see README caveat)
- [ ] AlpacaBridge ConformU run (v4.4.0)
- [ ] SD/eMMC device numbering (`lsblk`) recorded here
