# Native Debian Linux Installation on Qualcomm Snapdragon 625 (MSM8953)

This repository provides a complete, step-by-step guide, automated deployment scripts, and configuration files to install and run native Debian GNU/Linux (arm64) on devices powered by the Qualcomm Snapdragon 625 (MSM8953) platform, utilizing the improved mainline Linux kernel from [bourdoune/msm8953-linux-kernel-improved](https://github.com/bourdoune/msm8953-linux-kernel-improved).

The primary reference device is the **Xiaomi Redmi 5 Plus (codename: vince)**, but the methodology and scripts apply broadly to other MSM8953 boards with corresponding device tree adjustments.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Hardware & Software Prerequisites](#hardware--software-prerequisites)
3. [Repository Structure](#repository-structure)
4. [Step 1: Bootloader & Secondary Bootloader (lk2nd)](#step-1-bootloader--secondary-bootloader-lk2nd)
5. [Step 2: Build the Improved MSM8953 Mainline Kernel](#step-2-build-the-improved-msm8953-mainline-kernel)
6. [Step 3: Generate the Debian arm64 Root Filesystem](#step-3-generate-the-debian-arm64-root-filesystem)
7. [Step 4: Build the Custom Initramfs](#step-4-build-the-custom-initramfs)
8. [Step 5: Package the Boot Image (boot.img)](#step-5-package-the-boot-image-bootimg)
9. [Step 6: Flashing & First Boot](#step-6-flashing--first-boot)
10. [Step 7: Host-Side USB Networking (Plug & Play)](#step-7-host-side-usb-networking-plug--play)
11. [Step 8: Post-Installation Configuration](#step-8-post-installation-configuration)
12. [Step 9: Hardware Validation & Peripherals](#step-9-hardware-validation--peripherals)
13. [Step 10: Dual-Booting Debian & Android](#step-10-dual-booting-debian--android)
14. [Troubleshooting & Recovery](#troubleshooting--recovery)

---

## Architecture Overview

Stock Android devices on Qualcomm platforms rely on Android's proprietary boot header format and early bootloaders (Aboot/Little Kernel) that expect downstream Android kernels. To boot modern mainline Linux and standard distributions:

1. **lk2nd Secondary Bootloader**: Runs as an Android boot image in the `boot` partition, wraps standard mainline Linux device trees and kernels, and provides standard fastboot / extlinux booting capabilities.
2. **Mainline Linux Kernel (MSM8953)**: Close-to-mainline Linux 7.1.3 kernel with patches for Synaptics TD4310 TDDI touchscreen registers, Xiaomi Vince device trees, and Bluetooth BNEP networking.
3. **Initramfs with USB ConfigFS**: Configures early USB Ethernet (RNDIS/NCM) before the root filesystem is mounted, assigning an early static IP address (`192.168.140.121/24`) so the device is immediately reachable over USB for headless administration.
4. **Debian GNU/Linux 12 (Bookworm) / 13 (Trixie)**: Clean standard arm64 Debian rootfs running native `systemd`, `sshd`, and standard Linux package management.

---

## Hardware & Software Prerequisites

### Hardware Requirements
* Qualcomm Snapdragon 625 (MSM8953) smartphone (e.g., Xiaomi Redmi 5 Plus / `vince`) with unlocked bootloader.
* Standard USB-A to Micro-USB (or USB-C depending on model) data cable.
* Host Linux PC (x86_64 or aarch64) running Ubuntu, Debian, Fedora, or Arch Linux.

### Host Software Dependencies
Install the required cross-compilation and rootfs build tools:

```bash
# Debian / Ubuntu host
sudo apt-get update
sudo apt-get install -y \
    build-essential clang lld llvm bc bison flex libssl-dev libelf-dev git \
    debootstrap qemu-user-static binfmt-support e2fsprogs parted fastboot adb curl
```

---

## Repository Structure

```
.
├── README.md
├── scripts/
│   ├── 01_build_kernel.sh          # Clones and compiles msm8953-linux-kernel-improved
│   ├── 02_create_debian_rootfs.sh  # Generates sparse Debian arm64 rootfs image via debootstrap
│   ├── 03_build_initramfs.sh       # Packages initramfs with early USB gadget & storage mounter
│   ├── 04_package_bootimg.sh       # Builds fastboot boot.img with mkbootimg
│   └── post_install.sh             # First-boot configuration script executed on device
├── configs/
│   ├── initramfs/
│   │   └── init                    # Production initramfs early boot script
│   ├── systemd/
│   │   ├── screen-off.service      # Shuts off backlight to prevent burn-in & save power
│   │   └── battery-charging-watchdog.service # Enforces charging on 500mA USB host ports
│   ├── udev/
│   │   └── 99-msm8953-rndis.rules  # Host PC udev rules for plug-and-play USB networking
│   ├── host/
│   │   └── setup-host-network.sh   # Host PC IP forwarding, routing, and NAT script
│   └── boot/
│       └── extlinux.conf           # Dual-boot configuration file
└── tools/
    └── mkbootimg.py                # Standalone AOSP boot image packaging tool
```

---

## Step 1: Bootloader & Secondary Bootloader (lk2nd)

Mainline Linux on MSM8953 devices boots most reliably via `lk2nd`. `lk2nd` acts as a drop-in bootloader that masquerades as an Android kernel to the stock Little Kernel (LK), then provides standard Device Tree passing and fastboot protocol support.

1. Unlock the bootloader using official vendor tools (e.g. Mi Unlock for Xiaomi).
2. Download the latest `lk2nd-msm8953.img` release from the upstream lk2nd project:
   ```bash
   curl -LO https://github.com/msm8953-mainline/lk2nd/releases/latest/download/lk2nd-msm8953.img
   ```
3. Put the phone into fastboot mode (`Power` + `Volume Down`).
4. Flash `lk2nd` to the boot partition:
   ```bash
   fastboot flash boot lk2nd-msm8953.img
   ```
5. Reboot:
   ```bash
   fastboot reboot
   ```
   The phone screen will display the `lk2nd` splash screen and expose an independent, mainline-compatible fastboot interface over USB.

---

## Step 2: Build the Improved MSM8953 Mainline Kernel

Run the automated kernel build script:

```bash
./scripts/01_build_kernel.sh
```

### What this script performs:
1. Clones the kernel from [bourdoune/msm8953-linux-kernel-improved](https://github.com/bourdoune/msm8953-linux-kernel-improved).
2. Applies the `pmos_msm8953_defconfig` (with `CONFIG_BT_BNEP`, `CONFIG_RMI4_CORE`, `CONFIG_RMI4_I2C`, and USB ConfigFS enabled).
3. Cross-compiles using LLVM/Clang:
   ```bash
   make ARCH=arm64 LLVM=1 -j$(nproc) Image.gz dtbs modules
   ```
4. Produces the compiled kernel artifacts in `out/`:
   * `out/Image.gz`
   * `out/msm8953-xiaomi-vince.dtb`
   * `out/kernel_modules.tar.gz`

---

## Step 3: Generate the Debian arm64 Root Filesystem

Run the rootfs generation script (requires sudo for debootstrap and loop mounts):

```bash
sudo ./scripts/02_create_debian_rootfs.sh
```

### What this script performs:
1. Downloads and bootstraps clean Debian 12 (Bookworm) `arm64` base packages via `debootstrap` with QEMU emulation.
2. Installs core utilities: `systemd`, `udev`, `iproute2`, `openssh-server`, `sudo`, `curl`, `kmod`.
3. Configures:
   * Hostname: `msm8953-debian`
   * DNS resolvers: `1.1.1.1` and `8.8.8.8`
   * SSH daemon optimization: `UseDNS no` (prevents 20-second connection latency when working over USB RNDIS without internet).
   * User accounts: Default user `debian` (member of `sudo`) and `root`.
4. Installs power-management systemd units (`screen-off.service` and `battery-charging-watchdog.service`).
5. Extracts compiled kernel modules into `/lib/modules/`.
6. Generates a sparse ext4 disk image: `out/debian_rootfs.img` (4096 MB default).

> [!IMPORTANT]
> Change the default user and root passwords immediately upon your first login.

---

## Step 4: Build the Custom Initramfs

The initramfs is responsible for initializing the hardware before switching root to Debian:

```bash
./scripts/03_build_initramfs.sh
```

### Key Initramfs Functions:
* **Early USB Gadget**: Uses Linux ConfigFS to configure an NCM/RNDIS Ethernet gadget with fixed MAC addresses (`02:00:00:00:00:01` / `02:00:00:00:00:02`).
* **Static IP Assignment**: Assigns `192.168.140.121/24` to the USB interface during boot. If filesystem mounting ever encounters issues, you can rescue the device directly via network shell.
* **Storage Mounting**: Locates the target partition (eMMC `userdata` or external MicroSD), mounts the filesystem, loop-attaches `debian_rootfs.img`, and executes `switch_root /sysroot /lib/systemd/systemd`.

Output artifact: `out/initramfs.cpio.gz`.

---

## Step 5: Package the Boot Image (boot.img)

Generate an Android boot image compatible with fastboot and `lk2nd`:

```bash
./scripts/04_package_bootimg.sh
```

This packages `out/Image.gz`, `out/initramfs.cpio.gz`, and `out/msm8953-xiaomi-vince.dtb` with memory base address `0x80000000` and kernel offset `0x00080000` into `out/boot_debian.img`.

---

## Step 6: Flashing & First Boot

### Option A: Booting from eMMC Userdata Partition
1. Push `debian_rootfs.img` to the phone's internal storage (`userdata` partition) or copy it to a MicroSD card.
2. Put the phone into fastboot mode (under `lk2nd`).
3. Boot directly without permanent modification:
   ```bash
   fastboot boot out/boot_debian.img
   ```
4. Or flash permanently to the boot partition:
   ```bash
   fastboot flash boot out/boot_debian.img
   ```

### Option B: Booting from MicroSD Card
Format partition 1 of your MicroSD card as ext4 with label `debian_root`, copy the root filesystem contents directly to it, insert into phone, and boot.

---

## Step 7: Host-Side USB Networking (Plug & Play)

To automatically configure the network interface and share internet access from your Linux PC whenever the phone is plugged in:

1. Install the host supervisor script:
   ```bash
   sudo cp configs/host/setup-host-network.sh /usr/local/bin/setup-msm8953-host.sh
   sudo chmod +x /usr/local/bin/setup-msm8953-host.sh
   ```

2. Install the udev rule:
   ```bash
   sudo cp configs/udev/99-msm8953-rndis.rules /etc/udev/rules.d/
   sudo udevadm control --reload-rules
   sudo udevadm trigger
   ```

3. Connect the phone via USB. The host assigns IP `192.168.140.127/24` and the phone is reachable at `192.168.140.121`.

4. Test connectivity:
   ```bash
   ping -c 3 192.168.140.121
   ```

5. Log in via SSH:
   ```bash
   ssh debian@192.168.140.121
   # Default password: debian
   ```

---

## Step 8: Post-Installation Configuration

Once logged in, execute the post-installation script to finish system hardening:

```bash
sudo ./scripts/post_install.sh
```

### Manual Security Steps:
1. Change default user passwords:
   ```bash
   passwd debian
   passwd root
   ```

2. Install your SSH public key on the phone:
   ```bash
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   echo "<PASTE_YOUR_PUBLIC_KEY_HERE>" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

3. (Optional) Disable password authentication once keys are verified:
   ```bash
   sudo bash -c 'echo "PasswordAuthentication no" > /etc/ssh/sshd_config.d/nopasswd.conf'
   sudo systemctl reload ssh
   ```

---

## Step 9: Hardware Validation & Peripherals

### 1. Touchscreen (Synaptics ClearPad TD4310)
Verify the clamped presence register fix:
```bash
dmesg | grep -i rmi4
```
Expected output shows successful F11 and F12 registration:
```
rmi4_f12 rmi4-00.fn12: Found F12: register descriptors registered successfully
input: Synaptics RMI4 Touchscreen as /dev/input/eventX
```
Monitor real-time touch events:
```bash
sudo evtest /dev/input/eventX
```

### 2. Wi-Fi (`wcn36xx`)
Verify the wireless interface:
```bash
ip link show wlan0
sudo rfkill unblock wifi
sudo iw dev wlan0 scan
```
Connect using `nmtui` or `wpa_supplicant`.

### 3. Bluetooth PAN (BNEP)
Verify the BNEP module:
```bash
lsmod | grep bnep
bluetoothctl show
```

### 4. Battery Charging Management
The PMIC charger (`qpnp-smbcharger` on PMI8950) restricts current on standard USB 2.0 SDP host ports without explicit watchdog calibration. The installed `battery-charging-watchdog.service` automatically overrides `USB_SUSPEND` and enforces 900 mA charging current, ensuring continuous operation without battery depletion.

Verify current charging rate:
```bash
cat /sys/class/power_supply/battery/current_now
# Positive value indicates active charging (e.g. +790000 uA)
```

---

## Step 10: Dual-Booting Debian & Android

`lk2nd` supports standard `extlinux.conf` menus. To configure dual-booting:

1. Create a `boot` partition or directory containing both kernel pairs and `extlinux.conf`.
2. Copy `configs/boot/extlinux.conf` to `/boot/extlinux/extlinux.conf`.
3. On reboot, `lk2nd` displays a 3-second selection prompt allowing you to switch between Debian GNU/Linux and Android / LineageOS.

---

## Troubleshooting & Recovery

| Issue | Cause | Solution |
| :--- | :--- | :--- |
| `fastboot` hangs on `waiting for device` | Phone is not in lk2nd fastboot mode | Hold `Power` + `Volume Down` until the fastboot screen appears. |
| Host cannot ping `192.168.140.121` | USB interface was renamed or down | Check `ip link` on host PC. Run `sudo setup-msm8953-host.sh` manually. |
| SSH hangs for 20 seconds before password prompt | Reverse DNS lookup timeout | Verify `/etc/ssh/sshd_config.d/nodns.conf` contains `UseDNS no`. |
| Touchscreen input unresponsive | Upstream driver rejected extended 72-byte presence register | Ensure kernel is built from `msm8953-linux-kernel-improved` containing the TD4310 clamp patch. |
| Battery depletes while plugged into PC USB port | Qualcomm PMIC entered `USB_SUSPEND` | Ensure `battery-charging-watchdog.service` is active (`systemctl status battery-charging-watchdog`). |

---

## License

This project is licensed under the MIT License. Kernel patches and kernel configurations follow the GNU General Public License v2.0 (GPL-2.0).
