#!/usr/bin/env pwsh
# =============================================================================
# Windows Proxy Service - Smart Port Management
# Usage: .\proxy.ps1 [start|stop|status|fix]
# 
# Features:
# - Auto-detects occupied ports on Windows and server
# - Kills stale SSH tunnels on server before starting new ones
# - Generates .tunnel-mapping for servers
# - Updates config.yaml with assigned ports
# =============================================================================

param(
    [Parameter(Position = 0)]
    [ValidateSet("start", "stop", "status", "fix", "help")]
    [string]$Command = "help"
)

$ConfigFile = Join-Path $PSScriptRoot "config.yaml"
$MappingFile = Join-Path $PSScriptRoot ".tunnel-mapping"
$PidDir = Join-Path $env:TEMP "proxy-tunnels"

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-OK($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "[ERR] $msg" -ForegroundColor Red }

# Check if port is available on Windows
function Test-PortAvailable($port) {
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
        $listener.Start()
        $listener.Stop()
        return $true
    }
    catch {
        return $false
    }
}

# Check if port is occupied on remote server and kill stale processes
function Clear-ServerPort($serverHost, $port, $user) {
    Write-Info "Checking port $port on $serverHost..."
    
    # Check if port is in use on server
    $checkCmd = "lsof -i :$port 2>/dev/null || netstat -tlnp 2>/dev/null | grep ':$port ' || echo 'FREE'"
    $result = ssh "$user@$serverHost" $checkCmd 2>$null
    
    if ($result -match "LISTEN" -or $result -match "sshd") {
        Write-Warn "Port $port is occupied on server"
        
        # Try to find and kill the process
        $killCmd = "fuser -k ${port}/tcp 2>/dev/null || (pid=\$(lsof -ti :$port 2>/dev/null) && kill -9 \$pid 2>/dev/null) || echo 'KILL_FAILED'"
        $killResult = ssh "$user@$serverHost" $killCmd 2>$null
        
        Start-Sleep -Seconds 1
        
        # Check again
        $result2 = ssh "$user@$serverHost" $checkCmd 2>$null
        if ($result2 -match "FREE" -or $result2 -eq "") {
            Write-OK "Port $port cleared on server"
            return $true
        }
        else {
            Write-Err "Could not clear port $port on server"
            return $false
        }
    }
    else {
        Write-OK "Port $port is available on server"
        return $true
    }
}

# Find next available ports on both Windows and server
function Find-AvailablePorts($config) {
    $basePort = $config.proxy.base_tunnel_port
    $count = $config.servers.Count
    $availablePorts = @()
    $port = $basePort
    $maxPort = 65000
    
    foreach ($server in $config.servers) {
        $found = $false
        while (-not $found -and $port -lt $maxPort) {
            # Check Windows local port
            if (-not (Test-PortAvailable $port)) {
                Write-Warn "Port $port occupied on Windows, trying next..."
                $port++
                continue
            }
            
            # Check and clear server port
            if (Clear-ServerPort $server.host $port $server.user) {
                $availablePorts += $port
                $found = $true
            }
            else {
                $port++
            }
        }
        
        if (-not $found) {
            Write-Err "Could not find available port for $($server.name)"
            exit 1
        }
        
        $port++
    }
    
    return $availablePorts
}

function Read-Config {
    if (-not (Test-Path $ConfigFile)) {
        Write-Err "config.yaml not found!"
        exit 1
    }
    
    try {
        $content = Get-Content $ConfigFile -Raw
        $config = @{}
        $config.servers = @()
        $config.proxy = @{ local_proxy_port = 7897; base_tunnel_port = 11080 }
        
        $inServers = $false
        $currentServer = @{}
        
        foreach ($line in $content -split "`n") {
            $trimmed = $line.Trim()
            
            if ($trimmed -match "^servers:") {
                $inServers = $true
                continue
            }
            if ($trimmed -match "^proxy:") {
                $inServers = $false
                continue
            }
            
            if ($inServers -and $trimmed -match "^- name:\s*(.+)") {
                if ($currentServer.Count -gt 0) {
                    $config.servers += $currentServer
                }
                $currentServer = @{ name = $matches[1].Trim(); port = 22; user = "root" }
            }
            elseif ($inServers -and $trimmed -match "^host:\s*(.+)") {
                $currentServer.host = $matches[1].Trim()
            }
            elseif ($inServers -and $trimmed -match "^user:\s*(.+)") {
                $currentServer.user = $matches[1].Trim()
            }
            elseif ($inServers -and $trimmed -match "^port:\s*(\d+)") {
                $currentServer.port = [int]$matches[1].Trim()
            }
            elseif ($inServers -and $trimmed -match "^#?\s*assigned_tunnel_port:\s*(\d+)") {
                $currentServer.assigned_tunnel_port = [int]$matches[1].Trim()
            }
            elseif ($trimmed -match "^local_proxy_port:\s*(\d+)") {
                $config.proxy.local_proxy_port = [int]$matches[1].Trim()
            }
            elseif ($trimmed -match "^base_tunnel_port:\s*(\d+)") {
                $config.proxy.base_tunnel_port = [int]$matches[1].Trim()
            }
        }
        
        if ($currentServer.Count -gt 0) {
            $config.servers += $currentServer
        }
        
        return $config
    }
    catch {
        Write-Err "Failed to parse config.yaml: $_"
        exit 1
    }
}

function Update-ConfigFile($config, $portAssignments) {
    try {
        $lines = Get-Content $ConfigFile
        $newLines = @()
        $inServer = $false
        $currentServerIndex = -1
        
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            
            if ($trimmed -match "^- name:\s*(.+)") {
                if ($inServer -and $currentServerIndex -ge 0) {
                    $server = $config.servers[$currentServerIndex]
                    $port = $portAssignments[$server.host]
                    $newLines += "    assigned_tunnel_port: $port  # auto-assigned"
                }
                $inServer = $true
                $currentServerIndex++
                $newLines += $line
            }
            elseif ($inServer -and ($trimmed -match "^- name:" -or $trimmed -match "^proxy:")) {
                $server = $config.servers[$currentServerIndex]
                $port = $portAssignments[$server.host]
                $newLines += "    assigned_tunnel_port: $port  # auto-assigned"
                $inServer = $false
                $newLines += $line
            }
            else {
                $newLines += $line
            }
        }
        
        # Handle last server
        if ($inServer -and $currentServerIndex -ge 0) {
            $server = $config.servers[$currentServerIndex]
            $port = $portAssignments[$server.host]
            $newLines += "    assigned_tunnel_port: $port  # auto-assigned"
        }
        
        $newLines | Set-Content $ConfigFile -Encoding UTF8
        Write-OK "Updated config.yaml with assigned ports"
    }
    catch {
        Write-Warn "Failed to update config.yaml: $_"
    }
}

function Save-MappingFile($portAssignments) {
    $mapping = @()
    foreach ($srvHost in $portAssignments.Keys) {
        $mapping += "$srvHost $($portAssignments[$srvHost])"
    }
    $mapping -join "`n" | Set-Content $MappingFile
    Write-OK "Generated .tunnel-mapping"
}

function Start-ProxyService {
    $config = Read-Config
    
    if ($config.servers.Count -eq 0) {
        Write-Err "No servers configured!"
        return
    }
    
    if (-not (Test-Path $PidDir)) {
        New-Item -ItemType Directory -Path $PidDir -Force | Out-Null
    }
    
    Write-Info "Starting service for $($config.servers.Count) server(s)..."
    Write-Info "Windows proxy port: $($config.proxy.local_proxy_port)"
    
    # Find available ports (checks both Windows and server)
    Write-Info "Finding and clearing ports on Windows and servers..."
    $availablePorts = Find-AvailablePorts $config
    
    if ($availablePorts.Count -eq 0) {
        Write-Err "Could not find enough available ports!"
        return
    }
    
    if ($availablePorts[0] -ne $config.proxy.base_tunnel_port) {
        Write-Warn "Base port occupied, using $($availablePorts[0])-$($availablePorts[-1])"
    }
    else {
        Write-OK "Using ports $($availablePorts[0])-$($availablePorts[-1])"
    }
    
    $portAssignments = @{}
    
    for ($i = 0; $i -lt $config.servers.Count; $i++) {
        $server = $config.servers[$i]
        $tunnelPort = $availablePorts[$i]
        $pidFile = Join-Path $PidDir "tunnel-$($server.name).pid"
        
        $portAssignments[$server.host] = $tunnelPort
        
        Write-Host ""
        Write-Info "[$($server.name)] $($server.user)@$($server.host)"
        Write-Info "  Tunnel port: $tunnelPort"
        
        # Check if already running
        if (Test-Path $pidFile) {
            $oldPid = Get-Content $pidFile
            if (Get-Process -Id $oldPid -ErrorAction SilentlyContinue) {
                Write-Warn "  Already running (PID: $oldPid), skipping"
                continue
            }
        }
        
        # Start SSH tunnel
        try {
            $process = Start-Process -FilePath "ssh" -ArgumentList @(
                "-N",
                "-R", "$tunnelPort`:127.0.0.1`:$($config.proxy.local_proxy_port)",
                "-o", "ServerAliveInterval=60",
                "-o", "ExitOnForwardFailure=yes",
                "$($server.user)@$($server.host)",
                "-p", $server.port
            ) -WindowStyle Hidden -PassThru
            
            $process.Id | Set-Content $pidFile
            Start-Sleep -Milliseconds 500
            
            if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {
                Write-OK "  Tunnel started (PID: $($process.Id))"
            }
            else {
                Write-Err "  Failed to start tunnel"
            }
        }
        catch {
            Write-Err "  Error: $_"
        }
    }
    
    Save-MappingFile $portAssignments
    Update-ConfigFile $config $portAssignments
    
    # Show summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Port Assignment Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    foreach ($srvHost in $portAssignments.Keys | Sort-Object) {
        Write-Host "  $srvHost -> $($portAssignments[$srvHost])" -ForegroundColor Yellow
    }
    Write-Host "========================================" -ForegroundColor Cyan
    
    Write-Host ""
    Write-OK "All tunnels started!"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Green
    Write-Host "  1. scp config.yaml root@server:/path/to/proxy/" -ForegroundColor White
    Write-Host "  2. On server: source proxy.sh on" -ForegroundColor White
}

function Fix-ServerPorts {
    $config = Read-Config
    Write-Info "Fixing stale tunnels on servers..."
    
    foreach ($server in $config.servers) {
        $port = if ($server.assigned_tunnel_port) { $server.assigned_tunnel_port } else { $config.proxy.base_tunnel_port }
        Write-Host ""
        Write-Info "[$($server.name)] $port"
        Clear-ServerPort $server.host $port $server.user
    }
    
    Write-Host ""
    Write-OK "Fix complete. Run 'proxy.ps1 start' to create new tunnels."
}

function Stop-ProxyService {
    if (-not (Test-Path $PidDir)) {
        Write-Warn "No tunnels running"
        return
    }
    
    $pidFiles = Get-ChildItem $PidDir -Filter "tunnel-*.pid" -ErrorAction SilentlyContinue
    
    if (-not $pidFiles) {
        Write-Warn "No tunnels found"
        return
    }
    
    Write-Info "Stopping tunnels..."
    
    foreach ($pidFile in $pidFiles) {
        $name = $pidFile.BaseName -replace "^tunnel-", ""
        $processId = Get-Content $pidFile.FullName
        
        try {
            Stop-Process -Id $processId -Force -ErrorAction Stop
            Write-OK "[$name] Stopped"
        }
        catch {
            Write-Warn "[$name] Not running"
        }
        
        Remove-Item $pidFile.FullName -Force
    }
    
    if (Test-Path $MappingFile) {
        Remove-Item $MappingFile -Force
    }
    
    Write-Host ""
    Write-OK "All tunnels stopped"
}

function Get-ProxyStatus {
    if (-not (Test-Path $PidDir)) {
        Write-Host "Status: Not running" -ForegroundColor Red
        return
    }
    
    $pidFiles = Get-ChildItem $PidDir -Filter "tunnel-*.pid" -ErrorAction SilentlyContinue
    
    Write-Host ""
    Write-Host "=== Proxy Service Status ===" -ForegroundColor Cyan
    Write-Host ""
    
    $running = 0
    $stopped = 0
    
    foreach ($pidFile in $pidFiles) {
        $name = $pidFile.BaseName -replace "^tunnel-", ""
        $processId = Get-Content $pidFile.FullName
        $isRunning = Get-Process -Id $processId -ErrorAction SilentlyContinue
        
        Write-Host "[$name] " -NoNewline
        if ($isRunning) {
            Write-Host "RUNNING" -ForegroundColor Green -NoNewline
            Write-Host " (PID: $processId)"
            $running++
        }
        else {
            Write-Host "STOPPED" -ForegroundColor Red
            $stopped++
        }
    }
    
    Write-Host ""
    Write-Host "Running: $running, Stopped: $stopped" -ForegroundColor Yellow
    
    if (Test-Path $ConfigFile) {
        $config = Read-Config
        Write-Host ""
        Write-Host "Configuration:" -ForegroundColor Cyan
        Write-Host "  Local proxy port: $($config.proxy.local_proxy_port)"
        Write-Host "  Servers: $($config.servers.Count)"
        
        if ($config.servers[0].assigned_tunnel_port) {
            Write-Host ""
            Write-Host "Assigned Ports:" -ForegroundColor Cyan
            foreach ($server in $config.servers) {
                Write-Host "  $($server.host): $($server.assigned_tunnel_port)" -ForegroundColor Yellow
            }
        }
    }
}

# Main
switch ($Command) {
    "start" { Start-ProxyService }
    "stop" { Stop-ProxyService }
    "status" { Get-ProxyStatus }
    "fix" { Fix-ServerPorts }
    default {
        Write-Host ""
        Write-Host "Windows Proxy Service" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Usage: .\proxy.ps1 [start|stop|status|fix]" -ForegroundColor White
        Write-Host ""
        Write-Host "Commands:" -ForegroundColor Yellow
        Write-Host "  start   - Start tunnels (auto-clears stale ports)"
        Write-Host "  stop    - Stop all tunnels"
        Write-Host "  status  - Show status"
        Write-Host "  fix     - Clear stale ports on servers"
        Write-Host ""
        Write-Host "Features:" -ForegroundColor Green
        Write-Host "  - Auto-detects occupied ports on Windows and servers"
        Write-Host "  - Kills stale SSH tunnels before starting new ones"
        Write-Host "  - Generates .tunnel-mapping for servers"
        Write-Host ""
    }
}
