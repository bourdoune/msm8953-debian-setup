#!/usr/bin/env bash
# Host-side networking supervisor for MSM8953 USB RNDIS/NCM gadget
# Usage: ./setup-host-network.sh [INTERFACE_NAME]

set -euo pipefail

DEV="${1:-}"

# Auto-detect gadget interface if not specified
if [ -z "$DEV" ]; then
    DEV=$(ip -o link show | awk -F": " '{print $2}' | grep -E "^enx|^rndis|^usb[0-9]" | head -n 1 || true)
fi

if [ -z "$DEV" ]; then
    echo "[-] No active USB gadget network interface found."
    exit 1
fi

echo "[*] Configuring host interface: $DEV"
ip link set "$DEV" up
ip addr add 192.168.140.127/24 dev "$DEV" 2>/dev/null || true

# Enable IPv4 forwarding
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Detect primary WAN/upstream interface
WAN_DEV=$(ip route show default | awk '{print $5}' | head -n 1 || true)

if [ -n "$WAN_DEV" ]; then
    echo "[*] Configuring NAT forwarding via upstream interface: $WAN_DEV"

    # Forwarding rules between gadget and upstream network
    iptables -C FORWARD -i "$DEV" -o "$WAN_DEV" -j ACCEPT 2>/dev/null || iptables -A FORWARD -i "$DEV" -o "$WAN_DEV" -j ACCEPT
    iptables -C FORWARD -i "$WAN_DEV" -o "$DEV" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -A FORWARD -i "$WAN_DEV" -o "$DEV" -m state --state RELATED,ESTABLISHED -j ACCEPT

    # Outbound NAT Masquerade
    iptables -t nat -C POSTROUTING -s 192.168.140.0/24 -o "$WAN_DEV" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 192.168.140.0/24 -o "$WAN_DEV" -j MASQUERADE
    echo "[+] Host network ready: Device reachable at 192.168.140.121"
fi
