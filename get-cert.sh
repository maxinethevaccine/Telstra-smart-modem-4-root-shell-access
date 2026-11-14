#!/bin/bash
# Helper to get a free Let's Encrypt certificate for the TSM4 exploit
# The modem validates cert chain but NOT hostname, so any valid cert works
set -e

BOLD='\033[1m' GREEN='\033[32m' RED='\033[31m' CYAN='\033[36m' YELLOW='\033[33m' RESET='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${BOLD}${GREEN}TSM4 Exploit — Get TLS Certificate${RESET}"
echo ""
echo "The modem requires a real CA-signed certificate (self-signed won't work)."
echo "This script helps you get a free one from Let's Encrypt."
echo ""

# Check for certbot first
if ! command -v certbot &>/dev/null; then
  echo -e "${RED}certbot not found.${RESET}"
  echo ""
  echo "Install it first (do NOT run brew as root):"
  echo "  macOS:         brew install certbot"
  echo "  Ubuntu/Debian: sudo apt install -y certbot"
  echo "  Fedora:        sudo dnf install -y certbot"
  echo "  Manual:        https://certbot.eff.org/instructions"
  echo ""
  echo "Then re-run this script."
  exit 1
fi

echo -e "${BOLD}Choose how to get your certificate:${RESET}"
echo ""
echo "  1) DuckDNS — free domain + automatic DNS challenge (easiest)"
echo "  2) Own domain — use a domain you already own"
echo ""
read -p "Enter choice [1/2]: " CERT_CHOICE

case "$CERT_CHOICE" in
  2)
    # ── Option 2: Own domain ──
    echo ""
    echo -e "${BOLD}Own Domain${RESET}"
    echo ""
    read -p "Enter your domain (e.g. example.com): " DOMAIN

    if [ -z "$DOMAIN" ]; then
      echo -e "${RED}No domain entered${RESET}"
      exit 1
    fi

    echo ""
    echo -e "${CYAN}Running certbot for ${DOMAIN}...${RESET}"
    echo -e "${YELLOW}You will need to add a DNS TXT record when prompted.${RESET}"
    echo ""

    sudo certbot certonly \
      --manual \
      --preferred-challenges dns \
      -d "$DOMAIN" \
      --agree-tos \
      --no-eff-email \
      --register-unsafely-without-email \
      --force-renewal

    CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
    ;;

  *)
    # ── Option 1: DuckDNS (default) ──
    echo ""
    echo -e "${BOLD}DuckDNS${RESET}"
    echo ""
    echo "  1. Go to https://www.duckdns.org and sign in"
    echo "  2. Create a free subdomain (e.g. mymodem.duckdns.org)"
    echo "  3. Note your DuckDNS token from the dashboard"
    echo ""
    read -p "Enter your DuckDNS subdomain (e.g. mymodem): " SUBDOMAIN
    read -p "Enter your DuckDNS token: " TOKEN

    if [ -z "$SUBDOMAIN" ] || [ -z "$TOKEN" ]; then
      echo -e "${RED}Both subdomain and token are required${RESET}"
      exit 1
    fi

    DOMAIN="${SUBDOMAIN}.duckdns.org"
    echo ""
    echo -e "${CYAN}Getting certificate for ${DOMAIN}...${RESET}"

    AUTH_HOOK=$(mktemp)
    CLEANUP_HOOK=$(mktemp)

    cat > "$AUTH_HOOK" << AUTHEOF
#!/bin/bash
curl -s "https://www.duckdns.org/update?domains=${SUBDOMAIN}&token=${TOKEN}&txt=\${CERTBOT_VALIDATION}" > /dev/null
sleep 30
AUTHEOF

    cat > "$CLEANUP_HOOK" << CLEANEOF
#!/bin/bash
curl -s "https://www.duckdns.org/update?domains=${SUBDOMAIN}&token=${TOKEN}&txt=&clear=true" > /dev/null
CLEANEOF

    chmod +x "$AUTH_HOOK" "$CLEANUP_HOOK"

    echo -e "${CYAN}Running certbot with DNS-01 challenge...${RESET}"
    echo ""

    sudo certbot certonly \
      --manual \
      --preferred-challenges dns \
      --manual-auth-hook "$AUTH_HOOK" \
      --manual-cleanup-hook "$CLEANUP_HOOK" \
      -d "$DOMAIN" \
      --agree-tos \
      --no-eff-email \
      --register-unsafely-without-email \
      --force-renewal

    rm -f "$AUTH_HOOK" "$CLEANUP_HOOK"

    CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
    ;;
esac

# Copy certs to script directory
if [ -d "$CERT_DIR" ]; then
  sudo cp "$CERT_DIR/fullchain.pem" "$SCRIPT_DIR/cert.pem"
  sudo cp "$CERT_DIR/privkey.pem" "$SCRIPT_DIR/key.pem"
  sudo chmod 644 "$SCRIPT_DIR/cert.pem" "$SCRIPT_DIR/key.pem"
  echo ""
  echo -e "${GREEN}${BOLD}Certificate obtained and copied!${RESET}"
  echo "  cert.pem: $SCRIPT_DIR/cert.pem"
  echo "  key.pem:  $SCRIPT_DIR/key.pem"
  echo ""
  echo "You can now run the exploit:"
  echo "  sudo bash setup-macos.sh   (macOS)"
  echo "  sudo bash setup-linux.sh   (Linux)"
else
  echo -e "${RED}Certificate directory not found at $CERT_DIR${RESET}"
  echo "Check certbot output above for errors."
  exit 1
fi
