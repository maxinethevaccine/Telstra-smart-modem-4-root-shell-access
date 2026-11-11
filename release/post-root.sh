#!/bin/sh
# TSM4 Post-Root Script — run this ON the modem via SSH after the exploit
# Usage: ssh root@58.162.0.2 'sh -s' < post-root.sh
#    or: scp post-root.sh root@58.162.0.2:/tmp/ && ssh root@58.162.0.2 'sh /tmp/post-root.sh'

set -e
echo "============================================"
echo "  TSM4 Post-Root — Persistence & De-Telstra"
echo "============================================"
echo ""

# ── 1. Set root password ────────────────────────────────────────────────────
echo "[1/7] Setting root password..."
echo "Enter a new root password (you'll need this for future SSH access):"
passwd root
echo ""

# ── 2. Disable ssh-osu (it kills dropbear unless volatile SshdEnabled is set)
echo "[2/7] Disabling ssh-osu (SSH persistence)..."
/etc/init.d/ssh-osu disable 2>/dev/null || true
echo "  Done — dropbear will survive reboots now"
echo ""

# ── 3. Enable SSH on WAN + LAN ──────────────────────────────────────────────
echo "[3/7] Configuring dropbear for LAN + WAN access..."
uci set dropbear.wan_ssh=dropbear
uci set dropbear.wan_ssh.PasswordAuth='on'
uci set dropbear.wan_ssh.RootPasswordAuth='on'
uci set dropbear.wan_ssh.Port='22'
uci set dropbear.wan_ssh.Interface=''
uci commit dropbear
# Disable Telstra's debug dropbear instances
uci set dropbear.telstra_debug.enable='0' 2>/dev/null || true
uci set dropbear.telstra_debug6.enable='0' 2>/dev/null || true
uci commit dropbear
echo "  Done"
echo ""

# ── 4. Kill TR-069 / de-Telstra ─────────────────────────────────────────────
echo "[4/7] Disabling TR-069 (de-Telstra)..."
uci set tr69.mgmt_srv.enable='false'
uci set tr69.periodic_inform.enable='false'
uci set tr69.conn_request.enable='false'
uci commit tr69
/etc/init.d/tr69-osu disable 2>/dev/null || true
/etc/init.d/5g-osl-tr69-manager disable 2>/dev/null || true
killall tr69d tr69-osu 5g-osl-tr69-manager 2>/dev/null || true
echo "  Done — modem will no longer phone home to Telstra"
echo ""

# ── 5. Upgrade admin to internal role (full GUI access) ─────────────────────
echo "[5/7] Upgrading admin role to internal..."
uci set omdw_users.admin.role='internal'
uci commit omdw_users
echo "  Done"
echo ""

# ── 6. Unlock all GUI features ──────────────────────────────────────────────
echo "[6/7] Unlocking hidden GUI menus..."

# 6a. Dynamic features (REST API template)
FEATURES_TPL="/etc/rest-server/template/telstra/get_features.tpl"
if [ -f "$FEATURES_TPL" ]; then
  sed -i 's/"enable": false/"enable": true/g' "$FEATURES_TPL"
  echo "  Enabled all dynamic features in get_features.tpl"
fi

# 6b. Static features (Angular main.js — needs bind-mount over read-only squashfs)
MAINJS=$(ls /www/main.*.js 2>/dev/null | head -1)
if [ -n "$MAINJS" ]; then
  mkdir -p /overlay/www-patches
  if [ ! -f /overlay/www-patches/main.js ]; then
    cp "$MAINJS" /overlay/www-patches/main.js
  fi
  sed -i 's/myBoxDeviceInfoDHCPLeases:!1/myBoxDeviceInfoDHCPLeases:!0/g' /overlay/www-patches/main.js
  sed -i 's/myBoxBridgeMode:!1/myBoxBridgeMode:!0/g' /overlay/www-patches/main.js
  sed -i 's/myBoxEcoModeAdvanced:!1/myBoxEcoModeAdvanced:!0/g' /overlay/www-patches/main.js
  sed -i 's/internetConnectivityBasicDnsIpv4:!1/internetConnectivityBasicDnsIpv4:!0/g' /overlay/www-patches/main.js
  sed -i 's/internetConnectivityBasicDnsIpv6:!1/internetConnectivityBasicDnsIpv6:!0/g' /overlay/www-patches/main.js
  sed -i 's/gpon:!1/gpon:!0/g' /overlay/www-patches/main.js
  mount --bind /overlay/www-patches/main.js "$MAINJS"
  echo "  Patched and bind-mounted main.js (6 hidden features enabled)"
fi
echo ""

# ── 7. Enable UART console ──────────────────────────────────────────────────
echo "[7/7] Enabling UART serial console..."
sed -i 's/^#::askconsole/::askconsole/' /etc/inittab 2>/dev/null || true
uci set system.@system[0].ttylogin='1'
uci commit system
echo "  Done — ttyMSM0 @ 115200 8N1"
echo ""

# ── 8. Write rc.local (persist everything across reboots) ────────────────────
echo "[BOOT] Writing /etc/rc.local for boot persistence..."
cat > /etc/rc.local << 'RCEOF'
# TSM4 Root — persistent config
sleep 15

# Use cellular as default WAN (skip if real WAN DHCP is active)
if ! ip route show | grep -q "default.*eth1.*dhcp"; then
  ip route del default 2>/dev/null
  ip route add default dev rmnet_data0 metric 10 2>/dev/null
fi

# DNS
echo "nameserver 8.8.8.8" > /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null
echo "nameserver 1.1.1.1" >> /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null

# Kill TR-069
killall tr69d tr69-osu 5g-osl-tr69-manager 2>/dev/null

# Bind-mount patched main.js (unlocked GUI)
MAINJS=$(ls /www/main.*.js)
if [ -f /overlay/www-patches/main.js ]; then
  mount --bind /overlay/www-patches/main.js "$MAINJS"
fi

exit 0
RCEOF
chmod +x /etc/rc.local
echo "  Done"
echo ""

echo "============================================"
echo "  ALL DONE! Your modem is now:"
echo ""
echo "  - SSH persistent (survives reboot)"
echo "  - De-Telstra'd (no more phone-home)"
echo "  - All GUI menus unlocked"
echo "  - UART console enabled"
echo "  - Admin role: internal (full access)"
echo ""
echo "  Reboot to verify: reboot"
echo "  Then SSH back in: ssh root@192.168.0.1"
echo "============================================"
