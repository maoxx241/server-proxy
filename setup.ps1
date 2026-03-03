# FRP Proxy Setup Script
param(
    [string]$ServerIP = "173.125.1.2",
    [string]$ServerUser = "root",
    [int]$ServerPort = 22,
    [int]$LocalProxyPort = 7897,
    [string]$FrpVersion = "0.61.0",
    [Parameter()][ValidateSet("deploy","start","stop","status","config","docker")][string]$Action = "",
    [string]$ContainerName = "",  # For docker action
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
    Write-Host "Basic Commands:"
    Write-Host "  .\setup.ps1 -Action deploy              # Deploy to server (default SSH port 22)"
    Write-Host "  .\setup.ps1 -Action start               # Start frpc client"
    Write-Host "  .\setup.ps1 -Action stop                # Stop frpc client"
    Write-Host "  .\setup.ps1 -Action status              # Show status"
    Write-Host ""
    Write-Host "Custom SSH Port:"
    Write-Host '  .\setup.ps1 -Action deploy -ServerPort 2222   # Use SSH port 2222'
    Write-Host '  .\setup.ps1 -Action status -ServerPort 2222   # Check status on port 2222'
    Write-Host ""
    Write-Host "Docker Container Support:"
    Write-Host '  .\setup.ps1 -Action docker -ContainerName myapp   # Setup proxy for container'
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -ServerIP       : Server IP (default: 173.125.1.2)"
    Write-Host "  -ServerUser     : SSH user (default: root)"
    Write-Host "  -ServerPort     : SSH port (default: 22)"
    Write-Host "  -ContainerName  : Docker container name (for docker action)"
    Write-Host ""
}

function DeployServer {
    Info "Deploying FRP server to ${ServerUser}@${ServerIP}:${ServerPort}..."
    if (-not (Test-Path "frp\frpc.exe")) {
        Warn "frpc.exe not found, downloading..."
        DownloadFrp
    }
    Info "Running deploy script..."
    & "$PSScriptRoot\deploy\deploy.ps1" -ServerIP $ServerIP -ServerUser $ServerUser -ServerPort $ServerPort -LocalProxyPort $LocalProxyPort -FrpVersion $FrpVersion
    Ok "Deploy complete"
    Info "Next: .\setup.ps1 -Action start"
}

function SetupDockerContainer {
    if (-not $ContainerName) {
        Err "Please specify container name: -ContainerName <name>"
        return
    }
    
    Info "Setting up proxy for Docker container: ${ContainerName}"
    
    # Check if container exists and is running
    $containerCheck = ssh -p $ServerPort -o StrictHostKeyChecking=no -o LogLevel=ERROR "${ServerUser}@${ServerIP}" "docker ps --format '{{.Names}}' | grep -w ${ContainerName}" 2>&1
    if (-not $containerCheck) {
        Err "Container '${ContainerName}' not found or not running"
        Info "Available containers:"
        ssh -p $ServerPort -o StrictHostKeyChecking=no -o LogLevel=ERROR "${ServerUser}@${ServerIP}" "docker ps --format '{{.Names}}'"
        return
    }
    
    # Generate proxy scripts locally (avoid bash syntax issues)
    $setProxyLines = @(
        "#!/bin/sh",
        "export http_proxy=`"http://${ServerIP}:7897`"",
        "export https_proxy=`"http://${ServerIP}:7897`"",
        "export HTTP_PROXY=`"http://${ServerIP}:7897`"",
        "export HTTPS_PROXY=`"http://${ServerIP}:7897`"",
        "export ALL_PROXY=`"socks5://${ServerIP}:7898`"",
        "export no_proxy=`"localhost,127.0.0.1,.local`"",
        "echo `"[OK] Proxy enabled`""
    )

    $unsetProxyLines = @(
        "#!/bin/sh",
        "unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy",
        "echo `"[OK] Proxy disabled`""
    )

    $tempSet = "$env:TEMP\set-proxy-${ContainerName}"
    $tempUnset = "$env:TEMP\unset-proxy-${ContainerName}"
    
    [IO.File]::WriteAllText($tempSet, ($setProxyLines -join "`n"))
    [IO.File]::WriteAllText($tempUnset, ($unsetProxyLines -join "`n"))
    
    Info "Uploading scripts to server..."
    scp -P $ServerPort -o StrictHostKeyChecking=no -o LogLevel=ERROR $tempSet "${ServerUser}@${ServerIP}:/tmp/" 2>$null
    scp -P $ServerPort -o StrictHostKeyChecking=no -o LogLevel=ERROR $tempUnset "${ServerUser}@${ServerIP}:/tmp/" 2>$null
    
    Info "Installing scripts into container..."
    $installCmdLines = @(
        "docker cp /tmp/set-proxy-${ContainerName} ${ContainerName}:/usr/local/bin/set-proxy",
        "docker cp /tmp/unset-proxy-${ContainerName} ${ContainerName}:/usr/local/bin/unset-proxy",
        "docker exec ${ContainerName} chmod +x /usr/local/bin/set-proxy /usr/local/bin/unset-proxy",
        "rm -f /tmp/set-proxy-${ContainerName} /tmp/unset-proxy-${ContainerName}",
        "echo '[OK] Scripts installed'"
    )
    $installCmd = $installCmdLines -join "; "
    
    ssh -p $ServerPort -o StrictHostKeyChecking=no -o LogLevel=ERROR "${ServerUser}@${ServerIP}" $installCmd
    
    Remove-Item $tempSet -ErrorAction SilentlyContinue
    Remove-Item $tempUnset -ErrorAction SilentlyContinue
    
    Ok "Docker container proxy configured"
    Info ""
    Info "Usage inside container ${ContainerName}:"
    Info "  docker exec -it ${ContainerName} sh"
    Info "  set-proxy"
    Info "  curl https://www.google.com"
    Info "  unset-proxy"
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
    "docker" { SetupDockerContainer }
    "start" { StartFrpc }
    "stop" { StopFrpc }
    "status" { ShowStatus }
    default { ShowHelp }
}
