#!/bin/bash
# TSM4 Root Exploit — Linux Network Setup
# Configures your USB ethernet adapter and runs the exploit
set -e

BOLD='\033[1m' GREEN='\033[32m' RED='\033[31m' CYAN='\033[36m' RESET='\033[0m'

echo -e "${BOLD}${GREEN}TSM4 Root Exploit — Linux Setup${RESET}"
echo ""

# Check root
if [ "$(id -u)" != "0" ]; then
  echo -e "${RED}Must run as root: sudo bash setup-linux.sh${RESET}"
  exit 1
fi

# Check Node.js
if ! command -v node &>/dev/null; then
  echo -e "${RED}Node.js not found. Install it:${RESET}"
  echo "  Ubuntu/Debian: sudo apt install nodejs"
  echo "  Fedora:        sudo dnf install nodejs"
  echo "  Arch:          sudo pacman -S nodejs"
  exit 1
fi
echo -e "${GREEN}✓${RESET} Node.js $(node -v)"

# Check cert files
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$SCRIPT_DIR/cert.pem" ] || [ ! -f "$SCRIPT_DIR/key.pem" ]; then
  echo -e "${RED}✗ cert.pem and key.pem not found in $SCRIPT_DIR${RESET}"
  echo "  You need a valid CA-signed certificate. See README.md"
  exit 1
fi
echo -e "${GREEN}✓${RESET} TLS certificate found"

# Find USB ethernet adapter
echo ""
echo -e "${CYAN}Available network interfaces:${RESET}"
echo ""
for iface in $(ls /sys/class/net/ 2>/dev/null); do
  if [ -d "/sys/class/net/$iface/device" ] && [ "$iface" != "lo" ]; then
    driver=$(readlink -f "/sys/class/net/$iface/device/driver" 2>/dev/null | xargs basename 2>/dev/null || echo "unknown")
    state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo "unknown")
    echo "  $iface — driver: $driver, state: $state"
  fi
done

echo ""
echo -e "${BOLD}Which interface is your USB ethernet adapter?${RESET}"
echo -e "(It should be connected to the modem's WAN/blue port)"
read -p "> " IFACE

if [ -z "$IFACE" ]; then
  echo -e "${RED}No interface specified${RESET}"
  exit 1
fi

# Stop NetworkManager from managing this interface (if running)
if command -v nmcli &>/dev/null; then
  nmcli device set "$IFACE" managed no 2>/dev/null || true
fi

# Configure the interface
echo ""
echo -e "${CYAN}Configuring $IFACE with IP 58.162.0.1/24...${RESET}"
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add 58.162.0.1/24 dev "$IFACE"
ip link set "$IFACE" up
echo -e "${GREEN}✓${RESET} Interface configured"

# Verify
if ip addr show "$IFACE" | grep -q "58.162.0.1"; then
  echo -e "${GREEN}✓${RESET} $IFACE is UP at 58.162.0.1"
else
  echo -e "${RED}✗ Failed to configure $IFACE${RESET}"
  exit 1
fi

# Stop conflicting services
echo ""
echo -e "${CYAN}Stopping conflicting services...${RESET}"
systemctl stop systemd-resolved 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true
echo -e "${GREEN}✓${RESET} Cleared port 53 and 67"

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1

echo ""
echo -e "${BOLD}${GREEN}Network ready. Starting exploit...${RESET}"
echo -e "${CYAN}Power-cycle your modem now (unplug power, wait 10s, plug back in)${RESET}"
echo ""

# Run the exploit
exec node "$SCRIPT_DIR/tsm4-exploit.js" --cert "$SCRIPT_DIR/cert.pem" --key "$SCRIPT_DIR/key.pem"
