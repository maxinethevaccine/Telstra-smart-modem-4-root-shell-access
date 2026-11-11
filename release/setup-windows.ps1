# TSM4 Root Exploit — Windows Network Setup
# Run as Administrator in PowerShell
# Configures your USB ethernet adapter and runs the exploit

$ErrorActionPreference = "Stop"

Write-Host "`n=== TSM4 Root Exploit — Windows Setup ===" -ForegroundColor Green
Write-Host ""

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: Must run as Administrator" -ForegroundColor Red
    Write-Host "Right-click PowerShell -> Run as Administrator"
    exit 1
}

# Check Node.js
try {
    $nodeVer = & node -v 2>$null
    Write-Host "[OK] Node.js $nodeVer" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Node.js not found. Download from https://nodejs.org" -ForegroundColor Red
    exit 1
}

# Check cert files
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path "$scriptDir\cert.pem") -or -not (Test-Path "$scriptDir\key.pem")) {
    Write-Host "ERROR: cert.pem and key.pem not found in $scriptDir" -ForegroundColor Red
    Write-Host "You need a valid CA-signed certificate. See README.md"
    exit 1
}
Write-Host "[OK] TLS certificate found" -ForegroundColor Green

# Find ethernet adapters
Write-Host "`nAvailable network adapters:" -ForegroundColor Cyan
Write-Host ""
$adapters = Get-NetAdapter | Where-Object { $_.Status -ne "Not Present" -and $_.InterfaceDescription -match "USB|Ethernet|LAN" }
$i = 1
foreach ($adapter in $adapters) {
    Write-Host "  [$i] $($adapter.Name) — $($adapter.InterfaceDescription) ($($adapter.Status))"
    $i++
}

Write-Host ""
Write-Host "Which adapter is your USB ethernet? (enter number)" -ForegroundColor White
$choice = Read-Host ">"

$selectedAdapter = $adapters[([int]$choice - 1)]
if (-not $selectedAdapter) {
    Write-Host "Invalid selection" -ForegroundColor Red
    exit 1
}
$ifaceName = $selectedAdapter.Name
$ifaceIndex = $selectedAdapter.ifIndex

Write-Host "`nConfiguring $ifaceName with IP 58.162.0.1/24..." -ForegroundColor Cyan

# Remove existing IP config
Get-NetIPAddress -InterfaceIndex $ifaceIndex -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

# Disable DHCP on this adapter
Set-NetIPInterface -InterfaceIndex $ifaceIndex -Dhcp Disabled -ErrorAction SilentlyContinue

# Set static IP
New-NetIPAddress -InterfaceIndex $ifaceIndex -IPAddress "58.162.0.1" -PrefixLength 24 -ErrorAction Stop | Out-Null

Write-Host "[OK] $ifaceName configured at 58.162.0.1" -ForegroundColor Green

# Disable Windows DNS Client on this interface to free port 53
# (Windows DNS Client Service can conflict)
Write-Host "`nNote: If port 53 is in use, you may need to stop the DNS Client service:" -ForegroundColor Yellow
Write-Host "  Stop-Service Dnscache" -ForegroundColor Yellow

# Disable Windows Firewall for this profile (or add rules)
Write-Host "`nAdding firewall rules for exploit..." -ForegroundColor Cyan
New-NetFirewallRule -DisplayName "TSM4-DHCP" -Direction Inbound -Protocol UDP -LocalPort 67 -Action Allow -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "TSM4-DNS" -Direction Inbound -Protocol UDP -LocalPort 53 -Action Allow -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "TSM4-HTTP" -Direction Inbound -Protocol TCP -LocalPort 7547 -Action Allow -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "TSM4-HTTPS" -Direction Inbound -Protocol TCP -LocalPort 443,7548 -Action Allow -ErrorAction SilentlyContinue | Out-Null
Write-Host "[OK] Firewall rules added" -ForegroundColor Green

Write-Host ""
Write-Host "=== Network ready. Starting exploit... ===" -ForegroundColor Green
Write-Host "Power-cycle your modem now (unplug power, wait 10s, plug back in)" -ForegroundColor Cyan
Write-Host ""

# Run the exploit
& node "$scriptDir\tsm4-exploit.js" --cert "$scriptDir\cert.pem" --key "$scriptDir\key.pem"

# Cleanup firewall rules on exit
Write-Host "`nCleaning up firewall rules..." -ForegroundColor Cyan
Remove-NetFirewallRule -DisplayName "TSM4-DHCP" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "TSM4-DNS" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "TSM4-HTTP" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "TSM4-HTTPS" -ErrorAction SilentlyContinue
