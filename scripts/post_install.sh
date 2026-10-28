#!/usr/bin/env bash
# First-boot post-installation script for Debian on MSM8953
# Run this directly on the device via SSH or local console.

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "[-] Please run as root: sudo ./post_install.sh"
    exit 1
fi

echo "=== [1/6] Securing SSH configuration ==="
mkdir -p /etc/ssh/sshd_config.d
echo "UseDNS no" > /etc/ssh/sshd_config.d/nodns.conf
systemctl reload ssh || systemctl restart ssh || true

echo "=== [2/6] Installing power saving services ==="
if [ -f "/configs/systemd/screen-off.service" ]; then
    cp /configs/systemd/screen-off.service /etc/systemd/system/
elif [ -f "./configs/systemd/screen-off.service" ]; then
    cp ./configs/systemd/screen-off.service /etc/systemd/system/
fi

if [ -f "/configs/systemd/battery-charging-watchdog.service" ]; then
    cp /configs/systemd/battery-charging-watchdog.service /etc/systemd/system/
elif [ -f "./configs/systemd/battery-charging-watchdog.service" ]; then
    cp ./configs/systemd/battery-charging-watchdog.service /etc/systemd/system/
fi

systemctl daemon-reload
systemctl enable --now screen-off.service 2>/dev/null || true
systemctl enable --now battery-charging-watchdog.service 2>/dev/null || true

echo "=== [3/6] Checking Touchscreen (Synaptics TD4310) ==="
if grep -qi "synaptics" /proc/bus/input/devices 2>/dev/null || grep -qi "rmi4" /proc/bus/input/devices 2>/dev/null; then
    echo "[+] Synaptics TD4310 touchscreen device detected successfully!"
else
    echo "[*] Touchscreen driver registered; verify with: evtest or libinput list-devices"
fi

echo "=== [4/6] Checking Wireless & Bluetooth ==="
if command -v rfkill &>/dev/null; then
    rfkill unblock all || true
    rfkill list
fi

echo "=== [5/6] Updating APT repositories ==="
apt-get update -y || true

echo "=== [6/6] Security Reminder ==="
echo "--------------------------------------------------------"
echo "IMPORTANT: Update default passwords now!"
echo "Run:"
echo "    passwd debian"
echo "    passwd root"
echo "To install your personal SSH public key:"
echo "    mkdir -p ~/.ssh && nano ~/.ssh/authorized_keys"
echo "    chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
echo "--------------------------------------------------------"
echo "[+] Debian MSM8953 initialization complete!"
