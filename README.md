# tsm4-root

Root exploit and firmware dump for the **Telstra Smart Modem 4** (Sagemcom F5988TA "Mongoose"). 
Edit: This is firmware this was tested on this may be patched in the future

## Device Info

| Field | Value |
|-------|-------|
| Model | Sagemcom F5988TA |
| Marketing Name | Telstra Smart Modem 4 |
| SoC | Qualcomm SDX75 (5G) |
| WiFi | QCN9224 (WiFi 7, 802.11be) |
| OS | OpenWrt 22.03.5 |
| Kernel | Linux 5.15.149 aarch64 |
| Firmware | SGPE1TL0104AA-1.0.32A |
| Storage | 7.5GB eMMC (mmcblk0, 69+ partitions) |
| Root FS | SquashFS v4 (xz, NOT encrypted) via dm-linear |
| Overlay | ext4 on dm-crypt (aes-xts-plain64) |

## Vulnerability: CWE-295 — Improper Certificate Validation

The TR-069/CWMP client (`tr69d v1.32.5`) validates the ACS server's TLS certificate **chain of trust** but does **NOT** validate the hostname/SAN. Any valid certificate signed by a trusted CA (e.g. Let's Encrypt) is accepted, regardless of the domain it was issued for.

The UCI config confirms this: `tr69.settings.ssl_cn_verification='false'`

This allows a man-in-the-middle on the WAN interface to impersonate Telstra's ACS and send arbitrary TR-069 RPCs to the modem. Sorta-like the old tch-exploit on the gen 3 and gen 2

## Exploit Chain

The exploit runs a rogue ACS server on the modem's WAN interface that:

1. **DHCP + DNS** — Assigns the modem a WAN IP and resolves DNS
2. **TLS interception** — Serves a valid Let's Encrypt certificate (any domain)
3. **TR-069 session hijack** — Responds to the modem's CWMP Inform with RPCs
4. **SetParameterValues** — Sets `X_TELSTRA_Debug.SshdEnabled = true` (standalone SPV, Status=0)
5. **SetParameterValues** — Sets `X_TELSTRA_Debug.SshdAllowedIPList = 0.0.0.0/0` (standalone SPV, Status=0)
6. **SSH access** — Dropbear starts on port 22 with `root` (no password by default)

### Key Findings

- `SshdEnabled` and `SshdAllowedIPList` are **write-only** (GPV returns fault 9002) and **volatile** (lost on reboot)
- They must be sent as **standalone SPVs**, not batched together (batching causes fault 9002 on the second param)
- `Device.SSH.Server.1.*` params are **cosmetic** — they accept SPV but don't actually control dropbear
- The real dropbear control is via `X_TELSTRA_Debug.Sshd*` params processed by `ssh-osu`
- Root has **no password** by default (`root:::` in `/etc/shadow`)

### Dead Paths (Investigated, Not Exploitable)

- Upload RPC — Fault 9003 "unsupported FileType"
- Download RPC — Fault 9002
- NSLookup command injection — Empty CommandOutput
- TraceRoute command injection — DiagState=None
- DebugFileReporting — FileAvailable=false

## Network Setup

```
[Mac en8 USB Ethernet] ---- WAN ----> [SM4 eth1]
   58.162.0.1                           58.162.0.2
   (rogue ACS)                          (target modem)
```

The Mac's en8 adapter connects directly to the modem's WAN port. The rogue ACS runs DHCP (port 67), DNS (port 53), HTTP (port 7547), and HTTPS (ports 7548 + 443).

## Post-Root: De-Telstra & GUI Unlock (Edit this is only experimental so things can break since this is only recently discovered )

Once rooted, the following changes make the modem independently usable:

### Persistence
```sh
# Disable ssh-osu (stops it from killing dropbear on boot)
/etc/init.d/ssh-osu disable

# Set root password
echo -e "yourpassword\nyourpassword" | passwd root

# TR-069 disabled permanently
uci set tr69.mgmt_srv.enable=false
uci set tr69.periodic_inform.enable=false
uci set tr69.conn_request.enable=false
uci commit tr69
/etc/init.d/tr69-osu disable
/etc/init.d/5g-osl-tr69-manager disable
```

### GUI Unlock
Two layers of feature flags control menu visibility:Edit These dont work dont use these

1. **Dynamic features** (`/etc/rest-server/template/telstra/get_features.tpl`) — JSON template served by the REST API. Change all `"enable": false` to `"enable": true`.

2. **Static features** (hardcoded in `/www/main.*.js`) — 6 features disabled in the Angular bundle. Patch them and bind-mount over the read-only squashfs:
   ```sh
   cp /www/main.*.js /overlay/www-patches/main.js
   sed -i 's/myBoxDeviceInfoDHCPLeases:!1/myBoxDeviceInfoDHCPLeases:!0/g' /overlay/www-patches/main.js
   sed -i 's/myBoxBridgeMode:!1/myBoxBridgeMode:!0/g' /overlay/www-patches/main.js
   sed -i 's/myBoxEcoModeAdvanced:!1/myBoxEcoModeAdvanced:!0/g' /overlay/www-patches/main.js
   sed -i 's/internetConnectivityBasicDnsIpv4:!1/internetConnectivityBasicDnsIpv4:!0/g' /overlay/www-patches/main.js
   sed -i 's/internetConnectivityBasicDnsIpv6:!1/internetConnectivityBasicDnsIpv6:!0/g' /overlay/www-patches/main.js
   sed -i 's/gpon:!1/gpon:!0/g' /overlay/www-patches/main.js
   mount --bind /overlay/www-patches/main.js /www/main.*.js
   ```

3. **Admin role** — Change from `end-user` to `internal`:
   ```sh
   uci set omdw_users.admin.role=internal
   uci commit omdw_users
   ```

### UART Console
```sh
# Uncomment console login
sed -i 's/^#::askconsole/::askconsole/' /etc/inittab
uci set system.@system[0].ttylogin=1
uci commit system
# 115200 8N1 on ttyMSM0
```

### rc.local
```sh
cat > /etc/rc.local << 'EOF'
sleep 15
ip route del default 2>/dev/null
ip route add default dev rmnet_data0 metric 10 2>/dev/null
echo "nameserver 8.8.8.8" > /tmp/resolv.conf.d/resolv.conf.auto
echo "nameserver 1.1.1.1" >> /tmp/resolv.conf.d/resolv.conf.auto
killall tr69d tr69-osu 5g-osl-tr69-manager 2>/dev/null
MAINJS=$(ls /www/main.*.js)
[ -f /overlay/www-patches/main.js ] && mount --bind /overlay/www-patches/main.js "$MAINJS"
exit 0
EOF
```

## Firmware Dumps

| File | Size | Description |
|------|------|-------------|
| `rootfs.squashfs` | 81M | Root filesystem (squashfs v4, xz compressed) |
| `boot.img` | 10M | Linux kernel + initramfs |
| `modem_p55.img.part_*` | 300M (split) | 5G/WiFi cellular firmware (reassemble with `cat modem_p55.img.part_* > modem_p55.img`) |
| `xbl_p10.img` | 3.5M | Qualcomm XBL bootloader |
| `tz_p12.img` | 4M | TrustZone firmware |
| `qhee_p34.img` | 2M | Qualcomm Hypervisor (QHEE) |
| `abl_p36.img` | 1M | Android Boot Loader |
| `uefi_p38.img` | 5M | UEFI firmware |
| `keymaster_p49.img` | 512K | Keymaster (hardware crypto) |

**Not included** (contain device-specific config — serial, MAC, WiFi keys, password hashes):
- `overlay.tar.gz` / `persistent_p64.img` — writable overlay and persistent config
- `system_p57.img` — redundant with `rootfs.squashfs` (rootfs sits at sector offset 38192 inside the system partition)

### Partition Map (eMMC GPT)
```
mmcblk0p10  xbl       (XBL bootloader)
mmcblk0p12  tz        (TrustZone)
mmcblk0p34  qhee      (Hypervisor)
mmcblk0p36  abl       (Android Boot Loader)
mmcblk0p38  uefi      (UEFI)
mmcblk0p49  keymaster (Crypto)
mmcblk0p55  modem     (5G/WiFi)
mmcblk0p57  system    (rootfs via dm-linear @ sector 38192)
mmcblk0p59  systemrw  (overlay via dm-crypt aes-xts-plain64)
mmcblk0p64  persist   (persistent config)
```

## Repo Structure

```
tsm4-root/
├── exploit/
│   ├── recon.js                    # Rogue ACS rig (DHCP+DNS+HTTPS+CWMP)
│   ├── sm4_id_rsa.pub              # SSH public key for modem access
│   └── patches/
│       ├── get_features_original.tpl   # Original GUI feature flags
│       └── get_features_unlocked.tpl   # All features enabled
├── firmware/                       # Dumped partition images
│   ├── rootfs.squashfs
│   ├── boot.img
│   ├── modem_p55.img.part_*        # Split for GitHub (reassemble with cat)
│   ├── reassemble.sh               # Script to reassemble split images
│   ├── SHA256SUMS
│   └── ...
├── docs/
│   └── partition_map.txt
├── LICENSE                         # GPL-3.0
└── README.md
```

## Requirements

- macOS/Linux host with a USB Ethernet adapter
- Node.js 18+ (for the rogue ACS)
- A valid TLS certificate (Let's Encrypt works)
- Direct ethernet connection to the modem's WAN port

## Disclaimer

This project is for **educational and security research purposes only**. Use it only on devices you own. The authors are not responsible for any misuse or damage. Unauthorized access to computer systems is illegal in most jurisdictions.

## License

GPL-3.0 — see [LICENSE](LICENSE)
