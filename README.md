# TSM4 Shell Unlocker

Root shell exploit for the **Telstra Smart Modem 4** (Sagemcom F5988TA).

Exploits **CWE-295** — the modem validates the TLS certificate chain but **not** the hostname (`ssl_cn_verification='false'`). By impersonating the ISP's ACS (TR-069 management server) during boot, the exploit enables SSH root access via CWMP SetParameterValues.

## Requirements

- **TLS certificate** — a real CA-signed cert (self-signed won't work). The modem trusts ISRG Root X1, so a free Let's Encrypt cert works. Run `get-cert.sh` to obtain one.
- **Ethernet cable** — connect your computer directly to the modem's **RED WAN port**
- **Admin/root privileges** — the exploit binds to privileged ports (53, 67, 123, 443)

## Files

| File | Description |
|------|-------------|
| `exploit.py` | Pure Python exploit — works on **Windows, macOS, and Linux** with zero dependencies |
| `exploit.sh` | Bash exploit — uses dnsmasq, works on **macOS and Linux** |
| `get-cert.sh` | Helper script to obtain a free Let's Encrypt certificate |

## Quick Start

### 1. Get a TLS certificate

```bash
bash get-cert.sh
```

This creates `cert.pem` and `key.pem` in the current directory.

### 2. Run the exploit

**Python (all platforms — recommended):**
```bash
# macOS / Linux
sudo python3 exploit.py

# Windows (run as Administrator)
python exploit.py
```

**Bash (macOS / Linux only — requires dnsmasq):**
```bash
sudo bash exploit.sh
```

### 3. Boot the modem

1. Plug the ethernet cable into the modem's **RED WAN port**
2. Power cycle the modem (unplug power, wait 5 seconds, plug back in)
3. Wait ~5 minutes — watch the terminal for `*** ROOT SSH ENABLED ***`

### 4. Connect via SSH

```bash
ssh root@192.168.0.1
```

Connect over the modem's **LAN** (Wi-Fi or ethernet LAN port), not the WAN port.

## Options

```
exploit.py [-h] [-i IFACE] [-c CERT] [-k KEY] [-s SUBNET] [-p PREFIX] [-m MAC] [-v]

  -i IFACE   Network interface (interactive picker if omitted)
  -c CERT    Path to cert.pem (default: ./cert.pem)
  -k KEY     Path to key.pem (default: ./key.pem)
  -s SUBNET  First 3 octets of WAN subnet (default: 58.162.7)
  -p PREFIX  IPv6 prefix (default: 2001:800e:11:3100)
  -m MAC     Spoof DHCP MAC filter
  -v         Verbose logging (DNS queries, CWMP traffic, HTTP requests)
```

## Important Warnings

> **SSH is volatile.** The modem resets SSH access on every reboot. You must run the exploit before each boot to re-enable SSH.

> **Do NOT reconnect the modem to your ISP's WAN** until you have secured SSH and disabled TR-069. If the modem contacts the real ACS, it will reset your SSH configuration.

> **Post-rooting is your responsibility.** The exploit only enables root SSH access. Anything you do after that point (changing configs, installing packages, modifying firmware) can brick your modem. Proceed at your own risk.

## How It Works

1. Your computer impersonates the ISP's infrastructure on the WAN port (DHCP, DNS, NTP, HTTPS)
2. On boot, the modem gets an IP via DHCP and syncs time via NTP
3. The modem initiates a TR-069 session to what it thinks is the ISP's ACS
4. The exploit responds with CWMP commands to enable SSH with root access
5. The modem applies the settings — SSH is now accessible on the LAN

## Platform Notes

### Windows
- Run as **Administrator** (required for privileged ports)
- The script automatically adds/removes Windows Firewall rules
- Uses PowerShell for network interface configuration

### macOS
- Requires `sudo`
- The script configures the interface via `ifconfig`

### Linux
- Requires `sudo`
- `exploit.sh` requires `dnsmasq` (`sudo apt install dnsmasq`)
- `exploit.py` works without any external dependencies
- On multi-interface systems, the script uses `SO_BINDTODEVICE` to ensure traffic goes out the correct interface

## License

MIT
