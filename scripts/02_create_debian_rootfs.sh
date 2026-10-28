#!/usr/bin/env bash
# Step 2: Create a Debian arm64 root filesystem image
# Generates a bootable ext4 filesystem image suitable for loop-mount or direct eMMC flashing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
OUT_DIR="${BASE_DIR}/out"
ROOTFS_DIR="${BASE_DIR}/rootfs_staging"
IMAGE_FILE="${OUT_DIR}/debian_rootfs.img"
IMAGE_SIZE_MB="${IMAGE_SIZE_MB:-4096}" # 4 GB default

SUITE="${SUITE:-bookworm}" # or trixie
MIRROR="${MIRROR:-http://deb.debian.org/debian}"

echo "=== [1/6] Checking host tools ==="
if [ "$EUID" -ne 0 ]; then
    echo "[-] This script requires root privileges to mount filesystems and run debootstrap."
    echo "    Please run with: sudo ./02_create_debian_rootfs.sh"
    exit 1
fi

for cmd in debootstrap qemu-aarch64-static mkfs.ext4 parted; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "[-] Missing tool: $cmd"
        echo "    Install with: sudo apt-get install debootstrap qemu-user-static binfmt-support e2fsprogs parted"
        exit 1
    fi
done

mkdir -p "$OUT_DIR"
rm -rf "$ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR"

echo "=== [2/6] Running debootstrap for Debian ($SUITE / arm64) ==="
debootstrap --arch=arm64 --foreign --include=systemd,systemd-sysv,udev,iproute2,openssh-server,sudo,curl,wget,kmod,ca-certificates,locales,tzdata,procps,net-tools \
    "$SUITE" "$ROOTFS_DIR" "$MIRROR"

# Copy QEMU user binary for second stage execution if host is x86_64
if [ "$(uname -m)" != "aarch64" ]; then
    cp "$(command -v qemu-aarch64-static)" "$ROOTFS_DIR/usr/bin/"
    chroot "$ROOTFS_DIR" /debootstrap/debootstrap --second-stage
fi

echo "=== [3/6] Configuring base Debian system ==="

# Set hostname
echo "msm8953-debian" > "$ROOTFS_DIR/etc/hostname"

# Set hosts
cat << 'EOF' > "$ROOTFS_DIR/etc/hosts"
127.0.0.1   localhost msm8953-debian
::1         localhost ip6-localhost ip6-loopback
EOF

# Set DNS resolver
cat << 'EOF' > "$ROOTFS_DIR/etc/resolv.conf"
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# Set APT sources
cat << EOF > "$ROOTFS_DIR/etc/apt/sources.list"
deb http://deb.debian.org/debian ${SUITE} main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${SUITE}-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security ${SUITE}-security main contrib non-free non-free-firmware
EOF

# Configure locales and timezone
chroot "$ROOTFS_DIR" /bin/bash -c "
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
"

# Create standard user and set initial passwords
# NOTE: Replace 'debian' password immediately upon first login!
chroot "$ROOTFS_DIR" /bin/bash -c "
useradd -m -s /bin/bash -G sudo debian
echo 'root:debian' | chpasswd
echo 'debian:debian' | chpasswd
"

# Configure OpenSSH server:
# Disable UseDNS to avoid 20-second connection delay when offline or USB-tethered
mkdir -p "$ROOTFS_DIR/etc/ssh/sshd_config.d"
echo "UseDNS no" > "$ROOTFS_DIR/etc/ssh/sshd_config.d/nodns.conf"
echo "PermitRootLogin yes" > "$ROOTFS_DIR/etc/ssh/sshd_config.d/permitroot.conf"

# Copy systemd power saving and watchdog services
if [ -f "$BASE_DIR/configs/systemd/screen-off.service" ]; then
    cp "$BASE_DIR/configs/systemd/screen-off.service" "$ROOTFS_DIR/etc/systemd/system/"
    chroot "$ROOTFS_DIR" systemctl enable screen-off.service 2>/dev/null || true
fi

if [ -f "$BASE_DIR/configs/systemd/battery-charging-watchdog.service" ]; then
    cp "$BASE_DIR/configs/systemd/battery-charging-watchdog.service" "$ROOTFS_DIR/etc/systemd/system/"
    chroot "$ROOTFS_DIR" systemctl enable battery-charging-watchdog.service 2>/dev/null || true
fi

# Clean up QEMU binary and APT caches
[ -f "$ROOTFS_DIR/usr/bin/qemu-aarch64-static" ] && rm -f "$ROOTFS_DIR/usr/bin/qemu-aarch64-static"
chroot "$ROOTFS_DIR" apt-get clean 2>/dev/null || true
rm -rf "$ROOTFS_DIR/var/lib/apt/lists/*"

echo "=== [4/6] Creating ext4 sparse rootfs image (${IMAGE_SIZE_MB} MB) ==="
dd if=/dev/zero of="$IMAGE_FILE" bs=1M count=0 seek="$IMAGE_SIZE_MB"
mkfs.ext4 -F -L "debian_root" "$IMAGE_FILE"

echo "=== [5/6] Copying filesystem into image ==="
MOUNT_POINT="${BASE_DIR}/mnt_tmp"
mkdir -p "$MOUNT_POINT"
mount -o loop "$IMAGE_FILE" "$MOUNT_POINT"

cp -a "$ROOTFS_DIR"/* "$MOUNT_POINT"/

# Install kernel modules if previously built
if [ -f "$OUT_DIR/kernel_modules.tar.gz" ]; then
    echo "[*] Extracting kernel modules into rootfs..."
    tar -xzf "$OUT_DIR/kernel_modules.tar.gz" -C "$MOUNT_POINT"/
fi

sync
umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT"
rm -rf "$ROOTFS_DIR"

echo "=== [6/6] Packaging tarball backup ==="
tar -czf "$OUT_DIR/debian-rootfs-minimal.tar.gz" -C "$OUT_DIR" "$(basename "$IMAGE_FILE")"

echo ""
echo "=== Rootfs Generation Complete ==="
echo "Raw Image: $IMAGE_FILE"
echo "Default user: 'debian' (password: 'debian')"
echo "Root user:    'root'   (password: 'debian')"
echo "IMPORTANT: Change these default passwords upon first SSH login!"
