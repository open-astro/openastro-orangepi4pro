#!/bin/bash
# OpenAstro layer for the Orange Pi 4 Pro (Allwinner A733 / sun60iw2).
#
# This turns a stock Armbian "Orange Pi 4 Pro" image (Debian 13 Trixie minimal
# CLI, vendor 6.6 kernel) into the OpenAstro OS: a WiFi access point
# (OpenAstro / 12345678), baked-in credentials (astro/astro, no first-boot
# wizard), and the plumbing AlpacaBridge expects. The OS runs from the microSD
# card — there is no eMMC/SPI install step.
#
# AlpacaBridge is NOT included here — users install it from the OpenAstro apt
# repository (apt install alpacabridge), same as the other platforms.
#
# WiFi/BT is an AIC8800D80 combo chip (vendor driver in the Armbian image; BT
# is UART HCI). AP defaults to 2.4 GHz ch6 HT20 — the conservative choice for
# an untested vendor driver; tune via env once validated on hardware.
#
# Idempotent: safe to re-run. Runs as root, either in the image-build chroot
# (build/build-openastro-image.sh) or post-flash on a booted board.

set -euo pipefail

# --- Config (override via env) ---
AP_SSID="${AP_SSID:-OpenAstro}"
AP_PASSPHRASE="${AP_PASSPHRASE:-12345678}"
AP_IP="${AP_IP:-172.24.1.1}"
AP_SUBNET="${AP_SUBNET:-172.24.1.0/24}"
AP_DHCP_RANGE="${AP_DHCP_RANGE:-172.24.1.50,172.24.1.150,12h}"
AP_CHANNEL="${AP_CHANNEL:-6}"               # 2.4 GHz ch6 HT20 until the AIC8800 driver is validated for 5 GHz AP mode
AP_COUNTRY="${AP_COUNTRY:-US}"

log() { echo "[openastro] $*"; }
[ "$(id -u)" -eq 0 ] || { echo "Must run as root." >&2; exit 1; }

# ============================================================
# Packages
# ============================================================
log "Installing packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    hostapd dnsmasq iptables iw wireless-regdb \
    >/dev/null
# hostapd ships masked on Debian until configured.
systemctl unmask hostapd 2>/dev/null || true

# ============================================================
# WiFi access point (standalone hostapd; NetworkManager ignores wlan0)
# ============================================================
# Same architecture as the iMate image: hostapd owns the radio directly and
# NetworkManager manages only the wired link, so an auto-managing OS can never
# fight the vendor driver over the interface.
log "Configuring WiFi access point..."

cat > /etc/NetworkManager/conf.d/10-openastro-wlan0-unmanaged.conf <<EOF
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF

mkdir -p /etc/hostapd
cat > /etc/hostapd/hostapd.conf <<EOF
# OpenAstro AP (Orange Pi 4 Pro / AIC8800D80). 2.4 GHz HT20 conservative
# defaults; revisit channel/band after validating the vendor driver in AP mode.
interface=wlan0
driver=nl80211
ssid=${AP_SSID}
country_code=${AP_COUNTRY}
ieee80211d=1
hw_mode=g
channel=${AP_CHANNEL}
ieee80211n=1
wmm_enabled=1
auth_algs=1
macaddr_acl=0
wpa=2
wpa_passphrase=${AP_PASSPHRASE}
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0
EOF

cat > /etc/default/hostapd <<EOF
DAEMON_CONF="/etc/hostapd/hostapd.conf"
EOF

cat > /etc/dnsmasq.d/openastro-ap.conf <<EOF
interface=wlan0
listen-address=${AP_IP}
bind-dynamic
server=8.8.8.8
domain-needed
bogus-priv
dhcp-range=${AP_DHCP_RANGE}
EOF

# Uplink-agnostic NAT: share whatever wired uplink exists (Armbian names it
# end0/enx…, not eth0) with WiFi clients.
cat > /etc/openastro-nat.rules <<EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A FORWARD -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -i wlan0 -j ACCEPT
COMMIT
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s ${AP_SUBNET} ! -o wlan0 -j MASQUERADE
COMMIT
EOF
cat > /etc/sysctl.d/99-openastro-ap.conf <<EOF
net.ipv4.ip_forward=1
EOF

# Bring wlan0 up with the static AP address, before hostapd.
cat > /etc/systemd/system/openastro-ap-up.service <<EOF
[Unit]
Description=OpenAstro AP: wlan0 static IP
After=network-pre.target
Wants=network-pre.target
Before=hostapd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/ip addr replace ${AP_IP}/24 dev wlan0
ExecStart=/sbin/ip link set wlan0 up
ExecStartPost=/usr/sbin/iptables-restore /etc/openastro-nat.rules
ExecStop=/sbin/ip addr flush dev wlan0

[Install]
WantedBy=multi-user.target
EOF

systemctl enable openastro-ap-up.service hostapd dnsmasq >/dev/null 2>&1

log "WiFi AP configured (SSID: ${AP_SSID})."

# ============================================================
# Astro-device permissions (present from first boot, so device
# access never depends on install order of AlpacaBridge)
# ============================================================
# ZWO EAF/EFW/CAA are USB HID devices; without this, /dev/hidraw* is
# root-only until AlpacaBridge's own udev rules land AND the device is
# replugged. Shipping the rule in the image removes that ordering trap.
cat > /etc/udev/rules.d/70-openastro-zwo-hid.rules <<'EOF'
# ZWO HID accessories (EAF focuser, EFW/EFWmini filter wheels, CAA rotator)
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="03c3", GROUP="users", MODE="0666"
KERNEL=="hiddev*", ATTRS{idVendor}=="03c3", GROUP="users", MODE="0666"
EOF

# ============================================================
# System identity (turnkey — no Armbian first-boot wizard)
# ============================================================
log "Setting system identity..."
OA_HOSTNAME="${OPENASTRO_HOSTNAME:-openastro}"
OA_USER="${OPENASTRO_USER:-astro}"
OA_PASS="${OPENASTRO_PASS:-astro}"
echo "$OA_HOSTNAME" > /etc/hostname
if grep -q '^127.0.1.1' /etc/hosts; then sed -i "s/^127.0.1.1.*/127.0.1.1\t$OA_HOSTNAME/" /etc/hosts
else echo -e "127.0.1.1\t$OA_HOSTNAME" >> /etc/hosts; fi
id "$OA_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo,dialout,plugdev,audio,video "$OA_USER"
echo "${OA_USER}:${OA_PASS}" | chpasswd
# Disable Armbian's interactive first-login wizard (credentials are baked in).
systemctl disable armbian-firstlogin.service 2>/dev/null || true
rm -f /root/.not_logged_in_yet 2>/dev/null || true

log "OpenAstro OS layer complete (WiFi AP + identity). Install AlpacaBridge with: apt install alpacabridge"
