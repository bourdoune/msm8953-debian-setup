#!/usr/bin/env bash
# Step 1: Clone and build the improved MSM8953 Linux kernel
# Target Architecture: ARM64 (aarch64)
# Device: Xiaomi Redmi 5 Plus (vince) / Qualcomm Snapdragon 625 (MSM8953)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
KERNEL_DIR="${BASE_DIR}/msm8953-linux-kernel-improved"
OUT_DIR="${BASE_DIR}/out"

echo "=== [1/4] Checking build dependencies ==="
MISSING_PKGS=()
for cmd in git clang ld.lld make python3; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_PKGS+=("$cmd")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo "[-] Missing dependencies: ${MISSING_PKGS[*]}"
    echo "    On Debian/Ubuntu, install with:"
    echo "    sudo apt-get install build-essential clang lld llvm libssl-dev libelf-dev bc bison flex git"
    exit 1
fi

echo "=== [2/4] Cloning improved MSM8953 kernel ==="
if [ ! -d "$KERNEL_DIR/.git" ]; then
    git clone --depth 1 https://github.com/bourdoune/msm8953-linux-kernel-improved.git "$KERNEL_DIR"
else
    echo "[*] Kernel repository already exists at $KERNEL_DIR"
fi

echo "=== [3/4] Configuring kernel ==="
cd "$KERNEL_DIR"
export ARCH=arm64
export LLVM=1

# Use verified postmarketOS defconfig if available, or generate from msm8953.config
if [ -f "arch/arm64/configs/pmos_msm8953_defconfig" ]; then
    echo "[*] Using pmos_msm8953_defconfig"
    make pmos_msm8953_defconfig
else
    echo "[*] Merging defconfig with msm8953 and xiaomi-vince fragments"
    make defconfig
    ./scripts/kconfig/merge_config.sh -m .config \
        arch/arm64/configs/msm8953.config \
        arch/arm64/configs/xiaomi-vince.config
    make olddefconfig
fi

echo "=== [4/4] Compiling kernel and device tree blobs ==="
CORES=$(nproc)
make -j"$CORES" Image.gz dtbs modules

mkdir -p "$OUT_DIR"
cp arch/arm64/boot/Image.gz "$OUT_DIR/Image.gz"
cp arch/arm64/boot/dts/qcom/msm8953-xiaomi-vince.dtb "$OUT_DIR/msm8953-xiaomi-vince.dtb"

echo "[*] Installing modules to $OUT_DIR/modules..."
make INSTALL_MOD_PATH="$OUT_DIR/modules_staging" modules_install
tar -czf "$OUT_DIR/kernel_modules.tar.gz" -C "$OUT_DIR/modules_staging" lib
rm -rf "$OUT_DIR/modules_staging"

echo ""
echo "=== Build Complete ==="
echo "Kernel:      $OUT_DIR/Image.gz"
echo "Device Tree: $OUT_DIR/msm8953-xiaomi-vince.dtb"
echo "Modules:     $OUT_DIR/kernel_modules.tar.gz"
