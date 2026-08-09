#!/bin/bash
# Build the OpenAstro Orange Pi 4 Pro OS image.
#
# Customizes a stock Armbian "Orange Pi 4 Pro" image (Debian 13 Trixie minimal
# CLI, vendor 6.6 kernel) by running the OpenAstro layer
# (openastro/openastro-setup.sh) inside a chroot, then repacks it as a
# compressed, flashable image. The build host must be aarch64 (native chroot -
# no qemu), e.g. another Armbian/Debian arm64 box or the board itself.
#
# Usage: sudo build/build-openastro-image.sh <stock-armbian.img[.xz]> [output.img.xz]
#
# KERNEL_DEBS=<dir>: install custom kernel .debs (linux-image/-dtb/-headers from
# armbian-build output/debs) into the image, replacing the stock kernel. Used to
# ship the CONFIG_HIDRAW-enabled vendor kernel needed for ZWO EAF/EFW.
#
# AlpacaBridge is NOT baked in - users apt-install it after flashing.
set -euo pipefail

REPODIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:?usage: $0 <stock-armbian.img[.xz]> [output.img.xz]}"
OUT="${2:-$REPODIR/images/openastro-orangepi4pro.img.xz}"
WORK="$(mktemp -d)"
IMG="$WORK/openastro.img"
MNT="$WORK/rootfs"
LOOP=""

log() { echo "[build] $*"; }
cleanup() {
    set +e
    umount -lf "$MNT/dev/pts" "$MNT/dev" "$MNT/proc" "$MNT/sys" 2>/dev/null
    mountpoint -q "$MNT" && umount -lf "$MNT"
    [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT

[ "$(id -u)" -eq 0 ] || { echo "Must run as root." >&2; exit 1; }
[ "$(uname -m)" = aarch64 ] || { echo "Build host must be aarch64 (native chroot)." >&2; exit 1; }

log "Staging source image..."
case "$SRC" in
    *.xz) xz -dc "$SRC" > "$IMG" ;;
    *)    cp --reflink=auto "$SRC" "$IMG" ;;
esac

# Grow the image so there's room to install packages in the chroot. The unused
# space is zeroed and xz-compressed away at the end, so the .img.xz stays small.
truncate -s +1500M "$IMG"   # extra headroom for custom kernel debs; zeroed+compressed away at the end
LOOP=$(losetup -fP --show "$IMG")
parted -s "$LOOP" resizepart 1 100%
partprobe "$LOOP" 2>/dev/null || true; sleep 1
e2fsck -fy "${LOOP}p1" >/dev/null 2>&1 || true
resize2fs "${LOOP}p1" >/dev/null 2>&1
mkdir -p "$MNT"
mount "${LOOP}p1" "$MNT"
log "rootfs free space: $(df -h "$MNT" | awk 'NR==2{print $4}')"

# chroot plumbing (native aarch64, networked via the host)
mount -t proc proc "$MNT/proc"
mount -t sysfs sys "$MNT/sys"
mount -o bind /dev "$MNT/dev"
mount -t devpts devpts "$MNT/dev/pts"
# The image's /etc/resolv.conf is a dangling symlink (resolved at runtime), so
# replace it with a real one for the chroot's apt, and restore it afterwards.
RESOLV_LINK=$(readlink "$MNT/etc/resolv.conf" 2>/dev/null || true)
rm -f "$MNT/etc/resolv.conf"
cp -L /etc/resolv.conf "$MNT/etc/resolv.conf" 2>/dev/null || echo 'nameserver 8.8.8.8' > "$MNT/etc/resolv.conf"

if [ -n "${KERNEL_DEBS:-}" ]; then
    ls "$KERNEL_DEBS"/linux-image-*.deb >/dev/null 2>&1 || { echo "KERNEL_DEBS=$KERNEL_DEBS has no linux-image-*.deb" >&2; exit 1; }
    log "Installing custom kernel debs from $KERNEL_DEBS..."
    install -d "$MNT/opt/kernel-debs"
    cp "$KERNEL_DEBS"/linux-{image,dtb,headers}-*.deb "$MNT/opt/kernel-debs/" 2>/dev/null || cp "$KERNEL_DEBS"/linux-{image,dtb}-*.deb "$MNT/opt/kernel-debs/"
    chroot "$MNT" /bin/bash -c "dpkg -i /opt/kernel-debs/*.deb"
    rm -rf "$MNT/opt/kernel-debs"
fi

install -d "$MNT/opt/openastro"
install -m 0755 "$REPODIR/openastro/openastro-setup.sh" "$MNT/opt/openastro/"

log "Running openastro-setup.sh in chroot..."
chroot "$MNT" /bin/bash -c "cd /opt/openastro && ./openastro-setup.sh"

log "Cleaning image..."
chroot "$MNT" /bin/bash -c "apt-get clean" || true
rm -rf "$MNT"/var/lib/apt/lists/* "$MNT"/var/log/* "$MNT"/tmp/* 2>/dev/null || true
# Recreate the persistent-journal dir the log wipe just removed (matches
# openastro-setup.sh; systemd-journal is gid 999 on this image, but use the
# name via chroot to be safe).
install -d -m 2755 "$MNT/var/log/journal"
chroot "$MNT" chgrp systemd-journal /var/log/journal 2>/dev/null || true
rm -f "$MNT"/etc/ssh/ssh_host_*           # regenerated per-device on first boot
: > "$MNT/etc/machine-id" 2>/dev/null || true
rm -f "$MNT/etc/resolv.conf"              # don't ship the build host's DNS
[ -n "${RESOLV_LINK:-}" ] && ln -sf "$RESOLV_LINK" "$MNT/etc/resolv.conf"  # restore runtime symlink

log "Zero-filling free space (so the image compresses small)..."
dd if=/dev/zero of="$MNT/ZERO.fill" bs=4M status=none 2>/dev/null || true
sync; rm -f "$MNT/ZERO.fill"; sync

umount -lf "$MNT/dev/pts" "$MNT/dev" "$MNT/proc" "$MNT/sys"
umount "$MNT"
losetup -d "$LOOP"; LOOP=""

log "Compressing -> $OUT"
mkdir -p "$(dirname "$OUT")"
xz -T0 -6 -c "$IMG" > "$OUT"
( cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
log "Done: $OUT ($(du -h "$OUT" | cut -f1))"
