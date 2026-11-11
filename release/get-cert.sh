#!/bin/bash
# Helper to get a free Let's Encrypt certificate for the TSM4 exploit
# The modem validates cert chain but NOT hostname, so any valid cert works
set -e

BOLD='\033[1m' GREEN='\033[32m' RED='\033[31m' CYAN='\033[36m' RESET='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${BOLD}${GREEN}TSM4 Exploit — Get TLS Certificate${RESET}"
echo ""
echo "The modem requires a real CA-signed certificate (self-signed won't work)."
echo "This script helps you get a free one from Let's Encrypt."
echo ""
echo -e "${BOLD}Option 1: DuckDNS (easiest — free domain + cert)${RESET}"
echo ""
echo "  1. Go to https://www.duckdns.org and sign in"
echo "  2. Create a free subdomain (e.g. mymodem.duckdns.org)"
echo "  3. Note your DuckDNS token from the dashboard"
echo ""
read -p "Enter your DuckDNS subdomain (e.g. mymodem): " SUBDOMAIN
read -p "Enter your DuckDNS token: " TOKEN

if [ -z "$SUBDOMAIN" ] || [ -z "$TOKEN" ]; then
  echo -e "${RED}Both subdomain and token are required${RESET}"
  echo ""
  echo -e "${BOLD}Option 2: Manual (any domain you own)${RESET}"
  echo ""
  echo "  If you already have a domain and certbot installed:"
  echo ""
  echo "    sudo certbot certonly --manual --preferred-challenges dns -d yourdomain.com"
  echo "    cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem $SCRIPT_DIR/cert.pem"
  echo "    cp /etc/letsencrypt/live/yourdomain.com/privkey.pem $SCRIPT_DIR/key.pem"
  echo ""
  exit 1
fi

DOMAIN="${SUBDOMAIN}.duckdns.org"
echo ""
echo -e "${CYAN}Getting certificate for ${DOMAIN}...${RESET}"

# Check for certbot
if ! command -v certbot &>/dev/null; then
  echo -e "${RED}certbot not found. Installing...${RESET}"
  if command -v brew &>/dev/null; then
    brew install certbot
  elif command -v apt &>/dev/null; then
    sudo apt install -y certbot
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y certbot
  else
    echo -e "${RED}Can't auto-install certbot. Install it manually:${RESET}"
    echo "  https://certbot.eff.org/instructions"
    exit 1
  fi
fi

# Create DuckDNS auth hook scripts
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

# Copy certs
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
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

# Cleanup
rm -f "$AUTH_HOOK" "$CLEANUP_HOOK"
