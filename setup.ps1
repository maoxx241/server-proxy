# FRP Proxy Setup Script
param(
    [string]$ServerIP = "173.125.1.2",
    [string]$ServerUser = "root",
    [int]$ServerPort = 22,
    [int]$LocalProxyPort = 7897,
    [string]$FrpVersion = "0.61.0",
    [Parameter()][ValidateSet("deploy","start","stop","status","config")][string]$Action = "",
    [switch]$Help
)
$ErrorActionPreference = "Stop"
function Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Ok($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Err($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }

function ShowHelp {
    Write-Host "========================================"
    Write-Host "FRP Proxy Setup Tool"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\setup.ps1 -Action deploy   # Deploy to server"
    Write-Host "  .\setup.ps1 -Action start    # Start frpc client"
    Write-Host "  .\setup.ps1 -Action stop     # Stop frpc client"
    Write-Host "  .\setup.ps1 -Action status   # Show status"
    Write-Host '  .\setup.ps1 -Action config -ServerIP "x.x.x.x"   # Change server IP'
    Write-Host ""
    Write-Host "Prerequisites:"
    Write-Host "  - Clash running on port 7897"
    Write-Host "  - SSH key auth to root@173.125.1.2"
    Write-Host ""
}

function DeployServer {
    Info "Deploying FRP server..."
    if (-not (Test-Path "frp\frpc.exe")) {
        Warn "frpc.exe not found, downloading..."
        DownloadFrp
    }
    Info "Running deploy script..."
    & "$PSScriptRoot\deploy\deploy.ps1" -ServerIP $ServerIP -ServerUser $ServerUser -ServerPort $ServerPort -LocalProxyPort $LocalProxyPort -FrpVersion $FrpVersion
    Ok "Deploy complete"
    Info "Next: .\setup.ps1 -Action start"
}

function DownloadFrp {
    if (Test-Path "frp\frpc.exe") { return }
    if (-not (Test-Path "frp")) { New-Item -ItemType Directory -Path "frp" | Out-Null }
    $url = "https://github.com/fatedier/frp/releases/download/v${FrpVersion}/frp_${FrpVersion}_windows_amd64.zip"
    $temp = "$env:TEMP\frp.zip"
    try {
        Invoke-WebRequest -Uri $url -OutFile $temp -Proxy "http://127.0.0.1:$LocalProxyPort" -UseBasicParsing -TimeoutSec 120
    } catch {
        Invoke-WebRequest -Uri "https://gh.api.99988866.xyz/$url" -OutFile $temp -UseBasicParsing -TimeoutSec 60
    }
    Expand-Archive -Path $temp -DestinationPath "$env:TEMP\frptemp" -Force
    Get-ChildItem "$env:TEMP\frptemp" -Directory | Get-ChildItem | Move-Item -Destination "frp\" -Force
    Remove-Item "$env:TEMP\frptemp" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $temp -Force -ErrorAction SilentlyContinue
    Ok "FRP downloaded"
}

function StartFrpc {
    if (-not (Test-Path "frp\frpc.exe")) { DownloadFrp }
    $proc = Get-Process frpc -ErrorAction SilentlyContinue
    if ($proc) { Warn "frpc already running (PID: $($proc.Id))"; return }
    $proc = Start-Process -FilePath "$PSScriptRoot\frp\frpc.exe" -ArgumentList "-c","$PSScriptRoot\frpc.toml" -PassThru -WindowStyle Hidden
    Start-Sleep 3
    if ($proc.HasExited) { Err "frpc failed to start" } else { Ok "frpc started (PID: $($proc.Id))" }
}

function StopFrpc {
    $proc = Get-Process frpc -ErrorAction SilentlyContinue
    if (-not $proc) { Warn "frpc not running"; return }
    Stop-Process -Name frpc -Force
    Ok "frpc stopped"
}

function ShowStatus {
    Info "FRP Status"
    $proc = Get-Process frpc -ErrorAction SilentlyContinue
    Write-Host "Windows: $(if($proc){"Running (PID:$($proc.Id))"}else{"Stopped"})"
    try {
        $st = ssh -p $ServerPort -o StrictHostKeyChecking=no -o LogLevel=ERROR "${ServerUser}@${ServerIP}" "systemctl is-active frps"
        Write-Host "Server: $($st.Trim())"
    } catch { Write-Host "Server: Unknown" }
}

if ($Help -or $Action -eq "") { ShowHelp; exit 0 }
switch ($Action) {
    "deploy" { DeployServer }
    "start" { StartFrpc }
    "stop" { StopFrpc }
    "status" { ShowStatus }
    default { ShowHelp }
}
