# TSM4 Root Exploit — Quick Start

Root your Telstra Smart Modem 4 (Sagemcom F5988TA) in ~5 minutes.

## What You Need

1. **A USB Ethernet adapter** — any cheap one works
2. **An Ethernet cable** — to connect the adapter to the modem's WAN (blue) port
3. **Node.js 18+** — [nodejs.org](https://nodejs.org)
4. **A TLS certificate** — free from Let's Encrypt (see below)

## Step 1: Get a TLS Certificate

The modem validates the TLS certificate chain but NOT the hostname — any valid
CA-signed cert works. Self-signed certificates will NOT work.

**Easiest method (DuckDNS + Let's Encrypt):**

```bash
# macOS/Linux — automated helper
sudo bash get-cert.sh
```

Or manually:
1. Get a free domain at [duckdns.org](https://www.duckdns.org)
2. Install certbot: `brew install certbot` / `apt install certbot`
3. Run: `sudo certbot certonly --manual --preferred-challenges dns -d yourdomain.duckdns.org`
4. Copy files:
   ```
   cp /etc/letsencrypt/live/yourdomain.duckdns.org/fullchain.pem cert.pem
   cp /etc/letsencrypt/live/yourdomain.duckdns.org/privkey.pem key.pem
   ```

Place `cert.pem` and `key.pem` in this folder.

## Step 2: Connect Hardware

```
[Your Computer] --- USB Ethernet --- [Modem WAN port (blue)]
```

Plug the USB ethernet adapter into your computer, then connect it to the
modem's **WAN (blue) port** with an ethernet cable. Do NOT plug into the
LAN (yellow) ports.

## Step 3: Run the Exploit

### macOS
```bash
sudo bash setup-macos.sh
```

### Linux
```bash
sudo bash setup-linux.sh
```

### Windows
```powershell
# Run PowerShell as Administrator
.\setup-windows.ps1
```

### Manual (any OS)
```bash
# 1. Set your USB ethernet adapter IP to 58.162.0.1/24
# 2. Run:
sudo node tsm4-exploit.js --cert cert.pem --key key.pem
```

## Step 4: Power-Cycle the Modem

Unplug the modem's power, wait 10 seconds, plug it back in.

Watch the exploit output — within 2-3 minutes you'll see:
```
SSH ENABLED SUCCESSFULLY!
```

## Step 5: Connect via SSH

```bash
ssh root@58.162.0.2
```

Root has **no password** by default — just press Enter if prompted.

## Step 6: Make It Permanent

On the modem (via SSH), run the post-root script:

```bash
# Option A: pipe it directly
ssh root@58.162.0.2 'sh -s' < post-root.sh

# Option B: copy and run
scp post-root.sh root@58.162.0.2:/tmp/
ssh root@58.162.0.2 'sh /tmp/post-root.sh'
```

This will:
- Set a root password
- Make SSH survive reboots
- Disable TR-069 (Telstra management)
- Unlock all hidden GUI menus
- Enable UART serial console
- Upgrade admin to full access

After running, you can disconnect the USB ethernet and access the modem
normally at `ssh root@192.168.0.1`.

## Troubleshooting

**Modem doesn't connect:**
- Make sure the cable is in the WAN (blue) port, not LAN (yellow)
- Verify your adapter has IP 58.162.0.1: `ifconfig` / `ip addr`
- Try power-cycling the modem again
- Check that no other DHCP server is running on the adapter

**"TLS certificate required" error:**
- You need a real CA-signed cert, not self-signed
- Run `get-cert.sh` or see Step 1 above

**SSH connection refused after reboot:**
- SSH is volatile until you run `post-root.sh`
- Run the exploit again, then immediately run `post-root.sh`

**Port 53/67 already in use:**
- macOS: `sudo lsof -i :53` — kill conflicting process
- Linux: `sudo systemctl stop systemd-resolved dnsmasq`
- Windows: `Stop-Service Dnscache`

## Files

| File | Description |
|------|-------------|
| `tsm4-exploit.js` | The exploit — rogue ACS server |
| `post-root.sh` | Post-root persistence script (runs on modem) |
| `setup-macos.sh` | macOS network setup + exploit launcher |
| `setup-linux.sh` | Linux network setup + exploit launcher |
| `setup-windows.ps1` | Windows network setup + exploit launcher |
| `get-cert.sh` | Helper to get a free Let's Encrypt cert |
| `cert.pem` | Your TLS certificate (you provide this) |
| `key.pem` | Your TLS private key (you provide this) |

## How It Works

The Telstra Smart Modem 4 uses TR-069/CWMP to receive configuration from
Telstra's management server (ACS). The TR-069 client validates the TLS
certificate chain of trust but does NOT validate the hostname (CWE-295).

This exploit:
1. Acts as a DHCP server on the modem's WAN port
2. Redirects DNS to itself
3. Impersonates Telstra's ACS with a valid TLS cert
4. Sends SetParameterValues to enable SSH (dropbear)

The SSH params (`SshdEnabled`, `SshdAllowedIPList`) are volatile and lost
on reboot — that's why `post-root.sh` disables the service that controls
them and makes dropbear start directly.

## License

GPL-3.0
