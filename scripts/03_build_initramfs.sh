#!/usr/bin/env bash
# Step 3: Build the custom lightweight initramfs
# Includes busybox, USB ConfigFS network gadget, and storage mounting logic.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
OUT_DIR="${BASE_DIR}/out"
INITRD_STAGING="${BASE_DIR}/initramfs_staging"
OUTPUT_INITRD="${OUT_DIR}/initramfs.cpio.gz"

echo "=== [1/4] Preparing initramfs staging directory ==="
rm -rf "$INITRD_STAGING"
mkdir -p "$INITRD_STAGING"/{bin,sbin,dev,proc,sys,mnt/storage,sysroot,lib/modules}
mkdir -p "$OUT_DIR"

echo "=== [2/4] Providing BusyBox arm64 static binary ==="
BUSYBOX_BIN="${INITRD_STAGING}/bin/busybox"

# Check if busybox-static arm64 is available locally or in cache
if command -v busybox &>/dev/null && [ "$(readelf -h "$(command -v busybox)" 2>/dev/null | grep -i 'AArch64' || true)" != "" ]; then
    cp "$(command -v busybox)" "$BUSYBOX_BIN"
elif [ -f "${BASE_DIR}/tools/busybox-arm64" ]; then
    cp "${BASE_DIR}/tools/busybox-arm64" "$BUSYBOX_BIN"
else
    echo "[*] Downloading static BusyBox binary for aarch64..."
    curl -sSL "https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox" -o "$BUSYBOX_BIN" 2>/dev/null || true
    # Download official aarch64 musl static busybox
    curl -sSL "https://busybox.net/downloads/binaries/1.35.0-aarch64-linux-musl/busybox" -o "$BUSYBOX_BIN"
fi

chmod +x "$BUSYBOX_BIN"

# Create symlinks for essential utilities
cd "${INITRD_STAGING}/bin"
./busybox --install -s . 2>/dev/null || true
cd "$BASE_DIR"

echo "=== [3/4] Installing /init boot script ==="
cp "${BASE_DIR}/configs/initramfs/init" "${INITRD_STAGING}/init"
chmod +x "${INITRD_STAGING}/init"

# Copy gadget kernel modules if available in out/
if [ -f "$OUT_DIR/kernel_modules.tar.gz" ]; then
    echo "[*] Adding USB composite modules to initramfs..."
    tar -xzf "$OUT_DIR/kernel_modules.tar.gz" -C "$INITRD_STAGING" \
        --wildcards '*/libcomposite.ko' '*/u_ether.ko' '*/usb_f_ncm.ko' '*/usb_f_rndis.ko' 2>/dev/null || true
fi

echo "=== [4/4] Packing initramfs.cpio.gz ==="
cd "$INITRD_STAGING"
find . -mindepth 1 | cpio -o -H newc | gzip -9 > "$OUTPUT_INITRD"
cd "$BASE_DIR"

rm -rf "$INITRD_STAGING"

echo ""
echo "=== Initramfs Packaging Complete ==="
echo "Output: $OUTPUT_INITRD ($(du -h "$OUTPUT_INITRD" | awk '{print $1}'))"
