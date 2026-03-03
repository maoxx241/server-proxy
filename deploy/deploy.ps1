# 服务器部署脚本（由 setup.ps1 调用）

param(
    [string]$ServerIP = "173.125.1.2",
    [string]$ServerUser = "root",
    [int]$ServerPort = 22,
    [int]$LocalProxyPort = 7897,
    [string]$FrpVersion = "0.61.0"
)

$ErrorActionPreference = "Stop"

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }

Write-Info "目标服务器: ${ServerUser}@${ServerIP}:${ServerPort}"

# 创建临时目录
$tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempDir | Out-Null

# 检测服务器架构
Write-Info "检测服务器架构..."
$arch = ssh -p $ServerPort -o StrictHostKeyChecking=no -o LogLevel=ERROR "${ServerUser}@${ServerIP}" "uname -m"
$arch = $arch.Trim()

switch -Regex ($arch) {
    "x86_64|amd64" { $frpArch = "amd64" }
    "aarch64|arm64" { $frpArch = "arm64" }
    "armv7l|armv7|arm" { $frpArch = "arm" }
    "i386|i686" { $frpArch = "386" }
    default {
        Write-Err "不支持的架构: $arch"
        exit 1
    }
}
Write-Success "架构: $arch -> $frpArch"

# 下载 frp（使用本地代理）
$frpFileName = "frp_${FrpVersion}_linux_${frpArch}.tar.gz"
$frpDownloadUrl = "https://github.com/fatedier/frp/releases/download/v${FrpVersion}/${frpFileName}"
$frpLocalPath = Join-Path $tempDir $frpFileName

Write-Info "下载 frp Linux 版 ($frpArch)..."
$proxyUrl = "http://127.0.0.1:$LocalProxyPort"
$downloadSuccess = $false

try {
    Invoke-WebRequest -Uri $frpDownloadUrl -OutFile $frpLocalPath -Proxy $proxyUrl -UseBasicParsing
    $downloadSuccess = $true
    Write-Success "下载完成"
} catch {
    $mirrors = @(
        "https://gh.api.99988866.xyz/$frpDownloadUrl",
        "https://github.moeyy.xyz/$frpDownloadUrl"
    )
    foreach ($mirror in $mirrors) {
        try {
            Invoke-WebRequest -Uri $mirror -OutFile $frpLocalPath -UseBasicParsing -TimeoutSec 60
            $downloadSuccess = $true
            Write-Success "从镜像下载完成"
            break
        } catch {}
    }
}

if (-not $downloadSuccess) {
    Write-Err "下载失败，请检查代理"
    exit 1
}

# 生成安装脚本
$installLines = @(
    "#!/bin/bash",
    "set -e",
    "INSTALL_DIR=\"/opt/frp\"",
    "",
    "mkdir -p `$INSTALL_DIR",
    "cd `$INSTALL_DIR",
    "",
    "echo '[INFO] 解压 frp...'",
    "tar -xzf /tmp/$frpFileName --strip-components=1",
    "rm -f /tmp/$frpFileName",
    "",
    "cat > frps.toml << 'EOF'",
    "bindAddr = \"0.0.0.0\"",
    "bindPort = 7000",
    "kcpBindPort = 7000",
    "webServer.addr = \"0.0.0.0\"",
    "webServer.port = 7500",
    "webServer.user = \"admin\"",
    "webServer.password = \"admin123\"",
    "log.to = \"/var/log/frps.log\"",
    "log.level = \"info\"",
    "log.maxDays = 30",
    "allowPorts = [",
    "  { start = 7897, end = 7900 }",
    "]",
    "EOF",
    "",
    "cat > /etc/systemd/system/frps.service << 'EOF'",
    "[Unit]",
    "Description=Frp Server Service",
    "After=network.target",
    "",
    "[Service]",
    "Type=simple",
    "User=root",
    "Restart=on-failure",
    "RestartSec=5s",
    "ExecStart=/opt/frp/frps -c /opt/frp/frps.toml",
    "",
    "[Install]",
    "WantedBy=multi-user.target",
    "EOF",
    "",
    "systemctl daemon-reload",
    "systemctl start frps",
    "systemctl enable frps",
    "",
    "sleep 2",
    "if systemctl is-active --quiet frps; then",
    "    echo '[OK] frps 运行中'",
    "else",
    "    echo '[ERROR] frps 启动失败'",
    "    exit 1",
    "fi",
    "",
    "# 开放防火墙端口",
    "if command -v firewall-cmd &> /dev/null; then",
    "    firewall-cmd --permanent --add-port=7000/tcp 2>/dev/null || true",
    "    firewall-cmd --permanent --add-port=7897/tcp 2>/dev/null || true",
    "    firewall-cmd --permanent --add-port=7898/tcp 2>/dev/null || true",
    "    firewall-cmd --permanent --add-port=7500/tcp 2>/dev/null || true",
    "    firewall-cmd --reload 2>/dev/null || true",
    "fi",
    "",
    "if command -v ufw &> /dev/null; then",
    "    ufw allow 7000/tcp 2>/dev/null || true",
    "    ufw allow 7897/tcp 2>/dev/null || true",
    "    ufw allow 7898/tcp 2>/dev/null || true",
    "    ufw allow 7500/tcp 2>/dev/null || true",
    "fi",
    "",
    "echo ''",
    "echo '========================================'",
    "echo 'FRP 服务器部署成功!'",
    "echo '========================================'",
    "echo '端口: 7000 (通信), 7897 (HTTP代理), 7898 (SOCKS5)'",
    "echo '面板: http://$ServerIP:7500 (admin/admin123)'",
    "echo '========================================'"
)

# 生成代理脚本
$setProxyLines = @(
    "#!/bin/bash",
    "PROXY_HOST=\"$ServerIP\"",
    "HTTP_PORT=\"7897\"",
    "SOCKS_PORT=\"7898\"",
    "",
    "export http_proxy=\"http://`${PROXY_HOST}:${HTTP_PORT}\"",
    "export https_proxy=\"http://`${PROXY_HOST}:${HTTP_PORT}\"",
    "export HTTP_PROXY=\"http://`${PROXY_HOST}:${HTTP_PORT}\"",
    "export HTTPS_PROXY=\"http://`${PROXY_HOST}:${HTTP_PORT}\"",
    "export ALL_PROXY=\"socks5://${PROXY_HOST}:${SOCKS_PORT}\"",
    "export no_proxy=\"localhost,127.0.0.1,.local\"",
    "export NO_PROXY=\"localhost,127.0.0.1,.local\"",
    "",
    "echo \"[OK] 代理已启用: http://${PROXY_HOST}:${HTTP_PORT}\""
)

$unsetProxyLines = @(
    "#!/bin/bash",
    "unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY",
    "echo '[OK] 代理已关闭'"
)

$checkProxyLines = @(
    "#!/bin/bash",
    "echo '========================================'",
    "echo '代理状态检查'",
    "echo '========================================'",
    "echo ''",
    "echo '[环境变量]'",
    "echo \"  http_proxy:  `$http_proxy\"",
    "echo \"  https_proxy: `$https_proxy\"",
    "echo ''",
    "echo '[连接测试]'",
    "if [ -n \"$`http_proxy\" ]; then",
    "    PROXY_IP=`$(echo `$http_proxy | sed -E 's|http://([^:]+):.*|\1|')",
    "    PROXY_PORT=`$(echo `$http_proxy | sed -E 's|http://[^:]+:([0-9]+).*|\1|')",
    "    if timeout 3 bash -c \"exec 3<>/dev/tcp/`$PROXY_IP/`$PROXY_PORT\" 2>/dev/null; then",
    "        echo \"  代理端口: OK (`$PROXY_IP:`$PROXY_PORT)\"",
    "    else",
    "        echo '  代理端口: 失败'",
    "    fi",
    "fi",
    "echo ''",
    "echo '[网络测试]'",
    "if curl -s -o /dev/null --max-time 5 https://www.google.com 2>/dev/null; then",
    "    echo '  Google访问: OK'",
    "else",
    "    echo '  Google访问: 失败'",
    "fi",
    "MY_IP=`$(curl -s --max-time 5 ipinfo.io/ip 2>/dev/null || echo 'unknown')",
    "echo \"  当前IP: `$MY_IP\"",
    "echo '========================================'"
)

[IO.File]::WriteAllText("$tempDir\install-server.sh", ($installLines -join "`n") + "`n")
[IO.File]::WriteAllText("$tempDir\set-proxy.sh", ($setProxyLines -join "`n") + "`n")
[IO.File]::WriteAllText("$tempDir\unset-proxy.sh", ($unsetProxyLines -join "`n") + "`n")
[IO.File]::WriteAllText("$tempDir\check-proxy.sh", ($checkProxyLines -join "`n") + "`n")

# 上传到服务器
Write-Info "上传文件到服务器..."
scp -P $ServerPort -o StrictHostKeyChecking=no -o LogLevel=ERROR "$frpLocalPath" "${ServerUser}@${ServerIP}:/tmp/" 2>$null
scp -P $ServerPort -o StrictHostKeyChecking=no -o LogLevel=ERROR "$tempDir\install-server.sh" "${ServerUser}@${ServerIP}:/tmp/" 2>$null

ssh -p $ServerPort -o StrictHostKeyChecking=no -o LogLevel=ERROR "${ServerUser}@${ServerIP}" "mkdir -p /opt/proxy-tools" 2>$null
scp -P $ServerPort -o StrictHostKeyChecking=no -o LogLevel=ERROR "$tempDir\set-proxy.sh" "${ServerUser}@${ServerIP}:/opt/proxy-tools/" 2>$null
scp -P $ServerPort -o StrictHostKeyChecking=no -o LogLevel=ERROR "$tempDir\unset-proxy.sh" "${ServerUser}@${ServerIP}:/opt/proxy-tools/" 2>$null
scp -P $ServerPort -o StrictHostKeyChecking=no -o LogLevel=ERROR "$tempDir\check-proxy.sh" "${ServerUser}@${ServerIP}:/opt/proxy-tools/" 2>$null

ssh -p $ServerPort -o StrictHostKeyChecking=no -o LogLevel=ERROR "${ServerUser}@${ServerIP}" "chmod +x /tmp/install-server.sh /opt/proxy-tools/*.sh" 2>$null

Write-Success "文件上传完成"

# 执行安装
Write-Info "在服务器上安装 frp..."
ssh -p $ServerPort -o StrictHostKeyChecking=no -o LogLevel=ERROR "${ServerUser}@${ServerIP}" "bash /tmp/install-server.sh"

# 清理
Remove-Item -Path $tempDir -Recurse -Force
ssh -p $ServerPort -o StrictHostKeyChecking=no -o LogLevel=ERROR "${ServerUser}@${ServerIP}" "rm -f /tmp/install-server.sh /tmp/$frpFileName" 2>$null

Write-Success "部署完成"
