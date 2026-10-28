#!/usr/bin/env bash
# Step 4: Package fastboot Android boot image (boot.img) using mkbootimg
# Compatible with lk2nd secondary bootloader on MSM8953

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
OUT_DIR="${BASE_DIR}/out"

KERNEL_IMG="${OUT_DIR}/Image.gz"
INITRD_IMG="${OUT_DIR}/initramfs.cpio.gz"
DTB_FILE="${OUT_DIR}/msm8953-xiaomi-vince.dtb"
BOOT_IMG="${OUT_DIR}/boot_debian.img"
MKBOOTIMG="${BASE_DIR}/tools/mkbootimg.py"

echo "=== [1/2] Verifying boot artifacts ==="
for file in "$KERNEL_IMG" "$INITRD_IMG" "$DTB_FILE"; do
    if [ ! -f "$file" ]; then
        echo "[-] Missing required file: $file"
        echo "    Ensure steps 01, 02, and 03 have been executed successfully."
        exit 1
    fi
done

if [ ! -f "$MKBOOTIMG" ]; then
    echo "[-] Missing mkbootimg tool at $MKBOOTIMG"
    exit 1
fi

echo "=== [2/2] Generating boot_debian.img ==="

# MSM8953 typical fastboot memory layout:
# Base: 0x80000000
# Pagesize: 2048
# Cmdline: console=ttyMSM0,115200 console=tty0 consoleblank=60

python3 "$MKBOOTIMG" \
    --kernel "$KERNEL_IMG" \
    --ramdisk "$INITRD_IMG" \
    --dtb "$DTB_FILE" \
    --base 0x80000000 \
    --pagesize 2048 \
    --kernel_offset 0x00080000 \
    --ramdisk_offset 0x01000000 \
    --tags_offset 0x00000100 \
    --cmdline "console=ttyMSM0,115200 console=tty0 consoleblank=60 earlycon=msm_serial_dm,0x78af000" \
    --output "$BOOT_IMG"

echo ""
echo "=== Boot Image Created Successfully ==="
echo "File: $BOOT_IMG ($(du -h "$BOOT_IMG" | awk '{print $1}'))"
echo ""
echo "To test without flashing:"
echo "    fastboot boot $BOOT_IMG"
echo ""
echo "To flash permanently to the boot partition:"
echo "    fastboot flash boot $BOOT_IMG"
