#!/bin/bash
# TSM4 Root Exploit — macOS Network Setup
# Configures your USB ethernet adapter and runs the exploit
set -e

BOLD='\033[1m' GREEN='\033[32m' RED='\033[31m' CYAN='\033[36m' RESET='\033[0m'

echo -e "${BOLD}${GREEN}TSM4 Root Exploit — macOS Setup${RESET}"
echo ""

# Check root
if [ "$(id -u)" != "0" ]; then
  echo -e "${RED}Must run as root: sudo bash setup-macos.sh${RESET}"
  exit 1
fi

# Check Node.js
if ! command -v node &>/dev/null; then
  echo -e "${RED}Node.js not found. Install it: brew install node${RESET}"
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
# List all ethernet interfaces with their status
for iface in $(ifconfig -l); do
  if ifconfig "$iface" 2>/dev/null | grep -q "media.*Ethernet\|media.*baseT\|media.*USB"; then
    status=$(ifconfig "$iface" | grep "status:" | awk '{print $2}')
    media=$(ifconfig "$iface" | grep "media:" | head -1 | sed 's/.*media: //')
    echo "  $iface — $media (status: ${status:-unknown})"
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

# Configure the interface
echo ""
echo -e "${CYAN}Configuring $IFACE with IP 58.162.0.1/24...${RESET}"
ifconfig "$IFACE" 58.162.0.1 netmask 255.255.255.0 up
echo -e "${GREEN}✓${RESET} Interface configured"

# Verify
if ifconfig "$IFACE" | grep -q "58.162.0.1"; then
  echo -e "${GREEN}✓${RESET} $IFACE is UP at 58.162.0.1"
else
  echo -e "${RED}✗ Failed to configure $IFACE${RESET}"
  exit 1
fi

# Enable IP forwarding (needed for DNS/DHCP to work properly)
sysctl -w net.inet.ip.forwarding=1 >/dev/null 2>&1

echo ""
echo -e "${BOLD}${GREEN}Network ready. Starting exploit...${RESET}"
echo -e "${CYAN}Power-cycle your modem now (unplug power, wait 10s, plug back in)${RESET}"
echo ""

# Run the exploit
exec node "$SCRIPT_DIR/tsm4-exploit.js" --cert "$SCRIPT_DIR/cert.pem" --key "$SCRIPT_DIR/key.pem"
