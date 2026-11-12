# tsm4-root

Root exploit for the **Telstra Smart Modem 4** (Sagemcom F5988TA "Mongoose").

> **Note:** Tested on firmware SGPE1TL0104AA-1.0.32A. This may be patched in future firmware versions.

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

This allows a man-in-the-middle on the WAN interface to impersonate Telstra's ACS and send arbitrary TR-069 RPCs to the modem.

## Exploit Chain

The exploit runs a rogue ACS server on the modem's WAN interface that:

1. **DHCP + DNS** — Assigns the modem a WAN IP and resolves all DNS to our server
2. **TLS interception** — Serves a valid Let's Encrypt certificate (any domain — the modem doesn't check hostname)
3. **TR-069 session hijack** — Responds to the modem's CWMP Inform with RPCs
4. **SetParameterValues** — Sets `X_TELSTRA_Debug.SshdEnabled = true` (standalone SPV, Status=0)
5. **SetParameterValues** — Sets `X_TELSTRA_Debug.SshdAllowedIPList` (standalone SPV, Status=0)
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

## Usage

### Requirements

- macOS/Linux host with a USB Ethernet adapter
- Node.js 18+
- A valid TLS certificate (Let's Encrypt works — any domain, the modem doesn't check)
- Direct ethernet connection to the modem's **WAN port**

### Network Setup

```
[Mac en8 USB Ethernet] ---- WAN ----> [SM4 eth1]
   58.162.0.1                           58.162.0.2
   (rogue ACS)                          (target modem)
```

### Running the Exploit

```sh
git clone https://github.com/maxinethevaccine/tsm4-root.git
cd tsm4-root
chmod +x root.sh
./root.sh
```

The script will ask you to choose a mode:

| Mode | SSH Access | SshdAllowedIPList |
|------|-----------|-------------------|
| **1 — LAN** | LAN side only | `192.168.0.0/24` |
| **2 — WAN** | Any IP (LAN + WAN) | `0.0.0.0/0` |

> **WAN mode warning:** Exposes SSH to the internet. TR-069 (remote management) remains active and your ISP can push config changes or disable SSH at any time. TR-069 behaviour varies by ISP and firmware version — do not blindly disable it without understanding what it does on your specific device. Disabling it incorrectly can break WAN connectivity or brick the modem.

After the exploit reports success:

```sh
# Connect (root has no password by default)
ssh root@192.168.0.1

# Set a password immediately
passwd
```

### TLS Certificate Setup

Place your Let's Encrypt cert files in `exploit/`:
- `cert.key.pem` — Private key
- `real_cert.pem` — Full chain certificate

If not found, a self-signed cert is generated automatically. The self-signed cert will fail because the modem validates the chain of trust — it just doesn't validate the hostname.

### Overriding the Interface

If your USB Ethernet adapter isn't `en8`:

```sh
SM4_IFACE=en9 ./root.sh
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
├── root.sh                        # Wrapper script (run this)
├── exploit/
│   ├── recon.js                   # Rogue ACS (DHCP+DNS+HTTPS+CWMP)
│   └── sm4_id_rsa.pub             # SSH public key for modem access
├── firmware/                      # Dumped partition images
│   ├── rootfs.squashfs
│   ├── boot.img
│   ├── modem_p55.img.part_*       # Split for GitHub (reassemble with cat)
│   ├── reassemble.sh              # Script to reassemble split images
│   ├── SHA256SUMS
│   └── ...
├── docs/
│   └── partition_map.txt
├── LICENSE                        # GPL-3.0
└── README.md
```

## Disclaimer

This project is for **educational and security research purposes only**. Use it only on devices you own. The authors are not responsible for any misuse or damage. Unauthorized access to computer systems is illegal in most jurisdictions.

## License

GPL-3.0 — see [LICENSE](LICENSE)
